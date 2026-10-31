# Tasks — feat-one-shot-11694-ratchet-accept-rows

Plan: `knowledge-base/project/plans/2026-10-31-fix-affected-index-ratchet-accept-rows-plan.md`
Issue: #11694 — advisory `affected-index-ratchet` red on main (`reason=new-pair live=1515 baseline=1510`).

## 1. Accept rows (the whole fix)

- [ ] 1.1 Insert the seven accept rows from plan Phase 1 into `scripts/ci-pr-affected-audit.accept.tsv`, in sorted position (real TAB separators):
  - Row 1 (`scripts/betterstack-emitter-read` → `scripts/followthroughs/inngest-hostmetrics-trim-11602.sh`, `6b94378af8e8/1`) sorts before the existing `inngest-luks-keeper-dark-11265.sh` row of the same suite
  - Rows 2–4 (`scripts/followthroughs/inngest-bs-token-restage-7596`) and rows 5–7 (`scripts/followthroughs/inngest-hostmetrics-trim-11602`) sort before the `inngest-luks-keeper-dark-11265` suite block; `knowledge-base/…` row first, then the two `scripts/ensure-doppler.sh` rows in anchor order `1027621c5bba` then `7c59a1e49464`
- [ ] 1.2 Re-verify the file's `suite`/`path`/`anchor` key sequence is still non-decreasing (convention, not enforced — keep it)
- [ ] 1.3 (Optional evidence) `scripts/audit-suite-reads.sh record --mode check` on the two followthrough suites; confirm `ensure-doppler.sh` and `betterstack-log-query.md` are not opened; grep both suite files for the basenames and parent dirs as separate literals

## 2. Verification

- [ ] 2.1 `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 and prints `SOLEUR_PR_AFFECTED_RATCHET exit=0` (no `new-pair`, no `stale-accept`)
- [ ] 2.2 Confirm no change to `scripts/ci-pr-affected-audit.baseline.tsv` and no `AFFECTED_<LABEL>_PATHS` entry added in `scripts/lib/test-affected-paths.sh`
- [ ] 2.3 Confirm no `suite/path/anchor/ordinal` key duplicates an existing row
