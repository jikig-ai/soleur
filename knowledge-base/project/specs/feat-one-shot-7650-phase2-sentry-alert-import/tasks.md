---
title: "Tasks — #7650 Phase 2: adopt 27 Sentry rules as sentry_alert"
plan: knowledge-base/project/plans/2026-08-25-fix-7650-sentry-issue-alert-to-alert-migration-plan.md
issue: 7650
branch: feat-one-shot-7650-phase2-sentry-alert-import
lane: cross-domain
date: 2026-09-04
updated: 2026-09-04
---

# Tasks — #7650 Phase 2

Derived from the plan. **These phases do NOT mirror the plan's section numbering** — they are an
execution order, and the plan is organised by concern. The mapping is given per phase below, so
"plan §3.3" never means "task 3.3".

Read first: the plan's `## Retractions and measurements — 2026-09-04` (seven premises were
wrong, three of them inside the plan's own acceptance criteria) and
[`phase2-v0157-frequency-trigger-landed-scope-is-27.md`](../fix-7650-sentry-alert-migration/phase2-v0157-frequency-trigger-landed-scope-is-27.md).

| Task phase | Plan section |
|---|---|
| 1 Measure & capture | Scope, Trap 2, Trap 3, §2.1 |
| 2 Guards | Guard Contract |
| 3 Author | §2.1 |
| 4 Script ownership | §2.2 |
| 5 Gate wiring | §2.3, §2.4, §2.6 |
| 6 Ongoing detection | §2.9 |
| 7 Recovery & forensics | §2.5 |
| 8 Sweep | §2.8 |
| 9 Architecture record | Architecture Decision, §2.7 |
| 10 Pre-merge verification | AC1-AC14 |
| 11 Post-merge verification | AC15-AC22 |
| 12 Cleanup (follow-up PR) | AC23 |

## Phase 1 — Measure and capture

- [x] **1.1** Re-run the scope derivation against live `workflows/`; assert exactly 27 rows. **AC1.**
- [x] **1.2** Re-run the comparison-shape measurement; assert zero bare-boolean
      `event_frequency_count`. A precondition on authoring, not a post-condition.
- [x] **1.3** Commit the live capture as
      `specs/fix-7650-sentry-alert-migration/phase2-live-workflows-capture-<date>.json`. It is the
      sole authoring source **and** the baseline for the Phase-6 probe and for AC19/AC20. **AC8.**
- [x] **1.4** Record the pre-change 25/4 `ignore_changes` split as a baseline (this is *not* AC6,
      which asserts the post-authoring state — see 3.6).
- [x] **1.5** Confirm `apply-sentry-infra.yml` pins Terraform `>= 1.7` (currently `1.10.5`, `:131`)
      and `.terraform.lock.hcl` pins provider `0.15.7`.
- [x] **1.6** Preflight the Sentry token's **`workflows/` write** scope. Reads are exercised by the
      capture and the imports; the first *write* happens on the first Update after adoption, and a
      missing scope would surface mid-apply in the half-applied state.
- [x] **1.7** Measure `plan_pr`'s runtime against a plan carrying 27 live import reads plus up to
      210 s of retry sleep. `timeout-minutes: 15` (`:211`) was never re-derived for this shape, and
      a timeout is a `failure` the aggregator fails closed with no brownout annotation.

## Phase 2 — Guards first (RED before GREEN)

Write each matrix **before** the guard. Three guards; two proposed guards are in the plan's Cut
List with reasons.

- [x] **2.1** `tests/scripts/test-sentry-alert-adoption-guards.sh` — **Guard A** (create
      protection, correctly scoped to `sentry_alert` creates too) and **Guard B** (the
      forget↔import bijection), with harness rows.
- [x] **2.2** Wire Guard A into **both** `plan_pr` and `apply`, on the plan artifact, with the
      apply gated on its exit. Rows 8-10 exist because one invocation would otherwise satisfy the
      whole matrix while reproducing the asymmetry the guard closes.
- [x] **2.3** **Guard C** — `resource_forgets` in `destroy-guard-filter-sentry.jq`, summed into
      `destroy_count`. A counter that reports but does not feed the sum is a report, not a gate.
- [x] **2.4** **Register the new suite in `scripts/test-all.sh`.** Nothing under `tests/scripts/`
      is auto-discovered — every sibling is hand-registered (`:1043-1082`, `:1446-1459`). An
      unregistered suite is an orphan that reads as green. **AC12.**
- [x] **2.5** Run every matrix; confirm each RED row reds and each must-PASS row passes. **AC12.**

## Phase 3 — Author the 27

