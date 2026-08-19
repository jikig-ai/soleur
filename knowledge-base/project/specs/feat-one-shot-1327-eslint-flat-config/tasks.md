# Tasks — #1327 migrate off `next lint` to the ESLint CLI

Derived from `knowledge-base/project/plans/2026-08-19-chore-eslint-flat-config-migration-plan.md`.

Target: `apps/web-platform`. Closes #1327; unblocks #7594 (do NOT upgrade Next here).

---

## Phase 0 — Preconditions (no product code)

- [x] 0.1 Re-derive the baseline finding count WITH `languageOptions.globals` set for node +
      browser. The probe's 98 `no-undef` are suspected to be a globals artifact. The plan's ~195
      is an input, not an AC value.
- [x] 0.2 Confirm no new dependency is needed: `@typescript-eslint/parser`, `-eslint-plugin`,
      `eslint-plugin-react`, `-react-hooks`, `-import`, `-jsx-a11y`, `@next/eslint-plugin-next`
      all resolvable from `node_modules`.

## Phase 1 — Repair the dependency tree (BLOCKS every later phase)

- [x] 1.1 Remove the blanket `"brace-expansion": "^5.0.9"` from `apps/web-platform/package.json`
      `overrides`. If a line then resolves below its patched floor, use a SCOPED override
      (the `gray-matter` → `js-yaml` shape the repo root already uses) — never a blanket one.
- [x] 1.2 Regenerate with `npx --yes npm@11 install`; validate `npm ci --ignore-scripts`.
- [x] 1.3 Assert per-line patched floors (AC7): every resolved `brace-expansion` ≥ its major
      line's floor. Per line, never in aggregate. **The plan's floors were stale** — see the
      corrected AC7; the measured set is 1.1.18 / 2.1.4 / (no patched 3.x) / (no patched 4.x)
      / 5.0.9, now encoded and mutation-proven in Guard 3.
- [x] 1.4 Assert `rimraf`'s `minimatch@9` gets a `brace-expansion@2.x` (AC8) — proves the fix is
      not scoped only to the ESLint stack.
- [x] 1.5 Confirm a brace glob no longer crashes ESLint (AC6).

## Phase 2 — Guard suite FIRST (RED before GREEN)

- [x] 2.1 RED: write `apps/web-platform/test/eslint-config.test.ts` covering Guard 1 (script is
      non-interactive and terminates) and Guard 2 (finding count pinned + anti-vacuity floor).
      Run it; it must fail.
- [x] 2.2 Include the anti-vacuity minimum-file-count floor so a run that scanned nothing cannot
      report "0 findings, all good" (ADR-193 floor contract).

## Phase 3 — The flat config (GREEN)

- [x] 3.1 Author `apps/web-platform/eslint.config.mjs`: `@eslint/js` recommended;
      `@typescript-eslint/parser` for `.ts`/`.tsx`; `@next/eslint-plugin-next`
      `flatConfig.coreWebVitals`; node + browser globals; ignores
      (node_modules, .next, dist, supabase, public, __goldens__).
- [x] 3.2 Comment WHY `eslint-config-next` stays a dependency (Decision 2) so it is not
      "cleaned up" as unused — that is exactly what the issue's step 4 proposed.
- [x] 3.3 Make the guard suite pass.

## Phase 4 — Rule dispositions

- [x] 4.1 Drive the finding set to a deterministic state. Every rule ships `error` / `warn` /
      `off` WITH a stated reason. No blanket disable to reach zero.
- [x] 4.2 ~~Remove the 13 pre-existing unused `eslint-disable` directives.~~ **Not performed —
      instruction corrected, see the plan's amended Phase 3.** Measured 31, of which 29 name
      rules this config does not enable; removing those would discard suppressions authored for
      rules the ratchet has yet to turn on. All 31 stay, pinned by the baseline.
- [x] 4.3 Commit the baseline count the guard compares against.

## Phase 5 — Script + CI

- [x] 5.1 `"lint": "eslint ."` in `apps/web-platform/package.json`.
- [x] 5.2 Add a NON-BLOCKING lint job to `.github/workflows/ci.yml` on PRs touching
      `apps/web-platform`.
- [x] 5.3 Verify it is ABSENT from `scripts/required-checks.txt` and the required-status-check
      ruleset JSON (AC10). Never add a required check silently.

## Phase 6 — Propagation sweep (grep the OLD claim, not the new one)

- [x] 6.1 Correct IN PLACE the `plugins/soleur/skills/work/SKILL.md` bullet asserting there is no
      eslint config / lint is non-functional / CI does not run lint.
- [x] 6.2 APPEND `## Addendum — 2026-08-19 (#1327)` to
      `knowledge-base/project/learnings/2026-06-05-web-platform-lint-gate-is-non-functional-tsc-vitest-are-authoritative.md`.
      Do NOT rewrite its body — verify it stays byte-identical to `origin/main` (AC12).
- [x] 6.3 Leave the ~18 historical learnings/plans mentioning `next lint` alone (point-in-time
      records).

## Phase 7 — Verification

- [ ] 7.1 Work through all 15 Acceptance Criteria.
- [x] 7.2 Mutation-prove both Guard mutation matrices; run the UNMUTATED control first (a red
      baseline voids every row). Label any surviving mutant "fixture gap" or "equivalent" —
      never leave it unlabelled.
- [ ] 7.3 `TEST_GROUP=webplat bash scripts/test-all.sh`; also `bun`/`scripts` shards since the
      diff touches `plugins/` and `.github/`. Name which shards ran when reporting green.
- [x] 7.4 `bash scripts/lint-dual-lockfile.sh` passes; lockfile-sync regeneration byte-identical.
- [ ] 7.5 PR body: `Closes #1327`; reference #7594 as unblocked but do NOT close it.

---

## Do NOT do

- Do **not** run the `next-lint-to-eslint-cli` codemod — there is nothing to convert.
- Do **not** remove `eslint-config-next` — it supplies the parser and all five plugins.
- Do **not** add the lint job to the required-status-check ruleset in this PR.
- Do **not** blanket-disable a rule class to reach a zero finding count.
- Do **not** reintroduce a blanket `brace-expansion` override; scoped only, if needed at all.
- Do **not** bundle the Next 15→16 upgrade. #7594 stays open.
