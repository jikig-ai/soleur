# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-fix-merge-queue-stall-triage-headsha-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking (no plugins/soleur/test/run-all.sh; suite registered via test-all.sh glob, suite-shard-legs.tsv, test-affected-paths.sh).

### Decisions
- Assertion is a new arm in structural_check (real-workflow row S0); mutation rows MT1-MT5 plus must-pass PT1; EXPECTED_PASSES floor set from observed count.
- Order: red assertion first, one-token edit, then git rm the probe after census.
- PR body: Closes #12362, Ref #9927 only; no agent --admin; Guard 1 = merge_group test leg.
- Postmerge: remove follow-through label on #12362; Ref-only comment on #9927; operator notes only on #12272.

### Components Invoked
soleur:plan, soleur:deepen-plan, learnings-researcher, code-simplicity-reviewer, kieran-rails-reviewer

## Review Phase (PANEL_SHA d98ae579f0, tier none, 9 seats)

dedup: ~28 raw -> 9 unique (structural-cause roll-up: the new guard reads one physical line of one template; most findings are different instances of "the arm's reach is narrower than the property it names")

| canonical defect key | reporting seat(s) | disposition |
|---|---|---|
| MT3 killed by the older agent-runnable arm, so it exercises no new code (zero-members branch unreachable) | pattern, architecture, code-quality, test-design, simplicity | fixed: MT3 replaced by a left-extended lookalike row (xheadSha); floor stays 166 |
| selector copied into three jq programs (drift) | pattern, code-quality, simplicity | fixed: one `local sel`, three checks reuse it |
| check-3 REASON names a cause nothing measured; check-2 REASON misleads on wrapped / `--json=` forms | code-quality, architecture, test-design | fixed: REASON strings state only what is measured |
| header does not mention the new arm | pattern | fixed: one header sentence |
| plan text: "TRANSIENT noise" wrong (sweeper logs an ERROR for ~14 daily runs); MT3/MT4 wording stale | git-history, code-quality | fixed in plan |
| three sibling surfaces print the same command without headSha (pre-existing) | structural-enumeration | CTO ruling: widen PR to the three files (see decision-challenges.md) |
| PR body is a placeholder without `Closes #12362` | git-history | ship sets it; asserted via closingIssuesReferences |
| collapse the three jq checks into one; drop MT1/MT5/PT1 | simplicity | declined: per test-design's per-check kill table each check and row is the sole kill for a distinct mutant, and distinct REASONs keep attribution accurate |
| backtick-closed list false-reds; arm scans comment lines (S8 needs two simultaneous edits); decoy-first line; `--jq`/`--limit`/`--repo` unguarded | architecture, code-quality, test-design, structural-enumeration | accepted: fail-safe or needs deliberate double edit; fixing would add unpinned guard code |
| issue #12362 attributes the gap to #12295; code-quality said the plan's #11681 is stale | git-history, code-quality | git-history is right (full-history check; the shallow clone made #11784 look earliest): plan correct, noted in PR body |
| pre-existing `[^#\n]` ERE in the drain check at the existing line 187 can never fire | pattern | out of scope, noted for the PR body |

### Fix round 1 (FIX_PANEL_SHA 4a0fd0d68e, 7 seats: code-quality, pattern, architecture, performance, agent-native, test-design, structural-enumeration)

| canonical defect key | reporting seat(s) | disposition |
|---|---|---|
| first-panel fixes (MT3, shared selector, REASON strings, header, sibling edits, accept re-key) | all seven | verified closed; no fix introduced a defect |
| `merge-queue-dequeue.md:28` prints the same list and says "correlate by headSha/createdAt" (the lead's earlier "no headSha claim" premise was wrong) | architecture, structural-enumeration (code-quality noted it) | CTO re-ruling: add `headSha,` in this PR (fifth site of ADR-270's "five pr-N triage sites") |
| the four sibling surfaces carry no headSha pin (a future removal passes every suite) | structural-enumeration | declined for this PR per the CTO (separate concern); noted here |
| `createdAt` is named as a correlation key but not requested in the printed lists | agent-native | accepted: the ruling covered headSha only |
| ratchet needs `--base origin/main` locally (default `HEAD^1` reads accept-unattributed on an accept-only commit) | code-quality, structural-enumeration | noted: use `--base origin/main` |

## Operator Constraints
- Ref #9927 only, never Closes; operator-held items untouched; no operator technical forks.
