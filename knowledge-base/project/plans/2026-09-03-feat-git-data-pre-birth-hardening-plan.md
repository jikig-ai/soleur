---
title: "git-data pre-birth hardening: per-source ingest token, metadata egress closure, ingest-stage routing"
date: 2026-09-03
slug: feat-git-data-pre-birth-hardening
branch: feat-one-shot-7772-git-data-pre-birth-hardening
issue: 7772
closes: 7772
lane: cross-domain
type: enhancement
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 was run and the `## Infrastructure (IaC)` section below is its output. The two patterns
  the write guard flags are both already IaC-routed, and neither is a human step:

  1. `/etc/systemd/system/git-data-nftables.service` — delivered by cloud-init `write_files:` rendered
     through `module.git_data_userdata` into `hcloud_server.git_data.user_data`. That IS the Terraform
     route for this host: git-data has NO SSH provisioner by design (cloud-init-git-data.yml:6-9 — the CI
     runner cannot SSH it, so a remote-exec would hang the merge-triggered auto-apply) and no baked
     host-scripts image. The identical shape is already shipped at cloud-init-inngest.yml:84-101.
  2. `doppler secrets set` for GIT_DATA_BETTERSTACK_{LOGS_TOKEN,INGEST_URL} — these are `TF_VAR_*` INPUTS
     that Terraform itself reads from `soleur/prd_terraform`. A `doppler_secret` resource cannot manage
     them: the root would have to read the variable it is creating. This is the ADR-065 bootstrap pattern
     that `hr-tf-variable-no-operator-mint-default` presumes, and the write is performed by the agent over
     the Doppler CLI in Phase 1 — no operator action (`hr-never-label-any-step-as-manual-without`).
-->

## Overview

The git-data host has never been born. Its `user_data` is ForceNew with no `ignore_changes`, and
`git_data_rung2_rehearsal_gate` binds a sha256 over `cloud-init-git-data.yml` plus every `file()`-bound
payload. Every template-touching hardening change is therefore free today, costs a destructive replace of
the host holding every connected user's source once it exists, and costs a second paid rehearsal dispatch
if it lands after the next rehearsal. So the template-touching items land together or not at all.

This plan lands four items in one PR: a dedicated Better Stack Logs source for git-data so a metadata leak
no longer forces a rotation that darkens the web host and registry; a host-local nftables drop of the
Hetzner metadata endpoint for non-root UIDs; a low-severity Sentry route for the two warning stages that
today reach no rule; and two stale-prose corrections in birth-route artifacts.

**The single most consequential finding is that Item A is not blocked at all.** The issue and ADR-198 both
record it as needing "an operator mint that `hr-all-infrastructure-provisioning-servers` forbids doing ad
hoc." Measured this session: `BETTERSTACK_API_TOKEN` in Doppler `soleur/prd_terraform` is already
**write-scoped** and creates sources over plain REST. No Playwright, no operator mint, no token-mint
recursion. See Research Reconciliation R1.

---

## Research Reconciliation — Spec vs. Codebase

Every row was measured this session. The corrections are load-bearing: three of them change what the plan
builds, and two retire claims that would otherwise propagate into `/work` and `/ship` as fact.

