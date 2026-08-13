---
title: "infra: give vector.toml its own scoped delivery path (apply_target=vector-redeliver) so #7228's boot-trace stops waiting on unrelated drift"
date: 2026-08-13
slug: infra-vector-redeliver-apply-target
branch: feat-one-shot-7542-vector-redeliver-target
issue: 7542
closes: 7542
lane: cross-domain
type: chore
priority: p1-high
domain: engineering
brand_survival_threshold: none
---

> Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). The Domain Review
> below nonetheless found only Engineering relevant; the fail-closed default widens the review
> fan-out, it does not assert cross-domain impact.

## Overview

`apps/web-platform/infra/vector.toml` is hashed into the `triggers_replace` of
`terraform_data.journald_persistent`. A change to that file therefore shows up in the
web-platform plan as a replacement of that one resource. The merge-triggered apply path
grades the whole plan at once, so a replacement that is by itself routine cannot land while
unrelated pending changes sit in the same plan.

This plan adds a dispatch-only `apply_target=vector-redeliver` arm to
`.github/workflows/apply-web-platform-infra.yml`, scoped to that single address, with a gate
that refuses any plan wider than exactly one delivery of it. It also adds a runbook and
extends the existing destroy-guard test harness so the new gate is provably able to go red.

Every change here is Terraform-routed by construction: the delivery mechanism is an existing
`terraform_data` resource with create-time provisioners, and this plan adds a scoped apply
path for it. No new resource, host, secret, or runtime process is introduced, and no step is
performed outside Terraform.

## Design Findings

Findings established during planning that bear on the design. Each names the evidence that
established it. One of them refines a constraint carried in on the brief.

### F1 — Target-parity guard: VERIFIED, does NOT change the design

`plugins/soleur/test/terraform-target-parity.test.ts` is the CI guard that would most
plausibly break on a second `-target=terraform_data.journald_persistent` line. It does not.
Its collector at `terraform-target-parity.test.ts:151-156` is `const set = new Set<string>()`
fed by `workflowText.matchAll(/-target=terraform_data\.([A-Za-z0-9_]+)/g)` — a **set**, so a
second occurrence of an address already present dedupes to the same member. The guard is also
one-directional by its own header (`:34-36`): it asserts every SSH-provisioned `terraform_data`
appears in the covered union, *not* that every `-target=` line points at a live resource. The
SSH-set assertion is a floor, not an equality —
`expect(sshProvisioned.length).toBeGreaterThanOrEqual(MIN_SSH_PROVISIONED)` at `:228` with
`MIN_SSH_PROVISIONED = 10` at `:86`. The exact-count assertions in the file (`:1460`, `:1593`,
`:1669`, `:1699`, `:1808`) are all scoped to `WEB_HOST_BIRTH_TARGET_BASES` /
`WEB_HOST_REPLACE_TARGET_BASES`, not to the SSH `terraform_data` set.

**Consequence:** adding the new job's `-target=` line is safe against this guard. Residual
check for /work (cheap, not yet run): re-run the suite after the edit rather than relying on
this reading alone.

### F2 — Stranded-recovery shape: PLAUSIBLE BUT UNMEASURED; it DOES refine the brief's gate constraint

The brief specifies the gate "must assert the plan is EXACTLY one replace of
`terraform_data.journald_persistent` and nothing else". A gate written literally to that
wording refuses a **bare create** of the same address — and a bare create is the shape the plan
takes if the resource is absent from state.

The precedent gate makes this failure mode explicit rather than hypothetical. The
`ci_ssh_token_replace` blast-radius gate requires `sorted(actions) == ["create","delete"]` and
fails otherwise (`apply-web-platform-infra.yml:5362-5368`), and that same gate's header records
the cost of scoping a gate too tightly: *"Omitting it made the gate fail CLOSED on the remedy,
which is the 'a gate that always fails is an outage, not a tripwire' shape"* (`:5329-5331`).

**What is established:** the wording as given admits only `["delete","create"]`, so in any
state where the address is absent the gate can never pass — the recovery arm would be bricked
at exactly the moment it is needed.

**What is NOT established (open, deliberately not asserted):** how likely that state is. For a
`terraform_data` whose provisioners are create-time only, a *provisioner failure* taints the
resource and leaves it in state, so the next plan is still a replace; the bare-create shape
requires the run to die between the destroy and the create (job timeout, cancellation). I did
not measure that and claim no frequency for it.

**Why the refinement holds regardless of that frequency:** a bare create of this address is not
a widening of blast radius. Creating `terraform_data.journald_persistent` runs exactly the
create-time provisioners that deliver `vector.toml` and reload the logging agents — the intended
work of this arm, precisely. Admitting it costs no capability the replace path does not already
grant, and refusing it buys nothing.

**Proposed refinement:** the gate asserts *exactly one **delivery*** of
`terraform_data.journald_persistent` — `["delete","create"]` **or** `["create"]`, counted as one
— and nothing else. Every other clause of the brief's constraint is unchanged: no other address,
no host delete, no nested-block removal, no destroy capability beyond that address.

### F3 — Root cause is a transitive `depends_on` edge, not a widened allow-list

The brief states the replace rides in the merge-apply plan. The mechanism is more specific than
"it is in the allow-list", and the specificity matters because it is what makes the new arm's
plan non-trivial to gate.

`terraform_data.journald_persistent` is **not** in the main plan step's `-target=` allow-list
(that list runs `apply-web-platform-infra.yml:463-584` and ends at `betteruptime_team_member.ops`).
It enters the guarded plan **transitively**: `terraform_data.inngest_consumer_probe_install`
**is** targeted (`:578`) and carries `depends_on = [terraform_data.journald_persistent]`
(`apps/web-platform/infra/server.tf:753`). Terraform's `-target` includes a target's
dependencies, so the probe-install target drags journald_persistent into the plan the
destroy-guard grades.

**Consequence for the new job:** its own `-target=terraform_data.journald_persistent` is
likewise transitive — the resource's `connection` block references
`hcloud_server.web["web-1"].ipv4_address` (`server.tf:992-998`) and its remote-exec renders
`hcloud_server.web["web-1"].name` (`server.tf:1067`), so **`hcloud_server.web["web-1"]` will be
in the new arm's plan**. Today it refreshes as a no-op, which is why the brief observed it
appearing only as `Refreshing state`. That is a property of current state, not a guarantee — if
web-1 ever carries a pending change, it lands in this arm's plan. This is exactly why the gate
must assert the whole plan shape rather than trusting the `-target` flag, and it is the
`-target`-transitivity class already recorded in the plan skill's sharp edges. The `ci_ssh` gate
states the same principle in its own words: *"`-target` is transitive on dependencies, so the
flag list above is a request; this is the proof"* (`:5293-5294`).

### F4 — The arm must take the `web-1-swap` mutex, not only the workflow-level group

The workflow-level `concurrency.group: terraform-apply-web-platform-host` (`:263-278`)
serializes terraform applies against each other. It is **not** sufficient here. This arm reaches
web-1 over the CF Tunnel SSH bridge and, via the resource's final remote-exec, restarts both the
journal daemon and the Vector agent on the running host (`server.tf:1046`, `:1081`) — a
disruption that is invisible to a mutex scoped to terraform runs alone.

`ci_ssh_token_replace` takes a second, narrower mutex for the analogous reason —
`concurrency: group: web-1-swap` (`:5164-5166`) — and its comment states the rule directly:
*"Both sibling arms that touch web-1 take this same mutex on top of the workflow-level one"*
(`:5160-5161`). The group is shared across pipelines: `apply-deploy-pipeline-fix.yml:213`,
`web-platform-release.yml:519`, `workspaces-luks-cutover.yml:74`.

**RESOLVED (was an open check) — and it caught a gap in this plan's own file list.**
`apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` (invoked at
`infra-validation.yml:1088-1089`) is not a passive guard. It is an **explicit allow-list with an
exact-count assertion**:

- Seven `assert_member` calls (`:107`, `:108`, `:109`, `:113`, `:119`, `:126`, `:137`) — the last
  being `ci_ssh_token_replace`, our structural model. (The header comment still says "SIX"; it is
  stale by one.)
- `:173` — `if [ "$web1_count" -eq 7 ]`, an **equality** check, with `:165` instructing
  *"KEEP THIS NUMBER EQUAL TO THE assert_member COUNT ABOVE."*

So enrolling `vector_redeliver` in the group **fails this suite** at count 8 ≠ 7 unless the same
change adds an `assert_member` line and bumps the literal to 8. That makes
`web-1-swap-concurrency-parity.test.sh` a **mandatory** entry in Files to Edit — it was missing
from this plan until the check was actually run, which is precisely the orphan-suite class the
`-target`-allowlist learning warns about.

**The membership question itself is a genuine judgment call, so both sides are recorded.** The
suite carries a *negative* assertion (`:201-210`): the routine `apply` job must NOT be enrolled,
or it is an *"over-serialization trap"*. That matters here because the routine `apply` job's SSH
step performs the **identical** `terraform_data.journald_persistent` delivery this arm performs
(`:935`) — so the repo has already ruled that this specific work is not, by itself, web-1-swap
class.

**Position taken: enroll.** The exclusion's stated rationale is explicitly about *frequency* —
*"enrolling it would over-serialize every routine release behind every routine infra apply"* — not
about whether the work mutates web-1. That rationale does not transfer to a rare, deliberately
fired arm. The nearest sibling on that axis, `ci_ssh_token_replace`, is a rare non-container-swap
dispatch and **is** enrolled (`:137`). Serialization cost here is negligible; the cost of a
logging-plane reload racing a LUKS cutover or a release swap is not.

**If review disagrees**, the reversal is mechanical and cheap: drop the `concurrency:` block from
the job and make no parity-test change at all. The two options are exactly symmetric in effort, so
this decision does not need to be right the first time — it needs to be visible. Flagged for the
review panel rather than settled by assertion.

### F9 — P0, PREMISE CORRECTION: the #7228 boot-trace identifiers are NOT web-1 identifiers, so AC27 as briefed is unsatisfiable

**This falsifies a premise carried in on the brief**, and it is the most important finding of the
review pass — the runbook's verification section, AC27, AC28 and the issue-close condition were all
built on it.

