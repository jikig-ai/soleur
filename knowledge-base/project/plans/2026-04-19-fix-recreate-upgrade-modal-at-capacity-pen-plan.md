# Recreate `upgrade-modal-at-capacity.pen` under canonical `product/design/billing/`

**Issue:** #2636 (was CLOSED — auto-closed prematurely by PR #2630; reopened in Phase 1 of this plan)
**Branch:** `feat-one-shot-recreate-upgrade-modal-pen`
**Parent ref:** #1162 (plan-based agent concurrency enforcement)
**PR #2630 merge commit:** `2dac1c05ce4f8dac05002e1fdada052e67bf01ce` (merged 2026-04-19T10:56:11Z, resolved via `gh api repos/:owner/:repo/pulls/2630`)
**Type:** fix
**Detail level:** MINIMAL — this is a single-file design artifact recreation on a green path

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** Phase 1 preflight (adapter drift mechanics + learning-file grounding), Risks (fabrication-narrative class), Research Insights (authoritative file paths and checks), Acceptance Criteria (preflight evidence specificity).

### Key Improvements

1. Phase 1 preflight now names the **exact repo-relative scripts** (`plugins/soleur/skills/pencil-setup/scripts/{check_deps.sh,copy_adapter.sh}`) and cites the `ADAPTER_FILES` array that `copy_adapter.sh` syncs — so a partial copy (e.g., only `pencil-mcp-adapter.mjs` without its sibling pure modules) is detected, not just the top-level sha.
2. Added an explicit **fabrication-narrative guard** to the Risks table — the exact failure pattern documented in `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md` ("Pencil MCP headless stub — dropped all ops silently"). The ux-design-lead invocation prompt in Phase 2 already includes the "do NOT fabricate" instruction; this plan documents the exact string to watch for.
3. Research Insights resolves every external reference live (PR #2630 merge sha via `gh api`, learning-file path verified to exist, canonical-path enforcement line numbers in `ux-design-lead.md` verified by grep).

### New Considerations Discovered

- `copy_adapter.sh` syncs **5 files** (adapter + 4 pure modules per the `ADAPTER_FILES=(…)` array in the script itself); a naive sha check on only `pencil-mcp-adapter.mjs` would miss drift in the sibling modules. The `--check-adapter-drift` subcommand already checks all 5 — use it, do not invent a one-file check.
- Issue #2636's auto-close via PR #2630 body (`Closes #2636 on separate branch cleanup`) is a second-hand example of AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` — GitHub ignores the qualifier. No workflow-gate change is prescribed here (the gate already exists); this plan just produces the correct artifact that PR #2630 expected.

## Overview

Issue #2636 was created to track recreation of the `upgrade-modal-at-capacity.pen` design after PR #2630 fixed the Pencil MCP adapter regression that caused 0-byte `.pen` placeholders. The issue got auto-closed by PR #2630's `Closes #2636 on separate branch cleanup` line in the PR body, but **the actual recreation work was never performed** — the canonical-path `.pen` file still does not exist.

Current state (verified 2026-04-19):

- Deprecated path `knowledge-base/design/upgrade-modal-at-capacity.pen` — GONE (the entire `knowledge-base/design/` top-level directory was removed in #566).
- Canonical path `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen` — exists as a 0-byte placeholder scaffolded in `b4590aa5` (per `cq-before-calling-mcp-pencil-open-document`); Phase 2 must overwrite it with the real wireframe, not create from scratch.
- Issue #2636 — was `CLOSED` at plan-write time; reopened in Phase 1 step 4 before Phase 2 runs.

This plan reopens #2636, recreates the `.pen` file at the canonical path using `ux-design-lead`, verifies the post-save size gate enforced in `plugins/soleur/agents/product/design/ux-design-lead.md:55`, and closes the issue properly.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "Deprecated-path placeholder is already gone" (task input) | Verified — `ls knowledge-base/design/` returns ENOENT. | No deletion task needed; skip to recreation. |
| "Pick correct domain — likely billing or plan-concurrency related per Ref #1162" (task input) | `knowledge-base/product/design/billing/` already holds `subscription-management.pen`. `pricing/` holds `pricing-page-v2-wireframes.pen`. No `plan-concurrency/` domain exists. The upgrade modal is triggered by hitting a plan's agent-slot cap and presents an upgrade CTA — that is a **billing flow event**, not pricing-page content. | Use `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen`. |
| "Use ux-design-lead to create .pen — post-save gate verifies size > 0" (task input) | Verified in `plugins/soleur/agents/product/design/ux-design-lead.md:55` — the HARD GATE is in place. | Rely on agent's own gate; add a belt-and-suspenders `stat -c %s` check from the caller side. |
| Adapter drift (implicit precondition from PR #2630) | `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --check-adapter-drift` returns `DRIFT: installed 31b572c46a28 != repo 1b293c456353` on this worktree right now. **Running `ux-design-lead` without refreshing the installed adapter will reproduce the exact 0-byte regression #2630 fixed.** | Add a mandatory preflight step to refresh the installed adapter before invoking `ux-design-lead`. |
| Pencil MCP requires `PENCIL_CLI_KEY` (adapter hard-fails without it per PR #2630) | `claude mcp list` shows `pencil` as `✓ Connected` on this host — env is already configured. | Preflight verifies env; no credential setup step needed unless preflight fails. |

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "upgrade-modal-at-capacity" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
jq -r --arg path "knowledge-base/product/design/billing" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
```

None. No open code-review issues reference `upgrade-modal-at-capacity` or the billing design directory.

## Domain Review

**Domains relevant:** Product (blocking — creates a new design artifact for a user-facing modal)

### Product/UX Gate

**Tier:** blocking
**Decision:** auto-accepted (pipeline) — the recreation IS the UX artifact. `ux-design-lead` is the agent invoked in Phase 2; it both runs the design work and self-enforces the post-save gate.
**Agents invoked:** ux-design-lead (Phase 2)
**Skipped specialists:** spec-flow-analyzer, cpo, copywriter — the modal's flow, product framing, and copy are already fixed by the brainstorm/spec for #1162 (`knowledge-base/project/brainstorms/2026-04-19-plan-concurrency-enforcement-brainstorm.md` and the `feat-plan-concurrency-enforcement` spec). This plan's scope is reproducing the visual artifact at the canonical path — not re-litigating product decisions.
**Pencil available:** yes (MCP `✓ Connected`), but **installed adapter is drifted** — see Phase 1 preflight.

#### Findings

The modal's content and behavior were already decided in #1162 and are surfaced in the WebSocket close-code flow (`4008 CONCURRENCY_CAP`). The agent receives a scoped prompt describing that flow; it does not re-open product design.

## Implementation Phases

### Phase 1 — Preflight (MANDATORY, blocks Phase 2)

Fail-fast checks. Do NOT skip to Phase 2 even if these look trivial — the Phase 0 drift finding means skipping Phase 1 reproduces #2630.

1. **Verify env** — `printenv PENCIL_CLI_KEY | head -c 8` must print a non-empty prefix. If unset: `doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain` to confirm it exists in Doppler, then launch the session under `doppler run -p soleur -c dev -- …` OR export for the current shell. Do NOT hand off to a human if Doppler has the key (AGENTS.md `hr-exhaust-all-automated-options-before`).
2. **Refresh installed adapter** — `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --check-adapter-drift --auto`. Re-run without `--auto` and assert output starts with `OK`. Non-OK exit is a hard stop. The `--auto` path invokes `copy_adapter.sh` which syncs **5 files** per its `ADAPTER_FILES=(…)` array — verified by reading the script. Do NOT substitute a one-file sha check.
3. **Verify Pencil MCP connection** — `claude mcp list | grep -E '^pencil:.*Connected'` must return one line. If missing, run `skill: soleur:pencil-setup`. Use plain `claude mcp list`; the `-s user` variant no longer works (verified in `plugins/soleur/skills/pencil-setup/SKILL.md` with a `<!-- verified: 2026-04-19 -->` annotation).
4. **Reopen #2636** — `gh issue reopen 2636 --comment "Reopening: PR #2630 auto-closed this via its body but the canonical .pen was never created. See knowledge-base/project/plans/2026-04-19-fix-recreate-upgrade-modal-at-capacity-pen-plan.md."`
5. **Confirm canonical target is empty or missing** — `[ ! -e knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen ] || [ "$(stat -c %s knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen)" -eq 0 ]`. The path may already hold a 0-byte placeholder from `b4590aa5` (scaffolded for `cq-before-calling-mcp-pencil-open-document`) — that is expected. If the file exists with size > 0, the plan's premise is wrong — stop and reassess.

Exit criterion: all 5 checks pass. Commit nothing yet — Phase 1 is read-only state verification.

### Phase 2 — Recreate design via ux-design-lead

Invoke the `ux-design-lead` agent via the Task tool with the following scoped prompt (use absolute paths — the agent's Pencil MCP runs relative to the repo root, not the worktree CWD, per AGENTS.md hr-mcp-tools-playwright-etc-resolve-paths):

```text
Create a wireframe for the "upgrade modal at capacity" surface that displays
when a user attempts to start a new agent and has hit their plan's
concurrent-slot cap (Solo: 2, Startup: 5, Scale: unlimited).

Context (from #1162 plan-concurrency-enforcement brainstorm):
- Triggered by WebSocket close code 4008 CONCURRENCY_CAP on new-session attempt.
- Must show: current plan name, current slots used (e.g., "2/2 agents running"),
  upgrade CTA to the next tier with price, secondary "manage running agents" link,
  dismiss/close.
- Inline Stripe Checkout opens from the upgrade CTA (do NOT design the Checkout
  page itself — stop at the CTA).
- Brand voice: clear, non-punitive, explains capacity as a neutral fact
  ("You're using all 2 of your Solo plan's agent slots") — not as a penalty.

Save path (MANDATORY — the `product/` segment is required per
plugins/soleur/agents/product/design/ux-design-lead.md:54):

  /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-recreate-upgrade-modal-pen/knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen

Platform: desktop. Fidelity: wireframe.

After save, the post-save HARD GATE in your own instructions
(ux-design-lead.md:55) requires stat -c %s > 0. Do not announce completion
until that check passes. If size is 0, surface the verbatim adapter error —
do NOT fabricate a "headless stub" narrative.

Also export high-res screenshots as direct children of
knowledge-base/product/design/billing/screenshots/ (NOT a nested subfolder —
.gitignore rule 57 only unignores `screenshots/*.png` direct children, not
nested paths). Use export_nodes with scale: 3, format: "png", then rename
node-ID files to feature-prefixed kebab-case continuing the existing 01-04
numbering (e.g., 05-upgrade-modal-at-capacity-solo.png,
06-upgrade-modal-at-capacity-isolated.png,
07-upgrade-modal-at-capacity-startup.png) — matches sibling design folders'
flat convention.
```

Expected outputs on success:

- `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen` with `stat -c %s` > 0.
- `knowledge-base/product/design/billing/screenshots/upgrade-modal-at-capacity/NN-*.png` (high-res renders).

### Phase 3 — Caller-side verification (belt-and-suspenders)

Even though `ux-design-lead.md:55` enforces the gate itself, the caller must independently verify before committing. This guards against an agent self-announcing success on a 0-byte save (exactly the failure mode that produced #2636 in the first place — the prior invocation also self-announced).

```bash
PEN=knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen
test -f "$PEN" || { echo "MISSING: $PEN"; exit 1; }
SIZE=$(stat -c %s "$PEN")
[ "$SIZE" -gt 0 ] || { echo "ZERO-BYTE: $PEN"; exit 1; }
echo "OK: $PEN ($SIZE bytes)"
ls knowledge-base/product/design/billing/screenshots/upgrade-modal-at-capacity/ | head
```

If ZERO-BYTE: do NOT commit. Re-run Phase 1 drift check, read the adapter error verbatim per AGENTS.md `cq-pencil-mcp-silent-drop-diagnosis-checklist`, fix, retry Phase 2. Do not fabricate a "stub" explanation.

### Phase 4 — Ship

1. `git add knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen knowledge-base/product/design/billing/screenshots/upgrade-modal-at-capacity/` — explicit paths only (AGENTS.md guidance against `git add -A`).
2. `git status --short` to confirm no stray files.
3. Commit message:

   ```text
   design(billing): add upgrade-modal-at-capacity.pen at canonical path

   Recreates the .pen that PR #2630 was supposed to enable. The placeholder
   at the deprecated knowledge-base/design/ path was already gone
   (directory removed in #566); this creates the canonical
   knowledge-base/product/design/billing/ version that #1162 references.

   Post-save size gate verified: <SIZE> bytes.
   Adapter drift check: OK (refreshed in preflight).

   Closes #2636
   Ref #1162
   ```

4. Push and `/ship` — the PR body uses `Closes #2636` in the body (AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).
5. **Apply semver label:** `patch` — this is a design artifact recreation, not a new capability.

### Phase 5 — Post-merge verification

After the PR merges, confirm the canonical file exists on main:

```bash
git fetch origin main
git show origin/main:knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen | wc -c
```

Must be > 0. Also confirm #2636 auto-closed by the `Closes #2636` line.

## Files to Edit

None.

## Files to Create

- `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen` — the design artifact itself (binary; created by Pencil MCP via `ux-design-lead`).
- `knowledge-base/product/design/billing/screenshots/upgrade-modal-at-capacity/NN-*.png` — high-res exports (per `ux-design-lead.md:56-57`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen` exists with `stat -c %s` > 0. (41394 bytes)
- [x] `knowledge-base/product/design/billing/screenshots/` contains feature-prefixed kebab-case PNGs (per existing flat convention). (`05-/06-/07-upgrade-modal-at-capacity-*.png`, 3 PNGs)
- [ ] Preflight evidence posted in the PR body: adapter drift check output showing `OK`, `claude mcp list` line showing `pencil: ✓ Connected`, saved-file byte count.
- [x] Issue #2636 was reopened before any recreation commit landed (visible in issue timeline).
- [ ] PR body contains `Closes #2636` and `Ref #1162`.
- [ ] Semver label applied: `semver:patch`.

### Post-merge (operator)

- [ ] `git show origin/main:knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen | wc -c` > 0 on main.
- [ ] Issue #2636 state is `CLOSED` (by the PR's `Closes` line, not by manual override).
- [ ] No `knowledge-base/design/` directory exists on main (already absent; guard).

## Test Scenarios

This is a design artifact creation on a green path. The failure mode that produced the original regression (0-byte saves under a drifted adapter + missing `PENCIL_CLI_KEY`) is already covered by tests added in PR #2630:

- `plugins/soleur/test/pencil-adapter-*` — auth hard-fail, classification, save-gate
- `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` — canonical path enforcement

This plan relies on those tests as the regression safety net. No new tests are added — adding tests that exercise an agent invocation to produce a binary `.pen` file would duplicate the guards already in place and add flake risk.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Adapter drift on executor host silently re-produces 0-byte save (the exact #2636 cause). | Phase 1 preflight hard-stops on non-OK `--check-adapter-drift` output; Phase 3 belt-and-suspenders `stat` guards commit. `copy_adapter.sh` syncs all 5 files in its `ADAPTER_FILES` array (adapter + 4 pure modules), so drift in a sibling module cannot slip past. |
| `ux-design-lead` self-announces success on a 0-byte save (despite the HARD GATE in its own instructions — agents have self-announced stub narratives before, see PR #2630 learning file). | Caller-side Phase 3 `stat -c %s` independent of the agent's self-report. |
| Agent re-emits the exact fabricated narrative "Pencil MCP adapter is a headless stub — dropped all ops silently" documented in `2026-04-19-ux-design-lead-headless-stub-fabrication.md`. | Phase 2 invocation prompt includes the "do NOT fabricate" instruction verbatim pointing at `AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist`. If that narrative appears in the agent's return, Phase 3 `stat` still fails the commit — narrative is advisory, byte count is authoritative. |
| Wrong domain chosen — design lives under `billing/` but a future reviewer argues for `pricing/` or a new `plan-concurrency/` domain. | Rationale documented in Research Reconciliation: billing domain holds `subscription-management.pen`, the modal is a billing-flow event, and no `plan-concurrency/` domain exists. A reviewer can move the file in a follow-up if needed — cheap to relocate a single `.pen`. |
| Issue #2636 stays closed because reopen step is skipped. | Phase 1 step 4 is explicit and runs before any mutation. |
| Auto-close via `Closes #2636` in the PR body re-closes the issue while the recreation is still mid-review. | `Closes #<N>` fires only on merge-to-main, not PR open — the reopen-while-still-open window is safe. |

## Non-Goals

- NOT designing the upgrade-modal states beyond the single "at capacity" wireframe. The brainstorm for #1162 is the source of truth for flow variants.
- NOT opening Stripe Checkout inside the `.pen` — the CTA is the boundary.
- NOT re-litigating plan naming, tier prices, or slot counts — those are fixed in `pricing-page-v2-wireframes.pen` and the #1162 brainstorm.
- NOT adding new AGENTS.md rules — PR #2630 already added `cq-pencil-mcp-silent-drop-diagnosis-checklist` which fully covers the failure mode.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Place under `knowledge-base/product/design/pricing/` alongside `pricing-page-v2-wireframes.pen`. | Pricing page is a public marketing surface. This modal is an in-app billing-flow event triggered by a live session state. `billing/` is the correct domain. |
| Create a new `knowledge-base/product/design/plan-concurrency/` domain. | Adds a domain for a single artifact; `billing/` already covers this surface area (`subscription-management.pen` is the sibling). Avoid single-file domains. |
| Re-use `subscription-management.pen` by adding the modal as a frame inside it. | The modal is a distinct surface with its own triggering context; separate `.pen` files are easier to audit and update. `ux-design-lead.md` convention is one flow per `.pen`. |
| Skip `ux-design-lead` and hand-craft a `.pen` via direct Pencil MCP calls. | Bypasses the agent's built-in post-save gate, canonical-path enforcement, and screenshot-export convention. No upside. |

## Research Insights

- **Parent context:** Issue #1162 — plan-based agent concurrency enforcement. Relevant decisions from its brainstorm: WebSocket close code `4008 CONCURRENCY_CAP`, inline Stripe Checkout from upgrade CTA, no queue (reject with CTA).
- **Regression fixed in PR #2630:** Adapter now hard-fails on missing `PENCIL_CLI_KEY`, classifies auth errors, skips save on errored mutations, and `check_deps.sh --check-adapter-drift` detects stale installed adapter. The HARD GATE at `plugins/soleur/agents/product/design/ux-design-lead.md:55` was added in the same PR.
- **Canonical path rule:** `knowledge-base/product/design/{domain}/` — the `product/` segment is mandatory (#566 removed the top-level `knowledge-base/design/`). Enforced by `ux-design-lead.md:54` and guarded by `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh`.
- **Diagnosis checklist for 0-byte saves:** `AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist` — (a) env has `PENCIL_CLI_KEY`, (b) `check_deps.sh --check-adapter-drift` prints `OK`, (c) saved file `stat -c %s` > 0. "Headless stub" is NOT a known failure mode — the adapter has no stub code path. See `knowledge-base/project/learnings/bug-fixes/ux-design-lead-headless-stub-fabrication.md`.
- **Current executor-host drift (2026-04-19, verified on this worktree):** installed adapter sha `31b572c46a28`, repo sha `1b293c456353` (12-byte sha-256 prefixes from `check_deps.sh --check-adapter-drift`). Phase 1 step 2 refreshes this. Without the refresh, a fresh Phase 2 invocation will reproduce the exact regression that opened #2636. The drift covers 5 files per `plugins/soleur/skills/pencil-setup/scripts/copy_adapter.sh` `ADAPTER_FILES` array: `pencil-mcp-adapter.mjs`, `pencil-error-enrichment.mjs`, `sanitize-filename.mjs`, `pencil-response-classify.mjs`, `pencil-save-gate.mjs` — not just the top-level adapter.
- **Fabrication-narrative precedent:** The learning file at `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md` documents the exact hallucinated string ("Pencil MCP adapter is a headless stub — dropped all ops silently") that produced `cbd571d1` on the `feat-plan-concurrency-enforcement` branch. The narrative was false — `grep` against both repo and installed copies showed 654 / 603 lines respectively with **no stub code path**. Phase 2's scoped prompt explicitly names this pattern so it cannot recur unnoticed.
- **Auto-close origin:** PR #2630's body contained `Closes #2636 on separate branch cleanup (cross-branch placeholder deletion tracked there)` — GitHub's closer ignores the qualifier (AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`) and closed the issue on merge. No workflow change is prescribed here: the correct behavior was already documented; this PR just corrects the outcome.

## Deferrals

None. This plan is self-contained.

## CLI-Verification Gate

No CLI invocation lands in user-facing docs. The shell commands in this plan are local operator invocations (`stat`, `git`, `gh issue reopen`, `bash check_deps.sh`); none are copy-pasted into `*.njk` / `*.md` under `apps/` / README. Gate: N/A.
