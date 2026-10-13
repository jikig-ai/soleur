---
title: "fix(security): true least-privilege Doppler isolation for the zot registry host (pre-provision)"
feature: registry-oidc-migration
issue: "#6122"
adr: ADR-096 (amendment — Doppler credential isolation)
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-07
status: draft
---

# fix(security): true least-privilege Doppler isolation for the zot registry host 🐛🔒

> ⚠️ **SUPERSEDED MECHANISM — read before executing any step (CTO ruling, 2026-07-07, during `/work`).**
> This plan was authored proposing option **(b) a standalone `registry` ENVIRONMENT in `soleur`**. At
> implementation time that was found **infeasible**: the `soleur` project is at Doppler's **4-environment
> tier cap** (dev/prd/ci/cli) — a 5th environment needs a Team-plan upgrade (empirically confirmed:
> `doppler environments create` → "reached its limit of 4 environments"). The `cto` agent ruled for
> option **(a) a dedicated `soleur-registry` PROJECT** whose own `prd` root config holds only the two ZOT
> tokens (project creation is NOT tier-blocked). **The shipped fix uses the project.** Wherever this plan
> says `doppler_environment.registry` / `slug = "registry"` / `--config registry` / "the `registry`
> environment", the shipped reality is `doppler_project.registry` (name `soleur-registry`) /
> `config = "prd"` / `--project soleur-registry --config prd`. The load-bearing operator commands (AC11,
> the Observability `discoverability_test`, the Phase-4.1 gate script, failure_modes) are CORRECTED below
> to the shipped project; the Phase 0/1 narrative is left as the original planning record. Rationale +
> rejected alternatives: ADR-096 (2026-07-07 amendment) and #6167.

## Enhancement Summary

**Deepened on:** 2026-07-07 · **Review agents:** security-sentinel, architecture-strategist,
spec-flow-analyzer, user-impact-reviewer (all 4 confirmed the core approach isolates soundly).

**Key improvements folded in from review:**
1. **Self-enforcing isolation (highest-value).** The isolation guarantee is now a **cloud-init
   boot-time self-assertion** (Phase 2.5) that runs under the host's *actual* boot token
   (`doppler run --project soleur-registry --config prd`), counts non-`DOPPLER_` secrets == 2 AND asserts both are
   `ZOT_*`, and **`exit 1` before `docker run`** on any deviation. This closes the load-bearing gap
   all three security-lens reviewers flagged: every prior automated signal (empty-token guard,
   heartbeat, `terraform apply`) fails **open** on an over-scoped token — a token reading all 116
   secrets still boots clean. It also proves the *shipped* credential's scope (not a throwaway) and
   enforces *identity*, not just cardinality.
2. **Phase-0 go-condition corrected.** `terraform plan`-clean is INSUFFICIENT to select PRIMARY —
   `#6067` was an apply-time **Doppler tier** rejection, not a plan/schema error. PRIMARY now
   requires an operator-acked real create+destroy apply; else default to FALLBACK.
3. **Audit issue filed FIRST** (Phase 0.3) so its number backfills the code comment + ADR (no
   `#NEW` placeholder ships), and its severity triage is **by provisioning status** — `prd_cla`
   (`apps/cla-evidence/infra/bootstrap.sh:224-257`) is a **live** over-read now, P1, not a dormant p2.
4. **QA script hardened:** identity assertion, revoke-by-slug with `trap … EXIT` (no dangling live
   token on the failure path).
5. **C4 `doppler -> zotRegistry` edge added** (cheap, consistency-restoring — this PR re-scopes that
   exact relationship; the model's 3 sibling `doppler -> …` "Injects secrets" edges lack it).

**New considerations discovered:** the fix's own false-isolation escape surface (manual-gate-skip,
empty-only boot guard, fallback-missing-env) is now enumerated; the `soleur` project already has a
non-dev/stg/prd environment (`cli`, per `flag-bootstrap/SETUP.md:18`), confirming a 4th environment
breaks no invariant.

## Overview

The DARK (unprovisioned) zot registry migration (`apps/web-platform/infra/zot-registry.tf`,
`cloud-init-registry.yml`) scopes the registry host's boot credential to a Doppler config
**`prd_registry`, created as a BRANCH CONFIG under the `prd` environment**, and claims (in code
comments) this isolates the host so "a host compromise reads nothing else."

**That claim is false and empirically disproven.** In Doppler, every config within an environment
resolves that environment's **root config** as its base — the environment-root→branch inheritance
is fundamental and always on, *independent* of the paid "config inheritance" (`inherits`) feature.
The official docs are explicit: root configs "serv[e] as the base from which all future configs
branch off … secrets will be inherited by branch configs **unless deleted**"
(<https://docs.doppler.com/docs/branch-configs>). A read service token minted against `prd_registry`
empirically read the **full 116-secret `prd` set**, including the real `SUPABASE_SERVICE_ROLE_KEY`,
`GIT_*` keys, and `PROXY_TLS_*`. Provisioning as-designed would hand a brand-new private-net host
(reachable via the CF tunnel) read access to **all** production secrets — the exact opposite of the
design's stated goal.

This is a **pre-provisioning correctness fix**, scoped to **zot only**. No zot resource is
provisioned (`terraform apply` never ran; last init Apr 3, pre-zot). It unblocks task **1.8
(PROVISION)** of the registry-OIDC cutover. It does **not** complete the cutover — issue **#6122
stays OPEN**.

**The fix:** re-point the registry host's Doppler resources at a **standalone `registry`
ENVIRONMENT** in the `soleur` project whose **own root config** holds ONLY `ZOT_PULL_TOKEN` +
`ZOT_PUSH_TOKEN`. A config in a *different* environment resolves *that* environment's root — never
`prd`'s — so a service token scoped to it reads exactly two secrets. (Approach chosen over a
dedicated project; see §Isolation-boundary decision.)

