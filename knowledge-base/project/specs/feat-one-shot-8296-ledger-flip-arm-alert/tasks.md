# Tasks — flip the encryption-posture ledger and arm the wrong-volume alert (#8296)

Derived from
`knowledge-base/project/plans/2026-09-20-chore-flip-encryption-posture-ledger-and-arm-wrong-volume-alert-plan.md`
after plan review. **Two PRs.** PR-1 arms the detector; PR-2 publishes the record. PR-2 may not
start until AC-25 and AC-26 both hold — the record may lag the detector, never lead it.

## Phase 0 — Settle what the later phases assume (before any edit)

- [ ] 0.1 Read the Doppler override, single secret, read-only:
      `doppler secrets get INNGEST_LUKS_CUTOVER_COMPLETE -p soleur -c prd_terraform --plain --no-interactive`.
      Not found → the declared default governs. `true` → already armed; still make the edit, but do
      not use "plan shows 1 to change" as the criterion. Anything else → **stop**; resolving it is a
      gated Doppler write, not a step to take unasked.
- [ ] 0.2 Settle whether `paused` is ForceNew — **not** with `terraform providers schema -json`,
      which cannot express the answer (measured: `force_new`/`requires_replace` appear zero times in
      a well-formed 145 kB dump). Push the branch, open PR-1, and read the sticky comment from the
      `plan` job in `.github/workflows/infra-validation.yml` (pull_request-only, full-root, live
      state). Read it for the verb on `logtail_exploration_alert.inngest_luks_wrong_volume` and for
      any destroy/replace/create at an address in the apply's `-target` list.
- [ ] 0.3 Resolve which Better Stack credential `BETTERSTACK_API_TOKEN` is (Uptime vs Telemetry
      mgmt), and confirm the `.data[].attributes.paused` response shape, before AC-25's command is
      written. A 401 and a genuine pause are otherwise indistinguishable.

## Phase 1 — PR-1: arm the detector

- [ ] 1.1 `apps/web-platform/infra/variables.tf`: `default     = false` → `default     = true`
      (five spaces). Rewrite the comment above it: the inverting event, its evidence, the
      Doppler-override hazard. **Do not let `description` wrap to a second line; do not add a
      `validation {}` block** — either pushes `default` past `grep -A4` and silently kills AC-11.
- [ ] 1.2 `apps/web-platform/infra/betterstack-logs-alerts.tf`: comment-only — drop
      `terraform apply -var inngest_luks_cutover_complete=true  (or the tfvars entry)`. Leave
      `paused = !var.inngest_luks_cutover_complete` untouched.
- [ ] 1.3 `.github/workflows/apply-web-platform-infra.yml`: correct the `apply` job header comment
      that claims CODEOWNERS + branch protection is the gate. Measured false.

## Phase 2 — PR-1: move the guard with the world

- [ ] 2.1 Invert the default assertion to `default     = true`; prefer
      `grep -Eq 'default[[:space:]]+= true'` over the fixed-width `grep -qF`. Rewrite its `ok()`
      string — the current one states a rationale the cutover inverted.
- [ ] 2.2 Parameterise the mutator: `mutate_red <label> <target> <pristine> <python-prog>`; add
      `cp "$VARS" "$MUT_DIR/pristine.vars.tf"`; change `assert_fixture_dir "$TF"` to
      `assert_fixture_dir "$target"`; make both restore sites restore `$target`.
- [ ] 2.3 Fix the `trap`, which currently restores nothing and deletes the pristine copies. Take
      both copies **before** arming it. This is pre-existing, and extending the mutator to `$VARS`
      is what makes it dangerous — `variables.tf` is read by the apply on every push to main.
- [ ] 2.4 Add mutation rows 7 (default reverts to `false`) and 8 (`paused` becomes constant
      `false`). **Do not add a "lower the guard's own floor" row** — it cannot red this guard and
      would make it permanently red on the `mutation SURVIVED` arm.