- [x] **3.1** Add `data "sentry_project_issue_stream_monitor" "web_platform"`.
- [x] **3.2** Author 27 `resource "sentry_alert"` blocks **from the 1.3 capture only**: `name`
      byte-for-byte; `frequency_minutes` per rule; per-rule `action_filters[].logic_type` (4 of 27
      are `any-short`); `match` lowercase `eq`/`in`; `target_type = "issue_owners"`;
      `fallthrough_type` (`NoOne` for `byok_cap_exceeded` alone); `ignore_changes = [environment]`
      and nothing else; no `project` attribute.
- [x] **3.3** Add the inline comment at the `trigger_conditions` site recording the provider's
      hardcoded `any-short` — the replacement for the lint that would have shipped pre-suppressed
      on 13 of 27 blocks.
- [x] **3.4** Delete the 27 corresponding `sentry_issue_alert` blocks in the same commit — a
      `removed{}` naming an address that still has a resource block is a config error. Keep
      `auth_per_user_loop` and `sandbox_startup_failure`.
- [x] **3.5** Add 27 `removed { from = sentry_issue_alert.<n>  lifecycle { destroy = false } }`
      and 27 `import { to = sentry_alert.<n>  id = "<org>/<workflow id>" }`.
- [x] **3.6** Per-block assertions with a walker anchored on `/^resource "sentry_alert"/` — **not**
      the Trap-3 walker, which is anchored on `sentry_issue_alert` and returns nothing here:
      `[environment]` for all 27 (**AC6**), and zero `IssueOwners`/`"EQUAL"`/`"IS_IN"` *within
      those blocks* (**AC7**). A file-level grep fails on a correct migration — 49 and 50
      occurrences legitimately remain, five of them in the two survivors.
- [x] **3.7** `terraform validate`, **plus a deliberately conflicting fixture** that must fail —
      without the negative arm this is a syntax check, not an `ExactlyOneOf` check.

## Phase 4 — Retire the script's ownership of the three

- [x] **4.1** Read
      [`2026-08-19-i-proposed-deleting-a-control-because-terraform-appeared-to-own-it.md`](../../learnings/2026-08-19-i-proposed-deleting-a-control-because-terraform-appeared-to-own-it.md)
      **before cutting anything.**
- [x] **4.2** Delete **only** the three burst stanzas (`:151-154`, `:157-160`, `:175-178`). Keep
      `auth-per-user-loop` (`:165-168`); the script is **not** deleted. **AC13.**
- [x] **4.3** Rewrite the header enumeration (`:5-9`), which lists four rules.
- [x] **4.4** Fix the docstring at `apps/web-platform/test/auth/sentry-tag-coverage.test.ts:8` and
      confirm the test still passes.
- [x] **4.5** Update the ownership table in the 2026-08-19 learning; post the split to #4781.

## Phase 5 — Gate wiring

- [x] **5.1** **AC10 — the apply-side `0 to change`.** Add the same plan-JSON assertion as AC2 to
      the `apply` job against `/tmp/sentry-apply-plan.json`, **before** `terraform apply`, not
      `[ack-destroy]`-reachable. The apply **re-plans**, and its only gate is `destroy_count`,
      which the blanket ack greens by design. This is the largest hole the review round found.
- [x] **5.2** **AC11 — monitor-id equality.** Assert the resolved
      `data.sentry_project_issue_stream_monitor.web_platform.id` equals the captured `1213799`, in
      **both** jobs. A correlated rebind plans 27 updates with all four counters at 0.
- [x] **5.3** Widen the destroy gate's **address-display** jq (`:419`) to
      `index("delete") or index("forget")`. Per R6 it currently selects `["delete"]` only, so it
      prints an empty list while claiming N destructive changes. `resource_deletes` itself stays
      `delete`-only — AC4's discrimination depends on it.
- [x] **5.4** Update the destroy-gate operator message (`:809`), which itemizes two terms and would
      understate its own verdict once `destroy_count` has three.
- [x] **5.5** Sweep the counter consumers: `scripts/sentry-destroy-counts.sh` (`:55` validation,
      `:66` sum); `tests/scripts/test-destroy-guard-counter-sentry.sh` **whole-object literals at
      `:174`/`:191`** → per-field assertions, and its `_run_gate` hand-rolled
      `dcount=$((rdel + ndel))`; `tests/scripts/test-sentry-destroy-counts.sh` T3 (`:71`).
- [x] **5.6** Add `sentry_alert` fixtures to `tests/scripts/test-sentry-create-gate.sh` — the one
      guard suite in scope with no case for the new type.
- [x] **5.7** Add the `if: failure()` issue-open step to the `apply` job. The apply arm of the
      duplicate-creation mode has no operator route today.
