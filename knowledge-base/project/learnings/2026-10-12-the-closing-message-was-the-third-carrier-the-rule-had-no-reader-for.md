# Learning: a technical fork reached the operator in the closing message, a carrier none of the rule's three enforcers could read

## Problem

On 2026-10-12 a session ended turns with "Decision for you: 1. 2. 3." and "Your calls: is the personal CLI token acceptable? do you want a migration design? rotate Hetzner/R2?" — evidence sufficiency, a design A-vs-B and an ordering, put to a non-technical operator in END-OF-TURN PROSE. `hr-technical-fork-is-not-an-operator-question` was in force the whole time. The founder corrected it: "you should ask the CTO, not me ... improve the workflow and skills so we ask those to the CTO in the future".

The rule had three enforcers and each read a different carrier: the pre-ask hook reads `AskUserQuestion` tool calls, ship's Technical-Ruling Gate reads a `## Decision Classes` table, and one-shot runs that gate once after the plan phase. Two days earlier (2026-10-11) the carrier was an artifact pipeline; this time it was plain prose. Strengthening the enforcers that already existed would have changed nothing.

## Solution

- A repo-local `Stop` hook (`.claude/hooks/pre-closing-technical-fork-gate.sh`) judges each `?`-terminated sentence of the closing window alone and blocks at most once per turn. The block's first imperative is "spawn `soleur:engineering:cto`" (legal: `soleur:legal:clo`); the escapes come after it.
- The cue vocabulary lives in ONE lib (`.claude/hooks/lib/technical-fork-cues.sh`) with a verdict function `tfc_is_fork <unit> <groups>`, called by both hooks. A suite row derives the definition sites from the tree, so a second copy cannot land unnoticed.
- One pointer line each in `one-shot`, `go`, `plan` and `work`, naming the closing message as a carrier. `work` was at its byte ceiling, so the funding was a verbatim relocation of an explanatory tail into a reference, not a trim.

## Key Insight

1. **Find the carrier before strengthening the enforcer.** A rule with three enforcers is a rule with three READERS; the next failure arrives on the carrier none of them reads. When a rule is violated while it is in force, list what each enforcer reads before editing any of them.
2. **A shared vocabulary has to GROW, not only be shared.** The brief asked for "the SAME cue vocabulary". Measured, the existing cues matched none of the three incident sentences, and the existing operator-vocabulary veto silenced one of them (`deploy` inside `deploy-channel`). Sharing a list that does not cover the incident is a refactor, not a fix. The closing group therefore added three cues and a narrower veto, and the pre-ask hook was kept on group `shared` so it was not widened.
3. **Judge the sentence, not the message.** A whole-message exemption lets an appended "Approve?" hide a ruling in the same message, and a whole-message escape lets one appended label pass three unrelated questions. Each unit is judged alone and an `Operator-only (category):` label governs only its own sentence and the next unit.
4. **The hook is ONE forced reconsideration, not a guarantee.** A repeat after the block runs with `stop_hook_active == true` and passes; inside a ralph loop (one-shot) only the FIRST Stop of a chain is judged and every later one carries `true`, so the one-shot pointer is signage for the Step 8 closing. Write that where the next reader finds it, or the gate reads as stronger than it is.
5. **A fail-open gate needs its parse-doubt arms as rows.** Every doubt (jq missing, empty or invalid stdin, an absent loop-guard key, a non-string message, an empty or missing lib, an unterminated fence) exits 0 with one stderr line, and each is a suite row plus a mutation that makes the arm block. An empty cue regex matches every line, so a lib that fails its self-check is parse doubt, never a verdict.
6. **Measured first sample: 1 hit of 198 closings, a true positive; recall about 20%.** The phrase-shaped cues miss most rephrasings ("should the old emptiness evidence be accepted retrospectively"), which the ruling accepted as recall decay.

## Prevention

