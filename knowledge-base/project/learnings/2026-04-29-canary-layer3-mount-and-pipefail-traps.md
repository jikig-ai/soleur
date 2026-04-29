---
category: integration-issues
module: web-platform-infra
tags: [canary, ci-deploy, terraform, cloud-init, bash-strict-mode, pipefail, dedupe]
related_pr: 3042
related_issues: [3033, 3045, 3047, 3048]
---

# Learning: Canary Layer 3 mount path + dedupe ordering + pipefail-around-logger

## Problem

PR #3014 introduced canary Layer 3 — a JWT-claim probe of the deployed Next.js bundle — to catch the #3007 client-only validator-throw class that SSR HTML probes miss. The probe never executed in production for the week it shipped, because three independent failure modes compounded:

1. **Mount-path drift.** `ci-deploy.sh` invoked `canary-bundle-claim-check.sh` from `/app/shared/apps/web-platform/infra/...`, but the canary container only mounts `/mnt/data/plugins/soleur` — there is no `/mnt/data/apps/` mount, and that path is empty on the host. The `[[ -x "$CANARY_LAYER_3_SCRIPT" ]]` gate silently failed every iteration.
2. **Bundle layout assumption.** PR #3017 ("browser-safe JWT decode + preflight Check 9 + Layer 2 promotion") moved the inlined Supabase init out of the login chunk into a shared vendor chunk (`8237-*.js`). The probe hardcoded the login chunk path and grepped for `eyJ...` in that single chunk, so even if the mount were fixed the probe would now fail with `no JWT found in login chunk` on every healthy deploy.
3. **No CI test.** The probe script had no fixture coverage, so neither (1) nor (2) tripped any gate before merge.

## Solution

Three independent fixes landed in one PR:

**Mount fix:** Ship the script via `terraform_data.deploy_pipeline_fix` (existing servers) and `cloud-init.write_files` (fresh servers), mirroring the pattern already in place for `ci-deploy.sh` and `cat-deploy-state.sh`. Single source of truth at `apps/web-platform/infra/canary-bundle-claim-check.sh`; both delivery paths key off the same byte content via `base64encode(file(...))` (for cloud-init) and `provisioner "file"` + `triggers_replace = sha256(... file(...) ...)` (for terraform_data). Default of `CANARY_LAYER_3_SCRIPT` switched from the never-resolving `/app/shared/apps/...` to `/usr/local/bin/canary-bundle-claim-check.sh`.

**Bundle layout fix:** Replaced the hardcoded login chunk regex with a dynamic discovery loop that mirrors PR #3029's preflight Check 5 — enumerate all `<script src="/_next/static/chunks/...js">` references from `/login` HTML (cap 20), per-chunk fetch with `--max-time 5 --max-filesize 5242880`, path-validation regex `^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$` for command-injection defense, redirected-stdin `while read` loop (NOT pipe-into-while — subshell variable scope trap), `jq -er` decode pipeline, and a sanitize() pass that strips C0 controls + DEL + UTF-8 byte sequences for U+2028/U+2029 before any echo to stderr.

