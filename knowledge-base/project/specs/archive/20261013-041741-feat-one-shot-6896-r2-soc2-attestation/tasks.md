# Tasks — chore(encryption-posture): R2 SOC 2 Type II attestation formalization (#6896)

Plan: `knowledge-base/project/plans/2026-07-24-chore-r2-provider-soc2-attestation-formalization-plan.md`
Lane: cross-domain. Branch: feat-one-shot-6896-r2-soc2-attestation.

## Phase 0 — Preconditions + new tracking issue
- [ ] 0.1 Confirm Layer A green baseline: `python3 scripts/lint-encryption-posture.py --repo-sweep` → `0 failing checks -> PASS`.
- [ ] 0.2 `grep -n "tracked #6896" scripts/encryption-posture-ledger.json` → expect 7 hits (3 R2 + 4 non-R2).
- [ ] 0.3 Create the non-R2 tracking issue via `gh issue create` (labels: priority/p3-low, domain/engineering, type/security; milestone "Phase 4: Validate + Scale"; body per plan Phase 0). **Capture the number as `NEW`.**

## Phase 1 — Verify the Cloudflare SOC 2 attestation
- [ ] 1.1 WebFetch `https://www.cloudflare.com/trust-hub/compliance-resources/soc-2/` → confirm AICPA SOC 2 Type II named + URL live (200).
- [ ] 1.2 Confirm R2 is in Cloudflare's SOC 2 scope. In-scope → keep mechanism `provider-managed:Cloudflare-R2-SOC2-Type-II`; else `provider-managed:Cloudflare-SOC2-Type-II` + word evidence to not overclaim R2 SOC 2 scope.
- [ ] 1.3 Pin `retrieved_on` to the verification date (2026-07-24 if same-day).

## Phase 2 — Formalize the 3 R2 rows
- [ ] 2.1 Edit `scripts/encryption-posture-ledger.json` `cloudflare_r2_bucket.cla_evidence` `at_rest` per Target row shape.
- [ ] 2.2 Same for `cloudflare_r2_bucket.workspaces_luks_header` (append LUKS-header-escrow evidence clause).
- [ ] 2.3 Same for `r2.terraform_state_backend` (append state-backend evidence clause).
- [ ] 2.4 For each: set mechanism, evidence, attestation_url, retrieved_on, live_verification (`unavailable:` reworded, no `available`, no `tracked #`). Leave defends_against / does_not_defend / disclosed_as / kind / device_binding untouched. Verify no boilerplate substring.

## Phase 3 — Re-point the 4 non-R2 rows
- [ ] 3.1 In the ledger, change `live_verification` on `supabase.prd`, `supabase.inngest`, `doppler.secrets`, `betterstack.logs` from `tracked #6896` to `unavailable:named SOC 2 attestation formalization pending; tracked #<NEW>`.

## Phase 4 — Correct the audit-doc mis-grouping
- [ ] 4.1 `encryption-posture-audit-2026-07-23.md` lines 40–42 (R2): Source → "Cloudflare Trust Hub SOC 2 Type II"; Finding → #6896 resolved.
- [ ] 4.2 Lines 43–45 (non-R2): `#6896` → `#<NEW>`.
- [ ] 4.3 Line 74: split into "#6896 (R2 … — SOC 2 Type II named) / #<NEW> (non-R2 provider attestations, P3)".

## Phase 5 — Verify + close
- [ ] 5.1 `python3 scripts/lint-encryption-posture.py --repo-sweep` → PASS (0 failing).
- [ ] 5.2 `python3 scripts/lint-encryption-posture.py --json > /dev/null` → exit 0.
- [ ] 5.3 `bash scripts/lint-encryption-posture.test.sh` → all pass.
- [ ] 5.4 `grep -c "tracked #6896" scripts/encryption-posture-ledger.json` → `0`; `grep -c "tracked #<NEW>" …` → `4`.
- [ ] 5.5 Run AC1–AC11 (plan Acceptance Criteria). PR body: `Closes #6896`, `Ref #6893`, `Ref #6588`, reference `#<NEW>`.

## Notes
- No post-merge operator step (all `gh`/file edits; `Closes #6896` auto-closes at merge).
- Decision-challenges recorded in `decision-challenges.md` (B2 scope + live_verification), rendered into PR body by `/soleur:ship`.
