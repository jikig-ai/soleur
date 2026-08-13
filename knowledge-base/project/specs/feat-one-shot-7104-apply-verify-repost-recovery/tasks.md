# Tasks — feat-one-shot-7104-apply-verify-repost-recovery

Derived from `knowledge-base/project/plans/2026-08-12-fix-apply-verify-repost-recovery-plan.md`
after plan review.

**Read this first.** The plan's `## Implementation Phases`, `## Test Scenarios` and both function
signatures were written before the R13–R15 review revisions and are **superseded** by them
(plan R15.2). Task 1.1 reconciles them. Until it is done, R13/R14/R15 are authoritative.

**The work splits into two PRs** (plan R14.3, CPO condition C1). The order is forced, not
stylistic: PR-B's recovery would fire on the wrong runs without PR-A's discriminator.

---

## Phase 1 — Reconcile the plan (blocks everything else)

- [x] **1.1** Regenerate `## Implementation Phases`, `## Test Scenarios`, and both function
      signatures from R13/R14/R15 so the plan describes **one** machine. Specifically remove the
      R3-reversed teardown relocation from Phase 3, add the `DPF_REPLACED` extraction and the
      saved-plan rework, and correct T1 (a stale frame with `DPF_REPLACED == false` must classify
      non-zero).
- [x] **1.2** Fix the `GATE_MIN_ASSERTIONS` circular reference: Phase 0 records the **pre**-change
      count; the raise happens after the new assertions exist, from a **post**-change measurement.
- [x] **1.3** Restate Guard 1's Property to cover the escape-hatch arm (R15.1) and the
      `DPF_REPLACED == false` arm, and extend the mutation matrix to the post-revision arm set.

## Phase 2 — Preconditions to measure (not assume)

- [x] **2.1** Measure clock skew: compare a recent run's frame `start_ts` against that run's runner
      clock. **This decides whether R2 ships at all** (plan R13.3). Material → implement as a
      single comparator, no fallback arm. ~0 → defer with a re-evaluation trigger.
- [x] **2.2** Probe `FILE_MAP ⊆ TRIGGER_FILES` (plan R15.7). R1's skip arm is only truthful if it
      holds.
- [x] **2.3** Confirm the production call-site pin's three clauses survive an indentation-only wrap
      into `verify_once` (`adjudicate_infra_config /tmp/`, `infra_config_count_invariant /tmp/`, an
      intervening `done`).
- [x] **2.4** Record the pre-change assertion count from `bash apps/web-platform/infra/infra-config-gate.test.sh`.
- [x] **2.5** Re-derive the ADR ordinal across **all** `origin/*` refs (not just `origin/main`).
- [~] **2.6** PR-B SCOPE (gates task 6.4, not PR-A) — Verify `terraform plan -replace=… -target=…` composes and shows exactly one replaced
      resource. Read-only; no apply.

## Phase 3 — PR-A: the sensor (ships first)

- [x] **3.1** Change `Terraform plan` / `Terraform apply` to produce and consume a **saved plan
      file**. This is a dependency of 3.2, not a bonus — `DPF_REPLACED` read from a plan equals
      what was applied only if that plan is what was applied. Independently fixes the confirmed
      TOCTOU (the `host_creates` guard has been adjudicating a discarded plan).
- [x] **3.2** Extract `DPF_REPLACED` from the saved plan's `resource_changes[]`, using the repo's
      `select(.change.actions? | index(...))` convention.
- [x] **3.3** On `DPF_REPLACED == false`: assert the frame is UNCHANGED across the apply
      (equality against a pre-apply reading), plus a runner-side `APPLY_START_EPOCH` assert on
      the degraded sub-arm. **Rewritten at review:** the original text said *skip the freshness
      pin and adjudicate on count + content only* — the design ADR-186 lists under
      *Alternatives considered* as REJECTED, because on this arm a content match is guaranteed
      by construction. Task 1.1 was meant to reconcile superseded plan text into one machine
      and this line escaped it; left as-was, a future reader would conclude the implementation
      drifted from the plan when in fact the plan text was stale. Ends the three false-red merge classes
      (`seccomp-bwrap.json`, `apparmor-soleur-bwrap.profile`, `server.tf`).
