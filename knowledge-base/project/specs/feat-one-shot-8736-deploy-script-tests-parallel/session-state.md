# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8736-deploy-script-tests-parallel/knowledge-base/project/plans/2026-09-24-feat-deploy-script-tests-parallel-plan.md
- Plan file (actual): /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8736-deploy-script-tests-parallel/knowledge-base/project/plans/2026-09-24-feat-deploy-script-tests-parallel-shards-plan.md
- Status: complete

### Errors
- Early bounded command chain exited 2 (missing branch-specific spec dir; later created for tasks.md).
- No Task/Skill spawn tool in subagent environment — `soleur:plan`/`soleur:deepen-plan` executed inline from SKILL.md (`Reviewed-Coverage: sequential-fallback` disclosed; no independent review claimed).

### Decisions
- Chosen shape: `deploy-script-tests` becomes a K=4 `fail-fast: false` matrix invoking `run-registered-suites.sh` under `SOLEUR_INFRA_SHARD=k/N`, plus `deploy-script-tests-fixed` (sudo suites, terraform validates, test/infra steps, sandbox-canary) and a `deploy-script-tests-done` aggregator modeled on `ci.yml`. Projected ~7.8 min/leg.
- Registration contract extended: derivation moves to `git ls-files` glob (146 suites incl. 6 subdir — closes #7076); gate rewritten to registration-list contract in same atomic PR; privileged suites derive-but-do-not-execute.
- Rejected: BASH_ENV shard filter, N sibling jobs, K=1 runner-only (~10.5–12 min), published fixture image. Deferred: per-suite affected selection on PRs (no edge index).
- Fold-ins: #8744 apt retry+diagnose, #8735 cancelled-notification coverage, #7942 naming convention.
- All deepen gates pass (UBI, Observability, PAT clean, Guard Contract lint, markdownlint).

### Components Invoked
- `soleur:plan`, `soleur:deepen-plan` (inline SKILL.md execution)
- `lint-guard-contract.py`, `markdownlint-cli2`, `gh api` step-timing pulls, `git ls-files`/grep sweeps

## Phase: work complete, review in flight (2026-09-24 late)

Commits on the branch:
- `0ec8d0f7f4` fix(8744): bounded apt retries + diagnostics (ownership + runcmd-rehearsal)
- `87127d095c` feat(8736): runner glob-derives, SOLEUR_INFRA_SHARD, per-suite timeout+timings
- `b6298817f7` feat(8736): workflow restructure — K=4 matrix + fixed job + done aggregator;
  gate rewritten to connection contract (17/17 mutation arms); 12 suite self-checks
  re-pointed; manifest seeded 143 rows (legs 369-370s); ADR-251 authored; monitor + skill refs
- `3f2cd7dd5a` feat(8736): followthrough soak probe + stub-gh test (6/6)

All local verification green: run-registered-suites.test.sh 82/82 (19/19 mutants),
registration gate + mutation battery, lint-orphan 543/543 covered 0 orphans,
actionlint clean, all 11 re-pointed suites pass standalone, apt fix verified in docker.

Review: classified `code`, design-risk YES → design-validity pass spawned
(simplicity + architecture + performance seats), then full panel minus deduped lenses.
Remaining at ship: followthrough directive + `follow-through` label on #8736,
#8736 comment with measured per-leg fixed cost + chosen K.

## Post-merge session (2026-09-25 cont.)

Merge `9c667e4bb3` brought origin/main in (ADR renumber 250->251 — #8738
owns 250; zot-log-shipper suite absorbed by the glob, 147 derived /
144 executable). First CI run on the new structure measured:
legs 172-259 s, fixed 142 s, done 4 s (~4.5 min suite wall clock vs
20-24 min serial). CLA green after author rewrite (two plan-phase
commits were authored by the planning subagent's `devin` identity —
history rebuilt, all commits now `deruelle`, trees verified identical).

Full review panel (9 seats) folded in — five post-merge commits:
- runner: ls-tree HEAD derivation (index != committed), JOBS/empty-set/
  TIMINGS-path refusals, logdir-as-argv (unexported), literal bound
  lookup, ::error property strip, bash-5 gate hoisted, -c-string
  apostrophe hazard documented (a `'` inside the shim text truncated
  argv mid-comment — `s: unbound variable` measured live)
- gate+battery: manifest coherence arms (execute-set membership, leg
  range, dup/extra-field rows, FIRST `# n=`), masking extended to sudo +
  aggregate steps, PRIVILEGED parse floor, notify predicate SHAPE
  (`!= 'success'`), needs both-YAML-forms, ls-tree enumeration, floor
  50->130; battery now commits its sandbox + carries the manifest —
  M16-M27 land real arms (29/29)
- tests: T11i non-positional fixture (was vacuous — manifest and
  fallback agreed), 5 new T9 mutants (all killed, 89/89), aggregator
  W-arm (env->needs wiring), assertion floors on the three new
  batteries, probe k/N tiling instead of hardcoded /4 + boundary cases
- workflow: timings upload warns (not ignores) on missing feed,
  persist-credentials:false on legs, SUPERSEDED-CLASS rewording (no
  concurrency block here), stale comments
- prose: 25 "Registered as a step" headers, runcmd retained-tree
  comment, test-all pointer, ADR-251 #7376 cause marked unresolved
  upstream, runbook --group infra, apt scrub colonless userinfo x5,
  fanout-ledger 9->11, lint-orphan floor 90->135

Deferred (consciously, low-value-vs-cost): composite-action preamble
extraction (~2 identical 3-step blocks), awk multi-char RS portability
(linux-only CI; BSD awk is a test-harness portability nicety), JOBS cap
by memory (needs a measurement #7376 itself declined to take).
