---
issue: 4118
plan: knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md
lane: cross-domain
---

# Tasks — feat-one-shot-inngest-cloud-init-iac-4118

Derived from the plan at `knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md`. Phases match the plan's `## Implementation Phases` 1:1.

## Phase 0 — AGENTS.core.md budget restoration (BLOCKING Phase 3)

- [ ] 0.1 Create `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md` (lift 571 B rule body's Why + How to apply).
- [ ] 0.2 Create `knowledge-base/project/learnings/best-practices/2026-05-20-hr-tagged-build-workflow-needs-initial-tag-push-why-and-how.md` (lift 532 B rule body's Why + How to apply; back-link existing 2026-05-18 sibling).
- [ ] 0.3 Trim `AGENTS.core.md` line 38 (`hr-observability-as-plan-quality-gate`) to ≤ 200 B; retain `[id: …]` + `[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]` + one-line `**Why:** #4116 — see <learning>.` pointer.
- [ ] 0.4 Trim `AGENTS.core.md` line 15 (`hr-tagged-build-workflow-needs-initial-tag-push`) to ≤ 200 B; retain `[id: …]` + one-line `**Why:** PR-A #3973 — see <learning>.` pointer.
- [ ] 0.5 File 2 trim trackers per `wg-when-an-audit-identifies-pre-existing`. Per deepen-pass: `scripts/agents-md-trim-trackers.txt` does NOT exist AND `chore/agents-md-trim` label does NOT exist. Resolve via one of: (a) 2 issues with existing labels `chore + domain/engineering + priority/p3-low`, OR (b) `gh label create chore/agents-md-trim` in same PR + 2 issues, OR (c) create `scripts/agents-md-trim-trackers.txt` with header + 2 entries.
- [ ] 0.6 Run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` — expect exit 0, `B_ALWAYS ≤ 21849`, WARN tier (same as `main`).
- [ ] 0.7 Capture B_ALWAYS before/after diff and paste it into the commit message.

## Phase 1 — Cloud-init runcmd block (Tier 1)

- [ ] 1.0 **DECISION POINT (per deepen-pass).** Choose delivery path:
  - **(A) Issue-body literal (OCI pull + extract).** Implement Phase 1 as written below. Net change: ~20 lines in cloud-init.yml.
  - **(B) Base64-embed via templatefile() (deepen-pass-recommended; codebase precedent x7).** Add `inngest_bootstrap_script_b64`, `inngest_cli_version`, `inngest_cli_sha256` to `server.tf` templatefile() vars; add a `write_files:` block for `/usr/local/bin/inngest-bootstrap.sh`; runcmd reduces to ~3 lines. Net change: ~5 lines in server.tf + ~10 lines in cloud-init.yml. **Stronger choice unless time-boxed to literal scope.**
- [ ] 1.1 Edit `apps/web-platform/infra/cloud-init.yml` per chosen path (1.0). Either insert the OCI-pull runcmd between plugin-seed (line ~398) and final `docker run` (line ~418), OR add the write_files + reduced runcmd.
- [ ] 1.2 (Path A only) Block uses `trap cleanup EXIT` for `EXTRACT_DIR` + `EXTRACT_CONTAINER` cleanup (matches existing soleur-plugin-seed pattern).
- [ ] 1.3 (Path A) Block pins `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`; sources `INNGEST_CLI_VERSION` + `INNGEST_CLI_SHA256` from `docker inspect Config.Env`. (Path B) Values sourced from `inngest.tf:locals.inngest_cli_version` + `inngest_cli_sha256` via `templatefile()`.
- [ ] 1.4 Add `# Pinned image tag tracks apps/web-platform/infra/inngest.tf:locals.inngest_cli_version` comment (drift-sentinel). Wording may shift slightly under Path B (single source of truth).

## Phase 2 — Cloud-init test coverage

- [ ] 2.1 Extend `apps/web-platform/infra/inngest.test.sh` (or add `cloud-init.test.sh` if absent) with assertions:
  - [ ] 2.1.a grep for `docker pull ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`.
  - [ ] 2.1.b grep for `docker inspect` + `Config.Env` (verifies INNGEST_CLI_VERSION sourcing).
  - [ ] 2.1.c grep for `trap cleanup EXIT`.
  - [ ] 2.1.d Positional assertion: new block line number < final `docker run -d --name soleur-web-platform` line number.
  - [ ] 2.1.e Extract embedded shell snippet → `bash -n` and `dash -n` both succeed.
- [ ] 2.2 Run `yamllint apps/web-platform/infra/cloud-init.yml` (fallback: `python3 -c "import yaml; yaml.safe_load(open(…))"`) — exit 0.

## Phase 3 — Tier 3 rule add (requires Phase 0 GREEN)

- [ ] 3.1 Create `knowledge-base/project/learnings/best-practices/2026-05-20-hr-fresh-host-provisioning-reachable-from-terraform-apply.md` documenting the #4017 cascade, the rule semantics, and the relationship to sibling rules.
- [ ] 3.2 Insert new rule in `AGENTS.core.md` `## Hard Rules` section after `hr-all-infrastructure-provisioning-servers` (line ~17). Rule body ≤ 600 B (per `cq-agents-md-why-single-line`); target ~576 B per operator brief. Includes `[id: hr-fresh-host-provisioning-reachable-from-terraform-apply]`, `[skill-enforced: plan Phase 2.8 + iac-plan-write-guard.sh]`, and `**Why:** #4017/#4118 — see <learning>.` pointer.
- [ ] 3.3 Add index pointer `- [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] → core` in `AGENTS.md` `## Hard Rules`.
- [ ] 3.4 Run `python3 scripts/lint-rule-ids.py` AND `python3 scripts/lint-agents-rule-budget.py` AND `python3 scripts/lint-agents-enforcement-tags.py` (if present) — all exit 0.

## Phase 4 — Runbook update

- [ ] 4.1 Append a `## Fresh-host provisioning (#4118)` section to `knowledge-base/engineering/operations/runbooks/inngest-server.md` documenting the cloud-init install path AND the discoverability-test `curl` command.
- [ ] 4.2 Document the upgrade path (deploy webhook + `vinngest-vX.Y.Z` tag) as unchanged.

## Phase 5 — Final lint + budget sanity

- [ ] 5.1 Re-run all three linters; expect exit 0 across the board.
- [ ] 5.2 Final `B_ALWAYS` ≤ 21849 (≤ baseline).
- [ ] 5.3 Run extended `inngest.test.sh`; expect all assertions GREEN.

## Phase 6 — PR open

- [ ] 6.1 Open PR with `Ref #4118` (NOT `Closes`); body includes `## Tier 2 (deferred)` linking #4126 and `## Prior attempts` linking ONLY #4127 (deepen-pass verified #4143 is unrelated `feat-one-shot-agents-budget-recovery-4142`).
- [ ] 6.2 PR body has explicit `## Post-merge operator step` callout (curl + `gh issue close`).
- [ ] 6.3 Apply labels: `domain/engineering`, `priority/p1-high`, `bug` (mirror #4118 labels).

## Definition of Done

All Phase 0–6 tasks GREEN, pre-merge ACs (AC0–AC9) ticked in PR description, PR merged. Post-merge `curl /api/inngest` → 200/401, then `gh issue close 4118`.
