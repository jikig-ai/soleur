---
title: "fix(infra): move bake/apply coherence left to image-build time, then sweep the dead web-2 dispatch surface"
date: 2026-07-20
type: fix
lane: cross-domain
closes: [6712, 6575]
refs: [6730, 6538, 6725, 6574, 6425, 6040, 6416, 6718]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

> **Phase 2.8 IaC routing — reviewed, ack recorded above.** This plan introduces **no** new
> infrastructure: no server, service, cron, vendor account, DNS record, cert, secret, firewall rule
> or webhook. Its only `.tf` edit is a **comment** (`issue-alerts.tf:1524-1542`). Every occurrence of
> "operator-local apply" / "operator-driven" below is a **quotation of the repo's pre-existing state**
> — the `host_creates` HALT text and #6730's own framing — reproduced so the plan can describe what
> it must *not* silently delete. Closing that operator-local gap is **#6730's** scope and is
> explicitly a non-goal here (see § Alternative Approaches). The `## Infrastructure (IaC)` section
> below records the no-new-infrastructure finding and the merge-apply no-op expectation.

# fix(infra): move bake/apply coherence left to image-build time, then sweep the dead web-2 dispatch surface

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec directory exists for this branch.

## Overview

Two issues that must land together because they contend over the same 104-line file.

`apps/web-platform/infra/scripts/web2-recreate-preflight.sh` is the repo's **only** bake/apply
coherence guard. Verified: exactly one executable call site,
`.github/workflows/apply-web-platform-infra.yml:1372`, inside the `web_2_recreate` dispatch job.

- **#6575** lists that script, its test, its gate lib and its 8 fixtures under "Gates / scripts /
  fixtures" to be deleted as dead web-2 surface.
- **#6712** says that same script is the only artifact that would stand between a fresh web-1
  create/`-replace` and a doomed `runcmd` — and that it does not cover web-1 today.

A naive #6575 sweep therefore takes coherence coverage from one call site to **zero**, which is
precisely the gap #6712 exists to close.

**But the research falsified the framing both issues share.** Three findings reshape the plan:

1. **There is no web-1 create/replace path to generalize the preflight *onto*.** Every automated
   route to `hcloud_server.web` terminates in the `host_creates > 0` HALT
   (`apply-web-platform-infra.yml:462-475`). **#6730** owns building that path and is explicit that
   it does: *"An automated, image-pinned, attachment-complete path that can create
   `hcloud_server.web["web-N"]` from empty state."* So "add a call site on the web-1 create path"
   is not available to this PR.

2. **The one existing call site is already unreachable.** `web_2_recreate`'s gate requires
   `web2_server_replaced == 1`, unsatisfiable with the instance absent from state after the
   2026-07-17 retire. Coverage today is nominally 1 and effectively **0**.

