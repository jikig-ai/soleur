# PR4c handoff notes for PR5 (#10861)

Companion of `handoff-pr5-deferred-sweep.tsv` (the 43 whole-tree reads) and `edges-decisions.tsv` (one row per worklist edge). Written at review time, 2026-10-26; the numbers are as of origin/main `39ba94781f`.

## What PR5 inherits and how to list it

`awk -F'\t' 'NR>1 && $3!="declare"' receipts/edges-decisions.tsv` lists every worklist edge PR4c did not declare (column 3 outcome, column 4 reason; the reason prefix is the code). The glob-reader and accept-row items below are not rows of that table.

## 1. A glob reader PR4c only partly expresses: `plugins/soleur/test/boundary-prefix.test.sh`

The suite awk-scans four directory globs (`.claude/hooks/*.sh`, `.claude/hooks/lib/*.sh`, `plugins/soleur/scripts/*.sh`, `plugins/soleur/scripts/lib/*.sh`, `boundary-prefix.test.sh:285-299`, about 164 files; the recorder opened 168). PR4c declares 4 hook files as exact entries plus 3 library/hook files the glob opens; the audit sees only literally named paths, so the rest of the glob stays unmodelled and a new hook file would not select the suite after the lever flips. The one baselined pair that matters most, `boundary-prefix -> .claude/hooks/guardrails.sh`, is `held-hot` (13 commits) and the suite's EXEMPTIONS are keyed to line numbers in that file. PR5 evaluates a `glob:` edge for this suite under the PR4b row 6 policy (which would also cover the held `guardrails.sh` edge). The `glob:` decision stays in PR5 (CTO row 7).

## 2. Accept rows to re-read before any flip

An accept row is keyed to the mention line, not to how the suite uses the file. Before the lever flips, re-read the suite behind each accept row of kind `code line in a file read only as text` (4 rows), `data row not fed to a read loop` (6 rows) and `message` (the rest) and confirm the suite still does not `source`, execute or open the named path: a later edit that makes `boundary-prefix.test.sh` source `.claude/hooks/lib/incidents.sh` would turn the `scripts/lib/rule-metrics-constants.sh` row into a hidden real read. The recorder rows are in `retest/recorder-table.tsv`.

## 3. A dropped edge and why (review finding)

`tests/scripts/git-data-rung2-evidence-capture -> scripts/followthroughs/git-data-rung2-evidence-capture.sh` was declared in the first cut and dropped at review: the script is the suite's SUT, but it reaches `apps/web-platform/infra/cloud-init-git-data.yml` only through its default (`git-data-rung2-evidence-capture.sh:126`) and every suite arm passes `--cloud-init "$FIX/cloud-init-git-data.yml"` (a fixture written at `test-git-data-rung2-evidence-capture.sh:73-90`). That pair is therefore not a real read, an accept row for it would sit on a hot file (15 commits), and the unsure rule holds the whole edge (`real-read-unproven`). PR5 can reopen it with evidence that a suite arm reads the real file.

## 4. Knife-edge numbers to re-count when PR5 starts

`scripts/betterstack-query.sh` has exactly 8 commits in 90 days (not hot; PR4b counted 9, the 9th aged out of the window) and carries 3 accept rows of the rung2 edge; one new commit in the window makes it hot. `.claude/hooks/git-commit-secret-scan.sh` carries exactly 10 accept rows (the limit is "more than 10").

## 5. Hot-file budget heuristic

The exception of CTO row 4 was not used in PR4c. Counting for a future use: baselined consumers count as declaring suites (for example `scripts/betterstack-emitter-read` still has a baselined pair to the rung2 script, so that file's product is 15 x 2 = 30, not 15 x 1).
