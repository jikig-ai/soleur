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
revision: R2-deepened
---

# Tasks — stop the rehearsal's apt failures reading as emitter findings (#7535)

Primary target: `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`. Also
`knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`,
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh` and
`.github/workflows/scheduled-rehearsal-skip-monitor.yml`.

> **Scope note.** The pre-baked fixture image is **cut** on measured evidence ($0, 0
> operator-visible seconds, plus a T5 vacuous-green it would have introduced). Do not reintroduce
> it. See the plan's `Why the image was cut`.

> **Retarget (R1).** PR #7510 (`45ea9f7e9`) shipped the `run_case` and T5-mutation splits; PR #7507
> (`dfcf7bd26`) owns R4. **Two sites remain.**

> **Reconcile (R2, deepen-plan).** An implementation landed in this worktree during the deepen pass
> and is **uncommitted** (3630 -> 3717 lines). R2 **adopts** its `arm_skip` design and withdraws
> NG9; it names six things still owed. Task 2.0 decides the baseline before anything else.

> **Anchor discipline.** Trust no line number from these artifacts. Locate each site by the content
> anchors in the plan, and read the surrounding comment block first — several constraints below are
> stated in the file's own words at the site.

## Phase 1 — SHIPPED (`910f237f0`, PR #7540)

- [x] **1.1-1.10** Redundant `e2fsprogs` install and its dead `DEBIAN_FRONTEND` export deleted with
      a replacement comment; R1's four arms identical across the change (CI runs 31711619961 and
      31717913686, both `44 passed, 0 failed`); floor and total unchanged at 44; parity suite green;
      pushed with `Refs #7535`; image-cut measurements posted on the issue and the issue retitled.
      **The Phase-1 grep counts have since moved on `main` — do not re-assert them.**

## Phase 2 — name the two remaining apt cycles

### 2.0 Baseline decision and preconditions