| # | Claim as briefed / as recorded in #7772 + ADR-198 | Measured reality | Plan response |
|---|---|---|---|
| **R1** | Item A is blocked on "an operator mint that `hr-all-infrastructure-provisioning-servers` forbids doing ad hoc"; the REST fallback likely needs a write-scoped token that is "itself a mint". | **FALSE.** Two API tokens exist in `soleur/prd_terraform`, a suffix-variant sibling pair. Control probe: `POST /api/v2/sources` with `{}` returns **422 `{"errors":"Sorry, you are missing some required attributes","required_attributes":["name","platform"]}`** under `BETTERSTACK_API_TOKEN` (authorized, body invalid) and **403 `{"errors":"This API token is read-only and cannot be used for write operations."}`** under `BETTERSTACK_API_TOKEN_READONLY`. The write credential is already provisioned. | Item A ships via REST in `/work`. No Playwright, no operator handoff, no recursion. The 422-vs-403 pair is the scope evidence (`hr-verify-repo-capability-claim-before-assert`). Correct #7772 and ADR-198's Alternatives entry. |
| **R2** | The learning of 2026-07-18 records `BETTERSTACK_API_TOKEN` as minted Read-scoped. | **STALE.** The read-only token is the *separate* `BETTERSTACK_API_TOKEN_READONLY` secret, which `scheduled-terraform-drift.yml:1346` already uses by name for least privilege. The unsuffixed token is the write one. | Amend that learning. This is the `2026-07-30-one-blocked-mechanism-is-not-a-blocked-capability` class exactly — a suffix-variant sibling made "one blocked mechanism" read as a blocked capability. |
| **R3** | Better Stack documents `POST https://telemetry.betterstack.com/api/v1/sources`. | Current docs say **`/api/v2/sources`**. Measured: both `v1` and `v2` return 200 on GET; the v2 create contract is `{name, platform, data_region}` and the response carries `token` and `ingesting_host`. | Use **v2** (the current documented contract). Record that v1 still answers, so a future reader does not mistake the version for drift. |
| **R4** | Item B is "a .tf firewall change, NOT a template change" (#7772 item 2 and the briefing). | **FALSE, and this is what forces the item into the pre-rehearsal window.** Verified against Hetzner's own firewall FAQ: rules are allow-only (*"you only define what traffic is allowed to and from your server. All other traffic will be dropped"*), there is no UID matching, and *"our Firewall will always allow traffic from certain Hetzner services… This currently includes DNS resolver traffic, traffic from the Hetzner rescue system, and the cloud metadata server."* A cloud-level block is unexpressible, over-broad, and may not take effect at all. | Implement as host-local nftables inside `cloud-init-git-data.yml`. The PR body must state the correction — it is the reason the item cannot be deferred past the rehearsal. |
| **R5** | ADR-198's fourth pre-birth item: refresh the baked `/etc/default/git-data-betterstack` from Doppler at boot via a post-Doppler `runcmd`, so that "from boot N+1 the pre-Doppler stages would read a Doppler-fresh token". | **The mechanism cannot deliver its own stated benefit.** `runcmd` is once-per-instance — the repo asserts this in 14 places (`apply-web-platform-infra.yml:4273`, `git-data.tf:411`, `nic-wait-gate.test.sh:17`, …). It runs exactly once, on first boot, at the one instant the baked value and the Doppler value are identical. There is no boot N+1 execution to pick up a rotation. | **Triage OUT**, recorded on #7772 as a correction to ADR-198 rather than a deferral. A per-boot systemd variant would work but adds a boot-path write whose partial-write failure darkens eight of nine stages — and Item A independently collapses the residual it addresses. |
| **R6** | Item A adds a new address, so the birth fan-out may need widening across four sites plus `OPERATOR_APPLIED_EXCLUSIONS`. | **No cardinality change.** `doppler_secret.git_data_betterstack_logs_token` is *already* birth-target #20 (`git-data-luks.tf:128`). Item A changes the **value** bound to an existing address, not the address set. | The 20-address partition (15 presence + 3 entailed + server + firewall attachment) is untouched, and `terraform-target-parity.test.ts`'s partition assertion is unaffected. |
| **R7** | The rehearsal test pins `betterstack_logs_token` as not-divergent on the premise "prod and rehearsal share one sink"; a dedicated source falsifies that premise, so the 8-member allowlist may need widening. | **The allowlist does not need to change.** If prod git-data *and* the rehearsal both point at the new source, the token is still non-divergent — the premise's *wording* is falsified, not its truth. Widening would be refused anyway: `git-data-rung2-rehearsal.test.sh:1612-1618` hard-fails if `betterstack_logs_token` appears in the allowlist. | Design call D1: the rehearsal ships to the **new** source. Reword the premise; leave the closed 8-member set intact. No evidence weakening. |
| **R8** | `sentry_issue_alert.git_data_boot_fatal` is a "FATAL router", so widening it is a paging-policy change. | Directionally right, mechanically different: the rule has **no `level` filter at all**. Every `filters_v2` element in `issue-alerts.tf` is a `tagged_event`; the provider usage here cannot express level. The rule selects fatals *because those nine stages are only ever emitted at fatal*. | Item C remains a separate rule (correct conclusion), but the new rule discriminates by **stage value alone** — sufficient, since `betterstack_ingest` is only ever emitted at `warning`. |
| **R9** | Route Item C "to the non-paging channel." | There is no second channel. All 29 alerts use `notify_email`; the paging/non-paging distinction is **`fallthrough_type`**: `ActiveMembers` (28 rules, paging) vs **`NoOne`** (`byok_cap_exceeded` alone, non-paging). | Copy the `byok_cap_exceeded` shape: `fallthrough_type = "NoOne"`. |
| **R10** | The repo's ingest URL is `s2457081.eu-fsn-3.betterstackdata.com`; the live source reports `eu-central-1a`. | **Not drift.** `eu-fsn-3.betterstackdata.com` is a CNAME to `eu-central-1a.betterstackdata.com`; both resolve to the same five A records and both return HTTP 200. Better Stack renamed the region and kept the alias. | Leave the four non-git-data consumers untouched. For the new source, use the `ingesting_host` the API returns rather than hand-constructing an `eu-fsn-3`-style URL. |
| **R11** | `inngest-nftables.sh` is a payload to model on. | It is an **inline `write_files:` heredoc** at `cloud-init-inngest.yml:55-101` — no such file exists on disk. The whole inline block is 2,988 B. | Item B ships **inline**, not as a 10th `file()` payload. This avoids the entire payload-count cascade (D2). |
| **R12** | `git_data_boot_fatal`'s comment claims "The emitted-stage set is reconciled against this filter list." | **Unenforced.** No test reads `sentry/issue-alerts.tf` against git-data's emitted stages. The 13 sibling alerts each have an op-contract test; git-data has none. | Item C ships the first such reconciliation guard, modelled on `nic-wait-gate.test.sh:506-527`. |
| **R13** | Template hash to preserve awareness of: `241b47af…f7e08f`. Evidence file absent, route correctly HELD. | **Both confirmed.** `sha256sum` matches exactly; `git-data-rung2-boot-evidence.env` does not exist. Live Hetzner holds four servers (`soleur-web-platform`, `soleur-web-2`, `soleur-registry`, `soleur-inngest`) and **no `soleur-git-data`** — the host has never been born. | Proceed. Do not create the evidence file. |
| **R14** | The Playwright MCP server failed to connect at session start; do not report it as a capability gap without trying. | **Not a capability gap.** Driving the exact `.mcp.json` command with an MCP `initialize` handshake returned `{"result":{"protocolVersion":"2024-11-05",…,"serverInfo":{"name":"Playwright","version":"1.62.0-alpha-…"}}}`, rc=0. `@playwright/mcp@0.0.78` is cached, Chrome is present, no stale `Singleton*` locks, no orphaned processes. | Recorded as a transient session flake resolved by a `/mcp` reconnect. Item A does not need it, so it blocks nothing. |

---

## Research Insights

### Premise Validation (Phase 0.6)

Every artifact cited by the briefing was checked. `#7772` is **OPEN** (label `deferred-scope-out`, milestone
`Post-MVP / Later`). `#7460` is **CLOSED** — it is the PR-B this work defers from. All 23 cited file paths
exist except `apps/web-platform/infra/git-data-rung2-boot-evidence.env`, whose absence is the correct and
required state. `ADR-198` and `ADR-149` both exist. `sha256(cloud-init-git-data.yml)` matches the briefed
`241b47af28fee2951bad76d4c57f49d6220c21907d0b89b19c2bbdca08f7e08f` exactly. Live Hetzner and the live
Better Stack API were queried directly (`hr-no-dashboard-eyeball-pull-data-yourself`) rather than inferred
from code. Fourteen premises were corrected — see the table above; the two that change the plan's shape are
R1 (Item A is unblocked) and R11 (inline, not a payload).

The mechanism-vs-ADR-corpus check found the per-source token sitting in ADR-198's **Alternatives
Considered** as "REJECTED FOR NOW, TRACKED" with `Re-evaluation trigger: before the git-data host is born`.
This plan fires that trigger; it does not resurrect a rejected mechanism. The rejection's stated basis
("either a provider that does not exist here or an operator mint") is what R1 falsifies, so the ADR
amendment must correct the *reason*, not merely flip the status.

**The provider half of that basis is re-confirmed, not inherited.** `BetterStackHQ/better-uptime` at its
latest version **0.21.14** exposes **33 resources** — monitors, heartbeats, on-call, status pages,
integrations, catalog, severities — and none for Logs/telemetry sources. No other Better Stack provider
exists in the registry. `inngest.tf:451-473` records this as an "IaC gap". What was false was only the
operator-mint half.

### Property List (Phase 0.6b)

- **P1.** A git-data credential leak no longer forces rotating a credential three other consumers depend on.
- **P2.** Code execution as the unprivileged `git` account cannot read the host's entire `user_data` out of
  the Hetzner metadata endpoint.
- **P3.** A boot-time Better Stack ingest failure reaches a reader, on the first boot, when nobody is
  watching a dashboard.
- **P4.** Two birth-route artifacts stop asserting falsehoods about birth-route resources.
- **P5.** Every change above lands before the next rehearsal dispatch, so the evidence hash is bound once.

### Cut List (Phase 0.6b)

| Mechanism the ask proposed | Property it would buy | Why it is cut |
|---|---|---|
| Playwright MCP mint flow for the Better Stack source (idempotent find-or-create evaluate, `.playwright-mcp/` filename capture, browser-crash resumption) | P1 | An already-provisioned write-scoped REST credential buys P1 outright (R1). `hr-exhaust-all-automated-options-before` prefers the API path; the whole Playwright apparatus — and the write-scoped-token recursion the briefing asked to handle explicitly — dissolves. Retained only as a documented fallback if the REST create ever regresses. |
| A `hcloud_firewall.git_data` egress rule | P2 | Unexpressible (allow-only, no UID matching) and possibly inert against the metadata server (R4). Replaced by host-local nftables. |
| A 10th `file()`-bound payload for the nftables script | P2 | The inline `write_files:` precedent buys the same property (R11) without touching the payload floor at `git-data-birth-readiness-gate.sh:544`, the `-eq 9` arm at `git-data-render-strip-parity.test.sh:235`, `git-data-template-strip.test.sh:275`, `MIN_PAYLOADS` at `git-data-runcmd-rehearsal.test.sh:523` and its dest map at `:542`, `test-git-data-birth-readiness-gate.sh:425`, and the hand-mirrored map in `git-data-userdata-budget.sh`. Six files not edited is six chances to wedge the birth route not taken. |
| Widening `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` to admit `betterstack_logs_token` | (none) | Buys no property and weakens what the evidence proves. D1 makes it unnecessary; `git-data-rung2-rehearsal.test.sh:1612` would refuse it regardless. |
| A post-Doppler `runcmd` refresh of the baked env file (ADR-198's fourth item) | (none, as specified) | The mechanism runs once, at the instant the two values are identical (R5). It cannot deliver the rotation-freshness it is proposed for. |

### Value-Proposition Measurement (Phase 0.6c)

The cost case is "one PR, before the rehearsal." Measured rather than asserted:

- A second rehearsal dispatch costs **one real Hetzner cpx22 host (~€0.02, ~8 minutes)** plus a
  `web-platform-infra-apply` environment approval, per `runbooks/git-data-rung2-rehearsal.md`.
- The rehearsal route has already consumed **three paid hosts across four dispatches** (one dry-run success
  2026-07-30, three real-host failures), per `model.c4:218`. This is a measured cost, not a hypothetical.
- The evidence self-invalidates on any edit to the template or its nine payloads, so a template change
  landing after a PASS forces a full re-rehearsal — *"another paid host and another approval."*
- Post-birth, the same change costs a **destructive replace of the host holding every user's source**, and
  ADR-115 bars git-data from the reboot primitive, so there is no cheaper repair.

Byte headroom, from the authority (`bash apps/web-platform/infra/git-data-userdata-budget.sh`):

```
git-data user_data: stored=13132 B / cap=32768 B (headroom 19636 B, raw 78717 B, stripped 38935 B)
```

The inngest inline nftables block is 2,988 B raw, and comment lines are stripped at render by
`local.git_data_template_rationale_strip`, so rationale is free. **19,636 B of headroom against a ~3 KB
inline block is comfortable** — but the budget script is the only authoritative gate and must be re-run
after the edit, never predicted.

### Applicable institutional learnings

- `knowledge-base/project/learnings/workflow-patterns/2026-06-17-vendor-dashboard-mint-presumed-playwright-automatable.md` — a vendor
  dashboard action is presumptively automatable; the burden of proof is on the operator-only claim,
  discharged only by an attempt reaching a **named** gate (CAPTCHA/OTP/TOTP/passkey/push-MFA/payment-card/
  hardware-token). Here the burden is discharged one step earlier: the REST path works, so no dashboard
  interaction is needed at all.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-18-playwright-evaluate-filename-allowed-roots-and-token-transcript-fallback.md`
  — measured allowed roots are the repo root and `.playwright-mcp/`; the evaluated function **runs before
  the write is validated**. Also the source of the stale Read-scoped claim corrected in R2. Its
  credential-hygiene rule still governs: pipe via stdin, never `cat`, never echo.
- `knowledge-base/project/learnings/workflow-patterns/2026-06-17-operator-mint-tf-var-must-sequence-before-auto-applied-iac.md`
  (ADR-065) — a no-default variable in `apps/web-platform/infra/` must resolve in Doppler `prd_terraform`
  **at merge time**: Terraform resolves every root variable before `-target` pruning, so an unprovisioned
  one fails the whole merge-triggered apply. This is the hard ordering constraint on Phase 1 → Phase 2.
- `knowledge-base/project/learnings/2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md` — Doppler names drop the
  `TF_VAR_` prefix; `--name-transformer tf-var` **adds** it. So the secret is
  `GIT_DATA_BETTERSTACK_LOGS_TOKEN`, never `TF_VAR_git_data_betterstack_logs_token`.
- `knowledge-base/project/learnings/2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md` — Sentry dedups on
  `action_match + filter_match + frequency + actions-shape`, not conditions. The new rule needs an unused
  `frequency`.
- `knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md` — git-data is explicitly carved out of the reboot primitive: its
  `luksOpen` has no `crypttab` and its fstab entry is not reboot-safe, so a reboot silently unmounts the
  store. Anything added here must be correct on first boot without relying on a reboot to repair it.
- `knowledge-base/project/learnings/security-issues/2026-06-14-nft-injection-via-unvalidated-config-reject-whole-file.md` —
  repo-controlled nftables input must reject-whole-file on a bad line. Item B's rule is a **static literal**
  with no config file and no interpolation, so that injection surface does not exist here. Recorded so the
  omission is deliberate rather than overlooked.
- `knowledge-base/project/learnings/2026-07-30-one-blocked-mechanism-is-not-a-blocked-capability.md` — the exact class of R1/R2: one
  blocked mechanism (a read-only token) was generalized into a blocked capability, and the enabling sibling
  was one suffix away.

### Load-bearing mechanics `/work` must honor

- **Payload set is 9**, extracted from `modules/git-data-userdata/main.tf` by
  `git_data_rung2_user_data_sha256()`. Floor `-lt 9` at `git-data-birth-readiness-gate.sh:544`. The
  extractor ABORTs on a second `templatefile(` or any `file()` outside the strict single-line
  `file("${path.module}/…")` form. **Item B adds no payload, so none of this moves.**
- **Two template invariants** (`main.tf:54-58`): the strip expression contains no brace, and every map entry
  sits on one physical line — `cloud-init-user-data-size.test.ts` counts brace depth and parses vars
  line-wise. **Item B touches neither** (no new map entry).
- **The rehearsal suite's hard-wired assumptions**, all of which Item A moves:
  `git-data-rung2-rehearsal.test.sh:245-261` (arm 7) extracts prod's ingest URL from **`zot-registry.tf` by
  name**; `:1578-1602` (arm 72) pins `value = var.betterstack_logs_token` by exact regex; `:1621-1675`
  (arms 74/75) pin `betterstack_logs_token = var.betterstack_logs_token` in both roots and assert neither
  declares a default; `:1612-1618` (arm 5.6a) refuses the allowlist widening; `:599-604` pins the 12-member
  module-input set. Anti-vacuity floor is **75**.
- **The module enforces** `length(var.betterstack_logs_token) > 20`
  (`modules/git-data-userdata/variables.tf:96-101`). Better Stack ingest tokens are 24 chars — satisfied,
  but the new token must be checked against it before any apply.
- **Better Stack query plumbing is team-scoped, table-keyed.** `scripts/betterstack-query.sh:93` defaults
  `BS_TABLE=t520508_soleur_inngest_vector_prd_3_logs`; team is **520508**. A new source gets a new
  `table_name`, so `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — which interpolates
  `$BS_TABLE` at `:424-425` and passes no `--table` — must be pointed at the new table. The ClickHouse
  credential is unchanged (team-scoped, not source-scoped).
- **The Sentry root plans FULL-ROOT** (`apply-sentry-infra.yml:284`, asserted by
  `test-sentry-full-root-apply.sh`), so a new alert needs no `-target` entry.
  `scripts/sentry-create-gate.sh` is diff-matched and passes automatically when the
  `+resource "sentry_issue_alert" "<name>"` line is in the diff under `apps/web-platform/infra/sentry/*.tf`.
  `test-destroy-guard-sentry-scope-guard.sh` is **type**-keyed and already covers `sentry_issue_alert`.
- **Provider pin is `jianyuan/sentry 0.15.5`** (`sentry/versions.tf:49`), though several comments still say
  0.15.4. Frequencies taken: 5, 10-27, 30, 60-63. Free: 6-9, 28-29, 31+.
- **git-data makes zero IMDS calls.** `grep -c '169\.254\.169\.254'` returns **0** across
  `cloud-init-git-data.yml` and all nine payloads; so do `169.254` and `fe80::a9fe`. The three `metadata`
  hits are prose comments, one of which (`cloud-init-git-data.yml:112`) is this change's own justification:
  *"the git-data firewall declares zero rules and egress to the metadata endpoint is open."*
- **`nftables` is not in git-data's `packages:`** (only `git`, `util-linux`, `cryptsetup`, `curl`).
- **No `meta skuid` and no `hook output` chain exists anywhere in the repo.** Item B's rule is the first of
  both. The only base-chain precedent is `cloud-init-inngest.yml:74`
  (`type filter hook input priority -10; policy accept;`).
- **Hetzner serves no documented IPv6 metadata endpoint.** The service is IPv4-only at `169.254.169.254`
  and is itself what *supplies* the IPv6 configuration to cloud-init. `fe80::a9fe:a9fe` has zero repo hits
  and no vendor documentation.

---

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (63 issues) and matched every file this
plan touches against the bodies.

- **#7098** — *"ci: audit the 56 `run:` bodies whose `set` omits -e against GitHub's inherited `bash -e`,
  then shape the lint"* — names `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`.
  **Disposition: acknowledge.** Different concern (a repo-wide shell `set -e` audit plus a new lint), and
  this plan's edits to that file are content arms, not `set` handling. Folding a 56-site lint into a
  pre-birth hardening PR would put the birth route behind an unrelated audit. The issue stays open.

No other overlap across the remaining thirteen files.

---

## User-Brand Impact

**If this lands broken, the user experiences:** their repository push failing against a git-data host that
either never finished booting (an nftables unit placed inside the `set -e` region aborts `runcmd`, which is
once-per-instance and unrepairable by reboot — the host must be replaced) or that boots with a wedged `main`
behind it (a no-default Terraform variable unprovisioned at merge time fails the *entire* merge-triggered
apply for `apps/web-platform/infra/`, not just its own resource, blocking every unrelated infrastructure
change until it is fixed).

**If this leaks, the user's source code is exposed via:** the Hetzner metadata endpoint. Today any code
execution as the unprivileged `git` account — the account whose forced-command wrappers serve every
connected user's push — can `curl http://169.254.169.254/hetzner/v1/metadata` and read the entire
`user_data`, which bakes `doppler_token` (scoped to `prd_git_data`, which holds `GIT_DATA_LUKS_KEY`, the
passphrase decrypting every user's source at rest), `sentry_dsn`, and the Better Stack ingest token. ADR-198
concedes `0600` defends only a file-read primitive. This plan closes that path for non-root UIDs. A second,
narrower vector: the write-scoped `BETTERSTACK_API_TOKEN` and the newly minted ingest token must never reach
the transcript, a job log, or a CI artifact — **the repository is public**.

**Brand-survival threshold:** `single-user incident`

Consequently `requires_cpo_signoff: true` is set in frontmatter, and `user-impact-reviewer` is invoked at
review time per `plugins/soleur/skills/review/SKILL.md`.

---

## Design Calls

Made explicitly, with reasoning recorded, rather than by default.

### D1 — The rehearsal ships to the NEW git-data source (both roots, one sink)

**Decision.** Prod git-data and the rung-2 rehearsal both point at the new dedicated source. The closed
8-member `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` is **not widened**.

**Why this is strictly better than the alternative on every axis.** The briefing framed this as a trade:
widen the allowlist (weakening the evidence), or accept that the rehearsal stops attesting the channel prod
uses. There is a third option, and it is the correct one. `betterstack_logs_token` is "not a declarable
divergence" because prod and rehearsal ship to the *same* sink. That stays true when the same sink is the
git-data sink. What is falsified is the parenthetical wording — *"prod and rehearsal share one sink"* — not
the pin itself.

- The allowlist stays a closed 8-member identity-shaped set. No evidence weakening. Widening would be
  refused mechanically anyway: `git-data-rung2-rehearsal.test.sh:1612-1618` fails if the token name appears
  in it, and `:230-235` does the same for `betterstack_ingest_url`.
- The rehearsal attests the **exact** credential and endpoint production will use — the entire point of a
  rehearsal, and the same argument `rung2-rehearsal/variables.tf` already makes for `sentry_dsn`: *"against
  a different DSN it would prove a channel prod does not use."*
- Rehearsal rows landing in the prod git-data source are already isolable: `host_name` is
  `soleur-git-data-rehearsal-<run-id>` and **is** an allowlisted divergence (member 1 of 8). The capture
  script already isolates on it; that mechanism is unchanged, only re-pointed.

**Accepted cost, stated rather than elided:** rehearsal boot rows are written into the production git-data
source — a handful of lines per dispatch, distinguishable by `host_name`, against 90-day retention. This is
materially cheaper than either alternative.

**Consequent edits, each real rather than a formality:** arm 7 must extract prod's URL from git-data's own
source of truth instead of `zot-registry.tf` by name; arm 72's `value = var.…` regex; arms 74/75's variable
names; arm 5.6a's premise wording; and the capture script's table.

### D2 — Item B ships INLINE, not as a 10th `file()` payload

**Decision.** The nft script and its systemd unit are inline `write_files:` entries in
`cloud-init-git-data.yml`, modelled on `cloud-init-inngest.yml:55-101`.

**Why.** The closest precedent *is* inline — `inngest-nftables.sh` does not exist on disk. Going inline
avoids editing six independent gate/mirror sites that all hard-code the payload count 9, any one of which
wedges the birth route if missed. It also keeps `git-data-userdata-budget.sh`'s hand-mirrored map byte-equal
to `main.tf` with no edit, so `git-data-render-strip-parity.test.sh` stays untouched. At ~3 KB against
19,636 B of headroom, byte cost is not the deciding axis; blast radius is.

### D3 — A failed nftables load WARNS, it does not abort the boot

**Decision.** The unit is enabled after the main boot sequence with `rc` capture and a `warning`-level emit
at a new `stage:nftables_metadata`, following the `gc_timer` idiom (`cloud-init-git-data.yml:887-898`) —
**not** inside the `set -e` region armed at line 619.

**Why.** A host that boots correctly but without the metadata drop is degraded-but-serving, and that
degradation is exactly the status quo this plan improves on. A host that refuses to boot over a hardening
control is unrecoverable: `runcmd` is once-per-instance, ADR-115 bars git-data from the reboot primitive,
and the store holds every connected user's source. Inverting that risk to gain strictness on a deterministic
`nft -f` load is the wrong trade. The failure that actually needs catching is "we shipped the rule wrong",
which a render-time guard catches before any host exists (Guard 2).

### D4 — The new low-severity Sentry rule covers BOTH new warning stages

**Decision.** One `sentry_issue_alert` with
`tagged_event { key = "stage", match = "IS_IN", value = "betterstack_ingest,nftables_metadata" }` and
`fallthrough_type = "NoOne"`.

**Why.** D3 introduces `stage:nftables_metadata`, and `issue-alerts.tf` records repeatedly that a stage
matching no rule is a write-only event — *"`stage=pull` matched NO rule in this file, so the dead host paged
nobody"* (`:1681-1682`). Shipping a new stage with no route would reintroduce, in miniature, the exact
defect Item C exists to close. `IS_IN` with a comma-separated value is the established shape
(`byok_cap_exceeded`'s `op` filter). This is a deliberate extension of the issue's option 1, not a
substitution for it.

### ADR-198's fourth item — triaged OUT, as a correction rather than a deferral

ADR-198 tracks refreshing the baked `/etc/default/git-data-betterstack` from Doppler at boot, under the same
pre-birth trigger, and says it "is worth doing before the host is born." It does not survive triage:

1. **The proposed mechanism cannot deliver its stated benefit.** ADR-198 sketches a post-Doppler `runcmd`
   and claims "from boot N+1 the pre-Doppler stages would read a Doppler-fresh token." `runcmd` is
   once-per-instance (asserted in 14 places across the repo). It runs on first boot only — the one moment
   the baked value and the Doppler value are provably identical, because both were just provisioned from the
   same variable. There is no boot N+1 execution. The refreshed file persists, carrying boot-1's value
   forever.
2. **A per-boot variant would work but is a worse trade.** A systemd oneshot would deliver the freshness, at
   the cost of a write on the boot path whose partial-write failure leaves an empty token — darkening eight
   of the nine stages, the precise state ADR-198 spends a section making observable.
3. **Item A collapses the residual it addresses.** The value of a boot refresh is bounded by how often the
   baked token goes stale. With a dedicated per-host source, git-data's token rotates only when git-data
   itself is compromised — and in that scenario the host is being replaced anyway, which re-bakes the token.
   The shared-token rotation pressure from three other consumers, which is what made staleness likely, is
   exactly what Item A removes.

Recorded on #7772 and in the ADR-198 amendment with a re-evaluation trigger: **if git-data ever again shares
an ingest credential with another consumer, or if a per-boot refresh unit lands for another reason.**

### Item E — #7772 item 3 is not in scope, and why

`templatefile` ARGUMENT values are bound by declaration, not by the evidence hash. This is **not a birth
blocker** and this plan does not attempt it. The gate binds what is bindable: `RUNG2_VAR_DIVERGENCE` is
checked against a closed 8-member allowlist, `betterstack_logs_token` is deliberately absent from it, and
both roots declare the variable with no default. "Not on the allowlist" is genuinely weaker than "asserted
equal", but a value-equality assertion is unimplementable without the suite reading a secret at apply time.

**Re-stated against the post-Item-A allowlist, per the briefing's instruction:** D1 leaves the allowlist at
its existing 8 members, so the disposition is unchanged in substance — but it now rests on a *stronger*
premise. Before this PR, the structural parity arms asserted that both roots pass their own no-default
variable for a token pointing at a source shared with three other consumers. After it, they assert the same
for a token pointing at a source used by git-data alone, so the blast radius behind the residual gap shrinks
even though the gap is identical in kind. Closing it properly remains a redesign of what the evidence
attests. Recorded on #7772 with re-evaluation trigger: **when render-arg values (or an HMAC over them) are
bound into the evidence file.**

---

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-198.** No new ADR: every decision here executes or corrects a decision ADR-198 already framed,
and a new ordinal would split one argument across two documents. Four amendments, each an in-scope task:

1. **Alternatives → "A per-source Better Stack token — REJECTED FOR NOW, TRACKED" becomes ADOPTED**, with
   the *reason* corrected rather than the status merely flipped. The recorded basis was "either a provider
   that does not exist here or an operator mint, which `hr-all-infrastructure-provisioning-servers` forbids
   doing ad hoc." The provider half is true and re-confirmed at v0.21.14; the operator-mint half is false
   (R1). Leg (3) of the ADR's three-part capability test — "single-purpose to this host", its stated open
   residual — is now satisfied.
2. **The "0600 does not defend against code execution" concession gains its closure.** ADR-198 says the
   closure "is tracked, not claimed"; record that it shipped as host-local nftables, and why a Hetzner Cloud
   Firewall could not be it (R4, with the three vendor-documented reasons).
3. **"Considered: refresh the baked file from Doppler at boot" is retired**, with the once-per-instance
   finding (R5) as the reason — the mechanism could not deliver its own benefit.
4. **Cross-host blast radius is re-measured.** The section states one Logs source exists and the token fans
   out to four consumers; after this change there are two sources and git-data is on its own.

Also amend `knowledge-base/project/learnings/workflow-patterns/2026-07-18-…-token-transcript-fallback.md` to correct the Read-scoped
claim (R2).

**ADR-149 needs no amendment:** items 7 and 8 remain open and this plan touches neither. Its release
checklist item 3 is satisfied vacuously — no new address is introduced (R6).

### C4 views

All three model files were read in full, not keyword-grepped, per the completeness mandate.

- **External human actors:** none added. The founder/operator relationship is unchanged; the unprivileged
  `git` account is a host-local Unix account, not a modeled actor.
- **External systems:** none added. **Better Stack is already modeled** (`model.c4:309`) — but its
  description hard-codes the single-source assumption: *"a Logs warehouse (source 2457081,
  ClickHouse-SQL-queryable)"*. After this change there are two sources and git-data no longer multiplexes
  into 2457081. **That description is an in-scope edit.** The Hetzner metadata service is internal to the
  already-modeled `hetzner` container; the nftables rule is host-local hardening, not a new system edge.
- **Containers / data stores:** none added. `gitDataStore` (`model.c4:218`) is already modeled and already
  carries the unborn-host caveat.
- **Actor↔surface access relationships:** none *gained*. The change **removes** an implicit capability
  (non-root metadata read) that was never modeled as a relationship, so there is no edge to delete. No
  `views.c4` `include` line changes, and therefore no new element to render.

After editing, run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` — a
`view include` referencing an undefined element fails there, not at `tsc`.

### Sequencing

Both amendments describe state that is true when this PR merges, so they ship in it. Nothing is soak-gated,
so no `status: adopting` note is needed.

---

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `apps/web-platform/infra/variables.tf` | Add `git_data_betterstack_logs_token` (string, sensitive, **no default**) and `git_data_betterstack_ingest_url` (string, no default). Mirror the `betterstack_logs_token` description shape exactly: capability ceiling, where minted, which Doppler config supplies it, and the literal phrase `No default (hr-tf-variable-no-operator-mint-default)`. |
| `apps/web-platform/infra/git-data.tf` | `betterstack_ingest_url` and `betterstack_logs_token` in the `module "git_data_userdata"` block (`:303-304`) move off `local.betterstack_logs_ingest_url` / `var.betterstack_logs_token` onto the new variables. |
| `apps/web-platform/infra/git-data-luks.tf` | `doppler_secret.git_data_betterstack_logs_token.value` (`:132`) moves to `var.git_data_betterstack_logs_token`. Address unchanged, so no fan-out change. `lifecycle { ignore_changes = [value] }` stays. |
| `apps/web-platform/infra/cloud-init-git-data.yml` | Item B: inline `write_files:` for the nft script (0755) and its systemd unit (0644); `nftables` added to `packages:`; a `runcmd` item enabling the unit with rc capture and a `stage:nftables_metadata` warning emit. **This is the ForceNew change and the hash-invalidating change.** |
| `apps/web-platform/infra/rung2-rehearsal/variables.tf` | `betterstack_ingest_url`'s default re-points to the new source (D1). Its comment must be rewritten — the current one justifies the default by pointing at `zot-registry.tf`'s literal, which is no longer git-data's source of truth. |
| `apps/web-platform/infra/sentry/issue-alerts.tf` | Item C: new `sentry_issue_alert` per D4 — `fallthrough_type = "NoOne"`, `filter_match = "all"`, one `tagged_event` with `IS_IN`, an unused `frequency` (6-9/28-29/31+), `conditions_v2 = [{ first_seen_event = {} }]`, `lifecycle { ignore_changes = [environment] }`. |
| `apps/web-platform/infra/zot-registry.tf` | **Untouched.** `local.betterstack_logs_ingest_url` keeps serving the web hosts and the registry on 2457081. |

The four non-git-data consumers (`inngest-betterstack-token.tf`, `zot-registry.tf`'s Doppler secret,
`inngest-host.tf`'s bake, `vector.toml`'s sink) stay on 2457081 and `var.betterstack_logs_token`.

Required providers are unchanged: `hetznercloud/hcloud`, `DopplerHQ/doppler` in the main root;
`jianyuan/sentry 0.15.5` in the sentry root. Sensitive variables and their sources:
`TF_VAR_git_data_betterstack_logs_token` ← Doppler `soleur/prd_terraform` `GIT_DATA_BETTERSTACK_LOGS_TOKEN`;
`TF_VAR_git_data_betterstack_ingest_url` ← `GIT_DATA_BETTERSTACK_INGEST_URL` (non-secret, co-located so both
roots resolve identically).

### Apply path

**(a) cloud-init-only.** The git-data host has never been provisioned, so there is no running host to patch
and no bootstrap script to write. Every git-data resource is an `OPERATOR_APPLIED_EXCLUSION`, so merging is
**inert in production** by contract — the changes take effect at the gated `git-data-host-create` dispatch,
which is itself still held by `git_data_rung2_rehearsal_gate`. Blast radius at merge for git-data: none.

**The one real merge-time risk is the no-default variables**, which is why Phase 1 strictly precedes
Phase 2: `apply-web-platform-infra.yml` fires on any `apps/web-platform/infra/**` push to main, and
Terraform resolves every root variable before `-target` pruning, so an unprovisioned no-default variable
fails the whole apply and wedges unrelated infrastructure changes. Because the credential provisioning is
automatable in session (R1), no PR split is needed — but the Doppler write must be verified present before
the branch is marked ready (AC16).

The Sentry root applies **full-root** on push to `apps/web-platform/infra/sentry/**` and is a separate
workflow; a new alert rule is a zero-downtime create.

### Distinctness / drift safeguards

- `lifecycle { ignore_changes = [value] }` on `doppler_secret.git_data_betterstack_logs_token` is retained:
  rotation is managed at the source of truth, not by Terraform.
- `lifecycle { ignore_changes = [environment] }` on the new Sentry alert, matching all 28 siblings.
- The new ingest URL becomes a **third** hard-coded copy of a Better-Stack host literal (prod variable,
  rehearsal default, budget-script stub). Arm 7 is what keeps the first two byte-equal and must be
  re-pointed rather than deleted; the budget stub is cosmetic but should be updated for accuracy.
- Secret values land in `terraform.tfstate`, which lives in the encrypted R2 backend — unchanged posture.
- `dev != prd`: git-data has no dev counterpart; the new secrets are `prd_terraform` only.

### Vendor-tier reality check

Better Stack's Logs product is on a paid tier already carrying source 2457081 at 90-day retention. A second
source consumes additional ingest quota against the same account. This is material: the account **exhausted
its Logs quota on 2026-08-14 and refused every ingest POST with HTTP 402 for ~49 hours**
(`knowledge-base/operations/expenses.md:44`). git-data's own volume is nine boot-stage lines per boot plus
gc faults — negligible — and the new source is created with retention no longer than the incumbent's 90
days. The Telemetry API exposes no usage or billing endpoint (`/usage`, `/billing` both 404), so consumption
cannot be pulled programmatically; `scripts/betterstack-ingest-probe.sh` is the live accepting/refused
probe. **No new recurring vendor expense line is created** — this is a second source on an existing
subscription, not a new vendor, so `wg-record-recurring-vendor-expense-before-ready` does not fire.

---

## Implementation Phases

### Phase 0 — Preconditions (read-only)

1. Re-run `bash apps/web-platform/infra/git-data-userdata-budget.sh` and record the baseline. Re-confirm
   `sha256sum apps/web-platform/infra/cloud-init-git-data.yml` is still `241b47af…f7e08f` and that
   `git-data-rung2-boot-evidence.env` is absent.
2. Re-run the scope probe: `POST /api/v2/sources` with `{}` under both tokens, expecting 422 and 403.
   **Status codes only** — never a response body, because `GET /sources` returns every source's ingest
   token.
3. Re-confirm `grep -c '169\.254\.169\.254'` is 0 across the template and all nine payloads, and that no
   root-owned IMDS consumer exists on this host beyond cloud-init's own datasource.
4. Confirm `nftables` is absent from `packages:` and that no `git-data-nftables*` name collides.

### Phase 1 — Item A: create the source and provision Doppler (MUST precede any `.tf` merge)

1. **Idempotent find-or-create.** `GET /api/v2/sources`, filter by name `soleur-git-data-prd`. If present,
   reuse; if absent, `POST /api/v2/sources` with
   `{"name":"soleur-git-data-prd","platform":"http","data_region":"eu-central-1a","logs_retention":90}`.
   Platform `http` is semantically right — the emitter is a raw `curl` POST, not a Vector agent; the
   incumbent's `vector` platform is cosmetic for ingest.
2. **Capture without transcript exposure.** Extract `token` and `ingesting_host` from the create response
   with `jq` **inside the same shell** and pipe the token to the Doppler CLI over **stdin**. Never `cat`,
   never echo, never `--plain` to stdout. The repository is public and job logs are an exposure surface.
   Target `GIT_DATA_BETTERSTACK_LOGS_TOKEN` in `soleur/prd_terraform` (no `TF_VAR_` prefix —
   `--name-transformer tf-var` adds it), and `GIT_DATA_BETTERSTACK_INGEST_URL` =
   `https://<ingesting_host>/`.
3. **Verify without reading the value back.** Assert both names exist via `doppler secrets --only-names`,
   and prove the credential works with `scripts/betterstack-ingest-probe.sh` against the new URL (exit 0 =
   accepting). Record the new `table_name` for Phase 3.
4. Confirm the token length satisfies the module's `> 20` validation before any apply.
5. **Fallback, only if the REST create regresses:** Playwright MCP against the Better Stack dashboard,
   capturing via `browser_evaluate(filename: "<worktree>/.playwright-mcp/bs-git-data.json")` — an absolute
   path under the worktree, because MCP tools resolve from the repo root
   (`hr-mcp-tools-playwright-etc-resolve-paths`) and the measured allowed roots are the repo root and
   `.playwright-mcp/`. The evaluate must be find-or-create, because the function runs before the filename
   write is validated. Reconnect the MCP server first (`/mcp`); it is configured and installed correctly
   (R14).

### Phase 2 — Item A wiring (contract before consumers)

1. Add both variables to `variables.tf` (no defaults, mirroring the sibling description convention).
2. Re-point `git-data-luks.tf:132` to `var.git_data_betterstack_logs_token`.
3. Re-point `git-data.tf:303-304` to the new variables.
4. Re-point `rung2-rehearsal/variables.tf`'s `betterstack_ingest_url` default and rewrite its comment.
5. Update the ingest-URL stub in `git-data-userdata-budget.sh` for accuracy.
6. `terraform validate` both roots.

### Phase 3 — Item A gate and harness updates (D1)

1. Arm 7: extract prod's URL from git-data's new source of truth **by shape**, not from `zot-registry.tf`
   by name.
2. Arm 72: the `value = var.…` regex.
3. Arms 74/75: variable names in both roots' module blocks; the no-default assertions stay.
4. Arm 5.6a: reword the premise label from *"prod and rehearsal share one sink"* to state that both ship to
   the **git-data** sink, with the D1 reasoning in the surrounding comment. **The allowlist is not touched.**
5. The 12-member module-input pin at `:599-604` is unchanged (module input *names* do not change, only the
   root variables bound to them) — verify rather than assume.
6. `scripts/followthroughs/git-data-rung2-evidence-capture.sh`: query `t520508_<new_table_name>_logs`.
7. Keep the anti-vacuity floor at 75, or raise it if arms are added.

### Phase 4 — Item B: the metadata egress closure (the ForceNew change)

1. Add `nftables` to `packages:`.
2. Inline `write_files:` the nft script at `0755 root:root`, modelled on `cloud-init-inngest.yml:55-101`:
   a `command -v nft` preflight, then a quoted heredoc (`nft -f - <<'NFTEOF'`) declaring its **own** table
   so `nft -f` replaces it atomically and the script is idempotent:

   ```
   table inet soleur_git_data {
     chain output {
       type filter hook output priority -10; policy accept;
       meta skuid != 0 ip daddr 169.254.169.254 drop
       meta skuid != 0 ip6 daddr fe80::a9fe:a9fe drop
     }
   }
   ```

   `policy accept` plus a targeted drop leaves all other egress (apt, GitHub, Doppler, Sentry, Better
   Stack, DNS) untouched — which is why this works where an allow-only cloud firewall does not. The IPv6
   line is belt-and-braces: Hetzner documents no IPv6 metadata endpoint and the service is IPv4-only at
   `169.254.169.254`, so the rule matches nothing today, costs one line, and avoids leaving the
   documented-gap the repo's other v6 handling has to warn about. Root is exempt so cloud-init's own
   datasource — which queries the metadata server every boot, as root, to configure networking — is
   unaffected.
3. Inline the systemd unit at `0644 root:root`: `Type=oneshot`, `RemainAfterExit=yes`,
   `After=`/`Wants=network-online.target`, `WantedBy=multi-user.target`, and a `SyslogIdentifier` without
   the `.sh` suffix (the `#6617c` lesson from the inngest unit, where the basename-derived tag matched no
   Vector source and the failure never left the host).
4. A `runcmd` item after the `gc_timer` block enabling the unit with rc capture and a
   `stage:nftables_metadata` **warning** emit on failure (D3) — never a bare `|| true`, which would make
   the failure unobservable.
5. Re-run `git-data-userdata-budget.sh`. If headroom is insufficient, stop and re-shape before committing.
6. Record the **new** template sha256 in the PR body, so the evidence-invalidation is explicit.

### Phase 5 — Item C: route the warning stages

1. New `sentry_issue_alert` per D4, with an unused `frequency`.
2. Ship the **first** git-data stage-reconciliation guard (R12), modelled on
   `nic-wait-gate.test.sh:506-527`: for each of `betterstack_ingest` and `nftables_metadata`, assert the
   stage is a live `tagged_event` value in `issue-alerts.tf` — anchored on the HCL attribute construct, not
   a bare token, since both names also appear in prose in both files
   (`cq-assert-anchor-not-bare-token`) — **and** that the emitter actually emits it. Lockstep in both
   directions.

### Phase 6 — Item D: the two stale-prose corrections

1. `plugins/soleur/test/terraform-target-parity.test.ts`, `GIT_DATA_BIRTH_TARGET_BASES`: the
   `doppler_secret.git_data_ssh_host` comment claims it "Publishes GIT_DATA_SSH_HOST from a STATIC local,
   never from `hcloud_server_network.git_data.ip`". `git-data.tf:274` is
   `value = hcloud_server_network.git_data.ip`, which is what ADR-149's DC-5 **reversal** mandates. Correct
   the comment to match code and ADR, including its now-backwards final sentence. Sweep the sibling instance
   in the `OPERATOR_APPLIED_EXCLUSIONS` comment, which repeats the same false "static local" claim.
2. `tests/scripts/lib/git-data-host-birth-gate.sh:411`: the ABORT text says "each of the four entailed
   members" and "All four are entailed" while the loop at `:402-405` deliberately carries **three**;
   `hcloud_firewall_attachment.git_data` is handled by the separate outcome assertion at `:469-501`, as
   `:399-401` already says. Make the message match the loop **without changing the loop**. Sweep the same
   stale four at `:30` and `:52`. The PASS line at `:503` is already correct and is the model.

### Phase 7 — Records

1. ADR-198 amendment (four parts, above).
2. `model.c4` `betterstack` description: two sources, git-data on its own; run the C4 tests.
3. Amend the 2026-07-18 learning (R2).
4. Comment on #7772: Item E's re-stated disposition, the ADR-198 fourth-item triage-out with the
   once-per-instance finding, and the corrected Item A reasoning.
5. A new learning for the R1/R2 class (a suffix-variant sibling credential made a capability look blocked)
   is a `/compound` candidate at ship time, not a plan deliverable.

### Phase 8 — Verification and ship

Full battery, budget re-measure, `terraform validate` on both roots, C4 tests, a `plan`-only assertion that
no git-data resource is reachable by the per-merge apply, then the ship lifecycle. Arm auto-merge and sync on
BEHIND rather than hand-merging: `main` lands commits faster than a CI cycle and the CI Required ruleset is
`strict:true`.

---

## Acceptance Criteria

### Pre-merge (PR)

1. `bash apps/web-platform/infra/git-data-userdata-budget.sh` exits 0 and reports `stored` < 32768, with the
   measured value quoted in the PR body alongside the 13,132 B baseline.
2. `sha256sum apps/web-platform/infra/cloud-init-git-data.yml` differs from
   `241b47af28fee2951bad76d4c57f49d6220c21907d0b89b19c2bbdca08f7e08f`, and the new digest is quoted in the
   PR body. The template *must* change — Item B is a template change; this AC asserts the invalidation is
   deliberate and recorded, not accidental.
3. `test ! -e apps/web-platform/infra/git-data-rung2-boot-evidence.env`.
4. `git_data_rung2_user_data_sha256()` resolves exactly **9** payloads — unchanged, proving Item B added no
   `file()` binding. Sourcing `tests/scripts/lib/git-data-birth-readiness-gate.sh` and invoking it against
   the template returns rc 0 and a 64-hex digest.
5. The birth fan-out is unchanged at **20**: `grep -c "^\s*-target='"` over the `git_data_host_create` job
   returns 20, and `plugins/soleur/test/terraform-target-parity.test.ts` passes, including its
   partition-equation test with `entailed.length === 3`.
6. `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` passes with **≥ 75** cases and 0 failures,
   including the reworded arm 5.6a and the re-pointed arm 7.
7. `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` still contains exactly the 8 original members and contains neither
   `betterstack_logs_token` nor `betterstack_ingest_url`.
8. `bash apps/web-platform/infra/git-data-render-strip-parity.test.sh` passes unchanged (its `-eq 9` arm
   untouched, confirming D2).
9. The **rendered** `user_data` contains a `meta skuid != 0` drop for `169.254.169.254` inside a
   `table inet soleur_git_data` with `policy accept` — asserted against the render, not the source.
10. `grep -c '169\.254\.169\.254'` over the nine payload files returns 0, so git-data still makes no IMDS
    call of its own and the drop breaks nothing at boot.
11. Both `stage` values `betterstack_ingest` and `nftables_metadata` appear as live `tagged_event` filter
    values in `sentry/issue-alerts.tf` **and** are emitted by the cloud-init emitter — asserted in both
    directions by the new reconciliation guard.
12. The new `sentry_issue_alert` uses `fallthrough_type = "NoOne"` and a `frequency` not already present in
    `issue-alerts.tf`.
13. `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` and
    `bash tests/scripts/test-sentry-full-root-apply.sh` both pass (no `-target=` introduced).
14. `git grep -c 'STATIC local' plugins/soleur/test/terraform-target-parity.test.ts` returns 0, and the
    `doppler_secret.git_data_ssh_host` comment names `hcloud_server_network.git_data.ip`.
15. `grep -c 'four entailed\|All four are entailed' tests/scripts/lib/git-data-host-birth-gate.sh` returns 0,
    while the entailed loop still carries exactly 3 members.
16. `doppler secrets --project soleur --config prd_terraform --only-names` lists
    `GIT_DATA_BETTERSTACK_LOGS_TOKEN` and `GIT_DATA_BETTERSTACK_INGEST_URL` — **names only, never values**.
    This is the ADR-065 merge-time gate: without it the merge-triggered apply fails wholesale.
17. `terraform validate` exits 0 in both `apps/web-platform/infra` and
    `apps/web-platform/infra/rung2-rehearsal`.
18. No credential value appears in the diff, the PR body, or any job log. Asserted structurally rather than
    by grepping for the value (which would itself place it in a command): no file in the diff matches a
    24-char Better Stack token shape adjacent to a `BETTERSTACK` key, and `.playwright-mcp/` is absent from
    the diff.
19. `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass; the `betterstack` element
    description no longer asserts a single Logs source.
20. ADR-198 carries all four amendments and no longer lists the per-source token as rejected.
21. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0 over the full changed
    set — the gate's own invocation, not a hand-enumerated path list.
22. `bash scripts/test-all.sh` (TEST_GROUP=all) is green, or the run is reported skipped-for-contention with
    rc=4 rather than forced.

### Post-merge

23. #7772 carries three recorded dispositions: Item E re-stated against the unchanged allowlist, the ADR-198
    fourth-item triage-out with its re-evaluation trigger, and the corrected Item A reasoning. Closed by
    this PR via `Closes #7772` in the body.
24. No rehearsal dispatch is fired by this PR. The rung-2 rehearsal runs **after** this merges and its
    evidence lands in its own follow-up PR — a PR merges atomically, so evidence committed alongside the
    harness would attest a rehearsal that never ran.

---

## Observability

```yaml
liveness_signal:
  what: "stage:nftables_metadata absent on a healthy boot; stage:boot_complete present with its four booleans positive"
  cadence: "once per host birth (runcmd is once-per-instance); gc faults daily via git-data-gc.timer"
  alert_target: "sentry_issue_alert.git_data_boot_fatal (paging, nine fatal stages); the new low-severity rule (NoOne fallthrough) for the two warning stages"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf; apps/web-platform/infra/cloud-init-git-data.yml"
error_reporting:
  destination: "Sentry (baked DSN, no Doppler dependency) for fatals and the two warning stages; Better Stack Logs (new git-data source) for eight of the nine boot stages"
  fail_loud: "yes — a failed nftables load emits stage:nftables_metadata at warning and is routed by the new rule; a failed Better Stack POST already emits stage:betterstack_ingest, which this plan routes for the first time"
failure_modes:
  - mode: "nft rule fails to load (binary absent, kernel module missing)"
    detection: "in-host: the unit's ExecStart exits non-zero -> runcmd rc capture -> stage:nftables_metadata warning emit carrying the rc"
    alert_route: "the new low-severity sentry_issue_alert (IS_IN betterstack_ingest,nftables_metadata)"
  - mode: "the rule ships mis-scoped (drops for root, or matches nothing)"
    detection: "render-time: the Guard 2 mutation matrix reddens before any host exists"
    alert_route: "CI (infra-validation), not a runtime alert — this is the likely failure and it is caught pre-birth"
  - mode: "Better Stack ingest refused (401 after rotation, 402 quota, DNS/TLS)"
    detection: "the emitter's _bs_mirror posts stage:betterstack_ingest at warning with token_source and curl rc, never the token"
    alert_route: "the new low-severity sentry_issue_alert — closing the write-only gap this plan exists to fix"
  - mode: "the new no-default TF variables are unprovisioned at merge"
    detection: "apply-web-platform-infra.yml fails the whole root apply with 'No value for required variable'"
    alert_route: "the workflow run itself; prevented by AC16 before the branch is marked ready"
logs:
  where: "Better Stack Logs, new git-data source (team 520508), via scripts/betterstack-query.sh --table t520508_<new_table_name>_logs; Sentry issues for fatals and the two warning stages"
  retention: "90 days (matching source 2457081); Sentry 90 days rolling"
discoverability_test:
  command: "bash apps/web-platform/infra/git-data-userdata-budget.sh && grep -c 'meta skuid != 0' apps/web-platform/infra/cloud-init-git-data.yml"
  expected_output: "the budget line reporting stored < 32768, then '2' — the IPv4 and IPv6 drop rules"
  credentials_required: "none — both halves are local file reads. The live Better Stack read needs BETTERSTACK_QUERY_* from Doppler prd_terraform and has no unauthenticated substitute, so it is deliberately not the discoverability probe."
```

### Soak follow-through enrollment

Not applicable. No acceptance criterion is time-gated: there is no post-deploy soak, because the host this
change configures does not exist and will not exist when this merges. The first real signal comes from the
rung-2 rehearsal, a separate dispatch with its own evidence PR (AC24).

---

## Encryption Posture

```yaml
at_rest:
  - store: "Better Stack Logs — new git-data source (vendor-managed ClickHouse warehouse, eu-central-1a)"
    mechanism: "vendor-managed encryption at rest, EU-resident; no customer-managed key"
    evidence: "data_region=eu-central-1a confirmed via GET /api/v2/sources/<id>; identical posture to incumbent source 2457081"
    defends_against: "vendor-side disk theft or decommissioned-media recovery"
    does_not_defend: "anyone holding the ClickHouse read credential (BETTERSTACK_QUERY_*) reads every row; the ingest token itself cannot read anything back"
    disclosed_as: "operational telemetry, docs/legal/data-protection-disclosure.md (m); no new processing activity — content, vendor and region are unchanged, only the source partition"
    live_verification: "scripts/betterstack-ingest-probe.sh against the new URL (exit 0 = accepting)"
  - store: "/etc/default/git-data-betterstack on the git-data host"
    mechanism: "filesystem permissions only — 0600 root:root via write_files, on a PLAINTEXT ext4 root disk"
    evidence: "cloud-init-git-data.yml:113-118; ADR-198's mode table"
    defends_against: "a file-read primitive by the unprivileged git account (a path traversal in the transport wrapper, say)"
    does_not_defend: "code execution as root; and until this change, code execution as ANY account, because the same value is readable from the Hetzner metadata endpoint. Closing that is Item B — which is why this row moves toward 'defends' for non-root UIDs specifically"
    disclosed_as: "not user data; a write-only telemetry ingest credential"
    live_verification: "deferred to the rung-2 rehearsal, which boots the real template on a throwaway host"
in_transit:
  - connection: "git-data host -> new Better Stack ingest endpoint"
    tls: "TLS 1.2+ (https:// enforced; scripts/betterstack-ingest-probe.sh refuses any non-https betterstackdata.com URL)"
    cert_verification: "on (curl default; no -k anywhere in the emitter)"
    does_not_defend: "a compromised host can still forge rows into git-data's own stream — precisely the blast radius this change shrinks from four consumers to one"
    disclosed_as: "operational telemetry in transit, EU-to-EU"
  - connection: "CI/agent -> telemetry.betterstack.com (source management)"
    tls: "TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "the write-scoped BETTERSTACK_API_TOKEN can create and delete sources; it is never baked into user_data and never leaves Doppler prd_terraform"
    disclosed_as: "vendor management API, not a data path"
exception: none
```

The change **improves** posture on the axis that matters: today one ingest credential is baked into the
lowest-trust host in the fleet and shared with three others; after this, git-data's copy authorizes appends
to git-data's own stream alone.

---

## Guard Contract

### Guard 1 — Stage⇔route reconciliation (the first for git-data)

**Property.** Every `stage` value the git-data emitter can emit is either matched by a `tagged_event` filter
in `sentry/issue-alerts.tf` or is deliberately and namedly exempt — and every stage a filter names is
actually emitted.

**Assembly.** Not the list of current stages, which drifts. The chokepoints are (a) every
`git-data-emit … <stage> …` call site **plus** the two inline `curl` mirrors in `cloud-init-git-data.yml`
(the `bootcmd` beacon and `_bs_mirror`), which do **not** route through the emitter binary and are exactly
the sites a call-site-only sweep misses; and (b) every `value = "<stage>"` attribute inside a `filters_v2`
block in `sentry/issue-alerts.tf`. The guard quantifies over both directions of that pair. There is more
than one emit chokepoint, and a guard scoped to only the emitter binary would be the defect.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Delete the `betterstack_ingest` filter value from `issue-alerts.tf` | An emitted stage matching no rule is the write-only class the guard exists to end |
| 2 | Add a new emit at a stage with no filter, **after** a compliant one | A guard that stops at the first stage cannot see the second — the recurring defect class |
| 3 | Rename `nftables_metadata` in the cloud-init but not in `issue-alerts.tf` | Lockstep must break in both directions, not only on deletion |
| 4 | Make the guard's own loop iterate zero stages (empty the extracted set) | A guard reporting "0 checked" and exiting 0 is vacuous; the anti-vacuity floor must fire |
| 5 | Replace a `filters_v2` `value = "betterstack_ingest"` line with the same token in a **prose comment** | Asserting on a bare token rather than the HCL attribute construct is `cq-assert-anchor-not-bare-token`; prose must not satisfy the guard |

**Harness rows.** (a) Stub the extraction so it returns the canonical set regardless of file content — the
suite must red, proving it reads the real files rather than a constant. (b) A must-PASS input that is **not**
the canonical: an `issue-alerts.tf` carrying an additional unrelated alert with its own stage filter must
still pass, since the contract permits extra rules and forbids only unrouted emits.

### Guard 2 — The metadata drop is present, UID-scoped, and in the render

**Property.** The `user_data` Hetzner actually receives contains a drop of traffic to the metadata endpoint
that applies to non-root UIDs and does not apply to root.

**Assembly.** The **rendered** template (`templatefile` + the template strip), not the source YAML — the
strip expression removes comment lines, so a rule sitting inside a comment passes a source grep and ships
nothing. The chokepoint is the render produced by `git-data-userdata-budget.sh`'s pipeline, or the
equivalent `terraform console` render the parity suite already drives.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Drop the `meta skuid != 0` qualifier, leaving a blanket drop | Root must stay exempt — cloud-init queries the metadata server as root every boot to configure networking; a blanket drop breaks the datasource |
| 2 | Change `policy accept` to `policy drop` | The table must not become a default-deny egress firewall; that is the brittle CDN-allowlist shape this design explicitly rejects |
| 3 | Move the rule from an active line into a `#` comment line | The template strip deletes comments, so this is the mutation a source-level grep cannot see — the discriminating case |
| 4 | Rename the table to collide with `soleur_inngest` or the shared `filter` table | `nft -f` replaces a table atomically; colliding would flush a table this host does not own |
| 5 | Remove `nftables` from `packages:` | The script's `command -v nft` preflight fails every boot, silently reducing the control to a warning emit |

**Harness rows.** (a) Point the guard at a fixture render containing the rule but assert against an empty
string — it must red, proving the assertion is not vacuously true. (b) A must-PASS non-canonical: a render
expressing the rule with different whitespace plus an unrelated accept rule in the same chain must still
pass, since the contract is presence-and-scoping, not byte-equality.

### Guard 3 — The per-source split did not weaken the rung-2 evidence

**Property.** After the split the rehearsal still binds the same render inputs it bound before: the
divergence allowlist is unchanged at 8 identity-shaped members, both roots declare the token with no
default, and the two roots resolve the **same** ingest URL.

**Assembly.** The four enforcing arms in `git-data-rung2-rehearsal.test.sh` (5.6a allowlist-absence, 7 URL
value-equality, 72 Doppler residency, 74/75 both-roots parity) plus
`GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` in `git-data-birth-readiness-gate.sh` — read as a *set* across every
assignment, not the first match, because shell assignment is last-wins and a `+=` append would evade a
first-line read.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Append `betterstack_logs_token` to the allowlist via `+=` rather than reassignment | D1's whole claim is that no widening is needed, and the `+=` form is the one arm 5.6a was specifically hardened against |
| 2 | Give either root a `default` for the token | A default is a silent fallback to a different sink, producing hash-valid evidence for a boot prod would not get |
| 3 | Point the rehearsal root at 2457081 while prod uses the new source | The rehearsal would attest a channel prod does not use — the accepted-limitation arm D1 rejects |
| 4 | Re-point arm 7 back to `zot-registry.tf` | It would compare the *registry's* URL against the rehearsal default: a green arm silently comparing the wrong pair |

**Harness rows.** (a) Lower the suite's anti-vacuity floor below the real case count — the suite must red on
its own floor. (b) A must-PASS non-canonical: reordering the allowlist's 8 members must still pass, since
the contract is set membership, not string equality.

---

## Domain Review

**Domains relevant:** engineering

All eight domains were assessed semantically against the plan content. This is an infrastructure and
security change to an unborn internal host: no user-facing surface, no pricing or positioning change, no new
vendor relationship, no new processing activity, no support surface.

### Engineering

**Status:** reviewed
**Assessment:** The change sits squarely in the CTO/infra lane and its risks are the ones this plan's gates
enumerate — a ForceNew template edit that must land before the next paid rehearsal, a no-default variable
against an auto-applied root, and a first-of-its-kind nftables idiom (`meta skuid`, `hook output`) with no
repo precedent. The mitigations are the measured byte budget (19,636 B headroom), the ADR-065
Phase-1-before-Phase-2 ordering (AC16), the fail-open D3 placement, and Guard 2's render-level mutation
matrix. The design minimizes blast radius twice: inline over a 10th payload (six gate files not touched), and
a value change over a new address (fan-out cardinality untouched).

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Edit` and `## Files to Create` matched no
path under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`, and the change creates no user-facing
surface. Tier: NONE.

**Brainstorm-recommended specialists:** none — no brainstorm preceded this plan (direct one-shot entry).

### GDPR / Compliance Gate

Assessed and **not invoked**. The canonical regulated-data regex does not match (no schema, migration, auth
flow, API route, or `.sql` file), and none of the four expansion triggers fire: (a) no LLM or external-API
processing of operator-session-derived data is added — the Better Stack change re-partitions an existing
telemetry stream between two sources at the same vendor, in the same EU region, with the same content and
retention; (b) the `single-user incident` threshold does fire, and is handled by CPO sign-off plus
`user-impact-reviewer` at review rather than by a compliance write; (c) no new cron or workflow reads
`learnings/` or `specs/`; (d) no new artifact distribution surface. The existing Article 30 record and
`data-protection-disclosure.md` (m) already cover git-data boot telemetry; splitting a source creates no new
processing activity and does not change the processor. Recorded so the omission is deliberate.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A no-default variable is unprovisioned at merge, failing the **whole** `apps/web-platform/infra` apply and wedging unrelated changes | Low | High | Phase 1 strictly precedes Phase 2; AC16 asserts both Doppler names exist before the branch is ready. This is ADR-065's exact failure mode, and it is why the credential being obtainable in-session (R1) matters — no PR split is needed. |
| The nftables rule breaks something at boot that the grep did not predict | Low | Critical (unrepairable host) | Three independent checks: `grep -c` returns 0 across the template and all nine payloads; the only known IMDS consumer is cloud-init's own datasource, which runs as **root** and is exempt by `meta skuid != 0`; and D3 places the unit outside the `set -e` region so a failure warns rather than aborting `runcmd`. |
| The template edit lands after a rehearsal PASS, invalidating the evidence | Low | Medium (a second paid host + approval) | This is the entire reason for one PR. AC3 asserts the evidence file is absent; AC2 records the new digest so the invalidation is explicit; AC24 forbids firing a dispatch from this PR. |
| A credential value reaches a job log, artifact, or the public diff | Low | Critical | stdin-only piping; status-codes-only probes; `GET /sources` bodies never printed (they contain every source's token); AC18 asserts the structural property. The rung-2 runbook already warns its artifact redaction is a name-allowlist over a whole Doppler config and should be treated as sensitive. |
| Arm 7 silently compares the wrong pair after the split | Medium | Medium | Guard 3 mutation row 4 makes exactly this mutation red. |
| Better Stack quota exhaustion (the 2026-08-14 402 outage) worsens with a second source | Low | Medium | git-data's volume is ~9 lines per boot plus gc faults. Retention pinned to 90 days, matching the incumbent. `betterstack-ingest-probe.sh` is the live accepting/refused check; the vendor exposes no usage endpoint. |
| The new Sentry rule collides with Sentry's create-time dedup | Low | Low | An unused `frequency` (AC12), per the 2026-05-17 learning. |
| ADR ordinal collision | None | — | No new ADR is created; ADR-198 is amended. The highest ordinal across all 66 `origin/*` refs is **ADR-200**, recorded in case a reviewer requests a split — in which case re-derive immediately before merge, never from this number. |
| Sibling worktrees contend on `TEST_GROUP=all` (`/var/tmp`, rc=4) | Medium | Low | Report skipped-for-contention rather than forcing an untrustworthy run (AC22). |

---

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Hetzner Cloud Firewall egress rule** for the metadata endpoint | Three independent vendor-documented blockers (R4): rules are allow-only, there is no UID matching, and the firewall *always* allows the cloud metadata server. Expressing it would require allow-listing every other egress destination — brittle CDN ranges, which is exactly why `cron-egress-nftables.sh` needs a CIDR refresh loop. |
| **A 10th `file()` payload** for the nft script | D2 — six gate/mirror sites hard-code the payload count 9, each a chance to wedge the birth route, for no property the inline form does not buy. |
| **Playwright MCP mint** for the Better Stack source | Cut at Phase 0.6b: an already-provisioned write-scoped REST credential buys the property outright (R1), and `hr-exhaust-all-automated-options-before` prefers the API. Retained only as a documented fallback. |
| **Keep the rehearsal on the shared sink** and accept that it no longer attests prod's channel | D1 — strictly worse: it forfeits the rehearsal's purpose *and* would require widening the closed allowlist, which arm 5.6a refuses outright. |
| **Widen `git_data_boot_fatal`** to include `betterstack_ingest` | It is the fatal router; adding a warning stage is a paging-policy change (the issue says so, ADR-198 says so, and R8 explains the mechanism). A separate `NoOne`-fallthrough rule is the issue's own option 1. |
| **Ship ADR-198's fourth item** (boot refresh of the baked env file) | Triaged out: the proposed once-per-instance mechanism cannot deliver its own benefit (R5), a per-boot variant trades a narrow win for a boot-path write whose failure darkens eight stages, and Item A collapses the residual. |
| **Close #7772 item 3** (bind render-arg values into the evidence) | Item E — not a birth blocker, and unimplementable without the suite reading a secret at apply time. Recorded with a re-evaluation trigger rather than skipped silently. |

---

## Test Scenarios

Every scenario is `mutation -> guard reddens`, not `command -> terminal output`, because the deliverable
includes guards.

1. Append `betterstack_logs_token` to `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` with `+=` → arm 5.6a fails.
2. Give `rung2-rehearsal/variables.tf` a `default` for `betterstack_logs_token` → arm 75 fails.
3. Point the rehearsal root's ingest URL at 2457081 while prod uses the new source → arm 7 fails.
4. Re-point arm 7's prod extraction at `zot-registry.tf` → against a fixture where the two URLs differ, the
   arm must fail rather than silently compare the wrong pair.
5. Remove `meta skuid != 0` from the nft rule → Guard 2 row 1 fails.
6. Move the nft rule into a `#` comment line → Guard 2 row 3 fails against the **render**, while a naive
   source grep would still pass. This is the discriminating case.
7. Change the nft chain policy to `drop` → Guard 2 row 2 fails.
8. Remove `nftables` from `packages:` → Guard 2 row 5 fails.
9. Delete the `betterstack_ingest` filter value from `issue-alerts.tf` → Guard 1 row 1 fails.
10. Add an emit at a brand-new stage with no filter, after a compliant one → Guard 1 row 2 fails.
11. Empty Guard 1's extracted stage set → its anti-vacuity floor fails.
12. Add a `file()` payload to `modules/git-data-userdata/main.tf` → the payload count moves to 10 and AC4
    fails, proving the count assertion is live rather than decorative.
13. Add a 21st `-target=` to `git_data_host_create` without touching the gate → `terraform-target-parity`
    fails on both the set-equality and the partition-equation tests.
14. Reorder the allowlist's 8 members → Guard 3 must-PASS row: the suite still passes.
15. Add an unrelated `sentry_issue_alert` with its own stage filter → Guard 1 must-PASS row: still passes.

---

## Files to Edit

- `apps/web-platform/infra/variables.tf`
- `apps/web-platform/infra/git-data.tf`
- `apps/web-platform/infra/git-data-luks.tf`
- `apps/web-platform/infra/cloud-init-git-data.yml`
- `apps/web-platform/infra/git-data-userdata-budget.sh`
- `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`
- `apps/web-platform/infra/rung2-rehearsal/variables.tf`
- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `tests/scripts/lib/git-data-host-birth-gate.sh`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-198-baking-the-better-stack-ingest-token-into-git-data-user-data.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/project/learnings/workflow-patterns/2026-07-18-playwright-evaluate-filename-allowed-roots-and-token-transcript-fallback.md`

## Files to Create

- `apps/web-platform/test/sentry-git-data-warning-stages-op-contract.test.ts` — the Guard 1 reconciliation
  suite, the first for git-data. `apps/web-platform/vitest.config.ts` collects `test/**/*.test.ts`, so this
  path is inside the runner's discovery glob; a co-located test would be silently skipped.

**Deliberately NOT edited:** `apps/web-platform/infra/zot-registry.tf`,
`apps/web-platform/infra/modules/git-data-userdata/main.tf`,
`apps/web-platform/infra/git-data-render-strip-parity.test.sh`,
`tests/scripts/lib/git-data-birth-readiness-gate.sh`,
`.github/workflows/apply-web-platform-infra.yml`, `.github/workflows/git-data-rung2-rehearsal.yml`, and
`apps/web-platform/infra/git-data-rung2-boot-evidence.env` (which must not exist). Each omission is a design
choice recorded above (D1, D2, R6), not an oversight.

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. It is filled above with a concrete artifact and a concrete
  exposure vector.
- **The template hash changing is the point, not a defect.** AC2 asserts it changed and records the new
  digest. Do not "restore" the old hash.
- **Do not create `git-data-rung2-boot-evidence.env`.** It is produced by a rehearsal run, and committing it
  alongside its own harness would attest a rehearsal that never ran.
- The four non-git-data Better Stack consumers must stay on 2457081. A well-meaning sweep that re-points
  `local.betterstack_logs_ingest_url` would move the web hosts and the registry onto git-data's source and
  break `fresh-boot-ready.test.sh` S9.
- `git-data-emit`'s stage vocabulary is a closed set that two independent files must agree on. Adding
  `nftables_metadata` without the matching filter re-creates the write-only class in miniature — which is
  what Guard 1 exists to prevent, and why D4 folds it into the same rule.
- The rehearsal suite's arm 7 reaches into `zot-registry.tf` **by filename**. After D1 that file is no
  longer git-data's source of truth, and an arm left pointing at it stays green while comparing the wrong
  pair. Re-point it; do not delete it.