The brief states: *"#7457's change is file-only and never reached web-1, so #7228's boot-trace
SyslogIdentifiers are dark on the host."* The first half holds. The second does not.

Commit `0d6443960` added exactly two identifiers under its "#7228 boot-trace" comment blocks —
`inngest-boot-phone-home` (`vector.toml:194`) and `inngest-bs-token-restage` (`vector.toml:202`).
**Both emitters live on the dedicated inngest host, not web-1:** `cloud-init-inngest.yml:150,155,170`
(the only `logger -t inngest-boot-phone-home` sites), `cloud-init-inngest.yml:245,255` plus `:290`
(`SyslogIdentifier=inngest-bs-token-restage`), and further sites in `inngest-bootstrap.sh:598-1237`.
Grepping the **web** host's provisioning (`cloud-init.yml`, `soleur-host-bootstrap.sh`) for either
name returns zero hits. This arm delivers to one host only — `connection { host =
hcloud_server.web["web-1"].ipv4_address }` (`server.tf:992-998`) — while the inngest host's config
arrives via `apply_target=inngest-host-replace` (`server.tf:745-748`). A *successful*
`vector-redeliver` cannot light those two channels on any host.

They are also **boot-scoped and silent-on-success even on the right host**: `vector.toml:188-189`
says so verbatim — *"the emitter is SILENT ON SUCCESS, so a healthy host pays zero rows."* Nothing
in this plan causes a boot.

**The one #7228 tag that IS web-1-scoped is blocked by this plan's own AC24.**
`inngest-consumer-probe` (`vector.toml:244`) is emitted by a unit installed by
`terraform_data.inngest_consumer_probe_install`, which provisions **web-1** (`server.tf:767-772`,
timer at `:812`) — one of the pending creates AC24 forbids. So after a successful dispatch web-1
carries the Source-4 allow-list entry with **no unit emitting it** — exactly what
`vector.toml:246-248` warns about: *"an entry whose unit does not set that literal
SyslogIdentifier= is a permanently-dead no-op that reads like coverage."*

**Second defect, same area:** the Observability block claimed delivery failure "cannot occur
silently" thanks to the post-restart assertions. Those grep only `web-zot-consumer-probe`,
`web-git-data-probe`, `web-nic-guard` (`server.tf:1082-1085`) — the #6438 tags. **No #7228 tag is
asserted.**

**Resolution — AC27 is rewritten to assert what the arm can actually cause:** (1) extend the
resource's post-restart assertions with `grep -q 'inngest-consumer-probe' /etc/vector/vector.toml`,
making delivery a property of the apply itself; (2) keep the cat-deploy-state webhook check, which
was always sound; (3) add a **positive control** — an identifier web-1 genuinely emits (`sshd`,
`ci-deploy`) for `host_name=soleur-web-platform` after the restart timestamp, because **absence of
rows must never be the assertion** (an empty query is indistinguishable from a dead sink); (4) move
boot-trace verification to `inngest-host-replace` under #7462, stated in Known Residual rather than
silently dropped. Verified CLI shape, from the script's own no-credential message:
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep <marker>`.

### F10 — P0: the prescribed step order cannot authenticate SSH; AC12 and AC13 were jointly unsatisfiable

The first draft prescribed `plan -out=tfplan` → gate → **bridge** → `apply tfplan`. That cannot work.

`.github/actions/cf-tunnel-ssh-bridge/action.yml:161-163` notes the secret name
(`DEPLOY_SSH_PRIVATE_KEY`) does **not** map to the var name via `--name-transformer tf-var`, so the
action sets it explicitly — writing `TF_VAR_ci_ssh_private_key` into `$GITHUB_ENV` at `:199-203`,
i.e. only **after** the bridge step. `variables.tf:468-472` defaults it to `null`, and
`server.tf:992-998` resolves `agent = var.ci_ssh_private_key == null`. A plan produced *before* the
bridge therefore bakes `null` → `agent = true` → ssh-agent auth on an agent-less runner. And
`terraform apply <savedplan>` uses the variable values recorded in the plan file and accepts no
variable input, so the bridge's later export is inert.

The repo already encodes this at `apply-web-platform-infra.yml:917-925`: the SSH apply is *"a
SEPARATE `terraform apply` (not the saved tfplan) … TF_VAR_ci_ssh_private_key is exported by the
bridge action → agent=false."* No existing arm combines a saved plan with the bridge; all twelve
saved-plan applies sit in jobs with no bridge and no SSH provisioner.

**Resolution: move the bridge BEFORE the plan step.** The credential is then in env at plan time,
gets baked into `tfplan`, and `apply tfplan` works — preserving the Guard Contract's single-artifact
chokepoint, which is load-bearing. **AC12 is rewritten to "the gate runs before the *apply*"**, and
its original goal costs nothing to give up: the bridge is read-only setup (a cloudflared forward, a
NAT rule, a token-liveness assertion), and the `ci_ssh` arm's own doctrine (`:5203-5217`) argues for
proving the channel *before* the consequential step. The alternative — keep gate-before-bridge and
use a fresh `terraform apply -target=` — dissolves the Assembly's central claim and AC13. Rejected.

### F11 — P0: a successful dispatch UN-WEDGES the push apply, releasing the four pending creates unattended

An emergent consequence the first draft did not analyse.

The push destroy-guard halts on `destroy_count = resource_deletes + nested_deletes + reboot_updates`
(`apply-web-platform-infra.yml:667`), and the journald replace is the **only** destroy in the
pending plan. Once this arm applies that replace outside the merge path, the next push plan becomes
**4 add / 1 change / 0 destroy** → `destroy_count = 0`, `host_creates = 0` → **the guard passes and
the push apply proceeds unattended**, applying all four creates plus the `cloudflare_bot_management`
update, on an arbitrary future merge by an unrelated author.

AC24 forbids acking those at merge time; this arm removes the barrier one dispatch later. Whether
that is desirable is arguable — per **F9** it is what would finally make `inngest-consumer-probe`
live — but the plan must **state the intended end state** rather than let it emerge.

**Correcting AC24's rationale, which was factually wrong.** The first draft said
`terraform_data.inngest_consumer_probe_install` *"provisions a host currently under repair."* It
provisions **web-1** (`server.tf:767-772`), and its own header says the opposite: *"Nothing here
touches 10.0.1.40, which is the point … This block is inside the per-merge `-target=` set, so it
works on merge"* (`:743-748`). The scope-out may still be right; the reason given was not.

**Recurring obligation:** after this PR merges, *every* subsequent merge touching a
`paths:`-matching file halts on the same guard and needs its own `[skip-web-platform-apply]` until
the dispatch fires. #7462, PR #7516 and #7539 are all still open, so the window is not short. Name
an owner and a deadline.

### F12 — P1: failing the no-op is wrong here; the cited precedent is `-replace`-specific

The first draft justified failing on `journald_delivered == 0` by citing
`apply-web-platform-infra.yml:5353-5355` (*"a plan with zero replaces means the `-replace` silently
did nothing"*). That premise is `-replace`-specific: there the flag **is** the instruction, so zero
replaces means the instruction was lost. **This arm deliberately has no `-replace`.** Here
`journald_delivered == 0` means the desired state is *already realised* — the arm's own success
condition, one dispatch later. Legitimate states that hit it: a re-dispatch to re-verify after a
successful AC26; the push apply delivering first; a cancelled run after state was updated.

In-repo precedent points the other way — `destroy-guard-filter-web-platform.jq` splits
`retire_firewall_attachment_updates` from `…_deletes` precisely so a retry finding the work already
done *"must not fail closed."*

**Resolution:** keep the counter and the distinct message, change the **outcome**. `== 0` →
**NO-OP SUCCESS**: exit 0, skip the bridge and the apply, write *"nothing to redeliver"* to
`$GITHUB_STEP_SUMMARY`. Keep strict-red for `>= 2`. **M4 flips from RED to a distinct
green-with-summary** and needs its own assertion; AC26 must state `journald_delivered=1` is
assertable **only on the first dispatch** — as written it depended on run history, the
`cq-ac-must-not-depend-on-concurrent-sessions` shape.

### F13 — P1: the transitive closure is ~9 addresses, not one; and it has a dated future brick

**F3** named only `hcloud_server.web["web-1"]`. The real closure of
`-target=terraform_data.journald_persistent` also pulls `hcloud_server.web["web-2"]` (dependency
inclusion is resource-scoped, and `variables.tf:96-99` declares both), `hcloud_ssh_key.default`
(`server.tf:264`), `hcloud_placement_group.web_spread` (`:273`),
`cloudflare_zero_trust_tunnel_cloudflared.web` (`:322`) → `random_id.tunnel_secret`,
`doppler_service_token.web_probes` (`:410`), `hcloud_volume.workspaces[each.key]`, and
`tls_private_key.ci_ssh` via `local.ci_ssh_pubkey` (`ci-ssh-key.tf:48`).

This does not break the design — grading the whole plan is exactly the right response, and the
closure is empirically clean today. Three consequences: (1) the Risks row should read "any of ~9
closure addresses carries a pending change", not "web-1"; (2) **`host_destroyed` must also name
`hcloud_volume.*`** — the workspaces volumes are sole-copy user data, are in the closure, and are
actively mutated by the LUKS arms; (3) **a dated future brick** — the arm's cleanliness rests on
`hcloud_server.web`'s `lifecycle { ignore_changes = [user_data, ssh_keys, image,
placement_group_id] }`, which `server.tf` documents as a temporary GA deferral (*"REMOVE this entry
in the GA maintenance-window PR as its FIRST diff"*). When `placement_group_id` leaves that list,
web-1 plans a pending in-place update on every dispatch and the gate refuses forever — F2's own
"a gate that always fails is an outage" hazard, with a scheduled date. Belongs in Known Residual.

Also: `host_destroyed` must use a **type-scoped** `select(.type == "hcloud_server")`
(`destroy-guard-filter-web-platform.jq:185` — *"TYPE-scoped select (not address)"*), not an
address-prefix match, which would collide with the exact-equality rule.

### F14 — P1: four gate-refusal states have no documented remedy, one terminal

Phase 4's `## If it fails` is scoped to SSH-step failures; nothing covers a gate refusal. The
runbook needs an `## If the gate refuses` section *ahead of* it, with a per-counter table:

