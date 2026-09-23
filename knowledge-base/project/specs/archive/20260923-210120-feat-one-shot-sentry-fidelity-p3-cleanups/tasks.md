# Tasks — Sentry alert live-fidelity P3 cleanups

Plan: `knowledge-base/project/plans/2026-09-22-fix-sentry-alert-fidelity-p3-cleanups-plan.md`
Branch: `feat-one-shot-sentry-fidelity-p3-cleanups` · Draft PR: #8576 · Does NOT close #7985.

## 0. Setup

- [x] 0.1 Baseline: `bash tests/scripts/test-sentry-alert-live-fidelity.sh` → `59 passed, 0 failed`.
- [x] 0.2 Baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` → 25 passed.

## 1. RED — tests first (`tests/scripts/test-sentry-alert-live-fidelity.sh`)

- [x] 1.1 Add `CAPTURE_N`, `EXCL_DEF`, `EXCL_CAPTURE_N` derivations next to `N`, plus the floor `CAPTURE_N > N > 0`, `EXCL_CAPTURE_N > 0`, `N == CAPTURE_N - EXCL_CAPTURE_N` (exit 1 otherwise). (b, AC7)
- [x] 1.2 F13 (`t_live_api_shape`): replace `jq -e 'length == 31'` with `--argjson n "$CAPTURE_N" 'length == $n'`. (b)
- [x] 1.3 F12 (`t_survivors_out_of_scope`): replace `grep -q 'comparing 28 declared rule'` with a `grep -qF` on the derived `comparing ${N} declared rule(s) against ${N} live in-scope rule(s)`; update the label to name `${N}`, `${CAPTURE_N}`, `${EXCL_CAPTURE_N}`. (b)
- [x] 1.4 Reuse `CAPTURE_N` in the `FROZEN_N` derivation (~line 713); add `DEFAULTS_N=$(( FROZEN_N - FROZEN_TF_N ))`. (b, AC1)
- [x] 1.5 Add `_gained_live()` helper: capture with `{"type":"seer_activity_trigger","comparison":["pr_ready_for_review"]}` appended to the named rule's `triggers.conditions`; assert the edit landed (`jq -e`). (`cq-test-fixtures-synthesized-only`)
- [x] 1.6 Row **G4-25**: one managed rule gained → rc 1, `MANAGED RULE GAINED EXCLUDED TRIGGER: 'byok-art-33-breach'`, NOT `DELETED or RENAMED: 'byok-art-33-breach'`, NOT `UNMANAGED-FROZEN: 'byok-art-33-breach'`, count line contains `(${DEFAULTS_N} other excluded-type`. (AC1)
- [x] 1.7 Row **G4-26**: two managed rules gained → both names reported. (AC2, matrix row 3)
- [x] 1.8 Row **G4-27**: healthy managed rule + a same-name excluded-type COPY (different id) → assert the anchor `UNMANAGED-FROZEN: 'byok-art-33-breach'` and the ABSENCE of the GAINED marker. Do NOT assert the message tail: the `$KNOWN` narrowing moves this case from the "under a DIFFERENT id" arm to the generic arm (plan E3). (AC3, matrix row 4)
- [x] 1.9 Row **G4-28**: reference with `byok-art-33-breach` removed + live gained → rc 1 and `UNMANAGED-FROZEN: 'byok-art-33-breach'`. Baseline today is rc 0 / PASS (plan E2), so this row is RED before task 2.3. (AC4, matrix row 5)
- [x] 1.10 Register the 4 rows in the runner list; `EXPECTED_TESTS=63`. (Superseded 2026-09-23: the review panel added G4-29…G4-32, so the shipped value is `EXPECTED_TESTS=67`.)
- [x] 1.11 Run the suite: G4-25/26/28 RED, G4-27 green, all 59 pre-existing rows green. (AC12)

## 2. GREEN — probe (`scripts/sentry-alert-live-fidelity.sh`)

- [x] 2.1 Per-rule loop: before emitting `DELETED or RENAMED`, `continue` when a raw `live_json` workflow carries that name (`jq -e --arg n "$name" 'any(.[]; .name == $n)'`).
- [x] 2.2 Frozen-pin jq: add `--argjson refnames "$(jq -c 'keys' <<<"$ref_proj")"`; define `$INSCOPE`; add the GAINED arm to the `$O` chain, ordered empty-name → DUPLICATE → GAINED → KNOWN → known-name-other-id → else.
- [x] 2.3 Narrow `$KNOWN`'s capture half to excluded-type, non-frozen capture entries. (AC4)
- [x] 2.4 `COUNT`: third field counts KNOWN-and-not-GAINED members. (AC1, matrix row 7)
- [x] 2.5 Update the FROZEN-RULE PIN header comment (GAINED bullet) and the final stderr summary line. (AC6)
- [x] 2.6 `tests/scripts/lib/sentry-alert-projection.jq`: comment only, above `def in_scope`. Do NOT touch the `def excluded:` line (the probe greps `^def excluded: \[.*\];[[:space:]]*$`). (AC5, P3)
- [x] 2.7 `.github/workflows/scheduled-sentry-alert-drift.yml`: one new `printf` bullet in "How to read them". (AC6)
- [x] 2.8 Suite → `63 passed, 0 failed` at this point; `67 passed, 0 failed` on the shipped head after the review panel's four rows. (AC10)

## 3. (c) Generator comment

- [x] 3.1 Add the frozen-to-2026-09-04 comment above `EXCLUDE` in `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-generate-alert-blocks.py`; leave `EXCLUDE` unchanged.
- [x] 3.2 `python3 -m py_compile` on that file. (AC8)

## 4. (d) Widen `comparison`

- [x] 4.1 In `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`, add `FrequencyComparison` / `TagComparison` / `Comparison` and the two type guards; type both `conditions` arrays with `Comparison`.
- [x] 4.2 Narrow at the tag-filter site (`expect(...every(isTag)).toBe(true)` before `.map`) and at the threshold site (`expect(isFrequency(...)).toBe(true)` before destructuring). No `as` cast at a use site.
- [x] 4.3 `vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` → 25 passed; `tsc --noEmit` clean for that file. (AC9)

## 5. Verify & ship

- [x] 5.1 `grep -nE 'length == 31|comparing 28' tests/scripts/test-sentry-alert-live-fidelity.sh` → no output. (AC7)
- [x] 5.2 `git diff --name-only origin/main | grep -c '\.tf$'` → 0; `plan_pr` no-op expected. (AC11)
- [x] 5.3 `git diff origin/main -- tests/scripts/lib/sentry-alert-projection.jq` → only added `#` comment lines. (AC5)
- [x] 5.4 Run the mutation matrix spot checks (rows 1, 3, 4, 5) by temporary edit + suite run; revert each.
- [~] 5.5 (in flight — review complete, ship in progress, merge pending operator approval) `soleur:review` → `soleur:ship`. Admin-merge only with operator approval, after required checks are green on the pinned head (CI queue is 100–200 runs deep).
