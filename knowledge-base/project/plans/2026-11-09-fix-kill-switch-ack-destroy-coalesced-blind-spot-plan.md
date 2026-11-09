---
title: "fix: feed coalesced push-commit messages to the kill-switch and [ack-destroy] gates"
type: fix
date: 2026-11-09
slug: fix-kill-switch-ack-destroy-coalesced-blind-spot
branch: feat-one-shot-12403-coalesced-blind-spot
issue: 12403
closes: 12403
lane: cross-domain
domain: engineering
priority: p2-medium
brand_survival_threshold: none
---

# fix: feed coalesced push-commit messages to the kill-switch and [ack-destroy] gates

## Enhancement Summary

**Deepened on:** 2026-11-09
**Sections enhanced:** Research Insights (byte-budget measurement, cut list), Files to Edit
(sweep enumerated), Acceptance Criteria (AC3 countable-probe fix, AC8 canonical lint
invocation), Test Scenarios (executed-span rows), Guard Contract (2 entries)
**Research approach:** inline (no subagent spawn in this context) — repo greps, precedent
diff read of commit `f6c7ce7ddd` (#12404), live `gh`/`git` premise checks, mechanical
deepen-plan halt-gate verification (4.6–4.13 all pass; `lint-guard-contract.py` green, 2
entries).

### Key Improvements

1. Byte budget measured and made a first-class constraint: 489,262/490,000 — 738 bytes of
   headroom (AC4), driving the "prose in runbook, not YAML" discipline and the
   byte-neutral POLICY_MSGS→ALL_MSGS rename.
2. Test-pin sweep enumerated: G11 literal (`"$POLICY_MSGS"`), `_ack_line` pin
   (`HEAD_MSG.*ack-destroy`), and the counter suite's exact-count floor (121) all named as
   same-commit updates — the three places the rename/feed would otherwise redden silently.
3. Executed-step proof prescribed for the kill-switch (T66d–g) rather than text pins only —
   the 2026-09-24 learning's "precedent is its whole job" applied to this mirror.
4. Two pending technical rulings persisted to `decision-challenges.md` (any-commit reach for
   each gate) — implementation is identical under either ruling.

### New Considerations Discovered

- `needs.preflight.outputs.skip` gates only the `apply` job — dispatch jobs never consulted
  it (pre-existing; unchanged).
- Sibling workflows `apply-github-infra.yml` / `apply-sentry-infra.yml` carry the same
  tip-only readers — descoped to a follow-up (decision-challenges scope row).
- `git grep -c` exits 1 with empty output on zero hits — AC3 uses `git grep -l | wc -l`
  instead.

## Overview

`github.event.head_commit.message` is only the push tip. PR #12404 (merged 2026-11-08,
commit `f6c7ce7ddd`) fixed that blind spot for `deploy_policy_gate` in
`.github/workflows/apply-web-platform-infra.yml` by feeding the gate the tip message plus
every `github.event.commits[*].message`. Two sibling readers of `head_commit.message` in the
same workflow still have the defect (#12403):

- the `[skip-web-platform-apply]` kill-switch in the `preflight.kill_switch` step (today
  reads `HEAD_MSG` only — fail-unsafe: a below-tip skip is silently ignored and the apply
  runs);
- the `[ack-destroy]` read in the `apply` job's "Terraform plan" step (fail-closed: a buried
  ack is silently ignored and the apply refuses, the operator unwedges).

This plan mirrors the proven #12404 shape onto both sites: export
`EVENT_MSGS_JSON: ${{ toJSON(github.event.commits.*.message) }}` where missing, join the
event-commit messages onto the tip into one combined variable, and point each anchored token
regex at the combined variable. It also documents the `event.commits` 20-entry cap residual
in the operator-facing runbook.

## Problem Statement / Motivation

A merge-queue coalesce (or any multi-commit push) can place the commit carrying a gate token
below the tip. Verified on the branch (which is current `origin/main`):

- Kill-switch (`apply-web-platform-infra.yml`, `preflight` job, step `id: kill_switch`,
  ~line 250): `env: HEAD_MSG: ${{ github.event.head_commit.message }}`, then
  `if [[ "$HEAD_MSG" =~ (^|$'\n')\[skip-web-platform-apply\]($|$'\n') ]]`. The `skip`
  output is consumed by exactly one site — the `apply` job's
  `if: needs.preflight.outputs.skip != 'true' && ...` (~line 283). A below-tip
  `[skip-web-platform-apply]` is silently ignored and the apply runs inside whatever window
  the token was meant to hold open. The workflow's own UNWEDGE texts prescribe this token
  during scoped host retirements, so this is the fail-unsafe direction.
