---
feature: ci-eval-harness-backstop
lane: single-domain
issue: 5703
plan: knowledge-base/project/plans/2026-06-29-feat-ci-eval-harness-backstop-plan.md
---

# Tasks: CI backstop for gated classifier-skill edits (#5703)

## Phase 0 — Preconditions (verify)

- [x] 0.1 Re-confirm `git grep -hoE 'eval-gate:block:[a-z][a-z0-9-]*:start' -- 'plugins/soleur/' ':(exclude)plugins/soleur/skills/eval-harness/' | sed -E 's/eval-gate:block:(.*):start/\1/' | sort -u` → `{go-routing, ticket-triage}` (matches registry).
- [x] 0.2 Confirm `node plugins/soleur/skills/eval-harness/scripts/gen-skill-prompt.cjs <target> --stdout` regenerates a projection to stdout.

## Phase 1+2 — Create `test/registry-completeness.test.sh` (pure bash)

- [x] 1.1 Scaffold mirroring `test/eval-gate.test.sh`: `HERE`/`SKILL_DIR`/`REPO_ROOT`, `pass()`/`fail()`, `fails=0`, `cd "$REPO_ROOT"`, node one-liner JSON reads (no `jq`).
- [x] 1.2 **DEDUP guard:** scan source marker ids (pre-`sort -u`); assert each id appears exactly once. Fail message names the duplicated id.
- [x] 1.3 **PARITY:** build sorted source-scanned id set + sorted registry `block_id` set; assert set-equality (`comm -3` empty). Distinct fail messages for source-only (unregistered marker → additive recipe) vs registry-only (orphan/renamed entry). Characterize the live scan as exactly `{go-routing, ticket-triage}`.
- [x] 1.4 **CHARSET guard:** assert every registry `block_id` matches `^[a-z][a-z0-9-]*$` with a clear message.
- [x] 1.5 **NEGATIVE sanity (in-memory):** append (a) a synthetic unregistered id and (b) a duplicate id to in-memory copies of the scanned set; assert PARITY / DEDUP flag each. No file/registry fixture (git grep is tracked-only).
- [x] 1.6 Accumulate into `fails`; terminal `if [[ "$fails" -gt 0 ]]; then exit 1`; end with `echo "registry-completeness: all assertions passed"`.

## Phase 3 — Refactor `test/extract-block.test.sh` to registry-driven

- [x] 3.1 Replace lines 21–29 (`for target in go-routing ticket-triage` + `go-skill.txt`/`triage-skill.txt` ternary) with a loop over registry entries reading `target` (for `node "$GEN" "$target" --stdout`) and `projected_prompt_path` (committed = `"$REPO_ROOT/$projected_prompt_path"`).
- [x] 3.2 Keep the `diff -u` round-trip assertion + the three `extractBlock` unit assertions unchanged. Confirm both targets still covered.

## Phase 4 — Green + discovery + docs

- [x] 4.1 `bash plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh` → exit 0; output pins `{go-routing, ticket-triage}` (AC1) and prints negative-sanity `ok` lines (AC2).
- [x] 4.2 `bash plugins/soleur/skills/eval-harness/test/extract-block.test.sh` → exit 0; both `round-trip` `ok` lines present (AC3).
- [x] 4.3 `bash scripts/test-all.sh scripts` → exit 0 (both files discovered + green) (AC4).
- [x] 4.4 Add `registry-completeness.test.sh` to the `## Tests` list in `eval-harness/SKILL.md` and `eval-harness/README.md` (AC5).
- [~] 4.5 *(optional — SKIPPED: would bloat ADR; invariant documented in SKILL.md/README)*  one-line Consequences note in `ADR-069-validation-gated-classifier-skill-edits.md` that the registry-completeness invariant is now CI-asserted. Skip if it bloats the ADR.

## Exit

- [ ] 5.1 Run `/soleur:review` (or QA) before marking PR #5721 ready.
