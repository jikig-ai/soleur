---
title: "origin-tls: record the per-colo H capture and its T2 outcome in the strict-flip runbook"
type: chore
date: 2026-11-23
slug: chore-origin-tls-h-capture-t2-addendum
branch: chore-12846-h-capture-evidence
issue: 12846
closes: 12846
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# origin-tls: record the per-colo H capture and its T2 outcome

Spec lacks valid lane: defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this branch.

## Overview

Task 6.2 of #12846. One PR on the existing branch and draft PR #13016 inserts one dated section into `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md`, immediately before the heading `#### What was NOT run before the flip`. The section records the H read already kept in commit `ee0e31379a` and the output of the pre-registered T2 recipe on that read.

The outcome is `inconclusive: positive-colo`. The p90 step keeps the label "provisionally attributed", the evidence bar for "attributed" is not met, and no cause is claimed. The PR closes #12846 and references the capture tracker #13003, which stays open.

## Research Reconciliation: Brief vs. Codebase

Each row was measured against the kept file or the runbook on 2026-11-23.

| Brief or issue says | Reality | Plan response |
|---|---|---|
| Facts to record list E and the read instant | R1 also requires O: "record E, O and the read instant". The loop does not print O | Record O=250 (main) and O=101 (archival), labelled as derived from the kept hour minus E (CTO item 1) |
| SEA `late_run=null` | The recipe scans only non-positive colos, so SEA's `null` means "not scanned". A direct scan finds sustained runs from 01Z and 02Z | Print `null (not scanned)`, and do not write that no judged colo has a late run (CTO item 4) |
| "Every figure is a sampled estimate" | Durations and request counts are sampled. Row, colo and hour counts are exact counts of the file | Scope the sentence to durations and the request counts behind them (CTO defect 3) |
| Bar not met because of other origin-path changes | True. The bar also requires "a matching mechanism read", and the runbook names no read as one | State both reasons (CTO item 4) |
| #12846 suggests the file name `<UTC date>-analytics-<subcommand>-216h.json` | The handoff loop names files by window end (CTO D5 in the 2026-11-19 addendum) | Keep the loop's names |
| Wrapper has no zone-status subcommand | Confirmed: the dispatch in `plugins/soleur/scripts/cloudflare-readonly.sh` has seven subcommands, none reads zone status | State it as written in the brief |

## Research Insights

**Premise Validation.** #12846, #13003 and #12931 are open, and draft PR #13016 is this PR. `collision-precheck.sh` reports #13016 alone for #12846 and nothing for #13003. When this was measured on 2026-11-23, `origin/main` was `6e491a9fd4`, and the wrapper is unchanged from it. Re-running the pinned four-line block on the kept main file printed the brief's line 1, 36 colos, 2 judged, and the SEA and IAD rows exactly. The file has 2264 rows, 216 hours, no null-colo row, and hours from 2026-11-03T12Z to 2026-11-12T11Z. The archival file has 2198 rows, `truncated: false`, on the same zone. Both named suites pass at baseline (96 and 63 cases). The read instants come from the loop's printed `read at` lines, recorded in the `ee0e31379a` commit message and the brief, and the files themselves do not carry them.

**Property List.**

1. The runbook records the H read: files, zone, window, row counts, read instants.
2. The runbook records the T2 outcome as an `Unverified:` line carrying the recipe's line 1 verbatim.
3. The label and the evidence bar are stated without claiming a cause.
4. The skipped zone-status check is stated plainly.
5. Everything already in the runbook stays byte-identical.
6. #12846 closes on merge, and #13003 does not.

**Cut List.**

- A sentence in the addendum saying the S1 marker is not yet posted: property 6 is carried by #13003 and its probe, and a dated line would go stale (CTO item 2).
- A new script or test for the additions-only property: the removal check under Phase 2 proves it with existing tools.
- A ready-to-post marker line in this plan: the Deadline paragraph, #13003 and the probe already define its format.
- An operator row for the marker in `decision-challenges.md`: `soleur:ship` files one `action-required` issue per operator row, which would duplicate #13003.

**Runbook readers and the limits they set on the new text.**

