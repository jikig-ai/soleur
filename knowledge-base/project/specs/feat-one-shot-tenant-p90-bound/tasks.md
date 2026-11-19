# Tasks — feat-one-shot-tenant-p90-bound

Plan: `knowledge-base/project/plans/2026-11-19-fix-tenant-integration-required-bound-reseed-plan.md`
Issue: #12755 (standing tracker — referenced, never closed) | Epic: #11556
Disposition: (a) bound mis-seed → re-seed (bimodal latency; see plan Evidence)

## Phase 1 — Re-seed the bound row

- [x] 1.1 Edit `scripts/required-check-wallclock-bounds.tsv`: change the
  `tenant-integration-required` row's pull-request column `300` → `960`
  (literal tab bytes, exactly 4 columns; `merge_group` `180` and margin
  `0.30` unchanged; row position unchanged).
- [x] 1.2 Same file: add a `# ROW SEED` provenance comment block in the
  dated-notes header area (after the 2026-11-17 oracle seed block), field
  shape per that block: measurement timestamp, per-surface `n`, `p90`,
  `duration_p90`, the sentinel sha of the measurement script, and the
  one-line bimodal finding (slow mode = `tenant-integration` suite
  needs-chain wait, not queue congestion).
- [x] 1.3 Append a dated measured-history bullet to
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  under `## Measured history`, in the style of the
  `2026-11-17 oracle-review-required bound-row seed` bullet: seed values
  (960/180), `n` per surface (26/30), the bimodal evidence (23 samples at
  11-76s vs 3 at 915-970s on 2026-11-18T14:52/14:56/23:08Z), the
  sibling-check discriminator (same-run independent siblings ≤~355s;
  umbrella aggregators higher but within their own bounds),
  duration_p90=21s, the 4 NOSAMPLE classes (3 earlier-batch + 1
  suite-cancelled mid-flight, trigger unattributed — job was executing,
  so not the third-arrival arm; documented accepted residual), and the
  2026-11-13 prior breach as the same mode.

## Phase 2 — Commit-time verification (TSV-header-mandated)

- [x] 2.1 `GH_TOKEN="$(gh auth token)" bash scripts/watch-wallclock-p90-11774.sh --print-report --dry-run`
  — the `tenant-integration-required` row must appear on both surfaces;
  re-measured p90 ≤ seeded bound on each (PR p90 ≤ 960, MQ p90 ≤ 180);
  no `::error::wallclock p90 breach` line for this check. If the API is
  unreachable, treat as blocked — never green.
- [x] 2.2 Conditional re-seed arm: if the PR-surface p90 drifted above 960,
  re-seed to the next-minute ceiling of the re-measured p90 and update the
  ROW SEED comment, the runbook bullet, and the plan's recorded numbers in
  the same commit (a loosen is legal only with the measurement recorded —
  TSV header rule).
- [x] 2.3 Parser spot-check:
  `awk -F'\t' '$1=="tenant-integration-required"{print NF, $2, $3, $4}' scripts/required-check-wallclock-bounds.tsv`
  prints `4 960 180 0.30`.
- [ ] 2.4 Diff scope: `git diff --name-only origin/main...HEAD` ⊆ {the
  bounds TSV, the runbook, this plan file, this spec dir}.
- [ ] 2.5 PR body: reference #12755, #11556, #12905 contextually; NO
  `Closes`/`Fixes`/`Resolves` keyword against #12755 (standing tracker);
  include the `## Changelog` section the version-bump workflow reads.
