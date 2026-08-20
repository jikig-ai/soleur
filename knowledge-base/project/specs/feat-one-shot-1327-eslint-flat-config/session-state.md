# Session state — #1327 ESLint flat-config migration

Written 2026-08-20. Branch `feat-one-shot-1327-eslint-flat-config`,
worktree `.worktrees/feat-one-shot-1327-eslint-flat-config`, PR #7618 (draft), closes #1327.

**HEAD `3f8ffa5dd` — working tree clean, pushed, `origin` in sync.**

## Verified (each by running the stated command, not by inference)

- **Phases 1-7 complete.** 7 commits beyond `origin/main`.
- **Full local gate GREEN at `3f8ffa5dd`:** `bash scripts/test-all.sh`, rc=0 —
  `338 suites: 334 passed, 0 failed, 0 killed, 4 skipped (declined — not relevant to this diff)`,
  `orphan test suites: none`. All three shards ran: `apps/web-platform` (webplat, 218s),
  `plugins/soleur` (bun, 63s), the `scripts/` set. Coverage NOTE confirms
  `apps/web-platform/infra/` is out of scope (diff does not touch it).
- **AC1-AC14 verified** by each criterion's literal command. AC15 (PR body `Closes #1327`,
  reference #7594 as unblocked but NOT closed) lands at ship.
- **Mutation batteries: 17 rows total, every row RED as contracted, unmutated control GREEN first.**
  11 rows for Guards 1+2 and the harness; 6 rows for Guard 3. The must-PASS row H2 (a config
  reporting non-zero findings still satisfies Guard 1) is demonstrated by the control run itself,
  not by a battery row.
  - **Correction to carry into the PR body:** commit `4c3fa6404`'s message says "18 rows".
    The re-derived count is **17** (`grep -cE '^\[' /var/tmp/mutbat-1327.out` = 11,
    `… mutbat2-1327.out` = 6). Do not restate 18.
  - Two rows are labelled rather than glossed: **G2-M3** (`ignores: ["**"]`) reds via a config
    error, NOT via the anti-vacuity floor the matrix names — the floor is proven non-vacuous
    independently by **G1-M4** (11 files scanned against a floor of 500).

## CI at `3f8ffa5dd`

67 SUCCESS / 3 SKIPPED / **1 FAILURE**.

The failure is `plugin-root-propagation-gate`, and it is **environmental, not a code defect**:
the job invokes Claude Code and all three attempts returned `Credit balance is too low`
(exit 3). Re-run it once credit is restored; do not debug the diff for it.

## Review — INCOMPLETE. This is the blocker.

The operator authorised the **full panel (~11 agents)**. A process restart then dropped the
`soleur:*` agent types (only `claude`, `Explore`, `general-purpose`, `feature-dev:*` and
`pr-review-toolkit:*` resolve now).

**No findings have been collected yet.** Five agents were in flight when this state was written;
their transcripts persist and they are RESUMABLE BY ID (resume, never respawn — a fresh spawn
loses partial findings):

| Lens | Agent id | Status |
|---|---|---|
| security-sentinel | `a231f7387e9bfbdef` | resumed after restart, in flight |
| test-design-reviewer (find the vacuity my battery MISSED) | `a494a7041e56170ad` | resumed after restart, in flight |
| structural-enumeration seat (guard assembly map) | `ac4a582efc70a8e66` | resumed after restart, in flight |
| silent-failure-hunter (fail-open paths) | `ab3eec58920dfe6b9` | spawned, in flight |
| comment-analyzer (falsify added prose claims) | `ac6d16bbe981bd42c` | spawned, in flight |

**Lenses NOT yet run:** architecture-strategist, performance-oracle, data-integrity-guardian,
agent-native-reviewer, pattern-recognition-specialist, code-quality-analyst, semgrep-sast.
semgrep needs no agent — it is a CLI, already bootstrapped at `/home/jean/.local/bin/semgrep`;
run it directly from the repo root with
`--config=plugins/soleur/skills/review/references/semgrep-custom-rules.yaml --config=p/javascript --config=p/typescript`
and confirm the run was non-vacuous (`Ran N rules on M files`, N non-zero).

If any scope-out filing is proposed, the CONCUR gate needs `code-simplicity-reviewer`; the
available substitute is `pr-review-toolkit:code-simplifier`.

## Do NOT

