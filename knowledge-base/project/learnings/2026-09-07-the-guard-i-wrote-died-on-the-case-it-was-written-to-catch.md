---
title: The guard I wrote died on the case it was written to catch
date: 2026-09-07
issue: 7798
pr: 7878
tags: [testing, shell, errexit, ship, ci, verification]
category: workflow-issues
---

# The guard I wrote died on the case it was written to catch

`/compound` runs before `/ship`, so none of these reached the #7798 learning.
They all happened during ship.

## 1. The guard aborted on the only input it existed to detect

`www-apex-canonicalizer.test.sh` gained a W14 cross-read asserting that
`cutover-verify.sh`'s `SENTRY_MONITORS` array names exactly the declared Sentry
uptime monitors. It captured:

```bash
ARRAY_NAMES="$(... | tr ' ' '\n' | grep -v '^$' | sort -u | paste -sd',' -)"
```

The file runs under `set -euo pipefail`. A `grep` that matches nothing exits 1,
pipefail promotes that to the pipeline's status, and errexit kills the script
*inside the command substitution*.

The no-match case is reached **exactly when `SENTRY_MONITORS=(` has been renamed
or removed** — the single condition W14 was added to detect. So the assertion
aborted the run instead of reporting a clean FAIL.

It passed 41/41 locally and on CI's `deploy-script-tests`, because on a healthy
tree the grep matches. **No green run could have surfaced it**; only the failing
tree takes the bad path. `scripts/lint-shell-capture-exit.py` caught it, because
it reads the SHAPE rather than an execution.

This is the same defect class as the monitor #7798 exists to repair — a check
that cannot report the condition it was written to catch — reproduced inside the
guard written to prove the repair.

**Prevention:** in any file with `set -e`/`pipefail`, a capture whose pipeline
ends in `grep`/`diff`/`test` is a latent abort. Prefer a form whose "no match" is
a normal exit — `awk 'NF'` over `grep -v` on empty lines — rather than
`|| true`, which also swallows genuine failures upstream. And when writing an
assertion, ask which input makes it FAIL and confirm the harness survives long
enough to report it.

## 2. A `Closes #N` buried in a commit body nearly auto-closed the issue

The repo is `squash_merge_commit_message: COMMIT_MESSAGES`, so the squash body is
built from branch commit messages and GitHub's parser reads them.
A `Closes #7798` sat in commit `e06329cba`'s body, nine commits deep. The PR body was
clean; the merge would still have closed the issue on an unverified promise —
the #6537 shape exactly.

**Prevention:** the ship auto-close scan must run over `git log origin/main..HEAD
--format=%B`, not just the PR body — it already says so, and this is the case
that proves why. Fixing it means rewording the commit (verify the resulting tree
is byte-identical), not editing the PR body.

## 3. I reported a background job's state 1.5 s after launching it

Relaunched the full gate after #7870 landed, saw no rc file at 1.5 s, and said
"#7870's fix appears to have let it through". It had already refused (`rc=4`,
3 live siblings); the file simply had not been written yet.

**Prevention:** absence of a result file is not a result. Either wait for the
terminal marker or say "not yet known" — never read "no answer yet" as an answer,
least of all as confirmation of a hypothesis you were hoping for.

## 4. A process-pattern kill matched my own shell

Killing by full-command-line pattern took out the very Bash call issuing it,
because that call's own command line contains the pattern. Exit 144.

**Prevention:** enumerate PIDs and skip the current shell, or use the repo's
`plugins/soleur/scripts/lib/proc.sh` helpers (`list_runs`, `kill_mine`), which
establish ownership via `/proc/<pid>/cwd` instead of pattern-matching argv.
`main` landed `.claude/hooks/pkill-self-match-guard.sh` for this class the same
day — and that hook then blocked this very learning from being written by
heredoc, because the prose quotes the pattern. Write such a file with the Write
tool rather than fighting the guard; the guard is right and the prose is data.

## 5. Two near-misses where a tool's own warning was the real signal

- `comm -12` printed `comm: file 1 is not in sorted order` alongside a plausible
  overlap count. Re-measured with `grep -Fxf`; the count happened to agree, but
  it was luck. **Prevention:** a correctness warning invalidates the number
  printed beside it — re-measure, do not eyeball whether it "looks right".
- Ran `lint-shell-capture-exit.py` bare and got `206 NEW findings`, which is the
  whole baselined corpus. The real invocation (`--baseline …`) is in
  `scripts/test-all.sh`. **Prevention:** replay CI's exact invocation from the
  runner script rather than inventing one; a linter's bare default is rarely the
  gate's contract.

## 6. Ordering note that held up: `Ref`, not `Closes`

The plan's Risks table accepted `Closes #7798` with "AC25 re-opens it if
verification fails" as mitigation. That mitigation *is* the remediation the rule
exists to prevent. Using `Ref` and closing by hand after the applies landed meant
the issue closed on live evidence — check rows flipping `failure` to `success`,
`WEB-PLATFORM-11` resolved, a 1380 s soak — instead of on a merge.

**Prevention:** when the proof of a fix lands post-merge, `Closes` is wrong even
when a plan blesses it. Keep the close in the hands of whoever can see the
evidence.

## 7. Merge-race note (no action, recorded for calibration)

The PR took ~2.5 h to merge across 8 poll rounds and 7 syncs, reaching
`pending=1` three times before `main` moved. Measured: `main` merges every
~36–46 min; the PR's CI cycle is ~35 min. The documented escape hatch
(settle-then-admin-merge) was **declined on measurement**: it requires zero
conflict surface, and an exact-match overlap of this branch's files against the
last 8 merges to `main` returned two real files (`review/SKILL.md`,
`work/SKILL.md`). They auto-merged cleanly every time, but "merged cleanly so
far" is not the criterion.

**Prevention:** decide the admin-merge question by measuring file overlap against
recent merges, not by reasoning about file *types*.
