---
title: "feat(inngest): pin --effort high on the six audit crons + CI-gate that the pinned claude-code CLI bundle knows every model-tiers id"
type: feat
date: 2026-09-23
slug: feat-audit-cron-effort-and-cli-model-guard
branch: feat-one-shot-8603-cron-audit-effort-cli-model-guard
issue: 8603
closes: 8603
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# Audit-cron effort pin + pinned-CLI model-id guard

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this
one-shot branch.)

## Overview

This plan covers two coupled changes to how the Inngest crons start the `claude` CLI, shipped as one PR.

1. **Effort pin.** Add `AUDIT_EFFORT = "high"` to `apps/web-platform/server/inngest/model-tiers.ts`,
   next to `AUDIT_MODEL`, together with one shared argv tuple,
   `AUDIT_CLI_ARGS = ["--model", AUDIT_MODEL, "--effort", AUDIT_EFFORT]`. The six crons that use
   `AUDIT_MODEL` replace their `"--model", AUDIT_MODEL,` pair with `...AUDIT_CLI_ARGS,` in their
   `CLAUDE_CODE_FLAGS`, so each one passes `--effort high` alongside `--model claude-opus-5-5`. The
   six are `cron-agent-native-audit`, `cron-architecture-diagram-sync`, `cron-competitive-analysis`,
   `cron-growth-audit`, `cron-legal-audit` and `cron-ux-audit`. Every other cron keeps the CLI
   default. A test pins this. The argv the CLI receives is the same as writing the pair inline, but
   the pairing lives in one place and cannot drift across six hand-edited copies.
2. **Pinned-CLI guard (closes #8603).** Add a CI test with three checks. (a) The pinned
   `@anthropic-ai/claude-code` linux-x64 platform binary contains every Claude model id declared in
   `model-tiers.ts` and `leader-prompts/constants.ts`, matched on a boundary with `grep -a`. This is
   the logic from `audit-models.sh` `[2b]`, now run as a gate. (b) The package.json and Dockerfile
   pins agree. (c) The pinned binary accepts the `AUDIT_EFFORT` value without falling back.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / arguments) | Reality (measured 2026-09-23) | Plan response |
|---|---|---|
| "Opus 5.5 API default effort is medium and no cron passes --effort" | TRUE. Pinned CLI 2.1.280's bundled row reads `{id:"claude-opus-5-5",…,default_effort:"medium",…}`. `git grep -- '--effort' origin/main -- apps/web-platform` returns nothing. | The effort pin is still needed. |
| "The pinned claude CLI 2.1.280 accepts `--effort <low\|medium\|high\|xhigh\|max>`" | TRUE. The bundle has `lu=["low","medium","high","xhigh","max"]`. **But an unknown VALUE is not an error.** `claude --effort bogus --version` prints `Warning: Unknown --effort value 'bogus' — ignoring it and using the default effort. Valid values: low, medium, high, xhigh, max.` and exits 0. The `--print` path does the same. An unknown flag NAME (`--efort`) is a hard `error: unknown option` with rc=1 in `--print` mode. | A mistyped value falls back silently, so the flag-validity check is load-bearing, not optional (Guard 3). A mistyped flag name already fails loudly at runtime, and Guard 1 pins the exact string. |
| "Guard must run against the pin, not node_modules" | `audit-models.sh [2b]` greps `node_modules` and only prints a NOTE when the installed version differs from the pin. In CI, `test-webplat` runs `npm ci --ignore-scripts`, which installs the linux-x64 optional dep from the lockfile's `resolved` URL and checks its `integrity`. The lockfile integrity `sha512-dJHWFrDS…0Ck6Q==` matches the registry tarball byte for byte (`openssl dgst -sha512` on the downloaded `claude-code-linux-x64-2.1.280.tgz`, 105 MB, about 12 s locally). | The **property** stays: we measure the pinned bytes. The **mechanism** changes. Read the npm-ci-installed tree, but only after proving it IS the pin: `claude --effort <AUDIT_EFFORT> --version` must print that pin. A mismatch or a missing file is a hard FAIL in CI with the `npm ci` remedy, never a NOTE. See Cut List C1. |
| "audit-models.sh [2b] is the only check today" | TRUE. `--detect` returns before `[2b]`, and no CI job runs it. | Keep `[2b]` as the hand-run advisory. The new test's header cites it, and model-launch-review SKILL.md step 2b names the CI twin. |
| cron-bash-allowlist-hook might validate cron argv | FALSE. `cron-bash-allowlist-hook.mjs` gates the **agent's Bash tool commands** inside the spawn, not the `claude` argv (`_cron-claude-eval-substrate.ts` `ALLOWLIST_REL_PATH` / `parseAllowlist`). The substrate only prepends `--strict-mcp-config` (and `--output-format` when absent) in front of the cron's flags. | No allowlist change. |
| Existing tests pin the exact argv arrays | FALSE. `cron-ux-audit.test.ts`, `cron-claude-eval-mcp-flags.test.ts` and `cron-producer-output-wiring.test.ts` use `indexOf`/order checks (`--plugin-dir` before `"--"`). Nothing does a full `toEqual` on an audit cron's array. | No existing test needs editing. Guard 1 adds the new pins. |

## Research Insights

**Premise Validation (Phase 0.6).**

- #8603 is OPEN (`gh issue view 8603`).
- PR #8601 is MERGED (2026-09-23T16:21Z). It moved the CLI pin to 2.1.280 in `apps/web-platform/package.json:32`, the lockfile (stub plus all eight platform entries) and `apps/web-platform/Dockerfile:57`, and set `AUDIT_MODEL = "claude-opus-5-5"`.
- #7773 is CLOSED.
- `origin/main` has no commits beyond this branch's base, and no `--effort` or `AUDIT_EFFORT` anywhere.
- ADR corpus: ADR-053's "Addendum — 2026-09-23 (Opus 5.5 launch, PR #8601)" says effort *"is a flag for the model-launch-review Thinking-API item, not a config change"*. This plan **reverses** that sentence, so it must amend ADR-053 (Phase 2.10). No ADR lists a per-tier effort pin among its rejected alternatives.

**Property List (Phase 0.6b).**

