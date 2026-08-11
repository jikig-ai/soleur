---
title: "Tasks — /soleur:sync per-site producer guards (#7474)"
date: 2026-08-11
branch: feat-one-shot-7474-sync-producer-freshness-probe
issue: 7474
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-11-fix-sync-producer-freshness-probe-plan.md
---

# Tasks

Derived from the finalized (post-review) plan. Phase order is load-bearing: the tests land
before the `sync.md` edit (`cq-write-failing-tests-before`).

**Do not** edit the Phase 0 identity-gate fence in `plugins/soleur/commands/sync.md`. The
redesign deliberately leaves it untouched — no `exit 0`, no STOP-prose retarget.

## Phase 1 — Preconditions (verify, never assume)

- [ ] **1.1** Re-derive the producer inventory at HEAD:
      `grep -nE '(bash|bun) "\$\{CLAUDE_PLUGIN_ROOT\}/' plugins/soleur/commands/sync.md`.
      Expect 3 distinct paths across 6 sites. A fourth changes the work-list below.
- [ ] **1.2** Read **both** hand-ratcheted anti-vacuity floors and record the values:
  - [ ] **1.2.1** `apps/web-platform/test/plugin-root-anchoring.test.ts` → `expect(assertions).toBe(8)`.
  - [ ] **1.2.2** `tests/commands/test-sync-producer-reachability.sh` → `EXPECTED_CASES=9`
        (enforced twice — the anti-vacuity block and the final exit expression).
- [ ] **1.3** Confirm both suites green before editing:
  - [ ] **1.3.1** `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
        (**vitest, never `bun test`** — `bunfig.toml` sets `pathIgnorePatterns = ["**"]`).
  - [ ] **1.3.2** `bash tests/commands/test-sync-producer-reachability.sh`

## Phase 2 — RED (tests first)

- [ ] **2.1** Add the marker-emission case to `tests/commands/test-sync-producer-reachability.sh`.
  - [ ] **2.1.1** Synthesize an identity-valid root missing one producer. **Precondition:** the
        root must still contain an (empty) `scripts/` directory, or the identity gate refuses
        first and the case asserts nothing.
  - [ ] **2.1.2** Assert the exact marker, including `affects=` and
        `reason=absent-from-verified-root`.
  - [ ] **2.1.3** Assert the guarded producer did **not** execute.
  - [ ] **2.1.4** Leave T0i's `fi`-counting extractor alone — its truncation is load-bearing for
        `good_rc`.
- [ ] **2.2** Bump `EXPECTED_CASES` by exactly the number of cases added.
- [ ] **2.3** Add the **P6** parity assertion to `apps/web-platform/test/plugin-root-anchoring.test.ts`.
  - [ ] **2.3.1** **Insert the `it()` block ABOVE the P5 block.** `assertions` increments inside
        each callback in registration order; appending after P5 makes P5 read the pre-increment
        value and fail while P6 passes.
  - [ ] **2.3.2** Scope the expected set to `sync.md`'s entry of `parsed` only — `parse()` walks
        all of `plugins/soleur/commands/`, and `go.md` contributes two anchored `.sh` operands.
  - [ ] **2.3.3** Restrict to operands invoked by `bash`/`bun` in command position, not to any
        `.ts`/`.sh` suffix (`source` is in `RUNNERS`).
  - [ ] **2.3.4** Assert every guarded invocation carries an `affects=` value from the closed set
        `{c4, coverage, domain-model}`.
  - [ ] **2.3.5** Non-vacuity: assert both derived sets are non-empty (`>= 3`) before comparing.
  - [ ] **2.3.6** Remedy-bearing failure strings, matching the file's `expect(violations).toEqual([])`
        idiom (e.g. `PRODUCER NOT GUARDED: scripts/x.ts — wrap its invocation in the [ -f ] guard`).
  - [ ] **2.3.7** Scope the parser to fence bodies — `sync.md`'s Phase 0 prose contains ADR-179's
        worked `"${CLAUDE_PLUGIN_ROOT}/scripts/foo.ts"` examples.
  - [ ] **2.3.8** Do **not** widen `RUNNER_RE` or `DIRECT_EXEC_RE`.
- [ ] **2.4** Bump `expect(assertions).toBe(8)` → `toBe(9)`.
- [ ] **2.5** Confirm both suites RED for the right reason.

## Phase 3 — GREEN (the guard)

- [ ] **3.1** Wrap each of the 6 producer invocations in `plugins/soleur/commands/sync.md`:
      `[ -f "${CLAUDE_PLUGIN_ROOT}/<p>" ] && <runner> "${CLAUDE_PLUGIN_ROOT}/<p>" [args] || echo "SOLEUR_SYNC_PRODUCER_MISSING producer=<p> affects=<area> reason=absent-from-verified-root"`
  - [ ] **3.1.1** `scripts/generate-c4-from-components.ts` → `affects=c4`
  - [ ] **3.1.2** `scripts/write-kb-coverage.ts` (both plain and `--degraded` forms) → `affects=coverage`
  - [ ] **3.1.3** `scripts/domain-model-drift.sh` (`drift`, `write-row`, `init`) → `affects=domain-model`
  - [ ] **3.1.4** Keep every operand **bare-anchored and quoted** — no `:-`, no `:?` (P1b is a
        whole-file check).
- [ ] **3.2** Add the verbatim operator message (observation → remedy → fallback → what still
      worked). No internal term "producers"; no unproven "predates" as the sole instruction.
- [ ] **3.3** Add the headless variant — `auto-sync-trigger.ts` users have no plugin installed,
      so "reinstall the plugin" is misdirecting there.
- [ ] **3.4** Add the one-sentence `--degraded` reuse note with its two limits (unavailable when
      `write-kb-coverage.ts` is itself missing, and for standalone invocations; a prior
      `kb-coverage.md` persists and still satisfies the existing `SOLEUR_KB_SYNC_PRODUCERS` grep).
- [ ] **3.5** Add a pointer comment above the first guarded invocation naming both test suites.
- [ ] **3.6** Keep `domain-model`'s two contracts distinct (standalone terminal vs under `all`).
- [ ] **3.7** Both suites green.

## Phase 4 — ADR

- [ ] **4.1** Add one line to ADR-179's `## Consequences` marker enumeration for
      `SOLEUR_SYNC_PRODUCER_MISSING`.
- [ ] **4.2** Record that decision 5 (fail-closed in isolation) binds the freshness axis, and is
      why the guard is per-site.

## Phase 5 — Tracking and exit gate

- [ ] **5.1** Append the deferred SHA-divergence mechanism to #7452 with re-evaluation criteria.
- [ ] **5.2** File the update-path UX defect ("updating the marketplace does not update an
      installed plugin, and nothing says so") in the **Phase 4: Validate + Scale** milestone.
- [ ] **5.3** Assign #7474 to the Phase 4 milestone (currently unset).
- [ ] **5.4** `bash scripts/test-all.sh`.
- [ ] **5.5** PR body uses `Closes #7474`, links 5.1-5.3, and renders
      `decision-challenges.md` (3 User-Challenges, 2 Taste items).
