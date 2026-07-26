---
title: "feat: generic web-host-replace dispatch target + rebirth of the dark soleur-web-2"
date: 2026-07-26
type: enhancement
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 6969
branch: feat-one-shot-6969-web-host-replace
pr: 6973
---

# feat: generic `web-host-replace` dispatch target + rebirth of the dark `soleur-web-2`

## Overview

`soleur-web-2` is dark and there is **no mechanism to replace it**. This plan builds one — a
generic, gated `apply_target=web-host-replace` dispatch job over `var.web_hosts` keys — and then
uses it to rebirth web-2 onto an image carrying the boot-stage error channel.

The capability gap is the whole point: `web-host-create` is *additive-only* and its inverted birth
gate demands **exactly one create**; web-2 is present in state, so a plan yields zero creates and
the gate correctly aborts. The birth gate's own header already anticipates this work:

> *"Scoped host REPLACEMENT is a different operation with a different gate; it does not borrow
> this one."* — `tests/scripts/lib/web-host-birth-gate.sh`

So this is not a modification of the birth path. It is its sibling.

**The single most important safety property**: a web host owns **two** persistent volume families
(`hcloud_volume.workspaces` and `hcloud_volume.workspaces_luks`). A replace must destroy the
**server** and preserve **both volumes**. The `git-data-host-replace` precedent already solved this
shape — volumes are *preserved by omission* (an untargeted resource cannot be planned for destroy),
with named backstops for high-value error text.

## Research Reconciliation — Claims vs. Codebase

Every row measured this session against the worktree, not recalled.

| Claim | Reality | Plan response |
|---|---|---|
| "`web-host-replace` does not exist" | **Confirmed** — 0 occurrences on `main`; no `web_host_replace` job; only `web-host-birth-gate.sh` in `tests/scripts/lib/` | Build it |
| "`web-host-create` can rebirth an existing host" | **False** — birth gate aborts on `creates != 1`, and explicitly refuses a no-op ("the host already exists (a no-op the gate must not rubber-stamp)") | Separate gate, not a widened birth gate |
| "There is a `-replace` precedent" | **True and better than expected** — `git-data-host-replace-gate.sh`, `registry-host-replace-gate.sh`, `inngest-host-replace-gate.sh` all exist | Mirror git-data (closest: dual volumes + LUKS) |
| "web hosts have one volume" | **False** — `hcloud_volume.workspaces` (`server.tf:1627`) AND `hcloud_volume.workspaces_luks` (`workspaces-luks.tf:207`) | Both preserved by omission; two named backstops |
| "The environment gate is real" | **True** — `web-platform-infra-apply` is declared in `apps/web-platform/infra/web-host-birth-environment.tf` with `reviewers.users = [54279]` **and** a `main`-only `deployment_branch_policy` | Reuse as-is; do **not** re-declare |
| "web-2 has no private IP (the #6416 mode)" | **False** — live Hetzner API shows `private=10.0.1.11` | The birth path's `-target` set is correct; mirror it |
| "A post-fix image exists" | **True** — `web-v0.239.0` (2026-07-26T20:39:44Z); its tree carries `soleur-doppler-download` | Pin `image_tag=web-v0.239.0` |
| "`test-all.sh` auto-discovers suites" | **False** — explicit `run_suite` registration (`scripts/test-all.sh:340,352`) | New suite MUST be registered (orphan-suite class) |

**Premise validation (Phase 0.6).** All five cited artifacts resolve (`web-host-birth-gate.sh`,
`apply-web-platform-infra.yml`, `web-host-birth.md`, the post-mortem, `destroy-guard-filter-web-platform.jq`).
#6969 is OPEN; #6971 and #6459 are OPEN; PR #6970 is MERGED and is a *contextual citation*, not a
work target — its scope was the error channel, not the replace mechanism.

## User-Brand Impact

**If this lands broken, the user experiences:** a total outage of `app.soleur.ai`. `hcloud_server.web["web-1"]`
is the **singleton** behind the app A record with no failover partner and no load balancer. A
mis-scoped `-target` or a gate that admits the wrong address would destroy it. The user sees a dead
product, not a degraded one.