> ⚠️ **Broader (out-of-scope) context — separate follow-up issue, do NOT fix here:** the identical
> non-isolation affects the existing prod branch configs `prd_git_data` (git-data-luks.tf),
> `prd_kb_drift_walker` (kb-drift.tf), `prd_cla` (apps/cla-evidence/infra), and the `prd_ghcr`
> claim in ADR-088. "Scoped Doppler branch config = least privilege" is a **project-wide
> misconception** (git history shows it was asserted four times and verified zero times). Task 7
> files the audit issue; this PR fixes zot only.

## Research Reconciliation — Spec vs. Codebase

| Spec/code claim | Reality (empirically verified) | Plan response |
|---|---|---|
| `zot-registry.tf:63` "the DEDICATED `prd_registry` config (least-privilege)"; `:67` host "must NOT carry the full-prd token"; `cloud-init:100` "scoped to the prd_registry config (only the two ZOT tokens), so a host compromise reads nothing else" | FALSE. `prd_registry` is a **branch config under `prd`** → resolves the `prd` root → reads all 116 prd secrets incl. `SUPABASE_SERVICE_ROLE_KEY`. Verified: read token on `prd_registry` returned the full set. | Re-point host creds to a standalone `registry` **environment** (fresh root, 2 secrets). Rewrite all false comments. |
| `tasks.md:19` (1.3) "host-scoped … in operator-created `prd_registry` config (least-privilege, mirrors git-data-luks `prd_git_data`)" | The mirrored `prd_git_data` pattern is **itself broken** (same branch-config bug). Mirroring it propagated the defect. | Correct 1.3; stop citing `prd_git_data` as a least-privilege exemplar; note the departure + the follow-up audit issue. |
| `zot-registry.tf:71` OPERATOR NOTE: "the `prd_registry` config must exist in `prd` BEFORE apply … the Doppler provider does not manage the operator's environment+configs" | Partially stale premise. The provider CANNOT create **branch configs** here (workspace lacks "config inheritance" — 2026-07-05 `doppler_config.prd_ghcr` failure, PR #6067). But `doppler_environment` creates a **new environment + its own root config** — a different, basic "Project Structure" resource that does **not** need that feature. | Prefer TF-created `doppler_environment.registry` (removes the precondition); pre-declared fallback = operator-created env if Phase-0 verification fails. |
| ADR-088 amendment: "at-rest scope bound via config isolation [is] the isolation that actually matters" | The isolation claim is unsound for branch configs generally (prd_ghcr ultimately fell back to `prd` anyway). | Out of scope here; flagged in the Task-7 audit issue. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a provisioned private-net registry host whose
  0600 boot token can read every production secret — `SUPABASE_SERVICE_ROLE_KEY` (full read/write
  to **all users'** data, bypassing RLS), `GIT_*` transport keys, `PROXY_TLS_*`. A single
  registry-host compromise (a new CF-tunnel-reachable attack surface) becomes a total prod-secret
  breach.
- **If this leaks, the user's data / workflow / money is exposed via:** `SUPABASE_SERVICE_ROLE_KEY`
  → unrestricted read of every user's rows; `GIT_*` → repo/worktree access; `PROXY_TLS_*` → MITM of
  host↔host traffic.
- **The fix's OWN false-isolation escape surface** (why the verification must be self-enforcing, not
  manual): a subtly-wrong fix ships the same breach through any of — (a) the isolation check is
  skipped (it was a manual operator step); (b) the boot guard is blind (the existing `:118-119`
  empty-token check passes on an over-scoped 116-secret token); (c) the FALLBACK operator creates a
  branch config under `prd` (muscle-memory) instead of a standalone environment; (d) a partial edit
  repoints the secrets but leaves `doppler_service_token.registry` on `prd_registry`. Phase 2.5's
  boot-time self-assertion (fail-closed, on the shipped token, identity-checked) closes (a)-(d).
- **Brand-survival threshold:** single-user incident. (CPO sign-off required at plan time;
  `user-impact-reviewer` runs at review-time. Correct threshold — `SUPABASE_SERVICE_ROLE_KEY` exposes
  ALL users' data, which clears the single-user bar *a fortiori*; do NOT loosen to `aggregate
  pattern`. This PR *prevents* the exposure — but a wrong fix would ship the same breach at provision
  time, so the threshold governs *verification* rigor: the Phase-2.5 boot self-assert + Phase-4 QA
  count-assert are load-bearing, not ceremony.)

## Isolation-boundary decision (both options evaluated)

A `prd` **branch config cannot** achieve isolation — it always resolves the `prd` root (deleting
116 secrets from the branch and re-deleting every future prd secret forever is not a boundary).
True isolation requires a boundary that does **not share the prd root**. Two candidates:

| | **(a) Dedicated PROJECT `soleur-registry` ✅ SHIPPED (CTO ruling 2026-07-07 — see banner)** | **(b) Standalone ENVIRONMENT `registry` in `soleur` — ❌ INFEASIBLE (4-env tier cap)** |
|---|---|---|
| Isolation | True — separate project, own roots. | True — the `registry` env's **own root config** holds only 2 tokens; a token scoped to it never resolves `prd`'s root. |
| Provider resource | `doppler_project` (exists, v1.21+). | `doppler_environment` (exists; Required: project/slug/name; creates the env + its root config). |
| Needs "config inheritance" (workspace LACKS it)? | No. | No — a **root** config, not a branch config. This is the pivotal reason it can plausibly be TF-created where `doppler_config.prd_ghcr` could not. |
| TF-createable in THIS workspace? | Likely, but provider auth (`var.doppler_token_tf`) needs **workplace create-project** scope — unverified, heavier. | Provider already mints `soleur`-scoped configs/tokens (git-data, kb-drift, ghcr, write) — creating a new **environment** inside the already-managed project is the lighter, in-scope capability. **Phase-0 verified.** |
| Blast radius of CHANGE | Forces `--project soleur-registry` across cloud-init `doppler run` + the service-token mint + any push tooling; new project to govern/audit/rotate. | Keeps `--project soleur` everywhere; only the **config name** changes (`prd_registry` → `registry`). Minimal churn. |
| Operator-precondition impact | New project precondition if TF-create fails. | Removed entirely on the TF-create path; fallback = one dashboard step (same weight as today, now a *true* boundary). |
| Parity-test impact | New `doppler_project.*` → OPERATOR_APPLIED_EXCLUSIONS. | New `doppler_environment.registry` → OPERATOR_APPLIED_EXCLUSIONS (one line). |

**Rationale for (b):** identical isolation to (a) with strictly less disruption. It stays inside the
already-TF-managed `soleur` project (proven provider scope), changes only the config name, and — via
`doppler_environment` (a basic Project-Structure resource, not the branch-config path that this
workspace's plan tier blocks) — can be **Terraform-created**, *removing* the operator precondition
rather than merely relocating it. A dedicated project is disproportionate governance for a 2-secret
boundary and demands an unverified heavier provider scope. **Precedent that a 4th environment breaks
no invariant:** the `soleur` project already carries a non-dev/stg/prd environment `cli`
(`plugins/soleur/skills/flag-bootstrap/SETUP.md:18` — `doppler environments create cli cli -p
soleur`), and a repo sweep found no tooling that iterates a project's environments (all consumers are
`doppler run --config <x>`, config-pinned). Adding `registry` is precedented and non-disruptive.

**Capability-verification discipline (`hr-verify-repo-capability-claim-before-assert`):** whether
`doppler_environment` provider-create succeeds in this exact workspace is a *hypothesis*, not an
asserted fact — the `doppler_config.prd_ghcr` failure is the cautionary precedent. Phase 0 verifies
it empirically; a **pre-declared fallback** keeps the fix robust either way. The security outcome
(fresh root, 2 secrets, scoped token) is identical on both paths; only the presence of one operator
dashboard step differs.

## Implementation Phases

### Phase 0 — Empirical capability verification (no prod writes to the running fleet)

**0.1 — Verify `doppler_environment` provider-create in THIS workspace — REAL apply, not plan.**
⚠️ A clean `terraform plan` is NOT sufficient evidence to select PRIMARY: `#6067` (`fa12318d8`
"Doppler **tier** lacks config inheritance") was an **apply-time API rejection**, not a plan/schema
error — the provider accepts the resource shape and `plan` shows a clean create even when the
account tier will reject it at apply.
<!-- lint-infra-ignore start -->
So the PRIMARY go-condition is an **operator-acked real apply**
(`hr-menu-option-ack`) of a throwaway `doppler_environment` (project="soleur", slug="ziso-probe",
name="isolation-probe") against the live workspace token, `terraform apply` → confirm create
succeeds → immediate `terraform destroy`/`-target` remove. Record the verdict as an artifact (in the
ADR amendment + `tasks.md` 1.8 note), because downstream operator runbooks must know which path
shipped.
<!-- lint-infra-ignore end -->
(SUPERSEDED — the environment path was infeasible at the 4-env tier cap; the SHIPPED fix is the
dedicated `soleur-registry` PROJECT, which rides the operator's full apply per the banner + the
apply-path CTO ruling — the sanctioned fresh-host provisioning path CI structurally cannot run.)
- **Real create succeeds → PRIMARY path:** TF-created environment; the operator precondition is
  removed.
- **Create is tier-rejected at apply (or no operator ack available) → FALLBACK path:** the `registry`
  environment is an operator precondition — create once via dashboard: **Project → soleur → New
  ENVIRONMENT (slug `registry`) — NOT a "New config" under `prd`** (a branch config under `prd` is
  the exact bug this fixes and would silently not isolate). TF manages only the 2 `doppler_secret`s +
  the `doppler_service_token` at `config = "registry"`. Isolation is identical; one dashboard step
  remains. **Default to FALLBACK if the capability is unverified** — it is one dashboard step of
  identical weight to today, and it never risks a failed operator apply.

**0.2 — Confirm root-config auto-provisioning + FALLBACK fail-loud behavior.** (a) Verify a
`doppler_secret{config = "registry"}` targets the environment's auto-created root config directly (no
separate `doppler_config` — that is the blocked branch path; use FALLBACK if it's required). (b)
Empirically confirm the FALLBACK missing-env failure mode is fail-CLOSED: mint a token bound to a
**nonexistent** config and confirm `doppler run --config <nonexistent> -- …` **exits non-zero and
never resolves a default/prd config** (the plan's Observability "errors loudly" claim is otherwise an
unverified capability assertion, `hr-verify-repo-capability-claim-before-assert`). The cloud-init
boot self-check (Phase 2.5) is the backstop regardless.

**0.3 — File the audit follow-up issue FIRST (before Phases 2.1/6.1 reference it).** Create the
Task-7 issue now so its number backfills the `zot-registry.tf` comment and the ADR amendment — no
`#NEW` placeholder ships. (Full triage content in Phase 7; it is *created* here, *populated* there.)

**0.4 — Confirm the parity extractor enumerates `doppler_environment`.** Architecture review verified
`extractAllResources` (`terraform-target-parity.test.ts:348`, type regex `[a-z0-9_]+`) matches
`resource "doppler_environment" "registry"`, so the line-607 assertion fails-closed if the exclusion
is forgotten — AC3 is sound. Re-confirm at /work before relying on it.

### Phase 1 — Re-point the Doppler resources (`zot-registry.tf`)

**1.1** Add (PRIMARY path) `resource "doppler_environment" "registry" { project = "soleur"; slug =
"registry"; name = "Registry Host Isolation" }`. (FALLBACK path: omit; document the env as an
operator precondition.)

**1.2** Change the two host-scoped secrets — **keep the resource addresses**
(`doppler_secret.zot_pull_token_registry`, `doppler_secret.zot_push_token_registry`) to minimize
churn — repointing `config = "prd_registry"` → `config = doppler_environment.registry.slug`
(PRIMARY; the attribute ref creates the implicit dependency so the env exists first) or the literal
`"registry"` (FALLBACK, plus `depends_on` is unnecessary since the env is operator-made). Values
unchanged (`random_password.zot_pull/push.result`), `visibility = "masked"`, **no** `ignore_changes`
(TF owns them; rotation via `-replace`).

**1.3** Change `doppler_service_token.registry` — keep the address — to `config =
doppler_environment.registry.slug` (or `"registry"`). `access = "read"` unchanged.

**1.4** The **client/CI-facing** `prd` copies (`doppler_secret.zot_pull_token`,
`zot_push_token`, `zot_pull_user`, `zot_push_user`, `zot_registry_url`, `zot_heartbeat_url_prd`) are
**untouched** — web hosts + CI legitimately read these from the shared `prd` config; the isolation
concern is only the registry HOST's boot token. Retain the deliberate host-copy/client-copy
duplication; only the host copies' config changes.

### Phase 2 — Correct the false comments + the cloud-init invocation

**2.1** Rewrite `zot-registry.tf:63-75` (the "DEDICATED `prd_registry` config (least-privilege)"
block + OPERATOR NOTE). New comment states: the host reads a read-only token scoped to the
standalone **`registry` environment**, whose own root config holds ONLY the two ZOT tokens; a `prd`
**branch** config would resolve the `prd` root and expose all 116 prd secrets (the bug this fixes);
this **departs from** — does not mirror — the `prd_git_data`/`prd_kb_drift_walker` branch-config
pattern, which the Task-7 audit issue (#NEW) addresses. State the provisioning story for whichever
path Phase 0 selected (TF-created env / operator-created env).

**2.2** Rewrite `cloud-init-registry.yml:100` — the currently-false "scoped to the prd_registry
config … a host compromise reads nothing else." New: "scoped to the isolated `registry` environment
root (only the two ZOT tokens), so a host compromise reads nothing else" (now **true**).

**2.3** Update `cloud-init-registry.yml:108` (comment) and **:116** (the live invocation)
`doppler run --project soleur --config prd_registry` → `--config registry`.

**2.4** Sweep: `git grep -n prd_registry apps/web-platform/infra/` must return **zero** after edits
(the residual-zero check; excludes this plan + tasks.md, which are point-in-time records).

**2.5 — Self-enforcing boot-time isolation assertion (the load-bearing defense).** Insert into
`cloud-init-registry.yml`, inside the existing `doppler run --project soleur --config registry -- bash`
block (the one that builds htpasswd), a check that runs under the host's **actual** boot token and
**refuses to launch zot** if the credential can read anything beyond the two ZOT tokens — BEFORE the
`docker run`:
```bash
# Isolation self-check — the host's OWN scoped token must resolve EXACTLY the 2 ZOT tokens.
# Every other boot signal (empty-token guard, heartbeat, terraform apply) fails OPEN on an
# over-scoped credential (a 116-secret token still populates ZOT_PULL/PUSH non-empty); this is
# the only fail-CLOSED gate, and it runs on the shipped credential, not a throwaway.
names="$(doppler secrets --only-names --json | jq -r 'keys[]' | grep -v '^DOPPLER_' || true)"
n_total="$(printf '%s\n' "$names" | grep -c . || true)"
n_zot="$(printf '%s\n' "$names" | grep -Ec '^ZOT_(PULL|PUSH)_TOKEN$' || true)"
if [ "$n_total" -ne 2 ] || [ "$n_zot" -ne 2 ]; then
  echo "[zot] FATAL: boot credential is not isolated (sees $n_total non-DOPPLER secrets, $n_zot ZOT) — refusing to launch"; exit 1
fi
```
Rationale (all three security-lens reviewers): this converts isolation from a skippable manual
operator step into a host-level invariant, proves the **shipped** `doppler_service_token.registry`
scope (not a throwaway verify token, so a partial edit that repoints the secrets but leaves the
service token on `prd_registry` — or vice versa — fails the host loud), and asserts **identity**
(both are `ZOT_*`), not just cardinality. It is the fail-closed complement to the existing empty-token
guard (`:118-119`).

### Phase 3 — Parity test (`plugins/soleur/test/terraform-target-parity.test.ts`)

<!-- lint-infra-ignore start -->
**3.1** (SHIPPED: `doppler_project.registry`) Add it to `OPERATOR_APPLIED_EXCLUSIONS`
(the line-607 assertion enumerates **all** managed resources — verified — so a new resource without
a `-target` line or exclusion FAILS the test). It rides the operator full apply with the host, same
class as the other zot resources (the sanctioned fresh-host provisioning path per the apply-path CTO ruling).
<!-- lint-infra-ignore end -->

**3.2** Correct the misleading exclusion-block comments (~L524-526, L567-570) that say "prd_registry
host-token copies" / "the config does not exist until the operator creates it (runbook
precondition)" → describe the isolated `registry` environment and (PRIMARY) that TF creates it in
the operator's full apply while CI still cannot (no host).

**3.3** The three existing entries (`doppler_secret.zot_pull_token_registry`,
`doppler_secret.zot_push_token_registry`, `doppler_service_token.registry`) keep their addresses →
no removal needed; the `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` non-vacuity check still passes.

### Phase 4 — QA / verification (scoped-token count assertion — load-bearing)

**4.1** After the boundary exists (Phase-0 verification, or against a scratch mirror), mint a
throwaway read token and assert it sees **exactly the two** ZOT tokens, then revoke:
```bash
# Create with --json to capture BOTH the token value AND its slug; revoke by SLUG (revoking by the
# --plain value is unreliable). trap ensures the live throwaway token is revoked even on the FAIL
# exit path (otherwise an over-read failure leaves a 116-secret-capable token dangling).
resp=$(doppler configs tokens create zot-isolation-verify \
  --project soleur-registry --config prd --access read --json)
tok=$(jq -r '.key' <<<"$resp"); slug=$(jq -r '.slug' <<<"$resp")
trap 'doppler configs tokens revoke "$slug" --project soleur-registry --config prd >/dev/null 2>&1 || true' EXIT
# From a dir with NO doppler.yaml. Exclude Doppler's injected DOPPLER_* built-ins.
names=$(DOPPLER_TOKEN="$tok" doppler secrets --only-names --json | jq -r 'keys[]' | grep -v '^DOPPLER_' || true)
n_total=$(printf '%s\n' "$names" | grep -c . || true)
n_zot=$(printf '%s\n' "$names" | grep -Ec '^ZOT_(PULL|PUSH)_TOKEN$' || true)
# Assert BOTH cardinality (==2) AND identity (both are ZOT_) — count==2 of the WRONG two must FAIL.
if [ "$n_total" -eq 2 ] && [ "$n_zot" -eq 2 ]; then echo "PASS: isolated (exactly ZOT_PULL+PUSH)";
else echo "FAIL: $n_total non-DOPPLER secrets, $n_zot ZOT — NOT isolated"; exit 1; fi
```
> **Sharp edge (count semantics):** Doppler injects `DOPPLER_CONFIG`/`DOPPLER_ENVIRONMENT`/
> `DOPPLER_PROJECT` built-ins into every config, so a naive row-count is 5, not 2. The assertion
> counts **non-`DOPPLER_*`** names (== 2) AND confirms both are `ZOT_*`. The same scoped token on
> `prd`/`prd_registry` returns 116 non-built-in names — that contrast IS the regression proof.

**4.2** `terraform fmt` + `terraform validate` stay green. `tsc --noEmit` (`cd apps/web-platform &&
./node_modules/.bin/tsc --noEmit`) + the parity vitest suite pass:
`cd apps/web-platform && ../../node_modules/.bin/vitest run ../../plugins/soleur/test/terraform-target-parity.test.ts`
(confirm the runner/path at /work time against `package.json` scripts — do not assume).

### Phase 5 — Docs / runbook / spec references

**5.1** `tasks.md` task 1.3 — replace "operator-created `prd_registry` config (least-privilege,
mirrors git-data-luks `prd_git_data`)" with the isolated `registry`-environment description +
(PRIMARY) note the precondition is removed.

**5.2** `tasks.md` task 1.8 — the precondition line "requires `prd_registry` Doppler config
precondition" → (PRIMARY) drop the Doppler precondition (TF creates the env in the full apply);
(FALLBACK) "requires the `registry` **environment** precondition (create once via dashboard)."

**5.3** Add a `tasks.md` verification sub-item under 1.8: run the Phase-4.1 count-assert (== 2) as a
provisioning gate before flipping.

**5.4** Grep any runbook naming `prd_registry` (`git grep -rn prd_registry knowledge-base/` — the
provisioning/apply-path runbooks) and update, EXCLUDING this plan + `tasks.md` (point-in-time
records) and `apply-path-cto-ruling.md` line 39 (a historical CTO-ruling record — update only its
forward-looking precondition wording if present).

### Phase 6 — ADR-096 amendment (Architecture Decision deliverable)

**6.1** Amend `ADR-096` via `/soleur:architecture`: add a short **"Doppler credential isolation
(amendment 2026-07-07)"** subsection to `## Consequences` (or a new `### Credential isolation`).
Content: the registry host's boot credential is scoped to a **standalone `registry` environment**,
NOT a `prd` branch config, because branch configs inherit the environment root's full secret set
(the isolation the design originally claimed was structurally impossible for a branch config); the
`registry` environment's own root config holds only `ZOT_PULL_TOKEN` + `ZOT_PUSH_TOKEN`; verified by
the Phase-4 count-assert. Reference #6122 and the follow-up audit issue. Status stays **Adopting**.

**6.2 — C4 (completeness mandate; all three `.c4` files read).** Enumeration checked against
`model.c4` / `views.c4` / `spec.c4`: (external human actors) none new — the registry host + pull
hosts are internal `hetzner`; (external systems) `doppler` (model.c4:222) and `zotRegistry`
(model.c4:246) are already modeled; no new vendor; (data stores) none. **One in-scope edit
(access relationship):** the model has `doppler -> engine/claude/inngest "Injects secrets"` edges
(model.c4:289/340/359) but **no** `doppler -> zotRegistry` edge, even though the registry host
demonstrably reads a boot credential from Doppler (a pre-existing gap from the introducing PR #6120).
Because this PR is literally re-scoping that exact relationship, **add the symmetric edge** —
`doppler -> zotRegistry "Injects the registry-host boot credential (scoped isolated 'registry' env)"`
— which restores model consistency and correctly records the boundary this fix establishes. No new
element/tag; add the edge line to `model.c4` and confirm the two system-context views already
including both `doppler` and `zotRegistry` (views.c4:14,36) render it. Run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after. No falsified element
description found.

### Phase 7 — Follow-up audit issue (broader misconception; do NOT fix here)

**7.1** Populate the issue created in Phase 0.3 — "audit: Doppler branch-config non-isolation across
prod configs (`prd_git_data`, `prd_kb_drift_walker`, `prd_cla`, ADR-088 `prd_ghcr` claim)". Body:
branch configs under `prd` resolve the `prd` root and read all 116 prod secrets; each consumer's
read token may over-read far beyond its stated least-privilege scope. **Triage each by PROVISIONING
STATUS first — this is the load-bearing severity axis** (why zot is calm-fixable but siblings may
not be):
- **LIVE over-reads = P1 / incident-class, NOT a p2 audit line.** `prd_cla` is created **live** by a
  *separate, already-operational* bootstrap (`apps/cla-evidence/infra/bootstrap.sh:224-257`:
  `doppler configs create prd_cla --environment prd` + a config-scoped token surfaced to GitHub
  Actions via `iam.tf:31`) — independent of any web-platform apply. Its token believed-scoped to ~4
  R2 secrets resolves the prd root and can read `SUPABASE_SERVICE_ROLE_KEY` **right now**.
  `prd_git_data` (`git-data-luks.tf:53-70`) is the same bug on a client-facing git-shell host and is
  a live over-read **if the git-data host has been provisioned** (Phase-3 GA/LUKS commits landed).
  Confirm each's live status and file/label these as P1.
- **Assess-on-merits (may be legitimate):** `prd_terraform` feeds the CI `terraform apply` and
  legitimately reads many `TF_VAR_*` — audit, don't assume broken.
- **Remediation pattern:** migrate genuine over-reads to standalone environments (the pattern this
  PR establishes for zot); correct ADR-088's "config isolation is the isolation that actually
  matters" claim.

Keep all of this OUT of this PR's diff (zot-only scope) — the discipline is *file + correctly
triage*, not *understate as uniform p2*. Verify each label exists (`gh label list`) before assigning;
default `type/security`, `domain/engineering`; use `priority/p1-high` for the confirmed-live
over-reads and `priority/p2-medium` for the audit remainder (substitute existing labels if absent).
Reference the issue number in **this PR's body** (`Ref #<audit>`), never `Closes`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `git grep -n prd_registry apps/web-platform/infra/` returns **zero** (all repointed to the `registry` environment / config). This plan + `tasks.md` are excluded (point-in-time records).
- [ ] AC2 — `zot-registry.tf` host-scoped `doppler_secret.zot_pull_token_registry`, `doppler_secret.zot_push_token_registry`, and `doppler_service_token.registry` all declare `config` = the `registry` environment (attribute-ref on PRIMARY path, literal `"registry"` on FALLBACK); the `prd` client copies are unchanged.
- [ ] AC3 — (PRIMARY path) `doppler_environment.registry` exists in `zot-registry.tf` AND is present in `OPERATOR_APPLIED_EXCLUSIONS`; the parity vitest suite passes. (FALLBACK path) no new resource; suite passes unchanged.
- [ ] AC4 — The former false-isolation comments (`zot-registry.tf:63-75`, `cloud-init-registry.yml:100`) no longer claim a `prd` branch config isolates; they describe the `registry` environment root and (in zot-registry.tf) explicitly note the departure from the `prd_git_data`/`prd_kb_drift_walker` pattern + the audit issue.
- [ ] AC4b (pre-merge, load-bearing) — The rendered `cloud-init-registry.yml` contains the Phase-2.5 boot-time isolation self-assertion (`grep` the rendered `templatefile` output for the `refusing to launch` fail-closed guard AND the `grep -Ec '^ZOT_(PULL|PUSH)_TOKEN$'` identity check) placed BEFORE the `docker run`. This makes the isolation invariant verifiable at merge time, not only post-provision.
- [ ] AC5 — `terraform fmt -check` clean AND `terraform validate` green in `apps/web-platform/infra` (with the Doppler provider configured; validate does not need prod creds).
- [ ] AC6 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; the parity test file passes under vitest.
- [ ] AC7 — ADR-096 carries the "Doppler credential isolation" amendment; `## Domain Review`, `## Observability`, and the C4-completeness citation are present in this plan.
- [ ] AC8 — `tasks.md` 1.3/1.8 corrected; the Phase-4.1 count-assert added as a 1.8 provisioning gate.
- [ ] AC9 — The audit follow-up issue is filed and referenced as `Ref #<n>` in the PR body (not `Closes`); #6122 remains OPEN.
- [ ] AC10 — CPO sign-off recorded (threshold = single-user incident).

### Post-merge (operator, at provisioning / task 1.8 — NOT this PR)
<!-- lint-infra-ignore start (task-1.8 fresh-host provisioning gate — operator-run per the apply-path CTO ruling; CI structurally cannot provision a new host) -->
- [ ] AC11 — Before flip: run the Phase-4.1 scoped-token assertion against the live `soleur-registry` project's `prd` config → exactly 2 non-`DOPPLER_*` secrets, BOTH `ZOT_*` (identity, not just count); token revoked after. **MANDATORY-blocking, especially on the FALLBACK path** (an operator who created a branch config under `prd` instead of the dedicated `soleur-registry` project fails here with 116). Recommended preventive sequencing: stage the operator apply — `-target` the `doppler_project`+secrets+token first, run this assert, THEN apply the host — so the credential is proven isolated before the host ever receives it. The Phase-2.5 boot self-assert is the host-level backstop if this is skipped.
<!-- lint-infra-ignore end -->
- [ ] AC12 — Post-provision hygiene: confirm no stale `prd_registry` branch config exists in Doppler and no service token minted against it during diagnosis survives (the diagnosis config was created-then-deleted per state notes; verify Doppler is clean).

## Observability

```yaml
liveness_signal:
  what: existing betteruptime_heartbeat.registry_prd push-beat (UNCHANGED by this fix)
  cadence: 60s period / 30s grace (paused until Phase-3 probe cron ships)
  alert_target: Better Stack → inngest escalation policy (email)
  configured_in: apps/web-platform/infra/zot-registry.tf
  # NOTE: the heartbeat is paused=true until the Phase-3 probe cron ships, so it is INERT for
  # this fix's deploy window. The live no-SSH signals for THIS change are therefore (1) AC11 —
  # the pre-boot scoped-token count/identity assert (doppler CLI, no SSH), which MUST stay
  # MANDATORY-blocking, and (2) the Phase-2.5 boot self-assertion (host refuses to launch on a
  # mis-scoped token — observable as "zot never comes up", ssh-free). Post-boot ROOT-CAUSE
  # (the FATAL journald line) is on-host/SSH-only; AC11 moves the WHY before boot.
error_reporting:
  destination: cloud-init runcmd journald on the registry host (docker/zot logs) — boot-time htpasswd build FAILS LOUD on an empty ZOT_PULL_TOKEN/ZOT_PUSH_TOKEN (cloud-init-registry.yml:118-119, unchanged)
  fail_loud: true
failure_modes:
  - mode: registry host boot token can read more than the 2 ZOT tokens (the bug this fixes)
    detection: PRIMARY = Phase-2.5 cloud-init boot self-assertion on the host's OWN token (count==2 AND both ZOT_) → host refuses to launch zot + heartbeat stays red (fail-CLOSED, ssh-free); SECONDARY = Phase-4.1 scoped-token provisioning gate (AC11)
    alert_route: host does not boot / heartbeat never greens (self-enforcing); provisioning go/no-go (AC11)
  - mode: the `soleur-registry` project/config is missing at apply
    detection: `terraform apply` errors (PRIMARY: the project is a managed resource; FALLBACK: `doppler run --project soleur-registry --config prd` errors loudly at boot before zot launches)
    alert_route: apply failure surfaced to operator / betteruptime heartbeat never greens
  - mode: `doppler run --project soleur-registry --config prd` at boot yields empty tokens
    detection: cloud-init fail-loud guard exits 1 before docker run (journald)
    alert_route: heartbeat stays red (no false-green)
logs:
  where: registry-host journald (docker/zot + cloud-init runcmd)
  retention: journald default on-host
discoverability_test:
  command: 'tok=$(doppler configs tokens create ziso --project soleur-registry --config prd --access read --plain); DOPPLER_TOKEN=$tok doppler secrets --only-names --json | jq -r "keys[]" | grep -c "^ZOT_\(PULL\|PUSH\)_TOKEN$"'
  expected_output: "2 (asserts IDENTITY — exactly ZOT_PULL_TOKEN + ZOT_PUSH_TOKEN; a bare non-DOPPLER count would false-pass on 2 wrong secrets)"
```

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (inline — deep infra analysis performed in-plan; deepen-plan adds rigor)
**Assessment:** This is a least-privilege credential-boundary correction on an unprovisioned host,
fully within the established IaC surface (Terraform + cloud-init). It aligns with the binding
apply-path CTO ruling (`apply-path-cto-ruling.md`): the new `doppler_environment.registry` (PRIMARY)
rides the operator full apply, never the per-PR `-target` set — same class as every other zot
resource. It introduces **no** new infrastructure requiring manual provisioning; on the PRIMARY path
it *removes* an operator precondition (a net-positive under `hr-all-infrastructure-provisioning`).
The chosen environment-over-project boundary keeps the provider's proven `soleur`-scoped authority
and avoids an unverified workplace create-project scope. The single residual risk — whether
`doppler_environment` provider-create succeeds in this plan-tier-limited workspace — is gated by
Phase-0 verification with a pre-declared operator-precondition fallback, per
`hr-verify-repo-capability-claim-before-assert`.

### Product/UX Gate
**Not applicable** — no UI surface. Files touched are `.tf`, `.yml`, `.test.ts`, `.md`; none match
the UI-surface glob (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). Mechanical override
did not fire. Product = NONE.

## GDPR / Compliance (advisory)

Trigger (b) fires (brand-survival threshold = single-user incident) though no schema/migration/API
`.sql` surface is touched. The fix is a **confidentiality control** (GDPR Art. 32 security of
processing): it *reduces* exposure of `SUPABASE_SERVICE_ROLE_KEY` (a key to all-user PII) by
correctly scoping the registry host's credential. No new processing, no data movement, no new data
class. `/soleur:gdpr-gate` may run at review-time for completeness; expected: no Critical findings
(net risk reduction).

## Open Code-Review Overlap

None found. (Run `gh issue list --label code-review --state open --json number,title,body` and
`jq --arg path` per file at /work Phase 1.7.5 to confirm against the finalized Files-to-Edit list
before coding; the Doppler-branch-config audit issue this PR *files* is the intended net-positive,
not an overlap.)

## Files to Edit
- `apps/web-platform/infra/zot-registry.tf` — add `doppler_environment.registry` (PRIMARY); repoint the two host `doppler_secret`s + the service token to the `registry` env; rewrite the false-isolation comment block (`:63-75`).
- `apps/web-platform/infra/cloud-init-registry.yml` — rewrite `:100` false claim; update `:108` comment + `:116` live `doppler run --config` invocation; **add the Phase-2.5 boot-time isolation self-assertion** before `docker run`; **add `jq` to `packages:`**.
- `plugins/soleur/test/terraform-target-parity.test.ts` — add `doppler_environment.registry` to `OPERATOR_APPLIED_EXCLUSIONS` (PRIMARY); correct the `prd_registry` exclusion-block comments (~L524-526, L567-570).
- `knowledge-base/project/specs/feat-registry-oidc-migration/tasks.md` — correct tasks 1.3 + 1.8; add the count-assert provisioning gate + the Phase-0 PRIMARY/FALLBACK verdict note.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — Doppler credential-isolation amendment + record the shipped path (PRIMARY/FALLBACK).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — add the `doppler -> zotRegistry` boot-credential edge (Phase 6.2); re-run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- Any provisioning runbook under `knowledge-base/` naming `prd_registry` (grep; exclude plan/tasks/CTO-ruling records).

## Files to Create
- (none — the audit follow-up is a GitHub issue, not a file.)

## Sharp Edges
- **The section's own premise:** a plan whose `## User-Brand Impact` is empty/`TBD`/threshold-less fails `deepen-plan` Phase 4.6. This section is filled (threshold = single-user incident).
- **Count semantics:** `doppler secrets --only-names` includes the 3 `DOPPLER_*` built-ins; the isolation assert MUST count non-`DOPPLER_*` names (== 2), never a raw row count (would read 5) — see Phase 4.1.
- **Capability, not fact:** `doppler_environment` provider-create in this plan-tier-limited workspace is a *hypothesis* (the `doppler_config.prd_ghcr` #6067 failure is the precedent). Phase 0 verifies; the operator-precondition fallback keeps the fix correct if it fails. Do NOT assert TF-create works without the Phase-0 evidence.
- **Do NOT use a `doppler_config` (branch) to fix this** — that path is exactly what the workspace's plan tier blocks AND what fails to isolate. The fix is a new *environment* (own root), not a new *config*.
- **Address stability:** keep the resource addresses `zot_pull_token_registry` / `zot_push_token_registry` / `registry` — only their `config` argument changes. The benefit is avoiding **parity-exclusion-list churn** (no Terraform state exists — apply never ran — so a `config=` change is a plain destroy/create either way; "avoids a state move" would be imprecise).
- **`jq` in cloud-init:** Phase 2.5's boot self-check parses `doppler secrets --only-names --json` with `jq`, but `cloud-init-registry.yml`'s `packages:` list is `docker.io`/`apache2-utils`/`curl` — **add `jq`** to that list (or rewrite the check to parse plain `--only-names` output). Verify at /work.
- **Live siblings are NOT dormant:** `prd_cla` (`apps/cla-evidence/infra/bootstrap.sh:224-257`) and possibly `prd_git_data` are already-provisioned over-reads (live tokens reading 116 prod secrets NOW) — file them as P1 in the Task-7 audit, do NOT understate as uniform p2. Still out of THIS PR's diff.
- **Terraform ordering:** on the PRIMARY path the secrets/token MUST depend on the env — use `config = doppler_environment.registry.slug` (implicit dep), not the bare literal, so the environment is created first.
- **Scope discipline:** `prd_git_data` / `prd_kb_drift_walker` / `prd_cla` / `prd_ghcr` are the SAME bug but are OUT OF SCOPE — Task 7 files the audit issue; touching them here violates the PR's stated zot-only scope.
- **`Ref` not `Closes`:** #6122 stays OPEN (this is a correctness fix en route, not the cutover); the audit issue is `Ref`'d, never `Closes`d, from the PR body.

## Test Scenarios
1. Scoped read token on `registry` → exactly 2 non-built-in secrets (`ZOT_PULL_TOKEN`, `ZOT_PUSH_TOKEN`) → PASS; same token minted on `prd`/`prd_registry` → 116 → the contrast is the regression proof.
2. `terraform validate` green with `doppler_environment.registry` + repointed secrets/token.
3. Parity vitest suite green with `doppler_environment.registry` in OPERATOR_APPLIED_EXCLUSIONS; the synthetic-forgotten-resource non-vacuity test still FAILS on an un-excluded new resource.
4. `git grep prd_registry apps/web-platform/infra/` → zero.
5. Rendered cloud-init (`terraform plan` templatefile) shows `doppler run --project soleur-registry --config prd`.
