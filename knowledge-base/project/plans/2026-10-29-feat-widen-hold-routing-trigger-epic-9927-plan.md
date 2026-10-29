---
title: "feat: widen the go hold-routing trigger and classify the holds on epic 9927"
date: 2026-10-29
slug: widen-hold-routing-trigger-epic-9927
branch: feat-one-shot-hold-routing-trigger-9927
issue: 9927
closes: none
type: feat
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# feat: widen the go hold-routing trigger and classify the holds on epic 9927

## Overview

Two changes in one pull request, both referencing epic 9927 (`Ref #9927` only; never a closing keyword; the epic stays open until the owner closes it). The owner approved this scope on 2026-10-29.

1. **Widen Step 1.5 of `plugins/soleur/commands/go.md`.** Today the hold-routing paragraph fires only on a literal `HOLDS:` line, an `OWNER-GATED` heading, or a `## Operator Holds` section whose `- Hold:` item carries a `Gate:` line or begins `Operator-reserved:`. A resume brief that cited an open epic and listed "Owner-side items" and "Blocked by the read-only rules" had none of those, so the step fell through and the session classified the items itself instead of spawning the CTO. The widened trigger recognises a label-plus-items list of owner-side, blocked or waiting items that belongs to an open epic, found in the brief or in the owner-authored body of that epic, and routes it to the CTO for **classification only**. Classification routes; it never discharges a hold, never records a delegation, and every existing fail-closed rule is unchanged.
2. **Give epic 9927 a `## Operator Holds` section** (a post-merge append to the issue body, as the CTO ruled) in which every hold carries a class: technical (the CTO rules), an operator-only category, or a date wait. The draft is committed as a record in this feature's spec directory.

The change is prose outside the eval-gated `go-routing` block, plus the static-pin guard that pins that prose, plus one-sentence pointers in two sibling documents. No script, no delegation grammar, no verifier, no production act.

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality (checked 2026-10-29) | Plan response |
|---|---|---|
| "every harness mirror that carries the same paragraph: codex, cursor, devin, opencode, .grok/commands/go.md - find them with grep for 'Hold routing'" | `git grep -il 'hold routing'` finds `plugins/soleur/commands/go.md` only (plus its two tests and archived KB files). `.grok/commands/go.md` is a symlink onto `commands/go.md`; `opencode/commands/go.md` is a 279-byte pointer; the codex, cursor and devin `go` skills are 8 to 13 line shims; `skills/go/SKILL.md` says "the AUTHORITY is `commands/go.md`". None restates the paragraph. | Edit `go.md` only. AC: the same grep, run after the edit, still lists only `go.md` as a holder. No mirror edit. |
| "plus the test that pins it, e.g. plugins/soleur/test/go-session-gates.test.sh" | The pinning test is `plugins/soleur/test/go-hold-routing.test.sh` (Guard 6 of the standing-delegation plan). `go-session-gates.test.sh` has no hold-routing assertion (its "hold" hits are unrelated English). `cto-interface-selector.test.sh` derives the `Own the epic` cue from the paragraph (`_go_para`) and gains one row. | Extend `go-hold-routing.test.sh`; add one row to `cto-interface-selector.test.sh`; leave `go-session-gates.test.sh` untouched. |
| "any eval-gate fixture for the go-routing block per gated-skills.json" | `gated-skills.json` gates only the text between the `go-routing` start and end markers. The hold paragraph sits outside them and `go-hold-routing.test.sh` already pins the block byte-identical to the merge base. `eval-gate.cjs` prints `accept:true, reason:"no gated-block change"` with no API spend when the block is unchanged. | No corpus task and no paid run. Phase 3 proves the no-op with `--check` and a no-op candidate run. |
| "the ci-head-verdict.sh gap (a required context that never reported leaves a PR un-enqueued while the verdict reads green; the CONCUR gate dissented on the proposed trigger)" | `plugins/soleur/scripts/ci-head-verdict.sh` contains no read of required status contexts, rulesets or merge state (grep for `required_status`, `ruleset`, `contexts`, `statusCheckRollup`, `mergeStateStatus`, `merge_group` returns nothing); it decides from the `ci.yml` `pull_request` run for the head. The consequence and the CONCUR dissent are not in the repository. | Classified `technical` in the epic section; the hold text says what was checked and marks the rest "from the 2026-10-29 resume brief, not reproduced". Not ruled or built here. |
| "correcting body item 7, which still lists the dropped scratch-volume proof" | Confirmed: the body's item 7 reads "optional scratch-volume proof that detach works under delete protection"; the comments of 2026-10-26 and 2026-10-28 say the proof was not started and the body "was not edited again". | Class `technical`. The CTO ruled the correction can only be an appended note, because the body edit must keep the original as an exact prefix. |
| "the A6 record ... lives under knowledge-base/legal/audits/ per the runbook table ..., not inside the runbook" | Confirmed: runbook row A6 says "a record under `knowledge-base/legal/audits/`, linked from #10382 and #10136, written by the owner and attested separately by the CLO agent"; the 2026-10-26 comment calls the member list "the pending A6 record". The two statements differ in what the record is. | The A6 location is written once in the console-check hold (runbook row wins) and "reconcile where the A6 record lives" stays a `technical` hold for the CTO. |
| "the off-project ciphertext copy decision (money; deferred by CTO ruling with trigger the earliest of 2027-01-08, a written Hetzner answer ..., or the next host replace)" | Confirmed in body item 1b and the 2026-10-28 comments; ADR-282 addendum of 2026-10-28 records it. | Seeded as written. |
| "the follow-through re-look of #10972 from 2026-11-09T00:00Z" | Confirmed: #10972 is open, its follow-through directive is `script=scripts/followthroughs/orphan-sweeps-relook-10972.sh earliest=2026-11-09T00:00:00Z`; the script exists on main. | Seeded as a `waiting (2026-11-09T00:00:00Z)` hold. |
| (CTO finding, not in the brief) the section being added to #9927 already triggers the existing flow | The body's `Operator-reserved:` holds satisfy the CURRENT "Production holds" definition. Without a further clause, every run citing #9927 would go through `Own the epic`, the CTO would return zero Scope items (every hold is non-delegable), and an attached session would ask a delegation question with nothing to delegate; a headless run would file an empty `Standing-delegation epic: #9927` issue. | Add the zero-Scope clause (Phase 1, decision T7) and pin it. |

