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

**Open check for /work:** `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` is a
drift-guard over this group (invoked at `infra-validation.yml:1088-1089`). I have not read it.
If it enumerates the set of jobs required to hold the group, the new job must be registered
there — an orphan-suite miss of exactly the class the `-target`-allowlist learning warns about.

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
| `knowledge-base/engineering/operations/runbooks/vector-redeliver.md` | Operator runbook for the new target |
| `knowledge-base/engineering/architecture/decisions/ADR-187-scoped-vector-config-redelivery-arm.md` | The decision record (ordinal **provisional** — see Architecture Decision below) |

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/apply-web-platform-infra.yml` | Add `vector-redeliver` to the `apply_target` options list + a short clause in its description; add the `vector_redeliver` job |
| `scripts/test-all.sh` | Register the new suite in the gate cluster (`:982-1090`) |

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
- One `jq -n --slurpfile p` evaluation emitting four counters:
  - `vector_out_of_scope_changes` — resource_changes with any of create/update/delete/forget
    whose address is not `IN(.address; allow[])`, where `allow` is the single-member list
    `["terraform_data.journald_persistent"]`.
  - `host_destroyed` — named backstop: any `hcloud_server.*` with delete/forget.
  - `nested_removals` — named backstop for nested-block shrinkage on an in-allow-set address.
  - `journald_delivered` — count of entries at the allowed address whose sorted actions are
    `["create","delete"]` **or** `["create"]` (per **F2**).
- `plan_gate_assert_numeric` over all four before any arithmetic comparison.
- **PASS iff** `vector_out_of_scope_changes==0 && host_destroyed==0 && nested_removals==0 && journald_delivered==1`.
- Distinct, actionable ABORT messages per failure mode — in particular a `journald_delivered==0`
  message that says *nothing to redeliver: the committed vector.toml already matches state*,
  so a no-op is never mistaken for a gate defect.

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
- Steps: checkout → setup-terraform → Doppler CLI → typo-guard (`REDELIVER-VECTOR` + non-empty
  `reason`, both env-routed, reason echoed to `$GITHUB_STEP_SUMMARY`) → ephemeral SSH pubkey for
  `var.ssh_key_path` → extract R2 backend creds → `terraform init` → `terraform plan -out=tfplan
  -target=terraform_data.journald_persistent` → **gate** (`terraform show -json tfplan` → source
  the lib → `vector_redeliver_gate`) → CF Tunnel SSH bridge → `terraform apply tfplan`.
- The bridge is required because the resource's provisioners are SSH-borne (`server.tf:992-998`);
  it is placed **after** the gate so a refused plan never opens a tunnel.

### Phase 4 — Runbook

`knowledge-base/engineering/operations/runbooks/vector-redeliver.md`, matching the sibling shape
exactly (H1 `# Runbook — \`vector-redeliver\``, a bullet metadata block, then
`## When to fire this` / `## Preconditions` / `## Fire it` / `## What it does, and what protects
each step` / `## If it fails` / `## After it succeeds` / `## Known residual`) — verified against
`ci-ssh-token-replace.md`, which carries no YAML frontmatter. `## If it fails` MUST follow the
L3→L7 order from `## Hypotheses`. Verification is off-host only (see Observability).

### Phase 5 — ADR + wiring sweep

Write the ADR; re-verify the ordinal against freshly-fetched `origin/*` immediately before merge.
Run the sweep suites named in Acceptance Criteria.

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

| # | Mutation to the graded plan (or to the wiring) | Must go RED via |
|---|---|---|
| M1 | **Second member:** a compliant journald delivery **plus** one more changed resource (e.g. `cloudflare_bot_management.soleur_ai` with `["update"]`) | `vector_out_of_scope_changes ≥ 1` — proves the gate does not stop at the first compliant entry |
| M2 | Journald entry's actions changed from `["delete","create"]` to `["update"]` | `journald_delivered == 0` |
| M3 | `hcloud_server.web["web-1"]` present with `["delete","create"]` | `host_destroyed ≥ 1` (and out-of-scope) |
| M4 | Journald entry absent entirely (no-op plan) | `journald_delivered == 0`, with the "nothing to redeliver" message |
| M5 | Plan document unreadable / not classifiable (`{}`, invalid JSON, no `resource_changes` key) | fail-closed preamble asserts |
| M6 | **Own dispatch:** the workflow's gate step stops invoking `vector_redeliver_gate` (removed call, or a return before counters evaluate) | wiring assertion that the job's gate step sources the lib **and** calls the function, plus the suite's own non-vacuity floor (cases-executed > 0) |
| M7 | Two entries for the allowed address in one document | `journald_delivered == 2 ≠ 1` |
| M8 | Nested-block removal on the allowed address | `nested_removals ≥ 1` |

