# Tasks — fix(test-fixtures): stop the inherited git environment at the test-runner boundary (#7833)

Plan: `knowledge-base/project/plans/2026-09-04-fix-test-fixture-git-env-scrub-plan.md`
Branch: `feat-one-shot-7833-git-dir-beats-cwd` · Closes #7833

Phase order is load-bearing: the one-line fix ships before anything that depends on it, and the RED
tests precede the helper (`cq-write-failing-tests-before`).

## 1. Phase 0 — preconditions (measure; do not assume)

- [ ] 1.1 Re-run the hook-env probe (§M-1) on the machine of record: scratch repo, `lefthook install`,
      a `pre-commit` command dumping `env | grep '^GIT_'`; repeat inside a `git worktree add` checkout.
      Paste both tables into the PR body. **If `GIT_DIR` is absent in the worktree arm, STOP** — the
      re-evaluation trigger has fired.
- [ ] 1.2 Re-run the `unset … && <cmd>` probe inside a real lefthook `run:` string (§M-9), with the
      no-prefix control. Expected: `0` with the prefix, `2` without.
- [ ] 1.3 Re-run the Bun-vs-Node `delete process.env` divergence probe (§M-5) against the pinned
      `.bun-version`. Record the result; only mutation row M6 is version-sensitive.
- [ ] 1.4 Capture the scanner control: `python3 plugins/soleur/test/lib/fixture-scan.py --rule <cd|operand|relative> --repo .`
      for all three rules. Expected on `origin/main`: `FILES=936` for each; `SITES` = 0 / 9 / 1236.
      This is the baseline AC9 measures its delta against.
- [ ] 1.5 Determine how `scripts/hooks/*` is installed (`git config core.hooksPath`, any installer).
      Record the answer — Guard 2 covers those files either way, but the plan must not imply they are
      live if they are not.
- [ ] 1.6 Confirm `plugins/soleur/test/test-helpers.sh` › `assert_fixture_dir()` is still the
      byte-identical canonical copy before adding a prelude beside it.

## 2. Phase 1 — the fix, and the RED tests first

- [ ] 2.1 Write `plugins/soleur/test/git-fixture-env.test.ts` (Guard 1) against a helper that does not
      exist: victim repo, hostile absolute `GIT_DIR` + `GIT_INDEX_FILE` set by the test itself, and
      three observables asserted before/after — `HEAD`, `git for-each-ref`,
      `git diff --cached --name-only`. Record the RED output.
- [ ] 2.2 Add the Guard 1 case that spawns a **shell script** which runs `git init`, proving the
      constructed env reaches transitive spawns and not only direct `git` calls.
- [ ] 2.3 Write `plugins/soleur/test/git-tripwire.test.sh` (Guard 3 driver) against tripwires that do
      not exist. Record the RED output.
- [ ] 2.4 Re-run 2.1 against a deliberately pass-through helper (`return { ...process.env }`) and
      record that RED too — this is mutation M5 executed *before* the implementation, not after.
- [ ] 2.5 Edit `lefthook.yml` › `plugin-component-test` › `run:`: prefix
      `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE &&` before `bun test plugins/soleur/test/`.
      **This one line is the fix.** Keep it as its own commit so it is independently revertable.

## 3. Phase 2 — the fail-loud tripwires (Guard 3)

- [ ] 3.1 Create `plugins/soleur/test/lib/git-tripwire.ts`: exit non-zero when any git-location
      variable is present at process start, naming the variables, the runner, and the remedy. It must
      **fail**, never scrub — an in-process scrub is a false comfort under Bun (§M-5).
- [ ] 3.2 Register it in root `bunfig.toml` as `[test] preload`.
- [ ] 3.3 Invoke it from `apps/web-platform/test/setup-node.ts` and `setup-dom.ts` (the vitest
      `setupFiles` entries; neither scrubs today).
- [ ] 3.4 Add the shell tripwire to `plugins/soleur/test/test-helpers.sh`. Note the measured residual:
      only 17 of the 43 `git init` shell suites source it — state it, do not paper over it.
- [ ] 3.5 Green `git-tripwire.test.sh`. Assert **both** directions: non-zero abort with `GIT_DIR` set,
      zero exit and a passing suite when clean.
- [ ] 3.6 Run mutations K1-K4 and harness rows L1-L2; record the observed table.

## 4. Phase 3 — the entry-point ratchet (Guard 2)

- [ ] 4.1 Create `plugins/soleur/test/hook-git-env-coverage.test.sh`: parse every `run:` line in
      `lefthook.yml` (both `pre-commit` and `pre-push`) and every file under `scripts/hooks/`; assert
      each test-runner command carries the scrub.
- [ ] 4.2 Floor the guard's own dispatch — `RUN_LINES=26`, `RUNNER_LINES>=2`, `HOOK_SCRIPTS=2`,
      asserted and not merely printed. Per **AP-023**, floors report with `printf >&2` + `exit 1`,
      never through the suite's `fail`/`bad` helper, and the case counter moves at the **call site**,
      never inside `$( )`.
- [ ] 4.3 Anchor the runner matcher on the `run:` command form, not a bare token, so a comment
      containing `bun test` reads GREEN (`cq-assert-anchor-not-bare-token`).
- [ ] 4.4 Run mutations N1-N6 and harness rows J1-J4. Execute N2 and N3 against **real deletions** in a
      scratch copy of `scripts/test-all.sh` and `scripts/hooks/pre-push` — not asserted in prose.
      Record the observed table.

## 5. Phase 4 — the fixture helper (Guard 1)

