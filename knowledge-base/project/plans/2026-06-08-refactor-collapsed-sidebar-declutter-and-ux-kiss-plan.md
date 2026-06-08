---
title: "refactor: declutter collapsed sidebar (gold dot + section monogram) and bias ux-design-lead toward KISS"
type: refactor
date: 2026-06-08
lane: cross-domain
brand_survival_threshold: none
---

# refactor: Declutter Collapsed Sidebar + Bias ux-design-lead Toward KISS

## Enhancement Summary

**Deepened on:** 2026-06-08
**Sections enhanced:** Acceptance Criteria (AC5/AC6 corrected), Research Insights (added), gate dispositions (added).

### Key Improvements
1. **Corrected the test-edit premise (the load-bearing deepen catch).** AC5 originally said "invert the collapsed dot/K assertions." Verify-negative grep proved NO existing band unit test asserts `live-repo-dot` or the collapsed `nav-section-title` — the collapsed-block tests assert the *identity tile* instead. AC5 is now an ADD (new negative assertions), not an invert. This would have surfaced as a confused GREEN phase at /work.
2. **Bounded the e2e change exactly.** The only `live-repo-dot` references anywhere are `nav-states-shell.e2e.ts:525` and `:606` (exhaustive grep). Both are in AC7; no other suite touches it.
3. **Recorded the 4.9 UI-wireframe gate disposition** so /work and review know it was evaluated, not skipped (excluded as a style tweak per `ui-surface-terms.md`).

### New Considerations Discovered
- The `S` text assertion at `workspace-context-band.test.tsx:205` is the workspace-identity MONOGRAM ("Soleur Workspace" → "S"), NOT the section "K" — a near-miss that could lead an implementer to mistakenly touch it. The plan now flags the identity tile as retained-and-tested (AC3).
- `nav-rail-drill.test.tsx` likely needs zero edits (its `nav-section-title` assertion targets the expanded band) — Files-to-Edit notes it may be dropped at /work.

## Overview

Two coupled, low-risk UX-hygiene changes, both pure code/agent-prose edits against already-provisioned surfaces (no new infra, no schema, no regulated-data surface):

1. **Collapsed-sidebar declutter (the founder-named target).** In the collapsed nav rail (`md:w-14`, 56px) the workspace context band renders two decorative, non-interactive glyphs that carry no information the rest of the rail does not already carry:
   - a **gold dot** (`data-testid="live-repo-dot"`, the `●` glyph, label "Active repository") — a label-only decoration with no link and no per-repo distinction (it is identical for every repo/workspace); and
   - a **single-letter section monogram** (`data-testid="nav-section-title"` collapsed form, rendering `SECTION_LABELS[drill].charAt(0)` → e.g. "K" for Knowledge Base, "S" for Settings) — redundant with the section's own icon-only nav glyphs that already render in the collapsed rail.

   Remove both **from the collapsed-rail branch only**. The expanded-rail and mobile full-text section title (`nav-section-title` rendering the full "Knowledge Base"/"Settings" label) stays — it is legible, informative, and is what the section-title tests/e2e assert in those states. The workspace **identity monogram tile** (`workspace-identity-icon` / `WorkspaceIdentityTile`) also stays — it is the active-workspace orientation anchor (ADR-047 brand invariant 1), not decoration.

2. **Sweep other screens for similar decorative/redundant clutter.** Verify the rest of `apps/web-platform/components/**` for the same defect class (standalone decorative status dots, redundant single-letter monograms). The plan-time sweep (see Research Reconciliation) found the collapsed band is the *only* site of a standalone decorative `●` status dot and the *only* redundant single-letter section glyph; the other `•`/`●` hits are legitimate text separators and list bullets. The sweep is folded in as an explicit AC so the "everywhere" intent is verified, not assumed.

