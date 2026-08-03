# Decision challenges — feat-one-shot-7159-doppler-prd-read-token-coverage

Recorded per ADR-084 / `decision-principles.md`. The first two entries (UC-1, UC-2) were raised
in a headless session on 2026-08-02, so nothing was asked interactively then. On **2026-08-03**
the operator was shown the measurements and answered both open questions in an interactive
`AskUserQuestion`. Both answers are recorded below, and the entries have been resolved rather
than deleted — the measurements that produced them are why the design changed.

**The operator's two answers, verbatim in effect:**

1. **Credential shape — a project-scoped SERVICE ACCOUNT.**
   `doppler_service_account` + `doppler_project_member_service_account` +
   `doppler_service_account_token`. One credential enumerates all 13 configs. The union is
   dropped; `doppler_service_token` is not used.
2. **Coverage ladder — ratio plus floor state.** Emit `coverage_ratio: configs/expected` and a
   state from `unknown | degraded | at-floor`. `multi-config` is retired. The close arm fires
   on `at-floor`. The denominator **reports**; it does **not** gate — a short inventory must
   never be able to derive a healthy state and silence the channel.

---

## UC-1 — The checklist's swap: **SUPERSEDED** (the concern dissolved at the chosen shape)

**Class:** User-Challenge (the operator's direction is the default).
**Status:** superseded by the 2026-08-03 shape decision. Kept because the measurement below is
what forced the shape change.

**Direction as stated (#7159 decision comment, 2026-08-02):**

> - Point the token-drift step's `DOPPLER_TOKEN` at `secrets.DOPPLER_TOKEN_DRIFT`.
> - Verify: a scheduled run reports `coverage: multi-config`, and the
>   `Close the coverage issue once the fan-out is restored` step auto-closes the recurring
>   `token-drift-coverage` issue.

**Measured 2026-08-02** (ephemeral read credentials, revoked in the same command):

1. A `prd`-ROOT read **service token** enumerates **exactly one** config.
   `GET /v3/configs?project=soleur` returns 1 with `success: true` — a list silently scoped to
   the credential, not an error. `GET /v3/environments?project=soleur` returns `[]`.

2. The two configs' key sets are **not in a superset relation in either direction**.
   `prd_terraform` carries `CI_SSH_ACCESS_TOKEN_ID/_SECRET` and 10 `CF_API_TOKEN*` keys;
   `prd` root carries `CF_API_TOKEN_DNS_EDIT`, `CF_API_TOKEN_PURGE` and
   `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET`.

**What that implied at the time.** A literal swap of one config-scoped token for another would
have dropped the `CI_SSH_ACCESS_TOKEN` pair — the credential whose staleness produced the
63-hour outage recorded in ADR-154 — from continuous scanning, and pinned `configs` at 1
forever. The v1–v3 plans therefore proposed a **union**: keep `DOPPLER_TOKEN`, add
`DOPPLER_TOKEN_DRIFT`.

**Resolution (2026-08-03).** The concern **dissolves** at the chosen credential shape. A
project-scoped `viewer` reads `prd_terraform` as well as `prd`, so a swap drops nothing. The
union is dropped and the checklist's instruction is implemented **literally**: the token-drift
step's `DOPPLER_TOKEN` is sourced from `secrets.DOPPLER_TOKEN_DRIFT`. Both of UC-1's
consequences are void:

- No coverage regression. `CI_SSH_ACCESS_TOKEN` stays in scope, and
  `REGISTRY_PUSH_ACCESS_TOKEN` — the *first* case the detector's header cites as motivating it,
  and not scanned at all today — comes into scope for the first time.
- No unreachable Done-when. The scan reaches `coverage: at-floor` at `coverage_ratio: 13/13`,
  and the `Close the coverage issue once the fan-out is restored` step auto-closes the recurring
  `token-drift-coverage` issue, exactly as the checklist specifies.

**What survives.** Only the vocabulary change. `multi-config` is still retired — the same
issue's "Known follow-up" section says a 2-config scan deriving `multi-config` "would go quiet
while still missing the fan-out class", and the ladder the operator chose replaces it with a
ratio plus a floor state. The closing condition is `coverage: at-floor`, which is reachable and
which the first post-merge scan is expected to satisfy at `13/13`.

---

## UC-2 — A fourth credential shape the option table did not consider: **ADOPTED**

**Class:** User-Challenge.
**Status:** **ADOPTED 2026-08-03.** The operator was asked directly, shown the measurements
below, and chose this shape. It is no longer deferred and no tracking issue is filed for it.

**Direction as stated:** the option table in #7159 lists three shapes — a read token on the
`prd` root, a `for_each` token per config, and reuse of `DOPPLER_TOKEN_TF` — and asserts:

> there is no single project-scoped read token to mint.

**The falsified premise.** That sentence is **true for `doppler_service_token`** and **false for
`doppler_service_account`** in the pinned provider. `DopplerHQ/doppler v1.21.2`
(`.terraform.lock.hcl`) ships three resources the option table does not mention —
`doppler_service_account`, `doppler_project_member_service_account` and
`doppler_service_account_token` — which together produce a workplace identity holding a
project-scoped membership, minted in-band by the provider, needing no credential-entry step and
therefore compliant with `hr-tf-variable-no-operator-mint-default`. Read from the pinned
provider binary via `terraform providers schema -json` on 2026-08-03; recorded as probe D in
the plan's Appendix A. The premise was stated as a fact about Doppler when it is a fact about
one resource type.

**What the shape delivers.** One credential enumerates all 13 configs across all 4 environments.
The union is unnecessary, credential-iteration disappears from the detector, and the fan-out gap
that UC-2 was going to own as a deferred capability is closed by this change rather than tracked
past it.

**What it costs, stated plainly.** The credential reads the **entire `soleur` project** — wider
than the "whole prd tree" #7159 accepted, and wider than the pre-existing `DOPPLER_TOKEN_PRD`
repository secret. It resolves `GHCR_MINTER_DOPPLER_TOKEN` (a read/write Doppler token), the
Terraform GitHub App private key (an App with `secrets:write`) and `SUPABASE_SERVICE_ROLE_KEY`,
plus every secret in `dev`, `ci` and `cli`. The v3 mitigation — "adds no new capability, a
second copy of an existing scope" — is **false** at this shape and has been **withdrawn from
the plan, not softened**. The operator chose this knowingly; it is recorded as an accepted,
disclosed trade-off in `## Encryption Posture` and `## User-Brand Impact`.

**What bounds it, each verified rather than assumed:**

- `role = "viewer"` is the least-privileged role that can read secret values. Verified via
  `GET /v3/projects/roles`: it carries `enclave_project_config_secrets_read` and does **not**
  carry `enclave_project_config_secrets_write`. The only lower role, `no_access`, has zero
  permissions. Disclosed alongside: `viewer` also carries
  `enclave_project_config_dynamic_secrets_leases_write` (a write verb),
  `enclave_project_config_dynamic_secrets_read`,
  `enclave_project_config_rotated_secrets_read` and `enclave_config_logs`.
- `workplace_role` and `workplace_permissions` are **left unset**, so the project membership is
  the identity's only grant — it cannot reach any other Doppler project.
- `environments` is **left unset** (project-wide), justified by a measured per-config census of
  scannable keys on 2026-08-03: only `cli` and `cli_ops` are vacuous, so scoping to `prd` would
  forfeit 7 scannable keys across `dev*` and `ci` while removing **none** of the escalation
  hops, which all live in `prd` root.
- Unlike `DOPPLER_TOKEN_PRD`, the credential is Terraform-managed and rotates through
  `-replace=` in a single apply.

---

## UC-3 — The denominator needed a source the credential cannot move

**Class:** Design consequence of answer 2, resolved in-plan rather than escalated.

Answer 2 asks for `coverage_ratio: configs/expected` with the denominator reporting and never
gating. At the chosen credential shape, `doppler configs -p soleur` returns the project's true
total, so `configs == expected` holds **by construction** and `degraded` would have no producer.
A ratio that always prints `13/13` is decorative.

**Resolved as:** the *floor* is declared by the step (`DOPPLER_CONFIGS_FLOOR: 13`) and compared
one-sidedly (`configs >= floor → at-floor`); the *ratio* comes from the committed inventory and
gates nothing. `degraded` therefore detects a later narrowing: a downgraded membership role
(`0/13`), an `environments`-scoped membership (`7/13`), or `DOPPLER_TOKEN_DRIFT` repointed at a
config-scoped service token (`1/13`) — plus an absent or revoked credential. The floor is pinned
against the inventory's name count by a repo-internal CI assertion, so lowering it is a red
test rather than a silent state change. Full derivation, including the three rejected
alternatives, is in the plan's `## How the denominator is obtained`.

**What the operator may want to overturn:** a config *deletion* reds the coverage channel until
the floor is lowered. That is deliberate — a mechanism that let a shrinking live count lower its
own alarm threshold would be the very narrowing the floor exists to catch.

---

## Not challenged

- The credential shape as chosen on 2026-08-03: a project-scoped service account at
  `role = "viewer"`, with `environments`, `workplace_role` and `workplace_permissions` unset.
- The dedicated `DOPPLER_TOKEN_DRIFT` secret consumed only by the token-drift step.
- The absence of `lifecycle.ignore_changes` on `plaintext_value`.
- The absence of `expires_at` (reasoned in FR1, asserted by AC34).
- The four `-target=` allow-list additions.
- The accepted, disclosed trade-off that the credential reads the whole `soleur` project.
