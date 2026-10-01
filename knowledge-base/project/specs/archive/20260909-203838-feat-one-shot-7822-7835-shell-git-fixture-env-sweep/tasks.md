# Tasks — shell git-fixture containment sweep (PR 2, #7822 / #7835)

Plan: `knowledge-base/project/plans/2026-09-09-fix-shell-git-fixture-containment-sweep-plan.md`

Lane: `cross-domain` (no `spec.md` exists for this branch — fail-closed default per TR2).

## Phase 0 — preconditions (measure; do not assume)

- [ ] 0.0 Write the three predicate clauses (`_creates` / `_writes` / `_guarded`) as a shell snippet.
      This is a COMMAND pasted into the PR body, **not** a committed file — the file was cut (it would
      be the only never-invoked file in `plugins/soleur/test/lib/`, and it would join two ratchet
      corpora). Name the nine git-LOCATION variables explicitly in `_guarded`; never `GIT_.*`
      (`GIT_EDITOR` is in the ambient env and is not a location variable). Match `git -C <dir>` and
      `git --git-dir=` (a `^git init` anchor misses `harvest-debt`). **(AC13)**
- [ ] 0.1 Run it scoped; reconcile against the four-member set. **If it differs: restate the sweep in
      the PR body and explain the delta** — do not silently ship the plan's list. Run it repo-wide and
      capture the `.claude/hooks/` sub-count. **(AC13, AC20)**
- [ ] 0.2 Re-run the three A2 suites standalone; record exact counts (expect 27/27, 19, 20).
- [ ] 0.3 Confirm no git-LOCATION variable in the ambient environment (the nine names, not `GIT_.*`).
      **If one is present: re-exec the phase under `env -u <the nine> bash …` and record that you
      did.** Every measurement is void otherwise.
- [ ] 0.4 Record `grep -l 'test-helpers.sh' plugins/soleur/test/*.test.sh | sort | head -1` (AC24 baseline).
- [ ] 0.5 Record adoption **source-anchored**: `grep -lE '^[[:space:]]*(\.|source) .*test-helpers\.sh'`
      (expect **44**) against 88 total. A naive `grep -l` returns 51 and counts seven mention-only
      files — posting that number to #7849 would be wrong AND not reproducible by its own command.
- [ ] 0.7 **Capture the PRE-remedy reading before editing anything**: source `test-helpers.sh` into
      `gitleaks-merge-commit.test.sh` with no `set +e` and record `rc=1`. After the edit lands this
      is only reproducible by deliberately re-breaking the suite. **(AC13)**
- [ ] 0.6 Re-derive the do-not-touch owner set with `gh pr list` + per-PR file lists.

## Phase 2 — A1 vacuity repairs (write the failing assertion first)

- [ ] 2.1 Write `assert_not_a_repo()` per suite: probe SUCCEEDS in a known repo, FAILS in the fixture,
      failure text names `not a git repository`. Run under the case's own env and CWD.
- [ ] 2.2 `proc.test.sh` — add the precondition at T9 (`NOGIT`), under the case's own `env -u` prefix.
- [ ] 2.3 `fixture-dir-operand-assert.test.sh` — add preconditions to its non-repo arms.
- [ ] 2.4 Re-derive both suites' assertion floors from a green run, in the same commit. Never lower.
      **Keep `proc.test.sh`'s documented slack** — its header calls that slack deliberate budget for
      added arms, and tightening it would redden on every future arm.
- [ ] 2.4b **Structural precondition-coverage check** (this, not the floor, carries Guard 2 M4 and M5):
      the suite enumerates its non-repo fixtures and asserts a precondition ran for EACH, reporting
      directly with `printf >&2` + `exit 1`. The floor cannot do this job — it is a shrink-only `>=`
      ratchet, so an ADDED case with no precondition raises the count and passes.
- [ ] 2.5 Drive Guard 2 mutations M1-M6 and harness rows H1-H2; record each verdict. **(AC15)**
- [ ] 2.6 Neither A1 suite adopts `test-helpers.sh` — the precondition is the whole deliverable.

## Phase 3 — A2 tripwire adoption

- [ ] 3.1 `gitleaks-merge-commit.test.sh` — it binds **no** `SCRIPT_DIR` today (it uses `REPO_ROOT`,
      itself below the `set` line), so introduce a NEW binding above the `set` line, not a reorder;
      `source "$SCRIPT_DIR/test-helpers.sh"`; change `set -uo pipefail` -> `set +e -uo pipefail`
      with a comment naming `test-helpers.sh` as the reason.
