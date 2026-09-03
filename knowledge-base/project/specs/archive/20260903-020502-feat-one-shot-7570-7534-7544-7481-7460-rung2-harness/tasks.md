# Tasks — git-data rung-2 harness attribution

Derived from
[`knowledge-base/project/plans/2026-09-02-fix-git-data-rung2-harness-attribution-plan.md`](../../plans/2026-09-02-fix-git-data-rung2-harness-attribution-plan.md)
after the seven-agent plan review. Read the plan's **§Plan Review Revisions (R1–R24)** before
starting any phase — it records which instruments in the first draft could not fire, and several
of the tasks below exist only because of it.

Ordering is by **dependency direction**, not by file. Commit per phase, with the issue number in
the subject, so each is independently revertible.

---


## STATUS — PR A (this branch), 2026-09-02

Phases 0–4 are implemented and committed. **Phase 5 (#7460) is NOT in this PR** — it was split
into a follow-on PR B by operator decision; see the SCOPE SPLIT note in the plan and UC-1
RESOLUTION in `decision-challenges.md`. `apps/web-platform/infra/cloud-init-git-data.yml` is
UNTOUCHED here, so the rung-2 evidence hash is unaffected by PR A.

**Measured, not asserted.** Every suite below was run against the as-written tree:

| Suite | Result | Floor |
|---|---|---|
| `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` | 75 passed, 0 failed, Skipped: 0 | 69 → 72 (#7570) → 75 (#7544) |
| `tests/scripts/test-git-data-birth-readiness-gate.sh` | 77 passed, 0 failed | 69 → 77 (#7534) |
| `tests/scripts/test-git-data-rung2-evidence-capture.sh` | 48 passed, 0 failed | 34 → 48 (#7481) |
| `scripts/sentry-issue.test.sh` | 17 passed, 0 failed | unchanged |
| `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` | 9 passed, 0 failed | unchanged |

**Mutation-proved, with the baseline green and the SUT restored byte-identical after each:**

- #7570 — the pre-fix predicate reddens D1-MUT with `CAPTURE: unbound variable`, the defect verbatim.
- #7544 — reverting one spin site reads `bare=1 spins=5`; two rungs redden.
- #7481 — a bare `exit 2` at one site reddens 2 arms; dropping one redaction name reddens 1;
  neutering the consult so it never upgrades reddens 2.
- #7544 monitor — under Actions' real shell, a stale digest yields `drift=ubuntu-base` naming
  both digests with PROBLEMS empty; a missing `UBUNTU_BASE` yields PROBLEMS (detector failure).

**Three plan premises did not survive measurement and were corrected in place** (each is
argued at its call site rather than only here):

1. #7534's `templatefile(` check pins the FORM, not the canonical FILENAME. The filename pin
   ABORTed 25 arms in the gate's own suite (every synthesized tree binds `ci.yml`), and a moved
   template that keeps the form still hashes correctly — only indirection breaks the binding.
2. #7481's endpoint. `/projects/<org>/<proj>/events/` returns 403 to the least-privilege token
   and, with the broader one, ignores the search entirely (100 rows unfiltered, 0 for the host).
   `/organizations/<org>/events/` with explicit `field=` projections is event-level, honours the
   query, and works on the RO token — so the residual the plan documented never arises.
3. #7481's "extract from `fresh-host-boot-trail.sh`". That reader uses a different token against
   a different endpoint; extracting it would have meant either widening this route's token or
   changing a production script out of scope. The modes were added to `scripts/sentry-issue.sh`,
   which already owns the RO-token ladder and the 401/403 wording — so there is still no third
   Sentry reader in the repo, which is what that instruction was protecting.

**Two defects found in my own work by measuring rather than reading**, both fixed:

- A `shift 2` with only the flag left FAILS and leaves `$#` unchanged — an infinite loop. It
  was introduced in the new reader and already existed in the capture script's parser.
- ARM 16's first eyeball regex was case-sensitive and backtick-blind, reported a clean sweep,
  and TWO real sites survived it. Widened to anchor on the claim; both sites then fixed.

## Phase 0 — Preconditions (measure; do not inherit)

- [x] 0.1 Run the runcmd suite and record its real terminal line. Expected today:
      `git-data-runcmd-rehearsal: 69 passed, 0 failed, Skipped: 0 (69 assertions)`.
      **Do not quote the `t5-skip-persistence-bound-7510.test.sh` fixture** (`44/0/2 (46)`) — it is
      a fixture, the suite hard-exits below 69, and `_SKIP_CEILING=7`.
- [x] 0.2 Record all **four** anti-vacuity floors and their raise-itemisation conventions:
      evidence-capture (34), birth-readiness gate (69), runcmd (`-lt 69`), rung-2 rehearsal (71).
- [ ] 0.3 Migrate the hand-rolled floors to `tests/scripts/lib/gate-suite-harness.sh`
      **NOT DONE — unticked 2026-09-03 at review.** This was ticked by a bulk toggle over
      Phases 0-4, which is the anti-pattern the work skill names explicitly: a checkbox is a
      CLAIM, and a bulk replace marks every task verified with zero verification performed.
      All four floors are still hand-rolled with 2-3 duplicated literals each, and the stale
      `floor is 69` message the review found is exactly the drift this migration prevents.
      Left open deliberately rather than done here: it is a cross-suite refactor whose own
      commit should precede a floor raise, not ride along with four of them.
      (`gate_assert_ran <observed> <floor>`) **in its own commit**, before raising them — 3 literals
      per floor becomes 1, across four floors.
      **This is an established convention, verified: 12 `tests/scripts/test-*.sh` suites already
      source the harness** (`git grep -ln 'gate-suite-harness' -- 'tests/scripts/test-*.sh'`),
      including `test-git-data-host-birth-gate.sh` and `test-git-data-host-replace-gate.sh` — the
      two gates closest to this work. A narrower `gate_assert_ran`-only grep undercounts, because
      suites source the harness rather than naming that symbol; use the sourcing grep as the
      instrument.
- [x] 0.4 Re-derive the free ADR ordinal across all `origin/*` refs with
      `git for-each-ref refs/remotes/origin` (**not** `git ls-remote`, which counts tags).
      ADR-198 was free at plan time.
- [x] 0.5 Re-resolve the `ubuntu:24.04` **manifest-list** digest immediately before writing it:
      `docker buildx imagetools inspect ubuntu:24.04 | grep '^Digest:'`. Do **not** use
      `docker manifest inspect`, which returns the platform-specific digest.
- [x] 0.6 Re-validate the Sentry window parameter on the **events** endpoint (the issues endpoint's
      mandatory `start=`/`end=` pair need not carry over).
- [x] 0.7 Reconcile which Doppler config holds `SENTRY_ISSUE_RO_TOKEN` — the capture script's
      comment says `soleur/prd`, the token resolves under `prd_terraform`, and the capture step runs
      under `prd_terraform`.

## Phase 1 — #7570: D1 attributes its own failure

- [x] 1.1 Change the D1 read to `[ -s "${CAPTURE:-}" ]`. The `:-` is the mechanism; the
      `CAPTURE=""` init is optional.
- [x] 1.2 **Decide the `||` disjunct** — option (a) point `CAPTURE` at the real path before D1
      (preferred), or (b) delete the disjunct and say why. Do not leave it silently dead.
- [x] 1.3 Replace the `PRE-EXISTING HAZARD, TRACKED IN #7570` comment block; also correct the stale
      "skip ceiling at 2" line inside it.
- [x] 1.4 Add the `D1-MUT` mutation arm: a mutated emitter that dies at the `shift` (`_d_rc == 2`)
      producing no capture output must make D1 print **its own** message, not `unbound variable`.
- [x] 1.5 Raise the runcmd suite's `-lt 69` floor by the arms added, itemised.

## Phase 2 — #7534: canonical module-shape assertion (Guard 1)

- [x] 2.1 Add the two-part assertion before the payload loop, reusing the extractor's
      comment-strip so the two cannot disagree about what a comment is.
- [x] 2.2 **Carry the `(^|[^A-Za-z])` word boundary** into the occurrence count — without it
      `templatefile(` is counted and the gate aborts on the shipped tree (10 vs 9, measured).
- [x] 2.3 Use `grep -o … | wc -l` for the exactly-one `templatefile(` check, not `grep -c`.
- [x] 2.4 Update the `THE HONEST BOUND` comment: the four forms are now *inadmissible*, not
      *invisible*. Add the fourth, undocumented form. State that the existing `-lt 9` floor is
      **not** redundant with this check — it fires only downward.
- [x] 2.5 Arms A12–A15, one per binding form, on synthesized trees; each must ABORT naming the
      occurrence.
- [x] 2.6 Arm A16 (must-PASS): a **new** tenth payload file — not a second binding to an existing
      one, which the post-`sort -u` resolved count would false-ABORT. Digest must move on its
      content change.
- [x] 2.7 Arm: a **value-form** map entry (`foo = var.foo`) must NOT trip the gate — the row that
      stops Phase 5 from tripping Phase 2.
- [x] 2.8 Raise the birth-readiness floor (69), itemised.

## Phase 3 — #7544: digest-pin the base image (Guard 2)

- [x] 3.1 Add the `UBUNTU_BASE` literal with the manifest-list digest, the producing command, and
      the observed media type recorded in its comment.
- [x] 3.2 Replace all **six** live spin sites with `"$UBUNTU_BASE"`. Account for all **three**
      prose references, not two.
- [x] 3.3 Add the pinned digest and its measured `mke2fs` version to R1's failure detail so drift
      reads as a base-image change, not a template regression.
- [x] 3.4 `R1-PIN` arm using **the file's own published derivation**:
      `grep -cE '^[[:space:]]*docker run --rm'` = 6 (floor), plus zero bare `ubuntu:24.04` outside
      the literal and comments. **Not** `grep -c 'docker run'` (13, includes prose) and **not**
      `docker run.*@sha256:` (0 — the image is on a continuation line and then a variable).
- [x] 3.5 Justify in-file why a text-check over the suite's own source is right here, since that
      file explicitly rejects the antipattern elsewhere (ADR-188 residual stanza).
- [x] 3.6 Add the `ubuntu:24.04` case to `rule-audit.yml`'s existing `Detect zot pin staleness`
      step, sourcing the pin from `UBUNTU_BASE`. **Do not create a follow-through probe** — the
      sweeper closes a tracker on exit 0.

## Phase 4 — #7481: the Sentry second channel (Guard 3)

- [x] 4.0 **Reuse, do not rebuild.** Extract the shared reader from
      `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`, which already implements shape
      validation, the non-verdict failure message, event-level `level == "fatal"` filtering and a
      run anchor — on the `/projects/{org}/{proj}/events/` endpoint, which returns individual
      events and therefore has no issue-group residual. If extraction proves infeasible, record why
      in the PR body. **Do not create a third Sentry reader.**
- [x] 4.1 Build the query: event-level host + `level == "fatal"`, pinned org and project literals
      with the project id's source and measurement date in a comment, `end` tracking *now*.
- [x] 4.2 Liveness anchor on a **wide** window (not the run window), excluding the rehearsal host,
      projecting **counts or ids only** — never `title`/`culprit` into the public artifact.
- [x] 4.3 Split causes: 401 and 403 **deterministic and terminal** (do not retry — they burn the
      16-minute poll on a paid host); everything else one catch-all carrying `HTTP <code>` and
      `.detail`. Include the measured **400**. Add a token-presence preflight and a `command -v jq`
      check. Every cause carries a `**Next:**` clause stating that re-dispatch is not warranted.
- [x] 4.4 `jq -e 'type == "array"'` **before** any length is taken.
- [x] 4.5 Route every TRANSIENT exit through a single `transient()` helper; assert placement by
      **deriving** over `exit 2` sites with a floor, excluding the derivation fault by name.
      **Six sites, not four** — including the two transport-failure sites the first draft missed.
- [x] 4.5b Define the three undefined verdicts: a Sentry-derived FAIL is `exit 1` with its own
      summary variant; silent-both is TRANSIENT (must-PASS arm); the **PASS path gains a Sentry
      cross-check** (this also discharges §5.0's finding).
- [x] 4.6 **MERGE BLOCKER — widen the redaction tuple to ten names**, not one:
      `SENTRY_ISSUE_RO_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `DOPPLER_TOKEN`,
      `HCLOUD_TOKEN`, `BETTERSTACK_LOGS_TOKEN`, `GIT_DATA_LUKS_KEY` + the three incumbents. The
      workflow writes both AWS keys into `$GITHUB_ENV`, so they are in the capture step's
      environment, `tee`'d verbatim into a 7-day artifact on a **public** repo. Arm per name.
      File the allowlist-inversion separately (length floor ≥12, non-secret name exclusions, and
      the structural fix: stop writing R2 creds to `$GITHUB_ENV` at all).
- [x] 4.6a Arm: the Sentry `curl` carries no `-v`/`--trace*` and no token in a URL.
- [x] 4.6b Arm: no `set -x` in the workflow; no `set -x`/`printenv`/`env |` in the capture script.
- [x] 4.6c **Project `tags.detail` + `tags.rc` on the Sentry verdict print** (§4.5a). Without it the
      new FAIL path reproduces the plan's own baseline — a stage and an rc, no cause, on a host
      that no longer exists. Arm: an empty `detail` reports "FAIL, cause unavailable".
- [x] 4.7 Remove the eyeball instructions — **assert the class with a grep-with-floor, do not
      enumerate**. The site count went 2 → 3 → 7 across three passes of this plan; §4.5 already
      proved enumerated sets rot. Verb set: `Confirm against Sentry`, `Check Sentry`,
      `Check the Better Stack`, `check the .* secret`, across workflow + runbook + capture script — and **preserve** the artifact
      pointer, `DO NOT simply re-dispatch`, the **two-dispatch cap**, and the #7025 banner. Rewrite
      the now-stale #7116 sentence. Extend the runbook's outcome table with the new sub-causes.
- [x] 4.7b Update the capture script header's `WHAT THIS DOES NOT CLAIM` block — it currently says
      `#7116 owns that work; do not do it here` about a **closed** issue.
- [x] 4.8 Fixtures reproduce the measured production artifacts: the `level:info` beacon
      (`git-data boot stage`, `stage:bootcmd_start`) and the real fatal (`stage:luks_open`).
- [x] 4.9 Sentinel on every arm; raise the floor; anchor the config assertion on the **Sentry
      paragraph**.
- [x] 4.10 Window-derivation arm (stubbing the helper must redden) + an arm asserting a
      `start=`-only form is never emitted.

## Phase 5 — #7460: bake the ingest token (the single cloud-init edit)

- [ ] 5.0 **Fix the `HOST_SQL` row window first.** Phase 5 makes many stages emit; `LIMIT 50 DESC`
      can drop an early fatal → PASS over an unread fatal. Add an unlimited `level='fatal'` query
      (or scope the limit), and add an arm with >50 rows where the fatal is oldest.
- [ ] 5.0b Update the **three** code sites recording the prior rejection — including `main.tf`,
      which is a digest input, so a stale comment ships inside the attested byte set.
- [ ] 5.1 Module variable + one brace-free single-line map entry + both call sites. **`0600` vs
      `0755` is the open design point** — see 5.2.
- [ ] 5.1a Evaluate a **per-source** Better Stack ingest token for git-data — it deletes the
      four-host rotation coupling outright and stays compatible with §5.6. Take it or reject it
      in §Alternatives with a reason.
- [ ] 5.2 **Decide the token's on-host mode.** Prefer `write_files` + `permissions: '0600'` (NOT
      `printf > file; chmod 600`, which is 0644 for a window). Pass the token via `curl -K -`, not
      an argv `-H` — `/proc/<pid>/cmdline` is world-readable. Extend `_devalue` to the token.
      Note the `0600` file defeats a file read, **not** RCE: the git-data firewall has zero rules,
      so egress is open and the Hetzner metadata endpoint serves all of `user_data` regardless. Baking into the `0755` `git-data-emit` makes it
      readable by the `git` account that serves users' pushes, while `doppler_token` is `0600`.
      Prefer a `0600` root env file the emitter sources, unless a measured read-ordering obstacle
      rules it out. `${betterstack_logs_token}` must not start a line
      (`git-data-template-strip.test.sh` arm 5).
- [ ] 5.3 Ingest-failure Sentry mirror. **Specify its shape**: it cannot call `git-data-emit`
      (recursion on its own failing sink), so it is a second inline `curl`; budget its real byte
      cost; satisfy the runcmd emit-site analyzer (guarded detail source, pairwise-distinct arg-4
      name, no `cloud-init-output.log`). Keep the path non-fatal — only rc 2 refuses a boot.
      Weigh the sibling's boot-time Doppler **re-fetch** alternative
      (`cloud-init-inngest.yml`) and record why it was not chosen.
- [ ] 5.4 Mirror the map into `git-data-userdata-budget.sh`; re-run it. Note AC 21 (not AC 22) is
      what catches a forgotten mirror — the parity test is blind to value-form entries.
- [ ] 5.5 Splice `betterstack_logs_token` into `_mod_var_expected` (11 → 12, sorted) in
      `git-data-rung2-rehearsal.test.sh`, and raise its floor (71).
- [ ] 5.6 Add `betterstack_logs_token` to the **existing** `_pin` not-on-allowlist loop — one
      token. Do **not** add a byte-identical-to-`origin/main` arm (the tautology this repo already
      deleted). Add the no-default check via the existing `_var_default()` helper.
- [ ] 5.7 Update `git-data-emit.test.sh`'s channel-split contract, ADR-149's falsified premise,
      `git-data-gc.service`'s comment, `git-data-birth.md`'s inverted directive, and
      `cloud-init-user-data-size.test.ts`'s length model.
- [ ] 5.8 ADR-198: cite ADR-096 and discharge `(weigh before widening use)`; state the
      derivable-vs-directly-readable rule and that it does **not** extend to `GIT_DATA_LUKS_KEY`;
      price the cross-host rotation radius; correct nine → **eight** stages; link (do not
      duplicate) the PENDING Better Stack DPA.
- [ ] 5.9 ADR-147 addendum, scoped to the falsified *descriptive* sentence only — the normative
      invariant is preserved.

## Phase 6 — Cross-cutting

- [ ] 6.1 De-duplicate the Guard Contract / ACs / Test Scenarios (~25 mutations stated three
      times); consolidate to ~14 rows; move AC 36 to Non-Goals.
- [ ] 6.2 Retarget or drop AC 26 / Test Scenario 23 — ADR-147's frozen literals are the web host's
      and `git-data cloud-init FAILED` exists nowhere in the repo. The real freeze is R3(3b)(iv).
- [ ] 6.3 Add inline load-bearing-sub-value comments at each Sentry consult site (the
      defense-in-depth learning wants code, not a plan paragraph); delete R3's ordering argument.
- [ ] 6.4 Mechanize the two-dispatch cap in the existing `Validate dispatch inputs` step, or file
      it as a deferral with the trigger *"before the next rung-2 dispatch"*.
- [ ] 6.5 Re-run the code-review overlap scan over the full 17-path manifest.
- [ ] 6.6 Run all four suites, `scripts/test-all.sh`, `run-registered-suites.sh`,
      `lint-infra-no-human-steps.py --changed --base origin/main`,
      `lint-encryption-posture.py --repo-sweep`, `lint-guard-contract.py`.
- [ ] 6.7 Re-derive the ADR ordinal after the final rebase; sweep plan + tasks + ACs if it moves.

## Non-Goals

- **No rehearsal dispatch in this run.** It is a paid, operator-chosen action capped at two per fix
  attempt, and the harness must be on `main` first. Successors: **#7025** (gate-release tracker,
  `follow-through`) and **#7204** (the Phase 4 blocker whose root cause ADR-163 already fixed).
- The `HOST_SQL` `detail` field — already on `main` since `dfcf7bd26`.
- ADR-163's ext4 quota root cause — fixed 2026-08-03, out of scope.
- A general mechanism binding `templatefile` **argument values** into the evidence — a redesign of
  what the evidence attests; deferral issue filed per §5.6.