- [~] **3.4** DEFERRED — task 2.1 measured skew at ~0 (within a ~±2 s floor), so R13.3's own branch says do not implement. Tracked in #7527. Original text: Implement R2 **only if** task 2.1 justified it, as a single comparator
      (`FRAME_START_TS` exists and differs from `PRE_APPLY_FRAME_START_TS`, absent-pre as sentinel).
- [x] **3.5** Extend `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` to pin
      `FILE_MAP ⊆ TRIGGER_FILES` (task 2.2's invariant).
- [x] **3.6** Tests for 3.2/3.3 in `apps/web-platform/infra/infra-config-gate.test.sh`.
- [x] **3.8** Write ADR-186 (the PR-A decision record). Added at review — Phase 3 had no row
      for it, and task 9.2 is a DIFFERENT ADR belonging to PR-B.
- [x] **3.7** Re-derive PR-A's own brand-survival threshold — it removes production writes and adds
      none, so it is plausibly `none` rather than inherited.


---

# PR-B — Phases 4–10 (the bounded re-push)

> **[Reconciled 2026-08-13.]** PR-A (#7509) merged and is verified live. These phases were written
> before the R16.2 design pivot was fully propagated and before PR-A measured the ground they stand
> on. **The authoritative source for every phase below is `# R18 — PR-B` at the end of
> [the plan](../../plans/2026-08-12-fix-apply-verify-repost-recovery-plan.md).** Corrections are
> inlined per task with an `R18.x` citation; where a task's original text is struck it is kept
> visible rather than deleted, so a reader can see what changed and why.
>
> Three names appear below that must **not** be built: `infra_config_bounded_verify`,
> `infra_config_no_new_frame`, and a `repush_once` *function*. The one function PR-B adds is the
> pure predicate `infra_config_should_repush` (R18.1, R18.2).
>
> **STOP — read `# R19` and `# R20` in the plan before starting Phase 4.** An escalated five-agent
> review found that the design as described below does not work: the poll loop's break condition
> cannot see a stale frame, so the re-push block is **unreachable on the exact shape it was built
> for** (R19.1, confirmed independently three times). Four further fail-opens were found (R20.3–R20.6),
> the assert that bounds the production write has **never been evaluated** (R20.1, now blocking task
> **4.0**), and **two design forks are open** — extract the step body to a script (R18.16) and split
> the recovery into graded steps (R20.2). `/soleur:deepen-plan` adjudicates the forks. Do not start
> Phase 5 until task 4.0 has a number in it.

## Phase 4 — PR-B RED: the contract's tests, before the contract

**Design pivot (plan R16.2).** There is **no** higher-order `infra_config_bounded_verify`. The
decision logic is a **pure predicate** matching the seven existing siblings in
`infra-config-gate.sh`; the `if`/`else` that consumes it stays in the YAML. This is what keeps
`set -e` in force (R16.1) and what makes the tests exercise the real decision rather than stubs.

```
infra_config_should_repush <response-file> <pre-frame-start-ts> <apply-start-epoch> <dpf-replaced>
```

Measured convention it must match: `infra-config-gate.sh` carries **no `set` directives** — it is a
sourceable library of quiet, pure adjudicators. Exit status is the verdict; nothing is echoed.

- [ ] **4.0** **BLOCKING (R20.1) — measure the recovery plan's cardinality before anything else is
      built.** Read-only, no apply: run `terraform plan -replace=terraform_data.deploy_pipeline_fix
      -target=<the same four targets> -var="ssh_key_path=${CI_SSH_PUB}" -out=tfplan-repush` under
      `doppler run --name-transformer tf-var`, then `terraform show -json tfplan-repush`, and record
      **counts and addresses only** — never the JSON, which carries the live prd Doppler token and
      the webhook HMAC in cleartext. Run `destroy-guard-filter-web-platform.jq` over it. Delete the
      JSON immediately. The whole design rests on this being **exactly one** replaced managed
      resource: `deploy_pipeline_fix` `depends_on` two resources that carry SSH `remote-exec`
      provisioners, and `-target` is transitive at the resource level. If the count is not 1, the
      cardinality assert would abort **every** recovery on the failure path of a real incident, and
      because the path ships dark nobody would ever learn. Shape the I1–I3 fixtures from the measured
      addresses and state the number in ADR-187 as the invariant the assert pins.
- [ ] **4.1** Predicate cases — one per row of the discriminator table, including the
      `start_ts == baseline` boundary (equality is fresh, matching the existing `-lt`). Three
      clauses only: parses, numeric `start_ts`, not newer than the baseline (plan R13.8 — the
      `files_failed` / `fatal_line` clauses are unreachable). Cases are enumerated as **P1–P8** in
      plan R18.10.
- [ ] **4.2** `dpf-replaced == false` must return non-zero regardless of frame shape (R1(A)), and
      the `^(true|false)$` polarity guard must reject `null`, empty, `TRUE` and absent (R17.1).
- [ ] **4.3** Guard 1 matrix re-derived against the predicate: each row is "input X → wrong
      verdict", which is **stronger** than a stub-driven row because it exercises the real decision.
      **The rewritten matrix is in the plan's `## Guard Contract` §Guard 1** — seven rows, including
      the allow-list row (5), the vacuity row (6) and the positive control (7).
- [ ] **4.4** The escape-hatch case (R15.1): an `ALLOW_MISSING_STATUS` 404 fall-through must never
      be readable as "verified". Under the predicate design this is structural rather than a
      return-code convention — assert it anyway.
- [ ] **4.5** ~~`ALLOW_MISSING_STATUS=true` fall-through fidelity (R4c).~~ **[MERGED into 4.4 —
      R19.6.]** 4.4 and 4.5 target the same single scenario, which R18.10 lists exactly once as P7;
      two rows invite writing the test twice. **Re-scoped to what P7 does not cover (R20.4):** assert
      the hatch is **unavailable once the latch is set** — a 404 on the last poll after a re-push
      must not fall through to `exit 0`.
- [ ] **4.6** **PRIMARY (promoted — R18.4).** One integration-shaped test that drives the **real**
      extracted `run:` body twice against fixture responses and proves pass 2 was reached (plan
      R13.7). Cases **I1–I3** in plan R18.10. Promoted from "one test" to the primary acceptance
      criterion because R18.4 establishes the recovery path is **not producible in production on
      demand** — this test is the only verification that the wired decision behaves. Locate and
      reuse the repo's existing `run:`-block extractor (PR-A syntax-checked 19 extracted blocks);
      do not write a second one. Stub `curl`, `terraform` and `doppler` on `PATH`.
- [ ] **4.7** Assert each pass's verdict **independently** — no case may collapse to "the last
      attempt passed". Related: no case's expected verdict may be derived from the fixture builder's
      own defaults (Guard 1 row 6).

## Phase 5 — PR-B GREEN: the contract

- [ ] **5.1** Add `infra_config_should_repush` to `apps/web-platform/infra/infra-config-gate.sh`,
      following the file's pure-adjudicator convention. Allow-list semantics: every unclassifiable
      input returns non-zero. Quiet — the exit status is the verdict.
- [ ] **5.2** No higher-order dispatcher. No function takes a function name.
- [ ] **5.3** No existing function's behaviour changes.

## Phase 6 — PR-B: the consumer (workflow wiring)

- [ ] **6.1** Keep the poll loop + terminal adjudication + freshness pin **in the step body, not in
      a function** (R16.1 — a function called from a condition context silently disables `set -e`
      for its whole body). ~~The second pass re-runs the block; accept the duplication.~~
      **[Corrected — R18.2.]** Do **not** duplicate the block: task 6.2 wins. Duplication adds a
      second `count_invariant`, `done` and `adjudicate`, and the call-site pin takes `head -1` of
      each grep, so it would silently pin the first copy and stop quantifying over the second.
- [ ] **6.2** Widen the **existing** poll loop's attempt count rather than adding a second loop
      (plan R13.4 — a second `done` would make Guard 2's "strictly between" clause ambiguous).
      ~~The widened loop's own break condition *is* the re-verify R15.3 requires.~~
      **[FALSE — R19.1, the review's top finding.]** `infra_config_count_invariant` reads
      `exit_code`, `files_failed`, `files_written` and `files_total` — **never `start_ts`**. On the
      #7220 shape the frame on disk is a *previous, complete* apply (`exit_code=0`, 19/19,
      `files_failed=0`), so the invariant **holds**, the loop breaks on attempt 1, and a re-push
      placed after the break is unreachable on the very shape it exists for. The predicate must be
      consulted **before** the break:
      `if count_invariant …; then if [[ latch unset ]] && should_repush …; then <re-push>; continue; fi; break; fi`.
      Keep the `infra_config_count_invariant /tmp/` token textually before the `done` so the pin's
      `ci_line` still resolves. The bound still widens, but to give the post-latch passes somewhere
      to run — and per R20.5 the budget must be a function of the latch (`while` + a counter granting
      a fixed further budget once it fires), not a fixed list, or a re-push on a late attempt yields
      a **false red on a successful recovery**. Add an integration fixture whose pass-1 frame is
      **complete, healthy and stale** — the real production shape — and assert the re-push fires on
      it; without that fixture the fix is unverified. **R21 pins the fixture's exact shape:**
      `exit_code=0`, `files_written == files_total == expected`, `files_failed=0`, and a **stale
      `start_ts`** — that frame satisfies `infra_config_count_invariant` in full. Any pass-1 fixture
      that *fails* the count invariant is testing a state the #7220 race does not produce and would
      let this defect survive green.
- [ ] **6.3** Retain the last **HTTP 200** response separately from the last response overall, and
      feed the classifier that artifact (R15.4). **Truncate the response file per pass**
      (R17.2/R18.8 §7) — `curl -s -o` on a transport failure leaves the prior body in place, so
      pass 2 can otherwise adjudicate pass-1 bytes, and the #7220 alert step reads the same file.
- [ ] **6.4** Add the re-push as an **inline latched block** inside the widened loop — *not* a
      function (R18.2: a function invites `if ! repush_once`, which kills `errexit` for a body
      containing a production `terraform apply`). It must:
      - re-record the baseline as a **plain shell assignment**, never `$GITHUB_ENV` (R4a), using
        the **observed stale frame's own `start_ts`**, recorded **once before** the re-push fires
        and never re-read (R15.5, R18.8 §6 — both operands are then host-clock, so skew cancels
        without shipping R2, and the baseline cannot advance out from under the single retry);
      - set the latch **only after the re-push actually executes**, never on first sight of the
        classifying shape (Guard 2 row 4);
      - run the scoped `-replace` + `-target` plan **wrapped in `doppler run --name-transformer
        tf-var`** — ~~wrap the apply~~ **[Corrected — R18.8 §3]**: `terraform apply <planfile>`
        rejects `-target=`/`-var` and takes values from the plan file, so the wrapper belongs on the
        **plan** invocation and is inert on the apply. **The plan invocation must also pass
        `-var="ssh_key_path=${CI_SSH_PUB}"` (R19.4 §1)** — `variables.tf` defaults `ssh_key_path` to
        `~/.ssh/id_ed25519.pub`, which does not exist on the runner, and `server.tf` does
        `public_key = file(var.ssh_key_path)`; `-target` is transitive and `deploy_pipeline_fix`
        reaches `hcloud_server.web` through its `depends_on`. Without it the recovery plan **errors
        under `-input=false`**;
      - assert `[[ -s "$CI_SSH_PUB" ]]` **and** that the S3 backend credentials
        (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, exported by the `Extract backend
        credentials` step) are non-empty — `--name-transformer tf-var` would rename them, so they
        must be read as plain env vars (R18.8 §4);
      - apply R3's **exact-cardinality** assert, pinning `mode == "managed"` and exactly one
        replaced resource, and re-run the `host_creates` destroy-guard against the second plan's
        JSON with the same `destroy-guard-filter-web-platform.jq`;
      - use **no status-discarding constructs** (`|| true`, `2>/dev/null` on the apply) while
        **using** the AP-022-sanctioned `|| rc=$?` capture and an explicit
        `|| { echo "::error::…"; exit 1; }` branch — without it the step dies mute under `set -e`
        (R17.2, R18.8 §5). `scripts/lint-workflow-errexit-capture.py` enforces this.
      - ~~add **no bare `sleep`** for the handler settle~~ **[WITHDRAWN — R20.5.]** Reinstate the
        settle. The premise was wrong twice: measured on run 31714143720, plan (6 s) + apply (3 s) =
        **9 s** against a window of up to **11 s**, so "far longer" is false; and the interval is
        measured in the wrong place anyway, because `push-infra-config.sh` is a `local-exec`
        provisioner whose 202 fires at the **end** of the apply, so the 5–8 s settle starts *there*.
        Use the same constant the step's own opening `sleep 8` already documents;
      - write `repush_attempted=true` to `$GITHUB_OUTPUT` **before the first abort point**, not with
        the latch (R20.3). `$GITHUB_OUTPUT` writes survive a later `exit 1`, but a write that is
        never reached does not — and tying it to the latch makes it absent on exactly the runs where
        a production write was attempted and went wrong. Write `repush_failed=<phase>` before each
        `exit 1` in the block (R20.6). The latch stays where it is, after the apply, because its
        property is boundedness;
      - disable the `ALLOW_MISSING_STATUS` escape hatch once the latch is set (R20.4) —
        `[[ "$ALLOW_MISSING_STATUS" == "true" && "$REPUSH_DONE" != "true" ]]`. Without this, a last
        poll of 404 after a re-push falls through to `exit 0`: the job goes **green** having
        performed a production write and adjudicated nothing, re-arming the five `success()` steps
        including the one that closes the founder's drift issues;
      - name the artifacts `tfplan-repush` / `tfplan-repush.json` so the graded apply-#1 plan cannot
        be clobbered, and delete the JSON via `trap 'rm -f tfplan-repush.json' EXIT` — the only form
        that survives all six abort paths. It carries the live prd Doppler token and the webhook HMAC
        in cleartext; never `cat` it on an error branch (R20.7 §2);
      - pass `-lock-timeout` on both the plan and the apply, so a killed or cancelled re-push cannot
        leave the S3 backend lock held and block every subsequent apply on the sole no-SSH
        remediation path (R20.7 §3);
      - `echo` one line at the `should_repush` call site naming the branch taken, so a run that
        declined can be told apart from one where the block was skipped or where an unvalidated
        `APPLY_START_EPOCH` silently suppressed the recovery (R20.7 §8).
- [ ] **6.5** Add the `declare -F` anti-vacuity check, mirroring the existing
      `declare -F infra_config_red_alert` pattern. **[Corrected — R18.1]** it targets
      ~~`infra_config_bounded_verify`~~ **`infra_config_should_repush`** — the sourced predicate is
      the only thing a `declare -F` check can meaningfully guard.
- [ ] **6.6** The step's exit code remains the single terminal verdict. **No `continue-on-error`.**
- [ ] **6.7** Do **not** relocate the bridge teardown (R3 reversed this). The re-push needs no SSH:
      `deploy_pipeline_fix`'s push is a `local-exec` provisioner, and the cardinality assert aborts
      if the second plan touches anything else (R18.8 §8).

## Phase 7 — PR-B: observability

- [ ] **7.1** Emit one Sentry `warning` event, `op=infra-config-repush-attempted`, carrying attempt
      number and outcome. It is a breadcrumb, **not** the counter — Sentry is write-only here.
      **[Corrected — R18.6]** it is emitted from a **separate step** gated on a `repush_attempted`
      step output, mirroring PR-A's `Report degraded freshness evidence (#7104)` step. This keeps
      `SENTRY_*` and `GH_TOKEN` out of the step that holds prod-write Terraform credentials and
      renders the verdict, which dissolves R17.6. `tags.feature` is **mandatory** — every
      `issue-alerts.tf` rule filters `feature` + `op` as a `filter_match="all"` pair.
      **The step must be `if: always() && …outputs.repush_attempted == 'true'` (R19.4 §3)** — the
      report matters *most* on the terminal-red path, where the gate step exits 1; a bare
      `success()` gate would drop it on exactly the runs worth counting. "Outcome" is unknowable at
      output-write time, so derive it from `steps.infra_config_gate.outcome`, not a second output.
      Guard the whole step with `set +e` / a terminal `exit 0` — never `continue-on-error`, which
      AC18 bans (R20.7 §10).
- [ ] **7.2** Create the ledger issue **closed**, outside the `ci/` namespace, titled as a running
      tally; widen its dedupe query to `--state all`. Write it with plain `gh issue` calls —
      **do not touch `scripts/infra-config-red-alert.sh`** (measured: three labels hardcoded across
      five sites, fail-open by contract; widening the P1 helper is the exposure this avoids).
      Sequence the body write and the `gh issue edit --body-file` call in separate steps, never
      batched (`2026-05-12-gh-issue-edit-parallel-file-write-race.md`). Build the body with
      `printf` to a temp file, not a flush-left heredoc inside `run: |`
      (`2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md`).
- [ ] **7.3** Create the ledger label as an explicit task — measured: `gh label list --limit 300`
      has **no** matching label, and R14.2 moved it out of `ci/`. Proposed name:
      **`infra-config-recovery-ledger`**. Guard the emission so a failure can never red a run that
      actually recovered.
- [ ] **7.4** Exclude dispatch-triggered runs from the counter (R15.8).
- [ ] **7.5** **[FOLDED into 7.2/7.3 — R19.6.]** Once corrected it names no mechanism 7.2/7.3 do not already build — the same shape as the cut 7.7 and the discharged 9.3. Its acceptance moves into 7.2/7.3's definition of done. Add the ≥3-in-30-days escalation. **[Corrected — R18.7]** it ships as a **queryable
      counter plus the ledger title**, and must **not** be described as an alert route: no
      `sentry_issue_alert` rule matches a new `op=`, exactly as #7527 already records for
      `op=infra-config-preframe-degraded`. Claiming otherwise is the AP-021 violation this plan
      exists to avoid. Add the paging rule to #7527's scope with a re-evaluation trigger.
- [ ] **7.6** ~~One `$GITHUB_STEP_SUMMARY` line naming both attempts.~~ **[REPLACED — R20.7 §7.]**
      Written standalone it renders *orphaned above* the `Post-apply summary` step's own heading, and
      a summary line is the least durable of the three channels. Instead add a `**Self-healed:**`
      line **inside** `Post-apply summary` (which already runs `if: always()` and is the one artifact
      the founder actually sees), reading `repush_attempted` and linking the ledger issue. This is
      the only thing that converts property (4) from pull-only to push: as designed, a recovered run
      is a green job, a summary identical to a normal run, a Sentry event matching no alert rule, and
      a ledger issue deliberately built not to notify — so the honest answer to "can the operator
      tell a recovered run from a never-failed one" was **no**. It also gives the ledger its only
      inbound path.
- [ ] **7.7** ~~Verify the repo watch setting.~~ **[CUT — R18.7.]** The setting is not readable with
      the credentials available (`gh api repos/:owner/:repo/subscription` → `HTTP 404`, "needs the
      `notifications` scope"). The property it protected — *the ledger never notifies* — is bought
      by construction instead: the ledger is created **closed** and the workflow only ever edits its
      title and body. GitHub notifies on comments and state changes, not on body/title edits.
      Replaced by an assertion (AC18): the workflow contains no `gh issue comment` and no
      `gh issue reopen` against the ledger.

## Phase 8 — PR-B: Guard 2 and the floor

- [ ] **8.1** Extend the production call-site pin. **[Corrected — R18.3]** ~~the workflow calls
      `infra_config_bounded_verify`, and `verify_once` is invoked at most twice~~ — neither exists.
      The added clauses are: the workflow calls **`infra_config_should_repush`**; the re-push block
      appears exactly **once**; it is latch-guarded; and the loop still has exactly **one** `done`.
      Keep the three original clauses (`count_invariant` in-loop, a `done`, terminal
      `adjudicate_infra_config`) **byte-identical**. Follow the shape of the existing "#7104
      PRODUCTION CALL-SITE PIN" block, which already pins `infra_config_dpf_replaced` before
      `infra_config_frame_stability` by resolved line number.
      **Required, or Guard 2 row 1 cannot be driven RED (R19.2, measured):** the pin resolves its
      `done` with `awk '… $1=="done" {print NR; exit}'` — first match, first *field*, so indentation
      is irrelevant and any nested `for`/`while`/`until` (or a `done < <(…)`) inside the re-push
      block satisfies it. With `adjudicate_infra_config` moved into the loop and a nested `done`
      above it, the pin still reports PASS (`ci=2 adj=6 between_done=5`), so the #6594 coin-flip
      mutation stays green and **AC21 fails at implementation time**. Replace the first-match scan
      with a **counting** pass asserting **exactly one** `$1=="done"` strictly between the anchors.
      That also makes "the re-push block contains no nested loop" enforced rather than hoped for.
      **Also add the library clause (R20.7 §1):** Guard 2's assembly claims total quantification over
      production writes but `source ./infra-config-gate.sh` is invisible to it — and PR-B adds a
      function to that library, which is a pure adjudicator by *convention only*. Assert the library
      contains no command-position `terraform`, `curl`, `ssh`, `systemctl`, a mutating `doppler`
      subcommand, or `gh issue` (command position, not bare token — 20+ comment-only occurrences
      exist; `cq-assert-anchor-not-bare-token`).
- [ ] **8.2** Add the Guard 2 mutation rows. **[Corrected]** the rewritten matrix has **seven**
      rows (plan `## Guard Contract` §Guard 2); the old "row 4 is cut" note referred to the
      pre-rewrite table.
- [ ] **8.3** Raise `GATE_MIN_ASSERTIONS` to the post-change **measured** count, with no slack.
      **[Corrected — R18.8 §1]** the current value is **106** and the suite reports `106 passed,
      0 failed` — flush, no headroom. The PR-A findings' "95" is stale. Re-measure; do not carry
      either number forward.

## Phase 9 — Documentation

- [ ] **9.1** Edit the 000/502/503 recovery prose and the alert step's operator guidance so each
      remedy is attached to the failure shape it belongs to. Never print a bare
      `terraform apply -replace=` fragment without its full resource address; keep the
      `hcloud_server.web` prohibition in every body.
      **Add a fourth alert class (R20.6 — R18.8 §7's cut is withdrawn).** A failed re-push currently
      lands in the #7220 alert's final `else`, which tells a non-technical founder *"the handler did
      not die… the files that landed are on the host, and app health is unaffected — this is an
      ACTIVATION failure"* and routes them to a Better Stack query that returns nothing. Every clause
      is false when the *terraform* half failed mid-gate. It costs **no edit** to the fail-open
      helper: follow the `STABILITY_VERDICT` precedent 40 lines above — a new discriminator added as
      a branch in the **caller**, keyed on a new gate-step output. Add one
      `elif [[ -n "${REPUSH_FAILED:-}" ]]` arm above the frame-derived branches naming the phase,
      warning that state may hold a tainted resource or a held lock, and routing to the
      `-replace=terraform_data.infra_config_handler_bootstrap` lever. Branch the STALE FRAME message
      on the latch too, so a run whose re-push already failed is not told to try a DPF replacement
      (R20.7 §6).
- [ ] **9.2** Write the ADR — **provisional ordinal 187** (PR-A took 186; re-derived across all 67
      `origin/*` refs). One decision (the gate may now write production, bounded to one shape-gated
      re-push; the terminal verdict never leaves the step that fails closed), plus the **ADR-072
      distinction** stated as ADR-186 states it (ADR-072 waited on a signal that WAS going to
      arrive; here the newer frame is never coming) and R15.6's cancellation/timeout consequence.
      Cite `decision-challenges.md` for the `continue-on-error` rejection rather than restating it.
      **It must additionally record** (R18.11): the step-boundary collapse R17 named; that the
      "webhook alive after every apply" invariant now covers apply #1 only (R17.4); that the
      recovery **ships dark by construction** and cannot be exercised on demand (R18.4); why the
      re-push is inline rather than a function (R18.2); and R17.8's free win under
      `use_lockfile = false`. Implementation rationale goes in code comments beside the re-push.
- [ ] **9.3** ~~File the follow-up issues.~~ **[ALREADY DISCHARGED — R18.7.]** Verified open:
      **#7526** (the `server.tf`-in-paths-filter contradiction, R9.1) and **#7527**, whose body
      already carries both the R2 deferral and the missing `infra-config-channel-red` runbook.
      Nothing new is filed; tick with those two numbers as the evidence.
- [ ] **9.4** Move #7104 to the **Phase 4: Validate + Scale** milestone (number **4**; it is
      currently on **Post-MVP / Later**, number 6) — CPO condition C2.

## Phase 10 — Exit gate

- [ ] **10.1** `bash scripts/test-all.sh` green. **[Corrected — R18.8 §2]**
      ~~`run-registered-suites.sh` reports no new orphan~~ — `scripts/run-registered-suites.sh` does
      not exist (the real file is `apps/web-platform/infra/run-registered-suites.sh`, a different
      artifact). The orphan gate is **`scripts/lint-orphan-test-suites.sh`**, run as a registered
      suite by `test-all.sh`; it must report no new orphan. Also run
      `python3 scripts/lint-guard-contract.py` over the plan and
      `python3 scripts/lint-workflow-errexit-capture.py`.
- [ ] **10.2** `actionlint` clean on the workflow; extracted `run:` snippets checked with `bash -n`
      **on the extracted file** — never `bash -n` on the `.yml`, and never `bash -c`, which would
      *execute* the snippet and perform a production apply (R16.3).
- [ ] **10.3** Re-derive the ADR ordinal against freshly-fetched `origin/main` immediately before
      merge, and sweep the plan, this file and every AC if it changes.
- [ ] **10.4** Post-merge: confirm the `DPF_REPLACED == false` path — explicit `::notice::`, no
      re-push, green job. **[SATISFIED — R18.5.]** Evidence: GitHub Actions run **31714143720**
      (`workflow_dispatch` on `main`, 2026-08-13T15:12:19Z, conclusion `success`), which logs
      `DPF_REPLACED: false` at every step and emits
      `##[notice]No config push was expected on this run … VERIFIED: the frame is unchanged across
      this apply (start_ts=1786001951, identical to the pre-apply reading)`. **Do not re-dispatch.**
      The evidence transfers only under **AC20**: the diff must not touch the
      `DPF_REPLACED == "false"` branch of the freshness pin. Verify AC20, then tick.
- [ ] **10.5** **[Added — R18.4.]** The PR body carries `Closes #7104`. `ship`'s post-merge dispatch
      expects a **green no-op run on the `false` arm with zero `op=infra-config-repush-attempted`
      emissions** (AC14′) — a regression check on the arm PR-A shipped, **not** an exercise of the
      recovery path, which is not producible on demand.
