---
feature: prebake-rehearsal-image
issue: 7535
branch: feat-one-shot-7535-rehearsal-apt-misattribution
phase1_branch: feat-prebake-rehearsal-image-7535
phase1_pr: 7540
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-13-test-remove-rehearsal-apt-dependency-plan.md
date: 2026-08-13
updated: 2026-09-17
---

# Tasks — stop the rehearsal's apt failures reading as emitter findings (#7535)

Primary target file: `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (3630 lines on
`main` 2026-09-17). Secondary:
`knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`.

> **Scope note.** An earlier revision proposed a locally-built fixture image plus three guards.
> Seven-agent review measured the value case at **$0 and 0 operator-visible seconds** and found
> the image would introduce a T5 vacuous-green. It is cut. See the plan's
> `## Why the image was cut`. Do not reintroduce it.

> **Retarget note — 2026-09-17.** Phase 2's original four-site list is stale. PR #7510
> (`45ea9f7e9`, 2026-08-19) shipped the `run_case` and T5-mutation splits; PR #7507
> (`dfcf7bd26`) owns R4. **Two sites remain.** Re-derive every anchor by content — every line
> number the earlier revision carried has shifted.

> **Anchor discipline.** Do not trust a line number from this file or from the plan. Locate each
> site with the content anchors in the plan's retargeted site table, then read the surrounding
> comment block before editing: several of the constraints below are stated in the file's own
> words at the site.

## Phase 1 — delete the no-op `e2fsprogs` install — SHIPPED (`910f237f0`, PR #7540)

- [x] **1.1** Pre-change baseline recorded.
- [x] **1.2** `apt-get update -qq` / `apt-get install -y -qq e2fsprogs` deleted.
- [x] **1.3** The now-dead `export DEBIAN_FRONTEND=noninteractive` deleted.
- [x] **1.4** Replacement comment added: `ubuntu:24.04` ships
      `e2fsprogs 1.47.0-2.4~exp1ubuntu4.1` at `Priority: required`, and the deletion narrows R1's
      source from mirror-current to image-current — a behaviour change, not a no-op.
- [x] **1.5** R1's arms identical (AC4) — CI runs 31711619961 (main) and 31717913686 (PR), both
      `44 passed, 0 failed (44 assertions)`. Verified on CI rather than locally: three sibling
      sessions at load 11.6 made one local apt cycle exceed 19 min.
- [x] **1.6** Floor and reported `total` unchanged at 44 (AC5).
- [x] **1.7** `git-data-render-strip-parity.test.sh` green (AC6).
- [x] **1.8** AC1/AC2/AC3 verified **at that commit**. These counts have since moved on `main` and
      are frozen as a historical record in the plan — do not re-assert them.
- [x] **1.9** Pushed; PR body used `Refs #7535`.
- [x] **1.10** Image-cut measurements posted on #7535; issue retitled to residual scope.

## Phase 2 — name the two remaining apt cycles (UNBLOCKED)

### 2.0 Preconditions

- [ ] **2.0.1** Confirm the branch is rebased on a `main` that contains **both** `dfcf7bd26` and
      `45ea9f7e9` (`git merge-base --is-ancestor` each against `HEAD`).