## Research Insights

**Premise validation (2026-10-29).** #9927 is OPEN, authored by `deruelle` (`author_association` MEMBER), body 3698 characters, no `Operator Holds` section. #10972 is OPEN. PR 11476 is the draft PR for this branch. The collision pre-check reported only that PR (exit 10, no foreign runs). No cited blocker is closed. The proposed mechanisms were checked against the ADR corpus: ADR-289 (standing delegation) already records, in its 2026-10-22 addendum, that `go.md` Step 1.5 is the authority for the trigger and that an earlier widening was recorded as an addendum; nothing there rejects a classification route.

**Property List** (what the work must buy, one observable outcome each):

- P1. A brief or owner-authored open epic body with a label-plus-items list of owner-side, blocked or waiting items, and an epic reference, causes the CTO to be spawned for classification instead of the session classifying.
- P2. Input without an epic reference, without such a list, or whose epic text is outsider-authored or closed does not trigger; a bare "ask the operator" still routes normally.
- P3. Classification never discharges a hold, never records a delegation, never renders one, and leaves every existing fail-closed rule in place.
- P4. A list in which nothing is delegable raises no delegation question and files no `Standing-delegation` issue.
- P5. Epic 9927 carries a section in which every hold has a class, owner-only holds are `Operator-reserved:`, and the section triggers the route.
- P6. The change is detected if any property above regresses (guard) and does not demand a paid eval run.

**Cut List** (mechanism -> property -> what already covers it):

- A new `Classify holds` CTO interface in `cto.md` -> P1 -> the existing Rule interface (selector rule 3, `Item <id>:` multi-row output) already returns per-item rulings; CTO ruling T2.
- A deterministic trigger script (`hold-trigger.sh`) -> P1/P2 -> the routing is model-read prose by design (Guard 6 pins the prose); a script would be a second authority for "the one authority for the trigger" and a copy that can drift.
- A plan/spec file as the durable home of the epic section -> P5 -> the issue body (already source 2 of the trigger); a file added by this PR is archived by ship and then rejected by the `/archive/` path rule; CTO ruling T1.
- An eval-corpus task for the new trigger -> P6 -> the paragraph is outside the gated block; the block-hash anchor already proves no gated change.
- Ruling the four CTO-to-rule items, adding `third-party system` to the closed category list, editing ADR-282 -> out of scope by the brief; classified only.

**Institutional learnings applied** (from `knowledge-base/project/learnings/`):

- `workflow-patterns/2026-10-12-the-closing-message-was-the-third-carrier-the-rule-had-no-reader-for.md` (2026-10-19 recurrence section): the current tight trigger was a deliberate response to courtesy-closer false positives. The widening reverses part of it, so the plan keeps must-not-route fixtures (a line that only names the CTO, a prose sentence, a label with no items) and states the trigger as a closed vocabulary.
- `workflow-patterns/2026-10-14-a-briefs-own-wording-was-the-fourth-carrier-of-the-technical-fork-rule.md`: lexical cues need must-allow rows; a per-item loop stalled on a large input. The matcher is a single linear awk pass and one fixture carries 200 items under a time cap.
- `workflow-patterns/2026-10-15-the-founder-said-the-cto-owns-the-decision-and-soleur-users-are-not-technical.md`: a hold is a checkable predicate or a person's decision; classification must not imply authorization (clause P3).
- `workflow-patterns/2026-10-22-a-delegability-claim-nobody-ran-through-the-verifier-and-fixes-that-each-needed-a-cold-run.md`: `gh issue view --json authorAssociation` does not exist (use `gh api ... author_association`); hand-copied regex mirrors stay green when the source changes. The matcher derives its vocabulary and author set from the paragraph at run time instead of restating them.
- `2026-09-18-the-measured-facts-my-resume-brief-handed-me-were-the-defects.md`: brief facts are inherited, not measured. Every seeded fact was re-checked (table above); the one that could not be (CONCUR dissent) is marked as such in the hold text.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: close the deletion direction too; the mutation matrix below deletes each new cue and reverts to the old trigger.
- `2026-05-12-gh-issue-edit-parallel-file-write-race.md`: build the new body file first, then run the issue write in a separate call.

## Open Code-Review Overlap

None. Checked 2026-10-29: no open `code-review` issue body names `plugins/soleur/commands/go.md`, `plugins/soleur/test/go-hold-routing.test.sh`, `plugins/soleur/test/cto-interface-selector.test.sh` or `plugins/soleur/skills/one-shot/SKILL.md`.

## Technical Rulings (CTO, 2026-10-29)