- [ ] **2.0.1** **Decide the baseline.** `git status` shows the target file and the follow-through
      probe modified and uncommitted. Either adopt that work (R2's assumption) or discard it, and
      record the decision in the PR body. Do not start editing before this is written down.
- [ ] **2.0.2** Confirm `main` contains both `dfcf7bd26` and `45ea9f7e9`
      (`git merge-base --is-ancestor` each against `HEAD`).
- [ ] **2.0.3** Re-run the census: `grep -nE '^[^#]*apt-get' <file>` must resolve to the five sites
      in the plan's table, and `grep -cE '^[^#]*apt-get update.*&&.*apt-get install' <file>` must be
      **0** on the adopted tree (**1** on `origin/main`). If neither matches, stop and re-reconcile.
- [ ] **2.0.4** Read, at the site, the comment above `echo "S1_FIXTURE_OK"` — it states in the
      file's own words why an apt failure must route to `did-not-run`.
- [ ] **2.0.5** Record the pre-change baseline: `docker info` succeeds, then the suite's terminal
      `git-data-runcmd-rehearsal: N passed, M failed, Skipped: S (T assertions)` line. **A
      docker-less exit 0 is not a baseline** — see 2.7.

### 2.1 D1 — T17 MUTATION

- [ ] **2.1.1** *(done in tree)* Split the AND-OR list into two statements, carrying the measured
      mechanism-(b) comment: `set -e` does not fire on a failing non-final member
      (`bash -c 'set -e; sh -c "exit 100" && true; echo reached'` prints `reached`).
- [ ] **2.1.2** *(done in tree)* Capture the rc: `; _t17m_rc=$?` on the **same line**; not `local`.
- [ ] **2.1.3** **OWED — move the sink out of the bind mount.** Write `$TMP/t17m.stdout`, not
      `$TMP/out/…`. Two reasons: `$TMP/out` is mounted `-v "$TMP/out:/out"` so the marker's evidence
      file is writable by the **mutated driver under test**; and `$TMP/out/stdout` is `run_case`'s
      own capture file, into which the `run_case "T17 healthy run exits 0"` arm one arm above writes
      `DRIVER_REACHED_DL`.
- [ ] **2.1.4** **OWED — name each apt statement.** One fixed literal per statement, preserving the
      measured rc, so a starved `update` is distinguishable from a starved `install`. Keep
      `>/dev/null 2>&1`; never echo apt's own output.
- [ ] **2.1.5** **OWED — add the `FIXTURE:` bind rung above the vacuity branch.** Measured:
      `echo T17M_APT_OK` precedes `bash /work/drive.sh`, whose bind guard exits 2 with
      `FIXTURE: capture server never bound :8099` — so a bind failure is marker-PRESENT and takes the
      vacuity branch today. Read `$_T5_FIXTURE_MARKER` from the captured stdout, ordered as the
      T5-mutation ladder orders its conditions.
- [ ] **2.1.6** **OWED — add the `rc == 0` not-landed rung.** `on_err`'s `[ "$rc" -eq 0 ] && exit 0`
      is the line the `sed` removes, so a landed-and-ran mutant exits 1 and a non-landed one exits
      0. Free: no `diff`, no count, no assertion, no floor move.
- [ ] **2.1.7** **OWED — offer all five reachable rc classes from ONE variable** (0 did not land,
      1 the mutant ran, 2 no bind, 100 apt, 125 docker/image pull), *offered* and never asserted as
      cause. The tree's `_t17m_rc_note` re-spells two as a bare literal — a third hand-copy.
- [ ] **2.1.8** Keep `_T17M_ENV_RCS`, the `arm_skip`, and `grep -qx` (never `grep -q`). Write the
      `arm_skip` at **line-start** so the roster census sees it.
- [ ] **2.1.9** **OWED — plumb injection.** Add
      `-e "GIT_DATA_REHEARSAL_INJECT=${GIT_DATA_REHEARSAL_INJECT:-}"` and honour `t17-apt-update` /
      `t17-apt-install`. Compare with **exact `=` on a quoted `$INJECT`**, mirroring R4 — no `case`
      glob, no `=~`. The arm must **poison apt**, not `exit` directly, or the real `|| { … }`
      handler is never exercised. **Do 2.5 (D8) first.**
- [ ] **2.1.10** After every edit inside the `bash -c '…'` recipe run `bash -n <file>` — it is a
      single-quoted host string and one apostrophe is a whole-file syntax error (measured rc 2).

### 2.2 D2 — `_s1_run` (naming only)

- [ ] **2.2.1** *(done in tree)* Two distinct literals, one per statement, emitted **before**
      `echo "S1_FIXTURE_OK"`, with the comment explaining why this site is named-not-restructured.
- [ ] **2.2.2** **OWED — preserve the measured rc.** Replace the pinned `exit 100` with
      `_rc=$?; …; exit "$_rc"`, **inside the `<<'S1DRV'` heredoc immediately after each `apt-get`** —
      never at `_s1_run`'s `docker run`, where `_rc` is an unlocalised host global and `exit` ends
      the suite.
- [ ] **2.2.3** Keep `FIXTURE-FAIL:` (R2 relaxed the `FIXTURE-APT:` requirement) and record in the
      comment that `S1_NOTE`'s `tail -3 … | tr` fold is now **load-bearing** for the marker's
      non-anchoring against `run-registered-suites.sh`'s `MARKER_ERE`.
- [ ] **2.2.4** Do **not** use `fixture_fail`/`exit 2` here: rc 2 is outside `_S1_ENV_RCS='100 125'`
      and yields **11 hard FAILs** across the five call sites. Record the measured reason.
- [ ] **2.2.5** Do **not** move `echo "S1_FIXTURE_OK"` up, and do **not** add an apt statement
      **below** it.
- [ ] **2.2.6** Confirm the S1 structural marker guard still passes (anchored on the exact emit
      forms; verified unaffected by the new handler echoes).

### 2.3 D4 — amend ADR-188 (five items)

- [ ] **2.3.1** The image is **CUT**, not deferred — with the three measurements and the two hazards.
- [ ] **2.3.2** Restate the retry alternative's *"Reconsider only if the pre-bake lands"* condition,
      which becomes unsatisfiable, or record retry as CUT too.
- [ ] **2.3.3** Correct the non-declinable-arm enumeration: the T17 **mutation** arm is now
      declinable, so the set is T5-primary, T17-healthy (via `run_case`) and R4 — the *"at least one
      container-dependent arm must remain non-declinable"* invariant **holds**; the enumeration was
      what went stale. Say so explicitly.
- [ ] **2.3.4** Add T17 to the Carrier note's roster and a fourth row to the ceiling table.
- [ ] **2.3.5** Preserve the `[ ! -d /run/sshd ]` revival guard, distinguished from the
      separately-deferred `/out/setup.log` capture. Verify with an **increase** in
      `grep -c 'run/sshd' knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`
      — the **full path** (a bare `ADR-188-*.md` glob errors from the repo root and passes by being
      ignored), and an increase because "does not decrease" is satisfied by an unwritten amendment.
- [ ] **2.3.6** No new ADR ordinal; do not renumber.

### 2.4 D5 — pin `_T17M_MARKER`

- [ ] **2.4.1** Assert over `"$0"` that the recipe carries `echo <marker>` exactly once, via the
      `$_T17M_MARKER` variable, in the R1-PIN idiom (five existing `grep … "$0"` sites). Without
      this a one-sided reword routes **every** run to `arm_skip` — a permanent green decline.
      **+1 assertion.**

### 2.5 D8 — refuse fault injection under CI (precondition of 2.1.9)

- [ ] **2.5.1** Before any arm runs, a non-empty `GIT_DATA_REHEARSAL_INJECT` with `CI=true` must
      `echo … >&2; exit 1` **directly**, not through `fail()` (ADR-193). Traced: the token makes the
      T17 arm `arm_skip`, which never appends to `FAILURES`, so the verdict
      `exit $(( ${#FAILURES[@]} > 0 ))` returns **0** over an arm that ran nothing.
- [ ] **2.5.2** Do **not** add a `workflow_dispatch` input for that variable (NG12). Verify
      `infra-validation.yml`'s `workflow_dispatch:` stays input-free.

### 2.6 D6, D7, D9

- [ ] **2.6.1** **D6** — retire *"the deferred pre-baked image (#7535) is owed"* from
      `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` (three sites, including its exit
      contract) and `.github/workflows/scheduled-rehearsal-skip-monitor.yml` (one site); point both
      at the replacement trigger. Keep the probe's counting behaviour and its new
      `'SKIP (loud): T17 '` entry.
- [ ] **2.6.2** **D7** — add the in-suite census over `"$0"`: zero AND-OR apt pairs on non-comment
      lines **with an anti-vacuity floor on its own grep**, and zero `docker run … || true`.
      **+1 to +2 assertions.**
- [ ] **2.6.3** **D9** — file an issue recording the roster/ceiling defect with its three
      measurements (line-anchored census **4** vs **7** true call sites; declarable budget **14** vs
      ceiling **8**; `SKIP_MARKERS` missing `S2(`), and note it in the ceiling stanza's comment. Do
      not fix it here (NG13).
- [ ] **2.6.4** Re-derive the floor from a **measured** run and add a new `# RAISED 92 -> <measured>`
      stanza covering D5, D7 and the 2.7.2 counter. **Do not touch** the frozen 19-era baseline list
      or any earlier stanza; verify with `git diff` on that comment block. Never compute the number
      arithmetically.

### 2.7 Verification

- [ ] **2.7.1** Tag **every** AC `[local docker]` or `[CI run <id>]`, **and** require the quoted
      terminal line to show `Skipped: 0` — a green CI run is obtainable from a run in which every new
      path declined. A docker-less green is not evidence (`_skip` exits 0 off-CI; measured, and
      `run-registered-suites.sh` prints PASS for it). Docker is currently **unavailable** on this
      box (socket `root:docker`, empty `docker` group, no podman); the operator has been asked.
- [ ] **2.7.2** Add the executable route-invariance assertion for the T17 arm (a counter snapshot
      plus an equality check, modelled on S1's *"expected exactly 13 on every route"*), and budget
      it into 2.6.4's measured floor.
- [ ] **2.7.3** Run Guard 1 rows 1-8 and H1-H3, and Guard 2 rows 1-5 and H1-H2, recording each
      row's command and output. Rows 3, 4, 5 and 8 of Guard 1 currently fail on the tree — show each
      flipping. Guard 2 row 3 must be **demonstrated RED** with row 1's poison applied, and row 1's
      expected `Skipped: 14 > 8` ceiling red must be quoted so it is not read as a regression.
- [ ] **2.7.4** Run the **pre-fix control**: revert the verdict on a scratch copy and induce the
      starve by **poisoning apt in-recipe** (not with an injected token — the token is part of the
      fix, so on a reverted copy it is inert and the arm passes). The arm must emit *"the check is
      vacuous"*.
- [ ] **2.7.5** `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
      reports **zero new findings** with `git diff --stat` empty on the baseline.
- [ ] **2.7.6** Invariance: `grep -c 'Acquire::Retries'` unchanged at **3**; no new `_skip` call
      site; no edit to `run_case` or the T5-mutation site. Roster **consistency** per TR8.
- [ ] **2.7.7** Re-measure the discoverability probe
      (`grep -c T17M_APT_OK apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`) on the final
      tree and re-pin `expected_output` to its **actual** output. It is **0** on `main`, **2** on the
      tree as built, and D5's pin adds the third. Preflight Check 10 executes it.
- [ ] **2.7.8** `bash apps/web-platform/infra/git-data-render-strip-parity.test.sh` green (measured
      `15 passed, 0 failed` on this branch) and `bash plugins/soleur/test/c4-count-parity.test.sh`
      green (measured `10 passed, 0 failed`), with the diagrams directory untouched.
- [ ] **2.7.9** Full suite green with a real daemon, `Skipped: 0`, no INJECT set. Prefer the
      single-file invocation — the box is contended by sibling worktrees running the same docker
      suite. If the battery is needed and `TEST_GROUP=all` stalls: `TEST_GROUP=infra` is the only
      group reaching `run-registered-suites.sh`, and `TEST_GROUP=scripts SCRIPTS_SHARD=<n>/<m>`
      covers the scripts side (`SCRIPTS_SHARD` is rejected unless `TEST_GROUP=scripts`).
- [ ] **2.7.10** If docker stays unavailable, mark the docker-dependent ACs **UNVERIFIED** and do
      **not** mark the PR ready. Never report a green that was not obtained.
- [ ] **2.7.11** Diff scope: only the four files listed above plus the planning artifacts.

### 2.8 Ship

- [x] **2.8.1** Push; PR body uses **`Closes #7535`** in the **body**, never the title.
      **[2026-09-17] Reassigned to PR #8249** (parallel session owns the implementation); this
      branch is docs-only and uses `Refs #7535`. See the plan's `## Issue disposition`.
- [ ] **2.8.2** Paste both guard matrices with observed outputs, every AC with its provenance tag,
      and the 2.0.1 baseline decision.
- [ ] **2.8.3** Confirm nothing in the PR body reads as an operator checklist
      (`hr-ship-message-no-operator-checklist`).
