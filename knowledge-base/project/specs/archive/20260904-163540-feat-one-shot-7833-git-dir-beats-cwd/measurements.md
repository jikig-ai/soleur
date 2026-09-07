# Phase 0 measurements — re-run on the machine of record (2026-09-04)

Worktree: `feat-one-shot-7833-git-dir-beats-cwd`. git 2.53.0, bun 1.3.11 (`.bun-version` pins
**1.3.14** — see Residual below), node v22.22.2.

| # | Question | Result | Verdict vs plan |
|---|---|---|---|
| M-1 | Does a git hook export `GIT_DIR`? | **Worktree-conditional.** Plain clone: no `GIT_DIR`; `GIT_INDEX_FILE=.git/index` **relative**. Linked worktree: `GIT_DIR=<bare>/worktrees/<name>` and `GIT_INDEX_FILE=<abs>/index`, both **absolute** | CONFIRMED |
| M-2 | Does `GIT_DIR` beat `cwd` and `-C`? | `git init` left the fixture empty (`.` `..`); `rev-parse --git-dir` printed the victim's `.git`; the commit landed in the victim (HEAD moved, subject `PHANTOM`) | CONFIRMED |
| M-3 | Is scrubbing `GIT_DIR` alone enough? | **No.** With `GIT_DIR` unset and an absolute `GIT_INDEX_FILE`, `git add` staged `g.txt` into the **victim's** index; the fixture index stayed empty | CONFIRMED |
| M-4 | `GIT_CEILING_DIRECTORIES` = fixture dir vs parent | fixture-dir spelling still resolved the enclosing repo; **parent** spelling → `not a git repository` | CONFIRMED — parent is the working spelling |
| M-5 | Does `delete process.env.X` reach a child? | **Bun 1.3.11:** default-env child still sees `GIT_DIR`; explicit `env:{...process.env}` child clean. **Node v22.22.2:** clean both ways | CONFIRMED — *only for an INHERITED variable* (see note) |
| M-6 | Does an invocation-layer scrub fix the Bun case? | `env -u GIT_DIR …` and `bash -c 'unset …; …'`, control without | Both clean; control shows the variables. Both spellings equivalent |
| M-7 | Does a read-only probe allowlist survive a fixture commit? | `env -i PATH HOME GIT_CONFIG_NOSYSTEM=1 … git commit` | **`Author identity unknown`** — an allowlist cannot be reused; an identity must be pinned |
| M-8 | Can a runner prelude abort the run? | a preload that exits 97 when the family is present, with and without | Aborts **rc=97** when set; **rc=0** and the suite passes when clean |
| M-9 | Does `unset … && cmd` scrub inside a hook `run:`? | control `2` → prefixed `0` | CONFIRMED |
| M-10 | Is `scripts/test-all.sh` already protected? | read of its `--- Git Hook Isolation ---` block | **Yes** — landed `dccfd9b0e` (#1090, 2026-03-24) |

**M-5 refinement (not in the plan).** The Bun divergence manifests **only for a variable inherited
from the ambient environment**. A first probe that did `process.env.GIT_DIR = …` then
`delete process.env.GIT_DIR` in the same process showed BOTH children clean and appeared to falsify
M-5. Setting `GIT_DIR` in the parent shell and deleting the inherited value reproduces the plan's
result exactly. Any future re-probe must inherit, not set-then-delete, or it will wrongly read as
"Bun is fine".

## Corpus (Guard 2's closed set)

- `lefthook.yml`: **26** `run:` lines. **2** start a test runner:
  - L250 `SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh` — protected by test-all.sh's own
    `--- Git Hook Isolation ---` `unset` (M-10, landed `dccfd9b0e` / #1090).
  - L254 `bun test plugins/soleur/test/` — **UNSCRUBBED. This is the reported defect.**
- `scripts/hooks/pre-commit` — a lefthook shim; starts no test runner itself (its `test` hits are
  `test -n` / `test -f` builtins). No scrub required.
- `scripts/hooks/pre-push` — runs `bun test` (L109) and `npx vitest run` (L115); **carries the
  `unset` at L24.** Correct today; N3 pins it.

**Installation state (plan Phase 0 step 3).** `core.hooksPath=<bare>/.git/hooks`.
`.git/hooks/pre-commit` is byte-identical to `scripts/hooks/pre-commit` (live).
`.git/hooks/pre-push` is the **lefthook shim**, NOT `scripts/hooks/pre-push` — so that file is
currently **not installed** in this worktree, though it carries the scrub. Guard 2 covers it either
way; recorded here rather than implying it is live.

## Live exposure via the unscrubbed L254

`bun test plugins/soleur/test/` collects `*.test.ts` only. Of the five git-spawning `.test.ts`
suites there, three already carry a **private** `gitCleanEnv()` and two carry nothing:

| Suite | State |
|---|---|
| `web-platform-runtime-plugin-trigger.test.ts` | private `gitCleanEnv()` — landed **#7782 (`5d8a12736`), 2026-09-04** |
| `welcome-hook.test.ts` | private `gitCleanEnv()` — landed 2026-04-03 |
| `gdpr-gate-repo-scan.test.ts` | private `gitCleanEnv(envOverrides)` |
| `heartbeat-reprovision-parity.test.ts` | **no scrub** |
| `skill-security-scan.test.ts` | **no scrub** |

That is **three independent copies of one idea** (four counting `test/pre-merge-rebase.test.ts`'s
`GIT_ENV` destructure), the newest landed the SAME day as #7833 — and the suite the
incident report names was already patched per-file by #7782. This is the plan's central claim
measured rather than argued: the per-file fix has been applied three times and did not generalise
one directory over. The 11 `.test.sh` git-spawning suites in the same directory are not collected by
`bun test`; they run under `test-all.sh` / `pre-push`, both scrubbed.

## Sibling-scanner control (Phase 4b baseline)

`python3 plugins/soleur/test/lib/fixture-scan.py --rule <r> --repo <root>`:

| rule | FILES | SITES |
|---|---|---|
| `cd` | 936 | 0 |
| `operand` | 936 | 9 |
| `relative` | 936 | 1236 |

`FILES` must rise by exactly the number of tracked `.sh` files this PR adds.

## Residual

`.bun-version` pins **1.3.14**; the installed runtime is **1.3.11**, which is also what the plan
measured. M-5's divergence is therefore unverified against the pinned version. The helper's shape is
correct either way — only mutation row M6 is version-sensitive — so this is recorded, not blocking,
and carried into the follow-up's re-evaluation triggers.

---

## Verification record (Phase 5)

| AC | Evidence |
|---|---|
| AC1 (the fix) | `lefthook.yml` `plugin-component-test` → `run: unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE && bun test plugins/soleur/test/` |
| AC2-AC4 (containment) | `bun test plugins/soleur/test/git-fixture-env.test.ts` → **6 pass, 0 fail, 22 expect()**. Includes a real commit under the helper env (AC3) and a `TMPDIR=/var/tmp` fixture with a space- and `-`-leading path segment (AC4) |
| AC5 (tripwire aborts) | `bash plugins/soleur/test/git-tripwire.test.sh` → **20 assertions, 0 failed**. Asserts an observed non-zero abort from each of the three runtimes, not the file's existence |
| AC6 (registered) | `bunfig.toml` → `preload = ["./plugins/soleur/test/lib/git-tripwire.ts"]`; both vitest `setupFiles` import it, derived from `vitest.config.ts` rather than restated |
| AC7-AC8 (entry points) | `bash plugins/soleur/test/hook-git-env-coverage.test.sh` → **8 passed, 0 failed**, receipt `run_lines=26 runners=3 hook_files=2 assertions=8`. N2/N3 pin the two pre-existing scrub copies |
| AC9 (no sibling drift) | `FILES` 936 → **940** = +4, exactly the tracked `.sh` files added. `cd` SITES 0 → 0; `operand` 9 → 9; `relative` 1236 → 1243 (+7, all in the two new batteries), baseline regenerated in the same commit. All three sibling suites pass |
| AC10 (mutation matrices) | Guard 1 **10/10** (M1-M8, H1-H2); Guard 2 **10/10** (N1-N6, J1-J4); Guard 3 K/L matrix observed in its driver output |
| AC11 (full battery) | `test-all.sh` refused with **rc=4** — a sibling worktree's full-gate run was in flight (#7553). Per that contract, targeted suites were run instead: bun `plugins/soleur/test/` **2563 tests / 0 fail**, webplat vitest **1060 files, 13081 tests, 0 fail (rc=0)**, and every affected shell + python suite individually. The full battery runs at `/ship` Phase 4 (ADR-183) |
| AC13 (live hook) | Real commit `297569daf` in this linked worktree, hooks **live**. `plugin-component-test` ran (50.27 s, 2553 pass / 0 fail), commit rc=0, depth +1 exactly, **0 phantom subjects** in `git reflog` |
| AC14 (deferral filed) | **#7849** — OPEN, `type/chore` + `deferred-scope-out`, carries both load-bearing conditions, the between-the-lists file enumeration, and all three re-evaluation triggers |
| AC15 (end-to-end) | Under the real hook env (`GIT_DIR`/`GIT_INDEX_FILE` set as git exports them to a linked-worktree hook): **Arm A** — the unfixed command form — now aborts `rc=97` instead of corrupting silently; **Arm B** — the shipped form — runs clean (2563 tests). Branch tip unmoved; reflog free of `base`/`change`/fixture subjects |
| AC16 (citations) | 10 distinct `knowledge-base/**.md` citations in the plan, **0 missing** |

### A note on the glob, found while discharging AC13

`plugin-component-test`'s glob is `plugins/soleur/**/*.md`, which does **not** match a file sitting
directly in `plugins/soleur/` — a first attempt staging `plugins/soleur/AGENTS.md` reported
`plugin-component-test (skip) no matching staged files`. The job fires only for `.md` files in a
subdirectory. Recorded rather than changed: widening the glob is out of scope here, and the entry
point is now scrubbed either way.

## Cost (added after review — this record had none)

For a change that adds work to every file of a 1114-file suite, a cost figure belongs here.

| Arm | Cost | Method |
|---|---|---|
| bun preload | once per PROCESS, inside the ~10-20 ms bun startup floor | counter preload: 1 execution for 6 test files |
| vitest, as first shipped (`setupFiles`) | **~20 ms per FILE** → ~22 CPU-s, **~1.7 s wall** (~1.2% of a 136 s suite) | 120-file ABBA A/B (deltas 1.94 s / 2.76 s, same sign both blocks) and a within-run paired probe (24.5 ms vs 7.7 ms, paired delta 16.8 ms, apparatus floor 0.58 ms). A whole-run 40-file A/B could NOT resolve it — per-run SD ~1.3 s against a ~0.3 s effect — and is reported as unresolved rather than as a number |
| vitest, as shipped (`globalSetup`) | **once per RUN** | `globalSetup` executes in vitest's main process — the one that actually inherited the environment, and the one workers fork from. The property is unchanged and rc=97 now propagates instead of vitest's aggregate 1 |
| Guard 1 suite | 0.485 s; 34 `git`, 3 `bun`, 1 `bash` spawn | PATH shims counting and exec'ing the real binary. The two driver children are ~35 ms (~7%); the git spawns dominate. Kept — written the mutate-`process.env` way, mutation rows M4/M6 both SURVIVED, which is why the child exists |
| Guard 3 driver | 2.89 s → ~1.9 s after pointing the three clean-control arms at a one-assertion probe instead of re-running the full Guard 1 suite | ~1.5 s of the original was three redundant Guard 1 runs, which also coupled L2's verdict to Guard 1's health |
| Guard 2 | 0.23 s | pure static |

Guard 1 also leaked 7 temp directories per run with no cleanup (922 accumulated on the dev box,
~106 MB) and wrote its driver file to the `TMPDIR` root rather than anywhere sweepable. Now one
owning scratch root removed in `afterAll`; measured delta after the fix is 0 directories per run.
