# Tasks: Inngest LUKS arc items 6, 8b and C1

Plan: `knowledge-base/project/plans/2026-10-20-chore-inngest-luks-items-6-8b-c1-measure-and-no-fallback-plan.md`
Branch: `feat-one-shot-9927-inngest-luks-items-6-8b-c1` | Draft PR 10652 | `Ref #9927`, `Ref #10112` (never a closing keyword)
Lane: cross-domain (spec.md absent; fail-closed default). Commit series 1 = Phases 1 and 2; series 2 = Phase 3.

Read-only guard for every measurement task: names and metadata only; never print, log, store or transmit a value, a diff, an identifier or a payload; `set +x`, `set -o pipefail`, `2>/dev/null` on every `jq`; no `--debug`; no write command of any kind.

## Phase 0: Setup

- 0.1 Fetch origin/main and diff EVERY path in the plan's Files to Edit; rebase if main moved (TLS PR `f90d49c066` touched `infra-validation.yml`)
- 0.2 File deferred issues with `Ref #9927`: (a) site C `scripts/cutover-inngest.sh` fallback plus census/script scan over `scripts/` plus stale comments; (b) sweep steps off the loader token; (c) pre-drafted user notice for a total loss; (d) project-scoped read-only role for Inngest-history probes; (e) Doppler tier arbiter (owner dashboard read) if M6.2 cannot measure the tier
- 0.3 Baseline: loader suite green; `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`

## Phase 1: Item 6, Doppler version history (series 1)

- 1.1 M6.1 credential identity (key names first)
- 1.2 M6.2 plan tier from CLI fields named plan/tier/billing, else `documented, not measured` from the docs page (URL + date); unmeasured tier => Route A "unverified, plan as if unavailable"
- 1.3 M6.3 `configs logs` for `soleur-inngest/prd` only: count, oldest and newest timestamp, age; cap 50 pages; non-array/rc/cap hit => `could-not-measure`
- 1.4 Rollback scope from docs (URL + date); Route A `documented, not rehearsed`; never run `rollback`
- 1.5 Route A rule (available only if measured paid, scope documented, oldest-entry age meets a derived horizon) and sweep every Route A / version-history mention; record: runbook Route A row and ADR-282 loss-mode cell (old text under Superseded blockquote); ledger tier only if falsified

## Phase 2: Item 8b, no-fallback Hetzner token readers (series 1)

- 2.1 M8b.1 names-only listing; verdict computed from separate return codes (listed / absent / could-not-measure) for `HCLOUD_TOKEN_READONLY` and `HCLOUD_TOKEN`; identity-matched log corroboration each with a positive control; record the O5 write-probe date or `unverified`; if not listed, stop 8b and edit nothing under `.github/` or `tests/`
- 2.2 Census caller-invariant row (floor, mutation row) and PR-body caller table with transitive Hetzner need, incident-response jobs tagged, consumer empty-token rows (or recorded gaps), `set -u` check at the `apply-web-platform-infra.yml` empty-token checks (ADR-231 byte gate)
- 2.3 RED: commit the failing rows ALONE and record the SHA: loader rows 1c/1d/auth-error, census (delete `RO_FIRST`, invert M-g1-g2, site B coverage), `workspaces-luks-cutover-workflow.test.sh` (`readonly_absent`), fence rows
- 2.4 GREEN site A: `action.yml` legacy arm single read, `_bearer_ok` shape check, `::error` verdict `legacy_hcloud_readonly_absent` (hint `privileged_source_missing`), rc 0, nothing exported (deliberate, CTO F6; residual closed by O10)
- 2.5 GREEN site B: `infra-validation.yml` plan step (re-diff first)
- 2.6 GREEN site D: `workspaces-luks-cutover.yml` volume lookup
- 2.7 Listing fence: two echoed blocks and prose in `scheduled-terraform-drift.yml`; fence classifier RED-then-GREEN on `HCLOUD_TOKEN_READONLY`
- 2.8 Update `infra-credential-tiers-8209.md` fallback rows and O5/O10 notes, plus the break-glass row
- 2.9 Run touched suites and the census

## Phase 3: Item C1, surviving source for the affected-user list (series 2)

- 3.1 Code read, FINISHED (incl. `cron/*.manual-trigger`, `bot-fix/*`, `vendor/*`): event-class table; app-log fields; log retention (documented)
- 3.2 RED then GREEN: `scripts/inngest-history-probe.sh` (hostile-environment prologue, in-request `transaction_read_only` proof, event-name allowlist with `other` abort) and `.test.sh` (Guard 2 incl. stderr/xtrace/hex/hash leak rows), `run_suite` line in `scripts/test-all.sh`, `lint-supabase-deprecated-endpoints` host pin and highwater; trap-ownership high-water; CI-shaped `TMPDIR` run if the suite self-spawns
- 3.3 Push and read the `test` leg; only when green run the probe (gate)
- 3.4 Run round 1 (identity incl. `show transaction_read_only` = on, columns, estimates, time bounds); round 2 only if a typed user-reference column exists, one commit and green CI per entry
- 3.5 Apply the evidence bar; record tri-state results and queries in `measurements.md`
- 3.6 Record in runbook and ADR-282 with the CLO did-not-inspect sentence and evidence class; default "all active users" stays; 1b stays parked
- 3.7 Article 30 PA-13 (f), PA-27 (f) and sibling Superseded markers (one grep, count in PR body); `compliance-posture.md` entry; check `docs/legal/` for contradictions
- 3.8 Conditional storage-limitation issue if #7779 and #8528 do not cover the Postgres history
- 3.9 `soleur:gdpr-gate` at work Phase 2 exit
- 3.H Halt path: on any CLO stop condition, leave the PR draft, revert series 2 if the owner so decides, comment redacted on #9927

## Phase 4: Verify and ship

- 4.1 First push: read `test` and (if `.github/` or `apps/*/infra` changed) `deploy-script-tests` BEFORE spawning review seats
- 4.2 `c4-count-parity`, trap high-water, supabase endpoint lint, touched suites; C4 files re-read and the one-edge decision recorded
- 4.3 ADR-241 amendment-log entry; ADR-282 addendum (items 6, 8b, C1 tables with evidence classes and dates)
- 4.4 Added-lines leak tripwire over the whole diff
- 4.5 PR body: MEASURED / NOT MEASURED table with dates, caller table, rulings, deferred issues, no-write statement, `Ref #9927` and `Ref #10112`
- 4.6 Review seats: security-sentinel, user-impact-reviewer, observability-coverage-reviewer, test-design-reviewer

## Review outcome, 2026-10-22

- The C1 probe script and its suite (3.2) were built, run once (3.4, round 1) and then REMOVED from the PR on a CTO ruling: the finding is recorded, and a committed path to an account-wide token is the less safe state. The registrations in `scripts/test-all.sh`, `suite-durations.tsv`, `suite-shard-legs.tsv` and the lint highwater (25 back to 24) were reverted with it. Round 2 is an owner-gated, separate change.
- The ten `${HCLOUD_TOKEN:-}` guard edits and fence rows R7a-c (2.x) were reverted: every one of the ten steps already pre-binds the variable.
