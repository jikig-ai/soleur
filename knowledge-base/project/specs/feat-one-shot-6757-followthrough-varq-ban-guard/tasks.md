# Tasks — Fix #6757 followthrough `${VAR:?}` ban guard + convert 14 probes

Plan: `knowledge-base/project/plans/2026-07-22-chore-followthrough-varq-ban-guard-plan.md`
Lane: single-domain. Threshold: aggregate pattern. One PR (guard + conversions together).

## Phase 0 — Preconditions
- [ ] 0.1 Re-run the canonical census; confirm the 14 offenders + 6 comment-only exclusions match the plan table (drift check).
- [ ] 0.2 Confirm no offender carries trailing `|| { … exit 2; }` dead code (survey: none).

## Phase 1 — Guard script (NEW: `scripts/lint-followthrough-varq-ban.sh`)
- [ ] 1.1 Parameterized census: `TARGET_DIR="${1:-scripts/followthroughs}"`; default resolves via `git rev-parse --show-toplevel`.
- [ ] 1.2 Per non-`.test.sh` `*.sh`: `grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$f" | grep -vE '^[0-9]+:[[:space:]]*#'`; print `<file>:<line>` per surviving line. **`grep -n` on RAW file FIRST**, then drop full-line-comment hits — piping `grep -v '^#' | grep -n` re-indexes line numbers wrong (deepen-plan finding). Detection identical to canonical census.
- [ ] 1.3 Exit 1 on any violation, 0 on none, 2 on internal error.
- [ ] 1.4 Min-cardinality floor (≥10) ONLY when `$1` unset (production run); skip for explicit sandbox dir.
- [ ] 1.5 `chmod +x` (100755).

## Phase 2 — Mutation test (NEW: `scripts/lint-followthrough-varq-ban.test.sh`) — non-vacuity core
- [ ] 2.1 `mktemp -d` sandbox OUTSIDE `scripts/followthroughs/`; `trap 'rm -rf "$SANDBOX"' EXIT` (owns only its mktemp dir — satisfies lint-trap-tempfile-ownership).
- [ ] 2.2 GREEN: compliant fixture → guard exit 0.
- [ ] 2.3 RED (`:?`): `: "${FOO:?msg}"` executable line → guard non-zero, names the file.
- [ ] 2.4 RED (colon-less `?`): `${BAR?msg}` executable line → guard non-zero (proves `:?\?` breadth).
- [ ] 2.5 Comment-collision GREEN: banned form in a full-line `#` comment only → guard exit 0.
- [ ] 2.6 Live-run-not-flagged: production run (no arg) still exits 0 with fixtures present.
- [ ] 2.7 `chmod +x` (100755).

## Phase 3 — Register in `scripts/test-all.sh` (EDIT) — highest-risk
- [ ] 3.1 Add 2 `run_suite` lines in `if want_scripts;` block (near line ~156–161), comment citing #6757 + orphan-suite class:
      `run_suite "scripts/followthrough-varq-ban-live" bash scripts/lint-followthrough-varq-ban.sh`
      `run_suite "scripts/followthrough-varq-ban" bash scripts/lint-followthrough-varq-ban.test.sh`
- [ ] 3.2 Verify orphan-suite regex matches the `.test.sh` registration.

## Phase 4 — Convert the 14 probes (EDIT)
Replace each `: "${VAR:?…}"` with `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: VAR not set" >&2; exit 2; fi`. Preserve `set` flags + surrounding logic.
- [ ] 4.1 ac10-workspace-reconcile-sentry-4246.sh (L22, SENTRY_AUTH_TOKEN)
- [ ] 4.2 ac8-founder-ambiguous-soak-5673.sh (L30)
- [ ] 4.3 canary-promotion-5875.sh (L30,31,32 — 3 secrets, each line)
- [ ] 4.4 community-monitor-checkin-soak-5728.sh (L35)
- [ ] 4.5 deploy-ghcr-pull-recovery-6400.sh (L29)
- [ ] 4.6 ghcr-minter-live-6031.sh (L28)
- [ ] 4.7 gh-pages-cert-reissue-6657.sh (L22, GH_TOKEN)
- [ ] 4.8 moved-block-wedge-5887.sh (L29, GH_TOKEN)
- [ ] 4.9 phase3-ga-soak-5274.sh (L35)
- [ ] 4.10 reconcile-ff-only-sentry-4977.sh (L33)
- [ ] 4.11 sentry-checkins-3859.sh (L20)
- [ ] 4.12 sync-health-residual-5689.sh (L37)
- [ ] 4.13 zot-login-gate-erofs-repaired-6565.sh (L52,53,54 — 3 BETTERSTACK_QUERY_* secrets)
- [ ] 4.14 zot-login-gate-names-failure-6497.sh (L44,45,46 — 3 BETTERSTACK_QUERY_* secrets)

## Phase 5 — Convention cross-reference (EDIT)
- [ ] 5.1 Add 1 line to `followthrough-convention.md` §Author workflow (near L24) citing the new guard.

## Phase 6 — Acceptance verification (all pre-merge)
- [ ] 6.1 AC2: `bash scripts/lint-followthrough-varq-ban.test.sh` exits 0 (both RED directions + comment GREEN proven).
- [ ] 6.2 AC3: `bash scripts/test-all.sh scripts 2>&1 | grep -E 'scripts/followthrough-varq-ban(-live)?'` → both labels `[ok]`.
- [ ] 6.3 AC4: `bash scripts/lint-orphan-test-suites.sh` → "orphan test suites: none".
- [ ] 6.4 AC5: canonical census over the 14 → empty.
- [ ] 6.5 AC6: `bash scripts/lint-followthrough-varq-ban.sh` exits 0 (6 comment-only files green).
- [ ] 6.6 AC8: `bash scripts/test-all.sh scripts` exits 0.
- [ ] 6.7 AC9: `git status` shows no new tracked file under `scripts/followthroughs/`.