3. **Bias `ux-design-lead` toward KISS.** The `ux-design-lead` agent (`plugins/soleur/agents/product/design/ux-design-lead.md`) currently has no design-time simplicity principle in its `## Workflow`/`## Step 2: Design` sections — its only "less is more" guidance is buried in the screenshot-audit `real-estate` rubric. Add a concise, design-time KISS principle that biases new wireframes/screens toward fewer elements, less decoration, and removing anything that does not carry information or an action. This is an agent-prose edit (no `description:` change → no agent token-budget impact; current cumulative agent-description word count 1508, well under the ~2500 cap).

This is a `refactor` (visual-hygiene + agent-prose), not a `feat`: no new pages, no new components, no new flows.

## Research Reconciliation — Spec vs. Codebase

No spec file exists for this branch (`knowledge-base/project/specs/feat-one-shot-sidebar-declutter-kiss/` is absent) and no brainstorm preceded this plan. The premise was validated directly against the codebase. No external premises (issues/PRs) were cited by the founder, so there is nothing to `gh`-verify.

| Founder claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "collapsed sidebar has a gold dot" | `apps/web-platform/components/dashboard/workspace-context-band.tsx:117-124` — `data-testid="live-repo-dot"`, glyph `●`, class `text-soleur-accent-gold-fg` (gold), `aria-label`/`title` "Active repository". Renders only in the `variant === "rail" && collapsed` branch. Non-interactive (a `<span>`, not a link). | Remove this `<span>` from the collapsed branch. |
| "collapsed sidebar has a 'K'" | Same file, `:125-133` — collapsed-branch `data-testid="nav-section-title"` renders `SECTION_LABELS[drill].charAt(0)` (= "K" on `/dashboard/kb`, "S" on `/dashboard/settings`). Distinct from the expanded/mobile full-text title at `:199-206`. | Remove the collapsed-branch single-letter title only; keep the full-text title in the non-collapsed return. |
| "they serve no clear purpose" | Confirmed: the dot is identical for every repo (no per-repo state); the "K" duplicates the section's own collapsed nav icon. The identity monogram tile (`workspace-identity-icon`) is the one collapsed glyph that *does* carry orientation info — keep it. | Keep `workspace-identity-icon`; remove dot + section monogram. |
| "remove similar elements everywhere" | Sweep of `apps/web-platform/components/**/*.tsx`: the standalone decorative `●` at `workspace-context-band.tsx:123` is the *only* one; other `•`/`●` are text separators (`today-card.tsx`, `template-authorization-row.tsx`), list bullets (`dsar-export-dialog.tsx`), or password masks. The only `charAt(0)` monograms are the workspace identity tile (keep) and this section glyph (remove). | Fold the sweep in as an AC; no other component edits needed beyond the band. |
| "ux-design-lead agent/skill" | It is an **agent** (`plugins/soleur/agents/product/design/ux-design-lead.md`), invoked via the `.openhands/skills/ux-design-lead/SKILL.md` mirror and by `plan`/`brainstorm`/`work`/`ux-audit`. No design-time KISS principle exists in its body. | Edit the agent body (`## Step 2: Design`); mirror the principle into `.openhands/skills/ux-design-lead/SKILL.md` if it duplicates the body (verify at /work). |

## User-Brand Impact

**If this lands broken, the user experiences:** a collapsed sidebar that either still shows the clutter (no-op edit) or — the realistic failure — a collapsed rail whose vertical rhythm shifts because a removed glyph leaves a stray `gap-3` slot, or an e2e/unit test left asserting the now-removed `live-repo-dot`/collapsed-`K` fails CI.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this change touches presentational chrome only; it reads no PII, writes nothing, and changes no auth/data boundary.

