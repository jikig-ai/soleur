---
title: "chore(infra): sweep the dead web-2 dispatch surface, retain and re-anchor the coherence verifier"
date: 2026-07-20
type: chore
lane: cross-domain
closes: [6575]
refs: [6712, 6730, 6538, 6725, 6574, 6425, 6040, 6416, 6718]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
deepened: 2026-07-20
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

> **Phase 2.8 IaC routing — reviewed, ack recorded above.** This plan introduces **no** new
> infrastructure: no server, service, cron, vendor account, DNS record, cert, secret, firewall rule
> or webhook. Its only `.tf` edit is a **comment** (`issue-alerts.tf:1524-1542`). Every occurrence of
> "operator-local apply" below is a **quotation of the repo's pre-existing state** — the
> `host_creates` HALT text and #6730's own framing — reproduced so the plan can describe what it must
> not silently delete. Closing that gap is **#6730's** scope and an explicit non-goal here.

# chore(infra): sweep the dead web-2 dispatch surface, retain and re-anchor the coherence verifier

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec directory exists
> for this branch.

## Enhancement Summary

**Deepened:** 2026-07-20 · **Agents:** architecture-strategist, code-simplicity-reviewer,
spec-flow-analyzer, plus four targeted verification sweeps.

The deepen pass **materially re-scoped this plan.** Version 1 proposed relocating the coherence
guard to a new bake-time gate in `reusable-release.yml`. All three review agents independently
falsified that design, and direct verification confirmed every objection:

1. **The proposed gate was near-tautological.** At `docker_build`, the image and the checkout are
   the same commit by construction, so the gate could only fail on Dockerfile/`server.tf` list
   drift — which `plugins/soleur/test/cloud-init-user-data-size.test.ts:486-510` **already** catches
   at PR time, earlier, with a better diagnostic (it names the file; a hash gate prints two opaque
   64-hex strings).
2. **It would have poisoned `:latest`.** `reusable-release.yml:596-599` pushes `:v<next>`,
   `:<sha>` and `:latest` in a single `build-push-action` step. The gate ran *after* that, so a
   failure would leave `:latest` pointing at a known-incoherent image — creating the exact
   `single-user incident` the plan exists to prevent.
3. **Its feasibility premise was wrong.** v1 justified a new bash hash-recompute script by claiming
   `terraform console` needs credentials. `local.host_scripts_content_hash` is a pure function of
   `path.module` + `filesha256`; `infra-validation.yml:204-206` already proves
   `terraform init -backend=false` evaluates it "WITHOUT a Hetzner token or the R2 backend."
4. **Coverage was never zero.** The premise that a naive sweep drops coverage 1 → 0 is false: the
   baked-set parity test above is a live, required-check coherence guard that survives this PR
   untouched.

**Net effect: ~155 lines of new code/test are no longer written, and the PR becomes a clean sweep
plus a small, genuinely non-tautological coverage addition.** Four further premises were falsified
(rows 10-13 below), bringing the total to **thirteen**.

---

## Overview

Two issues contend over the same 104-line file.

`apps/web-platform/infra/scripts/web2-recreate-preflight.sh` is the repo's only *pinned-digest*
coherence verifier. It has exactly one executable call site,
`.github/workflows/apply-web-platform-infra.yml:1372`, inside the `web_2_recreate` dispatch job.

- **#6575** lists that script, its test, its gate lib and its 8 fixtures for deletion as dead web-2
  surface.
- **#6712** says that same script is the only artifact that would stand between a fresh web-1
  create/`-replace` and a doomed `runcmd`.

### What the research established

**There are two distinct coherence invariants, and the framing conflates them.**

| Invariant | What it catches | Status today | After this PR |
|---|---|---|---|
| **Build-integrity** — the image's baked `/opt/soleur/host-scripts/` matches the repo tree it was built from | Dockerfile `COPY` list drift; a post-`COPY` `RUN` mutating the directory; a duplicate list entry | Partly covered: `cloud-init-user-data-size.test.ts:486-510` asserts **list** parity in a required check | **Strengthened** — two new static assertions close the post-`COPY`-mutation and duplicate-entry gaps |
| **Cross-commit skew** — the image Terraform's `host_scripts_content_hash` was computed against is the image the host actually pulls | An apply at commit `C_tf` while `:latest` points at `C_img` — the real #6712 hazard | Nominally 1 call site; **effectively 0** (the gate needs `web2_server_replaced == 1`, unsatisfiable with web-2 absent from state) | **Still 0.** Closable only by digest-pinning `var.image_name`, which is **#6730's** scope |

The second row is why **#6712 does not close in this PR.** Its gap is an *apply-time* property:
`var.image_name` defaults to the mutable `ghcr.io/jikig-ai/soleur-web-platform:latest`
(`variables.tf:67-71`) while `host_scripts_content_hash` comes from the applying commit. No
build-time artifact can observe that. Closing it requires a resolver plus a digest-pinned birth
path — exactly what #6730 scopes and what PR #6725's operator decision already deferred.

**There is also no web-1 create/replace path to hang a guard on.** Every automated route to
`hcloud_server.web` terminates in the `host_creates > 0` HALT
(`apply-web-platform-infra.yml:462-475`). #6730 owns building that path.

### What this PR therefore does

1. **Sweeps** the dead web-2 dispatch surface: the `warm_standby` job, the 481-line `web_2_recreate`
   job, their gates, fixtures, orphaned scripts, falsified registers, and every parity sentinel they
   pin.
2. **Retains and re-anchors** the coherence verifier — renamed host-agnostic, logic byte-unchanged —
   by giving it a *documented, executable operator procedure* in the `host_creates` HALT runbook
   (the complete `crane digest` → verify → `-var image_name=` chain), so it is named in a live
   procedure rather than left callerless.
3. **Adds two cheap static assertions** to the existing required-check parity test, closing real
   build-integrity gaps that nothing covers today.
4. **Corrects the registers** the retire falsified, without deleting host-generic protections.

**Coverage accounting.** Before: one live list-parity test + one unreachable dispatch verifier.
After: the same list-parity test + two new assertions + a verifier named in an executable runbook
chain. Strictly greater, never zero at any commit, and every addition is non-tautological.

---

## Research Reconciliation — stated premises vs codebase

