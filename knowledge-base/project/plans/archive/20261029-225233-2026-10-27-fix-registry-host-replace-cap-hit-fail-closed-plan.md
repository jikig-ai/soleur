---
title: "registry-host-replace dispatcher: a compare-API 300-file cap hit must not default to deliver"
type: fix
date: 2026-10-27
slug: registry-host-replace-cap-hit-fail-closed
branch: feat-one-shot-10650-registry-host-replace-cap-fail-closed
issue: 10650
closes: [10650, 9149]
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: a compare-API 300-file cap hit must not default to deliver

## Enhancement Summary

**Deepened on:** 2026-10-27
**Sections enhanced:** Research Insights (deepen findings), Technical Considerations (snippet), Acceptance Criteria (AC8), Test Scenarios (K2 fixture)
**Checks run:** deepen-plan gates 4.6-4.13 (all pass or skip, see below), a prototype of the new gate arm patched into a scratch copy of the workflow and linted, a live read-only replay of the PR #10501 range, PR/issue citation verification.

### Key Improvements

1. The incident was replayed against the live API (read-only) and the design flips it: with the watermark `e071b82` and the #10501 merge commit `f90d49c0`, the compare returns 300 files (64 commits), the `cloud-init-registry.yml` and `zot-registry.tf` blobs are identical at both ends, and only `variables.tf` differs (a new unrelated `inngest_link_tls` variable). The by-value compare of `registry_server_type` (`cpx22`), `registry_location` (`hel1`) and `registry_volume_size` (`60`) is equal at both ends, so the new gate reaches `deliver=false` with no render. The K2 fixture is synthesized from that shape.
2. The prototype caught a lint regression in the first draft of the snippet: `_b=... && _a=... || { ...; break; }` raises shellcheck SC2015 through actionlint, and this workflow has 0 actionlint findings today. The snippet now uses `if ! _b=... || ! _a=...; then ...; break; fi`, which is clean.
3. AC8 now names the real invocation forms of the lints and checks actionlint's output rather than its exit code (the repo wrapper exits 0 on findings by design).

### New Considerations Discovered

- `scripts/lint-workflows.sh` exits 0 on both clean and findings; only a hang (124) fails. A zero-findings claim must read the output.
- The five run-body lints do not share one calling convention (see AC8).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this one-shot branch.

## Overview

