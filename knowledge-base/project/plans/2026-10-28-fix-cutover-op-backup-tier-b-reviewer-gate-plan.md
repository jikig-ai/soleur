---
title: "fix(cutover): gate op=backup behind the reviewer environment and re-plumb HCLOUD_TOKEN to Tier B"
type: fix
date: 2026-10-28
slug: fix-cutover-op-backup-tier-b-reviewer-gate
branch: feat-one-shot-9755-backup-env-gate
issue: 9755
closes: 9755
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

# fix(cutover): gate op=backup behind the reviewer environment and re-plumb HCLOUD_TOKEN to Tier B

## Overview

`cutover-inngest.yml`'s `op=backup` dispatch performs a Hetzner `create_image` — a write against the production web-platform server — using the read/write `HCLOUD_TOKEN` fetched from the `prd_terraform` Doppler config, yet the job's `environment:` expression does not include `backup`, so the write dispatches with no required-reviewer approval. ADR-241 operator step O10 has already evicted the read/write name from `prd_terraform` (names-only listing, 2026-10-20), so the op refuses today on an empty read: the gap is closed in the wrong direction — gated by absence, not by review. This plan binds `op=backup` to the `inngest-cutover` environment (required-reviewer plus a `main`-only deployment-branch policy, already carrying the `DOPPLER_TOKEN_INFRA_PRIVILEGED` environment secret since runbook step O3), delivers the token through the `.github/actions/infra-credentials` loader exactly as every other Tier-B consumer receives it, updates the pinned infra suite's membership and op-set parity assertions, and retires the expiring allowlist entry in `scripts/lint-hcloud-token-readonly-no-fallback.sh`, per issue #9755.

## Research Insights

**Premise validation (Phase 0.6).** Issue #9755 is OPEN (`type/security`, `priority/p2-medium`, `domain/engineering`), not closed by any PR. Both cited paths exist on `origin/main`: `.github/workflows/cutover-inngest.yml` (254 lines) and `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (4992 lines). Two premises were stale — see Research Reconciliation. Collision pre-check (`collision-precheck.sh 9755`, exit 10) found PR #11455 — it is this pipeline's own WIP draft on this branch (`feat-one-shot-9755-backup-env-gate`, author deruelle, no files), not a foreign duplicate. Three `test-all.sh` processes on other worktrees are unrelated suite runs.

**Property list (Phase 0.6b).** The asks restated as observable properties: (P1) an `op=backup` dispatch cannot reach its Hetzner write credential without a required-reviewer approval; (P2) the `HCLOUD_TOKEN` the arm uses comes from `soleur-infra-privileged/prd` (Tier B), never from `prd_terraform`; (P3) every op that can reach a prod-write-capable credential is inside the reviewer gate, and only those ops are; (P4) the change keeps every pinned guard green — membership, op-set parity, the hcloud no-fallback scan, the tier census, actionlint.

**Cut list (Phase 0.6b).** (a) A second `environment:` or a new GitHub Environment for `backup` — cut: `inngest-cutover` is the existing reviewer-gated, `main`-policied environment and was seeded with `DOPPLER_TOKEN_INFRA_PRIVILEGED` at runbook step O3 (`infra-credential-tiers-8209.md` O3 row). (b) A bespoke scoped `doppler secrets get` against `soleur-infra-privileged` inside the script — cut: `.github/actions/infra-credentials` already buys P2 and is the canonical O10 mechanism; a script-level read would stay invisible to the tier census and would perpetuate the `lint-hcloud-token-readonly-no-fallback.sh` allowlist debt the ADR schedules for deletion with this fix.

**Repo findings.**

