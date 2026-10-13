# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-21-fix-preflight-check-10-folded-scalar-parser-plan.md
- Status: complete

### Errors
None. All halt gates (4.5-4.9) passed; knowledge-base citation check clean; both commits pushed successfully.

### Decisions
- **Terminator uses pure YAML indent semantics, not key-name matching.** Continuation requires `indent > key`; `indent <= key` ends the scalar. This is the THIRD design — the issue's suggested `[a-z_]+:` terminator AND the first replacement both truncated real corpus commands (the issue's version truncates on `https://`). Verified against 10 fixtures plus the live corpus.
- **Scope covers `>`, `>-`, `>+` plus a trailing-comment tail on the header.** `>` (clip) is ~3x more common in the corpus than the reported `>-`, so scoping to `>-` alone would have left the majority broken. The comment tail is load-bearing: anchoring the header regex to a bare `$` recreated #6772 for `command: >- # comment`.
- **Block-scalar defect 2 fixed in the same rule line** (it swallows sibling `expected_output:` across ~19 plans), with its fail-open consequence bounded by a credentialed-CLI reject folded into this PR per CPO condition C1, plus AC11 gating on a reject-verdict delta.
- **Production awk extracted to `scripts/parse-form-a.awk`** so the parity harness executes the real runtime instead of regex-scraping markdown. Path resolves via `git rev-parse --show-toplevel` with hard-fail on load error — `CLAUDE_PLUGIN_ROOT` is unset in a plain session, and a silent load failure falls through to Form B and parses a DIFFERENT command.
- **Threshold raised from `none` to `single-user incident` with CPO sign-off.** Fixing the parser is a fail-open transition: 4 corpus plans flip from fail-closed to executing, all running `doppler run -c prd_terraform`, and `env -i` fails to scrub the file-backed Doppler token because `$HOME` is preserved. CPO caught that the newline-reject mitigation covered NONE of those flips and required the credentialed-CLI reject in this PR rather than tracked separately.

### Security note carried into /work
This is not a pure parser fix. Making the parser correct causes previously-unparseable commands to actually RUN under `bash -c`, against production credentials. The credentialed-CLI reject is therefore load-bearing, not polish — verify it covers each of the 4 flipping plans, not just the general case.

### Two divergences from operator direction (recorded, not silently applied)
See `decision-challenges.md`: the awk extraction to a standalone file, and the mutation-protocol scoping.

### Components Invoked
- `Skill: soleur:plan`
- `Skill: soleur:deepen-plan`
- `Agent: soleur:engineering:review:kieran-rails-reviewer`
- `Agent: soleur:engineering:review:code-simplicity-reviewer`
- `Agent: soleur:engineering:review:test-design-reviewer`
- `Agent: soleur:engineering:review:security-sentinel`
- `Agent: soleur:product:cpo`
