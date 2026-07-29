---
title: "feat: gated rung-2 rehearsal route for the git-data birth (build it, do not fire it)"
date: 2026-07-29
type: feature
issue: 7025
pr: 7066
branch: feat-one-shot-7025-git-data-rung2-rehearsal-route
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: gated rung-2 rehearsal route for the git-data birth

## Overview

`git_data_rung2_rehearsal_gate` refuses the git-data birth dispatch until
`apps/web-platform/infra/git-data-rung2-boot-evidence.env` exists and attests a rung-2 boot
rehearsal of the *current* template. That file is absent on `main`, and **no automation
exists to produce it** — `rung2` appears only in `apply-web-platform-infra.yml` and the gate
script itself. Nothing boots a throwaway host; nothing captures the three off-box artifacts.

This plan ships **the route, not the run**. After it merges, producing rung-2 evidence is one
gated `workflow_dispatch` the operator approves — not a hand-run laptop procedure. The
evidence file is deliberately **not** committed here, so both interlocks keep holding and the
DO-NOT-DISPATCH banner stays up.

**Operator scope decision (2026-07-29):** build the gated rehearsal route and prove its
dry-run arm green; do **not** fire the real boot, do **not** clear the banner in this PR.

> No `spec.md` exists for this branch (entered via the one-shot → plan path, which skips
> brainstorm), so there is no `lane:` to carry forward — defaulted to `cross-domain`
> (TR2 fail-closed).

### Why the banner-clear cannot ride in this PR

The same argument #7025 makes about #6982 applies to this PR with equal force: a PR merges
atomically, so a banner cleared in the final commit clears at the same instant as the
never-executed rehearsal harness it is supposed to be downstream of. The harness must exist,
merge, and then *run* before its output can release anything.

## Premise Validation

Both premises the issue body states are **stale** — it was written before PR #7015 (merged
2026-07-28) landed. Verified against `main` on 2026-07-29:

| Issue-body claim | Verified state on `main` | Verdict |
|---|---|---|
| "The DO-NOT-DISPATCH banner … is now the only thing holding the route." | `git_data_rung2_rehearsal_gate` (`tests/scripts/lib/git-data-birth-readiness-gate.sh:217`) is a **second mechanical gate**, wired at `apply-web-platform-infra.yml` as *"Rung-2 rehearsal interlock"*, running before any provider is contacted. `git-data-rung2-boot-evidence.env` is absent → a dispatch today exits 1. | **STALE.** The binding hold is the missing evidence file. The banner is now the *third* hold, not the only one. |
| "Tick ADR-149 checklist item 7." | ADR-149:189 already records item 7 as **"NOT SATISFIABLE AS WRITTEN"** — the emitter shipped as a *file* in `user_data` (`/usr/local/bin/git-data-emit`), not a Terraform resource, so there is no resource to assert; and that recording *is* the precondition item 7 places on clearing item 8. | **WRONG ACTION.** Item 7 is correctly dispositioned. The item #7025 owns is **item 8**, which ADR-149:186 records as "DELIBERATELY NOT DONE. Moved to its own follow-up PR (#7025)". |

Collision check (one-shot Step 0a.5): PR #7015 surfaced as MERGED on both the `linked:issue`
and body-text probes, with a 6-path intersection. Scope-discriminated as **genuinely new** —
the banner is still present at `git-data-birth.md:3` and the evidence file is still absent.
`gh pr view 7015 --json closingIssuesReferences` → `[6982]`, not 7025.