**If this leaks, the user's data is exposed via:** a replace that destroys `hcloud_volume.workspaces`
or `hcloud_volume.workspaces_luks` loses every workspace on that host irrecoverably; a replace that
rotates the LUKS passphrase strands the at-rest data behind a new header while the host boots
"successfully" and reports healthy.

**Brand-survival threshold:** `single-user incident` — `requires_cpo_signoff: true`;
`user-impact-reviewer` at review time.

## Architecture Decision (ADR/C4)

Detection fires: this introduces a **new dispatch route granted a destructive capability** that every
other automated route HALTs on — a trust/authorization boundary change.

### ADR

Create a new ADR: *"Web-host replacement is a distinct gated dispatch, not a widened birth."*
Decision: the `host_creates` HALT stays; `web-host-create` stays additive-only; replacement gets its
own inverted gate whose contract is *exactly one replace of the requested host, both volume families
preserved*. Alternatives considered: (a) widen the birth gate to accept `["delete","create"]` —
rejected, it dissolves the birth/replace distinction the birth gate exists to enforce; (b)
destroy-then-create as two dispatches — rejected, it opens a window where the host is absent and
doubles the approval surface; (c) operator-local `terraform apply -replace` — rejected per
`hr-all-infrastructure-provisioning-servers`.

**The ordinal is provisional.** `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main`
before merge; on renumber, sweep this plan + `tasks.md` + any AC naming the ordinal.

### C4 views

Enumerate against all three `.c4` files before concluding. The candidate deltas: no new external
actor, no new external system, no new data store — the operator and Hetzner are already modeled.
The change is an internal authorization route. **A "no C4 impact" conclusion must cite the
actor/system/relationship enumeration it checked** — do not write a bare "None".

## Infrastructure (IaC)

### Terraform changes

**None expected.** The environment (`github_repository_environment.web_platform_infra_apply`) and its
`main`-only deployment policy already exist in `web-host-birth-environment.tf`. Reuse them —
**do not re-declare**, and do not add a second environment. If `/work` finds a reason to touch that
file, treat it as a scope change and re-read its ADOPTION note first: an earlier revision of it
silently deleted the live main-only pin.

### Apply path

`workflow_dispatch` → `environment: web-platform-infra-apply` (reviewer gate) → digest-pin resolve →
coherence preflight → stock preflight → `terraform plan -replace=...` → inverted gate → apply.

### Distinctness / drift safeguards

- `concurrency: group: web-1-swap, cancel-in-progress: false` **plus** the workflow-level shared R2
  serializer literal. The backend is lockless (`use_lockfile = false`); that shared group is the sole
  serializer. **Do not rename it** — GitHub does not error on divergent group strings, they silently
  fail to serialize.
- The per-PR `host_creates` HALT stays untouched.

### Vendor-tier reality check

Hetzner stock is a live constraint: the 2026-07-26 repin (cx23→cpx22) was forced by stock, and the
entire cx/cax lines are orderable in 0 of 3 EU DCs. A replace **destroys before it creates**, so a
stock miss strands the fleet — this is #6393/#6400 verbatim. The stock preflight is mandatory here,
not optional.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

1. Read `tests/scripts/lib/git-data-host-replace-gate.sh` **in full** — it is the template.
2. Confirm whether `hcloud_volume.workspaces` and `hcloud_volume.workspaces_luks` are both
   `for_each`-keyed over `var.web_hosts`, and which one web-2 actually carries. Read `server.tf:1627`
   and `workspaces-luks.tf:207`.
3. Determine whether the LUKS passphrase resources (`random_password.*`, `doppler_secret.*_key`) exist
   for web hosts as they do for git-data. If yes, they get a `luks_passphrase_touched` backstop.
4. Determine whether the 4 web-probe resources (`betteruptime_heartbeat.web_{zot_consumer,nic_guard}`,
   `doppler_secret.web_{zot_consumer,nic_guard}_url` in `web-probe.tf`) reference the server id.
   **They govern whether they belong in the `-target` set at all** — include only if a replace must
   change them.
5. Confirm `cloudflare_record.app` behavior for a **non-web-1** key (expected: no-op) and for web-1
   (expected: content changes to the new IP). The gate must handle both without a special case that
   weakens it.

### Phase 1 — The gate library (TDD: test first)