- `[ack-destroy]` (~line 878): `ack_destroy=false; if [[ "$HEAD_MSG" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then ack_destroy=true; fi`. A buried ack silently misses and the
  apply refuses — fail-closed, lower urgency.
- The `EVENT_MSGS_JSON` feed already exists in this step's env (added by #12404 at
  `apply-web-platform-infra.yml:411`) and is consumed only by the `deploy_policy_gate` input
  build at ~lines 868-871.

Residual the fix does NOT close (documented, not engineered): `event.commits` is capped at
20 entries — a token older than the window in a giant coalesced push still misses
(fail-OPEN for the kill-switch, fail-closed for the ack).

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 12403`: **OPEN**, labels `priority/p2-medium`, `domain/engineering`,
  `type/security`, `meta/machinery`. Premise verified directly: both sites read `HEAD_MSG`
  only (workflow lines ~250/257 and ~878).
- Predecessor verified live: PR **#12404** (`fix(ci): feed deploy-policy ack gate all
  push-commit messages`) merged as commit `f6c7ce7ddd`; it added `EVENT_MSGS_JSON` at
  workflow line 411 and the `POLICY_MSGS` concat at lines 868-871, plus G10/G11 pins in
  `tests/scripts/test-deploy-access-token-forget.sh` and a doc note in
  `tests/scripts/lib/deploy-policy-gate.sh`.
- Epic **#10390** OPEN; **#10382** (operator-reserved) and **#12479** (deferred p3) both
  OPEN — untouched per the brief.
- Collision precheck: PR #12498 is this branch's own auto-created WIP draft (not a foreign
  duplicate); one foreign `test-all.sh` process in an unrelated worktree
  (`feat-one-shot-founder-acceptance-followups-12365`), no overlap.
- ADR corpus grep (`head_commit`, `event.commits`, `coalesc`, `ack-destroy`): no ADR
  prescribes or rejects the any-commit reach — the deploy-policy precedent is the only
  ruling on the mechanism.
- Collision/scope note: sibling workflows `apply-github-infra.yml` (HEAD_MSG at lines 88,
  290) and `apply-sentry-infra.yml` (lines 161, 802) carry the same tip-only readers. Out of
  scope per the issue text — see Non-Goals.

### Property List (Phase 0.6b)

- **P1** — A push payload carrying `[skip-web-platform-apply]` on its own line in ANY of the
  push's commit messages suppresses that push's `apply` job (any-commit reach, fail-safe).
- **P2** — A push payload carrying `[ack-destroy]` on its own line in ANY of the push's
  commit messages arms the destroy acknowledgement for that push's apply (any-commit reach,
  parity with `deploy_policy_gate`).
- **P3** — The `event.commits` 20-entry cap residual is documented where the operator reads
  the tokens (workflow comments + runbook).
- **P4** — Both anchored-line regexes stay byte-identical (parity suite
  `test-destroy-guard-regex-parity.sh` pins the `[ack-destroy]` literal across 7 sites).
- **P5** — The widened feed is pinned by tests mirroring the #12404 G10/G11 style, plus an
  executed step-span proof for the kill-switch.

### Cut List (Phase 0.6b)

- Shared `push_msgs` helper library (e.g. `tests/scripts/lib/push-msgs.sh`) — buys
  deduplication of a 4-line idiom across three sites; **cut**: the #12404 inline idiom is
  already the established, reviewed, pinned pattern; a lib extraction is churn without a
  need the sites don't already meet (the concat is 3 lines).
- Extending the executed-apply span past `destroy_count=` to execute the ack gate end-to-end
  — buys direct execution of the ack test line; **cut**: `_run_apply_halt_span`'s awk
  extraction deliberately stops at `destroy_count=`; the ack feed is shape-pinned (G11
  mirror) and the identical concat idiom is executed end-to-end at the kill-switch site.
  Recorded in Alternative Approaches.
- Widening `apply-github-infra.yml` / `apply-sentry-infra.yml` — same defect, but the issue
  scopes to `apply-web-platform-infra.yml`; **descoped** to a follow-up (decision row).

### Key file paths

- `.github/workflows/apply-web-platform-infra.yml` — kill_switch step ~lines 248-262;
  apply "Terraform plan" step ~lines 403-411 (env) and 865-880 (gate + ack test).
- `tests/scripts/test-deploy-access-token-forget.sh` — G10 (line ~128, var-agnostic call
  pin), G11 (line ~131, literal `"$POLICY_MSGS"` pin).
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — `_ack_line` pin at ~line
  2097 (`grep -n 'HEAD_MSG.*ack-destroy'`); `_job_block` extraction helper at ~line 905;
  executed-span machinery `_run_apply_halt_span` at ~line 1756; exact-count anti-vacuity
  floor `121` at the file tail.
- `tests/scripts/lib/deploy-policy-gate.sh` — header comment lines ~6-8 name `POLICY_MSGS`
  and already document the 20-entry cap.
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
  — kill-switch + destroy-ack paragraphs at ~lines 1033-1037.
- `plugins/soleur/test/workflow-file-size.test.ts` — `WORKFLOW_FILE_GATE_BYTES = 490_000`.

### Institutional learnings applied

- `2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md` — a precedent
  is its whole job, not the copied line: mirror #12404's env + concat + pinned-test shape
  wholesale, including the dispatch-shape guards (`${EVENT_MSGS_JSON:-null}`, `!= "null"`).
- `2026-11-05-a-branch-dispatch-of-the-workflow-you-edited-is-skip-masked...` — a
  `workflow_dispatch` of the edited workflow is skip-masked; verification is suite-level +
  post-merge push observation, not branch dispatch.
- `2026-10-02-early-exit-pipe-consumers-sigpipe-under-pipefail.md` — `>/dev/null` not
  `grep -q` on the 490 kB workflow producer in test predicates (existing convention in the
  forget suite).

### Byte budget (measured)

`wc -c .github/workflows/apply-web-platform-infra.yml` = **489,262** against the
**490,000**-byte gate (`plugins/soleur/test/workflow-file-size.test.ts`,
`WORKFLOW_FILE_GATE_BYTES = 490_000`) — **738 bytes of headroom**. The workflow's own header
directs new rationale prose to the runbook. Estimated delta: ~+74 (one env line) + ~190
(three concat lines in preflight) + comment trims/short clauses — target **≤ +400 bytes**.
The POLICY_MSGS→ALL_MSGS rename is byte-neutral. Hard rule for the implementation: keep new
comment prose in the workflow to a minimum; rationale lands in the runbook, not the YAML.

## Proposed Solution

Mirror the #12404 feed shape at both sites, using one combined variable named `ALL_MSGS`
(tip + every `event.commits[*].message`).

### Site A — `preflight.kill_switch` (~line 248)

```yaml
      - id: kill_switch
        env:
          HEAD_MSG: ${{ github.event.head_commit.message }}
          EVENT_MSGS_JSON: ${{ toJSON(github.event.commits.*.message) }}
        run: |
          set -euo pipefail
          ALL_MSGS="$HEAD_MSG"
          more_msgs="$(jq -r 'join("\n")' <<<"${EVENT_MSGS_JSON:-null}" 2>/dev/null || true)"
          [[ -n "$more_msgs" && "$more_msgs" != "null" ]] && ALL_MSGS="${ALL_MSGS}"$'\n'"${more_msgs}"
          if [[ "$ALL_MSGS" =~ (^|$'\n')\[skip-web-platform-apply\]($|$'\n') ]]; then
            echo "skip=true" >> "$GITHUB_OUTPUT"
            echo "Kill switch detected in commit message — skipping apply."
          else
            echo "skip=false" >> "$GITHUB_OUTPUT"
          fi
