---
title: "fix(hooks): grep-q-pipe-guard flags '|| grep -q' on herestring lines (false positive)"
type: fix
date: 2026-09-25
slug: fix-grep-q-pipe-guard-or-false-positive
branch: feat-one-shot-8807-grep-q-pipe-guard-or-fp
issue: 8807
closes: 8807
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(hooks): grep-q-pipe-guard stops reading a logical OR as a pipe

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

`.claude/hooks/grep-q-pipe-guard.test.sh` finds a pipe feeding `grep -q` with
`PATTERN='\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'`. The leading `\|` also matches the
second bar of `||`. As a result, the indented continuation line `|| grep -qE 'p2' <<<"$b"; then`
is reported, although it has no pipe and already uses the safe herestring form. That false
positive cost PR #8779 a full CI round.

The fix puts `(^|[^|])` in front of the bar, so only a single `|` counts. It also adds `&?`, so
`|&` (a real pipe that also carries stderr, with the same SIGPIPE exposure) is caught. The
non-vacuity probe gets must-NOT-match lines for `||`, per-line must-match checks, and a non-empty
floor on both probe files.

Class coverage: the one other copy of this regex whose `||` false positive can red a CI check in
this PR's scope (`tests/scripts/test-lint-supabase-deprecated-endpoints.sh` row 10, 2 lines) gets
the same prefix. The two copies under `apps/web-platform/infra/` are dispositioned separately
(see the class sweep table): one is already `||`-normalised, and one is deferred to #8869. The
reason for the deferral is that any infra-path edit triggers the production apply workflow on
merge.

Total change: 2 files, about 3 regex lines plus about 10 probe lines.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (measured 2026-09-25) | Plan response |
|---|---|---|
| `PATTERN='\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'` at about line 52 | Holds (`.claude/hooks/grep-q-pipe-guard.test.sh`, the `PATTERN=` assignment). The file is identical on HEAD and `origin/main` `eb11a33894` | Edit it in place |
| "A merged sibling (2026-09-25) added a FILES_8664 block that consumes `$PATTERN`" | **Stale.** The block exists only on PR **#8848** (`feat-one-shot-8664-zot-pull-mutation-misroute`), which is an **OPEN draft** and not merged. `git grep FILES_8664 origin/main` finds nothing. Its hunk inserts 28 lines between the `#7024` PASS/FAIL block and the `# Non-vacuity:` comment | Leave the `# Non-vacuity:` comment, the `probe=` line and the `trap` line untouched so either merge order rebases cleanly. The new PATTERN only drops `\|\|` hits and adds `\|&` hits. The repo has 0 `\|&`-into-`grep -q` lines, and the #8848 files score 4 → 4 on main-tree content, so the change cannot flip #8848's result |
| "There is a non-vacuity probe section below it" | Holds: one-line `bad.sh`/`good.sh`, checked with any-line `grep -qE` | Replace with multi-line probes, per-line checks, and non-empty floors (Phase 1) |
| pkill-self-match-guard may reuse the regex | **No.** `.claude/hooks/pkill-self-match-guard.sh` tokenizes the command, and its pipeline walk already stops at `\|\|` (`# \`\|\|\` ends the pipeline`). It has no regex copy | Nothing to fix |

## Research Insights

### Premise validation (Phase 0.6)

- #8807 is OPEN. Nothing has fixed it yet.
- #8779 (where the bug fired) is MERGED. The hooks tree has **0** `||`-then-`grep -q` lines today (`git grep -nE '\|\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' -- '.claude/hooks/*.sh' '.claude/hooks/lib/*.sh' \| grep -vE '\.test\.sh' \| wc -l` returns 0), so #8779 rewrote correct code to get past it. The bug is **latent**: it will bite the next contributor.
- #7005 (the wider pipefail sweep of `scripts/`/`plugins/`) is OPEN and not affected.
- #8848 is an OPEN draft (conflict analysis in the reconciliation table above).
- No ADR governs this guard's regex.

