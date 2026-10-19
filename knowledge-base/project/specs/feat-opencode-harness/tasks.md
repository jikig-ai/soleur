---
feature: OpenCode harness adapter
branch: feat-opencode-harness
spec: knowledge-base/project/specs/feat-opencode-harness/spec.md
measurements: knowledge-base/project/specs/feat-opencode-harness/measurements.md
adr: knowledge-base/engineering/architecture/decisions/ADR-291-add-an-opencode-plugin-adapter.md
status: ready-for-work
---

# Tasks: OpenCode harness adapter

Ordering rule: every phase opens with its RED tests (hard rule `cq-write-failing-tests-before`).
Phases 0 and 3.5 are measurement gates, not code — they gate the claim, not the commit.

## Phase 0 — Measurement gates (prerequisites)

### 0.1 Detection CLI-specificity (ADR-274 bar)

- [ ] 0.1.1 Run OpenCode in each non-CLI mode the install offers (desktop/app/headless `run`) and record whether `OPENCODE` / `OPENCODE_SESSION_ID` / `OPENCODE_TERMINAL` are set in `env`.
- [ ] 0.1.2 Record the probe command, version, and the observed variable set per mode in `measurements.md` under a new §1.1 (append-only; do not rewrite §1.0).
- [ ] 0.1.3 Decide: if the marker matches a non-CLI process, `detectHarness` does not grow the predicate and Phase 1.2 is dropped. If CLI-only, proceed.
- [ ] 0.1.4 If the predicate is dropped, file a follow-up issue and stop Phase 1.2; FR1 and the ADR's detection clause move to a later slice.

### 0.2 `session.idle` continuation

- [ ] 0.2.1 Write a throwaway OpenCode plugin whose `event` handler logs on `session.idle` and attempts to return a continuation / blocking signal.
- [ ] 0.2.2 Record whether a stop can be deferred or continued, or whether the downgrade in ADR-291 (advisory `<promise>DONE</promise>`) is final. Append to `measurements.md` §6.6.

## Phase 1 — Harness core

### 1.1 RED: harness tests

- [ ] 1.1.1 Extend `plugins/soleur/test/harness.test.ts` with an `opencode` case: `detectHarness` returns `opencode` for the measured marker set and leaves a plain env unchanged.
- [ ] 1.1.2 Add `formatSkillInvocation` cases: `soleur:plan` under `opencode` → `plan` (bare); a non-soleur name passes through.
- [ ] 1.1.3 Add `formatAgentSpawn` cases: `soleur:engineering:cto` under `opencode` → the path id `engineering/cto`.
- [ ] 1.1.4 Add the routing-instruction case: the `unknown` text is not returned for an `opencode` session.
- [ ] 1.1.5 Run `bun test plugins/soleur/test/harness.test.ts` — confirm RED.

### 1.2 GREEN: `Harness` union + detection

- [ ] 1.2.1 Add `"opencode"` to the `Harness` union in `plugins/soleur/lib/harness.ts`.
- [ ] 1.2.2 Add the `detectHarness` predicate on `OPENCODE` (only if 0.1.3 cleared), with `OPENCODE_SESSION_ID` / `OPENCODE_TERMINAL` corroboration. Do not use `AI_AGENT`.
- [ ] 1.2.3 Order the predicate so it cannot be shadowed by another harness marker.
- [ ] 1.2.4 Add the `formatSkillInvocation`, `formatAgentSpawn`, and routing-instruction arms.
- [ ] 1.2.5 GREEN `harness.test.ts`.

### 1.3 Workflow fidelity

- [ ] 1.3.1 RED: extend `plugins/soleur/test/workflow-fidelity.test.ts` with the `opencode` invocation form.
- [ ] 1.3.2 Add the `opencode` arm to `plugins/soleur/lib/workflow-fidelity.ts` where the invocation form differs.
- [ ] 1.3.3 GREEN.

## Phase 2 — Generator (ADR-245 obligation)

### 2.1 RED: generator drift test

- [ ] 2.1.1 Create `plugins/soleur/test/opencode-adapter-drift.test.ts`.
- [ ] 2.1.2 Write failing cases: a hand-edited stub fails `--check`; a missing stub fails `--check`; a canonical agent with no stub fails `--check`; a clean run exits 0.
- [ ] 2.1.3 Run `bun test plugins/soleur/test/opencode-adapter-drift.test.ts` — confirm RED.

### 2.2 Generator script