1. **`vector_out_of_scope_changes ≥ 1` from pending drift in the closure** — not hypothetical
   (**F13**). The remedy is **circular**: clearing that drift needs the push apply (wedged) or a
   full apply outside CI. This is the terminal dead end — `vector.toml` becomes undeliverable by
   any route, the exact #7228-prolonging condition the arm exists to end. Needs a named break-glass;
   the workflow's own halt text already points at the OPERATOR_APPLIED_EXCLUSIONS contract /
   ADR-096 (`:663-664`).
2. Any other closure address arriving with a change — enumerate the plausible ones.
3. Fail-closed preamble aborts — a tooling fault that reads like an infra fault. Needs an explicit
   *"re-dispatch once; if it repeats, the gate or `terraform show` is broken"* line.
4. `journald_delivered ≥ 2` — anomalous; needs a stated next action.

### F15 — additional required edits surfaced by review

- **`if: always()` bridge teardown step is mandatory.** `action.yml:33-58`: *"Every caller MUST add
  an `if: always()` teardown step."* The first draft's step list ended at the apply. It is also
  where `tail -n 200 /tmp/cloudflared.log` surfaces — without it, the L3 "tunnel unhealthy"
  hypothesis in `## Hypotheses` has no evidence to run on. Reference: `:1102`.
- **`timeout-minutes` is missing.** Every sibling has one (`ci_ssh_token_replace` `:5148` = 15).
  Omitted, GitHub applies 360 minutes — on a job holding **two** mutexes, one of which
  (`web-1-swap`) the in-band credential-repair arm also needs. Add `timeout-minutes: 15`.
- **AC21's `bash -c` would EXECUTE the snippet** (firing `terraform plan`/`apply` and the bridge).
  Correct form: `yq` the `run:` scalar to a temp file, then `bash -n` on the extracted snippet.
- **AC9 is not grep-able as written** — `REDELIVER-VECTOR` legitimately appears in the job header,
  the comparison, the error string, the runbook, this plan and the suite. Use a structured read:
  `yq '.on.workflow_dispatch.inputs.confirm.description'` piped to a negative grep.
- **The `apply_target` description enumeration must gain the option** (`:189-194`), and
  `terraform-target-parity.test.ts:2705-2716` enforces description→enum parity. But per `:181-187`
  the *detail* belongs in the job header, not that field — add the option to the enumeration only.
- **`scripts/lint-workflow-errexit-capture.py`** and **`scripts/lint-infra-no-human-steps.py`**
  (whose `SCAN_DIRS` covers both `runbooks/` and `decisions/`) belong in AC21.
- **CODEOWNERS** enumerates gate libs individually (`.github/CODEOWNERS:98-117`); the new gate needs
  a row.
- **M6/T13 must anchor on the `source` command, not the filename** —
  `stock-preflight-coverage.test.ts:207-215` records that a bare `.includes("…-gate.sh")` is
  satisfied by the `# shellcheck source=` directive alone, and *"deleting all five real `source`
  lines left this suite green."*
- **The dummy-key comment must not be copied verbatim.** `ci_ssh_token_replace`'s says
  *"hcloud_ssh_key.default is not in the target set and is never consumed"*; here it **is** in the
  closure (`server.tf:264`) and stays a no-op only via `lifecycle { ignore_changes = [public_key] }`
  (`:242-244`).

### F7 — P0: the arm needs `environment: web-platform-infra-apply`, because that environment is a MAIN-BRANCH PIN, not merely a reviewer click

**This reverses a design decision the first draft asserted**, and the reasoning it was asserted on
was a misreading.

The draft said: *"No `environment:` reviewer gate — consistent with every non-birth/non-recut arm
(`:112`)."* Line `:112` does describe `environment:` as a reviewer gate — but for the environment
the birth/replace arms actually use, that is only half of what it is.
`web_host_create` (`:3735`), `web_host_replace` (`:4201`) and `git_data_host_create` (`:4675`)
declare `environment: web-platform-infra-apply`, and
`apps/web-platform/infra/web-host-birth-environment.tf:63-66` + `:73-78` bind that environment to
`deployment_branch_policy { custom_branch_policies = true }` with `branch_pattern = "main"`.

That same file (`:35-39`) states this arm's threat model verbatim:

> `workflow_dispatch` runs the SELECTED REF's workflow and its scripts, and the birth job sources
> its only check from `${GITHUB_WORKSPACE}`. Without the branch policy, anyone who can dispatch can
> point the run at a branch carrying a neutered gate, and the reviewer prompt shows a branch name,
> not a diff.

**The new arm is that shape exactly.** Its gate (`tests/scripts/lib/vector-redeliver-gate.sh`), the
job that calls it, the `server.tf` provisioner bodies and the `vector.toml` payload all come from
`${GITHUB_WORKSPACE}` at the **dispatched ref**. `grep -n 'github\.ref'` over the workflow returns
**zero hits** — there is no ref guard anywhere in the file. And this is the **first
`workflow_dispatch`-only job in the file that opens the CF Tunnel SSH bridge and runs root
`remote-exec` on web-1**: `grep -n cf-tunnel-ssh-bridge` returns three hits, two comments (`:19`,
`:288`) and one invocation (`:897`) — inside the push/`manual-rerun` `apply` job. Every existing
dispatch arm is cloud-init only; `:1153` says so for the class, and `ci_ssh_token_replace` is
described at `:256-259` as reaching *"NO host, NO volume, and NO terraform_data."*

`hr-menu-option-ack-not-prod-write-auth` is correctly applied as an authorization model, but it
authorizes the operator's **intent**, not the **code that runs** — and for the first time in this
file that code is root commands on production.

**Resolution: add `environment: web-platform-infra-apply` to the job.** It is already
Terraform-managed, already carries the main-only pin, and yields the reviewer prompt as a
by-product. A first-step `github.ref` guard was considered and rejected as strictly weaker: the
guard would itself be supplied by the branch it is meant to police.

Note this also explains a resource in the pending plan — `github_repository_environment_deployment_policy.web_platform_infra_apply_main`
is one of the four out-of-scope creates. The environment exists; the *policy* pinning it to `main`
is among the changes the wedge is holding. That ordering must be checked at dispatch time.

### F8 — P0: two more guard suites enumerate what this change adds

Both are orphan-suite misses of the class this plan names — and then committed twice more.

1. **`plugins/soleur/test/stock-preflight-coverage.test.ts`** enumerates `apply_target.options` and
   asserts each option either carries `stock_preflight_gate` or is **explicitly declared** in
   `EXCLUSION_ALLOWLIST` (`:15` — *"Silence is not an option — which is the whole point"*;
   `:243-251` — `expect(unguarded).toEqual([])`). Adding `vector-redeliver` makes it an unguarded,
   undeclared option, so **AC22 fails** (the suite runs under
   `run_suite "plugins/soleur" bun test plugins/soleur/`, `scripts/test-all.sh:1145`). Needs one
   `EXCLUSION_ALLOWLIST` entry with a reason — the arm targets a `terraform_data` and creates no
   `hcloud_server`, so the stock gate's `select(.type == "hcloud_server")` is a legitimate no-op,
   the same class as the existing `workspaces-luks-cutover` entry. `:270-277` also asserts no
   *excluded* target carries the gate, so the exclusion and the job body must agree.
2. **`apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`** — see **F4**. Exact-count
   allow-list; independently confirmed by two reviewers.

### F6 — The brief's "refuse any nested-block removal" clause is UNIMPLEMENTABLE for this resource type; the allow-set already subsumes it

**This is the second place a constraint as literally worded cannot be met** (F2 is the first), so it
is recorded here rather than quietly dropped.

The brief specifies the gate must refuse "any other address, any host delete, **any nested-block
removal**". The first two are implemented. The third cannot be, and a counter for it would be
**vacuous** — the precise defect the Guard Contract gate exists to prevent, introduced by this
plan's own first draft.

**Why it cannot fire.** "Nested-block removal" is not a schema-agnostic primitive in this repo. The
only implementation is `tests/scripts/lib/destroy-guard-filter-web-platform.jq:148-165`, which is
five hand-written, **Cloudflare-provider-schema-shaped** array-length deltas (`cloudflare_ruleset.rules`,
`…tunnel_cloudflared_config.config[0].ingress_rule`, `cloudflare_zone_settings_override.settings[0].security_header`,
…). A `terraform_data` resource has a schema of exactly `input`, `output`, `triggers_replace`, `id` —
no nested block arrays at all. `connection` and `provisioner` are not attributes and never appear in
plan JSON; `triggers_replace` is a scalar `sha256(...)` (`server.tf:987-990`). A `nested_removals`
counter on `terraform_data.journald_persistent` is therefore **definitionally 0 for every plan
Terraform can emit**, and its matrix row could only be exercised by hand-writing a plan document
Terraform could never produce — a green row that proves nothing.

**The repo has already ruled on exactly this**, and the first draft cited the wrong sibling.
`tests/scripts/lib/web-host-birth-gate.sh:77-83`: *"WHY AN ALLOW-SET RATHER THAN NESTED-BLOCK
COUNTERS. … This path changes NONE of them, so the stronger and simpler contract is that no such
address may appear in the plan at all. That subsumes nested-block shrinkage without re-implementing
five provider-schema-shaped counters that would drift on the next provider major."*

**Resolution.** The *property* the brief asked for is preserved in full and by a stronger mechanism:
a single-member allow-set means no address capable of carrying a nested block can appear in the plan
at all. The counter is cut; the guarantee is not. A replacement mutation row (**M9**, a superstring
address) tests the allow-set's exact-equality matching, which is the real failure mode.

### F5 — Zero new `workflow_dispatch` inputs are available, and none are needed

`workflow_dispatch` caps at 10 inputs; 7 are used, and the file carries a standing rule that the
next per-target **input pair** must split into a dedicated workflow rather than spend two more
slots (`:97-100`). The design as specified adds an `apply_target` **option** and reuses the
existing `confirm` input, spending zero slots — so it stays on the right side of that rule. Any
later temptation to add a `vector-redeliver`-specific input (a hash pin, a force flag) would
trip it.