- [ ] 2.5 Raise `_floor` 19 → 21. **Leave the `MUT_SKIP` floor at 13.** Raising it to 14 makes every
      inner run exit 1 on the FATAL floor check, so `mutate_red` reads RED for every row including
      vacuous ones and the outer run prints green over a dead battery.

## Phase 3 — PR-1: stop exempting this alert from drift reporting

- [ ] 3.1 `plugins/soleur/lib/heartbeat-live-reconcile.ts` — **thread the existing `vars` parameter;
      do NOT write a new `variables.tf` reader.** `parseInfraVariables` / `listTfFiles` /
      `resolveInfraVariablesPerFile` / `resolveInfraVariables` already exist in this file and already
      record boolean defaults as `{ kind: "bool", value: raw === "true" }`, and
      `discoverHeartbeatsFromInfra` / `discoverMonitorsFromInfra` already take
      `vars: InfraVariables = resolveInfraVariables(infraDir)`. Only `discoverLogsAlertsFromInfra`
      and `parseLogsAlertBlocks` lack it. Give them the same parameter, then resolve
      `paused = !var.<name>` through `vars.get(name)` when `kind === "bool"`. Fail **closed**: an
      unresolved or non-bool variable stays an expression (exempt). Match the name exactly, never by
      prefix.
- [ ] 3.2 `plugins/soleur/test/heartbeat-live-reconcile.test.ts` — the `inngest_luks_wrong_volume`
      fixture's expectation **inverts**: a live pause is now a reported `logs-alert-paused`. Add
      Guard 2's four mutation rows and two harness rows.

## Phase 4 — PR-1: apply, and read the property back

- [ ] 4.1 Merge PR-1 with `[skip-web-platform-apply]` in the merge commit.
- [ ] 4.2 Dispatch the apply as a per-command ack:
      `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='Arm logtail_exploration_alert.inngest_luks_wrong_volume after the 2026-09-20 Inngest Redis LUKS cutover (#8296)'`
- [ ] 4.3 Poll that run to a terminal conclusion with a stated bound (AC-26). `success` → 4.4.
      `failure`/`cancelled`/still-running-at-bound → the detector is not live; **PR-2 does not
      start**.
- [ ] 4.4 Read the live `paused` field back (AC-25) as two assertions — HTTP 200, then the payload.
      Non-200 is `CANNOT ESTABLISH`, never "paused". Paste the output into the PR body.

## Phase 5 — PR-2: the record (only once 4.3 and 4.4 hold)

- [ ] 5.1 `scripts/encryption-posture-ledger.json` — `hcloud_volume.inngest_redis_luks` →
      `mechanism: luks`; **delete its `exception` block**; rewrite `evidence` (one string, content
      anchors only), `defends_against`, `does_not_defend` (must name the retained backstop).
- [ ] 5.2 Same row: `live_verification` → `unavailable:<cipher half unobserved …>`. **Not** the bare
      literal `available`. `live_coverage_floor` stays `1`.
- [ ] 5.3 `hcloud_volume.inngest_redis` — keep `plaintext-exception`; rewrite as the retained
      backstop; `reassessed_on` → `2026-09-20`; add `INNGEST_LUKS_CUTOVER=rolled-back` to
      `reevaluate_when`. **Leave `expires_on: 2026-10-22` byte-untouched.**
- [ ] 5.4 `knowledge-base/legal/article-30-register.md` — dated in-cell amendments to PA-21 §(f),
      PA-22 §(f), PA-13 §(e), using the register's `**[2026-09-20 AMENDMENT (#8296): …]**` /
      `**[Superseded 2026-09-20 (#8296): …]**` bracket convention. Retain the "Two copies, bounded"
      fact and the EXPIRED clause verbatim. Say the alert went live **on the apply**.
- [ ] 5.5 `knowledge-base/engineering/architecture/diagrams/model.c4` — replace
      `platform.infra.inngestRedis`'s falsified description; drop the stale `format = "ext4"` /
      `ignore_changes = [format]` citation.
