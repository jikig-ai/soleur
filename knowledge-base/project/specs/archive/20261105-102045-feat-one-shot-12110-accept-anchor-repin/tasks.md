# Tasks — feat-one-shot-12110-accept-anchor-repin

Plan: `knowledge-base/project/plans/2026-11-05-fix-affected-ratchet-stale-accept-plan.md`
Issue: #12110

## Phase 1 — Enumerate the live boundary set

- [ ] 1.1 Re-run `python3 -I scripts/ci-pr-affected-replay.py ratchet --report <report>` and confirm the flagged set still equals plan tables A (11 stale-accept rows) and B (3 new-pairs); if main drifted, re-enumerate before editing.
- [ ] 1.2 Run `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv --all-refs | grep '^ref'` and confirm the complete boundary-line set for the 3 pairs (report caps ~3 refs/pair; every boundary line needs coverage).

## Phase 2 — Apply the dispositions (assumed split arm; see decision-challenges.md row 1)

- [ ] 2.1 Delete the 11 stale-accept rows from `scripts/ci-pr-affected-audit.accept.tsv` (lines 355-362, 369, 374, 383 at plan time — re-confirm by anchor, not line number): `plugins/soleur` ↔ `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs` `4663b0253b8d/1` + `4e5a4d1caf27/1`; `plugins/soleur` ↔ `apps/web-platform/scripts/sandbox-canary.mjs` `0ce179c2ca7a/1`, `3be5ad93bfce/1`, `da9456338a93/1`, `db12ad216e7d/1`, `df729b3e38c7/1`, `fa71562066a9/1`; `plugins/soleur` ↔ `package.json` `0b403e085b16/1`, `8d47cc95bf11/1`, `f3792010002b/1`. No other row removed.
- [ ] 2.2 Add `"glob:scripts/*sentry-issue.sh"` to `AFFECTED_PLUGINS_SOLEUR_PATHS` in `scripts/lib/test-affected-paths.sh`, member-string order (after `glob:scripts/*prod-version-drift-b9-probe.sh`, before the `glob:tests/scripts/...` member), with comment `# mention pair; every boundary line anchored on >8-commits/90d file — accept rows refused` matching siblings at :1306-1309.
- [ ] 2.3 Insert the 4 `tests/hooks/emissions` accept rows (text in plan Phase 2 step 5 — anchors `6e9e24010f9b/1`, `b50d46d45247/1` for `scripts/betterstack-query.sh`; `ee8220c7499a/1`, `b50d46d45247/1` for `scripts/sentry-issue.sh`), C-locale order inside the `tests/hooks/emissions` block, every col-5 starting `false-positive:` + space.

## Phase 3 — Verify the fixpoint

- [ ] 3.1 `awk -F'\t' 'NF==5 && $5 !~ /^false-positive: /' scripts/ci-pr-affected-audit.accept.tsv` prints nothing; `audit --accept` shows no `ValueError` parse failure.
- [ ] 3.2 `python3 -I scripts/ci-pr-affected-replay.py ratchet --report <report>` → `exit=0 reason=pass live=0 baseline=0`; `oracle-inputs-changed:` notice names the touched oracle file(s). Iterate to fixpoint if any new flag appears.
- [ ] 3.3 Mutation probe (once, then revert): corrupt one new row's col-5 prefix, confirm `audit --accept` exits 2 naming the row — proves AC-4 is not vacuous.
- [ ] 3.4 After any rebase/merge before arming, re-run 3.2 on the merged state (anchor-keyed rows go stale on sibling merges without textual conflicts).

## Phase 4 — PR body

- [ ] 4.1 Note the `oracle-inputs-changed:` warning on the PR's own ratchet run as the designed notice (AC-6); cite `Closes #12110`; do not comment on or edit PR #12103.
