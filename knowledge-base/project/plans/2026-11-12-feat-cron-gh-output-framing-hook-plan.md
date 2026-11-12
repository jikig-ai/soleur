---
title: "feat(security): dark opt-in PostToolUse(Bash) gh-output framing hook for the cron eval substrate"
date: 2026-11-12
slug: feat-cron-gh-output-framing-hook
branch: feat-one-shot-11076-cron-gh-output-framing
issue: 11076
ref: [11076, 9601]
type: feat
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# feat(security): dark opt-in PostToolUse(Bash) gh-output framing hook for the cron eval substrate

Ref #11076 (under epic #9601). Draft PR #12705 already exists; this plan opens no other PR. The PR body uses `Ref #11076` and
`Ref #9601` only, never a closing keyword. Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed); no `spec.md`
exists for this branch.

## Overview

This plan adds a standalone Node hook that the cron Claude eval substrate can register after Bash tool calls. When the Bash
command was a read-style `gh` command, the hook appends the existing GitHub untrusted-content preamble as additional context for
the model. It never changes the tool output. Registration is opt-in through a new option on the settings builder, and no caller
turns it on in this change. ADR-287 is amended to record the cron surface, its dark status, and what is still unmeasured.

Four deliverables, all from the CTO ruling of 2026-11-12 (decision-challenges rows S1-S3, F1-F8, F4', F5', and the plan-review rows C1-C5):

1. `apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs` — PostToolUse(Bash) command hook. Ported verb table, the
   GitHub preamble as a constant, detection on the tokens of the sibling containment hook's own parser. Annotate only. Always
   exits 0. Emits nothing on any parse problem.
2. `buildCronEvalSettings(spawnCwd, { frameGhOutput?: boolean })` — adds one `PostToolUse` Bash entry only when
   `frameGhOutput === true`. The default output is byte-identical to today's.
3. `runHookSelfTest` — when the parsed `settings.json` has a `hooks.PostToolUse` key, it deep-equals that value against the one
   expected entry, probes the framing binary, and throws on any failure. When the key is absent (every spawn today), nothing
   new runs. No new argument (CTO C1, restoring F4).
4. ADR-287 addendum dated 2026-11-12 — the cron surface, its dark status, its coverage limits, and the residual that the hook's
   effect in headless `claude --print` is unmeasured.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (verified 2026-11-12) | Plan response |
