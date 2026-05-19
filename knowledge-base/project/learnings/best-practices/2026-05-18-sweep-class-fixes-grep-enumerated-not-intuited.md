---
date: 2026-05-18
problem_type: best_practice
component: workflow
symptoms:
  - "Runbook sweep missed 2 invocations in plan-named files (caught by multi-agent review)"
  - "Hook regex widened to cover 4 configs but missed a 5th config used by in-scope runbooks"
  - "Bootstrap script's `set -euo pipefail` abort left cleartext secret artifact on disk"
root_cause: intuited_enumeration_replacing_grep_enumeration
severity: high
tags: [sweep-fixes, regex-widening, exit-trap, secret-handling, multi-agent-review]
related_pr: 4031
related_issue: 4029
synced_to: [review]
---

# Sweep-class fixes: grep-enumerated, not intuited

## Problem

PR #4031 widened `.claude/hooks/prod-write-defer-gate.sh` to defer `doppler secrets {set|delete}` across more configs after #4029 leaked X_API_SECRET value chunks via the post-deletion surviving-secrets table render. The fix had three layers (hook regex + runbook sweep + post-merge rotation bootstrap). Multi-agent review caught three coverage gaps that all share one root cause: **the operator (me) enumerated the touch-sites by intuition instead of running the authoritative verification grep first**.

### Gap 1 — Runbook sweep missed 2 invocations

Plan AC5 named four runbooks as in-scope for the `--silent` + `>/dev/null 2>&1` sweep and provided a verification grep:

```bash
git grep -nE '(^|[[:space:]])doppler[[:space:]]+secrets[[:space:]]+(set|delete)[[:space:]]' \
  knowledge-base/engineering/ ... \
  | grep -vE '>/dev/null 2>&1|--silent|...'
```

I ran this grep BEFORE my edits — 9 hits across 4 files. I fixed each hit. The grep then returned 0. I declared done. But the grep ran ONCE at the start and the hits I saw were the only ones I edited. Two invocations in the SAME files were buried in deeper sections that I never landed on (`github-app-drift.md:263` rotation example; `tenant-provisioning.md:376` teardown one-liner). My intuition was "these files are 100% swept because I fixed the hits." Reality was "I fixed the hits I saw at one moment in time."

### Gap 2 — Hook regex widened to 4 configs, missed a 5th