- P1: The six audit-tier crons run claude-opus-5-5 at `high` effort, not the CLI's per-model default (`medium`).
- P2: No non-audit cron changes effort. It stays on the CLI default.
- P3: A PR that hands the cron CLI a model id missing from the pinned bundle cannot merge. This covers a swap before a bump, and a bump that drops an id.
- P4: A PR that sets an effort value the pinned CLI does not accept cannot merge. Today that failure is a silent fallback.
- P5: The package.json and Dockerfile pins cannot drift apart silently. package.json and the lockfile are already held together by `npm ci`. The Dockerfile carries a "KEEP IN SYNC" comment but has no mechanism enforcing it.

**Cut List (Phase 0.6b).**

- **C1 — fetch the registry tarball per CI run → P3 → already covered by `npm ci`.** Downloading `@anthropic-ai/claude-code-linux-x64@<pin>` (105 MB) and checking its sha512 re-does what `npm ci` already does in `test-webplat` from the same lockfile `resolved` + `integrity`. The one risk this fetch would guard against is a stale local install. That risk is closed by asserting installed version == lockfile pin == `--version` output, and failing closed. The fetch would add network flakiness and about 105 MB per PR, and buys no extra property.
- **C2 — check the per-model effort capability row (silent downgrade) → P1 → not worth it.** The CLI can silently downgrade effort for a model without the `effort` capability. The claude-opus-5-5 row carries `"effort","max_effort","xhigh_effort"`, and every Opus since 4.5 does. A static grep of the minified row shape would break on every table-format change and catch no realistic failure.
- **C3 — full-argv `--version` probe to catch flag-name typos → P4 → does not work.** Measured: `claude --print --efort high --version` exits 0, because `--version` short-circuits before unknown options are rejected. Flag-name correctness is covered by Guard 1's exact-token assertion, plus the loud runtime `unknown option` error.
- **C5 (plan-review): cuts made after the review.** Each item names the mechanism, what it was for, and what already covers it.
  - A `ClaudeCliEffort` TS union with `satisfies` (P4): Guard 3's probe covers it, and a hand-copied union can go stale.
  - Exporting and importing the six `CLAUDE_CODE_FLAGS` arrays (P1): walks (a), (b) and (e) cover it.
  - A four-way lockfile pin read (P5): `npm ci` already enforces package.json = lockfile.
  - A package.json name/version identity read plus a separate `--version` spawn (P3): the single Guard 3 spawn's `--version` output covers it.
  - A runtime-export id enumeration next to the regex harvest (P3): the harvest plus the ⊇ floor covers it.
  - Quote-boundary blob row (P3): the regex accepts it by construction.
  - `DISABLE_*` / `CLAUDE_CONFIG_DIR` env vars: `--version` short-circuits, and the measured run needed only `PATH` + `HOME`.
  - The `audit-models.sh` pointer: the SKILL.md sentence covers it.
- **C4 — a runtime `CLAUDE_CLI_EFFORT_LEVELS` const array compared against the CLI's `Valid values:` list → nothing in P1–P5 needs it.** The TS union type plus Guard 3's probe of the one value actually used is enough.

**Relevant files.**

