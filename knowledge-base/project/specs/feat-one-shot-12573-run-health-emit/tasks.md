# Tasks: instrument run-health emit on the existing pull request

Derived from `knowledge-base/project/plans/2026-11-27-feat-instrument-run-health-emit-plan.md`. Do not redesign the emitter. Do not open a second pull request. Do not start `scripts/test-all.sh`.

## Phase 1: Setup

- [ ] 1.1 Confirm the working tree is `feat-one-shot-12573-run-health-emit` and that pull request #12996 is the vehicle.
- [ ] 1.2 Leave `scripts/.h1probe.6G3BHeem.sh` untracked. Do not stage it and do not delete it.
- [ ] 1.3 Do not add files for #12575, #12576, #12577, or #12578. Article 30 is not this slice.

## Phase 2: Core Implementation

- [ ] 2.1 Merge `origin/main` into this branch. Replay a conflict only when it touches the helper or the three markdown files, and keep the existing seal rule, fail-open exit 0, and schema_version integer 1.
- [ ] 2.2 Keep the read-surface notice in `plugins/soleur/skills/one-shot/references/run-health-schema.md` and the token-form schema links in `plugins/soleur/skills/one-shot/SKILL.md` and `plugins/soleur/skills/test-fix-loop/SKILL.md`.
- [ ] 2.3 After the merge, `wc -c plugins/soleur/skills/one-shot/SKILL.md` must print at most 51950. If the spare is under 50 bytes, trim prose in that file that is not an emission condition. Do not drop the run-health call or the token-form link.

## Phase 3: Testing

- [ ] 3.1 From `apps/web-platform`, `bun x vitest run test/plugin-root-anchoring.test.ts -t "W4a:|W4b:"` reports 2 passed.
- [ ] 3.2 From the repo root, `bash plugins/soleur/scripts/run-health-emit.test.sh` exits 0.
- [ ] 3.3 `bash plugins/soleur/scripts/run-health-emit.sh --discover` prints `ok` and exits 0.
- [ ] 3.4 Re-run the plan's acceptance greps: schema integer line, phase_prompts mkdir line, seal-rule line, `.gitignore` `.soleur/` line, sibling-name filter prints nothing, and `git status --short` does not show the h1probe script as staged.
- [ ] 3.5 Push `feat-one-shot-12573-run-health-emit` so #12996's next CI run includes the merge and the read-surface commit. Do not open a second pull request.