### Property list (Phase 0.6b)

- **P1**: a line where `grep -q…` follows a logical OR (`||`) is not reported.
- **P2**: a line where a single pipe feeds `grep -…q…` is still reported. That covers `|` with or without a preceding space, `|` at the start of a continuation line, and `|&`.
- **P3**: the non-vacuity probe fails if the pattern loses P1 or P2 on any probe line, not only the first one. It also fails if either probe file is empty.
- **P4**: every pipe-into-`grep -q` detector whose `||` false positive can red CI is anchored, or is dispositioned with a reason.

### Cut list (Phase 0.6b and plan review)

- **A shared regex library, or a parity assertion that pins the sibling copies** → cut. The copies live in different trees and CI shards. A pin covers only the 4 known members and would never see the next detector someone writes. AC5 is a census grep at merge time instead.
- **Running the probe through `git grep --no-index` (engine parity with the sweeps)** → cut at plan review (DHH + simplicity). The sweeps pass `-E` on the command line, which overrides `grep.patternType`. GNU `grep -E` and `git grep -E` agreed on every probe line (measured with git 2.55.0). The only scenario it defends is a hypothetical future move to `-P`. The existing file already probes with plain `grep -E`.
- **Per-line count, `wc -l` floor, and FAIL-arm line listing** → replaced (simplicity review). `! grep -qvE "$PATTERN" bad.sh` means every bad line matches. `[[ -s ]]` is the non-empty floor on both files and is not tied to a line count. The FAIL arm keeps the existing count lines.
- **The indented-continuation and `a ||grep` probe lines** → cut. The first goes through the same `[^|]` path as the canonical line. The second repeats the `||` probe.
- **Editing `apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh` `SHAPE=`** → cut (Kieran). Its normalisation step 5 already rewrites `||` to `__OR__` before counting real sites. The script's header says outright that a `\|` regex cannot tell them apart. Real-site counts are unchanged by the anchor (429 → 429 on `apps/web-platform/infra/`), so an edit would only shift a raw figure the script reports on purpose.
- **Editing `apps/web-platform/infra/workspaces-luks-verify-root-mtime.test.sh` A3-nopipe now** → deferred to **#8869** (CTO). Its exposure is 0 today. Any `apps/web-platform/infra/**` edit fires `apply-web-platform-infra.yml` on push to main (its `paths:` filter, verified), and a one-token test edit should not queue a production apply by itself.
- **Multi-line pipes** (`producer |⏎ grep -q`, `producer | \⏎ grep -q`) → out of scope. See Sharp Edges.

### Measured regex behavior (GNU `grep -E` and `git grep -E` agree, git 2.55.0)

OLD = `\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q`. NEW = `(^|[^|])\|&?[[:space:]]*grep[[:space:]]+-[A-Za-z]*q`.