- [x] **5.8** **AC9** — confirm the brownout retry blocks are byte-unchanged in both jobs. This PR
      edits that file in both, and §3.3 makes the retry the mitigation for the two survivors.

## Phase 6 — Ongoing detection (§2.9)

- [x] **6.1** `scripts/sentry-alert-live-fidelity.sh` — one read-only `GET …/workflows/`, diffed
      against the committed capture. Detects deletion, `enabled:false`, name drift, changed
      `comparison.{value,interval}`, changed `tagged_event`, `logicType` flip, `monitor_ids`
      unbind — for all 27, not the 4 in `EXPECTED_RULES`.
- [x] **6.2** `.github/workflows/scheduled-sentry-alert-drift.yml` — schedule it per ADR-033
      (Inngest cron → `workflow_dispatch`), opening/updating an issue on drift. **AC22.**
      **Do not** add the Sentry root to `scheduled-terraform-drift.yml`'s matrix instead: that leg
      would plan the full root, still refreshing the two survivors through the deprecated
      endpoint, with none of the brownout retry.
- [x] **6.3** Wire the same script as a post-apply step in `apply-sentry-infra.yml` — it needs the
      three secrets already present at `:830-834`. **AC19/AC20.**

## Phase 7 — Recovery and forensics (§2.5)

- [x] **7.1** Capture `terraform state pull` as a workflow artifact **before and after** the apply,
      with an explicit short retention. Labelled **forensics**, not rollback.
- [x] **7.2** Add the Encryption Posture row for that artifact — it is a new egress surface
      carrying the whole root's state, readable by anyone with repo read.
- [x] **7.3** Probe R2 `list-object-versions`; if unsupported, file the issue that
      `infra/github/README.md` §"Phase 5 — Rollback" documents a capability that does not exist for
      **every** root on that bucket. Named owner, not a PR-body line.
- [ ] **7.4** Put the recovery gesture in the PR body: **re-run the failed job on the original
      run** is the only one that works — `workflow_dispatch` has no `head_commit.message` so it
      cannot carry the ack, and the push trigger is path-filtered so an ack-only commit does not
      retrigger. **Revert and state-restore are both traps** (§2.5). **AC14.**

## Phase 8 — Sweep (§2.8)

- [x] **8.1** `assert-byok-rules-exist.sh:33-43` — auth-\* set **four → one**. Keep the
      distinction, the warning and the per-resource-block instruction. **Do not weaken it**; this
      PR *inverts* the paragraph, and the file records having been "briefly 'corrected' into a
      falsehood on 2026-08-19 before being restored".
- [x] **8.2** `scripts/followthroughs/sentry-brownout-frequency-7650.sh` — the `25 + 4` FAIL
      message → 27 + 2; **read the `conclusion` it already fetches** (a failed apply currently
      yields `exhausted=0` → exit 0 → the sweeper posts PASS); bound the window on `createdAt`.
- [x] **8.3** `apps/web-platform/infra/sentry/README.md` — the adopted state and the mechanism.
- [x] **8.4** `tests/scripts/test-destroy-guard-sentry-scope-guard.sh:3-16` — four types covered.
- [x] **8.5** `apps/web-platform/scripts/sentry-monitors-audit.sh:1312` — a code-comment nit, not a
      compliance item (comments in the `{ … } > "$out_file"` block are not emitted).
- [x] **8.6** Verify the v0.15.5 spec's dated supersede banner survived (done at plan time).
      **`versions.tf` is deliberately NOT edited** — a second drift-capable record of a fact the
      ADR holds.

## Phase 9 — Architecture record

- [x] **9.1** ADR-031 `**Amendment (2026-09-04, #7650)**`: the deferral executed for 27 of 29; the
      ownership-model change and the AP-001 deviation shrunk 4→1; **`forget` entering the destroy
      gate's vocabulary and `destroy_count` gaining a third term**; the hardcoded `any-short` as a
      standing constraint; and the `auth-per-user-loop` residue.
- [x] **9.2** Consider a short standalone ADR for the *mechanism* — config-block adoption,
      including the "blocks stay in config until verification passes" sequencing. The repo now has
      two competing adoption patterns with nothing adjudicating between them.
- [x] **9.3** Correct `model.c4:619` (`actions_v2` → `action_filters[].actions[].email`, 28-of-29 →
      27-of-29). **Preserve** the `byok_cap_exceeded`/`NoOne` carve-out and the 30th-rule paragraph
      verbatim.
