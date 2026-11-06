# Learning: an `allow skipped` needs-result allowance leaks a dependency's failure downstream — re-derive every consumer's allowance when a need gains a new skip path

## Problem

PR #12153 (second review round). In `.github/workflows/inngest-key-rotate.yml`, the downstream write jobs `reboot`, `apply2` and `redeploy` legitimately allow `needs.apply1.result == 'skipped'`: under converge mode `apply1` is skipped by design and the later jobs must still run. When the new `approve` job landed, `apply1` gained a **second** skip path — a rejected or failed approval makes `apply1` skip — but the downstream allowance does not distinguish *why* `apply1` skipped. So on a refused approval, `apply1` skipped and `reboot`/`apply2`/`redeploy` read `apply1.result == 'skipped'`, matched the converge-shaped allowance, and ran their write steps on a rejected approval. `notify` stayed skipped, so the leak was silent.

## Solution

Add `approve` to each downstream job's `needs:` and add the same disjunct the first write job carries (commit 5ef3082cd8):

```yaml
# reboot / apply2 / redeploy — Before:
needs: [guard, apply1]          # (+ reboot, apply2 respectively)
if: ${{ !cancelled() && ... && (needs.apply1.result == 'success' || needs.apply1.result == 'skipped') && ... }}
# After:
needs: [guard, approve, apply1] # (+ reboot, apply2 respectively)
if: ${{ !cancelled() && ... && (needs.apply1.result == 'success' || needs.apply1.result == 'skipped') && (needs.guard.outputs.mode == 'plan' || needs.approve.result == 'success') && ... }}
```

The test suite gained `rotate/approve-fails` and `converge/approve-fails` matrix rows asserting every write job skips when `approve` fails — the leak shape is now a pinned expectation.

## Key Insight

A `needs.X.result == 'skipped'` allowance is a claim about **which path produced the skip**, encoded without the path. The moment the upstream job gains a new skip/fail route (here: approve-failure → apply1-skip), every downstream consumer's result-allowance must be re-derived — the allowance that was safe for one producer silently admits the other. The general rule: when a job's `needs:` set or its upstream's result-set changes, walk every DOWNSTREAM consumer, not just the job you edited. Same enumeration failure class as `2026-05-29-cancel-pending-invite-token-gate-consumer-enumeration.md` (harden every consumer of a gated state, not just the read path). Sibling mechanism, same session: `2026-11-05-an-implicit-success-in-a-job-level-if-stopped-the-apply-jobs-and-the-evaluators-agreed.md`.

## Session Errors

1. **The round-1 review fix modeled only the plan-mode skip path and stopped there** — the approve-failure path surfaced only in the second review round. Recovery: the approve-fails matrix rows pin both modes. **Prevention:** when a fix introduces a skip/fail branch, enumerate the upstream's full result-set (`success/failure/skipped/cancelled`) against each consumer before calling the fix complete.

## Tags
category: logic-errors
module: .github/workflows/inngest-key-rotate.yml, apps/web-platform/infra/inngest-key-rotate-workflow.test.sh