3. **The correct shape was already decided and recorded.** PR #6725's plan
   (`2026-07-19-fix-warm-standby-web1-birth-halt-plan.md:110-149`) carries an operator decision,
   backed by five of seven reviewers, that the verifier must stay a **pure verifier** and a
   **separate resolver** be added, never merged into one script. Quoted in full in
   [Research Reconciliation](#research-reconciliation--stated-premises-vs-codebase) row 8.

**The resolution: move the check left.** Instead of verifying coherence *immediately before one
destructive dispatch*, verify it *at the moment every image is produced*. A new gate in
`reusable-release.yml`, running after `docker_build` and before `cosign sign`, proves the image's
baked `/opt/soleur/host-scripts/` hashes to the value Terraform will apply from the same commit.
Every published image becomes coherence-verified against its own tree, so any future birth path
(#6730) that pins a released digest inherits coherence **by construction** rather than by
remembering to run a preflight.

Coverage accounting, which the non-negotiable requires be strictly greater:

| | Before | After |
|---|---|---|
| Executable coherence call sites | 1 (`web_2_recreate`, unreachable — gate unsatisfiable) | **1** (`reusable-release.yml`, fires on **every** image build) |
| Images covered | only the one digest a dispatch happened to pin | **every image ever published** |
| Verifier available to #6730 | yes, web-2-named, one dead caller | yes, host-agnostic, one live caller |
| Terraform-side WANT pinned to a test | no | **yes** (new equality test vs `terraform console`) |

Then the web-2 dispatch surface is swept around the relocated guard: the `warm_standby` job, the
481-line `web_2_recreate` job, their gates, fixtures, orphaned scripts, falsified registers and
every parity sentinel they pin.

**Non-goal:** this PR does not build the web-1 birth path. #6730 owns that and stays open. This PR
hands it a host-agnostic, live-tested verifier and a registry of images already proven coherent.

---

## Research Reconciliation — stated premises vs codebase

Every premise supplied in the task framing was re-verified. **Nine were wrong.** Several came from
#6575's body and propagated into the framing verbatim.

| # | Stated premise | Reality (verified) | Plan response |
|---|---|---|---|
| 1 | `warm_standby`: "**4 of its 6** targets are web-2 addresses" | **3 of 6** (`hcloud_server_network.web["web-2"]`, `hcloud_volume.workspaces["web-2"]`, `hcloud_volume_attachment.workspaces["web-2"]` at `:973-975`). The other 3 are `hcloud_network.private`, `hcloud_network_subnet.private`, `hcloud_server_network.web["web-1"]`. The workflow's own enum description already says "3 of its 6". #6575's body says 4 while listing 3 — internally inconsistent. | Use **3 of 6**. Deleting the job also removes 3 non-web-2 targets, so coverage of `hcloud_network.private` / `hcloud_network_subnet.private` must be re-checked (AC12). |
| 2 | "The `apply_target` enum drops **9 → 6**" | 9 options today; this sweep removes exactly **2** (`warm-standby`, `web-2-recreate`) → **7**. Neither #6575 nor the retire plan (`2026-07-16-chore-retire-web-2-fsn1-orphan-plan.md:594`) names a third option to remove. | **7**, not 6. `MIN_APPLY_TARGET_OPTIONS` → 7 with the 7 names enumerated in its comment. Do **not** invent a third deletion to make the arithmetic match a wrong number. |
| 3 | `stock-preflight-coverage.test.ts` sentinel `MIN_APPLY_TARGET_OPTIONS = **8**` | Actual value is **9** (`:105-110`). | Edit from 9 → 7. |
| 4 | `web-1-swap-concurrency-parity.test.sh` asserts "exactly **4** `group: web-1-swap` occurrences" | Asserts **5** (`:126-132`, `-eq 5`). The file's own header comment at `:30` says 4 and is **already stale**. | Change `-eq 5` → `-eq 3` **and** fix the pre-existing stale header (AC9). Do not propagate the 4. |
| 5 | `web_2_recreate` is "~490 lines" | **481** (`:1134-1614`). | Cosmetic; use 481. |
| 6 | Deleting relieves the pressure behind "a generic `scoped-apply-gate.sh` refactor" | **`scoped-apply-gate` has zero hits repo-wide** — no issue, plan, ADR, code or comment. The real tracker is **#6574**: *"the push-apply `-target` allow-list is a fiction (firewall attachment drags the fleet into every merge's graph)."* | See [§ scoped-apply-gate re-assessment](#scoped-apply-gate-re-assessment). The deletion does **not** relieve #6574. |
| 7 | Delete `apps/web-platform/infra/sentry/issue-alerts.tf`'s web-2 dead-boot alert | The alert `sentry_issue_alert.web_terminal_boot_fatal` (`:1543-1605`) is **host-generic** — it filters on `stage`, never on host. Only its **rationale comment** (`:1524-1542`) is web-2-specific. Deleting the resource removes the sole no-SSH boot page for **web-1 and every future host**. | **Comment rewrite only. Do NOT delete the resource.** (AC16) |
| 8 | Pick (a) a preflight that resolves `:latest`, or (b) make create paths pin a digest "the way the recreate job did" | **(a) is explicitly rejected** by the recorded design decision. **(b)'s named mechanism does not work for a fresh create**: the recreate job pins by polling the *running* web-1's `/health .version` (`resolve-web1-known-good-tag.sh`), which on a fresh create is empty → the script's case (b) exits 1. | Neither as stated. See [§ Architecture Decision](#architecture-decision-adrc4). |
| 9 | `lb-weight-gate.sh:107` — "not CI-wired today so not a merge blocker, but fix it" | The **script** is not CI-wired; its **test** is (`infra-validation.yml:585`). The script is dead code with a live test — its only intended caller (a Doppler-sourcing cutover orchestrator) was never built. Deleting only line 107 leaves a gate that **passes on a single-host roster**, green-lighting a weight flip toward a host that does not exist. | Delete script **and** test; record in ADR-068 §(c). (AC17) |

Premises that **held** and are not re-litigated:

- web-2 retire merged/closed 2026-07-17; `variables.tf:101` carries the RETIRED comment; web-2 absent from `web_hosts`. #6575's sequencing gate is satisfied.
- `cloud-init.yml:559` `[ "$GOT" = "$HOST_SCRIPTS_HASH" ] || exit 1` runs under the `set -e` armed at `:468`. The only earlier `set +e` (`:480`) is confined to a subshell closing at `:515`, 44 lines earlier; the next `set +e` is at `:568`, after. **Confirmed.**
- `var.image_name` defaults to mutable `ghcr.io/jikig-ai/soleur-web-platform:latest` (`variables.tf:67-71`).
- `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }` (`server.tf:288-290`).
- `hcloud_server.web` appears in **no** `-target=` in the `apply` job (lines 168-863). The only `-target` naming it is `:1390`, `["web-2"]`, inside `web_2_recreate`.
- **Important nuance already recorded in the repo, which the framing omits:** `nic-wait-gate.test.sh:381-386` records that the "web-1 is in no `-target=`, therefore a routine apply cannot create it" **inference is invalid** — `-target` is transitive at the resource level, so `hcloud_server.web` **is** reachable via `cloudflare_record.app` and `hcloud_firewall_attachment.web`. The real guarantor is the `host_creates > 0` HALT. The plan preserves the *asserts*, and preserves this correction; it must not restate the invalid inference.

**Premise Validation note.** #6712 and #6575 are both OPEN, milestone *Post-MVP / Later*. #6730 is OPEN and explicitly names #6712 (*"image-tag mutability; its resolver-extraction design record is preserved in PR #6725's plan"*). #6425 is OPEN with an orphaned follow-through script. #6040 is CLOSED with a sweeper-dead script still on disk. No cited artifact was missing; nine were mis-stated.

---

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` queried against every planned
file path (`apply-web-platform-infra.yml`, `web2-recreate-preflight`, `stock-preflight-gate`,
`destroy-guard-filter-web-platform`, `terraform-target-parity`, `lb-weight-gate`,
`reusable-release.yml`) returned zero matches.

---

## User-Brand Impact

**If this lands broken, the user experiences:** `app.soleur.ai` returns nothing — no page, no error
page, no DNS failover. The failure mode is specific and unrecoverable-in-place: a web-1 born on an
image whose baked host-scripts disagree with the applied `host_scripts_content_hash` aborts its
entire cloud-init `runcmd` at `stage=verify` — no cloudflared connector, no deploy webhook, no
monitors, no egress firewall. `runcmd` is once-per-instance, so **no reboot repairs it**, and there
is no failover partner (web-2 retired; #6459 unbuilt).

**If this leaks, the user's data is exposed via:** the transient window in that same failure — a
host that reaches the network before its egress firewall and AppArmor/seccomp profiles are applied
is briefly unconfined. The `#6416` private-NIC class is the precedent. No new secret material is
introduced by this PR; `GHCR_TOKEN` is already present on the release path and is passed via
`--password-stdin` (never argv).

**Brand-survival threshold:** `single-user incident`

Sole operator, sole web host, hard-pinned singleton A record. One bad birth is a total outage with
no automated recovery. CPO sign-off is required at plan time; `user-impact-reviewer` is invoked at
review time.

**Why the threshold does not permit a "sweep now, guard later" split:** the deletion half of this PR
removes the only artifact that could guard a birth. Landing it without the relocation leaves a
window — bounded only by when #6730 ships — in which nothing in the repo verifies coherence. That
window is exactly the single-user incident.

---

## Architecture Decision (ADR/C4)

This PR relocates a safety invariant across a lifecycle boundary — from **dispatch-time**
(verify the one image a destructive apply is about to use) to **bake-time** (verify every image at
publication). That is an architectural decision and is a deliverable of this plan, not a follow-up.

### ADR

**New ADR — "Bake-time host-scripts coherence: verify every image at publication, not the image a
dispatch happens to pin."** Ordinal is **provisional**; `/ship`'s ADR-Ordinal Collision Gate
re-derives the next free ordinal against `origin/main` before merge. When renumbering, sweep
`grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-one-shot-6712-6575-*/` in the same
edit so this plan, `tasks.md` and any AC naming the ordinal move together.

Decision content:

- **Verifier stays pure.** `host-scripts-coherence-preflight.sh` (renamed from
  `web2-recreate-preflight.sh`, logic byte-unchanged) accepts **only** a pinned `repo@sha256` ref
  and `die`s otherwise. Its digest-`die` branch must remain reachable.
- **Resolution is a separate concern**, deferred to whichever caller needs it. The release path
  needs no resolver: `steps.docker_build.outputs.digest` is already in hand.
- **Alternatives considered:** (a) generalize the verifier to accept a mutable tag — rejected,
  quoted rationale below; (b) a Terraform `lifecycle.precondition` requiring a pinned
  `var.image_name` — rejected, preconditions evaluate on **every** plan including no-op refreshes,
  so it would break every routine merge apply (which passes `:latest`), and Terraform cannot read
  inside an image to compute coherence anyway; (c) keep the verifier with zero call sites until
  #6730 — rejected, violates the coverage non-negotiable.

Rationale for (a)'s rejection, quoted verbatim from
`knowledge-base/project/plans/2026-07-19-fix-warm-standby-web1-birth-halt-plan.md:110-149`:

> The correct shape is **two scripts, not one**. `web2-recreate-preflight.sh` is a *pure verifier*
> whose header states the invariant — *"resolved ONCE upstream; AC3b TOCTOU — this script does NOT
> re-resolve a tag."* Generalizing it to accept a mutable ref would move the TOCTOU closure from
> "structurally cannot re-resolve" to "the caller faithfully consumes the emitted value", and make
> its digest `die` branch dead code on the mutable arm — a weaker guarantee sold as a
> generalization. Keep the verifier byte-unchanged; add a separate resolver; callers compose
> resolve → verify → `plan -var image_name=<pinned>`, and an AC must pin that the *same* variable
> feeds both the preflight and `-var image_name` (the composition is where the closure now lives).

### ADR-082 supersession

`ADR-082-fresh-web2-boot-observability.md` is **Status: Adopting** and its entire subject is web-2.
Supersede it properly — do not delete. Follow the `ADR-008` convention (verified as the repo's
pattern): YAML frontmatter (`status: superseded-in-part`, `superseded_by: [ADR-<new>]`) **plus** an
inline blockquote banner **plus** an explicit partition of what remains in force. Partition:

- **Remains in force (host-generic):** Item 3 (fresh-host post-container egress-enforcement probe,
  shipped), Item 4 (image digest pin + signature verification — now discharged at bake time by this
  PR's gate plus the existing `cosign sign`).
- **Dies with the retire:** Item 1 (per-host uptime absence detector), Item 2 (A-record drain on
  boot failure), and Item 5's web-2 clauses.
- **Falsified sentence at `:52-53`** — *"the SOLE page for a dead web-2 warm standby"* — is the same
  claim encoded in the Sentry alert comment; both must be rewritten together and consistently.
- **`:45-46`** claims Item 5 is "Half-met at ship (web-2 only)". Post-retire it is 0%-met, not
  half-met. State that plainly.

### ADR-114 amendment

`ADR-114-…:365-373` hazard #5 cites the preflight's web-2-only scope. The **hazard survives** the
retire and applies to every host; only its named mitigation moves. Rewrite `:369-372` to name the
bake-time gate. **Preserve `:375-380` verbatim** — the paragraph refuting the "web-1 appears in no
`-target=`" inference is load-bearing and independently correct.

### C4 views

Read all three model files — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — in full, not by keyword grep.

Enumeration performed for this change (the completeness mandate; a bare "None" is a reject condition):

- **External human actors:** none added or removed. No new correspondent, reviewer or recipient.
- **External systems / vendors:** none added. GHCR (already modeled — the release path already
  pushes, signs and mirrors to it) is the only registry touched; the new gate reads from the image
  the existing `docker_build` step just pushed. No new vendor edge.
- **Containers / data stores:** none added. `warm_standby` / `web_2_recreate` are workflow jobs, not
  C4 containers.
- **Actor↔surface access relationships:** none change. The dispatch menu loses two options; the menu
  is not a modeled relationship.
- **Element descriptions falsified:** `model.c4` carries one `warm-standby` hit (confirmed by the
  repo-wide grep). Read it and, if it describes a warm-standby host or edge, correct it — the
  retire falsified it independently of this PR.

If and only if that one `model.c4` hit describes a live element, edit it, add any needed
`view … include` line in `views.c4` so it renders, and run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view include` referencing
an undefined element fails there, not at `tsc`).

---

## Observability

```yaml
liveness_signal:
  what: the bake-time coherence gate's own PASS line in the release run
        ("host-scripts-coherence: COHERENT — pinned <digest> baked hash == applied <hash>")
  cadence: every push to main matching reusable-release.yml's paths filter (every image build)
  alert_target: the release workflow fails the job; GitHub Actions failure notification on main
  configured_in: .github/workflows/reusable-release.yml (new step, after docker_build,
                 before "Install cosign")
error_reporting:
  destination: GitHub Actions annotation (::error::) + non-zero job exit, failing the release
  fail_loud: true — the gate exits non-zero and blocks cosign signing and the zot mirror,
             so an incoherent image is never signed and never mirrored
failure_modes:
  - mode: baked host-scripts drift from the repo tree (a Dockerfile COPY change without the
          matching server.tf host_script_files change, or a build step mutating the directory)
    detection: the gate's COHERENCE MISMATCH die, naming both hashes
    alert_route: release job fails on main; image is pushed but unsigned and unmirrored
  - mode: an extra file lands in /opt/soleur/host-scripts/ in the image but is absent from
          local.host_script_files (the `find . -type f` vs enumerated-list asymmetry)
    detection: same gate — GOT includes the extra file, WANT does not, hashes diverge
    alert_route: same
  - mode: the bash WANT recompute drifts from terraform's local.host_scripts_content_hash
    detection: new equality test asserting host-scripts-want-hash.sh output ==
               `terraform console local.host_scripts_content_hash`, wired in infra-validation.yml
               (which already runs terraform console at :161/:178/:316)
    alert_route: required PR check fails
  - mode: silent vacuity — a parity assertion goes green because its subject job vanished
    detection: extractJobBlock returns "" for a missing job, so ~half the web-2 asserts in
               terraform-target-parity.test.ts pass on nothing. Guarded by DELETING the tests
               rather than observing them pass (AC11), plus the retained non-vacuity controls.
    alert_route: required PR check (plugins/soleur bun suite)
logs:
  where: GitHub Actions run logs for reusable-release.yml; the gate echoes both hashes on failure
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: >-
    gh run list --workflow=web-platform-release.yml --limit 1 --json databaseId
    -q '.[0].databaseId' | xargs -I{} gh run view {} --log
    | grep -E 'host-scripts-coherence: (COHERENT|.*MISMATCH)'
  expected_output: >-
    one line per release run beginning "host-scripts-coherence: COHERENT — pinned sha256:…"
```

No `ssh` appears in any command above. No soak/time-gated close criterion is declared, so
§2.9.1 follow-through enrollment does not fire.

---

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

**Finding: this plan introduces no new infrastructure.** No server, systemd service, cron job,
vendor account, DNS record, TLS cert, secret, firewall rule or monitoring webhook is created,
moved or re-tiered. `terraform-architect` routing is therefore not triggered.

### Terraform changes

Deletions and comment corrections only. No new resource, no new provider, no new variable, no new
`TF_VAR_*`, no minted credential.

- `apps/web-platform/infra/sentry/issue-alerts.tf` — **comment rewrite only** at `:1524-1542`. The
  `sentry_issue_alert.web_terminal_boot_fatal` resource is host-generic and **must survive**.
  `frequency = 24` is documented as dedup-unique; do not renumber.
- `apps/web-platform/infra/lb-weight-gate.sh` + `lb-weight-gate.test.sh` — deleted (see AC17). Not
  a Terraform resource; listed here because it is an infra gate.

### Apply path

**No apply is required by this PR.** The Sentry comment edit is a comment inside a `.tf` file, which
`apply-sentry-infra.yml` will re-plan as a no-op. The deletions are workflow/test/script files.

Note the merge-trigger interaction: `apply-web-platform-infra.yml` fires on
`apps/web-platform/infra/**` **and** on `tests/scripts/lib/destroy-guard-filter-web-platform.jq`
(defense-in-depth path added by #4419). This PR touches both, so the auto-apply **will** run on
merge. Expected plan: **zero changes**. AC19 requires confirming the post-merge apply is a no-op.

### Distinctness / drift safeguards

No `dev`/`prd` divergence. No state-stored secret changes. `hcloud_server.web`'s
`lifecycle.ignore_changes = [user_data, ssh_keys, image, placement_group_id]` is untouched and must
remain untouched — `nic-wait-gate.test.sh:420-421` pins it.

### Vendor-tier reality check

No new vendor resource. GHCR is already a private package on the release path; `docker login` with
`--password-stdin` already exists at `apply-web-platform-infra.yml:1343` and the pattern is reused.

### Pre-existing gap this plan deliberately does not close

The `host_creates` HALT currently routes a web-host birth to a locally-run full `terraform apply`
per the `OPERATOR_APPLIED_EXCLUSIONS` contract (ADR-096). That state violates
`hr-fresh-host-provisioning-reachable-from-terraform-apply` and is **already filed as #6730**, which
scopes closing it as *"an automated, image-pinned, attachment-complete path … from empty state."*
This plan neither creates nor widens that gap; it **narrows** it by ensuring every published image is
bake-verified, so #6730's future path can pin a digest that is coherent by construction. Folding
#6730's work in here was considered and rejected (§ Alternative Approaches).

---

## Implementation Phases

Phase order is load-bearing: **the guard is relocated and proven live before anything is deleted.**
At no commit boundary may coherence coverage be zero.

### Phase 0 — Preconditions (verify, do not code)

0.1 Re-read `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` in full. Confirm the
    logic to be preserved byte-for-byte: digest shape gate (`:44-50`), WANT shape gate (`:63-65`),
    the `GOT` pipeline (`:91`) and the comparison (`:100-101`).

0.2 **Feasibility gate for the new call site.** Confirm `reusable-release.yml` has **no**
    `setup-terraform` and **no** `prd_terraform` Doppler token (verified at plan time: it has
    `DOPPLER_TOKEN_PRD`, the prd *root* config, and no terraform at all). This is why WANT cannot
    come from `terraform console` on the release path. If this has changed, prefer
    `terraform console` and drop `host-scripts-want-hash.sh`.

0.3 Confirm `steps.docker_build.outputs.digest` is populated and already consumed
    (`reusable-release.yml:637` sign step, `:700` zot mirror). The new gate reuses the same output.

0.4 Confirm the boot-side and Terraform-side hash constructions agree:
    - Terraform (`server.tf:95-97`): `sha256(join("", sort([filesha256(f) for f in host_script_files])))`
    - Boot (`cloud-init.yml:558`): `find . -type f -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort | tr -d '\n' | sha256sum`

    Both hash each file, sort the **hashes**, concatenate, sha256. Record the confirmation.

0.5 Run the full suite on a clean tree and capture the baseline:
    `bash scripts/test-all.sh` — record pass/fail so post-deletion deltas are attributable.

### Phase 1 — Relocate the guard (additive; nothing deleted yet)

1.1 `git mv apps/web-platform/infra/scripts/web2-recreate-preflight.sh
    apps/web-platform/infra/scripts/host-scripts-coherence-preflight.sh`.
    Rename env seams `WEB2_PREFLIGHT_WANT_HASH` → `HOST_SCRIPTS_WANT_HASH`,
    `WEB2_PREFLIGHT_SEED_DIR` → `HOST_SCRIPTS_SEED_DIR`; `die()` prefix
    `web2-recreate-preflight` → `host-scripts-coherence`; success line likewise. Rewrite the header
    to be host-agnostic and to state the two consumers (bake-time gate today; a future birth path,
    #6730). **Comparison and validation logic byte-unchanged.**

1.2 `git mv tests/scripts/test-web2-recreate-preflight.sh
    tests/scripts/test-host-scripts-coherence-preflight.sh`. All six cases (T1 coherent, T2
    mismatch, T3 bare tag, T4 malformed digest, T5 bad WANT, T6 unset PINNED) are already
    host-agnostic — retarget names only, **retain every case**. Update the `run_suite` line at
    `scripts/test-all.sh:233` (nothing auto-discovers `tests/scripts/`).

1.3 **New** `apps/web-platform/infra/scripts/host-scripts-want-hash.sh`. Parses
    `local.host_script_files` out of `server.tf` (the single source of truth — **parses**, never
    duplicates) and recomputes the Terraform-side hash from the repo files. Emits the 64-hex hash
    or dies. This exists solely so the release path can obtain WANT without terraform.

1.4 **New** `apps/web-platform/infra/host-scripts-want-hash.test.sh`, registered in
    `.github/workflows/infra-validation.yml` beside the existing entries at `:576`/`:579`/`:585`.
    The load-bearing case: **assert the script's output equals
    `terraform console <<<'local.host_scripts_content_hash'`** — this is the drift-proofing that
    makes the bash recompute safe. Also assert it dies on a missing file and on a `server.tf` whose
    list fails to parse (fail-closed, never emits a hash on a partial parse).

1.5 **New step in `.github/workflows/reusable-release.yml`**, inserted **after** `docker_build`
    (`:580-611`) and **before** `Install cosign` (`:619`), guarded by
    `if: steps.docker_build.outcome == 'success'`:

    ```
    WANT=$(bash apps/web-platform/infra/scripts/host-scripts-want-hash.sh)
    PINNED="${IMAGE}@${DIGEST}"     # DIGEST = steps.docker_build.outputs.digest
    HOST_SCRIPTS_WANT_HASH="$WANT" PINNED="$PINNED" \
      bash apps/web-platform/infra/scripts/host-scripts-coherence-preflight.sh
    ```

    Placement is deliberate: failing **before** `cosign sign` means an incoherent image is never
    signed and never mirrored to zot, so `ci-deploy.sh`'s offline `cosign verify` refuses it
    downstream. Gate only on `docker_image != ''` / component `web-platform` so non-web components
    are unaffected.

1.6 Verify the gate fires: construct a deliberate local mismatch (add a stray file to the baked
    dir in a scratch image) and confirm non-zero exit + `COHERENCE MISMATCH`. Do **not** commit the
    scratch artifact.

**Checkpoint: coverage is now 2 call sites (old + new). Only now may deletion begin.**

### Phase 2 — Delete the web-2 dispatch jobs and their gates

2.1 Delete the `warm_standby` job (`apply-web-platform-infra.yml:864-1113`) and the `web_2_recreate`
    job (`:1134-1614`), plus the block comment at `:1114-1133` that introduces the latter.

2.2 Remove `warm-standby` and `web-2-recreate` from the `apply_target` enum options (`:99-108`) and
    rewrite the long enum `description:` so it names the remaining **7**.

2.3 Delete `tests/scripts/lib/web2-recreate-gate.sh`.

2.4 Delete the `web2_allow` (`:107-111`), `web2_out_of_scope_changes` (`:241-246`) and
    `web2_server_replaced` (`:251-256`) clauses from
    `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, with their rationale blocks
    (`:99-106`, `:218-240`, `:247-250`). **Deletion is safe by the filter's own recorded contract**
    at `:237-238`: *"BACKWARD-COMPAT: additive key; no consumer of THIS key exists outside the
    web_2_recreate gate."*
    **Do NOT touch `web2_retire_allow` (`:113-…`) or `retire_firewall_attachment_deletes`** — a
    separate surface with the opposite data-volume contract, explicitly warned against at `:113-133`.
    Fix the orphaned cross-reference to `web2_out_of_scope_changes` in the `host_creates` comment
    (`:331`).

2.5 Delete the 8 `tests/scripts/fixtures/tfplan-web2-recreate-*.json` fixtures and the 9 test cases
    consuming them in `tests/scripts/test-destroy-guard-counter-web-platform.sh` (`:426-439` helper,
    `:443-560` cases T20-T28).

    **Regression-value note:** fixtures 4 (`web1-inplace-nonplacement`), 6 (`volume-forget`) and 8
    (`substring-collision`) encode non-obvious protections — `IN()` exact-equality vs substring, and
    Terraform 1.7+ `forget` being counted as a destroy. Before deleting, confirm each protection is
    still exercised by a **surviving** counter test (the generic `resource_deletes` /
    `nested_deletes` / `host_creates` cases). If any is not, **retarget** that fixture to a
    surviving counter rather than deleting it (AC13). Coverage of the *mechanism* must not regress
    even though its web-2 *subject* is gone.

2.6 Delete `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` and
    `apps/web-platform/infra/deploy-status-fanout-verify.test.sh`, and its registration at
    `infra-validation.yml:576`. Both callers (`:1097`, `:1492`) are being deleted; verified no other
    caller exists. Its `ROSTER_COUNT -ne 2` invariant is falsified by the retire independently.
    **Preserve the design record** in the ADR (mirroring the #6725 precedent) so #6730's birth path
    can re-derive the verify-poll rather than rediscovering the `.tag` last-write-wins trap
    (`resolve-web1-known-good-tag.sh:6-13`) from scratch.

2.7 Decide `resolve-web1-known-good-tag.sh` + its test. Its only caller is the deleted pin step
    (`:1336`). It is 60 lines with 13 test cases encoding the `latest`-wedge and prerelease
    rejections. **Recommendation: keep both**, registered as-is at `infra-validation.yml:579` — it is
    a pure, well-tested resolver #6730 will need for a `-replace` of a *running* host, and unlike
    `lb-weight-gate.sh` its subject (web-1's running version) still exists. Record the decision
    either way; do not leave it unexamined.

### Phase 3 — Update every parity sentinel, each with a stated reason

Every edit below carries a one-line `# reason:` comment in the code. A sentinel lowered without a
stated reason is a defect.

3.1 `plugins/soleur/test/stock-preflight-coverage.test.ts`
    - `MIN_APPLY_TARGET_OPTIONS` **9 → 7**; rewrite the comment's 9-name enumeration to the 7
      survivors. Reason: `warm-standby` and `web-2-recreate` removed with their jobs.
    - `MIN_GATED_TARGETS` **5 → 4**. Reason: `web_2_recreate` was one of five stock-preflight-gated
      jobs (`:1435`); the other four (`:1878`, `:2066`, `:2288`, `:2518`) are unaffected.
    - Delete the `warm-standby` entry from `EXCLUSION_ALLOWLIST` (`:68-84`), else the
      not-stale test at `:191-196` fails with `orphans == ["warm-standby"]`.
    - Fix prose at `:141` ("all five destroy paths") and the test title at `:183`.

3.2 `plugins/soleur/test/terraform-target-parity.test.ts`
    - Delete `WARM_STANDBY_TARGETS` (`:1031-1038`) and its `describe` (`:1040-1130`).
    - Delete `WEB2_RECREATE_TARGETS` / `WEB2_RECREATE_REPLACE` (`:1179-1184`) and their `describe`
      (`:1197-1275`).
    - Remove the two `stripJob` wrappers for `warm_standby` / `web_2_recreate` in
      `stripDispatchJobs` (`:412-450`).
    - Fix stale comments at `:381-387`, `:402-406`, `:737`, `:960-962`, `:1051-1052`.
    - **Delete, do not merely observe green.** `extractJobBlock` returns `""` for a missing job, so
      roughly half these assertions would pass **vacuously** after the jobs vanish. A green suite
      after a partial deletion is not evidence the deletion is complete.

3.3 `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`
    - Delete the two `assert_member` lines for `web_2_recreate` (`:101`) and `warm_standby` (`:102`).
    - Change the count assert `-eq 5` → `-eq 3` (`:128`). Reason: the allow-list drops from 5
      members to 3 (`release-deploy`, `pipeline-fix-apply`, `workspaces-luks-cutover`).
    - **Fix the pre-existing stale header at `:30`** (says 4, code says 5) and the prose at `:12`,
      `:16-17`, `:123`.

3.4 `apps/web-platform/infra/web-hosts-fanout-parity.test.sh`
    - Delete `check_all_copies "$APPLY_WORKFLOW" "apply-workflow" 2` (`:99`) and the now-unused
      `$APPLY_WORKFLOW` handling including the `[ -f … ]` guard at `:35`. Reason: both
      `WEB_HOST_PRIVATE_IPS` copies lived in the deleted jobs; the floor of 2 becomes 0.
    - Fix stale prose at `:5-6`, `:9-15`. Leave the `-lt 1` floor at `:69-70` alone — already
      corrected for the retire.

3.5 `tests/scripts/test-stock-preflight-gate.sh` — see Phase 4.2 (coupled to the tine deletion).

### Phase 4 — Runbook lines: what happens instead

**Non-negotiable:** every deleted runbook line gets an explicit replacement. Where a capability
genuinely disappears, say so rather than papering over it.

4.1 **`host_creates` HALT `::error::` text** (`apply-web-platform-infra.yml:462-475`, plus the
    parallel HALT inside `warm_standby` at `:1005-1008`, deleted with the job).
    - Deleted references: the third bullet's `warm-standby (#6718 …)` and `web-2-recreate (gate
      needs web2_server_replaced==1 …)` clauses, and the last bullet's warm-standby aside.
    - **The routing is unchanged and already correct:** there is no automated path; the fallback is
      the locally-run full apply per the `OPERATOR_APPLIED_EXCLUSIONS` contract (ADR-096), tracked
      by **#6730**. Only the enumeration of now-deleted dead paths is removed.
    - Retain the `inngest-host` remediation bullet unchanged — it is a live path.
    - **Add one sentence** stating that any web-host birth must first run
      `host-scripts-coherence-preflight.sh` against the digest it intends to pin, and that images
      published after this PR are already bake-verified. This is a net **gain** in runbook quality.

4.2 **`tests/scripts/lib/stock-preflight-gate.sh` web-2 tine** (`:151-181`, setter `:274-275`).
    - Delete the tine and its 25-line rationale.
    - **This is a genuine capability loss, stated plainly:** the tine offered a *free repair* —
      "if you only need the NIC or volume re-attached, that is not a recreate; dispatch
      `warm-standby`, no stock required." With web-2 retired and `warm_standby` deleted, **no
      additive dispatch exists**, so there is no free repair to offer. Remaining guidance for an
      unorderable web-1 recreate: the generic `#6463` tine survives (re-run when stock returns, or
      choose a different EU location), plus the ADR-096 fallback. The plan does not pretend a
      replacement exists.
    - Also fix the two **already-stale** line references this file carries: `:159` cites
      `apply-web-platform-infra.yml:788-796` (actual `:970-975`, both about to vanish) and
      `:178`/`:180` cite `:451` (the HALT is at `:462-475`).
    - Restructure the coupled tests in `tests/scripts/test-stock-preflight-gate.sh` **with stated
      reasons**: **T2** (`:117-126`) asserts the abort *must* name warm-standby — its contract is
      falsified by the retire, so rewrite it to assert the surviving `#6463` tine. **T10b**
      (`:226-239`) and **T13b** (`:324`) assert warm-standby is *not* offered on
      registry/git-data paths — now vacuous; delete with a reason. **T10c** (`:242-247`), the
      over-suppression guard, exists precisely to catch "a fix that drops the tine everywhere" —
      it must be deleted **deliberately and with a note**, because this PR is exactly that fix,
      legitimately so. Do not let T10c be silently satisfied.

4.3 **`.github/workflows/scheduled-inngest-health.yml`**
    - `:838` remediation step 2 — *"recreate the offending host via `apply-web-platform-infra.yml`
      (`apply_target=web-2-recreate`)"*. Replacement: with web-1 the only web host, a non-primary
      `cloudflared` connector can no longer be a second host — it implies a hand-run `cloudflared`
      or a `web_tunnel_connector` predicate regression. New step 2: inspect and stop the stray
      process; if the predicate regressed, fix `server.tf` and redeploy. There is no recreate
      dispatch and the text must not imply one.
    - `:837` — the colo→host attribution table (*"`fra*` = fsn1 = **web-2**"*). Drop the fsn1/web-2
      row; keep `ams*`/`hel*` = hel1 = web-1.

4.4 **Follow-through scripts**
    - Delete `scripts/followthroughs/warm-standby-verify-dedup-6030.sh`. Tracker **#6040 is CLOSED**;
      `sweep-followthroughs.sh` only sweeps open `follow-through` issues, so it has not run since.
      Its subject job is being deleted. Nothing replaces it.
    - Delete `scripts/followthroughs/web2-tunnel-depool-6425.sh`. Tracker **#6425 is OPEN** but was
      never enrolled (no `soleur:followthrough` directive in any issue). Its subject — a second
      tunnel connector — cannot exist post-retire. **Close #6425 as resolved-by-#6538** with a
      comment stating the retire discharges it by construction; do not leave an open P1 pointing at
      a deleted script. This is the orphan class #6470 already tracks.

### Phase 5 — Registers

5.1 Author the new ADR (§ Architecture Decision) and supersede ADR-082 per the ADR-008 convention.

5.2 Rewrite `ADR-114-…:365-373` hazard #5 to name the bake-time gate. **Preserve `:375-380`
    verbatim.**

5.3 `apps/web-platform/infra/sentry/issue-alerts.tf:1524-1542` — **comment only.** Replace *"This is
    the SOLE PAGE for a dead web-2 WARM STANDBY"* with the post-retire truth: it is the sole no-SSH
    boot page for **web-1**, the only web host, which takes all `app.soleur.ai` traffic. The
    resource, its `stage` filters and `frequency = 24` are untouched.

5.4 Delete `apps/web-platform/infra/lb-weight-gate.sh` and `lb-weight-gate.test.sh`, and its
    registration at `infra-validation.yml:585`. Record the deletion in ADR-068 §(c). Reason: its
    subject — a second origin to weight — no longer exists; its only intended caller (a Doppler
    cutover orchestrator) was never built; and deleting only the `has("web-2")` assertion would
    leave a gate that passes on a single-host roster and green-lights a weight flip to a
    nonexistent host.

5.5 Read all three `.c4` files and act on the `model.c4` warm-standby hit per § C4 views.

### Phase 6 — Verification

6.1 `bash scripts/test-all.sh` — full suite green. Diff against the Phase 0.5 baseline; every delta
    must be an intended deletion.

6.2 `actionlint` on both edited workflows; `bash -c` on extracted `run:` snippets. **Do not run
    `bash -n` on a workflow YAML** and do not run `actionlint` on composite `action.yml` files.

6.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (never `npm run -w`; the repo root
    declares no `workspaces`).

6.4 Repo-wide residual sweep — see AC10.

---

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/infra/scripts/host-scripts-want-hash.sh` | Parse `local.host_script_files` from `server.tf`; recompute the Terraform-side hash from repo files. Terraform-free WANT source for the release path. |
| `apps/web-platform/infra/host-scripts-want-hash.test.sh` | Assert output == `terraform console local.host_scripts_content_hash`; assert fail-closed on parse failure / missing file. |
| `knowledge-base/engineering/architecture/decisions/ADR-<next>-bake-time-host-scripts-coherence.md` | The relocation decision, alternatives, and the preserved `deploy-status-fanout-verify` design record. |

## Files to Edit

**Renamed (git mv, logic preserved)**

- `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` → `host-scripts-coherence-preflight.sh`
- `tests/scripts/test-web2-recreate-preflight.sh` → `test-host-scripts-coherence-preflight.sh`

**Workflows**

- `.github/workflows/reusable-release.yml` — new coherence step after `docker_build` (`:611`), before `Install cosign` (`:619`)
- `.github/workflows/apply-web-platform-infra.yml` — delete `warm_standby` (`:864-1113`), `web_2_recreate` (`:1134-1614`), comment block (`:1114-1133`); enum options + description (`:99-108`); `host_creates` HALT text (`:462-475`)
- `.github/workflows/scheduled-inngest-health.yml` — `:837`, `:838`
- `.github/workflows/infra-validation.yml` — register `host-scripts-want-hash.test.sh`; deregister `deploy-status-fanout-verify.test.sh` (`:576`), `lb-weight-gate.test.sh` (`:585`)

**Gates / filters / fixtures**

- `tests/scripts/lib/destroy-guard-filter-web-platform.jq` — remove 3 `web2_*` clauses + rationale; fix `:331` cross-ref. **Do not touch `web2_retire_allow`.**
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — remove `_run_web2_gate` (`:426-439`) + T20-T28 (`:443-560`); retarget any fixture whose mechanism-coverage would otherwise regress
- `tests/scripts/lib/stock-preflight-gate.sh` — delete tine (`:151-181`), setter (`:274-275`); fix stale line refs
- `tests/scripts/test-stock-preflight-gate.sh` — rewrite T2; delete T10b/T10c/T13b with stated reasons
- `scripts/test-all.sh` — update `run_suite` at `:233`

**Parity guards**

- `plugins/soleur/test/stock-preflight-coverage.test.ts`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`
- `apps/web-platform/infra/web-hosts-fanout-parity.test.sh`

**Registers**

- `knowledge-base/engineering/architecture/decisions/ADR-082-fresh-web2-boot-observability.md` — supersede
- `knowledge-base/engineering/architecture/decisions/ADR-114-one-tunnel-many-connectors-ingress-must-be-origin-relative.md` — `:365-373`
- `knowledge-base/engineering/architecture/decisions/ADR-068-*.md` — §(c) record the lb-weight-gate deletion
- `apps/web-platform/infra/sentry/issue-alerts.tf` — `:1524-1542` **comment only**
- `apps/web-platform/infra/nic-wait-gate.test.sh` — comments at `:369-372` and `:404-406` (the guard IS now reused; the residual narrows). **Keep every assert passing and truthful; do not restate the invalid `-target` inference the file itself corrects at `:381-386`.**
- `knowledge-base/engineering/architecture/diagrams/model.c4` — conditional, per § C4 views

**Deleted**

- `tests/scripts/lib/web2-recreate-gate.sh`
- `tests/scripts/fixtures/tfplan-web2-recreate-*.json` (8)
- `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` + `apps/web-platform/infra/deploy-status-fanout-verify.test.sh`
- `apps/web-platform/infra/lb-weight-gate.sh` + `lb-weight-gate.test.sh`
- `scripts/followthroughs/warm-standby-verify-dedup-6030.sh`
- `scripts/followthroughs/web2-tunnel-depool-6425.sh`

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Coverage never zero, and strictly greater.** The commit adding the
      `reusable-release.yml` coherence step precedes every deletion commit. Verify per-commit, not
      just at HEAD: for each commit in `git rev-list origin/main..HEAD`, at least one executable
      coherence call site exists. Walk commits with `git rev-list` + `git show`; **do not** use
      `git log -- A B` (union filter — it cannot distinguish an asymmetric commit from a paired one).
- [ ] **AC2 — Verifier logic byte-unchanged.**
      `git diff origin/main -- '*coherence-preflight.sh' -M` shows a rename whose only content
      changes are identifier/comment renames. The digest-shape gate, WANT-shape gate, `GOT` pipeline
      and the `GOT != WANT` comparison are textually identical modulo variable names.
- [ ] **AC3 — The digest `die` branch stays reachable.** T3 (bare tag) and T4 (malformed digest) in
      `test-host-scripts-coherence-preflight.sh` pass, proving the pinned-digest requirement was not
      relaxed into a mutable-tag arm.
- [ ] **AC4 — WANT is pinned to Terraform.** `host-scripts-want-hash.test.sh` asserts equality with
      `terraform console <<<'local.host_scripts_content_hash'` and is registered in
      `infra-validation.yml`. Test passes.
- [ ] **AC5 — WANT is fail-closed.** `host-scripts-want-hash.sh` exits non-zero and emits **no**
      hash when `server.tf`'s list fails to parse or an enumerated file is missing. Asserted.
- [ ] **AC6 — The gate actually fires.** A deliberately incoherent scratch image produces non-zero
      exit and `COHERENCE MISMATCH` on stderr. Evidence pasted in the PR body. Non-vacuity: a
      coherent image exits 0.
- [ ] **AC7 — The gate blocks signing.** The new step is positioned after `docker_build` and before
      `Install cosign`; confirmed by line order in the diff. An incoherent image is never signed and
      never mirrored to zot.
- [ ] **AC8 — Enum is 7, not 6.**
      `yq '.on.workflow_dispatch.inputs.apply_target.options | length' .github/workflows/apply-web-platform-infra.yml`
      returns `7`; `MIN_APPLY_TARGET_OPTIONS === 7`; the sentinel comment enumerates all 7 by name.
- [ ] **AC9 — Every sentinel change carries a reason.** Each of `MIN_APPLY_TARGET_OPTIONS` (9→7),
      `MIN_GATED_TARGETS` (5→4) and `web-1-swap` count (5→3) has an adjacent `# reason:` comment.
      The pre-existing stale header at `web-1-swap-concurrency-parity.test.sh:30` (says 4) is
      corrected to 3 in the same edit.
- [ ] **AC10 — Residual sweep is zero on live surfaces.**
      `git grep -nE 'warm.standby|warm_standby|WARM_STANDBY|web-2-recreate|web_2_recreate|WEB2_RECREATE'`
      returns no hits under `.github/workflows/`, `tests/`, `scripts/`, `plugins/soleur/test/`,
      `apps/web-platform/infra/` **except** `web2_retire_allow` / `retire_firewall_attachment_deletes`
      (a different, live surface). **Excluded from the AC:** `knowledge-base/project/plans/**`,
      `knowledge-base/project/specs/**`, `knowledge-base/project/brainstorms/**` and `**/archive/**`
      — point-in-time records that must retain the old names, including this plan and its `tasks.md`.
- [ ] **AC11 — No vacuous green.** The web-2 `describe` blocks in `terraform-target-parity.test.ts`
      are **deleted**, not left to pass on an empty `extractJobBlock` result. Verified by grepping
      for `WARM_STANDBY_TARGETS` / `WEB2_RECREATE_TARGETS` → zero hits.
- [ ] **AC12 — No orphaned targets.** `hcloud_network.private` and `hcloud_network_subnet.private`
      were targeted only by the deleted `warm_standby` job. Confirm each is still reachable by a
      surviving apply path, or record explicitly that it is in `OPERATOR_APPLIED_EXCLUSIONS` (both
      already are, at `terraform-target-parity.test.ts:481`).
- [ ] **AC13 — Mechanism coverage does not regress.** For fixtures 4
      (`web1-inplace-nonplacement`), 6 (`volume-forget`) and 8 (`substring-collision`), a surviving
      counter test still exercises the same mechanism (non-placement update detection, `forget`
      counted as destroy, `IN()` exact-equality vs substring). Name the surviving test per
      mechanism, or retain the fixture retargeted.
- [ ] **AC14 — Every deleted runbook line has a stated replacement.** The PR body carries a table:
      deleted line → what happens instead. The `stock-preflight-gate.sh` tine row states plainly
      that the free-repair path is **gone**, not replaced.
- [ ] **AC15 — ADR-082 superseded, not deleted.** File retains its history; has YAML frontmatter
      with `status:` + `superseded_by:`, an inline banner, and an explicit in-force / dead partition.
      The falsified `:52-53` "SOLE page for a dead web-2 warm standby" sentence and the `:45-46`
      "half-met" claim are corrected.
- [ ] **AC16 — Sentry alert survives.** `sentry_issue_alert.web_terminal_boot_fatal` still exists in
      `issue-alerts.tf` with its four `stage` filters and `frequency = 24` unchanged; only the
      comment differs. `git diff` on the resource body is comment-only.
- [ ] **AC17 — lb-weight-gate fully removed.** Both script and test deleted, `infra-validation.yml:585`
      deregistered, ADR-068 §(c) records it. Grep for `A_web2_not_in_roster` → zero hits.
- [ ] **AC18 — Suite green.** `bash scripts/test-all.sh` passes; `actionlint` clean on both edited
      workflows; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] **AC19 — Merge apply is a no-op.** Because this PR touches
      `tests/scripts/lib/destroy-guard-filter-web-platform.jq` and `apps/web-platform/infra/**`,
      `apply-web-platform-infra.yml` fires on merge. The plan must show **0 to add, 0 to change,
      0 to destroy**. Confirm from the plan output in the merge run.
- [ ] **AC20 — `nic-wait-gate.test.sh` asserts stay green and truthful.** All asserts pass; the
      comments at `:369-372` / `:404-406` are updated to reflect that the guard **is** now reused at
      bake time and that the residual has narrowed (#6730). The `:381-386` correction refuting the
      invalid `-target` inference is preserved verbatim.
- [ ] **AC21 — Every `knowledge-base/` path cited in this plan resolves.**
      `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'`
      returns nothing (excluding the not-yet-created ADR).
- [ ] **AC22 — CPO sign-off recorded** (threshold = `single-user incident`).

### Post-merge (automated in `/ship`)

- [ ] **AC23 — First release run verifies coherently.** After the first merge to `main` that
      triggers `web-platform-release.yml`, the discoverability command in § Observability returns a
      `COHERENT` line. **Automation: `gh run view --log` via the `gh` CLI — runs in-session.**
- [ ] **AC24 — Close #6425.** `gh issue close 6425` with a comment recording that the #6538 retire
      discharges it by construction and its follow-through script was deleted here. **Automation:
      `gh` CLI.**
- [ ] **AC25 — #6730 updated.** Comment on #6730 noting that the host-agnostic verifier now exists
      at `host-scripts-coherence-preflight.sh`, that released images are bake-verified, and that the
      remaining work is the resolver + the birth path itself. **Automation: `gh` CLI.**

**Every post-merge item is `gh` CLI-automatable and runs inside `/ship`'s post-merge verification.
There are no human-only steps.**

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure/CI change on the sole prod web host's birth-safety path. No product
surface, no user-facing UI, no schema, no regulated-data surface, no vendor spend change. The
`brand_survival_threshold: single-user incident` is carried from the blast radius of a doomed web-1
birth (total outage, no failover, no reboot repair), not from anything this PR introduces. Principal
engineering risks are (i) deleting a guard before its replacement is live — mitigated by the
mandatory phase order and AC1's per-commit walk; (ii) parity tests going vacuously green rather than
red — mitigated by AC11; (iii) over-deletion of host-generic artifacts mistaken for web-2 surface —
mitigated by reconciliation rows 7 and 9.

**Product:** not relevant. No path in `## Files to Create` or `## Files to Edit` matches any
UI-surface term or glob (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). The
mechanical UI-surface override does not fire. Product/UX Gate: **NONE**.

**Legal / Finance / Marketing / Sales / Support / Operations:** not relevant. No personal data, no
pricing, no messaging, no customer-facing change, no recurring vendor expense.

### GDPR / Compliance Gate

**Not invoked.** The canonical regulated-data regex does not match (no schema, migration, auth flow,
API route or `.sql` file). None of the four expansion triggers fire: (a) no LLM/external-API
processing of session data; (b) the `single-user incident` threshold here is availability, not data
exposure — no new processing activity; (c) no new cron/workflow reads `learnings/` or `specs/`;
(d) no new artifact distribution surface (the release path already publishes; this PR only adds a
gate that can *block* publication).

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Deleting the guard before the replacement is live** leaves a zero-coverage window at a `single-user incident` threshold. | Phase order is mandatory: Phase 1 (relocate) fully precedes Phase 2 (delete). AC1 verifies per-commit with `git rev-list` + `git show`, not a union-filter `git log`. |
| **The bash WANT recompute drifts from Terraform's `local.host_scripts_content_hash`**, making the gate assert against the wrong value. | `host-scripts-want-hash.sh` **parses** the canonical list from `server.tf` (never duplicates it), and AC4's equality test pins it to `terraform console` in `infra-validation.yml` — which already runs `terraform console` at `:161`/`:178`/`:316`. |
| **The release workflow has no terraform and no `prd_terraform` token**, so `terraform console` is unavailable there. | Verified at plan time (Phase 0.2). This is precisely why WANT comes from the parsing script. Adding `setup-terraform` + R2 backend creds + a `prd_terraform` token to the release path was rejected: it would couple image publication to Terraform state access. |
| **Parity tests pass vacuously** after job deletion (`extractJobBlock` returns `""`, so `.not.toContain` assertions succeed on nothing). | AC11 requires deletion of the `describe` blocks and greps for the constant names. A green suite after partial deletion is explicitly not accepted as evidence. |
| **Over-deletion of host-generic artifacts.** The Sentry alert and the ADR-114 hazard read as web-2 surface but protect web-1. | Reconciliation rows 7 and 9; AC16 pins the Sentry resource body to comment-only changes. |
| **`web2_retire_allow` is cross-contaminated** with the `web2_*` clauses being removed — it has the **opposite** data-volume contract and the filter warns against cross-copying at `:113-133`. | Named as do-not-touch in Phase 2.4 and excluded from AC10's sweep. |
| **The merge-triggered apply does something unexpected**, since this PR touches both `infra/**` and the destroy-guard filter. | AC19 requires a confirmed `0/0/0` plan in the merge run. |
| **Fixture deletion silently drops non-obvious regression protections** (`forget` counted as destroy; `IN()` exact-equality vs substring). | AC13 requires naming a surviving test per mechanism, or retargeting the fixture. |
| **The plan's own numbers drift** — nine supplied premises were already wrong. | Every number in this plan is re-derived from the worktree and anchored to `file:line`. `/work` must re-verify line anchors before editing, since two deletions shift line numbers substantially. |
| **Line anchors go stale mid-implementation.** Deleting ~730 lines from `apply-web-platform-infra.yml` invalidates every later anchor in this plan. | Work top-down within each file, or re-grep by content anchor rather than line number (`cq-cite-content-anchor-not-line-number`). |

---

## scoped-apply-gate re-assessment

**Explicit finding, as required: `scoped-apply-gate.sh` does not exist, and this deletion does not
relieve the pressure the framing attributes to it.**

`grep -rn "scoped.apply.gate\|scoped_apply_gate" . --exclude-dir=.git -i` returns **zero hits**
repo-wide — no issue, plan, ADR, code or comment. The name has no referent.

The nearest real artifact is **#6574**, filed as Deferred in the retire plan
(`2026-07-16-chore-retire-web-2-fsn1-orphan-plan.md:590-591`):

> the push-apply `-target` allow-list is a fiction (firewall attachment drags the fleet into every
> merge's graph). Standing hazard.

**This deletion does not relieve #6574 at all, and the framing's claim that it does is false.**
#6574's hazard is `-target` **transitivity on the routine merge path** — the same mechanism
`ADR-114:377-380` and `nic-wait-gate.test.sh:381-386` both document, whereby
`hcloud_server.web` is reachable via `cloudflare_record.app` and `hcloud_firewall_attachment.web`
regardless of what the allow-list names. That is a property of Terraform's graph, not of how many
dispatch jobs exist. Removing two `workflow_dispatch` jobs reduces **job count and enum width**; it
changes **nothing** about what the `on: push` apply's `-target` set actually drags in.

**Recommendation:** #6574 remains warranted at unchanged priority after this PR. Do not close it,
do not down-scope it, and do not treat this sweep as partial payment against it. **This PR does not
do that refactor.**

---

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **Generalize the verifier to accept a mutable tag** (framing's option (a)) | Explicitly rejected by the recorded decision backed by 5 of 7 reviewers (quoted in § Architecture Decision). It moves the TOCTOU closure from "structurally cannot re-resolve" to "the caller faithfully consumes the emitted value" and makes the digest `die` branch dead code on the mutable arm — a weaker guarantee sold as a generalization. |
| **Pin a digest on create paths the way `web_2_recreate` does** (framing's option (b)) | Its mechanism polls the **running** web-1's `/health .version` via `resolve-web1-known-good-tag.sh`. On a fresh create there is no running web-1; `RUNNING_VERSION` is empty and the script's case (b) exits 1. The mechanism is structurally unavailable on the path that needs it. |
| **Terraform `lifecycle.precondition` requiring a pinned `var.image_name`** | Preconditions evaluate during plan for the resource on **every** apply, including no-op refreshes. The routine merge apply passes `:latest`, so this would break every merge. Terraform also cannot read inside an image, so it cannot express coherence at all — only pinning. |
| **Sweep now, keep the verifier with zero call sites, let #6730 wire it** | Violates the coverage non-negotiable: zero executable call sites for an unbounded window. It is also the exact rot pattern `lb-weight-gate.sh` demonstrates — dead code with a live test, never called, silently falsified. |
| **Build the web-1 birth path in this PR** | #6730 explicitly owns it and scopes it as an *"automated, image-pinned, attachment-complete path … from empty state."* Folding it in would put a prod-host-birth capability inside a ~730-line deletion PR — inverting the risk budget exactly as #6575's own sequencing rationale warns against. |
| **Tree-diff the baked directory instead of comparing hashes** | Would name the drifting file (nicer diagnostics) but forks a second implementation of the coherence check, diverging from the boot-side hash comparison the guard exists to predict. Byte-identity with `cloud-init.yml:558` is the whole point. Rejected in favour of reusing the verifier unchanged. |
| **Add terraform + `prd_terraform` to `reusable-release.yml`** so WANT comes from `terraform console` | Couples image publication to Terraform state access and R2 backend credentials, widening the release path's blast radius and secret surface for a value already obtainable by parsing the canonical list. |

---

## Deferrals

| Deferred | Why | Re-evaluation trigger | Tracker |
|---|---|---|---|
| The tag→digest **resolver** (`resolve-image-digest.sh`) | The release path already holds `steps.docker_build.outputs.digest`; no resolution is needed today. Only a path starting from a mutable tag needs one. | #6730 lands a real web-host create path → compose resolve → verify → `plan -var image_name=<pinned>`. | **#6730** (design record preserved in the new ADR and in `2026-07-19-fix-warm-standby-web1-birth-halt-plan.md:110-149`) |
| The web-1 **birth path** itself | Owned by #6730; out of scope per its own framing and #6575's risk-budget sequencing. | — | **#6730** (stays open) |
| `-target` transitivity ("the allow-list is a fiction") | Orthogonal to this deletion; see § scoped-apply-gate re-assessment. | Unchanged by this PR. | **#6574** (stays open, unchanged priority) |

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is complete.
- **Nine supplied premises were falsified.** Treat every remaining inherited number as suspect and
  re-derive it from the worktree before editing. Two of the falsified numbers
  (`MIN_APPLY_TARGET_OPTIONS = 8`, "exactly 4 `group: web-1-swap`") originate in #6575's body and
  would each have produced a wrong sentinel edit.
- **Line anchors in this plan will drift.** Phase 2 removes ~730 lines from
  `apply-web-platform-infra.yml`; every later anchor in that file shifts. Re-grep by content anchor.
- **A green suite is not evidence of complete deletion.** `extractJobBlock` returns `""` for a
  missing job, so negative assertions pass vacuously. Delete the tests; do not observe them pass.
- **`git log -- A B` is a union filter.** For AC1's per-commit invariant use
  `git rev-list origin/main..HEAD` + `git show <sha> -- <paths>`; the union form silently green-lights
  the asymmetric-commit failure the AC exists to catch.
- **The `web2_retire_allow` clause is a different surface with the opposite data-volume contract.**
  The filter warns against cross-copying at `:113-133`. Do not sweep it.
- **The Sentry alert and ADR-114's hazard #5 read as web-2 surface but protect web-1.** Deleting
  either removes live coverage for the only web host.
</content>
