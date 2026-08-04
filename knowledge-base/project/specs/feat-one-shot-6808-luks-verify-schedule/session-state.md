# Session State

## Status: review COMPLETE, fixes landed, shipping

The degraded pass is superseded. `/soleur:review` re-ran with a **12-agent panel** (the prior run
recorded `Reviewed-Coverage: inline-fallback 0/11 agents`). It returned **45 findings, 14 P1** — and
found the branch was **already red** on a pre-existing guard that had never been run against it.

All findings are fixed inline. Nothing was filed: the cost-of-filing gate put every fix under the
≤100-line / ≤4-file threshold, and filing would have worsened an already-blocking net-issue-flow.

## What the panel found that the green suite could not

- **20 mutations survived the original gate suite at full green**, and **45% of the suite was
  deletable while it reported `0 failed, exit 0`** — including the entire evaluated truth-table
  block, which is the PR's central claim.
- The `drift` class was a NEGATIVE gate, so any unmodelled non-zero rc — including `rc=2`, which
  bash returns on a **syntax error** — filed a p0 `type/security` issue asserting the published
  Article 32 claim FALSE.
- A >19-digit baseline made POSIX `[` exit 2, silently skipping the shortfall comparison, so a
  **total wipe reported PASS**.
- `gh issue list` was an unguarded pipeline under `set -euo pipefail`: a transient 403 aborted the
  alarm AFTER classifying and BEFORE filing. Measured directly.
- `labels` was consumed only by `gh issue create`, so a `workspace_count_shortfall` arriving onto an
  open p1 readiness issue never received `priority/p0-critical`.
- `#6808`'s own closure-condition comment still read as a **disjunction**; the conjunction
  correction had landed only in the KB file. Corrected on the issue.

## Verification

| Gate | Result |
|---|---|
| `workspaces-luks-verify-workflow.test.sh` | **121/121** (was 75) |
| Mutation battery | **20/20 killed**, sandbox copy, green control, landing asserted per mutation |
| Block deletions D1–D3 | all **RED** on a derived floor (previously all survived green) |
| `workspaces-luks-freeze.test.sh` (AC7/AC10) | 91/91 |
| `workspaces-luks-header.test.sh` (H15b/H20) | 62/62 |
| `scan-workflow.test.sh` | pass (was **RED** before the rebase) |
| `c4-count-parity.test.sh` (#7209) | 10/10 (was **0/7** post-merge) |
| shellcheck | clean on the suite; 2 pre-existing info notes in `luks-monitor.sh` |
| semgrep | 79 rules / 1 file / 0 findings, non-vacuity confirmed |
| `cron-monitors.tf` | 67 additions, **0 deletions**, 0 resources removed — no destroy derivable |

## Two things the operator must weigh at ship

1. **Net issue flow is 3 filed / 0 closed, and NO exemption applies.** `#7194` untagged
   `[mandates-filing]` from `wg-when-deferring-a-capability-create-a` four commits before this
   branch shipped, leaving `wg-block-pr-ready-on-undeferred-operator-steps` as the only mandating
   rule on `main`. The plan's premise that two filings were mandated is **no longer true**. The
   honest instrument is the `<!-- gate-override: net-issue-flow -->` marker citing #7235 as a
   discovered defect in another subsystem.
2. **P.1/P.2 are agent-doable but unrun.** `tasks.md` previously claimed `/soleur:postmerge`
   automated them; it does not read that file. Commands are now spelled out. Deliberately NOT
   filed as a fourth issue.

## Non-negotiables intact

`Ref #6808`, never `Closes` — now actually present in the PR body, which was 73 characters of
placeholder. Zero published `docs/legal/*` files touched (verified). The Inngest corollary cites
**#6178 / ADR-100**, not #5450, so #7230's re-derivation starts from the right record.

## Compounded

`knowledge-base/project/learnings/2026-08-04-a-zero-of-eleven-review-hid-fourteen-p1s-and-my-fixes-reproduced-two-of-them.md`

## One RED in the full run, resolved as contention — do not re-litigate

`scripts/test-all.sh` reported **258/259 suites**. The single failure was
`apps/web-platform/test/pdf-text-extract.test.ts` — the *"does NOT trip oversized_buffer for buffers
in the [old-15MB, new-24MB] band"* assertion, 16 s runtime. Confirmed **not** this diff, three ways:

1. **Isolated re-run: 29/29 passed.**
2. **Unreachable from the diff.** The test's SUT (`@/server/pdf-text-extract`) and both its imports
   (`@/lib/attachment-constants`, `./helpers/engines-floor`) are unchanged. This PR touches only
   `.github/workflows/`, `apps/web-platform/infra/`, one inngest count test, and `knowledge-base/`.
3. **The failure window had known resource pressure.** `/tmp` reached 100% (a whole-worktree sandbox
   copy) and a sibling `test-all` had been wedged for ~10 h, outliving its own `timeout 3000`
   wrapper. A 24 MB-buffer allocation is exactly what fails first under that.

Not filed as an issue: it is a flake induced by this session's own disk pressure, not a defect and
not a pre-existing red on `main`.

**Worth noting separately:** `test-all.sh` exited **0** while reporting 258/259. A non-zero suite
count and a zero exit code should not co-occur — that is the "a check that cannot report is
indistinguishable from one that passed" shape, in the runner itself. Not this PR's surface; recorded
here rather than swallowed.