- [x] **9.4** Run `c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [x] **9.5** Re-narrow #7634 to `auth-per-user-loop` and record the residue: once `rules/` is
      retired, that rule is unwritable by any available mechanism.

## Phase 10 — Pre-merge verification

- [x] **10.1** **AC2** on the PR plan JSON: zero non-`no-op`/non-`forget` rows; 27 `["forget"]`;
      27 `.change.importing.id` (**note the path**); ids match the capture. The summary line
      (`Plan: 27 to import, 0 to add, 0 to change, 0 to destroy.` — **note the `to import`
      clause**) is corroboration, not the assertion.
- [x] **10.2** **AC3** — the bijection, membership not cardinality.
- [x] **10.3** **AC4** — `sentry-squash-ack-detect.sh` exits 0 on the branch commits (the
      *predictor*, which is what is checkable pre-merge), and the counters read
      `deletes=0 / creates=0 / forgets=27`.
- [x] **10.4** **AC5** — assert the merge method is **squash**. A merge-commit merge yields a body
      with no ack and reds the apply after `main` has already taken the config.
      **Verified 2026-09-04, and the result carries a caveat.** `squash_merge_commit_message`
      is `COMMIT_MESSAGES`, so the AC4 predictor's squash-body emulation is VALID and its
      green verdict means what it says. But the repo also has `allow_merge_commit: true` and
      `allow_rebase_merge: true`, so a merge-commit merge is *possible* — nothing mechanically
      prevents it. The guarantee here is procedural: merge with `--squash`. The PR body states
      it in bold. Closing this repo-wide would disable merge commits for every PR and is out
      of scope.
- [x] **10.5** Pre-stage `[ack-destroy]` on its own line in a commit **BODY** (never a subject).
- [x] **10.6** **AC11** — the monitor-id equality check is green in `plan_pr`.
- [~] **10.7** `scripts/test-all.sh` green, including the newly-registered suite and the four
      touched guard suites. Run each suite's own invocation, not a reconstruction of its inputs.
      **PARTIAL — 21 suites run individually, green; the full gate was not completed locally.**
      The pre-commit full gate blocked on `flock` behind a sibling worktree's gate for 63
      minutes without executing a single suite (that sibling held the lock for 111 min). The
      prior completed full gate on this branch reported 351/361 with 7 failures; all seven are
      now fixed or confirmed environmental (`memory-backstop` passes standalone at 54/54 and
      this diff touches nothing under `.claude/`). Each affected suite was run via its own
      invocation, not a reconstruction. **CI runs the authoritative gate on the PR — that is
      the run this AC should be closed against, not a local one.**
- [x] **10.8** **AC14** — the PR body carries: the re-run recovery gesture; revert is forbidden; a
      clean plan is not evidence the deprecation lifted; two resources still read the deprecated
      path; and the brownout-deadlock case.
- [ ] **10.9** Full review panel — authorised and **required** before ship.

## Phase 11 — Post-merge verification

- [ ] **11.1** **AC15** — full-root plan `0 to add, 0 to change, 0 to destroy`, no 410s, all four
      types.
- [ ] **11.2** **AC16** — all four counters zero; type-scope guard passes with
      `SENTRY_STATE_TYPES` from the plan's own types.
- [ ] **11.3** **AC17** — `terraform state list` shows 27 `sentry_alert.` and 2
      `sentry_issue_alert.`, **no orphan**. This is what fails loudly on a partial apply rather
      than deferring it to the next unrelated push.
- [ ] **11.4** **AC18** — `legacy_trigger_conditions` empty for all 27 in state.
- [ ] **11.5** **AC19** — the §2.9 probe: all 27 match the committed capture.
- [ ] **11.6** **AC20** — `byok-art-33-breach` field-by-field against the capture.
- [ ] **11.7** **AC21** — `assert-byok-rules-exist.sh`, all four `EXPECTED_RULES`, ENABLED.
- [ ] **11.8** **AC22** — the scheduled probe is live and opens an issue on divergence.
- [ ] **11.9** Confirm the follow-through directive is on the tracking issue:
      `<!-- soleur:followthrough script=scripts/followthroughs/sentry-brownout-frequency-7650.sh earliest=<merge+7d> secrets=GH_TOKEN -->`

## Phase 12 — Cleanup (follow-up PR)

- [x] **12.1** Filed as #7826 (2026-09-04). File the tracking issue **now**, at deferral time, per
      `wg-when-deferring-a-capability-create-a` — not as the last task of the deferred work.
- [ ] **12.2** **AC23 — hard precondition.** Before removing the 27 `import{}` and 27 `removed{}`
      blocks: `terraform state list | grep -c '^sentry_alert\.'` on `main` is **27**, and
      AC15-AC22 have passed **on main**. If a partial apply left any address un-imported, removing
      its `import{}` turns it into a planned **create** of a live-colliding rule.
- [ ] **12.3** Remove the blocks. A stale `import{}` on an already-managed address is a silent
      no-op (measured) but a foot-gun for the next author.