This also confirms the brief's instruction to keep the token out of the `confirm` description:
that field's own comment says the exact token is *"deliberately not enumerated here"* and lives
in the target's runbook and job header (`:112`).

## Research Insights

### Premise Validation (Phase 0.6)

Every load-bearing claim carried in on the brief was re-verified against live state rather than
assumed. All held; two gained precision, and one cited fact was corrected.

| Claim | Verdict | Evidence |
|---|---|---|
| Issue #7542 open, unclosed | HOLDS | `gh issue view 7542` → `state: OPEN`, `closedByPullRequestsReferences: []`, labels `priority/p1-high`, `type/chore`, `domain/engineering` |
| Apply red on main at `19bbdb768` (run 31696609210) | HOLDS | `gh run view 31696609210` → `conclusion: failure`, `headSha 19bbdb76…`, `event: push`; `apply` job = failure, all dispatch jobs skipped |
| Plan is `5 to add, 1 to change, 1 to destroy` | HOLDS | run log: `Plan: 5 to add, 1 to change, 1 to destroy.` |
| The single destroy is journald_persistent replacing | HOLDS | run log: `# terraform_data.journald_persistent must be replaced`, preceded by `-/+ destroy and then create replacement` |
| `triggers_replace` hashes `vector.toml` | HOLDS | `server.tf:987-990` — `sha256(join(",", [file(journald-soleur.conf), file(vector.toml)]))` |
| #7457 (`0d6443960`) changed vector.toml by +43 lines | HOLDS | `git show --stat 0d6443960 -- …/vector.toml` → `1 file changed, 43 insertions(+)` |
| No server destroy / no reboot-forcing update in that plan | HOLDS | the only destructive line is the journald replace; no `hcloud_server` change appears |
| Guard reads `github.event.head_commit.message` (push-only) | HOLDS | `apply-web-platform-infra.yml:305` and `:439`; ack test at `:673` |
| `manual-rerun` routes to the same `apply` job | HOLDS | `apply` `if:` at `:332-334` = `… (github.event_name == 'push' \|\| inputs.apply_target == 'manual-rerun')` |
| `-target=terraform_data.journald_persistent` appears exactly once, at `:935` | HOLDS | `grep -n` returns exactly one hit, line 935 |
| `terraform_data.journald_persistent` defined at `server.tf:981` | HOLDS | exact line match |
| Create-time provisioners only, no `when = destroy` | HOLDS | `server.tf:1007-1087` — one `remote-exec` mkdir, two `file`, one closing `remote-exec`; no `when` argument anywhere in the block |
| Self-guards with a render-sanity gate + positive assertions | HOLDS | `server.tf:1075-1078` (pre-touch sanity) and `:1082-1085` (post-restart assertions) |
| The four out-of-scope creates are "inngest-consumer resources" | **CORRECTED** | Three are inngest-named (`betteruptime_heartbeat.inngest_consumer`, `doppler_secret.inngest_consumer_url`, `terraform_data.inngest_consumer_probe_install`); the fourth is `github_repository_environment_deployment_policy.web_platform_infra_apply_main`, which is not an inngest resource. The scope-out still stands — it is simply a 3+1, not a 4 |
| The wedge is still live | **UPDATED** | A **newer** red run exists than the brief cites: 31708799547 at `c723e45192f7` (2026-08-13 14:10Z), same `Plan: 5 to add, 1 to change, 1 to destroy`, same destroy-guard halt. The premise is not stale — it is if anything more current |

`[skip-web-platform-apply]` was confirmed verbatim from the live failure output as the
documented unwedge: *"add a line containing exactly '[skip-web-platform-apply]' to the merge
commit message … it skips the apply, it does not perform it."*

### Property List (Phase 0.6b)

1. A committed `vector.toml` change reaches the running web-1 without applying unrelated
   pending changes that happen to sit in the same plan.
2. A mis-dispatch (wrong target typed, wrong token) does not proceed.
3. The dispatch cannot destroy or mutate anything beyond the one named address.
4. Whoever fires this can confirm afterwards, without reaching the host, that delivery worked.
5. The gate is provably capable of refusing an out-of-scope plan.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Already covered by | Disposition |
|---|---|---|---|
| A new `workflow_dispatch` input to pin the expected `vector.toml` hash | 3 (id-pin) | The gate reads the **plan**, which is the authoritative statement of what will change; an input pin would restate it less reliably. Also blocked by the 10-input cap (F5) | **CUT** |
| A bespoke jq counter file for this arm | 3 | `tests/scripts/lib/plan-gate-preamble.sh` + the self-contained-jq-inside-the-gate idiom (`inngest-host-replace-gate.sh:85-116`) | **CUT** — reuse the established shape |
| A new test harness for the gate | 5 | `tests/scripts/lib/gate-suite-harness.sh` + the `test-<name>-gate.sh` convention, registered in `scripts/test-all.sh` | **CUT** — extend, do not invent |
| A dedicated workflow file for this target | 1 | The existing dispatch-job pattern; a split is only mandated when a new **input pair** is needed, which this is not (F5) | **CUT** |
| `[ack-destroy]`-style commit-trailer ack for the new arm | 2 | Structurally unavailable on dispatch (`head_commit.message` is empty); the menu-ack dispatch **is** the authorization per `hr-menu-option-ack-not-prod-write-auth` | **CUT** |

### Applicable conventions

- **Gate extraction is the dominant convention.** The decision logic lives in
  `tests/scripts/lib/<name>-gate.sh`, sourced by *both* the workflow step and the test, "so the
  CI decision logic is the SAME bytes the test exercises (no re-derived inline copy to drift)"
  (`inngest-host-replace-gate.sh:5-8`). The new gate follows this, not the inline-python shape
  that `ci_ssh_token_replace` still carries.