- The defect is exact: `.github/workflows/cutover-inngest.yml:100` binds `inngest-cutover` for `arm|rollback|resume|reflush|luks-cutover` — not `backup` (issue's mention of `luks-rollback` is stale; it was retired by #8285 PR B).
- `scripts/cutover-inngest.sh:1902` is the lone read/write `doppler secrets get HCLOUD_TOKEN --plain`, allowlisted (exact count 1, expiry 2026-12-15) in `scripts/lint-hcloud-token-readonly-no-fallback.sh`; since O10 the read returns empty and `_bearer_ok` refuses — **the op is already dead**, not merely ungated.
- The Tier-B delivery convention is uniform: `./.github/actions/infra-credentials` (composite; installs a pinned Doppler CLI itself) takes `doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}` on a job bound to a Tier-B environment, downloads `soleur-infra-privileged/prd`, masks and exports every name plus its `TF_VAR_*` form. Consumers then read the env var: `HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"  # loader-exported (#8209)` (apply-web-platform-infra.yml:2148, 2334, 2583, 2779) or stdin-fed (`git-data-wipe.sh`, `<<<"${HCLOUD_TOKEN:-}"` in git-data-cutover.yml:1442). Omitting `doppler-token-legacy` makes the loader fail closed on `verdict=no_credential_source` — the `git-data-cutover.yml::wipe` precedent for a must-never-fall-back op.
- `inngest-cutover` is TF-provisioned (`apps/web-platform/infra/inngest-arm-write-token.tf`: `github_repository_environment.inngest_cutover` with `reviewers.users = [54279]` + `github_repository_environment_deployment_policy.inngest_cutover_main` `branch_pattern = "main"`) and is one of the four environments seeded at O3.
- The pinned suite (`cutover-inngest-workflow.test.sh`) has three load-bearing structures this change must update: the reviewer-gate membership loop (`for _op in arm rollback resume reflush`), the `#7674` op-set parity (`ENV_OPS == TOK_OPS`, environment vs `DOPPLER_TOKEN_INNGEST_ARM` ternary — breaks the moment `backup` joins only one side), and `_EXACT_FLOOR=1135` (every added/removed assertion requires a measured count update plus a changelog comment). A fourth pin (`WF_YAML` non-comment lines must not contain `INNGEST_HOST|FLOOR|SKEW|HCLOUD`) forbids the literal `HCLOUD` anywhere in the workflow outside leading-`#` comments — including trailing comments on code lines.
- `test-infra-privileged-tier-census.sh` already classifies this job as Tier-B-bound (its `environment:` arms include `inngest-cutover`); its run: body stays script-only, so no census row changes. `trio-baseline.tsv` tracks only `WEBHOOK_DEPLOY_SECRET`/`CF_ACCESS_CLIENT_*` — no new row. The infra-privileged census's G1j (every loader caller declares a Tier-B `environment:`) stays green because the job's env arms already include `inngest-cutover`.
- The lint's documented end state: "SOLEUR-DEBT: one expiring allowlist entry for the op=backup read (#9755); delete when op=backup is re-plumbed to a Tier-B environment" — removal in the same change is the ADR's own instruction, and its battery (`tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh`) pins `allowlisted=1` on the live row plus expiry-parity rows (X2/X3) that must be retired with it.
- `gh workflow run cutover-inngest.yml --field op=backup` is runbook step 0.5 of the cutover (`inngest-server.md:2510`); the dispatch now holds in "Waiting" for the environment reviewer — the runbook's procedure text needs the one-line note.
- Merge effect: `apply-web-platform-infra.yml` fires on `push: main` with `paths: apps/web-platform/infra/**` — the `.test.sh` edit fires the production apply (expected: a no-op plan; no `.tf` resources change). Verification path is the apply's own run + `scripts/betterstack-query.sh`, no SSH (issue ask #3).

**Institutional learnings applied.** `2026-07-23-new-tf-resource-in-target-scoped-apply-root-and-unprotected-env-autocreate.md` (the apply is `-target`-scoped; we add no `.tf` resource so nothing must join a target list — and an environment referenced without TF state auto-creates unprotected, which is exactly why this plan reuses the already-provisioned `inngest-cutover` rather than creating one). `2026-10-01-the-credential-move-was-sound...` (a moved credential's *reach* must be re-measured: the op-set parity assertion is rewritten, not just extended). `2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md` (mirror the whole delivery wiring — `if:` + conditional `with:` + environment — not just a token line). `2026-10-24-credential-tier-cutover-invalidates-recipes-asymmetrically.md` (reads stay green, writes 403: the post-merge proof is a real gated dispatch, not a config readback). `2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` (the union assertion pins the property — no ungated credential, no uncredentialed gate — not the member list).

**External research decision.** Security topic → researched. Binding evidence is in-repo: `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED` in a step `with:` input is the exact form every Tier-B job already runs; environment secrets resolve in the `secrets` context for a job whose `environment:` binds — whether the binding is a literal or this expression form, the reviewer gate already proves binding works for arm ops today. GitHub context restrictions verified (step-level `with:`/`env:` accept `secrets`; step `if:` does not need it — `inputs` suffices).

**Open code-review overlap (Phase 1.7.5).** None — `gh issue list --label code-review --state open` bodies contain none of the planned paths.

## Problem Statement / Motivation

Two defects share one cause. (1) **Ungated prod write:** `op=backup`'s `create_image` wrote with a repo-secret-reachable Doppler token and no required-reviewer environment — the class ADR-241's Tier B exists to close. (2) **Dead op:** O10 evicted the read/write name from `prd_terraform`, so the arm refuses on an empty read — the pre-cutover recovery point (`inngest-server.md` step 0.5) has been unavailable since 2026-10-20. The issue's "before O10" deadline has already passed; this plan restores the op's function and closes the gate in one change, because a fix that only re-plumbs the token without the environment binding would resurrect the write *still ungated*, and a fix that only adds the environment leaves the op dead.

## Proposed Solution

Four coordinated edits, one mechanism:

1. **Bind the op to the reviewer gate.** Extend the `environment:` ternary in `cutover-inngest.yml` with `inputs.op == 'backup'`, so a backup dispatch resolves `inngest-cutover` — required-reviewer (`@deruelle`, TF `inngest-arm-write-token.tf`) plus `main`-only deployment policy. Update the suite's membership loop to cover it.
2. **Deliver the token the O10 way.** Add one step after `Install Doppler CLI`: `if: inputs.op == 'backup'`, `uses: ./.github/actions/infra-credentials`, `with: doppler-token-infra-privileged: ${{ (inputs.op == 'backup') && secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED || '' }}` and **no** `doppler-token-legacy` — a missing environment secret is the loader's `verdict=no_credential_source` refusal, never a silent Tier-A fallback (the `git-data-cutover.yml::wipe` precedent). The `if:` confines the whole-project export to backup dispatches; the conditional `with:` mirrors the `DOPPLER_TOKEN_INNGEST_ARM` injection idiom and gives the parity check a uniform extraction anchor.
3. **Consume it like every sibling.** In the `backup)` arm of `scripts/cutover-inngest.sh`, replace `HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN --plain)` with `HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"` (loader-exported), rewrite the `ALLOWLISTED READ` comment to describe the Tier-B delivery, and update the refusal message to name the loader and environment. `_bearer_ok` → `::add-mask::` → `_bearer_curl` order is unchanged — no `doppler` invocation remains in the arm.
4. **Retire the debt and re-pin the guards.** Delete the allowlist entry and its machinery (constants, match arm, `F-allowlist` check, expiry warning) from `scripts/lint-hcloud-token-readonly-no-fallback.sh` — the scanner returns to a pure ratchet; rework its battery (the `allowlisted=1` live row, the X2/X3 expiry-parity rows, and the allowlist-semantics rows M1/M8a/M8b/T3a/T3b/O1). In the pinned suite, extend the membership loop to `backup`, rewrite the `#7674` parity as a credentialed-set union (see Guard Contract), add loader-step and over-grant assertions, add behavioral driving of the backup arm, and bump `_EXACT_FLOOR` with a measured count. Append the dated ADR-241 amendment entry and correct the runbook's `op=backup` row.

## Technical Considerations

- **No new infrastructure.** The environment, its reviewer rule, its `main`-policy, and the `DOPPLER_TOKEN_INFRA_PRIVILEGED` environment secret all exist (TF + runbook O3). No `.tf` file changes; the post-merge apply is expected to be a no-op plan.
- **Expression-bound environment + env secrets.** `environment:` resolves at job start before secrets resolution; a `secrets.` reference in a step `with:`/`env:` then sees environment secrets. Step `if:` keys cannot read `secrets` but do not need to (`inputs` suffices). The reviewer hold fires before any step runs — including checkout — so the ack precedes credential delivery by construction.
- **`set -euo pipefail` interplay.** `HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"` is `-u`-safe; `_bearer_ok` refusal path unchanged.
- **Suite interaction surface.** Edits must not introduce the literal `HCLOUD` on any non-comment workflow line (the `WF_YAML` pin at test line ~1604, which strips only leading-`#` lines — a trailing comment on a code line still counts), must not place the text `DOPPLER_TOKEN_INNGEST_ARM:` earlier than the real env line, and must not place `doppler-token-infra-privileged:` earlier than the new `with:` line (both parity extractions read the *first* grep match).
- **Attack surface enumeration (security fix).** Paths that reach the read/write Hetzner credential: (a) `doppler secrets get` in code — this change removes the last one, and the de-allowlisted scan makes a reintroduction red; (b) the `infra-credentials` loader — gated to `if: inputs.op == 'backup'` and the environment binding, so a non-backup dispatch exports nothing; (c) a non-main `workflow_dispatch` — `inngest-cutover`'s `branch_pattern = "main"` policy refuses it, and the reviewer hold covers main dispatches; (d) `pull_request`/fork reach — the job is `workflow_dispatch`-only (`if: github.event_name == 'workflow_dispatch'`), out of attacker reach; (e) `DOPPLER_TOKEN_WRITE` planting a fake name in `prd_terraform` until O11 — inert: the arm reads the job env, never `prd_terraform`, and the loader's exports come from `soleur-infra-privileged` only. Unchecked path: none new — the export lands the whole Tier-B project in the backup dispatch's env (same posture as every Tier-B job; bounded by the `if:` and the reviewer hold).
- **NFRs.** Security posture (credential tier conformance), operability (op restored; one extra reviewer ack in the cutover procedure, already the norm for arm-class ops). No performance/availability impact.

## Research Reconciliation — Spec vs. Codebase

| Spec (issue) claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "`environment:` expression lists arm, rollback, resume, reflush, luks-cutover **and luks-rollback**" | `luks-rollback` was retired by #8285 PR B; the live list is five ops | Membership assertion updated against the real five-op set; the `#8285` Guard-1 pin (luks-rollback absent everywhere) stays green |
| "O10 removes that token … `op=backup` breaks outright **unless** re-plumbed" / "Deadline: before ADR-241 O10" | O10 already landed (names-only listing 2026-10-20; ADR-241 amendments 2026-10-20/22/23); the op already refuses fail-closed | Deadline recorded as missed-with-safe-failure in the ADR entry; fix restores function *and* closes the gate — both, not one |
| "the `environment:` expression … not `backup`" | Exact — `cutover-inngest.yml:100` | `inputs.op == 'backup'` added inside the same ternary |
| "the pinned infra suite's membership assertion" | Two membership sites exist: the `for _op` loop and the `#6894` luks assertion; plus the `#7674` op-set parity that silently breaks | All three reconciled: loop extended, parity rewritten as the credentialed-set union, luks pin untouched |

## User-Brand Impact

- **If this lands broken, the user experiences:** the pre-cutover recovery point (`op=backup`, runbook step 0.5) fails or the dispatch stalls unapproved; a cutover that then hits a defect has no server snapshot to roll back to — platform-wide durable-backend data recovery, not a single user's artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:** a read/write Hetzner token reaching a path without the required-reviewer hold — a `create_image`/`delete` credential for the host that stores every user's inngest state and the platform web root.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** blast radius is the whole fleet's writable credential and the sole pre-cutover recovery point, not one user's record — `aggregate pattern` over `single-user incident`.

## Observability

```yaml
liveness_signal:
  what: "op=backup dispatch reaches terminal state under the reviewer gate; the pinned suite's membership + parity assertions"
  cadence: "per-dispatch (workflow_dispatch); suite per-CI-run"
  alert_target: "GitHub Actions run conclusion + ::error:: annotation; reviewer hold surfaces as a pending deployment on the run"
  configured_in: ".github/workflows/cutover-inngest.yml (job gate + loader step); apps/web-platform/infra/cutover-inngest-workflow.test.sh (run by .github/workflows/ci.yml scripts shard)"
error_reporting:
  destination: "workflow run log annotations (::error title=infra-privileged:: / ::error::backup:)"
  fail_loud: "loader verdict=no_credential_source exit 1 when the environment secret is absent; SOLEUR_CREDENTIAL_REFUSED + ::error::backup: exit 1 when the env export is missing or mis-shaped; ::error::hcloud create_image returned HTTP <code> on a rejected write"
failure_modes:
  - mode: "DOPPLER_TOKEN_INFRA_PRIVILEGED absent on inngest-cutover"
    detection: "loader exits 1 with verdict=no_credential_source before any step runs"
    alert_route: "failed workflow run visible to dispatcher and reviewer"
  - mode: "op=backup dispatched without the env binding (ternary regression)"
    detection: "pinned suite membership + union-parity assertions go red; live dispatch runs ungated but the loader's empty token input fails closed"
    alert_route: "required CI check"
  - mode: "script-level read/write doppler get reintroduced"
    detection: "scripts/lint-hcloud-token-readonly-no-fallback.sh F-literal finding (allowlist deleted — zero tolerated)"
    alert_route: "required CI check"
logs:
  where: "GitHub Actions run log for Cutover Inngest (durable-backend Phase 2); apply outcome in apply-web-platform-infra run + scripts/betterstack-query.sh"
  retention: "GitHub run-log retention (~90 days); Better Stack logs per source retention"
discoverability_test:
  command: bash -c 'grep -oE "inputs\.op == .backup." .github/workflows/cutover-inngest.yml | sort -u'
  expected_output: "inputs.op == 'backup'"
```

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud server image `inngest-cutover-pre-<ts>` (created by the existing op; this plan does not add a store, it re-plumbs the op's authorization)"
    mechanism: "provider-managed:Hetzner snapshot storage (Hetzner security/ISO attestation, retrieved_on 2026-10-28 posture page)"
    evidence: "store itself is pre-existing and unchanged by this diff; cited for completeness of the credential path"
    defends_against: "loss of the root disk at the Hetzner host layer (the store's own purpose)"
    does_not_defend: "a leaked read/write token driving create/delete calls; RLS/host-layer access; snapshot content confidentiality beyond provider storage"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: snapshot image is created only at cutover time under the reviewer hold"
in_transit:
  - connection: "GitHub runner -> Doppler API (doppler secrets download, soleur-infra-privileged/prd)"
    enforced_at: ".github/actions/infra-credentials/action.yml load step (doppler CLI, TLS default)"
    tls: "HTTPS/TLS >=1.2 via Doppler CLI"
    cert_verification: "on"
    does_not_defend: "a compromised runner reading the exported values (reviewer hold + if:-scoping bound when the export exists)"
    disclosed_as: "not-publicly-claimed"
  - connection: "GitHub runner -> api.hetzner.cloud (create_image + action poll)"
    enforced_at: "scripts/cutover-inngest.sh backup) arm _bearer_curl calls"
    tls: "HTTPS/TLS via curl"
    cert_verification: "on"
    does_not_defend: "a holder of the read/write token calling the same API elsewhere (the reviewer gate, not TLS, is the authorization control)"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — credentialed-op-set parity in `apps/web-platform/infra/cutover-inngest-workflow.test.sh`

**Property.** Every dispatch `op` that can reach a prod-write-capable credential — the `DOPPLER_TOKEN_INNGEST_ARM` arm-token set or the Tier-B `DOPPLER_TOKEN_INFRA_PRIVILEGED` loader set — is inside the `environment: inngest-cutover` required-reviewer ternary; every op inside that ternary reaches exactly one such credential; and `backup` is never inside the arm-token set.

**Assembly.** Three chokepoints in `.github/workflows/cutover-inngest.yml`: the `environment:` expression (who must be approved), the `DOPPLER_TOKEN_INNGEST_ARM:` conditional env line (who gets the arm token), and the `infra-credentials` step's `if:`/`doppler-token-infra-privileged:` gating (who gets Tier-B exports). Ops enter through the constrained `choice` list and a single `run:` step — no second dispatch path exists. The suite's `_EXACT_FLOOR` anti-deletion counter is the meta-anchor on the assertion set itself.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `inputs.op == 'backup'` from the `environment:` ternary (loader still delivers) | RED — credentialed `backup` ungated: env set ⊋ union fails |
| 2 | Delete the loader step's `if:`-gating / `doppler-token-infra-privileged` input (env still gates backup) | RED — gated op with no credential delivery: union ⊋ arm set fails |
| 3 | Add `backup` to the `DOPPLER_TOKEN_INNGEST_ARM` ternary (over-grant) | RED — `backup ∉ TOK_OPS` assertion fires |
| 4 | Add a hypothetical second credentialed op (`op=x` in env ternary, no delivery expression) | RED — env ⊋ union, same class as #1 (second member after a compliant first) |
| 5 | Neuter the guard's own extraction (`grep -oE` → a constant list, or the union comparison to `==` a literal) | RED — own-dispatch: the anti-vacuity `non-empty` rows plus the comparison fail on the true tree |
| 6 | (harness) Swap a suite-side `sort -u` for `sort` so order matters | RED on permuted fixture — harness must actually compare sets, not text |
| 7 | (must-PASS) Reorder `inputs.op ==` terms inside the env ternary, or duplicate one term | PASS — set semantics explicitly permitted |

### Guard 2 — `scripts/lint-hcloud-token-readonly-no-fallback.sh` pure ratchet (allowlist retired)

**Property.** No scanned file contains a `doppler secrets get` segment that names the read/write `HCLOUD_TOKEN` — zero tolerated, no allowlist.

**Assembly.** `git ls-files -z --cached --others --exclude-standard` minus the pinned exclusion list; every candidate read flows through the per-logical-line `classify()` (rules A literal / B sameline). With the entry deleted there is no second path: `ALLOW_*` constants, the `rule_a`-satisfies-allowlist arm, the `F-allowlist` count check, and the expiry warning are all removed with it, and the battery loses its allowlist-semantics rows (M1/M8a/M8b/T3a/T3b/O1) and expiry-parity rows (X2/X3).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN --plain)` to `scripts/cutover-inngest.sh` (the exact reintroduction the ratchet exists to catch) | RED — F-literal |
| 2 | Add a *second* bare-name read in a different file after a compliant first | RED — two findings, one per file (a first-hit-only check is the defect class) |
| 3 | (own dispatch) Make `classify()` never report `rule_a` (e.g. drop the `elif rule_a:` findings arm) | RED on the battery's control fixtures — a scanner reporting `findings=0` unconditionally is vacuous |
| 4 | (harness) Mutate the battery's expected live string to `findings=1` | RED on the true tree — proves the battery compares output, not exit shape |
| 5 | (must-PASS) `doppler secrets get HCLOUD_TOKEN_READONLY -p soleur -c prd_terraform --plain` in a scanned file | PASS — the read-only name is the sanctioned Tier-A read; word-bounded match must not fire on it |

**Anchor.** The removed allowlist was a stored exception keyed on `(file, normalized text, count)` with an expiry mirrored in the ADR-241 2026-10-23 entry and the script's own comment; deleting it is safe because the same commit removes the protected line *and* appends a new dated ADR-241 entry recording the retirement — the outside-the-commit record a future auditor diffs against is the append-only amendment log, not a mutable in-file constant.

## Hypotheses

Network-outage checklist (triggered by `SSH`/`terraform apply` tokens in the issue; all layers opt out with artifacts — this defect is an authorization-binding gap, not a connectivity symptom):

1. **L3 firewall allowlist.** [opt-out: no host-side symptom exists — the failing surface is a GitHub environment binding inside Actions; the plan's verification is deliberately no-SSH (`scripts/betterstack-query.sh` + run-log annotations) per the issue's own ask]
2. **L3 DNS/routing.** [opt-out: no packet-path symptom; the op refuses *before* any request is made — `SOLEUR_CREDENTIAL_REFUSED reason=token_shape` in the run log is itself the artifact that no transport was attempted]
3. **L7 TLS/proxy.** [opt-out: no HTTPS-path symptom; the Hetzner API calls are never reached on the broken path]
4. **L7 application.** [opt-out: the service that would log the symptom is not running anywhere — the failure is pre-flight in a CI job, evidenced by the `::error::backup:` annotation, not a host journal]

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Add `backup` to the workflow's `environment:` membership expression and to the pinned infra suite's membership assertion in one change." | FR-1 / Files-to-Edit `.github/workflows/cutover-inngest.yml` + `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | mapped |
| 2 | "Re-plumb the `HCLOUD_TOKEN` read for `op=backup` to the environment-scoped secret (the O10 mechanism) before O10 lands." | FR-2, FR-3 / Files-to-Edit `.github/workflows/cutover-inngest.yml` (loader step) + `scripts/cutover-inngest.sh` | mapped — "before O10 lands" is stale (O10 landed 2026-10-20); the re-plumb is unchanged in substance |
| 3 | "Ship with an operator notice and verify the apply outcome afterwards (provisioners succeeded, Better Stack via `scripts/betterstack-query.sh`, no SSH)." | Operator Holds + Implementation Phase 4 (apply-outcome verification) | mapped |
| 4 | "Location: `.github/workflows/cutover-inngest.yml` (`environment:` expression), `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (membership assertion), ADR-241 amendment log." | Files-to-Edit (all three) + ADR-241 dated entry | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `environment:` ternary edit | "Add `backup` to the workflow's `environment:` membership expression" | asked |
| Pinned-suite membership + parity updates | "and to the pinned infra suite's membership assertion in one change" | asked |
| `infra-credentials` loader step | "to the environment-scoped secret (the O10 mechanism)" | asked |
| `scripts/cutover-inngest.sh` backup-arm env read | "Re-plumb the `HCLOUD_TOKEN` read for `op=backup`" | asked |
| `scripts/lint-hcloud-token-readonly-no-fallback.sh` allowlist removal | — | inferred — justification: the re-plumb deletes the allowlisted line, so `allow_hits` becomes 0 and the scan goes red (`F-allowlist found 0`); the lint's own header prescribes "delete when op=backup is re-plumbed to a Tier-B environment" |
| `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` battery surgery | — | inferred — justification: the battery pins `allowlisted=1` and expiry-parity rows (X2/X3) that cannot survive the allowlist's deletion; unedited it goes red, the contract rots |
| ADR-241 dated amendment entry | "ADR-241 amendment log" | asked |
| `infra-credential-tiers-8209.md` `op=backup` row update | — | inferred — justification: the row asserts "Currently ungated and non-conformant … until #9755 lands"; landing the fix without correcting it leaves the canonical tier table false (the stale-claim class of `2026-10-01-the-credential-move-was-sound`) |
| `inngest-server.md` step 0.5 approval note | — | inferred — justification: the procedure dispatches `op=backup` and waits for `success`; post-change the run first parks in "Waiting" on the environment approval — an undocumented hold reads as a stuck run mid-cutover |
| Apply-outcome verification phase | "verify the apply outcome afterwards (provisioners succeeded, Better Stack via `scripts/betterstack-query.sh`, no SSH)" | asked |

### Split Assessment

- Subsystems touched: 5 — `.github`, `scripts`, `apps/web-platform`, `tests`, `knowledge-base`
- Planned files: 8 | Estimated changed lines: ~420 (suite + battery surgery dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root-count threshold trips, but every file pair is one atomic guard↔subject unit; a split leaves the lint red without the script change, the pinned suite red without the workflow change, and the battery red without the lint change. Indivisible.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to CI credential plumbing, a guard suite, and runbook/ADR records. The mechanical UI-surface scan of Files to Edit/Create matches nothing (no `components/`, `app/`, `*.tsx`, `*.njk`).

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` — new dated amendment-log entry `### 2026-10-28 (#9755): op=backup re-plumbed to Tier B; the expiring script-read allowlist is retired`, recording: the `environment:` extension, the loader delivery (the O10 mechanism), the script env read, the allowlist deletion per the 2026-10-23 entry's own end state, the credentialed-set-union parity, and the retrospective that the "before O10" deadline was missed with a safe failure mode (the op refused rather than writing ungated). Append-only; no existing entry is edited. This is a record entry, not a new decision — the decision was already ADR-241's; no new ADR ordinal is consumed.

### C4 views

No C4 impact — enumeration performed against all three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors — dispatcher and reviewer are both `founder`, already modeled with `founder -> github`/`founder -> doppler` approval edges (model.c4:557-558); (b) external systems — `github`, `doppler`, `hetzner`, `betterstack`, `inngest` are all modeled elements and already included in `views.c4`; the environment/environment-secret binding is GitHub-internal machinery (per the views.c4 #8359 convention, github-internal writes live on edge descriptions, not elements); (c) containers/data-stores — none touched; the snapshot image the op creates is vendor state, not a modeled store; (d) actor↔surface relationships — the reviewer hold is an authorization property of an existing `github` edge, not a new relationship.

### Sequencing

Not applicable — the decision is true on merge (with the documented interim that the op already refuses today).

## Infrastructure (IaC)

No new infrastructure is introduced — environment, reviewer rule, `main` deployment policy and the `DOPPLER_TOKEN_INFRA_PRIVILEGED` environment secret are already provisioned (TF `inngest-arm-write-token.tf`, runbook step O3). The merge *does* fire `apply-web-platform-infra.yml` (push path `apps/web-platform/infra/**` covers the `.test.sh` edit); expected outcome is a no-op plan since no `.tf` resource changes. Post-merge verification follows the issue's ask: the apply run's provisioner results plus `bash scripts/betterstack-query.sh` for the pipeline — no SSH.

## Operator Holds

- Hold: Operator-reserved: merge authorization — merging this PR fires the production Terraform apply (`apps/web-platform/infra/**`); the #10390 standing delegation does not cover it.
- Hold: Operator-reserved: the post-merge `op=backup` verification dispatch itself performs a production Hetzner `create_image` (and a later `DELETE /v1/images/<id>`); it requires the same reviewer approval the change installs — the approval is the authorization, exercised by the operator, not by the pipeline.

## Implementation Phases

### Phase 1 — Workflow + script re-plumb

1. `.github/workflows/cutover-inngest.yml`: add `|| inputs.op == 'backup'` inside the `environment:` ternary; update the gate comment block (lines ~87-99) to record `op=backup` writes a prod artifact (Hetzner snapshot) and rides the same reviewer gate; insert the `if: inputs.op == 'backup'` `infra-credentials` step between `Install Doppler CLI` and `Run cutover host op via webhook`, passing only `doppler-token-infra-privileged` (conditional `&&` form, no legacy token). No `HCLOUD` literal on any non-comment line; no `DOPPLER_TOKEN_INNGEST_ARM:` text earlier than the real env line.
2. `scripts/cutover-inngest.sh` `backup)` arm: `HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"`; rewrite the `ALLOWLISTED READ` comment block into the Tier-B delivery description; refusal `::error::` text names the loader + `inngest-cutover` environment; keep `_bearer_ok` → `::add-mask::` → `_bearer_curl` order and every downstream line unchanged.

### Phase 2 — Pinned suite updates (`apps/web-platform/infra/cutover-inngest-workflow.test.sh`)

1. Membership loop: `for _op in arm rollback resume reflush backup`.
2. Rewrite the `#7674` parity block: extract `PRIV_EXPR`/`PRIV_OPS` from the `doppler-token-infra-privileged:` line (same `grep -oE "inputs\.op == '[a-z-]+'"` idiom); assert `ENV_OPS == sort -u(TOK_OPS ∪ PRIV_OPS)`; add `backup ∉ TOK_OPS`; keep both anti-vacuity non-empty rows plus a loader-located row.
3. New assertions: loader step exists with `uses: ./.github/actions/infra-credentials` + `if:` containing `inputs.op == 'backup'`; no `doppler-token-legacy:` in the file (fail-closed posture, wipe precedent); `backup` present in env ternary (via the loop above).
4. Behavioral driving of the extracted `backup)` arm (mirroring the `#8285` luks battery): env `HCLOUD_TOKEN` unset/empty → `SOLEUR_CREDENTIAL_REFUSED` + exit 1, zero curl calls; mis-shaped value → same refusal; well-formed sentinel → `::add-mask::` precedes the first `_bearer_curl` call and the request is the `create_image` POST; non-201 → named `::error::` exit 1. Assert the arm contains no `doppler` invocation.
5. Bump `_EXACT_FLOOR` to the measured count and append the count-changelog comment (`1135 -> N (+K) at #9755: …`).

### Phase 3 — Lint allowlist retirement (`scripts/lint-hcloud-token-readonly-no-fallback.sh` + battery)

1. Delete `ALLOW_FILE`/`ALLOW_TEXT`/`ALLOW_COUNT`/`ALLOW_EXPIRY`/`WARN_DAYS`, the `allow_hits` counter and match arm, the `F-allowlist` check, and the expiry warning block; update the header's `ALLOWLIST`/`EXPIRY`/`OWNER AND TRACKERS` prose to record that the exception was retired at #9755 and the scanner is now a pure ratchet; drop `allowlisted=` from the summary line (or print it pinned at 0 — pick one and match the battery).
2. `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh`: update `GREEN`/live-row expectations (`allowlisted` gone or `0`), delete/rework rows whose whole subject is allowlist semantics or expiry parity (M1, M8a, M8b, T3a, T3b, X2, X3, O1, and any fixture expecting `allowlisted=1`), keep all F-literal/F-sameline/population/self-test rows.

### Phase 4 — Records + apply verification

1. ADR-241: append the dated amendment entry (see Architecture Decision).
2. `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: rewrite the `cutover-inngest.yml::cutover` (`op=backup`) row — environment `inngest-cutover`, token `DOPPLER_TOKEN_INFRA_PRIVILEGED` → loader → `HCLOUD_TOKEN` env; remove "Currently ungated and non-conformant".
3. `knowledge-base/engineering/operations/runbooks/inngest-server.md` step 0.5: one line noting the dispatch holds in "Waiting" for the `inngest-cutover` approval before the snapshot starts.
4. Post-merge (operator hold): confirm the push-triggered `apply-web-platform-infra` run's provisioner results are green and query Better Stack via `bash scripts/betterstack-query.sh` — no SSH; then the operator may dispatch `op=backup` to prove the gate end-to-end (it must park in "Waiting" until approved).

## Files to Edit

- `.github/workflows/cutover-inngest.yml` — `environment:` ternary + new `infra-credentials` step + gate comments (~25 lines)
- `scripts/cutover-inngest.sh` — `backup)` arm token read + comment + refusal text (~15 lines)
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — membership loop, parity rewrite, loader assertions, backup-arm behavioral rows, `_EXACT_FLOOR` (~140 lines)
- `scripts/lint-hcloud-token-readonly-no-fallback.sh` — delete allowlist entry + machinery, header prose, summary line (~45 lines)
- `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` — battery surgery for the retired allowlist (~140 lines)
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` — dated amendment entry (~15 lines)
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` — `op=backup` row (~1 row)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — step 0.5 approval note (~2 lines)

## Files to Create

None.

## Acceptance Criteria

- [ ] `cutover-inngest.yml`'s `environment:` expression resolves `inngest-cutover` for `inputs.op == 'backup'` (and only for the gated op set).
- [ ] A step `if: inputs.op == 'backup'` invokes `uses: ./.github/actions/infra-credentials` with `doppler-token-infra-privileged` bound to `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED` and no `doppler-token-legacy` input.
- [ ] `scripts/cutover-inngest.sh` contains zero `doppler secrets get` of the bare `HCLOUD_TOKEN` name; the `backup)` arm reads `${HCLOUD_TOKEN:-}` and refuses with `SOLEUR_CREDENTIAL_REFUSED` before any request when it is empty or mis-shaped.
- [ ] `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0: membership loop covers `backup`; `ENV_OPS == union(arm-token ops, Tier-B loader ops)`; `backup` is absent from the arm-token expression; `_EXACT_FLOOR` matches the dispatched count.
- [ ] `bash scripts/lint-hcloud-token-readonly-no-fallback.sh` exits 0 with `findings=0` and no surviving allowlist entry.
- [ ] `bash tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` exits 0.
- [ ] `bash tests/scripts/test-infra-privileged-tier-census.sh` and `bash tests/scripts/test-trio-baseline-census.sh` exit 0 (no census regression).
- [ ] No non-comment line of `.github/workflows/cutover-inngest.yml` contains the literal `HCLOUD` (the suite's `WF_YAML` knob pin).
- [ ] ADR-241 carries a new dated entry recording the re-plumb, the allowlist retirement, and the missed-deadline retrospective; the `infra-credential-tiers-8209.md` `op=backup` row and `inngest-server.md` step 0.5 are updated.
- [ ] Actionlint/YAML parse of the edited workflow passes (the suite's `YAML parses` assertion plus CI's actionlint job).

## Test Scenarios

- Given `op=backup` is not in the `environment:` ternary, when the suite runs, then the union-parity assertion fails (RED) — `unit` (suite mutation row 1).
- Given the loader's `if:`/`with:` gating is removed while `backup` stays env-gated, when the suite runs, then the union assertion fails — `unit` (row 2).
- Given `backup` is added to the `DOPPLER_TOKEN_INNGEST_ARM` ternary, when the suite runs, then the `backup ∉ TOK_OPS` assertion fails — `unit` (row 3).
- Given the extracted `backup)` arm with `HCLOUD_TOKEN` unset, when the driver invokes it, then exit 1 with `SOLEUR_CREDENTIAL_REFUSED` and zero recorded curl calls — `unit`.
- Given the arm with `HCLOUD_TOKEN=RW-SENTINEL`, when invoked, then `::add-mask::` precedes the first request and the request is `POST /v1/servers/123931471/actions/create_image` — `unit`.
- Given `doppler secrets get HCLOUD_TOKEN --plain` reintroduced anywhere in the tree, when `lint-hcloud-token-readonly-no-fallback.sh` runs, then `F-literal` + exit 1 (no allowlist absorbs it) — `unit`.
- Given a post-merge `workflow_dispatch` of `op=backup` on `main`, when the run starts, then it parks in "Waiting" pending the `inngest-cutover` reviewer, and after approval the loader exports `HCLOUD_TOKEN` and the snapshot action completes — `e2e`, `pyramid-justified: the gate is a GitHub-side deployment hold that no suite can drive; only a real dispatch proves binding + hold + delivery`.
- Given the merge lands, when `apply-web-platform-infra` runs on push, then its plan is a no-op for resources and provisioners report success; verify with `bash scripts/betterstack-query.sh` — `integration` (post-merge verification, no SSH).

## Open Code-Review Overlap

None — the open `code-review` issue list contains none of the planned file paths.

## Context

- Issue: #9755 (`type/security`, `priority/p2-medium`, `domain/engineering`); refs #9597, #8767, #7797, #10664.
- The existing ruling carried into this plan: routable to ordinary pipeline up to draft PR; merge is production-effecting (`apps/web-platform/infra/**` fires the apply) and is **not** covered by the #10390 delegation — see Operator Holds.
- `SOLEUR_COLLISION` note: the only open change naming #9755 is this pipeline's own draft PR #11455.
- Spec lacks `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## References

- ADR-241 amendment log (esp. entries 2026-10-08 #8767, 2026-10-20/22/23 O10 + #10664 sites) — `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- Runbook: `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (O3 seeding; `op=backup` tier row) and `inngest-server.md` § Cutover procedure step 0.5
- Canonical consumer patterns: `apply-web-platform-infra.yml` `HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"  # loader-exported (#8209)`; `git-data-cutover.yml::wipe` loader call omitting `doppler-token-legacy`; `.github/actions/infra-credentials/action.yml`
- Guards touched: `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (membership/parity/`_EXACT_FLOOR`), `scripts/lint-hcloud-token-readonly-no-fallback.sh` (+ its battery `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh`), `tests/scripts/test-infra-privileged-tier-census.sh` (G1j)