- `apps/web-platform/server/inngest/model-tiers.ts` (`AUDIT_MODEL`, `EXECUTION_MODEL`).
- `apps/web-platform/server/inngest/leader-prompts/constants.ts` (`SONNET_MODEL`, `HAIKU_MODEL`).
- The six crons' `CLAUDE_CODE_FLAGS` constants. Each has exactly one `"--",` line.
- `_cron-claude-eval-substrate.ts`: `spawnClaudeEval` flags assembly (argv `["--strict-mcp-config", ...outputFormatFlags, ...flags, prompt]`), `resolveClaudeBin()` (prefers `/app/node_modules/.bin/claude`), and stderr lines to `logger.error({fn, stream:"stderr"})` plus `stderrTail`.
- `apps/web-platform/test/server/inngest/model-tiers.test.ts`: the existing comment-stripping source-walk idiom, derived-not-restated `RAW_MODEL_LITERAL`, and the ≥17-file floor.
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` `[2b]`: `ID_BOUNDARY='([^0-9A-Za-z-]|$)'`, the platform-binary-only scope, and the `-a` requirement.
- `plugins/soleur/test/model-launch-review.test.ts`: the `[2b]` fixture tests (prefix shadowing, sibling-SDK scope, skew).
- `apps/web-platform/test/helpers/engines-floor.ts`: the `if (process.env.CI) throw` / dev-skip precedent.
- `.github/workflows/ci.yml` `test-webplat`: `npm ci --ignore-scripts`, then `bash scripts/test-all.sh webplat` (vitest, 2-way shard).

**Institutional learnings applied.**

- `2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens.md` (#6934). An unknown id halves `max_tokens`. Grep with `-a`, and include a known-positive and a known-negative control. The Dockerfile/package.json pins had drifted 118 patches apart.
- `best-practices/2026-07-03-parity-guard-unmodeled-input-must-fail-loud-not-skip.md`. Derive, don't restate. Fail loud on unmodeled input.
- ADR-180 / plan Phase 2.12. Guard Contract with harness rows and must-PASS non-canonical inputs.
- `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`. Delete-the-control rows. Assert the discriminating output (the warning text), not only the rc.
- `2026-05-25-tr9-pr7-roadmap-review-claude-code-spawn-pattern-reuse.md` (#4017). The `--` end-of-options marker is load-bearing. Any flag after it becomes part of the prompt.
- `2026-04-18-action-pin-sync-with-model-bump.md`. Move the CLI pin and model swaps together.

**Measurements (commands and results).**

- `grep -aqE "<id>([^0-9A-Za-z-]|$)" package/claude` on the 2.1.280 binary: `claude-opus-5-5`, `claude-sonnet-5` and `claude-haiku-4-5-20251001` are present. The negative control `claude-opus-9-9` is absent. Each grep takes about 0.08 s over the 233 MB binary.
- `env -i PATH=/usr/bin:/bin HOME=$tmp ./claude --effort high --version` prints `2.1.280 (Claude Code)`, rc=0, stderr empty, in 0.09 s. It writes `$HOME/.claude*`, so the test needs a temp HOME. `--effort HIGH` is accepted (case-insensitive).
- Cron cadence (`routine-metadata.ts`): architecture-diagram-sync weekly (Sun 02:00), growth-audit weekly (Mon 07:00), agent-native-audit monthly (15th), competitive-analysis monthly (1st), ux-audit monthly (1st), legal-audit quarterly. That is about 12 audit-tier runs a month.

**Scoped advisor consult (Step 4.5, advisor tier).** It recommended three changes, all applied.

- Replace six hand-edited `--model`/`--effort` pairs with one shared `AUDIT_CLI_ARGS` tuple spread into each array. This removes the hand-rolled source tokenizer Guard 1 would otherwise need.
- Confirm the CI runner installs and can execute the optional linux-x64 binary before building Guards 2/3 on it. `.npmrc` was checked, and the check is now a Phase 1 precondition.
- Assert that stderr carries no other effort-related line in Guard 3.

**Functional overlap (Phase 1.5b).** `soleur:engineering:discovery:functional-discovery` found no community skill or agent covering this. The nearest in-repo capability is `soleur:model-launch-review` `[2b]`, which is advisory and hand-run.
**Community discovery (Phase 1.5).** Skipped: the stack (TS/Node/vitest) is covered.
**External research (Phase 1.6).** Skipped. Strong local patterns exist, and every CLI behavior was measured directly against the pinned binary above.

## Problem Statement / Motivation

- **Effort.** `claude-opus-5-5`'s bundled default effort is `medium` (Opus 5's was `high`). The audit crons are the deep, multi-step judgment workloads that justified the Opus tier (ADR-053 surface 5b). The #8601 swap quietly lowered their reasoning depth, and nothing in the argv says so.
- **Unknown model id (#8603).** When `AUDIT_MODEL` (or any tier id) is missing from the pinned CLI's bundled model table, the CLI treats it as unknown. It halves `max_tokens` (64000 to 32000, #6934) and takes thinking/effort params from the wrong row. The change passes `tsc`, the whole suite and CI. The only check, `audit-models.sh [2b]`, runs only when someone runs the audit by hand.
- **Unknown effort value.** The same silent class now applies to the new flag. A mistyped `AUDIT_EFFORT` value prints only a stderr warning, and the run falls back to `medium`.

## Proposed Solution

### Files to Edit

- `apps/web-platform/server/inngest/model-tiers.ts`:
  - (No TS union of effort levels. Guard 3's runtime probe against the pinned CLI is the authority, and a hand-copied union could go stale. Plan-review cut it.)
  - Add `export const AUDIT_EFFORT = "high" as const;`, with a comment on the medium default, why audit is `high`, and that execution crons deliberately pass no `--effort`.
  - Add `export const AUDIT_CLI_ARGS = ["--model", AUDIT_MODEL, "--effort", AUDIT_EFFORT] as const;`. Its comment says it is the ONLY place the audit model and effort are paired, and that crons spread it rather than naming `AUDIT_MODEL` or `AUDIT_EFFORT` directly (Guard 1 enforces this).
  - Fix the header comment: the audit list names 5 crons, but there are 6 (add `architecture-diagram-sync`). Add an `AUDIT_EFFORT` / `AUDIT_CLI_ARGS` paragraph.
- `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts`, `cron-architecture-diagram-sync.ts`, `cron-competitive-analysis.ts`, `cron-growth-audit.ts`, `cron-legal-audit.ts`, `cron-ux-audit.ts`:
  - Change the import to `import { AUDIT_CLI_ARGS } from "@/server/inngest/model-tiers";`, dropping `AUDIT_MODEL`.
  - Replace the two lines `"--model",` / `AUDIT_MODEL,` with the one line `...AUDIT_CLI_ARGS,`, in the same position (directly after `"--print",`, well before `"--"`).
  - Do not add exports: Guard 1 is source-level, and none of its checks imports the cron arrays.
  - Leave the historical GHA-contract comments (`--model claude-opus-5-5` mirror lines) alone. They are comments, and Guard 1 strips comments. Fix only the `cron-architecture-diagram-sync.ts:75` prose ("Uses AUDIT_MODEL (opus)…") if it would now mislead; it can say "Uses AUDIT_CLI_ARGS (opus, high effort)".
- `apps/web-platform/test/server/inngest/model-tiers.test.ts`: import `stripComments` from the new helper, then add Guard 1 (a new `describe`) and the identity pins `AUDIT_EFFORT === "high"` and `AUDIT_CLI_ARGS` deep-equals `["--model", AUDIT_MODEL, "--effort", AUDIT_EFFORT]`. Update the header list (e).
- (`audit-models.sh` is unchanged. The new test's header cross-references `[2b]`, and the SKILL.md sentence below records the CI twin. Plan-review cut the duplicate pointer.)
- `plugins/soleur/skills/model-launch-review/SKILL.md`:
  - Checklist row 3 (Thinking-API shape): replace the stale `measured … effort:"high"` with the per-model `default_effort` field (claude-opus-5-5: `medium`). Add that audit crons override it via `AUDIT_EFFORT`, and at each launch the operator re-reads the new row's `default_effort` and re-decides `AUDIT_EFFORT`.
  - Step 2b paragraph: rewrite it as an ordered procedure. (1) Bump the pin in `apps/web-platform/package.json` and the `Dockerfile` global. (2) Regenerate `package-lock.json`, honouring the existing release-age note (`--min-release-age=0` only as an operator waiver). (3) Then run the id swap, all in ONE PR. State plainly that `claude-cli-pin-knows-models.test.ts` now gates this in CI, so an id-swap PR opened before the bump goes red. Say that `[2b]` stays the hand-run check for candidate versions.
  - Do not touch the frontmatter `description:`.
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`: amend the 2026-09-23 addendum. See `## Architecture Decision (ADR/C4)`.

### Files to Create

- `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts`: Guards 2 and 3.
- `apps/web-platform/test/helpers/strip-comments.ts`: move the existing `stripComments` there unchanged from `model-tiers.test.ts`, which then imports it. Guard 1 and the Guard 2 harvest share one comment stripper.

No new workflow, script or CI step. The test is picked up by the existing vitest `unit` project (`test/**/*.test.ts`) and runs in `test-webplat`.

### Guard 2/3 test design (normative for `soleur:work`)

The test file's header comment carries three things:

- a short "on the next CLI bump / model launch" checklist: bump package.json + lockfile + Dockerfile together, re-decide `AUDIT_EFFORT` against the new row's `default_effort`, and update the warning needle if the control fails;
- a cross-reference to `audit-models.sh [2b]`, the source of the boundary and harvest regexes;
- the note that Guard 2 is complete only because Guard 1 walk (c) routes every cron `--model` value through `model-tiers.ts`.

