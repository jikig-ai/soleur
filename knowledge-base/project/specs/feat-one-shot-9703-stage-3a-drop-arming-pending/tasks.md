# Tasks: Stage 3a of #9703 - drop `arming_pending` from the Inngest probe heartbeat row

Plan: `knowledge-base/project/plans/2026-10-12-chore-inngest-probe-heartbeat-drop-arming-pending-plan.md`
Branch: `feat-one-shot-9703-stage-3a-drop-arming-pending` | Draft PR: #10134 | Issue: #9703 (`Ref` only, never a closing keyword)

Evidence to cite everywhere the docs say "armed": arm read-back `status=up paused=false` (2026-10-12), feeder runs 38264380002
(forced), 38265381453 and 38267189184 (clock-dispatched), each `verdict=beat http=200`. Record is dated; live state is read
from Better Stack, not from the repo.

## Phase 1: RED - flip the parity test

- 1.1 In `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh`, update the header comment (lines 13-15) and the section (h) comment.
- 1.2 Replace the `arming_pending` presence assertion (lines 181-185) with its inverse, bound to the row block and to code lines only (comments stripped), with a cardinality check (exactly one `name: "inngest_server_probe"`) and positive `feeder:` / `exempt_reason:` checks.
- 1.3 Move the other three section (h) assertions from the `grep -A 30` window to the row block. Keep `EXPECTED_PASSES=21`.
- 1.4 Run `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` and confirm it is RED against the unchanged manifest.

## Phase 2: GREEN - the manifest row

- 2.1 In `plugins/soleur/lib/heartbeat-manifest.ts` delete `arming_pending: { tracking_issue: 9703 },` from the `inngest_server_probe` row.
- 2.2 Rewrite the row comment as a dated record (style of the `git_data_host_prd` comment): no `arming_pending`, armed 2026-10-12, read-back, the three run ids, "live state is read from Better Stack", `paused: true` stays (source `.tf` state).
- 2.3 Change `exempt_reason` from "fed; arming pending on #9703" to "fed and armed (2026-10-12, #9703)"; keep the rest of the sentence.
- 2.4 Leave the `arming_pending?` interface field and doc untouched. Re-run the Phase 1 test: GREEN.

## Phase 3: code-adjacent comments

- 3.1 `apps/web-platform/infra/uptime-alerts.tf` lines ~527-529: rewrite the single sentence naming `feeder.kind = "none" + tracking_issue + arming_pending` as one coherent sentence (feeder landed, #9703; armed 2026-10-12). Touch nothing else in the file. Check comment-only diff and `terraform fmt -check`.
- 3.2 `.github/workflows/scheduled-inngest-probe-heartbeat.yml` line 9: "FED but not ARMED ..." becomes "FED and ARMED (2026-10-12) ...". Comment-only; run `actionlint` on the file.

## Phase 4: docs that state the arming status (one sentence or paragraph each)

- 4.1 `knowledge-base/engineering/operations/runbooks/inngest-server.md` ~line 1192: fix the `inngest_consumer` sentence (its row no longer carries `arming_pending`; observed `up` 2026-09-15 per the manifest comment). Do not cite this arm's run ids here.
- 4.2 Same file ~line 1539: replace "fed but not armed until the arming command below has run ..." with the dated armed record and the three run ids. Keep the arm block.
- 4.3 Same file ~lines 1679-1681: change "Only then drop `arming_pending` ... in a record PR" to past tense (dropped in the Stage 3a record PR, #10134).
- 4.4 `ADR-117-executable-heartbeat-arming.md`: append one dated sentence to the "Fed is not armed" paragraph of the 2026-10-11 amendment.
- 4.5 `knowledge-base/engineering/architecture/diagrams/model.c4` line 320: replace the "fed but NOT armed ... tracked on #9703" clause. Read all three `.c4` files first; confirm no actor, system or relationship changes.
- 4.6 `bash scripts/regenerate-c4-model.sh` (never hand-edit `model.likec4.json`); run `bash plugins/soleur/test/c4-count-parity.test.sh` and the two C4 vitest files.

## Phase 5: verify and ship

- 5.1 Guard 1 scratch-copy mutation rows M1-M6 (see the plan's Guard Contract); paste observed RED/GREEN lines into the PR body.
- 5.2 Targeted suites from the plan's Acceptance Criteria; gate-own invocations (`lint-infra-no-human-steps.py --changed --base origin/main`, `lint-guard-contract.py`, `actionlint`, markdownlint on the md files).
- 5.3 Union grep on the final diff: Stage 3b files untouched, `uptime-alerts.tf` comment-only, no closing keyword, trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- 5.4 PR body: first line answers "does merging this alone mutate production?" (web image deploy + plugin patch release for the `plugins/soleur/lib` edit; push-apply must plan no changes for the probe resources; no Better Stack, Sentry or Terraform write). Then `Ref #9703`, `## Changelog`, and the closing line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- 5.5 Comment on #9703: 3a landed with the three run ids; 3b (delete the 8296 probe, route the Sentry monitor, refresh other stale `.tf` comments, close #9703 explicitly) remains.

## Out of scope (Stage 3b)

Deleting `scripts/followthroughs/inngest-luks-property-8296*` and every row naming it; removing the follow-through directive from #9703;
routing the Sentry monitor; `scripts/encryption-posture-ledger.json`; `betterstack-logs-alerts.tf` comments; the legal audit record.
No `terraform apply`, no production write, no SSH. Do not touch web-1 LUKS volume 106443278, the inngest volume attachment, or PR 10081.
