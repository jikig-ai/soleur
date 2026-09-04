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
| M-9 | Does `unset … && cmd` scrub inside a hook `run:`? | control `2` → prefixed `0` | CONFIRMED |

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
| `web-platform-runtime-plugin-trigger.test.ts` | private `gitCleanEnv()` — landed **#7782, 2026-09-03** |
| `welcome-hook.test.ts` | private `gitCleanEnv()` — landed 2026-04-03 |
| `gdpr-gate-repo-scan.test.ts` | private `gitCleanEnv(envOverrides)` |
| `heartbeat-reprovision-parity.test.ts` | **no scrub** |
| `skill-security-scan.test.ts` | **no scrub** |

That is **three independent copies of one idea** (four counting `test/pre-merge-rebase.test.ts`'s
`GIT_ENV` destructure), the newest landed the day before #7833 was filed — and the suite the
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