1. **Pin agreement (runs on every host, no binary needed).**
   - `package.json` `dependencies["@anthropic-ai/claude-code"]` must match `^\d+\.\d+\.\d+$` (exact).
   - The Dockerfile `npm install -g @anthropic-ai/claude-code@(\S+)` must match exactly once, and must equal it.
   - package.json ↔ lockfile agreement is not restated, because `npm ci` already fails on it.
   - The failure message names both values and says: bump package.json, regenerate the lockfile, and edit `apps/web-platform/Dockerfile` in one PR (see model-launch-review SKILL.md step 2b and its release-age note).
2. **Id set (runs on every host).** The `[2b]` harvest `/"claude-(opus|sonnet|haiku|fable)-[0-9a-z-]+"/g` over `stripComments(source)` of `model-tiers.ts` and `leader-prompts/constants.ts`. Measured today: exactly the three ids on lines 46, 49 and 50.
   - Anti-vacuity floor: the set ⊇ `{AUDIT_MODEL, EXECUTION_MODEL, HAIKU_MODEL}` (imported constants, so set identity rather than a count).
   - Every id must match `^[a-z0-9-]+$` before it is put into a regex.
3. **Bundle and dispatch (the binary-dependent tests).**
   - `bin = join(APP_ROOT, "node_modules/@anthropic-ai/claude-code-linux-x64/claude")`, and nowhere else. Never resolve through the scope directory: the sibling `claude-agent-sdk*` packages carry sonnet ids.
   - `MUST_RUN = Boolean(process.env.CI) || process.env.GITHUB_ACTIONS === "true" || (process.platform === "linux" && process.arch === "x64")`. The CI terms matter only if a runner is ever not linux-x64; say so in a comment.
   - If `bin` is absent and `MUST_RUN`, throw with `cd apps/web-platform && npm ci`. Otherwise `describe.skip` only this block, with a stderr reason, following the `engines-floor.ts` precedent.