Repo-capability claims verified rather than assumed (`hr-verify-repo-capability-claim-before-assert`):
`grep -rln 'rung2\|rung-2' .github apps/web-platform/infra tests scripts` → only the apply
workflow and the gate/test pair. There is no rehearsal producer. `git-data.tf` contains **zero**
`provisioner "` / `connection {` blocks, so the network-outage checklist (plan Phase 1.4) does
not fire.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / prior art) | Reality on `main` | Plan response |
|---|---|---|
| "commit the evidence file with stub volume ids" | `boot_complete` carries `luks_mounted`, and a **PASS requires it true**. A stub volume id makes `cryptsetup luksOpen` fail → `luks_mounted=no` → the probe's FAIL arm. | The rehearsal provisions **real throwaway** Hetzner volumes + a real `GIT_DATA_LUKS_KEY` in a scratch Doppler config. Only the *identity* is throwaway, not the mechanism. |
| "reuse `git-data-birth-emitter-6982.sh`" | That probe pins `JSONExtractString(raw,'host_name') = 'soleur-git-data'` (line 60). A rehearsal host emits a different `host_name`, so the probe returns TRANSIENT forever against a perfect rehearsal. | Parameterize `host_name` (default `soleur-git-data`, preserving current prod behaviour) and reuse the field-isolated SQL from the capture script. Verbatim reuse is impossible; parameterized reuse is correct. |
| The gate's hash binds "the template" | It binds a **hash-of-hashes over the template + every `file()`-bound payload** in `git-data.tf`, with a **floor of 10 inputs** (gate:305). Measured live: 10 inputs → `aa1447f2b3bfa964707e1d8a0f51f866b0de1b917eb628a92575d6fe52349ff3`. | The capture script must not hand-roll this. **Extract the derivation into a shared function** both the gate and the capture script call (see FR1). |
| Render-time vars are covered by the hash | They are **not**. `host_name`, `git_data_volume_id`, `git_data_luks_volume_id`, `doppler_token`, `sentry_dsn` are `templatefile` arguments, not hashed inputs. A rehearsal with divergent vars still yields hash-valid evidence. | Accepted, bounded, and **recorded**: the evidence file carries a comment block enumerating every var that diverged from prod. Minimize divergence to identity-only. Record as a known limit in ADR-149. |
| "a Sentry event from the fatal channel" | The fatal channel fires **only on failure**. A clean rehearsal emits `info`-level events (cloud-init:33 `stage:bootcmd_start`) and never a fatal. Requiring a fatal from a successful boot is unsatisfiable. | Split into two arms: **(a)** ≥1 Sentry event via the baked DSN proves the channel; **(b)** a `fault_injection` arm deliberately forces a fatal and observes it. (b) is the arm that actually proves "green apply, dark host" is now detectable. |
| C4 `gitDataStore` description | Says *"A prose DO-NOT-DISPATCH banner in the runbook is what holds the route now"*. | **Falsified by #7015.** Correct it — the route is held by a hash-bound mechanical gate. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the rehearsal route is
inert until dispatched, and the birth stays held. The dangerous failure is *indirect*: a
rehearsal `terraform apply` whose target closure reaches `hcloud_server.git_data` would
**create the production git-data host outside the birth route**, bypassing the birth job's
environment reviewer, its confirm token, both interlocks, and its `-target` allow-set. That
host would hold every connected user's source code and would have been born by a workflow
whose approval prompt said "rehearsal".

**If this leaks, the user's source code is exposed via:** a rehearsal host attached to the
prod private network (`10.0.1.0/24`) without a deny-all firewall would be reachable from
every other host on that network while running the same git transport wrappers. Secondarily,
the scratch Doppler service token and the throwaway LUKS passphrase land in the rehearsal
root's `terraform.tfstate`.

**Brand-survival threshold:** `single-user incident`

The blast radius of a mis-targeted apply on this route is the shared source-code store, so a
single incident is brand-terminal. This is what drives the separate-Terraform-root decision
below: `-target` is *transitive on dependencies*, so target-scoping alone is a guard, while a
separate state file is a structural impossibility.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-149** (`ADR-149-git-data-host-birth-route-and-readiness-interlock.md`) — do **not**
mint a new ordinal. ADR-149 already owns the release checklist, the rung taxonomy, and the
per-item disposition table; the rehearsal route is the mechanism for its own item 8, not a new
decision domain. Amendment records:

1. The rung-2 rehearsal route exists, is gated, and shipped **unfired** (mirroring how
   `registry-luks-recut` shipped as an unfired vehicle).
2. **DC-6 (new):** the rehearsal runs in a **separate Terraform root** rather than
   `count`-gated resources in the shared root. Alternatives considered: (a) `count`-gated
   resources in `apps/web-platform/infra/` — rejected, because `-target` is transitive and a
   rehearsal address referencing any prod `git_data` attribute drags the prod host into the
   plan closure, which is exactly the `for_each`-over-target-excluded-map hazard; (b) a
   throwaway account/project — rejected, no such isolation exists in this Hetzner account.
3. The **hash-vs-vars scope limit**: rung-2 evidence binds the template + 9 payloads, not the
   render-time var set. Recorded as a known limit, not assumed away.
4. Item 8 stays **OPEN**. Item 7 stays **NOT SATISFIABLE AS WRITTEN**, untouched.

Ordinal note: amending needs no ordinal, so the `/ship` ADR-Ordinal Collision Gate has nothing
to re-verify here.

### C4 views

