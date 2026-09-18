---
title: "Tasks: registry heartbeat Phase-B delivery field (#7960)"
plan: knowledge-base/project/plans/2026-09-18-fix-registry-heartbeat-phase-b-delivery-field-plan.md
branch: feat-one-shot-7960-phase-b-delivery-field
pr: 8272
lane: cross-domain
---

# Tasks: registry heartbeat Phase-B delivery field (#7960)

## 0. Setup (read-only)

- [ ] 0.1 Baseline suites green: `bash scripts/followthroughs/zot-last-err-redact-7500.test.sh` (19/19), `bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` (33/33), `bash apps/web-platform/infra/registry-boot-guard.test.sh` (104).
- [ ] 0.2 `bash apps/web-platform/infra/registry-userdata-budget.sh --json` → record baseline (stored 14168).

## 1. Producer field (contract first)

- [ ] 1.1 RED: heartbeat redaction suite +3 assertions (structural: exactly one `LINE="SOLEUR_ZOT_DISK`, token value class before ` zot_last_err=`; emit-level via `assert` over `${out%% zot_last_err=*}` on the no-jq suppressed path; panic path must-PASS). `EXPECTED_MIN=36`.
- [ ] 1.2 RED: boot guard field list + `err_redact_rev=`; `MIN_ASSERTIONS=104`.
- [ ] 1.3 GREEN: add ` err_redact_rev=1` after `zot_last_err_src=$ZOT_ERR_SRC` in the `LINE=` assignment, plus a whole-line `#` contract comment (monotonic; ≥1 = Phase-B gate present; ADR-211).
- [ ] 1.4 Suites green (36/36, 105); budget re-run (stored ≤ 14,200, headroom ≥ 18,500); `registry-userdata-budget.test.sh` + `cloud-init-user-data-size` test via the package's own runner.

## 2. Probe harness (RED)

- [ ] 2.1 Extract the token from `$HERE/../../apps/web-platform/infra/cloud-init-registry.yml` (`grep -F 'LINE="SOLEUR_ZOT_DISK' | head -1 | grep -oE 'err_redact_rev=[^ "]+'`); FATAL if empty.
- [ ] 2.2 `rowf` builder; remove the `BASELINE` extraction and `-u SOLEUR_FT_BASELINE_BOOT`; fabricated `OLDBOOT`; `proof()` and case 13's `suppressed` row tail `""` → `none`; `CANARY7960` in every non-`suppressed` fixture tail and an absence check in `expect()`.
- [ ] 2.3 Changed cases: 3, 4, 18, 19 → 3 (`lacks err_redact_rev`); 5 and 7 rows carry the token in the head, newest `dt`, with an inline invariant comment → 3; 9 new-boot row carries the field → 2 `DELIVERY PROVEN`.
- [ ] 2.4 New cases: 3b, N1, N2, N4 (token after the row's own ` zot_last_err=`), N5 (`rowf(OLDBOOT)` + `row(NEWBOOT)` clean), N7, N9, N11, N12 (`suppressed` tail not `none` → 1), N13–N16 (leak shapes: `map[`, IPv6, `Headers:` case, bare `Cookie:[`) → 1, N17–N19 (`clientIP: default`, `headers: [Content-Type]`, `Authorization:[******]`) → 0. `MIN_CASES=35` (literal; `only %s cases ran`).
- [ ] 2.5 Confirm every new/changed case fails against the current probe for its named reason.

## 3. Probe change (GREEN)

- [ ] 3.1 Decision table R1–R4; `F` counted in the existing awk pass over all newest-boot rows (not `TIER4_ROWS`); `suppressed` secondary proof; tightened `L`: case-insensitive three-pattern set (header map incl. `map[`; IPv4/IPv6 `clientIP`; unmasked bare credential header) plus any `suppressed` row whose tail is not exactly `none`; R2 message says "header structure".
- [ ] 3.2 Delete `BASELINE_AT_MERGE`, `BASELINE`, the override, all drift branches, the empty-baseline and terminal-unreachable blocks.
- [ ] 3.3 Rewrite drift-as-proof prose; `# R1`–`# R4` comments on every verdict exit; `# PROOF KEY: err_redact_rev …` header line; comment why ≥1 newest-boot row suffices.
- [ ] 3.4 Harness 35/35; shellcheck; `bash scripts/guard-vacuity-floor.test.sh` green.
- [ ] 3.5 Mutation-prove M1–M16, H1–H2, PM1–PM5 on scratch copies; record results in the GREEN commit message.
- [ ] 3.6 Leak-regex check on real data, read-only via `doppler run -p soleur -c prd_terraform`: on the pre-Phase-B boot `d0107f1f…` count OLD, NEW, OLD∧¬NEW (NEW ≥ 1; every OLD∧¬NEW row classified by shape category, counts only); on `78111e0e…` NEW = 0.
- [ ] 3.7 Live read-only probe → exit 3 with `lacks err_redact_rev` and `78111e0e`.

## 4. Records and follow-ups

- [ ] 4.1 ADR-211 amendment (dated subsection, amended trigger, post-PASS residual); `status: adopting` unchanged.
- [ ] 4.2 Draft `issue-7960-body.md` (directive byte-identical; R1–R4 contract; falsification condition naming `err_redact_rev`).
- [ ] 4.3 File follow-up (a) 7440 sibling defect and (b) dispatcher hard-coded #7555/#7556 wording.
- [ ] 4.4 `bash scripts/generate-kb-index.sh`; commit `knowledge-base/INDEX.md`.

## 5. Ship and deliver (ship / post-merge)

- [ ] 5.0 Resume check (PR state, #7960 state, local probe).
- [ ] 5.1 Writer-idle check for the three zot writers.
- [ ] 5.2 File follow-up (c): post-PASS docs PR tracker.
- [ ] 5.3 THE ONE OPERATOR STOP: explicit authorization covering merge + dispatcher re-fire + one direct recovery dispatch; merge immediately (no `--auto`).
- [ ] 5.4 Apply the #7960 body edit after MERGED.
- [ ] 5.5 Watch dispatch + release/deploy (apply run id via the dispatcher's own `DISPATCHED_AT` filter); on P3 refusal post a pointer on #7960 and re-fire once writers conclude; verify the apply run itself (success + `zot store volume preserved (0 delete/forget)`); 5b direct recovery on apply failure.
- [ ] 5.6 Pull-path health on two new-boot rows.
- [ ] 5.7 Local probe loop to exit 0 (bounded 90 min); investigate R4 immediately.
- [ ] 5.8 `gh workflow run scheduled-followthrough-sweeper.yml`; verify #7960 CLOSED with PASS.
- [ ] 5.9 Open the post-PASS docs PR closing follow-up (c).