- Do not chain to `/compound` -> `/ship`. The review is incomplete, so the pipeline position is
  "finish /review", and a degraded review must not emit a full-strength evidence trailer.
- Do not re-run the mutation batteries to re-verify them; they passed. The open question is the
  axes they did NOT edit, which is what the resumed test-design agent is for.
- Do not treat the `plugin-root-propagation-gate` red as a diff defect.

## Findings so far — security-sentinel (agent `a231f7387e9bfbdef`) RETURNED

It re-derived the advisory data independently (`gh api /advisories` + the npm bulk endpoint)
rather than taking my derivation on trust.

**Confirmed correct:** floors 1.1.18 / 2.1.4 / null / null / 5.0.9; the "no patched 3.x/4.x"
conclusion; the fail-closed branches (it executed the `semverGte` + `hasOwnProperty` logic against
`1.1.17`, `3.0.6`, `4.0.1`, `5.0.8`, `6.0.0`, `0.1.0`, `5.0.9-beta.1` — all BLOCKED, and no
version passes while vulnerable). All four lockfiles clean; the override removal changed no other
resolution (`--numstat` = `40 0`, additions only). `lint-webplat` absent from all three
required-check ABI locations; no new secret/supply-chain surface (`pull_request`, not
`pull_request_target`; no `secrets:`). No demoted rule has a primary security function.

**To fix inline (not yet applied):**

- **P2, pr-introduced — six phantom dependencies.** `apps/web-platform/eslint.config.mjs` imports
  `@eslint/js`, `@next/eslint-plugin-next`, `@typescript-eslint/eslint-plugin`,
  `@typescript-eslint/parser`, `globals`, `eslint-plugin-react-hooks`; **none is declared** in
  `apps/web-platform/package.json` — all six resolve only by npm hoisting. `eslint-config-next`
  declares the parser as `^5 || ^6 || ^7 || ^8`, so a Dependabot bump can move it across three
  majors unconstrained. Also the config's own comment attributes all six to `eslint-config-next`,
  but `@eslint/js` and `globals` come from `eslint`. Fix: declare all six in `devDependencies`
  with explicit ranges, and correct the comment.
- **P3, pr-introduced — the advisory count in the Guard 3 header is wrong.** There are **seven**
  advisories, **four** HIGH; the comment says six and "three of them HIGH". Missing:
  **GHSA-832h-xg76-4gv6 (HIGH, `< 1.1.7`)**. No floor impact, but the block presents itself as an
  exhaustive re-derivation. Same text is mirrored in `scripts/assert-dependabot-drain.py`.
- **P3, pr-introduced — "no patched 3.x" is imprecise.** GHSA-rgw5 names `3.0.6` as first_patched
  for 3.x and npm ships it under dist-tag `maintenance-v3`. The precise claim is "no 3.x release
  clears *all* advisories". Encoding `null` stays the right conservative choice; the comment
  should say so rather than asserting no patched release exists.
- **P3, pr-introduced (latent, currently empty) — `.mts` gap.** The TS block matches `**/*.mts`
  but `tsconfig.json`'s `include` does not, so a future `.mts` file would get neither `no-undef`
  nor `tsc --noEmit`. `git ls-files '**/*.mts'` returns 0 today.
- **P3, pre-existing — not a demotion, worth a follow-up.** `no-eval`, `no-implied-eval`,
  `no-new-func`, `no-script-url` are not in `eslint:recommended` and so are off; `react/no-danger`
  is off because `eslint-plugin-react` ships via `eslint-config-next` but is never registered,
  while five files use `dangerouslySetInnerHTML` including the inbound-email render path.

## Findings — structural-enumeration seat (agent `ac4a582efc70a8e66`) RETURNED

It settled mechanism claims by probe, not assertion. **Measured at HEAD, eslint 9.39.4: 2019
files scanned, 192 findings, ALL warnings (errorCount 0), exit 0, 1880 files finding-free.**

Verdict: **all three guards' assemblies are NARROWER than the properties they name.**

### Guard 1 — "non-interactive and terminates"

- **It never runs `npm run lint`.** `runEslint()` reads `pkg.scripts.lint` then spawns the eslint
  binary directly, so `prelint`/`postlint` hooks are outside the window entirely
  (`"postlint": "next lint"` passes every guard).
- **"Terminates" has no enforcing assertion.** `execFileSync` is called with no `timeout` option
  and blocks the vitest worker's event loop, so the `600_000` test timeout **cannot fire**. A
  config with a top-level infinite loop hangs CI to its 6-hour ceiling instead of reddening.