Plan named `(prd|prd_terraform|dev|ci)` as the config-set to cover (derived from the configs where the #4029 leak event happened). I widened the regex accordingly. But the tenant-* runbooks operate against `prd_orchestration` (cross-tenant INSTALLATION_ID storage). Same post-deletion surviving-secrets table render trap applies cross-tenant. Security-sentinel caught it at review.

The plan's config-set was the **leak's footprint**. The trap-class config-set is the **union of every config the in-scope runbooks touch**. I conflated them.

### Gap 3 — Bootstrap script EXIT-trap gap

The first version of `scripts/rotate-x-api-secret-bootstrap.sh` had `set -euo pipefail` + a tail-of-script `shred -u "$TOKEN_FILE"`. If `gh secret set` failed between the Doppler write and the shred, the pipefail abort skipped the shred. Result: Doppler prd holds NEW secret, GitHub Actions repo secret holds OLD (compromised) secret, AND `.playwright-mcp/x-api-secret.txt` persists on disk as cleartext. User-impact-reviewer rated this P1.

## Solution

### For sweep-class fixes (Gaps 1 + 2)

When a plan declares a sweep, the verification grep is the **work checklist**, not a final check. Refactored workflow:

```bash
# Phase A: enumerate authoritatively (NOT by reading the plan's narrative).
git grep -nE '<pattern>' <plan-named-scope> > /tmp/sweep-targets.txt
wc -l < /tmp/sweep-targets.txt   # The work is N lines, not "as many as the narrative implies."

# Phase B: fix each line. Re-run the grep AFTER each batch.
# A non-zero result here means MORE WORK, not "false positive."

# Phase C: when the grep returns 0, the sweep is done.
# Cross-check against the plan's enumeration to validate the plan's scope,
# but the grep — not the plan — is authoritative.
```

The same pattern applies to regex widenings: enumerate the configs (or verbs, or paths) the **in-scope runbooks** invoke, not the configs the **incident** named. Tooling:

```bash
# For a doppler config widening:
git grep -nhE '(--config|-c)[[:space:]]+[a-z_]+' \
  knowledge-base/engineering/ops/runbooks/ \
  | awk '{for(i=1;i<=NF;i++) if ($i ~ /^(--config|-c)$/) print $(i+1)}' \
  | sort -u
```

That command answers "every config every in-scope runbook touches." The widened regex's alternation must include every value the command returns. The plan's narrative is a starting point, not a closed set.

### For bootstrap-style cleanup scripts (Gap 3)

Any script handling a cleartext secret artifact across multiple prod writes MUST install the cleanup in an `EXIT` trap, NOT at the tail. Recipe:

```bash
#!/usr/bin/env bash
set -euo pipefail

TOKEN_FILE=".playwright-mcp/x-api-secret.txt"

# EXIT trap fires on success AND on `set -e` abort. `|| true` makes the
# success-path's explicit shred (at the end of the script) idempotent —
# the file's already gone; that's fine.
trap 'shred -u "$TOKEN_FILE" 2>/dev/null || true' EXIT

# ... rest of the script.
```

Symmetric handling for in-memory copies:

```bash
SECRET_VALUE="$(...)"

# Use $SECRET_VALUE for all prod writes.

# Clear immediately after the LAST prod write succeeds. The variable
# still lives in the script's env until the script exits, but the
# window is bounded.
unset SECRET_VALUE

# Now the rest of the script (smoke tests, verification, etc.) runs
# without the value resident.
```

## Prevention

1. **Treat the verification grep as the work-list, not the close-out check.** Run it ONCE at the start, save the output, use it as the checklist. Re-run after each batch. The plan's narrative enumeration is a starting hypothesis; the grep is the truth.
2. **For regex widenings, enumerate from the in-scope runbooks (or the touch-sites the new rule will apply to), not from the incident's footprint.** The incident is one data point; the trap-class is the surface.
3. **For scripts handling cleartext secret artifacts, install cleanup in `trap '... EXIT'` at the top of the script, immediately after `set -euo pipefail` and the artifact-file constant.** Never rely on tail-of-script cleanup when `set -e` is active.
4. **Multi-agent review at PR time catches this class of gap reliably.** Pattern-recognition + security-sentinel both independently flagged Gaps 1 + 2 in this PR. User-impact-reviewer caught Gap 3. The defect class is "operator's intuited enumeration vs the grep/agent's exhaustive enumeration" — for security-remediation PRs, the multi-agent panel is load-bearing, not optional.

## Session Errors

1. **AC5 runbook sweep missed 2 invocations in named files.** Recovery: pattern-recognition + security-sentinel both flagged at review; fixed in `review: ...` commit. **Prevention:** Treat the verification grep as the authoritative work-list (see Solution §Phase A above). Don't trust intuited "I fixed all the hits I saw" — re-run the grep after each batch.

2. **Hook regex widened to (prd|prd_terraform|dev|ci) — missed `prd_orchestration`.** Recovery: security-sentinel flagged; widened to include `prd_orchestration` with 2 new positive tests (B24, B25) and README update. **Prevention:** When widening a regex to cover "every config where the trap applies," enumerate every config invoked by the in-scope runbooks, not just the configs the incident occurred against.

3. **Bootstrap script EXIT-trap gap left cleartext file on `set -e` abort.** Recovery: user-impact-reviewer flagged as P1; added `trap '... EXIT'` early in the script + `unset SECRET_VALUE` after step 3. **Prevention:** Recipe in Solution §For bootstrap-style cleanup scripts above.

4. **Multi-line `\` continuation evades per-line verification grep.** First AC5 check returned 1 result because `tenant-provisioning.md:358-359` had `\` continuation and the `--silent` flag was on line 359 while the match was line 358. Recovery: collapsed onto one line. **Prevention:** When the verification grep is per-line and the doc pattern uses `\` continuation, collapse to one line OR annotate the matching line with `# safe: <reason>` per plan AC5's escape clause.

5. **Interactive readline UI hidden by `>/dev/null 2>&1`.** First version of my `github-app-drift.md:85` fix added the redirect to an interactive `doppler secrets set` invocation that reads from operator stdin via Ctrl-D — the redirect hides the prompt and makes the command look hung. Recovery: removed redirect on interactive line; kept on pipe-fed line. **Prevention:** The canonical no-leak pattern is `--silent` + redirect ONLY on non-interactive (pipe-fed, value-via-flag, value-via-stdin-script) invocations. Interactive readline invocations need only `--silent`.

6. **Plan+deepen subagent didn't create tasks.md/spec.md.** The subagent wrote only the plan file; /work expected `knowledge-base/project/specs/feat-<name>/tasks.md` to exist. Recovery: created spec.md, tasks.md, and session-state.md manually. **Prevention:** Formalize in the plan skill's exit checklist — the plan skill should always emit the spec dir + tasks.md + session-state.md alongside the plan file, not just the plan file.

## See also

- `2026-05-12-cross-session-lock-lease-bash-primitives.md` — same hook regex's wrapped-form anchor pattern; widened-rule shape preserves the same anchor class.
- `2026-05-18-supabase-custom-access-token-hook-discriminator.md` — Leak-2 entry was amended at this PR to correct the false "no `--silent` flag exists" claim.
- `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md` — bootstrap script's Playwright `browser_evaluate(filename:)` pattern.
