# Tasks — feat-one-shot-6608-6197-inngest-host-prewiring

Plan: `knowledge-base/project/plans/2026-07-18-fix-inngest-host-nftables-allowlist-parity-plan.md`
Lane: single-domain · Threshold: none · Issues: #6608 (code), #6197 (reconcile-only, no code)

## Phase 0 — Preconditions (read-only)
- [ ] 0.1 Confirm `inngest-host.tf:40` literal is still `"10.0.1.10,10.0.1.11"`; `var.web_hosts`
      default is web-1-only (`10.0.1.10`).
- [ ] 0.2 Confirm `inngest-host.test.sh` line ~91 hardcodes the stale value
      (`grep -Fc '10\.0\.1\.11' …/inngest-host.test.sh` == 1) — the co-edit target.
- [ ] 0.3 (Optional, informs sequencing) Read-only: is `hcloud_server.inngest` provisioned, and has
      `10.0.1.11` been reallocated? (drift-detector / Hetzner API — no ssh, no write.)
- [ ] 0.4 Confirm #6197 is already delivered (Research Reconciliation table): `vinngest-v1.1.23`
      tag carries arm64 Vector + `BETTERSTACK_LOGS_TOKEN` (already verified). Do NOT touch Vector.

## Phase 1 — Fix the literal (RED→GREEN)
- [ ] 1.1 RED: edit `inngest-host.test.sh` — replace the hardcoded `.10,.11` grep (line ~91) with:
      (a) a single-host assertion (no `.11`), and (b) the parity guard mirroring
      `cutover-inngest-workflow.test.sh:184-199` — derive the literal's IP set from `inngest-host.tf`
      and the canonical set from `variables.tf` `web_hosts` `private_ip`, `assert` sorted-equal.
      Keep the `.20`/`.30` exclusion assertion (lines ~95-96).
- [ ] 1.2 Run `bash apps/web-platform/infra/inngest-host.test.sh` → confirm it FAILS against the
      current stale literal (guard bites).
- [ ] 1.3 GREEN: change `inngest-host.tf:40` → `web_host_private_ips = "10.0.1.10"`; update the
      SEC-H2 comment (single-host roster, #6538 retirement, #6608, now drift-guarded).
- [ ] 1.4 Re-run `bash apps/web-platform/infra/inngest-host.test.sh` → all pass.

## Phase 2 — Validate + docs
- [ ] 2.1 `terraform -chdir=apps/web-platform/infra fmt -check` + `terraform validate` clean.
- [ ] 2.2 Add the #6608 remediation note to `knowledge-base/engineering/operations/runbooks/inngest-server.md`
      (apply path + no-SSH nftables verification via Vector→Better Stack; not a ship-time checklist).
- [ ] 2.3 No-regression: `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh` and
      `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` still pass.
- [ ] 2.4 Non-vacuity note for PR body: temporarily re-add `,10.0.1.11`, confirm the parity
      assertion FAILs, revert.

## Phase 3 — Ship (merge inert; delivery deferred to Phase-2 cutover)
- [ ] 3.1 PR body: `Ref #6608` (ops-remediation — apply is post-merge at Phase-2), document the
      `inngest-host-replace` / Phase-2 re-provision apply path (NOT a routine apply), and the #6197
      reconciliation (delivered by #6209/#6631/#6651; no code here; #6197 stays OPEN as Phase-2
      tracker).
- [ ] 3.2 Confirm merge is inert: `inngest-host.tf` resources excluded from per-PR CI `-target`.
- [ ] 3.3 (HELD, epic #6178) At Phase-2 re-provision: verify rendered nftables has no `.11` and
      web-1 still reaches `:8288` (no-SSH), then `gh issue close 6608`.

## Notes
- Decision challenges (headless): `knowledge-base/project/specs/feat-one-shot-6608-6197-inngest-host-prewiring/decision-challenges.md`.
- No new test file; parity guard folds into the already-registered `inngest-host.test.sh`
  (`infra-validation.yml:535`). Do NOT add a `scripts/test-all.sh` entry.
- No new ADR / no C4 change (drift-fix; ADR-100 already amended by #6209).
