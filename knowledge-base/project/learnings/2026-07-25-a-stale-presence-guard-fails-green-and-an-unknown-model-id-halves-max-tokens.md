---
module: apps/web-platform/{server/inngest/model-tiers.ts,scripts/sdk-bump-sandbox-gate.sh}, plugins/soleur/skills/model-launch-review
date: 2026-07-25
problem_type: logic_error
component: test_harness
symptoms:
  - "a cron containing `export const POC_MODEL = \"claude-opus-5\"` — a direct SSOT bypass — left the suite at 4 passed, because the guard's regex still watched the retired `claude-opus-4-8`"
  - "`--model claude-opus-5` produced max_tokens=32000 against the pinned CLI, byte-identical to a garbage model ID, vs 64000 for the previous model"
  - "`grep -roh` for model IDs in the CLI bundle returned hits=0 for EVERY id including known-positive controls"
  - "`audit-models.sh --detect` would print `model-drift: none (config model IDs current)` and exit 0 from a scan that errored"
  - "the `sdk-bump-verified:` ack was unreachable for any SDK bump — `git log base..HEAD` exits 128 on a shallow base and the failure was swallowed by `|| true`"
root_cause: guard_restates_the_value_it_guards_and_gates_conflate_absent_with_unreadable
severity: high
tags: [model-launch, presence-guard, vacuous-test, fails-green, ssot-drift, control-arm, measurement-validity, fail-open, fail-closed, shallow-fetch, cli-model-table, max-tokens, mutation-testing]
issue: 5100
pr: 6934
---

# A stale presence-guard fails GREEN, and an unknown model ID silently halves max_tokens

The Opus 5 model-launch review. Two P1s got past 67 green CI checks, a clean `tsc`, and ~4,800 passing tests. Both were found by multi-agent review; neither was findable by any gate the repo had.

The through-line: **four separate mechanisms each reported the reassuring answer when they could not actually see.**

---

## L1 — A presence-based guard whose watched literal goes stale fails GREEN, not RED

`apps/web-platform/test/server/inngest/model-tiers.test.ts` held the regex powering the "no cron bypasses the `AUDIT_MODEL` SSOT" walk:

```ts
const RAW_MODEL_LITERAL = /"claude-sonnet-5"|"claude-opus-4-8"/;
```

The Opus 5 swap updated three of the four `claude-opus-4-8` occurrences in that file and missed this one. The guard then scanned every cron for a literal that no longer exists anywhere in the tree.

**Proof (run, then reverted):**

```bash
# Add a direct SSOT bypass to any cron:
echo 'export const POC_MODEL = "claude-opus-5";' > server/inngest/functions/zz-poc-ssot-bypass.ts
npx vitest run test/server/inngest/model-tiers.test.ts     # → 4 passed  ← guard is blind

# Same line with the RETIRED id reddens correctly:
echo 'export const POC_MODEL = "claude-opus-4-8";' > server/inngest/functions/zz-poc.ts
npx vitest run test/server/inngest/model-tiers.test.ts     # → 1 failed
```

Caught for the ID that can no longer occur; missed for the one that is now the only one that can.

### Why three safety nets were all silent

This is the part worth remembering — it is not "someone forgot a line":

1. **`model-launch-review/SKILL.md` says the opposite of what happens.** Its step 3 reads *"config ID swaps red the coupled test fixtures; update them in the same PR so CI stays green."* That is true of **assertions** and false of **presence-guards** — a guard whose pattern goes stale turns **green**, so following the documented process cannot surface it.
2. **`audit-models.sh`'s `EXCLUDE_RE` excludes `/test/`**, so `--fix` never rewrites the guard.
3. **`--detect` never flags it** for the same reason.

Seven review agents converged on it independently; no automated gate could.

### Fix — derive, don't restate

```ts
// DERIVED from the SSOT constants, never restated. A hand-written copy of the
// model ID here is a second, unsynchronized pin.
const RAW_MODEL_LITERAL = new RegExp(`"${SONNET_MODEL}"|"${AUDIT_MODEL}"`);
```

Plus a **non-vacuity control**, because `expect(offenders).toEqual([])` is satisfied both by "the guard works" and by "the guard scans for something impossible":

```ts
it("RAW_MODEL_LITERAL matches a synthesized literal for both tiers", () => {
  expect(RAW_MODEL_LITERAL.test(`const m = "${AUDIT_MODEL}";`)).toBe(true);
  expect(RAW_MODEL_LITERAL.test(`const m = "${EXECUTION_MODEL}";`)).toBe(true);
  expect(RAW_MODEL_LITERAL.test(`const m = "claude-haiku-4-5-20251001";`)).toBe(false);
});
```

**Generalize:** any guard that *restates* a value it guards is a second unsynchronized pin on that value. Derive it from the source of truth, and pin its non-vacuity separately. When a PR changes a value, grep for guards that mention that value — an empty-offenders assertion tells you nothing about whether the pattern can still match.

