# Tasks: Sweep argv bearer tokens to curl --config - (stdin)

Plan: `knowledge-base/project/plans/2026-10-06-chore-sweep-argv-bearer-tokens-to-curl-config-stdin-plan.md`
Residue tracker (already filed): #9597

Per-file recipe (every phase): (a) if the file is in a lint baseline or fails `python3 scripts/lint-shell-trace-credential-refusal.py <file>`, commit the xtrace-refusal, Rule D flag and destination-pin prerequisites first; (b) convert to canonical form A/B/C/D; (c) run `bash -n`, the owning tests, `--changed` lint, and regenerate baseline E (deletions only).

## Phase 0: Freeze, measure, RED battery

- [ ] 0.1 Re-run `census-argv-bearer.py` (expect `TOTAL sites=136 files=64`) and the acceptance grep
- [ ] 0.2 Lint the 19 baselined Tier 1 files by explicit path; record per-file A/B/C/D findings
- [ ] 0.3 Resolve token provenance for `linkedin-community.sh` (form C needed or not)
- [ ] 0.4 Write `tests/scripts/test-argv-bearer-sweep.sh`: shim replaying the real curl contract; dynamic rows for the 20 followthrough probes and form C sites; 3 negative rows (Sentry, Better Stack, Supabase); unset-token rows; static assertion for the 4 sourced gate libs
- [ ] 0.5 Observe every dynamic row RED on the unconverted tree
- [ ] 0.6 Register in `scripts/test-all.sh`; run `scripts/lint-orphan-test-suites.sh`

## Phase 1: Rule E first, exemplar, pilot

- [ ] 1.1 Fixtures and test rows first (Guard 1 matrix rows 1-10), then `check_rule_e()` + `main()` plumbing (`baselines_by_rule["e"]`, `load_baseline_e`, `--write-baseline-e`, `offenders_e`)
- [ ] 1.2 Wrapper awareness for Rules D and E (file-local wrapper functions whose body invokes curl)
- [ ] 1.3 Diff Rule E offenders against the census; resolve differences; generate baseline E (header cites #9597)
- [ ] 1.4 `cutover-verify.sh` `curl_auth()`: `--disable` first, `--noproxy '*'`
- [ ] 1.5 Pilot `arm-checkpoint.sh` (A), `configure-sentry-alerts.sh` (B), `provision-plausible-goals.sh` (array-held)

## Phase 2: scripts/followthroughs (20 files)

- [ ] 2.1 Prerequisites: `autovacuum-thrash-6168`, `concurrency-slot-wal-backoff`, `l3-probe-armed-6438`, `web2-standby-soak-6459`
- [ ] 2.2 Convert all 20 probes (curl invocation only)
- [ ] 2.3 Gates: battery, `lint-followthrough-varq-ban.sh`, `followthrough-exec-bit.test.sh`, `sweep-followthroughs.test.sh`, probe-owned tests

## Phase 3: scripts/*.sh (8 files)

- [ ] 3.1 Prerequisites: `check-cloudflare-token-drift.sh`, `provision-plausible-goals.sh`, `weekly-analytics.sh`
- [ ] 3.2 Convert; `cutover-inngest.sh` in its own commit; update `tests/scripts/test-betterstack-ingest-probe.sh` stub

## Phase 4: apps/web-platform/scripts and supabase/scripts (8 files)

- [ ] 4.1 Prerequisites: `dsar-export-oversize.sh`, `configure-auth.sh`, `seed-*`
- [ ] 4.2 Convert with form B wrappers; seed scripts use one `sb_curl` emitting Bearer + apikey; dsar moves its apikey headers

## Phase 5: cla-evidence, non-host infra, production gate libs

- [ ] 5.1 Prerequisites: `gdpr-override.sh`, `arm-heartbeats.sh`, `verify-tunnel-ingress-origin.sh`, `preapply-entrypoint-gate.sh`
- [ ] 5.2 Prove the four infra files are not host-coupled (grep output); `zot-image-oci-archive.sh` publish idempotence check (else move to Tier 2)
- [ ] 5.3 Convert incl. `_cf-admin-token.sh`, `fresh-host-boot-trail.sh`, gate libs; update owning tests

## Phase 6: plugins and hooks (10 files)

- [ ] 6.1 Convert; form C allowlist guard at response-derived sites; form D printed text; owning tests

## Phase 7: Final baselines, ADR addendum, verification

- [ ] 7.1 Regenerate A/B/C and D baselines (deletions only); baseline E ends as the 8 Tier 2 files
- [ ] 7.2 `fixture-relative-assert.test.sh` (regenerate baseline only if counts moved)
- [ ] 7.3 ADR-202 dated addendum (about 10 lines)
- [ ] 7.4 Full gate: repo-wide lint, `--changed`, battery, owning tests, c4-count-parity, markdownlint
- [ ] 7.5 PR body: `Ref #7797`, `Closes #7843` with scope moved to #9597 stated
