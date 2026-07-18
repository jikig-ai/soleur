# Tasks — feat-one-shot-6197 (reconciliation, NOT a build)

Plan: `knowledge-base/project/plans/2026-07-18-chore-reconcile-6197-arm64-vector-shipper-already-merged-plan.md`

> **Premise is STALE.** #6197's implementation is already merged (PR #6209) and reconciled in
> ADR-100. There is **no product-code deliverable.** Do NOT re-implement the arm64 Vector shipper.

## Phase 1 — Verify the premise is stale (read-only)
- [ ] 1.1 `gh pr view 6209 --json state` == MERGED; `gh issue view 6197 --json state` == OPEN.
- [ ] 1.2 `git grep -F 'aarch64-unknown-linux-musl' apps/web-platform/infra/inngest-bootstrap.sh` (present).
- [ ] 1.3 `git grep -E 'vector_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' apps/web-platform/infra/vector.tf` (present).
- [ ] 1.4 `test -f apps/web-platform/infra/inngest-betterstack-token.tf` + `git grep 'variable "betterstack_logs_token"' apps/web-platform/infra/variables.tf` (present).
- [ ] 1.5 `git grep -F 'vector-x86_64-unknown-linux-musl' apps/web-platform/infra/inngest-bootstrap.sh` returns non-zero (NOT hardcoded).
- [ ] 1.6 `bash apps/web-platform/infra/inngest-host.test.sh` green on `main`.

## Phase 2 — Reconcile the tracker (the only action)
- [ ] 2.1 Reconcile issue #6197 body → "implementation merged in PR #6209; open only as ADR-100 Phase-2 cutover tracker; blocked on #6178 + maintenance window."
- [ ] 2.2 Keep #6197 OPEN with `deferred-automation`; introduce no `Closes #6197`.
- [ ] 2.3 Ensure `decision-challenges.md` is carried into the PR body by `ship` (action-required issue).

## Explicitly out of scope
- [ ] NO edits to inngest-bootstrap.sh / vector.tf / vector.toml / inngest-host.tf / inngest-betterstack-token.tf / variables.tf / cloud-init-inngest.yml / ADR-100 (all already correct).
- [ ] NO `terraform apply` / host re-provision (operator-gated Phase-2 cutover, blocked on #6178).