- [ ] 3.2 `harvest-debt.test.sh` — same shape.
- [ ] 3.3 `roadmap-reconcile.test.sh` — source only; LEAVE `set -euo pipefail` unchanged.
      Source must sit ABOVE its own `assert_eq` / `assert_contains` definitions.
- [ ] 3.4 Re-run each standalone; each must match its Phase 0.2 count EXACTLY. **If one differs:
      revert that suite's A2 edit, record the delta as a finding, and ship the other two** — A2 is
      bookkeeping plus direct-invocation containment, so dropping a member costs a number, not a
      property.
- [ ] 3.5 Re-run each with `GIT_DIR="$(mktemp -d)/hostile.git"` (never a fixed shared path); each must exit 97 with a `FATAL` line. **(AC17)**
- [ ] 3.6 Re-run AC24: the shell arm's subject must be unchanged.

## Phase 4 — A3 containment regression test

- [ ] 4.0 **Read the precedents before writing anything** (plan §"Phase A3 — precedent"):
      `scripts/test-all-infra-coverage-notice.test.sh` `build_sandbox()` and
      `plugins/soleur/test/fanout-suite-scope.test.sh` `build_sandbox()`/`run_arm()` for the sandbox;
      `git-env-list-parity.test.sh` `scrub_list()` for extracting the `unset GIT_…` line;
      `fixture-dir-operand-assert.test.sh` `synth()` for the child writer (body on **stdin via a
      quoted heredoc**, never a single-quoted argument);
      **`plugins/soleur/test/git-fixture-env.test.ts` `makeVictim()`/`read()`/`hostileEnv()` — this is
      Guard 1's TypeScript half and already does what A3 must do in shell; port it, do not reinvent**;
      `git-tripwire.test.sh` for the AP-023 instrument self-test AND the separate dispatcher
      self-test; `proc.test.sh` `mutate()`/`expect_red()` for the mutation battery.
      **Three compositions are NOVEL and need extra review scrutiny**: scrub-line-as-wrapper, an
      executed shell child that sources `test-helpers.sh`, and the bash port of the victim triple.
- [ ] 4.1 Create `plugins/soleur/test/git-fixture-containment.test.sh`. It must NOT source
      `test-helpers.sh` (it controls the tripwire).
- [ ] 4.2 Inline `assert_fixture_dir`, extracted byte-exactly with the same awk the P1a guard uses.
      Do not redefine `exit`, `printf`, `return`. **(AC23)**
- [ ] 4.3 **Build a SANDBOX COPY of `scripts/test-all.sh`'s `unset GIT_DIR … GIT_EXEC_PATH` line** and
      invoke the child through it. This is the layer the containment arm tests. **Never invoke the
      real `scripts/test-all.sh`** (do-not-touch path; no single-suite mode; refuses rc 4 under
      `SOLEUR_SUBAGENT=1`). `SOLEUR_GIT_TRIPWIRE_ALLOW=1` **announces and falls through — it does NOT
      scrub**, so without this copy the arm is red from birth (see M-10).
- [ ] 4.3b `CHILDREN=( … )` holds **two SYNTHESIZED fixture suites** written into the sandbox
      (`cq-test-fixtures-synthesized-only`), each sourcing `test-helpers.sh` and doing a git write.
      Not real swept suites — that would couple this guard's verdict to unrelated suite churn.
      Two, because Guard 1 M4 needs a second member to break — and they must use **two different
      write shapes** (one `git -C "$d" init/add/commit`; one that writes into the victim's work tree
      and runs `git add`), because M-13 shows the observable variable set differs between them.