The registry-host-replace dispatcher's `gate` step (`.github/workflows/registry-host-replace-dispatch.yml`)
asks the GitHub compare API which files changed between the delivery watermark and the head. The API
caps `files` at 300 and gives no truncation flag, so the gate treats `n_files >= 300` as unprovable and
**delivers** (`deliver=true`, exit 0). After a stale watermark almost every range exceeds 300 files, so
the merge of PR #10501 (which touched only `variables.tf` among the watched files, with the rendered
user_data unchanged) destroyed and recreated the registry host, the fleet's sole image-pull path
(#10650). The same defect was reported earlier as #9149 (apply run 36417556135).

This plan changes the cap-hit arm in three ways, all inside the existing gate, verdict step and tests:

1. **Derive, never default.** On a cap hit the gate compares the git blob sha of each of the three render
   inputs at the watermark and at `AFTER_SHA` through the contents API. Differing blobs flow into the
   existing downstream arms (by-value variable compare, offline render, wiring text compare), which decide
   `deliver` exactly as for a non-truncated list. Identical blobs yield `deliver=false`.
2. **Fail closed when unprovable.** If any render input does not yield a 40-hex blob sha at either revision
   (API failure after three attempts, a directory, a bad shape, or a path absent at one ref), the gate
   writes `unproven=cap` to `GITHUB_OUTPUT`, prints an `::error::` and exits 1: no dispatch, a red run, and
   the watermark does not advance, so nothing is silently skipped.
3. **A distinct verdict.** The `verdict` step maps `unproven=cap` to a new `kind=gate-unproven` with its
   own sentences (never "NOT live", never "unchanged since"), filed through the existing machinery (PR
   comment on the derived target, or the single deduplicated `action-required` owner issue). The closed
   sets that enumerate verdict kinds (the follow-through probe, the runbook table, the suites) learn the
   new kind.

Nothing in this change dispatches a workflow, applies infrastructure or reads a secret: the only
production-adjacent behaviour is that the gate stops dispatching a host replace in a case where it used
to, and the tests execute the extracted `run:` bodies under a stubbed `gh` that refuses unexpected
requests (the stub records `gh workflow run` as an exit-0 no-op in the verdict suite and refuses it in
the gate suites).

## Research Insights

**Premise validation (Phase 0.6).** #10650 and #9149 are both OPEN; neither is closed by a merged PR.
PR #10501 (the unrelated merge that triggered the replace) merged 2026-10-20; #10205 (epic) is OPEN;
#7582 and #8714 are CLOSED (the render comparison and the zot boot image, already on main). Draft PR
#11324 is this branch's own PR; collision-precheck reports no other open change naming #10650 or #9149
(the foreign `test-all.sh` processes are the known sibling-run lock contention, not a duplicate). The
cited files exist on main: the workflow, the runbook, `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`.
ADR corpus check: no ADR rejects a blob-compare or fail-closed cap mechanism; ADR-169's amendment
documents the dispatcher but never states that a truncated list delivers, so no ADR text is contradicted.
No external premise was stale.

**Property List (Phase 0.6b).**

- P-a: A truncated compare list never by itself dispatches a host replace.
- P-b: A render input that really changed in the range still delivers, through the existing render decision.
- P-c: A range whose three render inputs are byte-identical at both ends does not deliver (this is #9149's
  "render unchanged must yield deliver=false").
- P-d: When P-a..P-c cannot be decided (a read fails), nothing is dispatched, the run is red, and the verdict
  names a distinct kind that a consumer can tell apart from `gate-failed`.

**Cut List (Phase 0.6b).** The brief names three mechanisms. Compare-file pagination is cut: measured live
2026-10-27, `compare/<wm>...main?per_page=100&page=2` returns 0 files (page 1 returns 300), so it buys
nothing. The paginated-commits intersection is cut: the compare `.commits` list is capped at 250 and
`scripts/registry-delivery-change.sh` already degrades to "unproven" above that, so it cannot answer P-b
on exactly the large ranges that matter. The per-path git log is subsumed by the blob compare (CTO ruling
F1, below), which answers "did these bytes differ between the watermark and the head" directly in six
reads. Retained: the blob compare, the existing render arms, the existing verdict/owner-issue machinery.
Rejected after plan review (CTO G1): forcing all three render-input flags on at a cap hit so the content
arms decide alone. It would run terraform on every cap hit, turn an unmeasurable render into a false
`gate-failed` for a range where nothing changed, and leave no distinct unprovable marker. Cut after plan
review: the ADR-169 dated Note (ADR-169 never states that a truncated list delivers; CTO G5), the
ABSENT/404 three-state logic (CTO G2), rows K6b, K7, K8, V17 (they pin code this change does not touch or
a branch that no longer exists), and two mutation-matrix rows that were duplicates.

**Mechanism ruling (CTO agent, 2026-10-27, persisted in `knowledge-base/project/specs/feat-one-shot-10650-registry-host-replace-cap-fail-closed/decision-challenges.md`).**
F1 blob compare via the contents API, head side pinned to `AFTER_SHA`, each sha validated as 40 hex, three
attempts per read (G3), and — as simplified by G2 — any result that is not 40 hex (404, 5xx, a
directory, a bad shape, a path absent at exactly one ref) is unprovable. F2 `unproven=cap` then `exit 1`,
`kind=gate-unproven` placed before the generic gate-failed arm. F3 cap-hit arm only (below the cap the list
is complete and exact). F4 #9149's "or could not be computed" refers to the downstream render arms, which
are unchanged. G4 one shared refusing stub for both suites.

**Live API facts (read-only, 2026-10-27).** Compare `files` cap 300, not pageable; `.commits` 250 without
paging parameters; `contents/<path>?ref=<sha> --jq .sha` returns the blob sha; a directory response makes
`--jq 'select(.type=="file")|.sha'` exit 1 ("expected an object but got: array"); a missing path prints
`gh: Not Found (HTTP 404)`. For the incident-like range (`e071b82...main`) cloud-init-registry.yml's blob
was identical at both ends while zot-registry.tf and variables.tf differed.

**Repo research.** Closed sets that enumerate verdict kinds (and so must learn `gate-unproven`):
`FAIL_KINDS` in `scripts/followthroughs/registry-htpasswd-stdin-10119.sh` and the loop in its `.test.sh`
(an unlisted kind is silently ignored there), the runbook kind table, the verdict suite. Generic
`kind=[a-z-]+` regexes (runbook, postmerge skill, follow-through capture) need no change. No other
workflow carries the dispatcher's `n_files >= 300` shape; `plugins/soleur/scripts/admin-merge-ready.sh`
(`length >= 300` => `error:incomplete`) is an existing fail-closed precedent for the same API cap.
Test registration: the verdict suite is declared for the workflow in `scripts/lib/test-affected-paths.sh`
(`edge:declared`, confirmed with `scripts/test-all.sh --print-selection --paths=.github/workflows/registry-host-replace-dispatch.yml`);
`apps/web-platform/infra/registry-render-delta.test.sh` (the only suite that executes the `gate` body, needs
terraform) is **not** selected by a workflow-only diff and its infra runner is gated on
`apps/web-platform/infra/` or `apply-web-platform-infra.yml`. Filed as #11325 (deferred, `Ref #10650`); this
plan mitigates by also placing the terraform-free cap rows in the always-selected verdict suite and by
editing the render-delta suite in the same PR. Lints for the edited `run:` body are listed in AC8 (all clean on the current file; actionlint and
shellcheck are installed locally).

**Institutional learnings applied.**
`2026-09-19-the-one-defect-lived-in-the-only-code-path-with-no-test-and-my-stub-answered-every-question.md`
(the cap arm today has zero behavioural rows; the stub must refuse unexpected requests, route on argv
position, and write refusals to a file the harness asserts empty);
`2026-09-28-an-offline-render-gate-inherits-every-stub-as-a-blind-spot.md` (compare by value; refusals must
not be swallowed by the gate's `2>/dev/null`);
`2026-10-26-a-caps-reachable-maximum-is-set-by-the-tightest-downstream-gate-and-a-scan-must-record-what-it-was-asked.md`
(an uncovered target is a distinct `unverifiable` kind, never clear: the `gate-unproven` kind);
`2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md`
(`null | length` is 0: assert the shape before trusting a count);
`2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md` (floors report by `printf` +
`exit 1`, never through the helper they audit);
`2026-09-25-gh-stub-must-mirror-real-cli-flags.md` (the stub accepts only the flags the gate really passes).

**Deepen-plan findings (2026-10-27).**

- Incident replay (read-only, live API; commands: `gh pr view 10501 --json mergeCommit`, `gh api repos/jikig-ai/soleur/compare/<wm>...<merge>`, `gh api repos/jikig-ai/soleur/contents/<path>?ref=<sha> --jq .sha`, then the gate's own `read_default` awk on both `variables.tf` revisions): watermark `e071b828f479fddf40023aff56fb377088d7c1ae`, merge `f90d49c0661b49664a39decb963f32a19488238d`, `status ahead`, `total_commits 64`, 300 files. `cloud-init-registry.yml` SAME, `zot-registry.tf` SAME, `variables.tf` DIFF (only a new unrelated `inngest_link_tls` variable block); `registry_server_type cpx22`, `registry_location hel1`, `registry_volume_size 60` equal at both ends. The new design therefore decides `deliver=false` for the exact incident range, while a file-list proxy could not.
- Prototype: the cap arm was patched into a scratch copy of the workflow (outside the repo) and linted. `actionlint` baseline for the real file is 0 findings; the first-draft snippet produced one SC2015 info finding, the `if !` form produces none. `lint-workflow-run-body-syntax.py`, `lint-workflow-step-env-refs.py` (file argument), `lint-workflow-errexit-capture.py` (`--root`), and `lint-workflow-issue-write-scope.py` (directory argument) are clean on the patched copy. The loop was also executed under `bash --noprofile --norc -eo pipefail` with a function-stubbed `gh`: one 502 input yields `unread=<that input>`, the other inputs are compared, and nothing aborts the step.
- Citations verified live: #10650 and #9149 OPEN; #10205 OPEN (epic); #10501 MERGED 2026-10-20 (merge commit above); #7582 and #8714 CLOSED; #11325 OPEN (the deferral filed by this plan); #11324 is this branch's draft PR. #10540/#11287/#11322 are named only as sibling work not to touch. No AGENTS rule ID is cited in the body.
- Gate results: 4.6 pass (threshold `aggregate pattern`); 4.7 pass (all five fields, `grep` is an allowlisted verb, the literal `gate-unproven` is a matchable output, no ssh; the probe becomes true once T3.1 lands, and the block is new in this run so the cap and literal conditions are satisfied); 4.8 pass (no PAT-shaped match); 4.9 skip (no UI surface); 4.10 skip (no store, no `.tf`, no migration); 4.11 pass (lint green, one guard entry, assembly names the chokepoint, matrix derived from the design); 4.12 pass (one unfenced `## Scope Check`, no `unmapped` cell, every `inferred` row justified, counts derived from the file lists); 4.13 skip (no new autonomous task surface).
- Not run, by judgment: the skill's "launch every available agent" fan-out. The plan changes one bash arm and its tests; the three-agent plan-review panel and the CTO rulings already covered simplicity, correctness and design, and a 40-agent sweep would re-read the same 70 lines. The mechanical halts above and the prototype are the deepen evidence.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (checked) | Plan response |
|---|---|---|
| Behavioural precedent is `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh` (extract `run:` body, stub `gh`) | That suite extracts `change`, `verdict`, `dispatch` — not `gate`. The gate's behavioural suite is `apps/web-platform/infra/registry-render-delta.test.sh` (29 rows, refusing stub, needs terraform, not selected on a workflow-only diff) | Add the terraform-free cap rows to the verdict suite by extracting `gate` there too (selected on every workflow edit, runs in the always-on `test` job), and the render-dependent cap rows to render-delta, both driving the gate through ONE shared refusing stub (`plugins/soleur/test/lib/registry-gate-gh-stub.sh`, CTO G4) so two stubs cannot drift. Deferral of the selection gap: #11325 |
| "derive … from paginated commits or a per-path git log" | Compare files cannot be paged (page 2 returns 0 files); compare `.commits` caps at 250 and the existing helper degrades above it | Blob-sha compare of the three inputs (CTO F1) — a per-path answer, without range membership |
| #9149: "keep rows where the render changed, or could not be computed, and the dispatcher delivers" | Those rows live in the downstream render arms (unmeasurable watermark render adds a WHY entry and delivers; unreadable variable value delivers). The new unprovable case is "was anything relevant touched", a different uncertainty | Downstream arms untouched and re-pinned by a cap-hit row (K5); only the unprovable touched-set fails closed (CTO F4) |
| "file or update the action-required issue per the existing machinery" | The verdict step already files/updates it when nothing is derivable, and comments on derived PRs, for any non-success job; the gate exiting 1 reaches it as `gate-failed` | No new filing mechanism; only a distinct `kind` and sentences |
| `registry-delivery-change.sh` header: the gate "can reach this helper when the compare's 300-file cap made it deliver unproven" | After the fix the cap no longer delivers; the helper still runs on every gate outcome (`if: always()`) | Reword that sentence |

## Open Code-Review Overlap

None. Open `code-review` issues were searched for every planned path (the workflow, both suites, the
follow-through probe, the helper, the runbook, ADR-169): no hit.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a cap-hit must NOT default to deliver" [brief] | Phase 2 gate cap arm (T2.1) | mapped |
| 2 | "derive the touched-file answer from paginated commits or a per-path git log over the dispatcher's three render inputs and deliver only when a render input actually changed in the range" [brief] | Phase 2 blob compare of the three inputs (T2.1), mechanism ruled F1 | mapped |
| 3 | "if the truncated answer still cannot be proven either way, fail closed (do not dispatch a host replace; emit a distinct verdict marker and file or update the action-required issue per the existing machinery)" [brief] | Phase 2 `unproven=cap` + exit 1 (T2.1), verdict `gate-unproven` arm (T2.2) | mapped |
| 4 | "Read the issue text and knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md first" [brief] | Research Insights; Phase 3 runbook update (T3.1) | mapped |
| 5 | "extract the run: body, execute it under bash --noprofile --norc -eo pipefail with a stubbed gh; make the stub refuse unexpected requests" [brief] | Phase 1 gate harness in the verdict suite (T1.1) and render-delta (T1.2) | mapped |
| 6 | "Add RED rows first, including: cap hit with no render input touched => no replace; cap hit with a render input touched => replace; unprovable => no replace and a distinct marker." [brief] | Phase 1 rows K1, K2, K3v, K3, K6, V16 committed before the fix | mapped |
| 7 | "Use Ref, not Closes, for the parent epic #10205; use `Closes #10650` in the PR body only if the acceptance criteria fully hold." [brief] | PR body (T4.4) | mapped |
| 8 | "never dispatch registry-host-replace or any workflow with `gh workflow run`, never apply anything, never read or print a secret value; no production write happens in this change" [brief] | Constraints in Overview; AC9; stubs refuse `workflow run` in gate suites | mapped |
| 9 | "a >=300-file compare with render unchanged must yield deliver=false; keep rows where render changed or could not be computed delivering" [issue #9149, extra context] | Rows K2, K4 (unchanged => false), K3, K5 (changed / uncomputable => delivers) | mapped |
| 10 | "carry `Closes #9149` only if it holds" [extra context] | PR body (T4.4) conditional on AC3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/registry-host-replace-dispatch.yml` gate cap arm + hoisted `INFRA/TF/VARS` | "a cap-hit must NOT default to deliver" | asked |
| same file, verdict step `GATE_UNPROVEN` env + `gate-unproven` arm | "emit a distinct verdict marker" | asked |
| same file, comments (cap block, STEP MAP) | — | inferred — justification: the cap-block comment states the removed behaviour ("Treat both as unproven and deliver"); leaving it contradicts the code |
| `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh` | "Existing behavioural suite precedent: plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh" and "Add RED rows first" | asked |
| `apps/web-platform/infra/registry-render-delta.test.sh` | "Add RED rows first" (asks 5-6, 9: the render-dependent rows need terraform and live in the gate's own suite) | asked |
| `plugins/soleur/test/lib/registry-gate-gh-stub.sh` (new, shared by both suites) | "make the stub refuse unexpected requests" | asked |
| `scripts/followthroughs/registry-htpasswd-stdin-10119.sh` + `.test.sh` (`FAIL_KINDS`) | — | inferred — justification: the closed set silently ignores an unlisted kind, so a `gate-unproven` verdict would never escalate there (CTO ruling, closed-set completeness) |
| `scripts/registry-delivery-change.sh` header sentence | — | inferred — justification: it states the cap "made it deliver unproven", false after this change |
| `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md` | "Read the issue text and knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md first" | asked |
| Deferral issue #11325 | — | inferred — justification: the deferral-tracking rule requires a tracking issue for the render-delta selection gap this plan found and only mitigates |

### Split Assessment

- Subsystems touched: 5 — `.github`, `plugins/soleur`, `apps/web-platform`, `scripts`, `knowledge-base`
- Planned files: 7 edited, 1 created (plus the spec dir artifacts) | Estimated changed lines: ~330 (about 70 workflow, 170 tests and shared stub, 25 probe/helper, 30 runbook)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root count is over threshold only because the contract spans the gate, its verdict kind, the two enumerations of that kind and the docs. Splitting leaves either RED rows with no fix, or a new verdict kind that the follow-through probe ignores and the runbook does not name. One reviewer reads one contract.

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) the status quo — an unnecessary registry-host replace that leaves every deploy unable to pull images for the minutes the new host takes to boot (running containers keep serving, the store volume is preserved), or (b) a really-changed zot/cloud-init render that is not delivered: no replace runs, the run is red and a `gate-unproven` verdict names the range, so the change waits for a manual re-fire rather than disappearing.
- **If this leaks, the user's workflow is exposed via:** nothing user-facing. The gate reads the blob sha of three files in this repository with the job's own `contents: read` token and emits no secret; the only text that crosses into markdown is fixed wording plus paths from a closed set, and the verdict step's existing `md_esc` path still escapes everything else.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident`, because no user data is at risk (the store volume is preserved) and the failure is a few minutes of blocked deploys that recurs on every stale-watermark merge, which is a pattern rather than one user's incident; not `none`, because the host is the fleet's sole pull path.

## Technical Considerations

**Gate cap arm (the change).** Today (`registry-host-replace-dispatch.yml`, gate step, comment "THE COMPARE API
CAPS `files` AT 300"): when `n_files >= 300` it writes `deliver=true`, warns, `exit 0`. New shape, same
position (after the ancestry check, before the `tpl_changed/tf_changed/vars_changed` flags):

```bash
INFRA=apps/web-platform/infra; TF="$INFRA/zot-registry.tf"; VARS="$INFRA/variables.tf"   # hoisted above the cap arm: `set -u` aborts on use-before-define
if [[ "${n_files:-0}" -ge 300 ]]; then
  blob_at() {  # $1 path, $2 ref -> prints the 40-hex blob sha; rc 1 = unprovable (any other result)
    local n r
    for n in 1 2 3; do
      r="$(gh api "repos/${GITHUB_REPOSITORY}/contents/$1?ref=$2" --jq 'select(.type=="file")|.sha' 2>/dev/null)" \
        && [[ "$r" =~ ^[0-9a-f]{40}$ ]] && { printf '%s' "$r"; return 0; }
      (( n < 3 )) && sleep "$n"
    done
    return 1
  }
  changed=""; unread=""
  for _p in "$CFG" "$TF" "$VARS"; do                      # all three are read until one is unprovable
    if ! _b="$(blob_at "$_p" "$BEFORE_SHA")" || ! _a="$(blob_at "$_p" "$AFTER_SHA")"; then unread="$_p"; break; fi
    [[ "$_b" != "$_a" ]] && changed="${changed:+$changed$'\n'}$_p"
  done
  if [[ -n "$unread" ]]; then
    echo "unproven=cap" >> "$GITHUB_OUTPUT"                # BEFORE the exit: the verdict step reads it
    echo "::error::the compare API returned ${n_files} files (its 300 cap), so the changed-file list is TRUNCATED, and render input ${unread} could not be read as a file at both the watermark ${BEFORE_SHA:0:7} and the head ${AFTER_SHA:0:7} (only the first unreadable input is named). Refusing to dispatch a registry host replace on an unprovable diff: it neither delivers nor skips. Re-fire via workflow_dispatch once the API recovers; a re-fire replaces the host."
    exit 1
  fi
  echo "::notice::compare list truncated at ${n_files} files; the three render inputs were compared by git blob at the watermark and the head (changed: ${changed:-none})."
fi
```

`changed` (overwritten here, deliberately) then feeds the unchanged `grep -qx` flag lines, so the by-value
variable compare, the offline render and the wiring text compare decide exactly as they do for a complete
list. The `deliver=false` branch ("Nothing since the watermark … touched a render input") gets a cap-aware
sentence. stdout only is read (`2>/dev/null`), so a success-path stderr notice from `gh` cannot corrupt the
sha; there is no 404 string match. Any non-sha result is unprovable, including a render input absent at
exactly one ref: a genuine add or delete of a render input costs one manual re-fire, which the runbook says
so nobody reads it as a bug (CTO G2). A render input absent at the head also never reaches the
`read_default ... || true` arm that would otherwise treat it as "unreadable" and deliver. Retry arithmetic:
the loop stops at the first unprovable input and each read sleeps 1 s then 2 s between its three attempts,
so the worst case is about 3 s of sleep before the exit, far inside the gate step's `timeout-minutes: 5`
and the job's 75-minute ceiling (no change to that sum).

**Verdict step.** New env `GATE_UNPROVEN: ${{ steps.gate.outputs.unproven }}` (via `env:`, never inline
in the `run:` body). New arm placed immediately before the generic `gate-failed` arm and keyed on
`GATE_OUTCOME == failure && GATE_UNPROVEN == cap`: `KIND="gate-unproven"`, `WHAT="Delivery UNPROVEN: the compare
API's file list was truncated and the render inputs could not be compared"`, a `WHY` naming the 300 cap and
that the gate's own `::error::` names the unread input, and a `STATE` that overrides the default
not-live sentence: nothing ran, whether the host's user_data is current is UNPROVEN (not known stale), the
watermark did not advance so the next push re-derives the range, and a manual re-fire delivers after the
three render inputs are checked. It never emits "NOT live" or "unchanged since". The marker stays the last
line of the body.

**Why a red run and not a green skip (CTO F2).** A green `deliver=false` advances the watermark past a range
nobody proved, which is the silent non-delivery this workflow exists to remove. A red run keeps the
watermark, the verdict step files the artifact, and the existing owner-issue dedupe (one open
`action-required` issue at a time) bounds repeats. A persistent unproven state means contents-API trouble,
and the runbook says a manual dispatch (which always delivers) is the way out.

**Attribution after a cap hit.** The `change` step still runs (`if: always()`); with `total_commits > 250`
it already degrades to "unproven" attribution. The verdict text must not claim a specific PR it cannot
prove, and does not (it reuses the existing summary/`range_note` composition).

### Attack Surface Enumeration

Paths that decide `deliver` for a push-triggered run, and whether each can be driven by a truncated list:
(1) manual dispatch — delivers unconditionally, not list-driven; (2) no watermark — delivers, not
list-driven; (3) watermark not an ancestor — delivers, not list-driven (compare `status`, not the list);
(4) **`n_files >= 300` — the defect, now blob-driven**; (5) list-complete path — exact; (6) downstream
render arms — content-driven. Only (4) trusted a truncated list. Unchanged-by-design: (2) and (3) still
fail toward delivering (the preflight still gates); changing them is out of scope and not part of #10650.

## Architecture Decision (ADR/C4)

No architectural decision is made: this repairs one arm of an existing gate and adds one verdict kind to
an existing vocabulary. No ADR is written or amended: ADR-169 documents the dispatcher but never states
that a truncated compare list delivers, and no decision text changes (CTO G5 cut the dated Note this plan
first proposed).

C4: no impact. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external
human actors — the operator who re-fires; already modelled and unchanged; (b) external systems — GitHub
(Actions, compare and contents API) and Better Stack; the dispatcher workflow itself is not a C4 element
(`model.c4` mentions `registry-host-replace` only inside the zot registry's description), and no new vendor
or edge appears; (c) containers/data stores — none touched; (d) actor-to-surface access relationships —
none change. `bash plugins/soleur/test/c4-count-parity.test.sh` is green on the current tree
(`ALL TESTS PASSED`) and is re-run in Phase 4 because no derived cardinality (workflows, monitors) moves.

## Observability

```yaml
liveness_signal:
  what: "the dispatcher run on main after every push touching a watched path; a truncated range now ends in a deliver=false run or a red run carrying kind=gate-unproven"
  cadence: "per push to main touching the three render inputs or the workflow file"
  alert_target: "the delivering PR(s), or the single open action-required owner issue (harvested by operator-digest)"
  configured_in: ".github/workflows/registry-host-replace-dispatch.yml (verdict step)"

error_reporting:
  destination: "GitHub Actions annotations plus the verdict artifact (PR comment or action-required issue) carrying the marker <!-- registry-delivery run=N kind=gate-unproven attempt=A -->"
  fail_loud: "the gate's ::error:: names the cap and the first unreadable render input, the step exits 1, and the job is red"

failure_modes:
  - mode: "a compare list at the cap hides a really-changed render input and the gate wrongly skips"
    detection: "blob compare reads the three inputs at both revisions; rows K3v/K3 pin it; a read failure is unproven, never skipped"
    alert_route: "kind=gate-unproven verdict on the PR or owner issue"
  - mode: "the contents API is unreadable or rate-limited at a cap hit"
    detection: "three attempts per read, then unproven=cap and exit 1"
    alert_route: "kind=gate-unproven verdict; repeats deduped by the one open owner issue"
  - mode: "a render input is added, deleted or renamed in the range (absent at one or both revisions)"
    detection: "any result that is not a 40-hex blob sha is unprovable, never unchanged"
    alert_route: "kind=gate-unproven verdict naming the path; a manual re-fire delivers"
  - mode: "a future consumer ignores the new kind (closed-set drift)"
    detection: "FAIL_KINDS loop row in the follow-through probe test; runbook kind table row"
    alert_route: "CI red on scripts/followthroughs/registry-htpasswd-stdin-10119.test.sh"

logs:
  where: "GitHub Actions run log of the gate step (::notice:: for a derived cap hit, ::error:: for unproven)"
  retention: "GitHub Actions default run-log retention (90 days)"

discoverability_test:
  command: "grep -m1 -o gate-unproven knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md"
  expected_output: "gate-unproven"
```

## Guard Contract

### Guard 1 — cap-hit gate (gate `n_files >= 300` arm, verdict `gate-unproven` arm, closed kind sets)

**Property.** A compare-API file list truncated at its 300 cap never by itself yields `deliver=true`: the gate delivers only through the existing render decision after the three render inputs' blobs provably differ between the watermark and `AFTER_SHA`, yields `deliver=false` when they provably match, and otherwise emits `unproven=cap` and exits 1 so the verdict is the distinct `gate-unproven` kind.

**Assembly.** One chokepoint, the `n_files >= 300` branch of the gate `run:` body: every push-arm range with a truncated list flows through it (manual dispatch, a missing watermark and a non-ancestor watermark exit earlier by design and are not list-driven). Quantified members: the three render inputs `CFG`, `TF`, `VARS` (the same constants the later `tpl_changed/tf_changed/vars_changed` flags use, hoisted so the loop and the flags cannot drift; the existing P2 row pins the same set against `on.push.paths`), both revisions (`BEFORE_SHA`, `AFTER_SHA`), and the consumers of the new output and kind: the verdict arm, `FAIL_KINDS` in the follow-through probe, its test loop, the runbook table and the verdict suite. There is exactly one cap check of this shape in the repo (grep for `-ge 300` / `300 cap` over `.github/workflows` and `scripts`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `deliver=true` + `exit 0` in the cap arm (the original behaviour) | K1, K2, K4 RED on `deliver=false` |
| 2 | Own dispatch: delete the `n_files` assignment so the cap arm is unreachable (the filler list names no render input, so the file-list path says `deliver=false`) | K3v and K3 RED (the fixtures hide a really-changed input behind a truncated list); K1 and K2 go RED only on their "six blob reads" assertion, which is why that assertion is mandatory and K3v is the load-bearing row |
| 3 | Change `-ge 300` to `-gt 300` (the cap fixtures carry exactly 300 entries) | K1 RED on the blob-read-count assertion only (its `deliver=false` decision is unchanged) |
| 4 | Second member after a compliant first: compare only `CFG` (or `break` after the first equal blob) | K3 (zot-registry.tf, second) and K2/K3v (variables.tf, third) RED |
| 5 | Read both sides at `BEFORE_SHA` (ref not swapped) | K3v RED |
| 6 | Treat a failed blob read as "unchanged" (swallow rc), or treat unprovable as `deliver=false` with exit 0 (green skip) | K6 RED (it asserts rc == 1, `unproven=cap`, no `deliver` line) |
| 7 | Write `unproven=cap` after the `exit 1` | K6 RED on the output assertion |
| 8 | Verdict: delete the `gate-unproven` arm, or place it after the generic `gate-failed` arm | V16 RED |
| 9 | Drop `gate-unproven` from `FAIL_KINDS` | the probe test's kind loop RED |

**Harness rows.** (a) Suite edit that MUST drive it RED: make the shared stub ignore the requested ref (serve every read from the BEFORE tree) — K3v and K3 must go RED, proving the fixtures discriminate the ref. (b) Each cap fixture asserts its own precondition (exactly 300 entries, none named like a render input, compare `status` is `ahead`); editing a fixture to include a render input name flips the row RED on the precondition rather than silently testing the list path. (c) K6 asserts the exact request, not just a failure: three attempts at `contents/<variables.tf>?ref=<AFTER>` in the stub's request log and an empty refusal file, so a wrong URL (which the stub refuses with exit 64) cannot satisfy the "unprovable" row by accident. (d) Must-PASS inputs that are not the canonical fixture and differ in a way the contract permits: K4 (a comment-only template change: the blob differs, the render does not, `deliver=false`) and K2 (a `variables.tf` blob that differs without a render-input value change). Mutations 1, 2, 4 and 6 and harness row (a) are driven RED once locally and noted in the PR body.

**Anchor.** No stored value: the comparison is between two live git revisions of this repository read through the API, so there is no hash or floor that one diff could move together with the thing it protects. The assertion-count literals (render-delta `exactly N`, verdict floor) are anti-vacuity controls reported by direct `printf` + `exit 1`, set from a measured green run, never from a guess.

A property about order or lifetime is not claimed: the unproven output must precede the exit, which is mutation 7, not a window.

## Implementation Phases

### Phase 1 — RED rows first (commit 1: tests only)

- **T1.1 `plugins/soleur/test/lib/registry-gate-gh-stub.sh` (new, shared).** One executable refusing `gh` stub used by both suites, driven by env (`STUB_WATERMARK`, `STUB_AFTER`, `STUB_COMPARE`, `STUB_BEFORE`, `STUB_HEAD` trees, `STUB_ERR`, `GH_LOG`). Routes: `run list` (watermark); `compare/<W>...<A>` exactly; `contents/<path>?ref=<ref>` where the argv's `--jq` selects `.sha` (returns the blob sha of the tree for that ref, computed without `git` as `{ printf 'blob %s\0' "$(wc -c <f)"; cat f; } | sha1sum`, because an unconstructed `git` spawn is forbidden by `plugins/soleur/AGENTS.md`) or `.content` (base64, watermark ref only, as today); modelled failures by env (`STUB_CONTENTS_FAIL` for every read, `STUB_SHA_FAIL=<path>@<ref>` for one read: HTTP 502, exit 1). Everything else, including `workflow run`, is refused (exit 64) with the refusal appended to `STUB_ERR`, which each harness's `run_gate` asserts empty. Both suites also put a no-op `sleep` earlier on `PATH` so the retry and `fetch_before` delays do not cost wall time.
- **T1.2 `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`.** Extract `gate` alongside `change/verdict/dispatch`; add a `run_gate` (cwd a fixture tree copied from the real `variables.tf`, `PATH` without terraform and `CI=1` so any render attempt fails closed, the gate body under `bash --noprofile --norc -eo pipefail`). Terraform-free rows:
  - **K1** cap hit (exactly 300 entries, none a render input), the three blobs identical => `deliver=false`, rc 0, exactly six `?ref=` blob reads (3 inputs x 2 refs), no `.content` read at the head ref, no render.
  - **K2** incident replay: cap hit, `variables.tf` blob differs only by an appended synthesized unrelated variable block (the shape measured on the live #10501 range: `cloud-init-registry.yml` and `zot-registry.tf` identical, only `variables.tf` differs, the three by-value variables equal) => `deliver=false` by the by-value compare, no render.
  - **K3v** cap hit, `variables.tf`'s `registry_server_type` differs => rc 0, `deliver=true`, `render_changed=true`, `why` names `registry_server_type` (a `deliver=true` alone would also pass against the old arm, so the `why` and `render_changed` assertions carry the RED).
  - **K6** unprovable: cap hit, HTTP 502 on `variables.tf` at the head ref (third input, after two compliant ones) => rc == 1, `unproven=cap` in the output, no `deliver` line, `::error::` names the cap and `variables.tf`, three attempts at that exact URL in the request log, empty refusal file.
  - **V16** verdict `gate-unproven`: `JOB_STATUS=failure GATE_OUTCOME=failure GATE_UNPROVEN=cap` (others skipped) => `kind=gate-unproven`, no "NOT live", no "unchanged since", marker last, owner issue created when no target is derivable.
  Raise the anti-vacuity floor from the measured green count (today 34/34, floor 32), keeping the exact `printf` + `exit 1` form that `scripts/guard-vacuity-floor.test.sh` constructs its mutant against. The existing `V11` row already pins that an empty `GATE_UNPROVEN` still yields `gate-failed`.
- **T1.3 `apps/web-platform/infra/registry-render-delta.test.sh`.** Replace its heredoc stub with the shared one (all 29 existing rows must stay green), add `cap_compare_of` (exactly 300 filler entries plus optional named ones), and add the terraform-dependent rows: **K3** cap hit, a zot digest bump (blob differs, second input) => `deliver=true`, `render_changed=true`, `why` contains "rendered user_data differs" (the render decided, not a cap fallback); **K4** cap hit, comment-only template change => `deliver=false` (#9149's "render unchanged => false"); **K5** cap hit, unmeasurable watermark render => `deliver=true`, `::warning::`, and `why` containing "unmeasurable by the head render" (the old arm also warned and delivered, so the `why` text carries the RED). Move the equality literal from 29 to the measured green total.
- **T1.4 `scripts/followthroughs/registry-htpasswd-stdin-10119.test.sh`.** Add `gate-unproven` to the kind loop (RED against the unchanged `FAIL_KINDS`).
- Commit the tests alone and record the RED run: K1 (read-count), K2, K3v (`why`), K3 (`why`), K4, K5 (`why`), K6, V16 and the probe loop fail against the unmodified workflow; the 29 existing render-delta rows and the existing verdict rows pass.

### Phase 2 — GREEN (commit 2)

- **T2.1** Gate cap arm as above, hoisted `INFRA/TF/VARS`, cap-aware `deliver=false` sentence, rewritten cap comment (state the property, the measured API facts and the F4 reading of #9149 so the two are not read as contradictory), STEP MAP line for `unproven=`.
- **T2.2** Verdict step: `GATE_UNPROVEN` env (read as `${GATE_UNPROVEN:-}`), the `gate-unproven` arm before `gate-failed`.
- **T2.3** Run both suites and the probe test green; drive mutations 1, 2, 4, 6 and the harness row (a) RED once and note the result in the PR body.

### Phase 3 — documentation and closed sets (commit 3)

- **T3.1** Runbook (`registry-host-replace-dispatch.md`): add the `gate-unproven` row to the `kind` table (cause: compare list truncated at the 300 cap and a render input unreadable as a file at either revision; next action: check the three render inputs between the watermark and the head, then re-fire; say plainly that a re-fire replaces the host and that a genuine add, delete or rename of a render input lands here by design), and fix the stale `gate-failed` prose.
- **T3.2** `FAIL_KINDS` in the probe plus its test loop; reword the helper header sentence in `scripts/registry-delivery-change.sh`.
- **T3.3** Run `bash scripts/test-all.sh --print-selection --paths=plugins/soleur/test/lib/registry-gate-gh-stub.sh` and record which suites an edit to the shared stub selects; if `registry-render-delta.test.sh` is not among them, add that fact to #11325 (a comment) rather than widening this PR.

### Phase 4 — validation and PR

- **T4.1** `actionlint .github/workflows/registry-host-replace-dispatch.yml` (expect no output), the run-body lints named in AC8, `bash plugins/soleur/test/c4-count-parity.test.sh`.
- **T4.2** `bash plugins/soleur/scripts/affected-tests.sh` (the test-all lock is contended by sibling runs; expect queueing) and the two suites directly.
- **T4.3** `rg` the repo for any other literal that pins the old cap behaviour ("Delivering rather than silently skipping", "cannot prove .* was untouched").
- **T4.4** PR body: `Closes #10650` and `Closes #9149` only if AC1-AC7 hold, `Ref #10205`, `Ref #11325`, a `## Changelog` section, the RED-first evidence and the mutation note. Arm the merge with `gh pr merge --squash --auto` only after the required checks are green; never push to a PR that is in the merge queue.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 A cap-hit range whose three render inputs are byte-identical at the watermark and the head yields `deliver=false` and dispatches nothing (rows K1, K2, K4). Verify: `bash plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh` and `bash apps/web-platform/infra/registry-render-delta.test.sh` exit 0.
- [ ] AC2 A cap-hit range where a render input really changed still delivers through the existing render decision (K3v, K3), and the row where the watermark render cannot be computed still delivers (K5).
- [ ] AC3 #9149's acceptance holds: "a >=300-file compare with render unchanged must yield deliver=false" (K4: the template blob differs, the render does not) and "rows where render changed, or could not be computed, deliver" (K3, K3v, K5). `Closes #9149` is written only after this is checked.
- [ ] AC4 An unprovable touched-set (a render input that does not yield a 40-hex blob sha at either revision) emits `unproven=cap` BEFORE `exit 1`, prints an `::error::`, and writes no `deliver` line (K6, rc == 1); the verdict step posts `kind=gate-unproven` with the marker last and no "NOT live"/"unchanged since" text (V16), and an ordinary gate failure is still `gate-failed` (existing V11).
- [ ] AC5 Every gate row ran against the shared stub that refuses unexpected requests; both harnesses assert an empty refusal file; the six blob reads (3 inputs x 2 refs) are asserted by argv in K1, and no `.content` read happens at the head ref.
- [ ] AC6 RED-first is demonstrable: `git log --oneline` shows the tests-only commit before the fix commit, and the recorded RED run lists K1 (read-count), K2, K3v, K3, K4, K5, K6, V16 and the probe loop failing against the unmodified workflow, with the existing rows green.
- [ ] AC7 Closed sets updated: `grep -c gate-unproven scripts/followthroughs/registry-htpasswd-stdin-10119.sh knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md` is at least 1 for each, and the probe test exits 0.
- [ ] AC8 Lints clean: `actionlint .github/workflows/registry-host-replace-dispatch.yml` prints nothing (baseline is 0 findings; `scripts/lint-workflows.sh` exits 0 even with findings, so read its output, not its rc); `python3 scripts/lint-workflow-run-body-syntax.py <file>` and `python3 scripts/lint-workflow-step-env-refs.py <file>` exit 0; `python3 scripts/lint-workflow-errexit-capture.py` and `python3 scripts/lint-workflow-issue-write-scope.py .github/workflows` exit 0; the verdict env uses `env:` only (no inline `${{ steps.gate.outputs.unproven }}` inside any `run:` body).
- [ ] AC9 Diff scope: `git diff origin/main --stat` lists only the seven edited files, the one new shared stub and the plan/spec artifacts; no `gh workflow run` appears in any added line outside comments, docs and the stub's refusal route; no `.tf`, no `apply-web-platform-infra.yml`, no secret reference is touched.
- [ ] AC10 Mutations 1, 2, 4, 6 and harness row (a) were each driven RED once locally and the outcome is noted in the PR body.
- [ ] AC11 `bash plugins/soleur/scripts/affected-tests.sh` passes; `bash plugins/soleur/test/c4-count-parity.test.sh` passes; the selection record for an edit to the shared stub is in the PR body (T3.3).
- [ ] AC12 Anti-vacuity: the render-delta equality literal and the verdict floor were set from measured green counts and keep their `printf` + `exit 1` form.

### Post-merge (agent-run, read-only)

- [ ] AC13 The merge push touches the workflow file, so the dispatcher runs on it. Verify with `gh run list --workflow=registry-host-replace-dispatch.yml --branch main --limit 1 --json conclusion,headSha` that the run concludes `success` (a cap hit with unchanged render inputs ends `deliver=false`; a range whose render really changed is delivered by design and is not a failure of this fix) and that, if the range hit the cap, the gate log shows the `compare list truncated` notice. No operator step.

## Test Scenarios

Layers: all are `integration` (extracted workflow `run:` bodies executed under the runner's shell with a refusing stubbed `gh`); the static wiring rows are `unit`.

- Given a compare of exactly 300 files naming no render input and identical blobs, when the gate runs, then `deliver=false`, rc 0, six blob reads, no render (K1).
- Given the incident shape (only an unrelated `variables.tf` default differs, 300 files), then `deliver=false` (K2).
- Given 300 files hiding a `registry_server_type` change in `variables.tf`, then `deliver=true`, `render_changed=true`, `why` names the type (K3v).
- Given 300 files hiding a zot digest bump, then the render decides: `deliver=true`, "rendered user_data differs" (K3).
- Given 300 files and a comment-only template edit (blob differs, render identical), then `deliver=false` (K4).
- Given 300 files and an unmeasurable watermark render, then `deliver=true`, a `::warning::` and a `why` naming the unmeasurable render (K5).
- Given a 502 on `variables.tf` at the head ref after two compliant inputs, then rc == 1, `unproven=cap`, no `deliver` line, three attempts at that URL (K6).
- Given `GATE_OUTCOME=failure GATE_UNPROVEN=cap`, then the verdict is `kind=gate-unproven` (V16); with `GATE_UNPROVEN` empty it stays `gate-failed` (V11).
- Given a `gate-unproven` marker on a PR after merge, then the follow-through probe escalates it like the other failure kinds (probe loop).
- Regression for the incident: the K2 fixture is the PR #10501 shape and must stay green.

## Files to Edit

- `.github/workflows/registry-host-replace-dispatch.yml`
- `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`
- `apps/web-platform/infra/registry-render-delta.test.sh`
- `scripts/followthroughs/registry-htpasswd-stdin-10119.sh`
- `scripts/followthroughs/registry-htpasswd-stdin-10119.test.sh`
- `scripts/registry-delivery-change.sh` (header comment only)
- `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`

## Files to Create

- `plugins/soleur/test/lib/registry-gate-gh-stub.sh` (the shared refusing `gh` stub; not a `*.test.sh`, so no suite auto-glob picks it up as a test)

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled the technical forks on 2026-10-27, twice: first mechanism, failure shape, scope and the reading of #9149 (F1-F4), then after plan review the blob-compare-versus-content-arms alternative, the 404 simplification, the retry, the shared stub and the ADR note (G1-G5); all rows are in `decision-challenges.md`. It listed the risks folded into this plan: stale comment and doc text (rewritten), the cap-hit fixture mirroring PR #10501 (K2), the read-failure case (K6), attribution degradation after a cap hit (the verdict does not claim a PR it cannot prove), repeated red runs (existing owner-issue dedupe plus runbook), and the head-side race (the checkout is already pinned to the same SHA). The three-agent plan-review panel (DHH, Kieran, simplicity) ran on the draft; mechanical findings were applied, the technical forks it raised were ruled by the CTO, none was put to the operator. No Product, Marketing, Legal, Finance, Operations, Sales or Support implication: a CI gate and its tests, no user-facing surface, no regulated data, no spend.

## Non-Goals

- Changing the other fail-toward-delivering arms (no watermark, non-ancestor watermark, manual dispatch). They are not list-driven and the preflight still gates them.
- Replacing the file-list proxy for ranges below the cap (it is complete and exact there).
- Selecting `registry-render-delta.test.sh` on a workflow-only diff: deferred to #11325.
- Any `terraform apply`, any dispatch, any change to `zot-registry.tf` or the cloud-init template.

## Dependencies & Risks

- **Risk: the gate suite needs terraform.** The render-dependent rows (K3, K4, K5) SKIP locally without terraform and fail closed in CI; terraform 1.17.0 is installed locally (CI pins 1.10.5, as the existing suite already assumes). The terraform-free rows in the verdict suite always run.
- **Risk: replacing render-delta's stub.** The existing 29 rows must pass unchanged against the shared stub; the shared stub keeps the refusing contract (exit 64, refusal file) so a drift fails loudly.
- **Risk: `set -e` semantics.** Actions' default shell is `bash -eo pipefail`; the gate's own `set -uo pipefail` does not clear `-e`. Every failing command in the new arm sits in an `&&`/`||` list or a `|| { ... }` guard (probed under `bash --noprofile --norc -eo pipefail` while planning), and `lint-workflow-errexit-capture.py` is run to prove it.
- **Residual, accepted (#9149 keeps it):** a cap hit whose blobs differ and whose watermark render is unmeasurable still delivers (K5), the same as a non-truncated range today. It needs a render input to have really changed, so it is the honest "cannot prove unchanged" case, not the #10650 shape.
- **Risk: a real change is delayed.** A render input that really changed but whose blob read fails at a cap hit is not delivered until the API recovers or a manual dispatch runs; the run is red and the verdict names it. A manual dispatch delivers unconditionally, i.e. it replaces the host, which the runbook states. That is the intended trade (recoverable and visible, against an unnecessary outage of the sole pull path).
- **Dependency:** none blocking. Sibling work on PR #11287 (#10540) and PR #11322 is untouched; this branch edits none of their files.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- The gate's `INFRA/TF/VARS` definitions currently follow the cap block; the arm reads them, and under `set -u` an un-hoisted use aborts the step. Hoist, do not duplicate.
- `GITHUB_OUTPUT` lines written before an `exit 1` remain readable by later steps (the existing `watermark` output relies on it), but a line written after the exit never exists: mutation 7.
- The verdict step runs under `set -uo pipefail`: read the new env as `${GATE_UNPROVEN:-}`, and have the verdict harness export it set or empty.
- The `kind` marker regex everywhere is `kind=[a-z-]+`; `gate-unproven` fits. Do not use a digit or an underscore.
- The verdict arm must override `STATE`; the default `NOT_LIVE` sentence on a proven empty range would say "this run was not applied" or "NOT live", both false for an unproven range.
- The follow-through probe ignores an unlisted kind by design (`dispatcher-unknown-kind-ignored`); that is why the closed set must be extended in the same PR.
- Do not compute blob shas in the stub with `git hash-object`: a test that spawns `git` needs the constructed environment from `plugins/soleur/AGENTS.md`; the pure `sha1sum` form needs none.
- `gh api --jq` does not take `--arg`; the select filter is a static program.
- Never run `gh workflow run` to "try" the gate: the extracted body is exercised only through the stub.
