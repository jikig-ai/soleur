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

- [x] 0.1.1 Run OpenCode in each non-CLI mode the install offers (desktop/app/headless `run`) and record whether `OPENCODE` / `OPENCODE_SESSION_ID` / `OPENCODE_TERMINAL` are set in `env`.
- [x] 0.1.2 Record the probe command, version, and the observed variable set per mode in `measurements.md` under a new §1.1 (append-only; do not rewrite §1.0).
- [x] 0.1.3 Decide: if the marker matches a non-CLI process, `detectHarness` does not grow the predicate and Phase 1.2 is dropped. If CLI-only, proceed.
- [x] 0.1.4 If the predicate is dropped, file a follow-up issue and stop Phase 1.2; FR1 and the ADR's detection clause move to a later slice. **Moot — not applicable:** the predicate was retained (see the Outcome below), so no issue was filed and Phase 1.2 ran.

Outcome (2026-10-18): **PASS — the predicate was retained**, so 0.1.4 is moot. Measured on
`opencode v2.0.32`: `OPENCODE` is absent from a clean env, `serve`, `acp`, and the session runtime
process, and present only in tool-spawned children (measurements §1.1). The arm set is wider than
0.1.1 named — the desktop/app mode is not installed on this host, so `acp` (the editor-embedding
entry) and `serve` stand in for the non-session surfaces, and headless `run` was measured directly.

### 0.2 `session.idle` continuation

- [x] 0.2.1 Write a throwaway OpenCode plugin whose `event` handler logs on `session.idle` and attempts to return a continuation / blocking signal. Done as four arms that differ only in module shape and delivery route (measurement §6.6).
- [x] 0.2.2 Record whether a stop can be deferred or continued, or whether the downgrade in ADR-291 (advisory `<promise>DONE</promise>`) is final. Append to `measurements.md` §6.6. **Finding: no blocking Stop contract exists** — the V2 hook surface is enumerated and none of it can defer a stop, force a continuation, or veto a completion, and `ctx.event.subscribe` is a one-way iterator. The advisory downgrade is final. The pass also refuted §6.2–§6.5 (they read the V1 package) and established the V2 module shape `export default { id, setup(ctx) }`.

## Phase 1 — Harness core

### 1.1 RED: harness tests

- [x] 1.1.1 Extend `plugins/soleur/test/harness.test.ts` with an `opencode` case: `detectHarness` returns `opencode` for the measured marker set and leaves a plain env unchanged.
- [x] 1.1.2 Add `formatSkillInvocation` cases: `soleur:plan` under `opencode` → `plan` (bare); a non-soleur name passes through.
- [x] 1.1.3 Add `formatAgentSpawn` cases: `soleur:engineering:cto` under `opencode` → the path id `engineering/cto`.
- [x] 1.1.4 Add the routing-instruction case: the `unknown` text is not returned for an `opencode` session.
- [x] 1.1.5 Run `bun test plugins/soleur/test/harness.test.ts` — confirm RED.

### 1.2 GREEN: `Harness` union + detection

- [x] 1.2.1 Add `"opencode"` to the `Harness` union in `plugins/soleur/lib/harness.ts`.
- [x] 1.2.2 Add the `detectHarness` predicate on `OPENCODE` (only if 0.1.3 cleared), with `OPENCODE_SESSION_ID` / `OPENCODE_TERMINAL` corroboration. Do not use `AI_AGENT`.
- [x] 1.2.3 Order the predicate so it cannot be shadowed by another harness marker.
- [x] 1.2.4 Add the `formatSkillInvocation`, `formatAgentSpawn`, and routing-instruction arms.
- [x] 1.2.5 GREEN `harness.test.ts`.

### 1.3 Workflow fidelity

- [x] 1.3.1 RED: extend `plugins/soleur/test/workflow-fidelity.test.ts` with the `opencode` invocation form.
- [x] 1.3.2 Add the `opencode` arm to `plugins/soleur/lib/workflow-fidelity.ts` where the invocation form differs.
- [x] 1.3.3 GREEN.

