---
date: 2026-05-20
category: best-practices
pr: 4121
issue: 4115
tags: [github-app, ci, drift-detection, brand-survival, iac]
---

# Learning: Manifest-as-IaC with shared diff-script contract between CI workflow and contract test

## Problem

GitHub App identity material (App ID, PEM, Client ID/Secret, webhook secret)
is a single-user-incident brand-survival artifact. The legacy provisioning
flow was a 12-field UI form fill at github.com/settings/apps/new — slow,
error-prone, and impossible to verify post-fact. Multiple prior attempts
proposed an online callback that would write all 5 credentials to Doppler,
but every iteration broke the existing `scheduled-github-app-drift-guard.yml`
invariant: the guard reads what the callback would write, and the
detection primitive cannot trust its source-of-truth.

## Solution

**Manifest-as-IaC pattern** with three load-bearing properties:

1. **Hand-authored `apps/web-platform/infra/github-app-manifest.json`** is
   the committed source-of-truth. Operator clicks a static internal page
   (`/internal/github-app-init`) that submits the manifest to GitHub's
   App-create form. No online Doppler write surface exists.

2. **Shared diff-script contract**: `bin/diff-github-app-manifest.sh` is
   invoked by BOTH the workflow YAML and the vitest contract test. The
   script reads `MANIFEST_FILE` + `RESPONSE_FILE` env vars and emits
   `<mode>:<details>` on stdout with three modes:
    - `permission_drift` → `ci/auth-broken` (manifest declares X, live lacks X — security regression direction)
    - `permission_unexpected_grant` → `ci/guard-broken` (live has Y, manifest doesn't — inventory drift)
    - `response_shape_unparseable` → `ci/guard-broken` (malformed `GET /app` response)

   Duplicating the diff logic inline in YAML means the test asserts
   behavior not in CI — exactly the failure mode SpecFlow flagged.

3. **First-merge suppression via committed timestamp file**
   (`apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL`) with strict
   ISO-8601 regex validation and a hard 30-day epoch cap. `date -d`
   accepts natural-language strings ("100 years", "next decade") which
   would otherwise silently suppress drift detection forever against a
   compromised or typo'd commit.

## Key Insight

**A drift-detection primitive cannot trust an online write path against
its own source-of-truth.** The CTO finding that drove Approach A
(rejecting online callback in favor of committed manifest) is the
generalizable principle: detection primitives must read state THEY are
authoritative for OR a separately-anchored source. When the same
endpoint produces both the detection signal AND the operational write,
the invariant collapses.

The pattern extends to other brand-survival surfaces:
- Webhook signature verification cannot use a key the same handler
  rotates.
- Doppler drift detection cannot read from the same scope the cron
  itself writes.
- Schema migrations cannot bootstrap from an RPC that depends on the
  migration's own new columns.

## Defense-in-depth additions surfaced at multi-agent review

The plan-time review caught three vectors; multi-agent post-implementation
review caught three more, all fixed inline:

1. **`APP_DOMAIN` env-var allowlist** — without it, a Doppler config
   swap (operator pastes dev value into prd, or vice-versa) silently
   mis-binds the manifest's `redirect_url`/`hook_attributes.url`/`setup_url`
   to the wrong environment. The submitted manifest creates a wrong-env
   App against the founder's repo. Fail-loud throw on out-of-allowlist
   value is cheap; the rogue-bind is irreversible.

2. **Operator allowlist gate** on `/internal/github-app-init` — middleware
   redirects unauth users but the page was reachable by any authenticated
   tenant user. Pattern reused from
   `app/(dashboard)/dashboard/admin/analytics/page.tsx` (`ADMIN_USER_IDS`
   env-var split + `user.id` membership check + redirect to `/dashboard`).

3. **Parity test on EXACT permission key set** (not just per-key
   assertions). A malicious PR could add an undeclared permission key
   that passes individual-key checks. Stored-injection guard locks the
   key set to the snapshotted size.

4. **SUPPRESS_UNTIL strict ISO-8601 + 30d epoch cap** — see above.

5. **Runbook Option B JWT-mint rewrite** — the original snippet was
   broken (`JWT=$(bash bin/snapshot-github-app.sh > /dev/null; ...)`
   discarded the script's only output and referenced a non-existent
   "Option C"). Now contains a working inline mint + curl PATCH with
   process-substitution for the Authorization header.

6. **Stale line-range citation in bin/snapshot-github-app.sh:6** — the
   header comment cited `lines 119-150` for the mint_jwt block, but the
   #4115 manifest-diff insertion shifted that range to `127-158`.
   Mirrored citations in `.github/workflows/scheduled-ruleset-bypass-audit.yml`
   were updated in the implementation PR but `bin/snapshot-github-app.sh`
   was missed by the Phase 0.6 sibling-citation sweep because it lives
   in `bin/`, not `.github/workflows/`.

## Session Errors

1. **PEM stored as plain PEM in Doppler prd, not base64** — `doppler secrets
   get GITHUB_APP_PRIVATE_KEY --plain | base64 -d` failed with
   `base64: invalid input`. Recovery: dropped the `base64 -d` pipe. The
   runbook documents the inverse (operator base64-encodes BEFORE writing);
   existing prd-setup is plain. Prevention: add a "format probe" to
   `bin/snapshot-github-app.sh` that grep-checks for `-----BEGIN` before
   openssl-validating, then branches between plain-PEM and base64-PEM paths.

2. **`openssl rsa -check` writes "RSA key ok" to stdout, not stderr** —
   first snapshot ran `openssl rsa -in $KEY -check -noout 2>/dev/null`
   which suppresses stderr but lets stdout through; the validation
   message was prepended to the snapshot JSON. Recovery: changed to
   `>/dev/null 2>&1`. Prevention: when capturing stdout from a script,
   always suppress BOTH streams from validation steps inside it.

3. **Bash tool CWD does not persist between calls** — `cd apps/web-platform
   && vitest` succeeded once, then the next Bash call landed at the
   worktree root and `cd apps/web-platform: No such file or directory`.
   Recovery: chain `cd <abs-path> && <cmd>` in single Bash invocations
   OR use absolute paths consistently. Prevention: already covered by
   AGENTS.md `hr-bash-tool-runs-in-a-non-interactive`; the loader-class
   gate fires every turn, but the model still slipped after several
   commands in the same worktree CWD. Mitigation: when writing a long
   sequence of test-runner invocations, prefix each with the absolute
   worktree path.

4. **Review-driven `requireOperator()` addition broke 5 init-page
   tests** — the new function imported `@/lib/supabase/server` and
   `next/navigation.redirect`, neither mocked in the existing test
   file. Tests failed with `\`cookies\` was called outside a request
   scope`. Recovery: added `vi.mock("next/navigation")` (throwing
   `REDIRECT:<path>` error so tests assert WHICH redirect fired) +
   `vi.mock("@/lib/supabase/server")` with a `setMockUser` helper +
   3 new tests for the gate (unauth → /login, non-admin → /dashboard,
   APP_DOMAIN-outside-allowlist → throw). Prevention: when a
   code-review fix adds new imports to a tested module, immediately
   re-run the test file and update mocks in the same edit cycle
   (not as a follow-up).

5. **Test fixture `APP_DOMAIN="app.test.example"` invalidated by review
   fix** — adding the host allowlist forced the test to use a domain
   in `{app.soleur.ai, app.dev.soleur.ai}`. Recovery: updated to
   `"app.dev.soleur.ai"`. Prevention: when adding an allowlist to a
   function under test, sweep test fixtures for the now-rejected
   values in the same edit.

## Tags

category: best-practices
module: github-app, ci, infrastructure-as-code