**Brand-survival threshold:** none. Rationale: purely decorative-glyph removal + agent-prose; the diff touches no sensitive path (no schema, migration, auth flow, API route, `.sql`, or BYOK/credential surface). The identity monogram (the one orientation-bearing glyph) is explicitly retained, so no workspace-disambiguation regression. (`threshold: none, reason: presentational chrome removal + agent-prose edit; touches no sensitive path and no data/auth boundary.`)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — In `workspace-context-band.tsx`, the `variant === "rail" && collapsed` branch no longer renders the `data-testid="live-repo-dot"` `<span>` (the gold `●`). Verify: `grep -c 'live-repo-dot' apps/web-platform/components/dashboard/workspace-context-band.tsx` returns `0`.
- [ ] AC2 — The same collapsed branch no longer renders the single-letter section monogram (`SECTION_LABELS[drill].charAt(0)`). The collapsed branch contains no `data-testid="nav-section-title"`. The **non-collapsed** return still renders the full-text `nav-section-title` (`:199-206` unchanged).
- [ ] AC3 — The collapsed `workspace-identity-icon` / `WorkspaceIdentityTile` is retained verbatim (orientation anchor, not decoration). `grep -c 'workspace-identity-icon' …band.tsx` returns `1`.
- [ ] AC4 — Collapsed-rail vertical layout has no orphaned spacing: the remaining children (optional back chevron + identity tile) sit in the `flex flex-col items-center gap-3` column with no empty slot. (RTL render asserts exactly the expected child set; see Test Scenarios.)
- [ ] AC5 — `workspace-context-band.test.tsx`: ADD negative assertions to the existing collapsed-block describe (`"WorkspaceContextBand — collapsed monogram identity (Phase 1, #4915)"`, `:192`) asserting `queryByTestId("live-repo-dot")` and `queryByTestId("nav-section-title")` are `null` in the `collapsed` render. (Reconciliation: NO existing band unit test asserts the removed glyphs — see Research Insights — so this is an ADD, not an invert. The collapsed-block tests at `:193`/`:210` assert the *identity tile* and stay green; the `nav-section-title` assertions at `:143`/`:159`/`:167`/`:234`/`:256`/`:261` are all NON-collapsed renders and stay green untouched.)
- [ ] AC6 — `nav-rail-drill.test.tsx` rail-band `nav-section-title` assertion (`:282`) renders the **expanded** rail (the test does not set `collapsed`), so it stays green. Confirmed: no test depends on the *collapsed* `nav-section-title`. Likely zero edits to this file; if untouched, drop it from Files-to-Edit at /work.
- [ ] AC7 — `e2e/nav-states-shell.e2e.ts`: the two `getByTestId("live-repo-dot")` `toBeVisible()` assertions (`:525`, `:606`) are replaced with a positive collapsed-identity invariant (`workspace-identity-icon` visible) so the e2e still proves identity-never-unmounts-on-collapse (ADR-047) without asserting the removed dot.
- [ ] AC8 — Other-screens sweep verified empty: `grep -rn '●' apps/web-platform/components --include=*.tsx | grep -v node_modules` returns no standalone decorative status dot outside the (now-edited) band; any remaining `●`/`•` are text separators / list bullets / masks (enumerated in Research Reconciliation). Record the grep output in the PR body.
- [ ] AC9 — `ux-design-lead.md` `## Step 2: Design` contains a KISS/simplicity design-time principle (bias toward fewer elements, remove non-informational decoration). The agent `description:` field is unchanged (no token-budget impact). Verify `grep -c 'description:' plugins/soleur/agents/product/design/ux-design-lead.md` still returns `1` and the description line is byte-identical to `origin/main`.
- [ ] AC10 — `.openhands/skills/ux-design-lead/SKILL.md` is reconciled with the agent body: if it mirrors the design workflow, the KISS principle is mirrored there too; if it diverges, note why in the PR body. (Verify at /work which file the mirror actually carries.)
- [ ] AC11 — `tsc --noEmit` clean for `apps/web-platform`; the targeted vitest files pass (`./node_modules/.bin/vitest run test/workspace-context-band.test.tsx test/nav-rail-drill.test.tsx` — paths confirmed against `vitest.config.ts` jsdom `include: test/**/*.test.tsx`).

### Post-merge (operator)

- [ ] None — pure code/agent-prose change; the `web-platform-release.yml` pipeline restarts the container on merge to `main` touching `apps/web-platform/**`. No migration, no infra apply, no dashboard step.

## Files to Edit

- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — remove the collapsed-branch `live-repo-dot` span (`:117-124`) and the collapsed-branch single-letter `nav-section-title` span (`:125-133`); leave the non-collapsed full-text title and the collapsed identity tile untouched. Audit the collapsed container's `gap-3` after removal (AC4).
- `apps/web-platform/test/workspace-context-band.test.tsx` — invert collapsed-state assertions to absence (AC5).
- `apps/web-platform/test/nav-rail-drill.test.tsx` — confirm/adjust collapsed-vs-expanded `nav-section-title` expectations (AC6); likely no change (assertions target the expanded rail band).
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — replace the two `live-repo-dot` visibility assertions with the `workspace-identity-icon` invariant (AC7).
- `plugins/soleur/agents/product/design/ux-design-lead.md` — add design-time KISS principle to `## Step 2: Design` (AC9).
- `.openhands/skills/ux-design-lead/SKILL.md` — mirror the KISS principle if it duplicates the agent design workflow (AC10; verify at /work).

## Files to Create

- None.

## Open Code-Review Overlap

None. (Checked: no open `code-review`-labeled issue names `workspace-context-band.tsx`, `nav-states-shell.e2e.ts`, or `ux-design-lead.md`. Re-confirm with the `gh issue list --label code-review` two-stage jq check at /work if connectivity allows; the sweep returned no matches at plan time.)

## Test Scenarios

1. **Collapsed rail, top level (`/dashboard`, collapsed):** band renders the identity tile only; no `live-repo-dot`, no section monogram (no drill → none anyway). `flex-col gap-3` has a single child.
2. **Collapsed rail, drilled (`/dashboard/kb`, collapsed):** band renders back chevron + identity tile; no `live-repo-dot`, no "K". (Verify both toggle states per the alignment Sharp Edge: the *expanded* `/dashboard/kb` band still shows "Back to menu" + full "Knowledge Base" title — unchanged.)
3. **Expanded rail, drilled:** full-text `nav-section-title` ("Knowledge Base"/"Settings") still present (regression guard — must NOT be removed).
4. **Mobile band:** unchanged; mobile section-title suppression logic (`suppressSectionTitle`) untouched.
5. **e2e collapsed invariant:** `workspace-identity-icon` visible when collapsed (identity never unmounts, ADR-047) on both `/dashboard` and `/dashboard/settings`.

## Domain Review

**Domains relevant:** Product (UI surface).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline path; advisory tier)
**Skipped specialists:** none — this is a `refactor` that *removes* presentational elements from an existing component; it creates no new page, component file, flow, or interactive surface. The mechanical UI-surface override fires (the path matches `components/**/*.tsx`), forcing Product-relevant=true, but the three-tier classification is **ADVISORY** (modifies an existing component without adding a new interactive surface), and there are no new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` *created* files to escalate to BLOCKING. Per the plan-skill ADVISORY pipeline rule, auto-accept and proceed.
**Pencil available:** N/A — no NEW UI surface; this is element removal from an existing component, so `wg-ui-feature-requires-pen-wireframe` (which targets new pages/flows/components) is not triggered. A `.pen` wireframe for "remove two glyphs" would be ceremony; the before/after is fully specified by the Files-to-Edit diff.

#### Findings

The change reduces cognitive load on the most-used persistent chrome (the collapsed rail), directly aligned with the `real-estate`/`comprehension` rubric in `ux-design-lead`'s own audit categories. The one risk a designer would flag — losing workspace orientation when collapsed — is explicitly mitigated by retaining the identity monogram tile (the orientation-bearing glyph). The section "K" is redundant with the section's collapsed nav icon, so its removal does not cost wayfinding.

## Observability

This plan's Files-to-Edit are presentational `.tsx` (a React component + tests + e2e) and agent prose — no `apps/*/server/`, no `apps/*/infra/`, no new runtime process, no new failure mode. Per the Phase 2.9 skip rule (no new server/infra/runtime surface; presentational-only), a 5-field observability schema does not apply. The only "signal" is the existing CI suite (vitest + Playwright + `tsc`), which fails loud on a stale `live-repo-dot`/collapsed-`K` assertion — that is the discoverability test:

```yaml
discoverability_test:
  command: ./node_modules/.bin/vitest run test/workspace-context-band.test.tsx (NO ssh)
  expected_output: collapsed-state tests assert absence of live-repo-dot and collapsed nav-section-title; all pass