Outcome (2026-10-18): RED confirmed at **8 failing arms**, all `opencode`-specific, then GREEN with no
collateral. The full plugin bun suite passes (4519 pass / 0 fail). Three deviations from the letter of
the plan, recorded:

- **1.2.2 is `OPENCODE`-only, no corroboration.** §1.1 shows the corroborating variables are always
  co-present, so requiring them would only add a way to miss a live session.
- **An `agentIdToPath` inverse was needed** (`plugins/soleur/lib/agent-registry.ts`). Only
  `pathToAgentId` existed, and OpenCode keys agents on the path form.
- **A predicate change is a cross-cutting env-boundary change.** Adding a detectable harness makes
  the suite's ambient environment observable: six test files manipulate harness markers, and this
  suite itself runs inside an OpenCode session, so each needed the OpenCode keys added to its sweep
  (`harness`, `workflow-fidelity`, `codex-harness`, `devin-harness`, `codex-plugin`, `devin-plugin`).
  Two harness-enumeration loops gained `opencode` (`pr-merge-poll` queue-mode sweeps, and the
  parked-deliverable contract, which for OpenCode is the *only* enforcement — there is no blocking
  Stop hook). Verified no runtime consumer outside tests imports `detectHarness`; the hooks do not
  call it, so no script needed changing.

Also delivered beyond the plan's list, because every `Harness` arm is expected to be total: a
`pollInstructions` arm (no wait primitive measured → bounded foreground `gh` loop, stated as such)
and a `routingInstructions` arm.

## Phase 2 — Generator (ADR-245 obligation)

### 2.1 RED: generator drift test

- [x] 2.1.1 Create `plugins/soleur/test/opencode-adapter-drift.test.ts`.
- [x] 2.1.2 Write failing cases: a hand-edited stub fails `--check`; a missing stub fails `--check`; a canonical agent with no stub fails `--check`; a clean run exits 0.
- [x] 2.1.3 Run `bun test plugins/soleur/test/opencode-adapter-drift.test.ts` — confirm RED.

### 2.2 Generator script

- [x] 2.2.1 Create `plugins/soleur/scripts/sync-opencode-adapter.ts`, modelled on `sync-grok-agent-compat.ts` and `sync-cursor-name-map.ts`, with a `--check` mode that exits non-zero on drift.
- [x] 2.2.2 Walk `plugins/soleur/agents/**/*.md`; for each, emit `plugins/soleur/opencode/agents/<relpath>.md` with frontmatter `mode: subagent`, `description:` copied from the canonical agent, **no `model:` line**, and a body pointing at the canonical agent file. (`model: inherit` was measured to drop the agent entirely — §11.2; omit the key instead.)
- [x] 2.2.2b Correction pass 2026-10-18: drop `model: inherit` from the generator and regenerate all 67 stubs (measurement §11.2). End-to-end proof after the fix: `GET /api/agent` = 74 (7 built-in + 67 stubs), `GET /api/skill` = 105 (103 canonical + 2 built-in), `GET /api/command` = 6 (2 built-in + 4 Soleur).
- [x] 2.2.3 Walk `plugins/soleur/commands/*.md`; emit `plugins/soleur/opencode/commands/<name>.md` preserving `$ARGUMENTS`.
- [x] 2.2.4 Emit `plugins/soleur/opencode/opencode.json` declaring the canonical `skills` root and `instructions`.
- [x] 2.2.5 Emit `plugins/soleur/opencode/INSTRUCTIONS.md` with the routing/tool sections (see 5.3).
- [x] 2.2.6 Ensure the emitted agent path **is** the agent id (e.g. `opencode/agents/engineering/cto.md` → `engineering/cto`).
- [x] 2.2.7 GREEN `opencode-adapter-drift.test.ts`; `--check` exits 0 on a clean tree.