Write `tests/scripts/test-web-host-replace-gate.sh` **before** the gate, with a fixture per arm.
Then write `tests/scripts/lib/web-host-replace-gate.sh`.

**PASS (rc=0) iff ALL of:**

| Arm | Assertion | Why |
|---|---|---|
| `server_replaced` | `== 1` | one authorization replaces one host |
| identity | replaced address `== hcloud_server.web["<key>"]` | a count-only check passes a plan that replaces **web-1** — the total-outage case |
| `workspaces_volume_destroyed` | `== 0` | named backstop; the plaintext store |
| `luks_volume_destroyed` | `== 0` | named backstop; the at-rest store |
| `luks_passphrase_touched` | `== 0` (if the resources exist) | a rotated passphrase strands data behind a new header while the host boots "healthy" |
| `nic_recreated` | `>= 1` | a server without its private NIC is #6416 and looks like a successful apply |
| `volume_attachment_recreated` | `>= 1` | a server without its attachment writes `/mnt/data` to the ROOT DISK behind a fail-open mount, serves normally, and loses every workspace when the real volume mounts over it |
| `reboot_updates` | `== 0` | no *other* live host power-cycled; `hcloud_firewall_attachment.web` is a fleet singleton whose targeting drags every host into the plan |
| `out_of_scope` | `== 0` | exact-equality `IN(...)` membership — never `contains`/`inside`, which would let bare `hcloud_server.web` satisfy the keyed member and wave the whole fleet through |

**Fail-closed** on: missing file, unparseable JSON, absent `resource_changes` array, or **any** entry
whose `.change.actions` is not an array (jq's `null | index("delete")` returns null, silently
*dropping* the entry — which is exactly a destroy the gate cannot see). Copy the birth gate's
explicit null-guard; it is mutation-proven load-bearing.

**No `[ack-destroy]` bypass.** Authorization is the menu-ack dispatch
(`hr-menu-option-ack-not-prod-write-auth`), never a commit trailer.

Define the allow-set **once** as `_WEB_HOST_REPLACE_ALLOW='def allow($k): [...]'` — the birth gate
documents that a duplicated allow-set drifted and review mutation-proved the second copy was guarded
by nothing.

### Phase 2 — The workflow job

Add `web_host_replace` to `.github/workflows/apply-web-platform-infra.yml`:

- `if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'web-host-replace'`
- `environment: web-platform-infra-apply`
- `concurrency: {group: web-1-swap, cancel-in-progress: false}`
- Reuse `web_host_key` (`^web-[0-9]{1,2}$`, routed through `env:`, never `${{ }}` inside `run:`),
  `image_tag`, `reason`. Add **`confirm=REPLACE-<key>`** — distinct from `BIRTH-<key>` so a token
  typed for one target cannot authorize the other. **Do not add new inputs**: the `workflow_dispatch`
  cap is 10 and 5 are used.
- Add `web-host-replace` to the `apply_target` `options:` enum and the `description:`.
- Source **`stock-preflight-gate.sh`** (a replace destroys before it creates — this is the gate's
  stated purpose) and update its header, which enumerates the sourcing steps by name.
- Digest-pin resolve + coherence preflight, as the birth path does.

### Phase 3 — Sweep every guard suite (the orphan-suite class)

`git grep -ln 'web-host-birth\|web_host_create'` returns **10** files. The `-target` allow-list is
asserted by more than the gate:

- `plugins/soleur/test/terraform-target-parity.test.ts` — add `web_host_replace` to
  `stripDispatchJobs`. The test *"stripDispatchJobs list is pinned to real jobs"* fails if the name
  does not match a real `^  <job>:` in the workflow. Consider a `WEB_REPLACE_TARGETS` pin mirroring
  `REGISTRY_REPLACE_TARGETS`.
- `scripts/test-all.sh` — `run_suite "tests/scripts/web-host-replace-gate" bash tests/scripts/test-web-host-replace-gate.sh`.
  **Explicit registration; a new suite is invisible without this line.**
- `tests/scripts/test-stock-preflight-gate.sh` — if it pins the sourcing list, extend it.
- `.github/workflows/infra-validation.yml` — check whether the new suite needs registration
  (`run-registered-suites.sh` derives the CI set from this file).