- **Fail-closed preamble is mandatory** (`plan-gate-preamble.sh`, #6997): `plan_gate_assert_readable`,
  `plan_gate_assert_classifiable`, `plan_gate_assert_numeric`. These refuse a plan document the
  gate cannot read, cannot classify, or whose counters did not evaluate — the shapes that
  otherwise score zero-of-everything and PASS.
- **Exact-equality address membership** via `IN(.address; allow[])`, never `inside`/`contains`
  (substring matching would false-match similar addresses) — `inngest-host-replace-gate.sh:83-84`.
- **Named, deliberately-redundant backstops are idiomatic**, not duplication: `redis_volume_destroyed`
  is "INTENTIONALLY REDUNDANT with the out-of-scope counter … kept as a named, loud backstop"
  (`inngest-host-replace-gate.sh:45-47`). The host-delete and nested-removal counters here follow that.
- **A no-op plan must abort loudly**, not pass: "A plan with zero replaces means the -replace
  silently did nothing — applying it would report success and repair nothing"
  (`apply-web-platform-infra.yml:5353-5355`).
- **Suite registration** is `run_suite "tests/scripts/<label>" bash tests/scripts/test-<name>.sh`
  in `scripts/test-all.sh` (gate cluster at `:982-1090`).
- **Audit trail must land**: every arm echoes its `reason` into `$GITHUB_STEP_SUMMARY`, because
  "requiring it is theatre" otherwise (`:5200-5207`).

### Open Code-Review Overlap

One substring hit, no real overlap. **#2197** (`refactor(billing): SubscriptionStatus type …`)
matched only because its body contains the string `apps/web-platform/infra/server.tf` in an
unrelated context; it concerns billing types, not this workflow. **Disposition: acknowledge** —
different concern, needs its own cycle, remains open. No open code-review issue names
`apply-web-platform-infra.yml`, `tests/scripts/lib/`, `scripts/test-all.sh`, or the runbooks
directory.

## Hypotheses

Required by Phase 1.4: this plan prescribes a `terraform apply -target=` against a resource whose
definition carries `provisioner "remote-exec"` and `connection { type = "ssh" }`
(`server.tf:992-998`, `:1007`), which makes SSH a hard apply-time dependency.

This is not an outage diagnosis — nothing is currently down. It is the **failure-triage order the
runbook must prescribe** for when the new arm's apply fails at its SSH step, recorded here so the
runbook cannot invert it into an sshd-first hunt. Per `hr-ssh-diagnosis-verify-firewall`, L3
before L7.

| Layer | Hypothesis for an SSH-step failure | Verification (off-host) | Status |
|---|---|---|---|
| **L3 — credential** | The CF Access `ci_ssh` service token is dead. CI reaches web-1 through the CF Tunnel bridge, so this is the L3-equivalent for the CI path — not `admin_ips` | The twice-daily token-drift detector's `verdict:` field; remedy is `apply_target=ci-ssh-token-replace` (`:196-201`) | **Not verified — verify first at incident time.** No current signal of failure |
| **L3 — firewall** | Operator egress IP drifted out of `var.admin_ips` | Applies to the **operator-local** apply path only, not this CI arm. `server.tf:976-980` names it explicitly: a `connection reset by peer` here "is admin-IP drift … NOT an sshd/journald fault". Remedy `/soleur:admin-ip-refresh`, runbook `admin-ip-drift.md` | Not verified; not on this arm's path |
| **L3 — tunnel/routing** | cloudflared tunnel unhealthy or the pinned binary mismatched | Bridge action `.github/actions/cf-tunnel-ssh-bridge`; pins `CLOUDFLARED_VERSION`/`_SHA256` at `:293-294` | Not verified |
| **L7 — service** | sshd config drift / fail2ban ban | **Last.** Only after all three L3 checks above are verified green | Not verified — deliberately last |

**Design consequence:** the runbook's troubleshooting section MUST list these in this order, and
MUST NOT open with an sshd or fail2ban hypothesis. This is the #2654→#2681 inversion the
checklist exists to prevent.

## Files to Create

| Path | Purpose |
|---|---|
| `tests/scripts/lib/vector-redeliver-gate.sh` | The sourced gate: `vector_redeliver_gate <plan-json>` → 0 = PASS, 1 = ABORT |
| `tests/scripts/test-vector-redeliver-gate.sh` | Mutation-matrix suite; sources the same gate bytes CI runs |
| `tests/scripts/test-vector-redeliver-wiring.sh` | Axis-D wiring suite (added at implementation time, modelled on `test-registry-d10-workflow-wiring.sh`). The gate suite proves the gate DECIDES correctly; nothing proved the workflow CALLS it, calls it on the artifact the apply consumes, or is gated on its verdict — and step ORDER (**F10**) is invisible to every unit test |
| `knowledge-base/engineering/operations/runbooks/vector-redeliver.md` | Operator runbook for the new target |

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/apply-web-platform-infra.yml` | Add `vector-redeliver` to the `apply_target` options list + a short clause in its description; add the `vector_redeliver` job |
| `scripts/test-all.sh` | Register the new suite in the gate cluster (`:982-1090`) |
| `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` | **Mandatory if the job is enrolled in `web-1-swap`** (F4): add an eighth `assert_member` line for `vector_redeliver` and bump the exact-count literal at `:173` from 7 to 8. The suite asserts equality, so an unlisted member fails it. Also correct the stale "SIX"/"== 6" prose. Note this suite runs only via `infra-validation.yml:1089` — **not** in `scripts/test-all.sh`, so AC22 will not catch it locally |
| `plugins/soleur/test/stock-preflight-coverage.test.ts` | **Mandatory (F8).** It reads the live `apply_target.options` enum and asserts every option is gated by `stock_preflight_gate` **or** declared in `EXCLUSION_ALLOWLIST` (`:224`, `:243-253`). Add an exclusion entry with a reason — the arm creates/replaces no `hcloud_server`, so the gate's `select(.type == "hcloud_server")` is a legitimate no-op. Mirror the `ci-ssh-token-replace` entry at `:108-129`. `:270-277` also asserts no *excluded* target carries the gate, so exclusion and job body must agree |
| `apps/web-platform/infra/server.tf` | Extend the post-restart assertions (`:1082-1085`) with `grep -q 'inngest-consumer-probe' /etc/vector/vector.toml`, so delivery of the #7228 web-1 tag is a property of the apply (**F9**). This is the only `.tf` edit, and it adds an assertion — no resource, provider or variable changes |
| `.github/CODEOWNERS` | Add a row for `tests/scripts/lib/vector-redeliver-gate.sh`; gate libs are enumerated individually at `:98-117` (**F15**) |

There is **no** `knowledge-base/engineering/operations/runbooks/README.md` (verified — the
directory carries no index file), so no index edit is required and none is prescribed.

Deliberately **not** edited: the `confirm` input description (F5), the main plan step's
`-target=` allow-list (this arm has its own plan step), and
`tests/scripts/lib/destroy-guard-filter-web-platform.jq` (that filter grades the push path; the
new arm carries its own gate).

## Implementation Phases

Phase order is load-bearing: the gate is a **contract** consumed by both the workflow and the
test, so it lands before either consumer.

### Phase 1 — The gate (contract first)

Write `tests/scripts/lib/vector-redeliver-gate.sh` modelled on
`tests/scripts/lib/inngest-host-replace-gate.sh`:

- Idempotent source of `plan-gate-preamble.sh` behind the `declare -F plan_gate_assert_readable`
  guard (`inngest-host-replace-gate.sh:60-64`).
- `plan_gate_assert_readable` + `plan_gate_assert_classifiable` as the function's first
  statements, each `|| return 1`.
- One `jq -n --slurpfile p` evaluation emitting **three** counters (not four — see **F6**):
  - `vector_out_of_scope_changes` — resource_changes with any of create/update/delete/forget
    whose address is not `IN(.address; allow[])`, where `allow` is the single-member list
    `["terraform_data.journald_persistent"]`.
  - `host_destroyed` — named backstop: any `hcloud_server.*` with delete/forget. Subsumed by the
    out-of-scope counter, but kept for the same reason `redis_volume_destroyed` is
    (`inngest-host-replace-gate.sh:45-47`): it gives a specific, legible "this dispatch would
    destroy web-1" line. Unlike the cut counter it is genuinely *reachable* — **F3** puts
    `hcloud_server.web["web-1"]` in this arm's plan.
  - `journald_delivered` — count of entries at the allowed address whose sorted actions are
    `["create","delete"]` **or** `["create"]` (per **F2**).
- `plan_gate_assert_numeric` over all three before any arithmetic comparison.
- **PASS iff** `vector_out_of_scope_changes==0 && host_destroyed==0 && journald_delivered==1`.
- Distinct, actionable ABORT messages per failure mode. The `journald_delivered==0` message must
  say **"no entry matched the allow-set"**, NOT "state already matches" — if the address is ever
  moved under `for_each`, exact-equality stops matching `…journald_persistent["web-1"]` and the
  counter reads 0 for a *broken allow-set*. Asserting "nothing to redeliver" there would emit the
  reassuring message for the alarming condition.
- **Gate header must record** (the decision content that would otherwise have gone in an ADR): the
  saved-`tfplan` assembly argument, why a bare `["create"]` is admitted (**F2**), why the
  `depends_on` edge was not removed (**F3**), and the un-indexed-address assumption above.

### Phase 2 — The mutation-matrix suite

Write `tests/scripts/test-vector-redeliver-gate.sh` using `tests/scripts/lib/gate-suite-harness.sh`
for fixture synthesis (fixtures are synthesized, never captured from a real plan, per
`cq-test-fixtures-synthesized-only`). It must implement every row of the Guard Contract matrix
below, and must assert its own non-vacuity (a case count > 0). Register it in `scripts/test-all.sh`.

### Phase 3 — The workflow job

Add `vector_redeliver` to `apply-web-platform-infra.yml`, modelled structurally on
`ci_ssh_token_replace` (`:5142-5400`):

- `if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'vector-redeliver'` —
  mutually exclusive with every other arm, and with `apply` (which requires `push` or
  `manual-rerun`).
- **`concurrency: group: web-1-swap`, `cancel-in-progress: false`** on top of the workflow-level
  group (**F4**).
- No `environment:` reviewer gate — consistent with every non-birth/non-recut arm (`:112`).
- Job header comment documenting the **real gate chain**: menu-ack dispatch is the authorization
  (`hr-menu-option-ack-not-prod-write-auth`); `confirm=REDELIVER-VECTOR` is only a typo-guard;
  the plan-reading gate is the mechanical protection; the token is recorded here and in the
  runbook, not in the `confirm` input description.
- `environment: web-platform-infra-apply` (**F7**) — the main-branch pin, not merely a reviewer
  click. This reverses the first draft.
- `timeout-minutes: 15`, matching `ci_ssh_token_replace` (**F15**).
- `permissions: contents: read` declared job-level, as the sibling does (`:5167-5168`).
- Steps, in this order (**corrected per F10**): checkout → setup-terraform → Doppler CLI →
  typo-guard (`REDELIVER-VECTOR` + non-empty `reason`, both env-routed, reason echoed to
  `$GITHUB_STEP_SUMMARY`) → ephemeral SSH pubkey for `var.ssh_key_path` → extract R2 backend creds →
  `terraform init` → **CF Tunnel SSH bridge** → `terraform plan -out=tfplan
  -target=terraform_data.journald_persistent` → **gate** (`terraform show -json tfplan` → source the
  lib → `if ! vector_redeliver_gate …`) → `terraform apply tfplan` → **`if: always()` bridge
  teardown**.
- **The bridge must precede the plan**, not follow the gate. It exports
  `TF_VAR_ci_ssh_private_key` into `$GITHUB_ENV` (`action.yml:199-203`); a plan produced before it
  bakes `null` → `agent = true` on an agent-less runner, and `apply <savedplan>` accepts no
  variable input, so the later export is inert. Full reasoning: **F10**.
- The teardown step is a caller obligation the composite action declares mandatory
  (`action.yml:33-58`), and is where the cloudflared log surfaces for the `## Hypotheses` L3 check.

### Phase 4 — Runbook

`knowledge-base/engineering/operations/runbooks/vector-redeliver.md`, matching the sibling shape
exactly (H1 `# Runbook — \`vector-redeliver\``, a bullet metadata block, then
`## When to fire this` / `## Preconditions` / `## Fire it` / `## What it does, and what protects
each step` / `## If it fails` / `## After it succeeds` / `## Known residual`) — verified against
`ci-ssh-token-replace.md`, which carries no YAML frontmatter. `## If it fails` MUST follow the
L3→L7 order from `## Hypotheses`. Verification is off-host only (see Observability).

### Phase 5 — Guard-suite sweep

Run every suite named in Acceptance Criteria, including the two that live OUTSIDE `scripts/test-all.sh`:
`web-1-swap-concurrency-parity.test.sh` (via `infra-validation.yml:1089`) and the vitest suites under
`plugins/soleur/test/`. No ADR is written — see Architecture Decision.

## Guard Contract

### Guard 1 — `vector_redeliver_gate`

**Property.** No apply fired by `apply_target=vector-redeliver` changes anything other than
exactly one delivery of `terraform_data.journald_persistent`.

**Assembly.** The gate quantifies over `.resource_changes[]` of the `terraform show -json`
document produced by *this job's own plan step* — the complete set of resources Terraform intends
to act on, not a list of addresses anyone enumerated. The chokepoint is single and structural:
the job runs exactly one `terraform plan -out=tfplan`, and exactly one `terraform apply tfplan`
that consumes **that saved plan file**; the gate reads the same artifact between them. Because
the apply consumes the saved plan rather than re-planning, no resource can enter the apply that
was absent from the graded document — the gate's scope and the apply's scope are the same object,
not two lists that must be kept in sync. This is why the gate must read the plan and not the
`-target` flags: `-target` is transitive and is a request, not a bound (**F3**). Which addresses
appear is a fact about current state and drifts; the assembly — one plan artifact, graded whole,
feeding one apply — is structural and does not.

**Mutation matrix.** Each row is an edit that MUST drive the guard RED. Derived from the design,
before the gate is written.

Rows carry an **Axis** column, because N edits on one axis is one mutation. The first draft had
eight rows that were really three axes, one of which was broken. Four axes are exercised: fixture
*content* (A), fixture *shape* (B), the *SUT itself* (C — mutating the gate file), and the
*workflow wiring* (D). A redundant backstop can only be pinned by a layered SUT mutation; a fixture
row for it is vacuous by construction, because the counter that subsumes it reddens first.

| # | Axis | Mutation | Must go RED via |
|---|---|---|---|
| M1 | A | **Second member:** a compliant journald delivery **plus** one more changed resource (`cloudflare_bot_management.soleur_ai`, `["update"]`) | `vector_out_of_scope_changes ≥ 1` — proves the gate does not stop at the first compliant entry |
| M2 | A | Journald entry's actions `["delete","create"]` → `["update"]` | `journald_delivered == 0` |
| M4 | A | Journald entry absent entirely (no-op plan) | `journald_delivered == 0` → **NO-OP SUCCESS** per **F12**: exit 0, skip bridge and apply, distinct step-summary line. Asserted as a green-with-summary, not a red |
| M7 | A | Two entries for the allowed address | `journald_delivered == 2 ≠ 1` |
| M9 | A | **Near-miss addresses:** `terraform_data.journald_persistent_v2` with `["update"]`, and separately `module.staging.terraform_data.journald_persistent` | `vector_out_of_scope_changes ≥ 1`. **The only row distinguishing `IN(.address; allow[])` from `inside`/`contains`** — with a one-member allow-set a prefix/`contains` implementation is otherwise indistinguishable. Models `test-inngest-host-replace-gate.sh:60-70` |
| M10 | A | **The measured D5 shape at an address F13 puts in the closure:** `rc_empty_actions 'hcloud_server.web["web-1"]'` — `"actions": []`, `"after": null` (`gate-suite-harness.sh:73-85`) | `vector_out_of_scope_changes ≥ 1`. A *measured* production hole — a hidden destroy of the singleton behind app.soleur.ai that scored zeroes and PASSED a sibling gate. Add `rc_scalar_change` (`:93-96`) alongside |
| M11 | A | Lone `["delete"]` (and separately `["forget"]`) at the **allowed** address | `journald_delivered != 1`. The most destructive single-address shape the arm can emit; `host_destroyed` is type-scoped to `hcloud_server` and out-of-scope excludes the allowed address, so nothing else catches it. M2 covers only the benign counterpart |
| M12 | A | A `hcloud_volume.workspaces[*]` delete in the closure | `host_destroyed ≥ 1` — the counter is extended to name volumes too (**F13**); these are sole-copy user data |
| M5a | B | Unreadable document (`{}` / invalid JSON / no `resource_changes`) | `plan_gate_assert_readable` |
| M5b | B | An unclassifiable plan entry | `plan_gate_assert_classifiable`, anchored on its `"unclassifiable plan entry"` text (`test-inngest-host-replace-gate.sh:153-156`) |
| M5c | B | A counter that fails to evaluate (empty string) | `plan_gate_assert_numeric`, naming the offending counter |
| M3 | C | `gate_mutate_layered`: neuter the `host_destroyed` clause, then feed `hcloud_server.web["web-1"]` with `["delete","create"]` | Plan **still refused** (by out-of-scope), `host_destroyed` text **gone**, out-of-scope text **appears**. The honest contract for a deliberately-redundant backstop — a *fixture* row here would be vacuous |
| M6b | C | Insert an early `return 0` in the gate | Already reddened by M1/M2/M7 — stated as **covered**, not claimed as an independent detector |
| M6a | D | The gate step stops invoking the gate, discards its status (`… \|\| true`), or gains `continue-on-error: true` | Separate wiring suite modelled on `test-registry-d10-workflow-wiring.sh`: `_strip` comments (`:49`), extract job + step (`:51-67`), hard vacuity floor if the extractor returns empty (`:71-82`), then anchor on the **call form** `^\s*if ! vector_redeliver_gate ` and on `^\s*source\s+\S*vector-redeliver-gate\.sh` — never a bare filename token (`stock-preflight-coverage.test.ts:207-215`: a bare `.includes` was satisfied by the `# shellcheck source=` directive alone), plus a negative assertion on `continue-on-error` |
| M6c | D | `terraform apply tfplan` rewritten to a re-plan (`-target=… -auto-approve`) | Assert `terraform plan -out=tfplan` occurs exactly once and the apply consumes the **saved** plan. Converts AC12/AC13 from checklist items into gate rows — the Assembly's claim rests on them and nothing else makes it true |
| M6d | D | The bridge step moved *after* the plan step | Assert bridge precedes plan (**F10**) — that ordering is what makes SSH auth possible at all |

Axis coverage A/B/C/D; M1 is the second-member row, M6a the own-dispatch row; 16 rows against a
floor of 3. **The suite's non-vacuity floor must be a numeric floor derived from a green run**
(`gate-suite-harness.sh:113-114`) and **self-contained** (bash builtins + the suite's own counters,
no harness call) — `test-inngest-host-replace-gate.sh:169-176` records a measured failure where a
harness-based floor whose `source` sat inside the deleted block exited 127 and the suite passed. A
bare `> 0` floor survives deleting all but one assertion, and counting assertions in the *test file*
has no bearing on whether the *workflow* invokes the gate — that was a category error in the first
draft's M6.

**M8 was cut, deliberately.** The first draft carried a "nested-block removal" row. It is
unfixturable for a `terraform_data` resource and would have been a green row proving nothing — the
vacuity this contract exists to prevent. Full reasoning and the preserved guarantee: **F6**.

**Two design corrections that follow from the matrix:**

1. **Use a NEGATIVE action filter**, not the positive four-member one. `vector_out_of_scope_changes`
   filtering positively on create/update/delete/forget silently admits any action verb Terraform
   adds later (ephemeral `open`/`close`, a future verb) at a non-allowed address. Mirror the ci_ssh
   gate's negative form (`apply-web-platform-infra.yml:5312-5316`): treat everything **except**
   `["no-op"]` and `["read"]` as a change. This matters more here than at the sibling gate, because
   with `host_destroyed` subsumed and the nested counter cut, out-of-scope is the *only* live
   address boundary.
2. **T1 must assert the PASS-path counter line.** `liveness_signal` and AC26 both depend on the gate
   printing its `name=value` tokens; nothing currently asserts it does
   (compare `inngest-host-replace-gate.sh:127`).

## Observability

```yaml
liveness_signal:
  what: the dispatch run's own conclusion + the gate's counter line echoed to the step log
        and the reason/outcome block in $GITHUB_STEP_SUMMARY
  cadence: on dispatch only (this is a deliberately-fired arm, not a scheduled one)
  alert_target: whoever fired the dispatch, via run conclusion; no paging channel is added
  configured_in: .github/workflows/apply-web-platform-infra.yml (vector_redeliver job)
error_reporting:
  destination: GitHub Actions run log + step summary; `::error::` annotations per failure mode
  fail_loud: true — the gate returns non-zero and the job fails; there is no continue-on-error
             and no swallow path. A refused plan fails before the SSH bridge opens.
failure_modes:
  - mode: gate refuses an out-of-scope plan
    detection: `::error::` naming the offending address + the four counters
    alert_route: run fails; the four counters are in the step log
  - mode: plan is a no-op (nothing to redeliver)
    detection: journald_delivered == 0 with the distinct "already matches state" message
    alert_route: run fails loudly rather than reporting a success that changed nothing
  - mode: SSH step fails (bridge/token/firewall)
    detection: apply step failure; triage order fixed by the ## Hypotheses table
    alert_route: run fails; runbook §If it fails routes L3→L7
  - mode: apply succeeds but delivery did not take
    detection: cannot occur silently — the resource's own post-restart assertions
               (server.tf:1082-1085) fail the provisioner if the identifiers are absent
               or the agent did not come back
    alert_route: run fails
logs:
  where: GitHub Actions run log (90d retention); host-side effects land in Better Stack
         via the Vector sink this arm delivers
  retention: 90 days (Actions); Better Stack per its configured plan
discoverability_test:
  command: bash tests/scripts/test-vector-redeliver-gate.sh
  expected_output: all mutation-matrix cases pass; suite reports a non-zero executed-case count
  # No credentials_required: the gate is a pure function over a JSON document, so the
  # property is fully verifiable locally with synthesized fixtures and no live infrastructure.
```

**Post-apply verification is off-host by construction** (`hr-no-ssh-fallback-in-runbooks`). The
runbook prescribes two independent reads, neither of which touches the host:

1. **Better Stack** via `scripts/betterstack-query.sh` — confirm the #7228 boot-trace
   `SyslogIdentifier`s are arriving from web-1 (they are dark today precisely because #7457's
   config never reached the host). Credentials read-only from Doppler `soleur/prd_terraform`.
2. **The cat-deploy-state webhook** — confirm `vector_journal_tail` is non-empty and
   `journald_storage.persistent=true`. This is the exact check the resource's own comment names
   as its no-SSH post-apply verification path (`server.tf:1043-1045`).

The precise flag spellings for both commands are pinned during /work against
`scripts/betterstack-query.sh --help` and an existing caller, per the CLI-verification gate — the
runbook must not carry an unverified invocation.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file is added or modified. The resource this arm applies
(`terraform_data.journald_persistent`, `apps/web-platform/infra/server.tf:981-1088`) already
exists and is already Terraform-managed; this plan adds a **scoped apply path** for it, not a new
resource. No new provider, no new version pin, no new variable, and therefore no new
`TF_VAR_*` to provision — which also means the `hr-tf-variable-no-operator-mint-default` hazard
does not arise.

### Apply path

**(c-scoped) dispatch-fired `terraform apply` of a saved, gate-graded plan**, scoped by
`-target=terraform_data.journald_persistent`. Not cloud-init: web-1 never re-runs cloud-init
(`ignore_changes=[user_data]`), which is exactly why this SSH provisioner path is the sole live
delivery route (`server.tf:968-971`, `:984-986`).

**Blast radius:** one `terraform_data` state entry replaced; on the host, the journald drop-in and
`/etc/vector/vector.toml` are rewritten and the journal daemon and Vector agent are reloaded.
Expected disruption is sub-second and gapless by design — Vector's journald sources read by
`sd_journal` cursor, so they resume from the stored cursor (`server.tf:1040-1043`). No container
restart, no application downtime, no host reboot.

### Distinctness / drift safeguards

- Production-only by construction: the arm targets the `prd_terraform` Doppler config and the
  `web-1` host; there is no dev counterpart to confuse it with.
- The R2 backend has **no state lock** (`main.tf use_lockfile = false`), so serialization is by
  GitHub concurrency group alone — hence both the workflow-level
  `terraform-apply-web-platform-host` group and the narrower `web-1-swap` group (**F4**).
- `cancel-in-progress: false` on both, per `hr-multi-step-post-merge-bootstrap-script`.
- The arm cannot widen silently: any address beyond the single allowed one fails the gate.

### Vendor-tier reality check

Not applicable — no vendor resource is created. Better Stack and Cloudflare are read/traversed,
not provisioned.

### Conditional-gate determinations

Two deepen-plan gates were evaluated and found not to fire. Recording the reasoning so a later
reader does not have to re-derive it, and so a wrong call is visible rather than silent.

**Downtime & Cutover (deepen Phase 4.55) — does not fire.** None of the three trigger classes
match. *Infra reboot/replace:* no `hcloud_server`, volume or attachment is replaced — the gate
actively **refuses** such a plan (M3), so the arm cannot reach that state. *Database lock:* no
migration. *Deploy/router:* no container swap, no tunnel restructure, no drain-less connector
restart on a serving connector — Vector and journald are the observability plane, not the serving
path, and the application container is untouched. The journal-daemon and agent reloads are
sub-second and gapless by design (`sd_journal` cursor resumption, `server.tf:1040-1043`). Note
this is the *inverse* of the class the gate guards: the arm exists to restore observability, and
the one serving-adjacent hazard (a botched render darkening the agent) is already held by the
resource's own pre-touch render-sanity gate.

**Encryption Posture (deepen Phase 4.10) — does not fire.** No file in Files to Create/Edit
matches `\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, or
`docker-compose.*\.ya?ml$`. The prose does name a log sink (`[sinks.betterstack]`), which is why
this determination is written down rather than assumed — but the gate's own skip condition is "a
change confined to an already-provisioned surface", and that is exactly what this is: no store is
introduced, no connection is created, and the Better Stack sink and its transport already exist
and are unchanged by this plan.

## Architecture Decision (ADR/C4)

### ADR — none. The trigger does not fire, and the first draft's two justifications were both false.

The first draft proposed `ADR-187`. Review falsified both reasons it gave:

1. *"The runbook template's metadata block has a required **ADR:** field."* **There is no runbook
   template** — no `*runbook*template*` file exists. Of the **61** runbooks in
   `knowledge-base/engineering/operations/runbooks/`, exactly **one** carries a `- **ADR:**`
   bullet: `ci-ssh-token-replace.md`, the single file the first draft happened to read. Its nearest
   sibling `web-host-replace.md` has no metadata block at all. A "required field" generalized
   from n=1.
2. *"Every sibling dispatch arm carries one."* Three named out of fourteen `apply_target` options.
   The unnamed ones are the counterexample: **`registry-host-replace` — a destructive production
   host replace — has no arm ADR**, and neither do `git-data-host-replace` or
   `inngest-host-replace`. Only ADR-148 is a true "new arm ⇒ new ADR" precedent, and it granted the
   capability to destroy a production host. This arm re-runs create-time provisioners on a
   `terraform_data` that the push path already runs on every merge.

**`wg-architecture-decision-is-a-plan-deliverable` does not fire**, by this plan's own C4 analysis
below: no ownership or tenancy boundary moves, no new substrate, no trust-boundary change, no
reversal or extension of an existing ADR. The plan proved the trigger absent and then proposed the
ADR anyway.

**Where the decision content goes instead:** the gate file header — which is where every other gate
in `tests/scripts/lib/` records its reasoning, and where the person changing the gate will actually
read it. It must carry the saved-`tfplan` assembly argument, the **F2** bare-create admission, the
**F10** bridge-before-plan ordering, the **F13** closure and its dated `ignore_changes` brick, and
the **F6** note that a nested-removal backstop is not applicable to a `terraform_data` address (so
nobody re-adds it).

**This also removes an AC that could not be satisfied deterministically.** The draft's AC18 pinned a
provisional ordinal that a concurrent, unrelated PR could invalidate with no line of this diff
changing — the `cq-ac-must-not-depend-on-concurrent-sessions` shape. Cutting the ADR deletes the
AC, the ordinal-collision risk row, the re-derivation ceremony, and half of Phase 5 in one move.

### C4 views

**No C4 impact.** Checked against all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — for each class
the completeness mandate requires:

- **External human actors:** none added. Whoever fires a dispatch is an existing modelled role;
  this adds a menu option, not a new actor.
- **External systems / vendors:** none added. Cloudflare (Access/Tunnel), Better Stack, Hetzner
  and Doppler are all already modelled and already reached by the existing apply path; this arm
  introduces no new vendor edge.
- **Containers / data stores:** none added or removed. web-1, its Vector agent and the journald
  store are existing elements; no new store appears.
- **Access relationships:** unchanged. The arm reaches web-1 over the **existing** CF Tunnel SSH
  bridge with the **existing** `ci_ssh` credential, and delivers a config file already delivered
  by the same resource on the push path. No ownership or trust boundary moves.

The change is a new *trigger* for an existing edge, not a new edge — which is precisely the case
the mandate's "would a competent engineer be misled?" test answers *no* for.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no user-facing surface is
touched. The realistic failure is indirect: a gate that refuses a legitimate plan leaves
`vector.toml` changes undeliverable, so web-1's boot-trace and probe telemetry stay dark and the
founder keeps learning about host failures late, from symptoms rather than from signal. That is
the #7228 condition this arm exists to end, prolonged rather than caused.

**If this leaks, the user's data is exposed via:** no new data path. The arm moves a committed,
non-secret config file (`vector.toml`, with a `@@HOST_NAME@@` sentinel rendered from Terraform)
onto a host that already runs it. The credentials it uses (R2 backend keys, the `ci_ssh` Access
token, `DOPPLER_TOKEN`) are the same ones the existing apply path already handles, all env-routed
and masked. The one genuinely new capability is a dispatch that can reload the Vector agent on
web-1 — a botched render there would dark host observability, which is why the resource's
pre-touch render-sanity gate (`server.tf:1068-1078`) runs before the live agent is touched and
the post-restart assertions (`:1082-1085`) fail the apply if it does not come back.

**Brand-survival threshold:** none

*Sensitive-path scope-out:* `threshold: none, reason: this change adds a gated CI dispatch arm
over an existing Terraform-managed config-delivery resource; it introduces no user-facing surface,
no new data processing, no new credential, and no new external egress.*

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure/CI change confined to a dispatch-only apply arm, its gate, its
tests, a runbook and an ADR. The load-bearing engineering concerns surfaced during planning and
are folded into the design: `-target` transitivity means the gate must grade the produced plan
rather than the flag list (**F3**); the arm mutates live web-1 daemons so it needs the
`web-1-swap` mutex, not just the terraform-apply group (**F4**); the input budget forbids new
dispatch inputs (**F5**); and the literal reading of "exactly one replace" would brick the arm in
the state where it is most needed (**F2**). Gate logic is extracted and shared with its test so
CI and the suite exercise the same bytes.

### Product/UX Gate

Not applicable — Product is not relevant. The mechanical UI-surface override does not fire: no
path in Files to Create/Edit matches any UI-surface glob (`components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`, or the shared UI-surface term list). The only
externally-visible surface is a `workflow_dispatch` dropdown option and a markdown runbook.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `[ack-destroy]` on the merge commit | Applies the **whole** pending plan, including `terraform_data.inngest_consumer_probe_install`, which provisions a host currently under repair. Explicitly out of scope, and the reason the unwedge must be `[skip-web-platform-apply]` instead |
| `apply_target=manual-rerun` | Routes to the same `apply` job (`:332-334`) and halts on the same guard, because `head_commit.message` is empty on dispatch. Structurally cannot work |
| Remove `depends_on = [terraform_data.journald_persistent]` from `inngest_consumer_probe_install`, or drop the probe from the main `-target` list | Would stop journald_persistent riding the guarded plan (**F3**) — a genuinely smaller change. Rejected: the `depends_on` is load-bearing ordering (the probe's fault classification is only readable off-box once Vector carries its identifier, `server.tf:750-753`), and dropping the probe target would strand #7462's own delivery. It also fixes the symptom for *this* pending change only; the next `vector.toml` edit that coincides with unrelated drift reproduces it |
| Add `-replace=terraform_data.journald_persistent` to the new arm | Would let the arm force a redelivery even when state already matches the committed file — useful if the host's `/etc/vector/vector.toml` drifted without a config change. Not adopted: it widens the arm from "deliver the committed config" to "force a reload of web-1's logging agents on demand", which is a different capability with a different blast radius. Recorded as a **deliberate limitation**, not an oversight — see Known Residual in the runbook, and file a tracking issue if a drift-only redelivery is ever needed |
| A dedicated workflow file for this target | Only mandated when a new **input pair** is needed; this arm adds none (**F5**). A split would fragment the shared concurrency group for no gain |

## Test Scenarios

All fixtures synthesized, never captured from a live plan (`cq-test-fixtures-synthesized-only`).

| # | Scenario | Expect |
|---|---|---|
| T1 | Compliant plan: single journald entry, actions `["delete","create"]` | PASS |
| T2 | Compliant recovery plan: single journald entry, actions `["create"]` (**F2**) | PASS |
| T3 | Journald entry + no-op entries for other addresses (`["no-op"]`) | PASS — no-op is not a change |
| T4 | Journald entry + a `["read"]` data-source entry | PASS — deferred data reads are not mutations (`:5305-5309`) |
| T5–T12 | Mutation matrix rows M1–M8 | RED, each with its named counter/message |
| T13 | Workflow wiring: the `vector_redeliver` job's gate step sources the lib and calls the function; the job carries `concurrency.group: web-1-swap` | PASS |
| T14 | Arm exclusivity: `vector-redeliver` appears in the `apply_target` options list, and the `apply` job's `if:` does not admit it | PASS |
| T15 | Suite non-vacuity: executed-case count > 0 | PASS |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `hcloud_server.web["web-1"]` carries a pending change when the arm is fired, silently entering the plan via transitivity (**F3**) | The gate refuses it (M3 / out-of-scope). The arm fails closed rather than rebooting prod |
| A botched `vector.toml` render darks all web-1 observability | Pre-touch render-sanity gate runs before the live agent is touched (`server.tf:1068-1078`); post-restart positive assertions fail the apply if the agent does not return (`:1082-1085`). Both already exist |
| Concurrent LUKS cutover or release deploy mutating web-1 | `web-1-swap` mutex, `cancel-in-progress: false` (**F4**) |
| Gate too tight → arm bricked when most needed | **F2** refinement admits the bare-create recovery shape; M4's distinct message distinguishes "nothing to do" from "gate is broken" |
| Merging this PR re-fires the still-wedged push apply | The `[skip-web-platform-apply]` merge-commit requirement, carried as a first-class AC below |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `tests/scripts/lib/vector-redeliver-gate.sh` exists and defines
      `vector_redeliver_gate`; it sources `plan-gate-preamble.sh` behind the `declare -F` guard
      and calls `plan_gate_assert_readable`, `plan_gate_assert_classifiable` and
      `plan_gate_assert_numeric`.
- [ ] **AC2** — The gate's `allow` list has exactly one member,
      `terraform_data.journald_persistent`, and membership is tested with `IN(.address; allow[])`
      (exact equality), not `inside`/`contains`.
- [ ] **AC3** — The gate PASSES a single-delivery plan in **both** shapes: actions
      `["delete","create"]` and actions `["create"]` (**F2**).
- [ ] **AC4** — Every mutation-matrix row drives the gate RED. Verified by
      `bash tests/scripts/test-vector-redeliver-gate.sh` exiting 0 with all cases asserted, and
      by the suite reporting a non-zero executed-case count (anti-vacuity).
      *(Two rows moved at implementation time, both measured. **M4** is green-with-summary rather
      than RED, per **F12**. **M10a** asserts "unclassifiable plan entry" rather than "outside the
      allow-set": the design predicted out-of-scope, but the fail-closed preamble refuses the
      empty-actions shape first — measured, the negative filter counts that shape (1) and the
      positive filter scores 0.)*
- [ ] **AC5** — `bash tests/scripts/test-vector-redeliver-gate.sh` is registered in
      `scripts/test-all.sh` and runs in the gate cluster.
- [ ] **AC5b** — `bash tests/scripts/test-vector-redeliver-wiring.sh` exists, is registered in
      `scripts/test-all.sh` beside the gate suite, and pins its own assertion count EXACTLY
      (anti-vacuity). Its rows anchor on the CALL FORM (`^\s*if ! vector_redeliver_gate "…"` and
      `^\s*source "…/vector-redeliver-gate.sh"`), never a bare filename token — the hole
      `stock-preflight-coverage.test.ts:207-215` records, where a `# shellcheck source=` directive
      alone satisfied the check. Mutation-proved against the job: a re-planning apply, a
      `continue-on-error` gate step, a deleted `environment:` pin, a renamed/gutted bridge step and
      a bridge physically MOVED after the gate each drive it RED.
- [ ] **AC6** — The `vector_redeliver` job's `if:` is exactly
      `github.event_name == 'workflow_dispatch' && inputs.apply_target == 'vector-redeliver'`,
      and `vector-redeliver` is present in the `apply_target` `options:` list.
- [ ] **AC7** — The job carries `concurrency: {group: web-1-swap, cancel-in-progress: false}`
      (**F4**), and `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` passes. If
      that suite enumerates member jobs, the new job is registered in it.
- [ ] **AC8** — The job's typo-guard requires `confirm == 'REDELIVER-VECTOR'` and a non-empty
      `reason`, both routed through `env:` and compared as data; the reason is echoed into
      `$GITHUB_STEP_SUMMARY`.
- [ ] **AC9** — `REDELIVER-VECTOR` appears in the job header comment and in the runbook, and
      **does not** appear in the `confirm` input's `description:` (F5, `:112`).
- [ ] **AC10** — The job header documents the real gate chain: menu-ack dispatch is the
      authorization; `confirm` is a typo-guard only; the plan-reading gate is the mechanical
      protection.
- [ ] **AC11** — No new `workflow_dispatch` input is added; the input count remains 7 (**F5**).
- [ ] **AC12** — *(rewritten by **F10**, which supersedes the original "gate before bridge"
      wording — that ordering cannot authenticate SSH, and F10 records why the original goal costs
      nothing to give up.)* The gate step runs **before the apply**, and the CF Tunnel SSH bridge
      runs **before the plan**. Asserted mechanically by
      `tests/scripts/test-vector-redeliver-wiring.sh` (rows `M6d`), which reads the step order out
      of the job body — the one property no unit test can see.
- [ ] **AC13** — The apply step consumes the **saved** `tfplan` graded by the gate, not a
      re-plan (Guard Contract assembly).
- [ ] **AC14** — `knowledge-base/engineering/operations/runbooks/vector-redeliver.md` exists and
      matches the sibling heading set of `ci-ssh-token-replace.md`.
- [ ] **AC15** — The runbook's `## If it fails` orders triage L3→L7 per `## Hypotheses`, and does
      not open with an sshd or fail2ban hypothesis (`hr-ssh-diagnosis-verify-firewall`).
- [ ] **AC16** — The runbook contains **no** `ssh ` invocation (`hr-no-ssh-fallback-in-runbooks`)
      and prescribes both off-host reads: the Better Stack query for the #7228
      `SyslogIdentifier`s and the cat-deploy-state webhook check for `vector_journal_tail`
      non-empty + `journald_storage.persistent=true`.
- [ ] **AC17** — Every CLI invocation the runbook embeds is verified at authoring time (a real
      `--help` output or an existing caller cited), per the CLI-verification gate.
- [ ] **AC19** — `plugins/soleur/test/terraform-target-parity.test.ts` passes (**F1**).
- [ ] **AC20** — `bash tests/scripts/test-destroy-guard-regex-parity.sh` passes — the new arm adds
      no `[ack-destroy]` regex site, so the seven-site pin is unchanged.
- [ ] **AC21** — `actionlint` passes on `apply-web-platform-infra.yml`, and each new embedded
      `run:` snippet parses under `bash -c` (never `bash -n` on the YAML).
- [ ] **AC22** — Full suite green: `bash scripts/test-all.sh`.

### Merge (load-bearing — must not be lost at ship)

- [ ] **AC23** — **The merge commit message carries a line containing exactly
      `[skip-web-platform-apply]`.** This file is in the workflow's own push `paths:` (`:86`), so
      merging re-triggers the push apply, which is *still wedged* on the same destroy-guard
      (confirmed live at run 31708799547). `[skip-web-platform-apply]` is the documented unwedge
      and skips the apply without performing it.
- [ ] **AC24** — **The merge commit must NOT carry `[ack-destroy]`.** That would apply the four
      pending creates plus the `cloudflare_bot_management` update, all of which belong to #7462 /
      PR #7516 / #7539 and are out of scope here. *(Rationale corrected per **F11**: the first draft
      said `terraform_data.inngest_consumer_probe_install` "provisions a host currently under
      repair". It provisions **web-1** — `server.tf:767-772`, and `:743-748` states "Nothing here
      touches 10.0.1.40, which is the point". The scope-out stands on ownership — those resources
      belong to another PR — not on host risk.)*
- [ ] **AC24b** — The plan states the **intended end state** for the four pending creates, per
      **F11**: a successful dispatch drops `destroy_count` to 0, so the next merge touching a
      `paths:` file will apply them unattended. Name an owner and a deadline, or state explicitly
      that this is the intended release path.
- [ ] **AC25** — PR body uses `Closes #7542`.

### Post-merge (dispatch-gated)

*Automation note: `gh workflow run` can fire this arm, and `/ship` could technically call it. It
is deliberately left as a separate deliberate dispatch because the menu-ack dispatch **is** the
human authorization for a production write per `hr-menu-option-ack-not-prod-write-auth` — this is
an authorization boundary, not an un-automatable step.*

- [ ] **AC26** — Dispatch `apply_target=vector-redeliver` with `confirm=REDELIVER-VECTOR` and a
      reason; the run succeeds and its gate line reports
      `vector_out_of_scope_changes=0 host_destroyed=0 journald_entries=1 journald_delivered=1`.
      *(Counter list corrected at implementation time. The first draft wrote `nested_removals=0`,
      a counter **F6** had already cut as unimplementable for a `terraform_data` — so as written
      this AC asserted a string the gate can never print. The shipped gate emits FOUR counters,
      the fourth being `journald_entries`, which is a different counter and does not reopen the F6
      cut: it exists because a lone `["delete"]` at the allowed address scores
      `journald_delivered=0` while `host_destroyed` is type-scoped and out-of-scope excludes the
      allowed address — so under three counters the most destructive shape this arm can emit would
      have hit **F12**'s NO-OP SUCCESS and printed "nothing to redeliver" for a plan that destroys
      the delivery resource.)*
      Per **F12**, `journald_delivered=1` is assertable only on the **first** dispatch; a
      re-dispatch legitimately reports the NO-OP line instead, which is also a success.
- [ ] **AC27** — Off-host confirmation, no SSH (**rewritten per F9** — the briefed version was
      unsatisfiable, because the #7228 boot-trace identifiers are emitted on the *inngest* host,
      not web-1). Three checks, none of which asserts an absence:
      (a) the apply's own extended post-restart assertion confirms `inngest-consumer-probe` is
      present in web-1's `/etc/vector/vector.toml`;
      (b) the cat-deploy-state webhook reports `vector_journal_tail` non-empty and
      `journald_storage.persistent=true`;
      (c) **positive control** — Better Stack returns rows for an identifier web-1 genuinely emits
      (`sshd` / `ci-deploy`) at `host_name=soleur-web-platform` with a timestamp after the restart,
      proving the agent returned and the sink still works. Via
      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep <marker>`.
      Verification of `inngest-boot-phone-home` / `inngest-bs-token-restage` belongs to
      `apply_target=inngest-host-replace` under #7462 and is recorded in the runbook's Known
      Residual, not asserted here.
- [ ] **AC28** — `gh issue close 7542` only after AC26 + AC27 both hold.