- [ ] 2.2.1 Create `plugins/soleur/scripts/sync-opencode-adapter.ts`, modelled on `sync-grok-agent-compat.ts` and `sync-cursor-name-map.ts`, with a `--check` mode that exits non-zero on drift.
- [ ] 2.2.2 Walk `plugins/soleur/agents/**/*.md`; for each, emit `plugins/soleur/opencode/agents/<relpath>.md` with frontmatter `mode: subagent`, `description:` copied from the canonical agent, `model: inherit`, and a body pointing at the canonical agent file.
- [ ] 2.2.3 Walk `plugins/soleur/commands/*.md`; emit `plugins/soleur/opencode/commands/<name>.md` preserving `$ARGUMENTS`.
- [ ] 2.2.4 Emit `plugins/soleur/opencode/opencode.json` declaring the canonical `skills` root and `instructions`.
- [ ] 2.2.5 Emit `plugins/soleur/opencode/INSTRUCTIONS.md` with the routing/tool sections (see 5.3).
- [ ] 2.2.6 Ensure the emitted agent path **is** the agent id (e.g. `opencode/agents/engineering/cto.md` → `engineering/cto`).
- [ ] 2.2.7 GREEN `opencode-adapter-drift.test.ts`; `--check` exits 0 on a clean tree.

### 2.3 Hygiene

- [ ] 2.3.1 Run the repo formatter/linter over the generated tree (biome / markdownlint as configured for `plugins/soleur`).
- [ ] 2.3.2 Confirm the generator is idempotent: a second run is byte-identical.

## Phase 3 — Hook plugin + registry (ADR-223)

### 3.1 Disposition ledger

- [ ] 3.1.1 Create the OpenCode hook disposition ledger, one row per hook, mirroring `.claude/hooks/devin-dispositions.tsv`'s shape and every row carrying a disposition (delivered / downgraded / absent-with-reason).

### 3.2 Plugin module

