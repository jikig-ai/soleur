# Decision Challenges — feat-one-shot-6197

## Challenge 1 — #6197 is already implemented; reconcile the tracker, do not build

- **Class:** user-challenge (ADR-084) — surfaced headless during `/plan` Phase 0.6 premise validation.
- **Operator's implied direction:** run the one-shot pipeline against #6197 to build the arm64 Vector
  journal→Sentry shipper on the dedicated Inngest host.
- **Challenge:** the entire implementation is **already merged to `main`** by PR #6209 (commit
  `c890464ce`) and reconciled in ADR-100 ("Phase-1 caveat — RESOLVED (#6197)", ADR-100:399). The
  x86_64 hardcode is gone (arch-parameterized off `VECTOR_CLI_ARCH`), the arm64 Vector SHA is pinned
  (`vector.tf:22`), and `BETTERSTACK_LOGS_TOKEN` is provisioned into the isolated `soleur-inngest/prd`
  project (`inngest-betterstack-token.tf`). CI (`inngest-host.test.sh`) asserts all of it. The
  "Sentry" in the title is also stale — Vector ships to Better Stack Logs (pivot #4273/#5526).
- **Why #6197 is still OPEN:** PR #6209 used `Ref #6197` (not `Closes`) because #6197 doubles as the
  `deferred-automation` tracker for the ADR-100 **Phase-2 cutover** (re-provision `cax11`/`10.0.1.40`
  so the latent resources activate) — blocked on **#6178** (OPEN) + an operator maintenance window.
- **Recommendation:** HALT before `/work` re-implements. Reconcile #6197's body to
  "implementation merged in PR #6209; open only as the Phase-2 cutover tracker (blocked on #6178)".
  Keep it OPEN with `deferred-automation`; do NOT `Closes #6197`. No product-code PR is warranted.
- **Evidence:** `gh pr view 6209 --json state` → MERGED; `git log origin/main -- inngest-betterstack-token.tf`
  → c890464ce; ADR-100:399-403; `inngest-bootstrap.sh:733-748`; `vector.tf:22`; `variables.tf:359`.