- `plugins/soleur/test/health-colo-falsification.test.sh` needs exactly one of each recipe and outputs marker line, and each run-block line exactly once. The addendum must not repeat them.
- `plugins/soleur/test/components.test.ts` collects rows matching `` ^\| `unverified - ``. The addendum must not start a table row that way.
- `scripts/lint-infra-no-human-steps.py` scans runbooks and plans for an actor word next to an infrastructure imperative.
- `.claude/hooks/ship-runbook-ssh-gate.sh` checks added runbook lines at `gh pr ready`.
- `scripts/markdown-lint.sh` needs blank lines around headings and tables and consistent table pipes.

**What merging triggers.** The changed paths match no path-filtered `push` workflow, so no `apply-*` workflow fires and no release is published. Of the eight workflows with no path filter (`ci`, `codeql-main-alert-gate`, `merge-bypass-audit`, `secret-scan`, two skill scans, `tenant-integration`, `vendor-pin-verify`), `tenant-integration` runs on a main push unless that push is a proven duplicate of the PR's green run. Its job seeds bot fixtures and runs `Apply migrations to dev` against the shared dev project. This PR adds no migration, and that step does not touch production. `Web Platform Release` also starts on every main CI completion through `workflow_run`; on a SHA that touches no deployable path, its release, migrate and deploy jobs are skipped, while its `verify-doppler-secrets` job still runs a read-only check that the prd secrets exist. `Post-Merge Monitor` also starts on that CI completion and skips, because it acts only on `[bot-fix]` commits, and `image-cve-verdict` starts when Web Platform Release completes and only reports on the image prod already serves. Merging needs none of the acts the standing limits reserve.

**Closing #12846 does not break the probe.** `scripts/lib/trusted-verdict.sh` reads comments with `gh issue view --json comments`, with no state filter, so a marker posted on the closed issue still counts.

**Learnings applied.**

- `knowledge-base/project/learnings/2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md`: the close parser ignores negation, so "does not close" followed by the tracker number closes the tracker.
- `knowledge-base/project/learnings/2026-09-17-evidence-verdicts-need-verbatim-provenance-not-summarized-attribution.md`: quote the recipe line verbatim.
- `knowledge-base/project/learnings/2026-11-19-a-verdict-covers-only-the-checks-that-ran-and-every-quoted-command-owes-its-required-inputs.md`: this is the SEA `late_run` case.
- `knowledge-base/project/learnings/2026-10-28-my-new-runbook-sentence-about-the-gate-was-false-and-a-job-key-allowlist-left-twenty-edits-green.md`: check each new sentence against its source.

**Community overlap.** None. No artifact was installed.

## Open Code-Review Overlap

None. The 96 open `code-review` issues were searched for the runbook path, its basename and the evidence file stem.

## Standing Limits

These are prohibitions on this pipeline, and none of them is a condition on merging this PR.

- No production apply, workflow dispatch or credential change without the owner's typed go.
- No `apply-web-platform-infra.yml` dispatch before #12931 lands.
- Do not post the `S1-HEALTHCOLO-CAPTURED:` marker on #12846. It needs the owner's typed go. When it is posted, it should name PR #13016 as well as the branch, because the branch may be deleted on merge.
- Leave #13003 open, with its label and directive unchanged.
- Do not retire the probe.
- Do not resolve review thread 1051496324.
- Never read or print a secret.

If merging ever turns out to need one of these, stop at the ready PR and say so.

## Implementation Phases

### Phase 1: insert the addendum

Read the runbook first. From the repository root, insert the block below and nothing else:

```bash
PLAN=knowledge-base/project/plans/2026-11-23-chore-origin-tls-h-capture-t2-addendum-plan.md
R=knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md
H='#### What was NOT run before the flip'
AH='##### Addendum 2026-11-22: the H capture and the T2 outcome (Ref #12846)'
A=$(mktemp); T=$(mktemp); rc=1
awk '/^````markdown$/ { f = 1; next } /^````$/ { f = 0 } f' "$PLAN" > "$A"
if [ "$(grep -cxF "$H" "$R")" = 1 ] && ! grep -qxF "$AH" "$R" && [ "$(head -n 1 "$A")" = "$AH" ] && [ "$(wc -l < "$A")" -eq 27 ]; then
  printf '\n' >> "$A"
  b=$(grep -nxF "$H" "$R" | cut -d: -f1)
  { head -n "$((b - 1))" "$R"; cat "$A"; tail -n +"$b" "$R"; } > "$T" && cat "$T" > "$R" && rc=0