- [ ] 3.2.1 Create `plugins/soleur/opencode/<plugin>.ts` binding: `tool.execute.before` for the Bash credential guard and destructive-command guard; a session-start surface for the rule injection; `experimental.session.compacting` for the compaction re-read directive.
- [ ] 3.2.2 Wire the `event` hook on `session.idle` to record the advisory completion-marker state (per 0.2's finding — do not claim a block if 0.2 found none).
- [ ] 3.2.3 Reuse the existing guard scripts where they are harness-agnostic; do not re-implement the credential or destructive-command logic.
- [ ] 3.2.4 Pin the `@opencode-ai/plugin` dependency and note the CLI-vs-package version skew (CLI 2.0.32 / package 1.19.3, v2 at `/v2/effect`) in a comment. Confirm the pin against ADR-245's vendor-pin policy.

### 3.3 RED: hook tests

- [ ] 3.3.1 Add a unit test that the credential guard fires on a representative Bash payload via the plugin's before-hook.
- [ ] 3.3.2 Add a unit test that the destructive-command guard refuses a representative payload.

### 3.4 `INSTRUCTIONS.md` "Hooks and completion"

- [ ] 3.4.1 State which hooks fire, which are downgraded, and that compaction re-read **is** delivered (unlike Codex/Devin). State the completion marker as advisory.

### 3.5 Gate: hook firing captured

- [ ] 3.5.1 In a live OpenCode session with the plugin installed, capture the credential guard and destructive-command guard actually dispatching (the Devin envelope-capture pattern). Append the capture to `measurements.md` §6.7.

## Phase 4 — Discovery proof in CI

### 4.1 RED: discovery tests

- [ ] 4.1.1 Move `opencode` off the *refused* harness name in `plugins/soleur/test/harness-discovery-smoke.test.ts` to a still-unknown name.
- [ ] 4.1.2 Write failing cases: a hermetic `skill.list` payload keyed on `path` distinguishes canonical registrations; a shrunken listing exits 1 naming the loss; an unreadable payload exits 3.

### 4.2 GREEN: parser + arm

- [ ] 4.2.1 Add the `opencode` arm to `plugins/soleur/scripts/harness-discovery-smoke.ts`: extend the `Harness` type and `parseArgs`, and add a parser keyed on `path` (not `name`).
- [ ] 4.2.2 Control `HOME` and the project dir so global skill roots cannot pollute the fixture.
- [ ] 4.2.3 Inherit ADR-245's exit taxonomy (3 = unresolved/unreadable, 1 = measured loss).
- [ ] 4.2.4 GREEN `harness-discovery-smoke.test.ts`.

### 4.3 CI job

- [ ] 4.3.1 Add the OpenCode arm to the `harness-discovery` CI job, non-required, matching the Codex/Devin arms.

### 4.4 Gate: hermetic install fixture

- [ ] 4.4.1 Prove a hermetic install from this checkout registers exactly the declared set (no global leakage), and record the fixture in `measurements.md`.

## Phase 5 — Model tiers + tool map

### 5.1 RED: model map

- [ ] 5.1.1 Extend `plugins/soleur/test/harness-model-map.test.ts` with the `opencode` entry: each semantic tier resolves to a `provider/model#variant`; `inherit` passes through null.

### 5.2 GREEN: tier map

- [ ] 5.2.1 Add the `opencode` entry to `TIER_MAPS` in `plugins/soleur/lib/harness-model-map.ts` following ADR-110's bump-one-table rule.
- [ ] 5.2.2 Update each inlined `TIER_MAPS` copy inside `skills/*/workflows/*.workflow.js` behind the `<!-- harness-model-map:start/end -->` markers so the inlined copies match this file.
- [ ] 5.2.3 GREEN `harness-model-map.test.ts`.

### 5.3 Tool map

- [ ] 5.3.1 Add the OpenCode column/rows to `plugins/soleur/lib/harness-tool-map.ts` coverage: every `CLAUDE_CODE_TOOLS` name resolves or is stated as unsupported.
- [ ] 5.3.2 Add the `## Tools` table to the generated `opencode/INSTRUCTIONS.md` covering the closed vocabulary; state the absent set (`todo`, `Monitor`/`AwaitShell`, `Cron*`/`PushNotification`/`RemoteTrigger`/`ScheduleWakeup`) as unsupported, and map `TodoWrite` the way Codex does.
- [ ] 5.3.3 GREEN `harness-tool-map.test.ts`.

## Phase 6 — Parity census + docs

### 6.1 Population globs

- [ ] 6.1.1 Add the OpenCode front-door globs to `POPULATION_GLOBS` in `plugins/soleur/lib/harness-parity.ts` (`opencode/agents/**/*.md`, `opencode/commands/*.md`), matching the Codex/Devin front-door rows.
- [ ] 6.1.2 RED then GREEN `plugins/soleur/test/harness-parity.test.ts`.

### 6.2 Tree test

- [ ] 6.2.1 Update `plugins/soleur/test/harness-parity-tree.test.ts` so the generated OpenCode tree is pinned to the registry (a missing or extra stub reds).

### 6.3 BOUNDARY re-read record

- [ ] 6.3.1 Record in the ADR (already drafted) that the ADR-226 §Consequences re-read was performed and `BOUNDARY` is unchanged; no code change.
- [ ] 6.3.2 Grep the generated OpenCode docs for `@`-mention sites; for each, either canonicalise or wrap in a `harness-forms` region so the census does not report a bare sigil.

### 6.4 Docs + counts

- [ ] 6.4.1 Update `plugins/soleur/README.md` component counts and the harness table only if the support bar is met (Phase 7).
- [ ] 6.4.2 Run `bun test plugins/soleur/test/components.test.ts`.

## Phase 7 — Support bar + ship

### 7.1 Four-point support bar (ADR-274 shape)

- [ ] 7.1.1 `/go` in a live OpenCode session classifies the intent (`opencode`, not `unknown`).
- [ ] 7.1.2 One pipeline skill completes its gates end to end.
- [ ] 7.1.3 One agent spawn runs, or is refused in words.
- [ ] 7.1.4 Both guards fire (from 3.5).
- [ ] 7.1.5 Commit a shape note quoting all four, with the captured evidence.

### 7.2 Legal gate

- [ ] 7.2.1 Grep `knowledge-base/legal` for future-tense harness sentences; route hits to the CLO before any public page edit.

### 7.3 PR finalization

- [ ] 7.3.1 Add a `## Changelog` section to the PR body (`semver:minor` — a new harness adapter).
- [ ] 7.3.2 Do NOT add a `version` key to any plugin manifest (#7471).
- [ ] 7.3.3 Attach the 3.5 and 7.1 capture evidence.
- [ ] 7.3.4 `/ship` skill — pre-ship gates, mark ready for review.

### 7.4 Post-merge

- [ ] 7.4.1 Verify release/deploy workflows succeed.
- [ ] 7.4.2 Flip ADR-291 `status: proposed` → `accepted` once 7.1 is quoted.

## Completion Gate

All boxes checked. ADR-291 status flipped. Four-point support bar quoted with captured evidence.
`harness-discovery` OpenCode arm green on a hermetic fixture and red on a dropped root. Generator
`--check` green in CI. `harness-parity` census and tree tests green with the new globs. Legal grep
routed. No `version` key added to any manifest.