|---|---|---|
| "Read-verb table is a .mjs port of `GH_READ_VERBS`" | The hosted twin's detection is ~250 lines beyond the table: `ghReadVerbOf`, `ghFallbackScan`, `commentQuoteRisk`, `measureBashResponse` and pino telemetry (`untrusted-content.ts`, section `gh output framing through Bash`). The TS module imports `./logger` and `./observability`, so plain node cannot import it. | Port the table and the preamble only (AC1). Detection reuses the containment hook's exported `splitSegments` and `tokenize` (CTO F1). The fallback scan, `commentQuoteRisk`, the shape gate and the telemetry are cut (Cut List). |
| "The spawn-time hook self-test also checks the PostToolUse hook when it is registered" | `setupEphemeralWorkspace` calls `buildCronEvalSettings(spawnCwd)` with one argument, and the brief forbids wiring. `runHookSelfTest` already parses `.claude/settings.json`. Its other directives are "passed explicitly (from the map, not parsed from the file) so the probes cross-check that the file ACTUALLY delivered". | "When it is registered" is a property of the file. `runHookSelfTest` keys on the parsed `settings.json` having a `hooks.PostToolUse` key and takes no new argument (CTO F4, restored by C1 after plan review overturned F4'). `setupEphemeralWorkspace` is not edited. |
| Issue #11076: "Needs its own ADR" | The CTO ruled on 2026-11-12 to amend ADR-287 instead (row S2). | ADR-287 addendum, not a new ADR. |
| Issue #11076: "Telemetry must stay a closed field set with no paths, filenames or matched text (CLO)" | No telemetry is emitted by this change (CTO F3). | The addendum states that enablement must decide a closed-field signal first. No legal review is triggered by a change that emits nothing. |
| "The hook shares the cron substrate" | Both hooks run from the depth-1 git clone of `main` (`join(spawnCwd, HOOK_REL_PATH)`), not from the Docker image. The settings builder runs from the deployed image. | After merge the clone carries the new file while no deployed caller registers it. The self-test catches a clone that lacks the file, but only when a caller registers the hook. Verification does not depend on a deploy (the web-platform deploy is failing `inngest_link_selfgate_failed`, an operator item outside this run). |

## Research Insights

### Premise Validation

- #11076 is OPEN ("untrusted-content hooks for cron Bash output and attachment reads"). #9601 is OPEN ("agent security hardening
  epic"). Neither is closed by a merged PR, so the premise holds.
- `collision-precheck.sh 11076` reports PR #12705, which is this run's own draft PR (expected). The foreign `test-all.sh`
  processes belong to the `feat-kernel-patch-web-hosts-12008` worktree, which is unrelated. `collision-precheck.sh 9601`: no
  open PRs.
- Cited symbols on the branch base (`96c719e124`, one commit above `origin/main` `34634d7431`): `UNTRUSTED_PREAMBLES.github` and
  `GH_READ_VERBS` exist in `apps/web-platform/server/untrusted-content.ts`. `buildCronEvalSettings`, `runHookSelfTest`,
  `resolveNodeBin`, `HOOK_REL_PATH` and `DEFAULT_CLAUDE_SETTINGS` exist in `_cron-claude-eval-substrate.ts`. `splitSegments`,
  `tokenize` and `decide` are exported from `cron-bash-allowlist-hook.mjs`. ADR-287 exists with addenda dated 2026-10-25 and
  2026-11-08.
- ADR corpus check for the mechanism: ADR-287 decision 6 ("Crons never opt in") covers the WebFetch scorer only; the 2026-10-25
  amendment says so explicitly. ADR-287 lists "cron Bash output as a hook-level control" as not covered and is the place to
  record it. ADR-156 (hook stdin is model-controlled) applies: every input field is type-checked. No ADR lists a cron PostToolUse
  hook among its rejected alternatives.
- Producer check over the population the hook would register in (learning 2026-11-09, where a hosted predicate removed the gh
  credential the cited producer needed):

  | Cited fact | File | Still true in the opted-in population? |
  |---|---|---|
  | Cron agents run `gh` reads through Bash | `CRON_BASH_ALLOWLISTS` in `_cron-claude-eval-substrate.ts`: `gh issue view` is in 5 cron allowlists, `gh issue list` in 5, `gh pr list` in 1, `gh api repos/jikig-ai/soleur/` in 1 | Yes. The option does not change allowlists. |
  | `gh` authenticates in the spawn | `buildSpawnEnv(installationToken)` carries `GH_TOKEN`. The run-report probe (d) exists because the spawn env carries it. | Yes. No predicate removes it. |
  | `gh` is installed | `apps/web-platform/Dockerfile`, the `GitHub CLI` install block | Yes. |
  | PostToolUse sees only admitted commands | `decide()` in `cron-bash-allowlist-hook.mjs` denies multiline, unbalanced quotes, substitution, `$VAR`, redirection, pipes and background `&` before the tool runs | Yes. That is why the fallback scan is cut. |
  | The model receives `additionalContext` under `--print` | Learning 2026-06-30 (PostToolUse additionalContext reaches the model in autonomous runs) is about interactive and plugin runs, not the cron `--print` spawn. | Unverified. Phase 0 probe (CTO F5). |

  Today the opted-in population is empty: no caller passes `true`.

### Property List (Phase 0.6b)

- **P1.** After a cron agent runs a read-style `gh` command through Bash in a spawn whose settings opt in, the model receives the
  GitHub untrusted preamble as additional context next to that output.
- **P2.** The hook never changes, blocks or delays the tool output. Every failure leaves the turn as it is today.
- **P3.** When the option is absent or not exactly `true`, the written `settings.json` is byte-identical to today's, so every
  production cron is unchanged.
- **P4.** The cron verb table and preamble cannot drift silently from the hosted source of truth.
- **P5.** When the framing hook is registered, a missing or broken hook is detected at spawn time on the host, and the cron
  aborts.
- **P6.** ADR-287 records the cron surface, its dark status, its named gaps, and that the effect in headless `--print` is
  unmeasured.

### Cut List (Phase 0.6b)

| Mechanism (hosted twin) | Property it bought | Why it is cut here |
|---|---|---|
| `ghReadVerbOf` tokenizer port | P1 (detect a gh read) | The containment hook's exported `splitSegments` and `tokenize` already produce the tokens gh receives for every command that can run (CTO F1). |
| `ghFallbackScan` + `commentQuoteRisk` | P1 for multiline scripts, unterminated quotes and padding | PreToolUse denies multiline commands and unbalanced quotes before the tool runs, so PostToolUse never sees those shapes. |
| `LEADING_NON_COMMAND` / `env` / assignment-word skipping | P1 for `env gh ...`, `FOO=1 gh ...` | Every allowlisted gh line starts with the literal `gh`, so a prefixed form is denied by the allowlist match. |
| `ghSegment`'s `-R`/`--repo` skip, `ls` alias and path-qualified `gh` | P1 for `gh issue -R x view`, `gh issue ls`, `/usr/bin/gh …` | `segmentMatchesAllowlist` admits only `norm === p`, `norm.startsWith(p + " ")` or a `/`-terminated prefix, and every cron gh prefix is literal `gh <noun> <verb>` or `gh api repos/jikig-ai/soleur/`. None of these shapes can reach PostToolUse (CTO C2). A guard fails if an allowlist gains another gh shape. |
| `measureBashResponse` shape gate | Observability of SDK shape drift (telemetry fields) | No telemetry here, so it would only add a silent arm (CTO F2). |
| `emitGhFrame` pino line + Sentry mirrors | Observability | No logger in the child process, and stdout is the hook protocol channel (CTO F3). |
| New flag or `setupEphemeralWorkspace` parameter | Enablement | Out of scope per the brief. |

### Files read (content anchors)

- `apps/web-platform/server/untrusted-content.ts` — `UNTRUSTED_PREAMBLES`, `GH_READ_VERBS`, `GH_FRAME_VERBS`, `ghSegment`
  (`-R`/`--repo` skip, `ls` alias, `api: []` noun-only rule), `ghReadVerbOf`, `createGhBashFramingHook`.
- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` — `dangerousMetacharReason`, `splitSegments`, `tokenize`,
  `decide`, the `main()` guard `invokedPath.endsWith("cron-bash-allowlist-hook.mjs")`, and the #8074 comment about this file being in
  the Next.js server bundle (no `new URL(..., import.meta.url)` asset syntax).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — `DEFAULT_CLAUDE_SETTINGS`, `HOOK_REL_PATH`,
  `resolveNodeBin`, `buildCronEvalSettings`, `runHookSelfTest` (the `matcherOk` settings parse), `setupEphemeralWorkspace` (the
  one call site, which writes `settings.json` and then calls the self-test), and the `--append-system-prompt UNTRUSTED_PREAMBLES.github`
  spawn argument.
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` — the `buildCronEvalSettings("/tmp/ephemeral/repo")`
  overlay block, and `makeSpawnCwd` / `stubHook` in the `runHookSelfTest` describe block (it copies only the containment hook
  today).
- `apps/web-platform/test/repo-wide-suites.ts` — the membership predicate. A file under `test/server/inngest/` that reads only
  inside the app is app-local.
- `knowledge-base/engineering/architecture/decisions/ADR-287-untrusted-content-annotate-not-block-heuristic-first.md` —
  Decision 6 and 7, amendment 2026-10-25, addendum 2026-11-08 items 1-8.
- Archived hosted plan `knowledge-base/project/plans/archive/20261109-003914-2026-11-08-feat-gh-bash-untrusted-framing-plan.md`
  — Guard Contract and Observability shape.

### Institutional learnings applied

- `2026-11-09-a-producer-check-was-true-of-the-system-and-false-of-the-population-the-hook-registered-in.md` — the producer
  table above. Separately: a fallback must share the primary grammar. Here there is no fallback, and the detection uses the same
  grammar as the gate that admitted the command.
- `integration-issues/2026-06-08-headless-claude-print-is-deny-list-and-hook-driven-not-allow-list.md` — a crashed hook fails
  open, `node` must be resolved by absolute path, never exit non-zero, and probe against the prod-pinned CLI, not the local one.
- `best-practices/2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md` — capture a real PostToolUse payload
  before trusting fixture shapes. The Phase 0 probe records the payload keys.
- `best-practices/2026-07-04-testable-workflow-internal-logic-lib-plus-duplicate-plus-parity-guard.md` and
  `2026-07-03-parity-guard-unmodeled-input-must-fail-loud-not-skip.md` — the parity guard compares whole structures and fails on
  an unmodeled key. It does not skip.
- `2026-10-25-a-framing-guard-for-a-channel-nobody-feeds-ships-green-and-inert.md` — this guard is inert by design today. The ADR
  says so, and the producer table names the future feeder.
- `2026-10-23-fix-round-agents-reported-green-on-their-own-files-and-broke-three-repo-global-gates.md` — run
  `repo-wide-containment.test.ts` after adding the test file.
- `test-failures/2026-05-20-vitest-unstub-does-not-clear-process-inherited-env-vars.md` — the binary spawns pass an explicit
  `env` (no `NODE_OPTIONS`, no `GH_TOKEN`).
- `2026-09-28-every-guard-was-narrower-than-its-name-and-my-battery-mutated-only-whole-chokepoints.md` — the mutation matrices
  below mutate single rows (one verb, one separator, one alias), not only whole functions.

### Functional overlap and community discovery

- Functional discovery (3 registries) found no artifact that frames `gh` output from a PostToolUse(Bash) hook. The closest,
  `bridgeward`, loads "treat as data" rules through a different mechanism. Nothing was installed.
- Community discovery: no uncovered stack (TypeScript and Node only), so it was skipped.

### CLI facts used (verified 2026-11-12 with `claude --help` on 2.1.322)

`--print`, `--output-format stream-json`, `--verbose`, `--include-hook-events` ("Include all hook lifecycle events in the output
stream (only works with --output-format=stream-json)"), `--setting-sources <sources>` ("Comma-separated list of setting sources to
load (user, project, local)"), `--settings <file-or-json>`, `--strict-mcp-config`. `--bare` skips settings hooks, so the probe must
not use it. The prod pin is `@anthropic-ai/claude-code@2.1.321` (`apps/web-platform/package.json`, `apps/web-platform/Dockerfile`).
Whether 2.1.321 has `--include-hook-events` is checked in Phase 0. The nonce is the deciding evidence either way (CTO F5).

## Implementation Phases

### Phase 0 — Delivery probe (FIRST for the decision; no product code) [CTO F5, F5', C3]

Run in a scratch directory outside the repo. Mirror the production spawn: `--strict-mcp-config`, `--output-format json`,
`--append-system-prompt "<UNTRUSTED_PREAMBLES.github>"`, `--print`, and a `.claude/settings.json` shaped like
`buildCronEvalSettings` output. That means the `*` PreToolUse containment hook (`cron-bash-allowlist-hook.mjs` plus a
`cron-allow.txt` admitting `echo`) and the PostToolUse entry under test. Add `--setting-sources project`
only to keep the developer's own user hooks out. Production does not pass it, and the ADR says so. Use a cheap model
(`--model haiku`). Budget: two short `--print` calls, well under US$0.10 on the developer's own Claude auth. No production
system is touched.

1. **Run 1, delivery proof (decides the CTO dissent).** Pinned CLI `npx -y @anthropic-ai/claude-code@2.1.321`. The PostToolUse
   entry is a 5-line STUB that prints
   `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"PROBE-NONCE-<random hex>"}}`. The nonce appears
   nowhere else: not in the prompt, not in the system prompt, not in the repo. The stub also writes its stdin to a file in the
   scratch directory, so the real `hook_event_name`, `tool_name` and `tool_input` keys are captured. This capture is REQUIRED
   evidence (CTO C3): with the shape gate cut (F2), the hook relies only on `tool_name` and `tool_input.command`, and the
   capture is the one live proof the pinned CLI sends them (the AC2 rows use a synthesized payload). The prompt asks the model
   to run `echo hello` (the stub ignores the command, so there is no gh-auth dependency), then reply with only the token
   starting `PROBE-NONCE` if any context gave one, else `NONE`. Pass only if the json `result` contains the exact nonce.
2. **Run 2, negative control.** Same as run 1 with no PostToolUse entry. The `result` must be `NONE`, which shows the nonce
   cannot be guessed.
3. Write the evidence to `knowledge-base/project/specs/feat-one-shot-11076-cron-gh-output-framing/probe-delivery.md`: CLI version
   per run, the flags, the nonce, each `result`, and the captured payload keys.

There is no real-hook run (CTO C3). It would prove only what the AC2 binary rows prove, and the model echoing the real
preamble is not evidence, because the same text is already in the system prompt (CTO F5' correction).

**Decision branch (run 1 alone decides).** Nonce returned at 2.1.321 and run 2 returns `NONE`: continue, and the ADR states
"delivery verified at 2.1.321; effect unmeasured". No nonce at 2.1.321: stop the hook work, record the result, and re-scope per
the CTO's recorded dissent (KB Read hook) through a new CTO consult, not an operator question. Run 1 cannot run (no Claude auth
or network): proceed, and the ADR states that delivery and effect are both unverified, with the reason. Neither run needs
product code, so both run before Phase 1.

### Phase 1 — The hook binary (`apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs`) [tests first: Phase 3 rows RED]

Shape (plain ESM, no dependencies, no `new URL(..., import.meta.url)`, per the #8074 note in the containment hook):

```js
#!/usr/bin/env node
// apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs
// Header: purpose, ADR-287 addendum 2026-11-12, "annotate only, never rewrite", "always exit 0",
// "dark: registered only through the framing option of buildCronEvalSettings" (the option's identifier is NOT
// written here, so the AC4 token scan stays exact), that the table + preamble are pinned to untrusted-content.ts
// by the parity test, and the posture inversion: a null or throw from the shared parser means "no annotation",
// where containment treats it as deny.
import { readFileSync } from "node:fs";

export const GH_READ_VERBS = Object.freeze({ /* exact copy of untrusted-content.ts GH_READ_VERBS */ });
export const GITHUB_UNTRUSTED_PREAMBLE = "…exact copy of UNTRUSTED_PREAMBLES.github…";

// tokens -> tokens[0] === "gh" && hasOwn(GH_READ_VERBS, tokens[1])
//           && (verbs.length === 0 || verbs.includes(tokens[2]))   (CTO C2; api: [] matches on the noun alone)
// No -R/--repo skip, no ls alias, no path-qualified gh: containment admits only literal `gh <noun> <verb>` prefixes,
// so those shapes never reach PostToolUse. They are named gaps in the ADR, and a guard fails if an allowlist changes that.
export function isGhReadTokens(tokens) { /* … */ }

// raw stdin + injected parser -> the hook output object, or null. Never throws.
export function frameDecision(raw, { splitSegments, tokenize }) { /* … */ }

async function main() {
  let out = "";
  try {
    const parser = await import("./cron-bash-allowlist-hook.mjs"); // dynamic, so a missing sibling still exits 0
    const d = frameDecision(readStdinOrEmpty(), parser);
    if (d) out = JSON.stringify(d);
  } catch { /* emit nothing */ }
  process.stdout.write(out);
  process.exit(0);
}
if ((process.argv[1] || "").endsWith("cron-gh-output-framing-hook.mjs")) main();
```

Rules for `frameDecision`:

- Parse `raw` with `JSON.parse` in a try. Return null on a throw, a non-object, `hook_event_name !== "PostToolUse"`,
  `tool_name !== "Bash"`, or a `tool_input.command` that is not a string. `tool_response` is never read (CTO F2).
- `splitSegments(command)`, then `tokenize(segment)` for each segment. A null token list skips that segment. The first segment
  where `isGhReadTokens` is true returns
  `{ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: GITHUB_UNTRUSTED_PREAMBLE } }`. No other key is ever
  set: no `updatedToolOutput`, no `decision`, no `continue`, no `systemMessage`.
- Wrap the whole body in try/catch, returning null.
- The containment hook's `main()` guard keys on its own file name, so importing it from this file does not run it.

Back-pointer comments (no code change), so whoever edits a shared piece finds its second consumer before breaking it:

- `apps/web-platform/server/untrusted-content.ts`: one comment line on `GH_READ_VERBS` and one on `UNTRUSTED_PREAMBLES.github`,
  each naming the cron copy in `cron-gh-output-framing-hook.mjs` and its parity test.
- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`: a short `Consumers` note above `export function splitSegments`
  and `export function tokenize`. It says they are used by `decide()` here and imported at runtime by
  `cron-gh-output-framing-hook.mjs`, and it names the inverted posture: for the framing hook a `null` result or a throw means
  "no annotation", not deny. A change that makes `tokenize` throw on a new shape keeps containment safe and silently turns
  framing off for that shape. The guards are the differential test and the AC2 rows in `cron-gh-output-framing-hook.test.ts`.
- The framing hook's header states the same posture difference.

### Phase 2 — Registration (`apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`)

- Add `const FRAMING_HOOK_REL_PATH = "apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs";` next to `HOOK_REL_PATH`.
- Add one exported helper `framingHookEntry(spawnCwd: string, nodeBin = resolveNodeBin())` returning
  `` { matcher: "Bash", hooks: [{ type: "command", command: `${nodeBin} ${join(spawnCwd, FRAMING_HOOK_REL_PATH)}` }] } ``. The
  builder and the self-test both use it, so the absolute hook path matches by construction (CTO C5).
- Change the signature to `buildCronEvalSettings(spawnCwd: string, opts: { frameGhOutput?: boolean } = {})`. Build `hooks`
  with `PreToolUse` first, unchanged. Only when `opts.frameGhOutput === true` (strict) add `PostToolUse: [framingHookEntry(spawnCwd)]`.
  Never write `PostToolUse: undefined`: it serialises identically but leaves an own key on the object, so the code adds the
  key conditionally and AC3 asserts `Object.keys(hooks)` equals `["PreToolUse"]` by default. The default object keeps today's
  key order, so its JSON is byte-identical.
- `setupEphemeralWorkspace` is not edited. It keeps calling `buildCronEvalSettings(spawnCwd)` and `runHookSelfTest({...})`.
- Add an exported `runFramingHookSelfTest({ spawnCwd, cronName, nodeBin, settings })` as its own function (Kieran P2: the
  existing `runHookSelfTest` is already about 300 lines). `runHookSelfTest` calls it once with the `settings` object it already
  parsed, after the existing containment probes. Its existing `matcherOk` logic and messages stay unchanged. No new argument is
  added to `runHookSelfTest` (CTO C1, restoring F4: the trigger is what the file says).
  - **`settings.hooks?.PostToolUse` absent (every cron today):** return immediately. No file is read, no process runs.
  - **Present:** `isDeepStrictEqual(settings.hooks.PostToolUse, [framingHookEntry(spawnCwd, nodeBin)])` from `node:util`.
    Otherwise throw `[<cron>] gh-output framing hook self-test FAILED: registration mismatch; expected <json> got <json>`
    (`settings.json` holds no secrets, so printing both is safe). This one check enforces exactly one entry, matcher `Bash`,
    exactly one command hook, and the byte-equal command, so the probed binary is the registered one (CTO C5).
  - **Probe (ii), gh read.** `execFileSync(nodeBin, [framingAbs], { input, encoding: "utf-8", timeout: 10_000 })`, through the
    same `run`-style wrapper, where a non-zero exit or a missing binary is a failure, with
    `{ hook_event_name: "PostToolUse", tool_name: "Bash", tool_input: { command: "gh issue view 1" }, tool_response: { stdout: "x", stderr: "" } }`.
    `isDeepStrictEqual(JSON.parse(stdout), { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: UNTRUSTED_PREAMBLES.github } })`
    must hold. That is an exact key set at both levels, so a stub that adds `decision: "block"` beside a correct
    `hookSpecificOutput` fails (Kieran P1). A JSON parse error or a mismatch throws.
  - **Probe (iii), `ls`.** The same call with `command: "ls"` must produce empty stdout (after trim). Otherwise throw.
- Throw, not mirror-and-proceed (CTO F4, F4' throw half). The probes are deterministic: fixed payloads, no network. So a
  failure is a real defect in a registered hook, such as a broken sibling import, the wrong stdout, or a `decision: "block"`
  that would feed a reason into the model loop on every gh read. Dissent recorded: if after enablement probes fail for
  environmental reasons (node resolution, spawn timeout) rather than hook defects, downgrade only those classes to
  `reportSilentFallback`. Second dissent (CTO C1): if enablement uses a per-cron map such as `CRON_FRAME_GH_OUTPUT`, decide
  again whether to pass the value explicitly to the self-test, as `noFileTools` is.
- **Dormant claim, input by input** (sharp edge: dormant must be shown per prod input). The new branch reads one input, the
  `settings` object `runHookSelfTest` already parsed from `settings.json`. Its only production writer is
  `setupEphemeralWorkspace`, which writes `buildCronEvalSettings(spawnCwd)` immediately before calling `runHookSelfTest`. No
  agent has run yet, so nothing else can have written the file. The AC3 golden shows that output has no `PostToolUse` key, so
  the branch returns at its first line in production. Other inputs (`NODE_BIN`, `process.execPath`, the allowlist file, the
  cron map) do not reach the branch. `cron-bug-fixer.test.ts` mocks `readFileSync` with settings holding only `PreToolUse`, so
  it also stays on the early return. The existing "passes" self-test cases on default settings in
  `cron-claude-eval-substrate.test.ts` (the `runHookSelfTest` describe block) already prove the default path does not throw.
  On a thrown error the cron aborts, the same producer contract as every existing probe; nothing is retried or dropped
  silently.

### Phase 3 — Tests [written before Phases 1-2; each starts RED]

New file `apps/web-platform/test/server/inngest/cron-gh-output-framing-hook.test.ts` (app-local; no `REPO_WIDE_SUITES` entry,
CTO F7):

- **AC1 parity.** `expect(mjs.GH_READ_VERBS).toStrictEqual(GH_READ_VERBS)` and
  `expect(mjs.GITHUB_UNTRUSTED_PREAMBLE).toBe(UNTRUSTED_PREAMBLES.github)`. Behavioural census, in-process (no child process per
  entry): for every entry of the TS `GH_FRAME_VERBS`, `frameDecision` with the real imported parser frames `gh <entry> 1`. The
  binary path is covered by the AC2 rows. The census count equals `GH_FRAME_VERBS.length`, which is greater than 0.
- **AC2 binary rows.** Each row spawns `process.execPath` on the real file with an explicit minimal `env` (no `NODE_OPTIONS`,
  no `GH_TOKEN`). It asserts exit 0 and stdout either deep-equal to the exact framed JSON (exact key sets at both levels) or
  exactly `""`. Rows are named and run through `it.each`. The census asserts the literal count of declared rows, written in the
  test as a number, not a floor recorded from a first green run (Kieran P2: that floor is circular).
  - Frame: `gh issue view 1`; `gh issue view 1 --repo jikig-ai/soleur --json title,body`; `gh pr view 12`;
    `gh pr view 12 --comments`; `gh api repos/jikig-ai/soleur/issues/1/comments`;
    `gh api repos/jikig-ai/soleur/pulls/1/comments --paginate`; `gh issue list --label bug`; `gh run view 123 --log`;
    `git status && gh issue view 1` (second segment); `gh issue view 'one'`; `gh issue view 1#x` (`#` starts a comment only at
    a word start in `tokenize`, so `1#x` is one token); `gh search issues foo`.
  - Nothing: `gh issue create --title t --body b`; `gh issue comment 1 --body x`; `ls`; `git log -1`; `gh label list` (noun
    outside the table, a named gap); `echo gh issue view 1`; `tool_name: "Read"` with a `file_path`; `hook_event_name: "PreToolUse"`
    with a gh read; `tool_input.command` a number; `tool_input` missing; malformed JSON `{not json`; empty stdin; JSON `null`.
  - Nothing, named unreachable gaps (CTO C2; pinned so a later widening is a visible test change): `gh issue ls`;
    `gh issue -R jikig-ai/soleur view 1`; `gh pr --repo=jikig-ai/soleur checks 1`; `/usr/bin/gh pr diff 3`. Containment never
    admits these shapes, so they never reach PostToolUse.
  - Sibling missing: the hook copied alone into a temp dir, then run on a gh read row, gives exit 0 and empty stdout. This is
    the only guard for the framing hook's import failure (CTO C4).
- **Adversarial size (in-process, sharp edge: heuristic over attacker text).** One `frameDecision` call on a command of
  `MAX_BASH_COMMAND_CHARS` (131072) characters made of spaces, `;` runs, `&&` runs and balanced quotes, with a gh read at the
  end, frames. A second call of the same length whose unbalanced quote sits INSIDE the final gh segment (for example padding
  then `gh issue view 'x`) emits nothing, because that segment's token list is `null`. A quote in an EARLIER segment would
  still frame the later gh segment (Kieran P2), and that shape is not part of any contract because containment denies it.
  Correctness only: there is no tight wall-clock bound (a loose 10 s vitest timeout at most), because a timed run measures CI
  load. The linear-cost property belongs to `splitSegments` and `tokenize` and is already pinned in
  `cron-bash-allowlist-hook.test.ts` (the `MAX_BASH_COMMAND_CHARS` timing rows). Containment's `decide()` also runs the same
  parse on the same command first, under the same length cap.
- **Differential (CTO F1, C2), one-way.** The corpus is every gh line from the union of `CRON_BASH_ALLOWLISTS` (imported, not
  copied) with a trailing argument, plus chained segments, quoted arguments, the admitted write row
  `gh issue create --title t --body b --label meta/machinery`, and shapes containment denies (multiline, pipe, `$(…)`). Each row
  first goes through containment `decide()` with that union as its allowlist; no test-only widening. For every ADMITTED row:
  `ghReadVerbOf(cmd).kind === "verb"` implies `frameDecision(...) !== null`, and a row on which the cron hook frames while the
  hosted side does not must be one of the named "known extra framing" rows. The equality form is false on admitted input
  (Kieran P1), in the over-framing direction only:
  - `gh issue comment 1 --body x #"; gh issue view 1; gh issue comment 1 --body y #"` — containment admits it, the cron
    parser sees a `gh issue view` segment and frames, while hosted `ghReadVerbOf` returns `none` (it reads the quoted text as one
    word). Bash runs only the first `gh issue comment`.
  - `"gh issue view 1" + 9000 spaces` — containment admits it (cap 131072), hosted returns `oversize` (cap 8192), the cron hook
    frames.
  Floors: the admitted count and the denied count are each greater than 0, and the admitted write row is admitted (if the
  filing-justification check denies it at work time, the work phase picks the admitted write form and records it). No
  hard-coded corpus size. The test file's header comment says how to triage a failure: "RED after an allowlist or `decide()`
  change means a new gh shape reached the boundary; compare with `ghReadVerbOf` before editing either side" (CTO-devex).
- **Allowlist-shape guard (CTO C2).** Every gh line across `CRON_BASH_ALLOWLISTS` matches `^gh [a-z-]+ [a-z-]+$` or
  `^gh api [^ ]+/$`. A line of any other form fails the test, which is the trigger for the F1 dissent (containment admitting
  more shapes) and for widening `isGhReadTokens`. Floor: at least one gh line is checked.
- **Exports pin.** `splitSegments` and `tokenize` are functions exported by `cron-bash-allowlist-hook.mjs` (CTO risk 1). The
  `describe` title names the consumer: `cron-bash-allowlist-hook exports consumed by cron-gh-output-framing-hook.mjs`
  (CTO-devex).

Additions to `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts`:

- **AC3 golden.** A hard-coded literal, independent of `DEFAULT_CLAUDE_SETTINGS` (Kieran P2: a spread would move both sides
  together): `{ permissions: { allow: [], defaultMode: "default" }, sandbox: { enabled: false }, hooks: { PreToolUse: [{ matcher:
  "*", hooks: [{ type: "command", command: <node> <cwd>/apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs <cwd>/.claude/cron-allow.txt }] }] } }`.
  Only the node token comes from `resolveNodeBin()`. Serialised with `JSON.stringify(x, null, 2)`, it must equal the serialised
  output for no options, `{}`, `{ frameGhOutput: false }`, `{ frameGhOutput: undefined }`, `{ frameGhOutput: 1 as never }` and
  `{ frameGhOutput: "true" as never }`, and `Object.keys(result.hooks)` must equal `["PreToolUse"]` for each (no own
  `PostToolUse: undefined`). The two `as never` rows stay: they are the only pin on the brief's strict `=== true`. With
  `{ frameGhOutput: true }`: `PreToolUse` is unchanged, and `PostToolUse` deep-equals
  `[{ matcher: "Bash", hooks: [{ type: "command", command: "<absolute node> <spawnCwd>/apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs" }] }]`
  written as a literal, not via `framingHookEntry` (absolute node: `path.isAbsolute` on the first token, or the documented
  `"node"` fallback stated as such).
- **AC4 dark.** A token scan over every `.ts`/`.tsx`/`.mjs` file under `apps/web-platform` outside `test/` and `node_modules`
  (the builder is exported, so the root is the app, not only `server/`; floor: more than 100 files). Three assertions:
  (i) `frameGhOutput` appears in no file other than `_cron-claude-eval-substrate.ts`; (ii) no file in scope matches
  `frameGhOutput\s*:\s*true`; (iii) the number of `frameGhOutput` occurrences in the substrate equals a literal count written
  in the test at work time (CTO-devex: any added call site changes it). The test comment says (iii) changes by design at
  enablement. There is no argument-count regex over TypeScript. The PR body also carries `git grep -n frameGhOutput`.
- **Self-test (CTO C1, C4, C5, F7).** Test `runFramingHookSelfTest` directly on `settings` objects, plus one end-to-end case
  through `runHookSelfTest`. Extend `makeSpawnCwd` to copy the real framing hook too, with a `framingSource` override and an
  option to omit it. Framing cases always use the REAL containment hook: `stubHook` reads stdin and calls `process.exit` at
  module top level, so a stubbed containment file would run inside the framing hook's dynamic import (Kieran P2). Cases:
  - `settings` with no `PostToolUse` key and a framing hook file that writes a sentinel and prints garbage: no throw and no
    sentinel (the early return is real; no `chmod`, so it holds for any user ID).
  - `settings` from `buildCronEvalSettings(spawnCwd, { frameGhOutput: true })` plus the real hook: no throw (must pass).
  - End to end: `runHookSelfTest` on a spawn dir whose `settings.json` was written with `{ frameGhOutput: true }` and whose
    framing stub emits nothing: throws, which shows `runHookSelfTest` reaches the framing check.
  - Registered plus a stub that emits `{"decision":"block","reason":"x","hookSpecificOutput":{<correct>}}` for gh: throws
    (exact key set).
  - Registered plus a stub that emits nothing for gh: throws.
  - Registered plus a stub that frames `ls`: throws.
  - Registered plus the framing hook absent: throws.
  - One table-driven bad-shape test sharing one spawn dir (CTO C5), each row throwing "registration mismatch": two entries
    (valid first, extra second); a second hook inside the valid entry; `matcher: "*"`; a command naming another file;
    `PostToolUse: []`.

### Phase 4 — ADR-287 addendum + C4

Append `## Addendum 2026-11-12 (Ref #9601, #11076): cron gh output framing, dark` to ADR-287 with:

1. **What.** A standalone `PostToolUse(Bash)` command hook for cron `claude --print` spawns. Registered only by
   `buildCronEvalSettings(spawnCwd, { frameGhOutput: true })`. No caller passes it, so it is inactive in every cron. It is
   annotate-only and never emits `updatedToolOutput` (decision 7 holds). It complements, and does not replace, the 2026-10-25
   system-prompt append.
2. **How it differs from the hosted twin, and why.** Detection reuses the containment hook's parse, the same tokens that admitted
   the command, and matches `gh <noun> <verb>` on the first three tokens. There is no fallback scan, because containment denies
   the shapes it covered. There is no `-R`/`--repo` skip, `ls` alias or path-qualified `gh`, because containment admits only
   literal `gh <noun> <verb>` prefixes; a test fails if a cron allowlist gains another gh shape. There is no shape gate and no
   telemetry. The table and preamble are pinned by a parity test. The cron hook frames a superset of the hosted decision on
   admitted commands; the known extra cases (a `#`-commented tail, a command over the hosted 8192-character cap) over-frame,
   which is harmless.
3. **Self-test.** When `settings.json` registers a `PostToolUse` key, the spawn-time self-test deep-equals it against the one
   expected entry and runs a gh-read probe (exact output) and an `ls` probe (no output). Any failure throws, which aborts the
   cron. When the key is absent, nothing new runs. Recorded dissent: environmental probe failures (node resolution, timeouts)
   may later be downgraded to `reportSilentFallback`.
4. **Not covered** (named so no coverage is implied): commands that exit non-zero go to `PostToolUseFailure`, which is not
   registered (example: `gh pr checks` while checks fail); GitHub text read through `bash plugins/soleur/skills/community/scripts/community-router.sh github …`,
   which is not a `gh` command at the Bash layer; nouns outside the table (`label list`, `gist`, `workflow`); `-R`/`--repo`
   between noun and verb, the `ls` alias and path-qualified `gh` (unreachable today); `git log` and `git show` text; Task
   subagent coverage (unverified); KB and attachment reads; leader PDF text; the plugin-side CLI. `api: []` frames every
   allowlisted `gh api` call, including write-method calls. That over-frames, which is harmless.
5. **Residuals.** The effect on model behaviour in headless `--print` is unmeasured. The marginal value over the 2026-10-25
   system-prompt append is positional only: the same text, placed next to each result. The Phase 0 probe ran with
   `--setting-sources project` to exclude the developer's own hooks, which production does not pass. Delivery is whatever Phase 0 recorded:
   "verified at 2.1.321" with a pointer to `probe-delivery.md`, or "unverified" with the reason. The note could make a legitimate
   task under-act, and it repeats after every matching call. No public claim follows.
6. **Enablement steps** (none in this change; in order, operator-authorized):
   1. Add a per-cron list `CRON_FRAME_GH_OUTPUT`, shaped like `CRON_NO_FILE_TOOLS`, and thread it through the same directives
      return to the builder call. Re-decide whether to also pass it explicitly to the self-test (CTO C1 dissent).
   2. Replace the dark pins (the AC4 token scan and its occurrence count) with a behavioural test that the listed crons get
      the entry and the others do not. These pins are meant to go RED on the first enablement edit.
   3. Re-rule the brand-survival threshold (the F8 flip condition).
   4. Choose the telemetry signal from two candidates: parse the `--include-hook-events` stream inside the substrate, or rely on
      the self-test alone. The signal must be a closed field set with no paths, filenames or matched text (CLO).
   5. Re-run the delivery probe at the then-pinned CLI, and run an under-action comparison for the first cron enabled, with its
      owner and pass bar stated before the run.
   6. Deploy the option before any cron registers it: the hook runs from the clone of `main` while registration runs from the
      deployed image.
7. **Status.** ADR-287 stays `adopting`. Decision 6 ("Crons never opt in") still concerns the WebFetch scorer only.

C4: no `.c4` edit (see `### C4 views`).

### Phase 5 — Verification (local; no deploy) and push hygiene

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-gh-output-framing-hook.test.ts test/server/inngest/cron-claude-eval-substrate.test.ts test/server/inngest/cron-bash-allowlist-hook.test.ts test/server/inngest/cron-bug-fixer.test.ts test/server/inngest/cron-untrusted-preamble.test.ts test/untrusted-content.test.ts test/repo-wide-containment.test.ts`
  (the exact runner invocation is taken from `apps/web-platform/package.json` scripts at work time).
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, the app's ESLint, and `bash plugins/soleur/test/c4-count-parity.test.sh`.
  The new test file is collected by the `unit` vitest project (`include: ["test/**/*.test.ts"]` in `apps/web-platform/vitest.config.ts`),
  so it is registered without a list edit.
- Run by hand, once, only the mutation-matrix rows marked **hand-run** below: the rows a single equality assertion does not
  already imply (own-dispatch, second-member, reorder and must-PASS rows). Rows a `toStrictEqual`/`toBe` on a constant or a
  golden obviously catches are not hand-run. Record each hand-run row's RED/PASS in the PR body. Restore from the echoed backup
  path, never a re-glob (learning 2026-11-09, session error 4).
- `git grep -n frameGhOutput` output goes into the PR body (AC4).

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — `FRAMING_HOOK_REL_PATH`,
  `framingHookEntry`, the `buildCronEvalSettings` option, the new `runFramingHookSelfTest`, and one call to it from
  `runHookSelfTest`.
- `apps/web-platform/server/untrusted-content.ts` — one comment line each on `GH_READ_VERBS` and `UNTRUSTED_PREAMBLES.github`
  pointing at the cron copy and its parity test. No code change.
- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` — a comment-only `Consumers` note above `splitSegments` and
  `tokenize` (Phase 1). No code change; containment behaviour is untouched.
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` — AC3 golden, AC4 dark scan, framing self-test
  cases, and the `makeSpawnCwd` extension.
- `knowledge-base/engineering/architecture/decisions/ADR-287-untrusted-content-annotate-not-block-heuristic-first.md` —
  addendum 2026-11-12.

## Files to Create

- `apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs`
- `apps/web-platform/test/server/inngest/cron-gh-output-framing-hook.test.ts`
- `knowledge-base/project/specs/feat-one-shot-11076-cron-gh-output-framing/decision-challenges.md` (written at plan time)
- `knowledge-base/project/specs/feat-one-shot-11076-cron-gh-output-framing/tasks.md` (written at plan time)
- `knowledge-base/project/specs/feat-one-shot-11076-cron-gh-output-framing/probe-delivery.md` (written by Phase 0)

## Open Code-Review Overlap

None. 95 open `code-review` issues were checked on 2026-11-12. None names `cron-gh-output-framing-hook`,
`_cron-claude-eval-substrate.ts`, `cron-claude-eval-substrate.test.ts`, `ADR-287`, `untrusted-content.ts` or
`cron-bash-allowlist-hook.mjs`.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-287 with a dated addendum (Phase 4), per the CTO's 2026-11-12 ruling (row S2). There is no new ordinal, so there is no
ordinal collision risk. The addendum extends the 2026-10-25 amendment and the 2026-11-08 addendum to a new surface. It reverses
no decision.

### C4 views

No `.c4` edit. All three files were read on 2026-11-12 (`model.c4` 1113 lines, `views.c4` 151, `spec.c4` 54). Enumeration:

- (a) External human actors: GitHub text authors are already reached through the `github` external system and the `contributor`
  actor. None is added.
- (b) External systems: `github` and `anthropic` are both modeled. None is added.
- (c) Containers or stores: the cron eval substrate runs inside the existing `api` / `inngest` containers. No store is added.
- (d) Access relationships: none change. The hook is dark, and no edge gains or loses a flow.

The cron containment hook and the 2026-10-25 cron system-prompt append are not modeled at component level today (`grep -n
"containment\|append-system\|claude-eval"` over `model.c4` finds only the `api -> kb` unattended-authorship edge). A dark
opt-in hook does not make that edge's prose false. The `api` container description already names the hosted PostToolUse(Bash)
framing note; the cron one is not live, so naming it there would overstate the deployed system. `plugins/soleur/test/c4-count-parity.test.sh`
ran green on 2026-11-12 (13/13).

### Sequencing

The addendum is written now and describes the dark state. Enablement is a later, operator-authorized slice. It is not
postponed to its own issue, because nothing is decided here beyond the dark hook.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing, while the hook stays dark. The one line that runs on every spawn is
  the `runFramingHookSelfTest` early return when `settings.hooks.PostToolUse` is absent. A bug there that throws would make
  every scheduled cron self-report FAILED on its next run (missed digests, triage and follow-through filings on the platform's
  own repo) until a revert. The existing default-settings "passes" self-test cases and the new "no key + sentinel stub" case
  pin that path.
- **If this leaks, the user's data / workflow / money is exposed via:** no new vector. The hook reads model-controlled stdin
  (ADR-156) and writes a constant string or nothing. It reads no file, no env and no network. The containment hook gets a
  comment-only edit; its code is only imported.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the cron substrate operates on the platform's own `jikig-ai/soleur` repo, not a
  customer workspace. The change is dark and the default settings are byte-identical, so no single user can be harmed by it.
  The hosted twin was `single-user incident` because it ran in customer Concierge sessions.
- `threshold: none, reason: the cron eval substrate clones and runs only on the platform's own repo (no customer workspace, customer data or credential path) and the change is dark, so the worst case is every cron reporting FAILED`
- Ruled by CTO agent, 2026-11-12 (row F8). The clone target is fixed to `${REPO_OWNER}/${REPO_NAME}` (`buildAuthenticatedCloneUrl`
  in `_cron-shared.ts`, used by `setupEphemeralWorkspace`). **What would flip it to `single-user incident`:** any caller passing
  `frameGhOutput: true` in this PR; the substrate cloning or acting in a customer repo or workspace; or the self-test change doing
  more than reading `settings.json`. Enablement sets its own threshold again.

## Observability

```yaml
liveness_signal:
  what: "runFramingHookSelfTest (registration deep-equal, gh-read probe, ls probe) on every cron spawn whose settings.json registers a PostToolUse key; a failure throws, which the cron's existing FAILED self-report surfaces through the Inngest function error -> Sentry (layer 2 app error reporting) and the run report. No spawn registers the hook in this change, so the signal is inactive by design and fires nowhere until enablement."
  cadence: "per cron spawn that registers the hook (zero today); every other spawn returns early"
  alert_target: "the existing cron FAILED self-report path and Sentry issue routing for the cron function; no new alert is provisioned"
  configured_in: "apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts (runFramingHookSelfTest, called from runHookSelfTest)"
error_reporting:
  destination: "Sentry, through the existing cron function error path (the self-test throw propagates out of setupEphemeralWorkspace exactly like the containment probes)"
  fail_loud: "a thrown Error starting '[<cron>] gh-output framing hook self-test FAILED:' that aborts the cron before the agent spawns"
failure_modes:
  - mode: "framing hook missing, crashed, or emitting the wrong text in an opted-in spawn"
    detection: "in-surface probe: the host runs the clone's framing binary with the byte-identical node and path the CLI would use, and compares its stdout to UNTRUSTED_PREAMBLES.github; one throw message per probe names which of registration, gh-read or ls failed"
    alert_route: "cron FAILED self-report + Sentry issue"
  - mode: "CLI drops PostToolUse additionalContext under --print"
    detection: "Phase 0 nonce probe at the pinned CLI (probe-delivery.md); not observable at runtime because the hook emits no telemetry"
    alert_route: "none at runtime (accepted; the ADR records delivery as verified or unverified per the probe, and enablement re-runs the probe)"
  - mode: "a cron allowlist gains a gh line that is not literal gh <noun> <verb> or gh api <path>/, so a shape isGhReadTokens does not parse can reach PostToolUse"
    detection: "pre-merge: the allowlist-shape guard in cron-gh-output-framing-hook.test.ts fails on the edit that adds it"
    alert_route: "CI failure on that PR (the F1 dissent trigger)"
  - mode: "gh read the hook does not recognise (PostToolUseFailure, community-router.sh github, nouns outside the table)"
    detection: "not detectable by design; named in the ADR addendum"
    alert_route: "none (accepted, documented gap)"
logs:
  where: "the hook writes no logs (stdout is the hook protocol channel); self-test failures land in the Inngest function error and the cron run report"
  retention: "Sentry plan retention for function errors; nothing new is retained"
discoverability_test:
  command: "node -e 'process.stdout.write(require(\"node:child_process\").spawnSync(process.execPath,[\"apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs\"],{input:JSON.stringify({hook_event_name:\"PostToolUse\",tool_name:\"Bash\",tool_input:{command:\"gh issue view 1\"}}),encoding:\"utf8\"}).stdout)'"
  expected_output: "UNTRUSTED"
```

The command contains none of Check 10's shell-active bytes (`|`, `;`, `&`, `<`, `>`, `$`, backtick). Its quoting was verified
on 2026-11-12 against a scratch stub at the same relative path, under `env -i PATH=/usr/local/bin:/usr/bin:/bin`, where it
printed the framed JSON. The real binary does not exist until Phase 1, so the work phase runs the command once against it
(AC10). The `discoverability_test` checks the hook offline: it proves the committed binary frames a gh read. It does not prove any cron
registers the hook, and none does. A post-enablement signal is an enablement precondition (CTO F3), not part of this change.

Affected-surface note (Phase 2.9.2): the cron worker is a surface the operator cannot inspect directly. The in-surface probe is
the self-test, which runs the clone's own binary on the host before the agent starts. Its three named probes separate "not
registered correctly", "binary absent or broken" and "binary frames too much".

## Guard Contract

Rows marked **hand-run** are run once at work time, with RED/PASS recorded in the PR body (Phase 5). The other rows are
implied by one equality assertion on a constant or a golden and are listed for design completeness.

### Guard 1 — cron verb table and preamble parity with the hosted source of truth

**Property.** The cron hook frames exactly the gh read verbs, and emits exactly the preamble text, that `untrusted-content.ts`
defines for the hosted hook, and its decision reads only its exported table.

**Assembly.** Two chokepoints on each side. Hosted: `GH_READ_VERBS` and `UNTRUSTED_PREAMBLES.github` in `untrusted-content.ts`
(`GH_FRAME_VERBS` is derived from the table). Cron: the exported `GH_READ_VERBS` and `GITHUB_UNTRUSTED_PREAMBLE` of
`cron-gh-output-framing-hook.mjs`, and `isGhReadTokens`, the only decision path, which must read that exported object and no
inline list. The data assertion covers the two constants. The in-process behavioural census covers the decision path through
`frameDecision` with the real parser, for every `GH_FRAME_VERBS` entry.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `"edit"` to the `.mjs` `issue` list | RED (deep-equal) |
| 2 | Delete the `release` noun from the `.mjs` table | RED (deep-equal, and census rows `release view` / `release list` unframed) |
| 3 | Change one character of the `.mjs` preamble | RED (string equality and the binary-row exact JSON) |
| 4 | **hand-run** Own dispatch: `isGhReadTokens` uses an inline `["view"]` for `issue` while the exported table stays correct | RED (census row `gh issue list 1` unframed) |
| 5 | Second member: add `gist: ["view"]` to the TS table only | RED (deep-equal; census count is `GH_FRAME_VERBS.length`, so it grows) |
| 6 | **hand-run** Reorder the `.mjs` table keys (must-PASS: order is not part of the contract) | PASS |

**Harness rows.** (H1) The census iterates an empty or wrong array (for example `Object.keys({})`), and the assertion
`count === GH_FRAME_VERBS.length && count > 0` fails: RED. (H2) A must-PASS input that is not canonical: the `.mjs` table
written with different key order and non-frozen inner arrays still deep-equals: PASS.

**Anchor.** Both sides live in this repo and one diff could edit both plus the test. The independent anchor is ADR-287's
addendum text, which names the verb table, and review. Residual: consistency, not integrity.

### Guard 2 — default settings stay byte-identical and no production caller opts in

**Property.** Unless `frameGhOutput` is exactly `true`, `buildCronEvalSettings` produces byte-for-byte today's `settings.json`
with no own `PostToolUse` key, and no production source under `apps/web-platform` passes the option at all.

**Assembly.** The single return of `buildCronEvalSettings`. The one production call site in `setupEphemeralWorkspace`. Every
`.ts`/`.tsx`/`.mjs` file under `apps/web-platform` outside `test/` and `node_modules` (the builder is exported, so any future
call site in any app file is in scope).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Register `PostToolUse` unconditionally | RED (golden) |
| 2 | **hand-run** Use a truthy check `if (opts.frameGhOutput)` | RED (`1` and `"true"` rows) |
| 3 | **hand-run** Write `PostToolUse: opts.frameGhOutput === true ? [...] : undefined` (serialises identically) | RED (`Object.keys(hooks)` row) |
| 4 | Emit the `hooks` key before `permissions` in the default object | RED (golden string comparison) |
| 5 | **hand-run** Own dispatch: the AC4 scan's file glob matches nothing (wrong root) | RED (file-count floor > 100) |
| 6 | **hand-run** Second member: a new app file calls `buildCronEvalSettings(cwd, { frameGhOutput: true })` after the compliant substrate call | RED (token outside the substrate, and `frameGhOutput: true` match) |
| 7 | **hand-run** Change `setupEphemeralWorkspace` to pass `{ frameGhOutput: flag }` | RED (substrate occurrence count changes) |

**Harness rows.** (H1) The golden is computed by calling `buildCronEvalSettings` or spreads `DEFAULT_CLAUDE_SETTINGS` (a
tautology). The test instead builds the golden from a hard-coded literal that contains `"PreToolUse"` and not `"PostToolUse"`,
and asserts both facts, so a swapped-in function output with a stray key goes RED. (H2) Must-PASS: no options, `{}`,
`{ frameGhOutput: false }` and `{ frameGhOutput: undefined }` all equal the golden.

**Anchor.** The golden reproduces the pre-change builder. The independent anchor is `git show origin/main:apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
(the `buildCronEvalSettings` body and `DEFAULT_CLAUDE_SETTINGS`). The work phase compares the golden against that body's
output once, by hand, and records it in the PR body. The occurrence count in (iii) is a stored value one diff can edit with
the code; its anchor is review of that diff, and the enablement steps in the ADR say it changes by design.

### Guard 3 — spawn-time self-test of a registered framing hook

**Property.** A spawn whose `settings.json` has a `hooks.PostToolUse` key aborts unless that value deep-equals the single
expected Bash entry and the registered binary frames a gh read with exactly the expected keys and stays silent on `ls`; a
spawn without the key runs nothing new.

**Assembly.** The `settings` object `runHookSelfTest` already parsed, passed to `runFramingHookSelfTest`, which is the only
place the trigger is read. The whole `hooks.PostToolUse` value (every element and every hook inside it, by deep-equal). The
binary at `join(spawnCwd, FRAMING_HOOK_REL_PATH)` and the sibling it imports at runtime. The single call from
`runHookSelfTest`, after the containment probes.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Registered, and the framing stub emits nothing for `gh issue view 1` | RED (throw) |
| 2 | Registered, and the stub frames `ls` | RED (throw) |
| 3 | **hand-run** Own dispatch: delete the `runFramingHookSelfTest` call from `runHookSelfTest` | RED (end-to-end case no longer throws) |
| 4 | **hand-run** Second member: a valid first entry plus a second entry | RED (bad-shape row) |
| 5 | Second hook inside the single valid entry (`hooks: [valid, extra]`) | RED (bad-shape row) |
| 6 | `matcher: "*"` | RED (bad-shape row) |
| 7 | Registered command names a different file | RED (bad-shape row) |
| 8 | Framing hook file absent from the spawn dir | RED (throw) |
| 9 | **hand-run** Stub emits `decision: "block"` beside a correct `hookSpecificOutput` | RED (exact key set) |
| 10 | **hand-run** Reorder: run the probes before the key-presence check, so they run on every spawn | RED ("no key + sentinel stub" case leaves a sentinel or throws) |

**Harness rows.** (H1) `makeSpawnCwd` silently does not copy the framing hook. The must-PASS case "registered + real hook"
would then throw, so a broken fixture cannot pass. (H2) Must-PASS that is not canonical: settings with a `PreToolUse` entry
and no `PostToolUse` key, with a sentinel-writing stub present, does not throw and leaves no sentinel.

**Anchor.** Probes and expected text come from the same `UNTRUSTED_PREAMBLES.github` import the spawn uses, and the expected
entry from the same `framingHookEntry` the builder uses. One diff could weaken both the probe and the hook, which is accepted,
the same residual as the containment probes. The AC3 `true` row pins the entry as a literal, independent of the helper.

### Guard 4 — hook binary behaviour on fixture stdin

**Property.** The binary exits 0 on every input and writes either exactly the framed JSON (no other key at either level) or
nothing, and it frames exactly when a segment's dequoted tokens start `gh <noun>` with the verb in that noun's list.

**Assembly.** `main()` (the stdin read, the dynamic sibling import, the single stdout write, `process.exit(0)`), `frameDecision`
(event and tool guards, the segment loop) and `isGhReadTokens` (command word, noun, verb, `api` noun-only rule).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | **hand-run** Own dispatch: the `main()` guard compares against the wrong file name, so main never runs | RED (every frame row gets empty stdout) |
| 2 | **hand-run** Second member: only the first segment is checked | RED (row `git status && gh issue view 1`) |
| 3 | Exit 1 on malformed JSON | RED (rows malformed, empty) |
| 4 | Add `updatedToolOutput` to the output | RED (exact key set) |
| 5 | Accept `hook_event_name` other than PostToolUse | RED (row PreToolUse) |
| 6 | **hand-run** Static `import` of the sibling (missing sibling makes the process exit non-zero) | RED (sibling-missing row) |
| 7 | Match `tokens.includes("gh")` instead of `tokens[0] === "gh"` | RED (row `echo gh issue view 1`) |

**Harness rows.** (H1) A row is dropped from the table. The census asserts the literal declared row count: RED. (H2)
Must-PASS that is not canonical: `gh issue view 'one'` (quoted argument) and `gh issue view 1#x` frame.

**Anchor.** The rows are derived from the brief's AC2 list and the CTO's F1 and C2 rules, not from the implementation.

### Guard 5 — one-way differential agreement with the hosted tokenizer on admitted commands

**Property.** For every command the cron containment hook admits under the real cron allowlists, a hosted `ghReadVerbOf`
read verdict implies the cron hook frames, and every case where the cron hook frames without a hosted read verdict is a
named known-extra row.

**Assembly.** The corpus derived from the union of `CRON_BASH_ALLOWLISTS` (imported). The containment `decide()` filter with
that union. The admitted and denied counters. Both decision functions called directly on each admitted row. The named
known-extra set.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Cron decision treats `issue view` as not a read | RED (hosted verb, cron silent) |
| 2 | **hand-run** Own dispatch: the filter admits zero rows (empty allowlist) | RED (admitted floor) |
| 3 | **hand-run** Second member: cron checks only the first segment | RED (row `git status && gh issue view 1`) |
| 4 | Cron decision frames `gh issue create` (the admitted write row) | RED (cron frames, not a named known-extra row) |

**Harness rows.** (H1) A filter that admits everything would compare the multiline rows too. The denied floor (> 0) and an
explicit "multiline row is denied" assertion make that RED. (H2) Must-PASS: a denied shape such as `gh issue view 1 | cat` is
excluded and not compared, and the two known-extra rows pass.

**Anchor.** The hosted tokenizer is an independent implementation that has shipped since 2026-11-09. A hosted read the cron
hook misses on an admitted row is a real divergence.

### Guard 6 — every cron gh allowlist line has a shape the cron predicate parses

**Property.** Every gh line in `CRON_BASH_ALLOWLISTS` is literal `gh <noun> <verb>` or `gh api <path>/`, so no gh shape
outside `isGhReadTokens`'s grammar can be admitted by containment.

**Assembly.** The imported `CRON_BASH_ALLOWLISTS` object, every cron key and every line under it, filtered to lines whose first
token is `gh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `gh issue -R jikig-ai/soleur view` to one cron | RED |
| 2 | **hand-run** Own dispatch: the filter matches no gh line (for example keys on `"gh:"`) | RED (floor >= 1) |
| 3 | **hand-run** Second member: add `gh pr ls` to a second cron after a compliant first | RED |

**Harness rows.** (H1) The test iterates only the first cron key: row 3 stays green, so the loop must cover every key; RED
once fixed. (H2) Must-PASS: `gh api repos/jikig-ai/soleur/` passes.

**Anchor.** The allowlists are reviewed security config; widening one is already a reviewed change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "New `apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs` (PostToolUse, Bash matcher). On a gh read verb it emits `hookSpecificOutput.additionalContext` with the GitHub untrusted preamble" [brief] | Phase 1; Files to Create entry 1 | mapped |
| 2 | "Annotate only, never rewrite output." [brief] | Phase 1 rules; Guard 4 row 4 | mapped |
| 3 | "Read-verb table is a .mjs port of `GH_READ_VERBS` from `server/untrusted-content.ts`." [brief] | Phase 1 `GH_READ_VERBS`; Guard 1 | mapped |
| 4 | "Always exit 0; parse errors emit no context." [brief] | Phase 1 `main()`; Guard 4 rows 3 and 6 | mapped |
| 5 | "`buildCronEvalSettings(spawnCwd, { frameGhOutput?: boolean })` ... adds the PostToolUse entry only when `frameGhOutput === true`. Default off; no caller passes true." [brief] | Phase 2; Guard 2 | mapped |
| 6 | "The spawn-time hook self-test also checks the PostToolUse hook when it is registered." [brief] | Phase 2 `runFramingHookSelfTest`, keyed on the file (CTO C1); Guard 3 | mapped |
| 7 | "Amend ADR-287 (untrusted-content annotate-not-block) with the cron surface, its dark status, and the residual that the effect in headless `claude --print` is unmeasured." [brief] | Phase 4 | mapped |
| 8 | "AC1 parity test: .mjs verb table deep-equals GH_READ_VERBS and the preamble deep-equals UNTRUSTED_PREAMBLES.github." [brief] | Phase 3 AC1; AC1 | mapped |
| 9 | "AC2 hook binary on fixture stdin: gh issue view / gh pr view / gh api .../comments read shapes emit the preamble; gh issue create, ls, non-Bash tools emit nothing; malformed JSON and empty stdin exit 0 with no context; named rows with a row-count census." [brief] | Phase 3 AC2 rows; AC2 | mapped |
| 10 | "AC3 default buildCronEvalSettings output byte-matches today's (no PostToolUse key); with frameGhOutput true exactly one PostToolUse Bash entry with absolute node and hook command." [brief] | Phase 3 AC3; AC3 | mapped |
| 11 | "AC4 `git grep frameGhOutput` shows no production caller passing true." [brief] | Phase 3 AC4 token scan; Phase 5 grep; AC4 | mapped |
| 12 | "AC5 existing cron substrate, containment and repo-wide-suites tests stay green; register the new test in repo-wide-suites.ts if it reads outside the app." [brief] | Phase 5 suite list; AC5 | mapped |
| 13 | "AC6 PR body says `Ref #11076` and `Ref #9601`, never Closes; no claim the control is covered or measured." [brief] | AC6 | mapped |
| 14 | "CTO dissent to record: if a probe shows `--print` drops PostToolUse additionalContext, switch to the KB Read hook instead." [brief] | Phase 0 decision branch; decision-challenges row S1 | mapped |
| 15 | "Record the CTO ruling of 2026-11-12 that selected this slice ... as rows." [brief] | decision-challenges.md rows S1-S3 | mapped |
| 16 | "this PR's verification must not depend on a deploy." [brief] | Phase 5 (local only); AC7 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cron-gh-output-framing-hook.mjs` | asks 1-4 | asked |
| `_cron-claude-eval-substrate.ts` edits | asks 5-6 | asked |
| `cron-gh-output-framing-hook.test.ts` | asks 8-9 | asked |
| `cron-claude-eval-substrate.test.ts` additions | asks 6, 10, 11 | asked |
| ADR-287 addendum | ask 7 | asked |
| `decision-challenges.md` | ask 15 | asked |
| Phase 0 delivery probe + `probe-delivery.md` | ask 14 | asked |
| Detection by reusing the containment parser (F1) | — | inferred — justification: the brief names the table port but not the detection logic, and the CTO ruled the reuse (F1) because the containment parse is what admitted the command |
| Differential test against `ghReadVerbOf` (Guard 5) | — | inferred — justification: CTO F1 condition; without it the reuse could diverge from the hosted semantics silently |
| Back-pointer comments on `GH_READ_VERBS`, `UNTRUSTED_PREAMBLES.github` and the containment `splitSegments`/`tokenize` | — | inferred — justification: plan review (CTO-devex P1); the drift pin and the inverted failure posture are only useful if whoever edits a shared piece can find the second consumer |
| Exports pin for `splitSegments` / `tokenize` | — | inferred — justification: CTO risk 1; a renamed export would silently drop annotation |
| `framingHookEntry` helper and the separate `runFramingHookSelfTest` | — | inferred (CTO C5; Kieran P2) — justification: one source for the expected entry, and the 300-line `runHookSelfTest` gets one call instead of a new branch |
| Registration deep-equal and exact-key probe checks | — | inferred (CTO F4, C5) — justification: "checks the PostToolUse hook" is met only if the probed binary is the registered one and a `decision` key cannot ride along |
| Allowlist-shape guard (Guard 6) | — | inferred (CTO C2) — justification: the simple predicate is exact only while every allowlisted gh line is literal; the guard fires when that stops holding |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 10 (5 edit, 5 create, of which 3 are planning or evidence artifacts) | Estimated changed lines: ~520 (hook ~80,
  substrate ~70, tests ~320, ADR ~45, comments ~10, planning artifacts excluded)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR #12705)

- [ ] **AC0** Phase 0 evidence is committed at `knowledge-base/project/specs/feat-one-shot-11076-cron-gh-output-framing/probe-delivery.md`
  with the CLI version per arm. Its outcome follows the decision branch: delivery observed at 2.1.321, or the reason it could
  not run. If delivery was NOT observed, this plan stops at Phase 0 and is re-scoped through the CTO.
- [ ] **AC1** `cron-gh-output-framing-hook.test.ts` asserts `toStrictEqual(GH_READ_VERBS)` and
  `toBe(UNTRUSTED_PREAMBLES.github)`, and the in-process behavioural census frames every `GH_FRAME_VERBS` entry (count
  equals `GH_FRAME_VERBS.length`, > 0).
- [ ] **AC2** The binary rows in Phase 3 all pass with exit 0. Frame rows produce exactly
  `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":<preamble>}}`. Silent rows, including the four named
  unreachable-gap rows, produce `""`. The census asserts the literal declared row count. The one-way differential (Guard 5)
  and the allowlist-shape guard (Guard 6) pass.
- [ ] **AC3** The serialised default `buildCronEvalSettings` output equals the hard-coded golden literal for no options, `{}`,
  `false`, `undefined`, `1` and `"true"`, and `Object.keys(hooks)` is `["PreToolUse"]` for each. With `true` the
  `PostToolUse` value deep-equals the literal single Bash entry whose command is
  `<absolute node> <spawnCwd>/apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs`, and `PreToolUse` is unchanged.
- [ ] **AC4** The dark token scan passes: `frameGhOutput` appears in no non-test app file except the substrate, no non-test
  app file matches `frameGhOutput\s*:\s*true`, and the substrate occurrence count equals its literal. The PR body carries
  the output of `git grep -n frameGhOutput`, with no production line passing `true`.
- [ ] **AC5** Green: `cron-claude-eval-substrate.test.ts`, `cron-bash-allowlist-hook.test.ts`, `cron-bug-fixer.test.ts`,
  `cron-untrusted-preamble.test.ts`, `untrusted-content.test.ts`, `repo-wide-containment.test.ts`, the new test file, app `tsc`
  and ESLint. The new test is not added to `repo-wide-suites.ts`, because it reads only inside `apps/web-platform`, and
  `repo-wide-containment.test.ts` confirms that.
- [ ] **AC6** The PR body says `Ref #11076` and `Ref #9601` and contains no `Closes`, `Fixes` or `Resolves` keyword.
  `gh pr view 12705 --json closingIssuesReferences` returns `[]`. No sentence in the PR body, the ADR or code comments claims the
  control is covered, measured or protective. The ADR uses "annotation", "unmeasured" and "dark".
- [ ] **AC7** No deploy, flag, Doppler, Terraform, migration or prd workflow dispatch is part of verification. The PR checks are
  the gate.
- [ ] **AC8** ADR-287 carries `## Addendum 2026-11-12 (Ref #9601, #11076): cron gh output framing, dark`, with items 1-7 from
  Phase 4, including the named gaps (PostToolUseFailure, community-router, the unreachable `-R`/`ls`/path-qualified shapes,
  `api` over-framing), the ordered enablement steps, and the Phase 0 delivery result.
- [ ] **AC9** Every Guard Contract row marked **hand-run** was run once as a single-row mutation, and its observed RED or PASS
  is recorded in the PR body.
- [ ] **AC10** The `discoverability_test.command` from `## Observability`, run from the repo root, prints a line containing
  `UNTRUSTED`.

### Operator-owned, not in this PR (no action by the agent)

- Enabling the hook for any cron, choosing which cron, and authorizing it. This is a later slice, after the enablement
  preconditions in the ADR addendum are met.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO selected the slice and ruled F1-F8 on 2026-11-12, F4' and F5' after the Step 4.5 advisor challenge, and C1-C5 after plan review (C1 restores F4's file-keyed trigger; `decision-challenges.md`). The key points: reuse the
containment parse instead of porting the hosted tokenizer; cut the fallback, the shape gate and the telemetry; throw on a broken
registered hook; probe delivery first.

Legal was assessed as not relevant: the change emits no telemetry, processes no personal data, and adds no new processing
activity. The CLO condition on #11076 (a closed telemetry field set) is preserved by emitting nothing, and is restated as an
enablement precondition. Product: no user-facing surface, no UI file (no Files-to-Create entry matches the UI-surface term list).
Marketing, Sales, Finance, Operations and Support: no implications. The GDPR gate does not fire: no regulated-data surface and
none of triggers (a)-(d). IaC, encryption and task-design gates do not fire: no infrastructure, no store or connection, no new
autonomous task surface.

## Test Scenarios

- unit — Given the TS table and preamble, when the `.mjs` exports are compared, then they are strictly equal (AC1).
- integration (real `node` child process) — Given each AC2 row as stdin, when the binary runs, then it exits 0 and prints the
  exact framed JSON or nothing (AC2).
- unit — Given each corpus command admitted by containment `decide()` under the real cron allowlists, when both decisions run,
  then a hosted read implies a cron frame, and every cron-only frame is a named known-extra row (Guard 5).
- unit — Given every gh line in `CRON_BASH_ALLOWLISTS`, then it is literal `gh <noun> <verb>` or `gh api <path>/` (Guard 6).
- unit — Given each option value, when `buildCronEvalSettings` runs, then the default output equals the golden and `true` adds
  exactly one Bash PostToolUse entry (AC3).
- unit (token scan) — Given every non-test app source file, when scanned, then `frameGhOutput` appears only in the substrate,
  never as `frameGhOutput: true`, and the substrate count equals its literal (AC4).
- integration (real binaries in a temp spawn dir) — Given each settings fixture, when `runFramingHookSelfTest` runs (and once
  end to end through `runHookSelfTest`), then it throws or passes as Guard 3 specifies, including the "no key + sentinel stub"
  must-pass case.
- regression — Given the unchanged default settings, when the existing substrate, containment, cron-bug-fixer and preamble suites
  run, then they stay green (AC5).
- probe (manual, local, Phase 0, not a test) — the nonce delivery probe at CLI 2.1.321.

No e2e test is planned. Delivery through a real model is a one-off probe, not a suite.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails
  `deepen-plan` Phase 4.6. It is filled here (`none`, with the preflight scope-out reason).
- The framing hook imports the containment hook at runtime. A rename of `splitSegments` or `tokenize` drops annotation silently
  in the child. The exports pin, the AC2 frame rows and self-test probe (ii) catch it pre-merge and at spawn. The containment
  file's `Consumers` comment names the inverted posture (null or throw means no annotation).
- `splitSegments` splits on `;`, `&&` and `||` even inside quotes, and `tokenize` treats `#` at a word start as a comment
  where the hosted tokenizer does not. A command like `gh issue comment 1 --body x #"; gh issue view 1; …"` is admitted by
  containment and framed by the cron hook while hosted says `none`. That is over-framing only, named as a known-extra row in
  the one-way differential (Guard 5) and in the ADR.
- Segmenting shell text (sharp edge #9088): the hook does not write its own segmenter. It reuses the one that admitted the
  command, so redirect operators, substitution and backgrounding never reach it (containment denies them first). `#` starts a
  comment only at a word start in `tokenize`, which a row (`gh issue view 1#x`) pins.
- `api: []` over-frames `gh api` write calls. This is deliberate and documented in the ADR, not a bug.
- The hook runs from the clone of `main` and registration runs from the deployed image. Until a deploy carries the option, no
  cron can register it, which is consistent with dark.
- `makeSpawnCwd` copies files. If the fixture forgets the framing hook, the must-pass registered case goes red (Guard 3 H1).
  That failure is intended.
- The Check 10 `discoverability_test` runs `node` from `/usr/bin`. It exists on this host. The command spawns the committed
  binary, so it finishes far inside 15 s.
- The AC2 census asserts the literal declared row count (`it.each` already guarantees every declared row runs), so a dropped
  row is a visible test diff.
- Framing self-test cases must use the REAL containment hook. `stubHook` reads stdin and calls `process.exit` at module top
  level, so a stubbed containment file would execute inside the framing hook's dynamic import and print a PreToolUse decision.
- The plan names the option identifier only in the substrate. The hook's header comment and any non-test app file must not
  spell it, or the AC4 token scan goes RED; this is deliberate.

## Non-Goals

Enabling the hook anywhere; creating or wiring any flag; a `setupEphemeralWorkspace` parameter; a KB or attachment Read hook;
leader PDF text; scoring cron output; any telemetry; `PostToolUseFailure` registration; the plugin-side CLI; widening the verb
table. These are recorded in ADR-287 or #11076 and are not new deferrals, so no new tracking issue is filed. #11076 stays open
as their tracker.
