---
title: "feat: Re-establish jikigai.com as a Terraform-managed Cloudflare zone"
date: 2026-09-09
slug: feat-jikigai-cloudflare-zone-terraform
branch: feat-one-shot-jikigai-cloudflare-zone-terraform
type: enhancement
lane: cross-domain
domain: engineering
priority: p1-high
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

> **DEFERRED 2026-09-09 (#7995 / PR #7989) — do not execute Phases 1-8.**
> Phase 0.4 could not be cleared: the registrar login needs a Squarespace
> credential that exists in no Doppler config. Per this plan's own gate and
> AC15a, no Terraform may be written or merged until it is, because task 1.2
> (`POST /zones`) starts Cloudflare's 28-day pending-zone clock — the exact
> mechanism that deleted the zone. PR #7989 shipped only the unblocked subset
> (the two dead Resend alert paths, the domains-ledger row, and the Art. 32
> withdrawal). Everything else is tracked in #7995.

Cloudflare deleted the jikigai.com zone. The mechanism is documented and matches
the symptom exactly: a free-plan zone that stays in `pending` — because the
registrar nameservers were never repointed at Cloudflare — is auto-deleted after
28 days. "Removed after four weeks" is that policy firing, not an anomaly.

This plan re-establishes the zone as Terraform-managed infrastructure, with the
zone itself **created by Terraform** rather than referenced through a hardcoded
id, carrying the complete Proton Mail record set as code. It then sequences the
nameserver cutover so that corporate mail never stops being deliverable.

Mail continuity is the acceptance criterion. Zone existence is not. `ops@jikigai.com`
is the only alert channel this infrastructure has, and `legal@jikigai.com` is the
published route for statutory data-subject requests — so a botched cutover does not
degrade anything, it silently removes the company's ability to hear either its own
alarms or its regulator-facing correspondence.

## Research Reconciliation — Brief vs. Probed Reality

Every row below was probed live on 2026-09-09. Three of them change the plan's shape.

| Claim as briefed | Probed reality | Plan response |
|---|---|---|
| Zone removed because NS were never repointed | Confirmed, and the mechanism is named: free-plan pending zones are deleted at 28 days ([Cloudflare domain-status reference](https://developers.cloudflare.com/dns/zone-setups/reference/domain-status/)) | The 28-day clock is now an explicit deadline the plan defends, not a background fact |
| Registrar NS are the four `ns-cloud-c*.googledomains.com` | Confirmed verbatim; parent NS TTL 172800 | Rollback target; the Google-side zone must survive until cutover is proven |
| Record set listed is "the whole zone" | **Not quite.** All briefed records confirmed verbatim (all three DKIM CNAMEs share selector `dlsyxrjkwef5bwihl4fgmgswd2heglj7tta7o4qqc2h72lmdfbllq`), but a widened sweep found a tenth name the brief omits: `_domainconnect` CNAME -> `_domainconnect.domains.squarespace.com`. Separately, `resend._domainkey` and `send.jikigai.com` are **absent**, and `GET https://api.resend.com/domains` lists no verified domain **[2026-09-09 CORRECTION (#7995 / PR #7989): this probe never supported that claim. The `RESEND_API_KEY` in `prd_terraform` is send-only and answers that endpoint `401 restricted_api_key` (control: an invalid key answers 400, so the 401 is a real scope response). The conclusion is re-established from key-independent DNS instead — `resend._domainkey.jikigai.com` and `send.jikigai.com` both resolve empty, while the soleur.ai equivalents carry a DKIM key and the SES bounce records.]** | Records transcribed from dig output. `_domainconnect` is deliberately dropped (see R8). The Resend absence is a live pre-existing defect — see F1 below |
| **(absent from brief)** | **jikigai.com is DNSSEC-signed.** `.com` publishes DS `26851 8 2 818EBD7D35A304518B7DE3574F4B885977CE1618977DBFEF01161455C571602D`, DS TTL 86400. `dig @1.1.1.1 MX jikigai.com` returns the `ad` flag | **Shape change.** The briefed 3-step sequence would SERVFAIL the whole domain at every validating resolver. A DS-retirement phase is inserted before the NS flip — see the Cutover Runbook |
| jikigai.com is not in Terraform | Confirmed. No `cloudflare_zone` resource exists anywhere in the repo; soleur.ai is referenced by `var.cf_zone_id` only | This is the repo's first Terraform-created zone — a new API surface for the credential |
| **(absent from brief)** | **No existing Cloudflare token can create a zone.** **[2026-09-09 CORRECTION (#7995 / PR #7989): NOT ESTABLISHED — withdrawn as an assertion. Three probe variants over all 11 `CF_API_TOKEN*` secrets each returned a UNIFORM verdict (`1002 Invalid domain` for every token, then `1068 Permission denied` for every token), including for Pages- and bot-management-scoped tokens that plainly cannot create zones. Cloudflare validates the domain name before authorization, so `POST /zones` cannot answer this non-destructively. Recorded as unresolved rather than reported as either uniform result. The ephemeral-admin-token design stands on least-privilege grounds independently of it, but do NOT provision a credential on the strength of this row.]** `CF_API_TOKEN`, `CF_API_TOKEN_DNS_EDIT` and `CF_API_TOKEN_AUDIT` each list exactly one zone (soleur.ai); the first two return zero accounts. Zone creation requires account-scoped `com.cloudflare.api.account.zone.create` | **Shape change.** A new account-scoped token is a precondition, minted before the IaC merges (ADR-065 sequencing) |
| `apps/web-platform/infra/` is the incumbent root | Confirmed, and it is `-target=`-scoped with ~110 entries plus three guard suites. Its merge-apply resolves **every** root variable before `-target` pruning | **Shape change.** A new no-default variable there would fail the entire production apply. New root instead — see ADR-214 |
| Squarespace has no public API for this | Confirmed: no domains/DNS/nameserver endpoint in the developer platform, no Terraform provider. **But** this is a claim about the API rung only — it is not evidence about the Playwright rung, which remains unattempted |
| `cloudflare_zone_dnssec` supports multi-signer | **False for the pinned provider.** Schema dumped locally from cloudflare/cloudflare **4.52.7**: the resource takes only `zone_id` and computes `ds`/`digest`/`key_tag`/`algorithm`. No `dnssec_multi_signer`, no `dnssec_presigned`, no settable `status` | Cloudflare's official multi-signer migration path is unavailable without a provider major bump. The DS-retirement path is taken instead |
| — | **No `cloudflare_registrar_domain` resource exists in 4.52.7 at all** | Registrar transfer is wholly outside Terraform here; it cannot be an in-scope IaC deliverable |

### Two defects this planning session found that predate the change

**F1 — Two alert paths are already dead, and fail silently.**
`apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` and
`cron-github-app-drift-guard.ts` both post to the Resend API with
`from: "ops@jikigai.com"`. Resend only sends from a verified domain, and jikigai.com
carries no Resend records (`resend._domainkey` and `send.jikigai.com` both resolve empty)
and does not appear in `GET /domains`. Neither call checks the response, so the rejection
is discarded — `cq-silent-fallback-must-mirror-to-sentry`. These two paths have been dead
independently of DNS. The four shell monitors are unaffected on the send leg: they send
`from: noreply@soleur.ai` `to: ops@jikigai.com`, so only their *inbound* leg depends on
this zone. This corrects the brief's framing and this plan's first draft — see the
revised User-Brand Impact.
*Disposition:* not folded into this PR (different file class, no `.tf` change). File as a
`type/chore` + `domain/engineering` issue and land the one-line `from:` correction as a
separate fast PR ahead of the cutover, since it repairs an alert channel this plan depends on.

**F2 — `knowledge-base/operations/domains.md` has no jikigai.com row.** It lists exactly
one domain, soleur.ai. The registrar, renewal date and nameservers for jikigai.com are
recorded nowhere in the repo. That absence — not Cloudflare's 28-day timer — is the
reason a pending zone died unobserved for a month. Adding the row is the cheapest fix in
this plan by an order of magnitude and is **in scope**, landing before the infrastructure work.

**F3 — The Article 30 register asserts a technical measure for a file that does not exist.**
PA-15 §(g)(4) in `knowledge-base/legal/article-30-register.md` records, as a published
Art. 32 TOM: *"DNS verification record managed in Terraform (`apps/web-platform/infra/jikigai-com.tf`):
narrow aliased `cloudflare.jikigai_com` provider backed by a `Zone:DNS:Edit on jikigai.com`-only
API token."* `apps/web-platform/infra/jikigai-com.tf` does not exist. The register documents a
control that was never implemented, and it prescribes a root placement this plan changes.
Both limbs must be reconciled in this PR — see §Cross-artifact reconciliation.

## Research Insights

### Premise Validation (Phase 0.6)

The brief cites no `#N` issue references, so there are no external issue premises to
re-verify. Every *factual* premise it does assert was re-probed rather than inherited,
and the results are in the reconciliation table above: seven claims held verbatim, and
three were incomplete in a way that changes the plan's shape (DNSSEC delegation,
credential scope, provider capability). The brief's own instruction to "re-dig to confirm
each verbatim" for the DKIM CNAMEs was followed; all three matched.

One premise was **not** verifiable and is carried forward as an open risk rather than a
fact: whether DS-record *removal* at Squarespace is customer-self-service or requires a
support ticket. Squarespace documents DS *addition* for custom-nameserver domains and is
silent on removal.

### Cross-artifact reconciliation (obligatory — three committed artifacts prescribe a different design)

Three committed artifacts already say where jikigai.com's Terraform lives, and all three
predate this plan. Leaving them stale would mean the next reader implements against a
prescription this plan has superseded.

| Artifact | What it prescribes | Reconciliation |
|---|---|---|
| `knowledge-base/legal/article-30-register.md` PA-15 §(g)(4) | `apps/web-platform/infra/jikigai-com.tf`, aliased `cloudflare.jikigai_com` provider, `Zone:DNS:Edit on jikigai.com`-only token | Amend §(g)(4) to name the new root. **Keep the token clause verbatim** — the register independently arrived at the same zone-scoped credential this plan now adopts, which is corroboration, not conflict. Note the measure was never implemented |
| `knowledge-base/project/plans/2026-06-15-feat-agent-native-outbound-email-pilot-plan.md` | `CF_API_TOKEN_JIKIGAI` (DNS:Edit on jikigai.com), `provider "cloudflare" { alias = "jikigai" }` in the web-platform root; wants `mail.jikigai.com` DKIM/SPF/DMARC; names "onboard jikigai.com to Terraform/Cloudflare" as its prerequisite | Update to point at `infra/jikigai-dns/`. This plan **satisfies its prerequisite**, so say so |
| `knowledge-base/project/plans/2026-05-19-feat-linkedin-api-reapply-jikigai-plan.md` | a `_linkedin-challenge.<sub>.jikigai.com` TXT in Terraform | Update to point at the new root |

The convergence on a **zone-scoped** `Zone:DNS:Edit` token across the register, the
outbound-email plan, and this plan's revised credential design is the strongest single
signal that the account-scoped standing token in this plan's first draft was wrong.

### Property List (Phase 0.6b)

What this change must buy, stated as observable outcomes:

- **P1.** Mail addressed to `ops@` and `legal@jikigai.com` is deliverable at every point in time, including every intermediate state of the cutover.
- **P2.** The zone's record set is declared in version control, and a divergence between the declaration and what Cloudflare actually serves is detectable without opening a dashboard.
- **P3.** The zone cannot silently lapse again — the failure that caused this incident is either prevented or alarmed.
- **P4.** The registrar-side steps are executed by the highest rung of the automation ladder that actually works, and the rung reached is recorded as evidence rather than asserted.
- **P5.** Post-cutover state is verified by pulling data, not by asking anyone to look at an inbox or a dashboard.

### Cut List (Phase 0.6b)

Mechanisms considered and removed before any research was spent on them:

- **`cloudflare_zone_settings_override` for jikigai.com** → would buy nothing in P1-P5. There is no HTTP traffic on this domain; zone settings govern proxying, TLS and security features that a mail-only zone never exercises. Cut.
- **A `www` or apex A record, or a Pages project** → explicitly out of scope in the brief and buys no listed property. Cut.
- **A bespoke DNS-record drift detector** → P2 is already bought by an existing mechanism — but not the one first cited. `scheduled-terraform-drift.yml` is `workflow_dispatch`-only; the `{ cron: "0 6,18 * * *" }` schedule lives in `apps/web-platform/server/inngest/functions/cron-terraform-drift.ts` per ADR-033, which dispatches it. The cadence conclusion holds, but the matrix edit therefore carries a second dependency — a healthy Inngest dispatcher — and property P3 rests on it. The root only needs a matrix entry; grepped and confirmed the matrix is a hardcoded two-leg list at `.github/workflows/scheduled-terraform-drift.yml` (`- apps/web-platform/infra` / `- infra/github`). Cut the bespoke detector; add the matrix entry.
- **A bespoke `terraform fmt`/`validate` gate for the new root** → already bought. `infra-validation.yml` auto-discovers roots by walking `apps/*/infra` and `infra/*` (`find infra/* -maxdepth 0 -type d`), so a root at `infra/jikigai-dns/` is covered with no workflow edit. Verified by reading the detection step, not inferred from the glob. Cut.
- **A new Playwright automation for the Cloudflare token mint** → already bought. `plugins/soleur/skills/cf-token-scope/` drives Cloudflare token scope changes through Playwright MCP and ships the ADR-130 retained-scope probe. Reuse it; do not write a second one.

### Repo anchors

- `apps/web-platform/infra/dns.tf` — the Proton Mail record set for soleur.ai (`cloudflare_record.protonmail_verification`, `protonmail_mx_primary`, `protonmail_mx_secondary`, `protonmail_dkim_1..3`, `spf_root`, `dmarc`). This is the exact shape to mirror, including the `# Use FQDN, not "@"` comments and `proxied = false` on the DKIM CNAMEs.
- `apps/cla-evidence/infra/main.tf` — the canonical R2 backend block for a small standalone Cloudflare-only root, and the closest structural precedent for the new root.
- `apps/web-platform/infra/variables.tf` — the scope-ledger comment convention each Cloudflare token variable carries.
- `apps/web-platform/infra/uptime-alerts.tf` — `betteruptime_team_member.ops` (`email = "ops@jikigai.com"`), and the comment recording that the member is **inert until the invite is accepted**.
- `apps/web-platform/infra/{container-restart-monitor,disk-monitor,resource-monitor,cron-egress-alarm}.sh` — each sends `to: ["ops@jikigai.com"]` via Resend.
- `.github/workflows/apply-sentry-infra.yml` — precedent for a small separate root applied **full-root** (no `-target=`) with a destroy gate.
- `plugins/soleur/skills/cf-token-scope/` — Playwright-driven Cloudflare token scope change plus the ADR-130 probe.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — the `<!-- soleur:followthrough script=… earliest=… secrets=… -->` directive and its exit-code contract (0 PASS / 1 FAIL / 2 TRANSIENT / 3,5 NOTIFY-ONLY).

### Institutional learnings that bind this plan

- `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md` — never `name = "@"`; the API normalizes to FQDN and `name` is ForceNew, so every plan destroys and recreates. Apex records use the literal `jikigai.com`.
- `2026-04-28-protonmail-domain-verification-cloudflare-terraform.md` — verification TXT first, then MX/SPF/DKIM **atomically**. Splitting MX from DKIM opens a window where mail flows unsigned. Also: the Cloudflare anycast edge lags the API by tens of seconds after an apply, so the REST API is the source of truth for a fresh write and `dig` is the source of truth for what the world sees.
- `2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md` — `terraform plan` never calls the API for a resource absent from state, so a clean plan is fully compatible with a 403 apply. This is why the credential probe ran at plan time and not at apply time.
- `2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md` — absence from state is not evidence of absence in the world. Enumerate the live collection before the first apply.
- `2026-04-10-context7-terraform-provider-version-mismatch.md` — provider docs returned by research reflect the latest version, not the pinned one. This is precisely what happened here: the researched `cloudflare_zone`/`cloudflare_zone_dnssec` schemas were v5-shaped and wrong for 4.52.7. The schema in this plan came from `terraform providers schema -json` against 4.52.7.
- `2026-06-17-vendor-dashboard-mint-presumed-playwright-automatable.md` — an a-priori "operator-gated, dashboard-only" assertion is not evidence. A vendor dashboard action under an authenticated session is presumptively automatable until a real attempt reaches a *named* human gate.
- `2026-06-17-inbound-email-dead-was-proton-sieve-redirect-spf-break-not-egress.md` — mail paths fail silently and for reasons one layer away from where they are looked for.

### CLAUDE.md / AGENTS conventions in force

`hr-all-infrastructure-provisioning-servers` (DNS through Terraform), `hr-every-new-terraform-root-must-include-an` (R2 backend), `hr-tf-variable-no-operator-mint-default` (no default on the new token var), `hr-exhaust-all-automated-options-before` and `hr-never-label-any-step-as-manual-without` (the registrar rungs), `hr-technical-fork-is-not-an-operator-question` (the registrar decision), `hr-no-dashboard-eyeball-pull-data-yourself` (verification pulls data), `hr-verify-repo-capability-claim-before-assert`, `wg-architecture-decision-is-a-plan-deliverable` (ADR-214 ships with this plan).

## User-Brand Impact

**If this lands broken, the user experiences:** every production alert email —
container restarts, disk pressure, resource exhaustion, cron egress alarms, and every
Better Stack uptime and heartbeat notification — is accepted by Resend and Better Stack
and then discarded at the destination, with no bounce path anyone reads. The operator's
first evidence of an outage becomes the outage itself. `var.betterstack_paid_tier`
defaults to `false`, so email is not the primary channel — it is the **only** channel.

Two precisions this plan's first draft got wrong, both of which matter for severity:

- **There is currently no alert channel that is not on the domain being changed.** `git config user.email` is `jean.deruelle@jikigai.com`, so GitHub issue notifications — including the follow-through sweeper's comments — are delivered to the domain under test. `apps/web-platform/infra/uptime-alerts.tf` names the account owner `jean.deruelle@` alongside `ops@`, both on jikigai.com. And the product's own outbound chokepoint **explicitly rejects** `*@jikigai.com` (`docs/legal/data-protection-disclosure.md` §(ab) recipient allow-list), so it cannot serve as a fallback. In the exact failure this plan exists to prevent, every notification path terminates in the black hole and the only surviving channel is voluntarily opening github.com. **This is AC0 and it is a precondition, not a follow-through.**
- **Two of those paths are already dead** and this change does not cause it — see F1. The
  claim "email is the only alert channel" is true of the four shell monitors and Better
  Stack; it overstates what currently works for the two Inngest cron paths.
- **The DNSSEC failure mode is not the catastrophic one.** A validation failure yields
  SERVFAIL, which sending MTAs treat as temporary and queue against for 24-72h — mail is
  delayed, not lost. The permanent, bouncing failure is **NXDOMAIN or a NOERROR/empty MX
  answer**, which happens if Cloudflare answers authoritatively with an incomplete zone.
  So the mitigation priority inverts: **guaranteeing record-set completeness before the
  flip (Phase 6.4-6.7) is more load-bearing than the DS sequencing**, and the plan's
  strongest control is exact set equality, not the DNSSEC dance.

**If this leaks, the user's workflow is exposed via:** the new Cloudflare token is
account-scoped (`Zone:Zone:Edit` across all zones), which is strictly broader than every
credential currently in `prd_terraform`. A leak of that token permits creating, editing
and deleting zones account-wide — including soleur.ai, the production surface. The
exposure vector is the token's storage in Doppler `prd_terraform` and its appearance in
`terraform.tfstate` in the R2 backend.

- **Brand-survival threshold:** `single-user incident`

`requires_cpo_signoff: true` is set in frontmatter. `user-impact-reviewer` is to be
invoked at review time per `plugins/soleur/skills/review/SKILL.md`.

There is a second, non-brand limb the threshold does not capture on its own:
`legal@jikigai.com` is the published route for GDPR Article 12-22 requests across nine
documents in `docs/legal/`. A silent black-hole there does not merely lose mail — it
runs the Article 12(3) one-month response clock against a request that was never
received, with no signal to either party. See the Domain Review §Legal.

## Architecture Decision (ADR/C4)

Three architectural decisions ship with this plan, recorded in **ADR-214**
(`knowledge-base/engineering/architecture/decisions/ADR-214-corporate-dns-root-and-terraform-created-zones.md`).
The ordinal is **provisional**: it was verified free across all 81 `origin/*` refs
(highest claimed: ADR-213), but a sibling PR can claim it before merge, so `/ship`'s
ADR-Ordinal Collision Gate re-derives it — and any renumber must sweep this plan, the
tasks file, and every AC naming the ordinal in the same edit.

### ADR

**D1 — A corporate-identity domain gets its own Terraform root; it does not live in the product root.**

`infra/jikigai-dns/` is created rather than extending `apps/web-platform/infra/`.
The decisive argument is **deletion blindness under `-target=`**, documented in the header
of `.github/workflows/apply-sentry-infra.yml` (#6589, which fired twice — #4929 and #6074):
a `-target=`-scoped plan cannot name a resource whose HCL block has been deleted, so
removing a `cloudflare_record` block silently orphans the live record instead of deleting
it, with no drift signal ever. `apply-web-platform-infra.yml` carries 259 `-target=`
occurrences. For a zone whose failure mode is silent mail loss, an apply path where
deleting an MX or DKIM declaration leaves the record live and unmanaged forever is
disqualifying. A small root applied whole has no such blind spot.

*(This plan's first draft led with an ADR-065 argument — that a new no-default variable
would fail the whole production apply. That argument does not carry: ADR-065's own remedy
is sequencing, not root-splitting, and the variable is unavoidable in either root. It is
retained below only as a secondary consideration.)*

Three secondary arguments agree: a new no-default variable in the incumbent root does put its whole
merge-apply at risk until provisioned, which correct sequencing fixes but a separate root
also confines; the new root stays outside `plugins/soleur/test/terraform-target-parity.test.ts`,
which is scoped to `apps/web-platform/infra/*.tf`; and `infra-validation.yml` already
auto-discovers `infra/<name>/` roots (`find infra/* -maxdepth 0 -type d`), so fmt/validate
coverage is free.

The apply workflow is modelled on **`apply-github-infra.yml`**, not `apply-sentry-infra.yml`:
the github-infra pattern gates destruction with `[ack-destroy]` and registers no required
PR context, avoiding the always-run-aggregator and `merge_group:` apparatus that
`sentry-destroy-required` needs. That is the single largest complexity saving available here.

Alternative considered and rejected: adding to `apps/web-platform/infra/` (recommended by
one research pass). Rejected on the root-variable blast radius alone.

**D2 — The zone is a Terraform resource, not a hardcoded id.**

Unlike soleur.ai, which predates the IaC and is referenced through `var.cf_zone_id`,
jikigai.com does not exist and must be created. `cloudflare_zone.jikigai_com.id` is
consumed by reference throughout. `jump_start = false` is load-bearing: with jump-start
enabled Cloudflare scans the existing zone and imports records Terraform does not manage,
which is precisely the whole-list blind spot that
`2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md` documents.

**D3 — DNS delegation now; registrar transfer as a gated follow-through.**

Recorded in full under Alternative Approaches Considered. In short: transfer is
*downstream* of activation rather than an alternative to it, so the fork is not
either/or.

### C4 views

Read all three model files — `knowledge-base/engineering/architecture/diagrams/model.c4`,
`views.c4`, `spec.c4` — before concluding. A keyword grep for `jikigai` is **not**
sufficient evidence of no impact; the elements that matter here are named for vendors and
roles, not for the feature. Enumerate specifically:

- **External human actors** — the operator as alert recipient; a data subject sending a rights request to `legal@`. Are either modeled as actors reaching the system by email?
- **External systems** — Cloudflare (already modeled as CDN/DNS/edge for soleur.ai; does the model assert the DNS boundary covers one zone or the account?), Proton AG (mail custody), Resend (alert egress), Better Stack (alert origination), and now Squarespace Domains as the registrar of record. Squarespace is very unlikely to be modeled today and is a genuine new external system on the alert-delivery path.
- **Containers/data stores** — a new Terraform state object under the existing R2 state bucket.
- **Access relationships** — the alert path `host script → Resend → jikigai.com MX → Proton → operator` crosses a DNS boundary this change moves. If that edge is modeled at all, its DNS operator changes.

Where an element or edge is missing, adding it (element + `#external` tag if outside the
boundary + relationship edges + the `view … include` line in `views.c4` so it renders) is
an in-scope task of this plan. A "no C4 impact" conclusion must cite the actors, systems
and relationships checked and found already modeled — an unsupported "None" is a reject
condition. Additionally, because `model.c4` embeds derived cardinalities in edge prose
that `apps/web-platform/test/c4-count-parity.test.sh` gates as required context, a
"no impact" conclusion must also be backed by a green run of that script.

After any `.c4` edit run `apps/web-platform/test/c4-code-syntax.test.ts` and
`c4-render.test.ts` — a `view include` naming an undefined element fails there, not at `tsc`.

### Sequencing

ADR-214 is authored in this plan's PR with `status: adopting` for D3 (the registrar
transfer is true only after the follow-through closes) and `status: accepted` for D1/D2.

## Infrastructure (IaC)

### Terraform changes

New root `infra/jikigai-dns/`:

| File | Contents |
|---|---|
| `infra/jikigai-dns/main.tf` | `terraform` block with the R2 `backend "s3"` (key `jikigai-dns/terraform.tfstate`), `required_providers { cloudflare = "~> 4.0" }`, `required_version = ">= 1.6"`, and the `provider "cloudflare"` bound to `var.cf_api_token_zone_admin` |
| `infra/jikigai-dns/variables.tf` | `cf_account_id` and `cf_api_token_zone_admin`, both no-default and `sensitive`, each carrying a scope-ledger comment in the house style |
| `infra/jikigai-dns/zone.tf` | `cloudflare_zone.jikigai_com` with `jump_start = false` |
| `infra/jikigai-dns/dns.tf` | the eight `cloudflare_record` resources |
| `infra/jikigai-dns/dnssec.tf` | `cloudflare_zone_dnssec.jikigai_com`, added in the re-signing phase |
| `infra/jikigai-dns/outputs.tf` | `name_servers`, `zone_status`, `zone_id`, and the DS components — consumed by the verification probe |
| `infra/jikigai-dns/README.md` | the root's purpose and the cutover runbook pointer |

Provider version pin is `~> 4.0`, resolving to **4.52.7**, matching every other
Cloudflare-using root. The schema below was dumped from that exact version — not from
documentation:

```hcl
# cloudflare_zone (4.52.7): required = account_id, zone.  Computed = name_servers,
# status, meta, verification_key.  NOT v5's `name` / nested `account`.
resource "cloudflare_zone" "jikigai_com" {
  account_id = var.cf_account_id
  zone       = "jikigai.com"
  type       = "full"
  # false is load-bearing: jump-start imports CF-scanned records that Terraform
  # would not manage, creating exactly the whole-list blind spot the plan's
  # parity guard exists to detect.
  jump_start = false
}
```

Records mirror `apps/web-platform/infra/dns.tf` exactly, with apex names written as the
literal FQDN `jikigai.com` and the three DKIM CNAMEs `proxied = false`. `ttl = 1`
(Cloudflare "auto", 300s for unproxied records) is used throughout, matching the soleur.ai
precedent — and it is strictly better than the current 3600s for rollback latency.

Sensitive variables and their source:

| Variable | Source | Scope |
|---|---|---|
| `TF_VAR_cf_account_id` | Doppler `soleur/prd_terraform` → existing `CF_ACCOUNT_ID` | account identifier, not a secret |
| `TF_VAR_cf_api_token_zone_admin` | Doppler `soleur/prd_terraform` → **new** `CF_API_TOKEN_ZONE_ADMIN` | account-scoped `Zone:Zone:Edit` + `Zone:DNS:Edit`, "All zones from account" |

The token cannot be a `cloudflare_api_token` resource: `var.cf_api_token` lacks
"User API Tokens: Edit", which is why `cf_api_token_dns_edit` and `cf_api_token_pages`
are also externally minted.

**Correction to this plan's first draft:** it claimed `soleur:cf-token-scope` automates
this mint. It does not. Reading `plugins/soleur/skills/cf-token-scope/SKILL.md` shows it is
**widen-only** and hardcoded to `CF_API_TOKEN_RULESETS`, with a rulesets-specific probe set
and deliberately no `--token-var` knob. There is no token-*mint* path in this repo. The
claim is retracted (`hr-verify-repo-capability-claim-before-assert`), and the missing
capability is recorded under Capability Gaps.

**Precedent found — the repo already does this, and better.** `apps/cla-evidence/infra/iam.tf`
declares `cloudflare_api_token` resources under `lifecycle { prevent_destroy = true }`, and
`apps/cla-evidence/infra/bootstrap.sh` mints a one-hour account-admin token carrying
"User → API Tokens → Edit", uses it once, and **self-revokes it via the API at the end of the
run**. That is codified as `hr-multi-step-post-merge-bootstrap-script`. So the statement above —
"the token cannot be a `cloudflare_api_token` resource" — is true only of the *standing*
credential and is otherwise falsifiable; it is retracted.

**Adopt the bootstrap pattern.** It strictly dominates a Playwright mint: it puts the token's
scope under version control rather than in a browser transcript, it removes the standing
account-wide credential from Doppler entirely (which R3 admits it cannot otherwise mitigate),
it dissolves the ADR-065 gate behind Phase 1, and it lets the token be re-scoped to the single
zone once that zone exists. `cloudflare_api_token` is already in the encryption ledger's
`non_store_types`, so the type is supported here.

**Credential design — two phases, one persistent credential.** A standing account-scoped
`Zone:Zone:Edit` token would be strictly broader than every credential in `prd_terraform`:
it could rewrite soleur.ai's MX and Resend DKIM, and delete the soleur.ai zone outright.
That is not acceptable as a steady state, and ADR-130's #5092 note requires a zone-to-account
escalation to be stated and bounded rather than treated as routine. So:

1. Mint a **short-TTL (7-day expiry) account-scoped `Zone:Zone:Edit`** token.
2. Create the zone with a scripted `curl` to `POST /zones` — not a dashboard click
   (`hr-exhaust-all-automated-options-before`). Let the token expire on its own.
3. Mint the **persistent `Zone:DNS:Edit` token scoped to jikigai.com only**, now possible
   because the zone id exists.
4. Declare `cloudflare_zone.jikigai_com` in Terraform and **`import`** it, so Terraform
   manages and drift-detects the zone with no account-scoped credential persisting anywhere.

The persistent variable is therefore `cf_api_token_jikigai_dns` (zone-scoped), which is
exactly what `article-30-register.md` PA-15 §(g)(4) and the outbound-email plan already
independently prescribe. The ADR-065 exposure collapses with it: the only persistent
no-default var is zone-scoped and is minted before the IaC merges.

### Apply path

**(a) cloud-init-only is not applicable** — no host. The chosen path is a
**full-root apply from a dedicated workflow**, `.github/workflows/apply-jikigai-dns.yml`,
mirroring `apply-sentry-infra.yml`: `on.push` to `main` filtered to
`infra/jikigai-dns/**`, full-root `terraform plan` with no `-target=` (so a deleted
resource cannot be silently orphaned), a destroy-guard gate, and `workflow_dispatch` kept
as a re-run escape hatch. The PR merge is the authorization
(`hr-menu-option-ack-not-prod-write-auth`).

Expected downtime: **zero**. Creating a pending zone and populating its records changes
nothing about resolution while Google Cloud DNS remains authoritative. All risk is
concentrated in the registrar-side steps, which are sequenced separately in the Cutover
Runbook.

### Destroy-gate cap-coupling (a convention, not a single file)

`tests/scripts/lib/destroy-guard-filter-web-platform.jq` states the rule verbatim — *"A future
apply-* workflow MUST follow the same pattern: dedicated `destroy-guard-filter-<workflow>.jq`,
dedicated `test-destroy-guard-counter-<workflow>.sh`, CODEOWNERS rows"* — and
`destroy-guard-filter.jq` reinforces it: *"Do NOT generalize this filter; a future apply-*
workflow gets its own sibling."* Saying "a destroy-guard gate" is therefore not enough. Four
mechanisms are required:

1. `tests/scripts/lib/destroy-guard-filter-jikigai-dns.jq` — new.
2. `tests/scripts/test-destroy-guard-counter-jikigai-dns.sh` — new, and necessarily separate:
   the existing counter's `MIN_ASSERTIONS=8` is compared with `-ne`, so added rows redden it.
3. `tests/scripts/test-destroy-guard-regex-parity.sh` — its `EXPECTED_SITES=(…)` array is a
   hardcoded registry of every `[ack-destroy]` site and prints its own cardinality; the new
   workflow and its counter suite are two new rows.
4. **The required-status-check trio.** `apply-sentry-infra.yml`'s gate is unbypassable only
   because `sentry-destroy-required` is registered in `scripts/required-checks.txt`,
   `scripts/ci-required-ruleset-canonical-required-status-checks.json`, and
   `infra/github/ruleset-ci-required.tf`, held in lockstep by
   `plugins/soleur/test/required-checks-canonical-parity.test.sh`. Without an equivalent
   registration, nothing makes an unacknowledged destroy of `cloudflare_zone.jikigai_com`
   unmergeable — the single resource whose destruction re-creates this incident.

**Sequencing consequence the plan must own:** step 4 edits `infra/github/*.tf`, a *second*
Terraform root, applied by `apply-github-infra.yml`. This PR therefore touches two auto-applied
roots and both applies must be sequenced rather than raced.

**Inherit the `["forget"]` sharp edge** documented in the same filter: for a one-zone root,
`resource_deletes` must count `forget` as well as `delete`, or a state-drop of the zone passes
every gate.

### Distinctness / drift safeguards

- The root touches exactly one Cloudflare zone and holds no `dev`/`prd` split — there is
  one jikigai.com. No `dev != prd` precondition applies.
- `.github/workflows/scheduled-terraform-drift.yml` carries a **hardcoded two-leg matrix**.
  A third leg for `infra/jikigai-dns` is an in-scope edit; without it the root gets no
  scheduled drift detection at all. Note the workflow's `token_drift` step is gated
  `matrix.directory == 'apps/web-platform/infra'` and correctly skips on the new leg.
- State-storage note: the Cloudflare token value lands in `terraform.tfstate` in the R2
  backend. See Encryption Posture.
- `use_lockfile = false` matches every sibling root — R2 has no S3 conditional writes, so
  this root is single-writer-apply like the others. The dedicated workflow's `concurrency`
  group enforces that.

### Vendor-tier reality check

The zone is created on Cloudflare's **Free** plan. That tier carries the 28-day
pending-zone deletion policy that caused this incident, so the plan treats it as a
deadline rather than a footnote — see Risks R1 and the follow-through enrolment. No paid
tier is required for DNS, DNSSEC, or the record types in use. `betterstack_paid_tier`
remains `false` and is untouched by this change.

## Encryption Posture

```yaml
at_rest:
  - store: "R2 object soleur-terraform-state/jikigai-dns/terraform.tfstate"
    mechanism: "Cloudflare R2 server-side encryption (AES-256), provider-managed keys"
    evidence: "Same bucket and backend block as apps/cla-evidence/infra and infra/github; verify against Cloudflare's R2 data-security documentation at /work Phase 0 and cite the URL in the ADR"
    defends_against: "disclosure from physical media or a raw object-store read without a credential"
    does_not_defend: "anyone holding the R2 credential reads plaintext state, including the account-scoped Cloudflare token value; Cloudflare itself holds the keys, so it is not defended against Cloudflare or against a lawful-access order served on Cloudflare"
    disclosed_as: "Terraform state, existing R2 bucket — no new store class and no new vendor"
    live_verification: "the followthrough probe asserts the state object is not publicly readable without credentials"
in_transit:
  - connection: "Terraform (CI runner) -> Cloudflare API"
    tls: "TLS 1.2+ (api.cloudflare.com; HSTS-preloaded)"
    cert_verification: "on"
    does_not_defend: "a compromised CI runner reads the token from the environment before TLS is applied"
    disclosed_as: "existing pattern — identical to every other Cloudflare-managed root"
  - connection: "Terraform (CI runner) -> R2 state backend"
    tls: "TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "R2 credential compromise yields full state read/write"
    disclosed_as: "existing pattern"
  - connection: "public DNS resolution of jikigai.com"
    tls: "n/a — DNS is cleartext by design; DNSSEC provides integrity, never confidentiality"
    cert_verification: "n/a"
    does_not_defend: "an observer sees which names are queried; DNSSEC does not hide the zone contents, and the record set is public by construction"
    disclosed_as: "public DNS records"
```

No `exception` block: no store uses a plaintext exception and no connection runs with
certificate verification off.

## Observability

```yaml
liveness_signal:
  what: "jikigai.com MX/SPF/DKIM/DMARC answer correctly, and the Cloudflare zone reports status=active"
  cadence: "daily at 18:00 UTC — the sweeper's actual schedule is `cron: '0 18 * * *'`, verified, not every 6 hours. During the cutover the live signal comes from the cutover workflow's own gate steps, because a follow-through `earliest=` is a hard wall-clock gate evaluated BEFORE the script runs, so a flip+7d directive means the probe does not execute at all during Phases 5-8"
  alert_target: "GitHub issue comment on the cutover tracker (pre-close); infra-drift issue (steady state)"
  configured_in: "scripts/followthroughs/jikigai-dns-cutover-<issue>.sh and .github/workflows/scheduled-terraform-drift.yml"
error_reporting:
  destination: "GitHub issue on the tracker via the follow-through sweeper; workflow annotation + job failure on the apply workflow"
  fail_loud: "true — the probe exits non-zero on any record mismatch and the sweeper comments; there is no silent-pass arm. NOTE: routing to a GitHub issue is NOT independent of the domain under test — see AC0. Independence is established by the AC0 precondition, not by the routing choice"
failure_modes:
  - mode: "DS record still published at the parent while Cloudflare serves the zone (the DNSSEC trap)"
    detection: "probe compares `dig DS jikigai.com @a.gtld-servers.net` against the zone's NS delegation and against whether cloudflare_zone_dnssec is present in state"
    alert_route: "probe exit 1 -> sweeper comment on tracker; this is the highest-severity arm and is checked first"
  - mode: "zone deleted again by the 28-day pending policy"
    detection: "probe reads GET /zones?name=jikigai.com; zero results after a successful apply is the signature"
    alert_route: "probe exit 1 -> sweeper comment; also surfaces as a drift-cron plan proposing to recreate the zone"
  - mode: "a record exists in Cloudflare that Terraform does not declare (jump-start or dashboard edit)"
    detection: "the parity guard enumerates the LIVE record list and diffs against the declared set in both directions"
    alert_route: "guard exit 1 in CI on the apply workflow, before apply"
  - mode: "NS flipped but zone never activates (typo in one of the two nameservers)"
    detection: "probe asserts zone status == active AND that the parent delegation names exactly the two nameservers in `cloudflare_zone.jikigai_com.name_servers`"
    alert_route: "probe exit 2 (transient) for the first 72h, exit 1 thereafter"
  - mode: "DNS is perfect but Proton does not ACCEPT mail for the address — the domain was de-verified during the lapse, or the mailbox routing changed"
    detection: "SMTP-layer probe: MAIL FROM:<> / RCPT TO:<ops@jikigai.com> against mail.protonmail.ch:25, expect 250, QUIT before DATA. Repeat for legal@. PLUS a catch-all discriminator — RCPT TO: a deliberately non-existent local part must be REJECTED; if it is accepted the domain is catch-all and the 250 for ops@ proves nothing, so the probe degrades to a real round-trip rather than reporting a false pass"
    alert_route: "probe exit 1. This is the ONLY limb that verifies the property the plan actually cares about; every DNS-layer assertion is a proxy for it"
  - mode: "a validating resolver other than the one sampled still holds the retired DS"
    detection: "resolver panel — 1.1.1.1, 8.8.8.8, 9.9.9.9 and at least one known fail-closed resolver, sampled repeatedly by the cutover workflow so `sustained` is evidenced rather than asserted"
    alert_route: "cutover workflow gate step fails; the flip does not proceed"
  - mode: "Better Stack team member for ops@ is still pending (invite never accepted), so the alert path is dark for a reason unrelated to DNS"
    detection: "probe reads the Better Stack team-members API and asserts the ops@ member is not in a pending state"
    alert_route: "REPORTING-ONLY — printed as NOTICE to stdout, never influencing the exit code. A shell script returns one exit code, and routing this pre-existing condition to exit 3 would park the tracker in TRANSIENT forever, making the closure criterion unsatisfiable regardless of whether the cutover succeeded"
logs:
  where: "GitHub Actions run logs for the apply and sweeper workflows; no host, no container, no journald surface"
  retention: "GitHub default (90 days)"
discoverability_test:
  # SCOPED TO WHAT SHIPPED, 2026-09-09 (#7995 / PR #7989). The CUTOVER probe
  # described above is deferred with the rest of Phases 1-8: `followthroughs/`
  # carries no jikigai script, the path still holds an unresolved `<issue>`
  # placeholder, and the zone it would query does not exist. What this PR
  # actually ships on a sensitive path is the ops-email alert repair, so that is
  # what this command verifies. When the cutover unblocks, ADD the cutover probe
  # here; do not replace this one.
  #
  # A `credentials_required:` field was declared here and has been REMOVED. Check
  # 10 treats that field as SKIP-DECLARED and exits BEFORE attempting the
  # command, so its only practical effect was to stop the gate noticing that the
  # command did not exist. It also answers the wrong question: its test is
  # "has this property no unauthenticated substitute", and every limb below is
  # unauthenticated -- so this probe was a candidate for REACHING Check 10, not
  # for waiving it.
  command: bash scripts/resend-alert-path-discoverability.sh
  expected_output: "RESEND_ALERT_PATH_OK or RESEND_ALERT_PATH_SKIP_NO_DIG"
```

Every limb runs locally with no SSH. The DNS assertions use `dig` against public
resolvers and against the parent `.com` nameservers; the zone-status assertion uses the
Cloudflare REST API. Neither requires a dashboard.

### Soak follow-through enrolment (Phase 2.9.1)

The close criterion is time-gated — the zone must be `active` and the record set correct
for a sustained period after the NS flip — so the closure is enrolled, not remembered:

- **Script:** `scripts/followthroughs/jikigai-dns-cutover-<issue>.sh`, exit 0 only when
  the zone is active, all eight records match the declaration, and the DS state is coherent
  with the delegation. Exit 2 (transient) while the flip is still propagating.
- **Directive** on the tracker issue, with `earliest` set to NS-flip + 7 days:

```text
<!-- soleur:followthrough
  script=scripts/followthroughs/jikigai-dns-cutover-<issue>.sh
  earliest=<flip-date+7d>T00:00:00Z
  secrets=GH_TOKEN,CF_API_TOKEN_ZONE_ADMIN,BETTERSTACK_API_TOKEN
-->
```

- `secrets=GH_TOKEN` is mandatory for any `gh`-using probe: the sweeper runs scripts under
  `env -i` with only PATH, HOME and the declared secrets, and an unauthenticated `gh`
  returns exit 2 on every sweep — a silent never-close rather than a loud failure.
- Of the three declared secrets, `GH_TOKEN` and `BETTERSTACK_API_TOKEN` are **already**
  wired in `.github/workflows/scheduled-followthrough-sweeper.yml` (verified by reading its
  `env:` block). Only `CF_API_TOKEN_ZONE_ADMIN` needs adding there — as a repository secret
  as well as a Doppler value, since the sweeper reads from `secrets.*`, not from Doppler.
- Label the tracker `follow-through`.
- **A second, date-anchored follow-through is required**, because the cutover one is keyed to a
  flip date that may never exist: if DS removal blocks on a vendor ticket (R2, the largest
  schedule risk), there is no flip, the directive is never enrolled with a real timestamp, and
  the only enrolled watchdog never arms — which is precisely the silent-lapse shape this plan
  exists to end. Enrol a second directive with `earliest = merge + 14d` whose sole assertion is
  **"the zone still exists"**. Its trigger is the merge, which has already happened by
  construction.
- Set the cutover directive's own `earliest` to the **filing date**, not flip+7d, and let the
  script self-gate with exit 2 until the soak elapses. `earliest` is a hard wall-clock gate
  evaluated *before* the script runs, so a far-future value does not delay closure — it stops
  the probe executing at all during the window it was written to watch. The convention warns
  against this shape directly.

## Guard Contract

### Guard 1 — Declared-vs-live record parity

**Property.** Every DNS record the Cloudflare zone serves is declared in
`infra/jikigai-dns/dns.tf`, and every record declared there is served — in both
directions, over the whole zone rather than over the declared list.

**Assembly.** Two chokepoints, both read as whole lists. On the declared side, the guard reads
**`terraform show -json` over the saved plan** — resource *values*, never an HCL text parse. An
address-level diff cannot see a changed DKIM target (mutation row 3 is value-level), and text
parsing has its own failure modes (`for_each`, heredocs, a comment containing
`resource "cloudflare_record"`). On the live side, `GET /zones/{id}/dns_records` with pagination
followed to exhaustion. The guard quantifies over both, never over a hardcoded count.

**Bootstrap state, named explicitly.** Before the first apply the live list is empty while eight
records are declared — which mutation row 5 requires to be RED. As first drafted this guard
would have blocked the very apply that creates the zone. It therefore runs **post-apply**, and
gates the *next* apply; the create-from-absent case is a declared skip, asserted as such rather
than left implicit. There is exactly
one write path to this collection in the repo — the `apply-jikigai-dns.yml` full-root
apply — and the guard runs on that path before apply. A record can also enter the
collection from outside the repo (a dashboard edit, or `jump_start`), which is the
asymmetry the two-directional diff exists to catch and the reason the guard cannot be
scoped to the declared list.

**Mutation matrix** (derived from the design, written before the guard):

| # | Mutation | Guard must |
|---|---|---|
| 1 | Delete one `cloudflare_record` block from `dns.tf` while the record still exists in the zone | RED — live-not-declared |
| 2 | Create a record in the zone out-of-band that `dns.tf` does not declare | RED — live-not-declared, the `jump_start` class |
| 3 | Change one DKIM CNAME's target by a single character in `dns.tf` | RED — declared-not-served |
| 4 | Add a **second** undeclared record after a first one has been reconciled | RED — proves the check does not stop at the first finding |
| 5 | Make the API return an empty record list (or fail the pagination follow) | RED — a zone that serves nothing must not read as "everything declared is absent, therefore consistent"; this targets the guard's own dispatch |
| 6 | Point the guard at a zone id that does not exist | RED — not a silent pass |

**Harness rows:**

| # | Edit to the SUITE (not the guard) | Must |
|---|---|---|
| H1 | Replace the guard invocation in the suite with `true` | RED — the suite must detect that it is no longer exercising the guard |
| H2 | Feed the guard a record list that differs from the canonical in a way the contract explicitly permits — same records, different API return order, and TTL rendered as `1` vs `auto` | **PASS** — the guard must not be satisfiable only by byte-identity with the canonical fixture |

### Guard 2 — DNSSEC delegation coherence

**Property.** The domain is never in a state where a DS record is published at the
`.com` parent that does not correspond to the key of whichever nameserver set is actually
authoritative. This is the state that hard-fails every validating resolver.

**Assembly.** The chokepoint is the tuple (parent DS RRset, parent NS RRset, Cloudflare zone
DNSSEC status, **declared cutover ordering**). The first three are read live: DS and NS from a
`.com` gTLD server directly rather than from a caching resolver, and the Cloudflare status from
the REST API. The fourth is `infra/jikigai-dns/cutover-order.json`, which exists so the ordering
is an artifact the guard can read rather than prose it cannot. The guard quantifies over the
tuple, not over any single member — reading only the DS, or only the NS, cannot express the
property, because the property is about their agreement.

**The tuple has no time dimension, and that is a known limit.** A state where the parent DS is
Cloudflare's, the parent NS is Cloudflare's, and Cloudflare DNSSEC is on reads as coherent —
even while resolvers still hold a cached Google NS RRset and therefore fetch Google's DNSKEY
against Cloudflare's DS, which SERVFAILs. That hazard is invisible to this guard by
construction, which is exactly why DNSSEC restoration is gated on an *elapsed-time* proof
(≥48h, preferably 72h, of a resolver panel returning only the Cloudflare pair) rather than on
Guard 2 alone.

**Mutation matrix:**

| # | Mutation | Guard must |
|---|---|---|
| 1 | Simulate: NS delegated to Cloudflare, DS still Google's `26851 8 2 818EBD…` | RED — this is the exact incident being prevented |
| 2 | Simulate: NS delegated to Cloudflare, Cloudflare DNSSEC enabled, DS absent from parent | AMBER/transient, not RED — a legitimate intermediate state while the new DS is being published |
| 3 | Simulate: NS still Google, DS Google's, Cloudflare DNSSEC enabled on a pending zone | PASS — Cloudflare is not authoritative yet, so its DNSSEC state is not observable by resolvers |
| 4 | **Reorder**: swap the DS-retirement and NS-flip entries in `infra/jikigai-dns/cutover-order.json` — a declared, machine-readable phase ordering that the probe reads as a fourth input, created **because** this row is otherwise untestable: the first draft's Assembly named only three live inputs and no runbook, so the row asserted against an artifact nothing produced | RED — the property is about the ordering and the window, so a delete-only battery that only ever observes the end state would certify a sequence broken in the middle. A working version of this row is what catches the publish-DS-too-soon hazard |
| 5 | Point the guard at a resolver that strips DS records | RED — must not read an inability to observe as coherence; targets the guard's own dispatch |

**Harness rows:**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Stub the DS lookup to return a fixed empty string for every input | RED — a guard that can never see a DS cannot assert this property |
| H2 | Feed a fully-migrated, DNSSEC-re-enabled steady state with Cloudflare's own DS and Cloudflare NS | **PASS** — the terminal good state must pass, so the guard is not merely rejecting everything |

## Files to Create

- `infra/jikigai-dns/main.tf`, `variables.tf`, `zone.tf`, `dns.tf`, `outputs.tf`, `README.md`
- `infra/jikigai-dns/google-zone-snapshot.txt` — the committed restorable capture (Phase 6.1)
- `.github/workflows/apply-jikigai-dns.yml`
- `.github/workflows/jikigai-dns-cutover.yml` — the actor for Phases 5-8, modelled on the
  existing `git-data-cutover.yml` (typed `confirm` token as typo-guard, `dry_run` defaulting
  true, a `rollback` input). Without it, Phases 5-8 have no producer and the "automated, gated
  dispatch" heading over the post-merge ACs describes something nothing creates.
- `tests/scripts/lib/destroy-guard-filter-jikigai-dns.jq`
- `tests/scripts/test-destroy-guard-counter-jikigai-dns.sh` — a **dedicated** counter suite.
  Rows cannot be added to the existing one: `tests/scripts/test-destroy-guard-counter.sh` pins
  `MIN_ASSERTIONS=8` compared with `-ne`, an exact equality, so extra rows redden it
- `infra/jikigai-dns/bootstrap.sh` — the self-revoking admin-token bootstrap
- `scripts/followthroughs/jikigai-dns-cutover-<issue>.sh` (+ its `.test.sh`)
- `knowledge-base/engineering/architecture/decisions/ADR-214-corporate-dns-root-and-terraform-created-zones.md`
- guard suites for Guard 1 and Guard 2

## Files to Edit

- `.github/workflows/scheduled-terraform-drift.yml` — add the `infra/jikigai-dns` matrix leg
- `.github/workflows/scheduled-followthrough-sweeper.yml` — add `CF_API_TOKEN_JIKIGAI` to `env:`
- `scripts/encryption-posture-ledger.json` — **add `cloudflare_zone` to `non_store_types`.**
  `scripts/lint-encryption-posture.py` is fail-closed over `infra/**/*.tf` and partitions every
  `resource "<type>"` into `store_classes` or `non_store_types`, failing on anything in neither.
  `cloudflare_zone` is in neither today (verified), so `zone.tf` reddens CI on its first commit
- `tests/scripts/test-destroy-guard-regex-parity.sh` — two new `EXPECTED_SITES` rows
- `scripts/required-checks.txt`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`,
  `infra/github/ruleset-ci-required.tf` — register the new destroy-required context (see below)
- `.github/CODEOWNERS` — an explicit `/infra/jikigai-dns/` row, as every other root has
- `plugins/soleur/test/infra-validation-detect.test.sh` — a fixture row for the new root
- `knowledge-base/operations/domains.md` — add the jikigai.com row (F2)
- `knowledge-base/operations/expenses.md` — record the registration renewal
- `knowledge-base/legal/article-30-register.md` — PA-15 §(g)(4) re-siting; Cross-Cutting TOMs availability measure (F3, CLO)
- `knowledge-base/project/plans/2026-06-15-feat-agent-native-outbound-email-pilot-plan.md` — repoint to the new root
- `knowledge-base/project/plans/2026-05-19-feat-linkedin-api-reapply-jikigai-plan.md` — repoint to the new root
- `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` — as the Phase 0.5 enumeration requires

No path above matches any UI-surface term or glob, which is why the Product/UX gate resolves to NONE.

## Implementation Phases

Phases 1-4 are autonomous and merge together. Phases 5-8 are the sequenced cutover and
are driven by a gated dispatch after the merge.

### Phase 0 — Preconditions (verify, do not assume)

0.1 Re-run the credential probe and record output in the PR body: confirm no existing
    token lists more than the soleur.ai zone, and confirm `GET /zones?name=jikigai.com`
    still returns zero.
0.2 Re-dig the complete record set and diff against the values in this plan. Transcribe
    from the dig output.
0.3 Confirm the pinned provider schema for `cloudflare_zone`, `cloudflare_zone_dnssec`
    and `cloudflare_record` via `terraform providers schema -json` against 4.52.7 —
    never from documentation, per the Context7 version-mismatch learning.
0.4 Determine, by a real attempt rather than by assertion, whether DS removal at
    Squarespace is self-service. This is the single largest schedule risk; if it needs a
    support ticket the timeline extends and Phase 6 blocks.
0.2a **Enumerate the Google-side zone in full.** `dig` cannot enumerate a zone — it only
    answers for names already known — so "the record set is complete" is not establishable by
    the probes run so far. Export the zone from the registrar's DNS panel (or
    `gcloud dns record-sets list` if the zone is reachable that way) and diff the complete
    rrset list against `dns.tf`. This applies the plan's own whole-list learning to the side
    being **replaced**, which Phase 2.4 applied only to the Cloudflare side. Any record found
    here that the plan does not declare would otherwise be silently destroyed at the flip, and
    Guard 1 is structurally incapable of seeing it.
0.5 Read the three `.c4` model files in full and produce the actor/system/relationship
    enumeration ADR-214 requires.
0.7 **File the cutover tracker issue** (label `follow-through`, no directive yet) and capture
    `#N`. The probe filename embeds it, `Ref #N` needs it, and
    `.claude/hooks/follow-through-directive-gate.sh` rejects a `script=` path that does not yet
    exist — so the issue must precede the script, and the script must precede the directive.
0.8 **Record the registrar account's own contact address.** If it is on jikigai.com, change it
    first: a support reply about a broken domain must not traverse the broken domain.

### Phase 1 — Credentials, two phases

1.1 Mint a **short-TTL (≤7-day) account-scoped `Zone:Zone:Edit`** token. There is no
    token-mint automation in this repo (see Capability Gaps), so this rides the automation
    ladder and the rung reached is recorded as evidence.
1.2 Create the zone with a scripted `curl` to `POST /zones` — never a dashboard click
    (`hr-exhaust-all-automated-options-before`). Capture the returned zone id and
    nameservers.
1.3 Mint the **persistent `Zone:DNS:Edit` token scoped to jikigai.com only**, now that a
    zone id exists. Write it to Doppler `soleur/prd_terraform` as `CF_API_TOKEN_JIKIGAI` —
    the name `article-30-register.md` PA-15 §(g)(4) and the outbound-email pilot plan both
    already prescribe.
1.4 Run the ADR-130 retained-scope probe: assert the new token reaches the jikigai.com zone
    and **403s on every other zone**, and — the load-bearing half — assert no pre-existing
    token lost scope.
1.5 Let the ephemeral token expire. Confirm expiry rather than assuming it.
1.6 **Gate:** the persistent zone-scoped value is in Doppler before Phase 4 merges (ADR-065).

### Phase 2 — Write the root (RED first)

2.1 Author the guard suites for Guard 1 and Guard 2 from the mutation matrices above,
    with fixtures, and confirm each matrix row drives its guard RED before the guards
    are implemented.
2.2 Author `main.tf`, `variables.tf`, `zone.tf`, `dns.tf`, `outputs.tf`, `README.md`.
2.3 `terraform init` + `terraform validate` + `terraform fmt -check` in the new root.
2.4 Live-enumerate: confirm no jikigai.com zone exists before the first apply, per the
    whole-list learning.

### Phase 3 — Wire CI

3.1 `.github/workflows/apply-jikigai-dns.yml`, modelled on `apply-sentry-infra.yml`:
    full-root plan, destroy guard, `workflow_dispatch` escape hatch, concurrency group.
3.2 Add the `infra/jikigai-dns` leg to the `scheduled-terraform-drift.yml` matrix.
3.3 Add `CF_API_TOKEN_ZONE_ADMIN` to `scheduled-followthrough-sweeper.yml`'s `env:` block
    and as a repository secret. `BETTERSTACK_API_TOKEN` and `GH_TOKEN` are already wired
    there — verified, not assumed.
3.4 Verify each new path glob matches at least one real file.

### Phase 4 — ADR, C4, expense, merge

4.1 Write ADR-214 (D1/D2 accepted, D3 adopting).
4.2 Apply the C4 edits the Phase 0.5 enumeration identified; run the syntax, render and
    count-parity suites.
4.3 Record the registrar renewal as a recurring vendor expense if it is not already in
    the ledger (`wg-record-recurring-vendor-expense-before-ready`) — a grep of
    `knowledge-base/finance/` found no jikigai.com or Squarespace line.
4.4 Merge. The apply workflow fires and creates the zone plus all eight records. **The
    28-day clock starts here.**

### Phase 5 — Retire the DS record FIRST, before the zone exists

Reordered from this plan's first draft, which created the zone before touching DNSSEC.
Nothing about DS removal requires the Cloudflare zone, and doing it first shortens the
28-day pending-zone exposure from ~50 hours to a few hours — it also surfaces the
Squarespace unknown before any Terraform, state or pending zone exists.

5.1 Remove the DS record at the registrar, driven by the automation ladder, recording the
    rung reached. Gated on the Phase 0.4 finding.
5.2 Poll `dig DS jikigai.com @a.gtld-servers.net` until it returns empty.
5.3 Wait **≥ 1.5 × the DS TTL** from the moment the parent stops publishing it. DS TTL is
    86400s, so the floor is 36h; this plan uses **48h**.
5.4 Assert the domain is unsigned-but-resolving: `dig +dnssec MX jikigai.com @1.1.1.1`
    answers **without** the `ad` flag, and every mail record still resolves. Google Cloud
    DNS is authoritative and untouched throughout, so mail is unaffected.
5.5 **Lower the parent NS TTL** at the registrar to 300-3600s and let it drain alongside the
    DS drain — same 48h, no extra schedule cost. This is what makes the Phase 7 rollback bound
    tolerable: without it, a bad flip is bounded by the 172800s parent NS TTL, i.e. up to two
    days of mail loss, and the whole risk acceptance rests on a number that would otherwise be
    wrong by three orders of magnitude.
5.6 Run Guard 2.

### Phase 6 — Create the zone and verify it exhaustively

6.1 Capture Google's complete zone as a **committed, restorable artifact** in the new root
    before anything else. It is the reconstruction source if the Squarespace-side zone is
    torn down at the flip.
6.2 Create the zone via the Phase 1 ephemeral token, then `terraform import` it; apply the
    records. **Every TTL is 300s for the first 72h**, raised afterwards — this is what makes
    forward-fix faster than rollback.
6.3 Read `cloudflare_zone.jikigai_com.name_servers`.
6.4 Assert via the Cloudflare REST API that the record set is **exactly equal** to the
    declaration — set equality in both directions, not a spot check. The API, not `dig`, is
    the source of truth immediately after an apply, because the anycast edge lags by tens
    of seconds.
6.5 Then assert via `dig @<ns>` against **each assigned Cloudflare nameserver individually**
    — never through `1.1.1.1`, which would mask a single divergent nameserver.
6.6 Confirm no record exists that Terraform does not declare (the `jump_start` class).
6.7 Run Guard 1. A mismatch blocks the cutover; nothing has changed for the world yet.

### Phase 7 — Flip the nameservers

7.0 **Blocking pre-flight, executed in the same automated step that writes the registrar —
    never as a separate earlier check.** Days elapse between reading the nameservers and
    writing them, and across that gap the zone sits pending on the 28-day clock. If it were
    deleted and recreated, Cloudflare assigns a **different nameserver pair and a different
    zone id**, and writing the stale pair delegates the domain to nameservers that serve
    nothing — REFUSED/NXDOMAIN for everything, mail included, which is the total-loss path.
    So immediately before the write: re-read `GET /zones?name=jikigai.com`; assert exactly one
    result; assert its `id` equals the id in Terraform state; assert `status == "pending"`;
    assert `name_servers` is set-equal to the values about to be written; re-run Guard 1.
    Abort the write on any mismatch.
7.1 Replace the four `ns-cloud-c*.googledomains.com` entries with the Cloudflare
    nameservers **re-read in 7.0**, driven by the automation ladder, recording the rung reached.
7.2 Poll the Cloudflare API for `status == active`.
7.3 Assert the parent delegation names exactly the expected Cloudflare nameservers.
7.4 Re-assert the full record set through public resolvers — the first point at which the
    world's view is what is being measured.
7.5 Confirm in Proton that the domain still reads verified. The
    `protonmail-verification=1530cebd64e78f12eb1c2931c1098fce81dc4d79` TXT must survive
    verbatim; losing it can de-verify the domain and stop mail acceptance independently of MX.
7.6 Plan for **zero** nameserver overlap: the Google-side zone may stop serving the moment
    the delegation changes. Do not rely on the 48h parent NS TTL as a safety margin.

### Phase 8 — Add DMARC reporting, then close

8.1 Add `rua=mailto:dmarc-reports@jikigai.com` to the `_dmarc` record. The current policy
    carries no `rua`, so a post-cutover SPF or DKIM alignment regression is invisible; this
    is the only post-flip mail-authentication telemetry that exists.
8.2 Raise TTLs from 300s once the record set has been stable for 72h.
8.3 Extend the PA-27 synthetic-liveness-probe pattern to `legal@jikigai.com` — see §Legal.
8.4 Enrol the follow-through with `earliest` = flip date + 7 days.
8.5 File the registrar-transfer follow-through (D3) and the DNSSEC-restoration
    follow-through (below) with their re-evaluation triggers.

### DNSSEC restoration — deliberately NOT part of the cutover

Re-signing is split out rather than sequenced into the cutover, for two reasons.

**It cannot safely happen soon after the flip.** The parent NS TTL is 172800s, so resolvers
may keep following `ns-cloud-c1..c4` for up to 48h afterwards. Publishing Cloudflare's DS
while any resolver still reaches Google's nameservers gives that resolver Google's RRSIGs
against Cloudflare's DS — SERVFAIL, which is the exact outage the sequencing exists to
avoid. Restoration must wait ≥48h, and preferably 72h, after positive proof that no path
returns the Google nameserver set.

**Going temporarily insecure is a security regression, not an availability one.** Removing
DNSSEC restoration from the riskiest sequence removes an entire class of failure from it,
at the cost of a bounded window in which the domain is unsigned — the state most of the
`.com` zone is in permanently.

Restoration is therefore its own follow-through: add `cloudflare_zone_dnssec.jikigai_com`,
read the computed `ds`, publish it at the registrar, and assert the `ad` flag returns.
**Conditional that must ride with the issue:** `cloudflare_zone_dnssec` computes the DS but
cannot push it to a third-party registrar, and many registrars support DNSSEC only for
domains on their own DNS. If Squarespace cannot accept a custom DS, **the registrar transfer
becomes a prerequisite for DNSSEC restoration rather than an optimisation** — the two
follow-throughs then have a dependency edge, and it must be recorded on both.

## Acceptance Criteria

### Pre-merge (PR)

- **AC0 — blocking precondition.** At least one alert recipient **not on jikigai.com** is
  provisioned and a test alert is confirmed received before anything else in this plan runs.
  Cheapest sufficient options, in rung order: a second Better Stack team member on an
  off-domain address; a GitHub account notification address distinct from the commit address;
  or routing the cutover workflow's failures to the existing Sentry surface. Until AC0 holds,
  every other verification in this plan is unobservable in the failure mode it guards against.
- **AC1** `terraform validate` and `terraform fmt -check` pass in `infra/jikigai-dns/`.
- **AC2** The nine record resources' values are byte-identical to fresh `dig` output captured in Phase 0.2, quoted in the PR body. Specifically: MX `mail.protonmail.ch` priority 10 and `mailsec.protonmail.ch` priority 20; apex TXT `v=spf1 include:_spf.protonmail.ch ~all`; apex TXT `protonmail-verification=1530cebd64e78f12eb1c2931c1098fce81dc4d79`; `_dmarc` TXT `v=DMARC1; p=quarantine`; three DKIM CNAMEs on selector `dlsyxrjkwef5bwihl4fgmgswd2heglj7tta7o4qqc2h72lmdfbllq`.
- **AC3** `grep -c 'name *= *"@"' infra/jikigai-dns/dns.tf` returns 0, and every apex resource uses the literal `jikigai.com`.
- **AC4** `grep -c 'jump_start *= *false' infra/jikigai-dns/zone.tf` returns 1.
- **AC5** No `-target=` appears in `apply-jikigai-dns.yml` — the root is applied whole.
- **AC6** `infra/jikigai-dns/main.tf` contains an R2 `backend "s3"` block with `key = "jikigai-dns/terraform.tfstate"` (`hr-every-new-terraform-root-must-include-an`).
- **AC7** The persistent token variable is declared with no `default`, `sensitive = true`, and a scope-ledger comment stating it is **zone-scoped to jikigai.com only**. No account-scoped Cloudflare token appears in any committed variable declaration (`grep -c 'Zone:Zone:Edit' infra/jikigai-dns/*.tf` returns 0).
- **AC8** `scheduled-terraform-drift.yml`'s matrix contains an `infra/jikigai-dns` entry.
- **AC9** Every mutation-matrix row for Guard 1 and Guard 2 drives its guard RED, and every harness must-PASS row passes. Demonstrated by running the suites, not asserted.
- **AC10** `python3 scripts/lint-guard-contract.py` passes against this plan.
- **AC11** `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes over the full changed set — run the gate's own invocation, not a hand-enumerated path list.
- **AC12** ADR-214 exists, is referenced from this plan, and the C4 enumeration is either reflected in `.c4` edits or accompanied by the checked-and-already-modelled citation. `apps/web-platform/test/c4-count-parity.test.sh` is green.
- **AC13** The ADR ordinal is re-verified free across all `origin/*` refs immediately before merge; a renumber sweeps this plan, `tasks.md`, and AC12.
- **AC14** The ADR-130 retained-scope probe output is in the PR body, showing the new token's scope **and** that no pre-existing token lost scope.
- **AC14b** The ephemeral zone-create token carries an expiry ≤7 days, evidenced by its `expires_on` from `GET /user/tokens/verify`, and the zone is `import`ed rather than created by a persistent credential.
- **AC14c** `knowledge-base/operations/domains.md` contains a jikigai.com row with registrar, renewal date and nameservers (F2).
- **AC14d** All three stale cross-artifact prescriptions are updated in this PR: `article-30-register.md` PA-15 §(g)(4), the outbound-email pilot plan, and the LinkedIn re-apply plan (F3).
- **AC14e** Every record TTL in `infra/jikigai-dns/dns.tf` is 300 at merge time, with the raise tracked in the follow-through rather than assumed.
- **AC14f** The `_dmarc` record carries a `rua=` tag.
- **AC15** `CF_API_TOKEN_JIKIGAI` (zone-scoped) is present in Doppler `soleur/prd_terraform` before merge, verified by **name listing only** — never by printing the value.

### Post-merge (automated, gated dispatch)

- **AC16** After the apply, `GET /zones?name=jikigai.com` returns exactly one zone; its record list matches the declaration in both directions (Guard 1 green).
- **AC17** **Each** assigned Cloudflare nameserver, queried individually rather than through a recursive resolver, answers a record set exactly equal to the declaration — set equality in both directions. Asserted before the delegation changes.
- **AC18** After Phase 5, `dig DS jikigai.com @a.gtld-servers.net` is empty and `dig +dnssec MX jikigai.com @1.1.1.1` returns **no** `ad` flag, sustained ≥48h **before the zone is created**.
- **AC19** After Phase 7, zone status is `active` and the parent delegation names exactly the two expected Cloudflare nameservers.
- **AC20** DNSSEC restoration is **not** an acceptance criterion of this change. It is enrolled as its own follow-through with the ≥48h post-flip gate and the Squarespace-custom-DS conditional attached.
- **AC20b** Proton reports jikigai.com verified after the flip, and the `protonmail-verification` TXT is byte-identical to its pre-cutover value.
- **AC21a** The SMTP acceptance limb passes for **both** `ops@` and `legal@`, with the catch-all discriminator asserted. This is the only criterion that covers `legal@` at all — every other AC is silent on the Article 12(3) limb the User-Brand Impact section raises.
- **AC17a** The parent NS TTL is observed ≤3600 at `a.gtld-servers.net` for ≥48h before the flip.
- **AC19a** The Phase 7.0 pre-flight ran inside the registrar-write step and every assertion passed.
- **AC5a** `jikigai-dns-cutover.yml` exists and every Phase 5-8 assertion appears in it as a gate step.
- **AC2a** The full Google-side zone enumeration is quoted in the PR body, and every non-NS/non-SOA rrset in it either appears in `dns.tf` or is listed with an explicit drop rationale.
- **AC15a** Phase 4 does not merge until Phase 0.4 has concluded that DS removal is achievable; if it requires a vendor ticket, the ticket is resolved first. Merging starts the 28-day clock, so it must not begin against an unbounded dependency.
- **AC21** The follow-through probe exits 0 on a sweep at flip + 7 days.
- **AC22** Every registrar-side step carries a recorded `playwright-attempt:` evidence line naming the URL reached and, where blocked, the specific named gate encountered.
- **AC23** `Ref #N`, not `Closes #N`, in the PR body — the remediation completes after merge, so an auto-close at merge would record a false-resolved state.

## Downtime & Cutover

**Trigger.** The plan's Files-to-Create include `.tf` files and the change restructures how a
serving surface is reached — the authoritative nameservers for a live mail domain. That is the
router class, so a zero-downtime path must be evaluated and defaulted to rather than accepting
an outage window.

**The offline-inducing operation and its surface.** The only irreversible-in-the-short-term
operation is the registrar delegation change (Phase 7.1). The surface it affects is inbound mail
for jikigai.com — `ops@` (every production alert) and `legal@` (statutory data-subject requests).
Nothing else in the plan can take a surface offline: creating a pending zone, populating its
records, and retiring a DS record are all invisible to resolution while Google Cloud DNS remains
authoritative.

**Zero-downtime path — evaluated and adopted as the default.** The cutover is a **blue-green
delegation swap** and is designed to have no offline window at all:

1. The "green" nameservers are built and fully verified *while* "blue" continues serving —
   Cloudflare answers authoritatively for a pending zone on its assigned nameserver IPs, so the
   entire record set is provable correct before any delegation changes (Phase 6.4-6.7).
2. The swap itself is atomic at the registrar and both sides serve **byte-identical** answers,
   which is what makes resolver-cache divergence during propagation harmless rather than a
   split-brain: a resolver holding the old delegation and one holding the new return the same MX,
   SPF, DKIM and DMARC.
3. The DNSSEC hazard that *would* have created a hard window is removed **before** the swap
   rather than repaired after it (Phase 5), so at no point does a validating resolver see a DS
   that fails to chain.
4. DNSSEC restoration — the one remaining step that could reintroduce a window — is deliberately
   **not** in the cutover. It is a separate follow-through gated on ≥48h of proof that no path
   resolves to the old nameservers.

**Residual downtime accepted: none.** No maintenance window is requested, because the design has
no step that requires one. The residual *risk* is a transcription error in the record set
surviving verification, and it is mitigated by exact set equality against each nameserver
individually plus 300s TTLs for the first 72h — which makes forward-fix (~5 minutes) the recovery
path rather than a delegation revert (bounded below by the 48h parent NS TTL). See the Rollback
section: forward-fix is the control, and that is a deliberate design property, not a concession.

**Per-stage verification and rollback** are enumerated in the Cutover Runbook below, one row per
phase.

## Cutover Runbook and Rollback

The full sequence is Phases 5-8 above. The property that makes it safe is that
**Google Cloud DNS remains authoritative and unmodified until Phase 7**, so every step
before the flip is reversible by doing nothing.

### There is no fast nameserver rollback — say so plainly

Reverting the delegation at the registrar is bounded below by the parent NS TTL: up to 48
hours before resolvers stop using Cloudflare. Worse, if the Squarespace-side hosted zone is
torn down when custom nameservers are set, flipping back yields an **empty** zone —
NXDOMAIN, hard bounces — which is strictly worse than the failure being rolled back from.

So nameserver rollback is **not** the control. The real controls, in order of load-bearing:

1. **Exact set-equality verification against each Cloudflare nameserver before the flip**
   (Phase 6.4-6.7). This is the actual safety mechanism.
2. **300s TTLs on every record for the first 72h.** A transcription error is then repaired
   in Cloudflare in about five minutes. **Forward-fix is the rollback.**
3. **DS already retired and proven gone** (Phase 5), so no failure mode is a cached-DS SERVFAIL.
4. **A committed restorable copy of the Google-side zone** (Phase 6.1), so re-entry at any
   provider is mechanical.
5. **Proton still reports the domain verified** post-flip (Phase 7.5).

### Rollback by phase

| Point of failure | Rollback |
|---|---|
| Phase 5 (DS retired, problem found) | Re-publish the original DS `26851 8 2 818EBD7D35A304518B7DE3574F4B885977CE1618977DBFEF01161455C571602D`. Resolution is unaffected meanwhile — an unsigned domain resolves normally |
| Phase 6 (verification fails) | Nothing to undo; the pending zone is inert and not delegated. Fix the declaration and re-apply |
| Phase 7 (mail breaks after flip) | **Forward-fix in Cloudflare at 300s TTL**, not a delegation revert. Restore the four `ns-cloud-c*.googledomains.com` entries only as a last resort, understanding it is bounded by the 48h parent NS TTL and may land on an empty zone |
| DNSSEC restoration follow-through | Remove the newly-published DS; the domain returns to unsigned-but-resolving, which is safe |

**Rollback precondition, stated because it is easy to lose:** the Google-side DNS zone must
not be deleted until the follow-through closes, and the Phase 6.1 committed artifact exists
precisely because that precondition may be violated by the registrar rather than by anyone here.

### If DS removal turns out to need a vendor support ticket

This is the plan's single point of failure and it has **no automated fallback**. The escape
routes are all closed: flipping the delegation with a stale DS breaks validation; transferring
to Cloudflare Registrar to escape it is circular, because Cloudflare Registrar requires the
zone active, which requires the flip; and transferring to a third registrar is blocked by the
ICANN lock to ~2026-10-06 and by `clientTransferProhibited`. The only remaining option is to
abandon the cutover and leave jikigai.com on the current DNS, unmanaged by Terraform.

**Therefore DS-removability is a Phase 0 gate** (0.4), determined before a line of Terraform
is written. If it resolves to a support ticket, that is unbounded-latency and non-automatable:
it becomes an explicitly deferred, tracked action, and the PR must not reach ready with it
undeferred (`hr-never-label-any-step-as-manual-without`, `wg-block-pr-ready-on-undeferred-operator-steps`).

### If the zone is deleted again mid-sequence

`terraform plan` is expected to **error** (Cloudflare 1003/1049 on an unknown zone id) rather
than gracefully plan a re-create, which fails the apply workflow rather than self-healing.
Recovery is `terraform state rm cloudflare_zone.jikigai_com` followed by a re-create.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations, Finance. Product: **NONE** — the
mechanical UI-surface scan over `## Files to Create` and `## Files to Edit` matches no
path in the UI-surface term list or glob superset (`components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`); the change is Terraform, workflows and docs.

**Agents invoked:** cto, clo, architecture-strategist, spec-flow-analyzer.
**Skipped specialists:** none.
**Pencil available:** N/A (no UI surface).

### Engineering (CTO)

**Status:** reviewed.
**Assessment:** agreed the new-root decision but rejected its original rationale, replacing
the ADR-065 argument with the #6589 `-target=` deletion-blindness argument (adopted, D1).
Rejected the standing account-scoped token as an end state and specified the two-phase
ephemeral-create / persistent-zone-scoped credential (adopted). Found two ordering defects:
DS retirement should precede zone creation, and DS re-publication must wait ≥48h for the
parent NS TTL (both adopted; restoration split into its own follow-through). Reframed
severity — SERVFAIL delays mail, NXDOMAIN/empty-MX bounces it — inverting the mitigation
priority toward record-set completeness (adopted). Retracted this plan's `cf-token-scope`
mint claim as a capability overstatement (adopted). Surfaced F1, F2 and the cross-plan
coupling. Flagged that the drift-cron matrix is hardcoded and that a new root also needs a
destroy-guard filter, and recommended modelling the apply workflow on `apply-github-infra.yml`.

### Legal (CLO)

**Status:** reviewed.
**Assessment:** `legal@jikigai.com` is materially more load-bearing than the brief implies.
It is the **sole** Article 15 route for six processing activities (PA-7 §(h), PA-31, PA-32,
PA-33, PA-34, PA-35 — several annotated "currently unanswerable by the automated export"),
the Article 22(3) human-review contact inlined on every `/dashboard/audit` row (PA-14), the
register's §0 controller contact, and the **only** contact in the Article 30(2) processor
register. A silent black-hole does not degrade one route among several; for six activities
it is the only route there is, and the Article 12(3) one-month clock runs regardless.

Three findings adopted into scope:

1. **P1 — extend the existing liveness probe to `legal@`.** PA-27 TOM (11) already ships a
   daily synthetic mailbox probe plus a Sentry cron monitor that pages within ~25.5h — but
   it is scoped to `ops@soleur.ai` only. The mailbox the register publishes as the Article 12
   contact is unmonitored. This is a second instance of a shipped control, not new
   engineering, and it is the **durable** fix: it outlives the cutover window, whereas the
   DMARC `rua` and the point-in-time send/receive checks do not.
2. **P1 — Article 32(1)(c) availability has zero coverage.** `32(1)(c)` does not occur in
   the register at all; `32(1)(b)` is used exclusively for confidentiality and integrity.
   There is no availability measure for any communication channel anywhere in the corpus.
   Add a channel-availability TOM to the **Cross-Cutting TOMs block**, not to any single
   processing activity — the channel serves six PAs plus §0 plus the 30(2) register.
3. **P2 — site the zone controls in PA-15 §(g)**, which is already the only place
   jikigai.com appears as a Cloudflare zone, extending the measures there rather than
   creating a parallel entry. This is the same edit F3 requires.

**Not folded in, cross-referenced instead:** #7845 ("Proton AG has no Vendor DPA Status row")
is under-scoped relative to the defect. The register also omits Proton from the Vendor /
Sub-Processor Mapping table entirely, and PA-27 omits Proton from §(d)/§(e) while its own
narrative calls Proton "the durable original" — so two processing activities in one register
reach opposite conclusions about the same processor. Add both as comments on #7845 so its
scope matches the defect; do not fold the substance into a DNS PR.

**Also noted, out of scope:** #7846 records an undisclosed outbound correspondence leg to a
non-adequacy jurisdiction that leaves *from* `legal@jikigai.com`, making the mailbox a
Chapter V surface in both directions.

### Operations / Finance

**Status:** reviewed (folded).
**Assessment:** `knowledge-base/operations/domains.md` has no jikigai.com row at all (F2) —
the absence that let a pending zone die unobserved. `knowledge-base/operations/expenses.md`
records no line for the jikigai.com registration at either registrar. Per
`wg-record-recurring-vendor-expense-before-ready`, the current Squarespace renewal must be
recorded before PR-ready, and the prospective Cloudflare Registrar figure (~$10.46/yr at
cost) attaches to the transfer follow-through rather than to this change.

## Capability Gaps

- **Cloudflare API-token *mint*.** `soleur:cf-token-scope` widens only and is hardcoded to
  one token variable. ADR-130's "mint a new narrow alias" branch has no automation while its
  "widen" branch does — and minting is the operation this plan needs. Domain: engineering/infra.
- **Per-root apply-workflow scaffolder.** Each new Terraform root hand-rolls its apply
  workflow, `[ack-destroy]` gate, `destroy-guard-filter-*.jq` and drift-matrix registration.
  Three roots have now paid this tax independently, and the drift-matrix step is the one that
  gets forgotten — which is the failure this plan exists to remediate. Domain: engineering/infra.

## Open Code-Review Overlap

**None.** Queried 64 open `code-review`-labelled issues and searched each body for
`apps/web-platform/infra/dns.tf`, `apps/web-platform/infra/uptime-alerts.tf`,
`apps/web-platform/infra/variables.tf`, `apps/web-platform/infra/main.tf`,
`.github/workflows/scheduled-terraform-drift.yml` and `infra/github`. No matches. The
new root's files do not exist yet and so cannot overlap.

## Risks and Mitigations

- **R1 — The 28-day pending-zone clock.** From the moment the apply creates the zone, the
  cutover has 28 days or Cloudflare deletes it again and the Terraform state points at a
  dead id. *Mitigation:* the follow-through probe treats "zone absent after a successful
  apply" as a named failure mode; the runbook's own critical path is ~4 days, leaving wide
  margin; and if Phase 6 blocks on a support ticket, the correct response is to destroy
  the pending zone and re-apply later rather than let it lapse silently.
- **R2 — DS removal may not be self-service at Squarespace.** Documented for addition,
  silent on removal. *Mitigation:* Phase 0.4 determines this before anything is created,
  by attempt rather than assumption. If a ticket is required, Phase 6 gains a lead time
  and R1's mitigation applies.
- **R3 — The new token is broader than anything currently held.** Account-scoped
  `Zone:Zone:Edit` can create, edit and delete zones account-wide, including soleur.ai.
  *Mitigation:* it is confined to a root that manages one zone; its scope ledger is
  written into the variable declaration; the ADR-130 probe asserts nothing else was
  re-scoped; and the token drift detector will see it. Residual risk is real and is stated
  in User-Brand Impact rather than mitigated away.
- **R4 — Terraform state now contains an account-scoped credential.** *Mitigation:* same
  bucket, same posture as every sibling root; see Encryption Posture, including what it
  does **not** defend against.
- **R5 — The Better Stack `ops@` team member may already be inert.** The code comment
  records that the member is pending until the invite is accepted. If so, the alert path
  was partly dark before this change. *Mitigation:* the probe reports it as notify-only
  and names it as pre-existing rather than attributing it to the cutover.
- **R6 — Playwright MCP failed to connect in the planning session.** This is a session-level
  connection failure, not evidence about the capability. *Mitigation:* the plan records
  every registrar rung as `automation-status: UNVERIFIED` and requires a real attempt at
  `/work` time; an a-priori "dashboard-only" claim is explicitly not accepted as evidence.
- **R11 — The domain is unsigned for 5-9 days, which is a temporary security downgrade.**
  From DS retirement to DNSSEC restoration, MX answers are forgeable by anyone with
  resolver-cache-poisoning position — during exactly the window in which the ability to notice
  is lowest. Accepted because the alternative (multi-signer) is not expressible in the pinned
  provider, and because the availability risk of the alternative ordering is strictly worse.
  Minimised by authoring and reviewing the restoration PR **before** Phase 7 so it can merge
  within minutes of the ≥48h gate clearing rather than days after.
- **R12 — The critical path is 7-9 days, not the ~4 first claimed.** Counting: Phase 5
  verification, DS propagation to the parent (bounded by the registrar's own publish cycle),
  the mandated 48h DS drain, the concurrent 48h NS-TTL drain, the flip, activation, and the
  restoration PR cycle. Still inside 28 days, but the margin is about a third of the original
  claim — and that claim was doing real work as the basis for accepting R1. A **Day-21 abort
  checkpoint** in the cutover workflow destroys the pending zone and re-plans if the flip has
  not occurred, and **invalidates any recorded nameserver values** so the 7.0 pre-flight cannot
  pass on stale data.
- **R8 — `_domainconnect` is dropped deliberately.** The live zone carries a
  `_domainconnect` CNAME to `_domainconnect.domains.squarespace.com`, a registrar-side
  Domain Connect affordance with no function once Cloudflare is authoritative. It is not
  carried. Recorded as a decision so the parity guard's silence about it is intentional
  rather than an omission.
- **R9 — Zero nameserver overlap must be assumed.** The Google-side zone may stop serving
  the instant the delegation changes; the 48h parent NS TTL is not a safety margin.
- **R10 — The Resend account may already be at its verified-domain cap.** The outbound-email
  pilot plan notes the free tier caps sending domains. Not this change's concern, but it
  bounds the F1 remediation options.
- **R7 — Provider-schema drift.** The v4/v5 split is a live hazard; researched docs
  described v5 shapes for both `cloudflare_zone` and `cloudflare_zone_dnssec`.
  *Mitigation:* every attribute in this plan came from a local schema dump of 4.52.7, and
  Phase 0.3 re-confirms.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Add jikigai.com to `apps/web-platform/infra/` | **Rejected.** A new no-default variable there fails the entire merge-triggered production apply until provisioned, because Terraform resolves all root variables before `-target` pruning. A corporate mail domain must not be able to wedge the product deploy path. It would also drag the change into `plugins/soleur/test/terraform-target-parity.test.ts`, which is scoped to `apps/web-platform/infra/*.tf` and `apply-web-platform-infra.yml` — verified by reading it; a root at `infra/jikigai-dns/` is outside that suite |
| Hardcode a zone id after creating the zone by hand | **Rejected.** Violates `hr-all-infrastructure-provisioning-servers`, and reproduces the original failure: a zone nobody's code knows about is a zone nobody notices lapsing |
| Widen an existing Cloudflare token instead of minting a new one | **Rejected** per ADR-130: account-level zone creation is a distinct API surface from per-zone DNS edit, so it mints a narrow alias. Widening would also put zone-create authority on a credential four production concerns already depend on |
| Cloudflare's official multi-signer DNSSEC migration | **Rejected as unavailable.** `cloudflare_zone_dnssec` in the pinned 4.52.7 has no `dnssec_multi_signer` argument, and the legacy Google-Domains-derived provider will not cross-import zone-signing keys. Revisit only alongside a provider major bump |
| Flip the nameservers first and fix DNSSEC after | **Rejected — this is the failure mode.** It publishes a DS whose key no longer signs the zone, and every validating resolver returns SERVFAIL for the entire domain, mail included |
| **Transfer registration to Cloudflare Registrar now, instead of delegating** | **Rejected as not an available option** — see below |
| **Transfer registration to Cloudflare Registrar later, as a tracked follow-through** | **Adopted (D3)** — see below |

### The registrar fork, decided

This is a technical fork and is decided here rather than referred
(`hr-technical-fork-is-not-an-operator-question`).

The fork is not either/or, because Cloudflare Registrar **requires the domain to already
be active on Cloudflare** before a transfer-in can be initiated. DNS delegation is
therefore a *precondition* of the transfer, not an alternative to it. "Transfer instead of
delegating" is not on the menu.

The remaining question is whether the transfer belongs in this change or after it.
**After.** Four reasons:

1. **It cannot be in this change.** Activation is a Phase 7 outcome; the transfer cannot
   begin before it.
2. **ICANN's 60-day lock probably forbids it anyway.** The registrar record changed
   2026-08-07; at 2026-09-09 that is ~33 days, so a lock, if triggered, runs to roughly
   2026-10-06. `clientTransferProhibited` is independently set and would also need lifting.
3. **It must not share a change window with the mail cutover.** Mail continuity is the
   acceptance criterion. Changing registrar-of-record concurrently would split the
   remediation path across two vendors at the exact moment the failure signal travels
   through the thing being changed.
4. **It is nonetheless the right end state, and that is why it is enrolled rather than
   dropped.** Cloudflare Registrar pins a domain's nameservers to the account's assigned
   set, which structurally removes the "nameservers never repointed" failure that caused
   this incident — it is the durable fix, not a cost optimisation. It is also cost-negative
   at roughly $10.46/yr at cost. Note it is dashboard-only: there is no
   `cloudflare_registrar_domain` resource in the pinned 4.52.7, and no transfer-in API.

**Decision:** delegate DNS now; enrol the transfer as a tracked follow-through whose
re-evaluation trigger is *(zone active for ≥7 days) AND (date ≥ 2026-10-07) AND (mail
continuity probe green)*. Filed with a re-evaluation criterion and a milestone, per
`wg-when-deferring-a-capability-create-a`.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `terraform validate` in the new root | passes against 4.52.7 |
| T2 | Guard 1 mutation rows 1-6 | each drives RED |
| T3 | Guard 1 harness rows H1/H2 | H1 RED, H2 PASS |
| T4 | Guard 2 mutation rows 1-5 | 1,4,5 RED; 2 transient; 3 PASS |
| T5 | Guard 2 harness rows H1/H2 | H1 RED, H2 PASS |
| T6 | Follow-through probe against a pre-cutover world | exit 2 (transient), never 0 |
| T7 | Follow-through probe with credentials absent | DNS limbs still run; credentialed limbs report SKIP-DECLARED, never a silent pass |
| T8 | `lint-guard-contract.py` over this plan | exit 0 |
| T9 | `lint-infra-no-human-steps.py --changed` | exit 0 |
| T10 | Apply-workflow path filter | matches a file that exists under `infra/jikigai-dns/` |
| T11 | Drift-cron matrix | includes the new root; the `token_drift` step skips on that leg |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- **`name = "@"` is a destroy-and-recreate on every plan.** The Cloudflare API normalizes `@` to the FQDN and `name` is ForceNew. Apex records use the literal `jikigai.com`.
- **`terraform plan` will happily report `1 to add` for a resource whose apply 403s**, because it never calls the API for a resource absent from state. The credential probe belongs at plan time, which is where it ran.
- **Researched provider docs describe the latest version, not the pinned one.** Both `cloudflare_zone` and `cloudflare_zone_dnssec` were returned in v5 shapes by external research and are wrong for 4.52.7. Dump the schema locally.
- **The Cloudflare anycast edge lags the API by tens of seconds after an apply.** Immediately post-apply, verify through the REST API; use `dig` for what the world sees, not for what was just written.
- **A pending free-plan zone is deleted at 28 days.** This is the root cause of the incident, and it applies to the replacement zone from the moment it is created.
- **`jump_start = true` imports records Terraform does not manage**, producing exactly the divergence Guard 1 exists to catch. It is set false and asserted.
- **Do not delete the Google-side DNS zone** until the follow-through closes; it is the Phase 7 rollback target.
- **Destroying and recreating the zone changes BOTH its id and its assigned nameserver pair.**
  This is the mechanism behind the Phase 7.0 pre-flight and the Day-21 abort: any nameserver
  value recorded before a recreate is silently wrong, and writing it at the registrar delegates
  the domain to nameservers that serve nothing.
- **A follow-through `earliest=` is a hard wall-clock gate evaluated BEFORE the script runs.**
  A far-future `earliest` therefore does not merely delay closure — it means the probe never
  executes during the window it was written to watch. Set `earliest` to the filing date and let
  the script self-gate with exit 2.
- **`Ref #N`, not `Closes #N`.** The remediation completes after merge; an auto-close at merge records a false-resolved state.
