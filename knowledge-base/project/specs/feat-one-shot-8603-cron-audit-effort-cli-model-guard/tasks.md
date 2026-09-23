# Tasks: audit-cron effort pin + pinned-CLI model-id guard (#8603)

Plan: `knowledge-base/project/plans/2026-09-23-feat-audit-cron-effort-and-cli-model-guard-plan.md`

## Phase 1: Setup and RED

- [ ] 1.1 Runner precondition: `ls -l apps/web-platform/node_modules/@anthropic-ai/claude-code-linux-x64/claude` shows an executable file, and a hermetic `--effort high --version` prints `2.1.280 (Claude Code)`.
- [ ] 1.2 Move `stripComments` unchanged into `apps/web-platform/test/helpers/strip-comments.ts`. Then add Guard 1 to `apps/web-platform/test/server/inngest/model-tiers.test.ts`.
  - [ ] 1.2.1 Walks (a)-(e) over comment-stripped `functions/*.ts`. Use the quote-agnostic `--effort`/`--model` regexes, count `=` forms as offenders, and set the (c) floor to ≥5.
  - [ ] 1.2.2 `AUDIT_CRONS` six-name set identity. The (c)/(d) failure messages cite ADR-053.
  - [ ] 1.2.3 Identity pins: `AUDIT_EFFORT === "high"`, and `AUDIT_CLI_ARGS` deep-equals `["--model", AUDIT_MODEL, "--effort", AUDIT_EFFORT]`.
- [ ] 1.3 Create `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts`.
  - [ ] 1.3.1 Header: the "next CLI bump" checklist, a cross-reference to `audit-models.sh [2b]`, and the walk (c) chokepoint note.
  - [ ] 1.3.2 Pin agreement (package.json exact semver = Dockerfile) and the id harvest over `stripComments(source)` with its ⊇ floor. Both run on every host.
  - [ ] 1.3.3 Binary block: `MUST_RUN` dispatch (throw with the `npm ci` remedy), `bundleHasId` (`LC_ALL=C`; rc ≥ 2 throws), per-id collect-all, real-bundle negative control.
  - [ ] 1.3.4 Blob rows: prefix shadow, EOF must-PASS, missing file throws.
  - [ ] 1.3.5 Guard 3: one spawn of `--print ...AUDIT_CLI_ARGS --version` in a temp HOME, asserting the pin prefix, no `/effort/i`, and the `not-a-level` positive control.
- [ ] 1.4 Confirm RED: Guard 1 fails on the six crons, and the effort half fails to compile until `AUDIT_EFFORT` exists.

## Phase 2: Core Implementation (GREEN)

- [ ] 2.1 `model-tiers.ts`: add `AUDIT_EFFORT = "high" as const` and `AUDIT_CLI_ARGS`. Fix the header comment to list 6 crons and add the effort paragraph.
- [ ] 2.2 In the six audit crons, change the import to `AUDIT_CLI_ARGS` and replace `"--model", AUDIT_MODEL,` with `...AUDIT_CLI_ARGS,` in the same position, before `"--"`.
- [ ] 2.3 Run `./node_modules/.bin/vitest run` on the targeted files and `./node_modules/.bin/tsc --noEmit` from `apps/web-platform`.

## Phase 3: Testing and verification

- [ ] 3.1 Apply every Guard Contract row by hand and revert it. Record RED/PASS and the two Guard 3 vacuity demonstrations for the PR body.
- [ ] 3.2 Run `bash plugins/soleur/test/c4-count-parity.test.sh` and `bun test plugins/soleur/test/model-launch-review.test.ts`.

## Phase 4: Docs and ADR

- [ ] 4.1 ADR-053: add the "Amendment — 2026-09-23 (#8603)" paragraph and a new row in Alternatives considered.
- [ ] 4.2 model-launch-review `SKILL.md`: rewrite row 3 (`default_effort` / `AUDIT_EFFORT`) and turn step 2b into an ordered procedure that names the CI gate.
- [ ] 4.3 PR body: `Closes #8603`, a link to #8643, and the cost note (about 12 audit-tier runs a month move from medium to high effort).
