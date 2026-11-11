---
title: "ci: bump-inngest-bootstrap-pin.sh suppresses enqueuePullRequest rejection reason (2>/dev/null)"
type: fix
date: 2026-11-11
slug: fix-unsuppress-enqueue-rejection
branch: feat-one-shot-12579-enqueue-rejection
issue: 12579
closes: 12579
lane: cross-domain
priority: p3-low
domain: engineering
brand_survival_threshold: none
---

# ci: bump-inngest-bootstrap-pin.sh suppresses enqueuePullRequest rejection reason (2>/dev/null)

Spec lacks valid `lane:` (no spec.md exists for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-11 (inline deepen pass — no agent-spawn tool in this planning subagent; gates run mechanically, research/learnings read inline)
**Sections enhanced:** Proposed Solution (script change + comment docs), Test fixture, ADR addendum anchor, Acceptance Criteria (AC2), Guard Contract (mutation row 3), Implementation Phases, References
**Gates evaluated:** 4.4 precedent-diff (FIRED — see below); 4.45 verify-the-negative (jq-fallback claim confirmed at script :652); 4.5 network-outage (incidental `timeout` matches — the coreutils wrapper in quoted code, not a connectivity symptom; no L3/L7 surface); 4.55 downtime (no infra/DB/deploy class); 4.6 user-brand (PASS); 4.7 observability (PASS — 5 fields, `grep` probe, literal `expected_output`); 4.8 PAT (no hits); 4.9 UI (none); 4.10 encryption (no store/connection); 4.11 guard-contract lint (PASS, 1 entry, 4 mutation rows); 4.12 scope-check (PASS — 1 section, all rows mapped/justified); 4.13 task-design (no new autonomous task).

### Key improvements

1. **Sanitization swapped to the repo-canonical pipeline** — precedent-diff found `tr '\n' ' '` at `bump-inngest-bootstrap-pin.sh:294`/`:377` and the stronger `tr -d '[:cntrl:]'` at `vinngest-digest-freshness.sh:149`/`:279`. The drafted `${enq_out//[$'\n\r']/ }` + `${enq_reason:0:300}` left `\t` and `\x1b` live in the annotation (empirically verified); the prescribed line is now `enq_reason=$(tr '\n' ' ' <<<"$enq_out" | tr -d '[:cntrl:]' | cut -c1-300)`. Bound stays 300 per the issue's ask (precedent bound is 200 — deliberate divergence, recorded).
2. **Precondition wording sharpened to the required-check SET** — learning `2026-11-10-merge-queue-admission-is-not-pr-head-green` (PR #12520 queued at position 2 with three FAILURE conclusions on non-required `deploy-script-tests*` contexts) proves admission gates on required contexts only. The comment/ADR text now says failing advisory contexts do NOT block enqueue; only pending/failed REQUIRED contexts refuse.
3. **ADR-270 anchor corrected** — the `#12508` addendum heading is at line 1180 (next `### Addendum` at 1218); the plan previously cited ~1216 ambiguously. Insertion point pinned: before the line-1218 heading.

### New considerations discovered

- Guard-1 reason assertion keyed to wiring, not spelling: `gh-stub: enqueuePullRequest rejected` exists only in stub stderr, so a green row proves stderr→`enq_out`→annotation plumbing (learning `2026-10-04-…pinned-spelling-not-wiring…`).
- `cut -c` counts bytes not characters — noted as immaterial (GitHub GraphQL errors are ASCII; the bound is an anti-flood ceiling).
- All cited PR/issue numbers re-verified live during deepen (#12579 OPEN, #12510 MERGED — `git log` commit `d8ae9b54fe` confirms "explicit enqueue", #12489 MERGED, #12562 CLOSED, #12652 OPEN); all line citations re-verified against the working tree (`2>/dev/null` at :651, `MIN_ASSERTIONS=712` at :84, stub at :355, fixture at :1010–1023, ADR anchor at :1180/:1218).

## Overview

Post-merge verification of #12510 on fabricated mint `vinngest-v1.1.72` (PR #12562) showed the new explicit `enqueuePullRequest` arm in `.github/scripts/bump-inngest-bootstrap-pin.sh` firing ~5s after PR open and being actively refused by GitHub. The GraphQL error output is piped to `/dev/null` at `bump-inngest-bootstrap-pin.sh:651`, so the run log carries only the generic `::warning::enqueuePullRequest ... was rejected` and the refusal reason is unobservable.

This plan makes two bounded changes:

1. **Unsuppress the rejection** — capture the mutation's stderr into the existing `enq_out` variable, flatten and bound it (~300 chars, CR/LF stripped), and echo it in the `::warning::` line so every future refusal is self-describing.
2. **Document the confirmed enqueue precondition** in the script's existing comment block: GitHub refuses `enqueuePullRequest` while the PR's branch-protection requirements are unmet (a pending required check refuses as `Pull request Required status check "<name>" is expected.`), so a refusal on a freshly opened PR is expected noise, not a defect — the arm exists for the case where protection is already met at arm time but armed auto-merge does not self-enqueue (the #12489 counter-instance).

The issue's second offered mechanism — moving the enqueue to a retry-on-check-complete step — is deferred with tracking issue #12652 (see Non-Goals / Alternative Approaches).

## Problem Statement / Motivation

- Every future `enqueuePullRequest` refusal is undebuggable: the warning names the event, never the cause. A suppression of an external API's error channel is exactly the class where the message would have answered the question the operator then had to raise as issue #12579.
- The ADR-270 addendum (2026-11-09, #12508) records the decision to enqueue authored bot PRs explicitly but does not record the precondition under which that enqueue can succeed. GitHub's documented refusal ("required status check expected") means the arm's 5-seconds-after-open placement will ~always be refused on a fresh PR — a reader of the script today cannot distinguish expected refusals from real failures.

## Proposed Solution

### Script change (`bump-inngest-bootstrap-pin.sh`, ~lines 650–656)

Replace `2>/dev/null` with `2>&1` on the `enq_out=$(timeout 60 gh api graphql …)` capture, so the rejection body/stderr lands in the same variable. In the `else` arm, sanitize with the script's own canonical pipeline (annotation-injection guard — `::warning::` is line-oriented; this is the `iss_safe`/`ref_safe` sanitization class from PR #3007's review) and embed in the warning:

```bash
elif enq_out=$(timeout 60 gh api graphql -F pr="$pr_node" \
    -f query='mutation($pr:ID!){enqueuePullRequest(input:{pullRequestId:$pr}){mergeQueueEntry{position state}}}' 2>&1); then
  echo "enqueued ${PR_URL} on the merge queue (position $(jq -r '.data.enqueuePullRequest.mergeQueueEntry.position // "?"' <<<"$enq_out" 2>/dev/null || echo '?'))"
else
  enq_reason=$(tr '\n' ' ' <<<"$enq_out" | tr -d '[:cntrl:]' | cut -c1-300)
  echo "::warning::enqueuePullRequest for ${PR_URL} was rejected — ${enq_reason:-no stderr captured (timeout or empty response)} — armed auto-merge remains; the PR joins the queue itself only once its head is up to date with main"
fi
```

Notes on shape:

- `2>&1` (merge into `enq_out`) is safe on the success path because `gh api graphql` writes only the response body to stdout on success; stderr is where its error text lives. The `jq` position-parse already tolerates garbage (`|| echo '?'`), so even an unexpected stderr line on success cannot break the arm.
- **Sanitization follows the script's own precedent, not a novel shape:** `bump-inngest-bootstrap-pin.sh:294` and `:377` already flatten embedded error text with `tr '\n' ' '`, and `vinngest-digest-freshness.sh:149`/`:279` add `tr -d '[:cntrl:]'` — which also strips ESC/BEL/TAB, a strictly stronger annotation-injection guard than a `\n\r`-only parameter expansion (empirically verified: `${x//[$'\n\r']/ }` leaves `\t` and `\x1b` live). Deepen-pass precedent-diff (§4.4) swapped the initially drafted `${var//[$'\n\r']/ }` + `${var:0:300}` for this pipeline.
- The bound stays 300 chars (issue's suggested value), a deliberate divergence from the 200-char precedent bound in the cited call sites. `cut -c` counts bytes, not characters — immaterial here: GitHub GraphQL error strings are ASCII, and the bound is an anti-flood ceiling, not a semantic edge.
- A `timeout 60` kill leaves `enq_out` empty; the `${enq_reason:-…}` fallback names that case explicitly rather than printing a bare dash.
- The bound (300 chars, issue's suggested value) keeps a pathological error body from flooding the log while preserving the leading refusal sentence, which is where GitHub names the unmet requirement.

### Comment documentation (same block, lines ~634–645)

Extend the existing `#12508 / ADR-270 addendum 2026-11-09` comment with the confirmed precondition — measured against GitHub's docs and the #12562 observation:

- `enqueuePullRequest` is refused while the PR's branch-protection requirements are unmet; the documented refusal for a pending required check is `Pull request Required status check "<name>" is expected.`
- Precision (deepen-pass learning `2026-11-10-merge-queue-admission-is-not-pr-head-green`): admission is gated on the REQUIRED-check SET, not on the head rollup being green — PR #12520 sat in the queue at position 2 with three FAILURE conclusions (`deploy-script-tests*`) because those contexts are not required. Failing non-required (advisory) contexts do not block enqueue; a pending or failed REQUIRED context does.
- On a PR armed ~5s after open, required checks are ~always still pending — a refusal there is expected, warn-and-continue is correct, and the unsuppressed message is what distinguishes it from a real failure class.
- The arm's value is the case where protection IS met at arm time but armed auto-merge does not self-enqueue — the #12489 counter-instance (armed 13:30Z with every required check SUCCESS, never queued after 5h20m).
- Re-evaluate if a refusal is ever observed while required checks are green (see tracking issue #12652 for the retry-on-check-complete alternative).

### Test fixture (`test-bump-inngest-bootstrap-pin.sh`)

The `enqueuefail` fixture (lines ~1010–1023) already stubs the rejection (`MOCK_GH_ENQUEUE_FAIL=1` → stub writes `gh-stub: enqueuePullRequest rejected` to stderr and exits 1) and `run_bump` captures combined output into `$LAST_OUT`. Add:

- `assert_out_has 'g1.enqueuefail:reason' 'gh-stub: enqueuePullRequest rejected'` — the stub's stderr must now appear in the run output (it is discarded under `2>/dev/null`, echoed under `2>&1`). The asserted string `gh-stub: enqueuePullRequest rejected` exists ONLY in the stub's stderr — the warning literal reads `enqueuePullRequest for <url> was rejected`, which contains neither the `gh-stub:` prefix nor the bare tail — so a green row proves the wire (stderr → `enq_out` → annotation), not the spelling of the fixture (learnings `2026-10-04-my-new-dispatcher-tests-pinned-spelling-not-wiring…`: key assertions on input the mock injects).
- One bound-assertion: make the stub's rejection text multi-line or >300 chars (e.g. extend the stub message or add a `MOCK_GH_ENQUEUE_FAIL=2` variant emitting a two-line message) and assert the warning stays single-line — assert the warning line still begins `::warning::` and that the stub's second line does NOT appear verbatim (CR/LF flatten proof).
- Bump `MIN_ASSERTIONS` (line 84, currently 712) by the exact count of rows added, per the anti-vacuity comment convention ("raise when adding rows, never lower it silently") — record the new count in the comment's running history.

### ADR-270 addendum entry

Append a short dated addendum to `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` (the `### Addendum 2026-11-09 (#12508)` section opens at line 1180 and runs to ~1217; insert the new `### Addendum` block before the `### Addendum 2026-11-09: max_entries_to_build` heading at line 1218) recording: the observed refusal on #12562 (armed `autoMergeRequest.enabledAt`, head 0 commits behind, BLOCKED on pending `quality-guards`), the documented protection-met precondition, that the rejection reason is now echoed in the run warning, and that the explicit arm's expected-success surface is already-green heads — with the retry-on-check-complete alternative deferred to tracking issue #12652.

## Technical Considerations

- **Blast radius:** one `elif` arm + its comment + one fixture block + one ADR paragraph. The arm already warn-and-continues; no exit-code or control-flow change.
- **Security:** the echoed text is a GitHub API error string — repo-trust-adjacent but treated as untrusted for annotation purposes; CR/LF flattening prevents `::warning::`/`::error::` spoofing or multi-line smuggling (the PR #3007 annotation-injection class).
- **No new runtime surface:** no new workflow, trigger, credential, or Inngest function; the change alters one log line's content inside the existing `bump-cloud-init-pin` job.
- **NFR impacts:** none — observability posture only.

## Research Insights

- **Premise validation:** #12579 OPEN (target issue, unblocked); #12510 MERGED (the residual batch that added the explicit enqueue); #12489 MERGED (the counter-instance motivating it); #12562 CLOSED (the fabricated-mint PR where the refusal was observed). Script verified: `2>/dev/null` present at `bump-inngest-bootstrap-pin.sh:651`; `enq_out` capture at :650. Collision pre-check: PR #12648 is THIS branch's own WIP draft (not a foreign collision); one foreign `test-all.sh` process in a sibling worktree is unrelated.
- **Semantics question (finding 2) — resolved by docs + repo evidence:** GitHub's merge-queue docs state a PR joins the queue "once it has passed all required branch protection checks"; a documented `enqueuePullRequest` refusal for unmet protection is `Pull request Required status check "<name>" is expected.` — #12562's refusal is consistent with `quality-guards` still pending 5s after open. This also bounds the arm's expected-success surface: it can only succeed when protection is already met at call time (already-green heads), which is the #12489 gap it was built for.
- **Existing repo precedent:** `scripts/merge-queue-jump.sh:133` captures the same mutation's output with `2>/dev/null` but fails hard with a named cause list in `die` — the runbook documents known refusal causes (permission, stale head, queue state). The bump script's warn-and-continue posture is deliberate; only the suppressed message is the defect.
- **Mechanism minimality (Phase 0.6b):** Property list — (P1) refusal reason visible in run log; (P2) script comment accurately states when the enqueue can succeed; (P3) a green-at-arm-time head still joins the queue when auto-merge does not self-enqueue. Proposed mechanisms: M1 unsuppress → P1 (no existing mechanism — the `2>/dev/null` IS the defect); M2 comment → P2 (none). M3 retry-on-check-complete → P3 is already carried by armed auto-merge when protection is met (ADR-270's 2026-10-07 measurement); M3's only incremental coverage is "armed + green + still not queued", a class with zero observed instances since the explicit arm shipped — **Cut List: M3 deferred** to tracking issue #12652 with re-evaluation criteria.
- **Institutional learnings applied:** annotation-CR/LF-strip before `::warning::` (PR #3007 session error 6 — log-injection via decoded values); anti-vacuity `MIN_ASSERTIONS` floor convention in the fixture suite (line 84 comment); `assert_out_has`/`run_bump` combined-output capture makes the stderr assertion free.
- **Open code-review overlap:** queried `gh issue list --label code-review --state open` (200 issues) for `bump-inngest-bootstrap-pin.sh`, `test-bump-inngest-bootstrap-pin.sh`, `ADR-270` — **None**.
- **Community discovery:** skipped — bash/GitHub-Actions surface fully covered by repo machinery; no uncovered stacks.
- **Functional overlap:** the only mechanism overlapping "PR joins merge queue eventually" is armed auto-merge itself — accounted for in the Cut List.

## User-Brand Impact

- **If this lands broken, the user experiences:** an internal CI run log — a founder-visible artifact only in the sense that repo automation noise is visible; the worst case is a noisier or misleading `::warning::` line on a bot-authored pin-bump PR.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the echoed text is a GitHub GraphQL error string bounded to 300 chars; it names check contexts and PR URLs already in the run log.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** this is a warning-line content change in a CI script with no customer-facing surface, no data path, and no new credential or trigger — a single-user incident requires a reachable user surface, which a bot-PR log line is not.

## Observability

The change IS an observability fix; the block below records the resulting signal per the 5-field schema.

```yaml
liveness_signal:
  what:            the ::warning::enqueuePullRequest ... was rejected — <reason> line in the bump-cloud-init-pin job log; a healthy-arm run instead prints "enqueued <url> on the merge queue (position N)"
  cadence:         per publish of a semver-max vinngest tag (event-driven, typically days apart)
  alert_target:    GitHub Actions run log + ::warning:: annotation on the run summary (no pager — warn-and-continue by design)
  configured_in:   .github/scripts/bump-inngest-bootstrap-pin.sh (enqueue arm, ~line 650)

error_reporting:
  destination:     GitHub Actions run log (::warning:: annotation)
  fail_loud:       ::warning::enqueuePullRequest for <url> was rejected — <reason> — the reason text now names the unmet requirement GitHub cited

failure_modes:
  - mode:          enqueuePullRequest refused while protection unmet (expected on fresh PRs)
    detection:     ::warning:: line names the pending required check in <reason>
    alert_route:   none (expected noise; armed auto-merge is the designed path once checks green)
  - mode:          enqueuePullRequest refused for another cause (permission, schema drift, queue state)
    detection:     ::warning:: line's <reason> does NOT read "Required status check"
    alert_route:   operator reads the run warning — this is the signal this PR restores
  - mode:          timeout 60 kill produces empty enq_out
    detection:     ::warning:: prints "no stderr captured (timeout or empty response)"
    alert_route:   operator reads the run warning

logs:
  where:           GitHub Actions run log for build-inngest-bootstrap-image.yml / bump-cloud-init-pin
  retention:       GitHub's default run-log retention (~90 days)

discoverability_test:
  command:         grep -n enq_reason .github/scripts/bump-inngest-bootstrap-pin.sh
  expected_output: enq_reason
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "capture the rejection into a variable and echo it in the `::warning::` line (bounded, e.g. first 300 chars). Cost: ~3 lines." | FR-1 / Files-to-Edit `.github/scripts/bump-inngest-bootstrap-pin.sh` (2>&1 + enq_reason echo) | mapped |
| 2 | "confirming GitHub's actual enqueue precondition (rejection message will say) and documenting it in the script comment" | FR-2 / comment block edit + ADR-270 addendum entry | mapped |
| 3 | "or moving the enqueue to a retry-on-check-complete step" | — | descoped — justification: P3 already carried by armed auto-merge when protection is met (ADR-270 2026-10-07 measurement); a retry surface only adds coverage for "armed + green + still not queued", a class with zero observed instances; deferred to tracking issue #12652 with re-evaluation criteria |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/scripts/bump-inngest-bootstrap-pin.sh` — `2>&1` capture + bounded `enq_reason` in `::warning::` | "capture the rejection into a variable and echo it in the `::warning::` line (bounded, e.g. first 300 chars)" | asked |
| `.github/scripts/bump-inngest-bootstrap-pin.sh` — comment documents enqueuePullRequest preconditions | "documenting it in the script comment" | asked |
| `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — enqueuefail assertions + MIN_ASSERTIONS bump | — | inferred — justification: repo convention is every script behavior is fixture-asserted (the suite exists for exactly this script); the new warning content is a behavior and the stub already emits the stderr the fix captures |
| `knowledge-base/engineering/architecture/decisions/ADR-270-...md` — dated addendum entry | — | inferred — justification: the 2026-11-09 addendum records the explicit-enqueue decision; the confirmed precondition materially qualifies when it can succeed — `wg-architecture-decision-is-a-plan-deliverable` makes the record update part of this plan |
| Tracking issue for retry-on-check-complete re-evaluation | — | inferred — justification: plan-skill deferral-tracking check — a descoped mechanism needs a visible re-entry point, not a silent one |

### Split Assessment

- Subsystems touched: 2 — `.github` (scripts + tests), `knowledge-base` (ADR)
- Planned files: 3 | Estimated changed lines: ~45
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `.github/scripts/bump-inngest-bootstrap-pin.sh` — enqueue arm (~lines 650–656): `2>/dev/null` → `2>&1`; `else` arm assigns `enq_reason=$(tr '\n' ' ' <<<"$enq_out" | tr -d '[:cntrl:]' | cut -c1-300)` and interpolates it into the `::warning::`; comment block (~lines 634–645) gains the confirmed precondition.
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — enqueuefail fixture (~lines 1010–1023): add reason-presence + single-line/bound assertions; `MIN_ASSERTIONS` (line 84) raised by the added row count.
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — new dated addendum after the `### Addendum 2026-11-09 (#12508)` section.

## Files to Create

None. (Plus the planning artifacts: this plan, `specs/feat-one-shot-12579-enqueue-rejection/tasks.md`, `specs/feat-one-shot-12579-enqueue-rejection/decision-challenges.md`.)

## Non-Goals / Out of Scope

- **Retry-on-check-complete enqueue** — deferred to tracking issue #12652 (created during planning); re-evaluation criteria: (a) a refusal is observed while the PR's required checks are green, or (b) an authored pin-bump PR sits armed + green + not-queued again (the #12489 shape), proving armed auto-merge's self-enqueue still has a gap the explicit arm is placed too early to cover.
- Changing the enqueue's placement, `expectedHeadOid` use, or `jump` — the arm's shape was decided by ADR-270's 2026-11-09 addendum; this plan changes only its observability and documentation.
- Any change to `merge-queue-stall-check.yml` — it watches queue ENTRIES, a different blind zone.

## Alternative Approaches Considered

| Alternative | Verdict | Reason |
|---|---|---|
| Separate stderr capture (temp file under the existing `WORK=$(mktemp -d)` dir, `2>"$WORK/enq.err"`) | rejected | `2>&1` into `enq_out` is the issue's suggested ~3-line shape; gh writes only the body to stdout on success, and the jq parse already tolerates noise — a second file adds a cleanup concern for zero behavioral gain |
| Retry-on-check-complete (new check_suite/status-triggered workflow or Inngest sweeper) | deferred (tracking issue #12652) | buys no property armed auto-merge doesn't already cover once protection is met; a whole new autonomous surface for an unobserved failure class |
| Delete the explicit enqueue arm entirely | rejected | the arm's residual value (already-green heads where auto-merge did not self-enqueue) is the #12489 class it was built for; the fix is visibility, not removal |

## Guard Contract

The deliverable adds assertion rows to an existing fixture suite — the rows pin one property.

### Guard 1 — enqueue refusal reason reaches the run log

**Property.** When `enqueuePullRequest` is refused, the run output's `::warning::` line contains the refusal's stderr text, flattened to a single line and bounded at 300 characters.

**Assembly.** Exactly one chokepoint: the `else` arm of the `enq_out=$(… gh api graphql …)` conditional in `bump-inngest-bootstrap-pin.sh`. The fixture suite's `enqueuefail` row drives it through the `MOCK_GH_ENQUEUE_FAIL=1` stub arm; `run_bump` captures combined output to `$LAST_OUT` for `assert_out_has`.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert `2>&1` → `2>/dev/null` on the enqueue capture | RED — the reason-text assertion finds nothing |
| 2 | Drop `${enq_reason…}` from the warning echo (restore the pre-fix literal) | RED — reason-text assertion fails |
| 3 | Stub emits a 2-line stderr (or a line containing a literal ESC) → assert the warning carries the text flattened on ONE line (the raw second line absent; the ESC stripped) | RED if the `tr '\n' ' '`/`tr -d '[:cntrl:]'` stages are removed (annotation-injection hole) |
| 4 | Stub exits 1 with EMPTY stderr → warning prints the `no stderr captured` fallback (must-PASS input differing from the canonical stub — catches a warn-line that hard-requires non-empty reason) | PASS only with the fallback |

## Implementation Phases

1. **RED (fixture first, per `cq-write-failing-tests-before`).** `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` `enqueuefail` block (~lines 1010–1023): add the reason-presence, single-line/bound, and empty-stderr-fallback assertions (Guard 1 matrix rows). Confirm they fail against the current `2>/dev/null` capture.
2. **GREEN (script).** `.github/scripts/bump-inngest-bootstrap-pin.sh`: flip `2>/dev/null` → `2>&1` at ~line 651; add `enq_reason=$(tr '\n' ' ' <<<"$enq_out" | tr -d '[:cntrl:]' | cut -c1-300)` + `${enq_reason:-…}` fallback interpolation in the `else` arm (~lines 652–656). Re-run the fixture suite green; bump `MIN_ASSERTIONS` (line 84) to the new count and extend its history comment.
3. **Document.** Same file's comment block (~lines 634–645): record the confirmed protection-met precondition, the expected-refusal reading on fresh PRs, and the arm's already-green-head value case. Then the ADR-270 addendum entry (see Architecture Decision).
4. **Ship.** Single PR `Closes #12579`, referencing #12652 for the deferred retry arm (Sequencing above).

## Acceptance Criteria

- [ ] **AC1** — `grep -n 'enq_out=' .github/scripts/bump-inngest-bootstrap-pin.sh` shows the capture line (and its continuation) carrying `2>&1`, and `sed -n '/enq_out=/,+2p' .github/scripts/bump-inngest-bootstrap-pin.sh | grep -c '2>/dev/null'` returns `0`.
- [ ] **AC2** — the `else` arm sanitizes with the canonical pipeline and embeds the result: `grep -n "tr -d '\[:cntrl:\]'" .github/scripts/bump-inngest-bootstrap-pin.sh` returns ≥1 hit inside the `else` arm, `grep -n 'enq_reason' .github/scripts/bump-inngest-bootstrap-pin.sh` returns ≥2 hits (assignment + `${enq_reason:-…}` echo interpolation), and `cut -c1-300` appears on the same assignment line.
- [ ] **AC3** — `SOLEUR_FIXTURE_PACKED=1 bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` exits 0 with the new `g1.enqueuefail:reason` (and bound/fallback rows) counted, and `MIN_ASSERTIONS` equals the new green run's assertion count.
- [ ] **AC4** — the script's enqueue comment block names the documented precondition: `grep -n 'required status check\|protection' .github/scripts/bump-inngest-bootstrap-pin.sh` returns ≥1 hit inside the comment lines (not only the warning echo).
- [ ] **AC5** — `grep -n '12562' knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` returns ≥1 hit in a dated addendum entry.
- [ ] **AC6** — the retry-on-check-complete tracking issue exists and is referenced in the PR body: `gh issue view 12652 --json state -q .state` returns `OPEN`.

## Test Scenarios

- **unit** — Given `MOCK_GH_ENQUEUE_FAIL=1` (stub writes `gh-stub: enqueuePullRequest rejected` to stderr, exits 1), when `run_bump enqueuefail` executes the arm path, then `$LAST_OUT` contains a `::warning::enqueuePullRequest` line carrying `gh-stub: enqueuePullRequest rejected`, exit stays 0, and `result=opened` is emitted.
- **unit** — Given a stub stderr containing a newline or >300 chars, when the refusal fires, then the warning is a single line and the text beyond the bound does not appear.
- **unit** — Given the stub exits 1 with empty stderr, when the refusal fires, then the warning prints the `no stderr captured` fallback (no bare dash, no empty interpolation).
- **unit** — Given `MOCK_GH_ENQUEUE_FAIL` unset (stub returns the QUEUED JSON), when the enqueue succeeds, then `enqueued … position 1` prints and no warning is emitted — regression: `2>&1` must not corrupt the success-path jq parse.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change to a CI script's warning line and its fixture, plus an ADR addendum. No user-facing surface, no UI files in Files-to-Edit/Create (Product/UX gate: NONE — mechanical UI-surface override did not fire; no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`).

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — new dated addendum after `### Addendum 2026-11-09 (#12508)` recording the #12562 refusal observation, the documented protection-met precondition, the now-unsuppressed warning as the per-run evidence channel, and the deferral of retry-on-check-complete to tracking issue #12652. Not a new ADR: this qualifies an existing decision's recorded rationale, which is the addendum mechanism ADR-270 already uses.

### C4 views

No C4 impact — enumerated per the completeness mandate: (a) **external human actors** — none new (the PR author remains `soleur-infra[bot]`); (b) **external systems/vendors** — GitHub's merge queue and GraphQL API are the pre-existing integration edge this script already calls; no new edge; (c) **containers/data-stores** — none touched (a log-line content change); (d) **actor↔surface access relationships** — unchanged (same minted App token, same mutation). The `.c4` model files describe the product runtime (hosts, tunnel, web-platform containers); the GHA publish workflow is not a modeled element and this change introduces no element a C4 reader would be misled to find absent.

### Sequencing

Single-PR — the script fix, fixture rows, and ADR addendum land together; tracking issue #12652 was already filed during planning.

## Open Code-Review Overlap

None — checked `gh issue list --label code-review --state open` (200 open issues) for `bump-inngest-bootstrap-pin.sh`, `test-bump-inngest-bootstrap-pin.sh`, and `ADR-270`; zero hits.

## Risks & Mitigations

- **Risk:** `2>&1` merges a stray stderr line into `enq_out` on the SUCCESS path, breaking the jq position parse. **Mitigation:** `gh api graphql` writes the body to stdout and nothing to stderr on success; the parse already falls back to `?` — worst case is cosmetic.
- **Risk:** a very long or multi-line error body floods the annotation. **Mitigation:** `${enq_reason:0:300}` bound + CR/LF flatten; fixture row asserts single-line shape.
- **Risk:** the documented precondition is wrong for some refusal subclass (e.g., permission vs. check-pending). **Mitigation:** that is precisely what the unsuppressed message now exposes per-run; the comment scopes the claim to "refusal while protection unmet is expected" rather than asserting every refusal is benign.
- **Risk:** a future reader treats the comment as permission to ignore all refusals. **Mitigation:** the warning text retains `armed auto-merge remains`, and the comment + ADR name the re-evaluation trigger.

## References

- Issue: #12579 (this plan, `Closes #12579`)
- Prior work: #12510 (residual batch that added the arm), #12489 (counter-instance), #12562 (refusal observed)
- Decision records: `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` (Addendum 2026-10-07 self-enqueue measurement; Addendum 2026-11-09 #12508 explicit enqueue), ADR-285 (App-authored enqueues)
- Script: `.github/scripts/bump-inngest-bootstrap-pin.sh:634-656` (arm + enqueue), `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh:84,349-360,1010-1023` (stub + fixture)
- Docs: GitHub "Managing a merge queue" — PR joins the queue after passing required branch-protection checks; `enqueuePullRequest` refuses unmet protection (`Pull request Required status check "<name>" is expected.`)
- Runbook precedent: `scripts/merge-queue-jump.sh:130-136` + `knowledge-base/engineering/operations/runbooks/merge-queue-jump.md` (refusal-cause enumeration)
- Learnings (deepen-pass): `knowledge-base/project/learnings/2026-11-10-merge-queue-admission-is-not-pr-head-green.md` (required-set admission; `gh pr view` lacks `mergeQueueEntry` — use `gh api graphql`), `knowledge-base/project/learnings/2026-10-04-my-new-dispatcher-tests-pinned-spelling-not-wiring-and-a-count-had-an-ungated-twin.md` (assert on mock-injected input)
- Sanitization precedent: `bump-inngest-bootstrap-pin.sh:294`/`:377` (`tr '\n' ' '`), `.github/scripts/vinngest-digest-freshness.sh:149`/`:279` (`tr '\n' ' ' | tr -d '[:cntrl:]' | cut -c1-200`)