- **`eslint.config.js` shadow.** Probe confirmed `.js` outranks `.mjs`. Test 2 asserts only that
  `.mjs` EXISTS, so `cp eslint.config.mjs eslint.config.js` makes the reviewed file dead code
  with all guards green.
- Shell operators survive when paired with `--no-error-on-unmatched-pattern`
  (`"eslint . --no-error-on-unmatched-pattern ; read x"` yields a normal report while
  `npm run lint` blocks forever).
- **Nothing asserts the CI job or its ESLint step exists.** Deleting the `- name: ESLint` step
  leaves all three guards green with zero linting in CI.

### Guard 2 — "the finding set is pinned"

- **The floor is 500 against an actual 2019, over 1880 finding-free files — 1519 files of
  headroom.** Adding `"app/api/**"` to `ignores` un-scans **the entire API-route layer** (109
  files, zero findings): `results.length` 2019 -> 1910, `byRule` byte-identical, both assertions
  green.
- **`MEMO.status` is captured and never asserted by any test.** Nothing pins the gate's VERDICT,
  only its report — `"lint": "eslint . --max-warnings 0"` keeps Guard 2 green while turning CI red.
- **`MIN_FILES_SCANNED` has no value assertion**; the harness regex only checks the identifier
  appears, so `const MIN_FILES_SCANNED = 1;` still matches. The baseline also has no monotonicity
  direction — it can be re-pinned upward silently.
- No test-count floor, so a whole `it(...)` block is deletable (`expect.assertions` floors cover
  gutting a body, not deleting the test).

### Guard 3 — "the dependency tree stays repaired"

- **The repo ROOT `package.json` already carries a top-level blanket
  `"brace-expansion": "^1.1.16"`** — one directory outside the guard's window, in exactly the
  shape test 2 forbids. Inert today only because root's sole minimatch is 3.1.5. **My Guard 3
  comment asserts the repo root uses only "a SCOPED override (the `gray-matter` -> `js-yaml`
  shape)" — that claim is FALSE and must be corrected.**
- A NESTED override (`"minimatch": { "brace-expansion": "^5" }`) escapes the exact-key lookup in
  test 2; only the behavioral probe (test 4) would catch it.
- All four assertions read `.version` only, never `resolved`/`integrity`, so a registry redirect
  serving different bytes under an identical version string passes both guards.
- Advisory-table staleness has no freshness assertion anywhere — shared blind spot with the drain.
- Guard 3 vs `assert-dependabot-drain.py` are NOT redundant and can disagree: e.g. an override
  added to `apps/web-platform/package.json` without regenerating the lock reds Guard 3 and the
  drain calls the tree CLEAN (it reads no package.json at all).

## Still in flight (resumable by id, transcripts on disk)

| Lens | Agent id |
|---|---|
| test-design-reviewer — find the vacuity my battery missed | `a494a7041e56170ad` |
| silent-failure-hunter — fail-open paths | `ab3eec58920dfe6b9` |
| comment-analyzer — falsify the added prose claims | `ac6d16bbe981bd42c` |

## Blocked: commits are failing in this session

`git commit` hangs and dies with `ssh-keygen died of signal 15`. Config is correct
(`gpg.format=ssh`, `user.signingkey=/home/jean/.ssh/github.pub`, `commit.gpgsign=true`) and both
keys ARE loaded in the agent (`ssh-add -l` lists them), so this is the `gcr` keyring agent
(`SSH_AUTH_SOCK=/run/user/1001/gcr/ssh`) blocking on a confirmation prompt that a non-interactive
shell cannot answer. **This file may therefore be uncommitted — check `git status` first.**

## Findings — silent-failure-hunter (agent `ab3eec58920dfe6b9`) RETURNED

Every item below was DEMONSTRATED with a working mutant, not argued. Measured baseline:
`eslint . -f json` exits 0 over 2019 files / 192 findings, **all warnings, errorCount 0**, and
only **139 of 2019 files carry any finding**.

### Block on these three

