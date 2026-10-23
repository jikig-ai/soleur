# Tasks — fix: Inngest generation anchor reads the read-only Hetzner token only (Site C)

Plan: `knowledge-base/project/plans/2026-10-23-fix-inngest-luks-site-c-readonly-only-anchor-plan.md`.
Branch `feat-one-shot-inngest-luks-site-c-readonly`, draft PR #10891, `Ref #10664` (never `Closes`).
Stage by explicit path; never `git add -A`. No `.tf`, workflow, action, flip-guard or migration file is
touched. The one file under `apps/web-platform/infra/` that is edited
(`cutover-inngest-workflow.test.sh`) fires the production push apply on merge; see tasks 5.1-5.3.

## Phase 0 — RED first

- 0.1 Write the scanner `scripts/lint-hcloud-token-readonly-no-fallback.sh` and the suite
  `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` per the plan's Guard 1 (write the suite
  first: instrument controls, matrix M1-M11, real-tree row L1, population-copy row L2, controls C1-C3;
  seams `HCLOUD_SCAN_ROOT` and `HCLOUD_SCAN_TODAY`; refusal of inherited seams under `GITHUB_ACTIONS`;
  the trio event and diff-touch decision for the expiry).
  - 0.1.1 Run on the unmodified tree: RED with exactly one F-literal finding (~l.568). Save the output.
  - 0.1.2 List the first live run's findings over the inverted population; if either non-literal arm
    hits an unrelated site, fall back to the same-line arm only and record the blind spot in the header.
- 0.2 Rewrite the assertions in `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (bait stub
  keyed on the name; the "no token resolved", "announced by NAME", "names the variable that was sent"
  and "falls back ... only after an empty read-only read" assertions; `http401 both`); run: RED.
- 0.3 Update `tests/scripts/test-argv-bearer-sweep.sh` (`empty-warning` text and the `warning-dropped`
  mutant's from-text and to-text); run the `lead (a1)` rows: RED.

## Phase 1 — GREEN: the script

- 1.1 Rewrite the comment block l.547-561 (facts as of 2026-10-23; leave l.477 and l.562 alone).
- 1.2 Remove `tokvar`, the fallback read and both notices; literal variable name in the shape and
  401/403 warnings; the empty-token warning names `HCLOUD_TOKEN_READONLY` and step O5.
- 1.3 `bash -n` and the shell lint for `scripts/cutover-inngest.sh`.

## Phase 2 — tests green

- 2.1 `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` green; the `rw` block goes RED
  when the SUT's bare read is respelled with reordered flags.
- 2.2 `lead (a1)` and `bk` rows of `tests/scripts/test-argv-bearer-sweep.sh` green.
- 2.3 The scanner green on the live tree (L1) and RED on the pre-change shape (L2).

## Phase 3 — documentation

- 3.1 `runbooks/inngest-server.md` (the "names which variable was sent" clause and the "today that is
  the read/write HCLOUD_TOKEN" paragraph), rewritten in place.
- 3.2 ADR-225: item 4 stays; add the "[Superseded 2026-10-23, see Amendment below]" bracket and append
  a dated `#### Amendment — 2026-10-23` block.
- 3.3 ADR-241: `*(Superseded 2026-10-23 ...)*` pointer on the "Left open" bullet and a new dated entry
  (no `Allow:`, `Re-date:` or `Reclass:` tokens).
- 3.4 `runbooks/infra-credential-tiers-8209.md`: generation-anchor row, step 4, one pointer sentence.
- 3.5 `model.c4` `github -> hetzner` clause; commit through the hook so `model.likec4.json`
  regenerates (never hand-edit; if the hook cannot run, stop and report); run the two C4 tests;
  `git grep -n 'until it is minted' -- knowledge-base/engineering/architecture/diagrams/` is empty.
- 3.6 Run the plan's sweep command (with `silent fallback`); classify every hit; fix the current-state
  ones (ADR-282 l.198 if it classifies as false); record the fixed ones for the PR body.

## Phase 4 — register and verify

- 4.1 `run_suite` line in `scripts/test-all.sh`.
- 4.2 `ALWAYS_ON_SUITES` entry (no-tofu-ssh comment style) in `scripts/lib/test-affected-paths.sh`;
  `scripts/lint-orphan-test-suites.sh`, `scripts/test-all-affected.test.sh`, and
  `scripts/test-all.sh --print-selection --paths=<scanner path>` lists the new label.
- 4.3 Shard manifest: predict no TSV change; do not run `--write`; run
  `plugins/soleur/test/scripts-shard-totality.test.sh` and
  `.github/scripts/test/test-infra-suite-registration.sh`.
- 4.4 Time the scanner (probe; target under 5 s) and run `scripts/lint-shell-trace-credential-refusal.py`
  and `scripts/lint-trap-tempfile-ownership.py` on the new files.
- 4.5 Markdownlint on the touched docs; confirm the diff-scope AC.

## Phase 5 — ship hand-off

- 5.1 PR body: first line says merging fires the web-platform apply, release and infra-validation
  workflows and that the apply is suppressed by the kill switch; `Ref #10664`; RED output of 0.1.1;
  first live scanner findings; fixed sweep hits; open items (flip-guard retention comment,
  `op=backup`); the operator item about the brief's constraint; ends with the `Generated with Claude
  Code` line; commits carry the `Co-Authored-By: Claude Sonnet 5.5` trailer.
- 5.2 Merge with an explicit squash body that carries the exact own-line `[skip-web-platform-apply]`.
- 5.3 Post-merge: read the `apply-web-platform-infra.yml` run and confirm preflight `skip=true`; read the
  `web-platform-release.yml` run and record it as an unchanged-code rebuild with no Tier-B or
  version-bump side effect beyond the normal release.
- 5.4 Split the Site C checkbox on #10664 with `gh issue edit` so the flip-guard retention-comment
  sub-item stays open.
