---
title: Codex API account control evidence intake
date: 2026-10-07
pr: 9051
status: organization-selections-reloaded-project-region-and-retention-unconfirmed
---

# API account control evidence intake

The operator reports no custom OpenAI contract override. This establishes an
operator-reported amendment fact only; it does not independently identify the
contracting entity or establish acceptance of the applicable standard terms.

Five operator-supplied settings screenshots were inspected on 2026-10-07.
They show organization-level controls. Raw images, local screenshot paths,
account identifiers and credential values are not included in this record.
The screenshots do not identify the nominated test project, establish saved
server state, or show its project-level overrides.

| Organization control | Visible selection or state |
|---|---|
| Model feedback sharing | Disabled |
| Evaluation and fine-tuning data sharing | Disabled |
| Input and output sharing | Disabled |
| API call logging | Enabled per call |
| Usage dashboard visibility | Visible to everyone |
| Logs page visibility | Visible to organization owners |
| MCP, web search, file search, image generation and Code Interpreter | Enabled for all projects |
| Text watermarking | Off |
| Audit logging | An activation button is visible; activation is not evidenced |
| Retention/storage panel | A storage-load error is visible; no ZDR/MAM policy is displayed |

The sharing screenshot includes a Save button. At initial intake, reload
confirmation was pending; the subsequent confirmation is recorded below.
“Everyone” is the UI
label for the organization setting, not evidence of public Internet access.
Hosted-tool enablement does not authorize a hosted ChatGPT sign-in integration.

The storage-load error does not establish either presence or absence of Zero
Data Retention, Modified Abuse Monitoring or a storage destination. The
[official data-control guide](https://developers.openai.com/api/docs/guides/your-data#configuring-data-retention-controls)
distinguishes organization and project retention controls; request-level
storage behavior must also be assessed independently. No retention reduction
is inferred from disabled sharing or per-call logging.

Remaining factual inputs are binding to the nominated test organization/project,
project geography and overrides, retention policy,
and the existing account/entity/agreement/custody evidence. The earlier
operator-reported Global geography, US$5 project limit and seven-day maximum
key lifetime remain separate historical observations.

The [official ChatGPT plan-usage overview](https://developers.openai.com/siwc/token-sharing-open-source)
describes open-source/local apps and directs paid or remotely hosted apps to
its interest form. Whether OpenAI has approved Soleur's particular hosted
integration remains unknown. No form was submitted and no authentication or
provider call was made during this intake.

This is factual intake, not an attributable CLO disposition. Carry forward the
[current CLO packet](clo-decision-packet.md#public-source-clo-reassessment--2026-10-05):
API-key mode remains PENDING without live authorization; the existing managed
hosted-auth path remains BLOCKED pending a provider-permitted integration.
Keep PR #9051 draft, Codex default-off and customer content blocked.

## Reload confirmation — 2026-10-07

The operator reports that the settings remain the same after reloading and
supplied a further retention screenshot. This supports persistence of the
displayed organization selections in the reloaded UI; it is not an independent
API readback or proof of test-project overrides. The storage-load error and
per-call logging selection remain visible. No ZDR/MAM policy is displayed.

The operator reports that General does not show geography or region. Record
that field as not displayed; do not infer a new regional setting from absence
or replace the historical Global observation with a stronger residency claim.
The repeated organization-level retention screenshot does not identify the
nominated test project. The existing mode dispositions remain unchanged.

## Hosted-integration permission report — 2026-10-07

The operator reports no OpenAI approval or written permission for Soleur's
hosted ChatGPT integration. This is an explicit absence report, superseding
the earlier unknown permission state in this intake. The existing managed
hosted-auth path remains blocked; this report neither rejects nor authorizes
the separate API-key mode. No interest-form or support submission was made.

## Missing control evidence: prepared support request

The repeated storage-load error and absent General field leave retention and
region unconfirmed. Additional copies of the same screen would not resolve
those fields. The operator can provide a sanitized support reply, scoped to
the nominated test project by an alias. No credentials or project IDs are
needed in the repository evidence. This request has not been sent:

> Our organization's Data retention page repeatedly says it cannot load
> storage, and the selected project's General page does not display a region.
> For our nominated test project, please confirm its effective abuse-monitoring
> retention policy (standard, approved MAM or approved ZDR), whether it inherits
> organization controls or has overrides, and its configured data storage and
> inference-processing regions. Please distinguish account configuration from
> endpoint-specific application-state storage and any residency exclusions.

A support response must be bound to the intended project; generic documentation
does not prove its actual settings. Record unanswered items as unknown. Provider
permission for the exact hosted authentication route remains a separate request
prepared in the [account guide](../feat-one-shot-codex-web-live-paths/account-evidence-guide-2026-10-06.md#exact-provider-route).

## Read-only inspection authorization and access results — 2026-10-07

The operator explicitly authorized read-only inspection of the nominated test
account's project metadata, project retention and inherited organization
retention. This supersedes only the earlier authenticated-settings-read hold.
Inference, setting changes, key creation, credential-value inspection and
browser-auth copying remain prohibited. It grants no Web qualification,
recovery retry, cohort change or promotion permission.

A fresh isolated, headed browser reached OpenAI sign-in. The operator entered
authentication directly in that browser, then reported repeated Cloudflare
verification. A redacted snapshot independently showed a security-verification
heading and human-verification checkbox. No authenticated project page was
observed. Challenge retries stopped and that browser was closed; no browser
authentication state was exported or copied.

A subsequent names-only check of Doppler `soleur` configs `prd`, `dev`,
`prd_terraform` and `cli_ops` returned no reference names containing `OPENAI`
or `CODEX`. No secret values were requested. This is limited reference discovery,
not proof that the nominated account has no key. Neither of the two checked
admin-key environment references was present. No running Chrome/Chromium/Brave
browser process was found for inspection in place.

The public Help Center loaded in a separate isolated browser. Its Open chat
button did not expose an intake form; after rejecting optional cookies, the
page displayed an error. The cause was not established. That browser was
closed. No support request, interest form or other external message was sent.

Official documentation supplies a concrete read-only alternative:

| Read | Documented result | Evidence limit |
|---|---|---|
| [Project metadata](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/methods/retrieve) | Optional `residency`, including Global, regional storage or combined storage/processing configurations | An omitted field does not establish a region |
| [Project retention](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/subresources/data_retention/methods/retrieve) | Project retention type, including `organization_default` | Inheritance needs the organization value |
| [Organization retention](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/data_retention/methods/retrieve) | Configured organization retention type | Availability or an error alone does not prove the effective policy |

These documented Admin API reads were not executed; the examples require admin
authentication and no suitable access reference was established. Project residency
also does not establish an actual request's processing location: the
[regional-processing guide](https://developers.openai.com/api/docs/guides/your-data#select-a-processing-region-per-request)
requires endpoint, model and eligibility checks. Account retention/inheritance
and configured storage/processing regions remain unconfirmed. The prepared
support request above remains unsent, and both mode dispositions are unchanged.