else
  echo "refused: heading count, existing addendum, or block extraction" >&2
fi
rm -f "$A" "$T"; [ "$rc" -eq 0 ]
```

The text to insert:

````markdown
##### Addendum 2026-11-22: the H capture and the T2 outcome (Ref #12846)

Written 2026-11-23; records the 2026-11-22 reads. Additions-only: the addenda above, the recipe block and its sha256 are left as written. The durations and the request counts behind them are sampled estimates.

**The reads.** Both ran on 2026-11-22 through the H handoff loop in the 2026-11-19 addendum, from a fresh `origin/main` at `6e491a9fd4`. Both passed the loop's keep rules on zone `5af02a2f394e9ba6e0ea23c381a26b67`, each as one H=216 read, so no split was needed. The files are under `knowledge-base/engineering/operations/runbooks/evidence/`.

| Read | Read at | Evidence file | Window end E | Offset O | Hours | Rows | `truncated` |
|---|---|---|---|---|---|---|---|
| Main (the R1 window) | 2026-11-22T22:59:45Z | `analytics-health-colo-216h-end20261112T12Z.json` | 2026-11-12T12:00:00Z | 250 | 216 | 2264 | false |
| Archival (never a verdict input) | 2026-11-22T22:59:47Z | `analytics-health-colo-216h-end20261118T17Z.json` | 2026-11-18T17:00:00Z | 101 | 216 | 2198 | false |

R1 asks for E, O and the read instant. The read instants are copied from the loop's `kept <file>, read at <time>` lines, because the files do not carry them. The loop does not print O, so both values above are derived: the read instant's hour (2026-11-22T22:00:00Z) minus E. The main read printed `null_colo_rows=0 null_colo_qualifying=0`.

**The T2 outcome.** The pinned four-line block above ran on the main file only, and its hash check passed. The record, carrying the recipe's line 1 verbatim:

Unverified: Cloudflare analytics-health-colo (H) #12846, inconclusive: positive-colo; null_colo_rows=0 null_colo_qualifying=0

The file holds 36 colos: 2 judged and 34 not judged. The two judged colos:

| Colo | Qualifying hours before | Qualifying hours after | Baseline max (ms) | Change point | Positive | Late run |
|---|---|---|---|---|---|---|
| SEA | 29 | 27 | 514 | 2026-11-08T00:00:00Z | true | null (not scanned) |
| IAD | 49 | 45 | 342 | 2026-11-08T14:00:00Z | false | null |

**What this does and does not show.** SEA is positive. IAD is not, and has no sustained run from 01Z on, so the outcome is `positive-colo`. SEA's `null` means the recipe does not scan a positive colo, not that SEA has no late run. IAD is not flat: by a direct count from the file, not a recipe output, 25 of its 45 qualifying after-hours are above its baseline max, the first at 14Z. A per-colo shape cannot separate the flip from the v0.395.7 release deploy in the same hour, so this is still not "supported". The label on the p90 step stays "provisionally attributed", because every `inconclusive:` outcome leaves it in place. The evidence bar for "attributed" (CTO ruling, 2026-11-16) is not met: the window holds the other origin-path changes listed under "Other events in the window" in the 2026-11-19 addendum, and this runbook names no read as the matching mechanism read. No cause is claimed.

**Not run.** The 2026-11-19 addendum's "check the zone's status before the read" was not run, because the wrapper has no zone-status subcommand. The read's own `zone` field and the keep predicate are what showed the old zone was still readable at the read. They do not show the zone's Cloudflare status.
````

### Phase 2: verify

```bash
R=knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md
E=knowledge-base/engineering/operations/runbooks/evidence
F=$E/analytics-health-colo-216h-end20261112T12Z.json
BASE=$(git merge-base origin/main HEAD)
# 1. Removing the new lines gives the base file byte for byte, so this is a pure insertion right before the heading.
a=$(grep -nxF '##### Addendum 2026-11-22: the H capture and the T2 outcome (Ref #12846)' "$R" | cut -d: -f1)
b=$(grep -nxF '#### What was NOT run before the flip' "$R" | cut -d: -f1)
{ head -n "$((a - 1))" "$R"; tail -n +"$b" "$R"; } | cmp - <(git show "$BASE:$R") && echo PURE-INSERT
# 2. The recorded line equals a fresh run of the pinned recipe (check 3 pins its hash).
L=$(/usr/bin/env -i /usr/bin/jq -r -f <(awk '/^<!-- health-colo-r2-recipe:start -->$/ { f = 1; next } /^<!-- health-colo-r2-recipe:end -->$/ { f = 0 } f && /^```/ { g = !g; next } f && g { print }' "$R") "$F" | head -n 1)
[ "$L" = 'inconclusive: positive-colo; null_colo_rows=0 null_colo_qualifying=0' ] \
  && grep -Fxq "Unverified: Cloudflare analytics-health-colo (H) #12846, $L" "$R" && echo RECORD-MATCHES
