# Tasks — feat-one-shot-9999-ghs-token-sentinels

Plan: `knowledge-base/project/plans/2026-10-11-fix-ghs-token-format-sentinels-plan.md`
Issue: #9999 — Update legacy `ghs_` token-format sentinels for GitHub's rotated installation-token shape

## Phase 1 — Failing tests first

- [x] 1.1 Create `plugins/soleur/skills/skill-security-scan/test/redact-pii-ghs-shape.test.sh`
  - 1.1.1 awk-extract the `redact_pii` sed program from `run-scan.sh` (between `^redact_pii() {` and the closing single-quote-only line)
  - 1.1.2 Synthesize a ~390-char `ghs_` fixture: split-assembled prefix (`"ghs"_"…"` or equivalent), tail carrying every canonical byte `.` `_` `~` `+` `/` `=` `-`; assert `wc -c` ≥ 380 after prefix AND self-check the fixture is out-of-class for the legacy `[A-Za-z0-9]` alphabet
  - 1.1.3 Rows: new-shape masked whole (`<github-server>` present, zero tail bytes) / legacy 40-char still masks / extraction-dispatch anti-vacuity (empty program → RED)
  - 1.1.4 `mktemp` under `TMPDIR` with an owning `trap` placed before any `source` of helpers; print `redact-pii-ghs-shape: ok` on pass
- [x] 1.2 Extend `apps/web-platform/test/git-auth.test.ts`
  - 1.2.1 Add ~390-char canonical-alphabet fixture + `ghs_<appid>_<jwt>`-shaped fixture to the `test.each` accepts table
  - 1.2.2 Mock `../server/logger` `createChildLogger` → `{ warn: vi.fn(), info: vi.fn(), error: vi.fn() }`; assert format warn NOT emitted for issued shapes, IS emitted for `not-a-ghs-token`
  - 1.2.3 Retire `"a".repeat(30)` from the accepts table (warn-not-throw masks the semantic drift)
- [x] 1.3 Extend `apps/web-platform/lib/safety/redaction-allowlist.test.ts` — new-shape `ghs_` fixture (split-assembled) → `[redacted-key]` with no tail residue
- [x] 1.4 Extend `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` — `bad-ghs-literal.ts` fixture in the drift-trip loop
- [x] 1.5 Add stale-`ghs_`-class census rows to `scripts/lint-shell-trace-credential-refusal.test.sh` (Guard 3; two arms — `ghs_<class>` and `gh*(…)_<class>` family alternation; `:!knowledge-base` exclusion + fixture/doc allowlist) — RED on current tree until Phase 2 lands

## Phase 2 — Site edits (single sweep, canonical class `[A-Za-z0-9._~+/=-]`)

