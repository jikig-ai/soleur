---
feature: one-shot-zot-migration-completion
issue: "#6122"
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-23-chore-zot-migration-completion-records-plan.md
---

# Tasks: close out the GHCR-to-zot migration records outside #8651

Out of scope, and must not be touched:

- `apps/web-platform/infra/cloud-init.yml`, and every file in #8660's list
- `soleur-host-bootstrap.sh` and `cloud-init-inngest.yml`
- `scripts/`, including `zot-soak-6122.sh`
- closing #6500
- 5.3b, 5.4, 5.5, 5.6 and #6129

## Phase 1: Repo record edits

- [ ] 1.1 ADR-096: replace only the `## Status` block (from `## Status` up to, not including, `## Amendment 2026-07-30`) with the plan's Phase 1.1 text. Keep the header bullet `- **Status:** Adopting`.
- [ ] 1.2 `knowledge-base/project/specs/feat-registry-oidc-migration/tasks.md`:
  - [ ] 1.2.1 Mark 1.8 `[~]` and add the partial evidence note (serving evidence; AC11 not run with 4 admitted secrets; `paused = true` heartbeat).
  - [ ] 1.2.2 Tick 1.9 with its evidence note.
  - [ ] 1.2.3 Tick 2.4 with its evidence note.
  - [ ] 1.2.4 Replace the 5.3 line with 5.3a `[x]` (cites #8600 / #8636) and 5.3b `[ ]`.
  - [ ] 1.2.5 Leave 5.4, 5.5 and 5.6 unchanged.

## Phase 2: GitHub record edits

Follow the plan's write protocol for every write:

- re-read state first
- `gh pr view 8660` before 2.2, 2.3 and 2.6
- an idempotency marker in every scratch body
- python `str.replace` with `count == 1` for body edits
- a piped `jq -e` assert after each label or milestone edit

Tasks:

- [ ] 2.1 #7077: post the evidence comment, then `gh issue close 7077 --reason completed`.
- [ ] 2.2 #8036: post the 1d sequencing comment. The table cites `apps/web-platform/infra/scripts/host-image-coherence-preflight.sh` and says 1d needs an inngest-host replace.
- [ ] 2.3 #6410: post the supersession-condition comment. The issue stays OPEN.
- [ ] 2.4 #6073: post the answer comment, remove `priority/p0-critical` and `action-required`, assert with `jq -e`, then `gh issue close 6073 --reason completed`.
- [ ] 2.5 #6122: change `priority/p2-medium` to `priority/p1-high` and set milestone `Phase 4: Validate + Scale`. Assert with `jq -e`.
- [ ] 2.6 #6122: extract the section-4 block with awk and check its head, tail and fence count. Append the marker, then post.
- [ ] 2.7 #6630: make the two anchored body edits (the step-2 signal and the **Amended** paragraph), then post the scratch-file note.
- [ ] 2.8 #6427: replace the `## Scope` span with the narrowed block (keys `appboot`, `appserved`, `freshboot`, `gate`), then post the scratch-file note.

## Phase 3: Verification

- [ ] 3.1 Run the plan's Pre-merge AC1–AC7.
- [ ] 3.2 Run the pinned `markdownlint-cli` over the two edited files, and `bash scripts/check-adr-ordinals.sh`.
- [ ] 3.3 Just before `gh pr merge`, re-run AC4 (no closing keyword) on the final PR title and body.