---

## L2 — The pinned `claude-code` CLI carries a bundled per-model table; an unknown ID silently halves `max_tokens`

The CLI injects `thinking` and `output_config` itself, keyed off a **bundled** per-model table. A model ID absent from that table falls back to conservative defaults.

**Measured** against the real pinned binary via a mock `ANTHROPIC_BASE_URL` (CLI 2.1.197):

| `--model` | in CLI table | `max_tokens` |
|---|---|---|
| `claude-opus-4-8` | yes | 64000 |
| `claude-sonnet-5` | yes | 64000 |
| `claude-opus-5` | **no** | **32000** |
| `zzz-garbage-model` | no | 32000 |

Six production audit crons pass `--model` via argv against `--max-turns` budgets of 45–70. The swap alone would have halved their output budget, making them byte-for-byte indistinguishable from passing a garbage model ID — while every run still *succeeded*. Invisible to the model-ID sweep, to `tsc`, and to the full suite, because the argv is well-formed.

**Fix:** bump `@anthropic-ai/claude-code` (2.1.197 → 2.1.219) and the `Dockerfile` global; `model-launch-review` grew **item 2b** asserting each tier model appears in the pinned bundle.

Two corrections worth recording:

- **A hypothesis that was wrong.** I expected Opus 5's thinking-on-by-default to inflate token spend. It does not — Claude Code sets `thinking: {type:"adaptive"}` and `effort: "high"` **explicitly** on both models, so the API-side default never applies. The checklist's item 3 ("no `thinking`/`output_config` params in config today") was true of *config* and false of *runtime*.
- **Unnecessary scope.** `@anthropic-ai/claude-agent-sdk` was bumped alongside the CLI purely because the version numbers looked paired. It produced **141 `tsc` errors** across 10 test files and was reverted. The SDK builds the bwrap argv; the **CLI** carries the model table. Bump the one that owns the thing you are fixing.

---

## L3 — A measurement that returns the same result on every arm, including the control, is un-run

Checking whether a newer CLI knew the model:

```bash
grep -roh "$id" node_modules/@anthropic-ai/ | wc -l
# claude-opus-5    → 0
# claude-opus-4-8  → 0   ← known-positive control
# claude-sonnet-5  → 0   ← known-positive control
```

I nearly concluded "the new CLI doesn't know Opus 5." The real cause: `grep -r` skips the compiled `linux-x64` binary. With `-a` and a negative control:

```bash
grep -raoh "$id" node_modules/@anthropic-ai/ | wc -l
# claude-opus-5    → 152
# claude-opus-4-8  → 172
# claude-sonnet-5  → 116
# zzz-not-a-model  → 0     ← negative control
```

**Generalize:** every measurement needs a **known-positive** and a **known-negative** control. An all-arms-identical result is a broken instrument, not a finding — and it is the most dangerous failure because the baseline-looking answer reads exactly like a real one. This is the measurement-side twin of the existing mutation-testing rule that *a mutation that does not land reports a false result in both directions*.

---

## L4 — A gate that cannot distinguish "absent" from "could not look" reports the reassuring answer — twice in one session

Same root cause, opposite blast radius. Both were `|| true` swallowing a non-zero exit.

### (a) Fail-open — `audit-models.sh`

```bash
grep -rEl "$re" "$ROOT" ... 2>/dev/null | grep -vE "$EXCLUDE_RE" || true
```

`grep` exits **1** on no-match and **≥2** on error (unreadable dir, bad regex). `|| true` made them identical, so `--detect` would print `model-drift: none (config model IDs current)` and exit **0** from a scan that never ran — from a detector whose entire job is noticing drift.

Fixed by capturing `rc`, returning 2 on `rc >= 2`, and having `--detect` report `UNKNOWN` + exit 1. Note the second trap: `mapfile -t hits < <(collect_config_hits)` **discards** the function's exit code, so the capture had to go through a tempfile for the failure to be visible at all.

### (b) Fail-closed — `sdk-bump-sandbox-gate.sh`

```bash
ack_text="$(git log "${BASE_REF}..HEAD" --format=%B 2>/dev/null || true)"
```

`ci.yml` fetched main with `--depth=1`, and the `lockfile-sync` job had no `fetch-depth` at all (defaults to 1). With both sides shallow the range has no merge base:

```bash
git init -q origin-repo && …           # 3 main commits, branch with an ack commit
git clone -q --depth=1 --branch feat "file://$PWD/origin-repo" shallow
cd shallow && git fetch --no-tags --depth=1 origin main
git log origin/main..HEAD --format=%B
# fatal: ambiguous argument 'origin/main..HEAD': unknown revision  → rc=128
```

`ack_text` came back empty, so the `sdk-bump-verified:` acknowledgement was **unreachable for any SDK bump regardless of what the author wrote**. The gate was unpassable by design-accident.

