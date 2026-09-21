---
title: "PR-2 of #8296: flip the Inngest LUKS ledger row and bring the records up to date"
date: 2026-09-21
slug: chore-8296-pr2-flip-inngest-luks-ledger-record
branch: feat-one-shot-8296-pr2-ledger-flip
issue: 8296
# Deliberately NOT `closes:`, as the parent plan dictates for both PRs: the body says `Ref #8296`,
# and #8296 is closed by `gh issue close 8296` after this PR merges (parent AC-P8).
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_plan: knowledge-base/project/plans/2026-09-20-chore-flip-encryption-posture-ledger-and-arm-wrong-volume-alert-plan.md
draft_pr: 8514
---

## Enhancement Summary

**Deepened on:** 2026-09-21. **Before deepen**, a 7-seat plan-review panel ran (DHH, Kieran,
code-simplicity, architecture-strategist, spec-flow-analyzer, CTO, CPO) plus a strong-model advisor
consult. Their changes are listed in `## Plan Review Revisions`. **Deepen passes:**
verify-the-negative (7/7 claims confirmed, including a scratch-ledger dry-run of the `luks` flip →
`0 failing checks -> PASS`), precedent research, test-design review (Farley, planned-suite score
6.5/10 before fixes), and institutional learnings.

### Key improvements

1. **The property probe cannot close #8285, and this is structural rather than a convention.**
   Notify-only exits, an EXIT trap that remaps 0/1 to 3, a final `exit 3`, and an allowlist scan.
   It adopts the `inngest-soak-6178.sh` trap precedent and the `assert_never_close_verb` helper.
2. **The expiry arm can no longer tell anyone to destroy the live store.** `backstop_expired` fires
   only in the encrypted-and-agreeing state, and a must-PASS case pins the reverted-past-expiry
   state to `2`.
3. **The suite is repeatable.** It uses an injected clock `SOLEUR_FT_NOW`, and fixtures sit well
   away from the edges, so the suite does not flip verdicts on 2026-10-22.
4. **The code-editing mutations are committed.** Rows 5 and 7–10 run in the suite against scratch
   copies, instead of being hand-run and pasted into the PR body.
5. **The rollback NEXT line is guarded explicitly.** The success notice it attaches to is shared
   with `luks-cutover`.

### New considerations discovered

- The sweeper posts a comment on every non-0/1 verdict with no dedup
  (`2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md`), and names the
  sweeper as the wrong vehicle for **indefinite** watches. This watch is **bounded**: it ends when
  #8285 closes, targeted for 2026-10-22. D12 records the escalation and dedup question. DC-1 and
  DC-2 remain open for the operator.
- A PR-body sentence like "the sweeper closes #8285" would itself auto-close #8285 on squash-merge
  (AC-39b).
- One learnings-agent suggestion was **rejected**: restoring `0 PASS / 1 FAIL` arms. That
  reintroduces the R1 defect.

## Overview

This is **PR-2 of #8296**, and only PR-2: tasks.md Phase 5 (items 5.1–5.12) of the parent plan
`knowledge-base/project/plans/2026-09-20-chore-flip-encryption-posture-ledger-and-arm-wrong-volume-alert-plan.md`
(its `## Implementation Phases` → `### Phase 5 — PR-2: the record, only once the detector is live`,
and its `## Acceptance Criteria` → `### PR-2 — the record`). **The parent plan is the source of
truth.** This file does not re-derive what it settled. It records three things:

1. the gate that let PR-2 start, re-verified read-only;
2. the three facts the operator asked to have measured before any edit: (a) the baked-carrier
   status of `scripts/cutover-inngest.sh`, (b) whether any PR-2 path is under
   `apps/web-platform/infra/**`, (c) which workflows run when PR-2 is pushed to `main`;
3. **the places where the parent plan went stale between 2026-09-20 and today**, and one design
   defect in its Guard 3 enrollment that would have auto-closed the backstop-retirement tracker.

PR-2 is the **record** half: the ledger flip for `hcloud_volume.inngest_redis_luks`, a rewrite of
the `hcloud_volume.inngest_redis` row as a retained backstop, the five records that describe the
world before the cutover, a property probe that watches the claim, and the deletion of a probe that
is now obsolete. **It fires no production apply and mutates nothing in production at merge**
(measured below). Every production-adjacent step is listed at the end as a post-merge step.
**The operator is asked before merging. No auto-merge.**

`lane:` is `cross-domain` because it is carried from the parent plan (TR2 fail-closed; no `spec.md`
exists for this branch).

## Research Insights

### Gate re-verification (read-only, 2026-09-21)

| Gate fact (parent AC-25 / AC-26) | Command | Measured |
| --- | --- | --- |
| PR-1 merged | `git merge-base --is-ancestor b53173a04 origin/main` | exit 0. `b53173a04` = "feat(8296): arm the Inngest wrong-volume alert (PR-1 of 2) (#8439)" |
| The arming apply succeeded | `gh run view 35605929787 --json conclusion,status,event,headSha` | `completed/success`, `event=push`, `headSha=b53173a04…` |
| The alert is live and unpaused | `gh api repos/jikig-ai/soleur/issues/comments/5762001007` | Comment by `deruelle` at 2026-09-21T14:19:27Z: alert `soleur-inngest-luks-wrong-volume-prd`, id `2988582970`, `paused=false`, `paused_reason=null` at 2026-09-21T14:18:56Z (it read `true` / `Manually paused` at 13:30:39Z, before the apply) |

**Premise validation.** `#8296` OPEN. `#8285` OPEN (the backstop retirement, milestone
"Post-MVP / Later", labels `priority/p2-medium,type/chore,domain/engineering`, **no `follow-through`
label and no directive**). `#6894` OPEN. `#8294` and `#8295` CLOSED 2026-09-20T16:19Z. `#8451` and
`#8453` OPEN: this PR does not touch `.github/workflows/apply-sentry-infra.yml` or `infra/sentry/`,
because #8453 owns those files. Draft PR `#8514` OPEN. `origin/main` = `45ebe7961`.

**One side note on the gate.** The arming apply was the **push** apply
(`event=push`). It was not the `manual-rerun` dispatch the parent's Phase 4 prescribed. It applied
`1 added, 2 changed`. Two of those actions were drift from earlier PRs
(`cloudflare_bot_management.soleur_ai`,
`github_repository_environment_deployment_policy.web_platform_infra_apply_main`). That already
happened and PR-2 changes nothing about it. It is the practical reason PR-2 must stay off
`apps/web-platform/infra/**`: any push there applies the **whole** drifted allowlist, not just the
lines in the diff.

### The three measured facts the operator asked for

**(a) `scripts/cutover-inngest.sh` is NOT a baked carrier.** "Baked carrier" is defined in code by
Guard A of `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` (the
`GuardA: every baked carrier is byte-identical at $GA_TAG_REF` assertion; ADR-199 §"compares every
baked carrier against `git show <pinned tag>`"). The set is derived from
`.github/workflows/build-inngest-bootstrap-image.yml`: its `cp apps/web-platform/infra/<f>` staging
lines, cross-checked against its `COPY` lines. The build workflow triggers **only** on
`push: tags: vinngest-v*.*.*` and on dispatch. The baked-carrier tag rule follows from that: if you
edit a carrier, you mint a new `vinngest-v*` tag and re-pin `cloud-init-inngest.yml`.

```
grep -oE '^[[:space:]]*cp apps/web-platform/infra/[A-Za-z0-9._-]+ ' .github/workflows/build-inngest-bootstrap-image.yml | awk '{print $2}' | sort -u
→ 13 paths, ALL under apps/web-platform/infra/:
  cat-inngest-cutover-state.sh inngest-bootstrap.sh inngest-cutover-flip.{service,sh,timer}
  inngest-luks-cutover.{service,sh,timer} inngest-redis-bootstrap.sh inngest-redis.conf
  inngest-redis.service inngest-server-flip-guard.sh vector.toml
grep -c 'cutover-inngest' .github/workflows/build-inngest-bootstrap-image.yml → 0
```

`scripts/cutover-inngest.sh` runs **on the GitHub runner**, from the checkout of the
`cutover-inngest.yml` `workflow_dispatch`. It is never copied into the image. **No PR-2 file is a
baked carrier**, so no `vinngest-*` tag push and no re-pin are needed, and Guard A cannot redden.

**(b) No PR-2 path is under `apps/web-platform/infra/**`.** See `## Files to Edit` below. Every
path is under `scripts/`, `knowledge-base/`, or is the planning artifacts. **One parent AC would
have broken this: AC-33.** Its "carry the dead-probe issue number inside the alert's own resource
block" limb edits `apps/web-platform/infra/betterstack-logs-alerts.tf`. That would fire the push
apply over the whole drifted allowlist for a comment-only change. It is re-scoped below (see
`## Research Reconciliation`, row R4).

**(c) Merging PR-2 mutates nothing in production. Measured by parsing every
`.github/workflows/*.yml` `on.push` filter against PR-2's exact file set.** The script was
`push_wf.py` in the session scratchpad. It applies GitHub glob semantics, including `!` negation.

| Workflow | Fires on PR-2's push? | Why | Mutates production? |
| --- | --- | --- | --- |
| `apply-web-platform-infra.yml` | **no** | `paths: apps/web-platform/infra/**` (minus two), its own file, `tests/scripts/lib/destroy-guard-filter-web-platform.jq` | — |
| `apply-deploy-pipeline-fix.yml`, `apply-github-infra.yml`, `apply-inngest-rls.yml`, `apply-sentry-infra.yml` | **no** | path filters name none of PR-2's files | — |
| `infra-validation.yml` | **no** | `apps/*/infra/**`, `infra/**`, `apps/web-platform/test/infra/**`, its own file | — |
| `cutover-inngest.yml` | **no** | push filter is only `.github/workflows/cutover-inngest.yml`. **Editing `scripts/cutover-inngest.sh` does not fire it** | — |
| `build-inngest-bootstrap-image.yml` | **no** | tag-only (`vinngest-v*.*.*`) | — |
| `deploy-docs.yml`, `version-bump-and-release.yml`, `web-platform-release.yml` (push arm), `deploy-inngest-image.yml`, `restart-inngest-server.yml`, `inngest-watchdog-restart-dispatch.yml`, `registry-*`, `validate-vector-config.yml` | **no** | path filters exclude `scripts/**` and `knowledge-base/**` | — |
| `ci.yml`, `secret-scan.yml`, `skill-security-scan-corpus.yml`, `skill-security-scan-postmerge.yml`, `tenant-integration.yml`, `vendor-pin-verify.yml` | **yes** (no path filter) | unfiltered `push: branches: [main]` | **no.** Tests and scans. `skill-security-scan-postmerge` can file a GitHub issue, and PR-2 touches no skill. `tenant-integration` and `vendor-pin-verify` gate their real jobs on a `detect-changes` output that PR-2's paths do not set |
| `web-platform-release.yml` (`workflow_run` on CI completed, main) | **yes** (chained) | runs after CI | **no.** `resolve-target` finds no Web Platform Release run for the SHA (its `on.push.paths` declined), so it reaches `clean_skip … "no_release_run"`. `migrate` and `deploy` are skipped. `verify-doppler-secrets` runs `doppler run -c prd -- bash apps/web-platform/scripts/verify-required-secrets.sh`, which only reads |
| `post-merge-monitor.yml` (`workflow_run` on CI completed, main) | **yes** (chained) | runs after CI | **no production effect.** Acts on the GitHub repo only when CI **failed** |

**Conclusion, measured: merging PR-2 alone triggers no terraform apply, no deploy, no image build
and no Doppler write.** The PR body states this. The merge needs no `[skip-web-platform-apply]`
token, because the apply's path filter is never matched.

### Property List (Phase 0.6b) — inherited, unchanged

The parent's P1–P5 (`## Research Insights` → `### Property List`). PR-2 buys **P1** (the flip),
**P2** (the backstop row), **P4** (the five records) and the rollback limb of **P5** (the property
probe). P3 was bought by PR-1.

### Cut List (Phase 0.6b) — inherited, plus two PR-2 cuts

The parent's Cut List stands (no line-number gate; no `available` flip; no bespoke arm-probe;
`paused` stays an expression). PR-2 adds two cuts:

