# Holder inventory: provider coverage design

## Disposition

Offline design only. These are candidate read surfaces, not executable
collection commands or a grant of authority. No account, provider, credential,
database or customer data was queried. Project/organization identities,
effective permissions, runtime response schemas, limits and deployment inventory
remain unverified. The previous catalog-capture approval was consumed. The
holder collector, independent technical/privacy review and separate exact-command
approval remain prerequisites to any live collection.

This design narrows [the holder-evidence contract](holder-evidence-preparation-2026-10-27.md);
it does not supersede it. Provider output is untrusted. Enforce HTTPS, fixed
hosts/paths, no redirects to a different authority, bounded time and response
bytes, per-source status, and a reviewed projection *before* persistence. Do
not log raw responses or errors. Use numeric provider identifiers in private
receipts where possible; their presence may still identify a person. Labels,
branches, service names and secret-reference names are arbitrary strings: use
approved classifications or a separately reviewed mapping; never persist an
unrecognized raw string merely because it is a metadata field.

## GitHub

The repository and workflow numeric IDs/path pairs are listed in the
[writer-window preparation](writer-window-preparation-2026-10-27.md). Inspect
these surfaces separately. A provider success or empty list is not permission,
holder or writer clearance; list changes during pagination remain possible.

| Candidate read surface | Documented authorization and pagination | Candidate private projection and unresolved coverage |
|---|---|---|
| `GET /repos/{owner}/{repo}/actions/workflows/{id}` and `/runs` | Actions repository read; per-page maximum 100. Follow and validate every `Link` page; filtered run searches have a documented 1,000-result ceiling. [GitHub workflow runs](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow) | Fixed workflow ID/path/state and run ID, status, conclusion, event, initiating actor ID and reviewed ref representation. A hash of a ref is potentially identifying and is not a usable ref; unresolved ref mapping stays unknown. Record interval, page termination, changing counts, statuses and all refs; no state sample fences future admission or runs. |
| `GET /repos/{owner}/{repo}/collaborators` | Metadata repository read for fine-grained credentials; documented user/organization conditions apply; page through every result. [Collaborators](https://docs.github.com/en/rest/collaborators/collaborators#list-repository-collaborators) | Numeric user ID, highest documented role and permitted boolean flags only. GitHub says the response includes inherited sources but does not distinguish organization from repository grant origin; custom roles, external principals and the ability to dispatch or alter a specific workflow still require their own mapping. |
| `GET /orgs/{org}/installations` | GitHub documents organization Administration read and an organization-owner condition; paginate. [Organization installations](https://docs.github.com/en/rest/orgs/orgs#list-app-installations-for-an-organization) | Installation ID, app ID, repository selection, suspension state and allowlisted action/administration permissions only. First establish whether the repository is organization-owned; otherwise this arm is unsupported. This identifies installations, not credentials or processes using them. Selected-repository installations require independently verified repository membership per installation. |
| `GET /installation/repositories` | Installation access token for the **observed installation**, no additional permission, paginated. [Installation repositories](https://docs.github.com/en/rest/apps/installations#list-repositories-accessible-to-the-app-installation) | Numeric repository IDs and the installation identity only. This endpoint covers the token's own installation; an existing token for one App cannot enumerate another App's repositories. No new token mint is implied. Inaccessible installations are unknown, not absent. |
| `GET /repos/{owner}/{repo}/environments` and environment metadata | Actions repository read for listing; paginate. [Environments](https://docs.github.com/en/rest/deployments/environments#list-environments) | Environment ID, reviewed name classification, protection-rule types, reviewer user/team numeric IDs and branch-policy flags. Team membership, bypass actors, custom protection apps and whether a job can actually use an environment require additional source-specific coverage; unknown if unavailable. |
| Repository, organization and environment Actions secret metadata | Repository Secrets read, organization Secrets read, or repository Environments read respectively; paginate each applicable list. [Secret metadata](https://docs.github.com/en/rest/actions/secrets) | Classify only preapproved reference names, timestamps if required, and org visibility/repository association. Unknown names map to `other` and raw names are not retained. No values are returned by the documented listing endpoints, but verify shape and do not fetch public keys, token values or secret content. |

GitHub's [pagination contract](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api)
uses `Link` headers; endpoint-specific cursors can differ. Validate the next
URL's host, target and permitted query parameters; enforce cycle/page/row/byte
caps and mark unexpected pagination, duplicates, inconsistent totals or missing
pages `partial`/`failed`. The 1,000 search-result limit applies to the
documented filter set: do not interpret reaching it as a complete census.
Installing, minting, widening or changing any credential is outside this design.

## Supabase

- Candidate organization roster: `GET /v1/organizations/{slug}/members`.
  The [Management API reference](https://supabase.com/docs/reference/api/v1-list-organization-members)
  specifies OAuth `organizations:read` or fine-grained `members_read`. The
  documented response includes `user_id`, `user_name`, `email`, `role_name`,
  MFA and avatar fields. Candidate projection is only `user_id` and an
  allowlisted `role_name`; exclude email, name, MFA and avatar. The reference
  does not establish a pagination contract on this endpoint; do not invent
  one or equate an unverified response with a complete organization census.
- Supabase supports organization-wide and project-scoped member roles.
  [Access control](https://supabase.com/docs/guides/platform/access-control)
  makes organization roster alone insufficient to derive effective project
  access. A documented, minimally scoped project-membership source, role
  expansion and pagination contract are still unverified; project-specific
  holders remain `unknown` until independently established.
- Secret and legacy `service_role` keys can authorize the `service_role`
  database role and bypass RLS; old keys can remain valid alongside newer keys.
  [API key behavior](https://supabase.com/docs/guides/getting-started/api-keys)
  does not identify copied values or processes. Do not query the Management
  API key endpoint as a metadata shortcut: the documented
  [key response](https://supabase.com/docs/reference/api/v1-get-project-api-key)
  includes an `api_key` field and permits reveal. It is not established that
  the intended call cannot return a secret value. A safe, reviewed key-metadata
  path and its exact scopes remain unknown. No key retrieval, rotation or
  revocation is authorized here.

## Doppler

- Candidate config-scoped roster: `GET /v3/configs/config/tokens` with explicit
  project and config. The [list reference](https://docs.doppler.com/reference/service_tokens-list)
  identifies the endpoint and required parameters but does not expose a reliable
  pagination or required-permission contract in its rendered response. The
  [service-token object](https://docs.doppler.com/reference/service_tokens-object)
  documents name, slug, project, environment, config, timestamps and access;
  it says the `key` value is available only on creation. Treat that as a
  documentation claim, not proof about an untested live response. A collector
  must reject unexpected key-bearing or unparseable responses without printing
  or persisting them, and must not invoke token creation.
- A token roster for `dev_scheduled` is not a principal census. Config-scoped
  service tokens, workplace/service-account identities, direct user/group
  access, wider administrative roles and inherited config access are separate
  paths. [Project permissions](https://docs.doppler.com/docs/project-permissions),
  [custom roles](https://docs.doppler.com/docs/custom-roles) and
  [service accounts](https://docs.doppler.com/docs/service-accounts) describe
  the role and scope distinctions; exact inventory endpoints, permissions,
  pagination and all effective role combinations still require verification.
  Candidate token projection is opaque slug, fixed config association,
  allowlisted access class and expiry; do not retain raw token, token preview,
  display name, email or arbitrary role description.
- Candidate activity evidence: `GET /v3/logs` or config logs with documented
  page parameters. The [config-log schema](https://docs.doppler.com/reference/config_logs-list)
  contains free-form text/HTML and a user object with email and name; these
  fields are excluded. Event category, stable actor ID, completeness and
  retention coverage are not established by that schema. Filtering logs cannot
  prove that no earlier read, export or cached fallback exists; Doppler documents
  a [CLI fallback file](https://docs.doppler.com/docs/service-tokens) that can
  remain usable after token revocation.

## Persistent and local consumers

At the referenced branch, all three named workflows reference the same
dev-scoped Doppler secret name; the tenant and scheduled workflows also invoke
the bot-fixture seed. Those source references establish possible routes, not
which credentials are currently configured, where they were copied or which
process is active. Inventory source declarations, current deployment records,
scheduled work, environment references and audit evidence separately, then
reconcile each to a concrete fence. Include local execution on the controlled
host only; other machines, cached exports, offline agents and future reconnects
remain unknown.

Deployment inventories must be selected from verified repository infrastructure
and bounded to the actual development project/account, not inferred from a
production deployment. For example, Cloudflare documents a [Pages project list](https://developers.cloudflare.com/api/resources/pages/subresources/projects/methods/list/),
but its response schema can contain environment values, build commands and
token-bearing fields. It is not an approved metadata-only collector: source
scope, read permission, pagination and an in-memory field projection must be
reviewed before use. Other runtime, worker, scheduler and container inventories
remain unknown until their owning platform and metadata APIs are established.
No absence claim follows from a missing deployment record.

## Completeness and review gates

For each source record `complete`, `partial`, `failed` or `unsupported` with
capture start/end, source identity, row/page/byte/time limits, termination
reason and observed count. `complete` means only the reviewed source traversal,
not a stable cross-provider snapshot or clearance. Treat 401/403/404/429,
unknown fields needed for classification, duplicate or malformed pages,
unverified pagination, hidden project scope and expired evidence as unknown;
do not substitute zero. Bound and categorize errors without copying bodies.

Before an approval request, bind the actual code, provider hosts and paths,
fields, limits, identities, credential scope and cleanup mechanism in one
immutable reviewed manifest. Test synthetic error and pagination cases, then
obtain independent technical, GDPR and CLO review. The identity and access
metadata, even when reduced to numeric IDs or hashes, remains potentially
personal data. Retention and deletion remain governed by the preparation
contract. A complete provider roster alone never proves cached credentials or
all writers have been excluded.
