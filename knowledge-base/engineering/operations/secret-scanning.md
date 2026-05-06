---
title: Secret-scanning floor — operator runbook
status: active
audience: operators, on-call, contributors
related:
  - https://github.com/jikig-ai/soleur/issues/3121
  - knowledge-base/engineering/operations/golden-tests.md
last_updated: 2026-05-06
---

# Secret-scanning floor

This document is the operator runbook for the secret-scanning floor introduced
in [#3121](https://github.com/jikig-ai/soleur/issues/3121). It covers:

- The rule pack and its allowlist semantics.
- The `# gitleaks:allow` waiver discipline.
- The decision tree when an alert fires (rotate vs. history-rewrite).
- Per-token rotation playbooks.
- The notification flow (Discord, GDPR).
- The forensics workflow (why we don't upload `--report-path` JSON).
- Rule-pack maintenance (adding a new token shape).

## Architecture

Two enforcement layers, one source of truth.

| Layer | Where | When | Bypassable | Purpose |
|---|---|---|---|---|
| **Lefthook `gitleaks-staged`** | local pre-commit | every `git commit` | yes (`--no-verify`, hook removal) | fast feedback before a leak hits the local index |
| **Lefthook `lint-fixture-content`** | local pre-commit | every `git commit` | yes | catches semi-sensitive shapes (real emails, prod-shape UUIDs, Supabase project refs) gitleaks misses |
| **CI `secret-scan` workflow** | GitHub Actions | PR + push:main + weekly cron | no (CODEOWNERS-protected) | load-bearing enforcer; the rule's `[hook-enforced: ...]` tag points here |

The local hook is a **fast-feedback courtesy**, not a safety floor. The CI
workflow is what stops a secret from reaching `main`. Operators MUST NOT
disable the CI job to "unblock" a PR; if a finding is a false positive, add
a per-rule `[[rules.allowlists]]` block in `.gitleaks.toml` or a `# gitleaks:allow`
waiver in the source file.

## Rule pack

`.gitleaks.toml` extends the upstream default pack and adds 13 project-specific
rules covering token shapes that appear in our `prd` Doppler config. See the
file for the full list; key categories:

- **Soleur BYOK** — `sk-soleur-` prefix.
- **Doppler** — `dp.{pt,st,sa,ct}.` prefix (personal / service / service-account / CLI tokens).
- **Supabase** — service-role JWT (HS256), anon JWT, access token (`sbp_`).
- **Stripe** — webhook secret (`whsec_`). Default pack covers API keys (`sk_live_`, etc.).
- **Anthropic / Resend / Sentry / Cloudflare / Discord webhook**.
- **Database URL** with embedded password.
- **VAPID** web-push private key.

### Allowlist semantics — read this carefully

gitleaks v8.24.2 supports **per-rule** `[[rules.allowlists]]` blocks. v8.25+
adds a top-level `[[allowlists]]` with `targetRules = [...]` syntax — we are
NOT on v8.25+, so the per-rule form is the only option.

**Default-pack rules do NOT inherit our project allowlists.** This is
intentional. Examples:

- An AWS access key under `__goldens__/foo.snap` would still trigger the
  default pack's `aws-access-token` rule. AWS keys never belong in fixtures
  even synthesized — if you need one for a contract test, paste it through
  the official sandbox docs and document the source.
- Our 13 custom rules each carry the same `paths` allowlist:
  - `__goldens__/.*` — golden snapshots from the A2 surface (#3121, #3143, #3144).
  - `(__snapshots__|__goldens__)/.*\.snap$` — anchored snapshot files.
  - `apps/web-platform/test/__synthesized__/.*` — fixtures with semi-sensitive
    shapes that need to look real (e.g., a JWT shape for a parser test).
  - `reports/mutation/.*` — Stryker output (also gitignored; defensive belt-and-suspenders).
- The `private-key` rule (and **only** that rule) additionally allowlists
  `knowledge-base/project/learnings/.*\.md$`. Learning files routinely document
  private-key-shape symptom reproductions (e.g.,
  `2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md` — the file that
  motivated this carve-out via [#3268](https://github.com/jikig-ai/soleur/issues/3268)
  / [#3281](https://github.com/jikig-ai/soleur/issues/3281)). Default-pack rules
  (AWS, Stripe, etc.) and the other 13 custom rules (Doppler, Supabase JWT,
  Anthropic, Resend, Cloudflare, Sentry, Discord webhook, database URL, VAPID,
  JWT, generic-API-key, Soleur BYOK, Stripe webhook secret) remain LIVE on the
  learnings tree — only literal `BEGIN/END PRIVATE KEY` blocks are silenced.

`apps/web-platform/test/fixtures/qa-auth.ts` is **NOT** allowlisted. It is a
real auth-test fixture that interacts with a live Supabase test project; if
it ever needs a synthesized token, the file should move under
`apps/web-platform/test/__synthesized__/`.

### Rename-laundering — empirical behavior (gitleaks v8.24.2)

The CI smoke matrix's `rename-laundering` case proved **empirically** that
gitleaks v8.24.2 **allows** a rename from a non-allowlisted path into an
allowlisted path. The path-based allowlist is evaluated against the
**destination** path of the staged change; the diff content (which carries
the same secret) is not re-evaluated against the source path.

This means a `git mv apps/web-platform/server/with-secret.ts
apps/web-platform/test/__synthesized__/now-allowed.ts` followed by
`git add` slips a real secret past the gate.

Mitigations in place:

1. **GitHub push protection** independently scans every committed line for
   well-known token shapes (Doppler, AWS, Stripe, etc.) and blocks the push
   regardless of allowlist scope. We confirmed this empirically when
   GitHub blocked our own smoke-test fixture commit until we split the
   token into prefix + body composed at runtime.
2. **CODEOWNERS** requires 2nd-reviewer for any change touching
   `.gitleaks.toml`, the workflow, the linter, or `AGENTS.md` — humans
   review the diff before merge.
3. **Reviewer awareness** — this runbook documents the gap so reviewers
   know to look for `git mv` into `__goldens__/` / `__synthesized__/`.

**Follow-up tracked:** [#3160](https://github.com/jikig-ai/soleur/issues/3160)
adds a CI rename-guard job that fails on rename targets landing in
allowlisted paths unless overridden via label or commit trailer.

Re-check on every gitleaks bump — the upstream behavior may change. The
PR1 smoke matrix's `rename-laundering` job is the canary; a green run on
a future bump where it should fail means the gitleaks behavior shifted
and our smoke expectations need updating in the same PR.

### `# gitleaks:allow` waivers

Both gitleaks and the companion `lint-fixture-content.mjs` linter honor
line-level waivers. The vocabulary is:

```
# gitleaks:allow # issue:#NNN <one-line reason>
// gitleaks:allow # issue:#NNN <one-line reason>
```

The `# issue:#NNN <reason>` trailer is **mandatory** — the linter rejects
waivers without it. The intent is forensic: every waiver in the codebase
points to a tracked decision, so a future reviewer can ask "why is this
allowed?" and get an answer in <30 seconds.

When opening a PR that adds a waiver, link the issue in the PR body. When
closing the issue, audit any waivers that reference it and remove them if
the underlying constraint is gone.

**Why the trailer is enforced in CI, not just by `lint-fixture-content`:**
Native gitleaks `# gitleaks:allow` is honored on **any line in any file**
with no trailer enforcement. `lint-fixture-content.mjs` is glob-scoped to
fixture/golden/snapshot directories — a developer could waive a real
`whsec_` or `sk-ant-` token in a server-path file with bare
`# gitleaks:allow` and gitleaks would honor it.

The `waiver-discipline` CI job closes this gap: it greps every PR-added
line containing `gitleaks:allow` (across the whole tree) and rejects any
without an `issue:#[0-9]+\s+\S{3,}` trailer. Failure blocks merge;
CODEOWNERS guards the job definition itself so the gate cannot be removed
without a 2nd-reviewer.

## When an alert fires

```
                 secret-scan finding
                          │
                          ▼
              ┌───────────────────────┐
              │ Where did it appear?  │
              └───────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
   pre-commit         PR diff           push:main /
   (local hook)       (CI gate)         weekly cron
        │                 │                 │
        ▼                 ▼                 ▼
   ┌─────────┐    ┌──────────────┐    ┌──────────────────┐
   │ Edit /  │    │ Push fix to  │    │ ROTATE NOW       │
   │ unstage │    │ same PR;     │    │ Do NOT rewrite   │
   │ before  │    │ never merge  │    │ history.         │
   │ commit. │    │ until green. │    │ Assume exfil.    │
   └─────────┘    └──────────────┘    └──────────────────┘
```

### Why "rotate, don't `filter-repo`" on `push:main`

Once `push:main` fires, the secret is on GitHub's CDN, replicated across
the issue/code search index, and potentially mirrored into every fork that
has fetched in the last few minutes. `git filter-repo` rewrites your local
copy and the canonical remote, but cannot scrub the CDN cache, the search
index, or any fork. Rotation is the only durable remediation.

History-rewrite is appropriate ONLY when:

1. The secret was committed in the **current PR** branch and has never been
   pushed to `main`. Push the rewritten branch (force-push to your own
   feature branch is fine) and proceed.
2. AND the secret was never visible in CI logs of a public-repo run (check
   the workflow logs even if the secret was redacted — `echo $TOKEN` in a
   `set -x` step bypasses redaction).

If both conditions hold, you may rewrite. Otherwise: rotate, document, move on.

## Per-token rotation playbook

Order: by blast radius — worst-case first.

### `BYOK_ENCRYPTION_KEY` — WORST CASE

The byok-encryption-key encrypts user-supplied provider keys at rest in
Supabase. Rotating it without re-encrypting stored ciphertexts will brick
every BYOK user's workspace.

1. Generate the new key. Do NOT swap immediately.
2. Stand up a dual-key migration: `BYOK_ENCRYPTION_KEY_NEXT` env var; the
   server-side decrypt path tries CURRENT, falls back to NEXT.
3. Run a backfill that re-encrypts every row under NEXT.
4. Promote NEXT → CURRENT; remove the fallback path.
5. Audit logs to confirm no further decrypt failures.

If the key was leaked publicly, also notify affected users (every BYOK
user is "affected" — assume their stored keys are compromised) and force
a re-enrollment on next login.

### `SUPABASE_SERVICE_ROLE_KEY`

1. Supabase dashboard → Project Settings → API → "Reset service_role key".
2. Update Doppler `prd` immediately: `doppler secrets set SUPABASE_SERVICE_ROLE_KEY="..." -p soleur -c prd`.
3. Coordinate with deploy: the running container holds the old key in env
   until the next restart. Either redeploy immediately or accept a window
   where server-side calls 401 until the next deploy.
4. Audit logs for unexpected requests in the gap.

### `SUPABASE_ACCESS_TOKEN` (CLI / `sbp_`)

1. https://supabase.com/dashboard/account/tokens → revoke compromised token.
2. Generate new token; update Doppler `prd_terraform` (used by Terraform
   provider) AND any local `~/.zshrc` exports.
3. Re-run any in-flight `terraform apply` that may have authenticated with
   the old token.

### `ANTHROPIC_API_KEY`

1. https://console.anthropic.com → API Keys → revoke + regenerate.
2. Update Doppler `prd` AND `dev` (separate keys per env if possible).
3. No re-deploy needed — server reads at request time.

### `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET`

1. Stripe dashboard → API keys → roll. (Restricted-key rotation is fine
   in flight; live secret-key rotation requires coordination.)
2. Webhook secret is a separate rotation: Developers → Webhooks → endpoint
   → "Roll secret". Update env var. The previous secret stays valid for
   24 hours by default — you have a window, use it.
3. Redeploy webhook handler to pick up new env var.

### `GITHUB_APP_PRIVATE_KEY`

1. https://github.com/settings/apps/<app> → Private keys → generate new.
2. Update Doppler `prd`.
3. **All installations re-authenticate.** The old private key is still
   accepted by GitHub for ~ 5 minutes; after that, every active
   installation token expires and must be re-minted with the new key.
4. Confirm the GitHub App callback service successfully mints a new
   installation token before declaring rotation complete.

### Other tokens (lower blast radius)

| Token | Where to rotate | Notes |
|---|---|---|
| `RESEND_API_KEY` | https://resend.com/api-keys | No re-deploy; reads at request time |
| `CF_API_TOKEN_PURGE` | https://dash.cloudflare.com/profile/api-tokens | Scoped to cache-purge; rotate + update Doppler |
| `SENTRY_*` (DSN, auth-token) | https://sentry.io → Settings → Auth Tokens / Project DSNs | DSN is public-by-design; auth-token rotation needs CI re-deploy |
| `GOOGLE_CLIENT_SECRET` | https://console.cloud.google.com → APIs & Services → Credentials | OAuth flow re-auth; no token invalidation |
| `GITHUB_CLIENT_SECRET` | https://github.com/settings/applications/<id> | Same as above |
| `BUTTONDOWN_API_KEY` | https://buttondown.email/settings/programming | Newsletter integration only |
| `VAPID_PRIVATE_KEY` | regenerate keypair, redeploy server, push subscriptions re-register | Web-push subscribers need to re-subscribe |
| `DISCORD_OPS_WEBHOOK_URL` | Discord channel → Edit Webhook → Regenerate URL | Internal-only |
| `DATABASE_URL` password | Supabase dashboard → Database → Connection pooler → reset password | Coordinate with deploy |

## Notification flow

When a secret is rotated due to a leak:

1. **Immediately** post to `#security-incidents` Discord via
   `DISCORD_OPS_WEBHOOK_URL`. Template:
   > Secret rotated: `<name>`. Source: <PR-link / commit-SHA / workflow-run>.
   > Blast radius: <one line>. Status: <rotated / re-deployed / monitoring>.
2. If the leaked secret could have allowed read access to **customer data**
   (Supabase service-role, BYOK encryption key, database URL with password):
   - Open a private incident in the security tracker.
   - Determine GDPR Article 33 obligation (notify supervisory authority
     within 72 hours if there is a "risk to the rights and freedoms of
     natural persons").
   - Determine GDPR Article 34 obligation (notify affected data subjects
     directly if "high risk").
   - Coordinate with CLO before any external statement.
3. Internal-only secrets (Discord webhook, Resend key for transactional
   email): Discord notification is sufficient; no external disclosure.

## Forensics workflow

The CI workflow does **NOT** upload `--report-path` JSON as an artifact.
Rationale: gitleaks v8.18+ redacts the `Secret` field in the JSON output,
but on a public repo the safer default is "logs only" — any future change
that disables `--redact` would leak via the artifact. The forensics path is:

1. Read the redacted finding from the workflow log: `<rule-id>` + `<file>:<line>`.
2. Locally re-run the scan against the offending commit:

   ```bash
   git fetch origin pull/<PR>/head:pr-<PR>
   git checkout pr-<PR>
   gitleaks git --redact=false --no-banner --log-opts="-1 <commit-SHA> --"
   ```

3. The local scan shows the unredacted secret. Do this in a private terminal
   on a trusted workstation; do NOT paste the unredacted secret anywhere.
4. Identify which `prd` token shape matched, then follow the rotation
   playbook above.
5. After rotation, re-run the workflow on the PR to confirm the finding
   does not re-fire (it should still fire — the secret is in git history;
   the point is to confirm the scan is detecting the same line).

## Author-Side Pitfalls

Pitfalls discovered while authoring the rule pack and CI workflow during
PR1 of #3121. Read before adding a new custom rule or smoke-test fixture.

### Always use non-capturing groups in custom rule regexes

Gitleaks auto-picks the **first capturing group** as `secretGroup` when
the rule does not set `secretGroup` explicitly. A token-shape alternation
like `(pt|st|sa|ct)` becomes the secret body, and the rule extracts only
that fragment instead of the full token — detection silently degrades.

```
# Wrong — first group captured by gitleaks as secretGroup
regex = '''dp\.(pt|st|sa|ct)\.[A-Za-z0-9_\-]{40,}'''

# Right — non-capturing group; gitleaks captures the whole match
regex = '''dp\.(?:pt|st|sa|ct)\.[A-Za-z0-9_\-]{40,}'''
```

**Rule:** every custom regex in `.gitleaks.toml` must use `(?:...)` for
grouping unless an explicit `secretGroup = N` is set with intent. The
smoke-fixture for the rule should include the full token shape so that a
silent capture-group regression is caught at CI time, not in production.

### Doppler-shape literals in workflow files trip GitHub push protection

GitHub server-side push protection scans every committed line for the
contiguous Doppler shape (and Slack, Stripe, AWS PATs, GitHub PATs, etc.)
regardless of file path or surrounding context. A YAML env literal like:

```yaml
env:
  FAKE_DOPPLER: "dp.pt.SMOKETEST..."
```

is rejected at push time with `GH013: Push cannot contain secrets`, even
though the value is a fixture and the file is `.github/workflows/*.yml`.

**Workaround:** split the shape across two env vars and concatenate at
runtime in the step:

```yaml
env:
  FAKE_DOPPLER_PREFIX: "dp.pt."
  FAKE_DOPPLER_BODY: "SMOKETEST..."
run: |
  echo "${FAKE_DOPPLER_PREFIX}${FAKE_DOPPLER_BODY}" > /tmp/fixture
```

Same trick applies to any vendor whose token shape GitHub push-protection
recognizes when a fake fixture token is genuinely needed for a smoke test.
Generating the fixture from random bytes inside a `run:` step is also
acceptable; the split-env pattern is preferred when you need fixture
stability across runs.

### Override default-pack rules by id, don't add parallel rules

Per-rule allowlists do **not** apply across rules. A custom rule named
`doppler-api-token-custom` with a `paths` allowlist will not silence the
default pack's `doppler-api-token` rule on the same file. To extend the
default pack with allowlists, declare a custom rule with the **same id**
as the default-pack rule — gitleaks treats the local definition as an
override, not an addition.

### Smoke-test fakes should map to allowlistable rules

`jwt` (default rule, v8.24.2) cannot be allowlisted per-path. If a smoke
matrix needs a fake JWT-shaped fixture, either upgrade gitleaks to a
version that supports per-path allowlist for `jwt`, or pick a different
fake-token shape whose rule you can allowlist. We chose Doppler shapes
for the smoke matrix because our custom rules carry the path allowlist.

## Rule-pack maintenance

When a new token shape lands in Doppler that the current pack misses:

1. Open a PR adding a `[[rules]]` block to `.gitleaks.toml`. Include:
   - `id` — kebab-case, prefix with vendor (e.g., `vendor-product-key`).
   - `description` — one line.
   - `regex` — anchored on a fixed prefix (`whsec_`, `sk-ant-`, etc.) to
     reduce false positives. Use `entropy = 4.5` or higher when shape alone
     would over-match.
   - `keywords` — array of literal substrings; gitleaks pre-filters lines
     by these before running the regex (cheap perf optimization).
   - Per-rule `[[rules.allowlists]]` block with the standard four paths.
2. Add a smoke-test case to `secret-scan.yml` matrix: stage a synthetic
   token in `__goldens__/` (expect pass) and at a server path (expect fail).
3. The weekly cron will re-scan history on Monday with the new rule pack;
   any pre-existing leak surfaces there.

## Upgrading gitleaks

`.gitleaks.toml` and `secret-scan.yml` are pinned to v8.24.2 with a
hardcoded SHA256.

To upgrade:

1. Read the gitleaks CHANGELOG between current and target. Pay special
   attention to schema changes — v8.25 introduced top-level `[[allowlists]]`
   with `targetRules = [...]`. Migrating to v8.25+ would let us collapse 13
   per-rule allowlist blocks into one. Worth doing on the next bump.
2. Fetch the new SHA256 from the release's `checksums.txt`:
   ```bash
   curl -sL https://github.com/gitleaks/gitleaks/releases/download/v<NEW>/gitleaks_<NEW>_checksums.txt \
     | grep linux_x64.tar.gz
   ```
3. Update `GITLEAKS_VERSION` and `GITLEAKS_SHA256` in `.github/workflows/secret-scan.yml`.
4. Verify the smoke-test matrix still passes on the bump PR.
5. Update the version pin reference in this runbook's frontmatter.

## See also

- [`golden-tests.md`](./golden-tests.md) — the partner runbook for the
  `__goldens__/` convention introduced in PR2 of #3121.
- [`AGENTS.md` rule `cq-test-fixtures-synthesized-only`](../../../AGENTS.md) —
  the workflow rule that documents the no-real-data invariant.
