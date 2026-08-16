---
title: "fix(infra): the bridge-less push-path plan must not reach an SSH-provisioned resource"
date: 2026-08-16
slug: fix-pushpath-bridgeless-ssh-target-leak
branch: feat-one-shot-7539-pushpath-bridgeless-target-leak
issue: 7539
closes: 7539
lane: cross-domain
type: bug
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
---

## Overview

`Apply web-platform infra` has been red on `main` for six consecutive pushes. The cause is a single
misplaced `-target=` line.

The `apply` job runs two Terraform stages separated by a **credential-availability boundary**.
Stage 1 is named **"Terraform plan (allow-list, non-SSH resources only)"**
(`apply-web-platform-infra.yml:434`, spanning to `:739`) and its saved `tfplan` is applied at `:764`
— both **before** the `CF Tunnel SSH bridge` at `:895` that exports `TF_VAR_ci_ssh_private_key`.
Stage 2, `Terraform apply (SSH-provisioned resources, over the bridge)` (`:904`), owns every
SSH-provisioned resource and carries 14 `-target=terraform_data.*` at `:931-944`.

`-target=terraform_data.inngest_consumer_probe_install` sits at `:578` — inside stage 1, whose own
title declares it carries no SSH resources. That resource (`server.tf:749`) is SSH-provisioned
against `hcloud_server.web["web-1"]` and carries `depends_on = [terraform_data.journald_persistent]`
(`:753`). Terraform's `-target` is transitive on dependencies, so `journald_persistent` entered the
bridge-less plan; with the bridge not yet open, `agent = var.ci_ssh_private_key == null`
(`server.tf:997`) evaluated **true** and the provisioner aborted with
`SSH agent requested but SSH_AUTH_SOCK not-specified`.

**Two mechanisms, one placement bug — measured 2026-08-16, both live.**

- *Transitive (2026-08-13, run `31751479550`).* `journald_persistent` was simultaneously due for
  replacement — its `triggers_replace` hashes `vector.toml`, changed at `0d6443960` — so `-target`
  transitivity dragged it into the bridge-less plan and **it** failed the SSH resolution. A *clean*
  transitive dependency plans as a no-op, which is why the misplacement had sat green for months.
- *Direct (2026-08-16, run `31952153708`).* After PR #7543's `apply_target=vector-redeliver`
  dispatch cleaned `journald_persistent` (below), the transitive drag disappeared — and the
  misplaced target now fails on **its own** first `file` provisioner:
  `terraform_data.inngest_consumer_probe_install: Provisioning with 'file'... Error: file
  provisioner error / SSH agent requested but SSH_AUTH_SOCK not-specified`.

The direct form is the durable statement of the defect: an SSH-provisioned resource on a stage with
no SSH transport fails whether or not anything else is dragged in with it. Both reduce to the same
one-line fix, and that a *clean* dependency hides the transitive form is precisely why placement
needs a structural check rather than a passing apply.

The fix moves that one line into stage 2, where its three structurally identical siblings already
live.

No `spec.md` exists for this branch — the one-shot path enters `plan` directly without a brainstorm —
so `lane:` could not be carried forward and defaulted to `cross-domain` (fail-closed). The Phase 2.5
domain sweep did run and found only Engineering relevant; the conservative lane is retained rather
than narrowed after the fact.

## Research Insights

### Premise Validation

Re-probed 2026-08-16 against `main` at `4a7e5cb08`.

| Premise (as briefed) | Verdict | Evidence |
|---|---|---|
| #7539 open | HOLDS | `gh issue view 7539` → `OPEN` |
| #7543 a live draft | HOLDS | `OPEN`, `isDraft: true`, `updatedAt 2026-08-16T11:35:51Z` |
| The `[ack-destroy]` guard is the blocker | **STALE** | Ack carried on `5c85b1c3e` (2026-08-13 22:49); guard passed; apply failed at the provisioner |
| `journald_persistent` ABSENT from state | **FALSE** | `terraform state pull` → `status=tainted`, `id=19da84b0-…` |
| `inngest_consumer_probe_install` may have landed | **FALSE — never created** | absent from `terraform state list` |
| Stage 1's plan "does not exclude the SSH set" | **IMPRECISE** | It excludes by construction; one address was misplaced into it |
| Repair needs #7543's redeliver arm | **FALSE** | taint + the existing `:935` target deliver it |

**The predicted concurrency exposure OCCURRED — re-measured 2026-08-16 14:2x UTC, after rebase.**

Plan review flagged that `journald_persistent`'s taint was the sole replacement driver (its stored
`triggers_replace` `31c8b8b4bab798dc…` already equalled the HEAD hash) and therefore consumable by
any concurrent apply. That is exactly what happened, inside this session:

| Run | When | Outcome |
|---|---|---|
| `31948197175` (push, #7543's merge) | 12:51 | "success" — but only `preflight` ran; `apply` was **skipped**. A vacuous green |
| `31950518641` (workflow_dispatch) | 13:41 | **`vector_redeliver` job** — #7543's new arm. Replaced `journald_persistent` over the bridge |
| `31952153708` (push) | 14:15 | `apply` **FAILED** — the direct form of this defect |

Live state now: `journald_persistent` = **normal** (taint consumed, `vector.toml` delivered to web-1
by #7543's dispatch); `inngest_consumer_probe_install` = **tainted** (object created, its `file`
provisioner failed for want of the bridge).

**Consequences for this plan, stated plainly:**

- **Properties 3 and 4 are already satisfied — by #7543, not by this PR.** The Cut List reasoning
  that decoupled from #7543 was sound at the time and is now moot; do not claim credit for delivery
  this PR did not perform.
- **Properties 1, 2 and 5 remain entirely unmet.** `main`'s apply is still red, and the misplaced
  target is still at workflow `:585`.
- The resource this PR's stage 2 will repair is now **`inngest_consumer_probe_install`** (tainted),
  not `journald_persistent` (clean). Acceptance must assert it reaches **untainted**, since merely
  "present in state" is now true and false-passes.

### Property List

1. A stage with no SSH transport never plans an operation requiring one.
2. `main`'s `Apply web-platform infra` is green, so declared infra reaches production.
3. `terraform_data.journald_persistent` reaches an untainted state with its provisioners actually run.
4. `vector.toml` (changed 2026-08-12 at `0d6443960`) reaches the running web-1, so the
   **`inngest-consumer-probe`** journald identifier it added to Vector Source 4 begins shipping.
5. The class cannot regress silently.

### Cut List

| Mechanism | Property | Why cut |
|---|---|---|
| `-exclude` flags on the push-path plan | 1 | Nothing to exclude once the address is in the correct stage |
| Open the bridge before stage 1 | 1 | Inverts the stage contract: puts root SSH on the stage named "non-SSH resources only". **Carried into the ADR's rejected-alternatives so it is not re-litigated** |
| A new saved-plan gate file | 5 | `terraform-target-parity.test.ts` already derives the SSH set from `server.tf` |
| Depend on #7543 for repair | 3, 4 | Taint + existing `:935` target suffice |
| **Transitive-closure walk over dependency edges (+ mutation M3, harness H1)** | 5 | **Cut on proof, not preference.** (a) It would go **RED on a clean tree**: `server.tf:142` names `terraform_data.journald_persistent` in a comment *inside* the `hcloud_server.web` block, and `ci-ssh-key.tf:97` names `terraform_data.root_authorized_keys` inside a `description` **string literal** that comment-stripping cannot remove — a body-grep extractor attributes phantom `hcloud_server.web → journald_persistent` edges, and nearly every push-path target depends on `hcloud_server.web`. (b) It requires generalising a hand-rolled brace-matching HCL parser whose own header documents that it **fails open** — buying coverage of a zero-instance shape by enlarging the silent-failure surface. (c) It is subsumed for this tree by the bright line below |

### Residual class, recorded rather than guarded

The bright line does not catch a **non-`terraform_data`** push-path target gaining a `depends_on`
into an SSH resource. Verified equivalence that makes this acceptable today: **no non-`terraform_data`
resource in any of the 45 infra `.tf` files carries a `provisioner` block at all** — 17 of the 18
`terraform_data` resources are SSH-provisioned and nothing else is. So "reaches an SSH-provisioned
resource" is presently equivalent to "reaches a `terraform_data`". Widening the SSH predicate to all
block types is filed as a follow-up rather than done here, because it edits a shared fail-open parser
that other assertions in the same suite depend on, under a P1 red-`main` fix.

### Key locations

- `.github/workflows/apply-web-platform-infra.yml` — **line numbers re-derived after the 2026-08-16
  rebase onto `f78468e53`; they shifted ~+7 when #7543 landed, which is why the guard anchors on
  content rather than coordinates.** `:441` stage-1 plan, `:585` the misplaced target, `:771` stage-1
  apply, `:902` bridge step / `:904` its `uses:` (the guard's end anchor), `:911` stage-2 apply.
  The recovery comment, `ssh_token_gate` warning, destroy-guard rationale and ARM gate shifted
  correspondingly — locate each by its quoted text, not by the pre-rebase line.
- `apps/web-platform/infra/server.tf` — `:142` phantom-edge comment, `:743` the `#7228` block title,
  `:749` the resource, `:753` `depends_on`, `:767-769` its SSH connection, `:981` `journald_persistent`,
  `:997` the `agent` expression, `:1070-1085` the Vector delivery and reload window.
- `plugins/soleur/test/terraform-target-parity.test.ts` — `:9` stale header count, `:79`
  `EXCLUSION_ALLOWLIST`, `:86` `MIN_SSH_PROVISIONED = 10` (actual set is **17**), `:152`
  `extractTargets` (flat whole-file `Set` — the vacuity), `:227` the floor, `:231` the union test,
  `:236` the 9-name pin.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Response |
|---|---|---|
| Root cause is a missing exclusion | One address in the wrong stage | Re-scoped to a one-line move |
| `journald_persistent` dropped from state | Tainted; hash already converged | Repair rides the existing `:935` target; ACs rewritten for the concurrency exposure |
| Stage 1 fails before any production mutation | **False** — three resources landed from the failed run | Recorded in Blast Radius |
| Five `terraform_data` cross-references | Five *lines*, **six edges** (`:1557` carries two); **zero** are interpolations — all are `depends_on` | Corrected |
| `MIN_SSH_PROVISIONED` bounds the SSH set | 10 vs an actual 17 — headroom of 7 | Floor raised; see Guard Contract |

## Hypotheses

Phase 1.4 fired (`SSH`, handshake-class symptom, `terraform apply` against a resource with
`provisioner "remote-exec"` + `connection { type = "ssh" }`). Per `hr-ssh-diagnosis-verify-firewall`
the L3→L7 layers are answered before any service-layer hypothesis. This plan proposes no sshd and no
fail2ban change.

**Disqualifying artifact for every network layer:** the failure string is
`SSH agent requested but SSH_AUTH_SOCK not-specified`, raised by Terraform's SSH communicator while
*resolving credentials*, before a socket is opened. No TCP connection was attempted, so **web-1 was
never touched** — which is also why no host-state repair is needed. Mechanical corroboration: the
bridge exporting `TF_VAR_ci_ssh_private_key` is at `:895`; the failing step is `:764`.

| Layer | Verified? | Artifact | Causal? |
|---|---|---|---|
| L3 firewall | Not required | Error precedes socket creation; no packet left the runner | No |
| L3 DNS/routing | Not required | `connection.host` is a literal IPv4 from state — no resolution occurs | No |
| L7 TLS/proxy | N/A | SSH path, not HTTPS | No |
| L7 sshd on web-1 | Not required | sshd received no connection; three siblings use the identical block and succeeded on the last green applies (`0d6443960`, `154302d32`, 2026-08-12) | No |
| **Terraform variable resolution** | **VERIFIED** | `agent = var.ci_ssh_private_key == null` (`server.tf:997`); bridge at `:895` runs after the failing step at `:764` | **YES — sole cause** |

## Open Code-Review Overlap

64 open `code-review` issues queried against each planned path. No overlap on the workflow or the
test file. `apps/web-platform/infra/server.tf` matched #2197 (a billing `SubscriptionStatus`
refactor whose body incidentally contains the path string) — **Acknowledge**, no overlap; the
scope-out remains open.

## Blast Radius

Today the job dies at `:764`. After the fix, five steps execute for the first time since 2026-08-12:

| Step | Line | New exposure |
|---|---|---|
| Verify tunnel ingress origins | `:800` | Hard `set -euo pipefail` gate; can red the job *after* stage 1 has mutated production |
| Sync CF Access CI-SSH token → Doppler | `:834` | Resumes production Doppler writes to `prd_terraform` |
| **CF Tunnel SSH bridge** | `:895` | Carries ADR-154 §3's fail-closed credential-liveness probe, **unexercised for 4 days — the most likely new red** |
| Stage-2 apply | `:904` | One create (`inngest_consumer_probe_install`) + one replace (tainted `journald_persistent`) |
| ARM gate | `:969` | Once the probe installs, the `inngest_consumer` arm unpauses → polls ≤230 s → rolls back → `::warning::`, because 10.0.1.40 still does not serve `:8288` (#7228 open). **+~4 min per merge apply** for the deferral window |

**Stage 1 is already partially applied on every red push** — `betteruptime_heartbeat.inngest_consumer`,
`doppler_secret.inngest_consumer_url` and the deployment policy landed from the failed run. The move
therefore *improves* stage 1 to all-or-nothing-per-run while relocating the failure boundary past
`:800`/`:834`/`:895`.

**Idempotency (favourable, and worth stating).** `triggers_replace` is a pure content hash with no
timestamp and no token, so a successful replace clears the taint and records the matching hash:
subsequent infra merges are a no-op and **the Vector agent on web-1 is not reloaded again**.
`inngest_consumer_probe_install` additionally hashes `doppler_service_token.web_probes.key`, which
stage 1 mints earlier in the same run — correct ordering, no hazard.

## Recovery

Every reachable non-green state and its lever. The `apply` job's `if:` requires
`github.event_name == 'push' || inputs.apply_target == 'manual-rerun'`.

| State | Recovery |
|---|---|
| `ssh_token_gate` skipped stage 2 (green, nothing delivered) | `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='deliver SSH stage'` |
| Bridge red at `:895` (stage 1 applied, stage 2 not) | Repair the credential per ADR-154, then the same `manual-rerun` |
| Stage-2 partial failure | Self-healing: the failed resource is tainted and replaced on the next stage-2 internal plan; the already-replaced `journald_persistent` no-ops on its converged hash |

**The comment at `:815` documents this lever incorrectly** — it says `-F reason='bootstrap'`, which
leaves `apply_target` at its default so the `apply` job does not run at all. Corrected in Phase 2.

## Implementation Phases

### Phase 1 — RED: the guard, as in-suite fixtures

Extend `plugins/soleur/test/terraform-target-parity.test.ts`. **Design constraint (load-bearing):**
the new extractor must be a **pure function taking `(workflowText)`**, mirroring the existing
`collectSshProvisioned(files)` / `extractTargets(text)` signatures, so every mutation row runs as an
in-suite fixture in CI forever rather than as a one-time hand edit. Place the new `describe` adjacent
to the existing parity block (~`:226`), not at EOF.

Also raise `MIN_SSH_PROVISIONED` from 10 to the measured 17 with a deliberate-edit contract. This is
not incidental: Guard 1 intersects against `collectSshProvisioned()`, so a silently narrowed SSH set
narrows Guard 1 too, and 8 of the 17 are unpinned by the `:236` name list — including
`inngest_consumer_probe_install` itself.

Against `main` as-is the new assertion MUST fail naming `inngest_consumer_probe_install`. Commit the
failing test first (`cq-write-failing-tests-before`).

### Phase 2 — GREEN: move the target, and correct every statement this edit falsifies

Move `-target=terraform_data.inngest_consumer_probe_install` from `:578` into the `:931-944` list.

Correct, in the same commit, the statements this move or its predecessors falsify:

| Location | Says | Fix |
|---|---|---|
| `server.tf:743-748` | "inside the per-merge `-target=` set, so it works on merge" — true of *both* stages, which is why it misled | Name the **stage**; state the resource is SSH-provisioned and belongs post-bridge. Frame the rule as **group by transport, not by feature** — `:576-578` batched all three inngest-consumer resources together and the SSH one rode along |
| `apply-web-platform-infra.yml:890` | "the **8** SSH-provisioned resources are deferred" (**operator-facing** warning text) | "every SSH-provisioned resource" |
| `:911` | "none of the **7** resources has a `when = destroy` provisioner" — **load-bearing**: it is the stated reason stage 2 carries no destroy-guard, and this PR adds a member | Re-assert for the set; verified there is **no `when = destroy` provisioner anywhere** in the infra root, so the rationale holds |
| `:918` | "internal plan against the **8** targets" | "against its target set" |
| `:815` | recovery lever `-F reason='bootstrap'` (a no-op) | `-f apply_target=manual-rerun` |
| `:440-444` `ALLOW-LIST MAINTENANCE` | Instructs "exclude server.tf SSH-provisioned resources" — added `620f682c2` (2026-05-20), three months before the violation at `0d6443960` (2026-08-12) landed six lines below it | Point at the guard as the enforcement, since the instruction alone demonstrably did not hold |
| `terraform-target-parity.test.ts:9` | "the **7** server.tf siblings" | the SSH-provisioned set |

Counts are replaced with set language wherever possible so they cannot rot again.

### Phase 3 — close the green-skip dark path (operator decision: fold in)

Add a `notify-ops-email` arm to the `apply` job gated on
`steps.ssh_token_gate.outputs.ssh_apply_skip == 'true'`, mirroring the idiom used by
`infra-validation.yml:1636`, `weakness-miner.yml:62` and `reusable-release.yml:1400`. Inputs are
`subject`, `body`, `resend-api-key: ${{ secrets.RESEND_API_KEY }}`.

The body must name what was **not** delivered and the exact recovery lever from the Recovery table —
a notification that says only "skipped" reproduces the `::warning::` problem in email form. Also add
the skip state to `Post-apply summary`, which today prints only `job.status`.

This converts the run from *green and silent* to *green and announced*. It does not make the gate
fail-closed; that option was considered and set aside as a larger change to failure semantics on a
currently-red workflow.

### Phase 4 — harden the Vector reload (operator decision: fold in)

Two changes to `terraform_data.journald_persistent`'s final `remote-exec` inline block
(`server.tf:1066-1086`). **This is a non-comment `server.tf` change** — AC6 is relaxed accordingly.

1. **Validate the rendered config before touching the live agent.** Extend the existing render-sanity
   gate with a real `vector validate` against `/opt/soleur/vector.toml`, injecting a dummy
   `BETTERSTACK_LOGS_TOKEN` for the duration of the call. The comment at `:1071-1074` declines
   validation because that variable is unset in this `remote-exec` — injecting a placeholder retires
   that objection exactly, and the comment must be rewritten to say so rather than left contradicting
   the code.
2. **Keep a restorable copy across the swap.** Preserve the current `/etc/vector/vector.toml` before
   the `install`, and restore it plus reload the agent if validation or the post-reload liveness
   check fails. Today the window between the overwrite and the detect-only `is-active` check has no
   backup, and this apply reloads onto a config that has **never executed** on this host.

Both are idempotent and run inside the same Terraform-managed provisioner; neither adds a step
outside the apply.

### Phase 5 — verify delivery, self-pulled

No SSH, no dashboard. See Acceptance Criteria.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — move one `-target=`; correct `:815`, `:890`,
  `:911`, `:918`, `:440-444`; add the `notify-ops-email` skip arm and the summary line.
- `apps/web-platform/infra/server.tf` — comment correction at `:743-748`, **and** the Phase 4
  hardening at `:1066-1086` (validation + restorable copy) with its stale comment rewritten.
- `plugins/soleur/test/terraform-target-parity.test.ts` — scoped extractor, the placement assertion,
  mutation fixtures, `MIN_SSH_PROVISIONED`, header `:9`.

## Files to Create

None.

## Guard Contract

### Guard 1 — the bridge-less stage may not target an SSH-provisioned resource

**Property.** No `-target=terraform_data.*` may appear anywhere in the `apply` job before the
`CF Tunnel SSH bridge` step.

Stated as a bright line over `terraform_data` rather than over the SSH predicate deliberately: it is
strictly stronger for this tree (17 of 18 `terraform_data` are SSH-provisioned, and nothing else in
the root has a provisioner), needs no dependency graph, and cannot be narrowed by a resource silently
dropping out of the SSH set. A future legitimately-local `terraform_data` on the push path costs one
`EXCLUSION_ALLOWLIST` entry with a stated reason — the pattern already at `:79`.

**Assembly.** Two chokepoints, both re-derived per run:

1. *The bridge-less range* — from the `apply` job's first `terraform` step to the step whose
   `uses:` is `./.github/actions/cf-tunnel-ssh-bridge`. Anchored on that **content anchor**, not on a
   step title (`cq-cite-content-anchor-not-line-number`), so a legitimate rename cannot hard-fail the
   guard. One boundary, not a header pair — this closes the hole where a `-target=` added to the
   `:764` apply step, or to any future pre-bridge step, would fall outside a plan-step-only range.
2. *The target set within it* — matched over **comment-stripped** text (the suite's existing
   `stripComments()`), and only on flag-shaped lines. Both are load-bearing: the range contains two
   prose mentions of `-target=` (`:365` a comment, `:854` a `::warning::` string) that a naive regex
   would count.

**Failure message contract.** On RED the guard must name the offending address, the step it was found
in, and the step it belongs in. In six months that string is the entire DX surface of this work.

**Mutation matrix.** Each row is an in-suite fixture asserting the guard reports RED.

| # | Edit | Why it must redden |
|---|---|---|
| M1 | Re-add `-target=terraform_data.inngest_consumer_probe_install` before the bridge | The regression itself |
| M2 | Add a *different* SSH address (`fail2ban_tuning`) while M1's address stays correctly placed | **Second offender after a compliant first** — catches a check that stops at the first hit |
| M3 | Add a `-target=terraform_data.*` to the `:764` apply step rather than the plan step | The range hole; a plan-step-only scope stays green |
| M4 | Replace the bridge step's `uses:` so the end anchor does not resolve | **The guard's own dispatch.** An unresolvable range must FAIL, never pass vacuously on zero scanned targets |

**Harness rows.**

| # | Input | Expected |
|---|---|---|
| H1 | A synthetic workflow whose pre-bridge range contains a *commented-out* `-target=terraform_data.x` and a `::warning::` string mentioning `-target=` | Must **PASS** — proves comment-stripping and flag-shape matching are live, not incidental |
| H2 | A synthetic workflow with SSH addresses only after the bridge, plus non-`terraform_data` targets before it | Must **PASS**. Non-canonical names and file, proving the guard is not diffing against the real workflow |

## Acceptance Criteria

### Pre-merge

1. `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes — each M-row asserting its
   fixture drives the guard RED, each H-row asserting PASS. (The suite is green *because* the
   mutations redden their fixtures; there is no contradiction.)
2. Reverting only the Phase 2 workflow move drives the suite RED naming
   `inngest_consumer_probe_install` against the real tree.
3. Zero `-target=terraform_data.` on flag-shaped, comment-stripped lines in the bridge-less range:
   `awk 'NR>=434 && NR<=739' <workflow> | grep -E '^\s*-target=terraform_data\.' | wc -l` → `0`
   (`wc -l` so a zero result exits 0 under `set -euo pipefail`).
4. The moved address is present in the post-bridge list. No exact count is pinned — the extractor
   re-derives, and `MIN_SSH_PROVISIONED` uses `>=` for the same reason.
5. `MIN_SSH_PROVISIONED` equals the measured 17 and the suite still discovers ≥ that many.
6. `git diff apps/web-platform/infra/server.tf` shows exactly two change sites: the comment
   correction at `:743-748` (including the `#7228` block title at `:743`) and the Phase 4 hardening
   at `:1066-1086`. No other resource is touched.
7. `actionlint .github/workflows/apply-web-platform-infra.yml` clean.
8. All seven statements in the Phase 2 table are corrected.
9. **Phase 3 arm is wired and non-vacuous:** the `notify-ops-email` step's `if:` references
   `steps.ssh_token_gate.outputs.ssh_apply_skip == 'true'`, its body names both the undelivered work
   and the `manual-rerun` recovery command, and `Post-apply summary` prints the skip state. Proven by
   a workflow-shape assertion in the parity suite, not by eyeballing the YAML.
10. **Phase 4 hardening is real, not decorative:** the validation call precedes the `install` that
    overwrites the live config; a restorable copy is taken before that `install`; and the restore
    path is reachable from both the validation failure and the post-reload liveness failure. The
    comment at `:1071-1074` no longer claims validation is impossible.

### Post-merge — agent-executed (not workflow-executed)

<!-- lint-infra-ignore start -->
These are read-only verifications the **agent** performs after merge — no human runs them, and none
mutates infrastructure. Credentials are read from Doppler `prd_terraform` (`AWS_ACCESS_KEY_ID`/
`_SECRET` for state reads, Better Stack for the log query). Named because nothing enforces them if
the session ends at merge.

11. **`terraform_data.inngest_consumer_probe_install` reaches `status != "tainted"` in state.**
    Presence alone is now FALSE-PASSING — the 14:15 apply already created the object and left it
    tainted, so `terraform state list` reports it today with the defect fully live. Assert the taint
    clears: `terraform state pull | jq '.resources[] | select(.name=="inngest_consumer_probe_install")
    | .instances[0].status'`. Clearing it requires the provisioners to actually run, which requires
    the bridge — so this is caused by this diff and nothing else.
12. **Better Stack carries rows for `SyslogIdentifier=inngest-consumer-probe` within ~4 minutes of
    the merge apply** (probe timer period 180 s; the ARM gate's own deadline is 230 s), pulled via
    `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`. This single query
    proves **both** hops: the identifier exists only in the Source 4 allowlist added by `0d6443960`
    (⇒ `vector.toml` reached web-1) and only the unit this PR installs emits it (⇒ the probe install
    landed). `hr-no-dashboard-eyeball-pull-data-yourself`.
13. The merge run's `Terraform apply (SSH-provisioned resources, over the bridge)` step has
    `conclusion == "success"`, never `"skipped"`:
    `gh run view <id> --json jobs | jq`. Distinguishes a real delivery from the green-skip.
14. **The Vector agent on web-1 is alive after the reload**, read off the `inngest-consumer-probe`
    rows in AC12 — a dead agent ships none. This is the property the Phase 4 restore path exists to
    protect, verified through the same query rather than a separate probe.
<!-- lint-infra-ignore end -->

### Context, not acceptance

These were acceptance criteria in the first draft. Each is either concurrent-session-dependent or
non-discriminating, so they are recorded as observations rather than gates
(`cq-ac-must-not-depend-on-concurrent-sessions`):

- *`journald_persistent` shows no `tainted` status* — true whether this run or a prior `manual-rerun`
  or #7543 consumed the taint.
- *The job log shows stage 2 replacing `journald_persistent`* — **fails on success** if any earlier
  apply consumed the taint.
- *The cat-deploy-state webhook reports `journald_storage.persistent=true` and non-empty
  `vector_journal_tail`* — steady-state properties, already true on any host where the provisioner
  ever succeeded, with no baseline recorded. `cat-deploy-state.sh` exposes no web-1 probe-timer
  field, so it cannot see the probe install at all.

## User-Brand Impact

**If this lands broken, the user experiences:** `main`'s infra apply stays red, so every subsequent
infra merge silently fails to reach production. The web-1 probe channel stays dark, so a host outage
goes undetected for as long as the twelve-day dark-host outage this probe exists to catch.

**If this leaks, the user's data is exposed via:** no new exposure surface. The change moves a
`-target=` line, corrects comments, and adds a test. The credential involved
(`TF_VAR_ci_ssh_private_key`) is ephemeral per run; this change *narrows* where it is required.

**Brand-survival threshold:** aggregate pattern — the failure degrades detection and delivery across
the fleet rather than exposing or breaking any single user's data. No `requires_cpo_signoff`.

## Observability

```yaml
liveness_signal:
  what: "terraform-target-parity suite — runs on EVERY pull_request, unconditionally (no paths filter)"
  cadence: per-PR and per-merge
  alert_target: "the synthetic `test` required check (branch-protection ruleset)"
  configured_in: ".github/workflows/ci.yml → job `test-bun` (:667, `bash scripts/test-all.sh bun` at :698) → scripts/test-all.sh:1197 `run_suite \"plugins/soleur\" bun test plugins/soleur/`"
error_reporting:
  destination: GitHub Actions job failure; the apply job's own failure annotation
  fail_loud: true
failure_modes:
  - mode: "an SSH-provisioned address is placed before the bridge again"
    detection: "Guard 1 placement assertion (M1/M2/M3)"
    alert_route: CI red on the PR, before merge
  - mode: "the guard is narrowed to scan nothing, or the SSH set silently shrinks"
    detection: "M4 dispatch floor + MIN_SSH_PROVISIONED raised to the measured 17"
    alert_route: CI red on the PR
  - mode: "ssh_token_gate skips the bridge AND stage 2 AND the ARM gate; run is GREEN having delivered nothing"
    detection: "Phase 3 notify-ops-email arm gated on ssh_apply_skip == 'true'; Post-apply summary prints the skip state; AC13 asserts the step concluded `success`, never `skipped`"
    alert_route: "ops@jikigai.com via Resend, naming the undelivered work and the manual-rerun recovery command"
  - mode: "the Vector agent dies on reload, darkening all web-1 observability"
    detection: "Phase 4 validation before the live overwrite; restore-and-reload on validation or liveness failure; AC14 reads liveness off the inngest-consumer-probe rows"
    alert_route: "apply fails loud with the previous config restored"
logs:
  where: GitHub Actions run logs; Better Stack for the web-1 `inngest-consumer-probe` identifier
  retention: 90 days (Actions); Better Stack per plan retention
discoverability_test:
  command: "bun test plugins/soleur/test/terraform-target-parity.test.ts"
  expected_output: "all tests pass; the placement describe-block reports a non-zero scanned-target count and a non-zero SSH-provisioned count"
```

**The green-skip dark path — closed by Phase 3.** When `CI_SSH_ACCESS_TOKEN_ID` is absent from
Doppler, `ssh_token_gate` sets `ssh_apply_skip=true` and the bridge (`:895`), stage 2 (`:904`) **and**
the ARM gate (`:980`, whose `always()` guards against a bridge *failure*, not against the *skip*) all
skip. Before this plan the run was green, nothing was delivered, no heartbeat armed, and
`Post-apply summary` printed only `job.status`. This repo had already ruled on that shape in
`scheduled-terraform-drift.yml`: *"A named `::error::` alone is not a channel."* Phase 3 gives it a
real channel — an ops email naming the undelivered work and the recovery lever — rather than
deferring it to an issue.

The gate remains a **soft** skip by design: making it fail-closed would change failure semantics on a
workflow that is currently red, and was set aside as a separate decision rather than bundled here.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** A CI-workflow placement fix, comment corrections, and a test extension on an
already-provisioned surface. No new infrastructure, vendor, store, schema, or auth surface. The one
production consequence — replacing a tainted `terraform_data` over the existing bridge — is that
resource's own designed delivery mechanism.

Product/UX Gate: not applicable — no file in `## Files to Edit` matches a UI-surface term or glob.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-154** (`repair-the-credential-channel-not-the-host`). Its §3 requires probing the
transport before a destroy, implemented as the final step of the `cf-tunnel-ssh-bridge` composite —
whose contract is *step position*: "a caller that has invoked the bridge has necessarily passed the
gate." **That argument structurally cannot reach a stage that never invokes the composite.** The
amendment generalises §3 from *"probe the channel before using it"* to *"a stage that has no channel
must not be able to plan over it,"* and moves enforcement from runtime to build time.

Amending rather than forking: amendments are the established pattern here (ADR-071, ADR-103, ADR-179,
ADR-184 …), and ADR-154 is the same credential channel at the same host — a separate ordinal would
fragment one subject. The amendment must also carry the **"open the bridge before stage 1" rejection**
into rejected-alternatives; it is a genuine architectural rejection that currently lives only in a
plan that gets archived. Reciprocal pointers: ADR-154's Related gains the test file, and the guard's
header gains a one-line `See ADR-154`.

Also cite ADR-154's already-accepted AP-002 deviation (web-1 remains a mutated host) rather than
marking Infrastructure "skipped".

### C4 views

**Corrected 2026-08-16 — the original "no C4 impact" finding was right for the original scope and
became FALSE when Phase 3 was folded in.** Recorded rather than quietly amended, because the way it
went stale is the same defect class this PR exists to fix.

The enumeration against all three of `model.c4`, `views.c4`, `spec.c4` still holds for the *element*
set: no external human actor added; no external system/vendor added (CF Tunnel and Hetzner Cloud
already modeled, relationships unchanged); no container or data store added; no actor↔surface access
relationship changed.

What changed is a **count embedded in an existing edge's prose**. The `github -> resend` edge said
*"one of twelve Resend emitters under .github/"*, and Phase 3's `notify-ops-email` arm made it
thirteen. `plugins/soleur/test/c4-count-parity.test.sh` derives that number
(`grep -rlE 'api[.]resend[.]com|notify-ops-email' .github/workflows/ .github/actions/ | wc -l`) and
failed the scripts shard — a count in prose going stale the moment its set grew, which is precisely
the class the Phase 2 comment sweep addresses. Corrected to thirteen, `model.likec4.json` regenerated,
and the guard's word→int map extended past `twelve` (it fails CLOSED on an unmapped word rather than
passing silently, which is why it surfaced at all).

**Process note worth keeping:** the C4 gate was evaluated once, at plan time, against the original
scope. Folding in a new phase after that assessment invalidated it, and nothing re-ran the gate — the
scripts shard caught it. A scope widening should re-trigger the plan-time gates it could falsify.

## Infrastructure (IaC)

No new infrastructure. The plan relocates one `-target=` flag between two existing stages of an
existing Terraform root and corrects comments. The on-host mutation it enables is ADR-154's
already-accepted AP-002 deviation, not a new one. Every step executes inside the Terraform apply the
workflow already runs; no step is performed outside it.

## Encryption Posture

Skipped — no persistent store and no new cross-component connection. The SSH channel used by stage 2
already exists and is unchanged.

## Test Scenarios

1. Extended suite against `main` at `4a7e5cb08` → placement assertion fails naming
   `inngest_consumer_probe_install`.
2. Apply the Phase 2 move → suite green.
3. M1–M4 fixtures each drive the guard RED; H1–H2 each PASS.
4. `MIN_SSH_PROVISIONED = 17`; removing one `connection` block from any of the 17 drives the floor RED.
5. Post-merge AC9–AC11, all self-pulled.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The moved resource fails in stage 2 | It connects to `hcloud_server.web["web-1"]` (`server.tf:767-769`) — the same host as its three siblings, explicitly not 10.0.1.40. All three siblings are present in state, so stage 2 demonstrably provisions this shape on this host |
| The move drags a new resource into stage 2 | Verified against live state: `doppler_service_token.web_probes` and `hcloud_server.web["web-1"]` already exist. `hcloud_server.web["web-1"]` enters the closure via every `connection.host` interpolation, but `ignore_changes = [user_data, ssh_keys, image, placement_group_id]` (`server.tf:467`) covers the replace triggers — in-place update is the realistic worst case |
| **The Vector reload window is unguarded** | **Closed by Phase 4**, on the operator's decision to harden rather than defer. The provisioner previously overwrote the live `/etc/vector/vector.toml` with no backup, reloaded, then performed a detect-only liveness check — the render gate protects the *render*, not the *reload*, and this apply reloads onto a config that has **never executed** (Property 4). The resource's own comment names the stakes: "a dead vector on web-1 darkens ALL host observability." Phase 4 adds real validation before the live overwrite and a restorable copy across it. Note this makes `server.tf` a non-comment edit, relaxing the original AC6 |
| Phase 4's validation false-fails and blocks a legitimate apply | The stated reason validation was omitted is the unset `${BETTERSTACK_LOGS_TOKEN}` interpolation; a dummy value retires exactly that. The mutation to prove it is real: feed a deliberately broken render and confirm the apply fails **with the previous config still live**, which is the property the change exists to buy |
| A prior apply consumes the taint before this merge | Delivery still occurs (that apply replaces and provisions). Only the *attribution* criteria are affected, which is why the taint-based checks were demoted to context and acceptance rests on `state list` and the Better Stack identifier |
| Green run that delivers nothing (`ssh_token_gate` skip) | AC11 detects it for this merge. No standing detector — recorded as a named gap and a scope decision |
| Merge conflict with PR #7543 | #7543 adds a job near `:5472` and a comment near `server.tf:1082`; this edits `:578`, `:931-944`, `server.tf:743-748` and several comments. Non-adjacent. The operator accepted this risk |
| The bridge reds at `:895` after stage 1 applied | The most likely new red — the ADR-154 §3 credential probe has been unexercised for 4 days. Recovery table above covers it |