- [ ] **2.0.2** Re-run the site census and confirm it still returns exactly the five sites in the
      plan's table: `grep -nE '^[^#]*apt-get' apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`.
      Confirm `grep -cE '^[^#]*apt-get update.*&&.*apt-get install' <file>` is **1** (the T17 site
      is the last AND-OR pair). If either has changed, stop and re-reconcile the plan.
- [ ] **2.0.3** Re-read, at the site, the comment above `echo "S1_FIXTURE_OK"` — it states in the
      file's own words why an apt failure must route to `did-not-run` and why moving the fixture
      marker above apt would be a regression.
- [ ] **2.0.4** Record the pre-change baseline: `docker info` succeeds, then the suite's terminal
      `git-data-runcmd-rehearsal: N passed, M failed, Skipped: S (T assertions)` line. **If docker
      is unavailable, do not substitute a docker-less exit 0** — see 2.6.

### 2.1 D1 — T17 MUTATION (primary)

Anchor: `# MUTATION: remove the rc guard and prove T17's assertion can FAIL`.

- [ ] **2.1.1** Split the `apt-get update -qq … && apt-get install -y -qq curl python3 …` AND-OR
      list into two statements, matching the form already on `main` at `run_case` and T5-mutation.
- [ ] **2.1.2** Carry the split comment and **name mechanism (b) explicitly**: `set -e` does not
      fire on a failing non-final member of an AND-OR list (measured:
      `bash -c 'set -e; sh -c "exit 100" && true; echo reached'` prints `reached`), so the
      one-liner *looks* safe under `set -e` and is not — a failed `update` fell through into
      `drive.sh` with no `curl`/`python3`.
- [ ] **2.1.3** Keep `>/dev/null 2>&1` on both statements and record the reason inline: behind an
      authenticated apt proxy, apt error text embeds `user:pass@host`.
- [ ] **2.1.4** Replace `' >/dev/null 2>&1 || true` with `' >"$TMP/out/stdout" 2>&1; _t17m_rc=$?`.
      The assignment stays on the **same line**; not `local` (this arm is top-level).
- [ ] **2.1.5** Emit a distinct `FIXTURE-APT:` literal per apt statement inside the container,
      naming the site and the statement. Fixed literals only — never apt's own output.
- [ ] **2.1.6** Add `-e "GIT_DATA_REHEARSAL_INJECT=${GIT_DATA_REHEARSAL_INJECT:-}"` to this arm's
      `docker run` and honour **namespaced** tokens `t17-apt-update` / `t17-apt-install`, each
      emitting its literal and exiting 100. Tokens must not collide with R4's `apt-update` /
      `apt-install` — one env var is read by more than one driver.
- [ ] **2.1.7** Make the verdict three-way, **exactly one assertion on every route**: capture
      non-empty → `pass`; capture empty **and** `grep -qx "$_T5_MARKER" "$TMP/out/stdout"` absent
      → a named "did not run" fail carrying rc, the offered rc classes, marker-seen and a tail;
      capture empty **and** marker present → the existing vacuity message, **byte-unchanged**.
- [ ] **2.1.8** Use the pinned `$_T5_MARKER` variable, and `-qx` not `-q` (bash echoes the
      offending source line on an error, which satisfies a bare `grep -q`).

### 2.2 D2 — `_s1_run` (naming only)

Anchor: the `S1DRV` heredoc's `apt-get install -y -qq openssh-server`.

- [ ] **2.2.1** Leave the two statements as two statements. `set -e` already fires here and rc 100
      already reaches `_s1_classify`, which allowlists it — the rc-propagation property is already
      bought. Record in the comment **why this site is treated differently** from the `&&` sites.
- [ ] **2.2.2** Name each statement:
      `apt-get … || { _rc=$?; echo "FIXTURE-APT: S1 driver — <statement> failed (…)" >&2; exit "$_rc"; }`.
- [ ] **2.2.3** **Preserve the measured rc.** Do not pin `exit 100` — that would launder a
      non-apt-class rc into the environment allowlist and hide a harness defect as a decline.
- [ ] **2.2.4** Do **not** use `fixture_fail` or any `exit 2` here. Record the measured reason in
      the comment: rc 2 is outside `_S1_ENV_RCS='100 125'`, so `_s1_classify` routes it to
      `harness-defect` and the five `_s1_run` call sites produce **11 hard FAILs**.
- [ ] **2.2.5** Do **not** move `echo "S1_FIXTURE_OK"` above apt.
- [ ] **2.2.6** Record that the `FIXTURE-APT:` prefix deliberately does **not** match
      `run-registered-suites.sh`'s
      `MARKER_ERE='^[[:space:]]*(\[FAIL\]|[A-Z][A-Z0-9]*-FAIL|FAIL)([[:space:]:_-]|$)'` — an apt
      decline at S1 is an environment decline, not a fixture failure, and a `*-FAIL` marker would
      anchor a RED excerpt on a non-failure.
- [ ] **2.2.7** Add `-e "GIT_DATA_REHEARSAL_INJECT=${GIT_DATA_REHEARSAL_INJECT:-}"` to `_s1_run`'s
      `docker run` (it already forwards two `-e`s) and honour `s1-apt-update` / `s1-apt-install`.
- [ ] **2.2.8** Confirm the S1 structural marker guard still passes — it is anchored on
      `^\s*echo "S1_DRIVER_REACHED_STAGE"\s*$` and `^\s*echo "S1_FIXTURE_OK"\s*$` in the mounted
      driver, so the new echoes must resemble neither.

### 2.3 D3 — T17 mutation-landed pre-check (fold-in; cut criterion in the plan)

- [ ] **2.3.1** Before the container run, assert the mutation landed: count the rc-guard line in
      `$TMP/drive.sh` (expect 1) and in `$TMP/drive.noguard.sh` (expect 0), mirroring the S2(m)
      precedent in this file.
- [ ] **2.3.2** On not-landed, emit the named fail **plus** a substitute fail for the verdict that
      cannot run, so the arm contributes **exactly 2 assertions on every route**.
- [ ] **2.3.3** Re-derive the floor from a **measured** run and quote the terminal summary line.
      Do not compute `92 + 1`.
- [ ] **2.3.4** Add a **new** stanza immediately above the floor:
      `# RAISED 92 -> <measured> (#7535), ITEMISED — one new counted assertion, pure text over
      $TMP, made on every route …` with the one-line itemisation and the
      "Re-derived from a measured run … not incremented by memory" sentence.
- [ ] **2.3.5** **Do not edit** the frozen 19-era baseline list (`B1: 1, B2: 1, D1: 2, T5: 4 + 1
      mutation, T17: 2 + 1 mutation, S1: 3 + 4 mutation`) or any earlier `RAISED` stanza. Verify
      with `git diff` on the floor comment block.

### 2.4 D4 — amend ADR-188

- [ ] **2.4.1** Add a dated amendment to `## Alternatives Considered` recording the pre-baked
      image as **CUT** (not DEFERRED-and-preferred), with the three measurements and the two
      hazards from the plan's `## Why the image was cut`.
- [ ] **2.4.2** Record the replacement re-evaluation trigger (Infra Validation becomes the longest
      workflow on a PR's head SHA in >= 3 consecutive runs, with the `gh api` one-liner),
      superseding the skip-rate trigger that points at the cut design.
- [ ] **2.4.3** Preserve the revival guard: any revival must carry a `[ ! -d /run/sshd ]` in-arm
      assertion, because installing `openssh-server` at build time can make `/run/sshd` exist at
      runcmd time and **silently invalidate S1 rather than fail it**. Confirm
      `grep -c 'run/sshd' ADR-188-*.md` does not decrease.
- [ ] **2.4.4** No new ADR ordinal, so no `origin/*` collision probe is needed. Do not renumber.

### 2.5 Guard Contract execution — both matrices

Each row is one container run and needs a **real docker daemon**. Record every row's command and
observed output in the PR body.

- [ ] **2.5.1** Guard 1 rows 1-2: `GIT_DATA_REHEARSAL_INJECT=t17-apt-update` then `…=t17-apt-install`
      → the matching literal appears, the verdict names rc + marker-absent, and the vacuity string
      does **not** appear. The two literals differ.
- [ ] **2.5.2** Guard 1 row 3: rewrite the mutating `sed` so it matches nothing → the verdict says
      the mutation did not land; the vacuity string does not appear.
- [ ] **2.5.3** Guard 1 row 4 (dispatch): delete the arm's `docker run` and verdict → the floor
      reds.
- [ ] **2.5.4** Guard 1 row 5 (second member): add a **third** apt statement to the T17 recipe and
      starve it → it is also rc-checked and named.
- [ ] **2.5.5** Guard 1 row 6 (order): move the marker read before the `docker run` writes stdout →
      a healthy run is misreported as "did not run".
- [ ] **2.5.6** Guard 1 harness H1: neuter `fail()` with the bucket swap → the CANARY self-test and
      the `FAILURES` ledger red.
- [ ] **2.5.7** Guard 1 harness H2: reword the injected token on one side only → row 1 reds. Then
      pin the token once (a variable or a structural assertion) rather than replicating the literal.
- [ ] **2.5.8** Guard 1 harness H3 (must-PASS, non-canonical): run healthy with
      `GIT_DATA_REHEARSAL_INJECT=apt-update` (R4's token) → the T17 arm **passes** and emits none of
      the new literals. This is the namespacing proof.
- [ ] **2.5.9** Guard 2 rows 1-2: `s1-apt-update` / `s1-apt-install` → the literal appears in
      `S1_NOTE`'s tail, every S1/S2 arm declines via `arm_skip`, and **zero** `FAIL:` lines name S1
      or S2.
- [ ] **2.5.10** Guard 2 row 3: change `exit "$_rc"` to `exit 2` → **demonstrated RED** with all
      five arms flipping to `harness-defect`/`fixture-defect`. This row is the evidence for TR3.
- [ ] **2.5.11** Guard 2 rows 4-5: delete the naming echo but keep the exit → the literal-presence
      AC reds; add a third apt statement to `S1DRV` and starve it → it is also named.
- [ ] **2.5.12** Guard 2 harness H1: rename the `-e` on the `docker run` but not in the driver →
      row 1 reds. H2 (must-PASS): `S1_RESTART_MODE=fail` with no INJECT → S2(h-j) makes its normal
      verdicts and no new literal appears.
- [ ] **2.5.13** **Pre-fix control (AC12):** with the fix reverted on a scratch copy and the same
      starve applied, the T17 arm emits *"the check is vacuous"*. An assertion nobody has seen fail
      is not evidence.

### 2.6 Verification and evidence provenance

- [ ] **2.6.1** Tag **every** AC with `[local docker]` (quoting the terminal summary line, after
      `docker info` succeeded) or `[CI run <id>]` (quoting the conclusion of the "Rehearse the
      git-data runcmd chain (abort ordering + rc guard)" step).
- [ ] **2.6.2** Do **not** treat a docker-less run as evidence: `_skip` exits 0 off-CI, and
      `apps/web-platform/infra/run-registered-suites.sh` prints `PASS` for a docker-less skip (its
      own header says so). Docker is currently unavailable on the authoring box (socket
      `root:docker` 0660, empty `docker` group, no podman); the operator has been asked to fix it.
- [ ] **2.6.3** If docker stays unavailable, mark AC10/AC11/AC12 **UNVERIFIED** and do not mark the
      PR ready. Never report a green that was not obtained.
- [ ] **2.6.4** Prefer the single-file invocations
      (`bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`,
      `bash apps/web-platform/infra/git-data-render-strip-parity.test.sh`) — the box is contended by
      sibling worktrees running the same docker suite. If the battery is needed and `TEST_GROUP=all`
      stalls, shard: `TEST_GROUP=infra` is the only group that reaches `run-registered-suites.sh`,
      and `TEST_GROUP=scripts SCRIPTS_SHARD=<n>/<m>` covers the scripts side (`SCRIPTS_SHARD` is
      rejected unless `TEST_GROUP=scripts`).
- [ ] **2.6.5** `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
      passes and `git diff --stat` shows **zero** changes to the baseline (7 grandfathered findings
      for this file; may only shrink).
- [ ] **2.6.6** Invariance checks: `grep -c 'Acquire::Retries' <file>` unchanged;
      `grep -cE '^[[:space:]]*_skip ' <file>` unchanged;
      `grep -cE '^[[:space:]]*arm_skip ' <file>` still **3**; `_SKIP_CEILING` and its stanza
      unchanged.
- [ ] **2.6.7** Re-measure the `## Observability` discoverability probe on the final tree
      (`grep -c FIXTURE-APT: apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`) and pin
      `expected_output` to its **actual** output. The previous probe's `"7"` now returns 15 on a
      correct tree — preflight Check 10 executes it.
- [ ] **2.6.8** `bash plugins/soleur/test/c4-count-parity.test.sh` green (baseline 2026-09-17:
      10 passed, 0 failed) and `git diff --stat -- knowledge-base/engineering/architecture/diagrams/`
      empty.
- [ ] **2.6.9** Confirm the diff touches only the paths in the plan's `## Files to Edit`.

### 2.7 Ship

- [ ] **2.7.1** Push; PR body uses **`Closes #7535`** in the **body**, never the title.
- [ ] **2.7.2** Paste both guard matrices' rows with their observed outputs, and every AC with its
      evidence-provenance tag.
- [ ] **2.7.3** Confirm nothing in the PR body reads as an operator checklist
      (`hr-ship-message-no-operator-checklist`).