M1 satisfies the second-member requirement; M6 satisfies the own-dispatch requirement; the matrix
is 8 rows against a floor of 3.

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

### ADR

**Create `ADR-187` — "Scoped vector-config redelivery arm".** Every sibling dispatch arm carries
one (ADR-145 web-host-create, ADR-148 web-host-replace, ADR-154 ci-ssh-token-replace), and the
runbook template's metadata block has a required **ADR:** field, so omitting it leaves a
structural hole. The decision to record: *a config artifact whose delivery is coupled to an
unrelated apply plan gets its own gated delivery arm, rather than being unblocked by acking
through the shared plan.* Its `## Alternatives Considered` must carry the five entries in
Alternative Approaches below.

**The ordinal is provisional.** ADR-186 is the highest present across `origin/main` **and** all
`origin/*` refs as of this writing, so 187 is the next free one — but a sibling PR can claim it
mid-pipeline, and these only surface together post-squash. Re-derive against a fresh fetch
immediately before merge, and if it moves, sweep this plan, `tasks.md`, and any AC naming the
ordinal in the same edit.

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
| ADR ordinal collision mid-pipeline | Re-derive against fresh `origin/*` before merge; sweep plan + tasks + ACs in the same edit if it moves |
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
- [ ] **AC4** — Every mutation-matrix row M1–M8 drives the gate RED. Verified by
      `bash tests/scripts/test-vector-redeliver-gate.sh` exiting 0 with all cases asserted, and
      by the suite reporting a non-zero executed-case count (anti-vacuity).
- [ ] **AC5** — `bash tests/scripts/test-vector-redeliver-gate.sh` is registered in
      `scripts/test-all.sh` and runs in the gate cluster.
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
- [ ] **AC12** — The gate step runs **before** the CF Tunnel SSH bridge step, so a refused plan
      never opens a tunnel.
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
- [ ] **AC18** — `ADR-187` (or its re-derived ordinal) exists, records the decision, and its
      `## Alternatives Considered` carries all five rows from Alternative Approaches. If the
      ordinal moved, `grep -rn 'ADR-187' knowledge-base/project/{plans,specs}/` returns no stale
      hits.
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
      pending creates — including `terraform_data.inngest_consumer_probe_install`, which
      provisions a host currently under repair — plus the `cloudflare_bot_management` update. All
      of those belong to #7462 / PR #7516 / #7539 and are out of scope here.
- [ ] **AC25** — PR body uses `Closes #7542`.

### Post-merge (dispatch-gated)

*Automation note: `gh workflow run` can fire this arm, and `/ship` could technically call it. It
is deliberately left as a separate deliberate dispatch because the menu-ack dispatch **is** the
human authorization for a production write per `hr-menu-option-ack-not-prod-write-auth` — this is
an authorization boundary, not an un-automatable step.*

- [ ] **AC26** — Dispatch `apply_target=vector-redeliver` with `confirm=REDELIVER-VECTOR` and a
      reason; the run succeeds and its gate line reports
      `vector_out_of_scope_changes=0 host_destroyed=0 nested_removals=0 journald_delivered=1`.
- [ ] **AC27** — Off-host confirmation, no SSH: the #7228 boot-trace `SyslogIdentifier`s appear in
      Better Stack for web-1 (dark before this dispatch), **and** the cat-deploy-state webhook
      reports `vector_journal_tail` non-empty with `journald_storage.persistent=true`.
- [ ] **AC28** — `gh issue close 7542` only after AC26 + AC27 both hold.
