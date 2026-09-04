---
title: "fix(test-fixtures): stop the inherited git environment at the test-runner boundary (#7833)"
issue: 7833
closes: 7833
type: fix
classification: test-infrastructure
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-09-04
slug: fix-test-fixture-git-env-scrub
branch: feat-one-shot-7833-git-dir-beats-cwd
---

## Overview

A test that builds a temporary git fixture and passes `cwd` (or `-C`) to every `git` call is still
not scoped to that fixture: when the test process inherits `GIT_DIR` / `GIT_INDEX_FILE` from a git
hook environment, the subprocess honours the environment over both its working directory and `-C`.
`git init` then initialises nothing and the fixture's writes land in the surrounding repository.

The fix is at the **process boundary**, not at the call site: no test process that can spawn `git`
should ever hold an inherited `GIT_DIR`. Three layers — one that removes it, one that refuses to run
without it removed, and one that ratchets the entry-point set — plus a corrected fixture-env helper
for the small number of suites that must construct an env explicitly.

No spec exists for this branch, so there is no `lane:` to carry forward — defaulted to
`cross-domain` (fail-closed).

## Decision headline

1. **The environment is the write boundary, not the operand.** `git -C <abs>` and `cwd:` are both
   overridden by `GIT_DIR`; and with `GIT_DIR` scrubbed, an absolute `GIT_INDEX_FILE` still retargets
   `git add` into the victim's index. Both measured (§Measurements M-1, M-3).
