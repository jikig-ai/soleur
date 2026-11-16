# Tasks: cron gh-output framing hook (dark, opt-in)

Plan: `knowledge-base/project/plans/2026-11-12-feat-cron-gh-output-framing-hook-plan.md`. Ref #11076, Ref #9601 (never
Closes). Draft PR #12705; open no other PR. No deploy, flag, Doppler, Terraform, migration or prd dispatch.

## Phase 1: Setup and delivery probe (Phase 0 of the plan; no product code)

- [x] 1.1 In a scratch directory outside the repo, build a `.claude/settings.json` shaped like `buildCronEvalSettings` output:
  the `*` PreToolUse containment hook with a `cron-allow.txt` admitting `echo`, plus the PostToolUse entry under test.
- [x] 1.2 Run 1 at `npx -y @anthropic-ai/claude-code@2.1.321`: a nonce stub hook with `--strict-mcp-config`,
  `--output-format json`, `--append-system-prompt <UNTRUSTED_PREAMBLES.github>`, `--print`, `--setting-sources project`,
  `--model haiku`. The prompt runs `echo hello`. Capture the stub's stdin payload keys (required evidence).
- [x] 1.3 Run 2: the same setup with no PostToolUse entry (negative control, expect `NONE`).
- [x] 1.4 Write `probe-delivery.md` with the CLI version, flags, nonce, both results and the payload keys.
- [x] 1.5 Decision branch: if there is no nonce at 2.1.321, stop and re-scope through a new CTO consult (KB Read hook dissent).
  If the probe cannot run, proceed and record "delivery and effect unverified" with the reason.

## Phase 2: Core Implementation

- [x] 2.1 Write the Phase 3 tests first and confirm each starts RED (see 3.x).
- [x] 2.2 Create `apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs`.
  - [x] 2.2.1 Export the `GH_READ_VERBS` copy and `GITHUB_UNTRUSTED_PREAMBLE`.
  - [x] 2.2.2 `isGhReadTokens`: `tokens[0] === "gh"`, the noun found with `hasOwn` in the table, the verb in the noun's
    list, and `api: []` matches on the noun (CTO C2).
  - [x] 2.2.3 `frameDecision(raw, { splitSegments, tokenize })`: never throws, never reads `tool_response`, emits only
    `hookSpecificOutput.{hookEventName, additionalContext}`.
  - [x] 2.2.4 `main()`: dynamic import of the sibling, a single stdout write and `exit(0)`, guarded by
    `argv[1].endsWith("cron-gh-output-framing-hook.mjs")` so importing the module has no side effects (CTO D4).
  - [x] 2.2.5 Header comment covering annotate-only, always exit 0, dark, the parity pin and the inverted posture. It must
    not spell the option identifier.
- [x] 2.3 Edit `_cron-claude-eval-substrate.ts`.
  - [x] 2.3.1 Add `FRAMING_HOOK_REL_PATH` and the exported `framingHookEntry(spawnCwd, nodeBin = resolveNodeBin())`.
  - [x] 2.3.2 Add the `buildCronEvalSettings(spawnCwd, opts = {})` strict `=== true` option. Add the key conditionally,
    never as `PostToolUse: undefined`.
  - [x] 2.3.3 Export `runFramingHookSelfTest({ spawnCwd, cronName, nodeBin, settings })`.
    - Trigger on `Object.hasOwn(settings?.hooks ?? {}, "PostToolUse")`, and return early when the key is absent.
    - Otherwise check `isDeepStrictEqual` (`node:util`) against `[framingHookEntry(...)]`.
    - Run the gh-read probe (exact deep-equal output) and the `ls` probe (empty after trim) through a framing-specific exec
      wrapper, since the existing `run` helper is hard-wired to containment.
    - On failure, throw `[<cron>] gh-output framing hook self-test FAILED: <registration mismatch | gh-read probe … | ls probe …>`.
  - [x] 2.3.4 Hoist `settings` in `runHookSelfTest` out of the `matcherOk` `try`: one parse, a widened type, and `matcherOk`
    unchanged. Then call `runFramingHookSelfTest` once after the containment probes. Add no new argument and leave
    `setupEphemeralWorkspace` unchanged.
- [x] 2.4 Add the back-pointer comments (no code change).
  - [x] 2.4.1 `untrusted-content.ts`: one line on `GH_READ_VERBS` and one on `UNTRUSTED_PREAMBLES.github`.
  - [x] 2.4.2 `cron-bash-allowlist-hook.mjs`: a `Consumers` note above `splitSegments` and `tokenize`.