**Test fix:** New `canary-bundle-claim-check.test.sh` with 14 fixtures covering both bundle layouts (F1 pre-#3017, F2 post-#3017, F3 mid-traversal), every claim-failure mode (F4-F7), every fetch/discovery failure mode (F8-F11), log-injection guards for both C0 and U+2028 (F12, F12-bis), and the cap-of-20 boundary (F13). Wired into `.github/workflows/infra-validation.yml`'s `deploy-script-tests` job.

## Key Insights

### 1. `awk '!seen[$0]++'` not `sort -u` for capped enumeration

When a discovery loop uses `head -N` to cap candidates, dedupe BEFORE `head` must preserve document order. `sort -u` reorders alphabetically (c1, c10, c11..., c19, c2, c20, c21, c3..., c9) and a cap of 20 silently includes c21 — exactly the bug F13 was designed to catch but originally couldn't catch because the script used `sort -u` first.

**Pattern:**
```bash
grep -oE 'pattern' file | awk '!seen[$0]++' | head -20
```

The same drift had to be healed in `plugins/soleur/skills/preflight/SKILL.md` line 262 (which inherited the `sort -u` form from PR #3029's first revision).

### 2. `set +o pipefail` is required around `cmd | logger -t` under `set -euo pipefail`

Piping a fallible command through `logger` for journalctl triage seems harmless — `logger` always returns 0 in normal operation, so the pipe rc would be 0 and the post-pipe rc-check would be the only gate. Wrong: with `pipefail` ON, the pipe rc is the rightmost non-zero rc (the script's failure), and `set -e` aborts the entire ci-deploy run before the rc-check can fire.

**Pattern (load-bearing):**
```bash
if [[ -x "$SCRIPT" ]]; then
  set +o pipefail
  "$SCRIPT" "$ARGS" 2>&1 | logger -t "$LOG_TAG" -p user.warning
  rc=${PIPESTATUS[0]}
  set -o pipefail
  if [[ "$rc" -ne 0 ]]; then
    # handle failure
  fi
fi
```

`${PIPESTATUS[0]}` is load-bearing because `| logger` swallows the script's rc into the pipe; only PIPESTATUS preserves it. The `set +o pipefail` window is exactly three lines so a future refactor doesn't accidentally widen the pipefail-disabled scope.

### 3. The umbrella reason was for log-stability, not a parser contract

The plan and initial implementation framed the umbrella `canary_layer3_jwt_claims` reason as preserving a "cross-repo string-shape contract" with `cat-deploy-state.sh` and `reusable-release.yml`. Architecture review showed that contract is unverifiable: `cat-deploy-state.sh` is opaque-passthrough (`jq -c .`), and `web-platform-release.yml` line 295 uses `*)` catch-all on the reason field for `::error::` printing. There is no parser anywhere in the repo that asserts on specific reason strings.

The umbrella still has a real (smaller) reason to exist: log-stability of the deploy-status `::error::` line in CI runs. Granular reasons (`canary_layer3_no_jwt`, `canary_layer3_no_chunks`, etc.) can flow to journalctl for SSH triage; promoting them into the state-file reason would surface them in CI logs too but changes the log-line shape every time the failure mode changes. Tracked in #3047.

### 4. Discoverability is load-bearing for new test files

A test file that no CI workflow runs is a silent rot vector. Phase 3 of the plan called this out explicitly and prescribed `grep -rn 'canary-bundle-claim-check' .github/workflows/` as the post-creation discoverability gate. Without that gate, the new fixtures would have lived as a maintenance burden with zero protective value.

## Session Errors

- **F11 fixture initially didn't match the eyJ regex (used `!!!` chars not in base64url alphabet).** Recovery: rewrote the fixture to use a base64-shaped payload (`Y29ycnVwdGNvcnJ1cHRjb3JydXB0`) that decodes to non-JSON bytes, exercising the `jq -er` parse-failure path. **Prevention:** Already covered (the test author has line-of-sight to the regex; standard fixture-design discipline).

- **F13 fixture initially passed against the intended-broken script** because the script used `sort -u` (not `awk '!seen[$0]++'`), so chunk c21 alphabetically sorted into the first 20 of (c1, c10, c11...c20, c21, c2, c3...c9). This was the F13 fixture catching exactly the bug it was designed to catch — but only AFTER the script was rewritten. **Prevention:** Captured in Key Insight #1 above; healed `preflight/SKILL.md` so the runbook agrees with the canary script.

- **ci-deploy.test.sh Layer 3 rollback fixture failed under the new pipe** because `set -euo pipefail` aborted on the script's first non-zero rc through `| logger`. The umbrella `canary_layer3_jwt_claims` reason was never written to state file because the script aborted before the post-pipe rc-check. **Recovery:** scope-disabled pipefail with `set +o pipefail`/`set -o pipefail`. **Prevention:** Captured in Key Insight #2 above.

- **shellcheck SC2034 on `JWT_CHUNK`** (introduced briefly during GREEN; the variable was tracked but never read). **Recovery:** removed in same edit cycle. **Prevention:** Already enforced by existing shellcheck step in `infra-validation.yml`.

- **`cd apps/web-platform/infra` failed because the shell was already in that directory from a prior cd that didn't reset.** **Recovery:** switched to `terraform -chdir=apps/web-platform/infra`. **Prevention:** Already enforced by AGENTS.md `cm-when-running-test/lint/budget-commands` (use absolute paths or `--chdir`).

- **`gh issue create` rejected `type/improvement` label** (tried as a guess from training data; the project uses `type/chore` for refactor/tech debt). **Recovery:** retried with `type/chore`. **Prevention:** Already covered by `cq-gh-issue-label-verify-name` rule.

## Cross-references

- PR #3033 — originating issue
- PR #3014 — introduced Layer 3 + the silent-skip
- PR #3017 — caused the bundle-layout assumption regression
- PR #3029 — load-bearing precedent for dynamic chunk discovery (preflight Check 5)
- Issue #3045 — follow-up: investigate empty `/mnt/data/plugins/soleur` mount
- Issue #3047 — follow-up: surface granular Layer 3 reasons in deploy-status state
- Issue #3048 — follow-up: apply `logger -t` pattern to canary Layers 1/2/4
- `knowledge-base/project/learnings/2026-04-21-cloud-task-silence-watchdog-pattern.md` — bash-strict-mode tradeoffs
- `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` — log-injection guard precedent
- `knowledge-base/project/learnings/integration-issues/2026-04-29-webpack-chunk-relocation-invalidates-bundle-content-canary.md` — the chunk-relocation class this fix closes