- [ ] 4.3c `run_child()` is the single child-invocation chokepoint and takes the hostile variable NAME
      as a parameter. **DERIVE the containment set by calibration — never hand-partition it** (M-13:
      under the canonical `git -C "$d" init/add/commit` child only `GIT_DIR` moves the victim triple;
      a hand-written "seven write-redirecting variables" list would have shipped six arms that cannot
      fail). For each of the nine x each child, run once with the sandbox scrub REMOVED and record
      whether the triple moved; movers form the containment set, the rest are refusal-only. Print the
      derived partition and floor on its size. Derive the nine from `test-helpers.sh`'s
      `for _v in GIT_DIR …` loop (reuse `git-env-list-parity.test.sh`'s derivation), never hand-copy.
      **(AC14)**
- [ ] 4.4 `victim_quad()` — the single victim-state read. Port the TS precedent's three commands
      (`git rev-parse HEAD`, `git for-each-ref --format='%(refname) %(objectname)'`,
      `git diff --cached --name-only`) **and add a FOURTH: a loose-object count**
      (`find "$V/.git/objects" -type f | wc -l`). **M-14 measured that `GIT_COMMON_DIR` and
      `GIT_OBJECT_DIRECTORY` grow the victim's object store 3 -> 6 while HEAD, refs and index stay
      byte-identical** — a real breach a three-component oracle certifies as contained. (`git for-each-ref` appears in no other `.sh` test here — this
      is a port, not a reuse.) Capture to variables first; no `producer | grep -q` (SIGPIPE fails on
      an EARLY match).
- [ ] 4.4b **Fail closed on an empty HEAD**: refuse with "baseline is not established" rather than
      returning it — an uninitialised victim otherwise compares equal to itself and the containment
      arm passes vacuously. Guard 1 **M8** proves this guard is load-bearing (ported from
      `git-fixture-env.mutation.sh` row H2).
- [ ] 4.5 Refusal arm: tripwire armed + hostile env -> child exits 97.
- [ ] 4.6 Containment arm: `SOLEUR_GIT_TRIPWIRE_ALLOW=1` + hostile env -> child exits 0 AND the
      victim triple is unchanged.
- [ ] 4.7 Snapshot the victim BEFORE the child runs (the property is about a window).
- [ ] 4.8 **The hostile environment must BE the victim**: `GIT_DIR="$VICTIM/.git"`,
      `GIT_WORK_TREE="$VICTIM"`, `GIT_INDEX_FILE="$VICTIM/.git/index"` — the #7835 shape. A hostile
      path aimed at scratch (`/tmp/hostile-probe`) makes the victim triple unable to move whether
      containment holds or not, so M1 silently stops being driveable. Guard 1 **M7** pins this.
      Victim is a synthesized `mktemp` repo.
- [ ] 4.9 `assert_fixture_dir "$1"` at every ENCLOSING FUNCTION HEAD that takes a fixture path.
- [ ] 4.9b Bind `readonly TRIPWIRE_RC=97` once (mirroring `git-tripwire.test.sh`) rather than
      inlining `97`; it already has copies in four places.
- [ ] 4.9c **Chokepoint floor**: the suite greps its own source and fails, reporting directly, if a
      git read verb or child invocation appears outside `victim_quad()` / `run_child()`.
- [ ] 4.9d **Variable-coverage floor**: assert the set of variables actually driven equals the derived
      nine, partitioned into the seven write/ref-redirecting and the two code-execution-only.
- [ ] 4.9e The oracle reads git state, **never the child's stderr** — the disarm banner prints on
      every containment-arm invocation.
- [ ] 4.9f Every A3 git write is `git -C "$dir"` with a guarded operand, or `cd … || exit`
      (`fixture-cd-containment`). Capture-then-match, never `producer | grep -q` (SIGPIPE on an
      EARLY match, and `lint-shell-capture-exit-live`).
- [ ] 4.10 Instrument self-test (drive `ok()`/`bad()` and the dispatcher once; require both counters
      to move; then subtract), plus an assertion floor.
- [ ] 4.11 The floor reports `printf >&2` + `exit 1` DIRECTLY, never through `fail()` (ADR-193);
      counters increment at the call site, never inside `$( )`.
- [ ] 4.12 The floor block must be INDEPENDENTLY RUNNABLE — `guard-vacuity-floor` builds its mutant
      by widening backward over contiguous simple assignments; an unbound var under `set -u` kills
      the mutant and scores a compliant floor as a construction failure. Mirror
      `git-tripwire.test.sh`'s `VITEST_ARM_RAN=${VITEST_ARM_RAN:-0}` re-bind.
- [ ] 4.12b **Comparator self-test** — against a throwaway victim, advance HEAD, stage a file, create
      a ref, and write a loose object; assert the comparator reds INDEPENDENTLY on each of the four
      components. Guard 1 M2, M5 and H1's substitution case are prose without it.
- [ ] 4.12c **Arm precondition**: assert the hostile value resolves under `$VICTIM`
      (`[[ "$hostile_value" == "$VICTIM"* ]]`), reported directly. This is what makes M7 driveable.
- [ ] 4.12d **Derive the sandbox scrub, never transcribe it** — extract the `unset GIT_…` line from
      `scripts/test-all.sh` at runtime with `git-env-list-parity.test.sh`'s extractor (read-only; the
      do-not-touch constraint is about writes). Carries M9.
