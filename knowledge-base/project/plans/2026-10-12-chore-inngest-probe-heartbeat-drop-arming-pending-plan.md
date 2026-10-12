---
title: "chore(infra): record the armed Inngest probe heartbeat and drop arming_pending (Stage 3a of #9703)"
date: 2026-10-12
slug: inngest-probe-heartbeat-drop-arming-pending
branch: feat-one-shot-9703-stage-3a-drop-arming-pending
issue: 9703
type: chore
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore(infra): record the armed Inngest probe heartbeat and drop `arming_pending` (Ref #9703)

Spec lacks a `spec.md` for this branch, so `lane:` defaults to `cross-domain` (fail-closed). The PR is
draft #10134. Every commit and the PR body say `Ref #9703` only; no closing keyword anywhere.

## Overview

`betteruptime_heartbeat.inngest_server_probe` (live id 504655, `soleur-inngest-server-probe-prd`,
period 3600 / grace 1800) was armed on 2026-10-12 through the runbook's arm block. The arm read-back
reported `status=up paused=false`, and the feeder has since reported `verdict=beat` on three runs. This is
Stage 3a of the staged plan in
`knowledge-base/project/plans/2026-10-11-feat-inngest-probe-heartbeat-feeder-plan.md` (Phase 7): a
**record PR** that removes `arming_pending` from the manifest row and corrects the repo wording that the
read-back now makes false. It re-arms the nightly reconcile's `fed-but-paused` class for this row, which
is the net if anything re-pauses the heartbeat (a paused heartbeat makes the feeder report
`fresh_heartbeat_paused` with exit 0, so the feeder itself would not alert).

Evidence (each `verdict=beat http=200`, read for this plan from the run logs with
`gh run view <id> --log`; all three are `workflow_dispatch` runs of
`Scheduled: Inngest Probe Heartbeat Feeder`):

| Run | Created (UTC) | Note |
|---|---|---|
| 38264380002 | 2026-10-12 14:38 | forced dispatch from the arm block, `age_s=3266` |
| 38265381453 | 2026-10-12 14:46 | clock-dispatched, `age_s=186` |
| 38267189184 | 2026-10-12 15:01 | clock-dispatched, `age_s=1052` |

The `status=up paused=false` read-back itself is a Better Stack read that this planning phase did not
repeat (it needs the read-only token, and the instruction for this phase is plan-only); it is recorded as
the arm record stated for #9703, and the docs say it is a dated record whose live state is read from Better
Stack, not from the repo (the `git_data_host_prd` precedent, PR #10080 / commit `67dec0d7c6`).

### What this PR does not do (Stage 3b, its own later PR)

Delete the superseded 8296 probe and every row naming it (`scripts/followthroughs/inngest-luks-property-8296*`,
`test-all.sh`, the two `.tsv` files, the baseline, the `MUST_FIND` entry); remove the follow-through
directive from #9703; route the Sentry monitor `scheduled_inngest_probe_heartbeat`
(`apps/web-platform/infra/sentry/`); refresh other stale `.tf` comments; edit
`scripts/encryption-posture-ledger.json`; close #9703. Its mechanical gate (four completed runs spanning
at least 45 minutes, one clean nightly reconcile after 3a) is the next PR's. No `terraform apply`, no Better
Stack write, no production action runs in this plan or this PR's authoring.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief | Reality | Plan response |
|---|---|---|
| Runbook `inngest-server.md` near line 1192 says the probe heartbeat is `arming_pending` | Line 1192 is about a **different** heartbeat, `inngest_consumer` (`soleur-inngest-consumer-prd`, #7462). Its manifest row already dropped `arming_pending` (manifest comment, observed 2026-09-15: id 482259 `paused:false status:up`, #7462 closed 2026-08-20). The sentence is stale independently of this arm | Fix the one sentence using the **manifest's own recorded evidence**, not this arm's run ids. After this PR no manifest row carries `arming_pending`, so the sentence would otherwise cite a field no row has |
| Runbook near line 1680 says drop `arming_pending` in a record PR | True, and it is the exact record this PR is. Line 1539 ("fed but not armed until the arming command below has run. Nothing in the repo may say armed before that command's read-back exists") is the sibling stale claim | Rewrite both to a dated record citing the three run ids |
| `uptime-alerts.tf` near line 528 names `feeder.kind = "none"` + `arming_pending` | True (lines 527-529), and the same sentence says the feeder is "deliberately not in this resource's PR" with candidate shapes tracked on the issue | Rewrite **that one sentence** as a unit so it stays coherent. Every other comment in the file is left for Stage 3b |
| `inngest-server-probe-heartbeat.test.sh` parity-tests the row | Section (h) asserts `arming_pending` **is present** (line 181-185) and its header says "plus arming_pending while the heartbeat is still paused" (line 14-15). It would go red the moment the manifest row changes | Flip the assertion to its inverse (see `## Guard Contract`), keep `EXPECTED_PASSES=21` |
| (implicit) only the manifest, test and comments carry the claim | Also: `model.c4` line 320 ("fed but NOT armed: arming is a separately authorized step tracked on #9703", Inngest queue description), `.github/workflows/scheduled-inngest-probe-heartbeat.yml` line 9 ("FED but not ARMED until the runbook arming step"), and the ADR-117 2026-10-11 amendment paragraph "Fed is not armed" | Include all three: they are the exact wording the read-back makes false, and Stage 1's plan (Phase 7) named "the ADR amendments and C4 clause" for 3a |

## Research Insights

Premise Validation (Phase 0.6). Checked: issue #9703 is open; PR #10134 is the open draft for this branch;
the three cited runs exist, completed with `conclusion=success`, and print `verdict=beat http=200`; the
manifest row, the test section, the `.tf` sentence and both runbook lines exist on this branch at the cited
locations; no ADR rejects the mechanism (the staged plan and ADR-117 amendment of 2026-10-11 both prescribe
dropping `arming_pending` after the read-back). Stale: the line-1192 attribution above. Nothing else.

Property List (Phase 0.6b):

1. P1 - the nightly live reconcile flags a re-pause of `inngest_server_probe` (the `fed-but-paused` class
   stops being suppressed for this row).
2. P2 - no repo statement says the heartbeat is unarmed or "arming pending", and every statement that
   it is armed is dated and cites the read-back and the run ids.
3. P3 - the parity test fails if `arming_pending` is re-added to this row.
4. P4 - the 3b gate (the superseded probe's deletion) is not pre-empted.

Cut List (Phase 0.6b). Mechanisms the brief or its parent plan could add and this plan cuts:

- An `EXPECT_ARMED` / `paused_overdue` verifier mode: P1 is already bought by the live reconcile once
  `arming_pending` is gone (`heartbeat-live-reconcile.ts:1025`); the parent plan rejected the mode for the same reason.
- A new committed mutation battery for the one flipped assertion: P3 is bought by the flipped assertion
  itself plus a work-time scratch-copy check recorded in the PR body (YAGNI; the sibling suites' batteries
  guard far larger surfaces).
- A new ADR: no architectural decision changes. The ADR-117 edit is a dated status line on an existing amendment.
- Editing `scripts/encryption-posture-ledger.json`, the 8296 script comments, `betterstack-logs-alerts.tf`
  line 276 ("born paused pending its feeder"): Stage 3b's "refresh other stale comments / prose references".

Key repo facts, with the authority read:

- `plugins/soleur/lib/heartbeat-manifest.ts` row `inngest_server_probe` (lines ~320-342): `arming_pending: { tracking_issue: 9703 }` at line 338; the row comment (lines 322-329) and `exempt_reason` (line 340) both say "arming pending". `paused: true` at line 331 is the **source `.tf`** state (born paused, `ignore_changes = [paused]`) and stays, as in the `git_data_host_prd` precedent.
- `plugins/soleur/lib/heartbeat-live-reconcile.ts:1025`: `if (fed && !row.arming_pending && livePausedByName.get(disc.liveName) === true)` is the only consumer that changes behaviour; it only reads. Live is `up`, so the nightly run stays clean.
- Merge side effects (the 2026-09-21 learning: a "merge is inert" claim is a property of the **final** file set): `plugins/soleur/lib/heartbeat-manifest.ts` is outside the `docs/` and `test/` exclusions of `web-platform-release.yml` and `version-bump-and-release.yml`, so merging builds and deploys the web image and cuts a plugin patch release (same as PR #10080 did). `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml`, with or without the `uptime-alerts.tf` edit, because the test file already lives there; the push-apply `-target` plan for `betteruptime_heartbeat.inngest_server_probe` and `doppler_secret.inngest_server_probe_heartbeat_url` must show no changes (comment-only). Re-run the union grep on the final diff at work exit.
- `scripts/check-web-host-escrow-config.sh` census lists `uptime-alerts.tf` (`WEB1_FILES`) but strips comment-only lines before matching, so a comment edit cannot trip it. No test hashes `uptime-alerts.tf`.
- PRs 10081 (parked draft) and 10086 (open) edit `runbooks/inngest-server.md` at lines ~27, ~610, ~1493 and ~3052. This plan's three runbook edits sit at ~1192, ~1539 and ~1680; the nearest hunk is 46 lines away.

Learnings applied: `2026-09-21-the-record-pr-was-inert-except-for-one-comment-and-one-aging-probe.md`
(re-run the push-filter union on the final diff), `2026-09-07-i-wrote-the-next-action-down-and-treated-that-as-doing-it.md`
(a record of arming is the read-back, not the sentence that says it), and the PR #10080 review note that a
`.tf` comment edit can be hash-bound (verified not to apply to `uptime-alerts.tf`, above).

External research skipped: strong local context, no new external API. Community discovery and functional
overlap skipped: no new stack and no new functionality.

## Scope Check

| Ask (from the brief) | Plan item |
|---|---|
| Drop `arming_pending` from the manifest row | Phase 2 |
| Anything that parity-tests it | Phase 1 (`inngest-server-probe-heartbeat.test.sh`) |
| Stale comments that say it is still pending (`uptime-alerts.tf`~528; runbook ~1192, ~1680) | Phase 3, Phase 4 |
| Wording the read-back makes true, cite the run ids | Phase 3, Phase 4 (workflow header, runbook, ADR-117, `model.c4`) |
| Not Stage 3b | `## Non-Goals` |

No unmapped ask. Two items are `inferred` and justified: the workflow header line and the `model.c4` clause
carry the same false claim (the parent plan names the C4 clause for 3a), so leaving them contradicts the
manifest this PR changes. Split assessment: one PR, ~9 small files, one concern.

## Non-Goals

Stage 3b (above); `terraform apply`; any Better Stack or GitHub write; editing the legal audit record
`knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md` (line 411, "#9703 not armed", a
dated point-in-time record that must not be rewritten); the `git_data_host_prd` runbook/ADR lines
(different heartbeat); web-1 LUKS volume 106443278; the inngest volume attachment; PR 10081's files.

## Implementation Phases

### Phase 1 - flip the parity test first (RED)

File: `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh`. Per `cq-write-failing-tests-before`, change
the test before the manifest and see it fail.

- Header (lines 13-15): replace "plus arming_pending while the heartbeat is still paused" with "and NO
  arming_pending (dropped after the 2026-10-12 arm read-back, #9703)".
- Section (h) comment (lines 150-152 region, "tracked, still-pending arming"): update to "armed; no arming_pending".
- Replace the assertion at lines 181-185 with its inverse, bound to the **row block, code lines only**:

  ```bash
  mf_row="$(awk '/name:[[:space:]]*"inngest_server_probe"/{p=1} p{print} p&&/^  \},?[[:space:]]*$/{exit}' "$MANIFEST")"
  mf_row_code="$(grep -vE '^[[:space:]]*//' <<<"$mf_row")"
  mf_row_count="$(grep -cE 'name:[[:space:]]*"inngest_server_probe"' "$MANIFEST")"
  if [ "$mf_row_count" -eq 1 ] && has "$mf_row_code" 'feeder:' && has "$mf_row_code" 'exempt_reason:' \
    && ! has "$mf_row_code" 'arming_pending'; then
    ok "the inngest_server_probe row carries no arming_pending (armed 2026-10-12, #9703; re-adding it hides a re-pause from the reconcile)"
  else
    no "the inngest_server_probe row must exist exactly once, and must not carry arming_pending in code"
  fi
  ```

  Comment lines are excluded because the dated record comment names the field (the `git_data_host_prd`
  comment at manifest line 297 does the same). The `feeder:`/`exempt_reason:` positive checks make a broken
  extractor fail instead of passing on empty input.
- Switch the other three section-(h) assertions from the `grep -A 30` window to `mf_row` so a longer row comment
  cannot push `feeder` out of a 30-line window. `EXPECTED_PASSES` stays 21 (one assertion replaced by its inverse,
  none added or removed).
- Run `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh`; expect RED (the row still carries it).

### Phase 2 - the manifest row (GREEN)

File: `plugins/soleur/lib/heartbeat-manifest.ts`, row `inngest_server_probe`.

- Delete `arming_pending: { tracking_issue: 9703 },`.
- Rewrite the row comment (lines 322-329) from "FED; ARMING PENDING on #9703 ... until the record PR removes it"
  to a dated record in the style of the `git_data_host_prd` comment (lines 297-301): no `arming_pending`
  (record PR for #9703); armed 2026-10-12 via the runbook arm block, read-back `status=up paused=false`; feeder
  runs 38264380002 (forced), 38265381453 and 38267189184 (clock-dispatched) each `verdict=beat`; a dated record,
  the live state is read from Better Stack, not from this file; `paused: true` stays (source `.tf` state, born
  paused). Keep it to ~8 comment lines.
- `exempt_reason`: "fed; arming pending on #9703 — ..." becomes "fed and armed (2026-10-12, #9703) — ..."; the rest
  of the sentence (repo-side verifier, no `inngest-host-replace`, ADR-103 `replace_target` correctly not firing)
  is unchanged.
- Leave the `arming_pending?:` interface field and its doc comment (line ~68-76): the field stays a legal state
  for future rows. Re-run Phase 1's test: GREEN.

### Phase 3 - code-adjacent comments

- `apps/web-platform/infra/uptime-alerts.tf` lines 527-529: rewrite the sentence "The FEEDER is deliberately
  not in this resource's PR — candidate shapes and the beat budget are tracked on the issue the
  heartbeat-manifest.ts row (feeder.kind = "none" + tracking_issue + arming_pending) names." as a single
  coherent sentence: the feeder landed separately (the verifier workflow the heartbeat-manifest.ts row
  evidences, #9703) and the heartbeat was armed on 2026-10-12 (read-back and run ids in the runbook section
  "Arming the probe heartbeat (#9703)"). Touch no other line of the file (the `paused = true` resource,
  "forever-until-armed" and the Doppler comment stay for Stage 3b). Comment-only: `terraform fmt -check`
  must still pass; no attribute changes.
- `.github/workflows/scheduled-inngest-probe-heartbeat.yml` line 9: "FED but not ARMED until the runbook arming
  step (...)" becomes "FED and ARMED (2026-10-12, read-back in the runbook section 'Arming the probe heartbeat')." Comment-only; the
  `schedule:` trigger, concurrency group and run line are untouched (the harness binds those, not this comment).

### Phase 4 - docs that state the arming status

Keep every edit to one sentence or paragraph; do not reflow around it.

- `knowledge-base/engineering/operations/runbooks/inngest-server.md`:
  - ~1192: replace "It is `arming_pending` on #7462 in `plugins/soleur/lib/heartbeat-manifest.ts`, so read its
    live state before relying on it — `up` is armed, `paused` is not:" with a statement that its manifest row
    no longer carries `arming_pending` (observed `up` 2026-09-15 per the manifest comment, #7462 closed
    2026-08-20) and that its live state is still worth reading (`up` is armed, `paused` is not). Keep the curl block.
  - ~1539: replace "so the feeder is **fed but not armed** until the arming command below has run. Nothing in
    the repo may say "armed" before that command's read-back exists." with the dated record: armed 2026-10-12
    through the command below; read-back `status=up paused=false`; runs 38264380002 (forced), 38265381453 and
    38267189184 (clock-dispatched) each `verdict=beat http=200`; live state is read from Better Stack, not
    this paragraph; a paused heartbeat is still reported as fed-but-not-armed by the feeder. The arm block
    stays (its state gate refuses a second arm, and it is the re-arm path after a rollback or recreate).
  - ~1679-1681: change "Only then drop `arming_pending` from the manifest row in a record PR; that re-arms the
    nightly reconcile's `fed-but-paused` class (...)" to past tense: the read-back above was taken 2026-10-12
    and `arming_pending` was dropped in the Stage 3a record PR (#10134), which re-armed the reconcile's
    `fed-but-paused` class. Keep the rest of the paragraph (the "a paused heartbeat makes the feeder report
    `fresh_heartbeat_paused`" net argument, the rollback reading guidance, the "later stages tracked on #9703" sentence).
- `knowledge-base/engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md`: in the
  2026-10-11 amendment's **"Fed" is not "armed"** paragraph (lines ~459-466) append one dated sentence (2026-10-12
  record: armed per the runbook block, `arming_pending` dropped, the reconcile's `fed-but-paused` class now covers
  the row). Leave the generic mentions at lines 172 and 186 (the field still exists).
- `knowledge-base/engineering/architecture/diagrams/model.c4` line 320 (Inngest queue description): replace
  "so it is fed but NOT armed: arming is a separately authorized step tracked on #9703" with "armed 2026-10-12
  (read-back `status=up`, feeder runs `verdict=beat`, #9703)". Then `bash scripts/regenerate-c4-model.sh` to
  refresh `model.likec4.json` (generated, do not hand-edit), and run `bash plugins/soleur/test/c4-count-parity.test.sh`
  and the two C4 vitest files. This changes prose only: no element, actor, system or relationship is added or
  removed.

### Phase 5 - verify, then ship

- Targeted suites only (CI is authoritative), see `## Acceptance Criteria`.
- Union grep on the final diff for merge side effects (the 2026-09-21 learning) and the closing-keyword grep.
- Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body: first line answers "does merging this
  alone mutate production?" (web image deploy and plugin patch release for the `plugins/soleur/lib` edit;
  a push-apply that must plan no changes; no Better Stack or Sentry write), then `Ref #9703`, `## Changelog`, and
  the closing line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Comment on #9703 recording that 3a landed with the three run ids; 3b stays the remaining tracked work (the issue
  stays open with its 8296 follow-through directive).

## Files to Edit

- `plugins/soleur/lib/heartbeat-manifest.ts`
- `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh`
- `apps/web-platform/infra/uptime-alerts.tf` (one comment sentence)
- `.github/workflows/scheduled-inngest-probe-heartbeat.yml` (one comment line)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (three spots)
- `knowledge-base/engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md` (one sentence)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (one clause) and the regenerated `knowledge-base/engineering/architecture/diagrams/model.likec4.json`

## Files to Create

None (planning artifacts only: this plan and `knowledge-base/project/specs/feat-one-shot-9703-stage-3a-drop-arming-pending/tasks.md`).

## Open Code-Review Overlap

None. Queried the 89 open `code-review` issues (`gh issue list --label code-review --state open --json
number,title,body --limit 200`, then `jq --arg path <file> 'select(.body | contains($path))'`) against every file in
`## Files to Edit`, including the full `knowledge-base/engineering/...` paths and `model.likec4.json`: zero matches.
Re-run on the final file list before the PR is marked ready.

## Guard Contract

### Guard 1 — `inngest-server-probe-heartbeat.test.sh` section (h): the `inngest_server_probe` manifest row carries no `arming_pending`

**Property.** The manifest row for `inngest_server_probe` exists exactly once and carries no `arming_pending` in code, so the nightly live reconcile cannot be told to ignore a paused-yet-fed state for this heartbeat.

**Assembly.** The property quantifies over every `MANIFEST` row named `inngest_server_probe` in `plugins/soleur/lib/heartbeat-manifest.ts` (the single chokepoint every consumer reads: `heartbeat-live-reconcile.ts:1025` reads `row.arming_pending` off the same array, and `reconcile-live-heartbeats.ts` passes `MANIFEST`), and over the row's CODE lines only (the dated record comment legitimately names the field, so comment lines are excluded by construction rather than by a token allow-list). The extractor is bounded from the row's `name:` line to the row's closing brace line (the one indented exactly two spaces) and is tied to a cardinality check (exactly one such `name:` line in the file) so a duplicate row cannot hide behind the first. The suite's own dispatch is protected by the existing `EXPECTED_PASSES=21` count plus the positive `feeder:` and `exempt_reason:` checks inside the assertion. The guard compares no stored hash or count to the thing it protects, so there is no Anchor to name: it asserts a source property, and weakening it requires editing the test and the manifest in one diff, which the review sees together.

**Mutation matrix.**

| # | Edit under test | Must drive the guard |
|---|---|---|
| M1 | re-add `arming_pending: { tracking_issue: 9703 },` to the row | RED (the assertion's `! has ... arming_pending` arm) |
| M2 | re-add it in a different spelling: `arming_pending:{tracking_issue:9703}` on one line, and separately split across three lines | RED both (the assertion matches the token, not one shape) |
| M3 | own dispatch: rename the row's `name:` so the extractor finds nothing | RED (cardinality and positive `feeder:` checks reject empty input; it must not report "0 checked" green) |
| M4 | add a SECOND `inngest_server_probe` row after the compliant first, carrying `arming_pending` | RED (cardinality check) |
| M5 | harness row: delete the flipped assertion block from the suite | RED (`EXPECTED_PASSES` conservation: 20 passes, expected 21) |
| M6 | must-PASS, not the canonical: add `arming_pending: { tracking_issue: 1 }` to a DIFFERENT row (for example `workspaces_luks`), and separately mention `arming_pending` only in a `//` comment inside this row | GREEN both (the guard must not reject everything; the comment form is explicitly permitted) |

Run each row on a scratch copy of the two files (not the working tree) and paste the observed RED/GREEN lines into
the PR body. The remediation-tree check: after Phase 2 the row's own dated comment contains the literal
`arming_pending: { tracking_issue: 9703 }` text; M6's second half proves the classifier does not match the
remediation's own text.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The failure surface is the operator's monitoring. A wrong edit could leave the nightly reconcile either flagging a healthy heartbeat (a spurious issue) or still suppressing a real re-pause (a silent dead-probe window for the plaintext-store tripwire).
- **If this leaks, the user's data is exposed via:** no exposure vector. The diff carries no secret, no heartbeat URL and no token; run ids and the numeric heartbeat id are not credentials.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** a docs, comment and one test-assertion change that adds no capability and is reversible by re-adding one field; the monitoring it re-arms protects an already-encrypted store, not a user-facing surface.

threshold: none, reason: the diff touches `apps/web-platform/infra/**` only in comments and one shell assertion; no schema, auth, API route, credential or provisioning path changes.

## Observability

```yaml
liveness_signal:
  what: "Better Stack heartbeat soleur-inngest-server-probe-prd (id 504655), beaten by scheduled-inngest-probe-heartbeat.yml only on a fresh host_role=dedicated probe row; Sentry cron monitor scheduled-inngest-probe-heartbeat"
  cadence: "15-minute watchdog slots; period 3600 + grace 1800 (pages 5400 s after the last beat)"
  alert_target: "Better Stack team email policy; nightly heartbeat-live-reconcile files an issue on fed-but-paused"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf (betteruptime_heartbeat.inngest_server_probe), .github/workflows/scheduled-inngest-probe-heartbeat.yml, plugins/soleur/lib/heartbeat-live-reconcile.ts"
error_reporting:
  destination: "Sentry cron monitor scheduled-inngest-probe-heartbeat (check-in error means withheld or failed); reconcile output SOLEUR_HEARTBEAT_RECONCILE_MISMATCH"
  fail_loud: "feeder prints one 'inngest-probe-feeder: verdict=<v> ...' line per run; the reconcile prints reason=fed-but-paused when the heartbeat is re-paused"
failure_modes:
  - mode: "heartbeat re-paused after arming"
    detection: "nightly live reconcile class fed-but-paused (re-armed by this PR); the feeder itself exits 0 with fresh_heartbeat_paused and would not alert"
    alert_route: "reconcile-filed issue and Sentry monitor scheduled-heartbeat-reconcile"
  - mode: "arming_pending re-added by mistake"
    detection: "inngest-server-probe-heartbeat.test.sh section (h) fails in CI"
    alert_route: "red PR check"
  - mode: "probe pipeline dark"
    detection: "feeder withholds the beat (producer_silent or no_rows); heartbeat pages after 5400 s"
    alert_route: "Better Stack heartbeat policy"
logs:
  where: "GitHub Actions run logs of Scheduled: Inngest Probe Heartbeat Feeder (gh run view <id> --log, no SSH)"
  retention: "GitHub Actions default 90 days; Better Stack incident history"
discoverability_test:
  command: bash scripts/inngest-probe-heartbeat-feeder.sh --selftest
  expected_output: selftest=ok
```

The selftest proves the feeder verdict logic offline (it measured 0.01 s here); the live armed state is a
credentialed Better Stack read (`BETTERSTACK_API_TOKEN_READONLY`, Doppler `prd_terraform`) shown in the runbook's
P3 read, which has no unauthenticated substitute and is therefore described, not declared as the executed probe.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an infrastructure record and wording change. Product/UX gate does not
fire (no UI-surface file in the Files lists). GDPR gate does not fire (no regulated-data surface, no new
processing). Encryption Posture gate does not fire: `uptime-alerts.tf` matches the `.tf` detection pattern but
the edit introduces no persistent store and no new connection. IaC routing gate does not fire: no new
infrastructure. ADR/C4 gate: no architectural decision is made or changed; the ADR-117 and `model.c4` edits are
status wording. C4 completeness check for that wording edit: the Inngest queue element and the `github`,
`betterstack`, `sentry` systems and their edges are already modeled; no external actor, system, data store or
access relationship is added or changes, so no `.c4` structural edit is in scope. The implementer re-reads
`model.c4`, `views.c4` and `spec.c4` before the edit and confirms the same, and `c4-count-parity` plus the two
C4 vitest files are the evidence.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/lib/heartbeat-manifest.ts`: `rg -n 'arming_pending' plugins/soleur/lib/heartbeat-manifest.ts` shows only the interface field and comments; the `inngest_server_probe` row has none in code; `paused: true` and the `feeder` block are unchanged.
- [ ] `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` prints `21 passed, 0 failed`; it was RED before Phase 2.
- [ ] Guard 1's matrix rows M1-M6 were each run on a scratch copy with the observed RED/GREEN recorded in the PR body (`plugins/soleur/lib/heartbeat-manifest.ts:<row>` is the mutation target; pointer for the assertion: `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` section (h)).
- [ ] `git diff origin/main --name-only` is a subset of `## Files to Edit` plus the files the pipeline itself writes (this plan, `knowledge-base/project/specs/feat-one-shot-9703-stage-3a-drop-arming-pending/tasks.md`, any `session-state.md` and `decision-challenges.md` under that spec directory, and a regenerated `knowledge-base/INDEX.md` if the pipeline emits one). No file under `scripts/followthroughs/`, `scripts/test-all.sh`, `scripts/*.tsv`, `scripts/test-affected-kb-consumers.baseline.txt`, `apps/web-platform/infra/sentry/`, `apps/web-platform/infra/betterstack-logs-alerts.tf`, `scripts/encryption-posture-ledger.json` or `knowledge-base/legal/` is touched.
- [ ] `git diff origin/main -- apps/web-platform/infra/uptime-alerts.tf` changes comment lines only (every `+`/`-` line starts with `#` after whitespace) and `terraform fmt -check apps/web-platform/infra/uptime-alerts.tf` exits 0.
- [ ] `git grep -n -E 'fed but NOT armed|FED but not ARMED|arming pending|ARMING PENDING|arming_pending' -- ':!knowledge-base/project' ':!knowledge-base/legal'` returns no line that still presents the probe heartbeat as unarmed. Allowed residue: the `arming_pending?` interface field and its doc, the reconcile logic and its tests, the `git_data` and `inngest_consumer` dated records, ADR-117 generic mentions (lines ~172, ~186), the `git-data.tf` and `git-data-luks-cutover-5274.md` text (a different heartbeat), and the dated record comments.
- [ ] The three run ids `38264380002`, `38265381453`, `38267189184` appear in the manifest comment and the runbook record, each with `verdict=beat`.
- [ ] Targeted suites green locally: `bash scripts/inngest-probe-heartbeat-feeder.test.sh`; `bash apps/web-platform/infra/luks-monitor.test.sh`; `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh`; `bash scripts/check-web-host-escrow-config.sh`; `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts plugins/soleur/test/heartbeat-live-reconcile.test.ts plugins/soleur/test/terraform-target-parity.test.ts` (path-targeted from the repo root; the root `bunfig.toml` preloads the git tripwire and ignores `apps/web-platform/**`); `./node_modules/.bin/vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts` from `apps/web-platform` (the workflow header edit is the only reason it is in scope); `bash plugins/soleur/test/c4-count-parity.test.sh`; the two C4 vitest files (`test/c4-code-syntax.test.ts`, `test/c4-render.test.ts`) from `apps/web-platform`. `TEST_GROUP=affected bash scripts/test-all.sh` is the broader option; CI is authoritative. Where a CI gate has its own invocation, run that invocation and not a path list: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, `python3 scripts/lint-guard-contract.py` (no arguments), and `actionlint .github/workflows/scheduled-inngest-probe-heartbeat.yml`.
- [ ] `model.likec4.json` was regenerated by `bash scripts/regenerate-c4-model.sh`, not hand-edited.
- [ ] markdownlint (`./node_modules/.bin/markdownlint` if present, else the lefthook invocation) passes on the two edited `.md` files, this plan and `tasks.md` (a literal tab inside a quoted command and a list directly after a heading are the recurring violations).
- [ ] Commit and PR text: `git log origin/main..HEAD --format=%B` and the PR body contain `Ref #9703` and no `Closes|Fixes|Resolves` keyword followed by #9703; the commit trailer is `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; the PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- [ ] PR body states, first line, what merging does to production (see Phase 5) and that this change makes no Better Stack, Sentry or Terraform write.

### Post-merge

- [ ] Read-only: confirm `apply-web-platform-infra.yml`'s push run for the merge commit planned no changes for the two probe resources, and that `web-platform-release` and the plugin release completed. Comment on #9703 with the three run ids and the merge SHA.
- [ ] Read-only, next day: the nightly `heartbeat-live-reconcile` run after this merge is clean (this is also the first half of the Stage 3b gate).

## Test Scenarios

1. Re-pause: the heartbeat is live-paused and the manifest row has no `arming_pending`: `reconcileHeartbeats` returns one `fed-but-paused` violation (already covered by `heartbeat-live-reconcile.test.ts`; the synthetic rows there do not name this heartbeat, so no test edit is needed).
2. Re-add `arming_pending` to the row: the suite goes RED at section (h).
3. Unchanged live state (`up`, unpaused): the reconcile reports nothing for this row.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries only placeholder text fails `deepen-plan`; this one is filled and the threshold is `none`.
- `heartbeat-manifest.ts` is in the runtime-plugin path: the merge deploys the web image (see Research Insights). That is expected for a record PR and the same as PR #10080, but the PR body must say it.
- Do not cite the three run ids as the evidence for the `inngest_consumer` sentence at runbook line ~1192; that row's evidence is the manifest's own 2026-09-15 observation.
- Do not edit `uptime-alerts.tf` beyond the one sentence: the 3b PR owns the rest, and a larger edit widens the push-apply review for no gain.
- The dated record in the manifest comment contains the literal field text; the new assertion strips comment lines first. If the comment is ever moved inside a code expression the assertion will (correctly) fail.
- The runbook arm block stays executable. A future operator re-arming after a rollback or a recreated heartbeat uses the same block (its state gate refuses a second arm of an unpaused heartbeat); do not delete it with the stale wording.
- Draft PR #10134 is the PR for this branch. Parked draft PR 10081 and the volume attachment are untouched.
