# Learning: a resume brief told the agent to ask the operator a technical question, the fourth carrier the rule's enforcers could not read

## Problem

On 2026-10-14 a resume brief said "ask the operator once, then act" about whether leftover roadmap items (live-verify work, a cheaper CI path) should run as a new pipeline or be recorded as not fixed. The agent put it to the operator through `AskUserQuestion`, although `hr-technical-fork-is-not-an-operator-question` and the routing skill's first Sharp Edge both forbid it. The operator answered: "ask the CTO not me and improve the workflow and skills to ensure this is the case in the future for such technical questions".

Three carriers had already been closed: the tool call (pre-ask hook), an artifact pipeline (ship's Technical-Ruling Gate, 2026-10-11) and the closing message (Stop hook, 2026-10-12). This one is the brief's own wording, which a hook cannot read, and the skill text covered only a brief that said "surface it, do not decide it".

## Solution

- The delegation reference now says a brief's "ask the operator" / "OPEN DECISION" wording about a technical item is itself the trigger to spawn the CTO, and classifies routing or ownership of an already-identified gap the brief named as technical (the closed operator-only list keeps its eight categories; only the `scope` definition is clarified).
- `commands/go.md` (the authority), its `skills/go/SKILL.md` shim and the one-shot inline copy carry equivalent wording; `components.test.ts` pins the reference, the Sharp Edge and the inline copy. `AGENTS.rules.md` and `work/SKILL.md` still carry only the older "surface it" wording: the brief forbade editing them, so extending them is the operator's call.
- The pre-ask hook gets one narrow `ask` cue under a new `shared+ask` group: a route phrase and a record phrase in one interrogative sentence. Measured on the real hook: the synthesized incident variants were all allowed before; the committed AK1-AK5 fixtures are denied after (fitted to that phrasing), and the ownership-only, scope-limited, two-sentence, options-only and permission-shaped phrasings stay allowed (the stated residual, pinned as AL9-AL11 and AL18-AL19).

## Key Insight

1. **The brief is a carrier.** Enumerate the carriers (tool call, artifact, closing message, brief) before strengthening an enforcer; the next failure arrives on the one nothing reads.
2. **A brief's instruction to ask is not an exemption.** The wording that tells you to ask the operator is the cue to check whether the question is technical, and a scope-worded question about routing or owning a gap the brief named is technical.
3. **Lexical cues have a measured reach.** An ownership-only arm falsely denied an assignment ask ("Who should own the remaining items, Alice or Bob?") and was cut; the residual is pinned as must-allow rows so nobody claims it is covered.
4. **A review fix is the least-audited code in the PR.** The per-segment loop that closed one finding opened a stall on a count the model controls, and no test had a row at that count. Time every fix at the input size an adversary can choose.

## Prevention

- When a brief's wording tells you to ask the operator about a technical fork, spawn `soleur:engineering:cto` first (legal: `soleur:legal:clo`), record `Ruled by CTO agent`, and ask the operator only the authorization from the closed list.
- The miss, cue, fixture loop applies to the new cue; the budget is 3 `TFC_ASK_*` patterns or a second paraphrase miss.

## Session Errors

- The session asked the operator the routing question although the rule was loaded. **Prevention:** the hook cue and the skill text above.
- Changing the pre-ask hook's group string turns the closing suite's G2-2 mutation row red (its anchor stops landing). **Prevention:** G2-2 now targets the `shared+ask` line, with a comment saying a pre-ask group change reddens that suite.
- `plugins/soleur/skills/go/SKILL.md` is a harness shim; the authority and the Sharp Edge live in `plugins/soleur/commands/go.md`. **Prevention:** edit the authority and add a pointer to the shim.
- **A review fix introduced a performance regression.** Judging the ask cue per `?` segment with a `while read` loop forked a grep per segment (about 1.6 ms each, 34 s at 20,000 segments) on a count the model controls, which would stall the hook and fail it open. Two seats found it independently; no suite had a many-`?` row. **Prevention:** when a fix moves a check from the whole text to per-item, run it as one pipeline (not a loop with a fork per item), read it through a command substitution rather than `grep -q` (SIGPIPE under `pipefail`), and add a timing row with the item count at 4,000 or more (T5).
- A mutation I wrote widened only one of two alternations of the ROUTE regex and so "survived", which read as a coverage gap in the test. **Prevention:** assert the anchor occurs the expected number of times before replacing, and treat a survivor as un-run until the mutant is shown to change behaviour.
- Fixture slips: AL17's phrase matched a second RECORD verb (`listed`), and ML2 fed an empty hook output to `jq`. **Prevention:** run each new fixture against the pristine hook before relying on it, and read an empty hook output as allow with the `${out:-{\}}` form.
- A two-dot `git diff origin/main` after a fetch listed workflow files this branch never touched. **Prevention:** use `git diff origin/main...HEAD` for branch scope.
- `AGENTS.rules.md` and `work/SKILL.md` still carry the older wording because the brief forbade editing them. **Prevention:** recorded as H15 in the spec for the operator to authorise; no issue filed.

## Tags

category: workflow-patterns
module: hooks, go, one-shot
