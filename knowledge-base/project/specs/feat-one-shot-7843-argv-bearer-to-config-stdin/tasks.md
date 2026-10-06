# Tasks: Sweep argv bearer tokens to curl --config - (stdin)

Plan: `knowledge-base/project/plans/2026-10-06-chore-sweep-argv-bearer-tokens-to-curl-config-stdin-plan.md`
Residue tracker (already filed): #9597. Tier 1 = 53 files / 123 sites; Tier 2 = 11 files / 13 sites (deferred).

Per-file recipe (every conversion phase): (a) if the file fails `python3 scripts/lint-shell-trace-credential-refusal.py <file>`, commit the xtrace-refusal, Rule D flag and destination-pin prerequisites first; (b) convert to canonical form A/B/D with the token-shape guard (`_bearer_ok`, rejects empty); (c) run `bash -n`, the battery row, the owning tests, `--changed` lint, and regenerate baseline E (deletions only, per-file counts).

## Phase 0: Freeze and measure (no code)

- [x] 0.1 Re-run `census-argv-bearer.py` (expect `TOTAL sites=136 files=64`; TOTAL is on stderr) and the acceptance grep
- [x] 0.2 Lint the 19 baselined Tier 1 files by explicit path; record per-file A/B/C/D findings, behaviour-changing prerequisites, existing token guards (plan time: 13 fail, 6 only need baseline-line deletion)
- [x] 0.3 Record per Tier 1 script: token provenance, real character class, existing `--disable`/`--noproxy`; decide the plugin `--noproxy` policy
- [x] 0.4 Grep Tier 1 curls for `-v`/`--trace*`/`-D -` and stdin bodies
- [x] 0.5 Confirm no Tier 1 file is host-hashed or run live in the apply without its own test

## Phase 1: Lint first, battery, pilot

- [x] 1.1 Rule D fix: `_destination_vars` skips tokens after a redirection operator and masks `<(...)`; fixture `compliant-stdin-bearer-procsub-bare.sh` first
- [x] 1.2 Wrapper awareness for Rules D and E (file-wide names, transitive closure, command position, argument splicing); `--census` before/after; resolve new offenders in the same commit
- [x] 1.3 Guard 1 fixtures and rows first, then `check_rule_e()` + `main()` plumbing (`"e"` map entry, `load_baseline_e`, `--write-baseline-e`, `offenders_e`, equality on path and count in full-tree mode), own scope function, invocation-segment scan, file-wide variable-held headers, config-hazard sub-checks
- [x] 1.4 Generate baseline E (path TAB count) from the unconverted tree; diff vs census; resolve differences
- [x] 1.5 Write `tests/scripts/test-argv-bearer-sweep.sh` (instrument controls, real-curl oracle, auth-gated shim, rows keyed to baseline E); register in `scripts/test-all.sh`, shard manifest, affected-paths; prove registration by `grep -c` and a run log
- [x] 1.6 Pilot `arm-checkpoint.sh` (A), `configure-sentry-alerts.sh` (B), `provision-plausible-goals.sh` (array-held)

## Phase 2: scripts/followthroughs (20 files)

- [ ] 2.1 Prerequisites: `autovacuum-thrash-6168`, `concurrency-slot-wal-backoff`, `l3-probe-armed-6438`, `web2-standby-soak-6459` (re-run battery 401 row)
- [ ] 2.2 Convert all 20 probes (curl invocation + token-shape guard in place of the `-z` guard)
- [ ] 2.3 Gates: battery, `lint-followthrough-varq-ban.sh`, `followthrough-exec-bit.test.sh`, `sweep-followthroughs.test.sh`, probe-owned tests

## Phase 3: scripts/*.sh (6 files after pilots)

- [ ] 3.1 Prerequisites: `check-cloudflare-token-drift.sh`, `weekly-analytics.sh`
- [ ] 3.2 Convert; extend `check-cloudflare-token-drift.test.sh`; update `tests/scripts/test-betterstack-ingest-probe.sh` stub; `cutover-inngest.sh` in its own commit with its workflow and flip tests

## Phase 4: apps/web-platform/scripts and supabase/scripts (7 files after pilot)

- [ ] 4.1 Prerequisites: `dsar-export-oversize.sh`, `configure-auth.sh`; delete baseline lines for the six already-passing files
- [ ] 4.2 Convert with form B wrappers; seed scripts use one `sb_curl` (Bearer + apikey; anon-key call at `seed-qa-user.sh:175` stays); dsar moves its apikey headers

## Phase 5: cla-evidence, non-host infra, production gate libs

- [ ] 5.1 Prerequisites: `gdpr-override.sh`, `arm-heartbeats.sh`, `preapply-entrypoint-gate.sh`
- [ ] 5.2 Convert `_cf-admin-token.sh` (extend its test), `gdpr-override.sh`, `arm-heartbeats.sh` (rewrite fake curl to read stdin), four gate libs with their tests

## Phase 6: plugins and hooks (10 files)

- [ ] 6.1 Convert; token-shape guard everywhere; form D printed text; bash 3.2-safe constructs; owning tests

## Phase 7: Final baselines, ADR addendum, rebase, verification

- [ ] 7.1 Regenerate A/B/C and D baselines (full tree; deletions only vs end of Phase 1); baseline E ends as the Tier 2 set
- [ ] 7.2 `fixture-relative-assert.test.sh` (regenerate baseline only if counts moved)
- [ ] 7.3 ADR-202 dated addendum (sweeper-hop residual, sourced-lib limit, plugin proxy note); raise `MIN_ASSERTIONS`
- [ ] 7.4 Rebase on fresh `origin/main`; re-run census and Rule E; regenerate baseline E mechanically
- [ ] 7.5 Full gate: repo-wide lint, `--changed`, battery, owning tests, c4-count-parity, markdownlint
- [ ] 7.6 PR body: merge triggers a production release and an infra apply (zero Terraform delta); `Ref #7797`; `Closes #7843` with scope moved to #9597
