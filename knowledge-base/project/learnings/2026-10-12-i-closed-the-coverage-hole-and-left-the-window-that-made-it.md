# Learning: I closed the coverage hole and left the window that made it — an enumerated set is only true for the tree it was measured on

## Problem

#9969: three whole-tree corpus suites (`guard-vacuity-floor`, `lint-orphan-test-suites`,
`scripts/lib/repo-write-boundary.test.sh`) scanned every `*.test.sh`/`*.sh` via `git ls-files`
but declared affected edges only for the roots holding suites today. A corpus file under
`knowledge-base/`, `bin/`, `infra/`, `docs/` or ten other roots was scanned, moved the verdict,
and never selected the suite locally — silent under-coverage with a green gate.

The fix itself was data: `glob:<root>/**.test.sh` ×13 appended to the two `*.test.sh` arrays,
a new `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS` of `glob:<root>/**.sh` ×20
(the #9945 disposition — keep honest prefixes, glob the gaps). What the review panel then
showed is that the *shape of the fix is the shape of the defect*: a hand-enumerated root set
is a window, and every later finding was a way a member could slip outside it.

## Solution

- **Re-derive, never restate.** `_TH_ROOTS=$(git -C "$REPO_ROOT" -c core.quotePath=false
  ls-files | awk -F/ 'NF>1{print $1}' | sort -u)` drives ALL of: th4's per-root `.test.sh`
  probes, th4b's `.sh` probes, th4c's `.md` decline probes, and th6's exists→declared census.
  A new top-level dir joins every probe automatically AND fails the census — in CI, where the
  full gate runs (the affected selector is local-only, so a check living in a suite that
  declines cannot fire locally; the battery row is the enforcement point, not a redundancy).
- **A member under a root is not root coverage.** Three independent fix-round seats caught
  `[[ "$_m" == "$root/"* ]]` accepting `scripts/test-all.sh` — a file literal that selects
  itself and nothing else — as "covering" `scripts`. The tightened predicate requires the
  exact `root/` dir prefix or a `glob:root/*<corpus-tail>` edge, tail-anchored so
  `glob:docs/**.md` can't satisfy a `.test.sh` census.
- **Expectations key on deliberate literals, never on the data under test.** The listed vs
  unlisted split for th4b/th4c reads `_TH_PREFIX_ROOTS` (a literal set of the 7 legacy prefix
  roots), not the arrays — a dropped prefix must flip the expectation and RED, not silently
  re-derive to green.
- **A decline verdict must bind to the keep-list.** th7 windows the injected case block out
  of the built sandbox and greps each asserted label anchored on case delimiters
  (`label|`/`label)` — substring presence is not membership.
- **Non-vacuity everywhere a derivation feeds an assert.** th6 emits an
  `EMPTY-ROOT-DERIVATION` sentinel into its own miss set; an enumeration that produces
  nothing must never read as a clean census (the sibling producer's own arm carries the
  same guard).

## Key Insight

1. **"Verified read set" is a property, not a comment.** The plan's method — verify each
   suite's actual discovery corpus before choosing edges — only holds if something re-checks
   the enumeration. The issue fixed 13 missing roots; the review found the fourteenth failure
   mode (the next root) and the fifteenth (a literal pretending to be coverage). The guard's
   assembly now equals its named property for the tree it measures AND trips on the tree
   changing.
2. **Literal counts are the corpus's shadow — they move when the family grows.** p1's
   `selected=8 of=13` became `10 of=16`, tg6's `want 5` became `6`, `_TG_ALL_SIX` became
   `_TG_ALL_SEVEN`, MIN_CASES 115→125→156→178, "five `glob:` siblings" became six. Every one
   of these was a count literal pinned to yesterday's family — the same under-count class
   #9969 itself fixes, one level down, and five seats each found a different one.
3. **Editing a file a running `bash` process reads is a self-inflicted corruption vector.**
   Bash reads scripts lazily by byte offset; two mid-run edits to `test-all-affected.test.sh`
   forced kills + restarts (~40 min), and a session reaping shells killed a third run mid-tail.
   Long batteries run under `setsid nohup` and get edited between runs, never during.

## Session Errors

1. **`edit`-tool hook ENOENT — `security_reminder_hook.py` doesn't exist under the bare repo
   root this worktree resolves to.** Recovery: applied all edits via `python3` heredocs.
   **Prevention:** in a worktree session, treat dedicated file-edit tools as potentially
   hook-broken; verify with a small edit first or default to heredocs. (Recurring env defect —
   worth a follow-up to whoever owns the hook's worktree-path resolution.)
2. **p1/p4 corpus-count literals RED after the keep-list grew by 3.** Recovery: recomputed
   `selected=10 of=16 ... edge=9`, updated, battery confirmed. **Prevention:** when a diff
   grows a counted family, grep every literal count in the same file before running — the
   rows did their job, but the fix-forward cost a 20-min battery leg.
3. **tg6 `want 5` went stale when rwb's `**.sh` edge joined the receipt family.** Recovery:
   `want 6` + message/comment updates. **Prevention:** same as #2 — a receipt row that counts
   family members must be re-derived when the family changes, ideally by construction.
4. **Edited `test-all-affected.test.sh` twice while the battery read it lazily — in-flight run
   corrupted.** Recovery: killed and restarted on the fixed file. **Prevention:** never edit a
   file a running `bash` process executes; kill the run first or defer the edit.
5. **Normal `git push` rejected `stale info` after rebase.** Recovery: `--force-with-lease`
   against the remote-tracking ref. **Prevention:** after a rebase, expect the lease dance —
   check `git rev-list origin/<branch>..HEAD` before assuming divergence.
6. **`git rebase --continue` hung — `nvim` opened on the commit message in a non-interactive
   session.** Recovery: killed the editor, `GIT_EDITOR=true git rebase --continue`.
   **Prevention:** always set `GIT_EDITOR=true` (or `-c core.editor=true`) for scripted rebase
   flows in this harness.
7. **`gh api` milestone enumeration hit a 403 rate limit.** Recovery: `gh issue view` supplied
   the milestone name instead. **Prevention:** prefer a targeted `gh issue view`/`gh pr view`
   over `gh api` list endpoints when rate-limited; the data needed was on the sibling issue.
8. **Background battery reaped with the shell session at ~case 168.** Recovery: restarted
   under `setsid nohup`. **Prevention:** any verification expected to outlive a turn boundary
   gets `setsid nohup` from the start, not a second try.
9. **Stale `index.lock` left by the reaped git process.** Recovery: verified no live git in
   the worktree, removed it, committed. **Prevention:** after a killed git command, check for
   `$GIT_DIR/index.lock` before the next index operation.
10. **`emit-review-trailer.sh --fix-round` emitted `Reviewed-Fix-Round: unknown` without seat
    args.** Recovery: `git reset --soft`, re-emitted with `--agents-ran 7 --agents-expected 7`
    (and the never-emitted main-panel trailer). **Prevention:** the script's usage string says
    it plainly — pass seat counts on the first call, both trailers.
11. **Forwarded from the plan phase:** `gh pr view --json merged` invalid field (→`mergedAt`);
    `--print-selection --paths=…` exceeded the 60s check cap (→grep probe); one stale
    `old_string` edit (→re-read + wider context). **Prevention:** verify JSON field names
    against `gh pr view --json` docs; bound real-runner calls in premise probes; re-read
    before re-editing.

## Tags

affected-test-selection, glob-edges, whole-tree-corpus, enumerated-set-drift,
live-derivation, coverage-predicate, keep-list-binding, non-vacuity-floor,
review-fix-round, bash-lazy-read, sandbox-fixtures

## See also

- `knowledge-base/project/learnings/2026-10-11-the-fix-landed-green-and-left-its-own-pin-red.md` —
  a fix changing the mechanism's emit surface orphans its pins; the same class in reverse
  (here the mechanism stayed, the corpus enumeration went stale).
- `knowledge-base/project/plans/2026-10-12-fix-affected-edges-under-cover-siblings-plan.md` —
  the disposition-table method and Guard Contract this session executed.
- Issue #10117 — filed residuals: `covers()` dir-ref tail-blindness, root-anchored grammar,
  `--paths` `./` normalization.
