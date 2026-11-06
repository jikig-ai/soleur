# Learning: a "credential only on curl's stdin" wrapper leaked through jq, and its own scoping clause contradicted itself

## Problem

PR #12061 added `plugins/soleur/scripts/cloudflare-readonly.sh`, a GET-only Cloudflare read wrapper for Class R (issue #10479, epic #10205). The first version had a 632-assertion hermetic suite and 31 mutation rows, all green, and still shipped five defects that a nine-seat review found:

1. **The bound token reached stdout through a helper child.** Only curl ran under `env -i`. `jq` and `date` inherited every `CF_API_TOKEN*` variable and `HOME`, and a planted `$HOME/.jq` containing `def length: $ENV.CF_API_TOKEN_RULESETS;` made the `rule_count` field print the (fake) token. The header said "credential on curl's stdin config only"; that was true of curl and false of the process.
2. **Records verdicts rested on a substring heuristic.** `mentions_app_host` was `contains("\"app.soleur.ai\"")` on an expression the wrapper deliberately never prints. A wildcard override such as `ends_with(http.host, ".soleur.ai")` or the pattern `*soleur.ai/*` projected `false/false`, so check B or C could read "ok" over a rule that applies to the app host.
3. **The curl flag set was a deny-list.** Eight dangerous mutants (`-X GET -X POST`, glued `-XPOST`, `--connect-to`, `-k`, `--config /dev/null`, `--location-trusted`, `--resolve`, `--form-string`) stayed green because the stub never parsed its flags and the wire check only looked for known-bad tokens.
4. **A whole test group was unpinned.** Deleting `proj` (the projection and sanitization group) from the suite's run loop left it green: no mutation row touched it and the assertion-count floor had about 200 assertions of slack.
5. **The scoping clause for the owner's push bar contradicted itself, and a test locked the contradiction in.** The PR needed a way to push a branch touching `plugins/soleur/scripts/`. The first draft said "`scripts/**` means the repository-root `scripts/`; `plugins/**/scripts/**` is not covered", which exempted every plugin script (including `delegation-verify.sh`). The amended draft said the root-only meaning AND "every other plugins script keeps the plain reading of the bar", which cannot both hold. The pin test asserted both phrases separately and so froze the ambiguity.

## Solution

- Run every external child as `/usr/bin/env -i /usr/bin/<tool> ...`. An empty `HOME` also stops jq loading `~/.jq` (verified on jq 1.8.2 only). Census the call forms in the suite, strip trailing comments before the census, and ban tool paths built from variables.
- Make verdicts depend on counts and refs the wrapper can establish (`enabled_ssl_rules`, `ssl_rule_count`, `rule_count`, the adopted ref), never on a boolean derived from text the wrapper does not print. Say plainly in the header that the wrapper cannot verify host scoping of an unprinted expression.
- Replace the deny-list with exact-argv equality against a closed-grammar stub that refuses any unmodeled flag and reads stdin only with `--config -`.
- Give every test group a mutation row and a group-executed floor reported by `printf` + `exit`, outside the helper it backstops.
- Write the item 4 clause with ONE reading (`scripts/**` is any directory named `scripts` at any depth) and exempt exactly two named paths; pin the whole sentence by equality, not its backticked fragments.

## Key Insight

A guard is the property it enforces, not the string that describes it. Four recurrences in one PR: a *process-level* claim ("the token never leaves curl's stdin") was only enforced on one child; a *verdict* claim ("no other rule affects the host") rested on a heuristic over data that was deliberately withheld; a *closed-set* claim ("only a GET") was a deny-list; and a *scoping* claim was pinned phrase by phrase. For each, ask "name an input that satisfies the check while violating the property", and check every external child process's environment, not only the one the design names. A scoping clause written in the same PR that needs it is a widening of an owner limit, not a clarification — route it to the owner (here: via the CTO agent, ruled `amended`) and record it as an owner-visible widening.

## Session Errors

1. **Three review seats (test-design, simplicity, structural-enumeration) were lost when the previous session ended mid-panel.** Recovery: `SendMessage` to each agent id resumed them with their transcripts. **Prevention:** a panel's seats are resumable by id; on a session resume, check seat completion records before respawning (already in `review/SKILL.md` Gate 2b "a dead agent is RESUMABLE").
2. **Review seats left `/var/tmp` scratch (`cfro`, `cfmap.*`, `cfrev.*`) because the rm hook blocked cleanup.** Recovery: none needed (outside the repo); named in seat reports. **Prevention:** brief seats to use the sandbox allocator (`scripts/soleur-sandbox.sh new`) so the lead can remove the path; already specified in `review/SKILL.md`.
3. **The new suite failed the `fixture-relative-assert` ratchet (4 unguarded redirect sites) on the implementer's first run.** Recovery: guarded with `assert_fixture_dir` (commit `7cdd770857`). **Prevention:** already in `work/SKILL.md` Phase 0.5 check 6.6; the implementer brief should name it explicitly.
4. **`technical-ruling-gate.sh` rejected the decision-challenges rows because the `(review)` marker sat before the colon.** Recovery: moved after the colon (commit `a89f81acea`). **Prevention:** the gate's required shape is `Ruled by CTO agent, <date>: <decision>`; put any tag inside the decision text.
5. **The first draft of the item 4 clause and its pin test locked in a self-contradiction.** Recovery: CTO ruling amended D9, clause rewritten with one reading, pin by sentence equality. **Prevention:** a scoping clause that widens an owner limit goes through a CTO/owner ruling BEFORE the pin test is written, and the pin asserts the whole sentence.
6. **My closing text named a future action while the turn ended with the implementer still running (Stop hook `unkept-promise`).** Recovery: ended with a `Paused:` sentence naming the one thing waited on. **Prevention:** when waiting on a background agent, end with `Paused: <what>`, not a first-person future commitment.
7. **The pre-session gates (Steps 0.0 to 0) were run from a condensed resolver, not the byte-identical fence.** Recovery: none needed (the plugin root verified in each); **Prevention:** copy the fence verbatim or call the scripts it wraps with the same verification.
