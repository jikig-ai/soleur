---
title: "Tasks: Auto-regenerate the LikeC4 model artifact when C4 sources change"
branch: feat-one-shot-c4-model-autoregen
lane: procedural
plan: knowledge-base/project/plans/2026-06-18-feat-c4-model-autoregen-sync-gate-plan.md
---

# Tasks — C4 model auto-regen sync gate

Derived from `knowledge-base/project/plans/2026-06-18-feat-c4-model-autoregen-sync-gate-plan.md`.
**Load-bearing invariant across all tasks: pin `likec4@1.50.0`, never `@latest`.**

## Phase 0 — Preconditions

- [x] 0.1 Confirm `likec4@1.50.0` pin in `apps/web-platform/Dockerfile` + `package.json` (`@likec4/core`, `@likec4/diagram`).
- [x] 0.2 Re-read the `lefthook.yml` `generate-kb-index` block (priority 10, single-star glob, `run: <script> && git add <file>`) as the template.
- [x] 0.3 Confirm `.c4` files are flat in `knowledge-base/engineering/architecture/diagrams/` -> single-star glob is correct (gobwas `**` skips depth-1).
- [x] 0.4 Read `.github/workflows/ci.yml` `test-scripts` shard + `scripts/test-all.sh scripts` group; pick the freshness-test runner convention (bash vs `node --test`).
- [x] 0.5 Confirm `jq` + `node` available in the scripts shard.
- [x] 0.6 Run the code-review overlap query against the final Files-to-Edit list.

## Phase 1 — Regen script

- [x] 1.1 Create `scripts/regenerate-c4-model.sh` (model on `scripts/generate-kb-index.sh`): `set -euo pipefail`, `--help`, three-source guard, pinned `likec4@1.50.0`, off-tree `mktemp` render, `jq -e '(.elements | length) > 0'` validation BEFORE publish, atomic `cp` onto the tracked path, summary echo. `chmod +x`.
- [x] 1.2 Verify idempotency (run twice -> clean `git status` for the JSON) — AC1.
- [x] 1.3 Verify empty-model clobber protection (break a `.c4`, assert exit non-zero + JSON unchanged) — AC2.

## Phase 2 — CI freshness gate

- [x] 2.1 Create `plugins/soleur/test/c4-model-freshness.test.sh` (or scripts-shard `node --test`): render to temp, byte-diff against committed `model.likec4.json`, FAIL with "run scripts/regenerate-c4-model.sh and commit" on drift — AC5.
- [x] 2.2 Add `npm install -g likec4@1.50.0` runner-tool step to the `test-scripts` shard in `.github/workflows/ci.yml` (mirror the gitleaks-install precedent); confirm it runs inside the job already in the synthetic `test` aggregator's `needs` (no new required check) — AC6.
- [x] 2.3 Verify test fails on a staled fixture, passes on the synced tree.

## Phase 3 — architecture SKILL.md + README fix/mandate

- [x] 3.1 SKILL.md `render`: replace both `npx -y likec4@latest` -> `npx -y likec4@1.50.0` — AC7/AC8.
- [x] 3.2 SKILL.md `diagram`/`add-*`/`render`: add the "regen is automatic on commit via the c4-model-regenerate hook; run scripts/regenerate-c4-model.sh outside the hook" mandate (body prose only) — AC8.
- [x] 3.3 Update `knowledge-base/engineering/architecture/diagrams/README.md` authoring-workflow regen snippet to the script + pinned version + hook.
- [x] 3.4 Confirm no `description:` frontmatter touched -> `bun test plugins/soleur/test/components.test.ts` passes — AC9.
- [x] 3.5 Measure AGENTS.md always-loaded byte budget; add `wg-c4-source-edit-regenerates-compiled-model` pointer only if it fits, else doc-only. Record the number — AC10.

## Phase 4 — Dogfood (lefthook hook + regenerate stale artifact)

- [x] 4.1 Add `c4-model-regenerate` pre-commit command to `lefthook.yml`: `glob: "knowledge-base/engineering/architecture/diagrams/*.c4"`, `run: bash scripts/regenerate-c4-model.sh && git add knowledge-base/engineering/architecture/diagrams/model.likec4.json` — AC3.
- [x] 4.2 Add the advisory warn-only `c4-model.md` staleness reminder (same hook or sibling) — exit 0 always — AC4.
- [x] 4.3 Verify via `lefthook run pre-commit` (stage a `.c4` edit -> JSON regenerated + staged).
- [x] 4.4 Run `scripts/regenerate-c4-model.sh`; commit the freshly-regenerated `model.likec4.json` (brings in email-triage + inngest elements).
- [x] 4.5 Review `c4-model.md` `## Notes` vs `model.c4`; surgically add bullets for any now-modeled-but-unmentioned system (inngest / Resend / email-triage). Human prose, not machine regen.

## Phase 5 — Verify all ACs

- [x] 5.1 Run script idempotency + clobber tests, `lefthook run pre-commit`, the new CI freshness test (pass synced / fail staled), `c4-likec4-version-pin.test.ts`, components budget test, and the full `apps/web-platform/test/c4-*` suite — AC11.
- [x] 5.2 `grep -rn "likec4@" scripts/ lefthook.yml .github/workflows/ci.yml plugins/soleur/skills/architecture/SKILL.md` returns only `1.50.0` — AC7.
