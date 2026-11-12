# Tasks: cron gh-output framing hook (dark, opt-in)

Plan: `knowledge-base/project/plans/2026-11-12-feat-cron-gh-output-framing-hook-plan.md`. Ref #11076, Ref #9601 (never
Closes). Draft PR #12705; open no other PR. No deploy, flag, Doppler, Terraform, migration or prd dispatch.

## Phase 1: Setup and delivery probe (Phase 0 of the plan; no product code)

- [ ] 1.1 In a scratch directory outside the repo, build a `.claude/settings.json` shaped like `buildCronEvalSettings` output:
  the `*` PreToolUse containment hook with a `cron-allow.txt` admitting `echo`, plus the PostToolUse entry under test.
- [ ] 1.2 Run 1 at `npx -y @anthropic-ai/claude-code@2.1.321`: a nonce stub hook with `--strict-mcp-config`,
  `--output-format json`, `--append-system-prompt <UNTRUSTED_PREAMBLES.github>`, `--print`, `--setting-sources project`,
  `--model haiku`. The prompt runs `echo hello`. Capture the stub's stdin payload keys (required evidence).
- [ ] 1.3 Run 2: the same setup with no PostToolUse entry (negative control, expect `NONE`).
- [ ] 1.4 Write `probe-delivery.md` with the CLI version, flags, nonce, both results and the payload keys.
- [ ] 1.5 Decision branch: if there is no nonce at 2.1.321, stop and re-scope through a new CTO consult (KB Read hook dissent).
  If the probe cannot run, proceed and record "delivery and effect unverified" with the reason.

## Phase 2: Core Implementation

- [ ] 2.1 Write the Phase 3 tests first and confirm each starts RED (see 3.x).
- [ ] 2.2 Create `apps/web-platform/server/inngest/cron-gh-output-framing-hook.mjs`.
  - [ ] 2.2.1 Export the `GH_READ_VERBS` copy and `GITHUB_UNTRUSTED_PREAMBLE`.
  - [ ] 2.2.2 `isGhReadTokens`: `tokens[0] === "gh"`, noun in the table, verb in the noun's list, `api: []` matches on the
    noun (CTO C2).
  - [ ] 2.2.3 `frameDecision(raw, { splitSegments, tokenize })`: never throws, never reads `tool_response`, emits only
    `hookSpecificOutput.{hookEventName, additionalContext}`.
  - [ ] 2.2.4 `main()`: dynamic import of the sibling, a single stdout write, `exit(0)`, and a file-name guard.
  - [ ] 2.2.5 Header comment covering annotate-only, always exit 0, dark, the parity pin and the inverted posture. It must
    not spell the option identifier.
- [ ] 2.3 Edit `_cron-claude-eval-substrate.ts`.
  - [ ] 2.3.1 Add `FRAMING_HOOK_REL_PATH` and the exported `framingHookEntry(spawnCwd, nodeBin = resolveNodeBin())`.
  - [ ] 2.3.2 Add the `buildCronEvalSettings(spawnCwd, opts = {})` strict `=== true` option. Add the key conditionally,
    never as `PostToolUse: undefined`.
  - [ ] 2.3.3 Export `runFramingHookSelfTest({ spawnCwd, cronName, nodeBin, settings })`.
    - Return early when no `PostToolUse` key is present.
    - Otherwise check `isDeepStrictEqual` on the registration, run the gh-read probe (exact deep-equal output), and run the
      `ls` probe (empty output). Throw on any failure.
  - [ ] 2.3.4 Call it once from `runHookSelfTest` after the containment probes. Add no new argument and leave
    `setupEphemeralWorkspace` unchanged.
- [ ] 2.4 Add the back-pointer comments (no code change).
  - [ ] 2.4.1 `untrusted-content.ts`: one line on `GH_READ_VERBS` and one on `UNTRUSTED_PREAMBLES.github`.
  - [ ] 2.4.2 `cron-bash-allowlist-hook.mjs`: a `Consumers` note above `splitSegments` and `tokenize`.
- [ ] 2.5 Add the ADR-287 addendum `## Addendum 2026-11-12 (Ref #9601, #11076): cron gh output framing, dark`, items 1-7.
  Include the named gaps, the known-extra framing, the ordered enablement steps, and the Phase 0 result.

## Phase 3: Testing

- [ ] 3.1 New `apps/web-platform/test/server/inngest/cron-gh-output-framing-hook.test.ts` (app-local).
  - [ ] 3.1.1 AC1 parity (`toStrictEqual`, `toBe`) plus the in-process census over `GH_FRAME_VERBS`.
  - [ ] 3.1.2 AC2 binary rows: frame, nothing, named unreachable gaps, sibling missing. Use a minimal explicit `env` and a
    literal declared row count.
  - [ ] 3.1.3 Adversarial size, in-process: the quote goes inside the final gh segment. No tight timing bound.
  - [ ] 3.1.4 One-way differential against `ghReadVerbOf` over the real `CRON_BASH_ALLOWLISTS`.
    - Include two known-extra rows and an admitted write row.
    - Assert admitted and denied floors.
    - Add a triage header comment.
  - [ ] 3.1.5 Allowlist-shape guard (Guard 6).
  - [ ] 3.1.6 Exports pin, with a describe title that names the consumer.
- [ ] 3.2 Additions to `cron-claude-eval-substrate.test.ts`.
  - [ ] 3.2.1 AC3 hard-coded golden for every option value, with `Object.keys(hooks)` rows. The `true` row is a literal
    entry.
  - [ ] 3.2.2 AC4 token scan over non-test app files:
    - no `frameGhOutput` outside the substrate;
    - no `frameGhOutput: true` anywhere;
    - the substrate occurrence count equals a literal.
  - [ ] 3.2.3 Framing self-test cases (Guard 3). `makeSpawnCwd` copies the real framing hook, and every case uses the real
    containment hook. Cases:
    - no key plus a sentinel stub;
    - registered plus the real hook;
    - an end-to-end throw;
    - `decision: "block"`;
    - silent;
    - frames `ls`;
    - hook absent;
    - one table-driven bad-shape test.
- [ ] 3.3 Run the plan's Phase 5 vitest list, then app `tsc --noEmit`, ESLint and `c4-count-parity.test.sh`.
- [ ] 3.4 Run the Guard Contract rows marked hand-run once each, and record RED/PASS in the PR body.
- [ ] 3.5 Run the `discoverability_test` command from the repo root and confirm `UNTRUSTED` is printed (AC10).
- [ ] 3.6 PR body:
  - `Ref #11076`, `Ref #9601`, and no closing keyword;
  - the `git grep -n frameGhOutput` output;
  - the golden-versus-`origin/main` comparison;
  - no claim that the control is covered or measured.