### Phase 4 — Docs

- New runbook `knowledge-base/engineering/operations/runbooks/web-host-replace.md` alongside
  `web-host-birth.md`, cross-linked both ways.
- The ADR from §Architecture Decision.

### Phase 5 — Execute the rebirth (in scope, not a follow-up)

```
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-host-replace \
  -f web_host_key=web-2 \
  -f confirm=REPLACE-web-2 \
  -f image_tag=web-v0.239.0 \
  -f reason='dark-host rebirth onto the boot-stage error channel'
```

Dispatch **queues** the job behind the environment reviewer gate; it does not bypass approval.
Then poll the run and read the boot trail.

### Phase 6 — Record the outcome

Update `knowledge-base/engineering/operations/post-mortems/2026-07-26-web-2-dark-boot-doppler-download-postmortem.md`:
its `status:` is `unresolved but ended` and its Recovery-verification section explicitly defers to
this rebirth. Fill in what the birth gate reported. **Only then** close #6969.

## Files to Create

- `tests/scripts/lib/web-host-replace-gate.sh`
- `tests/scripts/test-web-host-replace-gate.sh`
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md`
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-web-host-replacement-is-a-distinct-gated-dispatch.md`

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `tests/scripts/lib/stock-preflight-gate.sh` (header sourcing list)
- `tests/scripts/test-stock-preflight-gate.sh` (if it pins the list)
- `scripts/test-all.sh`
- `.github/workflows/infra-validation.yml` (if registration is required)
- `knowledge-base/engineering/operations/runbooks/web-host-birth.md` (cross-link)
- `knowledge-base/engineering/operations/post-mortems/2026-07-26-web-2-dark-boot-doppler-download-postmortem.md`

## Open Code-Review Overlap

**None.** Run at `/work` (2026-07-26) against the finalized file list: 60 open `code-review`
issues fetched, then a per-file `jq --arg path ... | contains($path)` for each of the eight
changed/created files (gate lib, gate suite, workflow, parity test, `test-all.sh`,
`stock-preflight-gate.sh`, the extracted boot-trail reader, the observability suite). Every
query returned `[]`.

## Observability

```yaml
liveness_signal:
  what: the web-host-replace run's own boot-trail poll reaching cloud_init_complete
  cadence: per dispatch (not periodic)
  alert_target: GitHub Actions run conclusion + the ::error::/::warning:: annotations
  configured_in: .github/workflows/apply-web-platform-infra.yml (web_host_replace job)
error_reporting:
  destination: GitHub Actions annotations + Sentry (jikigai-eu/web-platform) boot-stage events
  fail_loud: true — the gate aborts the apply; the boot-trail poll fails the run on a fatal
failure_modes:
  - mode: gate admits a wrong-identity replace (web-1)
    detection: identity arm compares the replaced address to the dispatch key
    alert_route: run fails before apply; nothing is destroyed
  - mode: replace strands a volume (destroyed or detached)
    detection: workspaces_volume_destroyed / luks_volume_destroyed backstops + the
               volume_attachment_recreated requirement arm
    alert_route: run fails before apply
  - mode: stock unavailable at destroy time
    detection: stock-preflight-gate.sh asserts the planned server_type is orderable in-location
    alert_route: run aborts before the destroy
  - mode: fresh host boots dark again
    detection: the birth-path boot-trail poll; post-#6969 emitter now carries stage + detail +
               host_name, so the ::error:: names the CAUSE, not just the stage
    alert_route: Sentry fatal (web_terminal_boot_fatal rule) + run failure
logs:
  where: GitHub Actions run log; Sentry boot-stage events; Vector once the host has a token
  retention: Actions default; Sentry project retention
discoverability_test:
  command: curl -sS -o /dev/null -w "%{http_code}" --max-time 10 https://o4511404939345920.ingest.de.sentry.io/api/4511404943671376/store/
  expected_output: "401"
  # 401 unauthenticated IS the healthy signal — reachable and auth-gated. This is the only
  # transport a first-booting host has. NO ssh.
```

