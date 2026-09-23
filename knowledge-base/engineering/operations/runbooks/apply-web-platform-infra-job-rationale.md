---
title: apply-web-platform-infra.yml job rationale (relocated workflow comments, #8361)
date: 2026-09-19
owners: engineering/ops
category: infrastructure
tags: [ci, github-actions, workflow, apply-web-platform-infra, rationale]
applies_to:
  - .github/workflows/apply-web-platform-infra.yml
related_issues: [8361]
---

# `apply-web-platform-infra.yml` job rationale

This file exists because GitHub refuses to start any run of a workflow file larger than 512,000 bytes
(zero jobs — conclusion `startup_failure` on a `workflow_dispatch`, plain `failure` on a push — and
no message; #8361 measured it, and the bracket is recorded in the gate test's header).
`.github/workflows/apply-web-platform-infra.yml` crossed that limit on 2026-09-19, and roughly half
of its bytes were comments. Each section below is the design rationale that used to sit as a
comment block above the named job (or step) in that workflow, moved here with the `#` prefix
stripped and otherwise verbatim — with one exception: two sentences in `## ci_ssh_token_replace`
(the ones now reading "a laptop-local ... outside CI — i.e. exactly the out-of-band infra step")
had their human-actor wording replaced so the file passes `scripts/lint-infra-no-human-steps.py`,
which scans runbooks but not `.github/`; `git show f64b0ebc2:.github/workflows/apply-web-platform-infra.yml`
holds the original. The
workflow keeps the block's first line, any comment line a test suite anchors on (its pointer says
so when it does), and one pointer of the form
`# Rationale: knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md §<job_id>`.
Section headings are the job ids verbatim (a step-level block is `## <job_id>/<step name>`), so the
pointer's `§<job_id>` is an exact anchor. Line-number citations inside the prose are as of the
commit that wrote them and drift the way ADR-116 already accepts. The gate that keeps the workflow
under the limit is `plugins/soleur/test/workflow-file-size.test.ts`; the decision is ADR-231. If a
RED run of this workflow shows zero jobs, start at
`knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md`.

## notify-apply-failure

--- #7586: a non-green apply run reaches a channel ----------------------------------------
Before this job, the file had exactly ONE `notify-ops-email` call site — the `#7539` step
inside `apply`, gated on `ssh_apply_skip == 'true'`. That is a GREEN-SKIP predicate: it fires
when the run completed green having delivered nothing, and it cannot fire when the run goes
red. Nothing else covered the gap: no `workflow_run` watcher names this workflow, it has no
`sentry-heartbeat` call site, and GitHub's built-in failed-run email routes to the pushing
actor, which `reusable-release.yml` already documents in-repo as "frequently a GitHub App
identity, i.e. nobody". Measured on 2026-08-20: 23 `failure` + 1 `cancelled` of the last 60
`main` runs, none of which notified anyone, while the post-mortem for this same workflow
records detection as "by looking at the Actions tab" after three days of unapplied
production infrastructure.

A separate JOB, not the sibling `if: failure()` step the issue proposed (Cut List C1). A job
that exceeds `timeout-minutes` concludes `cancelled`, and `failure()`-gated steps are SKIPPED
on that path, so a step arm is structurally silent on exactly the #7587 path. A downstream job
reads `needs.apply.result` regardless.

CITATION, corrected (#7661 G5). Run 32168637847 is real and it measures the FIRST half: Main
Health Monitor ran 70m43s against `timeout-minutes: 70` and concluded `cancelled`, and its
`always()` siblings still ran, consuming 43 s past the timeout instant. It does NOT measure
the second half — the step it was cited for, `Create issue on failure`, is gated
`if: ${{ !cancelled() && … }}`, and that run contains no `failure()`-gated step at all.

THE TWO LOAD-BEARING PREMISES, MEASURED (#7661 G5). Both were asserted from documentation; both
were then checked against this repo's own run history, and each is recorded with exactly what
its evidence covers and what it does not.

  (a) A downstream `always()` JOB runs when an upstream job is CANCELLED.
      VERIFIED. `infra-validation.yml`, runs 32272435663 / 32294251707 / 32296436704: the job
      `validate (apps/web-platform/infra)` concluded `cancelled` after 6h, annotated "The job
      has exceeded the maximum execution time of 6h0m0s / The operation was canceled", and the
      downstream `infra-validate-required` (`needs: [detect-changes, validate]`, `if: always()`)
      concluded `failure`, NOT `skipped` — its own log printed `RESULT: cancelled`, so it both
      ran and read the cancelled result. NARROW SPOT: that job declares no `timeout-minutes`,
      so the ceiling that cancelled it was GitHub's 6h platform default. That the two ceilings
      are one code path is separately measured — `deploy-script-tests` (`timeout-minutes: 14`,
      runs 32299138340 / 32299155123 / 32300783446) emits the identical annotation with a
      different number, concludes `cancelled`, and every sibling job after it ran to `success`.
      NOT IN HISTORY: a job cancelled by its DECLARED `timeout-minutes` that is literally named
      in the `needs:` of the `always()` job that ran. The two halves are measured; the single
      run joining them is not.

  (b) A STEP exceeding its own `timeout-minutes` concludes `failure` (not `cancelled`) and the
      job carries on. VERIFIED, in two halves from two workflows.
      Half 1 — `web-platform-release.yml`, runs 32293304541 (job 96217488153) and 32283291347
      (job 96183288475): step "Install psql", `timeout-minutes: 5`, logged "The action 'Install
      psql' has timed out after 5 minutes", API step conclusion `failure`, and the JOB was not
      cancelled — it ran on through `Post Run actions/checkout` and `Complete job`, both
      `success`. Half 2 — `reusable-release.yml`'s `Tear down cloudflared registry bridge`
      (`if: always()`) concludes `success` after a failed sibling step, across ~30 runs
      (30913993850, 31379319736, 31751479655). NOT IN HISTORY: a step-level TIMEOUT with an
      `if: always()` sibling behind it in the same job. Half 1 gives the conclusion, half 2
      gives the continuation; no single run gives both.

  Measurement note that feeds the ladder: a timeout kill overshoots its declared ceiling by
  13–31 s of API wall clock (313 s against 300, 859–930 s against 840, 4243 s against 4200).
  The job ceiling's 69 s of slack over the step ceiling absorbs that; do not shrink it below it.

This job's HEADER COMMENT is inside `extractJobBlock(wf, "apply")` — that helper resets only
on `/^ {2}[A-Za-z0-9_-]+:/` and `#` is not in that class, so 2-space-indented comment lines
never close a job block (#7661 G4; the first version of this sentence claimed the opposite).
The `#7539` guard survives anyway, for a different reason: its `extractStep` requires
`^ {6}- name:` and takes the FIRST `/Notify ops/` STEP, which is still the one in the apply
job. Guards that key on the apply block's TEXT must account for this header being in it.

RESIDUAL, RE-DERIVED AND LARGER THAN FIRST STATED (#7654 A3). The first version of this
paragraph read "~24/60 to ~1/60", which silently assumed all 23 failures were pushes. Counted
properly over the same window (`gh run list --workflow apply-web-platform-infra.yml --branch
main --limit 60`, 2026-08-20): 27 push/success, 18 push/failure, 9 dispatch/success,
5 dispatch/failure, 1 dispatch/cancelled — 24 non-green.

This job covers the 18 push failures. It does NOT cover:

- the 5 dispatch failures, because every one of them was a NON-`manual-rerun` target
    (registry_store_restore, registry_pull_path_gate x2, registry_luks_recut,
    registry_host_replace) and the trigger clause below admits only `push` or `manual-rerun`;
- the 1 dispatch cancellation (run 32293338273, a `vector-redeliver` dispatch), for the
    same reason AND because a RUN-level cancellation cancels queued jobs too, so an `always()`
    job never starts. (A concurrency supersede cannot happen here: the group declares
    `cancel-in-progress: false`.)
Post-PR residual is therefore 6/60, not ~1/60.

Note also that `preflight` carries no `if:` and no `needs:`, so it runs on EVERY dispatch
target while no dispatch job `needs:` it — a red `preflight` reds the run while the target job
goes green, and this job is silent on all 13 non-`manual-rerun` targets. Widening the trigger
clause to every dispatch target means widening `needs:` to jobs that do not run on a push,
which changes the predicate's shape; it is deliberately NOT done here, and the uncovered set
is named above rather than glossed. The covering mechanism for BOTH residuals -- the 5
non-`manual-rerun` dispatch failures and the 1 run-level cancellation -- is a `workflow_run`
watcher, which does not exist for this workflow. It is tracked by #7662 (a default
notification posture for production-affecting workflows), filed at ship time from the #7642
plan's `## Deferrals`. `workflow_run` fires on `completed` INCLUDING `cancelled`, which is why
it reaches the run-level cancellation that no in-run mechanism can: when a run is cancelled,
its queued jobs are cancelled with it, so an `if: always()` job never starts at all.

Asserted by `describe("apply-web-platform-infra has a failure channel")` in
`plugins/soleur/test/terraform-target-parity.test.ts`, which EVALUATES the predicate below
over {success,failure,cancelled,skipped}² × {push,manual-rerun,other} rather than
string-matching it, and pins `needs:` in the same test so shrinking the array cannot shrink
the obligation.

## vector_redeliver

See also: knowledge-base/engineering/operations/runbooks/vector-redeliver.md

#7542 — deliver a `vector.toml` change to web-1 WITHOUT riding unrelated pending drift.

WHY THIS ARM EXISTS. `vector.toml` is hashed into the `triggers_replace` of
terraform_data.journald_persistent (server.tf:987-990), so a Vector config change reaches
the running host ONLY by replacing that resource. Before this arm the sole route was the
merge-triggered push apply, which grades the WHOLE plan at once — so a delivery that is by
itself routine could not land while unrelated pending drift sat in the same plan. This arm
gives the delivery its own dispatch, scoped to that one address.

── THE REAL GATE CHAIN (read this before adding another guard) ────────────────────────────

  1. AUTHORIZATION is the menu-ack dispatch itself (`hr-menu-option-ack-not-prod-write-auth`).
     A non-technical operator selecting this target from the dropdown IS the human approval
     for the production write. There is no commit trailer on this path — `[ack-destroy]`
     is structurally unavailable, because the push guard reads
     github.event.head_commit.message, which is EMPTY on workflow_dispatch.
  2. `confirm=REDELIVER-VECTOR` is a TYPO-GUARD ONLY, not the authorization. It exists so a
     token typed for a host birth or a credential destroy cannot fire a delivery. The token
     is recorded HERE and in knowledge-base/engineering/operations/runbooks/vector-redeliver.md
     — deliberately NOT in the `confirm` input's description (:112 keeps that field a
     pointer, because the string accreted one clause per target and no operator reads it).
  3. The MECHANICAL protection is the sourced plan gate below
     (tests/scripts/lib/vector-redeliver-gate.sh) — the same bytes
     tests/scripts/test-vector-redeliver-gate.sh exercises. It reads the SAVED PLAN, not the
     `-target=` flags, because `-target` is transitive and is a request, not a bound: the
     real closure of this one target is ~9 addresses (both hcloud_server.web entries,
     hcloud_ssh_key.default, hcloud_placement_group.web_spread, the CF tunnel +
     random_id.tunnel_secret, doppler_service_token.web_probes, hcloud_volume.workspaces[*],
     tls_private_key.ci_ssh). Grading the plan is what makes that closure safe.
  4. `environment: web-platform-infra-apply` is a MAIN-BRANCH PIN, not merely a reviewer
     click — and for this job it is the load-bearing one. `workflow_dispatch` runs the
     SELECTED REF's workflow AND its scripts; this job sources its gate from
     ${GITHUB_WORKSPACE} and runs root `remote-exec` on web-1, so without the environment's
     `deployment_branch_policy` (web-host-birth-environment.tf:63-78) anyone who can
     dispatch could point the run at a branch carrying a neutered gate — and the reviewer
     prompt shows a branch NAME, not a diff. A first-step `github.ref` guard was considered
     and rejected as strictly weaker: the guard would itself be supplied by the branch it is
     meant to police.
     THE PIN IS LIVE — measured 2026-08-16, not inherited. The environment carries
     protection_rules ["required_reviewers","branch_policy"] and exactly one deployment
     branch policy, "main". `github_repository_environment_deployment_policy.web_platform_infra_apply_main`
     does still show as a pending CREATE in the push plan, but that is a STATE fact
     (Terraform has not adopted it yet), NOT a liveness one. An earlier revision of this
     comment inherited the plan's "the pin is among the changes the wedge is holding" and
     read it as "the pin may not be protecting you" — the opposite of the measurement, and
     understating a security control is the more dangerous direction of that error. When
     the question is whether the pin protects a dispatch RIGHT NOW, read the environments
     API, never the terraform plan.

── STEP ORDER IS LOAD-BEARING ─────────────────────────────────────────────────────────────
The CF Tunnel SSH bridge MUST precede the plan. It writes TF_VAR_ci_ssh_private_key into
$GITHUB_ENV (cf-tunnel-ssh-bridge/action.yml:199-203); variables.tf:468-472 defaults that to
null and server.tf:992-998 resolves `agent = var.ci_ssh_private_key == null`, so a plan
produced BEFORE the bridge bakes agent = true and looks for an ssh-agent on an agent-less
runner. `terraform apply <savedplan>` uses the values recorded in the plan file and accepts
no variable input, so a later export is inert. This is the only job in this file that
combines a saved plan with the bridge, and that is why.

── NO-OP IS A SUCCESS SHAPE, NOT A FAILURE ────────────────────────────────────────────────
Zero entries at the allowed address means the desired state is ALREADY REALISED — the arm's
own success condition, one dispatch later. Legitimate ways to land there: a re-dispatch to
re-verify, the push apply delivering first, a cancelled run after state was updated. The
gate returns 0 with outcome=noop, the apply is SKIPPED by a positive verdict rather than by
a failure, and "nothing to redeliver" is written to the step summary. (The plan's F12 said
the no-op should also skip the BRIDGE; F10 then moved the bridge ahead of the plan, so by
the time the verdict exists the bridge is already up. The `if: always()` teardown covers it.)

## git_data_host_create

See also: knowledge-base/engineering/operations/runbooks/git-data-birth.md

── #6977 — the git-data BIRTH path ───────────────────────────────────────────────

CONFIRM TOKEN: BIRTH-GIT-DATA. (The confirm input's own description deliberately does
not enumerate per-target tokens — it accreted one clause per target until no operator
read it. The token lives here and in the runbook.)

WHY THIS JOB EXISTS. Until 2026-09-14 `soleur-git-data` was declared in IaC and had
never existed: an authenticated `terraform state list` returned 201 addresses and ZERO
git-data members (it was born by this job on run 34836141887 / replaced by 34861860722).
No automated route could create it: git-data-host-replace requires
actions ⊇ {delete,create} so a first CREATE fails its server_replaced arm, its
luks_passphrase_touched arm fires on a create too, and its 5-member allow-set cannot
hold an 18-address birth fan-out. The only remaining route was an untargeted apply
from an operator laptop — no destroy-guard, no stock preflight, and a plan of that
shape taken 2026-07-27 carried NINE destroys. That was a standing violation of
hr-all-infrastructure-provisioning-servers.

A NEW DISPATCH JOB INHERITS NOTHING (ADR-145). The per-PR `host_creates > 0` HALT is
a separate inline copy in the `apply` job whose `if:` is mutually exclusive with this
one, so for this path the sourced birth gate is the ONLY check.

THIS JOB CARRIES THREE MECHANICAL INTERLOCKS. ALL THREE CURRENTLY RELEASE.

An earlier version of this header read "STILL HELD, BY TWO GATES". That inverted the
moment the rung-2 boot evidence merged, which is exactly the drift a comment asserting
a live verdict invites -- so it now states what the gates ARE rather than what they
currently answer. What held the route before the birth was the runbook's
DO-NOT-DISPATCH banner (cleared by PR #8128, merged 2026-09-14) and the environment approval;
the approval is the remaining hold, and it
reports prevent_self_review:false with a single reviewer (declared nowhere in this
repo's Terraform, so that is the provider default rather than a chosen setting).

(1) The birth-readiness (sentinel) interlock RELEASED as of #6982. It held because
cloud-init-git-data.yml emitted nothing off-host and nothing in its boot path failed
closed, so a green apply and a dark host were indistinguishable and ADR-145's readiness
gates had no analogue here (nothing to poll). #6982 shipped the emitter:

  grep -vE '^[[:space:]]*#' apps/web-platform/infra/cloud-init-git-data.yml \
    | grep -c 'sentry_dsn'          # => 2 (was 0; the gate's sentinel, non-comment)

(2) The RUNG-2 REHEARSAL interlock HELD until the evidence landed. Releasing (1)
retired the only mechanical hold on this route, which left the birth held by the
runbook's DO-NOT-DISPATCH banner alone — prose, in a different file from this button, and an earlier revision of THIS
COMMENT said "the interlock is released", inviting the dispatch the banner forbids.
ADR-149's own Alternatives table rejects a capability held only by prose. So the rung-2
precondition is now enforced here: git_data_rung2_rehearsal_gate requires committed boot
evidence hash-bound to the template being dispatched, and re-holds automatically on any
later edit to cloud-init-git-data.yml.

Rung 2 — booting the rendered template once on a throwaway host outside the
hcloud_server.git_data address — is carried as #7025's own precondition and was
deliberately NOT inherited as a pass from #6982's rung-1 container rehearsal. See
ADR-149's release checklist and its #6982 disposition table for what each item
delivered. The evidence landed (PR #8126, run 34768256297) and the banner was
cleared (PR #8128).

DELTAS FROM web_host_create, each evidenced rather than inherited:
  • SINGLETON, not a for_each map — no host key input, and the gate's `def allow:`
    takes no key argument.
  • NO image digest pin. git-data has no image var and no host_scripts_content_hash,
    so the amd64 assert, the GHCR login, the digest freeze and the coherence preflight
    have no analogue. Omitted rather than faked.
  • A LUKS BOOT DEPENDENCY the web host lacks (P12/P13).
  • NO firewall-attachment fan-out risk: hcloud_firewall_attachment.git_data is
    `server_ids = [hcloud_server.git_data.id]`, a direct singleton, unlike the web
    fleet's for-loop. No other hcloud_server can enter this plan's closure, which is
    why the gate's reboot arm is a backstop here rather than live coverage.

## web_host_create

See also: knowledge-base/engineering/operations/runbooks/web-host-birth.md

Selected by `-f apply_target=web-host-create -f web_host_key=<key>` (#6730, ADR-145).
THE web-host BIRTH path — the one automated route allowed to create an
hcloud_server.web, where every other route HALTs on host_creates > 0.

THE HALT IS INVERTED HERE, NOT REMOVED. "must never create a host" becomes "must
create exactly the one host that was authorized, and nothing else". That distinction
is the whole design: weakening the HALT globally would reintroduce #6416 (a host born
via the per-PR apply gets its server but not its hcloud_server_network attachment, so
it comes up with no private IP and, transiently, no firewall). A NEW DISPATCH JOB
INHERITS NOTHING — the per-PR HALT is a separate inline copy in the `apply` job whose
`if:` is mutually exclusive with this one — so the sourced web_host_birth_gate is not
defense-in-depth behind an existing check. For this path it is the ONLY check.

THE -target SET IS THE WHOLE PER-HOST FAN-OUT, and each member is there for a reason
that has already cost an incident or is one bad boot away from doing so:
  • hcloud_server.web / hcloud_server_network.web  — the server WITHOUT its private
    NIC is #6416 exactly.
  • hcloud_volume.workspaces + attachment          — /mnt/data; server.tf's user_data
    interpolates the volume id, so the host cannot even render without it.
  • cloudflare_record.app                          — `content =
    hcloud_server.web["web-1"].ipv4_address` (dns.tf). `-target` is transitive UPSTREAM
    only, so this DEPENDENT never enters the plan on its own: a web-1 birth would
    otherwise finish green with app.soleur.ai still resolving to the dead host's IP, and
    the runbook's own verification step would fail with nothing explaining why. On a
    web-2 birth it plans as a no-op (web-1's address is unchanged), so including it is
    free there and load-bearing for the case the path is documented to serve.
  • hcloud_firewall_attachment.web                 — a SINGLETON over
    `[for h in hcloud_server.web : h.id]`. hcloud provider 1.63.0 documents that this
    resource (unlike hcloud_server.firewall_ids) does NOT attach before first boot, so
    omitting it means the new host is briefly reachable with no firewall. Including it
    is what drags every OTHER web host into the plan — which is why the gate carries a
    reboot arm and an allow-set: web-1 must come along as a no-op or not at all.
  • the 4 web-probe resources                      — web-probe-envwrite.sh resolves
    WEB_NIC_GUARD_URL_<KEY> / WEB_ZOT_CONSUMER_URL_<KEY> from Doppler ON the fresh
    host, so omitting them births a host whose probes have no URL to beat to. Including
    them REGISTERS the heartbeats; it does NOT arm them — web-probe.tf ships both
    `paused = true` + `ignore_changes = [paused]`, and the only unpause path is the
    `Arm web-host probe heartbeats` step in the `apply` job (ADR-117: measure a real beat
    before arming). So this target set is necessary-but-not-sufficient for coverage, and
    the born host is unmonitored until a later merge-to-main apply arms it. That is a
    deliberate consequence of ADR-117's measure-then-arm ordering, not an oversight —
    but it is disclosed in the Dispatch summary rather than left for the operator to
    discover from a silent host.
proxy-TLS is DELIBERATELY ABSENT: those resources are singletons, not a
`for_each = var.web_hosts` fan-out (verified against proxy-tls.tf), so there is no
per-host member of them to birth.

ADR-128's five carried-forward MUSTs are implemented as named steps below: R1 (DSN
non-empty BEFORE any create), R2 (surface the fresh host's boot telemetry), R3 (EU
data plane), R4 (client-side filter — the events endpoint ignores `message:`), R5
(`if: always()`, so a green apply still proves the probe fired).

A GREEN APPLY IS NOT A GREEN BOOT. `runcmd` is once-per-instance: a host that aborts
at stage=verify is not repairable by a reboot, only by replacement. That asymmetry is
why the coherence preflight is mandatory and PRE-apply, and why R2 exists at all.

## registry_luks_recut

See also: knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md

Selected by `-f apply_target=registry-luks-recut` (#6929, ADR-096 amendment 2026-07-24).

THE SANCTIONED VEHICLE FOR THE GUEST-SIDE-LUKS RECUT, and the removal of a live footgun.
The 2026-07-24 change made hcloud_volume.registry a RAW device: cloud-init discriminates on
`blkid TYPE` — "" (fresh) -> luksFormat; crypto_LUKS -> reuse; ANY OTHER TYPE -> FATAL.
`registry-host-replace` cannot perform a recut: it PRESERVES the volume. Forgetting the
`-replace` on the volume is likewise not a recut. (History, including the pre-2026-08-10 plaintext
FATAL: the header of `tests/scripts/lib/registry-luks-recut-gate.sh`.) This job performs the recut as ONE
ATOMIC APPLY, `-replace`ing the volume + its attachment + the server TOGETHER, so a fresh raw
volume meets the empty arm and gets luksFormatted; zot then re-fills from GHCR.

NO `environment:` — like all four host-replace/migrate jobs (only workspaces-luks-recut has
one, because it touches sole-copy /mnt/data). An `environment:` naming an UNPROVISIONED
GitHub environment silently AUTO-APPROVES (DP-11 F8), so declaring one here would add the
APPEARANCE of a reviewer gate without the gate. Authorization is the menu-ack dispatch plus
the typed confirm; CODEOWNERS gates this file.

NO job-level `concurrency:` — it inherits the workflow-level
`terraform-apply-web-platform-host` group, which is the verified-complete serializer for the
LOCK-LESS R2 backend (`cancel-in-progress: false` also prevents a cancel mid-destroy).

`timeout-minutes: 30` is load-bearing: this job holds that fleet-wide apply mutex, so
GitHub's 360-minute default would let a hung poll block EVERY merge-apply for six hours.
The D11 poller's own bound (150s + 480s) is strictly below it so its diagnostic wins over an
opaque cancellation.

THAT 30 IS ONLY A DERIVED NUMBER BECAUSE THE REHEARSAL IS NO LONGER INSIDE IT (#7277). The
multi-GB A2 rehearsal used to run here, ahead of the apply, with an UNMEASURED wall-clock —
so a rehearsal that succeeded slowly ate the post-destroy window and could push a timeout
into `terraform apply` or D11, where a timeout is a cancellation and therefore catastrophic.
It now lives in `registry_pull_path_gate`, which this job `needs:`. The clock below starts at
the apply again, which is what makes the D11 derivation valid.

Note honestly what did NOT change: the `concurrency` group is WORKFLOW-level, so the split
released no mutex. Worst-case fleet-wide apply block is now the SUM across the gate job, this
job, and `registry_store_restore`.

2026-08-20 (#7587, corrected #7657): that same workflow-level accounting moved on the OTHER
side of the file. The per-merge `apply` job went 15 → 41 and gained a `notify-apply-failure`
sibling at 5, so the routine-merge arm of this group now has a run-level worst case of
preflight 1 + apply 41 + notify 5 = 47 min rather than 15. (`preflight` is chained by `needs:`
and was uncounted in the first version of this paragraph, which said 40 for what was then 41.)
This job is dispatch-only and runs by deliberate action — but "deliberate" governs when a
dispatch is ISSUED, not whether a merge apply is already in flight, and the measurement below
says it queues: over 80 completed runs of the shared group across 35 days the overlap histogram
was {0 concurrent: 69, 1 concurrent: 11}, i.e. 11 of 80 runs DID queue. Observed queue depth
never exceeded 1 and the longest run took 23.7 min. Priced consequence, because it lands on the
dispatches issued during an outage: worst-case wait for an emergency dispatch stuck behind a
routine merge apply moves from 16 min to 47 min, and this group covers `ci_ssh_token_replace`
— described in this same file as "the ONE arm that can run while the SSH bridge is dead".

## inngest_volume_recut

─── inngest Redis AOF volume recut: plaintext ext4 -> LUKS (#7695) ────────────
Selected by `-f apply_target=inngest-volume-recut`. A scoped
`terraform -replace=hcloud_volume.inngest_redis` (+ its attachment) that DESTROYS the plaintext
ext4 AOF volume (soleur-inngest-redis-store) and creates a RAW replacement with the same name,
which cloud-init-inngest.yml's five-arm blkid discriminator then luksFormats on the next boot.

THIS IS THE ONE DISPATCH THAT DESTROYS PRODUCTION SCHEDULER STATE, and it is the only apply_target
in this file that must PROVE something about the WORLD before it plans. Five layers, and the
first is the only authorization:

  1. `environment: inngest-cutover` — required-reviewer gate. The SOLE human authorization
     (DP-11 F8); the reviewer set is terraform-backed at inngest-arm-write-token.tf and is
     asserted non-empty by its own check. The whole job waits before ANY step runs.
  2. `confirm=RECUT-INNGEST-VOLUME` — a TYPO-GUARD, not authorization. Distinct from every other
     confirm literal in this file, so a token typed for one target cannot authorize another.
  3. `expected_inngest_volume_id` — the operator names the physical volume. Pinned twice, against
     two independent sources: the LIVE Hetzner attachment (Guard 2 / G17) and the PLAN's
     `.change.before.id` (Guard 1). They can disagree — a plan is a projection of state, and
     state can be wrong about the world — and it is the world that gets destroyed.
  4. Guard 1 (tests/scripts/lib/inngest-volume-recut-gate.sh) — the plan destroy-guard.
  5. Guard 2 (tests/scripts/lib/inngest-host-dark-gate.sh) — the layer absent from the workspaces
     template: twenty predicates proving, from ONE probe row on the CURRENT boot plus four
     synchronous dispatch-time re-reads, that the host is dark and the store is measured empty.
     It runs BEFORE the plan, so a serving host costs nothing and reaches no terraform.

NO [ack-destroy] BYPASS, NEVER AUTO-EXECUTED, NEVER CHAINED. This job dispatches nothing and is
dispatched by nothing: it is reachable only from the menu (hr-menu-option-ack-not-prod-write-auth).

⚠️ CONCURRENCY — THE GROUP IS `deploy-inngest-restart`, NOT A NEW `inngest-cutover` LITERAL, AND
THE DEVIATION FROM THE PLAN'S AC B9 IS DELIBERATE. The property B9 is about is stated in the
plan's own words: "a mutex on one side of a race is not a mutex". The race is an
`op=arm` landing between Guard 2's read and this job's apply — the flip flag goes to `armed`, the
on-host 30s timer fires `run_preflush_flip`, and terraform destroys the volume mid-`FLUSHALL`.
`cutover-inngest.yml` ALREADY serializes on `deploy-inngest-restart`, and so do
`deploy-inngest-image.yml` and `restart-inngest-server.yml` — three surfaces that all restart or
re-provision inngest-server. A job may declare only ONE concurrency group, so minting
`inngest-cutover` and putting it on the cutover job would have REMOVED that job from the group it
shares with the deploy pipeline: the deploy could then restart inngest-server mid-cutover, which
is a strictly worse race than the one B9 set out to close. Joining the existing literal covers
SIX surfaces instead of four and orphans none. The plan is authoritative for the intent (one
shared mutex across every surface that can touch this Redis), never for the literal.
tests/scripts/test-inngest-volume-recut-gate.sh asserts the PROPERTY — that all four surfaces
carry one identical group — rather than the string, so the guard survives a future rename.

Zero downtime is NOT claimed and must not be: the volume being destroyed is the inngest
scheduler's own store, and Guard 2 refuses unless the host is already dark. There is nothing to
take down because nothing is serving.

## apply/Measure the apex origin (ADR-194 Hypothesis Z)

Tunnel ingress origin verification (#6594 / ADR-114 I2).

WHY THIS EXISTS: `terraform apply` of a Cloudflare tunnel config ALWAYS
succeeds — CF accepts an ingress `service` without ever checking the origin is
reachable. So a wrong origin (bad IP, wrong port, an un-converged private NIC)
applied GREEN and took out the management plane silently. Nothing else caught
it: apply-deploy-pipeline-fix.yml does NOT fire on tunnel.tf (its `paths:`
lists explicit .sh files + server.tf), and the SSH bridge's readiness check is
`nc -z 127.0.0.1 2222`, which proves only that the LOCAL cloudflared listener
opened — true whether or not the origin answers. A tunnel.tf-only merge had
ZERO post-apply verification: the same "closed by construction, verified by
nothing" defect (#6425/#6594) this change exists to retire. Do not delete
without a replacement that reads the LIVE config plane.

Two instruments, because they prove different things:
  (a) CF API config read-back — authoritative, vantage-free. Proves the edge
      holds the config we intended.
  (b) HMAC probe of /hooks/deploy-status — proves the pinned origin is
      actually SERVING. (a) cannot: a perfect config pointing at a dead origin
      reads back clean.

Deliberately NOT a data-plane distribution check: connector selection is
colo-STICKY (scheduled-inngest-health.yml — on 2026-07-15, 10/10 identical EU
reads "proved" inngest was down while a US runner read it healthy). Polling N
times from one runner colo samples ONE sticky binding N times, not a
distribution. (b) asserts an INVARIANT (the route serves), which is
colo-independent and needs no control arm.
HYPOTHESIS Z, MEASURED RATHER THAN ASSERTED (ADR-194 PR3).

cf-pages.tf said the branch of Z "is measured AFTER this applies, by
apex-origin-probe.sh". Nothing invoked it: the probe was wired to no
workflow, and deploy-docs.yml's build-identity probes do not fire on an
infra-only merge (their paths do not match). So under Z-true with
content-identical origins, the apex origin could move and NOTHING would
observe it — the project's first datum on Z depended on a human
remembering to type a command. This step is that measurement.

REPORTING-ONLY, deliberately. Both verdicts are legitimate at this stage:
SERVING-FROM-GITHUB-PAGES means Z is false and the record swap (PR4) is
what moves the origin; SERVING-FROM-CLOUDFLARE-PAGES means Z holds and
attachment already moved it. Neither is a failure — the failure mode this
step exists to end is having no record at all. UNREACHABLE is the one
result worth alarming on, and it exits non-zero into the summary.

`if: always()` so a failed apply still records where the apex is pointing,
which is exactly when you most want to know.

## git_data_host_replace

Selected by `-f apply_target=git-data-host-replace` (#6242, ADR-103). git-data.tf +
git-data-luks.tf + network.tf resources are OPERATOR_APPLIED_EXCLUSIONS (ADR-068) —
deliberately NOT in the per-PR `-target=` allow-list, and the per-PR path bridges over SSH
to the EXISTING web host so it cannot reprovision the git-data host at all. Before this job
git-data had ZERO non-SSH reprovision path (a standing hr-prod-host-config-change-immutable-
redeploy gap on the fleet's most irreplaceable data store). This scoped -replace is the
sanctioned non-SSH reprovision path (mirrors registry_host_replace / inngest_host_replace):
it re-runs the git-data cloud-init WITHOUT SSH and WITHOUT touching either data volume.

5-target scope (server + its 4 id-referencing dependents; BOTH data volumes + the LUKS
passphrase are PRESERVED BY OMISSION — an untargeted resource cannot be planned for destroy):
  hcloud_server.git_data                   (-replace: force a fresh cloud-init boot)
  hcloud_server_network.git_data           (network.tf:48 — server_id ForceNew → replace;
                                             else the new host has no private NIC 10.0.1.20)
  hcloud_volume_attachment.git_data        (git-data.tf:275 — server_id ForceNew → replace;
                                             else /mnt/git-data — plaintext bare-repo store —
                                             boots UNMOUNTED)
  hcloud_volume_attachment.git_data_luks   (git-data-luks.tf, `resource "hcloud_volume_attachment"
                                             "git_data_luks"` — server_id ForceNew → replace;
                                             else /mnt/git-data-luks — LUKS at-rest store —
                                             boots UNMOUNTED)
  hcloud_firewall_attachment.git_data      (git-data.tf:296 — server_ids update-in-place;
                                             registry-style INCLUDE — else the fresh host boots
                                             NAKED on its public IPv4/IPv6)
LUKS re-open on fresh boot is SAFE because the passphrase is unchanged: the idempotent isLuks
skip (cloud-init-git-data.yml:152-173) re-opens the existing header with no luksFormat. This
holds ONLY while random_password.git_data_luks / doppler_secret.git_data_luks_key are OUT of
scope — the sourced git_data_host_replace_gate's luks_passphrase_touched backstop asserts it.

The sourced git_data_host_replace_gate (no [ack-destroy] bypass) reads the STRUCTURED plan
JSON and ABORTS unless the plan is EXACTLY this scoped recreate with BOTH volumes preserved.

## ci_ssh_token_replace

See also: knowledge-base/engineering/operations/runbooks/ci-ssh-token-replace.md

── #7095: re-mint the CF Access ci_ssh service token ──────────────────────

WHY THIS ARM EXISTS. On 2026-07-28 the ci_ssh Access service token was rotated
out-of-band during incident response. Cloudflare never returns `client_secret`
after creation, so `terraform plan` stayed clean while the credential was dead —
and every remote write path to web-1 runs over the SSH bridge that authenticates
with it. Production could not be redeployed for three days.

The repair is `terraform apply -replace=` on ONE resource. Before this arm, no
workflow could run a `-replace`, so the documented recovery was a laptop-local
`terraform apply` outside CI — i.e. exactly the out-of-band infra step this repo's rules forbid
(hr-all-infrastructure-provisioning-servers). This is the in-band replacement.

WHY IT IS NARROW, not a general `-replace` input. A free-text `-replace` would let
a typo destroy an hcloud_server, and the dispatch-input budget is near its 10-input
cap. The -target set below is TWO addresses and is enumerated in full; the gate
then re-reads the PLAN and refuses anything outside it. Membership is asserted
against the plan, not against the flag list — a `-target` is transitive on
dependencies, so the written flags are a request, never a proof of blast radius.

WHY `.deploy` IS ABSENT AND MUST STAY ABSENT. The sibling
`cloudflare_zero_trust_access_service_token.deploy` is the only OTHER remote write
path to web-1. web-1 sits on a cx33, which has been out of stock in all six Hetzner
datacenters — so the host cannot be replaced if it is stranded. Replacing both
tokens in one apply means any failure between destroy and Doppler republish leaves
an unreachable, unreplaceable host. `check-cloudflare-token-drift.test.sh` (W7)
asserts no `-replace` in this repo ever names `.deploy`.

NO `environment:` REVIEWER GATE, deliberately. This arm's purpose is to restore a
DEAD control plane; gating recovery behind a reviewer click is how a three-day
outage becomes a four-day one. It matches the `apply` job's posture (PR #4220
removed that gate for the same reason). The authorization is the dispatch itself
plus the typo-guard below, per hr-menu-option-ack-not-prod-write-auth. The
workflow-level `concurrency:` group still serializes it against every other
terraform apply, which is the property the lockless R2 backend actually needs.

## registry_store_restore

── the chained REAL restore (#7277) ────────────────────────────────────────────────────────

THIS IS THE LOAD-BEARING HALF OF THE DESIGN. The D10 rehearsal is its pre-destroy safety
net, not its equal: the rehearsal proves the restore SCRIPT is correct against a real
registry HTTP API, while THIS job exercises the actual path, with the actual credentials,
against the actual sink.

WHY A SEPARATE JOB AND NOT ANOTHER STEP IN registry_luks_recut. That job's
`timeout-minutes: 30` is explicitly load-bearing — it holds the fleet-wide apply mutex, and
its own comment records that D11's 150s + 480s bound sits strictly below the timeout "so its
diagnostic wins over an opaque cancellation". Adding a multi-GB restore inside that budget
breaks the invariant, and a timeout is a CANCELLATION: store destroyed, restore half
applied, no `::error::`, and the Dispatch summary — the only emitter of the NEW volume id,
without which the next recut is blocked — never runs. A partially populated registry is
worse than an empty one, because tag lookups then succeed for some refs and not others.

Splitting gives the restore its own budget and keeps the recut job's cancellation semantics
intact.

IT DOES NOT RELEASE THE MUTEX, and an earlier revision of this comment claimed it did. The
`concurrency:` group is declared at WORKFLOW level, so it is held for the whole RUN — this
job inherits it and cannot release what a sibling job holds. Worst-case fleet-wide apply
block therefore goes from 30 to **135 minutes: 45 (registry_pull_path_gate) + 30
(registry_luks_recut) + 60 (this job)**. An earlier revision of this line said "90 (30 + 60)",
which was correct until #7277 split the authorization gate into its own job and then silently
understated the block by the gate's 45. A comment that half-corrects a number is worse than
one that never claimed it, because it reads as already-audited — so when a job is added to
this chain, this arithmetic moves with it. That is still far better than the 360-minute
default the 30 was chosen against, but it is 4.5x the number that comment defends, and saying
otherwise would be naming a property the change does not have. Genuinely releasing it needs a
SEPARATE WORKFLOW (workflow_run), not a chained job — tracked, not done here.

## confirm and the gate model

Relocated from `apply-web-platform-infra.yml`'s `confirm:` field label (ADR-231 byte
budget; the field's own comment already said no operator reads a label that long).

`confirm` is a TYPO-GUARD, never the authorization. Each job accepts only its own literal,
so a token typed for one target cannot authorize another, and birth and replace tokens are
always distinct -- a token typed for a birth cannot authorize a destroy.

**What actually gates each target.**

- `web-host-create`, `web-host-replace`, `git-data-host-create`, `workspaces-luks-recut`
  and `inngest-volume-recut` carry an `environment:` with a REVIEWER. The reviewer click
  is the human authorization on those paths.
- Since #8209 / ADR-241 D2 every OTHER target carries `environment: infra-privileged`.
  That environment has no reviewer -- it serves unattended jobs -- but its
  deployment-branch policy admits `main` only, so a dispatch from any other ref is refused
  before the job starts.
- For the reviewer-less targets the gate chain, the destroy-guard and the id-pin remain
  the rest of the protection. Those are `registry-luks-recut`, `registry-host-replace`,
  `registry-region-migrate`, `inngest-host-replace` and `git-data-host-replace`, all of
  which destroy or replace production hosts.

**What changed, and what did not.** Before #8209 those five ran the SELECTED REF, so each
gate was supplied by the branch it polices. They now run main's gate. The limitation is
narrowed, not removed: a deliberate actor who can land a commit on `main` still reaches
them. ADR-169 and ADR-220 carry superseding callouts to the same effect.

## plan_only

`plan_only` (boolean dispatch input, default false) is the incident-recovery REHEARSAL
arm, honoured by `web_host_replace` and `git_data_host_replace`. It runs the credential
load, `terraform init`, `terraform plan` and the path's own gate, then stops.

Three properties make it safe to add to a destructive job, and the census asserts all
three:

1. It only ever SKIPS steps. Every mutating step from the boot-trail anchor onward carries
   `inputs.plan_only != true`, so a true value can make the job do less and never more.
2. The set of guarded steps is DERIVED from the mutating set, not hand-kept -- a newly
   added apply step with no guard is red.
3. Input validation, the typo-guard and the environment gate are UNCONDITIONAL, so
   `plan_only` is not a way around any of them.

**A note for anyone adding a guard here.** A second `if:` on a step is a duplicate YAML
key. The parser accepts it and the LAST one wins, so an inserted guard reads as present
and is dead. Merge into the existing expression instead (`always() && inputs.plan_only !=
true`), and verify by PARSING the file rather than by reading the diff.

Operator step **O4b** dispatches both paths this way from `main` before the eviction (O10)
removes the legacy credential fallback. Without it, a recovery path that fails closed is
first discovered during the incident it exists to fix. See
`infra-credential-tiers-8209.md`.

## legacy-app-key-evicted

Why the App-token mint refuses `EVICTED_SEE_ADR_241` by name, rather than letting
`openssl rsa -check` reject it a few lines later.

After operator step O10 (#8209), Doppler `soleur/prd_terraform` holds the literal string
`EVICTED_SEE_ADR_241` under `GITHUB_APP_PRIVATE_KEY` instead of a key. The eviction has to be an
**override** rather than a delete, because the value is inherited from the `prd` config and a
branch config cannot delete an inherited name — so the `doppler secrets get` **succeeds** and
returns a non-empty string, which every check around it was written to treat as a key.

`openssl rsa -check` does reject it, so the name check is not the difference between working and
broken. It is the difference between an operator reading

    verdict=legacy_app_key_evicted … is the #8209 eviction sentinel, not a key. Do NOT re-set it there.

and reading `GITHUB_APP_PRIVATE_KEY in Doppler is not a valid RSA PEM`. The second one means "the
key is corrupted", and the remedy it suggests is to paste a fresh key into `prd_terraform` — which
**undoes the eviction**, on a config every branch of this public repository can read. A message
that invites the operator to reverse the fix is worse than no message.

Four consumers read this name and all four carry the refusal:
`.github/actions/mint-soleur-ai-app-token/action.yml`, `apply-github-infra.yml`,
`board-status-sync.yml`, and this workflow. ADR-241 D5, the plan and the #8209 runbook all promised
`verdict=legacy_app_key_evicted`; nothing implemented it until review round 3. Census row **G4e**
is what keeps a fifth consumer from being added without it.

### plan_only, belt-and-braces on the post-apply steps

Each `inputs.plan_only != true` guard is **merged into the step's existing `if:` expression**, never
added as a second `if:` key — YAML keeps only the last duplicate key and the parser says nothing, so
a second key silently discards whichever guard it shadows. That happened twice while writing this
change and both guards were dead until it was caught.

The guards on the post-apply steps (the failure notification, the drift probe) are belt-and-braces:
with the apply skipped, `steps.apply.outcome` is `'skipped'` and neither arm of those conditions
matches anyway. Relying on that would leave the guard implicit, and an edit to the apply step's own
condition would silently re-arm a step that must not run in a rehearsal.

### plan_only, and the one step that deliberately has no guard

`git_data_host_replace`'s boot-signal poll carries NO `inputs.plan_only != true` conjunct,
and that is deliberate rather than an omission.

It would be redundant. With the apply step skipped, `steps.apply.outcome` is `'skipped'`, so
neither arm of the poll's `(outcome == 'success' || outcome == 'failure')` matches and the step
already cannot run in a rehearsal. The step is also not MUTATING by Guard 5's definition — no
`terraform apply`, no `ssh`/`scp` — so census row G5a does not ask for one.

And it is not free. `tests/scripts/test-git-data-boot-signal-poll.sh` pins that `if:` line
verbatim as case **S19**, and that file belongs to the parallel #8211 session (PR #8564), which
has commits against it. Adding a redundant conjunct here bought belt-and-braces and broke a
contract another PR depends on — measured, in CI, as one red suite out of 163.

The sibling `web_host_replace` Sentry-surface step DOES carry the guard, because there the step
runs on `always()` and would otherwise query Sentry for a fresh host that was never created.
That asymmetry is the rule working, not drift: the guard goes where the step could actually run.