2. **The recurring assembly is the set of hook entry points, not the set of test files.** All four
   recurrences (2026-03-24 #1090, 2026-04-03 ×2, #7833) entered through a **hook command that lacked
   the scrub**, never through a test file that lacked a helper. That set is closed and tiny:
   `lefthook.yml` has **26** `run:` lines across two hooks, of which exactly **2** invoke a test
   runner; plus two standalone hook scripts under `scripts/hooks/`. A guard over ~900 test files
   would quantify over the wrong thing.
3. **A static shape guard over test files could not see the real hazard anyway.** Most git-spawning
   suites exercise *scripts under test* that spawn `git` themselves; the test file's source says
   nothing about those. And the beneficiary set is not even greppable: `git grep -l 'git init' --
   '*.test.ts'` returns 5, while the `execFileSync("git", ["init", …])` array form appears in at
   least 10 more. A guard whose corpus cannot be enumerated is a guard with a permanent
   grandfathering ledger.
4. **A process-wide scrub is NOT a chokepoint under Bun — but an invocation-layer one is.** Measured
   on Bun 1.3.11: `delete process.env.GIT_DIR` takes effect in-process yet a child spawned without an
   explicit `env` still receives the original value (Node v22 propagates it correctly). Removing the
   variable *before* the Bun process starts (`unset …; bun test`) works completely (§M-5, §M-6). So
   the scrub belongs on the invocation, and the in-process check must **fail loud**, never scrub.
5. **The helper must be a deny-list with pinned identity, not the read-only probe's allowlist.**
   `apps/web-platform/server/git-worktree-validity.ts` › `buildGitProbeEnv()` is the right *idea* and
   the wrong *shape* to copy: it exists for a `rev-parse` and drops `user.name`/`user.email` along
   with everything else. Measured: a fixture `git commit` under that env fails with `Author identity
   unknown` (§M-7). Every one of the 43 shell fixture suites commits.
6. **`GIT_CEILING_DIRECTORIES` must name the fixture's PARENT.** With the ceiling set to the fixture
   directory and git's cwd equal to it, discovery still escaped upward (§M-4). The issue's suggested
   `GIT_CEILING_DIRECTORIES: dir` is the ineffective spelling.
7. **No ADR.** See `## Architecture Decision (ADR/C4)`.

## Measurements

Every design claim above is a probe, not a judgement. Each was run in this worktree; each hazardous
arm is paired with a control so the probe cannot read as vacuous.

| # | Question | Probe | Result |
|---|---|---|---|
| M-1 | Does a git hook export `GIT_DIR`? | scratch repo + `lefthook install`, `pre-commit` command dumps `env \| grep '^GIT_'`; repeated inside a `git worktree add` checkout | **Worktree-conditional.** Plain clone: no `GIT_DIR`, and `GIT_INDEX_FILE=.git/index` **relative** (harmless). Linked worktree: `GIT_DIR=<bare>/worktrees/<name>` and `GIT_INDEX_FILE=…/index`, both **absolute** |
| M-2 | Does `GIT_DIR` beat `cwd` and `-C`? | `GIT_DIR=<victim> git init -q` in an empty fixture dir, then commit | Fixture dir stays empty (`ls -a` = `.` `..`); the commit lands in the victim; `git -C fixture rev-parse --git-dir` prints the **victim's** `.git` |
| M-3 | Is `GIT_DIR` alone enough to scrub? | `GIT_DIR` unset, `GIT_INDEX_FILE=<victim>/.git/index` absolute, `git add f.txt` in the fixture | **No.** `f.txt` staged into the **victim's** index; fixture index empty |
| M-4 | `GIT_CEILING_DIRECTORIES=<fixture>` vs `<parent>` | `git rev-parse --show-toplevel` from the fixture dir under each spelling | fixture-dir spelling → still resolves the enclosing repo. Parent spelling → `not a git repository` before `init`, correct fixture repo after |
| M-5 | Does `delete process.env.X` reach a child? | same script under `bun run` and `node`, spawning `/usr/bin/env`, with and without an explicit `env:` | **Bun 1.3.11:** default-env child still sees `GIT_DIR`; explicit `env: {...process.env}` child is clean. **Node v22.22.2:** clean in both |
| M-6 | Does an invocation-layer scrub fix the Bun case? | `env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE bun test` and `bash -c 'unset …; bun test'`, control without | Both clean; control shows both variables |
| M-7 | Does the `buildGitProbeEnv()` allowlist survive a commit? | `env -i PATH HOME GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null … git commit` | **`Author identity unknown`.** Adding `GIT_AUTHOR_*`/`GIT_COMMITTER_*` succeeds |
| M-8 | Can a `bunfig.toml [test] preload` abort the run? | preload that `process.exit(97)` when the family is present; run with and without `GIT_DIR` | Aborts with **rc=97** when set; **rc=0** and suite passes when clean |
| M-9 | Does `unset … && <cmd>` work inside a lefthook `run:` string? | lefthook command in a linked worktree counting `GIT_(DIR\|INDEX_FILE\|WORK_TREE)` in its own env, with and without the prefix | With prefix: **0**. Control without: **2**. The one line the whole fix rests on |
| M-10 | Is `scripts/test-all.sh` already protected? | read of the `--- Git Hook Isolation ---` block | **Yes** — `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE`, landed `dccfd9b0e` (#1090, 2026-03-24) |

## Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| #7833 open, not already closed by a merged PR | `gh issue view 7833 --json state` → `OPEN` | HOLDS |
| #7708 / #7709 / #7810 are the prior family and are done | `gh issue view` → `CLOSED`, `CLOSED`, `MERGED` | HOLDS — do not re-target |
| `plugins/soleur/test/lib/fixture-scan.py` exists, with the #7810 rule | read of its `main()` dispatch → `--rule` accepts `operand`, `cd`, `relative` | HOLDS |
| `plugins/soleur/test/fixture-relative-assert.test.sh` + baseline exist | `ls` | HOLDS |
| "git hooks export `GIT_DIR`" | §M-1 | **Worktree-conditional** — corrected below |
| The mechanism sits in a rejected ADR alternative | `grep -rl 'GIT_DIR\|fixture-safety\|fixture-scan' knowledge-base/engineering/architecture/decisions/` → 0 hits | No conflict |

The issue states flatly that "git hooks export `GIT_DIR`". §M-1 shows that is true only in a **linked
worktree**. This does not weaken the report — it sharpens it. Every feature branch in this repo is a
linked worktree (`AGENTS.md` `hr-when-in-a-worktree-never-read-from-bare`, the `git-worktree` skill),
so the hazardous arm is the normal one here, and anyone reproducing in a plain clone will measure
"no leak" and wrongly conclude the issue is stale.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality | Plan response |
|---|---|---|
| "git hooks export `GIT_DIR`" | Worktree-conditional (§M-1) | Keep the fix; record as re-evaluation trigger and Sharp Edge |
| "`GIT_DIR: undefined` may stringify to the literal `"undefined"`" | **It does not** — measured on Bun 1.3.11 and Node v22.22.2; a control run without the scrub shows the variable present, so the probe is not vacuous | Spelling is safe. Moot anyway: the primary fix removes the variable before the process starts |
| Scrub set = `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_CEILING_DIRECTORIES=dir` | The location family is right but incomplete (`GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_NAMESPACE`); and `GIT_CEILING_DIRECTORIES=dir` is the **ineffective** spelling (§M-4) | Deny-list the full location family; ceiling at the parent |
| "A shared helper is better than per-call scrubbing" | Agreed in principle, but a helper only protects spawns that *use* it — not the scripts-under-test that spawn `git` themselves, and not a suite added tomorrow | Helper is layer 4, not the fix. Layers 1-3 protect the process regardless of what any suite does |
| "a detector that flags a test spawning `git` without scrubbing `GIT_DIR`" | The corpus is not enumerable (§Decision 3) and the scanner's shared machinery (`heredoc_lines`, `scope_has_set_e`, `_outside_quotes`) is shell-specific | **Re-aimed**, not dropped: the detector quantifies over the hook entry points (26 `run:` lines + 2 hook scripts), a closed set needing no grandfathering baseline |
| Prior art in `apps/web-platform/test/` "does not delete `GIT_DIR`" (repo-research finding) | **FALSE — corrected.** All six delete `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE` and set the ceiling to `tmpdir()` | Do not touch them. They are correct **for vitest/Node** (§M-5) and are a trap if copied into a Bun suite |
| `scripts/*.test.sh` is unregistered in `test-all.sh` (repo-research finding) | **Mostly FALSE.** 98 match; **91** hand-registered; the 7 others are `scripts/lib/*` names the `scripts/lib/*.test.sh` glob already covers | No action; recorded so a later reader does not chase it |
| Blast radius = "`git grep -l 'git -C\|execFileSync("git")'`" | 393 tracked `*.test.sh`, 151 spawn `git`, **43** run `git init`. `git grep -l 'git init' -- '*.test.ts'` returns 5 but **undercounts** — the `["git", ["init", …]]` array form adds ≥10 more | Used as evidence that the beneficiary set is not the guard's assembly, not as a work-list |

### Provenance of the recurrence

`scripts/test-all.sh` already carries the exact fix, under a comment block headed
`--- Git Hook Isolation ---` that names the lefthook pre-commit case verbatim (§M-10). It landed in
`dccfd9b0e` (*fix: test isolation failures when running global bun test from worktrees*, #1090,
2026-03-24), and that same change repointed the `bun-test` lefthook command at `scripts/test-all.sh`.
It did **not** touch the sibling `plugin-component-test` command, which had existed since `e9d4eccc0`
(2026-02-12) and still runs `bun test plugins/soleur/test/` directly. That command is the exact runner
named in the incident report. `scripts/hooks/pre-push` independently acquired its own copy of the
same `unset`. Three copies of one idea, one uncovered sibling, and nothing measuring the set.

## Research Insights

### Applicable institutional learnings

- `knowledge-base/project/learnings/2026-03-24-git-ceiling-directories-test-isolation.md` — the
  originating learning; already states the two-layer rule. Its fix #2 records the
  `apps/web-platform/test/workspace.test.ts` shape and its rationale ("`provisionWorkspace` uses
  `execFileSync` without an explicit `env` parameter, so it inherits `process.env`") — sound under
  vitest/Node, **unsound under Bun** (§M-5).
- `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`
  and `knowledge-base/project/learnings/2026-04-03-git-env-var-leak-resolve-git-root-test.md` — two
  further recurrences twelve days later.
- `knowledge-base/project/learnings/2026-09-03-the-deviation-ledger-was-an-hour-of-my-own-test-fixtures.md`
  — a documented-but-unbound isolation variable let hook suites write to the live repo. Constraint:
  assert the isolation is *bound*, never merely referenced in a comment.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — derive the mutation matrix from the design, not the finished code; anti-vacuity controls need
  floors of their own.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — every suite needs a must-PASS row that is not byte-identical to the canonical.
- `knowledge-base/project/learnings/2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md`
  — a delete-only mutation battery certifies an ordering property it never tested.
- `knowledge-base/project/learnings/2026-09-03-every-p1-was-in-the-verification-not-the-fix.md` —
  on a guard-shaped PR, review the new assertions before the new code.

### Rules in force

`hr-write-boundary-sentinel-sweep-all-write-sites` — the sentinel here lives at the **entry points**,
so the sweep obligation is over the entry-point set, and that set is enumerated exhaustively
(`lefthook.yml` 26 `run:` lines across `pre-commit`/`pre-push`, plus `scripts/hooks/pre-commit` and
`scripts/hooks/pre-push`) and mechanically pinned by Guard 2. Also in force:
`cq-write-failing-tests-before`, `cq-assert-anchor-not-bare-token`,
`cq-cite-content-anchor-not-line-number`, `wg-defer-only-after-inline-triage`,
`hr-verify-repo-capability-claim-before-assert`.

**`knowledge-base/engineering/architecture/principles-register.md` › AP-023** governs every floor in
this plan and is hook-enforced by the CI-required `scripts/guard-vacuity-floor.test.sh`: an
anti-vacuity floor must report with `printf >&2` + `exit 1` — **never** by calling the suite's own
`fail`/`bad` helper, because that increments the counter the exit status reads, so neutering the
helper silences both the assertion rows and the floor meant to notice the silence. The case counter
must move at the **call site**, never inside `$( )`. Guard 2's `RUN_LINES`/`RUNNER_LINES`/`HOOK_SCRIPTS`
floors and Guard 3's per-runtime prelude floor are written in that form, and the new drivers will be
picked up by that guard's shape-derived population.

### In-repo prior art

- `apps/web-platform/server/git-worktree-validity.ts` › `buildGitProbeEnv()` — the allowlist
  reference. Correct for a read-only `rev-parse`; **not** reusable verbatim for a fixture that commits
  (§M-7). Its comment enumerates the exec-hook and config-injection variables a naive spread leaves
  live (`GIT_SSH_COMMAND`, `GIT_PROXY_COMMAND`, `GIT_EXTERNAL_DIFF`,
  `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY*`/`GIT_CONFIG_VALUE*`) — those go on the deny-list explicitly.
- `test/pre-merge-rebase.test.ts` › `GIT_ENV` — the closest existing *test-side* art: destructures the
  location family out of `process.env`, then adds `GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_GLOBAL=/dev/null`,
  `GIT_CEILING_DIRECTORIES=tmpdir()`. This is the shape the helper generalises.
- `tests/scripts/test_lint_rule_ids.py` › `_GIT_ENV` — already pins `GIT_AUTHOR_*`/`GIT_COMMITTER_*`;
  it needs the location family removed, not replacing.
- `scripts/test-all.sh` › `--- Git Hook Isolation ---` and `scripts/hooks/pre-push` — the two existing
  copies of the invocation-layer scrub.

### External research

Not run. Every question the plan turned on was settled by a local probe (§Measurements). Registry
discovery returned zero relevant artifacts across three registries; the deliverable is coupled to
this repo's hook topology.

### Property List (Phase 0.6b)

| # | Property |
|---|---|
| P1 | A git write issued from a test fixture cannot move the enclosing repository's `HEAD`, refs, or index. |
| P2 | No test-runner process started from any hook entry point holds an inherited git-location variable. |
| P3 | A **new** hook entry point that starts a test runner without the scrub is rejected mechanically. |
| P4 | If P2 is ever violated anyway — a new runner, an agent shell, `git rebase -x`, an editor — the run **aborts loudly** instead of silently writing to the real repository. |
| P5 | A fixture that must construct its own env (Bun suites, python suites) gets one that is correct **for writes**, not only for reads. |

### Cut List (Phase 0.6b)

| Mechanism | Property claimed | Already covered / why cut | Disposition |
|---|---|---|---|
| `scripts/test-all.sh` scrub | P2 (full battery) | **Already on `main`** — `--- Git Hook Isolation ---` (§M-10) | **CUT — build nothing.** Guard 2 pins it so it cannot be deleted |
| `scripts/hooks/pre-push` scrub | P2 (pre-push) | **Already present** at the script's top | **CUT — build nothing.** Guard 2 pins it |
| Per-call `env: { ...process.env, GIT_DIR: undefined, … }` | P1 | Protects only spawns that use it; blind to scripts-under-test | **CUT** — superseded by P2/P4 |
| `GIT_CEILING_DIRECTORIES: dir` (fixture dir) | P1 | **Measurably ineffective** (§M-4) | **CUT** — parent spelling instead |
| A `bunfig.toml [test] preload` that *scrubs* | P2 | Measured non-functional for default-env children (§M-5) | **CUT as a scrub — KEPT as a fail-loud tripwire** (§M-8), which is the P4 mechanism |
| `--rule gitenv` in `fixture-scan.py` + corpus extended to `*.test.ts` and `*.py` | P3 | Wrong assembly (§Decision 2, 3); ~250 LOC of scanner + ~600 LOC driver + a permanent grandfathering ledger over a corpus that is not even enumerable | **CUT** — replaced by a ~30-line assert over the 26 `run:` lines + 2 hook scripts, which needs no baseline because the set is closed |
| Converting all 43 shell + ≥10 TS fixture suites to a helper | P1 at each site | With P2 + P4 in force, no suite can observe a hostile env in any reachable invocation | **DEFERRED** to a tracked follow-up as defence-in-depth; not load-bearing for closing #7833 |
| A shell `git-fixture-env.sh` canonical body | P5 | `test-all.sh` + the tripwire already cover every shell suite; a second byte-for-byte canonical body beside `assert_fixture_dir()` is the drift this plan exists to end | **CUT** |
| `tests/scripts/git_fixture_env.py` shared module | P5 | Two call sites | **CUT** — edit both `_GIT_ENV` dicts inline |

### Value-Proposition Measurement (Phase 0.6c)

Correctness, not cost, so 0.6c does not gate. The number worth pinning is the assembly size: **26**
`run:` lines in `lefthook.yml` (`grep -cE '^\s+run:' lefthook.yml`), of which **2** match a
test-runner token (`grep -nE '^\s+run:.*(test-all\.sh|bun test|vitest|pytest|unittest|bats)'`), plus
**2** files under `scripts/hooks/`. That is the entire surface the guard must cover — against ~900
files for the cut design.

## User-Brand Impact

**If this lands broken, the user experiences:** a `git commit` that silently rewrites their branch —
`git init` in a fixture creates nothing, the fixture's `commit` lands on the live branch and moves its
tip, and the working tree afterwards reads as wholly untracked. The reporter recovered only because
the pre-incident commit was still a reachable object and they thought to read the reflog; that reflog
shows repeated `commit: base` / `commit: change` pairs, so it has fired silently more than once.

**If this leaks, the user's workflow is exposed via:** unreviewed fixture content committed under the
developer's identity onto a real branch, and a staged index (§M-3) that a later `git commit -a` or an
agent-driven commit would carry into a push.

**Brand-survival threshold:** `single-user incident`. A tool that rewrites git history during
`git commit` ends trust on the first occurrence, and recovery depended on the operator noticing.

CPO sign-off is required at plan time before `/work`; `user-impact-reviewer` runs at review time.

## Open Code-Review Overlap

`None`. All 63 open `code-review` issues (`gh issue list --label code-review --state open --json
number,title,body --limit 200`, then `jq --arg path … | contains($path)`) checked against
`lefthook.yml`, `scripts/test-all.sh`, `scripts/hooks/pre-push`,
`plugins/soleur/test/lib/fixture-scan.py`, `plugins/soleur/test/test-helpers.sh`,
`plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts`, and the bare token
`fixture-scan`. Zero matches.

## Architecture Decision (ADR/C4)

**No ADR, no C4 change.**

- **ADR:** `grep -rl 'GIT_DIR\|fixture-safety\|fixture safety\|test isolation\|fixture-scan'
  knowledge-base/engineering/architecture/decisions/` returns **zero** files, and the two sibling
  rules in this family (#7708, #7810) each shipped without one. This plan neither reverses nor
  extends a recorded decision.
- **C4:** no change. All three model files —
  `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — checked for each
  category the completeness mandate requires. **External human actors:** none added (the only human is
  a repo contributor, not a modelled actor of the web-platform system). **External systems / vendors:**
  none (`git` is a local binary invoked by the repo's own runners, not an integration edge).
  **Containers / data stores:** none created, read, or written — the artifacts are a YAML hook line,
  three runner preludes, one TS helper, and a shell assert. **Actor↔surface access relationships:**
  none — no ownership, tenancy, or sharing boundary moves. No element description is falsified. No
  `views.c4` `include` line to add.

## Guard Contract

### Guard 1 — fixture git-write containment (runtime)

**Property.** Under a hostile inherited git environment, a `git` write issued by a fixture mutates
only the fixture repository: the victim repository's `HEAD`, its ref set, and its index are all
unchanged.

**Assembly.** Not the list of suites that call the helper — that is a membership snapshot the next
new test invalidates. The chokepoint is the **env the git subprocess actually receives**, and the
guard exercises the two constructions that produce it: the invocation-layer scrub
(`unset …; <runner>`, the P2 mechanism) and `gitFixtureEnv()` in
`plugins/soleur/test/lib/git-fixture-env.ts` (the P5 mechanism). The guard sets the hostile
environment **itself** rather than relying on an ambient one, so it reproduces in a plain clone as
well as a worktree.

**Transitive spawns are part of the assembly.** A suite that shells out to a repo script which itself
runs `git` (`scripts/learning-retrieval-bench.sh`, `apps/web-platform/infra/git-data-bootstrap.sh`,
`scripts/lint-supabase-deprecated-endpoints.sh`, …) inherits the env transitively, so the constructed
env must be passed to the **script** spawn as well as to direct `git` spawns. An env *constructor*
becomes an env *chokepoint* only when every spawn out of the suite carries it. Guard 1 includes a
case that spawns a shell script which runs `git init`, asserting the victim is untouched — this is
the arm neither a helper-call grep nor any source scan could ever reach, and it is the reason
Guard 3 exists as a separate layer.

**Mutation matrix** (run against a pristine backup; a GREEN unmutated control is required first):

| # | Mutation | Must be |
|---|---|---|
| M1 | Return `GIT_DIR` to the constructed env | RED — victim `HEAD` moves |
| M2 | Return `GIT_INDEX_FILE` (absolute) while `GIT_DIR` stays removed | RED — victim **index** gains a staged path though `HEAD` is unchanged. M1 alone would certify a property it never tested (§M-3) |
| M3 | Point `GIT_CEILING_DIRECTORIES` at the fixture directory instead of its parent | RED (§M-4) |
| M4 | **Reorder**, not delete: construct the env *after* the first `git init` | RED — the property is about the environment *during* the window git runs in; a delete-only battery cannot see it |
| M5 | Replace the helper body with `return { ...process.env }` | RED — a pass-through must not satisfy the guard |
| M6 | Replace the explicit `env:` argument with a module-scope `delete process.env.GIT_DIR` | RED under Bun (§M-5). This row is the reason the helper returns an object instead of mutating the process |
| M7 | Remove the pinned `GIT_AUTHOR_*`/`GIT_COMMITTER_*` from the helper | RED — the commit fails `Author identity unknown` (§M-7). Guards the regression the read-only-probe shape would have introduced |

**Harness rows** (edits to the SUITE, not the guard):

| # | Edit | Must be |
|---|---|---|
| H1 | Neuter the suite's `fail`/`bad` helper | RED — per AP-023 the floors report with `printf >&2` + `exit 1` and never through that helper, so neutering it cannot silence them; the verdict is additionally reconciled against an independent append-only ledger |
| H2 | Delete the victim-repo setup so the "before" reading is empty | RED — must fail closed on a missing baseline, never pass on `"" == ""` |
| H3 | **Must-PASS, not canonical:** fixture created under `TMPDIR=/var/tmp`, directory name containing a space and a `-`-leading segment | GREEN — `TMPDIR` is therefore load-bearing and must survive the deny-list |
| H4 | **Must-PASS, not canonical:** a fixture that only *reads* (no `git init`, read-only verbs) | GREEN — the contract permits it; it must not be collateral |

### Guard 2 — hook entry-point coverage (static)

**Property.** Every hook entry point that starts a test runner removes the git-location family before
starting it.

**Assembly.** The complete, closed set of hook entry points: every `run:` line in `lefthook.yml`
(26, across `pre-commit` and `pre-push`) plus every file under `scripts/hooks/`. Because the set is
closed and small, the rule is **all**, not *all-except-baselined* — there is no grandfathering ledger
and therefore no ledger to quietly grow. The guard reports the size of the set it examined so a
corpus that stops matching cannot read as green.

**Mutation matrix:**

| # | Mutation | Must be |
|---|---|---|
| N1 | Add a new `run:` line invoking a test runner without the scrub | RED |
| N2 | Delete the `unset` from the `--- Git Hook Isolation ---` block in `scripts/test-all.sh` | RED — pins the mechanism already on `main` that buys P2 for the full battery |
| N3 | Delete the `unset` from `scripts/hooks/pre-push` | RED — the second existing copy |
| N4 | Add a **second** unscrubbed test-runner `run:` to a hook that already has a scrubbed one | RED — proves the check does not stop at the first match in a file |
| N5 | Make the runner-token matcher match nothing (so the guard examines 0 commands) | RED — a floor on the guard's own dispatch: `RUN_LINES == 26` and `RUNNER_LINES >= 2`, asserted, not merely printed |
| N6 | Rename `lefthook.yml` / move a hook script out from under `scripts/hooks/` | RED — the corpus is asserted non-empty per source, not in total |

**Harness rows:**

| # | Edit | Must be |
|---|---|---|
| J1 | Replace the guard body with `exit 0` | RED — the suite asserts a nonzero count of *examined* commands and a nonzero count of *satisfied* assertions, from two independent observables, both incremented at the **call site** and both floored with `printf >&2` + `exit 1` (AP-023) |
| J2 | **Must-PASS, not canonical:** a `run:` line that scrubs using `env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE <runner>` instead of `unset … && <runner>` | GREEN — both spellings are measured-equivalent (§M-6) and the contract permits both |
| J3 | **Must-PASS, not canonical:** a non-test `run:` line with no scrub (`terraform fmt`, `markdownlint`) | GREEN — 24 of the 26 lines are exactly this; a guard that reddened on them would be unusable |
| J4 | Add a comment line containing the literal `bun test` inside `lefthook.yml` | GREEN — the matcher anchors on the `run:` command form, not a bare token (`cq-assert-anchor-not-bare-token`) |

### Guard 3 — fail-loud runtime tripwire

**Property.** A test-runner process that starts while holding any git-location variable **aborts**
before running a single test, naming the variables and the runner.

**Assembly.** One prelude per runner runtime — the complete set is three, because there are three
runtimes: `bunfig.toml` `[test] preload` (bun), `apps/web-platform/test/setup-node.ts` and
`setup-dom.ts` (vitest), and `plugins/soleur/test/test-helpers.sh` (the sourced shell prelude).
This is the layer that covers what neither Guard 1 nor Guard 2 can: an entry point nobody enumerated
(an agent shell with `GIT_DIR` exported, `git rebase -x`, `git bisect run`, an editor's test runner)
and **transitive** spawns — a script under test that runs `git` itself, which no helper and no source
scan can reach.

**Mutation matrix:**

| # | Mutation | Must be |
|---|---|---|
| K1 | Remove a variable from the tripwire's watched set | RED — a run with only that variable set must still abort |
| K2 | Change the tripwire from `process.exit` / `exit` to a warning | RED — it must **fail**, not scrub; an in-process scrub is a false comfort under Bun (§M-5) |
| K3 | Remove the preload registration from `bunfig.toml` (the tripwire file remains) | RED — registration is part of the mechanism, and the guard asserts the tripwire *fired*, not that the file exists |
| K4 | Add a fourth runner runtime without a prelude | RED — the guard asserts one prelude per registered runtime, derived from the runner list, not from a hand-copied set |

**Harness rows:**

| # | Edit | Must be |
|---|---|---|
| L1 | Assert only that the tripwire file contains the variable names | RED — a source grep is satisfied by a comment; the guard must observe a real aborted run and its exit status |
| L2 | **Must-PASS, not canonical:** a run with `GIT_AUTHOR_NAME` and `GIT_CONFIG_PARAMETERS` set but no location variable | GREEN — those leak into fixture commit metadata (a flake source) but are not a write-boundary breach, and the tripwire must not block on them |

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/test/lib/git-tripwire.ts` | **Guard 3**, bun + vitest arm. Exits non-zero when any git-location variable is present at process start, naming them and the runner. |
| `plugins/soleur/test/lib/git-fixture-env.ts` | `gitFixtureEnv(fixtureDir)` — deny-list env constructor for the Bun suites that must pass an explicit `env`, and `gitFixture(fixtureDir)` returning a bound `git(args)` runner. |
| `plugins/soleur/test/git-fixture-env.test.ts` | **Guard 1.** RED-first: victim repo + hostile `GIT_DIR`/`GIT_INDEX_FILE`; asserts victim `HEAD`, `git for-each-ref`, and `git diff --cached --name-only` are each byte-identical before and after. Carries M1-M7 + H1-H4. |
| `plugins/soleur/test/hook-git-env-coverage.test.sh` | **Guard 2.** ~30 lines: parse `lefthook.yml` `run:` lines and `scripts/hooks/*`; assert every test-runner command carries the scrub; assert the examined-set floors (N5, N6). |
| `plugins/soleur/test/git-tripwire.test.sh` | **Guard 3** driver: spawns each runner with a hostile env and asserts a non-zero abort, plus the L2 must-PASS. |

## Files to Edit

Every glob and count below was derived by a command quoted beside it.

| Path | Change |
|---|---|
| `lefthook.yml` | `plugin-component-test` › `run:` — prefix `bun test plugins/soleur/test/` with `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE &&`. **This one line is the fix** (§M-9 probed the exact form, with a control). |
| `bunfig.toml` | Add `[test] preload = ["./plugins/soleur/test/lib/git-tripwire.ts"]` (§M-8 measured the abort, rc=97, and the clean pass, rc=0). |
| `apps/web-platform/test/setup-node.ts`, `apps/web-platform/test/setup-dom.ts` | Import and invoke the tripwire. These are the vitest project setup files (`setupFiles:` in `apps/web-platform/vitest.config.ts`); neither scrubs today. |
| `plugins/soleur/test/test-helpers.sh` | Add the shell tripwire to the sourced prelude. Covers the 17 of 43 `git init` shell suites that source it; the rest are covered by the invocation layer, and the residual is stated in `## Risks`. |
| `scripts/test-all.sh` | **Almost a no-op — do not add a redundant registration.** `SUITE_GLOBS` already contains `plugins/soleur/test/*.test.sh`, which auto-registers both new shell suites (this is how the sibling `fixture-relative-assert.test.sh` is picked up — `grep -n fixture-relative-assert scripts/test-all.sh` returns zero hits), and the bun group runs `bun test plugins/soleur/`, which picks up the new `.test.ts`. The array's own comment warns that a second copy of the list is the mutation it exists to catch. The only real edit is a sentinel comment on the `--- Git Hook Isolation ---` block naming Guard 2 N2. |
| `plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts` | The suite named in the incident report — convert to `gitFixture()`. |
| `plugins/soleur/test/welcome-hook.test.ts`, `plugins/soleur/test/gdpr-gate-repo-scan.test.ts` | The other Bun-discovered fixture-creating suites under `plugins/soleur/test/` (`git grep -ln '"init"\|git init' -- 'plugins/soleur/test/*.test.ts'`). |
| `tests/scripts/test_lint_rule_ids.py` | Remove the git-location family from the existing `_GIT_ENV` dict — which already pins `GIT_AUTHOR_*`/`GIT_COMMITTER_*` and **must keep them** (§M-7). Inline edit; no shared module. |
| `tests/scripts/test_lint_rule_bodies.py` | **Different shape, and the worse one.** It has no `_GIT_ENV` at all: its `_git()` helper calls `subprocess.run(["git", "-C", str(repo), *args], …)` with **no `env` argument**, i.e. total inheritance. Give `_git()` a constructed env with the location family removed and identity pinned. Do not assume the sibling's dict exists here. |
| `tests/scripts/test_rule_id_regex_parity.py` | Verify at `/work` time whether it spawns `git` (`git ls-files 'tests/scripts/*.py'` is **3**, not 2 — the count of python suites in the earlier draft was wrong). If it does, apply the same edit; if not, record that it does not and make no change. |

### Explicitly NOT edited

| Path | Why |
|---|---|
| `apps/web-platform/test/workspace{,-cleanup,-auth-preflight,-error-handling,-symlink-hardening}.test.ts`, `mu1-integration.test.ts` | Already correct **for their runtime**: all six delete the location family and set the ceiling to `tmpdir()`, and vitest runs on Node where a `process.env` deletion propagates (§M-5). Converting them is churn. |
| `apps/web-platform/test/server/agent-ready-git-worktree.test.ts` | Deliberately sets `GIT_DIR` to an unrelated repo as its own subject. The tripwire runs at process start, before the test sets it, so no waiver is needed. |
| `plugins/soleur/test/fixture-{cd-containment,dir-operand-assert,relative-assert}.test.sh` and `lib/fixture-scan.py` | Untouched. The sibling rules keep their corpus and baselines exactly as they are — Guard 2 is a new standalone suite, not a fourth `--rule`, so there is no risk of perturbing them. |
| The 43 shell + ≥10 TS fixture suites | **Deferred** (see below). With P2 and P4 in force, none can observe a hostile env in any reachable invocation. |

### Deferral (`wg-defer-only-after-inline-triage`)

Per-suite conversion to the helper is deliberately deferred to a follow-up issue: *"test-fixtures:
adopt `gitFixtureEnv()` at every fixture-creating suite (defence-in-depth behind #7833's process
boundary)"*. Triaged inline and deferred because (a) it buys nothing over layers 1-3 in any reachable
invocation, (b) the beneficiary set is not reliably greppable (`git grep -l 'git init'` misses the
`["git", ["init", …]]` array form), and (c) coupling a ~50-file diff to the guards guarantees a
rubber-stamp review. Filed with the two conditions that would make it load-bearing — a runner that
cannot host a tripwire, or a fixture that must run `git` with a partially-inherited env — **and** with
all three entries from `## Re-evaluation Triggers` carried into the same issue (AC14), so trigger 3
(the Bun `process.env` behaviour that mutation row M6 rests on) is recorded somewhere durable rather
than only in this plan.

The follow-up must also carry the files that are neither converted nor waived by this plan, so nothing
falls between the two lists: `test/pre-merge-rebase.test.ts` (Bun-run, already isolated via its own
`GIT_ENV` destructure — correct today, but a fourth spelling of the same idea),
`apps/web-platform/test/cc-reprovision-git-discriminator.test.ts` and `worktree-config-seed.test.ts`
(vitest, `git init`, with no `GIT_DIR`/ceiling handling of their own — covered by Guard 3's vitest
prelude once it lands, not by any per-file scrub), `apps/web-platform/infra/workspaces-luks-loopback.test.sh`,
`apps/web-platform/test/helpers/context-queries-fixture.ts` (a helper, not a `*.test.ts`), the four
`tests/**` shell suites, and `.github/scripts/test/test-*.sh`. Enumerated here because the earlier
draft's single `git grep -l 'git init' -- '*.test.sh' '*.test.ts'` derivation is structurally blind to
every one of them — python list-form spawns, `test-*.sh` naming, and helper files all escape it.

## Implementation Phases

Phase order is load-bearing — the fix ships before anything that depends on it.

### Phase 0 — preconditions (measure; do not assume)

1. Re-run §M-1 and §M-9 on the machine of record; paste both tables into the PR body. If `GIT_DIR` is
   absent from a linked-worktree hook, **stop** — the re-evaluation trigger has fired.
2. Re-run §M-5 against the pinned `.bun-version`. The helper's shape is correct either way; only
   mutation row M6 is version-sensitive.
3. Determine how (and whether) `scripts/hooks/*` is installed — `git config core.hooksPath`, and any
   installer. If they are dead files, Guard 2 still covers them (cheap), but say so rather than
   implying they are live.
4. Capture `--rule cd`, `--rule operand`, `--rule relative` `FILES=`/`SITES=` as a control, so the new
   suite registration cannot be blamed for a sibling drift later.

### Phase 1 — the fix (`lefthook.yml`) + RED tests

Write the Guard 1 and Guard 3 suites **first**, against a hostile env and a not-yet-existing helper,
and record the RED output. Then apply the one-line `lefthook.yml` change. This phase alone closes the
reported incident and is independently revertable.

### Phase 2 — the tripwires (Guard 3)

`git-tripwire.ts` + the `bunfig.toml` registration + the two vitest setup files + the
`test-helpers.sh` prelude. Green the Guard 3 driver. Run K1-K4 and L1-L2 and paste the observed table.

### Phase 3 — the entry-point ratchet (Guard 2)

`hook-git-env-coverage.test.sh`. Run N1-N6 and J1-J4 and paste the observed table. N2 and N3 must be
executed against real deletions in a scratch copy, not asserted in prose.

### Phase 4 — the fixture helper (Guard 1)

`gitFixtureEnv()` with the corrected shape: inherit the ambient env, **remove** the location family
(`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`,
`GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_NAMESPACE`) and the exec-hook / config-injection family
(`GIT_SSH_COMMAND`, `GIT_PROXY_COMMAND`, `GIT_EXTERNAL_DIFF`, `GIT_CONFIG_COUNT`,
`GIT_CONFIG_KEY*`, `GIT_CONFIG_VALUE*`), **keep** `PATH`, `HOME`, `TMPDIR`, `LANG`, then set
`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_TERMINAL_PROMPT=0`,
`GIT_CEILING_DIRECTORIES=<realpath of the fixture's parent>`, and **pin**
`GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL`/`GIT_COMMITTER_NAME`/`GIT_COMMITTER_EMAIL` to synthesized values
(`@example.com`, per `cq-test-fixtures-synthesized-only`). Convert the three Bun suites and the two
python `_GIT_ENV` dicts. Run M1-M7 and H1-H4 and paste the observed table.

### Phase 4b — sibling-baseline reconciliation

Run `--rule cd`, `--rule operand`, `--rule relative` and diff against the Phase 0 control. `FILES=`
must have risen by exactly the number of tracked `.sh` files this PR adds (2). If either
row-pinned baseline gained rows from those files, regenerate it with `--write-baseline` **in the same
commit** as the file that caused it — that is the drivers' own stated remediation, and the row-by-row
equality means a fall reddens exactly like a rise.

### Phase 5 — verification

Full battery (`bash scripts/test-all.sh`); a real commit in this linked worktree with the hook live;
`git reflog -n 5` asserted free of any fixture-named subject; and the CI guard job (AC12) exercised
on the PR.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 (the fix).** Extract the `plugin-component-test` command body —
   `awk '/^    plugin-component-test:$/{f=1; next} f&&/^    [a-z0-9-]+:$/{exit} f'` (block-scoped, and
   it terminates on the *next command key* rather than on the first `run:`, so a multi-line
   `run: |` block scalar is captured whole rather than reading as `run: |`) — and assert on that body:
   (a) it names **all three** variables `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`, not `GIT_DIR`
   alone (§M-3 makes `GIT_INDEX_FILE` an independent breach, so a `GIT_DIR`-only fix must fail this);
   (b) the scrub token appears **before** `bun test` in command order, with any trailing `#`-comment
   stripped first, so `bun test … # unset GIT_DIR` does **not** satisfy it (`cq-assert-anchor-not-bare-token`);
   (c) the extracted body is non-empty — a rename of the block that makes the awk print nothing fails
   rather than passes. AC1 is a **snapshot** of one command; Guard 2 (AC7) is the assembly that
   prevents a fourth command being added without it.
2. **AC2 (containment).** `bun test plugins/soleur/test/git-fixture-env.test.ts` passes, asserting
   victim `HEAD`, `git for-each-ref` output, and `git diff --cached --name-only` are each byte-identical
   before and after — three observables, because `HEAD` alone is blind to §M-3.
3. **AC3 (commit works under the helper env).** The Guard 1 suite contains a case that performs a real
   `git commit` through `gitFixtureEnv()` and asserts a non-empty `%an`/`%ae`. Deleting the pinned
   identity from the helper turns it RED (mutation M7).
4. **AC4 (`TMPDIR` survives).** A Guard 1 case runs with `TMPDIR=/var/tmp` and asserts the fixture was
   created under `/var/tmp` (harness row H3). This fails if the helper drops `TMPDIR`.
5. **AC5 (tripwire aborts).** `bash plugins/soleur/test/git-tripwire.test.sh` passes, and it asserts a
   **non-zero exit** from each runner started with `GIT_DIR` set, and a **zero exit** from the same
   runner started clean. Both directions, per §M-8.
6. **AC6 (tripwire is registered, not merely present).** `bunfig.toml` `[test] preload` lists the
   tripwire, and `apps/web-platform/vitest.config.ts`'s `setupFiles` entries both invoke it. Asserted
   by the Guard 3 driver observing a real aborted run (mutation K3), not by a source grep (harness L1).
7. **AC7 (entry-point coverage).** `bash plugins/soleur/test/hook-git-env-coverage.test.sh` passes and
   prints the size of the set it examined: `RUN_LINES=26`, `RUNNER_LINES=2`, `HOOK_SCRIPTS=2`. Each is
   asserted, not merely printed (mutation N5).
8. **AC8 (existing scrubs pinned).** Guard 2 fails when the `unset` is removed from either
   `scripts/test-all.sh`'s `--- Git Hook Isolation ---` block or `scripts/hooks/pre-push` — executed
   against real deletions in a scratch copy, with the observed output in the PR body (N2, N3).
9. **AC9 (no sibling drift — expressed as a DELTA, not as equality).** `plugins/soleur/test/lib/fixture-scan.py`
   is unchanged (`git diff --stat origin/main -- plugins/soleur/test/lib/fixture-scan.py` is empty),
   **and** the three existing rules report exactly the arithmetic this PR predicts. The scanner's
   corpus is `tracked_shell_files(repo_root, "*.sh")` — *all* tracked shell files, not `*.test.sh` —
   so **every new tracked `.sh` file raises `FILES=` by one**. Measured control on `origin/main`:
   `cd FILES=936 SITES=0`, `operand FILES=936 SITES=9`, `relative FILES=936 SITES=1236`. This PR adds
   two tracked `.sh` files (`hook-git-env-coverage.test.sh`, `git-tripwire.test.sh`), so the AC is
   `FILES = 938` on all three rules, and each rule's `SITES` delta is enumerated per file in the PR
   body. Note `cd SITES` is `0` today, so an equality claim on that arm alone is `0 == 0` and proves
   nothing — the `FILES` arm is the load-bearing half.
   **AC9b (sibling baselines regenerated in the same commit).** `plugins/soleur/test/fixture-relative-assert.baseline.txt`
   (262 rows) and `fixture-dir-operand-assert.baseline.txt` are **row-by-row equality-pinned** — their
   drivers state that "a fall reddens exactly like a rise". If either new `.sh` file produces rows
   under those rules, the baselines are regenerated with `--write-baseline` **in the same commit** as
   the file that caused it, per the baselines' own header instruction, and the added rows are listed
   in the PR body. `bash plugins/soleur/test/fixture-relative-assert.test.sh` and
   `fixture-dir-operand-assert.test.sh` both pass.
10. **AC10 (mutation matrices observed).** All three matrices — M1-M7/H1-H4, N1-N6/J1-J4, K1-K4/L1-L2 —
    are executed, each with a GREEN unmutated control row, and the observed tables are committed to
    a `mutation-matrices.md` under this branch's spec directory. A file in the repo, not a paragraph in
    a PR body, so the evidence survives merge. (Written without a literal path here: AC15's citation
    loop greps every `knowledge-base/…​.md` token in this plan and would otherwise flag this plan's own
    forward reference to a file that does not exist until `/work` creates it.)
11. **AC11 (full battery).** `bash scripts/test-all.sh` prints its terminal `=== N/M suites passed ===`
    marker with `N == M`, **and** the three new suites each report a run, not a skip. `test-all.sh`
    carries its own comment that `N/N suites passed` "read IDENTICALLY whether a suite was deliberately
    gated", and the runner has `skip_suite`/`skipped` accounting plus a relevance gate — so `N == M`
    alone is satisfiable by skipping every new suite. Assert each new suite by name in the run list.
12. **AC12 (the guard is exercised where it is green).** CI runs `scripts/test-all.sh` on a runner that
    has no `GIT_DIR`, so Guards 1 and 3 would pass trivially there. The PR therefore adds a CI step
    that invokes the Guard 1 and Guard 3 suites **with `GIT_DIR` and `GIT_INDEX_FILE` deliberately
    exported** at a victim repo, and asserts the expected outcome. A guard that can only fail on a
    developer's laptop is a guard nobody sees.
13. **AC13 (live hook).** Make a real commit in this **linked worktree** with the hook enabled, touching
    a **nested** `plugins/soleur/**/*.md` path (see the gobwas Sharp Edge — a depth-1 file such as
    `plugins/soleur/AGENTS.md` does **not** fire `plugin-component-test`, so verifying on one would
    prove nothing). Capture `git for-each-ref --format='%(refname) %(objectname)'` and
    `git status --porcelain` before and after; both must differ only by the intended commit. Do **not**
    rely on `git rev-parse HEAD@{1}` (after any commit it *is* the previous tip by construction of the
    reflog) or on a "fixture-named subject" scan (the incident's own reflog signature is
    `commit: base` / `commit: change`, which no fixture-name filter would catch).
14. **AC14 (deferral is filed).** The follow-up issue named in `## Deferral` exists, is open, and
    carries **all three** re-evaluation conditions from `## Re-evaluation Triggers` — including
    trigger 3 (Bun `process.env` deletion propagation), which is the sole basis for Guard 1 mutation
    row M6. `gh issue view <N> --json state` reads `OPEN`. It is a plain tracking issue, **not**
    `follow-through`-labelled — that label is reserved for an external dependency awaiting
    verification and is driven from a verification script by the daily sweeper.
15. **AC15 (end-to-end, the reported-incident shape).** Take a **converted** suite — not the guard's
    own — export an absolute `GIT_DIR` and `GIT_INDEX_FILE` pointing at a victim repository, run it
    **directly** (`bash <suite>.test.sh` and `bun test <suite>.test.ts`), and assert the victim's ref
    set, index, and `git status --porcelain` are unchanged. Guards 1 and 3 set their own hostile env,
    which proves the mechanism; this AC proves the mechanism reaches a real suite by the exact path the
    incident took. Do the same for the python arm (`python3 -m unittest tests.scripts.test_lint_rule_ids`
    and `…test_lint_rule_bodies`) — that arm otherwise has no containment assertion at all.
16. **AC16 (citations resolve).** `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{}
    bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` prints nothing. Verified passing on this plan as
    written; keep it passing by citing directories rather than not-yet-created files.

### Post-merge

17. **AC17.** `gh issue view 7833 --json state` reads `CLOSED`, closed by this PR via `Closes #7833`
    in the PR body (not the title).

## Observability

```yaml
liveness_signal:
  what: "hook-git-env-coverage.test.sh verdict — every test-runner hook entry point carries the scrub"
  cadence: "every CI run (registered in scripts/test-all.sh, executed by the ci.yml scripts shard) and every pre-commit full-gate run"
  alert_target: "CI job failure on the PR; lefthook pre-commit refusal locally"
  configured_in: "scripts/test-all.sh suite registration + .github/workflows/ci.yml test-scripts shard"
error_reporting:
  destination: "test runner stderr and the CI job log. No Sentry surface by design — this is build-time developer tooling on observability layer 7 (code executing on a contributor's CLI), not a runtime service"
  fail_loud: "yes — Guard 2 exits non-zero on any uncovered entry point and on a vacuous corpus; Guard 3 aborts the runner process itself with a non-zero status"
failure_modes:
  - mode: "a new hook entry point starts a test runner without the scrub"
    detection: "Guard 2 — enumerates every lefthook run: line and every scripts/hooks/ file, asserts the scrub on each runner command"
    alert_route: "pre-commit refusal locally, CI red on the PR"
  - mode: "an existing scrub is deleted (test-all.sh or scripts/hooks/pre-push)"
    detection: "Guard 2 mutations N2 / N3"
    alert_route: "CI red"
  - mode: "Guard 2's corpus silently stops matching (file renamed, matcher rotted) and it examines 0 commands"
    detection: "asserted floors RUN_LINES=26, RUNNER_LINES>=2, HOOK_SCRIPTS=2 — the guard's own dispatch is floored"
    alert_route: "CI red"
  - mode: "an unenumerated entry point leaks the env anyway (agent shell, git rebase -x, editor runner), or a script under test spawns git transitively"
    detection: "Guard 3 — the runner process aborts non-zero at start, naming the leaked variables and the runner"
    alert_route: "the developer's own terminal, immediately, before any test runs"
  - mode: "the fixture helper degrades to a pass-through, or loses pinned identity"
    detection: "Guard 1 — drives a real git write against a real victim repo and asserts HEAD, refs and index (mutations M5, M7)"
    alert_route: "CI red"
discoverability_test:
  command: "bash plugins/soleur/test/hook-git-env-coverage.test.sh"
  expected_output: "RUN_LINES=26, RUNNER_LINES=2, HOOK_SCRIPTS=2 and a PASS line per examined runner command; exit 0"
```

`ssh` appears nowhere; the first token is `bash`, on preflight Check 10's `PROBE_VERB_ALLOWLIST`
(`curl bash grep rg jq python3 node bun printf git`). No credentials are required, so
`credentials_required` is omitted.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering

**Status:** reviewed — five reviewers (a scoped strong-model advisor, simplicity, architecture,
spec-flow, correctness), plus ten local probes (§Measurements).
**Assessment:** the first draft of this plan aimed its static guard at ~900 test files. Review
converged, from two independent directions, on the same finding: the recurring assembly is the hook
entry-point set (26 `run:` lines + 2 scripts), not the test corpus, and a shape guard over test files
cannot see transitive `git` spawns at all. That redirection cut roughly 85% of the planned change
while covering strictly more of the property. Review also falsified a load-bearing design choice by
measurement — the `buildGitProbeEnv()` allowlist breaks every fixture that commits (§M-7) — which
would have gone red on the first converted file. Residual risk is now concentrated in Guard 3's
prelude registration (one per runtime, mutation K3/K4) rather than in a large diff.

**Product/UX Gate:** not applicable. `## Files to Create` and `## Files to Edit` contain no path
matching the UI-surface term list or glob superset — no `components/**/*.tsx`, no `app/**/page.tsx`,
no `app/**/layout.tsx`. Deliverables are a YAML hook line, three runner preludes, one TS helper, two
shell guards, and two inline python edits. Product is NONE under both the semantic sweep and the
mechanical override.

Not relevant: Legal, Finance, Marketing, Sales, Support, Operations — build-time developer tooling
with no data processing, no vendor, no recurring cost, and no customer-facing surface.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The `test-helpers.sh` tripwire reaches only 17 of the 43 shell fixture suites (measured: `for f in $(git grep -l 'git init' -- '*.test.sh'); do grep -q test-helpers.sh "$f" && …`) | Stated, not papered over. The other 26 are covered at the invocation layer by `test-all.sh` and by the `lefthook.yml` fix; the residual is a *direct* invocation of one of those 26 from a shell that already has `GIT_DIR` exported. Guard 2 prevents new entry points; the deferred sweep closes the residual if it ever bites |
| Guard 3 aborts a developer who has `GIT_DIR` exported for a legitimate reason | That is the intent — fail loud. The abort message names the variables and the remedy (`unset …`), and §M-8 confirms a clean run is unaffected |
| A fourth runner runtime is added with no prelude | Guard 3 mutation K4 derives the expected prelude set from the registered runner list rather than a hand-copied set |
| `scripts/hooks/*` may be dead files, making part of Guard 2 vacuous | Phase 0 step 3 determines the install path and records the answer. Covering them costs ~2 lines either way; claiming they are live without checking would not be acceptable |
| The `lefthook.yml` `unset … &&` form might not be honoured | Probed with a control (§M-9): `0` with the prefix, `2` without |
| The helper's deny-list misses a future `GIT_*` variable | The location family is enumerated from git's own documented set; Guard 1 mutation M1/M2 covers regression on the two that matter, and Guard 3 watches the same set at process start, so a miss shows up as an abort rather than a silent write |

## Re-evaluation Triggers

1. **lefthook or git stops exporting `GIT_DIR` in a linked worktree.** Re-run §M-1. If it is gone, the
   `lefthook.yml` prefix becomes redundant and can be retired; Guards 1 and 3 still hold because they
   set the hostile environment themselves.
2. **The fixture helpers are consolidated so scrubbing happens in exactly one place** — e.g. if
   `plugins/soleur/test/*.test.sh` reaches full `test-helpers.sh` adoption (measured today: 41 of 73;
   17 of the 43 `git init` suites). At that point Guard 3's shell arm becomes a true chokepoint and the
   deferred sweep can be closed as unnecessary.
3. **Bun changes `process.env` deletion propagation** (§M-5). Mutation row M6 must be re-derived; if
   Bun starts matching Node, an in-process scrub becomes a viable additional layer — though the
   tripwire should still fail rather than scrub.

Recorded in the deferred follow-up issue (AC14) so the review is scheduled rather than remembered.
These are conditional revisits, not external-dependency soaks, so they take a plain tracking issue —
**not** the `follow-through` label, which the daily sweeper reserves for "external dependency awaiting
verification" and drives from a verification script.

## Sharp Edges

- **The defect is invisible in a plain clone.** `GIT_DIR` reaches a hook command only in a linked
  worktree (§M-1). Anyone reproducing in a fresh `git clone` will measure "no leak" and conclude the
  issue is stale. Always reproduce in a `git worktree add` checkout.
- **`GIT_INDEX_FILE` is a second, independent breach.** Scrubbing `GIT_DIR` alone leaves an absolute
  `GIT_INDEX_FILE` live, and a fixture's `git add` then stages into the victim's index (§M-3). A guard
  that asserts only `HEAD` passes straight over it.
- **`GIT_CEILING_DIRECTORIES=<the fixture dir>` does not work when git's cwd equals it** (§M-4). Use
  the parent. Both in-repo prior-art sites already do; the issue's suggested spelling is the odd one out.
- **Under Bun, `delete process.env.X` does not reach a default-env child** (§M-5) — Node does. The six
  correct `apps/web-platform/test/workspace*` scrubs work only because vitest runs on Node. Copying
  that shape into a Bun suite is silently ineffective, and a source grep for `delete process.env.GIT_DIR`
  would certify it.
- **Do not reuse `buildGitProbeEnv()` verbatim.** It is a read-only probe env; a fixture `git commit`
  under it fails `Author identity unknown` (§M-7), and it also drops `TMPDIR`, which harness row H3
  depends on. Deny-list plus pinned identity, not allowlist.
- **`test-helpers.sh` is not a chokepoint.** 41 of 73 `plugins/soleur/test/*.test.sh` source it, and
  only 17 of the 43 `git init` suites do. A plan that edits it and calls the sweep done covers 40% of
  the shell fixtures and none of `.claude/hooks/`, `scripts/`, or `plugins/soleur/skills/*/test/`.
- **The beneficiary set is not greppable.** `git grep -l 'git init' -- '*.test.ts'` returns 5; the
  `execFileSync("git", ["init", …])` array form appears in at least 10 more. Any guard whose corpus is
  "test files that spawn git" is starting from a count it cannot verify — which is the strongest reason
  the guard quantifies over entry points instead.
- **`scripts/test-all.sh` already has the fix; `scripts/hooks/pre-push` has it too.** Do not re-add a
  third copy. The gap was never the runner — it was the sibling entry point that bypasses it, and the
  absence of anything measuring the set. Guard 2 mutations N2 and N3 pin both existing copies.
- **`plugins/soleur/**/*.md` does not match `plugins/soleur/AGENTS.md`.** lefthook's gobwas `**`
  requires at least one intermediate directory — the repo's own
  `knowledge-base/project/learnings/2026-03-21-lefthook-gobwas-glob-double-star.md`, cited six times
  inside `lefthook.yml`. So verifying the `plugin-component-test` fix by committing a depth-1 file
  passes while firing nothing. AC13 requires a **nested** path.
- **A commit touching only `*.sh` fires no test runner at all.** No `pre-commit` glob matches `*.sh`
  generically (`bun-test` is `*.{ts,tsx,js,jsx}`; `plugin-component-test` is `plugins/soleur/**/*.md`).
  The shell arm therefore gets no pre-commit exercise, and CI runs in a plain clone with no `GIT_DIR`.
  This is precisely why Guard 3 must be a **runtime abort** rather than a pre-commit check — it is the
  only layer that fires on the path with no gate.
- **CI cannot reproduce the hazard on its own.** `.github/workflows/ci.yml` shards run
  `bash scripts/test-all.sh <group>` after `actions/checkout` — a plain clone (no `GIT_DIR`), and
  `test-all.sh` unsets the family regardless. Guards 1 and 3 are only non-trivially exercised because
  they export a hostile environment **themselves**; AC12 additionally requires a CI arm that does so
  explicitly. A guard that can only fail on a developer's laptop is a guard nobody sees.
- **The scanner's corpus is `*.sh`, not `*.test.sh` — so every new tracked shell file moves `FILES=`.**
  Measured control: all three rules report `FILES=936`. Adding this PR's two `.sh` guards makes it 938,
  and `fixture-relative-assert.baseline.txt` (262 rows) is row-by-row equality-pinned. An AC that
  asserts sibling `FILES=` is *unchanged* deadlocks against the PR's own new files — express the delta
  (AC9), and regenerate the baselines in the same commit (Phase 4b).
- **This is the fourth recurrence** — 2026-03-24 (#1090), 2026-04-03 ×2, now #7833 — each fixed at the
  one site that hurt, none with a ratchet. If this ships the `lefthook.yml` line without Guard 2,
  expect a fifth.