| Line | OLD | NEW | Want |
|---|---|---|---|
| `echo "$x" \| grep -qE 'p'` | match | match | match |
| `echo "$x"\|grep -qE 'p'` (no spaces) | match | match | match |
| `\| grep -q x` (continuation at column 0) | match | match | match |
| `␣␣\| grep -q x` (indented continuation) | match | match | match |
| `a \|& grep -q p` | **miss** | match | match |
| `grep -qE 'p' <<<"$x"` | – | – | no |
| `a \|\| grep -qE p <<<"$x"` | **match** | – | no |
| `␣␣␣␣␣\|\| grep -qE 'p2' <<<"$b"; then` (the issue's line; `␣` marks a leading space) | **match** | – | no |
| `a \|\|grep -q p <<<"$x"` | **match** | – | no |
| `a \|\| b \| grep -q x` | match | match | match |
| `a \| \| grep -q p` (a bash syntax error) | match | match | harmless |

### Sweep results under NEW

- Hooks sweep: 0 → 0. #7024 pass: 0 → 0. The suite runs in 0.12 s.
- `|&` into `grep -q` in tracked `*.sh`: 0 lines, so `&?` adds no new reds.

### Class sweep (P4): every copy of the regex in executable code

Census command: `git grep -nE "'\\\\\|(\[\[:space:\]\]\*| \*)grep" -- ':!knowledge-base'`. It finds a single-quoted `\|` directly followed by a space class and `grep`. Today it returns exactly 5 lines at 4 sites:

| Site (content anchor) | Role | `\|\|` false positive live? | Disposition |
|---|---|---|---|
| `.claude/hooks/grep-q-pipe-guard.test.sh` `PATTERN=` | required CI gate (test-scripts shard) | latent (0 hits today; fired on #8779) | **fix** + probes |
| `tests/scripts/test-lint-supabase-deprecated-endpoints.sh` row 10 `qpipe_hits` loop (the `grep -cE` count line and the `grep -E` report line) | CI gate over 2 files | latent (0) | **fix** both lines (same literal). On the report line, `[^\|]` matches the `N:` prefix that `grep -n` adds |
| `apps/web-platform/infra/workspaces-luks-verify-root-mtime.test.sh` `A3-nopipe` | CI gate over one function body | latent (0) | **defer → #8869** (an infra-path edit fires the prod apply on merge) |
| `apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh` `SHAPE=` | triage measurement probe | none: normalisation step 5 already turns `\|\|` into `__OR__` | **acknowledge, unchanged** |

Not in the class: `workspaces-luks-freeze.test.sh` AC5 (`lsof.*\| *grep`) is an lsof-anchored check, not a `grep -q` detector, and has 0 exposure. `registry-luks.test.sh`, `deploy-arm.test.sh` and `scan-workflow-mutation.test.sh` are literal content assertions, not detectors.

### Institutional learnings applied

- `cq-assert-anchor-not-bare-token`: anchor on the pipe *operator*, not on a bare `|` character.
- 2026-08-13, "every guard I shipped was satisfiable by a guard that asserts nothing": both probe files need a non-empty floor (for `good.sh` this was a Kieran plan-review finding). The must-match side is checked per line with `! grep -qv`, because any-line `grep -q` cannot see a pattern that fails on line 2 or later.
- `cq-write-failing-tests-before`: write the probes first, confirm they go RED under the old PATTERN, then change the PATTERN.
- The learnings-researcher suggested `(^\||\|\|)`. That is wrong (it would *match* `||`), so it was rejected.

### Conventions

- The file header's scope rule stays: grow the pathspec by naming files, never by widening a glob. This change touches only the regex and the probes.
- Comments cite issue numbers (`#8807`), matching the existing `#6992`/`#7024` style.

### Discovery phases

- Community discovery (1.5) and functional overlap (1.5b): skipped. This is a one-token fix to an internal test regex, and no community artifact could hold it.
- External research (1.6b): skipped. POSIX ERE behavior was measured directly (table above).

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh`: the `PATTERN=` line and the comment above it; the probe body from the `printf … > "$probe/bad.sh"` line through the `fi` that closes the probe check. Leave the `# Non-vacuity:` comment, `probe="$(mktemp -d)"` and `trap` lines alone (#8848 context).
- `tests/scripts/test-lint-supabase-deprecated-endpoints.sh`: the two regex literals in the row-10 `qpipe_hits` loop.

## Files to Create

None.

## Implementation Phases

### Phase 1: RED first (probes before the pattern)

Replace the two single-line `printf` probes and the check with this block (quoted heredocs, so
nothing is expanded under `set -u`):

```bash
cat > "$probe/bad.sh" <<'EOF'
echo "$x" | grep -qE 'p'
echo "$x"|grep -qE 'p'
| grep -qE 'p'
echo "$x" |& grep -qE 'p'
EOF
cat > "$probe/good.sh" <<'EOF'
grep -qE 'p' <<<"$x"
a || grep -qE 'p' <<<"$x"
     || grep -qE 'p' <<<"$b"; then
EOF

# Every bad line must match (grep -v finds any that do not) and no good line may.
# Both files must be non-empty, or either half passes having checked nothing.
if [[ -s "$probe/bad.sh" && -s "$probe/good.sh" ]] \
   && ! grep -qvE "$PATTERN" "$probe/bad.sh" \
   && ! grep -qE "$PATTERN" "$probe/good.sh"; then
  echo "PASS: guard pattern matches the forbidden shapes and not the fixed shapes (incl. || herestrings, #8807)"
else
  FAIL=1
  echo "FAIL: guard pattern is broken — it cannot distinguish the shapes"
  echo "  forbidden lines matched: $(grep -cE "$PATTERN" "$probe/bad.sh" || true)/$(wc -l < "$probe/bad.sh") (want all)"
  echo "  fixed lines matched:     $(grep -cE "$PATTERN" "$probe/good.sh" || true) (want 0)"
fi
```

What each bad line is for:

1. The canonical pipe.
2. A pipe with no surrounding space. `[^|]` consumes the `"` in front of the bar.
3. A backslash-continuation line starting at column 0 (the `^` alternative).
4. `|&`.

The good lines:

1. The herestring.
2. The issue's must-NOT-match probe.
3. The issue's own indented continuation line, verbatim.

Run `bash .claude/hooks/grep-q-pipe-guard.test.sh` **with the old PATTERN**. It must exit 1 and
report `3/4` forbidden and `2` fixed (simulated at plan time: `bad=3/4 good=2`).

### Phase 2: GREEN (the pattern)

```bash
# Match a pipe feeding grep with a -q anywhere in its flag cluster (-q, -qE,
# -qiE, -qF, -qs...). Anchored on the pipe + grep + q so a comment that merely
# mentions the words cannot match. The pipe must be a SINGLE bar (`|` or `|&`)
# preceded by line start or a non-bar: without `(^|[^|])` the second bar of a
# logical OR (`a || grep -q p <<<"$x"`, already the safe form) read as a pipe (#8807).
PATTERN='(^|[^|])\|&?[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'
```

Re-run the suite. It should exit 0 and print all three PASS lines.

### Phase 3: the in-scope sibling

In `tests/scripts/test-lint-supabase-deprecated-endpoints.sh` row 10, replace
`'\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'` with
`'(^|[^|])\|&?[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'` on **both** lines. Then run that suite
(AC6).

## Guard Contract

Every row was simulated at plan time: the Phase 1 block ran standalone in a scratch dir against
each mutated PATTERN or suite. The shipped block PASSes with rc 0, and every mutation gives rc 1
(the one exception is H2, which is labelled below).

### Guard 1 — grep-q-pipe-guard PATTERN

**Property.** A line is reported exactly when a single pipe operator (`|` or `|&`) feeds `grep` with `q` in its first flag cluster, and never when the bar in front of `grep` is the second bar of a logical OR.

**Assembly.** The chokepoint is the `PATTERN` variable in `.claude/hooks/grep-q-pipe-guard.test.sh`. Every pass in that file reads it: the hooks sweep (`.claude/hooks/*.sh` + `lib/*.sh`), the #7024 named-file pass, the non-vacuity probe, and the FILES_8664 pass once #8848 merges. Four sibling detectors carry their own literal copy and do NOT flow through it. `tests/scripts/test-lint-supabase-deprecated-endpoints.sh` row 10 (2 lines) is fixed here. `workspaces-luks-verify-root-mtime.test.sh` A3-nopipe is deferred to #8869. `sigpipe-triage-feasibility.sh` `SHAPE=` is already `\|\|`-normalised. The set was found by the census command in the class sweep, which AC5 re-runs.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `PATTERN` to the unanchored `'\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'` | RED: `bad=3/4 good=2` (the `\|&` line is missed, and both `\|\|` lines are wrongly matched) |
| 2 | Drop `&?` | RED: `bad=3/4` (the `\|&` line is missed) |
| 3 | Replace `(^\|[^\|])` with `[^\|]` (lose the line-start alternative) | RED: `bad=3/4` (the column-0 continuation is missed) |
| 4 | Guard's own dispatch: `PATTERN='zzz-never'`, or `PATTERN=''` | RED: `bad=0/4`, and for the empty pattern `good=3` |
| 5 | Second member after a compliant first: a pattern that only matches after `echo` (`echo[^\|]*\|&?…`) | RED: `bad=3/4`. `! grep -qv` catches it. Any-line `grep -q` would not, because line 1 still matches |
| 6 | "Tighten" to require whitespace before the bar: `(^\|[[:space:]])\|&?…` | RED: `bad=3/4` (the no-space `"$x"\|grep` line is missed) |
| 7 | Over-broad: drop the pipe, `PATTERN='grep[[:space:]]+-[A-Za-z]*q'` | RED: `good=3` |

**Harness rows:**

| # | Suite edit (PATTERN unchanged) | Expected |
|---|---|---|
| H1 | Empty `bad.sh` (heredoc body deleted) | RED via `[[ -s bad.sh ]]`. Without it, `! grep -qv` on an empty file passes |
| H1b | Empty `good.sh` | RED via `[[ -s good.sh ]]`. This file is the only thing protecting P1 |
| H2 | Change the bad check back to any-line `grep -qE`, then apply mutation 5 | Goes GREEN. It is recorded to show why the per-line `! grep -qv` form is required |
| H3 | Must-PASS non-canonical input: good line 3 is the issue's indented continuation, verbatim | Stays unmatched: GREEN |

**Anchor.** Not applicable. The guard compares against no stored value (hash, count floor or manifest). The fixtures live in the same file as the pattern on purpose, because the probe tests how the pattern behaves.

## User-Brand Impact

- **If this lands broken, the user experiences:** one of two failures. A contributor (the operator or an agent session) gets a red required `test` check on correct `|| grep -q … <<<` code, which is what cost #8779 a CI round and a forced rewrite. Or the pattern is over-narrowed and stops catching a real `| grep -q` in a policy-gate hook, which reopens the #6992 fail-open (a hook silently allowing what it exists to block).
- **If this leaks, the user's workflow is exposed via:** no exposure vector. The change is test-time regex literals only, with no runtime path, credential or user data.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: "the guard suite's own PASS/FAIL lines in the required `test` check (test-scripts shard, leg 6 per scripts/suite-shard-legs.tsv)"
  cadence: "per PR and per push to main"
  alert_target: "red required GitHub check on the PR"
  configured_in: "scripts/test-all.sh ('.claude/hooks/*.test.sh' glob) + scripts/suite-shard-legs.tsv"
error_reporting:
  destination: "GitHub Actions job log of the `test` check"
  fail_loud: "FAIL: guard pattern is broken — it cannot distinguish the shapes"
failure_modes:
  - mode: "PATTERN regresses to matching `||` (false positive returns)"
    detection: "non-vacuity probe: a good line matches"
    alert_route: "red `test` check"
  - mode: "PATTERN over-narrowed and misses a real pipe (fail-open returns)"
    detection: "non-vacuity probe: grep -v finds an unmatched bad line"
    alert_route: "red `test` check"
logs:
  where: "GitHub Actions run logs"
  retention: "90 days (GitHub default)"
discoverability_test:
  command: "bash .claude/hooks/grep-q-pipe-guard.test.sh"
  expected_output: "PASS: guard pattern matches the forbidden shapes"
```

## Open Code-Review Overlap

None. I matched `gh issue list --label code-review --state open` (≤200 issues) against the
four class-sweep paths and the string `grep-q-pipe-guard`, and got 0 hits.

## Acceptance Criteria

- [ ] **AC1** `grep -cxF "PATTERN='(^|[^|])\|&?[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'" .claude/hooks/grep-q-pipe-guard.test.sh` prints `1`.
- [ ] **AC2** RED first. With the Phase 1 probes and the old PATTERN, the suite exits 1 and prints `forbidden lines matched: 3/4` and `fixed lines matched:     2`. With the new PATTERN it exits 0.
- [ ] **AC3** `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0 and prints `PASS: no pipe-into-grep-q in .claude/hooks/ non-test code`, `PASS: no pipe-into-grep-q in the two files #7024 took to zero`, and `PASS: guard pattern matches the forbidden shapes`.
- [ ] **AC4** The probe block is built from the Phase 1 heredocs:
  - `good.sh` contains `a || grep -qE 'p' <<<"$x"`.
  - `bad.sh` contains `echo "$x" |& grep -qE 'p'`, `echo "$x"|grep -qE 'p'` and a column-0 `| grep -qE 'p'`.
  - The check uses `[[ -s … ]]` on both files and `! grep -qvE` for the bad side.
- [ ] **AC5** Census. `git grep -nE "'\\\\\|(\[\[:space:\]\]\*| \*)grep" -- ':!knowledge-base'` prints exactly two lines, one in `apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh` (the `SHAPE=` literal, acknowledged) and one in `apps/web-platform/infra/workspaces-luks-verify-root-mtime.test.sh` (the `A3-nopipe` literal, deferred to #8869). Also, `git grep -cF '(^|[^|])\|&?[[:space:]]*grep' -- .claude/hooks/grep-q-pipe-guard.test.sh tests/scripts/test-lint-supabase-deprecated-endpoints.sh` reports `1` and `2`.
- [ ] **AC6** `bash tests/scripts/test-lint-supabase-deprecated-endpoints.sh` reports `45 passed, 0 failed`.
- [ ] **AC7** The diff touches no path under `apps/web-platform/infra/`: `git diff --name-only origin/main...HEAD -- apps/web-platform/infra/` prints nothing.
- [ ] **AC8** The PR body carries `Closes #8807`, names the class-sweep dispositions (including #8869), and notes that #8848 is still open.

## Test Scenarios

- Given a hooks `.sh` line `elif grep -qE 'p1' <<<"$a" \` followed by the indented line `|| grep -qE 'p2' <<<"$b"; then`, when the guard runs, then neither line is reported. Good lines 2–3 stand in for this case.
- Given `producer | grep -q x`, `producer|grep -q x` or `producer |& grep -q x`, when the guard runs, then it FAILs. The `|&` case is new: the old pattern missed it.
- Given a backslash-continued pipeline whose next line starts with `| grep -q` at column 0 or indented, when the guard runs, then it FAILs.

## Domain Review

**Domains relevant:** none

There are no cross-domain implications. This is a tooling change to regex literals in test-time
drift guards, with no runtime, UI, data, legal or marketing surface.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above (`none`).
- **The guard is line-based.** `producer |⏎ grep -q` and `producer | \⏎ grep -q` (the pipe at the END of a line) are false negatives before and after this change. Only a pipe at the START of a continuation line (bad line 3) is covered.
- **The guard is a text scanner, not a lexer.** It still matches the shape inside strings, which is why the scope rule keeps the pathspec narrow. This fix does not change that.
- **`a | | grep -q` matches.** It is a bash syntax error that cannot ship, so it is not special-cased.
- **#8848 ordering.** If #8848 merges first, rebase onto it. Its FILES_8664 block reads `$PATTERN` and gets the fix for free. Re-run AC3 and expect a fourth PASS line, `PASS: grep-q-zero-8664-pass`.
- **Why not the infra siblings.** Editing anything under `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml` on push to main. AC7 keeps this PR off that path. #8869 carries the A3-nopipe edit to the next infra PR.
