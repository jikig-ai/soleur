# Learning: cross-file drift guards must extract EVERY numeric operand by shape — one hardcoded term re-creates the drift class the guard exists to catch

## Problem

PR #5146 (#5145) added a cross-file budget drift guard to `ci-deploy.test.sh`: the restart workflow's client poll window (`MAX_POLLS × POLL_INTERVAL`) must cover ci-deploy.sh's server-side verify worst case (`(health + cron) × (interval + curl_tail) + TimeoutStopSec + margin`). The first implementation extracted five operands by shape (regex over the source files) but hardcoded the sixth — `+180` for `TimeoutStopSec` — as a literal copied from `inngest-bootstrap.sh:178`. Four independent review agents (pattern-recognition, performance-oracle, git-history-analyzer, test-design-reviewer) concurred: a server-side retune of `TimeoutStopSec` to 240 would have silently consumed the exact 60s headroom and the guard would have green-lit a too-small client window — the precise failure class the guard was written to catch, with one of its three files unguarded.

## Solution

Extract the sixth operand by shape too, scoped to its unit region (a second `TimeoutStopSec=30` exists in the sibling vector unit):

```bash
DG_INNGEST_UNIT=$(awk '/Description=Inngest self-hosted server/,/^UNITEOF$/' "$BOOTSTRAP_SCRIPT")
DG_STOP=$(printf '%s\n' "$DG_INNGEST_UNIT" | grep -oE '^TimeoutStopSec=[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
```

plus the same hardening every extraction gets: exactly-one assignment-count check per shape (a future sibling match silently retargets `head -1`), and `[[ "$v" =~ ^[0-9]+$ ]]` validation BEFORE arithmetic (bash `$((empty * 5))` evaluates to 0 silently and the inequality passes for the wrong reason).

## Key Insight

When a test encodes a cross-file inequality, audit each term and ask "which file does this number live in, and does the guard read that file?" Every term whose source file is not read by the guard is a silent-drift hole. The checklist that survived four-agent review:

1. Extract by SHAPE (regex with `[0-9]+`), never pin literals in the invariant assertion — pins belong in a separate exact-value assertion whose job is catching down-tuning.
2. Exactly-one count check per extraction shape, per file.
3. Integer-validate every extracted value before `$(( ))`.
4. Scope extractions to their region when the pattern recurs in the file (awk range over the owning unit/function).
5. FAIL message prints every extracted value + both sides + all file names.

## Session Errors

1. **`${1:-10}` digit-run extraction grabbed the positional index, not the default.** `grep -oE '[0-9]+'` on `${1:-10}` emits two runs — "1" then "10" — and `head -1` returns the wrong one. Caught at write time before the RED run. **Prevention:** for `${N:-DEFAULT}` shapes, take `tail -1` of the digit runs (the default is the last run), and keep the RED-first discipline that exposes wrong extractions as loud failures.
2. **Plan AC asserted `actionlint exits 0` while main's baseline also exits 1** (pre-existing SC2034 warning) — the plan had verified actionlint was *installed*, not that it passed. **Prevention:** plan-quoted tool-gate preconditions are preconditions to verify (run the gate against origin/main before trusting "exits 0" as the acceptance shape); when the baseline already fails, the AC must either fix the pre-existing warning in-scope or assert no-new-findings instead.
3. **Stale-at-birth line-number comment:** a new test comment cited `ci-deploy.sh:674`, which this same PR's edits shifted to :686; three review agents flagged it. **Prevention:** never cite absolute line numbers of a file your own PR edits — reference by symbol/anchor ("the deploy-arm health probe outside the function") instead.
4. **Forwarded (plan phase): IaC-routing hook false positive** on descriptive `systemctl` prose in the plan body. Recovery: documented `iac-routing-ack` opt-out after Phase 2.8 review. **Prevention:** existing opt-out path is the prevention; no new rule needed.
5. **Edit-before-Read rejections (×2)** on files only inspected via Bash `sed`. Recovery: Read then re-Edit. **Prevention:** already mechanically enforced; read target regions with the Read tool when an Edit is anticipated.
6. **Chained `sleep 60` Bash call denied** by the background-poll hook. Recovery: Monitor + TaskOutput blocking wait. **Prevention:** already hook-enforced (`hr-monitor-not-run-in-background-for-polling`).
7. **Review-agent stale-fact divergence:** git-history-analyzer reasoned from the pre-#5066 900s wrapper cap while performance-oracle read `ci-deploy-wrapper.sh:15` and found 1800s. Recovery: cross-reconcile favored the agent that read the file. **Prevention:** covered by the existing review sharp edge — single-agent claims about current values must be file-read-verified before acting.

## Tags

category: test-failures
module: apps/web-platform/infra
