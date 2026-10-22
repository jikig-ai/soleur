# Decision challenges: feat-one-shot-10609-secret-scan-target-dir

Headless planning (2026-10-20). Technical forks were ruled by the CTO agent, never put to the operator.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 reuse `resolve_command_cwd` vs a purpose-built resolver | technical | Ruled by CTO agent, 2026-10-20: new purpose-built resolver in `.claude/hooks/lib/`, `resolve_command_cwd` untouched - its xargs parse, single directory and silent fallback to payload cwd are the skip path, and two other hooks depend on its current behaviour |
| T2 single effective directory vs union of targets | technical | Ruled by CTO agent, 2026-10-20: scan the union of every literal cd/pushd/-C/--git-dir/--work-tree/GIT_DIR/GIT_WORK_TREE target plus fallback roots - extra scans only add denies and no shell-state model is needed |
| T3 disposition of a non-literal or unresolvable target | technical | Ruled by CTO agent, 2026-10-20: deny with the repair named, not ask - a headless pipeline cannot answer an ask, so it degenerates into a skip; the model can rewrite the command at once |
| T4 bare-root commit with no target | technical | Ruled by CTO agent, 2026-10-20: keep the existing `.gitleaks.toml absent` bypass - a commit in a bare root cannot stage anything and the brief requires the no-cd behaviour unchanged |
| T5 lexer implementation | technical | Ruled by CTO agent, 2026-10-20: reuse `plugins/soleur/hooks/lib/shell-argv.pl` through a thin bash walker (reverses the first ruling of a pure-bash lexer, made before the existing lexer was found) - a third lexer repeats the 31-finding hand-written-lexer failure of #9089 |
| T6 perl or lexer unavailable, lexer error, truncated stream | technical | Ruled by CTO agent, 2026-10-20: deny when the command has a commit plus a directory-affecting token, never degrade to a cwd-only scan; commands without those tokens never invoke perl - deliberately stricter than the sibling guard's ask |
| T7 fallback roots always unioned | technical | Ruled by CTO agent, 2026-10-20: confirmed - a false deny costs one re-run, a missed scan can leak a secret; flip only if the ledger shows a material false-deny rate |
| T8 `sh -c` / `bash -c` / `eval` re-lex | technical | Ruled by CTO agent, 2026-10-20: handled by the lexer's own runner re-lex (depth cap 16); a payload it cannot resolve counts as a non-literal target; documented as not a defence against a hostile agent |
| T9 library missing at hook start | technical | Ruled by CTO agent, 2026-10-20: deny every `git commit` with a loud reason naming the repair (`git checkout -- .claude/hooks/lib`), never warn-and-allow; applies to `git commit` only |
| T10 unresolvable-target deny placed after a lazily memoized gitleaks probe, before the legacy bypass | technical | Ruled by CTO agent, 2026-10-20: confirmed - an environment fault stays allow plus a bypass row; the incident variant from a bare root must still deny |
| T11 brand-survival threshold value | taste | Ruled by plan author, 2026-10-20: `single-user incident`; a credential committed to public git history cannot be undone by reverting the commit, and the hook is a secret-scan gate. CPO signed off in the plan. |
| T12 lexer ownership: a repo-local hook depends on the plugin-shipped `shell-argv.pl` (architecture-strategist asked for an explicit owner decision) | technical | Ruled by CTO agent, 2026-10-20: reuse the plugin lexer directly, no third copy; coupling guarded by T40 (framing plus path) and documented in the hooks README |
| T13 DHH alternative: scan every linked worktree with staged content, or deny any commit from a cwd with no toplevel, instead of resolving the target from `cd` / `-C` | operator (scope) | Keep the operator-stated direction (derive the repo from the commit's target directory); the alternative changes the brief and is recorded for the operator to see |
| T14 presence of `--git-dir` / `--work-tree` / `GIT_DIR=` / `GIT_WORK_TREE=` on a commit is a deny, not value-parsed | technical | Ruled by CTO agent, 2026-10-20: approved - parsing gitdir values is costly and error-prone, and denying fails toward scanning |
| T15 routing of the add-then-commit-in-one-command gap (index scanned before the command's own `git add` / `commit -a` runs) | technical | Ruled by CTO agent, 2026-10-20: keep it out of this PR, tracked as #10696 - the gap exists today and folding it in would grow the diff past the planned size |
| T16 commit detection: line 113 stays byte-identical (pinned positionally by boundary-prefix.test.sh); a loose test after line 115 plus lexer confirmation covers `git <global options> commit` | technical | Ruled by CTO agent, 2026-10-20: approved - a loose-only match with no lexer commit record allows, an unavailable lexer denies only when the loose test matched; widening line 113 and allowing on an unavailable lexer were rejected |
| T17 deny text repairs | technical | Ruled by CTO agent, 2026-10-20: name two repairs (install perl when the lexer is the cause; run `cd <abs path>` as its own command first) and do not rely on cwd persistence alone - it is unverified for hook payloads |
| T18 ADR-157 handling | technical | Ruled by CTO agent, 2026-10-20: an addendum to ADR-157 citing ADR-256 as the precedent for a scoped exception, not a new ADR |

## Review round (2026-10-22, 11-seat panel; fix round applied from SHA f4c67d21aa)

| Item | Class | Ruling |
|---|---|---|
| T2 amended by T14 | technical | Superseded by T14: `--git-dir` / `--work-tree` / `GIT_DIR` / `GIT_WORK_TREE` are denies, not unioned targets. The code follows T14. |
| T9 scope when the helper library is missing | technical | Amended by the plan author as a clarification inside the CTO's deny ruling, not a new fork: the deny applies to a plain `git commit` and to option-bearing `git -...` forms; a command with no option form (`git log --grep=commit`) is left alone. Substring-only matching had denied `echo "no git here, just commit msg"`. |
| T19 walker shape: closed wrapper table vs look-through | technical | Ruled by plan author, inside T5/T6 (fail toward scanning): the walker looks through any unmodelled first word for a later `git` / `cd` / `env` / runner / `eval` word and treats an unknown git option followed by a `commit` word as a commit, instead of maintaining a wrapper table that must be complete (four seats found launchers outside the table). Over-recognition only adds scans. |
| T20 refusals after the last commit | technical | Ruled by plan author: dropped (a later `cd "$X"` cannot retarget an earlier commit); a refusal before or at a commit is kept. |
| T21 same-call `git add` / `commit -a` | technical | Unchanged: tracked as #10696 (T15); now listed as an accepted residual in the README and the ADR-157 addendum. |
| T22 sibling hook `brand-hex-commit-gate.sh` resolves its repo from the process cwd (same shape) | technical | Filed as its own issue (a different hook, a different decision); not folded in here. |
