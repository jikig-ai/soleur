---
issue: 4692
branch: feat-inngest-dispatch-tag-invariant
lane: cross-domain
brand_survival_threshold: single-user incident
plan: ../../plans/2026-05-31-arch-inngest-bootstrap-tag-driven-dispatch-plan.md
---

# Tasks: inngest-bootstrap tag-driven `workflow_dispatch` invariant

## Phase 0 — Preconditions
- [x] 0.1 Confirm the seam is still on `main` (dispatch path has no tag-push step).
- [x] 0.2 Read `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh:178-209`; copy the consumer stripped-tag regex (`^v[0-9]+\.[0-9]+\.[0-9]+$`, ~line 187) verbatim for the parity check.
- [x] 0.3 Read `.github/scripts/test/test-tag-filter.sh` for the convention (PASS/FAIL counters, `LC_ALL=C`, `grep -F`, synthetic corpus).

## Phase 1 — Guard script (RED-supporting)
- [x] 1.1 Create `.github/scripts/inngest-bootstrap-tag-guard.sh` with `set -euo pipefail` + `export LC_ALL=C`.
- [x] 1.2 Implement `resolve-tag <event_name> <github_ref> <inputs_ref>`: discriminate on `event_name == workflow_dispatch` (not on ref emptiness); strip `refs/tags/` then `vinngest-`; reject via `^v[0-9]+\.[0-9]+\.[0-9]+$` (regex is the reject gate AND guarantees non-empty — redundant `[[ -n ]]` from the plan omitted as provably-dead); print tag.

## Phase 2 — Fixture test
- [x] 2.1 Create `.github/scripts/test/test-inngest-bootstrap-tag-guard.sh` (auto-discovered by `run-all.sh`).
- [x] 2.2 Group 1 (YAML-shape on the workflow): `contents: read` present + `write` absent; input is `ref` not `tag`; inline validate literal present; resolve step invokes the guard.
- [x] 2.3 Group 2 (`resolve-tag` behavior): the 7 scenarios in the plan — incl. push `vinngest-v1.1.11-rc1`→fail, push `refs/heads/main`→fail, dispatch-empty→fail, double-prefix→fail.
- [x] 2.4 Parity check: `resolve-tag` post-strip regex == consumer `cloud-init-inngest-bootstrap.test.sh:~187` regex (read both).
- [x] 2.5 Run `bash .github/scripts/test/test-inngest-bootstrap-tag-guard.sh` — RED before Phase 3 (workflow still old), GREEN after. (RED→GREEN confirmed: 14 pass / 0 fail.)

## Phase 3 — Workflow edit
- [x] 3.1 `workflow_dispatch.inputs`: `tag` → `ref` (desc: existing vinngest-vX.Y.Z tag to re-publish). (Security advisory was PostToolUse non-blocking; env-indirection + pre-checkout validate satisfy it.)
- [x] 3.2 Add pre-checkout "Validate dispatch ref" step (`if: workflow_dispatch`, env-indirected, inline `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$`).
- [x] 3.3 Checkout: `with: { ref: ${{ inputs.ref }} }` + refspec comment (no `fetch-tags`).
- [x] 3.4 Resolve step → call the guard's `resolve-tag` (env-indirected) → `GITHUB_OUTPUT`.
- [x] 3.5 Confirm `permissions: contents: read` + `packages: write` unchanged; no post-push assert step.

## Phase 4 — Verify (pre-merge ACs)
- [x] 4.1 `bash .github/scripts/test/run-all.sh` passes (AC1/AC2).
- [x] 4.2 `grep -nE 'contents:|packages:' …` shows `contents: read` (AC3).
- [x] 4.3 `actionlint .github/workflows/build-inngest-bootstrap-image.yml` clean; `bash -n` the scripts (AC6).
- [x] 4.4 Existing `cloud-init-inngest-bootstrap.test.sh` AC6 still passes (AC7 — 21/21).

## Phase 5 — Ship
- [ ] 5.1 File the NG3 deferred tracking issue (non-max-tag content-freshness; re-eval criterion in the plan).
- [ ] 5.2 PR body uses `Ref #4692` (NOT `Closes`); post-merge AC8/AC9 via `gh workflow run`, then `gh issue close 4692`.