**Thirteen premises were falsified.** Rows 1-9 came from the task framing (several inherited from
#6575's body); rows 10-13 came from this plan's own v1 and were caught by the deepen pass.

| # | Stated premise | Reality (verified) | Plan response |
|---|---|---|---|
| 1 | `warm_standby`: "**4 of its 6** targets are web-2" | **3 of 6** (`:973-975`). The other 3 are `hcloud_network.private`, `hcloud_network_subnet.private`, `hcloud_server_network.web["web-1"]`. The workflow's own enum says "3 of its 6"; #6575 says 4 while listing 3. | Use **3 of 6**; re-check the 3 non-web-2 targets (AC7). |
| 2 | Enum drops **9 → 6** | 9 today; this sweep removes exactly **2** → **7**. No third option is named anywhere. | **7**. Do not invent a third deletion to match a wrong number. |
| 3 | `MIN_APPLY_TARGET_OPTIONS = **8**` | Actual **9** (`:105-110`). | 9 → 7. |
| 4 | `web-1-swap-concurrency-parity.test.sh` asserts "exactly **4**" | Asserts **5** (`:128`). Its own header at `:30` says 4 and is **already stale**. | `-eq 5` → `-eq 3`; fix the stale header too (AC6). |
| 5 | `web_2_recreate` is "~490 lines" | **481** (`:1134-1614`). | Cosmetic. |
| 6 | Deletion relieves "`scoped-apply-gate.sh` refactor" pressure | **Zero hits repo-wide.** The real tracker is **#6574** (`-target` transitivity), which this deletion does not touch. | See § scoped-apply-gate re-assessment. |
| 7 | Delete the web-2 Sentry dead-boot alert | `sentry_issue_alert.web_terminal_boot_fatal` (`:1543-1605`) filters on `stage`, **never on host**. Deleting it removes the sole no-SSH boot page for **web-1**. Only its comment is web-2-specific. | **Comment rewrite only** (AC9). |
| 8 | Pick (a) resolve-`:latest` preflight, or (b) pin like the recreate job | **(a)** is rejected by PR #6725's recorded decision (quoted below). **(b)**'s mechanism polls the *running* web-1's `/health`, empty on a fresh create → `exit 1`. | Neither. See § Architecture Decision. |
| 9 | `lb-weight-gate.sh:107` — "not CI-wired, but fix it" | The **script** is not wired; its **test** is (`infra-validation.yml:585`). Deleting only line 107 leaves a gate that **passes on a single-host roster**. | Delete script **and** test (AC10). |
| 10 | *(v1)* A naive sweep drops coherence coverage 1 → **0** | **False.** `plugins/soleur/test/cloud-init-user-data-size.test.ts:486-510` asserts Dockerfile↔`server.tf` baked-set parity in the required bun suite, before and after this PR. | Coverage table rewritten; the mandatory relocate-before-delete phase ordering **dissolves**. |
| 11 | *(v1)* A bake-time gate in `reusable-release.yml` adds coverage | **Near-tautological**: image and tree share a commit at `docker_build`; the only reachable failure is list drift, already caught earlier by row 10's test. Worse, `:596-599` pushes `:latest` in the same step, so a gate failure **poisons `:latest`**. | Gate **dropped**. See § Alternative Approaches. |
| 12 | *(v1)* `terraform console` is unavailable on the release path, so a bash hash-recompute is needed | **False.** `local.host_scripts_content_hash` is a pure function of `path.module` + `filesha256`; `infra-validation.yml:204-206` runs `terraform init -backend=false` "WITHOUT a Hetzner token or the R2 backend." | `host-scripts-want-hash.sh` + its test **dropped** (also moot once the gate is dropped). |
| 13 | *(v1)* `resolve-web1-known-good-tag.sh` has **one** caller | **Two**: `apply-web-platform-infra.yml:1336` and `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh:159`. Both are deleted here. | Retention decided by the uniform rule below, not case-by-case. Also: `test-all.sh`'s `run_suite` is at **`:218`**, not `:233`. |

Premises that **held**:

- web-2 retire merged/closed 2026-07-17; `variables.tf:101` carries the RETIRED comment; web-2 absent from `web_hosts`. #6575's sequencing gate is satisfied.
- `cloud-init.yml:559` `[ "$GOT" = "$HOST_SCRIPTS_HASH" ] || exit 1` runs under the `set -e` armed at `:468`. The only earlier `set +e` (`:480`) is confined to a subshell closing at `:515`; the next is `:568`, after. **Confirmed.**
- `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }` (`server.tf:288-290`).
- `hcloud_server.web` appears in **no** `-target=` in the `apply` job (168-863). The only one naming it is `:1390`, `["web-2"]`.
- **Nuance the framing omits:** `nic-wait-gate.test.sh:381-386` records that "web-1 is in no `-target=`, therefore a routine apply cannot create it" is an **invalid inference** — `-target` is transitive, so `hcloud_server.web` *is* reachable via `cloudflare_record.app` and `hcloud_firewall_attachment.web`. The real guarantor is the `host_creates` HALT. Preserve this correction; do not restate the invalid inference.

**Premise Validation.** #6712, #6575, #6730, #6425, #6574 all OPEN. #6040 CLOSED with a sweeper-dead
script still on disk. No cited artifact was missing; thirteen were mis-stated.

---

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` queried against every planned
file path returned zero matches.

---

## User-Brand Impact

**If this lands broken, the user experiences:** `app.soleur.ai` returns nothing — no page, no error
page, no DNS failover. A web-1 born on an image whose baked host-scripts disagree with the applied
`host_scripts_content_hash` aborts its entire cloud-init `runcmd` at `stage=verify` — no cloudflared
connector, no deploy webhook, no monitors, no egress firewall. `runcmd` is once-per-instance, so
**no reboot repairs it**, and there is no failover partner (web-2 retired; #6459 unbuilt).

**If this leaks, the user's data is exposed via:** the transient window in that same failure — a host
reaching the network before its egress firewall and AppArmor/seccomp profiles apply is briefly
unconfined (the #6416 class). No new secret material is introduced.

- **Brand-survival threshold:** `single-user incident`

Sole operator, sole web host, hard-pinned singleton A record. One bad birth is a total outage with no
automated recovery. CPO sign-off required at plan time; `user-impact-reviewer` at review time.

**What the threshold demanded, and how v1 got it wrong.** v1 read the threshold as "add a guard
before deleting anything." The deepen pass showed the guard it added was tautological *and* created a
new `:latest`-poisoning failure mode — i.e. the threshold-driven addition was itself the largest
single-user-incident risk in the PR. The threshold is honoured here by **not** shipping a
safety-shaped mechanism that cannot fire, by keeping the deletion honest, and by refusing to mark
#6712 closed while its hazard is live.

---

## Architecture Decision (ADR/C4)

### ADR

**New ADR — "Coherence has two invariants: build-integrity is statically checkable; cross-commit
skew needs a digest-pinned birth path."** Ordinal **provisional**; derive from a freshly-fetched
`origin/main` and let `/ship`'s ADR-Ordinal Collision Gate re-verify. On renumber, sweep
`grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-one-shot-6712-6575-*/`.

Decision content:

- **Name the two invariants separately** (the table in § Overview). Conflating them is what made
  both #6575 and #6712 read as closable together.
- **Build-integrity is enforced statically**, in `cloud-init-user-data-size.test.ts` — list parity
  (existing) plus post-`COPY` mutation and duplicate-entry assertions (new). No image pull, no
  registry round-trip, no release-path coupling.
- **Cross-commit skew is not closable here.** It requires pinning `var.image_name` to a digest at
  create time. Owned by **#6730**.
- **The verifier stays pure.** `host-scripts-coherence-preflight.sh` accepts **only** a pinned
  `repo@sha256` ref and `die`s otherwise; its digest-`die` branch must remain reachable.
- **Retention rule (uniform, replacing case-by-case judgement):** *retain a callerless script iff it
  is named as a step in a documented procedure an operator can execute today; delete otherwise, and
  preserve its design record in this ADR.* Applied: preflight **retained** (named in the HALT
  runbook chain); `resolve-web1-known-good-tag.sh` **retained** (named in the `-replace` arm of the
  same chain); `lb-weight-gate.sh` **deleted** (no procedure; subject gone);
  `deploy-status-fanout-verify.sh` **deleted** (no procedure; both callers gone).
- **Alternatives considered:** see § Alternative Approaches — in particular the bake-time gate,
  rejected with measured evidence rather than on taste.

Rationale for rejecting a mutable-tag-accepting verifier, quoted verbatim from
`knowledge-base/project/plans/2026-07-19-fix-warm-standby-web1-birth-halt-plan.md:110-149`:

> The correct shape is **two scripts, not one**. `web2-recreate-preflight.sh` is a *pure verifier*
> whose header states the invariant — *"resolved ONCE upstream; AC3b TOCTOU — this script does NOT
> re-resolve a tag."* Generalizing it to accept a mutable ref would move the TOCTOU closure from
> "structurally cannot re-resolve" to "the caller faithfully consumes the emitted value", and make
> its digest `die` branch dead code on the mutable arm — a weaker guarantee sold as a
> generalization. Keep the verifier byte-unchanged; add a separate resolver; callers compose
> resolve → verify → `plan -var image_name=<pinned>`.

### ADR-082 supersession

`ADR-082-fresh-web2-boot-observability.md` is **Status: Adopting**; its entire subject is web-2.
Supersede per the `ADR-008` convention (verified as the repo pattern): YAML frontmatter
(`status: superseded-in-part`, `superseded_by: [ADR-<new>]`) **plus** an inline banner **plus** an
explicit in-force / dead partition:

- **Remains in force:** Item 3 (fresh-host post-container egress-enforcement probe, shipped).
- **Remains in force but UNMET, owned by #6730:** Item 4 (image digest pin + signature verification).
  **Do not record Item 4 as discharged** — nothing here pins `var.image_name`, and the boot path
  performs no signature verification (`server.tf`'s own threat-model comment says so).
- **Dies with the retire:** Item 1 (per-host uptime absence detector), Item 2 (A-record drain on boot
  failure), Item 5's web-2 clauses.
- **Falsified `:52-53`** — *"the SOLE page for a dead web-2 warm standby"* — is the same claim the
  Sentry comment encodes; rewrite both consistently. **`:45-46`** claims Item 5 is "half-met
  (web-2 only)"; post-retire it is 0%-met.

### ADR-114 amendment

`ADR-114:365-373` hazard #5 cites the preflight's web-2-only scope. The **hazard survives** and
applies to every host; only its scope statement changes. Rewrite `:369-372` to say the verifier is
now host-agnostic and reachable via the documented operator chain, while the underlying mutable-tag
hazard remains open under #6730. **Preserve `:375-380` verbatim** — the paragraph refuting the
"web-1 appears in no `-target=`" inference is load-bearing and independently correct.

### C4 views

Read all three model files — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — in full, not by keyword grep.

Enumeration (the completeness mandate; a bare "None" is a reject condition):

- **External human actors:** none added or removed.
- **External systems / vendors:** none added. GHCR is already modeled; this PR adds no registry edge
  (the bake-time gate that would have added one is dropped).
- **Containers / data stores:** none. `warm_standby` / `web_2_recreate` are workflow jobs, not C4
  containers.
- **Actor↔surface access relationships:** none change.
- **Element descriptions falsified:** `model.c4` carries one `warm-standby` hit. Read it; if it
  describes a live element, correct it — the retire falsified it independently of this PR.

If that hit describes a live element, edit it, add any needed `view … include` in `views.c4`, and run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (an undefined-element `include`
fails there, not at `tsc`).

---

## Observability

```yaml
liveness_signal:
  what: the baked-set coherence assertions in the required bun suite —
        "Dockerfile <-> server.tf baked-set parity" (existing, list parity)
        plus the two new assertions (no post-COPY mutation; no duplicate entries)
  cadence: every pull request and every push to main (required check)
  alert_target: the PR check fails and blocks merge
  configured_in: plugins/soleur/test/cloud-init-user-data-size.test.ts (run via
                 `run_suite "plugins/soleur" bun test plugins/soleur/` in scripts/test-all.sh)
error_reporting:
  destination: vitest/bun assertion failure naming the drifting file, surfaced in the
               GitHub PR check annotation
  fail_loud: true — a failing assertion blocks merge; there is no soft-warn path
failure_modes:
  - mode: Dockerfile COPY set and server.tf host_script_files diverge
    detection: existing `expect(df).toEqual(tf)` assertion, which names the differing entries
    alert_route: required PR check fails before merge
  - mode: a build step added after the COPY mutates /opt/soleur/host-scripts/, so baked bytes
          differ from repo bytes while the file LISTS still match
    detection: NEW static assertion — no RUN instruction between the host-scripts COPY and the
               end of the runner stage writes into /opt/soleur/host-scripts/
    alert_route: required PR check fails before merge
  - mode: a duplicate entry in host_script_files makes the Terraform-side list hash and the
          boot-side `find . -type f` hash disagree permanently
    detection: NEW assertion — host_script_files contains no duplicates
    alert_route: required PR check fails before merge
  - mode: cross-commit skew (apply at C_tf while :latest points at C_img) — the live #6712 hazard
    detection: NOT DETECTED by this PR. Boot-side `cloud-init.yml:559` aborts at stage=verify and
               the terminal block emits `soleur-boot-emit <stage> fatal`, paging via
               sentry_issue_alert.web_terminal_boot_fatal (retained, AC9).
    alert_route: Sentry issue alert (first occurrence) — the sole no-SSH boot page for web-1.
                 Prevention is owned by #6730.
  - mode: silent vacuity — a parity assertion goes green because its subject job vanished
    detection: extractJobBlock returns "" for a missing job, so ~half the web-2 asserts in
               terraform-target-parity.test.ts would pass on nothing. Guarded by DELETING the
               tests (AC5), not by observing them pass.
    alert_route: required PR check (plugins/soleur bun suite)
logs:
  where: GitHub Actions check output for the `test` shard; Sentry for the boot-time arm
  retention: GitHub Actions default (90 days); Sentry per project retention
discoverability_test:
  command: bun test plugins/soleur/test/cloud-init-user-data-size.test.ts
  expected_output: "0 fail"
  # Substring-matched against the command's real stdout (bun prints "30 pass" / "0 fail").
  # Prose here would never match and would FAIL preflight Check 10 row 6 — the
  # expected_output field is EXECUTED, not read.
  # Semantics: the "Dockerfile <-> server.tf baked-set parity" describe block passes,
  # including the two new assertions; a duplicated host_script_files entry makes it fail.
```

No `ssh` appears in any command. No soak/time-gated close criterion is declared, so §2.9.1
follow-through enrollment does not fire.

---

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

**Finding: no new infrastructure.** No server, service, cron, vendor account, DNS record, cert,
secret, firewall rule or webhook. `terraform-architect` routing is not triggered.

### Terraform changes

Deletions and comment corrections only. No new resource, provider, variable, `TF_VAR_*` or minted
credential.

- `apps/web-platform/infra/sentry/issue-alerts.tf` — **comment rewrite only** at `:1524-1542`. The
  `sentry_issue_alert.web_terminal_boot_fatal` resource is host-generic and **must survive** — it is
  the detection arm for the one failure mode this PR cannot prevent. `frequency = 24` is documented
  as dedup-unique; do not renumber.
- `apps/web-platform/infra/lb-weight-gate.{sh,test.sh}` — deleted (AC10). Not Terraform resources;
  listed here because they are infra gates.

### Apply path

**No apply is required.** The Sentry edit is a comment; `apply-sentry-infra.yml` re-plans it as a
no-op.

Merge-trigger interaction: `apply-web-platform-infra.yml` fires on `apps/web-platform/infra/**`
**and** on `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (#4419 defense-in-depth). This PR
touches both, so the auto-apply **will** run. Expected plan: **zero changes** (AC11).

**Network-Outage Deep-Dive (Phase 4.5, resource-shape trigger).** That merge-triggered apply includes
a **token-gated SSH leg** (8 `terraform_data.*` siblings in `server.tf`, applied over the CF Tunnel
SSH bridge, `.github/actions/cf-tunnel-ssh-bridge`). The bridge is a hard apply-time dependency with
`connection { type = "ssh" }` semantics, so this PR's merge run can go red for reasons unrelated to
its diff:

- **L3 firewall allow-list** — the runner egress IP is deliberately *not* in `var.admin_ips`; access
  is via the tunnel, not a direct `:22` dial. No allow-list change is needed or made here.
- **L3 DNS / routing** — tunnel hostname resolution; unchanged by this PR.
- **L7 tunnel / cloudflared** — `CLOUDFLARED_VERSION` / `CLOUDFLARED_SHA256` pins unchanged.
- **L7 application** — the 8 `terraform_data` siblings are untouched.

**Verification status: all four layers unchanged by this diff.** If the merge run fails on the SSH
leg, the correct diagnosis is bridge/firewall drift (per `hr-ssh-diagnosis-verify-firewall`, verify
the allow-list and egress IP *before* any sshd/fail2ban hypothesis) — **not** a regression from this
PR. AC11 covers the plan being 0/0/0; a red SSH leg with a 0/0/0 plan is pre-existing drift.

### Distinctness / drift safeguards

No `dev`/`prd` divergence. No state-stored secret changes. `hcloud_server.web`'s
`lifecycle.ignore_changes` is untouched and must remain so — `nic-wait-gate.test.sh:420-421` pins it.

### Vendor-tier reality check

No new vendor resource. No registry round-trip is added (the bake-time gate that would have required
a GHCR pull and a `docker login` in the release job's shell is dropped).

### Pre-existing gap deliberately not closed

The `host_creates` HALT routes a web-host birth to a locally-run full `terraform apply` per the
`OPERATOR_APPLIED_EXCLUSIONS` contract (ADR-096). That violates
`hr-fresh-host-provisioning-reachable-from-terraform-apply` and is **already filed as #6730**. This
plan neither creates nor widens it; it **narrows** the operator's exposure by supplying a complete,
executable verify-then-pin chain in the HALT text (Phase 3.1). Folding #6730's work in here was
considered and rejected (§ Alternative Approaches).

---

## Implementation Phases

No cross-phase ordering constraint applies: build-integrity coverage
(`cloud-init-user-data-size.test.ts:486-510`) is live before, during and after every commit. The
rename must nonetheless be **atomic with its references** (Phase 2.8) — a `git mv` that leaves the
call site or the parity assertion pointing at a vanished path breaks CI mid-branch.

### Phase 0 — Preconditions

- 0.1 `bash scripts/test-all.sh` on a clean tree; record the baseline so post-deletion deltas are
  attributable.
- 0.2 Re-grep every `file:line` anchor in this plan. Phase 2 removes ~730 lines from
  `apply-web-platform-infra.yml`; anchors below that point shift.

### Phase 1 — Strengthen build-integrity coverage (additive, ~10 lines)

- 1.1 In `plugins/soleur/test/cloud-init-user-data-size.test.ts`, inside the existing
  `describe("Dockerfile <-> server.tf baked-set parity (AC2)")`:
  - **New assertion A** — no `RUN` instruction between the host-scripts `COPY` and the end of the
    runner stage writes into `/opt/soleur/host-scripts/`. Today only
    `RUN chown -R 1001:1001 /opt/soleur` follows it, which is ownership-only and content-preserving;
    the assertion pins that nothing content-mutating is added later. Allow-list the `chown` form
    explicitly so the assertion states *why* it is safe.
  - **New assertion B** — `host_script_files` contains no duplicate entries. The Terraform side
    hashes an enumerated list (duplicates preserved by `sort()`); the boot side hashes files found on
    disk. A duplicate makes the two constructions disagree permanently.
- 1.2 Harden the existing parser against the comment-quoting hazard: strip `^\s*#` lines before the
  `/"([^"]+)"/g` match. The `host_script_files` block carries ~10 interleaved comment lines; none
  contains a double-quoted string *today*, but one future comment reading
  `# … installs "vector.toml" …` would silently inject a phantom entry. Add a fixture asserting a
  quoted comment does not change the parsed set.
- 1.3 Verify non-vacuity: temporarily duplicate an entry and confirm assertion B fails; temporarily
  add a `RUN sed -i` into the baked dir and confirm assertion A fails. Do not commit either.

### Phase 2 — Delete the web-2 dispatch surface

- 2.1 Delete `warm_standby` (`:864-1113`), `web_2_recreate` (`:1134-1614`) and the intervening
  comment block (`:1114-1133`).
- 2.2 Remove both enum options (`:99-108`); rewrite the `apply_target` description for the remaining
  **7**.
- 2.3 Delete `tests/scripts/lib/web2-recreate-gate.sh`.
- 2.4 Delete the `web2_allow` (`:107-111`), `web2_out_of_scope_changes` (`:241-246`) and
  `web2_server_replaced` (`:251-256`) clauses plus rationale (`:99-106`, `:218-240`, `:247-250`) from
  `tests/scripts/lib/destroy-guard-filter-web-platform.jq`. Safe by the filter's own contract at
  `:237-238`: *"additive key; no consumer of THIS key exists outside the web_2_recreate gate."*
  **Do NOT touch `web2_retire_allow` (`:113-…`) or `retire_firewall_attachment_deletes`** — a
  separate surface with the opposite data-volume contract, warned against at `:113-133`. Fix the
  orphaned cross-reference in the `host_creates` comment (`:331`).
- 2.5 Delete the 8 `tfplan-web2-recreate-*.json` fixtures and cases T20-T28 plus the `_run_web2_gate`
  helper (`:426-439`, `:443-560`) in `tests/scripts/test-destroy-guard-counter-web-platform.sh`.
  **Before deleting**, confirm a surviving counter test still exercises: non-placement-update
  detection (fixture 4), `forget`-counted-as-destroy (fixture 6), and `IN()` exact-equality vs
  substring (fixture 8). Retarget any fixture whose mechanism would otherwise lose coverage (AC4).
- 2.6 Delete `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` and
  `apps/web-platform/infra/deploy-status-fanout-verify.test.sh`, plus its `infra-validation.yml:576`
  registration. Both callers are deleted here; no procedure names it. Its `ROSTER_COUNT -ne 2`
  invariant is falsified by the retire independently. **Preserve its design record in the ADR** —
  specifically the `.tag` last-write-wins trap (`resolve-web1-known-good-tag.sh:6-13`) — so #6730 does
  not rediscover it.
- 2.7 Delete `apps/web-platform/infra/lb-weight-gate.sh` + `lb-weight-gate.test.sh` and its
  `infra-validation.yml:585` registration; record in ADR-068 §(c). Per the retention rule: no
  procedure names it and its subject (a second origin to weight) is gone. Deleting only the
  `has("web-2")` line would leave a gate that passes on a single-host roster and green-lights a
  weight flip to a nonexistent host.
- 2.8 **Atomic rename commit.** In ONE commit:
  `git mv apps/web-platform/infra/scripts/web2-recreate-preflight.sh .../host-scripts-coherence-preflight.sh`;
  `git mv tests/scripts/test-web2-recreate-preflight.sh tests/scripts/test-host-scripts-coherence-preflight.sh`;
  update `scripts/test-all.sh:218`; and confirm no reference remains in
  `apply-web-platform-infra.yml` or `terraform-target-parity.test.ts:1252` (both deleted in 2.1/3.2 —
  sequence 2.8 after them, or fold all three into one commit). Rename env seams
  `WEB2_PREFLIGHT_WANT_HASH` → `HOST_SCRIPTS_WANT_HASH`, `WEB2_PREFLIGHT_SEED_DIR` →
  `HOST_SCRIPTS_SEED_DIR`; `die()` prefix and success line → `host-scripts-coherence`. Rewrite the
  header host-agnostically, naming its consumer: the HALT runbook chain (Phase 3.1) today, a
  digest-pinned birth path (#6730) later. **Comparison and validation logic byte-unchanged.**
  Retain all six test cases.
- 2.9 Retain `resolve-web1-known-good-tag.sh` + its test under the retention rule — it is the
  `-replace` arm of the Phase 3.1 chain (for a *running* web-1, its `/health .version` source
  exists). Correct the record: it had **two** callers, both deleted here. Keep its
  `infra-validation.yml:579` registration.

### Phase 3 — Runbook lines: what happens instead

**Non-negotiable:** every deleted runbook line gets an explicit replacement. Where a capability
genuinely disappears, say so.

- 3.1 **`host_creates` HALT text** (`:462-475`; the parallel HALT at `:1005-1008` dies with its job).
  - Remove the `warm-standby (#6718 …)` and `web-2-recreate (gate needs web2_server_replaced==1 …)`
    clauses and the trailing warm-standby aside.
  - **Routing is unchanged and already correct:** no automated path; fall back to the locally-run
    full apply per `OPERATOR_APPLIED_EXCLUSIONS` (ADR-096), tracked by **#6730**. Retain the
    `inngest-host` bullet — a live path.
  - **Add the complete, executable verify-then-pin chain** — not an instruction to "run the
    preflight", which would be unactionable (the preflight refuses the mutable `:latest` the
    operator holds, by design):

    ```
    DIGEST=$(crane digest ghcr.io/jikig-ai/soleur-web-platform:latest)
    PINNED="ghcr.io/jikig-ai/soleur-web-platform@${DIGEST}"
    PINNED="$PINNED" bash apps/web-platform/infra/scripts/host-scripts-coherence-preflight.sh
    terraform apply -var image_name="$PINNED" ...
    ```

  - **Add one sentence on `ignore_changes`:** `hcloud_server.web` carries
    `ignore_changes = [..., image, ...]` (`server.tf:288-290`), so a pin applied at create is
    honoured, and a later routine apply will not drift it back. An operator who does not know this
    will assume the pin was reverted.
- 3.2 **`tests/scripts/lib/stock-preflight-gate.sh` web-2 tine** (`:151-181`, setter `:274-275`).
  - Delete the tine and its 25-line rationale.
  - **Genuine capability loss, stated plainly:** the tine offered a *free repair* — "if you only need
    the NIC or volume re-attached, that is not a recreate; dispatch `warm-standby`, no stock
    required." With web-2 retired and `warm_standby` deleted, **no additive dispatch exists**.
  - **Rewrite the surviving `#6463` tine to be web-1-specific.** Inheriting the generic text is
    wrong: it says "choose a different EU location", but web-1's location is pinned precisely because
    *"a location change would force-REPLACE the live prod host"* (`server.tf:112-118`), and
    `hcloud_volume.workspaces` is location-bound, so relocating strands or recreates the workspaces
    volume — a data-migration decision, not a stock workaround. The real menu is: **wait for stock
    and retry** (primary), or **change `server_type` within hel1** (secondary), with a location
    change explicitly flagged as implying volume recreation.
  - Fix two **already-stale** refs: `:159` cites `apply-web-platform-infra.yml:788-796` (actual
    `:970-975`, both vanishing) and `:178`/`:180` cite `:451` (the HALT is `:462-475`).
  - Restructure the coupled tests in `tests/scripts/test-stock-preflight-gate.sh` **with stated
    reasons**: **T2** (`:117-126`) asserts the abort must name warm-standby — falsified by the
    retire; rewrite to assert the surviving web-1 tine. **T10b** (`:226-239`) and **T13b** (`:324`)
    assert warm-standby is not offered elsewhere — now vacuous; delete with a reason. **T10c**
    (`:242-247`) is the over-suppression guard that exists to catch "a fix that drops the tine
    everywhere" — this PR *is* that fix, legitimately, so deleting it is correct, but the invariant
    must not die with it: **replace T10c** with an assertion that the abort emits ≥1 remediation
    line, so a future edit cannot strip every tine silently.
- 3.3 **`.github/workflows/scheduled-inngest-health.yml`**
  - `:838` step 2 — *"recreate the offending host via … `apply_target=web-2-recreate`"*. With web-1
    the only web host, a non-primary `cloudflared` connector cannot be a second host; it implies a
    hand-run `cloudflared` or a `web_tunnel_connector` predicate regression. New step 2: inspect and
    stop the stray process; if the predicate regressed, fix `server.tf` and redeploy. No recreate
    dispatch exists and the text must not imply one.
  - `:837` — drop the `fra*` = fsn1 = web-2 row from the colo→host attribution table; keep
    `ams*`/`hel*` = hel1 = web-1.
- 3.4 **Follow-through scripts**
  - Delete `scripts/followthroughs/warm-standby-verify-dedup-6030.sh`. Tracker **#6040 is CLOSED**;
    the sweeper only sweeps open `follow-through` issues, so it has not run since. Its subject job is
    deleted here. Nothing replaces it.
  - Delete `scripts/followthroughs/web2-tunnel-depool-6425.sh`. Tracker **#6425 is OPEN** but was
    never enrolled. Its subject — a second tunnel connector — cannot exist post-retire. **Close
    #6425** as discharged-by-#6538 (AC13). Do not leave an open P1 pointing at a deleted script; this
    is the orphan class #6470 tracks.

### Phase 4 — Parity sentinels (each with a `# reason:` comment)

- 4.1 `plugins/soleur/test/stock-preflight-coverage.test.ts`: `MIN_APPLY_TARGET_OPTIONS` **9 → 7**
  (rewrite the 9-name enumeration to the 7 survivors); `MIN_GATED_TARGETS` **5 → 4**
  (`web_2_recreate` was one of five stock-gated jobs at `:1435`; the other four are unaffected);
  delete the `warm-standby` `EXCLUSION_ALLOWLIST` entry (`:68-84`) or the not-stale test at
  `:191-196` fails with `orphans == ["warm-standby"]`; fix prose at `:141` and the title at `:183`.
- 4.2 `plugins/soleur/test/terraform-target-parity.test.ts`: delete `WARM_STANDBY_TARGETS`
  (`:1031-1038`) + its `describe` (`:1040-1130`); delete `WEB2_RECREATE_TARGETS` /
  `WEB2_RECREATE_REPLACE` (`:1179-1184`) + their `describe` (`:1197-1275`), which includes the
  `web2-recreate-preflight.sh` assertion at `:1252`; remove the two `stripJob` wrappers in
  `stripDispatchJobs` (`:412-450`); fix stale comments at `:381-387`, `:402-406`, `:737`,
  `:960-962`, `:1051-1052`. **Delete, do not observe green** — `extractJobBlock` returns `""` for a
  missing job, so ~half these assertions would pass vacuously.
- 4.3 `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`: delete the `web_2_recreate`
  (`:101`) and `warm_standby` (`:102`) `assert_member` lines; count `-eq 5` → `-eq 3` (`:128`);
  **fix the pre-existing stale header at `:30`** (says 4) and prose at `:12`, `:16-17`, `:123`.
- 4.4 `apps/web-platform/infra/web-hosts-fanout-parity.test.sh`: delete
  `check_all_copies "$APPLY_WORKFLOW" "apply-workflow" 2` (`:99`) and the now-unused
  `$APPLY_WORKFLOW` handling incl. the `[ -f … ]` guard (`:35`); fix prose at `:5-6`, `:9-15`. Leave
  the `-lt 1` floor (`:69-70`) — already corrected for the retire.

### Phase 5 — Registers

- 5.1 Author the new ADR (§ Architecture Decision), including the retention rule and the preserved
  `deploy-status-fanout-verify` design record.
- 5.2 Supersede ADR-082 per the ADR-008 convention, with Item 4 marked **in force but UNMET (#6730)**.
- 5.3 Rewrite ADR-114 hazard #5; **preserve `:375-380` verbatim**.
- 5.4 `issue-alerts.tf:1524-1542` — **comment only**; the resource survives unchanged.
- 5.5 Read all three `.c4` files; act on the `model.c4` warm-standby hit; run the C4 tests.
- 5.6 Update `nic-wait-gate.test.sh` comments at `:369-372` and `:404-406` — the verifier is now
  host-agnostic and reachable via the documented chain, and the residual is cross-commit skew owned
  by #6730. Keep every assert green; **do not restate the invalid `-target` inference** the file
  corrects at `:381-386`.
- 5.7 Comment on **#6712** (AC14): it stays OPEN; record that its residual is apply-time mutable-tag
  skew, that the verifier is now host-agnostic with a documented chain, and that closure needs
  #6730's digest-pinned birth path.

### Phase 6 — Verification

- 6.1 `bash scripts/test-all.sh` green; diff against the 0.1 baseline — every delta an intended
  deletion.
- 6.2 `actionlint` on the two edited workflows; `bash -c` on extracted `run:` snippets. **Never
  `bash -n` on workflow YAML**; never `actionlint` on composite `action.yml`.
- 6.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (never `npm run -w`).
- 6.4 Residual sweep per AC3.

---

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-<next>-coherence-two-invariants.md` | The two-invariant decision, the retention rule, the rejected bake-time gate with measured evidence, and the preserved `deploy-status-fanout-verify` design record. |

*(v1's `host-scripts-want-hash.sh` and its test are no longer created — see reconciliation rows 11-12.)*

## Files to Edit

**Renamed (atomic with references, Phase 2.8)**

- `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` → `host-scripts-coherence-preflight.sh`
- `tests/scripts/test-web2-recreate-preflight.sh` → `test-host-scripts-coherence-preflight.sh`
- `scripts/test-all.sh` — `run_suite` at **`:218`**

**Coverage**

- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — two new assertions + comment-strip parser hardening

**Workflows**

- `.github/workflows/apply-web-platform-infra.yml` — delete `warm_standby` (`:864-1113`), `web_2_recreate` (`:1134-1614`), comment block (`:1114-1133`); enum (`:99-108`); HALT text (`:462-475`)
- `.github/workflows/scheduled-inngest-health.yml` — `:837`, `:838`
- `.github/workflows/infra-validation.yml` — deregister `deploy-status-fanout-verify.test.sh` (`:576`) and `lb-weight-gate.test.sh` (`:585`)

**Gates / filters / fixtures**

- `tests/scripts/lib/destroy-guard-filter-web-platform.jq` — remove 3 `web2_*` clauses + rationale; fix `:331`. **Do not touch `web2_retire_allow`.**
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — remove `_run_web2_gate` + T20-T28; retarget per AC4
- `tests/scripts/lib/stock-preflight-gate.sh` — delete tine + setter; rewrite the `#6463` tine web-1-specific; fix stale refs
- `tests/scripts/test-stock-preflight-gate.sh` — rewrite T2; delete T10b/T13b; **replace** T10c with a ≥1-remediation-line assertion

**Parity guards**

- `plugins/soleur/test/stock-preflight-coverage.test.ts`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`
- `apps/web-platform/infra/web-hosts-fanout-parity.test.sh`

**Registers**

- `knowledge-base/engineering/architecture/decisions/ADR-082-fresh-web2-boot-observability.md` — supersede
- `knowledge-base/engineering/architecture/decisions/ADR-114-one-tunnel-many-connectors-ingress-must-be-origin-relative.md` — `:365-373`
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — §(c)
- `apps/web-platform/infra/sentry/issue-alerts.tf` — `:1524-1542` **comment only**
- `apps/web-platform/infra/nic-wait-gate.test.sh` — comments at `:369-372`, `:404-406`
- `knowledge-base/engineering/architecture/diagrams/model.c4` — conditional

**Deleted**

- `tests/scripts/lib/web2-recreate-gate.sh`
- `tests/scripts/fixtures/tfplan-web2-recreate-*.json` (8)
- `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` + `apps/web-platform/infra/deploy-status-fanout-verify.test.sh`
- `apps/web-platform/infra/lb-weight-gate.sh` + `lb-weight-gate.test.sh`
- `scripts/followthroughs/warm-standby-verify-dedup-6030.sh`
- `scripts/followthroughs/web2-tunnel-depool-6425.sh`

---

## Acceptance Criteria

Trimmed from v1's 25 to 14. Each names a way the diff can be *silently* wrong; criteria that merely
restated phase instructions were cut per the deepen review.

### Pre-merge (PR)

- [ ] **AC1 — New coverage is real, not vacuous.** Temporarily duplicating a `host_script_files`
      entry makes assertion B fail; temporarily adding a `RUN` that writes into
      `/opt/soleur/host-scripts/` makes assertion A fail. Evidence in the PR body. Neither temporary
      change is committed.
- [ ] **AC2 — Verifier logic byte-unchanged.** `git diff origin/main -- '*coherence-preflight.sh' -M`
      shows a rename whose only content changes are identifier/comment renames; the digest gate, WANT
      gate, `GOT` pipeline and `GOT != WANT` comparison are textually identical modulo names. All six
      test cases pass, including T3/T4 — proving the pinned-digest `die` branch stays reachable.
- [ ] **AC3 — Residual sweep is zero on live surfaces.**
      `git grep -nE 'warm.standby|warm_standby|WARM_STANDBY|web-2-recreate|web_2_recreate|WEB2_RECREATE'`
      returns no hits under `.github/workflows/`, `tests/`, `scripts/`, `plugins/soleur/test/`,
      `apps/web-platform/infra/` **except** `web2_retire_allow` / `retire_firewall_attachment_deletes`.
      **Excluded:** `knowledge-base/project/{plans,specs,brainstorms}/**` and `**/archive/**` —
      point-in-time records that must retain the old names, including this plan and its `tasks.md`.
- [ ] **AC4 — Mechanism coverage does not regress.** For fixtures 4, 6 and 8, name the surviving
      counter test that still exercises non-placement-update detection, `forget`-as-destroy, and
      `IN()` exact-equality vs substring — or retain the fixture retargeted.
- [ ] **AC5 — No vacuous green.** The web-2 `describe` blocks in `terraform-target-parity.test.ts`
      are **deleted**, not left passing on an empty `extractJobBlock`. Verified by grepping for
      `WARM_STANDBY_TARGETS` / `WEB2_RECREATE_TARGETS` → zero hits.
- [ ] **AC6 — Sentinels changed deliberately.** `MIN_APPLY_TARGET_OPTIONS` 9→7, `MIN_GATED_TARGETS`
      5→4 and the `web-1-swap` count 5→3 each carry an adjacent `# reason:` comment; the pre-existing
      stale header at `web-1-swap-concurrency-parity.test.sh:30` (says 4) is corrected to 3 in the
      same edit.
- [ ] **AC7 — No orphaned targets.** `hcloud_network.private` and `hcloud_network_subnet.private`
      were targeted only by the deleted `warm_standby`. Confirm each is still reachable by a surviving
      apply path or is in `OPERATOR_APPLIED_EXCLUSIONS` (both are, at
      `terraform-target-parity.test.ts:481`).
- [ ] **AC8 — Every deleted runbook line has a stated replacement, and the replacements are
      executable.** The PR body carries a deleted-line → replacement table. The HALT chain is a
      complete copy-pasteable command sequence (not "run the preflight"). The `#6463` tine is
      web-1-specific and does not advise a location change as a stock workaround. The
      `stock-preflight-gate.sh` row states plainly that the free-repair path is **gone**.
- [ ] **AC9 — Sentry alert survives.** `sentry_issue_alert.web_terminal_boot_fatal` still exists with
      its four `stage` filters and `frequency = 24` unchanged; `git diff` on the resource body is
      comment-only. This is the detection arm for the one failure mode this PR cannot prevent.
- [ ] **AC10 — lb-weight-gate fully removed.** Script, test and `infra-validation.yml:585`
      registration all gone; ADR-068 §(c) records it. `grep -c A_web2_not_in_roster` → 0.
- [ ] **AC11 — Merge apply is a no-op.** The merge-triggered `apply-web-platform-infra.yml` run shows
      **0 to add, 0 to change, 0 to destroy**. A red SSH leg with a 0/0/0 plan is pre-existing bridge
      drift, not a regression (§ Network-Outage Deep-Dive).
- [ ] **AC12 — Suite green.** `bash scripts/test-all.sh` passes; `actionlint` clean on both edited
      workflows; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean. **`terraform-target-parity.test.ts:1252`
      no longer references a renamed-away path** — the atomic-rename check.

### Post-merge (automated in `/ship`)

- [ ] **AC13 — Close #6425** with a comment recording that the #6538 retire discharges it by
      construction and its follow-through script was deleted here. **Automation: `gh` CLI.**
- [ ] **AC14 — #6712 and #6730 updated.** Comment on **#6712** (which stays **OPEN**) recording the
      two-invariant split, the host-agnostic verifier, the documented chain, and that closure needs
      #6730. Comment on **#6730** recording the retention rule and the preserved design records.
      **Automation: `gh` CLI.**

**No human-only steps.** Every post-merge item is `gh` CLI-automatable inside `/ship`.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (deepened — three review agents, all findings folded)
**Assessment:** Infrastructure/CI change on the sole prod web host's safety surface. No product
surface, UI, schema, regulated-data surface or vendor spend change. The `single-user incident`
threshold reflects the blast radius of a doomed web-1 birth, not anything this PR introduces. The
deepen pass materially reduced risk by removing v1's additive half, which was both tautological and
capable of poisoning `:latest`. Residual risks: (i) parity tests going vacuously green — AC5;
(ii) over-deletion of host-generic artifacts — reconciliation rows 7/9, AC9; (iii) the rename
breaking references mid-branch — Phase 2.8 atomicity, AC12.

**Product:** not relevant. No path in Files to Create/Edit matches any UI-surface term or glob.
Product/UX Gate: **NONE**.

**Legal / Finance / Marketing / Sales / Support / Operations:** not relevant.

### GDPR / Compliance Gate

**Not invoked.** The canonical regulated-data regex does not match. None of the four expansion
triggers fire: no LLM/external-API processing of session data; the threshold here is availability,
not data exposure; no new cron/workflow reads `learnings/` or `specs/`; no new distribution surface.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The rename breaks CI mid-branch.** `git mv` alone leaves `apply-web-platform-infra.yml:1372` and `terraform-target-parity.test.ts:1252` pointing at a vanished path. | Phase 2.8 makes the rename atomic with (or sequenced after) the deletions that remove both references. AC12 checks the parity test explicitly. |
| **Parity tests pass vacuously** after job deletion (`extractJobBlock` → `""`, so `.not.toContain` succeeds on nothing). | AC5 requires deleting the `describe` blocks and greps for the constant names. Green-after-partial-deletion is explicitly not accepted as evidence. |
| **Over-deletion of host-generic artifacts.** The Sentry alert and ADR-114 hazard #5 read as web-2 surface but protect web-1. | Reconciliation rows 7/9; AC9 pins the Sentry resource body to comment-only changes. |
| **`web2_retire_allow` cross-contamination** — opposite data-volume contract; the filter warns at `:113-133`. | Named do-not-touch in Phase 2.4; excluded from AC3's sweep. |
| **The parser hazard in the baked-set test.** A future comment containing a quoted filename silently injects a phantom entry, yielding a wrong set with no diagnostic. | Phase 1.2 strips `^\s*#` before matching and adds a quoted-comment fixture. |
| **The merge run goes red on the SSH-bridged apply leg** for reasons unrelated to this diff. | § Network-Outage Deep-Dive documents all four layers as unchanged; AC11 scopes the criterion to the plan being 0/0/0 and names bridge drift as the correct diagnosis (`hr-ssh-diagnosis-verify-firewall`). |
| **Fixture deletion silently drops non-obvious protections** (`forget`-as-destroy; `IN()` exact-equality). | AC4 requires naming a surviving test per mechanism, or retargeting. |
| **Deleting T10c removes the "don't strip every tine" invariant.** This PR is legitimately the fix T10c guards against, but the invariant should outlive it. | Phase 3.2 **replaces** T10c with a ≥1-remediation-line assertion rather than deleting it outright. |
| **Thirteen premises were already falsified.** | Every number here is re-derived from the worktree with `file:line` anchors. `/work` must re-verify anchors — Phase 2 shifts ~730 lines. |
| **#6712 stays open while its hazard is live.** A reader may assume the sweep closed it. | Frontmatter says `closes: [6575]`, `refs: [6712]`; the two-invariant table, the ADR, AC14 and `decision-challenges.md` all state it explicitly. |

---

## scoped-apply-gate re-assessment

**Explicit finding: `scoped-apply-gate.sh` does not exist, and this deletion does not relieve the
pressure attributed to it.**

`grep -rn "scoped.apply.gate\|scoped_apply_gate" . --exclude-dir=.git -i` → **zero hits**. The name
has no referent. The nearest real artifact is **#6574**, filed as Deferred in the retire plan:
*"the push-apply `-target` allow-list is a fiction (firewall attachment drags the fleet into every
merge's graph). Standing hazard."*

#6574's hazard is `-target` **transitivity on the routine merge path** — the mechanism
`ADR-114:377-380` and `nic-wait-gate.test.sh:381-386` both document, whereby `hcloud_server.web` is
reachable via `cloudflare_record.app` and `hcloud_firewall_attachment.web` regardless of what the
allow-list names. That is a property of Terraform's graph, not of how many dispatch jobs exist.
Removing two `workflow_dispatch` jobs reduces **job count and enum width**; it changes **nothing**
about what the `on: push` apply drags in.

**Recommendation:** #6574 remains warranted at unchanged priority. Do not close it, down-scope it, or
treat this sweep as partial payment. **This PR does not do that refactor.**

---

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **A bake-time coherence gate in `reusable-release.yml`** (this plan's own v1) | Three independent objections, all verified. (i) **Near-tautological** — at `docker_build` the image and tree share a commit, so the only reachable failure is list drift, already caught earlier and with a better diagnostic by `cloud-init-user-data-size.test.ts:486-510`. (ii) **Poisons `:latest`** — `reusable-release.yml:596-599` pushes `:v<next>`, `:<sha>` and `:latest` in one step, so a gate failure leaves the mutable default pointing at a known-incoherent image, manufacturing the exact single-user incident it was meant to prevent. (iii) Its enabling premise was false (row 12). Fixing (ii) properly means restructuring to `push-by-digest` + post-verify `crane tag` — a release-pipeline redesign well outside this PR. |
| **Generalize the verifier to accept a mutable tag** (framing option (a)) | Rejected by PR #6725's recorded decision (5 of 7 reviewers). Moves the TOCTOU closure from "structurally cannot re-resolve" to "the caller faithfully consumes the emitted value" and makes the digest `die` branch dead code on the mutable arm — a weaker guarantee sold as a generalization. |
| **Pin a digest on create paths "the way the recreate job did"** (framing option (b)) | Its mechanism polls the **running** web-1's `/health .version` via `resolve-web1-known-good-tag.sh`. On a fresh create there is no running web-1; `RUNNING_VERSION` is empty and the script exits 1. Structurally unavailable on the path that needs it. |
| **Terraform `lifecycle.precondition` requiring a pinned `var.image_name`** | Preconditions evaluate during plan on **every** apply, including no-op refreshes. The routine merge apply passes `:latest`, so this breaks every merge. Terraform also cannot read inside an image, so it cannot express coherence — only pinning. |
| **Delete the verifier outright** (its callers all vanish) | Defensible, and the deepen review argued for it. Rejected because the retention rule's condition is met: it is named as a step in the Phase 3.1 HALT chain, which an operator can execute today. Deleting it would leave #6730 to re-derive a byte-exact match to `cloud-init.yml:558` — the highest-risk part to get subtly wrong. |
| **Build the web-1 birth path here** | #6730 explicitly owns it. Folding a prod-host-birth capability into a ~730-line deletion PR inverts the risk budget exactly as #6575's own sequencing rationale warns. |
| **Promote `host_script_files` to a shared `host-scripts.json`** consumed by `server.tf` via `jsondecode()` and by scripts via `jq` | Genuinely better than any parsing approach — makes list drift structurally impossible rather than test-detected. But it edits the Terraform locals feeding `user_data` on the sole web host, inside a large deletion PR. **Recommended as a follow-up**; filed in § Deferrals. |

---

## Deferrals

| Deferred | Why | Re-evaluation trigger | Tracker |
|---|---|---|---|
| **#6712's substance** — cross-commit skew from mutable `:latest` | Not closable without digest-pinning `var.image_name` at create time, which requires a birth path that does not exist. | #6730 lands the birth path → compose resolve → verify → `-var image_name=<pinned>`. | **#6712** (stays OPEN) + **#6730** |
| The tag→digest **resolver** (`resolve-image-digest.sh`) | The Phase 3.1 chain uses `crane digest` inline; a script is warranted only once a CI caller exists. Design record preserved in the ADR and in `2026-07-19-fix-warm-standby-web1-birth-halt-plan.md:110-149`. | Same as above. | **#6730** |
| `host-scripts.json` as the shared list source | Strictly better than parsing HCL, but touches `user_data` inputs on the sole web host — wrong PR. | File as a follow-up issue at ship time. | **new issue (file at ship)** |
| `-target` transitivity | Orthogonal; see § scoped-apply-gate re-assessment. | Unchanged by this PR. | **#6574** (unchanged priority) |

---

## Sharp Edges

- **Thirteen premises were falsified**, four of them in this plan's own first draft. Treat every
  inherited number as suspect and re-derive from the worktree. Note especially that `test-all.sh`'s
  `run_suite` is at **`:218`** (v1 said `:233`) and `resolve-web1-known-good-tag.sh` had **two**
  callers (v1 said one).
- **A safety-shaped mechanism that cannot fire is not a safety mechanism.** v1's gate would have
  printed `COHERENT` forever for structural reasons. Before shipping any guard, ask what input makes
  it go red — and if the honest answer is "none," it is decoration with a failure mode.
- **Line anchors will drift.** Phase 2 removes ~730 lines from `apply-web-platform-infra.yml`; every
  later anchor shifts. Re-grep by content anchor (`cq-cite-content-anchor-not-line-number`).
- **A green suite is not evidence of complete deletion.** `extractJobBlock` returns `""` for a missing
  job, so negative assertions pass vacuously. Delete the tests; do not observe them pass.
- **`web2_retire_allow` is a different surface with the opposite data-volume contract** (`:113-133`).
  Do not sweep it.
- **The Sentry alert and ADR-114 hazard #5 read as web-2 surface but protect web-1.** Deleting either
  removes live coverage for the only web host — and the Sentry alert is the *only* detector for the
  failure mode this PR cannot prevent.
- **A runbook line telling an operator to "run the preflight" is unactionable by construction** — the
  preflight refuses the mutable `:latest` they hold. Runbook additions must carry the full command
  chain, not an instruction.
</content>