**Soak follow-through:** not engaged — no acceptance criterion is time-gated.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.workspaces_luks[<key>]
    mechanism: LUKS (existing; unchanged by this plan)
    evidence: workspaces-luks.tf:207
    defends_against: offline disk/volume seizure
    does_not_defend: a live host with the volume unlocked and mounted
    disclosed_as: unchanged — this plan adds no new store
    live_verification: the replace must NOT touch the volume or its passphrase (gate arms)
  - store: hcloud_volume.workspaces[<key>]
    mechanism: provider-managed (plaintext at the LUKS layer)
    evidence: server.tf:1627
    defends_against: n/a
    does_not_defend: offline seizure of the underlying block device
    disclosed_as: unchanged
    live_verification: preserved by omission from the -target set
in_transit:
  - connection: none new
    tls: n/a
    cert_verification: n/a
    does_not_defend: n/a
    disclosed_as: unchanged
```

**No `exception` block** — this plan introduces no new store and no new connection; it changes only
which resources a dispatch may replace. If Phase 0 finds a web-host LUKS passphrase resource, the
`luks_passphrase_touched` arm is the control that keeps this true.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `tests/scripts/lib/web-host-replace-gate.sh` exists and is sourced by BOTH the workflow's
  plan step AND `tests/scripts/test-web-host-replace-gate.sh` (same bytes, no inline copy).
- **AC2** The gate PASSES a fixture that replaces exactly `hcloud_server.web["web-2"]` with its NIC
  and volume attachment recreated.
- **AC3** The gate ABORTS on each of: wrong identity (`web-1`), a `workspaces` volume delete, a
  `workspaces_luks` volume delete, a missing NIC recreate, a missing volume-attachment recreate, a
  reboot-forcing update on another host, an out-of-scope address, and an unparseable plan.
  One fixture per arm; each must fail for its **own** reason.
- **AC4** Mutation check: deleting any single arm from the gate makes at least one test go red
  (no vacuous arms — the birth gate's own history shows a duplicated allow-set guarded by nothing).
- **AC5** `grep -c 'web-host-replace' .github/workflows/apply-web-platform-infra.yml` ≥ 1 and the
  `apply_target` enum contains `web-host-replace`.
- **AC6** `confirm` accepts only `REPLACE-<key>`; a `BIRTH-<key>` token is rejected by this job.
- **AC7** `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes with
  `web_host_replace` in `stripDispatchJobs`.
- **AC8** `grep -c 'test-web-host-replace-gate.sh' scripts/test-all.sh` == 1 (orphan-suite guard).
- **AC9** `bash apps/web-platform/infra/run-registered-suites.sh` passes (the authoritative infra
  gate; `scripts/test-all.sh` does **not** cover `apps/web-platform/infra/`).
- **AC10** `bash scripts/test-all.sh` exits 0.
- **AC11** `bash scripts/check-adr-ordinals.sh` exits 0.
- **AC12** The per-PR `host_creates` HALT is byte-unchanged:
  `git diff origin/main -- .github/workflows/apply-web-platform-infra.yml` shows no modification
  inside the `apply` job's HALT block.
- **AC13** PR body uses `Ref #6969` — **not** a closing keyword.

### Post-merge (operator-gated dispatch, executed by this workflow — not deferred)

- **AC14** The `web-host-replace` dispatch is fired with `image_tag=web-v0.239.0` and **queues** on
  the `web-platform-infra-apply` reviewer gate (evidence: run URL in `waiting` state).
- **AC15** After approval, the run either (a) reaches `cloud_init_complete` — web-2 is reborn and
  healthy — or (b) fails with an `::error::` naming `stage=doppler_download` **together with** the
  Doppler CLI's own error line and exit code.
- **AC16** The post-mortem is updated with whichever outcome occurred, and `status:` is moved off
  `unresolved but ended` only if (a).
- **AC17** #6969 is closed **only** after AC15/AC16, with the live evidence in the closing comment.

## Test Scenarios

