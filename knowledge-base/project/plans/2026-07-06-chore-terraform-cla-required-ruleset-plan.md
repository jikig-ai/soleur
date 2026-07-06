---
title: "chore(infra): Terraform-ify the CLA Required ruleset + repoint its drift-guard sync gate at the .tf"
type: chore
issue: 6072
branch: feat-one-shot-6072-terraform-cla-ruleset
date: 2026-07-06
lane: single-domain
brand_survival_threshold: none
status: draft
related:
  - ADR-032-github-branch-protection-as-iac.md
  - 2026-07-05-feat-cla-required-ruleset-drift-guard-plan.md  # #6061 (drift-guard chain)
  - 2026-05-16-feat-ci-required-ruleset-widening-via-terraform-plan.md  # CI IaC precedent
---

# chore(infra): Terraform-ify the CLA Required ruleset + repoint the #6061 sync gate at the .tf

## Enhancement Summary

**Deepened on:** 2026-07-06 · **Reviewed by:** architecture-strategist + kieran-rails-reviewer + code-simplicity-reviewer (eng panel).

**Key improvements applied from review:**
1. **SE-3 header-token hygiene** — the `.tf` header/block comments must carry no literal
   `context = "..."` / `required_check {` / `bypass_actors {` token and no inline `#...=...`
   on assignment lines (Kieran: comment-naive gate greps false-fail otherwise); the two
   count-ACs are now leading-anchored/comment-safe.
2. **`set -e` guards** on the two negative greps in `T-cla-1` (happy path exits 1).
3. **`moved {}` caveat** preserved on the per-address import gate; **CI-specific `context=test`
   preflight explicitly excluded** from the CLA DR script refactor (architecture P2-a/b).
4. **No-op-apply dependency made explicit** — it rests on the daily audit being green, since
   the post-apply verify probes RSC count only, not bypass_actors (architecture P2-c).
5. **CUT** `cla_ruleset_id`/`cla_ruleset_url` outputs + the optional `T-cla-2` gate (YAGNI,
   code-simplicity).

**New confirmations from deepen (live probes):** the live CLA ruleset is byte-identical to
the canonicals + planned `.tf` (no-op apply verified); provider pinned `integrations/github
6.12.1`; precedent-diff vs the CI `.tf` shows exactly three intended divergences. See
`## Deepen Insights`.

## Overview