**Container view — `gitDataStore` description is factually wrong on `main` and must be
corrected.** Enumeration performed against all three model files
(`model.c4`, `views.c4`, `spec.c4`):

- **External human actors:** none new. The operator (`founder`) already has the approval edge
  via the existing environment.
- **External systems:** `sentry`, `betterstack`, `doppler`, `hetzner` — **all four already
  modelled** (`model.c4:294`, `:287`, `:238`, `:180`) and already carry edges to the platform
  boundary. The rehearsal introduces no new vendor.
- **Containers / data stores:** the rehearsal host is an *ephemeral instance* of the existing
  `hetzner` compute container writing to a throwaway volume; `gitDataStore` (`model.c4:214`)
  already models the store. No new element.
- **Access relationships:** unchanged — no new actor↔surface edge; the rehearsal host serves
  no user traffic and is never in any ingress rotation.

So the only `.c4` edit is a **correctness fix**, not an addition: `gitDataStore`'s description
currently ends *"A prose DO-NOT-DISPATCH banner in the runbook is what holds the route now,
pending the rehearsal-boot evidence."* That sentence was true for ~one day and is false since
#7015. Replace with the two-gate reality and the hash-binding. Because this is a description
edit on an existing element with no new `view … include` line, `c4-code-syntax.test.ts` and
`c4-render.test.ts` are regression checks here rather than new-element validation — run both.

### Sequencing

The ADR amendment and the C4 fix ship **in this PR**, describing the route as built-and-unfired.
Neither is deferred.

## Infrastructure (IaC)

### Terraform changes

**New root:** `apps/web-platform/infra/rung2-rehearsal/`

| File | Contents |
|---|---|
| `main.tf` | `terraform{}` block, R2 S3-compatible backend with a **distinct key** (`web-platform/rung2-rehearsal.tfstate`), `use_lockfile = false` mirroring the parent root, provider requirements pinned to the versions in `apps/web-platform/infra/main.tf` |
| `variables.tf` | `hcloud_token`, `doppler_token`, `sentry_dsn`, `location`, `git_data_server_type`, `private_network_id`, `rehearsal_run_id`, `fault_injection` (bool, default `false`). **No `default` on any secret-bearing variable** (`hr-tf-variable-no-operator-mint-default`) |
| `rehearsal.tf` | `hcloud_server.rehearsal` + `hcloud_volume.rehearsal` + `hcloud_volume.rehearsal_luks` + both attachments + `hcloud_firewall.rehearsal` (zero rules = deny-all) + attachment + `hcloud_server_network.rehearsal` + `tls_private_key` trio + `random_password.rehearsal_luks` + `doppler_config`/`doppler_secret`/`doppler_service_token` for the scratch config |
| `outputs.tf` | `rehearsal_host_name`, `rehearsal_server_id`, `user_data_sha256` |

`hr-every-new-terraform-root-must-include-an` is satisfied by `main.tf`'s backend block.

**The render reads the parent's files, unmodified:**

```hcl
user_data = base64gzip(templatefile("${path.module}/../cloud-init-git-data.yml", {
  # …identical payload set, read via ${path.module}/../<payload>…
  host_name              = "soleur-git-data-rehearsal-${var.rehearsal_run_id}"
  git_data_volume_id     = hcloud_volume.rehearsal.id
  git_data_luks_volume_id = hcloud_volume.rehearsal_luks.id
  doppler_token          = doppler_service_token.rehearsal.key
  sentry_dsn             = var.sentry_dsn
  # …
}))
```

This is what makes the evidence meaningful: the bytes that boot are the *same* template and
the *same* nine payloads the gate hashes. Only identity-shaped vars diverge.