### 2.3 Hygiene

- [x] 2.3.1 Run the repo formatter/linter over the generated tree (biome / markdownlint as configured for `plugins/soleur`).
- [x] 2.3.2 Confirm the generator is idempotent: a second run is byte-identical.

## Phase 3 — Hook plugin + registry (ADR-223)

### 3.1 Disposition ledger

- [x] 3.1.1 Create the OpenCode hook disposition ledger, one row per hook, mirroring `.claude/hooks/devin-dispositions.tsv`'s shape and every row carrying a disposition (bind / downgraded / already-covered-by-config / absent-with-reason). 13 rows in `.claude/hooks/opencode-dispositions.tsv`, pinned by `test/opencode-plugin.test.ts`.

### 3.2 Plugin module

- [x] 3.2.1 Create `plugins/soleur/opencode/plugin.ts` in the **V2** shape `export default { id, async setup(ctx) { … } }` (the V1 named-export form is rejected — measurement §6.6 arm A): `ctx.permission.hook("evaluate")` for the Bash credential guard and destructive-command guard; `ctx.session.hook("context")` for the session-start rule injection; `ctx.session.hook("compaction")` plus `context` for the compaction re-read directive.
- [x] 3.2.1b **Correction pass 2026-10-19 (measurement §12.1/§12.2), replacing what 3.2.1 originally specified.** The guards bind at `permission.evaluate`, not `tool.hook("execute.before")`, and there is no `shell.hook("create.before")` binding. Two measurements forced it: (1) the shell tool's wire name is **`shell`**, so a map keyed on `bash` never matched and the guard dispatch was a silent no-op; (2) `tool.execute.before` fires *before* `permission.evaluate` and can only refuse by throwing, so binding it would preempt the permission hook and collapse every guard's `ask` into a refusal. `permission.evaluate` carries a mutable `effect: allow|ask|deny` plus `message`, measured to block on `deny` and to hold the tool open on `ask` — so `ask` is delivered as a real prompt and nothing is downgraded.
- [x] 3.2.2 Subscribe to `ctx.event.subscribe()` and record the advisory completion-marker state. **Measured (§6.6, §12.4): no hook can block a stop** — this row is observation-only and must not claim a block or a continuation.
- [x] 3.2.3 Reuse the existing guard scripts where they are harness-agnostic; do not re-implement the credential or destructive-command logic. Both bind by path to `hooks/*.sh`, which run unmodified.
- [x] 3.2.4 No vendor pin exists to take. `@opencode/plugin@2.0.32` is not on this module's import graph: the V2 loader accepts a plain default-exported object (measurement §6.6 arms B/C), so the module imports only `node:` builtins and carries no runtime dependency. ADR-245's vendor-pin policy is therefore satisfied vacuously — there is no vendor package to version-skew. (The V1 package `@opencode-ai/plugin@1.19.3` remains the wrong generation; its module shape is rejected by the 2.0.32 runtime.)

### 3.3 RED: hook tests

- [x] 3.3.1 Add a unit test that the credential guard fires on a representative shell payload through `decidePermission`, and that its decision lands on the permission event with `effect` and `message` set.
- [x] 3.3.2 Add a unit test that the destructive-command guard refuses a representative payload — and that at least one real command reaches `ask`, since the ask path is what a throw-based binding would have destroyed.

### 3.4 `INSTRUCTIONS.md` "Hooks and completion"

- [x] 3.4.1 State which hooks fire, which are downgraded, and that compaction re-read **is** delivered (unlike Codex/Devin). State the completion marker as advisory.

### 3.5 Gate: hook firing captured

- [x] 3.5.1 In a live OpenCode 2.0.32 session with the adapter installed, capture the guards actually dispatching end to end (measurement §12.5, appended as §12 not §6.7): `agent-browser snapshot` came back `permission.rejected` carrying the credential guard's message and the model read it and corrected the command; `terraform destroy` stayed `running`, the guard's real ask. §12.1 also records the raw hook fire order and `permission.evaluate`'s payload shape.