- [x] 2.4b Containment code change (CTO D1): add `/cron-gh-output-framing-hook/` to `WRITE_PROTECTED_PATTERNS`. Comment that
  any new file the framing hook imports must join the list.
- [x] 2.5 Add the ADR-287 addendum `## Addendum 2026-11-12 (Ref #9601, #11076): cron gh output framing, dark`, items 1-7.
  Include:
  - the named gaps (failed-command event, compound commands, oversized output, subagents documented but not probed);
  - the known-extra framing, "on the test corpus";
  - the ordered enablement steps 1-7, with the D3 deploy-before-preamble-edit order and the D1 write-protection check;
  - the Phase 0 result.

## Phase 3: Testing

- [x] 3.1 New `apps/web-platform/test/server/inngest/cron-gh-output-framing-hook.test.ts` (app-local).
  - [x] 3.1.1 AC1 parity (`toStrictEqual`, `toBe`) plus the in-process census over `GH_FRAME_VERBS`.
  - [x] 3.1.2 AC2 rows in two groups (CTO D4), with one literal-count census over both.
    - Binary group: the brief-named shapes, malformed JSON, empty stdin, sibling missing and sibling throws at load. Each row
      asserts a minimal `env`, exit 0, `stderr === ""` and trim-empty or deep-equal output.
    - In-process group: the logic rows, the prototype keys (`gh toString x`, `gh constructor view`, `gh __proto__ view`) and
      the named unreachable gaps.
    - Add the import-has-no-side-effects row.
  - [x] 3.1.3 Adversarial size, in-process: the quote goes inside the final gh segment. No tight timing bound. Import
    `MAX_BASH_COMMAND_CHARS` from the hook `.mjs`.
  - [x] 3.1.4 One-way differential against `ghReadVerbOf` over the real `CRON_BASH_ALLOWLISTS`.
    - Include two known-extra rows, an admitted write row (`--label meta/machinery`) and the admitted chain
      `gh issue comment 1 --body x && gh issue view 1`.
    - Assert admitted and denied floors, at least one hosted `verb` row, each derived row admitted, and each known-extra row
      admitted and framed only on the cron side.
    - Add a triage header comment.
  - [x] 3.1.5 Allowlist-shape guard (Guard 6): the shape regex AND a closed canonical verb set (`GH_READ_VERBS` values plus
    create, edit, comment, close) over every cron key.
  - [x] 3.1.6 Exports pin, with a describe title that names the consumer.
- [x] 3.2 Additions to `cron-claude-eval-substrate.test.ts`.
  - [x] 3.2.1 AC3 hard-coded golden for every option value, with `Object.keys(hooks)` rows. The `true` row is a literal
    entry.
  - [x] 3.2.2 AC4 dark checks:
    - token scan over non-test app files: no `frameGhOutput` outside the substrate, and no `frameGhOutput: true` anywhere;
    - behavioural row: `setupEphemeralWorkspace`, run through the git-shim harness, writes a settings.json with no
      `PostToolUse` key (CTO D2).
  - [x] 3.2.3 Framing self-test cases (Guard 3). `makeSpawnCwd` copies the real framing hook, and every case uses the real
    containment hook. Cases:
    - no key plus a sentinel stub, with the sentinel in the test's own temp dir;
    - registered plus the real hook;
    - end to end, must pass (real hook) and must fail (silent stub);
    - `decision: "block"`;
    - silent;
    - frames `ls`;
    - hook absent;
    - one table-driven bad-shape test.

    Every throw asserts the `gh-output framing hook self-test FAILED` message plus the check name.
- [x] 3.2b `cron-bash-allowlist-hook.test.ts` (Guard 7):
  - `decide()` denies Write, Edit and the other gated file-mutating tools on the framing hook path, both repo-relative and
    absolute, with the reason `protected-path write:`;
  - `Read` is still allowed.
- [x] 3.3 Run the plan's Phase 5 vitest list, then app `tsc --noEmit`, ESLint and `c4-count-parity.test.sh`.
- [x] 3.4 Run the Guard Contract rows marked hand-run once each, and record RED/PASS in the PR body.
- [x] 3.5 Run the `discoverability_test` command from the repo root and confirm `UNTRUSTED` is printed (AC10).
- [x] 3.6 PR body:
  - `Ref #11076`, `Ref #9601`, and no closing keyword;
  - the `git grep -n frameGhOutput` output;
  - the golden-versus-`origin/main` comparison;
  - no claim that the control is covered or measured.