All forks were ruled by `soleur:engineering:cto` in one batched spawn and are recorded as rows T1 to T9 in `knowledge-base/project/specs/feat-one-shot-hold-routing-trigger-9927/decision-challenges.md`. Summary:

- **T1 location:** the issue body, appended post-merge, with a read-back proving the original body is an exact prefix.
- **T2 route:** the existing Rule interface, prompt never starting `Own the epic`; per-item output; no cto.md change.
- **T3 structure:** closed vocabulary `Owner-side`, `Open owner items`, `Blocked by`, `Blocked`, `Waiting on`, `Waiting for`; label (heading, bold line, or colon-terminated plain line) plus at least one open item in the same block; fences, quoted lines and done-headed blocks stripped; the list belongs to the OPEN epic the brief cites.
- **T4 tests:** static pins plus a matcher derived from the paragraph, run over synthesized fixtures, ten mutation rows, raised floor (the plan-review consolidation reduced the first draft's 13 fixtures and 11 rows to 8 fixtures and exactly ten rows).
- **T5 class carrier:** `- Hold: [Operator-reserved:] <words>` plus an indented `  Class: <cell>` line.
- **T7 zero-Scope clause (one bullet, both session modes)** (not in the brief; the CTO's finding that the new section would otherwise cause a bogus ask).
- **O1 (operator, scope):** the closed category list has no `third-party system`; the owner's own wording is used on the two Hetzner holds and the word is NOT added to the list. Flagged for the owner in the PR body.

## Implementation Phases

### Phase 1 - Edit the Step 1.5 paragraph (`plugins/soleur/commands/go.md`, outside the markers)

Work test-first (see Phase 2): add the failing pins, then make the prose satisfy them. Every sentence currently pinned by `go-hold-routing.test.sh` must survive byte-for-byte (none is re-worded; the two sentences touched below keep their pinned phrases). The paragraph is extracted by `para_awk` up to the next line that starts with `#` or a gate marker, so the new bullets must be single-line list items and must hold no fenced block and no line starting `#`. Draft wording follows; the implementer may rephrase but must keep every quoted pin phrase intact.

1. **Routing sentence** (second sentence of the paragraph): keep `routes only when ... BOTH an epic reference (`#N`) and a structured list of operator holds` as is, and add after the clause ending "...defined per the List source bullet below)": "The one exception is the classification-only form of the Classification list bullets below."
2. **Prose sentence** inside the List source bullet: keep `Prose ("after the soak", "waiting on") never counts as a hold list,` exactly, and add a separate sentence right after the bullet's last sentence: "A sentence counts as a classification list only through the label-plus-items structure of the Classification list bullets." (two sentences, not one long clause; the pins `never counts as a hold list` and `a closed epic never triggers, and` are untouched).
3. **Two new bullets, placed between the List source bullet and the Headless bullet** (trigger, then route; a short pair instead of one 350-word bullet):

   > - **Classification list: trigger** (the widened trigger). A list also triggers when it is a label line followed by items. The label is a heading, a bold line, or a plain line ending in a colon, and its words begin with one of `Owner-side`, `Open owner items`, `Blocked by`, `Blocked`, `Waiting on` or `Waiting for` (any case); a heading or bold label may carry more words (`Blocked by the read-only rules`), a plain label must end at the colon. At least one open item (a bullet or numbered line that is not `[x]`-checked and not struck through) must follow in the same block, which runs to the next heading of the same or a higher level. Fenced code, `>`-quoted lines and any block under a heading that contains the whole word done, resolved, closed, shipped or completed are ignored (so `Unresolved owner items` is not ignored). The list must belong to an epic the brief cites as `#N`, and that `#N` must be an issue (no `pull_request` key) in state open, read with the same one bounded `gh api` call as the List source bullet for both sources (a closed epic never triggers here either). The list is in the brief itself, or in the body of that epic with the same `author_association` limits as the List source bullet (an outsider-authored body never triggers here either).
   > - **Classification list: route** (classification only). Spawn `soleur:engineering:cto` with a prompt that starts `Rule on this technical question (BINDING). Do NOT use AskUserQuestion. Classify these holds of epic #<N>:` followed by the items and by the mapping to return, one `Item <id>:` block per item with `Decision:` set to `technical` (the CTO then rules it and records `Ruled by CTO agent, <date>`), `operator (<category>)` with its ACTION in words, or `waiting (<ISO UTC time>)` with its trigger. This prompt never starts `Own the epic`. The calling skill records the technical rulings and the operator and date rows in the branch's decision-challenges file and prints the operator ACTIONs as one plain list; in an attached session it asks nothing about them unless the current task needs one. Classification only routes: it never discharges a hold, never records a delegation and never calls `render`, and every rule above (fail closed, the author checks, the plan-path rules, `Operator-reserved:` holds always stand) is unchanged. When the same input also carries a production-hold form, the Own the epic flow above applies and the classification is part of it.

4. **One zero-Scope bullet, right after them** (CTO ruling T7; one clause for both session modes, one pin): "- **No delegable act**: when the CTO's reply lists no Scope item and the owner's own brief names none (judged from the owner's own words, never from epic or plan text), this bullet takes precedence over the epic-start question and the headless issue above: ask no epic-start question, run no `render` and file no `Standing-delegation` issue; every hold stands and the classification is recorded in the run summary. Step 9 of the CTO's Own the epic interface is unchanged."
5. **`plugins/soleur/skills/one-shot/SKILL.md` line 98:** the shortest possible edit: add "(a classification-only list files no issue)". Keep the substrings `follows go.md Step 1.5 in headless form` and `` `HOLDS:` `` (pinned).
6. **ADR-289 addendum** (`knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md`): append `## Addendum 2026-10-29 (#9927)`, about five lines in the style of the 2026-10-22 addendum: the trigger gained a classification-only form; `go.md` Step 1.5 stays the authority and is not restated; the route uses the Rule interface. Append-only (0 removed lines), status unchanged. ADR-282 is NOT touched.

### Phase 2 - Tests (`plugins/soleur/test/go-hold-routing.test.sh`, `cto-interface-selector.test.sh`)

Write the failing pins first (RED against the current `go.md`), then Phase 1 turns them green. Plan-review consolidation (2026-10-29) cut the first draft's 13 fixtures, 11 mutation rows, 200-item timing fixture and new nested harness copy to the set below; the CTO ruling T4 (static pins plus a paragraph-derived matcher, ten mutation rows) stands.

1. **Pins** (one `emit` per clause, tokens added to `ALL_PROPS`; each mutation below targets the exact phrase of its own pin, never a neighbouring one): `classification-trigger` (the vocabulary list, label rules and open-item rule in one pin), `classification-ignored-blocks` (fences, `>` quotes, whole-word done headings), `classification-open-epic-only` (`must be an issue (no \`pull_request\` key) in state open`), `classification-author-limits` (`an outsider-authored body never triggers here either`), `classification-route` (the prompt opener `Rule on this technical question (BINDING)`), `classification-prompt-not-own-the-epic` (`This prompt never starts \`Own the epic\``), `classification-only` (`never discharges a hold, never records a delegation and never calls \`render\``), `classification-both-forms` (`the classification is part of it`), `prose-amended` (`A sentence counts as a classification list only through the label-plus-items structure`), `zero-scope` (the whole No delegable act bullet, one pin).
2. **Derived matcher** (decision T4). Inside `evaluate()`, from the paragraph under test, extract the vocabulary (the backticked tokens between `begin with one of` and `(any case)`) and the author set (the existing sentence `its \`author_association\` is OWNER, MEMBER or COLLABORATOR`). `would_route <brief> <body-json|none>` is one linear `awk` pass that implements ONLY what the fixtures exercise: a label line from the vocabulary, an open item under it, a `#N` in the brief, and for a body source `author_association` in the extracted set and `state` open. Fence, quote, done-heading and prose rules are pinned as prose (item 1), not re-implemented. An empty extraction makes every positive fixture fail (fail closed, never vacuously green). Fixtures are synthesized inline (heredocs), never real briefs (`cq-test-fixtures-synthesized-only`):

   | Fixture | Expected | Token on failure |
   |---|---|---|
   | measured shape, synthesized: `Resume #123.` then `Owner-side items:` with two items and `Blocked by the read-only rules` with one item | route | `fx-positive-brief` |
   | brief `Resume #123 and continue`; open epic body, MEMBER, a single `## Waiting on` heading with one item | route | `fx-positive-body` |
   | `OWNER-SIDE ITEMS:` re-cased with numbered items (the must-PASS row that is not the canonical) | route | `fx-positive-variant` |
   | `ask the operator before you continue`, no epic, no list | no route | `fx-negative-bare-ask` |
   | label and items, no `#N` anywhere | no route | `fx-negative-no-epic` |
   | body authored by `CONTRIBUTOR` with a valid list (the outsider case) | no route | `fx-negative-outsider-body` |
   | cited epic in state closed (brief source and body source) | no route | `fx-negative-closed-epic` |
   | a line naming `soleur:engineering:cto` as the decider of forks, nothing else (2026-10-19 courtesy closer) | no route | `fx-negative-cto-line` |

3. **Ten mutation rows** (each uses `mrow`, which also asserts the mutation landed; this is the one list the Guard Contract refers to): (1) strip the two Classification bullets (revert to the old trigger) -> RED `classification-trigger` and `fx-positive-brief`; (2) widen the author set (`OWNER, MEMBER or COLLABORATOR` gains `CONTRIBUTOR or NONE`; a second member after a compliant first) -> RED `fx-negative-outsider-body`; (3) invert the author handling for the widened source (`never triggers here either` -> `triggers here too`) -> RED `classification-author-limits`; (4) drop the epic-reference requirement (`cites as \`#N\`` removed) -> RED `fx-negative-no-epic`; (5) let a closed epic trigger (`in state open` removed) -> RED `classification-open-epic-only` and `fx-negative-closed-epic`; (6) delete the vocabulary label `Waiting on` -> RED `fx-positive-body`; (7) the classification prompt may start `Own the epic` (`never starts` -> `may start`) -> RED `classification-prompt-not-own-the-epic`; (8) the route may discharge a hold (`never discharges a hold` inside the route bullet -> `may discharge a hold`) -> RED `classification-only`; (9) delete the No delegable act bullet by its unique substring `**No delegable act**` -> RED `zero-scope`; (10) the dispatch row: rename `begin with one of` so the vocabulary extraction is empty -> RED `classification-trigger` and every positive fixture (the matcher must fail closed, never report 0 checked). The mutation that strips a bullet uses the bold substrings `**Classification list: trigger**` and `**Classification list: route**`, never the bare words "Classification list", which also appear in the routing and prose sentences.
4. **Harness row:** extend the existing H4 (it already copies the suite, deletes one `emit` and requires the copy to go RED) to delete a second emit, the `fx-negative-outsider-body` one, in the same nested copy and require RED on the outsider row too. No new nested copy. Both branches of the extended H4 do `nrows++` and `ck`.
5. **Floor:** run the suite green once, then set `ABSOLUTE_FLOOR` (212 today) to the actual green-run count with zero slack, in the same commit as the rows (a floor written ahead of a count is the defect).
6. **`cto-interface-selector.test.sh`** (kept because the CTO's own F2 ruling asked for this pin): derive the classification cue from the `go.md` paragraph the way `GO_OWN_CUE` is derived, assert it is non-empty (`-n`, as for `GO_OWN_CUE`), add one `add_caller 'go hold classification' rule "<cue> #9757 ..."` row, and raise that file's own `ABSOLUTE_FLOOR` (167 today) by exactly the added assertions.
7. **Run:** `bash plugins/soleur/test/go-hold-routing.test.sh`, `bash plugins/soleur/test/cto-interface-selector.test.sh`, `bash plugins/soleur/test/go-routing-table-parity.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`. Local gates that queue behind sibling runs are not waited for beyond their timeout; CI is the gate and the PR body says so.

### Phase 3 - Eval gate (the go routing block is eval-gated)

The edit is outside the `go-routing` markers, so the gate must be a no-op; prove it rather than assume it. The block-hash anchor row of `go-hold-routing.test.sh` is the standing proof (the block is byte-identical to the merge base); CI runs `eval-gate.test.sh` and `registry-completeness.test.sh`.

1. `node plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs --check plugins/soleur/commands/go.md` -> `gated:true, target:go-routing`.
2. Copy the edited `go.md` to a temp path and run `node plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs --target go-routing --candidate-file <temp copy>` -> `{"accept":true,"reason":"no gated-block change"}`, exit 0, no API call (the short-circuit runs before any key or task is required). Record the output line in the PR body.
3. No row is added to `tasks/go-routing.jsonl` and `gated-skills.json` is untouched. If the block hash differs, the edit leaked inside the markers: revert; do not run the paid eval.

### Phase 4 - Epic 9927 `## Operator Holds` (post-merge GitHub write)

The committed draft is `knowledge-base/project/specs/feat-one-shot-hold-routing-trigger-9927/epic-9927-operator-holds-draft.md`, a record inside a fenced block. Ship archives that spec directory before the merge, so after the merge the file is read from `origin/main` at its archived path: resolve it with `git ls-tree -r --name-only origin/main knowledge-base/project/specs/archive/ | grep 'feat-one-shot-hold-routing-trigger-9927/epic-9927-operator-holds-draft.md$'` (exactly one match, else stop). The edit to the issue is a GitHub write, scheduled **after the merge** (so the section lands with the trigger that reads it), and is a named action of the shipping agent, run through `gh` as the logged-in owner identity under the owner's approval of 2026-10-29 for exactly this scope:

1. Read the raw body: `gh api repos/jikig-ai/soleur/issues/9927 > "$SCRATCH/issue.json"`, then `jq -j .body "$SCRATCH/issue.json" > "$SCRATCH/orig.txt"` (`-j` adds no trailing newline) and note `.updated_at`. Require `orig.txt` non-empty. Never print the body.
2. Build `"$SCRATCH/new.txt"` = the original bytes + one blank line + the text between the fence lines of the draft (no re-flow).
3. Abort unless `cmp -n "$(wc -c < "$SCRATCH/orig.txt")" "$SCRATCH/orig.txt" "$SCRATCH/new.txt"` succeeds (original is an exact prefix) and the appended section holds `^- Hold:` = 10, `Operator-reserved:` = 5, `Class: technical` = 4, `Class: waiting` = 1, `Class: operator` = 5.
4. In a separate call (parallel-file-write race learning), re-read `.updated_at` and abort if it moved since step 1; then `gh api -X PATCH repos/jikig-ai/soleur/issues/9927 -F body=@"$SCRATCH/new.txt"`.
5. Read back the same way and require: the original is still an exact prefix, `.state == "open"`, `.author_association == "MEMBER"`, the section heading present. Print only counts and these booleans.
6. Nothing else on the issue is changed: no label, no comment, no close.

The resulting section fires the trigger at once (it has `Operator-reserved:` holds) and, by the No delegable act bullet, routes to classification and the existing flow without a bogus delegation ask. The class cells are `technical`, `operator (<category>)` and `waiting (<ISO UTC>)`; the Hetzner console check and support question use the owner's own `operator (third-party system)` wording (row O1). Out of scope and untouched: the four CTO-to-rule items are NOT ruled here, ADR-282 is not edited, and no apply_target dispatch, Hetzner or Doppler write, secret rotation or ruleset change happens.

### Phase 5 - Ship notes

- PR body: `Ref #9927` only (no closing keyword; verify with `gh pr view --json body` that no `Closes|Fixes|Resolves` precedes any issue number). State what was measured and what was not, with dates: measured 2026-10-29 (live issue state, ADR-282 and runbook rows, the grep for mirrors, the `ci-head-verdict.sh` grep, the eval-gate no-op output, the test results with counts); not measured (the CONCUR dissent and the un-enqueued-PR behaviour, whether any real brief matches the vocabulary beyond the one measured shape, any local affected-test gate that queued). CI is the gate.
- Render `decision-challenges.md` rows into the PR body; the `operator (scope)` row O1 is the one owner-facing flag. The draft PR title `WIP: ...` is replaced at ship.
- A merge-queue PR that is BEHIND waits for the queue: check with `bash plugins/soleur/scripts/ci-head-verdict.sh verdict <PR>`.

## Files to Edit

- `plugins/soleur/commands/go.md` - Step 1.5 paragraph only, outside the eval-gate markers (Phase 1 items 1 to 4).
- `plugins/soleur/test/go-hold-routing.test.sh` - new pins, matcher, fixtures, ten mutation rows, extended H4, floor (Phase 2).
- `plugins/soleur/test/cto-interface-selector.test.sh` - one caller row (Phase 2 item 6).
- `plugins/soleur/skills/one-shot/SKILL.md` - line 98, one clause (Phase 1 item 5).
- `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md` - append-only addendum (Phase 1 item 6).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-hold-routing-trigger-9927/decision-challenges.md` (created at plan time).
- `knowledge-base/project/specs/feat-one-shot-hold-routing-trigger-9927/epic-9927-operator-holds-draft.md` (created at plan time; the record of the body append).
- `knowledge-base/project/specs/feat-one-shot-hold-routing-trigger-9927/tasks.md`.

Not edited: `plugins/soleur/skills/go/SKILL.md` and the codex, cursor, devin, opencode, `.grok` shims (none carries the paragraph); `gated-skills.json`; `tasks/go-routing.jsonl`; `delegation-verify.sh`; `hold-gate-eval.sh`; `cto.md`; ADR-282.

## Acceptance Criteria

- [ ] `go.md` Step 1.5 carries the two Classification list bullets, the amended prose sentence and the No delegable act bullet; every previously pinned phrase is intact; the text between the `go-routing` markers is byte-identical to the merge base (`go-hold-routing.test.sh` anchor row green).
- [ ] The measured shape (a synthesized brief citing an open epic with `Owner-side items:` and `Blocked by the read-only rules` lists) is routed by the derived matcher (`fx-positive-brief`), and the same fixture is NOT routed when the paragraph is reverted to the old trigger (mutation row 11 RED).
- [ ] A bare `ask the operator` with no epic and no list is not routed (`fx-negative-bare-ask`), and neither are the no-epic, closed-epic and CTO-line fixtures; the prose, no-items, fenced and done rules are pinned as prose (`classification-trigger`, `classification-ignored-blocks`, `prose-amended`).
- [ ] An outsider-authored epic body with a valid list is not routed (`fx-negative-outsider-body`), and inverting that clause turns the suite RED.
- [ ] `go-hold-routing.test.sh` exits 0 with its anti-vacuity floor raised and the assertion count equal to the floor (zero slack); `cto-interface-selector.test.sh` exits 0 with the new row selecting `rule` and not `own-the-epic`.
- [ ] `git grep -il 'hold routing' -- plugins` after the edit still lists `commands/go.md` as the only holder of the paragraph (no mirror gained or lost a copy).
- [ ] Phase 3 outputs recorded: `--check` gated, candidate run `accept:true, reason:"no gated-block change"`, no API spend.
- [ ] ADR-289 has the 2026-10-29 addendum, with 0 removed lines against the merge base; ADR-282 has 0 changed lines; `c4-count-parity.test.sh` green (no C4 element changes).
- [ ] No file outside `plugins/soleur/{commands,skills/one-shot,test}`, ADR-289 and `knowledge-base/project/specs/feat-one-shot-hold-routing-trigger-9927/` (plus this plan) is in the PR diff; no script, workflow, terraform or secret file is touched.
- [ ] PR body: `Ref #9927` only, no closing keyword; measured versus not measured with dates; CI named as the gate; the O1 flag present.
- [ ] Post-merge (Phase 4): the live #9927 body is the original plus the appended section; original is an exact prefix; state open; association MEMBER; 10 `- Hold:` lines, 5 `Operator-reserved:`, 4 `Class: technical`, 1 `Class: waiting`, 5 `Class: operator`; no other change to the issue. A fresh read-only check shows the section would trigger (`## Operator Holds` heading with at least one `- Hold: Operator-reserved:` line).

## Test Scenarios

- Given the measured resume brief shape and an open epic, when Step 1.5 is read, then the CTO is spawned with the classification prompt and no delegation is recorded (unit: matcher fixture `fx-positive-brief`).
- Given a bare "ask the operator", when Step 1.5 is read, then nothing routes (unit: `fx-negative-bare-ask`).
- Given an epic body authored by a non-member, when Step 1.5 reads it, then the list is ignored (unit: `fx-negative-outsider-body`).
- Given a list in which the CTO finds nothing delegable, when the route completes, then no question is asked and no issue is filed (unit: the `zero-scope` pin).
- Given epic 9927 after the post-merge append, when a brief cites #9927, then the existing Own the epic flow applies with classification part of it (post-merge read check).
- Regression: the 2026-10-19 courtesy-closer case (a line that only names the CTO) still does not trigger (`fx-negative-cto-line`).

## User-Brand Impact

- **If this lands broken, the user experiences:** a session that again classifies owner-side items itself (the measured failure), or one that raises a delegation question on epic 9927 with nothing to delegate; both cost the owner attention, neither performs an act.
- **If this leaks, the user's workflow is exposed via:** the epic body is public repository text; the appended section names tools, issue numbers and dates already public on the issue and ADR, and contains no values, identities or personal data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change only routes to classification and cannot discharge a hold or authorize an act; every production act still needs a valid Standing Delegation or an in-session per-command go.

*Scope-out:* `threshold: none, reason: the paragraph only routes to a CTO classification and discharges nothing; the diff touches no credential, data-store or auth surface.`

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Six forks ruled on 2026-10-29 (rows T1 to T7 of decision-challenges.md): body not file; Rule interface, no cto.md change; closed vocabulary with structure and fence/quote/done guards; static pins plus a paragraph-derived matcher; `Class:` line carrier; and a zero-Scope clause to stop a bogus delegation ask on the new epic section. One owner-facing flag (O1, closed category list lacks `third-party system`). No product, marketing, legal, finance, operations, sales or support implication: no UI surface, no user-facing copy, no regulated data (the GDPR gate does not apply: no schema, auth, API route, personal data or new processing). The CLO was not spawned because no legal fork arose.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-289 with an append-only `## Addendum 2026-10-29 (#9927)`: the `soleur:go` trigger gained a classification-only form; the authority stays `go.md` Step 1.5; classification uses the Rule interface; it discharges nothing. This is a task in Phase 1 (item 6), not a follow-up. No new ADR ordinal. ADR-282 is untouched.

### C4 views

No C4 change. Checked on 2026-10-29 against the model: external human actors (the owner, already the operator actor), external systems (GitHub, the only edge this reads, already modelled as the CTO component's read-only edge, per ADR-289's Diagram section), containers and data stores (none touched), actor-to-surface access (unchanged: the same CTO component reads the same epic body under the same author limits). Proof is the green `plugins/soleur/test/c4-count-parity.test.sh` run in Phase 2 item 7.

### Sequencing

The addendum describes the target state and lands in the same PR.

## Guard Contract

### Guard 1 - go-hold-routing trigger pins and derived matcher

**Property.** The widened Step 1.5 trigger routes exactly a label-plus-items list that belongs to an open epic and is found in the brief or in an owner-authored epic body, routes it to classification only, and nothing else about the paragraph's fail-closed rules changes.

**Assembly.** The paragraph in `plugins/soleur/commands/go.md` is the single chokepoint, but the property quantifies over every place that restates or consumes it: the two Classification list bullets, the amended prose sentence, the No delegable act bullet, `skills/one-shot/SKILL.md` line 98, the ADR-289 addendum, and the cue the selector test derives from the paragraph (`cto-interface-selector.test.sh`). The two list sources of the widened form (the brief, the epic body) are separate fixtures (`fx-positive-brief`, `fx-positive-body`), and the closed-epic fixture covers both. The vocabulary and the author set are derived from the paragraph at run time (single source), never restated in the matcher. The anchor outside the commit is the merge-base block hash the suite already uses; because the paragraph's text and its pins can be weakened in one diff, the pins are paired with fixtures that fail when the prose stops meaning what the pins say, and the extended H4 harness row proves the suite itself goes RED when an emit is removed. Fence, quote, done-heading and prose rules are pinned as prose and are not re-implemented in the matcher, so a stub matcher cannot hide a weakened rule: each has its own pin and mutation.

**Mutation matrix** (the same ten rows as Phase 2 item 3, by number):

| # | Mutation | Expected |
|---|---|---|
| 1 | Strip the two Classification bullets (revert to the old trigger) | RED `classification-trigger` and `fx-positive-brief` |
| 2 | Widen the author set (`CONTRIBUTOR or NONE` added after the compliant first three) | RED `fx-negative-outsider-body` |
| 3 | Invert the widened-source author handling (`never triggers here either` -> `triggers here too`) | RED `classification-author-limits` |
| 4 | Drop the epic-reference requirement | RED `fx-negative-no-epic` |
| 5 | Let a closed epic trigger (`in state open` removed) | RED `classification-open-epic-only` and `fx-negative-closed-epic` |
| 6 | Delete the vocabulary label `Waiting on` | RED `fx-positive-body` |
| 7 | The classification prompt may start `Own the epic` | RED `classification-prompt-not-own-the-epic` |
| 8 | The route may discharge a hold, record a delegation or call `render` | RED `classification-only` |
| 9 | Delete the No delegable act bullet | RED `zero-scope` |
| 10 | Own dispatch: rename `begin with one of` so the vocabulary extraction is empty | RED `classification-trigger` and every positive fixture (the matcher fails closed) |

Harness and must-PASS rows: the extended H4 removes the `fx-negative-outsider-body` emit from a copy of the suite and requires that copy to go RED; `fx-positive-variant` (`OWNER-SIDE ITEMS:` re-cased with numbered items) must stay green, so a guard that rejects every non-canonical input is caught. The existing H2 and H3 rows cover whitespace-only and re-cased edits.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Widen the Step 1.5 hold-routing trigger in the go skill" | Phase 1, `go.md` edit | mapped |
| 2 | "routes to the CTO for CLASSIFICATION only" | Phase 1 item 3 (route, prompt, never discharges) | mapped |
| 3 | "every existing fail-closed rule (author checks, plan-path checks, headless behaviour, Operator-reserved holds always stand) is unchanged" | Phase 1 item 3 (last sentences) + AC 1 (all existing pins intact) | mapped |
| 4 | "A bare \"ask the operator\" with no epic and no list must still route normally." | `fx-negative-bare-ask`, existing M4 | mapped |
| 5 | "Add tests for: the new positive case, the unchanged negative case, and an outsider-authored epic body that must not trigger." | Phase 2 fixtures `fx-positive-*`, `fx-negative-bare-ask`, `fx-negative-outsider-body` | mapped |
| 6 | "every harness mirror that carries the same paragraph" | Research Reconciliation row 1 + AC (grep shows `go.md` only) | mapped (no mirror carries it; verified) |
| 7 | "the go routing block is eval-gated, so plan the eval-gate per the repo rules" | Phase 3 | mapped |
| 8 | "Give epic #9927 a `## Operator Holds` section so the trigger fires on it and each hold carries a class" | Phase 4 + draft file | mapped |
| 9 | "the CTO rules and records the decision" | decision-challenges.md T1 to T9 | mapped |
| 10 | "use the `Gate:` / `Operator-reserved:` container format ... with the owner-only items written `Operator-reserved:`" | draft file (5 owner-only holds written `Operator-reserved:`) | mapped |
| 11 | "if the issue body is chosen, the edit is a GitHub write the plan must schedule post-merge and name as an action" | Phase 4 | mapped |
| 12 | "the PR body states what was measured and what was not, with dates, and says CI is the gate" | Phase 5 | mapped |
| 13 | "Ref #9927 only (never a closing keyword" | frontmatter `closes: none`, AC, Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/commands/go.md` edit | "Widen the Step 1.5 hold-routing trigger in the go skill" | asked |
| `go-hold-routing.test.sh` extension | "Add tests for: the new positive case" | asked |
| derived matcher and fixtures | "an outsider-authored epic body that must not trigger" | asked |
| Phase 3 eval-gate proof | "plan the eval-gate per the repo rules" | asked |
| Phase 4 body append | "Give epic #9927 a `## Operator Holds` section" | asked |
| draft record and decision-challenges.md | "Persist every decision as a row" | asked |
| `cto-interface-selector.test.sh` row | - | inferred - justification: CTO ruling F2/T2 asked for this pin; the selector test derives its cue from this paragraph and without a row for the new prompt the property that the prompt selects `rule` is unguarded |
| `one-shot/SKILL.md` line 98 clause | - | inferred - justification: it restates the brief forms and a test pins it, so leaving it unchanged would describe a narrower trigger than `go.md` and the two would drift |
| ADR-289 addendum | - | inferred - justification: `wg-architecture-decision-is-a-plan-deliverable`; the 2026-10-22 widening of the same trigger was recorded as an addendum, and the recorded architecture must not lag the change |
| No delegable act bullet | - | inferred - justification: CTO ruling T7; adding the epic 9927 section would otherwise raise a delegation ask with nothing to delegate on every run, breaking the section's own purpose |

### Split Assessment

- Subsystems touched: 2 - `plugins/soleur`, `knowledge-base`
- Planned files: 5 edited + 3 created = 8 | Estimated changed lines: ~420 (mostly test rows and fixtures)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Observability

Skipped: no file under `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts/` is edited and no infrastructure surface is introduced (prose, tests, an ADR addendum, and one issue-body write).

## Dependencies & Risks

- **Risk: the model reads the new bullets as "also ask the epic-start question".** Mitigation: the prompt shape is pinned (never `Own the epic`), the No delegable act bullet is pinned and takes precedence over the epic-start question, and the selector row proves the prompt selects `rule`.
- **Risk: false positives in the epic-body source** (`Blocked`, `Waiting on`, `Waiting for` are ordinary issue headings; the 2026-10-19 courtesy-closer learning). Mitigation: the epic must be an open issue the brief cites; a false positive only routes to a classification and discharges nothing. A narrower vocabulary for the body source (brief-only bare-word labels) is a taste row (T10), not applied because the CTO ruled the vocabulary for both sources.
- **Risk: a real brief writes the label as plain text with no colon and misses the trigger, repeating the measured failure.** The CTO accepted this bias (a false positive only routes to classification). Mitigation: the measured shape is a fixture; widening the plain-label rule later is a one-line change guarded by the same pins.
- **Risk: the body write rewrites the original (trailing newline, CRLF).** Mitigation: byte-exact prefix proof before and after (Phase 4 steps 3 and 5); abort on mismatch.
- **Risk: a later session "tidies" a `Class:` line into the `Hold:` words or a `Gate:`.** The draft header says nothing here is delegable; `Operator-reserved:` holds cannot take a discharging gate in the evaluator.
- **Risk: the matcher and the model read the prose differently.** The matcher is a model of the prose; it catches vocabulary and structure drift, not model behaviour, and implements only what its eight fixtures exercise. A behavioural eval is out of scope because it would touch the gated block.
- **Dependency:** none blocks; no sibling PR names #9927's files (collision pre-check).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries placeholder text fails `deepen-plan` Phase 4.6; this plan fills it.
- The first draft's 200-item timing fixture was cut: a linear awk cannot stall, and the fixture would have run about 85 times per suite copy.
- The test file must assemble the eval-gate marker strings (never write them literally), or `registry-completeness.test.sh` sees a duplicate gated block.
- `Class:` is deliberately not a marker. Do not rename it to `Hold:`, `Gate:`, `Delegation:` or `Envelope:`: the evaluator counts those and would mis-parse the section.
- The body append must not be printed: the body is public but the rule is counts and booleans only.
- Phase 1 items 1 and 2 add sentences next to pinned phrases; run the existing suite before adding pins, and again after each wording change. The new bullets must be single-line list items with no fenced block and no line starting `#` (`para_awk` ends the paragraph there).
- The draft record is archived by ship before the merge; Phase 4 reads it from its archived path on `origin/main`.
- The `waiting (<ISO UTC>)` cell lives only in the epic section; decision-challenges rows for date waits use `operator (schedule)` because the Class enum is closed (row T9).