# 3. The named suites. The exit status is the verdict: a floor failure can still print "0 failed".
for s in plugins/soleur/test/health-colo-falsification.test.sh scripts/followthroughs/health-colo-capture-12846.test.sh; do
  o=$(bash "$s" 2>&1); rc=$?; printf '%s\n' "$o" | tail -n 1; [ "$rc" -eq 0 ] && echo "SUITE-OK $s"
done
# 4. The two kept files are unchanged since the capture commit, and nothing else is pending in that directory.
git diff --quiet ee0e31379a -- "$F" "$E/analytics-health-colo-216h-end20261118T17Z.json" && [ -z "$(git status --porcelain -- "$E")" ] && echo EVIDENCE-UNCHANGED
```

CI runs the other two runbook readers (`cloudflare-readonly.test.sh`, `components.test.ts`) in the full battery: the two `.json` evidence files are outside the docs-only oracle lane in `scripts/ci-oracle-lane.sh`, so the heavy legs are not skipped.

### Phase 3: ship

The PR body needs these lines, each on its own line:

```text
Closes #12846
Ref #13003
```

The body must also say, in prose:

- The capture already ran, and the handoff loop must not be run again. The probe on #13003 keeps reporting ACTION REQUIRED until the marker exists.
- The marker is not posted by this PR and needs the owner's typed go, so #13003 stays open.
- Merging triggers no production apply and no release.

Never put a closing keyword next to `#13003`, in the title, the body or any commit message, even in a negated sentence. After the last `gh pr edit` and the last commit, run:

```bash
gh pr view 13016 --json closingIssuesReferences --jq '[.closingIssuesReferences[].number]'   # must print [12846]
D=$(git diff --name-only origin/main...HEAD)
allow='^knowledge-base/(engineering/operations/runbooks/(origin-tls-strict-flip\.md|evidence/analytics-health-colo-216h-end202611(12T12|18T17)Z\.json)|project/(constitution\.md|glossary\.md|plans/(archive/)?[^/]*chore-origin-tls-h-capture-t2-addendum-plan\.md|specs/(archive/[0-9-]+-)?chore-12846-h-capture-evidence/[^/]+|learnings/.+\.md))$'
printf '%s\n' "$D" | grep -qxF knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md && ! printf '%s\n' "$D" | grep -qvE "$allow" && echo SCOPE-OK
```