## Phase 4 — Discovery proof in CI

### 4.1 RED: discovery tests

- [x] 4.1.1 Move `opencode` off the *refused* harness name in `plugins/soleur/test/harness-discovery-smoke.test.ts` to a still-unknown name (`cursor`; commit `05a3e2582b`).
- [x] 4.1.2 Write failing cases: a hermetic `skill.list` payload keyed on `path` distinguishes canonical registrations; a shrunken listing exits 1 naming the loss; an unreadable payload exits 3.

### 4.2 GREEN: parser + arm

- [x] 4.2.1 Add the `opencode` arm to `plugins/soleur/scripts/harness-discovery-smoke.ts`: extend the `Harness` type and `parseArgs`, and add a parser keyed on `path` (not `name`).
- [x] 4.2.2 Control `HOME` and the project dir so global skill roots cannot pollute the fixture (`resolveBin` + hermetic `HOME`/`XDG_*`; §11.6).
- [x] 4.2.3 Inherit ADR-245's exit taxonomy (3 = unresolved/unreadable, 1 = measured loss). The listing is polled to settlement; the payload is read from a file (§11.6).
- [x] 4.2.4 GREEN `harness-discovery-smoke.test.ts` — 48 pass, and the live arm exits 0 (`ok (mode=single)`) in ~5 s.

### 4.3 CI job

- [x] 4.3.1 Add the OpenCode arm to the `harness-discovery` CI job, non-required, matching the Codex/Devin arms. `@opencode/cli@2.0.32` installed by npm with the version asserted before the arm runs (the version-mismatch guard mirrors the Codex arm); `OPENCODE_PIN` is job-level `env` declared once, and `--pin` is passed to the script so a lagging pin cannot turn the check into a no-op. The package is `@opencode/cli`, **not** `opencode-ai` — the latter's latest is 1.19.3, the previous API generation. `if: '!cancelled()'` on both steps: three vendors now drive the job and one npm outage must not cost the other two their signal. Commit `3fc7d3ece3`. The README's vendor-pin table gained the OpenCode row.

### 4.4 Gate: hermetic install fixture

- [x] 4.4.1 Prove a hermetic install from this checkout registers exactly the declared set (no global leakage), and record the fixture in `measurements.md` (§11.4, §11.6).

## Phase 5 — Model tiers + tool map

### 5.1 RED: model map

- [x] 5.1.1 Extend `plugins/soleur/test/harness-model-map.test.ts` with the `opencode` entry: each semantic tier resolves to a `provider/model` id, `cheap` is never the flagship, no tier names a trial-terms model, `inherit` passes through, `detectHarness(OPENCODE)` reaches the same map, and the inlined fence is pinned at **four** literals (grok, claude, opencode, all-inherit) with `OPENCODE` added to the fence-execution `envCases` in its three load-bearing orderings.

### 5.2 GREEN: tier map

- [x] 5.2.1 Add the `opencode` entry to `TIER_MAPS` in `plugins/soleur/lib/harness-model-map.ts` following ADR-110's bump-one-table rule. `cheap` → `opencode/glm-5.3-flash-free`; `standard`/`strong`/`advisor` → `opencode/big-pickle`; `inherit` → `inherit`. Basis and the rejected candidates (NVIDIA trial rows, paid Zen SKUs) are in measurement §12.7 and in the file docblock.
- [x] 5.2.2 Update each inlined `TIER_MAPS` copy inside `skills/*/workflows/*.workflow.js` behind the `<!-- harness-model-map:start/end -->` markers so the inlined copies match this file. Seven files, byte-identical fences; the `var claude` / `var opencode` / `var grok` declaration order now mirrors `detectHarness`'s precedence (CLAUDECODE → OPENCODE → GROK).
- [x] 5.2.3 GREEN `harness-model-map.test.ts` — 17 pass. Commit `fad0d3c7e4`.