- **The miss, cue, fixture loop.** When a technical fork reaches the operator unblocked: find the closing in the transcript, add ONE cue (or tighten one) in the lib with a synthesized must-BLOCK fixture and the near-miss must-PASS fixtures, re-run the whole sample, and only then ship; never widen preemptively. A BUSINESS word is never the fix (it changes the pinned `RULING_OPVOCAB_RE` and silences the pre-ask hook too).
- **Cue-growth tripwire.** More than 6 CLOSING cue patterns (3 today), or 3 founder-reported misses in 30 days, or misses inside ralph loops: revisit judging "Decision for you:" lists that carry no `?`, or stop adding cues.
- **False-positive sample recipe** (the extractor is not committed; nothing from a transcript is copied anywhere): read `~/.claude/projects/<project-dir>/*.jsonl` newest first, read-only; a turn closes at the next REAL user record (string content, or text blocks with no `tool_result`); the closing is the last assistant record's last content block when it is `text` (a turn ending in `tool_use` is not a closing); keep it when the fence-, `>`- and code-span-stripped last 1500 bytes holds a `?`; feed `{"stop_hook_active":false,"last_assistant_message":...,"session_id":...}` to the real hook with `INCIDENTS_REPO_ROOT` pointed at a scratch directory; record counts and classes only (technical, operator-class, ambiguous). The bar is zero operator-class or ambiguous hits and at most 15% blocked.
- **Graduation** to the plugin follows #10056 and the checklist in the ADR-084 2026-10-12 addendum.

## Recurrence 2026-10-19: the same rule, the declarative carrier, and a trigger that needed a literal

A #8211 resume brief carried an `OWNER-GATED` list and the line "Technical forks go to soleur:engineering:cto" but no literal `HOLDS:` line. go Step 1.5 therefore never spawned the CTO, and the session closed with "Next step: your call. Tell me to build #10297 ...": a technical fork handed to the operator as declaratives with no `?`, the carrier the cue-growth tripwire above reserved for a revisit. The founder corrected it for the second time (2026-10-12, 2026-10-19), so the tripwire count is 2 of 3 founder-reported misses in 30 days; closing cues are now CL1, CL2a, CL2b, CL3 and CL4 (5 of 6).

Fixed in two places, because the miss had two links. (1) The cause: Step 1.5 now routes on `#N` plus a `HOLDS:` line or an `OWNER-GATED` heading with items, and a line naming the CTO as the decider of technical forks is a modifier, not a trigger. Pinned in `go-hold-routing.test.sh`. (2) The symptom: CL4, a declarative cue in its own function (`tfc_is_handoff`), not in the generic judge.

What the first draft got wrong, found by an 8-seat review, so the next cue does not repeat it: a broad "hand-off phrase + common noun" cue (`pr`, `fix`, `build`, `#N`) blocked courtesy closers ("let me know if you want the design doc") and operator authorizations ("say the word and I will merge #123"), because the veto list held 13 verbs and omitted merge, ship, release and push. A declarative cue judged inside the `?` judge also (a) reached the strong cues and blocked a status line carrying "evidence bar", (b) spent the 12-unit question budget so thirteen "Let me know." closers pushed a real fork out of the window, (c) was prefiltered on raw bytes so a non-breaking space inside "your call" defeated it, and (d) lived in three hand-kept vocabulary copies that had already drifted. The shape that held: a narrow phrase set plus a DECISION noun, one shared candidate alternation in the lib used by both the prefilter and the awk emitter, separate judging and budget for declaratives, and one must-PASS row per veto and per courtesy shape. A cue that blocks a courtesy closer is a wrongful block, which the hook header calls the worse failure.

## Session Errors

- The brief named the delegation reference as a PR (#9642); it is an open issue, and the file arrived in PR #10049. The brief's Stop-hook location was also wrong (the model hook is a PLUGIN hook, `plugins/soleur/hooks/unkept-promise-hook.sh`). **Prevention:** resolve every `#N` a brief names with `gh issue view`/`gh pr view` before building on its label.
- The same session asked the founder three technical questions in closing prose AFTER the rule and its reference had been loaded; the founder's correction, not a gate, caught it. **Prevention:** the Stop hook in this PR; before ending a turn, any "Decision for you:" item is a ruling to delegate, not a question to ask.
- A review-time design pass (simplicity + architecture seats) found two claims the PR's own prose got wrong: "a request to authorize passes in every shape" (four real authorization shapes blocked) and "one appended label disarms both gates" (false for the bold `**Paused**:` form). **Prevention:** probe the real hook with the claim's own examples before writing a universal into an ADR; the closing-only permission regex and the bold-label normalisation are the fixes.

## Tags

category: workflow-patterns
module: hooks, one-shot, work