- **F1 CRITICAL, silent — Guard 2's two assertions are jointly satisfiable with 75% of the tree
  unlinted.** `MIN_FILES_SCANNED=500` against an actual 2019, over 1880 finding-free files. The
  agent built a config ignoring 1519 finding-free files: `results.length` = 500 (floor passes),
  `total` = 192, `byRule` byte-identical. **Fully green with 1519 of 2019 files (75.2%) unlinted.**
  The per-rule breakdown cannot help — every dropped file had zero messages. Fix: pin
  `results.length` with a real lower bound (`>= 1900`), or assert coverage per top-level directory
  (test/ 1142, server/ 317, components/ 220, app/ 165, lib/ 106).
- **F2 CRITICAL, silent — the harness self-guard loses to all three obvious mutations.** Its
  comment claims "a comment can name `toEqual`, but it cannot produce this construct" — false, a
  comment CAN contain the construct verbatim. Green under: (A) assertions commented out with the
  pinned text pasted back as a `//` comment; (B) `it.skip(` on both Guard 2 tests, source text
  untouched; (C) `MIN_FILES_SCANNED = 0` — the guard asserts `BASELINE_FINDINGS > 0` but never
  the same for `MIN_FILES_SCANNED`, closing the inline `>= 0` form and leaving the
  set-the-constant-to-0 form open. Fix: floor `MIN_FILES_SCANNED`, assert no
  `it.skip`/`describe.skip`/`.todo`, and strip `//` lines before regex-matching.
- **F3 CRITICAL, silent — every CVE floor in the drain table can be zeroed and the script exits 0.**
  `MIN_ROWS`/`MIN_RESOLVED` are floors on COUNTS; nothing asserts the fourth tuple element, which
  is the only thing the table exists to enforce. Setting all 19 thresholds to `"0.0.0"` prints a
  confident clean summary and exits 0. **`assert-dependabot-drain.py` has no test file at all.**
  `scripts/lint-dual-lockfile.test.sh:192` is the in-repo precedent for guarding exactly this.

### Also fix

- **F4 HIGH — deleting a lockfile from `LOCKS` exits 0**, which is the precise regression the
  code comment above `"spike"` says was fixed ("a vulnerable copy here was asserted clear by
  nobody"). No floor on `len(LOCKS)`. Repointing a path IS caught; deletion is not. Fix:
  `MIN_LOCKS = 4`, mirroring `lint-dual-lockfile.sh`'s `MIN_PACKAGE_LOCK_DIRS=4`.
- **F5 HIGH — substituting a row's package name for another REAL package keeps the count at 19**
  and silently drops the original from the watched set. A mistype deflates and IS caught; a
  substitution is not. Fix: assert the watched set contains its known-required members.
- **F6 HIGH — `status` is captured, memoized, returned, and never asserted** (line 119 is its last
  mention). Two consequences, both measured: `eslint . --max-warnings 0` exits 1 with a
  byte-identical report, so **CI goes red while the guard suite stays green**; and Guard 1's third
  test passes against a shim that prints `[]` and exits 2. Fix: `expect(status).toBe(0)` — the
  single highest-value one-line fix in the set.
- **F7 HIGH — `lint-webplat` can go green having linted 11 of 2019 files.** `export default []`
  exits 0 with `results.length` 11. The job has no anti-vacuity floor of its own; its entire
  anti-vacuity story lives in a different job on a different matrix. (npm-ci failure and eslint
  crash ARE handled correctly.)
- **F8 MEDIUM — the catch discards `err.code`/`err.message`**, so every spawn failure (ENOENT,
  EACCES, ENOBUFS, OOM) prints the same fabricated `exit 1 ... stderr: (empty)`. The replacement
  buries a different cause as thoroughly as the one it replaced.
- **F9 MEDIUM — fatal parse errors bucket as `(unused-disable-directive)`** (`m.ruleId ?? ...`),
  so an unparseable file is reported as "32 stale disable directives". Fix: branch on `m.fatal`
  first and pin `(fatal-parse-error): 0`.
- **F10/F11/F12 LOW** — `braceExpansionResolutions()` doesn't guard `v.version`; `execFileSync`
  has no `timeout` and its comment's claim that a stdin wait "throws" is false (with
  `stdio[0]="ignore"` a reader gets EOF); a `ci.yml` comment is glued to the new job.

### Clean, verified

Guard 3's floor logic (22 version strings driven through `undefined`/`null`/`semverGte` — all
unparseable input fails CLOSED, including the subtle `NaN` path). The agent also singled out the
brace-glob probe as **the best-built guard in the PR**: it anticipates its own
`JSON.parse(stdout || "[]")` fail-open and closes it by asserting the glob actually MATCHED.