**`local.git_data_rationale_strip` must be duplicated byte-for-byte** into the rehearsal root
(the parent's `locals` is not visible across roots). `git-data-render-strip-parity.test.sh`
already exists to keep the parent's copy and `git-data-userdata-budget.sh` equal — extend it
to cover the rehearsal root's third copy, or the rehearsal renders a *different* payload than
the one it attests. **This is the single highest-risk drift in the design.**

### Apply path

**(a) cloud-init-only.** The rehearsal host is created fresh, boots once, is measured, and is
destroyed. There is no bootstrap-script path and no in-place patch path — matching
`git-data.tf`'s own "cloud-init-only, NO remote-exec provisioner" posture. Expected wall clock
~8 min (Hetzner provisioning ~6 min + boot + emit). Blast radius: confined to the rehearsal
root's own state file.

### Distinctness / drift safeguards

- **Separate state key** — the rehearsal root physically cannot address a prod resource. This
  is the primary control; every guard below is defence-in-depth.
- **Zero references to the parent root.** `rehearsal.tf` must not contain the string
  `hcloud_server.git_data`, `hcloud_volume.git_data`, or any `data "terraform_remote_state"`.
  Enforced by a grep assertion in the new suite.
- **Deny-all firewall attached before the host serves anything** — zero-rule
  `hcloud_firewall`, same shape as `hcloud_firewall.git_data`.
- **Mandatory destroy** — the workflow's teardown step runs `if: always()`, so an aborted or
  failed rehearsal still tears down. A leaked host is a paying, private-net-attached box.
- **`terraform.tfstate` holds secrets** (LUKS passphrase, Doppler service token) — the R2
  backend is encrypted at rest and the key is distinct, so a rehearsal state leak does not
  expose prod material.
- **No `lifecycle.ignore_changes`** anywhere in the rehearsal root: the host is cattle by
  construction and there is no drift to suppress.

### Vendor-tier reality check

No free-tier gate applies. Hetzner `cpx22` + two small volumes for <30 min is ~€0.02 per
rehearsal — an ephemeral cost, not a recurring vendor expense, so
`wg-record-recurring-vendor-expense-before-ready` does not fire. Better Stack and Sentry
ingest are already-paid existing channels.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.rehearsal_luks (throwaway, rehearsal root)
    mechanism: guest-side LUKS2 via cryptsetup, keyed by random_password.rehearsal_luks
               delivered through a scratch Doppler config read by a read-only service token
    evidence: the boot_complete assertion luks_mounted=yes, captured off-box in the
              evidence file — this is the whole point of the rehearsal
    defends_against: Hetzner-side disk/volume recovery of the detached block device after
                     the rehearsal is destroyed
    does_not_defend: anything readable while the host is up and the mapper is open (a
                     compromise of the live rehearsal host reads plaintext); the passphrase
                     in the rehearsal root's terraform.tfstate
    disclosed_as: not user-facing — no user data ever reaches a rehearsal host; the volume
                  is created empty and destroyed empty
    live_verification: the rehearsal itself IS the live verification
  - store: hcloud_volume.rehearsal (plaintext ext4, mirrors the prod plaintext store shape)
    mechanism: plaintext-exception — deliberately mirrors hcloud_volume.git_data so the
               rehearsal exercises the real dual-volume boot path
    evidence: format = "ext4", no LUKS apparatus (identical to the prod declaration)
    defends_against: nothing
    does_not_defend: at-rest recovery of the detached device
    disclosed_as: n/a — never holds data
    live_verification: n/a
in_transit:
  - connection: rehearsal host -> Sentry (de.sentry.io) via baked DSN
    tls: yes
    cert_verification: on
    does_not_defend: the DSN itself is semi-public and lands in tfstate + retrievable
                     user_data (already accepted for prod, variables.tf says so)
    disclosed_as: Art. 30 PA8 §(e) already covers Sentry DE ingest
  - connection: rehearsal host -> Better Stack Logs ingest
    tls: yes
    cert_verification: on
    does_not_defend: log contents are visible to Better Stack; the rehearsal emits only
                     boot-stage booleans and a host name, no user data
    disclosed_as: existing Better Stack sub-processor disclosure
  - connection: rehearsal host -> prod private network (10.0.1.0/24)
    tls: no (private-net, same posture as prod git-data transport)
    cert_verification: n/a
    does_not_defend: an already-compromised peer on the private net
    disclosed_as: n/a — deny-all firewall, no service published, destroyed within the hour
exception:
  - store: hcloud_volume.rehearsal (plaintext)
    justification: it mirrors the prod plaintext store BY DESIGN. Making the rehearsal
                   volume LUKS while prod's is plaintext would rehearse a boot that does
                   not exist. The volume never holds data.
    tracking_issue: 6897 (the prod git-data plaintext-store cutover)
    reevaluate_when: hcloud_volume.git_data becomes the LUKS volume (GIT_DATA_STORE_ENABLED
                     cutover) — at which point the rehearsal must mirror the new shape
    expires_on: 2026-12-31
```

## Observability

```yaml
liveness_signal:
  what: the rehearsal workflow run itself is the signal — it is dispatch-only and has no
        steady state to keep alive
  cadence: on-dispatch only
  alert_target: the dispatching operator (workflow run conclusion) + Sentry via the
                rehearsal host's own baked DSN
  configured_in: .github/workflows/git-data-rung2-rehearsal.yml
error_reporting:
  destination: Sentry (host-side, baked DSN — the ONE channel that survives a broken
               Doppler stage) + Better Stack Logs (host-side stage markers) + the GitHub
               Actions run log and job summary (workflow-side)
  fail_loud: yes — every capture failure exits non-zero and fails the job; the three-state
             contract (0 PASS / 1 FAIL / 2 TRANSIENT) is preserved from
             git-data-birth-emitter-6982.sh, and only 0 writes an evidence file
failure_modes:
  - mode: the rehearsal host boots dark (no event ever arrives)
    detection: bounded poll in the capture script times out -> exit 2 TRANSIENT, job fails,
               NO evidence file written
    alert_route: workflow run conclusion + job summary naming which of the three artifacts
                 was missing
  - mode: boot_complete arrives with a FALSE assertion (luks_mounted/repo_root/hooks_path/
          provision)
    detection: capture script's FAIL arm (the `\bno\b` match, inherited from the #6982 probe)
    alert_route: exit 1, job fails, the offending row is printed into the job summary
  - mode: the fatal channel does not work (fault_injection arm forces a fatal, none arrives)
    detection: the fault_injection arm asserts a Sentry event with level=fatal exists for
               the rehearsal host_name; absence -> exit 1
    alert_route: workflow failure — this is the arm that proves "green apply, dark host" is
                 actually detectable
  - mode: the rehearsal host is not destroyed (leaked paying host on the private net)
    detection: teardown step runs `if: always()`; a post-teardown assertion queries the
               Hetzner API for any server whose name matches the rehearsal prefix and fails
               the job if one survives
    alert_route: workflow failure + the existing scheduled-terraform-drift run would also
                 surface an unmanaged host
  - mode: the rehearsal renders a DIFFERENT payload than the one it attests (strip-parity
          drift between the two roots)
    detection: git-data-render-strip-parity.test.sh extended to the rehearsal root; plus
               the capture script recomputes the hash via the SHARED helper and refuses to
               write evidence if it disagrees with the rendered user_data
    alert_route: CI red on infra-validation; job failure at rehearsal time
logs:
  where: Better Stack Logs source 2457081 (host-side, queried via
         scripts/betterstack-query.sh), Sentry issues (host-side), GitHub Actions run log
  retention: Better Stack per existing source retention (the capture script's SQL windows
             the query to INTERVAL 30 DAY, matching the #6982 probe); GHA logs 90 days
discoverability_test:
  command: >-
    doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/git-data-rung2-evidence-capture.sh
    --host-name soleur-git-data-rehearsal-<run-id> --verify-only
  expected_output: >-
    a three-state verdict line (PASS / FAIL / TRANSIENT) naming each of the three artifacts
    and the exact query that retrieved it, with NO ssh anywhere in the path
```

**Empty-query discipline (mandatory, `hr-no-dashboard-eyeball-pull-data-yourself` +
the go-skill's absence-of-evidence sharp edge):** the rehearsal host is the *first* git-data
host that has ever existed, so a Better Stack query returning zero rows is **indistinguishable**
between "never instrumented" and "not yet arrived". The capture script must therefore, before
reading silence as failure, assert the channel is live by confirming the source has received
*any* row from the rehearsal `host_name` (`stage:bootcmd_start` fires first, at cloud-init:33).
Only after that anchor lands does an absent `boot_complete` mean a dark boot.

## Implementation Phases

Phase order is load-bearing: the shared hash helper is a **contract change** consumed by the
capture script, so it lands first.

### Phase 0 — Preconditions (verify, do not assume)

1. Re-derive the live payload hash and pin it in the PR body:
   `printf '%s\n' <inputs> | sort | xargs sha256sum | sha256sum | cut -d' ' -f1`
   (measured 2026-07-29: 10 inputs → `aa1447f2b3bfa964707e1d8a0f51f866b0de1b917eb628a92575d6fe52349ff3`).
2. Confirm `terraform` and the pinned provider versions in
   `apps/web-platform/infra/main.tf`; the rehearsal root pins **the same** versions.
3. Confirm the R2 backend bucket accepts a second key (read the parent `main.tf` backend block).
4. Read `scripts/betterstack-query.sh --help` and confirm **Mode 1 (raw SQL, first positional,
   no convenience flags)** — the #6982 probe's header records that mixing Mode 1 with `--since`
   exits 64. Pin the verified invocation form in the plan artifact.
5. `git grep -n 'REHEARSE-GIT-DATA'` → expect zero (the confirm token must be new and distinct
   from `BIRTH-GIT-DATA`).

### Phase 1 — Shared hash helper (RED first)

Extract the user_data hash derivation out of `git_data_rung2_rehearsal_gate` into
`git_data_rung2_user_data_sha256 <cloud-init-path>` in the same lib. The gate calls it; the
capture script calls it. Preserve the `< 10 inputs` fail-closed floor and the `ABORT` messages
verbatim. Write the failing test first (`cq-write-failing-tests-before`).

### Phase 2 — Evidence-capture script

`scripts/followthroughs/git-data-rung2-evidence-capture.sh`. Three-state contract inherited
from the #6982 probe. Captures all three artifacts, each recorded **with the query that
retrieved it**. Writes the evidence file **only** on PASS. `--verify-only` re-runs the queries
without writing.

### Phase 3 — Parameterize the #6982 follow-through probe

Add `--host-name` (default `soleur-git-data`) to
`scripts/followthroughs/git-data-birth-emitter-6982.sh` so the field-isolated SQL is shared
rather than duplicated. Default preserves current prod behaviour byte-for-byte — the sweeper
invokes it with no arguments.

### Phase 4 — The rehearsal Terraform root

Create `apps/web-platform/infra/rung2-rehearsal/`. Extend
`git-data-render-strip-parity.test.sh` to cover the third copy of
`local.git_data_rationale_strip`.

### Phase 5 — The gated workflow

`.github/workflows/git-data-rung2-rehearsal.yml`. `workflow_dispatch` only; `confirm` typo-guard
= `REHEARSE-GIT-DATA`; `dry_run` default **true**; `fault_injection` default **false**;
`environment: web-platform-infra-apply` (reused — already Terraform-managed with a non-empty
reviewer set and a main-only branch policy, both guarded by DP-11 F8); a **distinct**
`concurrency` group (`git-data-rung2-rehearsal`) so a rehearsal and a birth cannot race; SHA-pinned
actions; every untrusted input routed through `env:`, never interpolated into a `run:` body.

The `dry_run=true` arm renders, runs `terraform plan`, and **asserts the plan creates only
rehearsal addresses and destroys nothing** — then stops. The `dry_run=false` arm applies,
polls, captures, tears down `if: always()`, and uploads the evidence file **as a workflow
artifact plus a PR** — it must **never** auto-commit to `main`, because a route that writes
its own release evidence is self-approving.

### Phase 6 — Tests + registration

New suite `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`; register it as a
`run: bash …` step in `.github/workflows/infra-validation.yml` (the suite list is *derived*
from that workflow, so registration is what makes `run-registered-suites.sh` pick it up).
Unit tests for the capture script in `tests/scripts/`.

### Phase 7 — Docs, ADR, C4, premise reconciliation

Runbook, ADR-149 amendment, the `gitDataStore` C4 description fix, the banner *text* update
(route now exists + how to run it — **banner NOT cleared**), and a comment on #7025 recording
the two corrected premises.

## Files to Create

- `apps/web-platform/infra/rung2-rehearsal/main.tf`
- `apps/web-platform/infra/rung2-rehearsal/variables.tf`
- `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf`
- `apps/web-platform/infra/rung2-rehearsal/outputs.tf`
- `.github/workflows/git-data-rung2-rehearsal.yml`
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh`
- `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`
- `tests/scripts/test-git-data-rung2-evidence-capture.sh`
- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`

## Files to Edit

- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — extract `git_data_rung2_user_data_sha256()`
- `tests/scripts/test-git-data-birth-readiness-gate.sh` — cover the extracted helper
- `scripts/followthroughs/git-data-birth-emitter-6982.sh` — add `--host-name`
- `apps/web-platform/infra/git-data-render-strip-parity.test.sh` — cover the third strip copy
- `.github/workflows/infra-validation.yml` — register the new suite
- `plugins/soleur/test/terraform-target-parity.test.ts` — assert the rehearsal root is **outside**
  every shared-root `-target` set, and that the rehearsal workflow targets no `git_data` prod address
- `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `gitDataStore` description fix
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md` — banner **text**, not cleared

## Acceptance Criteria

### Pre-merge (PR)

1. `git_data_rung2_user_data_sha256` exists in the shared lib; `git_data_rung2_rehearsal_gate`
   calls it rather than inlining the derivation; the `< 10` fail-closed floor is preserved.
   Verify: `bash tests/scripts/test-git-data-birth-readiness-gate.sh` exits 0.
2. The capture script and the gate agree on the hash for the current tree. Verify: a test
   asserts `git_data_rung2_user_data_sha256` output equals the value the capture script would
   write — one shared call, so disagreement is structurally impossible; the test guards the
   *call site*, not the arithmetic.
3. `git-data-rung2-boot-evidence.env` is **ABSENT** from the PR.
   Verify: `test ! -f apps/web-platform/infra/git-data-rung2-boot-evidence.env`.
4. Both interlocks still HOLD on this branch.
   Verify: sourcing the lib and calling `git_data_rung2_rehearsal_gate apps/web-platform/infra/cloud-init-git-data.yml`
   exits **1** with the `no rung-2 boot evidence` message.
5. The DO-NOT-DISPATCH banner is still present.
   Verify: `grep -c 'DO NOT DISPATCH THIS YET' knowledge-base/engineering/operations/runbooks/git-data-birth.md` == 1.
6. ADR-149 item 7 is **untouched**.
   Verify: `git diff origin/main -- <ADR-149>` contains no change to the item-7 row; the string
   `NOT SATISFIABLE AS WRITTEN` still appears exactly once.
7. The rehearsal root references **no** prod git-data address.
   Verify: `grep -cE 'hcloud_(server|volume|firewall)\.git_data\b|terraform_remote_state' apps/web-platform/infra/rung2-rehearsal/*.tf` == 0.
8. The rehearsal workflow's environment has a non-empty reviewer set (DP-11 F8).
   Verify: the existing `terraform-target-parity.test.ts` DP-11 F8 assertion covers
   `web-platform-infra-apply`; add an assertion that the new workflow declares that
   `environment:`.
9. `dry_run` defaults to `true` and `fault_injection` defaults to `false`.
   Verify: `actionlint .github/workflows/git-data-rung2-rehearsal.yml` clean **and** the new
   suite asserts both defaults. (Use `actionlint` for the workflow YAML and
   `bash -c '<extracted run: snippet>'` for embedded shell — never `bash -n` on a `.yml`.)
10. The new suite is registered in CI, not merely on disk.
    Verify: `bash apps/web-platform/infra/run-registered-suites.sh --list` lists
    `git-data-rung2-rehearsal.test.sh` and reports **zero** orphans.
11. `git-data-render-strip-parity.test.sh` covers all **three** copies of the strip expression.
12. Full infra suite green: `bash apps/web-platform/infra/run-registered-suites.sh` exits 0.
    **Run the gate's own invocation, not a hand-enumerated reconstruction of its inputs**
    (`cq-assert-anchor-not-bare-token`, and the #7003 AC-scope lesson).
13. C4 validates: `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` green,
    and `gitDataStore`'s description no longer claims the banner is what holds the route.
14. The `#7025` premise correction is recorded (issue comment) naming both stale claims.

### Post-merge (operator)

15. **Dispatch the rehearsal in `dry_run=true` mode** and confirm the plan creates only
    rehearsal addresses and destroys nothing.
    *Automation:* fully automated — `gh workflow run git-data-rung2-rehearsal.yml -f confirm=REHEARSE-GIT-DATA -f dry_run=true`.
    The operator's only action is the **environment approval**, which is the deliberately-gated
    human authorization, not an operator checklist step.
16. **Dispatch `dry_run=false`** when ready to produce evidence. Produces the evidence file as
    an artifact + a PR for human review. Merging that PR is what releases the rung-2 gate.
    *Automation:* dispatch + capture + teardown are automated; the environment approval and the
    evidence-PR review are the two intentional human gates.

## Open Code-Review Overlap

**None.** Scanned all 60 open `code-review` issues against every path in *Files to Edit* /
*Files to Create* using the two-stage `gh --json` → standalone `jq --arg` form (single-stage
`gh --jq --arg` does not forward `--arg`). Zero matches.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is an infrastructure/CI change with no user-facing surface. The dominant
engineering risk is target-closure blast radius, addressed structurally by the separate
Terraform root rather than by guard logic. Second risk is render drift between the two roots,
addressed by extending the existing strip-parity suite. Third is evidence soundness — the hash
binds payloads but not render vars, which is recorded as a known limit in ADR-149 rather than
assumed away.

### Product/UX Gate

Not applicable. The mechanical UI-surface override does **not** fire: no path in *Files to
Create* or *Files to Edit* matches `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx`. No user-facing surface exists in this change.

**GDPR gate (Phase 2.7):** does not fire. No schema, migration, auth flow, API route, or `.sql`
file is touched; no personal data reaches a rehearsal host (the volumes are created empty and
destroyed empty); no new processing activity is introduced. The existing Sentry/Better Stack
disclosures already cover the telemetry channels the rehearsal reuses.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| A rehearsal apply's target closure reaches `hcloud_server.git_data` and births prod outside the birth route | **Brand-terminal** | Separate Terraform root with its own state key — structurally impossible, not guard-dependent. Plus AC7's grep, plus the dry-run plan assertion. |
| Render drift: the rehearsal root strips comments differently, so it boots a payload it does not attest | High | Extend `git-data-render-strip-parity.test.sh` to the third copy; capture script recomputes the hash via the **shared** helper against the rendered `user_data`. |
| Evidence attests a hash but the rehearsal diverged on render **vars** | Medium | Bounded by design: only identity-shaped vars diverge. Evidence file carries a comment block enumerating every divergence. Recorded as a known limit in ADR-149. |
| Leaked rehearsal host keeps running on the prod private net | Medium | `if: always()` teardown + a post-teardown Hetzner API assertion that no server matching the rehearsal prefix survives. |
| Better Stack returns zero rows and is read as "dark boot" when the channel was simply never instrumented for this host | Medium | The capture script anchors on `stage:bootcmd_start` first; only after that row lands does an absent `boot_complete` mean a dark boot. Never read silence as evidence. |
| The workflow auto-commits evidence, making the route self-approving | High | Evidence lands as an artifact + a PR. The workflow has `contents: read` only on the capture job. |
| A clean rehearsal proves the info channel but not the **fatal** channel | Medium | The `fault_injection` arm deliberately forces a fatal and asserts it arrives. Without this the rehearsal would not test the failure reporter — the exact thing the interlock exists for. |
| Reusing `web-platform-infra-apply` makes a rehearsal approval look like a birth approval | Low | Distinct confirm token (`REHEARSE-GIT-DATA` vs `BIRTH-GIT-DATA`), distinct workflow name, distinct concurrency group. Alternative (a dedicated environment) recorded in the ADR amendment with its DP-11 F8 cost. |

## Test Scenarios

1. **Gate still holds with no evidence** — call `git_data_rung2_rehearsal_gate` on a tree with
   no evidence file; expect exit 1 and the `no rung-2 boot evidence` message.
2. **Gate accepts well-formed evidence** — synthesize an evidence file with the live hash;
   expect exit 0. *(Fixture synthesized only, `cq-test-fixtures-synthesized-only`.)*
3. **Gate rejects a stale hash** — mutate one payload byte; expect exit 1 with `STALE EVIDENCE`.
4. **Gate rejects a malformed hash / missing URL / missing PASS** — three separate arms.
5. **Payload-floor fail-closed** — feed a `git-data.tf` whose `file()` extraction yields <10
   inputs; expect `ABORT`.
6. **Capture script three-state contract** — stub `betterstack-query.sh` to return (a) no rows
   → exit 2, (b) a row with `no` → exit 1, (c) all-positive → exit 0 **and** an evidence file.
7. **Capture script writes nothing on non-PASS** — assert no evidence file after arms (a)/(b).
8. **`--host-name` default preserves prod behaviour** — invoking the #6982 probe with no
   arguments still queries `soleur-git-data`.
9. **Rehearsal root purity** — grep assertions for AC7.
10. **Workflow input defaults** — `dry_run: true`, `fault_injection: false`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
  deepen-plan or `/work`.
- **Do not "simplify" the rehearsal into the shared root.** `count = 0` looks equivalent and is
  not: `-target` is transitive on dependencies, so any rehearsal address referencing a prod
  `git_data` attribute pulls the prod host into the plan closure. The separate root is the
  control; the greps are only the belt.
- **`local.git_data_rationale_strip` now has three copies.** The parity suite is the only thing
  keeping them equal, and an unequal copy means the rehearsal attests a payload it did not boot.
- **The evidence file is the release artifact — never let CI commit it.** A workflow that writes
  its own gate-releasing evidence to `main` converts a two-human-gate route into a one-dispatch
  route.
- **`actionlint` is for workflows only.** It emits spurious "section missing" errors against
  composite `action.yml` files. Use `bash -c '<extracted snippet>'` for embedded `run:` shell,
  never `bash -n` on a `.yml`.
- **`betterstack-query.sh` Mode 1 takes raw SQL as the first positional and rejects `--since`**
  (exit 64). The time window lives *inside* the SQL, as the #6982 probe's header records.
