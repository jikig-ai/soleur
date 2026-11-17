# Decision Challenges — feat-one-shot-12509-oracle-bot-author

Headless one-shot run for issue #12509. The harness has no Task subagent tool;
the batched `soleur:engineering:cto` ruling was obtained by spawning the agent's
Rule interface through `claude -p` (one spawn, three rows; cto_spawns=1 in the
tally). Verbatim rulings recorded below.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Regex shape: widen the existing `^[A-Za-z0-9][A-Za-z0-9-]*$` with a `(\[bot\])?$` suffix vs. adopting the repo precedent `^[A-Za-z0-9-]{1,39}(\[bot\])?$` (watch-lint-ratchet-reeval-10515.sh:179) wholesale | technical | Ruled by CTO agent, 2026-11-09: Use the minimal widening `^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$`, do not adopt the `{1,39}` cap - the cap would be a second behavior change on a RATCHET_ORACLE file, the current regex never enforced one, and the `_` enterprise-login gap affects both regexes and is a separate defect; the watcher regex is an output-sanitizer branch, not a gate, so it is not a binding precedent — only the `(\[bot\])?$` suffix is shared. Dissent: none (a 39-char cap is harmless for real logins but does not belong in a minimal fix). |
| Emit `author=soleur-infra[bot]` raw into the marker vs. strip the suffix before emit | technical | Ruled by CTO agent, 2026-11-09: Emit the raw login - stripping would make `deruelle[bot]` compare equal to `deruelle` at the exact-string owner arm (ci-oracle-review.sh:186 vs REQUIRED_REVIEWER at :58), opening a spoof path on the owner release valve, and would emit a wrong author; the only other marker consumer (ci.yml:644) reads only `reason=`, so a wider `author=` is safe. Dissent: stripping keeps the grammar simpler, at the cost of weakening the owner arm. |
| Widen the two marker-grammar pins in the SAME PR (driver :45 comment, suite want() pin) vs. leave untouched | technical | Ruled by CTO agent, 2026-11-09: Widen both pins in this PR — :45 to `^[A-Za-z0-9-]+(\[bot\])?$\|-`, want() to `author=[A-Za-z0-9-]+(\[bot\])?`; add `[bot]` regression rows plus a `deruelle[bot]` non-spoof row - an un-widened pin reports a false marker-off-grammar failure for every future `[bot]` author, and the brief requires fixing every instance of the shape in the same PR. Dissent: none. |
| Brand-survival threshold `none` | taste | assumed: none — CI gate internals; wrong outcome is a loud red required check, never a silent user-facing defect. |
