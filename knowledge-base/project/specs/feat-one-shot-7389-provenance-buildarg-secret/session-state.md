# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-10-fix-sentry-token-in-build-provenance-plan.md`
- Status: complete

### Errors
None outstanding. Three recorded during planning:

- A `Write` was blocked by the IaC-routing hook on `doppler secrets set`. Resolved rather than
  bypassed: `doppler_secret` resources are reserved for Terraform-*generated* values, and routing an
  externally-minted token through Terraform would newly persist a live bearer token in
  `terraform.tfstate`. Ack added with that justification.
- A bad edit added an unconditional `[ -s ]` test that would have broken every local build, and
  mangled the `RUN` block's assignment. Caught on re-read and rewritten.
- Two stale `src=/dev/null` prescriptions survived that correction and contradicted the new
  guidance. Caught by a follow-up grep; fixed in both plan and tasks.

### Decisions
- **The allowlist as first designed re-opened the class.** Verified by execution: `BUILD_DEPLOY_TOKEN`
  and `NEXT_PUBLIC_SECRET_KEY` are *admitted* by a prefix-only allowlist. Now a conjunction —
  allowlisted AND not credential-shaped.
- **R0 is settled, and inverts the issue's reasoning.** A local A/B canary proves `mode=min` genuinely
  excludes build-args (0 occurrences vs 1 at `max`). So the published attestation carrying
  `request.args` means the release is **not** emitting min — a new open question (Phase 0.1b), not a
  docs bug. The fix is unchanged: a mode setting is configuration that drifts, not a control.
- **Containment decoupled from the PR** — minting under a new secret name kills the leaked token
  pre-merge, dissolving a proposed PR split while preserving the single-PR deliverable.
- **Identity split over scope narrowing** — one token cannot serve both Terraform write and release read.
- **Gate keys on secret-value absence** with value-layer positive controls; a key-shaped control would
  decay into fail-*always*.

### Findings carried into /work
- CPO returned `CHANGES REQUESTED` (B1–B7), all addressed. Brand-survival threshold is **PROVISIONAL**
  with five flip conditions — it rests on a *pending* Art. 4(12) determination.
- The `.att` deletion premise was wrong — that is a cosign convention; buildx attestations live inside
  the image index, so AC24 prescribes rebuild-and-repush. GitHub App tokens do not authenticate to GHCR.
- The prescribed canary would have failed on a stock machine (the `docker` driver rejects both
  attestations and OCI export) and passed unconditionally at `mode=min`.
- `required=true` proves presence, never non-emptiness — combined with `silent: !process.env.CI`, a
  blank token would have skipped source-map upload silently. An explicit `[ -s ]` test is the control.
- Token scope is **wider** than the issue supposed, not narrower (`project:admin` + `alerts:*`); the
  cited 403 was a `team:read` 403, making that workflow comment itself false.
- Verify-the-negative sweep: 16 repo claims, 16 confirm, 0 contradict.

### Components Invoked
`soleur:plan` · `soleur:plan-review` · `soleur:deepen-plan` · `soleur:gdpr-gate` ·
repo-research-analyst · learnings-researcher · framework-docs-researcher · Explore ×2 ·
dhh-rails-reviewer · kieran-rails-reviewer · code-simplicity-reviewer · architecture-strategist ·
spec-flow-analyzer · engineering:cto · product:cpo · scoped strong-model advisor (fable) ·
verify-the-negative sweep · API-realism pass

### Scope verification (one-shot post-plan gate)
`git diff origin/main...HEAD --name-only` and `git diff <base-sha>..HEAD --name-only` both return
exactly the three planning artifacts. No product code, workflow YAML, or CHANGELOG touched — the
subagent stayed inside its plan-only mandate.