- [ ] 5.6 ADR-142 — **appended** amendment correcting apparatus-scope item 8 (it instructs flipping
      the wrong row). Additions only. ADR-218 — appended: "It ships PAUSED" is falsified.
- [ ] 5.7 `inngest-luks-cutover-6894.md` §5 steps 2 and 4; `betterstack-log-query.md` — the second
      carrier of the dead `-var` route.
- [ ] 5.8 `scripts/followthroughs/inngest-luks-cutover-6894.sh` — re-point its `NEXT` line at #8285
      and update its `RETIREMENT:` line, which names a sibling this PR deletes.
- [ ] 5.9 `scripts/cutover-inngest.sh` — add a `NEXT (not automatic):` line on the
      `op=luks-rollback` success path naming the ledger and the register. The rollback writes the
      world and makes no commit, so today nothing says the record went false.
- [ ] 5.10 Create `scripts/followthroughs/inngest-luks-property-8296.sh` + its `.test.sh`. It
      asserts the **property** (store's actual alias vs the ledger's claim), not "is the alert
      armed" — after a rollback the alert is unpaused and firing, so an arm-probe would PASS while
      the claim is false. Arms `0` / `1` / `3 CANNOT ESTABLISH`. Copy four structural elements from
      `scripts/followthroughs/registry-luks-live-8386.sh` rather than reinventing them:
      `set -uo pipefail` (**never `-euo`**); the `case "$-" in *x*)` xtrace-refusal exiting **78**
      when `BETTERSTACK_QUERY_PASSWORD` is set (#7797); `--limit "${SOLEUR_FT_LIMIT:-5000}"` on the
      query (**not optional** — the default reads only the newest ~8h20m); and the ledger read
      positioned **after** every measurement verdict. `RETIREMENT:` in the dominant colon-prose form,
      naming the `.test.sh` sibling, any `scripts/test-all.sh` `run_suite` line, and the #8285
      directive.
- [ ] 5.11 Delete `scripts/followthroughs/inngest-luks-staging-6894.sh` — it asks a staging-era
      question the cutover has settled, and until deleted it exits 1 on every sweep and posts a false
      regression comment on #6894. **Do not write "permanently falsified" in the PR body**: its PASS
      is driven by live host state through the durable `INNGEST_LUKS_ACTIVE_VOLUME_ID` pointer, which
      `op=luks-rollback` clears and any boot can re-arm, so it *could* exit 0 again. The reason is
      obsolescence, not impossibility.
- [ ] 5.12 Enroll the new probe on **#8285** (OPEN) with the `follow-through` label — never on
      #8296, which closes. The sweeper is a one-shot latch: exit 0 closes and is never re-litigated,
      closed mode reopens only on exit 1, and after 14 days the issue leaves the window entirely.

## Phase 6 — Verification

- [ ] 6.1 PR-1 ACs: AC-11 … AC-17, AC-25, AC-26, AC-34, AC-36.
- [ ] 6.2 PR-2 ACs: AC-1 … AC-10, AC-18 … AC-24, AC-27 … AC-33, AC-35, AC-37.
- [ ] 6.3 Unchanged-gate floors: 96/96, 57/57, 665/665, 160/160, 79/79.
- [ ] 6.4 `python3 scripts/lint-encryption-posture.py --repo-sweep`, `bash scripts/lint-encryption-posture.test.sh`,
      `bash plugins/soleur/test/c4-count-parity.test.sh`, and
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
      Note the first two and the alert drift guard are **advisory**, not required checks — run them
      locally and paste the output.
- [ ] 6.5 AC-P8: close #8296 only after PR-2 merges and AC-25/AC-26 hold. Both PR bodies say
      `Ref #8296`. Do **not** reference #7529 in either body (ship Phase 5.5 blocks on its missing
      Active Items row).

## Phase 7 — Deferrals

- [ ] 7.1 File D1, D3, D4, D5, D8, D9, D10, D11 per the plan's table, each with its measured
      evidence. D2 (move #8285 to Phase 4) and D6/D7 are operator/CLO actions.