### 5.3 Tool map

- [x] 5.3.1 Add the OpenCode rows to the `harness-tool-map.ts` coverage: `OPENCODE_INSTRUCTIONS` exported alongside the Codex and Devin paths, and the coverage property generalised from "BOTH tables" to a `TABLES` list so a new harness cannot join the corpus without joining the gate. Non-vacuity proven by mutation: renaming the `SendMessage` row, and blanking the `Bash` translation, each red with the exact skill path and line that uses the name.
- [x] 5.3.2 Add the `## Tools` table to the generated `opencode/INSTRUCTIONS.md` (source: the generator's `instructions()` template) covering the closed vocabulary; the absent set (`TodoWrite`/`TodoRead` — no `todo` tool; `Monitor`/`AwaitShell`/`TaskOutput` — no await primitive; `Cron*`/`PushNotification`/`RemoteTrigger`/`ScheduleWakeup`; `TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate`/`TaskStop`; `NotebookEdit`) is stated as unsupported rather than omitted. 36 rows parse, no blank translation. Measurement §12.8 also corrected the Agents section's "Task tool" to V2's `subagent`.
- [x] 5.3.3 GREEN `harness-tool-map.test.ts` — 7 pass.

## Phase 6 — Parity census + docs

### 6.1 Population globs

- [x] 6.1.1 Add the OpenCode front-door globs to `POPULATION_GLOBS` in `plugins/soleur/lib/harness-parity.ts` (`opencode/agents/**/*.md` policy `agent`, `opencode/commands/*.md` policy `command`), beside the Codex/Devin rows. They are front doors for a different reason: Codex/Devin re-use the skill tree, OpenCode's shims ARE those globs (the canonical `skills/` dir registers through a config key), so this is the only place the generated prose was outside the census.
- [x] 6.1.2 RED then GREEN `plugins/soleur/test/harness-parity.test.ts`. RED was the tree test's population pin (`Expected: 323 / Received: 394`); after the count and floor updates, 474 pass / 0 fail across the pair, and the census reports **394 docs, 0 non-canonical**. `opencode/INSTRUCTIONS.md` stays out for the same measured reason as the Codex and Devin one: each carries the *typed* slash form as its subject (`/go`, `/soleur:go`), the ADR-226 §4 human-typed entry-point class.

### 6.2 Tree test

- [x] 6.2.1 Update `plugins/soleur/test/harness-parity-tree.test.ts` so the generated OpenCode tree is pinned to the registry. Counts alone admit the drift that matters (a stub for a RETIRED agent, or one agent's stub overwritten by another's); a second test compares the path SETS by prefix swap, non-vacuously, so both a missing and an extra stub red.

### 6.3 BOUNDARY re-read record

- [x] 6.3.1 Record in the ADR that the ADR-226 §Consequences re-read was performed and `BOUNDARY` is unchanged; no code change. `@`, `/` and `$` were already sigils, so the re-read admits nothing new — and the sentence now says why that is a decision rather than a deferral.
- [x] 6.3.2 Grep the generated OpenCode docs for `@`-mention sites. Measured: `grep -rn "@" plugins/soleur/opencode/{agents,commands}` is **empty**, so there is no site to canonicalise or wrap. Recorded in the ADR beside the re-read, because "0 sites" is the measurement that makes the unchanged `BOUNDARY` a decision.

### 6.4 Docs + counts

- [x] 6.4.1 Update `plugins/soleur/README.md` component counts and the harness table only if the support bar is met (Phase 7). Support bar met (7.1.1–7.1.5, SHAPE-NOTE.md), so: **counts verified unchanged** — `bash scripts/sync-readme-counts.sh --check` → "All component counts are in sync" (67 agents / 4 commands / 103 skills), corroborated by 6.4.2's `components.test.ts` (1436 pass); **the harness-table row landed in the Step 2.0 harness table of `plugins/soleur/commands/go.md`** — the table 6.4.2's phrasing ("the README tables are unchanged; the harness *table* row waits on Phase 7") separates from them, and the one Cursor shipped a row into — as an OpenCode row plus one paragraph/bullet in each of the three `harness-forms` regions; census pin moved 44 → 48 with the dated note in `harness-parity-tree.test.ts` (still one file, three regions). The README's `### Harness support` (compaction) table is **deliberately not extended**: an OpenCode row there is a public compaction-support claim, and the hook the rules injection and the compaction re-read both ride (`session.hook("context")`) carries an unreconciled later non-fire (§12.3 vs. the later probe pair) — recorded as measurement §14, not claimed. Tracked for follow-up rather than deferred silently.
- [x] 6.4.2 Run `bun test plugins/soleur/test/components.test.ts` — 1423 pass. The adapter adds no canonical component, so the README tables are unchanged; the harness *table* row waits on Phase 7.

## Phase 7 — Support bar + ship

### 7.1 Four-point support bar (ADR-274 shape)

- [x] 7.1.1 `/go` in a live OpenCode session classifies the intent (`opencode`, not `unknown`). — SHAPE-NOTE §7.1.1 (live session): `detectHarness(process.env)` → `"opencode"` (markers `OPENCODE=1`, `AI_AGENT=opencode`), `resolveGoRoute("plan")` → `{kind:"skill", skill:"brainstorm"}`, `dispatchGoRoute` → `{harness:"opencode", tool:"skill", command:"brainstorm"}`; §1.0/§7.0 record the predicate and marker precedence.
- [x] 7.1.2 One pipeline skill completes its gates end to end. — SHAPE-NOTE §7.1.2, measuring §12.5: in a hermetic installed-adapter session a model met the credential guard's block (`agent-browser snapshot` → `permission.rejected`), read the message, ran the routed variant, and that call **completed** — the installed module, generated config, and canonical guard script were all on the path. **Substituted evidence, disclosed in SHAPE-NOTE:** the completion is one routed call after a guard block, not a full skill gate sequence; a full run needs provider credentials the probe host does not have (#10591 item 1).
- [x] 7.1.3 One agent spawn runs, or is refused in words. — SHAPE-NOTE §7.1.3: `spawnAgent(cto)` → `{tool:"subagent", agent:"engineering/cto"}` with the canonical agent path and `opencode/INSTRUCTIONS.md` in the prompt; generated stubs carry `mode: subagent`. Refusal-in-words was observed for unsafe actions (§12.5), never a silent absence. **Substituted evidence, disclosed in SHAPE-NOTE:** the capture is the returned dispatch, not a live `subagent` call on the wire (#10591 item 1).
- [x] 7.1.4 Both guards fire (from 3.5). — SHAPE-NOTE §7.1.4, measuring §12.5: credential guard → `permission.rejected` on `shell`; destructive-command guard → `effect:"ask"` held open on `terraform destroy` (a real blocking prompt, not downgraded, per D10). Dispositions ledger: `.claude/hooks/opencode-dispositions.tsv`.
- [x] 7.1.5 Commit a shape note quoting all four, with the captured evidence. — `knowledge-base/project/specs/feat-opencode-harness/SHAPE-NOTE.md` (committed), quoting all four points with the captures and naming its evidence sources (measurements §1.0, §6.6, §11.1–§11.6, §12.1–§12.8; the dispositions ledger; the in-session probe; 547 pass in the targeted parity/drift set).

### 7.2 Legal gate

- [x] 7.2.1 Grep `knowledge-base/legal` for future-tense harness sentences; route hits to the CLO before any public page edit. — **Run 2026-10-19, 130 files, zero hits to route:** `grep -rn -i "opencode" knowledge-base/legal --include="*.md"` → **2 matches, both in `drafts/`** (unsent convergence-CCLA replies naming the branch `feat-opencode-harness`, carrying no support promise); the tight future-tense sweep `grep -rnoiE "[^.]{0,120}\b(will (be )?(add|support|include|ship|work)|coming soon|planned support|is planned|roadmap)\b[^.]{0,120}"` piped through harness/CLI/plugin terms → **1 match, unrelated** (a Supabase member-read policy in `data-processing-agreement-template.md`). No sentence in `knowledge-base/legal` promises harness support, so there is nothing to route to the CLO. One **present-tense** enumeration exists and is *not* touched by this PR: CLO attestation `audits/2026-09-13-clo-attestation-8119-harness-neutral.md` pins the union as four members and quotes the public parenthetical as `including Claude Code, Grok Build, Codex, and Devin CLI` — the parenthetical is non-exhaustive and the attestation is a dated record of #8119, so neither is falsified by adding a fifth union member; **any future edit to those canonical pages remains a public-page edit and routes to the CLO first.** Recorded as measurement §13.

### 7.3 PR finalization

- [x] 7.3.1 Add a `## Changelog` section to the PR body (`semver:minor` — a new harness adapter). — PR #10571 body; label `semver:minor` applied.
- [x] 7.3.2 Do NOT add a `version` key to any plugin manifest (#7471). — unchanged: the diff adds no manifest and no `version` key.
- [x] 7.3.3 Attach the 3.5 and 7.1 capture evidence. — SHAPE-NOTE §3.5/§7.1.* committed; §7.1.2/§7.1.3 now name their substituted-evidence scope (#10591).
- [x] 7.3.4 `/ship` skill — pre-ship gates, mark ready for review. — **done 2026-10-19/20 on PR #10571.** Pre-ship gates ran and passed: `.github/scripts/check-pr-body-vs-diff.sh` (`PR_NUMBER=10571`) → no-op, `technical-ruling-gate.sh --pr-body` → PASS (no unscoped owner-decision label, no pending placeholder), `pr-overlap-preflight.sh --mode merge` → exit 13 (five overlapping open PRs, none blocking), `hold-gate-eval.sh` → 0 holds. `pr ready` was run with a rationale: the review panel was green after the P1/P2 fix round. PR un-drafted (ready for review) and merged through the merge queue at `95562f22ffb4`.

### 7.4 Post-merge

- [x] 7.4.1 Verify release/deploy workflows succeed. — **verified 2026-10-20** on merge commit `95562f22ffb4` (PR #10571, merged 2026-10-19T23:40:33Z through the merge queue). All 11 post-merge workflows green: `Version Bump and Release` → `v3.342.0` published 23:41:29Z (minor bump off the `semver:minor` label; `v3.341.0` was the prior tag), `Web Platform Release`, `Deploy Documentation to Cloudflare Pages`, `Push on main`, `CI`, `CodeQL Main Alert Gate`, `secret-scan`, `vendor-pin-verify`, `Tenant integration (dev-Supabase)`, and both `skill-security-scan` arms — all `completed/success`, 0 failures.
- [x] 7.4.2 Flip ADR-291 `status: adopting` → `accepted` once 7.1 is quoted. — **done 2026-10-20**. `status: accepted` in the frontmatter and the Status section rewritten to carry the evidence footing forward: all four ADR-274 points are quoted in `SHAPE-NOTE.md`, with §7.1.2 and §7.1.3 on disclosed substituted evidence (no provider credentials on the probe host), live reproduction tracked in #10591 item 1. The flip-time sweep of `knowledge-base/legal` for future-tense harness-list claims returned zero hits (nothing to route to the CLO), and no public "supports OpenCode" claim was made — README/getting-started/comparison/blog/battlecard unchanged.

## Completion Gate

All boxes checked. ADR-291 status flipped. Four-point support bar quoted with captured evidence.
`harness-discovery` OpenCode arm green on a hermetic fixture and red on a dropped root. Generator
`--check` green in CI. `harness-parity` census and tree tests green with the new globs. Legal grep
routed. No `version` key added to any manifest.
