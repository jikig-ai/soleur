---
feature: flag-org-scoping
issue: 4581
branch: feat-flag-org-scoping
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-29-feat-flag-org-scoping-plan.md
status: ready
---

# Tasks: Org-Targetable Runtime Flag Provisioning + Per-Org Scoping (#4581)

Two PRs, portability first. Shared audit helper underpins PR-1.

## PR-1 — Portability (gaps 4 + 5)

### 1. Preconditions (read-only)
- [ ] 1.1 `GET /rest/v1/flag_flip_audit?limit=1` (service_role from `-c dev`) → 2xx reachability.
- [ ] 1.2 Verify anon/authenticated lack EXECUTE on `audit_flag_flip` via Supabase MCP `routine_privileges` (read-only; no write-probe). Pre-existing → issue if regressed.
- [ ] 1.3 Confirm `OPERATOR_EMAIL` absent in all configs (done: absent in dev/prd/ci/cli_ops/prd_terraform).

### 2. Shared helper
- [ ] 2.1 Create `plugins/soleur/scripts/audit-flag-flip.sh` — `audit_flag_flip_rpc <url> <srk> <flag> <env> <target> <action> <before_json> <after_json> <actor>`; `--argjson` for bool/null; HTTP-code + id-presence check → `return 4`.
- [ ] 2.2 Helper test `plugins/soleur/test/audit-flag-flip.test.sh` — non-2xx/empty/missing-id → 4; bool args JSON-typed; forbidden-token guard (`psql`/`DATABASE_URL_POOLER`/`5432`/`6543` absent from the 3 scripts' audit paths) + helper-call-before-mutation ordering.

### 3. Convert the three scripts (source helper + 7-arg map)
- [ ] 3.1 `create.sh:84-88` — source helper; replace audit block + DB_URL fetch; args (`$NAME`,`dev`,`global`,`create`,null,null,`$ACTOR`); resolve dev URL+key.
- [ ] 3.2 `flip.sh:235-242` — replace `audit_append()` body + DB_URL fetch; role args + org args per map; resolve dev URL+key.
- [ ] 3.3 `set-role.sh:101-109` — source helper; replace audit block + DB_URL fetch; add `AUDIT_URL`/`AUDIT_SRK` from `-c dev` (distinct from prd `SUPA_URL`/`SUPA_KEY`); args (`user-role`,`prd`,`user:$USER_ID`,`$AUDIT_ACTION`,null,null,`$ACTOR`).
- [ ] 3.4 `set-role.sh:107` tautology — out of scope; fix only if promote/demote semantics unambiguous at /work, else file follow-up.

### 4. Seed + verify (post-merge automatable)
- [ ] 4.1 Seed `OPERATOR_EMAIL` in `cli_ops` (stdin form).
- [ ] 4.2 Real psql-less `flip.sh <flag> dev off` writes an audit row (verify via discoverability `GET`).

### 5. PR-1 close
- [ ] 5.1 ACs green; PR body `Ref` (not `Closes`) #4581; gate on `user-impact-reviewer`.

## PR-2 — Per-Feature-Segment Model (gaps 1 + 2 + 3)

### 6. ADR gate
- [ ] 6.1 Amend ADR-043 in place → `superseded-in-part` + per-feature-segment section (model, O(features) rationale, fallback-fidelity). `/soleur:architecture`.

### 7. Live state capture
- [ ] 7.1 `GET segments/` → bind live `org-targeted` id + membership; fail loud if ≠ {`70a70ab0`,`1a8045bf`}.
- [ ] 7.2 `GET feature-segments/` → record existing overrides per org-targetable feature.

### 8. Provisioning
- [ ] 8.1 `create.sh --flagsmith-only` — skip server.ts/.env.example/Doppler + `:42` precheck; create Flagsmith feature only.
- [ ] 8.2 `provision_feature_segment <flag>` — idempotent create `<flag>-orgs` with `ALL→ANY/EQUAL orgId` envelope (from `flip.sh:328-330`, NOT SETUP.md) + ON override both envs.

### 9. `--org` reshape + eval re-verify
- [ ] 9.1 `flip.sh --org` targets `<flag>-orgs`: provision-first, then edit membership (re-read before PUT).
- [ ] 9.2 Eval-based re-verify (FR8): identity + `orgId` trait → assert `<flag>` enabled for target AND not-enabled for control org. (NOT segment-membership.)
- [ ] 9.3 Empty-membership case → eval=false for all; test.

### 10. Migration dry-run + cutover
- [ ] 10.1 `--dry-run` re-reads live state, prints (feature,override) moves, fails loud on drift.
- [ ] 10.2 Cutover (idempotent, re-runnable, eval-verify each step): (a) twi→own segment, verify both orgs; (b) remove twi from shared, verify both orgs; (c) byok→own segment {jikigai}, verify byok ON jikigai / OFF `1a8045bf`. [steps a-b = scope-cut line if hot]
- [ ] 10.3 Assert `FLAG_BYOK_DELEGATIONS` prd=0 (OFF-on-outage safety).

### 11. Tests + docs
- [ ] 11.1 Tests: `--flagsmith-only`, provision idempotency, `--org` per-feature, eval re-verify (pos+neg), empty-membership.
- [ ] 11.2 SKILL.md body updates (no `description:` change).

### 12. PR-2 close + unblock
- [ ] 12.1 byok enabled for jikigai (eval-verified); `Ref #4232`, close #4232 after verify; `Closes #4581`.
- [ ] 12.2 Gate on `user-impact-reviewer`; CPO sign-off recorded.
