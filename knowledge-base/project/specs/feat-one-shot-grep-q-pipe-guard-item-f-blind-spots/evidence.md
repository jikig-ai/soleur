# Evidence: grep -q pipe-guard, Item F (guard blind spots)

Branch `feat-one-shot-grep-q-pipe-guard-item-f-blind-spots`, draft PR #10327, tracker #9217 (`Ref`, never `Closes`). Measured 2026-10-15 on the branch merged with `origin/main` at `30407a8597`. Each figure carries its command; counts rot, so re-measure before quoting one.

## Phase 0 (read-only, before any guard edit)

| What | Command | Result |
|---|---|---|
| Base guard at merged main | `bash .claude/hooks/grep-q-pipe-guard.test.sh` | exit 0; `1862 files swept`; join `151 derived pairs, 264 producer triples; 23 of 23 drains rows, 129 exempt rows, 152 of 152 rows`; wall time 1m19s at load average 55 (18.6 s at load 7 at plan time) |
| Reader classification over the swept population | `python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-f-blind-spots/j0-measure.py` | 1,858 files (plan time) / same classes: awk-exit 41 single-line + 13 multi-line, `head -N` 575 `head -1` + 179 other, `read` 3, variable binary with an early flag 1 (a `-hmac`, not a reader), without 709; 25 functions with a stdin early-exit grep body |
| Widened pattern, live tree | `bash knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-f-blind-spots/j0-pattern-prototype.sh` | `shipped=33 widened=33` (0 only in the widened set); fixture table ok; the two stated false positives (`grep -c p -eq`, `xargs echo grep -q p`) still match |
| Marker census | `git -c core.excludesFile=/dev/null grep --no-index --exclude-standard -c -E '<ALLOW_MARKER>' -- <SWEEP_PATHSPEC>` | 25 marked lines in 12 files outside knowledge-base, guard excluded (matches the plan's 25 / 12) |
| Open-PR screen | `bash /var/tmp/itemf/pr-screen.sh` (added lines of each open PR in a newly read file class, widened pattern) | 25 PRs with files in a newly read class, 0 added-line hits (the only matches printed were this branch's own `.txt` fixtures, which are not swept) |

Reconciliation with the plan-time figures: no difference. The brief's guard figures (150 / 263 / 151) were one merge stale; the plan's base figures (151 / 264 / 152) are the merged tree's own. Join figures move only with main (#10322, #10081 edit the join table and `PJ_TRIPLES`).

## Notes carried forward

- The guard takes about 80 s at the load this host reaches during the full-gate queue; a wall-time claim needs `uptime` beside it.
- `scan_split` finds 8 trailing-bar logical lines whose joined text holds a reader stage by the classifier's loose test; the guard's own pass applies the widened pattern to the joined line, so the figure that matters is the guard's `split` result, recorded in the red-first and green runs below.
- Self-sweep (task 0.5): the widened pattern over every script in this spec dir (`*.sh`, `*.py`, `*.awk`) reports 0 lines; fixtures stay in `.txt` data and mutants are built with `printf`.
