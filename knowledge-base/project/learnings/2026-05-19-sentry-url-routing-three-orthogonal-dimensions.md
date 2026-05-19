# Learning: Sentry URL routing has THREE orthogonal dimensions — slug, cluster, token scope

**Date:** 2026-05-19
**Category:** workflow-patterns / vendor-topology
**Source:** brainstorm `2026-05-19-sentry-residency-reframe-3861-brainstorm.md`, Sentry support replies 2026-05-19
**Brand-survival threshold:** single-user incident (corrects prior published learning)
**Supersedes (partial):** the two-dimensional model in [[2026-05-15-sentry-dsn-cluster-substring-authoritative-residency]]

## Problem

The 2026-05-15 learning `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md` established two facts:

1. **DSN cluster substring is authoritative for residency** — the `.de.sentry.io` / `.us.sentry.io` substring in the DSN determines which Sentry database cluster receives the events. (Still true.)
2. **Cluster substring ≠ admin-controllability** — a DSN can point to a cluster you can audit at the substring level without your account having any membership/admin relationship to the destination org. (Still true, but learned in service of a wrong story.)

The implicit two-dimensional model was: `(DB cluster) × (operator admin membership)`. This model produced a misclassification on 2026-05-16: when probing `https://eu.sentry.io/api/0/organizations/jikigai/` with the runtime `SENTRY_AUTH_TOKEN` returned 401, the model concluded "operator has no admin membership in the destination cluster → destination is unowned third-party."

On 2026-05-19, Sentry support replies revealed:

- Both `jikigai` and `jikigai-eu` orgs are on **EU databases** (same cluster).
- Org `4511123328466944` (jikigai) is **operator-owned**.
- Both orgs accessible at distinct URL slugs: `https://jikigai.sentry.io/...` and `https://jikigai-eu.sentry.io/...`.
- The runtime token's 401 against the `jikigai` slug was almost certainly a token-scope mismatch (token minted only for `jikigai-eu` slug).

The two-dimensional model couldn't reconcile these facts. It needed a third dimension.

## Solution

**Sentry has THREE orthogonal dimensions, not two:**

| Dimension | What it is | How to read it |
|---|---|---|
| **URL front-door slug** | `<slug>.sentry.io` host or path component | Visual / DNS resolution. `jikigai.sentry.io` and `jikigai-eu.sentry.io` are different URL slugs. |
| **Database cluster** | EU (de) vs US ingest databases | DSN substring (`o<id>.ingest.de.sentry.io` = EU). Authoritative for residency. Independent of slug. |
| **Token-membership scope** | Per-token org-scope grants | `SENTRY_AUTH_TOKEN`'s scope list at mint time. Independent of who-owns-the-org. |

These three dimensions are **independent**: a single org has exactly one slug AND exactly one cluster AND zero-or-more tokens scoped to it. Two orgs with different slugs CAN be on the same cluster (jikigai + jikigai-eu both EU). A single owner CAN have multiple orgs on the same cluster with separately-scoped tokens. The dashboard URL front door (`<slug>.sentry.io`) does NOT imply a separate cluster — it's pure URL routing.

**Implications for residency reasoning:**

- DSN cluster substring is still authoritative for residency (Article 30 §(e)).
- Operator admin-membership is determined by **org ownership** (queryable only via Sentry support, not by API probe alone).
- API probe access is determined by **token scope**, which is independent of ownership.
- A 401 on `/api/0/organizations/<slug>/` reveals nothing about which of (a) slug doesn't exist, (b) token has wrong scope, (c) operator is genuinely not a member — see companion learning `2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md` for the disambiguating probe.

**Implications for IaC / token minting:**

- Each Sentry org needs its own scoped token. A token minted for org A returns 401 for org B even if the operator owns both.
- The `org:read` scope on a token is bound to a specific slug at mint time.
- Multi-org IaC needs to either (i) mint one token per org-slug, or (ii) use a personal user-token with cross-org visibility (broader blast radius — not recommended for runtime).

## Key Insight

When reasoning about a vendor's organizational topology, count the orthogonal dimensions before committing a model to corpus. A two-dimensional model that "explains" the observed behavior is not proof the topology IS two-dimensional — it may be a three-dimensional topology projected onto two axes by your observation surface. The Sentry case: `(cluster, membership)` looked complete until support replies forced a third axis (`(cluster, ownership, token-scope)`), which then trivially reconciled all observations.

Test your model by enumerating: for a single resource, how many independent properties can vary? If you've named N properties and a new observation forces re-explaining an old observation, you've under-counted.

## Routing for downstream consumers

- **ADR-031** (`knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`) — the §DE region support section needs the three-dimensional language; the recipient-drift causal narrative drops out.
- **Article 30 register Vendor DPAs row** — DE-cluster claim remains true; cross-reference to PA8 §(d) recipient-drift block drops out (separate retraction in the §(d) block itself).
- **`apps/web-platform/scripts/sentry-monitors-audit.sh`** — the cluster-substring check remains valuable; the comment framing reframes from "destination-controllability" to "destination-controllability and token-scope match" (the audit script already checks token-scope via the `audit_token_destination_match` gate from PR-β #3945, just with a different motivating story).
- **Brainstorm SKILL.md Phase 1.1** — add a verification pattern noting "vendor topology dimensions: list them explicitly before letting an observation surface bound your model" (likely PR-2 candidate).

## Session Errors

None directly. This learning corrects a model committed across three PRs (#3904, #3945, #3946) on 2026-05-17.

**Prevention:** when a learning is published that names a vendor topology, add an explicit "Dimensions" section listing the axes counted. Future brainstorms grep for that section and check whether their observations stay inside the named dimensions — an observation that requires re-explaining is a signal to look for an unaccounted axis.

## Tags

category: workflow-patterns
module: vendor-topology / sentry / residency
