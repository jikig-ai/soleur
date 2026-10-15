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
- [ ] 1.2 Test 5 — compatibility-confusable + invisible-splitter (JWT split by ZWSP **+ U+00AD + U+2028**, fullwidth Stripe): raw regex misses, engine exits 1. Runtime-generate via `\uXXXX`.
- [ ] 1.3 Test 6 + 6b — oversize (raw) AND NFKC-expansion oversize → synthetic HIGH, exit 1, no per-class scan.
- [ ] 1.4 Test 7 — invalid-UTF-8 splice (→ U+FFFD) caught after strip.
- [ ] 1.5 Test 8 — clean negative baseline still exits 0; Test 10 — `python3` off PATH → exit **2**.
- [ ] 1.6 Test (AC7) — `Юsk-ant-…` still caught (guards `re.ASCII`).
- [ ] 1.7 Test 11 — legal-generate: secret-bearing draft `mktemp` → sentinel exits non-zero.
- [ ] 1.8 Test 12 — cross-script homoglyph known-gap: un-mapped-prefix secret asserts exit 0 (version-controls the residual); `CONFUSABLE_MAP`-covered `ѕk_live_…` asserts exit 1.
- [ ] 1.9 Preserve Tests 1–4; **update Test 4 format regex** to the capped reveal `.{0,4}\*\*\*(.{0,4})?`.

## Phase 2 — GREEN engine

- [ ] 2.1 Create `incident/scripts/redact-engine.py`: `cap → strip → NFKC → strip → CONFUSABLE_MAP → re-check len(norm.encode) → finditer → meta_redact`. Full STRIP set (zero-width + bidi + U+00AD + U+2028/U+2029 + Hangul/Khmer fillers + annotation + U+FFFD). All patterns compiled `re.ASCII`; `env_var` uses `\S+`.
- [ ] 2.2 Tightened `meta_redact` (cap reveal: `{t[:4]}***{t[-4:]}` if len>24 / `{t[:4]}***` if >12 / `***`).
- [ ] 2.3 Exit semantics: matches/synthetic-HIGH → 1; bad-arg/unreadable/crash → 2 (try/except wraps `scan`).
- [ ] 2.4 Rewrite `redact-sentinel.sh` as thin shim: python3-absent → exit 2; normalize non-{0,1,2} → 2; else pass through.
- [ ] 2.5 Phase 2b: add `doppler_token`/`slack_token` classes; broaden PEM (`[A-Z0-9 ]*PRIVATE KEY`), UUID (`[0-9A-Fa-f]`), env_var vendors (HETZNER|FLAGSMITH|RESEND|TAILSCALE); build `CONFUSABLE_MAP` (~25 Cyrillic/Greek→ASCII). Add a synthesized `positive-corpus.md` fixture per new class.
- [ ] 2.6 Run Phase 1 tests → GREEN, including golden parity (Test 9 old-vs-new on existing corpus; new classes additive).

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