4. **Probe helper.** `bundleHasId(file, id)` runs `grep -aqE "<id>([^0-9A-Za-z-]|$)" <file>` via `spawnSync` (argv array, no shell), with `env: { LC_ALL: "C", PATH }`. In a UTF-8 locale, a byte after the id that is not valid UTF-8 would fail the bracket class and report a present id as absent. Status 0 means present, 1 means absent, and anything else throws. That covers the "could not look" versus "absent" conflation (#5100).
5. **Per-id assertion.** Collect every ABSENT id, then call `expect(absent).toEqual([])`. The message names the ids and the pin, and says to bump to a version whose bundle carries them. Collecting first means the loop quantifies over all ids and does not stop at the first.
6. **Real-bundle negative control.** `bundleHasId(bin, "claude-zz-not-a-model-0")` must be false.
7. **Helper unit rows (synthesized in `mkdtemp`, never under the repo).**
   - `\0claude-opus-5-5-20260101\0` does NOT vouch for `claude-opus-5-5` (prefix shadowing).
   - `…\0claude-opus-5-5` at EOF with no trailing byte DOES (must-PASS non-canonical: the `$` boundary).
   - A missing file throws.
8. **Guard 3 + identity (one spawn).**
   - Run `spawnSync(bin, ["--print", ...AUDIT_CLI_ARGS, "--version"], {env: {PATH: "/usr/bin:/bin", HOME: <mkdtemp>}, timeout: 20_000, encoding: "utf8"})`. Spreading the tuple ties the probe to what the crons actually pass. Measured: this argv shape exits 0 and prints the version.
   - Expect `status === 0`, and stdout starting with the pin followed by one space. This is the behavioral proof that the grepped file is the pinned build; a stale install fails here with the `npm ci` remedy.
   - Expect no `/effort/i` anywhere in stdout + stderr.
   - **Positive control:** `["--print", "--model", AUDIT_MODEL, "--effort", "not-a-level", "--version"]` MUST contain `Unknown --effort value`. If a CLI bump rewords the warning, the control fails and forces a needle update. It never passes silently.
   - Remove the temp HOME in `afterAll`. The measured run wrote `$HOME/.claude*`.
   - Set the test timeout explicitly to 60 s.

## Implementation Phases

1. **RED first (`cq-write-failing-tests-before`).**
   - Write Guard 1 in `model-tiers.test.ts` and the new `claude-cli-pin-knows-models.test.ts`.
   - Guard 1 must fail on the current tree: walk (a) flags the six crons that name `AUDIT_MODEL`, and `AUDIT_CLI_ARGS`/`AUDIT_EFFORT` do not exist yet.
   - Guards 2/3 must pass against 2.1.280 for the model ids. The effort half fails to compile until `AUDIT_EFFORT` exists, which is the expected RED.
   - Runner precondition, checked before building Guards 2/3 on it. On this linux-x64 host, `ls -l apps/web-platform/node_modules/@anthropic-ai/claude-code-linux-x64/claude` shows an executable file, and the hermetic `--version` probe prints `2.1.280 (Claude Code)`. `apps/web-platform/.npmrc` carries only `min-release-age=3`, with no `omit=optional`, so `npm ci --ignore-scripts` in `test-webplat` installs the optional glibc x64 package. The first CI run on the branch is the confirmation: the test must report the ids checked, not skip.
2. **GREEN.**
   - Add `AUDIT_EFFORT` to `model-tiers.ts`.
   - Add `AUDIT_CLI_ARGS` to `model-tiers.ts`.
   - Edit the six crons (import, spread).
   - Run `./node_modules/.bin/vitest run test/server/inngest/model-tiers.test.ts test/server/inngest/claude-cli-pin-knows-models.test.ts test/server/inngest/cron-ux-audit.test.ts test/server/inngest/cron-claude-eval-mcp-flags.test.ts test/server/inngest/cron-producer-output-wiring.test.ts` from `apps/web-platform`.
   - Run `./node_modules/.bin/tsc --noEmit`.
3. **Mutation battery.** Apply each row from `## Guard Contract` by hand (or in a scratch copy), confirm it goes RED, and revert. Record the results in the PR body.
4. **Docs/ADR.**
   - Amend ADR-053.
   - Edit the model-launch-review SKILL.md row 3 and the step 2b sentence.
   - Write the "next CLI bump" checklist header in the new test file.
   - Run `bun test plugins/soleur/test/model-launch-review.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh`.

## Technical Considerations

- **Argv order.** `--effort` must sit before `"--"`. After the end-of-options marker it would be read as part of the prompt (#4017). Guard 1 row M2 is the order-sensitive row.
- **Cost / time budget.** High effort increases thinking and output tokens on about 12 audit-tier runs a month (2 weekly at ~4.3 each, 3 monthly, 1 quarterly), all on claude-opus-5-5 ($4/$20 per MTok). Longer turns also press on the fixed wall-clock budgets, for example agent-native-audit's 50 min with `--max-turns 50`. The existing timeout classification (`abortedByTimeout` goes to a FAILED issue and the Sentry cron monitor) already surfaces an overrun. See Observability. Model tier is unchanged (still opus-5-5), so this is not the ADR-053 re-tiering class. The ADR amendment records the decision.
- **Agent SDK bundle.** Out of scope. `@anthropic-ai/claude-agent-sdk` ships its own CLI binary (`claude-agent-sdk-linux-x64`) with its own model table. `agent-runner-query-options.ts` defaults to a raw `"claude-sonnet-5"`. Follow-up: #8643.
- **NFR.** No runtime performance or availability NFR moves. The test adds about 1 s to one vitest shard (four greps of about 0.08 s, two `--version` spawns of about 0.1 s, one 233 MB file stat).

## User-Brand Impact

- **If this lands broken, the user experiences:** the scheduled audit reports (agent-native, architecture-diagram drift, competitive analysis, growth/SEO, legal, UX) that the operator reads as GitHub issues are missing, or come out shallower. That happens if an argv misorder makes a cron fail, or if a silent effort fallback makes it reason at `medium`. No end-user page, account or data is touched.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The change adds a CLI argv flag and a CI-only test that runs the already-shipped pinned binary with `--version`, a hermetic env and no credentials.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the touched apps/web-platform/server/inngest/ paths only change internal operator-cron CLI argv (an effort level) and add a CI test; no user data, auth, billing or user-facing surface is read or written.`

## Observability

```yaml
liveness_signal:
  what: "Existing per-cron Sentry cron monitors (e.g. scheduled-agent-native-audit) check in on every audit-cron run; the new guard is the vitest file claude-cli-pin-knows-models.test.ts plus model-tiers.test.ts in the required CI `test` aggregate (test-webplat leg)"
  cadence: "per PR / per push (CI); per cron run (weekly to quarterly) for the monitors"
  alert_target: "required status check `test` blocks merge; Sentry cron-monitor missed/failed check-in pages the operator"
  configured_in: ".github/workflows/ci.yml (test-webplat job) + apps/web-platform/server/inngest/functions/cron-*.ts SENTRY_MONITOR_SLUG"
error_reporting:
  destination: "Sentry (web-platform project, SENTRY_DSN) via reportSilentFallback / cron classify-fatal path; CI failure annotations for the guard"
  fail_loud: "vitest assertion `bump @anthropic-ai/claude-code … to a version whose bundle carries <ids>` / `Unknown --effort value` in the guard; at runtime the CLI stderr line `Warning: Unknown --effort value` reaches logger.error({fn, stream: 'stderr'}) and stderrTail"
failure_modes:
  - mode: "a tier model id absent from the pinned CLI bundle (#6934 half-max_tokens)"
    detection: "Guard 2 per-id boundary-anchored grep -a in CI (test-webplat)"
    alert_route: "required `test` check red, PR cannot merge"
  - mode: "AUDIT_EFFORT value not accepted by the pinned CLI (silent fallback to medium)"
    detection: "Guard 3 `--effort <v> --version` probe (no /effort/i output) with a positive control"
    alert_route: "required `test` check red"
  - mode: "audit tuple dropped, bypassed with a raw --model AUDIT_MODEL, extra --effort appended, moved after `--`, or spread into a non-audit cron"
    detection: "Guard 1 source walk + exported-array assertions"
    alert_route: "required `test` check red"
  - mode: "package.json / Dockerfile CLI pins drift (package.json / lockfile drift is already an npm ci failure)"
    detection: "Guard 2 pin-agreement assertion"
    alert_route: "required `test` check red"
  - mode: "high effort pushes an audit cron past its wall-clock budget or max-turns"
    detection: "existing abortedByTimeout / max-turns classification in spawnClaudeEval -> FAILED cron issue + Sentry cron monitor error check-in"
    alert_route: "Sentry cron monitor alert + auto-filed FAILED GitHub issue"
logs:
  where: "CI job log for test-webplat; runtime claude stderr is logged via pino logger.error({fn, stream:'stderr'}) and shipped by the host Vector agent to Better Stack Logs source 2457081"
  retention: "GitHub Actions logs 90 days; Better Stack per source retention"
discoverability_test:
  command: "grep -rlF ...AUDIT_CLI_ARGS apps/web-platform/server/inngest/functions"
  expected_output: "cron-agent-native-audit.ts"
```

## Guard Contract

Every row below is applied by hand during `soleur:work`, then reverted, with the observed result recorded in the PR body (AC5). The matrices are cut to the rows that each test a distinct way of failing; plan-review asked for a smaller battery.

### Guard 1 — audit-cron `--effort` argv pin

**Property.** Every `claude` argv in `apps/web-platform/server/inngest/functions/*.ts` that selects the audit model also passes `--effort AUDIT_EFFORT`, before the `"--"` end-of-options marker. No argv that does not select the audit model passes `--effort`.

**Assembly.**

- **Chokepoint 1: the pairing.** `AUDIT_CLI_ARGS` in `model-tiers.ts` is the only place `AUDIT_MODEL` and `AUDIT_EFFORT` are paired. An identity pin asserts it deep-equals `["--model", AUDIT_MODEL, "--effort", AUDIT_EFFORT]`. A second pin asserts `AUDIT_EFFORT === "high"`, the operator-requested value.
- **Chokepoint 2: the `"--model"` argv token in `server/inngest/functions/*.ts`.** Every CLI spawn in that directory selects its model either through `...AUDIT_CLI_ARGS` or through a `"--model", EXECUTION_MODEL` pair. That includes the two inline spawners, `cron-daily-triage.ts` and `cron-follow-through-monitor.ts`, which use the single-line form.
- **Source walk (comment-stripped, `readdirSync(FUNCTIONS_DIR)`, reusing the existing `stripComments`).** It asserts five things:
  - (a) the identifiers `AUDIT_MODEL` and `AUDIT_EFFORT` occur zero times;
  - (b) `/["'`]--effort/` matches zero times (any quote style, including an `--effort=` form);
  - (c) every `/["'`]--model["'`],\s*([^\s,\]]+)/g` capture is `EXECUTION_MODEL`, and `/["'`]--model=/` matches zero times. The floor is at least 5 captures (10 today), with headroom so retiring one execution cron does not trip it;
  - (d) the set of files matching `/\.\.\.AUDIT_CLI_ARGS\b/` equals an explicit six-name `AUDIT_CRONS` table;
  - (e) in each of those six, the spread's offset is before the file's single `"--",` line, and that line occurs exactly once (measured: one per audit cron today).
- **Failure messages.** The (c) and (d) messages name ADR-053: moving a cron between tiers is a reviewed change that edits `AUDIT_CRONS` too.
- **Measured.** On the current tree the walk finds 16 `--model` captures (10 `EXECUTION_MODEL`, 6 `AUDIT_MODEL`), and (a) flags exactly the six audit crons. That is the RED baseline.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| M1 | In `cron-legal-audit.ts`, replace `...AUDIT_CLI_ARGS,` with the old `"--model", AUDIT_MODEL,` (effort dropped) | RED (walk (a) + (d)) |
| M2 | REORDER: move `...AUDIT_CLI_ARGS,` to after `"--",` in `cron-ux-audit.ts`. A delete row cannot see an order defect. | RED (walk (e)) |
| M3 | Drop the effort pair from `AUDIT_CLI_ARGS` in `model-tiers.ts` | RED (identity pin; no walk can see it) |
| M4 | SECOND MEMBER: add a second flags array to `cron-competitive-analysis.ts`, after the compliant spread, spelling `"--model", AUDIT_MODEL` raw | RED (walk (a); a per-file "contains the spread" check would stop at the compliant first) |
| M5 | Spread `...AUDIT_CLI_ARGS,` into the execution-tier `cron-bug-fixer.ts` | RED (walk (d) set identity) |
| M6 | DISPATCH: point `FUNCTIONS_DIR` at a wrong path | RED (existing ≥17-file floor + (c) ≥5 floor + (d) set identity) |

**Harness rows:**

| # | Mutation to the SUITE / input | Expected |
|---|---|---|
| H1 | Make `stripComments` return `""` for every line | RED ((c) floor + (d) empty set) |
| H2 | must-PASS non-canonical: the single-line `"--model", EXECUTION_MODEL,` form counts, and a full-line comment naming `AUDIT_MODEL` (`cron-architecture-diagram-sync.ts:75` today) does not trip walk (a) | PASS |

**Anchor.** The six-name `AUDIT_CRONS` table is a stored list. One diff can edit both the table and a cron. That is intended: re-tiering is a reviewed ADR-053 change. The table is checked for set identity (not a `>= 6` floor), so swapping in a different cron still fails.

### Guard 2 — pinned claude-code CLI bundle knows every tier model id

**Property.** Every Claude model id declared in `model-tiers.ts` or `leader-prompts/constants.ts` occurs, boundary-anchored, in the linux-x64 platform binary of the exact `@anthropic-ai/claude-code` version pinned by package.json and the Dockerfile.

**Assembly.**

- **Ids.** The `[2b]` harvest over the comment-stripped text of both files (a historical id quoted in a comment is not a required bundle id), with a ⊇ floor on the imported constants. The chokepoint argument is that Guard 1 walk (c) proves every cron `--model` value is a `model-tiers.ts` identifier, so those two files are the only route by which an id reaches the cron CLI. The oneshot functions pass no `--model`.
- **Pin.** package.json dependency (exact semver) = Dockerfile `npm install -g` line. `npm ci` already enforces package.json = lockfile, and the lockfile's `integrity` check covers the platform tarball bytes.
- **Bundle.** `node_modules/@anthropic-ai/claude-code-linux-x64/claude` only. Its `--version` output must equal the pin (behavioral identity).
- **Dispatch.** Fail-closed when `CI`/`GITHUB_ACTIONS` is set or on linux-x64. Only the binary-dependent block may skip; pin agreement and the id floor run everywhere.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| M1 | `AUDIT_MODEL = "claude-opus-9-9"` (id absent from 2.1.280) | RED |
| M2 | SECOND MEMBER: add `export const X_MODEL = "claude-opus-9-9" as const;` to `constants.ts` after the compliant ids | RED (collect-all loop, not first-only) |
| M3 | Dockerfile pin `2.1.279` while package.json says `2.1.280` | RED (pin agreement, on every host) |
| M4 | Stale install: `node_modules` holds a different claude-code version than the pin | RED (`--version` identity, with the `npm ci` remedy) |
| M5 | DISPATCH: delete the bundle directory with `CI=true` | RED (throws; never skips) |
| M6 | DISPATCH: break the harvest regex so the id set is empty | RED (⊇ floor) |

**Harness rows:**

| # | Mutation to the SUITE / input | Expected |
|---|---|---|
| H1 | Replace `bundleHasId`'s grep with a constant `true` | RED (real-bundle negative control + prefix-shadow row) |
| H2 | Drop the boundary suffix (fixed-string match) | RED (prefix-shadow row) |
| H3 | must-PASS non-canonical: blob with the id at EOF and no trailing byte | PASS |

**Anchor.** No stored hash. The guard reads the real bytes of the pinned artifact. Those bytes are integrity-checked by `npm ci` against the lockfile's registry-issued `integrity`, which comes from outside this repo. One diff can move the pin and `AUDIT_MODEL` together. The guard then measures the new pin's real bytes, which is the intended path (bump plus swap).

### Guard 3 — pinned CLI accepts `AUDIT_EFFORT`

**Property.** The pinned CLI binary parses `--effort <AUDIT_EFFORT>` without any effort warning, including its unknown-value fallback warning.

**Assembly.** The single `AUDIT_EFFORT` constant, which Guard 1 proves is the only effort value any cron argv carries (via `AUDIT_CLI_ARGS`), crossed with the same pinned binary Guard 2 resolves. There is no hand-maintained TS union of CLI effort levels: this probe is the authority.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| M1 | `AUDIT_EFFORT = "hgih"` | RED (probe output matches `/effort/i`; also the identity pin) |
| M2 | DISPATCH: the binary is missing in CI | RED (shared Guard 2 dispatch throws) |
| M3 | The CLI rewords the warning (simulated by changing the needle to `Unknwn --effort`) | RED (positive control `not-a-level` no longer matches) |

**Harness rows:**

| # | Mutation to the SUITE / input | Expected |
|---|---|---|
| H1 | Swap the spawned binary for a stub that prints `2.1.280 (Claude Code)` and never parses flags | RED (positive control finds no warning) |
| H2 | must-PASS non-canonical: `--effort HIGH` (upper case) | PASS (measured: accepted, no warning) |

**Vacuity demonstration** (recorded in the PR body; not a RED row). Delete the positive control and apply M3, and the suite goes GREEN. Replace the output check with `status === 0`, and M1 goes GREEN, because rc is 0 on a bad value (measured). Those two runs are why both checks are mandatory.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-053** (`knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`). In the "Addendum — 2026-09-23 (Opus 5.5 launch, PR #8601)", keep the recorded sentence and follow it with a dated paragraph, "Amendment — 2026-09-23 (#8603)":

- Surface 5b now pins **effort alongside the model**: `AUDIT_EFFORT = "high"` in `model-tiers.ts`.
- The reason: claude-opus-5-5's CLI-bundled `default_effort` is `medium`. The CLI "sets effort itself" from that per-model row, so leaving effort unset silently lowered audit reasoning depth at the 5 to 5.5 swap.
- Execution-tier crons stay on the CLI default.
- A change to `AUDIT_EFFORT` is a same-tier tuning change, not re-tiering.
- The pinned-CLI guard (Guards 2/3) makes "the pinned CLI knows the tier ids and accepts the effort value" a CI invariant. It is no longer only a hand-run audit item.

Also add one row to `## Alternatives considered`: *"Leave effort to the CLI's per-model default | The default moved medium←high at the 5→5.5 swap with no argv change; a tier whose rationale is reasoning depth cannot inherit an unowned default."*

### C4 views

No C4 impact. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **(a) External human actors:** none added or changed.
- **(b) External systems:** the `anthropic` system and its edges (`engine -> anthropic`, `claude -> anthropic`, `github -> anthropic`, `evalharness -> anthropic`) already exist. Only a request parameter (effort) on the existing cron `claude -> anthropic` call changes. No new vendor.
- **(c) Containers or stores:** none. The guard runs inside the existing `github` CI element.
- **(d) Access relationships:** unchanged.

`grep -in 'opus\|effort\|claude-code' model.c4` shows no model id, effort level or CLI version in any element or edge prose, so no description is falsified. Baseline `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 on this branch. The plan adds no workflow, cron, monitor or heartbeat, so no count moves. An AC re-runs it after implementation.

### Sequencing

The decision is true when the PR merges. No soak.

## Open Code-Review Overlap

None. Checked all 75 open `code-review` issues against every planned path (`model-tiers.ts`, the six cron files, `model-tiers.test.ts`, `audit-models.sh`, `model-launch-review/SKILL.md`, ADR-053, `Dockerfile`). None match.

## Non-Goals

- **Agent SDK bundle (`@anthropic-ai/claude-agent-sdk` / `claude-agent-sdk-linux-x64`).** It is a second CLI copy with its own model table. It is excluded from this gate. Tracked as #8643; see Deferrals.
- **Changing effort on execution-tier crons.**
- **Changing `audit-models.sh [2b]` logic.** It stays the hand-run advisory for testing *candidate* versions.
- **Fetching registry tarballs in CI.** See Cut List C1.

## Acceptance Criteria

- [ ] AC1: `model-tiers.ts` exports `AUDIT_EFFORT = "high" as const` and `AUDIT_CLI_ARGS = ["--model", AUDIT_MODEL, "--effort", AUDIT_EFFORT] as const`. The header comment lists all 6 audit crons.
- [ ] AC2: Guard 1 walks (a), (b), (d) and (e) pass on the final tree. That is the mechanical check: the spread appears in exactly the six audit crons, before `"--"`, and no code line names `AUDIT_MODEL`/`AUDIT_EFFORT` or an `--effort` literal. `git grep -l -F '...AUDIT_CLI_ARGS' -- apps/web-platform/server/inngest/functions` listing the six files is supporting evidence only.
- [ ] AC3: `model-tiers.test.ts` contains Guard 1: walks (a)-(e), the `AUDIT_CRONS` table and both identity pins. `claude-cli-pin-knows-models.test.ts` runs its pin-agreement and id-floor tests on every host.
- [ ] AC4: `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts` exists, runs (not skipped) in CI `test-webplat`, and passes against 2.1.280. Its log line states the ids checked and the pin measured.
- [ ] AC5: Every row in `## Guard Contract` (every M and H row) was applied and reverted during `soleur:work`, with the observed RED/PASS recorded in the PR body. Guard 3's two vacuity demonstrations are recorded too.
- [ ] AC6: `./node_modules/.bin/tsc --noEmit` and the targeted vitest files listed in Implementation Phase 2 pass from `apps/web-platform`.
- [ ] AC7: ADR-053 carries the "Amendment — 2026-09-23 (#8603)" paragraph and the new Alternatives row.
- [ ] AC8: model-launch-review `SKILL.md` row 3 no longer claims `effort:"high"` as the measured injected default, and names `default_effort` and `AUDIT_EFFORT`. `bun test plugins/soleur/test/model-launch-review.test.ts` passes.
- [ ] AC9: `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 after implementation.
- [ ] AC10: The PR body contains `Closes #8603` and states the cost note (about 12 audit-tier runs a month move from medium to high effort).
- [ ] AC11: The PR body links the Agent SDK follow-up #8643.

## Test Scenarios

- Given the current tree (crons name `AUDIT_MODEL` directly, and there is no tuple), when Guard 1 runs, then it fails naming all six crons (RED baseline).
- Given the six edits, when Guard 1 runs, then it passes. Given any single M1–M9 mutation, it fails with a message naming the file.
- Given `npm ci` at the 2.1.280 lockfile on linux-x64, when Guard 2 runs, then the pins agree, `--version` prints `2.1.280 (Claude Code)`, and each of `claude-opus-5-5`, `claude-sonnet-5` and `claude-haiku-4-5-20251001` is present.
- Given `AUDIT_MODEL = "claude-opus-9-9"`, when Guard 2 runs, then it fails naming `claude-opus-9-9` and the bump remediation.
- Given `CI=true` and no bundle directory, when the suite loads, then it throws (no skip).
- Given `--effort not-a-level`, when the Guard 3 control runs, then the output contains `Unknown --effort value` (the control holds).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO rated the approach sound and small. Six risks were raised and folded in:

- (1) the `--version` short-circuit could skip effort parsing. Refuted by measurement: the warning prints under `--version`. The positive control is mandatory anyway.
- (2) the CI detection env. Now `CI || GITHUB_ACTIONS || linux-x64`.
- (3) a hermetic spawn env with temp HOME/CLAUDE_CONFIG_DIR, `DISABLE_AUTOUPDATER`, `DISABLE_TELEMETRY` and a timeout. Adopted.
- (4) source-regex fragility across the multi-line and single-line argv forms. Resolved by removing the need for a tokenizer. A shared `AUDIT_CLI_ARGS` tuple is spread into the six exported arrays, per the scoped advisor consult. The source walk is now four plain regexes, with a must-PASS row for both `--model` forms.
- (5) an executable-bit assertion for the linux-x64 binary. Adopted.
- (6) the Agent SDK bundle. Deferred with a follow-up issue.

The CTO also pointed out two weekly crons (architecture-diagram-sync, growth-audit) and the 50-minute agent-native-audit budget. Both are recorded in Technical Considerations and Observability failure_modes.

Finance (the cost of high effort on about 12 runs a month) was judged below the CFO threshold: there is no budget-allocation decision. The cost is disclosed in the PR body (AC10).

## Plan Review Consolidation (headless)

Panel: DHH, Kieran, code-simplicity (per mechanism), and the named-panel CTO (devex lens). The threshold is `none`, so the escalated panel did not run. Every applied change below is classed **Mechanical**. None of them drops operator-requested scope: `AUDIT_EFFORT = "high"`, the six-cron scope, the #8603 grep-a guard and the effort-flag check all remain.

- **Applied (simplify):**
  - Cut the `ClaudeCliEffort` union, the `CLAUDE_CODE_FLAGS` exports and the runtime half, the four-way lockfile read, the package.json identity read, the runtime-export id enumeration, the quote blob row, the extra env vars and the `audit-models.sh` pointer.
  - Shrank each mutation matrix to rows that each test a distinct way of failing.
  - Merged the identity and effort probes into one spawn.
- **Applied (correctness):**
  - (c) floor lowered to ≥5.
  - Quote-agnostic `--effort`/`--model` regexes, with `=` forms counted as offenders.
  - The harvest runs over comment-stripped text, using a shared `stripComments` helper.
  - `LC_ALL=C` for grep.
  - The Guard 3 probe spreads `AUDIT_CLI_ARGS`.
  - Corrected the M5 rationale.
  - AC2 is now a mechanical check.
- **Applied (devex, CTO):**
  - An ordered bump-then-swap procedure in SKILL.md step 2b.
  - Remediation commands in every failure message.
  - Pin agreement and the id floor run on every host; only the binary block skips.
  - A "next CLI bump" checklist header.
  - ADR-053 pointers in the Guard 1 messages.
- **Declined, with reason:**
  - Cutting the `AUDIT_EFFORT === "high"` pin (simplicity): the operator asked for the value to be pinned with a test.
  - Dropping walk (c) (DHH): it is the chokepoint that makes Guard 2 complete for P3.
  - Moving Guard 1 into its own file (Kieran): its reason, importing cron modules, went away with the source-level redesign.
  - A `| wc -l` discoverability command (Kieran): `|` is rejected by preflight Check 10. The expected token is a substring of the printed paths, so the current probe matches.
  - A bash/TS regex parity check (CTO): cross-reference comments are enough for two short regexes.
- **Taste / User-Challenge findings:** none. Nothing was written to `decision-challenges.md`.

## Deferrals

- **Agent SDK bundle model-id gate.** What: extend the pinned-bundle check to `@anthropic-ai/claude-agent-sdk`'s `claude-agent-sdk-linux-x64` and the raw `"claude-sonnet-5"` default in `server/agent-runner-query-options.ts`. Why deferred: it is a different pin, a different consumer (the Agent SDK runtime, not the cron CLI), and outside #8603's scope. Re-evaluate at the next Anthropic model launch or the next claude-agent-sdk bump, whichever comes first. Filed as #8643, linked in the PR (AC11).

## Dependencies & Risks

- **The CLI rewords the effort warning in a future bump.** The positive control goes RED and the needle is updated in the bump PR. This is intended.
- **`npm ci --ignore-scripts` stops installing the optional platform dep** (npm behavior change, or a musl runner). Guard 2's dispatch throws in CI. It is loud, not vacuous.
- **Longer audit runs.** The existing timeout/max-turns classification surfaces them. Tuning `--max-turns` or budgets is a separate follow-up if FAILED issues appear.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Do NOT grep the `@anthropic-ai` scope or `node_modules/.bin/claude`. Under `--ignore-scripts` the `.bin` shim points at the stub `bin/claude.exe`, and the scope contains `claude-agent-sdk*`, which carries sonnet ids. The probe target is `node_modules/@anthropic-ai/claude-code-linux-x64/claude` and nothing else.
- `claude --version` writes `$HOME/.claude*`. Always spawn with a temp HOME and `CLAUDE_CONFIG_DIR`. Never inherit the developer's or the runner's.
- Unpack any candidate tarball **outside** the repo (`mktemp -d`), per model-launch-review SKILL.md. Do not commit fixture blobs containing real model ids under a scanned path; synthesize them in `mkdtemp`.
- Put `...AUDIT_CLI_ARGS,` exactly where `"--model", AUDIT_MODEL,` was, directly after `"--print",` and **before** `"--"`. The `cron-ux-audit.ts` array has `--mcp-config` entries and comments near the end, so never append.
- `.github/workflows/scheduled-marketplace-drift.yml` pins its own `CLI_VERSION` (2.1.228) for the plugin-update drift probe. That is a different consumer from the cron runtime, which resolves `/app/node_modules/.bin/claude`. It is deliberately NOT part of Guard 2's pin agreement. Do not "fix" it in this PR.