```

## Risks & Sharp Edges

- **Both-toggle-states verification (learning `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`):** the change is collapsed-only, but the expanded state shares the same component. The plan explicitly guards the expanded full-text title (AC2, Test Scenario 3) so the edit cannot accidentally strip the legitimate expanded title.
- **Test-assertion staleness:** removing the dot/K orphans the `live-repo-dot` and collapsed `nav-section-title` assertions. They are enumerated in Files-to-Edit (AC5/AC7) so CI does not fail on a stale positive assertion — the modal failure mode for "remove an element" PRs.
- **Identity tile is NOT clutter:** the easy over-correction is to also remove the collapsed `workspace-identity-icon`. AC3 forbids this — it is the ADR-047 brand invariant 1 orientation anchor.
- **Agent `description:` byte-identity:** the ux-design-lead edit must touch only the body, never the `description:` line (AC9), so no agent token-budget recompute is needed.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold `none` with a sensitive-path scope-out reason.)

## Research Insights

### Deepen-plan gate dispositions (Phases 4.6–4.9)

- **4.6 User-Brand Impact:** PASS. Section present; threshold `none` with a non-empty sensitive-path scope-out reason. None of the Files-to-Edit match the canonical `SENSITIVE_PATH_RE` (verified: all six paths return `ok`).
- **4.7 Observability:** PASS (presentational-only; section present with the discoverability_test documenting the vitest command — no SSH).
- **4.8 PAT-shaped variable:** PASS — sweep returns no PAT-shaped var/literal.
- **4.9 UI-Wireframe Artifact Halt:** EVALUATED → EXCLUDED (not halted). The glob superset mechanically matches `components/**/*.tsx`, but `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` `## Excluded` explicitly carves out "Pure copy or style tweaks with no structural/layout change." This refactor *removes* two presentational glyphs from an existing component — no new page/flow/component, no layout redesign. The gate's intent (`wg-ui-feature-requires-pen-wireframe`, #4819) is to stop a *new UI feature* shipping with zero wireframes; a two-glyph removal is the excluded style-tweak class. The Domain Review Product/UX Gate is correspondingly ADVISORY (auto-accepted, pipeline). No `.pen` is produced — generating one for "remove two glyphs" would be the ceremony `wg-ui-feature-requires-pen-wireframe` is not asking for.

### Verify-the-negative pass (Phase 4.45)

- Claim "the `●` at `workspace-context-band.tsx:123` is the only standalone decorative status dot in `components/**`": CONFIRMED. `grep -rn '●' apps/web-platform/components --include=*.tsx` returns exactly one hit (that line). The `•` hits elsewhere are text separators (`today-card.tsx`, `template-authorization-row.tsx`), list bullets (`dsar-export-dialog.tsx`), and a password mask — all legitimate.
- Claim "no existing band unit test asserts the removed glyphs": CONFIRMED via grep — drives the AC5 correction above.

### Precedent-diff (Phase 4.4)

No pattern-bound behavior (no SQL/lock/RPC/atomic-write). The component-edit precedent is the surrounding file's own convention: removing a presentational `<span>` from a conditional branch. The collapsed container (`flex flex-col items-center gap-3`) already renders a variable child set (the back chevron is conditional on `drill && !suppressBack`), so dropping two children leaves a well-formed `gap-3` column — no novel pattern, no new spacing primitive (AC4 audits this).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Keep the dot but make it carry per-repo state (color/animation) | The founder's intent is *less* clutter, not more meaning on a 56px rail; a stateful dot adds complexity against KISS. Deferred — no tracking issue (explicitly rejected, not deferred). |
| Remove the identity tile too (maximal declutter) | Violates ADR-047 brand invariant 1 (workspace orientation must survive collapse). Rejected. |
| Produce a Pencil `.pen` wireframe for the before/after | Ceremony for a two-glyph removal; the diff is fully self-specifying. Skipped per ADVISORY-tier rule. |
