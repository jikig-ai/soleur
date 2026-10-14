---
title: "feat: org-targetable runtime flag provisioning + per-org scoping"
issue: 4581
branch: feat-flag-org-scoping
worktree: .worktrees/feat-flag-org-scoping
pr: 4582
date: 2026-05-29
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-29-flag-org-scoping-brainstorm.md
spec: knowledge-base/project/specs/feat-flag-org-scoping/spec.md
status: draft
plan_review: applied (DHH, Kieran, code-simplicity, spec-flow — 2026-05-29)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- IaC ack rationale: the only infra-adjacent step is `doppler secrets set OPERATOR_EMAIL -c cli_ops`.
     cli_ops is NOT Terraform-managed — no `doppler_secret` resource targets it (verified:
     grep -rn cli_ops apps/web-platform/infra/*.tf -> none; TF doppler_secret resources target
     prd/prd_terraform/dev/prd_kb_drift_walker only). Its existing secret FLAGSMITH_MANAGEMENT_API_KEY
     is CLI-managed. OPERATOR_EMAIL is an operator-identity (per-operator email), not app-runtime
     infra. CLI seed is the sanctioned, consistent path. See ## Infrastructure (IaC). -->

# feat: Org-Targetable Runtime Flag Provisioning + Per-Org Scoping (#4581)

## Overview

Fix five verified gaps that make it impossible to enable a legally-sensitive
org-targetable runtime flag (`byok-delegations`) for **one** org (jikigai
`70a70ab0`) via sanctioned tooling, blocking #4232. Two PRs, portability first:

- **PR-1 (portability):** remove the hard `psql` binary dependency for the WORM
  audit append (gap 5) + seed the audit actor (gap 4), across **all three**
  flag-audit scripts, via one **shared sourced helper**.
- **PR-2 (model change, ADR-043-gated):** per-feature-segment scoping (Option A,
  gaps 1 + 2 + 3), shipped **with its consumer** (byok@jikigai enable), with a
  state-migration dry-run and an **evaluation-level** single-org re-verify.

This plan incorporates 4-agent plan review (DHH/Kieran/code-simplicity/spec-flow).
Material corrections from review are marked `[review]`.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality (verified) | Plan response |
|---|---|---|
| "Both scripts" carry the psql audit | **Three**: `create.sh:84-88`, `flip.sh:237-242`, `set-role.sh:104-109` (`grep -rln psql plugins/soleur/skills/` = exactly these 3) | PR-1 converts **all three** |
| FR4: "seed `SUPABASE_URL` + service-role key in `cli_ops`" | `soleur/dev` already has both (+ `DATABASE_URL_POOLER`, the existing audit target) | RPC reads both from `-c dev`. **Only `OPERATOR_EMAIL` needs seeding** (absent in all 5 configs) |
| repo-research: migration 071 / `server.ts` "absent" | **Present** (verified by direct read + `git ls-tree`); subagent false-negative | Trust direct reads |
| `create.sh`+`flip.sh` both have a `server.ts` exit-1 precheck | Only `create.sh:42` does | `--flagsmith-only` is a `create.sh`-only change |
| `org-targeted` uses `orgId IN [...]` | Live shape: `ALL→ANY` rule of N `EQUAL orgId` conditions (`flip.sh:262,328-330`) | `<flag>-orgs` replicates that envelope, not `IN` |
| `[review]` FR6 cites `SETUP.md:64-75` as the orgId segment template | **False** — that is the `role` template (`property=role`; `grep -n orgId SETUP.md`=0). Real orgId shape: `flip.sh:328-330` | Phase 3 sources the rules body from `flip.sh:328-330` |
| `[review]` "verbatim block reused across 3 scripts" | `set-role.sh:34-35` reads its service-role key from `-c prd` (for the users PATCH); the audit reads `-c dev` | Shared helper takes **url+key as params**; each caller resolves its own (all pass `-c dev` for the audit) — distinct var names, no collision |

## User-Brand Impact

**If this lands broken, the user experiences:** a flag flip that either silently
fails to write the WORM audit row (lost accountability evidence) or **reports a
successful byok enable while the flag is actually OFF** (membership set but override
missing — spec-flow P0-3), or enables byok for an org that never opted in.

**If this leaks, the user's data/money is exposed via:** the shared `org-targeted`
segment's all-or-nothing blast radius (today {jikigai, `1a8045bf`}).

**Brand-survival threshold:** `single-user incident`. → `requires_cpo_signoff: true`
(brainstorm carry-forward; CPO assessed Phase 0.5). `user-impact-reviewer` runs at PR review.

## Implementation Phases

### Shared audit helper (PR-1, used by all three scripts)

New file `plugins/soleur/scripts/audit-flag-flip.sh` (precedent: skills source
`plugins/soleur/scripts/resolve-git-root.sh` via `$SCRIPT_DIR/../../../scripts/…`).
`[review: DHH]` one helper replaces 3 inline copies — fix-once for a security-critical
WORM transport; the precedent removes the cross-skill-sourcing fragility objection.

Signature: `audit_flag_flip_rpc <url> <srk> <flag> <env> <target> <action> <before_json> <after_json> <actor>`
where `<before_json>`/`<after_json>` are **literal JSON tokens** `true`|`false`|`null`.

```bash
audit_flag_flip_rpc() {
  local url="$1" srk="$2" flag="$3" env="$4" target="$5" action="$6" before="$7" after="$8" actor="$9"
  local body resp code id
  # [review P0-1/Kieran] --argjson (NOT --arg) for the bool/null args; --arg for text
  body=$(jq -nc --arg f "$flag" --arg e "$env" --arg t "$target" --arg a "$action" --arg ac "$actor" \
              --argjson b "$before" --argjson af "$after" \
    '{p_flag_name:$f,p_env:$e,p_target:$t,p_action:$a,p_before_bool:$b,p_after_bool:$af,p_actor:$ac}')
  resp=$(curl -sS -w '\n%{http_code}' -X POST \
    -H "apikey: $srk" -H "Authorization: Bearer $srk" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    "${url}/rest/v1/rpc/audit_flag_flip" -d "$body")
  code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
  [[ "$code" =~ ^2 ]] || { echo "FATAL: audit RPC failed (HTTP $code): $body" >&2; return 4; }
  id=$(jq -r 'if type=="array" then .[0] else . end' <<<"$body")  # RETURNS uuid => scalar; array branch dead-but-safe
  [[ -n "$id" && "$id" != "null" ]] || { echo "FATAL: audit RPC returned no id: $body" >&2; return 4; }
  echo "$id"
}
```

Caller contract: `audit_id=$(audit_flag_flip_rpc "$AUDIT_URL" "$AUDIT_SRK" …) || exit 4`
(helper `return 4`; caller `exit 4` — preserves the mandatory-abort semantic).

**`[review P1-4/Kieran]` 7-arg-per-call-site map** (the audit `url`/`key` are always
`-c dev`):

| call site | flag | env | target | action | before | after | actor |
|---|---|---|---|---|---|---|---|
| `create.sh` | `$NAME` | `'dev'` | `'global'` | `'create'` | `null` | `null` | `$ACTOR` |
| `flip.sh` role | `$FLAG` | `$ROLE` (prd/dev) | `role:$ROLE` | `$VALUE` | `$before_bool` | `$after_bool` | `$actor` |
| `flip.sh` org | `$FLAG` | `$ROLE` | `org:$TARGET_ORG` | `$VALUE` | `$before_bool` | `$after_bool` | `$actor` |
| `set-role.sh` | `'user-role'` | `'prd'` | `user:$USER_ID` | `$AUDIT_ACTION` | `null` | `null` | `$ACTOR` |

All `env`/`action` values satisfy migration-071 CHECKs. `set-role.sh` resolves a
**separate** `AUDIT_URL`/`AUDIT_SRK` from `-c dev` (distinct from its existing prd
`SUPA_URL`/`SUPA_KEY`) — no var collision.

### PR-1 — Portability (gaps 4 + 5)

**Phase 0 — Live preconditions (read-only; no WORM writes) `[review P1-5/DHH]`:**
1. **Reachability:** `GET $SUPABASE_URL/rest/v1/flag_flip_audit?limit=1` with the
   service_role key from `-c dev` → 2xx proves URL+key+table reachable. Side-effect-free.
2. **Grant integrity (out-of-band, read-only):** verify anon/authenticated lack EXECUTE
   on `audit_flag_flip` via Supabase MCP introspection of `information_schema.routine_privileges`
   (NOT a write-probe — a write-probe would pollute the WORM table if the grant is
   regressed, the exact thing being tested). If re-granted (default-privileges class,
   learning 2026-05-06), it is **pre-existing** → file an issue, do not expand scope.
   The first real audit append's mandatory `exit 4` (append-before-flip) is the live
   functional test of the RPC path — no synthetic preflight row needed.
3. Audit `OPERATOR_EMAIL` across all configs (`dev`,`prd`,`ci`,`cli_ops`,`prd_terraform`)
   — confirmed absent in all 5 (learning 2026-03-25).

**Phase 1 — Seed `OPERATOR_EMAIL` (FR4):**
- `printf '%s' "jean.deruelle@jikigai.com" | doppler secrets set OPERATOR_EMAIL -p soleur -c cli_ops --silent`
  (stdin form; `hr-never-paste-secrets-via-bang-prefix`; matches the scripts' `doppler_mirror`).
- Satisfies migration-071 `actor ~ '^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$'` after the
  function's `lower()` (P2-6: `lower()` is load-bearing — do not regress to raw insert).
- Read live by the CLI at invocation (not container-baked) → no redeploy.
- CLI-managed (not TF) — see `## Infrastructure (IaC)`.

**Phase 2 — psql → shared RPC helper (FR1/FR2), all three scripts:**
- Add `source "$SCRIPT_DIR/../../../scripts/audit-flag-flip.sh"` to each script
  (define `SCRIPT_DIR` if absent).
- Replace each psql audit block AND **its paired `DATABASE_URL_POOLER` fetch**
  `[review P1-5/Kieran]` (`create.sh:84-85`, `flip.sh:237-238`, `set-role.sh:104-105`)
  with: resolve `AUDIT_URL`/`AUDIT_SRK` from `-c dev`, then call the helper with the
  call-site's 7 args (table above). Preserve append-before-flip ordering.
- `set-role.sh` tautology (`:107` `… && echo "on" || echo "on"`): **out of scope for
  this PR** `[review/spec-flow P1-3]`. The `action` value is computed before the helper
  call (the transport swap does not require touching it), and promote-vs-demote has no
  defined truth table between role strings. Note as a pre-existing bug → fix only at
  /work if the role-direction semantics are unambiguous, else file a follow-up. Do not
  land another arbitrary constant.

**Phase 3 — Helper test:**
- `plugins/soleur/test/audit-flag-flip.test.sh` `[review P1-3/Kieran]` (flat dir; the
  repo's `*.test.sh` convention — NOT a per-skill `test/`): mock PostgREST → assert
  helper `return 4` on non-2xx, on empty body, on missing/`null` id; assert the JSON
  body uses JSON bool/null for before/after (not strings).
- **Forbidden-token guard** (in the same test or a lint): assert none of the three
  scripts' audit paths contain `psql`, `DATABASE_URL_POOLER`, or `6543`/`5432`
  `[review P1-5/Kieran]`. Assert each script `source`s the helper and calls it **before**
  its first Flagsmith/Supabase mutation `[review P2-2 — checkable ordering]`.

**PR-1 Acceptance Criteria:**

*Pre-merge (PR):*
- [ ] `grep -rlE 'psql|DATABASE_URL_POOLER' plugins/soleur/skills/{flag-create,flag-set-role,user-set-role}/scripts/` → zero in the audit path (helper test green).
- [ ] All three scripts source `plugins/soleur/scripts/audit-flag-flip.sh` and call it before any Flagsmith/Supabase mutation.
- [ ] Helper test: non-2xx / empty / missing-id → `return 4`; bool args serialized as JSON bool/null (not strings).
- [ ] Test suite green via the project's actual runner (verify `ls plugins/soleur/test/`).

*Post-merge (operator) — automatable:*
- [ ] `OPERATOR_EMAIL` seeded in `cli_ops`.
- [ ] One real `flip.sh <flag> dev off` on a psql-less path writes an audit row (verified via the discoverability `GET`) — proves the in-script helper call works (no escape hatch) `[review P2-3]`.

### PR-2 — Per-Feature-Segment Model (gaps 1 + 2 + 3), ADR-043-gated

**Phase 0 — ADR amendment (gate) `[review DHH+simplicity]`:**
- **Amend ADR-043 in place** → status `superseded-in-part`; add a "Per-feature segment
  scoping (2026-05-29)" section. (No new ADR-044.) Record: the `<flag>-orgs` model;
  O(features) vs O(orgs) rationale dismantling the explosion rejection; the
  **fallback-fidelity property** (per-org overrides invisible to the Doppler `FLAG_*`
  mirror → per-org-scoped flag falls back OFF on Flagsmith outage — verified safe for
  byok, prd mirror = 0). Use `/soleur:architecture`.

**Phase 1 — Live state capture (source-of-truth) `[review P1-1]`:**
- `GET /projects/39082/segments/` → record `org-targeted` id + `ALL→ANY/EQUAL orgId`
  membership. **Fail loud** if membership ≠ expected {`70a70ab0`,`1a8045bf`} (a 3rd org
  would change the cutover). The id `1130454` is spec-only — bind to the live value.
- `GET /features/feature-segments/?environment=<prd>&feature=<id>` for each
  org-targetable feature → record existing overrides on `org-targeted`.
- This snapshot is re-validated at cutover time (Phase 5), not trusted stale.

**Phase 2 — `create.sh --flagsmith-only` (FR5, gap 1):**
- New flag skips the `server.ts`/`.env.example`/Doppler mutations AND the `create.sh:42`
  exit-1 precheck; only creates the Flagsmith feature for an already-code-wired flag.

**Phase 3 — `provision_feature_segment <flag>` (FR6, gap 2) `[review P0-2/Kieran + P0-4/spec-flow]`:**
- Idempotently `POST /projects/39082/segments/` to create `<flag>-orgs` with the
  **orgId** envelope sourced from `flip.sh:328-330` (NOT SETUP.md, which is the role
  template): `rules:[{type:"ALL",rules:[{type:"ANY",rules:[],conditions:[{operator:"EQUAL",property:"orgId",value:<uuid>}…]}],conditions:[]}]`, initially zero conditions.
- Then ensure an **ON feature-state override** for `<flag>` on `<flag>-orgs` in **both
  envs** (reuse `flip_segment_in_env`, `flip.sh:185`). The helper must be a single
  idempotent unit: segment-exists + override-ON-both-envs.

**Phase 4 — Reshape `flip.sh --org` to the flag's own segment (gap 2/3) `[review P0-3/P0-4]`:**
- `--org` first calls `provision_feature_segment <flag>` (segment + both-env override),
  THEN add/removes the org's `EQUAL orgId` condition on `<flag>-orgs` (re-read the
  segment immediately before the PUT to shrink the read-modify-write window, P1-1).
- **Re-verify = flag EVALUATION, not segment membership (FR8, the load-bearing fix):**
  POST to the Flagsmith identities endpoint with a transient identity carrying
  `orgId=<target>` trait (per ADR-043 identity model) and assert `<flag>` resolves
  **enabled=true**; AND evaluate for a control orgId (`1a8045bf` for byok) and assert
  **enabled=false**. Membership-set-equality alone is insufficient — override-missing or
  one-env-only passes a membership check while the flag is OFF (spec-flow P0-3). Absolute
  invariant (exact target org, control org excluded), not circular against the script's
  own computed value (P2-5).
- Audit append (helper, from PR-1): `target=org:<uuid>`.
- Empty-membership case (last org removed → empty `ANY` rule matches nobody): document
  as "feature OFF for all via this segment"; add a test asserting eval=false for any org
  when `<flag>-orgs` is empty `[review P1-2]`.

**Phase 5 — State migration dry-run + cutover (FR9) `[review P0-5/P1-1]`:**
- `--dry-run` re-reads live state (Phase 1 snapshot is advisory only) and prints the
  planned per-feature moves; **fail loud** if live ≠ expected. Output must equal the
  enumerated (feature, override) source-of-truth `[review P2-4]`.
- Cutover is **idempotent + re-runnable**; each step re-reads live state immediately
  before mutating; explicit exit-code contract (a step-2 failure after step-1 commits is
  non-destructive — twi stays ON via both segments — and re-running completes it):
  1. Create `team-workspace-invite-orgs` {`70a70ab0`,`1a8045bf`}; add twi ON override;
     **eval-verify twi enabled for both orgs**.
  2. Remove twi's override from shared `org-targeted`; **eval-verify twi still enabled
     for both orgs** (served by its own segment now).
  3. Create `byok-delegations-orgs` {`70a70ab0`}; add byok ON override; **eval-verify
     byok enabled for jikigai, NOT enabled for `1a8045bf`**.
- **Scope-cut line** `[review/simplicity]`: steps 1-2 (twi migration) are NOT strictly
  required for the byok@jikigai unblock (step 3 alone suffices — byok gets its own
  segment, no leak). Keep for correctness (fully retire the shared segment); if PR-2 runs
  hot, steps 1-2 are the clean split to a follow-up.
- **Consumer/proof** (sibling #4456 lesson): success criterion IS the byok@jikigai enable
  verified by eval-read, not capability-only.

**Phase 6 — Tests + docs:**
- Tests: `--flagsmith-only` skips server.ts; `provision_feature_segment` idempotency
  (segment + override both envs); `--org` targets `<flag>-orgs`; eval-based re-verify
  (positive + control-negative); empty-membership eval=false.
- SKILL.md **body** updates (flag-create `--flagsmith-only`; flag-set-role per-feature
  `--org`). **`description:` frontmatter unchanged** → skill-description budget check N/A.

**PR-2 Acceptance Criteria:**

*Pre-merge (PR):*
- [ ] ADR-043 amended in place (`superseded-in-part` + per-feature-segment section).
- [ ] `create.sh --flagsmith-only byok-delegations` creates the feature without touching server.ts/.env.example/Doppler.
- [ ] `<flag>-orgs` created with `ALL→ANY/EQUAL orgId` envelope (sourced from flip.sh:328-330); feature has ON override on its own segment in BOTH envs.
- [ ] `flip.sh byok-delegations prd on --org 70a70ab0` → eval-verify asserts byok enabled for `70a70ab0` AND not-enabled for `1a8045bf`.
- [ ] `FLAG_BYOK_DELEGATIONS` Doppler **prd=0** (verified 2026-05-29) → "OFF on Flagsmith outage" holds; no prd-role mirror pinned it ON `[review P1-4]`.
- [ ] `--dry-run` output equals the live (feature, override) enumeration; fails loud on membership drift.
- [ ] Tests green.

*Post-merge (operator) — automatable via Flagsmith API in-script:*
- [ ] Cutover executed; eval-reads confirm twi enabled for both orgs, byok enabled for jikigai only.
- [ ] byok-delegations enabled for jikigai → **unblocks #4232** (`Ref #4232`; close after eval-verify).

## Files to Edit

- `plugins/soleur/skills/flag-create/scripts/create.sh` — PR-1: source helper, replace audit block + DB_URL fetch (**84-88**); actor (81-82). PR-2: `--flagsmith-only` + bypass `:42`; `provision_feature_segment`.
- `plugins/soleur/skills/flag-set-role/scripts/flip.sh` — PR-1: source helper, replace `audit_append()` body + DB_URL fetch (**235-242**). PR-2: reshape `--org` (253-340) to `<flag>-orgs` + full provision-first + eval-re-verify; `--dry-run` enumerator.
- `plugins/soleur/skills/user-set-role/scripts/set-role.sh` — PR-1: source helper, replace audit block + DB_URL fetch (**101-109**); add `AUDIT_URL`/`AUDIT_SRK` from `-c dev`.
- `plugins/soleur/skills/flag-create/SKILL.md`, `flag-set-role/SKILL.md` — PR-2 body only (no `description:` change).
- `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md` — PR-2: in-place amendment.

## Files to Create

- `plugins/soleur/scripts/audit-flag-flip.sh` — PR-1 shared helper.
- `plugins/soleur/test/audit-flag-flip.test.sh` — PR-1 helper + forbidden-token test.

## Open Code-Review Overlap

None (`gh issue list --label code-review --state open` bodies reference none of the three scripts).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (brainstorm carry-forward; triad).

### Engineering (CTO) — reviewed (carry-forward)
Gap-3 is an ADR-043 reversal → ADR amendment gates PR-2. RPC via service_role (not raw
insert / not Bun.sql). Two-PR, portability first. State-migration dry-run mandatory.
(CTO recommended Option B; operator chose Option A.)

### Product (CPO) — reviewed (carry-forward) — **CPO sign-off required (single-user incident)**
Per-(feature,org) needed now; cap at n-features, no targeting-matrix UI. Option A.
Extend `flag-set-role`, no new skill.

### Legal (CLO) — reviewed (carry-forward)
`exit 4` hard-block; RPC route; no owner-insert RLS on the audit table (RPC bypass —
migration 071 confirmed RLS-on with no policies; do not regress). Actor: Doppler
`OPERATOR_EMAIL` → hard fail; no silent `git config`. Prove single-org via re-verify.
GDPR Art. 33 72h only if a non-opted-in org actually accesses personal data → design for
detectability. Gate PR on `user-impact-reviewer`: yes.

### Product/UX Gate
**Tier:** none — operator-CLI/infra tooling, no user-facing UI.

## Infrastructure (IaC)

### Terraform changes
**None.** No server/service/DNS/cert/persistent process. Two infra-adjacent touches:
- **`OPERATOR_EMAIL` seed (`cli_ops`):** `cli_ops` is not TF-managed (no `doppler_secret`
  targets it; its sole secret is CLI-managed). `doppler secrets set -c cli_ops` is the
  sanctioned path — satisfies Phase-2.8 (operator-identity, not app-runtime infra). See
  `iac-routing-ack` header.
- **Flagsmith per-feature segments:** Flagsmith Admin API in-script, not IaC
  (`SETUP.md:111-126` argues against TF for segments).

### Apply path
N/A — operator-CLI tooling. PR-1 seed = one idempotent `doppler secrets set`. PR-2
segment provisioning idempotent (create-if-absent + override-if-absent).

### Distinctness / drift safeguards
Audit `SUPABASE_URL`/service-role read from `-c dev` (matches existing
`DATABASE_URL_POOLER -c dev` target); does not cross dev/prd
(`hr-dev-prd-distinct-supabase-projects`). `set-role.sh` keeps its prd key for the user
PATCH separate from the dev audit key.

## Observability

```yaml
liveness_signal:
  what: "N/A — on-demand operator CLI, not a daemon. Success = exit 0 + printed audit_id (persisted WORM row id)."
  cadence: on-invocation
  alert_target: operator terminal (exit code + stderr)
  configured_in: plugins/soleur/scripts/audit-flag-flip.sh + the three flag scripts
error_reporting:
  destination: stderr + non-zero exit (audit-RPC failure -> 4; Flagsmith API error -> 3; missing secret -> 2/4)
  fail_loud: true
failure_modes:
  - mode: audit RPC non-2xx / empty body / missing id
    detection: explicit HTTP-code + id-presence check in the shared helper
    alert_route: "return 4 -> caller exit 4 (flip aborted before any mutation)"
  - mode: per-org enable leaks to second org OR override missing (flag OFF despite membership)
    detection: eval-based re-verify (identity with orgId trait) — positive + control-negative
    alert_route: "verification failure -> exit 3 + stderr (FR8)"
  - mode: cutover partial failure (twi double-served)
    detection: post-step eval-verify; idempotent re-run
    alert_route: "non-destructive; re-run completes; exit-code contract documented"
logs:
  where: operator terminal + durable WORM row in public.flag_flip_audit (dev Supabase project)
  retention: 7 years (migration 071 retention_until)
discoverability_test:
  command: "curl -sS -H \"apikey: $SRK\" -H \"Authorization: Bearer $SRK\" \"$SUPABASE_URL/rest/v1/flag_flip_audit?flag_name=eq.byok-delegations&order=created_at.desc&limit=1\"  # SRK/SUPABASE_URL from doppler -c dev; no remote shell"
  expected_output: "JSON array with the most recent byok-delegations audit row (actor, action, target, created_at)"
```

## Risks & Mitigations

- **WORM trail for PROD flips lives in the DEV Supabase project** (existing; all 3 scripts
  read `-c dev`). Preserved, not introduced. → OQ-1.
- **PR-2 cutover blast radius:** dry-run + ordered cutover (new-override-before-remove) +
  per-step **eval** read-back + idempotent re-run (spec-flow P0-5).
- **Read-modify-write race on the segment `conditions` array** (`flip.sh:334` PUTs a full
  replacement built from an earlier read): re-read immediately before PUT; single-operator
  tooling (no concurrent operators expected); fail-loud on drift. Known limitation
  (spec-flow P1-1).
- **service_role RPC reachable by anon** (default-privileges re-grant class): Phase-0
  read-only introspection (not a write-probe); pre-existing if found → issue.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Per-org segment model (Option B, CTO) | Relocates ADR-043's explosion to the unbounded customer axis |
| `git config`/`gh api user` actor fallback | Spoofable / may fail the email CHECK; weakens 7-yr WORM actor integrity. Seed Doppler instead |
| `Bun.sql` for the audit | Bypasses the service_role grant model; adds a Bun dep |
| Raw PostgREST table insert | Bypasses the SECURITY DEFINER actor enforcement + WORM intent |
| 3 inline audit copies + drift-guard test | DHH: the canonical block IS a function; shared-sourcing precedent exists (`resolve-git-root.sh`). Shared helper = fix-once |
| New ADR-044 | DHH+simplicity: partial supersession of one section → amend ADR-043 in place |
| Phase-0 WORM preflight write + anon write-probe | Pollutes the WORM table (esp. if the grant is regressed). Read-only reachability + introspection instead |
| One combined PR | DHH leaned here; operator chose two-PR (portability is a real standalone capability + de-risks PR-2). Noted |
| Migrate twi in this PR vs follow-up | Kept for correctness (retire shared segment); flagged as the clean scope-cut if PR-2 runs hot |

## Open Questions

- **OQ-1 (decided → follow-up):** PROD flag-flip WORM audits live in the DEV Supabase
  project. Pre-existing; out of scope. File a follow-up to evaluate moving to prd.

## GDPR / Compliance Gate

Carry-forward from brainstorm CLO (Art. 6(1)(f); LIA at
`knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md`).
**No new regulated-data surface:** no schema/migration change (the table is unchanged),
no new auth flow/API route — PR-1 is transport-only, PR-2 is Flagsmith API + ADR doc.
Only personal data is the `actor` email (processing unchanged). `user-impact-reviewer` at
PR review is the load-bearing gate.

## Sharp Edges

- Verify the live Flagsmith segment shape (`ALL→ANY/EQUAL orgId`, not `IN`) and the live
  `org-targeted` id before PR-2 mutates — `1130454` is spec-only.
- The `<flag>-orgs` rules body comes from `flip.sh:328-330`, **not** `SETUP.md` (that is
  the `role` template).
- Re-verify must read flag **evaluation** (identity+orgId trait), not segment membership —
  membership-correct-but-override-missing is the silent-leak failure mode.
- jq `--argjson` (not `--arg`) for the bool/null audit args.
- Remove the paired `DATABASE_URL_POOLER` fetch when removing each `psql` call.
