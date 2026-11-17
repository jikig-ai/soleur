---
title: "A verified drain is a snapshot — a fix round that adds path-naming code to an audited suite reopens the boundary debt it just closed"
date: 2026-11-07
status: active
category: testing
tags: [guard-shaped-pr, accept-file, boundary-drift, review-fix-round, qa-gate]
related: [10859, 12329]
---

## The defect

PR #12329's verification pass drained the affected-index census to `live=0` (accept=3136). The review fix round that followed added five `_wf` job-wiring pins to `scripts/ci-oracle-review.test.sh` — including line 426's awk extraction that REALLY READS `.github/workflows/ci.yml`. That one line created a new uncovered boundary ref on TWO pairs and re-reddened the ratchet (`exit=1 reason=new-pair live=2`) on a tree everyone believed was drained — the QA phase caught it only because it re-ran the gate on the post-fix tree instead of trusting the earlier verification receipt. The same sweep caught a second drain surface the verification had never run: `scripts/test-affected-kb-consumers.baseline.txt` lacked the unreachability suite's `weakness-digest.md` argv-code literal (:92).

Three subtleties the repair surfaced:

- **One real-read ref makes the whole pair an edge.** Every sibling ref of `(scripts/ci-oracle-review → ci.yml)` was naming-only with an accept row; the new :426 awk genuinely opens ci.yml, so the pair takes an `AFFECTED_` edge — and the existing accept row for the naming-only :98 ref goes `stale-accept` the moment the edge lands (delete it in the same edit).
- **A derived edge makes a sibling suite read your file as text.** The unreachability suite never opens ci.yml, but the derive granted it `^scripts/ci-oracle-review.test.sh`, so the naming walk reads the test file as text and its :426 code line becomes a boundary ref for `(unreachability → ci.yml)` — drained by a typed-kind accept row (`code line in a file read only as text`), not an edge.
- **The `accept-unattributed` verdict diffs `HEAD^1..HEAD`.** Worktree edits are invisible to it: the drain had to be committed before the verdict could see that an oracle input (`test-affected-paths.sh`) was touched. A red `accept-unattributed` on uncommitted drain work is expected, not a second defect.

## The rule

- A drain (edge, accept row, kb-consumers baseline row) covers boundary lines of a suite's TEXT at a commit. Any later edit that adds a path-naming line to that suite — exactly what fix rounds do when they add structural pins — mints uncovered refs. Re-run the ratchet AND `test-affected-kb-consumers.test.sh` after every fix-round commit that touches an audited suite, not only at the initial verification. The last writer of audited-suite code owns the re-drain; otherwise the QA phase inherits it.
- "Verification-clean" certifies the tree AT that commit. A fix round between verification and QA is the highest-risk window for boundary drift — the fix's own additions are the least-audited code in the PR (same seat as the chk() vacuity class in `2026-11-07-a-pin-whose-harness-runs-only-arg-two-passes-vacuously.md`).
- Never reach for an accept row to silence a boundary that is a real read — the ratchet's own remedy calls that the false negative the lever exists to expose. Real read ⇒ edge; text-only ⇒ typed-kind accept row keyed on the ref's anchor.
- Drain-shaped commits must themselves satisfy `accept-unattributed`: touch the named path, a file that references the pair, or an oracle input other than the accept file — and commit before re-running the gate.

## Session Errors

1. Injected a literal `</antml :parameter>` token into `scripts/ci-pr-affected-audit.accept.tsv` mid-edit (tool-call formatting slip); caught by the post-edit `cat -n` echo, removed next edit. **Prevention:** after editing a structured data file, `git diff` it before moving on — the stray token would have failed `accept_rows`' 5-column check had it survived to a ratchet run.
2. First `ratchet` run measured `tail`'s exit code through a pipe (`| tail -8; echo $?`) — the marker line carried the truth (`exit=1`), but the shell reported 0. **Prevention:** for marker-emitting checks read the marker, or capture the real rc via `PIPESTATUS`/redirect-to-file before truncating output.
3. First `audit` run (no `--accept`) reported 261 gap suites / 1620 gap refs — pre-exemption output, not a regression; confirmed by `live=0` under the accept file. **Prevention:** run `ratchet` (the gate) before `audit` (the census viewer) when checking drain state.

## Evidence

QA-phase fix commits `4f9dbcd8c3` (edge for `ci-oracle-review → ci.yml`, delete stale `709bb11119fc` row, add `6d5f6cb5284c` typed-kind row — `exit=1 live=2` → `exit=0 reason=pass live=0 baseline=0 accept=3158`) and `de348b8a70` (kb-consumers baseline `--write-baseline`, 31/31). The refs: `scripts/ci-oracle-review.test.sh:98` (naming-only, accept-row kind `data row not fed to a read loop`), `:426` (real read, the `87a3af2614`/`46ea4d9d69` fix-round `_wf` pin).