Fixed with `fetch-depth: 0` on `lockfile-sync`, dropping `--depth=1` from all four main fetches, and routing both ack-scan call sites through a `read_branch_messages` helper that fails loudly and names the shallow-fetch cause.

**Generalize:** ask of every gate — *what does this print when it cannot look?* If the answer is the same as "all clear," the gate is decorative in exactly the case it exists for. (a) failed open and silently passed; (b) failed closed and blocked a legitimate ack. Both are the same bug.

---

## Session Errors

**A stale presence-guard shipped in the swap that created it** — Recovery: seven review agents converged; fixed by deriving the regex from the SSOT constants + a non-vacuity control. Prevention: when a PR changes a value, grep for guards that restate it; an empty-offenders assertion never proves the pattern can still match.

**`grep -r` returned 0 hits on every arm including known-positive controls** — Recovery: re-ran with `grep -a` plus a garbage-string negative control. Prevention: never accept a measurement without a positive AND negative control; an all-arms-identical result is an un-run instrument.

**`git checkout -- <file>` wiped an uncommitted sibling fix during mutation testing** — Recovery: re-applied the lost edit from context. Prevention: **this exact trap is already documented in `review/SKILL.md` and was hit anyway.** Prefer *adding* a temp file over mutating a tracked one (cleanup is then `rm`), or mutate a sandbox copy; if you must mutate in place, back up to a session-unique `mktemp`, echo the path, and restore in a **separate** Bash call.

**Bumped `@anthropic-ai/claude-agent-sdk` on a guess, producing 141 `tsc` errors** — Recovery: reverted; only the CLI was required. Prevention: bump the package that owns the mechanism you are fixing, not the one whose version number looks paired with it.

**Two `mktemp` sites added without owning `trap`s** — Recovery: CI's `lint-trap-tempfile-ownership` caught both; added single owning traps (ADR-129). Prevention: allocate a tempfile and write its `trap … EXIT` in the same edit.

**A PreToolUse guard blocked an entire Bash invocation pre-execution, so an earlier heredoc in the same command never wrote its file** — Recovery: rewrote the file with the Write tool. Prevention: when one command both writes a file and runs a guarded operation, write the file with the Write tool — a blocked invocation runs *none* of it, and the failure surfaces later as a confusing "no such file".

**`bun test <path>` on web-platform matched no files** — Recovery: switched to `vitest`. Prevention: `bunfig.toml` sets `pathIgnorePatterns = ["**"]` under `[test]` (#1469); web-platform runs vitest. The "filters did not match any test files" message reads like a path typo — check the package's `test` script first.

**Long `vitest`/`tsc` runs were backgrounded mid-run** — Recovery: re-ran with an explicit `timeout`. Prevention: the Bash tool defaults to 120s; pass a longer `timeout` for full-suite runs.

**`worktree-manager.sh create` blocked on an interactive prompt** — Recovery: `yes | bash …`. Prevention: the Bash tool is non-interactive; pipe confirmations.

**`git diff origin/main...HEAD` reported "no merge base" locally** — Recovery: `git fetch --no-tags origin main --depth=200`. Prevention: same root cause as L4(b) — a shallow base makes any `..`/`...` range unusable.

**One-off, noted without action:** a GitHub "Partial System Outage" blocked PR creation for ~8 minutes (recovered by retry); a CI log blob had rotated (`BlobNotFound`) when fetching an older job's log; a persisted `cd` made a later relative `cd` fail; `rm -rf` was blocked by the protected-location guard (used `mktemp -d` instead); `gh issue create` was blocked without `--milestone`. The last two are guards working as designed.

---

## Prevention

- **Derive guards from their source of truth.** A guard that restates a value is a second pin that drifts silently and fails green.
- **Pin non-vacuity.** For any "no offenders" assertion, add a control proving the detector still matches a synthesized positive.
- **Control every measurement.** Positive + negative arms; treat an all-arms-identical result as a broken instrument.
- **Never `|| true` a command whose failure is the signal.** Capture the exit code and distinguish "nothing found" from "could not look."
- **At each model launch, verify the ID is in the pinned CLI's bundled table** (`model-launch-review` item 2b) — an unknown ID degrades silently rather than erroring.

## Related

- [2026-02-22-model-id-update-patterns.md](./2026-02-22-model-id-update-patterns.md) — the original model-ID sweep patterns this launch extends
- [2026-04-18-action-pin-sync-with-model-bump.md](./2026-04-18-action-pin-sync-with-model-bump.md) — action-pin sync; its `git/commits/<SHA>` command was corrected here (these pins are annotated **tag** objects, so that form 404s)
- [2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md](./2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md) — the mutation-side twin of L3
- [2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md](./2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md) — same family as L4: a check that cannot succeed reads like one that passes

Follow-ups filed: #6942 (dated sonnet intro-pricing expiry, 2026-09-01), #6945 (BYOK cap sums cents×tokens against a cents budget; sub-cent turns quantize to 0).
