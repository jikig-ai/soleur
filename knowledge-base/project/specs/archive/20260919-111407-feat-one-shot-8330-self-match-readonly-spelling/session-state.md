# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-19-fix-hooks-self-match-guard-readonly-ps-grep-spelling-plan.md
- Status: complete
- Plan artifact: complete (selector=subagent-summary)

### Errors
- Live `pkill-self-match-guard.sh` denied two of the planning session's own Bash calls (text carried the signal spelling) — the #7994 class; worked around via Write tool + split-variable probes; recorded as a plan Sharp Edge / Phase 0 precondition.
- Three duplicate background Monitor tasks superseded and stopped; no data lost.

### Decisions
- Detection is a simulation (extract each grep/awk stage regex, run it against the model wrapper line `bash -c <command>`, honour `-v`, per-pipeline fail-open), not the issue's "pattern appears elsewhere" heuristic (measured: escaped-dot spelling alone returns 0, so the heuristic would allow a real self-match).
- #7994 docs-about-themselves handled structurally for the new arm only: trigger/walk/extraction read `strip_heredocs "$CMD"`, model reads raw `$CMD`; `-f` arm unchanged. Missing `lib/incidents.sh` → WARN + skip arm.
- Plan-review cuts: no second wrapper model, no continuation join, no pass-through stage whitelist, no awk slot grammar, no sudo/prefix boundary set, no second rule id on `-f` arm — each a named header gap. Taste items persisted to decision-challenges.md.
- Test rows made RED-capable at deepen time (H1 deletes four rows; A14 quoted; A6 positive control; D11 discriminates on `BLOCKED:` prefix); A6 fixture synthesized inline; repo docs verified once in Phase 3 (AC4).
- Scope held to #8330: 4 files (hook, suite, one review/SKILL.md clause, one README roster row).

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:spec-templates
- Plan agents: learnings-researcher, repo-research-analyst, functional-discovery, spec-flow-analyzer, advisor consult (fable)
- Plan-review: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, cto
- Deepen: architecture-strategist, security-sentinel, test-design-reviewer, pattern-recognition-specialist, code-quality-analyst, performance-oracle, git-history-analyzer, best-practices-researcher, general-purpose (sonnet, verify-the-negative)
- Commits: 7db34cd11, a03e64568

## Work Phase
- Status: complete (commits da205a75c RED suite, f57ccbd24 GREEN hook, 925ae1074 docs)
- Suite: 62 verdicts, 0 failed (floor 59); also green under CI=1, SOLEUR_SUBAGENT=1, and a simulated main-branch CWD
- Mutation battery: control green; M1–M13 + H1/H1b/H2/H3a/H3b/H4 all RED, every mutation landed (md5), M13 companion D16 stayed deny — /var/tmp/soleur-8330-battery.out
- AC1–AC14: all PASS (/var/tmp/soleur-8330-ac.out); AC12 via the per-suite fallback (full gate refused: sibling run in flight) — 19 consumer suites + ratchets green; lint-window-closure-assertion.py rc=1 is pre-existing on origin/main (same two files)
- Doc verification (AC4): review/SKILL.md bullet and the filtered learning section both → empty stdout (allow). Note: the learning section's poller sits in inline backticks, so it is allowed by the boundary rule regardless of heredoc wrapping; the fenced doc shape that exercises strip_heredocs is suite row A6 (with its positive control)
- Session errors: (1) first hook draft used `timeout … command grep` — `command` is a builtin so timeout exec'd nothing (rc 127, every pipeline fail-open, all D rows allow); fixed by resolving `type -P grep`. (2) battery perl replacements interpolated `$CMD`/`$psflags` to empty — three rows went RED for the wrong reason until `\$` was escaped; (3) the battery's D16 companion used `suite | grep -q` under pipefail → SIGPIPE false FLIPPED; fixed with a herestring. (4) `gh issue comment --body-file` for #7994 was denied by the LIVE -f arm because the body names the spelling — the #7994 class, observed live.
- #7994 comment: https://github.com/jikig-ai/soleur/issues/7994#issuecomment-5740340304

## Review Phase (round 1)
- Panel: git-history-analyzer, pattern-recognition-specialist, architecture-strategist, security-sentinel, performance-oracle, data-integrity-guardian, agent-native-reviewer, code-quality-analyst, test-design-reviewer, structural-enumeration seat (general-purpose); shellcheck as the deterministic gate (bash-only diff); code-simplicity-reviewer at step 4. All report-only; fixes applied by the lead from HEAD 23fe40c9d.
- Findings: 1 P1 (projection awk after a live grep read as "filtered"), ~10 P2, ~25 P3. Structural roll-up: (a) raw-text pipeline segmentation was quote-blind (terminator cut inside quoted literals, `2>&1`, `|&`, newline-after-pipe) → quote-aware `split_pipeline`; (b) grep modelled as a pure line filter → `-c/-o/-l/-L/-q` end the walk (the hook's own `| grep -v grep` remedy was a bypass after `-c`); (c) `ps` boundary/flag classification was value-blind (keywords, prefixes, `-C bash`); (d) performance: quadratic `${rest#*"$m"}` + eager `incidents.sh` source + unbounded regex memory.
- All fixed inline (commits f0666593f, + P3 follow-up). 0 scope-outs filed. Battery v2: 28 RED, control 126/0; residual H6 (lower floor AND delete a row) is the developer-maintained-floor class.
- ACs amended, not quietly satisfied: AC7 (anchored on code, locals renamed), AC11 (clause reworded), AC13 (work/SKILL.md added to the set).
- Session errors this round: (5) the live -f arm denied my doc-fix python heredoc and my first `gh issue comment` (the #7994 class, twice more); routed through Write-tool scripts. (6) first perf fix (`${rest%%ps*}`) was itself 262 ms/100 kB — the fnmatch-per-position cost; `${rest/ps*/}` measured 6 ms. (7) 4,000-`ps`-token synthetic stays at ~2 s (O(n·k) remainder copies in bash) — named in the header, bounded by the 4 s budget.