`soleur:compound` can edit `plugins/soleur/{skills,agents,commands}/` on this branch. Never add those paths to `allow`: any `plugins/soleur/**` change makes the merge publish a plugin release (the `version-bump-and-release.yml` filter covers the whole tree, `docs/` and `test/` included), and a change outside `docs/` and `test/` also triggers a web-platform deploy. If `SCOPE-OK` does not print, move the out-of-scope edit to its own PR from `origin/main`, drop it from this branch, and re-run this block.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md`: one inserted section.

## Files to Create

- `knowledge-base/project/plans/2026-11-23-chore-origin-tls-h-capture-t2-addendum-plan.md`
- `knowledge-base/project/specs/chore-12846-h-capture-evidence/tasks.md`
- `knowledge-base/project/specs/chore-12846-h-capture-evidence/decision-challenges.md`
- `knowledge-base/project/specs/chore-12846-h-capture-evidence/session-state.md`

The two evidence files are already on the branch in `ee0e31379a`.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing in the product. The change is text in an internal runbook. A wrong record would mislead a later origin-TLS decision, which is why the figures are checked against the kept file.

**If this leaks, the user's data is exposed via:** no new vector. The evidence files hold hourly colo codes, counts and durations for `/health`, with no user identifier. The zone id is public.

**Brand-survival threshold:** none

threshold: none, reason: the diff is limited to an internal runbook, committed aggregate `/health` evidence and planning files, and matches no sensitive path.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "one PR whose body says "Closes #12846" and "Ref #13003"" [brief] | Phase 3 | mapped |
| 2 | "adding an additions-only dated section" [brief] | Phase 1, Files to Edit | mapped |
| 3 | "placed immediately before the heading "#### What was NOT run before the flip"" [brief] | Phase 1, Phase 2 check 1 | mapped |
| 4 | "Earlier addenda stay byte-identical, and the recipe block and its sha256 must not change." [brief] | Phase 2 checks 1 and 3 | mapped |
| 5 | "Facts to record (measured this session)" [brief] | Phase 1 text | mapped |
| 6 | "Record the outcome as an "Unverified: Cloudflare analytics-health-colo (H) #12846, ..." line carrying that recipe line 1." [brief] | Phase 1 text, Phase 2 check 2 | mapped |
| 7 | "State this plainly in the addendum." [brief, the zone-status check] | Phase 1 text, "Not run" | mapped |
| 8 | "run plugins/soleur/test/health-colo-falsification.test.sh and scripts/followthroughs/health-colo-capture-12846.test.sh, and confirm the diff against origin/main is additions-only in the runbook" [brief] | Phase 2 | mapped |
| 9 | "Standing limits (hard)" [brief] | Standing Limits | mapped |
| 10 | "One sanctioned read is committed as an evidence file, and the runbook records whether the p90 step meets the evidence bar" [issue #12846] | `ee0e31379a`, Phase 1 text | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Runbook section | asks 2-7 | asked |
| Phase 2 checks | ask 8 | asked |
| Closing-reference and scope checks in Phase 3 | asks 1 and 9 | asked |
| O values in the record | — | inferred — justification: the pre-registered R1 ruling requires E, O and the read instant to be recorded |
| IAD direct count (25 of 45) | — | inferred — justification: CTO item 4, so that "not positive" is not read as "flat" |
| Plan, tasks and decision-challenges files | "Persist every decision as a row" | asked |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base`
- Planned files: 5, plus the 2 evidence files already on the branch | Estimated changed lines: 380
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge

- [x] Phase 2 prints `PURE-INSERT`.
- [x] Phase 2 prints `RECORD-MATCHES`.
- [x] Phase 2 prints `SUITE-OK` for both named suites.
- [x] Phase 2 prints `EVIDENCE-UNCHANGED`.
- [ ] The `closingIssuesReferences` check in Phase 3 prints `[12846]`.
- [ ] The PR body carries the three prose statements in Phase 3.
- [ ] Phase 3 prints `SCOPE-OK`.

### Post-merge

- [ ] `gh issue view 12846 --json state --jq .state` prints `CLOSED`.
- [ ] `gh issue view 13003 --json state,labels` shows `OPEN` with the `follow-through` label while #12846 has no trusted marker. If the owner authorized the marker, `CLOSED` by the sweeper is expected, and the tracker is not reopened.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled on four items, recorded in `knowledge-base/project/specs/chore-12846-h-capture-evidence/decision-challenges.md`. It found one false sentence in the first draft (a claim about SEA late runs), an incomplete evidence-bar reason and an over-broad sampling sentence. All three are fixed in the Phase 1 text.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6.
- The recipe's `late_run` is `null` for a positive colo because the recipe does not scan it. Do not read it as "no late run".
- Until the marker exists, the probe on #13003 reports ACTION REQUIRED, and through 2026-11-24 it says "run the H handoff loop now". The capture has run. A re-run would still send the read, then refuse to overwrite the kept files.