- **CUT — the in-block issue citation in `betterstack-logs-alerts.tf` (parent AC-33, second
  limb).** The property it buys is "the dead-probe gap is on the record". It is bought just as well
  by an OPEN issue cited in the probe header, the ledger row and the runbook. Buying it inside the
  `.tf` fires a production apply over unrelated drift. Moved to the D1 issue's own first task.
- **CUT — a "0 = PASS" arm in the property probe.** See R1. On #8285 a PASS closes the tracker the
  probe exists to keep watching. Replaced by the notify-only vocabulary, which is already
  registered and already has a precedent.

### Relevant files and precedents (measured today)

- `scripts/followthroughs/registry-luks-live-8386.sh` is the shape authority for **three idioms
  only**: `set -uo pipefail` (line 110), the `case "$-" in` xtrace refusal with `exit 78`
  (lines 116–120), and `LIMIT="${SOLEUR_FT_LIMIT:-5000}"` (line 174). It also contributes a
  per-branch marker idiom and a staleness arm ("newest row older than 30 min -> 3
  producer_silent"). **It is NOT notify-only**, which corrects this plan's first draft (Kieran P1):
  it has `exit 1` FAIL arms at lines 504 and 611. Do not copy its exit set. It is registered via
  `run_suite "scripts/registry-luks-live-8386" …` in `scripts/test-all.sh`, and
  `scripts/lint-orphan-test-suites.sh` enforces that registration.
- **Notify-only vocabulary precedents**, measured by `grep -oE '\bexit [0-9]+'`:
  - `ccla-representative-icla-7922.sh` is the convention's named "first use". Its exits are 0×1,
    2×2, 5×1 and 64×1, and its last line is `exit 2`.
  - `questionnaire-unanswered-8289.sh`: exits 1, 2, 3, 5 and 64, last line `exit 2`.

  **Neither is purely never-0/never-1.** This probe is stricter than every precedent, because it
  is enrolled on a tracker that must not close. That strictness is enforced by Guard 3, not
  inherited from them.
- The emitter (`apps/web-platform/infra/inngest-bootstrap.sh`) writes `data_mount_src=n/a` (line
  653) or `__UNREADABLE__` (line 673) when it cannot read the mount. The probe row carries
  `data_mount_src=… data_bytes=… data_mount_base=… data_mount_devid=…` (line 1192), so
  `data_mount_src` is never the last field and a trailing-space match on it is sound.
- `scripts/betterstack-query.sh`: `LIMIT` takes the **newest** rows (inner `ORDER BY dt DESC`).
  Output is re-sorted ascending (outer `ORDER BY dt ASC`), so the newest row is the **last** line.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`, the paragraph
  beginning "A registered sub-vocabulary inside the TRANSIENT bucket, for NOTIFY-ONLY probes": codes
  2 = NOT YET, 3 = CANNOT ESTABLISH, 5 = ACTION REQUIRED. It says "A notify-only probe should say so
  in its header and assert the never-0/never-1 invariant in its own suite".
- `scripts/sweep-followthroughs.sh`: exit 0 → comment PASS **and `gh issue close`**. Exit 1 → FAIL
  comment. 2/3/5 → a mapped heading plus "Leaving the issue open". A missing script logs `ERROR …
  missing in repo HEAD — leaving issue open`, returns 0 and does not fail the run. The closed-set
  path re-verifies any issue closed in the last `CLOSED_LOOKBACK_DAYS=14` that has no
  sweeper-authored PASS comment, and **exit 1 reopens it**.
- `scripts/followthroughs/inngest-luks-cutover-6894.sh` is the existing discriminator:
  `data_mount_src=/dev/mapper/inngest-redis ` **with a trailing space**, so it cannot
  prefix-match `inngest-redis-plain` (the plaintext row's `device_binding.mapper`).
- Its generated companion `knowledge-base/engineering/architecture/diagrams/model.likec4.json` must
  be regenerated after any `model.c4` edit: `bash scripts/regenerate-c4-model.sh`. The
  `c4-model-freshness.test.sh` gate in `ci.yml` byte-diffs a fresh render against the committed
  file. **The parent plan does not mention this.**

### Institutional learnings carried forward

All of the parent's (`## Research Insights` → `### Institutional learnings that bind this
change`). The one that decides R1 is
`2026-07-24-holding-a-live-overclaim-pending-infra-teardown-and-drain-can-mean-keep-open.md`:
a retained plaintext residual keeps its umbrella issue OPEN. A probe whose PASS closes that issue
defeats it.

### Measured baselines before any edit (2026-09-21)

| Gate | Result |
| --- | --- |
| `python3 scripts/lint-encryption-posture.py --repo-sweep` | `19 stores, 6 connections, 0 unledgered, 0 failing checks -> PASS` (0.7 s) |
| `jq '.live_coverage_floor'` | **`2`** (the parent says 1; see R2) |
| `jq '[.stores[]\|select(.at_rest.live_verification=="available")\|.store]'` | `hcloud_volume.registry`, `hcloud_volume.workspaces_luks` |
| `grep -c -E '(inngest-host\|inngest-redis-luks)\.tf:[0-9]'` on the ledger | `0` |
| Register: `This cell asserts no encryption until that flip is made` / `the apparatus is still inert until a reviewer-gated dispatch runs (#8295)` / `TWO copies of the same AOF exist concurrently` / `reads as EXPIRED if that date passes with the backstop attached` / `[2026-09-20 AMENDMENT (#8296)` / `[Superseded 2026-09-20 (#8296)` | `2` / `1` / `2` / `2` / `0` / `0` |
| `model.c4`: `AT REST: STILL PLAINTEXT ext4` / `AT REST IS STILL PLAINTEXT AS OF THIS EDIT` / `ignore_changes = [format]` | `1` / `1` / `1` |
| `bash plugins/soleur/test/c4-count-parity.test.sh` | `ALL TESTS PASSED` |
| `grep -c 'apply_target=main'` in `inngest-luks-cutover-6894.md` | `1`, and it is **inside** PR-1's `CORRECTED 2026-09-20 (#8296)` paragraph ("Both halves were wrong") |
| `grep -c 'inngest_luks_cutover_complete=true'` in `betterstack-log-query.md` | `1` (line 47: "**Ships PAUSED** and is armed by `-var inngest_luks_cutover_complete=true`") |
| ADR-142: `apparatus scope item 8` / `hcloud_volume.inngest_redis_luks` | `0` / `2`. Item 8 (line 130) still reads "flip `hcloud_volume.inngest_redis` `mechanism` → `luks`" |
| ADR-218: `It ships PAUSED` | Present (line 234). PR-1's amendment says it "is falsified by PR-2 of #8296 … which carries its own amendment" |

## Research Reconciliation — Parent Plan vs. Today's Tree

| # | Parent plan claim | Measured reality (2026-09-21) | PR-2 response |
| --- | --- | --- | --- |
| **R1** | Guard 3's arms are `0 PASS` / `1 FAIL` / `3 CANNOT ESTABLISH`, enrolled on **#8285** "which stays open until the backstop is destroyed". | `sweep-followthroughs.sh` **closes** the issue on exit 0. The first healthy sweep after `earliest` would close #8285 while the plaintext backstop is still attached. That is the same one-shot-latch failure the parent cited as its reason for not enrolling on #8296. Its Risks entry reads "The sweeper is a one-shot latch, not a monitor". | **The probe is NOTIFY-ONLY: never 0, never 1.** Healthy agreement → `2`: the heading reads "NOT YET" and the output reads "healthy: nothing to do; this probe never closes #8285". Claim and world disagree → `5` (ACTION REQUIRED). Cannot measure → `3`. Xtrace refusal → `78`. This uses the registered vocabulary (`followthrough-convention.md`). It is stricter than every precedent, and Guard 3 enforces that. **Cost, accepted:** one sweeper comment per day on #8285 until #8285 closes, not until the expiry date. That is about 30 per 30 days, open-ended if the destroy slips. Leaving the tracker open is the property, and the comments are its price. A later `earliest` is recorded as a taste challenge (DC-2). **Coverage ends when #8285 closes.** In closed mode the sweeper does nothing for exits 2, 3 and 5, and after 14 days it stops running the probe. That is acceptable only because a destroyed backstop leaves no plaintext volume to roll back to. So **#8285 must not be closed before the backstop is destroyed**. Post-merge step 1 writes that into #8285's body. |
| **R2** | `live_coverage_floor` "stays `1`"; AC-6 expects floor `1` and one `available` row; `hcloud_volume.registry` "is held at `unavailable:`". | Floor is **`2`**. `hcloud_volume.registry` went `available` in #8423 (`181730800`), on its `store_luks` probe field. | AC-6 is re-baselined: the floor **stays 2** and the `available` count **stays 2**. The flipped row still does not take `available`: nothing about the cipher-half gap changed. `registry`'s promotion is now the **worked precedent** for what would earn it (D3). |
| **R3** | 5.7: `inngest-luks-cutover-6894.md` §5 step 2 and `betterstack-log-query.md` still carry the dead `-var` route. AC-28 expects `grep -c 'apply_target=main'` → `0`. | PR-1 already rewrote §5 step 2 and kept the old command **quoted inside its CORRECTED paragraph**. `betterstack-log-query.md` still carries the route at line 47. §5 step 4 still says "#8296 … does not close itself". | 5.7 shrinks to: `betterstack-log-query.md` line 47, and §5 step 4. AC-28 takes AC-18's shape: the one remaining `apply_target=main` must sit on the `Both halves were wrong` line. |
| **R4** | AC-33's second limb puts the dead-probe issue number inside the alert's resource block in `betterstack-logs-alerts.tf`. | That path fires the push apply over the whole drifted allowlist. The operator's constraint (b) forbids it. | The limb is cut from PR-2 (see Cut List). D1 is **filed** during work. Its number is cited in the new probe's header, the flipped ledger row's `does_not_defend`, and runbook §5. The D1 issue body names "cite this issue inside `logtail_exploration_alert.inngest_luks_wrong_volume` in the next PR that edits that file for its own reason" as its first task. |
| **R5** | 5.11: the staging probe "exits 1 on every sweep, and posts a false regression comment on **#6894**". | Its directive is on **#8294** (CLOSED 2026-09-20T16:19:47Z, no sweeper PASS). The latest sweep log reads `issue #8294: … exit=0` and `closed and verification passes — no action, no comment`. It currently exits **0**, not 1: its query window still holds pre-cutover rows. | Delete it anyway, for the parent's stated reason (obsolescence). One more hazard, stated correctly: once its window slides past the cutover it would exit 1, and in closed mode **exit 1 reopens #8294** until the 14-day lookback ends (2026-10-04). After deletion the sweeper logs `script … missing in repo HEAD` for #8294 until 2026-10-04. That is harmless: `return 0` and no GitHub write. Optional clean-up: strip the directive from #8294's body. |
| **R6** | `model.c4` edit, then run AC-24 (c4 parity + syntax + render). | `model.likec4.json` is a committed render. `c4-model-freshness.test.sh` (CI) fails if it is not regenerated. | Added to Files to Edit: regenerate with `bash scripts/regenerate-c4-model.sh`. |
| **R7** | 5.8: the cutover probe's `RETIREMENT:` line names the staging sibling. | It reads "when #6894's cutover tracker closes, delete this file with its staging sibling". That tracker (#8295) closed 2026-09-20. Its directive's `earliest` is 2026-09-23, so the closed-set path re-verifies it from 09-23 until 10-04. | Rewrite `RETIREMENT:` to name the real end condition (#8295 leaves the closed lookback on 2026-10-04) and drop the staging sibling. Re-point `NEXT` at #8285. Do not delete it in this PR: until 10-04 it is the only thing that would reopen #8295 if the cutover regressed. |
| **R8** | Phase 7 (file D1, D3, D4, D5, D8, D9, D10, D11) sits outside Phase 5. | None of the eleven deferrals has been filed. PR-1's body says "0 filed". PR-2 is the last PR before #8296 closes. **D9 duplicates open #6907** ("encryption-posture: ARM Layer A repo-sweep as required check"). | **D1 is filed in work Phase 0**, because the ledger text cites its number. **Every other deferral is filed after merge, before `gh issue close 8296`**: D3, D4, D5, D8, D10, D11, **and D2, D6, D7 as issues assigned to the operator or CLO**. A line in a closed issue's comment does not satisfy `wg-when-deferring-a-capability-create-a`. D9 is a comment on #6907, not a new issue. Before each filing, run a dedup search, set a milestone, and file them in one batch. Also file **D12**, below. |

## User-Brand Impact

Inherited from the parent plan's `## User-Brand Impact`, narrowed to the record half.

**If this lands broken, the user experiences:** a regulator-facing record (the Article 30 register
and the encryption-posture ledger) that says their in-flight Inngest job payloads are encrypted at
rest while the store is on the plaintext volume, or returns to it after a sanctioned
`op=luks-rollback`. Or, through R1, the tracker for the **plaintext copy that still exists** closes
itself on a healthy day, and nothing prompts anyone to destroy that copy by its 2026-10-22 expiry.

**If this leaks, the user's data is exposed via:** a seized, RMA'd or snapshot-imaged
`hcloud_volume.inngest_redis`, the retained plaintext backstop. It holds a full second copy of the
same AOF (user prompts and agent output) until #8285, and no erasure path reaches it. The flip
narrows exposure to one volume. The record must not read as if it ended it (AC-7).

**Brand-survival threshold:** single-user incident. One seized volume exposes every in-flight
user's prompts at once, and one false limb in the Art. 30(1) record fails on its first reading.
`requires_cpo_signoff: true`. CPO's GRANTED-CONDITIONAL sign-off on the parent plan covers PR-2's
scope (parent `## Domain Review` → `### Product (CPO)`). Every condition is structural in this plan:
`live_verification` held at `unavailable:`, the backstop named in `does_not_defend`, and the
record lagging the detector (the gate above). R1 **strengthens** that CPO condition ("the claim
never outlives its detector"). It does not relax it. `soleur:engineering:review:user-impact-reviewer`
runs at review time.

## Files to Edit

| File | Change (parent task) |
| --- | --- |
| `scripts/encryption-posture-ledger.json` | **5.1–5.3.** Parent `### Phase 5` steps 1–3 and `## Encryption Posture`, verbatim in intent. `hcloud_volume.inngest_redis_luks` → `mechanism: luks`, **`exception` block deleted**, one `evidence` string (content anchors only), `defends_against`, and a `does_not_defend` that names `hcloud_volume.inngest_redis` **and the D1 issue number** (R4). `live_verification` → `unavailable:<cipher half unobserved …>`, which now names `hcloud_volume.registry`'s `store_luks` promotion (#8423) as the precedent (R2). `hcloud_volume.inngest_redis`: keep `plaintext-exception`; rewrite `evidence`, `live_verification`, `exception.justification`, `exception.reevaluate_when` (add `INNGEST_LUKS_CUTOVER=rolled-back`), `tracking_issue` → `#8285`, `reassessed_on` → `2026-09-21` (the date the reassessment is made; see Sharp Edges); **`expires_on: "2026-10-22"` and `expires_on_not_extended` byte-untouched**. `live_coverage_floor` untouched (`2`). |
| `knowledge-base/legal/article-30-register.md` | **5.4.** Dated in-cell amendments to PA-21 §(f), PA-22 §(f) and PA-13 §(e) in the register's `**[2026-09-20 AMENDMENT (#8296): …]**` / `**[Superseded 2026-09-20 (#8296): …]**` convention. The date is the cutover's. The "Two copies, bounded" fact and the EXPIRED clause are kept verbatim. The pinned phrase `the apply that follows` is present in each amended cell (parent AC-21). Any
back-reference inside an amendment is written as "recorded above in this cell", never "immediately
above" or "the preceding row". The register is append-only, so positional locators go false
(learning `2026-09-18-my-supersession-pointer-named-the-wrong-bracket.md`). The amendment states that the apply **has run** (run 35605929787, 2026-09-21) and the alert read back unpaused. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | **5.5.** Replace `platform.infra.inngestRedis`'s falsified description. Drop `AT REST: STILL PLAINTEXT ext4`, `AT REST IS STILL PLAINTEXT AS OF THIS EDIT`, and the `format = "ext4"` / `ignore_changes = [format]` citation. State the post-cutover shape: LUKS-backed store, a retained plaintext backstop until #8285. |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | **R6.** Regenerated by `bash scripts/regenerate-c4-model.sh`. Never hand-edited. |
| `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` | **5.6.** Appended `## Amendment — 2026-09-21 (#8296)`: the observed cutover (15:29:10Z terminal row, 15:36:40 probe row), and a correction of **apparatus scope item 8**: the row to flip is `hcloud_volume.inngest_redis_luks`, never `hcloud_volume.inngest_redis`. Additions only (`--numstat` deletions `0`). |
| `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` | **5.6.** Appended amendment: "It ships PAUSED" is falsified. The alert armed on the push apply of `b53173a04` (run 35605929787) and read back `paused=false` at 2026-09-21T14:18:56Z. This fulfils PR-1's forward pointer ("carries its own amendment"). Additions only. |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | **5.7 (R3).** Line 47's "**Ships PAUSED** and is armed by `-var inngest_luks_cutover_complete=true` …" becomes the current state (armed by the declared default since #8296). |
| `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` | **5.7 (R3).** §5 step 4: #8296 closes post-merge by hand after PR-2. #8285 now carries the property probe's directive (notify-only, never closes itself). Cite D1. **Leave step 2's CORRECTED paragraph alone** (PR-1 already landed it). |
| `scripts/followthroughs/inngest-luks-cutover-6894.sh` | **5.8 (R7).** Comment and `echo` text only; no exit statement changes (AC-32b). #8295 is re-verified in closed mode until 2026-10-04, and it is the only detector that can REOPEN on a rollback until then. `NEXT (not automatic):` → the one remaining step: destroy the backstop under #8285 by 2026-10-22. `RETIREMENT:` → "delete after #8295 leaves the sweeper's 14-day closed lookback (2026-10-04); it has no sibling". |
| `scripts/cutover-inngest.sh` | **5.9.** On the `op=luks-rollback` **success** path only, add one `NEXT (not automatic):` line. **The `FSM confirmed '$LK_EXPECT'` notice is SHARED by `luks-cutover` and `luks-rollback`** (one `case` arm, with `LK_EXPECT=rolled-back` set only for rollback, confirmed by the verify-the-negative pass). So the line must sit behind an explicit `[[ "$OP" == luks-rollback ]]` guard right after that notice. It must not be written unguarded next to the notice. It names `scripts/encryption-posture-ledger.json` (`hcloud_volume.inngest_redis_luks` back to `plaintext-exception`) and `knowledge-base/legal/article-30-register.md` (PA-21/PA-22/PA-13 amendments). It is **not** added to the `luks-cutover` success path. |
| `scripts/test-all.sh` | Register `run_suite "scripts/inngest-luks-property-8296" bash scripts/followthroughs/inngest-luks-property-8296.test.sh` beside the #8386 entry (the `lint-orphan-test-suites.sh` gate). |

## Files to Create

| File | Purpose |
| --- | --- |
| `scripts/followthroughs/inngest-luks-property-8296.sh` | **5.10, revised by R1 and plan review.** Asserts the **property**: the ledger's claim for `hcloud_volume.inngest_redis_luks` agrees with the device the store is on. **Notify-only.** The header says so, and says it never closes #8285. Full exit contract: `## Guard Contract` → Guard 3 → **Decision table**. It is one equivalence, `claims_luks == on_luks_mapper`, evaluated only over a **usable, fresh** newest row. Idioms copied from `registry-luks-live-8386.sh`: `set -uo pipefail` (never `-euo`), the `case "$-" in *x*)` refusal (exit 78) when `BETTERSTACK_QUERY_PASSWORD` is set, `--limit "${SOLEUR_FT_LIMIT:-5000}"`, and branch markers. **Not** its exit set. `RETIREMENT:` uses the colon-prose form. It names the `.test.sh`, the `test-all.sh` `run_suite` line, and the #8285 directive, and it states that coverage ends when #8285 closes (R1). The exit-5 output **points to** runbook `inngest-luks-cutover-6894.md` §5 for the revert anchors rather than duplicating them. When the store is on the plaintext volume, the output leads with `backstop is the LIVE store — do NOT destroy hcloud_volume.inngest_redis` (spec-flow P0-2). |
| `scripts/followthroughs/inngest-luks-property-8296.test.sh` | Guard 3's harness (see `## Guard Contract`). It stubs `scripts/betterstack-query.sh` and points the probe at a fixture ledger. It pins a **branch marker per case**, not just the exit code, because several arms share `5` or `3` and a code-only suite collapses them. It also carries the **rollback-NEXT placement check** for `scripts/cutover-inngest.sh` (AC-32). That check lives here, not in `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, because any edit under `apps/web-platform/infra/**` fires the push apply. |

## Files to Delete

| File | Why |
| --- | --- |
| `scripts/followthroughs/inngest-luks-staging-6894.sh` | **5.11 (R5).** Its staging-era question is settled. **The reason is obsolescence, not impossibility.** A rollback plus a boot can re-arm the staging block, so it *could* exit 0 again, and the PR body must not say "permanently falsified". `git grep -n 'inngest-luks-staging-6894'` outside the planning artifacts returns **zero** references today, so nothing else needs editing. Its tracker is #8294, not #6894. |

**Not created:** a counsel-review audit file. `soleur:ship` Phase 5.5 produces it (parent
`## Files to Edit` → "Not created").

**Not touched (constraint):** `.github/workflows/apply-sentry-infra.yml`, `infra/sentry/**` (#8451 /
#8453), and everything under `apps/web-platform/infra/**`.

## Open Code-Review Overlap

1 open scope-out touches these files: **#7942** ("Two mutation batteries in plugins/soleur/test/
are named *.mutation.sh and run in no gate"), which matches `scripts/test-all.sh`.
**Acknowledge:** PR-2 adds one `run_suite` line for a `.test.sh`. It neither creates nor renames a
`*.mutation.sh`. The concern is different and #7942 stays open. No other of the 71 open
`code-review` issues names a PR-2 path (standalone `jq --arg` over their bodies).

## Implementation Phases

Parent `### Phase 5`'s order: ledger → records → probe → deletion. One pre-step first.

### Phase 0 — file D1 (needed by the ledger text)

File the D1 issue (dead-probe heartbeat; parent `## Deferred Capabilities` D1, trigger
**2026-10-22**) after a dedup search, with a milestone, and record its number. This is a GitHub write. It is not production and needs no
per-command ack. Its first task is the in-block citation that R4 moved out of this PR.

### Phase 1 — the ledger (5.1–5.3)

1. Edit both rows per `## Files to Edit`. Dry-run against a scratch copy first:
   `python3 scripts/lint-encryption-posture.py --ledger <scratch> …`. The parent measured
   `0 failing checks -> PASS` for the intended shape. Then edit in place.
2. Assert AC-1 … AC-10 directly. Two of them (AC-2 and AC-4) exist because the lint is blind to the
   case they cover.

### Phase 2 — the five records (5.4–5.7)

Register (5.4), `model.c4` then `regenerate-c4-model.sh` (5.5/R6), ADR-142 and ADR-218 appended
amendments (5.6), `betterstack-log-query.md` line 47 and runbook §5 step 4 (5.7/R3).

### Phase 3 — scripts (5.8, 5.9)

The cutover probe's `NEXT`/`RETIREMENT` (5.8/R7), and the rollback `NEXT` line in
`cutover-inngest.sh` (5.9). Re-run `apps/web-platform/infra/cutover-inngest-workflow.test.sh`
(665/665): it reads `scripts/cutover-inngest.sh`.

### Phase 4 — the property probe (5.10, R1)

Write the `.test.sh` **first**, from Guard 3's Decision table, mutation matrix and harness rows
(RED). Then write the probe (GREEN). Put the rollback-NEXT placement check (AC-32) in the same
suite. Register it in `scripts/test-all.sh`. Then run:

- `bash scripts/lint-followthrough-varq-ban.sh`
- `bash scripts/lint-orphan-test-suites.sh`

Apply each of the 9 mutation rows by hand to a scratch copy and record the measured RED
(marker + exit). **Mandatory (AC-29d):** run one live read-only invocation using the Better Stack
**query** credentials from Doppler `prd_terraform`. This reads production telemetry and does not
mutate it. Expected result: `agree`, exit `2`. Paste the verdict line into the PR body.

### Phase 5 — delete the staging probe (5.11)

`git rm scripts/followthroughs/inngest-luks-staging-6894.sh`.

### Phase 6 — verification

Run:

- every PR-2 acceptance criterion below;
- the unchanged-gate floors;
- `lint-infra-no-human-steps.py --changed --base origin/main`.

**Do not reference #7529** in any PR body.

### Post-merge (after the operator's explicit merge go-ahead, never auto-merged)

None of these steps mutates production, and fact (c) verified that merging is inert. These are
GitHub writes and local reads. The agent runs them itself; they are not an operator checklist.

1. **5.12** Enroll the probe on **#8285**, only **after** merge, so the script exists at `main`
   HEAD when the sweeper reads it:
   - Add the `follow-through` label.
   - Add a column-0, unfenced directive:
     `<!-- soleur:followthrough script=scripts/followthroughs/inngest-luks-property-8296.sh earliest=<merge date+1d>T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
     The three secrets are already wired, and the #8294 and #8295 directives use them.
   - Add two body lines:
     - "Do NOT close this issue before `hcloud_volume.inngest_redis` is destroyed. Closing it turns
       off the ledger-vs-device probe."
     - "The backstop-destroy PR also deletes `scripts/followthroughs/inngest-luks-property-8296.{sh,test.sh}`
       and its `run_suite` line."

   Read the result back (AC-30).
2. **R8 deferrals.** Run a dedup search first. Then, in one batch, file D3, D4, D5, D8, D10, D11,
   and D2, D6, D7, the last three as issues assigned to the operator or CLO. Add the D9 evidence
   as a comment on #6907. File D12. Give each issue a milestone.
3. Strip the obsolete directive from #8294's body (R5). This is one `gh issue edit` and ends the
   daily ERROR log line.
4. **AC-P8** `gh issue close 8296`, gated as AC-P8 states, with a closing comment listing every
   deferral number.
5. Compound Step E archival of the parent spec dir and plan, which was deferred to PR-2's compound
   run (parent tasks.md `## Archival note`).

**Any production mutation that surfaces during work** is **out of scope**: a terraform apply, a
`workflow_dispatch` with `dry_run=false`, a Doppler write, or a vendor API write. It needs the
operator's per-command authorization with the exact command shown
(`hr-menu-option-ack-not-prod-write-auth`). This plan prescribes none. **Do not dispatch
`scheduled-followthrough-sweeper.yml` manually**: it sweeps and comments on every enrolled tracker,
not just #8285.

## Acceptance Criteria

The parent's `### PR-2 — the record` ACs apply unchanged **except where re-baselined here**.
`grep -c` exits 1 when it prints `0`, so assert on stdout: `[ "$(grep -c … || true)" = 0 ]`.

### Pre-conditions (measured, recorded above)

- [x] **AC-G1** PR-1 merged, the apply succeeded, and the alert read back `paused=false` (gate table).
- [x] **AC-G2** No PR-2 file is a baked carrier (fact (a)), and no PR-2 file is under
  `apps/web-platform/infra/**` (fact (b)). Re-checked on the final diff:
  `git diff --name-only origin/main... | grep -c '^apps/web-platform/infra/'` → `0`.
- [ ] **AC-G3** Fact (c) holds for the **final** diff. Checked with one grep over the union of
  every push filter that can reach production (the table above):
  `git diff --name-only origin/main... | grep -cE '^(apps/web-platform/|apps/[^/]+/infra/|infra/|\.github/workflows/|tests/scripts/lib/destroy-guard-filter-web-platform\.jq|plugins/soleur/|plugin\.json|eleventy\.config\.js)'`
  → `0`. There is also no `vinngest-*` tag push. The PR body states the result.

### Ledger (parent AC-1 … AC-10, AC-6 re-baselined)

- [ ] **AC-1 … AC-5, AC-7 … AC-10**: as the parent writes them.
- [ ] **AC-6 (re-baselined, R2)** `jq -r '.live_coverage_floor'` → `2`, and
  `jq '[.stores[]|select(.at_rest.live_verification=="available")]|length'` → `2`. Both unchanged.
- [ ] **AC-6b** The backstop row's `exception.tracking_issue` → `#8285`, and the flipped row's
  `does_not_defend` contains the D1 issue number.

### Records (parent AC-18 … AC-24, AC-27; AC-28 re-shaped)

- [ ] **AC-18 … AC-24, AC-27**: as the parent writes them.
- [ ] **AC-24b (R6)** `bash plugins/soleur/test/c4-model-freshness.test.sh` passes: the committed
  `model.likec4.json` matches a fresh render.
- [ ] **AC-27b** ADR-218 gained an appended amendment containing `It ships PAUSED` **and**
  `2988582970`, with `git diff --numstat origin/main -- <ADR-218 path>` showing deletions `0`.
- [ ] **AC-28 (re-shaped, R3)** Three checks:
  - Regression guard: `grep -n 'apply_target=main' …/inngest-luks-cutover-6894.md | grep -vc 'Both halves were wrong' || true`
    prints `0`. This passes today; it guards the CORRECTED paragraph.
  - Proves the edit: `grep -c 'inngest_luks_cutover_complete=true' …/betterstack-log-query.md || true`
    prints `0` (baseline `1`).
  - Proves the edit, **positively**: §5 step 4 contains the new wording pinned by the work phase.
    It names #8285 as the probe's enrollment and says #8296 was closed by hand after PR-2.
    Assert it with `grep -c` on a single-line anchor phrase (≥ 1). Do not use an absence grep,
    which a line-wrapped "does not / close" would pass by accident.

### Probe (parent AC-29 … AC-32; AC-29/AC-30 revised by R1)

- [ ] **AC-29 (revised)** `scripts/followthroughs/inngest-luks-property-8296.sh` exists and is
  executable. Its header contains `NOTIFY-ONLY` and `never closes #8285`. It carries a
  `RETIREMENT:` line that states coverage ends when #8285 closes.
  `bash scripts/followthroughs/inngest-luks-property-8296.test.sh` is green and covers every
  Decision-table row and harness row. **Each of the 9 mutation rows is applied by hand to a
  scratch copy, and its measured RED result (marker + exit) is recorded in the PR body.** No
  committed runner executes the mutations; that gap is the #7942 class.
- [ ] **AC-29b (never-0 / never-1, structural)** Four checks:
  - The last non-blank line of the probe is `exit 3`.
  - An `EXIT` trap remaps 0/1 to 3.
  - Every `exit` token passes the allowlist:
    `grep -noE '\bexit\b[[:space:]]*[^[:space:];)]*' <probe> | grep -vE ':exit[[:space:]]+(2|3|5|64|78)$'`
    → nothing.
  - The suite drives a fall-through case and an unset-variable case, and asserts neither
    yields 0 or 1.

  Output strings never contain the word `exit`.
- [ ] **AC-29d (live, mandatory)** One read-only invocation against real Better Stack rows. It
  uses the query credentials from Doppler `prd_terraform`, and reading them is not a mutation.
  It prints `agree` with exit `2`, and the verdict line is pasted into the PR body. A `3` here
  blocks enrollment until the field shape is explained: a probe that is blind on day one covers
  nothing.
- [ ] **AC-29c** `bash scripts/lint-orphan-test-suites.sh` and
  `bash scripts/lint-followthrough-varq-ban.sh` exit 0, and `scripts/test-all.sh` carries the
  `run_suite "scripts/inngest-luks-property-8296"` line.
- [ ] **AC-30 (post-merge, revised)** `gh issue view 8285 --json body,labels` shows:
  - the `follow-through` label;
  - the directive from Post-merge step 1, at column 0 and unfenced;
  - the "Do NOT close this issue before" line and the retirement line.

  #8296 carries no directive.
- [ ] **AC-31** `test ! -e scripts/followthroughs/inngest-luks-staging-6894.sh`, and
  `inngest-luks-cutover-6894.sh`'s `RETIREMENT:` line no longer names a staging sibling.
- [ ] **AC-32** as the parent writes it. Also:
  `grep -c 'NEXT (not automatic)' scripts/cutover-inngest.sh` → `1` (baseline `0`), and that one
  line sits under a `luks-rollback` guard. It is reached only when `$OP == luks-rollback` **and**
  the FSM confirmed `rolled-back`. It is never on the `luks-cutover` path and never on a
  refusal/abort path. **Asserted by the placement check in `inngest-luks-property-8296.test.sh`**
  (Guard 3). It is not asserted in `apps/web-platform/infra/cutover-inngest-workflow.test.sh`,
  because editing that file fires the push apply.
- [ ] **AC-32b** The `inngest-luks-cutover-6894.sh` edit changes no exit behaviour. #8295 is still
  re-verified in closed mode until 2026-10-04:
  `git diff -U0 origin/main -- scripts/followthroughs/inngest-luks-cutover-6894.sh | grep -E '^[-+][^-+]' | grep -c '\bexit\b' || true`
  → `0`.

### Dead-probe gap (parent AC-33, re-scoped by R4)

- [ ] **AC-33 (re-scoped)** D1 is an OPEN issue with a milestone. Its number appears in the
  flipped ledger row's `does_not_defend` and in runbook §5. Its body names the in-block `.tf` citation as its first task.
  The probe's `3 CANNOT ESTABLISH` arm covers the gap in the meantime.

### Gates

- [ ] **AC-35** `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
- [ ] **AC-37** Unchanged-gate floors hold: 96/96, 57/57, 665/665, 160/160, 79/79. The 665 floor
  is load-bearing here, because `cutover-inngest-workflow.test.sh` reads `scripts/cutover-inngest.sh`.
- [ ] **AC-38** Constraint: `git diff --name-only origin/main... | grep -cE '^(\.github/workflows/apply-sentry-infra\.yml|infra/sentry/)'` → `0`.
- [ ] **AC-39b** No closing keyword sits next to an issue number anywhere in the PR title or body.
  `grep -ciE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[^.#]{0,3}#[0-9]+'` on the body prints
  `0`. Prose like "the sweeper closes #8285" would auto-close the backstop tracker on squash-merge
  (learning `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`). Write
  it as "the sweeper never closes that tracker".
- [ ] **AC-39** The PR body's **first line** answers "does merging this alone mutate production?"
  with the measured answer (no: no apply, deploy or image build fires). This is the plan-sharp-edges
  rule from #8296/PR #8439. The body also says `Ref #8296` (never `Closes`), never mentions #7529,
  and says "obsolete", never "permanently falsified", for the staging probe.
- [ ] **AC-40** The final diff's file set is exactly `## Files to Edit` + `## Files to Create` +
  `## Files to Delete` + this plan and its `tasks.md`, **plus any file the pipeline writes**
  (`knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt`,
  `specs/feat-one-shot-8296-pr2-ledger-flip/session-state.md`, a learning from compound). Any
  other path is a scope question for review, not something to tick silently.
- [ ] **AC-P8 (post-merge)** `gh issue close 8296` runs only after all of these hold:
  - this PR has merged;
  - AC-29d printed `agree`;
  - AC-30 has been read back;
  - #8285's body carries the two lines from Post-merge step 1;
  - #8294's directive is stripped;
  - every deferral issue (R8, D12) is OPEN and listed in the closing comment.

## Observability

```yaml
liveness_signal:
  what: >-
    the hourly SOLEUR_INNGEST_SERVER_PROBE row from host_role=dedicated. Its data_mount_src must be
    /dev/mapper/inngest-redis (the flipped ledger row's device_binding.mapper) and its
    data_mount_devid must pin hcloud_volume.inngest_redis_luks's alias. The new property probe
    reads the same row and cross-reads the ledger claim once a day
  cadence: hourly probe row; daily 18:00 UTC sweep of the property probe (scheduled-followthrough-sweeper.yml)
  alert_target: >-
    store moves: logtail_exploration_alert.inngest_luks_wrong_volume (armed by PR-1) -> Better
    Stack email incident. Claim and store disagree: the sweeper's "ACTION REQUIRED" comment on #8285
  configured_in: >-
    apps/web-platform/infra/betterstack-logs-alerts.tf (alert, unchanged here);
    scripts/followthroughs/inngest-luks-property-8296.sh + the #8285 directive (probe, this PR)
error_reporting:
  destination: >-
    the sweeper posts a comment on #8285 with heading "Sweeper run: ACTION REQUIRED (exit 5 …)" or
    "CANNOT ESTABLISH (exit 3 …)" and the probe's last 4 KB of output. The workflow run log carries
    the same verdict
  fail_loud: >-
    PARTIAL, stated honestly. Exit 5 posts an "ACTION REQUIRED" comment on #8285 every day until
    fixed, but the sweeper RUN STAYS GREEN; it fails only for truncation, a missing secret or a
    fenced directive. The PAGING path for a store move is PR-1's wrong-volume alert (Better Stack
    email incident). This probe's unique contribution is catching a record that disagrees with the
    device, delivered as a comment only; D12 tracks escalation. Missing or stale data is exit 3,
    never a healthy verdict.
failure_modes:
  - mode: a sanctioned op=luks-rollback returns the store to the plaintext volume and nothing reverts the ledger or the Article 30 cells
    detection: >-
      layer 6: scripts/followthroughs/inngest-luks-property-8296.sh exits 5 (the newest dedicated
      row is not on the ledger row's mapper while the ledger claims luks). The dispatch output also
      prints a NEXT (not automatic) line naming both files (scripts/cutover-inngest.sh rollback arm)
    alert_route: >-
      comment only: layer 6 (scheduled-followthrough-sweeper.yml run log) plus the ACTION REQUIRED
      comment on #8285, whose text leads with "backstop is the LIVE store — do NOT destroy". Paging
      for the underlying store move is layer 4 (PR-1's Better Stack alert)
  - mode: the ledger claim is withdrawn or reverted while the store is still on the LUKS volume (under-claim drift)
    detection: layer 6, same probe, exit 5
    alert_route: layer 6, same as above
  - mode: the probe -> vector -> Better Stack path dies, so no rows arrive or the newest row goes stale
    detection: the same probe exits 3 (no_rows / producer_silent at > 3 h). This reports and does not page; D1 (filed in Phase 0) is the paging fix
    alert_route: layer 6 (sweeper run log) plus the CANNOT ESTABLISH comment on #8285
  - mode: the probe itself regresses into a PASS-shaped exit that would close #8285
    detection: >-
      layer 5 (CI): inngest-luks-property-8296.test.sh asserts the never-0/never-1 invariant
      statically and behaviourally. It is registered in scripts/test-all.sh (merge-blocking
      test-scripts shard)
    alert_route: layer 5 (a red required CI check on the PR that introduces it)
logs:
  where: >-
    scheduled-followthrough-sweeper.yml run logs (GitHub Actions) and the #8285 comment trail;
    probe source rows in Better Stack (Vector journald shipper, tag inngest-server-probe)
  retention: GitHub Actions default log retention; issue comments are permanent; Better Stack per plan tier
discoverability_test:
  # Credential-free and sub-second (measured 0.71 s). It verifies the RECORD half PR-2 changes:
  # the flipped row resolves against real code. The live-device half needs the Better Stack query
  # credentials. It is run once during work (Phase 4) and its verdict is pasted into the PR body.
  command: python3 scripts/lint-encryption-posture.py --repo-sweep
  expected_output: "PASS"
```

## Encryption Posture

Inherited verbatim in intent from the parent's `## Encryption Posture`, which carries the full
`at_rest` / `in_transit` / `exception` block for both rows. Three re-baselines:

- `live_coverage_floor` is `2` today and stays `2` (R2).
- The backstop row's `exception.tracking_issue` moves from `#6894` to `#8285`. `#8285` is the
  parent's own `tracking_issue` value in that block. `#6894` is the flipped row's parent exception
  and stays open.
- The flipped row's `does_not_defend` also names the D1 issue (R4).

`in_transit`: unchanged. No new cross-component connection is introduced.
`exception.expires_on: "2026-10-22"` is not moved.

The block below is restated here so the deepen-plan Phase 4.10 field check has something concrete
to verify. The work phase writes the final ledger strings from it.

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis_luks
    mechanism: luks
    evidence: >-
      apps/web-platform/infra/inngest-redis-luks.tf, resource "hcloud_volume" "inngest_redis_luks";
      cryptsetup luksFormat + luksOpen apparatus resolving to mapper inngest-redis; key =
      random_password + doppler_secret co-located in inngest-redis-luks.tf. OBSERVED 2026-09-20:
      terminal SOLEUR_INNGEST_LUKS_CUTOVER row 15:29:10Z (reason=cutover-complete, flag=done) and
      post-cutover probe row 15:36:40 with data_mount_src=/dev/mapper/inngest-redis,
      data_mount_devid=scsi-0HC_Volume_106903269. Content anchors only, no line numbers.
    defends_against: >-
      a seized, RMA'd or snapshot-imaged Hetzner block volume. The Inngest queue and run-state AOF
      are unreadable without the Doppler-held passphrase
    does_not_defend: >-
      a leaked credential; an app-layer read on the unlocked host; exfiltration through a
      compromised redis or inngest process; a dead probe pipeline, which the wrong-volume alert
      reads as healthy under treat_as_zero (D1, #<D1>). Also, until #8285, the retained plaintext
      backstop hcloud_volume.inngest_redis holds a full second copy of this same AOF
    disclosed_as: not-publicly-claimed
    live_verification: >-
      unavailable:the hourly probe row proves WHICH device backs /mnt/data (data_mount_devid), not
      that it is crypto_LUKS; the cipher half is the statically-resolved apparatus check_luks_row
      verifies. Flip to available in the commit recording a probe row with an explicit LUKS-type
      field, as hcloud_volume.registry's store_luks did (#8423)
  - store: hcloud_volume.inngest_redis
    mechanism: plaintext-exception
    evidence: >-
      apps/web-platform/infra/inngest-host.tf, resource "hcloud_volume" "inngest_redis". It was
      retained, attached and intact after the additive cutover, by design
    defends_against: nothing at the volume layer
    does_not_defend: >-
      a seized or snapshot disk exposes a full second copy of the Inngest queue and run-state AOF
      (in-flight user prompts and agent output), and no erasure path, including account deletion,
      reaches those bytes
    disclosed_as: not-publicly-claimed
    live_verification: >-
      unavailable:this row asserts the OPPOSITE of its sibling. A fresh probe row whose
      data_mount_src is not /dev/mapper/inngest-redis means the store came back, which the
      wrong-volume alert pages on and inngest-luks-property-8296.sh reports as exit 5
    exception:
      justification: >-
        retained plaintext backstop. The cutover is additive, so a rollback is a mount move plus a
        reverse copy, not a restore from a snapshot of unknown age
      tracking_issue: "#8285"
      reassessed_on: "2026-09-21"
      reevaluate_when: >-
        the backstop is DETACHED and DESTROYED under #8285; ALSO on INNGEST_LUKS_CUTOVER=rolled-back,
        which inverts the sibling row's claim and requires reverting it and the Article 30 cells
      expires_on: "2026-10-22"
in_transit: unchanged
```

## Guard Contract

Guards 1 and 2 shipped in PR-1 and are not touched. **Guard 3 is re-specified** because R1 changes
its exit contract.

### Guard 3 — the property probe (`scripts/followthroughs/inngest-luks-property-8296.sh`)

**Property.** While the plaintext backstop exists, the ledger's claim for
`hcloud_volume.inngest_redis_luks` agrees with the device the Inngest store is on, measured
from a **fresh, usable** probe row. When the claim and the device disagree, or cannot be
compared, someone is told every day. **The probe cannot close the tracker it is enrolled on:
no path through the script ends with status 0 or 1.**

**Decision table.** Evaluated in this order. The measurement comes first, the ledger read second.

| # | Condition | Exit | Marker (pinned by the suite) |
| --- | --- | --- | --- |
| 1 | shell tracing is on while `BETTERSTACK_QUERY_PASSWORD` is set | `78` | `xtrace_refused` |
| 2 | the query failed, or returned malformed JSON | `3` | `query_failed` |
| 3 | no `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row in the `--since 26h` window | `3` | `no_rows` |
| 4 | the newest such row (the **last** line; the helper outputs ascending) is older than **3 h** (hourly cadence plus slack) | `3` | `producer_silent` |
| 5 | the newest row's `data_mount_src` is empty, `n/a`, `__UNREADABLE__`, or does not start with `/dev/`; or its `data_mount_devid` does not match `scsi-0HC_Volume_[0-9]+` | `3` | `row_unusable` |
| 6 | the ledger is unreadable, or the `hcloud_volume.inngest_redis_luks` row, its `at_rest.mechanism` or its `device_binding.mapper` is missing | `3` | `ledger_unreadable` |
| 7 | claims `luks`, store not on the LUKS mapper | `5` | `rollback_inversion`. The output leads with "backstop is the LIVE store — do NOT destroy hcloud_volume.inngest_redis" and points to runbook §5 for the revert |
| 8 | does not claim `luks`, store on the LUKS mapper | `5` | `under_claim` |
| 9 | **only when** claims `luks` **and** store on the LUKS mapper, **and** `now` (see Clock) is after the backstop row's `exception.expires_on`, **and** that row still exists | `5` | `backstop_expired`: "destroy the backstop under #8285". It is restricted to the encrypted-and-agreeing state, so it can never tell anyone to destroy a volume that is the live store after a revert (test-design P1) |
| 10 | otherwise: `claims_luks` (`mechanism == "luks"`) **equals** `on_luks_mapper` (`data_mount_src == "/dev/mapper/" + mapper`, exact string equality, no prefix or glob) | `2` | `agree`. A correct post-rollback revert (plaintext claim on the plaintext volume) also lands here, even after the expiry date |
| — | fall-through: the last line of the file | `3` | `unreachable` |

**Clock.** "Now" is read from an injected `SOLEUR_FT_NOW` (ISO-8601 UTC) when set, and from
`date -u` otherwise. A value that is set but malformed goes to `3 clock_malformed`; there is no
silent fallback (learning `2026-09-20-my-probe-graded-itself-against-a-clock-its-grader-never-read.md`).
Every fixture pins `SOLEUR_FT_NOW`. Fixture times sit well away from each boundary: 2 h 50 m vs
3 h 10 m for staleness, and a day either side of `expires_on`. Nothing depends on the real date,
so the suite does not change verdict on 2026-10-22.

**Structural enforcement of never-0 / never-1** (Kieran P0):

- An `EXIT` trap maps any status of `0` or `1` to `3`, with marker `trap_remapped`.
- The file's last non-blank line is a literal `exit 3`.
- The static scan is an **allowlist**, run over the file with comment lines stripped. Every `exit`
  token must be followed by a literal `2`, `3`, `5`, `64` or `78`, and the capture excludes quote
  characters so `trap '…; exit 3' EXIT` parses. A bare `exit`, `exit $?` or `exit "$rc"` fails
  the scan.
- Human-readable output never contains the word `exit`. The suite greps the stdout and stderr of
  every case for it.
- Precedent for the trap: `scripts/followthroughs/inngest-soak-6178.sh` (`on_exit()` rewrites any
  rc outside `{2,3,5,78}` to `3`, installed by `trap on_exit EXIT`). It is the only rc-filtering
  EXIT trap in the corpus; the other EXIT traps are cleanup-only.
  `ccla-representative-icla-7922.test.sh` supplies `assert_never_close_verb()`, which is
  self-tested with `assert_never_close_verb 0 SELFTEST`. Reuse its shape.

**Assembly.** Four chokepoints:

1. The newest dedicated probe row, read through `scripts/betterstack-query.sh` with
   `--since 26h --limit "${SOLEUR_FT_LIMIT:-5000}"`.
2. The ledger row's `at_rest.mechanism` and `device_binding.mapper`. The mapper is the
   discriminator, so the probe holds no literal mapper name or volume id.
3. The backstop row's `exception.expires_on`.
4. **Every exit path in the file, including the implicit ones** (fall-through, unset variable,
   `$?`). The never-0/1 property covers the whole file, not one arm.

**Mutation matrix** (written before the probe; each result is recorded in the PR body, see AC-29):

| # | Edit | Must red because |
| --- | --- | --- |
| 1 | newest row `data_mount_src=/dev/mapper/inngest-redis-plain `, ledger `luks` | must be `5 rollback_inversion`. A prefix match of `inngest-redis` would give `2` |
| 2 | ledger `plaintext-exception`, store on the LUKS mapper | `5 under_claim`, never `2` |
| 3 | newest row older than 3 h, on the LUKS mapper, ledger `luks` | `3 producer_silent`, never `2`. A dead probe must not read as healthy |
| 4 | two rows: the newest (last line) on plaintext, an older one on LUKS | `5`. An any-row match, or taking the first line, would give `2` |
| 5 | **order**: the fixture breaks BOTH reads (the query stub fails AND the ledger is unreadable) | the marker must be `query_failed`. The reversed order gives `ledger_unreadable`, so this row sees the order |
| 6 | newest row `data_mount_src=__UNREADABLE__` (and separately `n/a`) | `3 row_unusable`, never a false `5` alarm on #8285 |
| 7 | any `exit 2` edited to `exit 0`; separately, the trailing `exit 3` deleted and a function made to fall off the end; separately, an unset variable referenced | both the static allowlist and the behavioural scan red. This row targets the guard's own dispatch: an exit-0 path closes #8285 |
| 8 | a second non-allowlisted exit added after a compliant first (`exit 1` in a new arm) | the allowlist scan reds on the **second** member |
| 9 | the `backstop_expired` arm deleted, with `SOLEUR_FT_NOW` after `expires_on` | the fixture expecting `5 backstop_expired` gets `2` |
| 10 | the rollback NEXT line in a scratch copy of `scripts/cutover-inngest.sh` is moved into the `luks-cutover` success path, and separately above the `rolled-back` confirm | the placement check reds. The check also asserts the case label is found exactly once and the extracted body is non-empty, so a failed extraction cannot pass |

**Committed, not hand-run** (test-design P1). Rows 5, 7, 8, 9 and 10 edit **code** (the probe or
`cutover-inngest.sh`). The suite applies each of them to a scratch copy under `mktemp -d`, never
to the tracked file. It asserts that each edit landed inside the target arm's line range, then
expects RED. A known-positive and a known-negative run first prove the runner works. Rows 1–4 and
6 change fixtures only, so they are ordinary table cases. Nothing restores a tracked file, so
there is no restore trap to get wrong.

**Harness rows:**

- **H1.** The stub ignores the `--grep`/tag and returns every row. A mixed-host fixture must then
  red. A stub that does not apply the probe's filter hides a probe that does not apply it either.
- **H2 (must-PASS, non-canonical).** Unrelated rows from another host or tag, plus an older LUKS
  row, around a fresh newest LUKS row still give `2`. The fixture ledger uses a different mapper
  name with the row on that name, which proves the mapper is read from the ledger.
- **H3 (must-PASS, non-canonical).** A reverted pair (ledger `plaintext-exception`, store on the
  plaintext mapper) gives `2 agree`.
- **H4.** The suite's success condition is `fail == 0 && pass >= FLOOR`, with `FLOOR` a
  **hard-coded literal**. A runtime-derived floor falls when a case is deleted. `0 passed, 0 failed`
  must exit non-zero.
- **H5 (must-PASS).** A reverted pair (ledger `plaintext-exception`, store on the plaintext mapper)
  with `SOLEUR_FT_NOW` a day **after** `expires_on` gives `2 agree`, never `backstop_expired`.
- **H1, spelled out.** The fixture mixes a web-1 row on the plaintext source (newest) with a
  dedicated row on the LUKS mapper, and expects `2`. With the probe's own `host_role=dedicated`
  filter removed, which is a code mutation on the scratch copy, the verdict must turn to `5`, so
  the case reds. The probe must filter by itself and not rely on the stub's `--grep`.

**Implementation precedents** (copy them; do not invent):

- **Stub mechanism: a fake-tree file drop.** It is not an env override or a PATH shim.
  `registry-luks-live-8386.test.sh` `run_probe()` copies the probe into `$WORK/root/scripts/followthroughs/`
  and writes an executable stub at `$root/scripts/betterstack-query.sh`. The stub asserts its argv
  (e.g. `--since 26h`) and exits 64 otherwise.
- **The probe resolves the repo from its own location:**
  `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"` (`registry-luks-live-8386.sh`
  line 125). This is what lets the fixture ledger at `$root/scripts/encryption-posture-ledger.json`
  be injected with no env var. **Do not** copy the `git rev-parse --show-toplevel` form from
  `inngest-luks-cutover-6894.sh`, which does not work in a non-git sandbox.
- **Row parsing:**
  `jq -R -r 'fromjson? | .raw? | fromjson? | select(.host == $h and .host_name == $hn) | …'`
  (`inngest-luks-cutover-6894.sh`, the `DONE_N` / `ON_MAPPER` blocks). Take the newest row by `.dt`.
- The sweeper forwards `SOLEUR_FT_EARLIEST` (`sweep-followthroughs.sh`, `env_args+=`). This probe
  does not need it; its clock is `SOLEUR_FT_NOW`.

**Also in this suite: the rollback NEXT placement check (AC-32).** It extracts the
`luks-cutover|luks-rollback)` case body from `scripts/cutover-inngest.sh`. It asserts exactly one
`NEXT (not automatic)` line, reached only on `$OP == luks-rollback` after the `rolled-back`
confirm. The line is absent from the `luks-cutover` success notice and from every `REFUSING`
branch.

**Anchor.** The live half is the host's own rows. The record half is the committed ledger.
Beyond the suite, two things sit outside the commit: the **mandatory** Phase 4 live invocation,
whose verdict line is pasted into the PR body, and the daily sweep after enrollment. No repo
edit can make the live verdict pass.

## Architecture Decision (ADR/C4)

This PR makes no new architectural decision. It records that ADR-142's decision has been
carried out (parent `## Architecture Decision (ADR/C4)`).

### ADR

- **ADR-142**: appended amendment only. It records the observed cutover and corrects apparatus
  scope item 8. No status change.
- **ADR-218**: appended amendment only. "It ships PAUSED" is falsified.
- **ADR-141** (`adopting`): **not** moved. `live_verification` stays `unavailable:`, so its floor
  clause is not triggered. No new ordinal is claimed.

### C4 views

All three model files were checked in the parent plan, and the conclusion holds for PR-2.
**External actors:** none added or changed. **External systems:** none added (`betterstack`
and `doppler` already carry the edges). **Containers / stores:** none added. **Access
relationships:** none change. **One element description is falsified and replaced:**
`platform.infra.inngestRedis` in `model.c4`. `views.c4` and `spec.c4` need no edit.
`model.likec4.json` is regenerated (R6). Cardinality: `c4-count-parity.test.sh` passes today, and
this edit moves none of the counts in `model.c4` edge prose.

## Plan Review Revisions (2026-09-21)

The panel had seven seats: DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CTO (devex) and CPO. There was also one strong-model advisor consult
(plan Step 4.5). The verdicts:

- **CPO: GRANTED.** All four parent conditions hold, and neither the AC-33 re-scope nor the
  notify-only change weakens them.
- **Architecture:** no P0. It independently confirmed facts (a), (b) and (c), including the
  `workflow_run`, issue and PR triggers. `infra-validation.yml` lists `scripts/cutover-inngest.sh`
  on `pull_request` only, which is a PR check, not a production write.

**Applied (mechanical):**

1. **Kieran P0: never-0/1 made structural.** The last line is `exit 3`, an EXIT trap remaps 0 and
   1, and the static scan is an allowlist. The suite covers fall-through and unset-variable cases.
   The first draft's `exit [01]` grep could not see a fall-through that closes #8285.
2. **Kieran P1: precedent corrected.** `registry-luks-live-8386.sh` has `exit 1` arms and is not
   notify-only. Only its three idioms are cited.
3. **Kieran P1: unreadable values.** `n/a`, `__UNREADABLE__`, empty, and non-`/dev/` sources go
   to `3`, never a false `5`. The devid must be resolved.
4. **Advisor, spec-flow P1-5: staleness.** `--since 26h`, and newest row older than 3 h → `3`.
   Newest means the last line, because the helper takes the newest N rows and emits them
   ascending.
5. **Kieran P1: mutation row 5.** It now breaks both reads, so it can see order.
6. **Kieran P1, DHH: AC-32's conditional test resolved.** The check lives in the probe's suite,
   because the infra test file is under `apps/web-platform/infra/**`.
7. **Spec-flow P0-2: the exit-5 text leads with "backstop is the LIVE store — do NOT destroy".**
8. **Spec-flow P0-1, architecture P1-2, CTO: "coverage ends when #8285 closes" is written down.**
   It is stated in RETIREMENT, R1, Risks, and a #8285 body line.
9. **Spec-flow P1-3: the correct-revert state is defined.** It is `2 agree`, by the single
   equivalence (H3).
10. **Spec-flow P1-6: the live run is mandatory (AC-29d) before enrollment and before #8296
    closes.**
11. **Spec-flow P1-7: D2, D6 and D7 filed as issues.** AC-P8 is gated on enrollment read-back and
    on every deferral being open. D9 folds into open #6907 (dedup).
12. **Spec-flow P1-8: `backstop_expired` arm.** Exit `5` past `expires_on` while the backstop row
    exists.
13. **Architecture P1-1: Observability `fail_loud` corrected to "comment only".** Paging is PR-1's
    alert. D12 is filed.
14. **Architecture P2-1: the cutover-probe edit must not change any exit (AC-32b).**
15. **DHH, architecture P2-2: AC-G3 is one grep** over the union of production-reaching push
    filters.
16. **Simplicity: D1 is not cited in the probe header; the revert text is not duplicated** (the
    probe points to runbook §5).
17. **Kieran P2: AC-28 asserts the new step-4 wording positively.** AC-29 records each mutation's
    measured RED in the PR body.
18. **Spec-flow P2-11: stripping #8294's directive is mandatory,** not optional.
19. **DHH: deferrals D3–D11 moved from a pre-merge phase to post-merge.** Only D1 stays pre-merge.

**Not applied (persisted as decision challenges, `specs/feat-one-shot-8296-pr2-ledger-flip/decision-challenges.md`):**

- **DC-1 (User-Challenge, DHH): cut the property probe entirely.** Outvoted by CPO,
  code-simplicity, architecture and spec-flow. It is the only thing that detects a record that
  disagrees with the device, and it implements parent task 5.10, which the operator scoped.
- **DC-2 (Taste, CTO): enroll with `earliest≈2026-10-12`** instead of merge+1d, trading about 3
  weeks of daily record checks for about 20 fewer comments. The plan keeps merge+1d.
- **DC-3 (Taste, simplicity): trim the Guard 3 matrix further** (drop the under-claim arm and row
  2, and row 7). Kept: the under-claim arm is the same single equivalence with no extra code, and
  row 8 is the second-member row the guard contract requires.

## Domain Review

**Domains relevant:** engineering, legal, product. Carried forward from the parent plan's
`## Domain Review`. Its panel reviewed PR-2's whole scope (register amendments with CLO-supplied
convention and draft text; the GDPR gate; CPO conditional sign-off). No domain leader is
re-spawned for the same scope. The one design change in this plan (R1, notify-only) is technical.
It tightens the CPO condition and is reviewed at plan-review and review time.

### Engineering

**Status:** reviewed (parent panel), plus this plan's reconciliation R1–R8.

### Legal

**Status:** reviewed (parent: `soleur:legal:clo`, `soleur:gdpr-gate`). The Article 30 amendment is
a deliverable. DPIA no. Art. 33/34 no. `disclosed_as: not-publicly-claimed` stays true.
`soleur:ship` Phase 5.5 produces the counsel-review file.

### Product/UX Gate

**Tier:** none. No PR-2 path matches the UI-surface term list or glob superset.
**Pencil available:** N/A (no UI surface).

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | `lint-encryption-posture.py --repo-sweep` after both row rewrites | `0 failing checks -> PASS` |
| T2 | Flipped row with its `exception` block left in | passes both gates. AC-2 is the only catch |
| T3 | `live_verification: "available: observed …"` | schema failure (`^(available\|unavailable:.+)$`) |
| T4 | Guard 3 mutation rows 1–9 and every Decision-table row | each reds its named arm and marker |
| T5 | Guard 3 H1–H4 | as specified |
| T6 | `c4-model-freshness.test.sh` after the `model.c4` edit without regeneration | FAIL. After `regenerate-c4-model.sh`: PASS |
| T7 | `cutover-inngest-workflow.test.sh` after the rollback NEXT line | 665/665 |
| T8 | `lint-orphan-test-suites.sh` with the `run_suite` line removed | FAIL |
| T9 | fact (c) re-run on the final diff | no apply/deploy/build/cutover workflow fires |

## Risks & Sharp Edges

- **R1 is the load-bearing correction.** A follow-through probe with any `exit 0` enrolled on
  #8285 closes the backstop's retirement tracker on its first healthy day. AC-29b and Guard 3 row 6
  exist for that reason alone.
- **The lint cannot catch a half-done flip** (`check_at_rest` early-returns on `luks`). AC-2 and
  AC-4 are direct assertions.
- **Do not move `expires_on`.** After the flip, the backstop row is the only carrier of hard expiry
  enforcement for the pair, and that job is not a required check (D9).
- **`reassessed_on` date.** The parent says `2026-09-20`, the cutover date. The reassessment is
  made in this PR on 2026-09-21. Use the date the reassessment is committed. The register's
  amendment brackets keep `2026-09-20`, the event date that AC-18/AC-19 pin.
- **Nothing under `apps/web-platform/infra/**`.** A comment-only `.tf` edit still runs the push
  apply over the whole drifted allowlist. PR-1's apply applied two unrelated drift actions.
- **The C4 json is generated.** A hand edit, or none, fails `c4-model-freshness`.
- **Enroll after merge, not before.** The sweeper reads the script at `main` HEAD. A directive that
  names a script not yet on main only logs an ERROR. That is harmless, but it is noise.
- **Daily comments on #8285 are expected** (exit 2, heading "NOT YET"). The probe's output line
  must say "healthy: nothing to do" so a reader does not take the heading literally. The count is
  open-ended: roughly 30 per 30 days until #8285 closes, not capped at the expiry date.
- **Closing #8285 turns the probe off.** In closed mode the sweeper does nothing for exits 2, 3
  and 5. The #8285 body line written in Post-merge step 1 is the only guard against an early
  close. This is acceptable once the backstop is destroyed, because nothing is left to roll back
  to.
- **After a rollback, the ACTION REQUIRED comment lands on the tracker titled "Retire the
  plaintext … backstop".** A reader primed to destroy the volume could delete the live store. The
  exit-5 output leads with "backstop is the LIVE store — do NOT destroy". Until 2026-10-04 the
  cutover probe on #8295 also reopens that issue on a rollback. After that date, the comment and
  PR-1's alert are the only signals.
- **The probe covers the ledger, not the Article 30 cells.** On exit 5 its output names both files
  via runbook §5. A reverted ledger with unreverted register cells reads as `agree`. That residual
  is carried into D11 (hand-written prose with no ledger anchor).
- **Unreadable device values are `3`, never `5`.** The emitter writes `n/a` and `__UNREADABLE__`;
  a false ACTION REQUIRED on #8285 is the costliest false positive this probe can produce.
- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text,
  or omits the threshold fails `deepen-plan` Phase 4.6. This section is filled.
- **Never reuse, reset or remove `.worktrees/luks-stage-8294`, or the merged PR-1 worktree
  `feat-one-shot-8296-ledger-flip-arm-alert`.**

## Deferred Capabilities

The parent's D1–D11 table stands (`## Deferred Capabilities`). This plan changes **when** they are
filed, not what they are. D1 is filed in work Phase 0; the rest are filed post-merge, before #8296
closes (R8). D2, D6 and D7 become issues, and D9 becomes a comment on #6907. D3's trigger now has a
worked precedent: `hcloud_volume.registry` went `available` via `store_luks` in #8423.

| # | Deferred | Why not here | Re-evaluation trigger |
| --- | --- | --- | --- |
| D12 | A notify-only probe's exit 5 is delivered only as a comment, and the sweeper posts a comment on every run. So a daily "NOT YET" stream buries the one ACTION REQUIRED, and the run stays green. Candidates: suppress repeated identical verdicts, add a label or run-failure on exit 5, or have `op=luks-rollback` comment on #8285 directly | Changing the sweeper's contract affects every enrolled probe (`sweep-followthroughs.sh`), and a rollback-path GitHub write widens a production workflow's authority | The next notify-only probe enrolled, or the first exit 5 on #8285, whichever comes first |