1. Replace web-2 (happy path) — gate PASS, one replace, both volumes untouched.
2. Replace web-1 requested but plan replaces web-2 (and vice versa) — identity ABORT.
3. Plan carries a `workspaces_luks` delete — named backstop ABORT.
4. Plan replaces the server but omits the NIC — requirement-arm ABORT (#6416).
5. Plan replaces the server but omits the volume attachment — requirement-arm ABORT (silent data loss).
6. Plan power-cycles web-1 via a `server_type` delta — reboot arm ABORT.
7. Plan JSON with a null `resource_changes` — fail-closed ABORT.
8. Plan entry with non-array `.change.actions` — fail-closed ABORT.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Replacing web-1 destroys the only live origin** | Identity arm + out-of-scope allow-set keyed on the requested host + the reviewer gate showing the dispatch inputs |
| Volume destroyed / detached | Preserved by omission from `-target` (an untargeted resource cannot be planned for destroy) + two named backstops + a requirement arm on the attachment |
| LUKS passphrase rotated → data stranded behind a new header | `luks_passphrase_touched == 0` (git-data precedent) |
| Stock unavailable → destroy succeeds, create fails, fleet stranded | `stock-preflight-gate.sh` asserts orderability **before** the destroy (#6393/#6400) |
| Concurrent apply clobbers the lockless R2 state | Shared workflow-level concurrency literal + `web-1-swap` group; do not rename |
| New job silently un-tested | `scripts/test-all.sh` explicit registration + parity test's `stripDispatchJobs` pin |
| Gate ships with a vacuous arm | AC4 mutation check |

## Deviations from the PLAN, recorded at /work

Two, both forced by Phase 0 measurement rather than chosen.

**1. web-1 is refused, not handled.** The plan required a gate handling web-1 and non-web-1
keys "without a special case that weakens it". Its premise — that a web host owns two
symmetric per-host volume families, mirroring git-data — is false:
`hcloud_volume.workspaces` is `for_each`-keyed, but `hcloud_volume.workspaces_luks` is a
SINGLETON whose attachment is hardcoded to `hcloud_server.web["web-1"].id`, and **web-2 has no
LUKS volume at all**. The two extra members web-1 entails (that attachment, and
`cloudflare_record.app`) are expressible as key-conditional arms; the decisive hazard is not.
web-1 currently carries two attached volumes mid-ADR-119 cutover, which `workspaces-luks.tf`
states makes cloud-init's `scsi-0HC_Volume_*` mount glob AMBIGUOUS — a cloud-init property no
plan-shaped gate can observe. Refusing is a *strengthening* special case and the only honest
one. Full reasoning + the revisit condition: ADR-148 §Alternatives item 4.

**2. The ADR ordinal is 148, not the plan's provisional 146.** ADR-146 and ADR-147 both exist
on `origin/main`; the plan's own note said the ordinal was provisional and to sweep on
renumber, which was done across five in-code references.

**3. Two further findings that changed the -target set** (not deviations from a stated
requirement, but corrections to plan assumptions): the four web-probe resources reference no
server id, so a replace does not change them and they are out of both the `-target` set and
the allow-set; and `cloudflare_record.app` is likewise out, because with web-1 refused the
apex record must never move — any positive action on it is an out-of-scope abort rather than a
permitted side effect.

**4. The fresh-host boot-trail reader was extracted** to
`apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`. The plan's Observability block
requires the replace job to carry the boot-trail poll; the birth job's copy is ~230 lines of
dense shell pinned by exactly one test, so duplicating it would have left the two copies with
one test between them. Lifted with `sed`, not retyped.

## Deviations from the plan skill (disclosed)

The session's operating instructions prohibit spawning subagents unless the operator requests them.
The following phases are normally agent-spawning and were performed **inline** instead: Phase 1
research (repo-research-analyst, learnings-researcher), Phase 2.5 Domain Review, Phase 3 SpecFlow,
Phase 4.5 scoped advisor consult, and the Plan Review panel. The substance — repo grep, precedent
reads, guard-suite sweep, premise validation — was done directly and is cited above with file:line
evidence. A reviewer wanting the panel's independent lenses should run `/soleur:plan-review` on this
file before `/work`.

## Domain Review

**Domains relevant:** Engineering (infrastructure, security).

Product/UX Gate: **NONE** — no UI surface in `Files to Create`/`Files to Edit`; the mechanical
UI-surface override does not fire. Legal/Compliance: `gdpr-gate` not triggered — no regulated-data
surface (no schema, migration, auth flow, API route, or `.sql` file in scope).
