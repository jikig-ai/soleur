---
feature: feat-one-shot-5987-redaction-hardening-nfkc-zerowidth-redos
issue: 5987
epic: 5983
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-05-feat-redaction-hardening-nfkc-zerowidth-redos-plan.md
---

# Tasks — Redaction hardening (NFKC + zero-width strip, ReDoS fail-closed)

Derived from the finalized (post-plan-review) plan. Implement with `skill: soleur:work`.

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 `python3 -c "import unicodedata; assert unicodedata.normalize('NFKC','ｓｋ_ｌｉｖｅ_1234')=='sk_live_1234'"`; confirm python3 on PATH in CI.
- [ ] 0.2 Whole-pipeline ReDoS benchmark on a 1 MiB **max-NFKC-expansion** payload (e.g. repeated U+FDFA) + email/UUID storm; confirm < ~1 s; tune `REDACT_MAX_INPUT_BYTES` if needed.
- [ ] 0.3 Contract baseline GREEN on `main`: `redact-sentinel.test.sh`, `code-to-prd.test.sh`, and a `dry-run.sh` smoke invocation.

## Phase 1 — RED tests (extend `incident/test/redact-sentinel.test.sh`)

- [ ] 1.1 Test 9 (golden ERE↔`re` parity) FIRST — capture OLD engine per-class hits on `positive-corpus.md` + near-miss negatives; assert NEW engine identical class-hit set.
- [ ] 1.2 Test 5 — confusable evasion (ZWSP JWT + fullwidth Stripe): raw regex misses, engine exits 1 w/ class. Generate input at runtime via `\uXXXX`.
- [ ] 1.3 Test 6 + 6b — oversize (raw) AND NFKC-expansion oversize → synthetic HIGH, exit 1, no per-class scan.
- [ ] 1.4 Test 7 — invalid-UTF-8 splice (→ U+FFFD) caught after strip.
- [ ] 1.5 Test 8 — clean negative baseline still exits 0; Test 10 — `python3` off PATH → exit **2**.
- [ ] 1.6 Test (AC7) — `Юsk-ant-…` still caught (guards `re.ASCII`).
- [ ] 1.7 Test 11 — legal-generate: secret-bearing draft `mktemp` → sentinel exits non-zero.
- [ ] 1.8 Preserve Tests 1–4 (14 classes, bad-arg=2, output-format regex).

## Phase 2 — GREEN engine

- [ ] 2.1 Create `incident/scripts/redact-engine.py`: `cap → strip(STRIP incl. U+FFFD + bidi) → whole-string NFKC → re-check len(norm) → finditer → meta_redact`. All 14 patterns compiled with `re.ASCII`; `env_var` uses `\S+` (NOT `[^[:space:]]+`).
- [ ] 2.2 Exit semantics: matches/synthetic-HIGH → 1; bad-arg/unreadable/crash → 2 (try/except wraps `scan`).
- [ ] 2.3 Rewrite `incident/scripts/redact-sentinel.sh` as a thin shim: python3-absent → exit 2; normalize any non-{0,1,2} engine code → 2; else pass through.
- [ ] 2.4 Run Phase 1 tests → GREEN, including golden parity (2.1 must reproduce the old class-hit set).

## Phase 3 — Legal path

- [ ] 3.1 Edit `legal-generate/SKILL.md` Phase 3: write draft to `mktemp`, run sentinel **before** the AskUserQuestion presentation (SKILL.md:54); exit 0 → present→write, 1 → revise/re-run, 2 → halt. Cite `../incident/scripts/redact-sentinel.sh`.
- [ ] 3.2 (Test 11 covers the executable assertion; ensure the gate block precedes presentation.)

## Phase 4 — Docs, NOTICE, ADR

- [ ] 4.1 `incident/SKILL.md` — note engine is Python behind the shim; contract unchanged.
- [ ] 4.2 NOTICE stanza attributing gstack `redact-engine` (clean-room, no verbatim lift).
- [ ] 4.3 Author ADR-086 (minimal): fail-closed engine contract (whole-string NFKC match; oversize/non-running → block) + homoglyph scope boundary + redact-sentinel-as-shared-3-consumer-dependency accepted debt. Re-verify next-free ordinal at `/ship`.

## Phase 5 — Verify

- [ ] 5.1 Full suite: `redact-sentinel.test.sh` + `code-to-prd.test.sh` + `dry-run.sh` smoke GREEN.
- [ ] 5.2 AC1–AC7 checked (see plan Acceptance Criteria).
- [ ] 5.3 `git grep -nP '[\x{200b}\x{200c}\x{200d}\x{2060}\x{feff}\x{202a}-\x{202e}\x{fffd}]' plugins/soleur/skills/incident plugins/soleur/skills/legal-generate` returns nothing (AC6).
- [ ] 5.4 File the deferral follow-up issue (legal-audit + digest-scrub NFKC hardening + class-set sync).
- [ ] 5.5 Review-time: spawn `security-sentinel` prompted for MISSED classes; `user-impact-reviewer` (single-user threshold).