```

The existing anchor comment above `run:` stays (it already covers anchoring; append at most
one short clause naming the coalesced-merge reach — bytes are capped).

### Site B — `apply` job "Terraform plan" step (~lines 865-880)

Rename `POLICY_MSGS` → `ALL_MSGS` (it now feeds two gates; the rename is byte-neutral and
honest about reach — sweep list below) and point the ack test at the combined var:

```bash
          source "${GITHUB_WORKSPACE}/tests/scripts/lib/deploy-policy-gate.sh"
          # The ack can sit below the tip when the merge queue coalesces: the
          # squash that changed the policy is in event.commits, not head_commit.
          ALL_MSGS="$HEAD_MSG"
          more_msgs="$(jq -r 'join("\n")' <<<"${EVENT_MSGS_JSON:-null}" 2>/dev/null || true)"
          [[ -n "$more_msgs" && "$more_msgs" != "null" ]] && ALL_MSGS="${ALL_MSGS}"$'\n'"${more_msgs}"
          deploy_policy_gate "$counts" "$ALL_MSGS" || exit 1
          destroy_count=$((resource_deletes + nested_deletes + reboot_updates))
          # Anchor `[ack-destroy]` to its own line (start-of-string OR
          # preceded by newline; followed by newline OR end-of-string) so
          # the token cannot fire from a quoted block, code fence, or
          # `Co-Authored-By:` trailer carrying that literal substring.
          ack_destroy=false
          if [[ "$ALL_MSGS" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then
            ack_destroy=true
          fi
```

`POLICY_MSGS` full-file sweep: workflow lines ~868-871,
`tests/scripts/lib/deploy-policy-gate.sh` comment lines ~6-8,
`tests/scripts/test-deploy-access-token-forget.sh` G11 literal ~line 133.

### Semantics (ruled — see `specs/<branch>/decision-challenges.md`)

- **Kill-switch reach**: **any-commit** (Ruled by CTO agent, 2026-11-09) — the token is a
  veto with no un-skip counterpart; a suppressed apply is recoverable through the
  `manual-rerun` dispatch (verified at workflow :284 + runbook :1039), while an apply
  inside a retirement window is the harm the token exists to prevent.
- **Ack reach**: **any-commit** (Ruled by CTO agent, 2026-11-09) — parity with
  `deploy_policy_gate` (#12404); the push's commit set collectively constitutes the merged
  change the apply operates on, and a buried ack's same-`head_commit` re-run cannot unwedge.
- **Sibling workflows**: ruled **ship web-platform only** — file one follow-up issue
  covering the four sibling readers (`apply-github-infra.yml:88,290`,
  `apply-sentry-infra.yml:161,802`); the pipeline files it as a Class R act alongside this
  PR.

### Test plan

- `tests/scripts/test-deploy-access-token-forget.sh`: update G11's literal
  `"$POLICY_MSGS"` → `"$ALL_MSGS"` (G10's `\[A-Z_\]+` pattern is already var-agnostic).
- `tests/scripts/lib/deploy-policy-gate.sh`: update the header comment's `POLICY_MSGS`
  mentions to `ALL_MSGS`; extend the existing 20-cap sentence to name all three consumers.
- `tests/scripts/test-destroy-guard-counter-web-platform.sh`:
  - `_ack_line` pin (~line 2097): `HEAD_MSG.*ack-destroy` → `ALL_MSGS.*ack-destroy`.
  - New `T66` block (row labels indicative; re-derive the exact-count floor with a green
    run): `T66a` preflight job block carries `EVENT_MSGS_JSON` env;
    `T66b` the kill_switch run block tests `$ALL_MSGS` against the canonical skip regex
    (comment-stripped, anchored); `T66c` the apply step's ack test reads `$ALL_MSGS`
    (anchored on `ALL_MSGS.*ack-destroy`); `T66d` executed proof — extract the `preflight`
    job's `run:` body via `_job_block`, run it under `bash -e` with
    `HEAD_MSG="tip only"`, `EVENT_MSGS_JSON` carrying `[skip-web-platform-apply]` on its own
    line in the SECOND of two commit messages → `skip=true` in a stub `GITHUB_OUTPUT`;
    `T66e` executed control — same span, token mid-line (not line-anchored) → `skip=false`;
    `T66f` executed control — `EVENT_MSGS_JSON` unset/`null` (dispatch shape) → verdict
    identical to HEAD_MSG-only input; `T66g` executed — token in HEAD_MSG only → `skip=true`
    (baseline preserved).
  - Anti-vacuity floor at the file tail: re-derive `121` → `121+N` in the same commit (the
    floor is exact-count by design; a green run produces the number).
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
  (~lines 1033-1037): extend the kill-switch and destroy-ack paragraphs — any-commit reach +
  the `event.commits` 20-entry cap residual (fail-open for skip, fail-closed for ack), per
  the workflow header's "rationale prose lives in the runbook" rule.

## Technical Considerations

- **Dispatch shape**: on `workflow_dispatch` `head_commit`/`commits` are absent — the
  `${EVENT_MSGS_JSON:-null}` + `!= "null"` guard (verbatim from #12404) yields tip-only
  behavior, identical to today. `jq` is preinstalled on `ubuntu-24.04` runners; the
  `2>/dev/null || true` guard degrades to tip-only rather than failing the step.
- **`set -euo pipefail` safety**: `[[ cond ]] && cmd` under `set -e` is safe — the `[[ ]]`
  is a non-final `&&` member, exempt from `-e` (this is the #12404 shape verbatim).
- **Untrusted input**: `HEAD_MSG`/`EVENT_MSGS_JSON` stay env-routed (never interpolated into
  `run:`) per the file's existing convention.
- **`event.commits` duplicates the tip** in a push payload — harmless for an anchored token
  check; no dedup needed.
- **Timeout**: `preflight` is `timeout-minutes: 1`; one `jq` join is negligible.
- **Skip-output scope**: `needs.preflight.outputs.skip` gates only the `apply` job;
  dispatch jobs don't consult it (pre-existing, unchanged).
- **NFR**: no new attack surface — the input is still the push payload's commit messages;
  the anchored regex + env routing are unchanged.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — this changes CI gate
  inputs on the internal infra-apply pipeline. A defect in the fix itself resolves to either
  a skipped apply (loud, recoverable) or today's tip-only behavior (no worse than status
  quo).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user-data or
  credential surface is touched; the only exposure class is infra — a missed skip token
  running `terraform apply` inside a scoped-retirement window (a pre-existing residual this
  change narrows, not widens).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** CI-gate input plumbing on an internal apply
  workflow — no user-facing surface, data store, or credential boundary changes.
- `threshold: none, reason: the diff touches .github/workflows/apply-web-platform-infra.yml
  (a preflight-flagged sensitive path) but only widens gate-message input plumbing — no
  user-facing surface, no store, no credential handling`

## Observability

```yaml
liveness_signal:
  what: "per-push Actions run of apply-web-platform-infra.yml — kill_switch step emits 'Kill switch detected in commit message — skipping apply.' when armed; a skipped apply shows needs.preflight.outputs.skip == 'true' in the run log"
  cadence: "per push to main (and per workflow_dispatch)"
  alert_target: "operator via the Actions run conclusion/annotations"
  configured_in: ".github/workflows/apply-web-platform-infra.yml (preflight.kill_switch step, apply 'Terraform plan' step)"
error_reporting:
  destination: "GitHub Actions ::error:: annotations on the failing step"
  fail_loud: "run conclusion = failure plus the gate's ::error:: lines (e.g. the destroy_count HALT text)"
failure_modes:
  - mode: "skip/ack token buried below tip in a coalesced push (the defect this fixes)"
    detection: "T66 pin rows + G11 keep the feed from silently reverting to HEAD_MSG"
    alert_route: "red CI on the PR that reverts the feed"
  - mode: "push carrying >20 commits — a token older than the event.commits window still misses (fail-open for skip, fail-closed for ack)"
    detection: "documented residual in workflow comment + runbook §file-header contract; no automated probe exists"
    alert_route: "operator UNWEDGE path (re-merge carrying the token inside the window, or the supervised apply)"
  - mode: "EVENT_MSGS_JSON unreadable or absent (jq failure, dispatch shape, empty commits)"
    detection: "the != \"null\" / -n guard degrades to tip-only — identical to pre-fix behavior"
    alert_route: "no new route; same posture as today"
logs:
  where: "GitHub Actions run logs for the apply-web-platform-infra workflow"
  retention: "GitHub default retention (~90 days)"
discoverability_test:
  command: grep -cF 'toJSON(github.event.commits.*.message)' .github/workflows/apply-web-platform-infra.yml
  expected_output: "2"
```

## Guard Contract

### Guard 1 — coalesced-commit kill-switch feed

**Property.** A `push` payload carrying `[skip-web-platform-apply]` on its own line in ANY
of the push's commit messages (tip or below, within `event.commits`' 20-entry window) sets
`skip=true` and suppresses that push's `apply` job; a payload without the token applies.

**Assembly.** The `preflight.kill_switch` step in
`.github/workflows/apply-web-platform-infra.yml` — the single site that derives
`needs.preflight.outputs.skip`; the `apply` job's `if:` is the only consumer. The input
chokepoint is the step's `env:` block (`HEAD_MSG`, `EVENT_MSGS_JSON`) plus the concat in its
`run:` body.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `EVENT_MSGS_JSON` env line from the kill_switch step — the feed pin (T66a) reports the missing input | RED |
| 2 | Revert the regex test to `[[ "$HEAD_MSG" =~ ... ]]` while leaving the concat in place — feed built, never consulted (own-dispatch vacuity; T66b) | RED |
| 3 | `join("\n")` → `join("")` — the second commit's message fuses onto the first's last line, so a token anchored in the second message no longer matches (executed T66d) | RED |
| 4 | Harness: `EVENT_MSGS_JSON` fixture with the token in the SECOND of two messages against a tip-only read — a check that stops at the first member (executed T66d) | RED |
| 5 | Harness must-PASS: `EVENT_MSGS_JSON` unset/`null` (dispatch shape) → verdict identical to HEAD_MSG-only input (T66f) | PASS |
| 6 | Harness must-PASS: token mid-line (not line-anchored) in a buried message → `skip=false` (T66e) | PASS |

### Guard 2 — coalesced-commit ack-destroy feed

**Property.** A `push` payload carrying `[ack-destroy]` on its own line in ANY commit
message (within the 20-entry window) arms `ack_destroy` for that push's apply; tip-only
reads miss a buried ack and refuse the apply.

**Assembly.** The `apply` job's "Terraform plan" step — the single combined-message
variable (`ALL_MSGS`) built once and consumed by both `deploy_policy_gate` and the
`ack_destroy` regex test; the `EVENT_MSGS_JSON` env line already exists (#12404).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert the ack test to `[[ "$HEAD_MSG" =~ ... ]]` — the `_ack_line`/T66c pin sees a HEAD_MSG-keyed read | RED |
| 2 | Drop `more_msgs` from the `ALL_MSGS` concat (gate input silently narrows to tip-only; deploy-policy loses its own feed) | RED |
| 3 | Delete the `!= "null"` guard — a literal `null` line lands in the message window on every dispatch; the pin asserts the guard line's presence | RED |
| 4 | Harness: buried-ack shape pin (T66c) — a workflow whose ack regex reads any HEAD_MSG-only var | RED |
| 5 | Harness must-PASS: `EVENT_MSGS_JSON=null` (dispatch shape) → concat adds nothing, ack verdict identical to today (shape preserved by the T66f executed sibling) | PASS |

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — kill_switch env + run body; apply step
  POLICY_MSGS→ALL_MSGS rename + ack test var. Byte budget: must finish `wc -c` ≤ 490,000.
- `tests/scripts/test-deploy-access-token-forget.sh` — G11 literal pin
  (`"$POLICY_MSGS"` → `"$ALL_MSGS"`).
- `tests/scripts/lib/deploy-policy-gate.sh` — header comment `POLICY_MSGS` mentions +
  extend the 20-cap note to name all three consumers.
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — `_ack_line` pin; new T66
  block (feed pins + executed kill_switch span); exact-count floor re-derived with a green
  run.
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
  — kill-switch + ack paragraphs: any-commit reach + 20-entry cap residual.

## Files to Create

None — the new checks fold into the existing suites (a new `plugins/soleur/test/` suite
would need an `AFFECTED_*_PATHS` declaration and would degrade `--affected` to the full
battery; folding avoids that machinery).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open --limit 200` bodies contain no
reference to any planned file path (checked 2026-11-09).

## Alternative Approaches Considered

| Approach | Verdict |
|----------|---------|
| Mirror #12404 inline (`EVENT_MSGS_JSON` + `jq join` + combined var) | **Chosen** — precedent is reviewed, merged, pinned; smallest possible diff inside a 738-byte headroom |
| Extract a shared `tests/scripts/lib/push-msgs.sh` consumed by all three sites | Rejected — deduplicates a 3-line idiom at the cost of a third artifact class + its own pin machinery; the inline idiom is already the established pattern |
| Keep `POLICY_MSGS` name and reuse it for the ack test | Rejected — the var feeds two gates, not just deploy-policy; the misnomer is the kind of semantic lie this file's comments exist to prevent. Rename sweep is 3 files, all already in the edit list |
| Tip-only widening for the ack gate (keep blind spot, just document it) | Rejected — leaves the fail-closed wedge in place for no benefit; any-commit is the #12404 semantic |
| Extend `_run_apply_halt_span` past `destroy_count=` to execute the ack gate end-to-end | Rejected — the awk span deliberately ends at `destroy_count=`; extending it couples this change to span-extraction surgery. The identical concat idiom is executed end-to-end at the kill-switch site; the ack feed carries G11-mirror shape pins |
| `gh api` fetch of the push's full commit list (defeats the 20-cap) | Rejected — adds a network call + credential to a 1-minute preflight for a residual that needs a >20-commit coalesced push; documented instead |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Mirror the deploy_policy_gate fix (which reads the tip message + every event.commits[*].message ... into the two sibling readers of github.event.head_commit.message in .github/workflows/apply-web-platform-infra.yml" | Site A + Site B workflow edits; ALL_MSGS concat | mapped |
| 2 | "(a) the [skip-web-platform-apply] kill-switch in the preflight job (~line 250) — the fail-unsafe direction" | Site A diff sketch; FR/AC 1; T66 executed span | mapped |
| 3 | "(b) [ack-destroy] (~line 872) — same defect, fail-closed (refuse → operator unwedges), lower urgency" | Site B diff sketch; FR/AC 2; T66c pin | mapped |
| 4 | "Widening needs a semantic sign-off: whether any one commit's skip suppressing the whole push's apply is the desired reach vs tip-only" | decision-challenges.md technical ruling row | mapped |
| 5 | "Also document the event.commits 20-entry cap residual" | runbook edit + lib comment + workflow comment + AC | mapped |
| 6 | "Do NOT touch #10382 (operator-reserved) or #12479 (deferred p3)" | Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Workflow edits at both sites | "Mirror the deploy_policy_gate fix ... into the two sibling readers" | asked |
| Test pins + executed span (T66 block, G11/_ack_line updates) | — | inferred — justification: the deploy_policy_gate precedent shipped with pins (G10/G11); an unpinned feed silently reverts to HEAD_MSG with a green suite, which is the #6612 test-pinning defect class |
| POLICY_MSGS→ALL_MSGS rename sweep (lib comment, G11) | — | inferred — justification: the var feeds two gates after the change; honest naming is a comment-hygiene requirement in this file |
| Runbook + lib comment documentation | "Also document the event.commits 20-entry cap residual" | asked |
| decision-challenges.md ruling rows | "Widening needs a semantic sign-off" | asked |

### Split Assessment

- Subsystems touched: 3 — `.github`, `tests`, `knowledge-base`
- Planned files: 5 | Estimated changed lines: ~120 (workflow ~10 net, tests ~80, runbook ~15, lib ~5)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] **AC1** — The `preflight.kill_switch` step's env carries
      `EVENT_MSGS_JSON: ${{ toJSON(github.event.commits.*.message) }}` and its token test
      reads the combined var:
      `awk` on the `preflight:` job block shows `EVENT_MSGS_JSON` in env and
      `[[ "$ALL_MSGS" =~ (^|$'\n')\[skip-web-platform-apply\]($|$'\n') ]]` in the run body.
- [ ] **AC2** — The apply step's ack test reads the combined var:
      `grep -n 'ALL_MSGS.*ack-destroy' .github/workflows/apply-web-platform-infra.yml`
      returns 1 hit; `grep -n 'HEAD_MSG.*ack-destroy' ...` returns 0 hits.
- [ ] **AC3** — `deploy_policy_gate "$counts" "$ALL_MSGS" || exit 1` — G10/G11 green;
      no `POLICY_MSGS` remains:
      `git grep -l 'POLICY_MSGS' -- .github tests scripts | wc -l` == 0 (`git grep -c`
      exits 1 and prints nothing on zero hits; `wc -l` on the `-l` form is the countable
      probe). Scope note: `knowledge-base/` is excluded — the plan/tasks files
      legitimately name the old var.
- [ ] **AC4** — Byte gate: `wc -c .github/workflows/apply-web-platform-infra.yml` ≤ 490000.
- [ ] **AC5** — Both anchored regexes byte-identical to canonical:
      `bash tests/scripts/test-destroy-guard-regex-parity.sh` green, and the skip regex is
      unchanged (`(^|$'\n')\[skip-web-platform-apply\]($|$'\n')`).
- [ ] **AC6** — Executed proof (T66d-g): a stub-`GITHUB_OUTPUT` run of the extracted
      preflight run-block reports `skip=true` for a buried line-anchored token, `skip=false`
      for a mid-line token, `skip=false` with `EVENT_MSGS_JSON` absent (dispatch shape), and
      `skip=true` for a tip-only token.
- [ ] **AC7** — Suites green: `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`
      (incl. re-derived exact-count floor), `bash tests/scripts/test-deploy-access-token-forget.sh`,
      `bash tests/scripts/test-destroy-guard-regex-parity.sh`,
      `bun test plugins/soleur/test/workflow-file-size.test.ts`.
- [ ] **AC8** — Workflow syntax: `bash scripts/lint-workflows.sh` (the repo's canonical
      actionlint invocation) clean on the edited file; each touched `run:` block extracted
      and `bash -n`-clean.
- [ ] **AC9** — `git grep -cF 'toJSON(github.event.commits.*.message)'
      .github/workflows/apply-web-platform-infra.yml` == 2 (kill_switch + apply plan step).
- [ ] **AC10** — Runbook documents the any-commit reach for both tokens AND the
      `event.commits` ≤20-entry residual (fail-open for skip, fail-closed for ack):
      `grep -n 'event.commits' knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
      returns ≥1 hit in the kill-switch/ack paragraphs region.
- [ ] **AC11** — Diff scope: `git diff --name-only origin/main...HEAD` ⊆
      {`.github/workflows/apply-web-platform-infra.yml`,
      `tests/scripts/test-deploy-access-token-forget.sh`,
      `tests/scripts/test-destroy-guard-counter-web-platform.sh`,
      `tests/scripts/lib/deploy-policy-gate.sh`,
      `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`,
      `knowledge-base/project/plans/2026-11-09-fix-kill-switch-ack-destroy-coalesced-blind-spot-plan.md`,
      `knowledge-base/project/specs/feat-one-shot-12403-coalesced-blind-spot/tasks.md`,
      `knowledge-base/project/specs/feat-one-shot-12403-coalesced-blind-spot/decision-challenges.md`,
      `knowledge-base/project/specs/feat-one-shot-12403-coalesced-blind-spot/session-state.md`,
      `knowledge-base/INDEX.md`} (pipeline artifacts enumerated per the diff-scope sharp edge).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change on an internal CI
gate. Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed); the domain
sweep still finds no non-engineering surface (no UI, no docs-site content, no marketing or
legal artifact).

## Test Scenarios

- **T66a-c (unit, workflow-shape pins)**: Given the edited workflow file, when the
  preflight and apply job blocks are comment-stripped and grepped, then the feed env +
  combined-var reads are present at both sites.
- **T66d (unit, executed)**: Given HEAD_MSG="chore: tip" and
  EVENT_MSGS_JSON=`["feat: infra\n\n[skip-web-platform-apply]"]`, when the extracted
  preflight run-block executes under `bash -e` with a stub `GITHUB_OUTPUT`, then it writes
  `skip=true`.
- **T66e (unit, executed)**: Given the same fixture but the token mid-line
  (`"feat: see [skip-web-platform-apply] note"`), then `skip=false` — anchoring preserved
  through the concat.
- **T66f (unit, executed)**: Given `EVENT_MSGS_JSON` unset/`null` (dispatch shape), then the
  verdict equals the HEAD_MSG-only verdict — no regression on dispatch/manual-rerun runs.
- **T66g (unit, executed)**: Given the token only in HEAD_MSG (baseline), then `skip=true` —
  tip-only reach preserved.
- **Integration**: `test-destroy-guard-counter-web-platform.sh` full suite incl. the
  re-derived floor; `test-deploy-access-token-forget.sh` G1–G11; regex-parity suite;
  `workflow-file-size.test.ts`.

## Implementation Phases

### Phase 1 — Workflow + lib comment

- Edit `apply-web-platform-infra.yml` Site A (env + concat + `ALL_MSGS` test).
- Edit Site B (POLICY_MSGS→ALL_MSGS rename; ack test reads `ALL_MSGS`).
- Update `tests/scripts/lib/deploy-policy-gate.sh` comment.
- Verify byte count ≤ 490,000; `actionlint` + `bash -n` the touched `run:` blocks.

### Phase 2 — Test pins + executed span

- G11 literal update in `test-deploy-access-token-forget.sh`.
- `_ack_line` pin update + new T66 block in
  `test-destroy-guard-counter-web-platform.sh`; re-derive the exact-count floor with a green
  run.

### Phase 3 — Docs

- Runbook: any-commit reach + 20-cap residual for both tokens.
- Commit plan/tasks/decision-changes artifacts.

## Dependencies & Risks

- **Byte budget**: 738 bytes of headroom — the dominant risk. Mitigation: minimal comment
  additions in the YAML; prose goes to the runbook; the rename is byte-neutral. If the
  budget cannot be met, the remedy is trimming comment prose (never the `!= "null"` guard).
- **Semantic ruling**: the any-commit reach is `pending - assumed:` pending a CTO ruling;
  the implementation is identical either way (the concat ships regardless — reach is a
  property of which var each regex tests, and the assumed answer is both regexes read
  `ALL_MSGS`).
- **`_run_apply_halt_span` compatibility**: the executed span ends before `destroy_count=`
  and runs with `EVENT_MSGS_JSON` unset — the guarded concat already tolerates that
  (`:-null` + `!= "null"`), so the harness needs no env change.
- **jq on ubuntu-24.04 runner**: preinstalled on GitHub-hosted images; `|| true` guards a
  hypothetical absence (degrades to today's tip-only, never worse).
- **Floor collision risk**: the counter suite's exact-count floor is shared state; if a
  sibling PR lands rows first, re-derive on the merged tree (per the suite's own comment).

## Non-Goals

- `apply-github-infra.yml` and `apply-sentry-infra.yml` — same tip-only readers
  (`[skip-github-apply]`/`[skip-sentry-apply]` + their `[ack-destroy]` sites); the issue
  scopes to `apply-web-platform-infra.yml`. Follow-up candidate — see
  decision-challenges.md scope row.
- The `event.commits` 20-entry cap itself — documented as a residual, not engineered around
  (API fetch rejected in Alternatives).
- Issues #10382 (operator-reserved) and #12479 (deferred p3) — explicitly out of scope per
  the brief.
- The dispatch-job `if:` guards — `needs.preflight.outputs.skip` continues to gate only the
  `apply` job.

## References & Research

- Issue: #12403 (parent epic #10390)
- Precedent: PR #12404 / commit `f6c7ce7ddd` —
  `.github/workflows/apply-web-platform-infra.yml:411,868-871`;
  `tests/scripts/lib/deploy-policy-gate.sh:6-8`;
  `tests/scripts/test-deploy-access-token-forget.sh` G10/G11
- Triggering incident: PR #12330's `[ack-deploy-policy]` buried one squash below the tip in
  a coalesced push
- Byte gate: `plugins/soleur/test/workflow-file-size.test.ts` (`WORKFLOW_FILE_GATE_BYTES =
  490_000`; GitHub hard refusal bracket measured at ~512,000)
- Runbook: `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
  §file-header, §ack-destroy-steer
- Learning: `knowledge-base/project/learnings/2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md`