> Scope extension recorded at work time: the Guard-3 sweep enumerated additional
> same-class sites the plan's static list missed — all folded in (write-boundary
> sweep rule): `server/cc-dispatcher.ts` + `server/debug-probes.ts` (redaction
> fallthrough/mirror probes), `server/repo-resolver-divergence.ts` (`GH_TOKEN_RE`),
> `scripts/live-verify/redact.ts`, `operator-digest/scripts/digest-scrub.sh`,
> `incident/scripts/redact-engine.py` (the canonical Python engine; `*.py` added to
> the sweep pathspec), `.github/workflows/main-health-monitor.yml` + the paired
> `infra/cloud-init-git-data.yml` / `infra/soleur-host-bootstrap.sh` sed recipes
> (bracketed-prefix `gh[pousr]_` form — arm C), the `PII_REGEX` parity pair
> `scripts/compound-promote.sh` + `server/inngest/functions/cron-compound-promote.ts`
> (`gh[psr]_` form, both copies edited byte-identically per the parity test), and a
> stale doc comment in `test/server/inngest/cron-shared.test.ts`. Documented-narrower
> dispositions (allowlist, not widened): `incident/test/fixtures/legacy-bash-scanner.sh`
> (fixture models a legacy scanner), `deepen-plan/SKILL.md` + `plan/references/
> plan-sharp-edges.md` (docs cite the vendor's current unrotated prefix formats /
> GitHub's own push-protection regex), non-`ghs_` arms in `boundary.test.sh` +
> `work/SKILL.md` drift pins, and the `git-auth.ts` comment's verbatim vendor regex.


- [x] 2.1 `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` — `redact_pii` GitHub family (`ghp_`/`gho_`/`ghs_`/`ghr_`) → `[A-Za-z0-9._~+/=-]{20,}`
- [x] 2.2 `scripts/learning-retrieval-bench.sh` + `plugins/soleur/skills/kb-search/SKILL.md` — GitHub alternation (`ghp_`/`gho_`/`ghs_` `{36}`, `github_pat_` `{40,}`) → canonical class, byte-identical literals in both files, same commit
- [x] 2.3 `plugins/soleur/skills/work/SKILL.md` — `ghs_[A-Za-z0-9_]{20,}` → `ghs_[A-Za-z0-9._~+/=-]{20,}`; SAME edit trims ≥7 bytes of prose (file is at its 362000-byte ceiling — net delta must be ≤ 0 vs merge base; trim a redundant word, never a condition)
- [x] 2.4 `apps/web-platform/server/git-auth.ts` — `TOKEN_FORMAT_RE` → `/^ghs_[A-Za-z0-9._~+/=-]{36,}$/` + extended comment (vendor rec `ghs_[A-Za-z0-9.\-_]{36,}`, canonical superset, warn-not-throw rationale, rotation tripwire)
- [x] 2.5 `apps/web-platform/lib/safety/redaction-allowlist.ts` (`API_KEY_RE`) — widen BOTH GitHub arms: `(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9._~+/=-]{20,}` and `github_pat_[A-Za-z0-9._~+/=-]{22}_[A-Za-z0-9._~+/=-]{59,}`; non-GitHub arms (`sk-*`, `AKIA`, `xox*`, `sbp_`, `sb_secret_`) stay documented-narrower
- [x] 2.6 `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` — `check_value_safe_drift` pin → `ghs_[A-Za-z0-9._~+/=-]{20,}`
- [x] 2.7 `tests/scripts/lib/git-data-birth-readiness-gate.sh` — comment refresh only ("alphanumeric plus `_`" → canonical b64token alphabet)
- [x] 2.8 ADR-280 amendment — `## Decision` scope clarification (canonical alphabet governs ALL credential-shape sites) + rejected alternative "per-site vendor-format pins" citing #9972 → #9999

## Phase 3 — Verification

- [x] 3.1 `bash plugins/soleur/skills/skill-security-scan/test/redact-pii-ghs-shape.test.sh` → `redact-pii-ghs-shape: ok`
- [x] 3.2 `bash plugins/soleur/test/kb-search-lockstep.test.sh` → `kb-search-lockstep: ok`
- [x] 3.3 `bash plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` → 0 failures
- [x] 3.4 `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-auth.test.ts lib/safety/redaction-allowlist.test.ts` → green
- [x] 3.5 `bash scripts/lint-shell-trace-credential-refusal.test.sh` → green; manually reintroduce `ghs_[A-Za-z0-9]{20,}` in a scratch file under a swept pathspec → new census rows RED (record result in PR body)
- [x] 3.6 `bash scripts/lint-orphan-test-suites.sh` → `orphan test suites: none` (new test file registered via `plugins/soleur/skills/*/test/*.test.sh` glob)
- [x] 3.7 `git grep -n '_bearer''_ok() {' -- '*.sh'` → zero NEW contiguous-literal hits from this change (all additions assembled split)
- [x] 3.8 Byte-delta check on `work/SKILL.md` vs merge base ≤ 0 (`lint-skill-body-budget.py` green)

## Sharp-edge reminders

- No `*.sh` line (code OR comment) may contain the contiguous `_bearer_ok() {` literal — assemble split.
- All `ghs_` fixtures split-assembled; every new fixture carries every canonical byte.
- The bench ↔ kb-search regex literals must stay byte-identical (lockstep test).