- [ ] 5.1 Create `plugins/soleur/test/lib/git-fixture-env.ts`. Shape: inherit the ambient env;
      **remove** the location family (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`,
      `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_NAMESPACE`) and the exec-hook /
      config-injection family (`GIT_SSH_COMMAND`, `GIT_PROXY_COMMAND`, `GIT_EXTERNAL_DIFF`,
      `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY*`, `GIT_CONFIG_VALUE*`); **keep** `PATH`, `HOME`, `TMPDIR`,
      `LANG`; then set `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`,
      `GIT_TERMINAL_PROMPT=0`, `GIT_CEILING_DIRECTORIES=<realpath of the fixture's PARENT>`.
- [ ] 5.2 **Pin the identity**: `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL`/`GIT_COMMITTER_NAME`/
      `GIT_COMMITTER_EMAIL` to synthesized values (`@example.com`, per `cq-test-fixtures-synthesized-only`).
      Without this a fixture `git commit` fails `Author identity unknown` (§M-7) — this is the concrete
      regression the read-only-probe allowlist would have introduced.
- [ ] 5.3 Export `gitFixture(fixtureDir)` returning a bound `git(args)` runner that passes both `cwd`
      and the constructed `env` on every call.
- [ ] 5.4 Convert `plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts` (the suite named in
      the incident report).
- [ ] 5.5 Convert `plugins/soleur/test/welcome-hook.test.ts` and
      `plugins/soleur/test/gdpr-gate-repo-scan.test.ts`. **Read
      `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`
      before touching `welcome-hook.test.ts`** — it is the file that was already fixed once for this
      exact defect under this exact lefthook command, five months ago. Confirm the helper subsumes
      that per-file fix rather than leaving a fourth spelling of it in place. That learning also
      names `Bun.spawnSync()` as a spawn form the constructed env must reach, alongside
      `execFileSync`.
- [ ] 5.6 `tests/scripts/test_lint_rule_ids.py`: strip the location family from the existing
      `_GIT_ENV` dict — **keep** its `GIT_AUTHOR_*`/`GIT_COMMITTER_*` pins.
- [ ] 5.7 `tests/scripts/test_lint_rule_bodies.py`: **different shape** — its `_git()` helper passes
      **no `env` at all** (total inheritance, worse than a spread). Give it a constructed env with the
      location family removed and identity pinned. Do not assume `_GIT_ENV` exists here.
- [ ] 5.8 `tests/scripts/test_rule_id_regex_parity.py`: verify whether it spawns `git`
      (`git ls-files 'tests/scripts/*.py'` is **3**, not 2). Apply the same edit if it does; record
      that it does not if it does not.
- [ ] 5.9 Run mutations M1-M7 and harness rows H1-H4; record the observed table. H3 (`TMPDIR=/var/tmp`,
      a fixture name with a space and a `-`-leading segment) must read GREEN — it is what makes
      `TMPDIR` load-bearing in 5.1.

## 6. Phase 4b — sibling-baseline reconciliation

- [ ] 6.1 Re-run all three scanner rules and diff against the 1.4 control. `FILES=` must have risen by
      exactly the number of tracked `.sh` files this PR adds (**2**) → `FILES=938`.
- [ ] 6.2 If either row-pinned baseline gained rows from the new `.sh` files, regenerate it with
      `--write-baseline` **in the same commit** as the file that caused it — the drivers' own stated
      remediation. `fixture-relative-assert.baseline.txt` is 262 rows and equality-pinned row by row;
      a fall reddens exactly like a rise.
- [ ] 6.3 `bash plugins/soleur/test/fixture-relative-assert.test.sh` and
      `fixture-dir-operand-assert.test.sh` both pass. Confirm
      `git diff --stat origin/main -- plugins/soleur/test/lib/fixture-scan.py` is **empty**.

## 7. Phase 5 — verification

- [ ] 7.1 `bash scripts/test-all.sh` → terminal `=== N/M suites passed ===` with `N == M`, **and** each
      of the three new suites named in the run list (not skipped — `N == M` alone is satisfiable by
      skipping them).
- [ ] 7.2 AC12: add a CI arm that runs the Guard 1 and Guard 3 suites with `GIT_DIR` and
      `GIT_INDEX_FILE` deliberately exported at a victim repo. CI checks out a plain clone, so without
      this the guards are trivially green there.
- [ ] 7.3 AC15 end-to-end: take a **converted** suite, export absolute `GIT_DIR`/`GIT_INDEX_FILE`, run
      it **directly** (`bash …`, `bun test …`, and `python3 -m unittest …`), assert the victim's ref
      set, index and `git status --porcelain` unchanged.
- [ ] 7.4 AC13 live hook: real commit in this **linked worktree**, touching a **nested**
      `plugins/soleur/**/*.md` path — a depth-1 file such as `plugins/soleur/AGENTS.md` does not match
      lefthook's gobwas `**` and would verify nothing. Compare `git for-each-ref` and
      `git status --porcelain` before/after.
- [ ] 7.5 AC1: assert the `plugin-component-test` command body names all three variables, with the
      scrub before `bun test` in command order and trailing comments stripped.
- [ ] 7.6 AC16: citation loop over the plan prints nothing.

## 8. Ship

- [ ] 8.1 File the deferral issue (AC14): the per-suite adoption follow-up, carrying its two
      load-bearing conditions **and** all three entries from `## Re-evaluation Triggers`, plus the
      enumerated files that are neither converted nor waived. Plain tracking issue — **not**
      `follow-through`-labelled.
- [ ] 8.2 Commit the three observed mutation tables to a `mutation-matrices.md` under this branch's
      spec directory (AC10) so the evidence survives merge.
- [ ] 8.3 `Closes #7833` in the PR **body**, not the title.
- [ ] 8.4 Render `decision-challenges.md` into the PR body and file it as an `action-required` issue.