The **"CLA Required"** ruleset (id `13304872`) is drift-guarded (canonical JSONs +
daily `cron-ruleset-bypass-audit` + file-vs-file sync gates, shipped in #6061) but,
unlike the **"CI Required"** ruleset (id `14145388`), it is still **imperatively
managed** by `scripts/create-cla-required-ruleset.sh` with **no Terraform SSOT**.
Consequence: the CLA sync gates (`T-cla-1` / `T-cla-1b`) pin the canonicals to the
create-script's inline heredoc (a `sed`-sliced payload), whereas the CI ruleset's
equivalent (`T-rsc-9`) pins to a clean `.tf` (`infra/github/ruleset-ci-required.tf`).

This change lifts the CLA ruleset into Terraform exactly as the CI ruleset already
is — same root (`infra/github/`), same provider, same auto-apply workflow
(`apply-github-infra.yml`), same canonical↔`.tf` sync-gate shape — and demotes the
create-script to a DR-only restore skeleton (mirroring
`scripts/create-ci-required-ruleset.sh`). **No enforced value changes**: the two
required checks (`cla-check`, `cla-evidence` @ integration_id 15368) and the three
bypass actors (OrganizationAdmin/pull_request, RepositoryRole:5/pull_request,
Integration:1236702/always) are byte-identical to today's live ruleset and to the
two canonical JSONs. This is a maintainability/SSOT lift, not a policy change.

This is the deferred IaC-cleanup follow-up to #6061 (DC-2 / Phase 6.1). The
security-load-bearing part (the drift-guard chain) already shipped and stays in
place; this migrates the declaration surface only.

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Reality (verified against worktree) | Plan response |
|---|---|---|
| `ruleset-ci-required.tf` is the CI IaC pattern to mirror | ✅ `infra/github/ruleset-ci-required.tf` uses `resource "github_repository_ruleset" "ci_required"`, `var.actions_integration_id`, `bypass_actors` blocks, `enforcement = "active"`. | New `.tf` mirrors this structure exactly. |
| CLA required checks: `cla-check` + `cla-evidence` @ integration_id 15368 | ✅ Confirmed in create-script heredoc + `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json`. Job names verified live: `cla-check` (`.github/workflows/cla.yml:31`), `cla-evidence` (`.github/workflows/cla-evidence.yml:41`). | Two `required_check` blocks, `integration_id = var.actions_integration_id` (default 15368). |
| CLA bypass: OrgAdmin/pull_request, RepoRole:5/pull_request, Integration:1236702/always | ✅ Confirmed in create-script + `scripts/ci-cla-required-ruleset-canonical-bypass-actors.json`. | Three `bypass_actors` blocks. |
| Wire into `apply-github-infra.yml` | ✅ Workflow auto-applies on `infra/github/*.tf` merge, imports on first apply, has destroy-guard + post-apply verify. | Extend import gate to per-address; extend verify to probe the CLA ruleset. |
| **[DISCOVERY]** create-script `strict_required_status_checks_policy` | The CLA create-script uses `false` (CI uses `true`). | CLA `.tf` uses `false` — a documented divergence from the CI `.tf`. |
| **[DISCOVERY]** canonical bypass `OrganizationAdmin.actor_id` is `null`; CI `.tf` uses `0` sentinel | ✅ Canonical JSON carries `null` (mirrors live API); CI `.tf` uses `actor_id = 0` per provider issue #2536 (provider HCL form for null is `0` on v6.10+). | CLA `.tf` uses `actor_id = 0`; **`T-cla-1b` must normalize `0`↔`null`** when comparing `.tf`↔canonical (SE-1). |
| **[DISCOVERY]** apply workflow import gate uses a blanket `grep -qE '^github_repository_ruleset\.'` | ✅ `apply-github-infra.yml` "First-apply import" step skips import if **any** ruleset address is in state. With a second resource this would **never import** the CLA ruleset → next apply tries to **CREATE** a "CLA Required" ruleset that already exists live. | Rewrite the gate to import per-address (`grep -qxF <addr>`). Highest-risk item. |
| **[DISCOVERY]** cron audit `CLA_AUDIT_CONFIG.sourceHint` = `scripts/create-cla-required-ruleset.sh` | ✅ `cron-ruleset-bypass-audit.ts:129`. Human-facing hint in the drift-issue body naming the file to reconcile. | Repoint to `infra/github/ruleset-cla-required.tf` + update the file-header comment. |
| Terraform-ifying CLA is deferred (per #6061 docs, cron comment, runbook) | ✅ Multiple docs assert "deferred — #6061 Phase 6.1". | Update the stale "deferred/no-Terraform" assertions in the cron comment + `ruleset-bypass-drift.md` + `cla-signature-evidence-retrieval.md`. |

## Deepen Insights (2026-07-06)

**Live-state confirmation (zero-blast-radius premise verified).** Read-only
`gh api repos/jikig-ai/soleur/rulesets/13304872` returns EXACTLY the planned values:

```json
{"enforcement":"active","strict":false,
 "checks":[{"context":"cla-check","integration_id":15368},{"context":"cla-evidence","integration_id":15368}],
 "bypass":[{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"},
           {"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"},
           {"actor_id":1236702,"actor_type":"Integration","bypass_mode":"always"}]}
```

live == the two canonical JSONs == the planned `.tf`. This substantiates the
import-then-plan **no-op first apply** and independently confirms **SE-1**: the live
OrganizationAdmin `actor_id` is `null` (the `.tf`'s `0` sentinel must normalize to it in
`T-cla-1b`).

**Provider-attribute confirmation.** `infra/github/.terraform.lock.hcl` pins
`integrations/github 6.12.1` (constraint `~> 6.10`). The sibling `ruleset-ci-required.tf`
already exercises `bypass_actors { actor_type / actor_id / bypass_mode }`,
`required_check { context / integration_id }`, and
`strict_required_status_checks_policy` on this exact provider (43 attribute occurrences) —
the strongest possible proof that the CLA `.tf`'s surface is supported. The only value not
present in the CI `.tf` is `actor_type = "Integration"`, which the live ruleset already
carries, so `terraform import` round-trips it. No Context7 lookup needed — the installed,
pinned sibling resource is the ground truth.

**Precedent-diff gate (4.4) — CLA `.tf` vs `ruleset-ci-required.tf`.** Exactly three
intended divergences, each documented in the `.tf` header:

| Attribute | CI (`ci_required`) | CLA (`cla_required`) | Why |
|---|---|---|---|
| `strict_required_status_checks_policy` | `true` | **`false`** | CLA gate does not require branches be up-to-date (preserved from live). |
| `bypass_actors` count | 2 (OrgAdmin, RepoRole:5) | **3** (+ Integration:1236702/always) | The CLA bot must update CLA status on every PR. |
| `required_check` count / apps | 17, incl. CodeQL @ `var.codeql_integration_id` | **2** (cla-check, cla-evidence), both @ `var.actions_integration_id` | CLA has no GHAS/CodeQL check — all GitHub Actions. |

Everything else (resource type, `name`/`repository`/`target`, `enforcement = "active"`,
`conditions.ref_name`, `actor_id = 0` OrgAdmin sentinel, `do_not_enforce_on_create = false`,
provider, R2 backend) is identical — the mirror is faithful.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the CLA ruleset
governs **contribution provenance for the founder's own repo**, not any Soleur
end-user surface. A mis-authored `.tf` that on apply removed a required check or
added a bypass actor would let an un-CLA'd contribution merge to `main` (an IP/legal
provenance gap), but that is contained by three independent guards (destroy-guard on
nested-check removal, daily `cron-ruleset-bypass-audit` on bypass widening /
enforcement suspension, and the pre-merge `T-cla-1`/`T-cla-1b` sync gates).

**If this leaks, the user's data is exposed via:** N/A — no user data, secrets, or
PII are touched. The change is a declaration-surface migration; the only sensitive
material (GitHub App PEM, R2 creds) is already handled by the existing, unchanged
credential-fetch steps of `apply-github-infra.yml`.

**Brand-survival threshold:** none — reason: this migrates the *declaration* of an
internal contribution-governance control whose enforced values are unchanged and
whose failure modes are already covered by the shipped drift-guard chain; no Soleur
end-user surface, data path, or secret is affected. (Sensitive-path scope-out bullet
for preflight Check 6: `threshold: none, reason: internal CI/branch-protection IaC
refactor with byte-identical enforced values, guarded by destroy-guard + daily audit
+ sync gates; no end-user data path.`)

## Implementation Phases

> TDD note: the sync-gate rewrite (Phase 3) is test code — write the repointed
> `T-cla-1`/`T-cla-1b` assertions to target the `.tf` FIRST (they will fail RED
> until the `.tf` exists), then author the `.tf` (Phase 1) to turn them GREEN. The
> `.tf` is the contract the gates assert against, so **author the `.tf` and the
> canonicals-unchanged fact in the same PR**; the phase ordering below is
> dependency-ordered for `/work`, not a merge split (single atomic PR).

### Phase 1 — Author `infra/github/ruleset-cla-required.tf`

Create the file with `resource "github_repository_ruleset" "cla_required"`:

- `name = "CLA Required"`, `repository = var.gh_repo`, `target = "branch"`,
  `enforcement = "active"`.
- `conditions { ref_name { include = ["~DEFAULT_BRANCH"]; exclude = [] } }`.
- Three `bypass_actors` blocks:
  - `actor_id = 0`, `actor_type = "OrganizationAdmin"`, `bypass_mode = "pull_request"`
    (`0` = null sentinel per provider issue #2536; header comment cites SE-1).
  - `actor_id = 5`, `actor_type = "RepositoryRole"`, `bypass_mode = "pull_request"`.
  - `actor_id = 1236702`, `actor_type = "Integration"`, `bypass_mode = "always"`
    (the CLA bot — the one actor CI does not have).
- `rules { required_status_checks { strict_required_status_checks_policy = false;
  do_not_enforce_on_create = false; required_check { context = "cla-check";
  integration_id = var.actions_integration_id } required_check { context =
  "cla-evidence"; integration_id = var.actions_integration_id } } }`.
- Header comment documenting: (a) values are byte-identical to the former create-script
  payload + the two canonical JSONs; (b) the `strict = false` divergence from CI;
  (c) the third bypass actor; (d) the `0`↔`null` sentinel (SE-1); (e) the job-name ABI
  contract (renaming `cla-check`/`cla-evidence` silently un-requires it — same as CI
  per ADR-032).
- **Header-comment token hygiene (SE-3, load-bearing for the gates).** The `T-cla-1` /
  `T-cla-1b` gates grep/awk this file with comment-naive patterns. The header + block
  comments MUST NOT contain any literal `context = "..."`, `required_check {`, or
  `bypass_actors {` token, and MUST NOT put an inline `# ... = ...` comment on any
  `actor_id`/`actor_type`/`bypass_mode`/`context` assignment line (the awk `actor_id`
  extractor greedily consumes through a second `=`). Keep the SE-1 sentinel rationale in
  the file **header**, and keep the CI precedent's shape: a bare `actor_id = 0` with the
  `# built-in Admin repository role` note only on the RepoRole line (no `=`). Every such
  slip fails **safe** (RED / false-fail) except the two `grep -c '... {'` count ACs, which
  are made comment-safe below.

No new variables (reuse `var.gh_repo`, `var.actions_integration_id` from
`variables.tf`). `main.tf`'s single `provider "github"` block already serves both
resources — no provider change. **No `outputs.tf` change** — a `cla_ruleset_id` output has
no consumer (the post-apply verify probes the API by the hardcoded id `13304872`, not an
output); cut per code-simplicity review (YAGNI).

### Phase 2 — Wire the CLA ruleset into the apply path (`apply-github-infra.yml`)

Two edits to `.github/workflows/apply-github-infra.yml`:

1. **First-apply import (per-address).** Replace the blanket
   `grep -qE '^github_repository_ruleset\.'` gate with a per-address helper so BOTH
   rulesets import independently:
   ```bash
   state_list=$(terraform state list 2>/dev/null || true)
   import_ruleset() {
     local addr=$1 id=$2
     if grep -qxF "$addr" <<<"$state_list"; then
       echo "Resource $addr already in state, skipping import."
     else
       echo "Importing ruleset $id as $addr (one-time bootstrap)."
       doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
         terraform import "$addr" "soleur:$id"
       state_list=$(terraform state list 2>/dev/null || true)  # refresh
     fi
   }
   import_ruleset github_repository_ruleset.ci_required 14145388
   import_ruleset github_repository_ruleset.cla_required 13304872
   ```
   Rationale: without per-address import, the CI resource's presence in state skips
   the CLA import, and the next `terraform apply` computes `cla_required` as a
   **create** against a name that already exists live (SE-2). `grep -qxF` matches the
   full address line exactly (no prefix false-positive).
   Carry forward the existing step's `moved {}` caveat as a one-line comment: if either
   resource is later renamed via a `moved {}` block, the hardcoded import address here MUST
   be updated in the same PR (else `terraform import` errors "resource already managed").
   The per-address form replaces the blanket `grep -qE '^github_repository_ruleset\.'` that
   previously served this defense.

2. **Post-apply verify (add CLA probe).** After the existing CI count probe, reuse the
   already-minted `INSTALL_TOKEN` to probe `rulesets/13304872` and assert the CLA
   required-check count (`select(.type=="required_status_checks") | ... | length`,
   expect `2`). Surface `cla_actual_count` in `$GITHUB_OUTPUT` + the Post-apply summary.
   Use the same order-independent `select(.type==...)` (never positional `.rules[0]`).

The destroy-guard filter (`tests/scripts/lib/destroy-guard-filter.jq`) is already
address-agnostic (`select(.type == "github_repository_ruleset")`) — it covers the CLA
resource with no change. The `[skip-github-apply]` / `[ack-destroy]` kill switches are
unchanged.

> The "zero blast radius / no-op first apply" claim rests on the live CLA ruleset already
> matching the `.tf` (the daily `cron-ruleset-bypass-audit` CLA step is currently green,
> which substantiates live == canonical == `.tf`). The post-apply verify probes the RSC
> **count** only (symmetric with the CI probe), not bypass_actors; a silent bypass_actors
> reconcile on first apply would be caught by the destroy-guard only if it removed a nested
> `required_check`, so the no-op guarantee is the daily audit's, not the verify's. State
> this dependency explicitly rather than asserting a bare "no-op."

### Phase 3 — Repoint the CLA sync gates at the `.tf` (`tests/scripts/test-audit-ruleset-bypass.sh`)

Rewrite `T-cla-1` and `T-cla-1b` to pin the canonicals to
`infra/github/ruleset-cla-required.tf` (matching `T-rsc-9`), and **delete the
`_cla_create_payload` heredoc-slice helper** (the create-script is no longer the SSOT).

- **`T-cla-1` (RSC: context-set + integration_id, `.tf`-anchored):**
  - `cla_tf="$REPO_ROOT/infra/github/ruleset-cla-required.tf"`; fail if missing.
  - Extract `.tf` context set with the exact `T-rsc-9` mechanism:
    `grep -oE 'context[[:space:]]*=[[:space:]]*"[^"]+"' "$cla_tf" | sed -E 's/.*"([^"]+)"$/\1/' | sort`.
  - Compare to `jq -r '.[].context' "$CLA_RSC_CANONICAL" | sort` (context-set equality).
  - **integration_id load-bearing pin** (keep — issue says "context-set + integration_id"):
    assert every canonical row is `15368` (`jq -e 'all(.[]; .integration_id == 15368)'`)
    AND assert the `.tf` binds every required_check to `var.actions_integration_id` and
    NOT `var.codeql_integration_id` (count of
    `grep -cE 'integration_id[[:space:]]*=[[:space:]]*var\.actions_integration_id' "$cla_tf"`
    equals the context count `2`; `grep -q 'codeql_integration_id' "$cla_tf"` must be
    absent). Mirrors `T-rsc-9` (context set) + `T-rsc-7` (integration literal pin) and
    keeps `var.actions_integration_id` default (15368, per `variables.tf`) `.tf`-anchored.
  - **`set -e` guard:** the suite runs `set -euo pipefail` and calls test fns unguarded.
    The two negative greps exit 1 on their happy path (`grep -cE '...actions_integration_id'`
    exits 1 when a broken `.tf` has 0 matches; `grep -q 'codeql_integration_id'` exits 1
    when correctly absent). Write them as `count=$(grep -cE ... || true)` and
    `if grep -q ...; then _report ... fail; fi` — never a bare `grep -q ... && _report fail`
    pipeline — mirroring the existing `|| true` idiom at line ~696.
  - Keep the no-dup guard + non-vacuity floor (`>= 2`).
- **`T-cla-1b` (bypass triples, `.tf`-anchored, `0`↔`null` normalized):**
  - Parse the `.tf` `bypass_actors { ... }` blocks into `actor_id|actor_type|bypass_mode`
    triples via awk (split on `=`, strip quotes + trailing comments; default `actor_id`
    to `null` per block; see the awk sketch in Test Scenarios).
  - **Normalize `actor_id == "0"` → `"null"`** (the OrganizationAdmin sentinel; no real
    actor has id 0) so the `.tf`'s `0` compares equal to the canonical's `null`.
  - Compare the sorted normalized `.tf` triple set to the canonical triples
    (`jq -r '.[] | "\(.actor_id)|\(.actor_type)|\(.bypass_mode)"' | sort` — `null` prints
    as `"null"`).
  - Keep the no-dup guard + non-vacuity floor (`>= 3`). Preserve the comment that the
    `Integration:1236702/always` actor is the CLA bot (legitimately `always`, IN the
    canonical).
- Update the section header comment (lines ~742–750) from "imperatively managed …
  no Terraform SSOT … Phase 6.1 deferral" to "Terraform-managed via
  `infra/github/ruleset-cla-required.tf`; these gates pin the canonicals to the `.tf`
  (matching `T-rsc-9`)."
- The dispatch list at the bottom already calls both `t_cla_*` functions — no change
  there. `T-rsc-9`'s `.tf` grep is file-scoped to `ruleset-ci-required.tf`, so the new
  `.tf` cannot cross-contaminate it.

> `T-cla-2` (asserting the DR create-script references the canonical filenames) was
> considered and **CUT** per code-simplicity review: it gates a filename string in a
> non-production DR script, a weak proxy for "reads the canonicals" that Phase 4's runtime
> `jq --slurpfile` already guarantees. YAGNI.

### Phase 4 — Demote `scripts/create-cla-required-ruleset.sh` to a DR-only restore skeleton

Refactor to mirror `scripts/create-ci-required-ruleset.sh` (the CI DR precedent):

- Header: this is the **disaster-recovery restore path only**; the canonical
  management path is Terraform (`infra/github/ruleset-cla-required.tf` +
  `apply-github-infra.yml`); after running, `terraform import` +
  `terraform plan/apply` to reconcile back to state.
- Read the two canonical JSONs (`ci-cla-required-ruleset-canonical-bypass-actors.json`,
  `ci-cla-required-ruleset-canonical-required-status-checks.json`), validate each is a
  JSON array, and merge them into the skeleton via `jq --slurpfile` — **removing the
  inline heredoc** (this retires "the heredoc-slice comparison" on the producer side).
- Skeleton preserves CLA semantics: `enforcement = "active"`,
  `strict_required_status_checks_policy = false`, `do_not_enforce_on_create = false`.
- **DR-only guard:** exit early (0) if a "CLA Required" ruleset already exists — never
  replace a live ruleset (matches create-ci; the update/full-replace path is now
  `terraform apply`).
- **Do NOT inherit create-ci's CI-specific preflight.** `create-ci-required-ruleset.sh`
  gates on a `context=test` synthetic-status check in bot workflows — that is CI-semantic
  and wrong for CLA (whose checks are `cla-check`/`cla-evidence`). Mirror ONLY the DR-only
  existence guard + the two-canonical `--slurpfile` merge; omit the `context=test` preflight.

### Phase 5 — Reconcile docs + cron hint to the new SSOT

- `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts`:
  `CLA_AUDIT_CONFIG.sourceHint` → `"infra/github/ruleset-cla-required.tf"`; update the
  file-header comment (lines ~22–27) that says "for the CLA ruleset it is the imperative
  `scripts/create-cla-required-ruleset.sh` (Terraform-ifying CLA is deferred — #6061
  Phase 6.1)" → "for the CLA ruleset it is Terraform (`infra/github/ruleset-cla-required.tf`)
  as of #6072."
- `knowledge-base/engineering/operations/runbooks/ruleset-bypass-drift.md`: update the
  "Source of truth (differs from CI)" paragraph (CLA is now Terraform-managed like CI,
  applied by `apply-github-infra.yml`); "kept in lockstep with the create-script's inline
  blocks by `T-cla-1`/`T-cla-1b`" → "kept in lockstep with
  `infra/github/ruleset-cla-required.tf` by `T-cla-1`/`T-cla-1b`"; the remedy line
  "reconcile `scripts/create-cla-required-ruleset.sh` **and** the two CLA canonical
  JSONs" → "reconcile `infra/github/ruleset-cla-required.tf` **and** the two CLA
  canonical JSONs (apply via `apply-github-infra.yml` on merge)".
- `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md:428`:
  update "use `scripts/create-cla-required-ruleset.sh` which rewrites the entire payload"
  → note `.tf` is SSOT; the create-script is DR-only.
- `infra/github/README.md`: add a short CLA subsection to the import runbook (managed
  resource `github_repository_ruleset.cla_required`, ruleset id `13304872`, imported by
  the same first-apply flow; manual reconcile command mirrors the CI Phase 1 block with
  `soleur:13304872`).
- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md`:
  append a dated amendment noting the CLA Required ruleset (id 13304872) is now managed by
  the same `infra/github/` root (extends the accepted decision to a second ruleset; see
  ADR/C4 section).

## Files to Create

- `infra/github/ruleset-cla-required.tf` — the CLA ruleset resource (Phase 1).

## Files to Edit

- `.github/workflows/apply-github-infra.yml` — per-address import gate + CLA post-apply verify.
- `tests/scripts/test-audit-ruleset-bypass.sh` — repoint `T-cla-1`/`T-cla-1b` at the `.tf`;
  delete `_cla_create_payload`; update section header.
- `scripts/create-cla-required-ruleset.sh` — refactor to DR-only skeleton reading canonicals.
- `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts` — `sourceHint` + header comment.
- `knowledge-base/engineering/operations/runbooks/ruleset-bypass-drift.md` — SSOT + sync-gate + remedy prose.
- `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` — SSOT note.
- `infra/github/README.md` — CLA import subsection.
- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` — CLA amendment.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `infra/github/ruleset-cla-required.tf` exists and `terraform fmt -check` passes on
      `infra/github/` (the `infra-validation.yml` `validate` job is green for `infra/github`).
- [ ] `cd infra/github && terraform init -backend=false && terraform validate` passes
      (schema-valid HCL for both resources).
- [ ] `.tf` declares exactly: `enforcement = "active"`; `strict_required_status_checks_policy = false`;
      two `required_check` contexts `cla-check` + `cla-evidence`, both
      `integration_id = var.actions_integration_id`; three `bypass_actors`
      (`OrganizationAdmin`/`pull_request`, `RepositoryRole` id `5`/`pull_request`,
      `Integration` id `1236702`/`always`). Verify with **leading-anchored, comment-safe**
      greps (a bare `grep -c 'required_check {'` false-counts against a header comment that
      names the token):
      `grep -cE '^[[:space:]]*required_check[[:space:]]*\{' ruleset-cla-required.tf` → 2;
      `grep -cE '^[[:space:]]*bypass_actors[[:space:]]*\{' ruleset-cla-required.tf` → 3.
- [ ] `bash tests/scripts/test-audit-ruleset-bypass.sh` exits 0 with `T-cla-1` and
      `T-cla-1b` reporting `ok` **against the `.tf`** (not the create-script). Confirm the
      run output names `ruleset-cla-required.tf`, and `grep -c _cla_create_payload
      tests/scripts/test-audit-ruleset-bypass.sh` → 0 (heredoc slicer deleted).
- [ ] `T-cla-1b` is non-vacuous: temporarily flip the `.tf` OrganizationAdmin `actor_id`
      to a non-sentinel value (e.g. `7`) and confirm `T-cla-1b` reports `fail`; revert.
- [ ] Import-gate rewrite is per-address:
      `grep -c 'import_ruleset github_repository_ruleset' apply-github-infra.yml` → 2, and no
      remaining blanket `grep -qE '\^github_repository_ruleset'` gate.
- [ ] `cron-ruleset-bypass-audit.ts` `CLA_AUDIT_CONFIG.sourceHint ===
      "infra/github/ruleset-cla-required.tf"`; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] `grep -rn 'create-cla-required-ruleset.sh' apps/web-platform/server/inngest knowledge-base/engineering/operations/runbooks`
      returns only DR-context mentions (no "source of truth"/"deferred/no-Terraform" assertions remain).
- [ ] `scripts/create-cla-required-ruleset.sh` no longer contains the `cat > "$payload" << 'EOF'`
      heredoc; `bash -n scripts/create-cla-required-ruleset.sh` parses.
- [ ] ADR-032 carries a dated CLA amendment; `grep -q 'ruleset-cla-required.tf' ADR-032*.md` → true.

### Post-merge (auto, no operator action)

- [ ] On merge, `apply-github-infra.yml` fires (path `infra/github/*.tf`), imports
      `github_repository_ruleset.cla_required soleur:13304872` (first apply only), plans a
      **no-op** for the CLA resource (live values already match), and the destroy-guard
      shows `0` destructive changes. Verify via the workflow run's Post-apply summary:
      `Ruleset 13304872 required_status_checks count = 2`.
- [ ] `Ref #6072` in the PR body (NOT `Closes` — the auto-apply reconcile is the true
      completion; close #6072 after the apply run is green). `gh issue close 6072` is handled
      by `/ship` post-merge verification, not an operator step.

## Infrastructure (IaC)

### Terraform changes
- New: `infra/github/ruleset-cla-required.tf` (`github_repository_ruleset.cla_required`).
  Edited: `infra/github/outputs.tf`. No new variables (reuse `var.gh_repo`,
  `var.actions_integration_id`). Provider (`integrations/github ~> 6.10`, App-auth) and
  R2 backend are unchanged — this root already has both.
- Sensitive vars: none new. Existing `TF_VAR_github_app_id` /
  `TF_VAR_github_app_private_key` (Doppler `prd_terraform`, mirrored from `prd` by the
  web-platform infra `doppler_secret` resources) and R2 `AWS_*` creds are already wired
  into `apply-github-infra.yml`.

### Apply path
- **Auto-apply workflow (cloud-init equivalent = the existing CI apply job).** The PR
  merge IS the human authorization (`hr-menu-option-ack-not-prod-write-auth`);
  `apply-github-infra.yml` fires on `infra/github/*.tf`, imports the CLA ruleset on first
  apply (idempotent), plans, runs the destroy-guard, applies, and post-apply-verifies.
  Expected blast radius: **zero** — the CLA `.tf` values are byte-identical to live, so the
  first apply is a no-op reconcile (import-then-plan), exactly like the CI ruleset's
  `adr-ordinals` reconciliation.
- Fully automated: no operator terminal step, no secret-provisioning step, no vendor
  dashboard step. No new secret to mint — the App credentials already live in
  `prd_terraform`.

### Distinctness / drift safeguards
- `dev != prd`: N/A — this root manages one org's repo governance; there is no dev/prd split.
- No `lifecycle.ignore_changes` needed (bypass_actors are declared explicitly). If a
  post-import plan surfaces `bypass_actors` churn, add
  `lifecycle { ignore_changes = [bypass_actors] }` mirroring CI Risk R6 — flag at apply.
- State: the CLA resource lands in the same encrypted R2 state key
  (`github/terraform.tfstate`) as CI. Rulesets carry no secrets → no secret values in state.

### Vendor-tier reality check
- N/A — GitHub rulesets have no paid-tier gate; the CI ruleset already proves the
  `integrations/github` provider creates/manages rulesets on this plan.

## Observability

```yaml
liveness_signal:
  what: daily cron-ruleset-bypass-audit (CLA step) + apply-github-infra Post-apply summary (CLA count probe)
  cadence: daily (Inngest cron) + on every infra/github/*.tf merge
  alert_target: Sentry heartbeat "scheduled-ruleset-bypass-audit" (degrades via reportSilentFallback on guard fault); GitHub issue "[Ruleset Audit] CLA Required ruleset drift" on real drift
  configured_in: apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts
error_reporting:
  destination: Sentry (guard fault -> reportSilentFallback heartbeat) + GitHub compliance/critical issue (real drift)
  fail_loud: true (apply workflow exits non-zero on plan/import/verify failure; sync gate fails CI)
failure_modes:
  - mode: CLA .tf diverges from canonical (context/integration_id/bypass)
    detection: T-cla-1 / T-cla-1b in test-audit-ruleset-bypass.sh (CI "Bash fixture tests for guard scripts")
    alert_route: CI red on the PR (blocks merge)
  - mode: apply computes a destructive change on the CLA ruleset (nested required_check removal)
    detection: destroy-guard-filter.jq nested_deletes counter in apply-github-infra.yml
    alert_route: apply workflow exit 1 + ::error:: annotation; requires [ack-destroy]
  - mode: CLA ruleset first-apply import skipped -> apply attempts CREATE (name collision)
    detection: terraform apply error surfaced in the workflow run (non-zero exit) + Post-apply summary status=failure
    alert_route: apply workflow exit 1 (mitigated at source by the per-address import gate, Phase 2)
  - mode: live CLA ruleset drifts (bypass widened / check dropped / enforcement suspended)
    detection: daily cron-ruleset-bypass-audit CLA step
    alert_route: GitHub issue "[Ruleset Audit] CLA Required ruleset drift" (labels ci/auth-broken, compliance/critical)
logs:
  where: GitHub Actions run logs (apply-github-infra Post-apply summary) + Sentry (cron heartbeat) + GitHub issues (drift)
  retention: GitHub Actions default (90d) + Sentry retention + issue permanence
discoverability_test:
  command: bash tests/scripts/test-audit-ruleset-bypass.sh
  expected_output: "=== N passed, 0 failed ===" with T-cla-1 and T-cla-1b reporting ok
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-032 — GitHub branch-protection ruleset as IaC** (status: accepted,
2026-05-16). ADR-032's accepted decision is "the branch-protection ruleset is
Terraform-managed"; its Context names only the CI ruleset (id 14145388). This change
**extends that same accepted decision to a second ruleset** (CLA Required, id 13304872)
under the same `infra/github/` root + `apply-github-infra.yml` apply path — an extension,
not a new decision — so **amend ADR-032** (dated "Amendment (2026-07-06, #6072): the CLA
Required ruleset (id 13304872) is now managed by the same root via `ruleset-cla-required.tf`;
`create-cla-required-ruleset.sh` is demoted to a DR-only restore skeleton mirroring
`create-ci-required-ruleset.sh`"). No new ADR ordinal.

### C4 views
**No C4 impact** — checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
`grep -niE 'ruleset|cla required|ci required|branch protection'` returns **zero hits** in
all three. Enumerated for this change: (a) external human actors — none new (contributors
are not modeled as C4 elements; the CLA ruleset governs their PR merges, a CI/governance
control outside the runtime C4 boundary); (b) external systems / vendors — GitHub is the
repo host / CI substrate, already the implicit build-plane and deliberately not a C4
runtime element (the CI ruleset, also IaC per ADR-032, is likewise absent from C4);
(c) containers / data stores — none (no runtime container touches the ruleset); (d) access
relationships — none change in the product runtime (bypass actors are GitHub-side merge
permissions, not product authZ). Declaration-surface-only within an already-non-C4-modeled
governance plane, so "no C4 impact" is correct and consistent with ADR-032's CI ruleset
also being absent from the C4 model.

### Sequencing
No soak gate. The ADR-032 amendment ships in this PR (the decision is true the moment the
`.tf` is authored + applied).

## Domain Review

**Domains relevant:** Engineering (primary). Legal (low — no enforced-value change).

### Engineering
**Status:** reviewed (via plan-review eng panel — architecture-strategist + Kieran +
code-simplicity; findings folded below).
**Assessment:** Extension of an established, reviewed pattern (CI ruleset IaC, ADR-032).
Highest-risk surface is the apply-path import gate (SE-2) and the `.tf`↔canonical `0`/`null`
normalization in `T-cla-1b` (SE-1); both are load-bearing and covered by ACs. No new
architecture; mirrors CI structure 1:1.

### Legal
**Status:** reviewed (carry-forward from #6061 CLO review).
**Assessment:** The CLA ruleset's *enforced values* (required checks + bypass actors) are
byte-identical before/after. CLO already reviewed the drift-guard chain in #6061. This
change moves only HOW the ruleset is declared (imperative script → Terraform), not WHAT it
enforces, so the compliance posture is unchanged. No CLO re-sign required (threshold is
`none`; #6061 owns the compliance-load-bearing framing).

### Product/UX Gate
Not relevant — no UI surface (no files under `components/**`, `app/**`, etc.). NONE.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` queried against the 9 planned file
paths at plan time — zero bodies reference `ruleset-cla-required.tf`,
`apply-github-infra.yml`, `test-audit-ruleset-bypass.sh`, `create-cla-required-ruleset.sh`,
or `cron-ruleset-bypass-audit.ts`. `/work` re-runs the two-stage `gh --json` + standalone
`jq --arg` form to confirm.)

## Test Scenarios

1. **`T-cla-1` green against `.tf`:** canonical RSC contexts (`cla-check`, `cla-evidence`)
   == `.tf` `context = "..."` set; all canonical integration_ids `15368`; `.tf` binds both
   to `var.actions_integration_id`, no `codeql_integration_id`; no dup; `>= 2` floor.
2. **`T-cla-1b` green with `0`↔`null`:** `.tf` bypass triples (awk-parsed, `0`→`null`
   normalized) == canonical triples; no dup; `>= 3` floor. RED-proof: OrgAdmin
   `actor_id = 7` → `fail`.
3. **`T-cla-1b` awk extraction sketch** (verify against the authored `.tf` at `/work`, do
   not trust blind):
   ```bash
   awk '
     /^[[:space:]]*bypass_actors[[:space:]]*\{/ {blk=1; aid="null"; at=""; bm=""; next}
     blk && /^[[:space:]]*actor_id[[:space:]]*=/    {v=$0; sub(/.*=[[:space:]]*/,"",v); sub(/[[:space:]]*(#.*)?$/,"",v); aid=v}
     blk && /^[[:space:]]*actor_type[[:space:]]*=/  {v=$0; sub(/.*=[[:space:]]*"?/,"",v); sub(/"?[[:space:]]*(#.*)?$/,"",v); at=v}
     blk && /^[[:space:]]*bypass_mode[[:space:]]*=/ {v=$0; sub(/.*=[[:space:]]*"?/,"",v); sub(/"?[[:space:]]*(#.*)?$/,"",v); bm=v}
     blk && /^[[:space:]]*\}/ {print aid"|"at"|"bm; blk=0}
   ' "$cla_tf" | sed 's/^0|/null|/' | sort
   ```
4. **Import idempotency (dry-run reasoning):** on a state that already contains
   `ci_required` but not `cla_required`, the per-address gate imports only `cla_required`;
   on a state with both, it imports neither. Confirm by reading the rewritten step.
5. **Terraform validate:** `terraform init -backend=false && terraform validate` green for
   the two-resource root; `terraform fmt -check`.
6. **Full suite:** `bash tests/scripts/test-audit-ruleset-bypass.sh` exits 0 (all T-rsc-*,
   T-cla-*, T-mq-1 green — the `.tf` addition must not perturb `T-rsc-9`'s file-scoped grep).

## Risks & Sharp Edges

- **SE-1 (`0`↔`null` sentinel):** the canonical bypass JSON carries `actor_id: null` for
  OrganizationAdmin (it mirrors the LIVE API shape the daily audit compares against — do
  NOT change the canonical to `0`), while the `.tf` uses `actor_id = 0` (provider issue
  #2536). `T-cla-1b` MUST normalize `0`→`null` before comparing, or it false-fails on a
  correct `.tf`. Load-bearing; covered by AC + Test 2 RED-proof.
- **SE-2 (import-gate name collision):** the blanket `grep -qE '^github_repository_ruleset\.'`
  import gate would skip the CLA import once CI is in state, making the next apply CREATE a
  duplicate/colliding "CLA Required" ruleset. The per-address rewrite (Phase 2) is the fix;
  if it regresses, the first post-merge apply fails loudly (non-zero exit) — design it right.
- **SE-3 (comment-naive gate greps):** `T-cla-1`/`T-cla-1b` and two count-ACs grep/awk the
  `.tf` with comment-naive patterns. The `.tf`'s header/block comments must not contain a
  literal `context = "..."`, `required_check {`, or `bypass_actors {` token, nor an inline
  `# ... = ...` on any assignment line (greedy awk `.*=`). All slips fail safe (RED) except
  the two count-ACs, which are made leading-anchored/comment-safe. See Phase 1 token hygiene.
- **Deepen-plan precedent-diff (DONE):** the precedent-diff gate (deepen Phase 4.4) ran —
  see the Deepen Insights precedent-diff table. Only the three documented divergences
  (`strict = false`, third bypass actor, two checks / no CodeQL) exist; the mirror is faithful.
- **Empty `## User-Brand Impact` fails deepen-plan Phase 4.6** — filled above (threshold none
  + reason bullet).
- **Do NOT generalize `destroy-guard-filter.jq`** — it is intentionally path-specific and
  already `github_repository_ruleset`-type-scoped (covers CLA with no edit).
- **`terraform fmt`** — run `terraform fmt infra/github/` before commit; `infra-validation.yml`
  fails on unformatted HCL.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Leave `create-cla-required-ruleset.sh` as-is (inline heredoc), only repoint the gate + sourceHint | **Rejected** — leaves an unpinned second SSOT (heredoc no longer gated → silent drift). CI precedent refactored `create-ci` to read canonicals; mirror it. |
| **Delete** `create-cla-required-ruleset.sh` entirely | **Rejected** — removes the documented DR restore path. CI kept `create-ci` as DR; keep the capability. |
| Use a literal `integration_id = 15368` in the `.tf` (not `var.actions_integration_id`) | **Rejected** — diverges from the CI pattern the issue asks to mirror; the variable already defaults to 15368 and keeps one knob. |
| Write a NEW ADR for CLA-as-IaC | **Rejected** — ADR-032 already decided ruleset-as-IaC; this is an extension → amend, not a new ordinal. |
| Change the canonical `null` → `0` to avoid `T-cla-1b` normalization | **Rejected** — the canonical mirrors the LIVE API (null); changing it would break the daily audit's live-vs-canonical comparison. Normalize in the gate instead. |
| Add `cla_ruleset_id`/`cla_ruleset_url` outputs + a `T-cla-2` DR-script-references-canonicals gate | **CUT (code-simplicity review)** — outputs have no consumer (verify probes by hardcoded id); `T-cla-2` gates a filename string that Phase 4's runtime `--slurpfile` already guarantees. YAGNI. |