- [ ] 4.12e **Child-side positive control**: assert the child's OWN fixture HEAD/index advanced.
      With `GIT_WORK_TREE` set alone every git call in the child fails and it still exits 0, so
      "child exits 0, victim unchanged" is otherwise satisfied by a child that did nothing. Carries M10.
- [ ] 4.13 Drive Guard 1 mutations **M1-M10** and harness rows H1-H4; record every verdict. **(AC14)**
      `mutate()` must set a GLOBAL, never echo — `proc.test.sh` documents that a `t=$(mutate …)` form
      put its `fail` in a subshell so the counter never moved in the parent. `expect_red()` must treat
      an EMPTY oracle reading as FAIL: a mutant that cannot RUN is not a detected mutation.
- [ ] 4.14 Produce the AC14 evidence: a victim-state-ONLY version must be shown to PASS with an
      entry-point `unset` removed. Both readings go in the PR body.

## Phase 5 — ratchets and verification

- [ ] 5.1 Run the change-covering suites AND all **15** repo-wide ratchets (the brief's 14 plus
      `scripts/lint-shell-capture-exit-live`) **(AC21)** (TEST_GROUP=all is often
      refused; its "run the suite covering your files" advice is NOT sufficient).
- [ ] 5.2 `fixture-relative-assert` green WITHOUT `--write-baseline`. If a row appears, guard the site
      per-function; only then, if legitimate, add the row with a justification in the commit message. **(AC21)**
- [ ] 5.3 `fixture-dir-operand-assert` green — **BOTH arms**: the repo-wide byte-exactness corpus AND
      the strict `SITES_LIVE == ACK_TOTAL` equality (`NAMED_WANT=8`). A new unasserted operand site in
      either new file takes it 8 → 9 and hard-fails; the remedy is a guarded operand, **never** a
      regenerated baseline. Re-confirm the Phase 2.4 floor after the A3 file lands. **(AC23)**
- [ ] 5.3b `scripts/lint-shell-capture-exit-live` green — the **15th** repo-wide ratchet, omitted from
      the brief's list of 14. Walks `git ls-files '*.sh'`; any un-baselined capture-exit site in a new
      file reds it. **(AC21)**
- [ ] 5.4 `guard-vacuity-floor` green; the A3 file classified, not deferred. **If still red after the
      4.12 re-bind: hoist the floor block's variable bindings INTO the block** so the mutant is
      self-contained. **(AC22)**
- [ ] 5.5 `git-tripwire.test.sh` green.
- [ ] 5.6 Resolve `knowledge-base/INDEX.md` conflicts ONLY via `bash scripts/generate-kb-index.sh`.
      Expect 3-5 resyncs.

## Phase 6 — ship

- [ ] 6.1 AC19 hard gate BEFORE `gh pr ready`: the diff touches none of `scripts/test-all.sh`,
      `plugins/soleur/test/test-helpers.sh`,
      `apps/web-platform/infra/workspaces-luks-loopback.test.sh`.
- [ ] 6.2 PR body carries: the predicate script's own output (scoped, repo-wide, hooks sub-count);
      the AC16 before/after `-e` readings; the AC14 false-green demonstration.
- [ ] 6.2b **File the residue issue** (`type/bug`, `priority/p2-medium`): the ten shell files from
      #7822's measured population plus the four unscrubbed TypeScript fixtures from #7835, noting
      that `workspaces-luks-loopback.test.sh` is owned by PR #7879. A PR body is not a durable
      artifact (`wg-when-an-audit-identifies-pre-existing`).
- [ ] 6.3 PR body references the residue issue BY NUMBER and states the sweep discharges NO exit condition outright, advances #7849 trigger 2
      from 44/88 to 47/88 (source-anchored; the naive grep says 51 and counts mentions), and names the `.claude/hooks/` residue as out of scope — described as
      #7822 describes it (candidates, not confirmed defects; most likely executed FROM a hook). **(AC20)**
- [ ] 6.4 **`Ref #7822`, `Ref #7835`, `Ref #7849` — NO `Closes` on any of the three.** Closure was
      downgraded on measured evidence (0 of #7822's 10 enumerated files touched; 4 of #7835's TS
      fixtures still unscrubbed). This reverses the brief's stated direction and is recorded as a
      **User-Challenge** in `decision-challenges.md` for the operator to overrule.
- [ ] 6.5 Post the new adoption count to #7849 as a comment; do NOT close it. **(AC25)**
- [ ] 6.6 Assert `scripts/test-all.sh` is UNMODIFIED and its `plugins/soleur/test/*.test.sh` glob
      reaches the new A3 file — by reading the glob, not by editing the runner. **(AC18)**
