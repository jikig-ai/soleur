---
title: "docs(legal): forward-port plugin-mirror legal docs to match canonical (KB-sharing + push notifications + Resend)"
type: docs
date: 2026-05-12
issue: 3666
lane: single-domain
requires_cpo_signoff: false
---

# Forward-Port Plugin-Mirror Legal Docs to Match Canonical (#3666)

## Enhancement Summary

**Deepened on:** 2026-05-12

**Scope of deepen pass:** Verification gates only (no per-section research fan-out). The plan is documentation-only with a verbatim forward-port from canonical to plugin mirror; there is no library/framework surface to research, no algorithm to benchmark, and no UI/UX to enhance. Deepen value comes from live-reference verification and gate compliance rather than horizontal research.

### Verification Gates Run

1. **User-Brand Impact halt (Phase 4.6):** PASS. Section present, threshold `none` is valid for documentation-only forward-port with no sensitive-path-regex match.
2. **Live PR/issue verification:** `gh pr view 3662 --json state,title` returned `state=MERGED` ✓; `gh issue view 3603 --json state,title` returned `state=CLOSED` ✓ (corrected plan prose from "PR #3603" to "issue #3603" — `#3603` is the umbrella tracking issue, not a PR).
3. **AGENTS.md rule-citation verification:** 1 rule cited (`wg-when-an-audit-identifies-pre-existing` in Risks R3). `grep -n` against `AGENTS.core.md` confirms it is an **active** rule (line 48). Cross-checked against `scripts/retired-rule-ids.txt` — not retired. ✓
4. **Label verification:** `semver:patch`, `domain/legal`, `priority/p3-low` all exist per `gh label list --limit 200` (verified at plan-write time).
5. **Eleventy build command verification:** Read `package.json` at repo root — confirmed `scripts.docs:build` exists as `"npx @11ty/eleventy"`. AC12 updated from `cd plugins/soleur/docs && npx @11ty/eleventy --dryrun` to canonical `npm run docs:build`.
6. **Network-Outage gate (Phase 4.5):** N/A — zero SSH/network keywords in plan body, no `provisioner` blocks in scope.
7. **GDPR gate (Phase 2.7):** Skipped silently — no canonical-regex match, no (a)-(d) trigger fire.
8. **Pathspec/regex translation gate:** N/A — no globs prescribed.
9. **Workflow constant equality invariants:** N/A — no constants prescribed.
10. **Cited learning file existence:** All 4 cited learnings (`2026-03-18-dpd-processor-table-dual-file-sync.md`, `2026-03-20-eleventy-mirror-dual-date-locations.md`, `2026-03-02-legal-doc-bulk-consistency-fix-pattern.md`, `2026-02-20-dogfood-legal-agents-cross-document-consistency.md`) verified present in `knowledge-base/project/learnings/`.

### Key Improvements vs. v0 Plan

1. **PR/issue citation drift corrected.** Plan v0 used "PR #3603" / "#3603 PR-A/B/C" — `gh issue view 3603` returns issue, not PR; #3603 is the umbrella tracking issue under which #3662 (PR-C) shipped. Updated Overview and References sections.
2. **Eleventy build command corrected.** Plan v0 prescribed `cd plugins/soleur/docs && npx @11ty/eleventy --dryrun`; the project's actual build script is `npm run docs:build` from repo root (verified via `package.json` `scripts.docs:build`).
3. **Live-verification provenance added inline.** Each cited PR/issue now carries the `gh` verification output alongside the citation per the deepen-plan Quality Check on SHA/PR/issue live verification.

### New Considerations Discovered

- **Row 8 (GDPR §4.2 OAuth provider row) was not a gap.** Verified by direct file diff that the OAuth provider row exists identically in both `docs/legal/gdpr-policy.md:134` and `plugins/soleur/docs/pages/legal/gdpr-policy.md:141`. It was forward-ported in a prior PR. The issue listed this row as "open — investigate spec table form" — investigation result is documented in the plan's Research Reconciliation row 8 and explicitly called out as PR-body content via AC11.
- **§3.8 prose drift is larger than the issue body implied.** Issue body says "absent"; verification shows the heading exists in both but the body differs (canonical: parenthetical heading + intro paragraph + two qualified bullets; plugin: condensed heading + two condensed bullets without intro). Forward-port replaces heading + body, not just inserts.
- **No agent-fan-out value-add.** Standard deepen-plan procedure spawns per-section research agents, skill agents, and learning sub-agents. For this plan, none would return load-bearing findings: there are no library docs to fetch, no UI to redesign, no perf considerations to benchmark, no architectural decisions to revisit. The deepen pass is intentionally gate-only.

## Overview

The canonical legal corpus at `docs/legal/` is ahead of the plugin-mirror at `plugins/soleur/docs/pages/legal/` on several Web Platform processing-activity disclosures that already landed in canonical via prior PRs under umbrella issue #3603 (verified live 2026-05-12: `gh issue view 3603` returns state=CLOSED, title "hardening: cc-soleur-go transcript persistence — cross-tenant invariants, abort flush, migration affordance, privacy refresh"). The KB-sharing and push-notification disclosures landed in earlier PRs (specific PR numbers not cited inline — see commit footers of `plugins/soleur/docs/pages/legal/*` and `docs/legal/*` history for provenance). This is the **inverse direction** of the PR-C-anticipated drift — the v2 plan of issue #3603's PR-C assumed canonical was behind on conversation-data disclosures; verification at edit time of PR #3662 (verified live: state=MERGED, title "docs(legal): PR-C legal refresh for cc-soleur-go transcript persistence + DSAR audit — #3603") showed canonical was actually ahead on the rows enumerated below.

This PR consolidates the forward-port per PR-C plan AC13 (`knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md:111`). Three plugin-mirror files are edited; canonical is **untouched** (it is the source of truth in this direction). Each plugin-mirror file's `Last Updated` line (both hero `<p>` and body `**Last Updated:**` per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`) is bumped to `2026-05-12` with a one-line summary of changes.

**Scope:** documentation-only. No code, no schema, no migrations, no auth or API surfaces. Three files edited:

1. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
2. `plugins/soleur/docs/pages/legal/privacy-policy.md`
3. `plugins/soleur/docs/pages/legal/gdpr-policy.md`

## User-Brand Impact

**If this lands broken, the user experiences:** the docs-site visitor (soleur.ai/legal/*) sees stale disclosures that omit push-notification consent basis, Resend transactional-email processor, KB-sharing lawful basis, and Article 30 register activity #11. A privacy-conscious user reading only soleur.ai (not app.soleur.ai) may not realize the Web Platform processes additional data categories disclosed in the canonical corpus.

**If this leaks, the user's data is exposed via:** N/A — no data leak vector. This PR only updates prose disclosures to inform users about processing activities that are already happening in production (and are already disclosed in the canonical corpus at app.soleur.ai/legal/*). The PR adds disclosure, it does not change processing.

**Brand-survival threshold:** none.

**Threshold-none rationale:** This is a documentation-only forward-port of disclosures that already exist in the canonical corpus and have already been reviewed under prior PRs (#3486-ish KB-sharing, #3486-ish push notifications, #3603 Resend). The plugin-mirror surface is the docs-site at soleur.ai/legal/* and serves the same disclosure function as the canonical at app.soleur.ai/legal/*. A diff between the two surfaces is the asymmetry being closed — not a new processing activity, not a new threat surface, not a regulated-data-write change. Preflight Check 6's sensitive-path regex (schema/auth/API/`.sql`) does not match `plugins/soleur/docs/pages/legal/**`; the section is present per gate, threshold is `none`, no scope-out bullet required.

## Research Reconciliation — Spec vs. Codebase

The issue body enumerates a 10-row gap inventory. Verified each row against current `docs/legal/` and `plugins/soleur/docs/pages/legal/` heads at branch base — all 10 verified accurate **except one** (GDPR §4.2 OAuth provider row, see row 8 below):

| Row | Issue claim | Codebase reality (verified 2026-05-12) | Plan response |
|-----|-------------|----------------------------------------|---------------|
| 1 | DPD §2.3(j) push notification subscriptions: canonical present, plugin absent | Canonical `docs/legal/data-protection-disclosure.md:100` present; plugin ends at `(i)` on line 108. **Confirmed gap.** | Forward-port `(j)` bullet verbatim from canonical (line 100). |
| 2 | DPD §2.3(k) Resend transactional email: canonical present, plugin absent | Canonical `docs/legal/data-protection-disclosure.md:101` present; plugin absent. **Confirmed gap.** | Forward-port `(k)` bullet verbatim from canonical (line 101). |
| 3 | DPD §4.2 Resend processor row: canonical present, plugin absent | Canonical `docs/legal/data-protection-disclosure.md:156` present (Web Platform Processors table, 5th row); plugin table ends at Cloudflare (4 rows). **Confirmed gap.** | Forward-port Resend table row verbatim from canonical line 156. |
| 4 | DPD §4.2 cross-ref line: canonical ends at `2.3(k)`, plugin ends at `2.3(i)` | Canonical `docs/legal/data-protection-disclosure.md:158`: "consistent with Sections 2.1b, 2.3(a), 2.3(e), 2.3(f), 2.3(g), 2.3(h), 2.3(i), 2.3(j), and 2.3(k)". Plugin line 164: ends at `2.3(i)`. **Confirmed gap.** | Edit plugin line 164 to extend cross-ref to `2.3(j)` and `2.3(k)`. |
| 5 | Privacy Policy §4.8 Content Sharing: no gap | Verified: canonical `docs/legal/privacy-policy.md:118-134` ≈ plugin `plugins/soleur/docs/pages/legal/privacy-policy.md:127-137` (modulo minor whitespace). **No action.** | No edit. |
| 6 | Privacy Policy §4.9 Push Notification Subscriptions: canonical present, plugin absent | Canonical `docs/legal/privacy-policy.md:130-142` present (HTML comment markers `<!-- Added 2026-04-13: Push notifications -->` + 5-bullet section); plugin jumps from §4.8 (line 137) directly to §5 (line 139). **Confirmed gap.** | Forward-port §4.9 verbatim from canonical lines 130-142, insert between §4.8 and §5. |
| 7 | Privacy Policy §5.9 Resend (Web Platform Transactional Email): canonical present, plugin absent | Canonical `docs/legal/privacy-policy.md:212-220` present (5-bullet section after §5.8 Cloudflare); plugin ends at §5.8 (line 205) and jumps to §6 (line 207). **Confirmed gap.** | Forward-port §5.9 verbatim from canonical lines 212-220, insert between §5.8 and §6. |
| 8 | GDPR Policy §4.2 OAuth provider row: open — investigate spec table form | **NOT A GAP.** Canonical `docs/legal/gdpr-policy.md:134` has the OAuth provider row identical to plugin `plugins/soleur/docs/pages/legal/gdpr-policy.md:141`. Row was already forward-ported in a prior PR (likely #3486-ish or #3530-ish). | No edit. Plan documents the investigation result. Mark issue row 8 as resolved-no-action in PR body. |
| 9 | GDPR Policy §3.8 KB-sharing lawful basis: canonical present, plugin absent | **Partial gap.** Heading exists in both (canonical `docs/legal/gdpr-policy.md:93`, plugin `plugins/soleur/docs/pages/legal/gdpr-policy.md:104`), but the **body content differs**. Canonical: "Content Sharing (Knowledge Base Document Sharing)" heading + intro paragraph "For processing related to the knowledge base document sharing feature..." + two qualified bullets `(authenticated users)` / `(unauthenticated viewers)`. Plugin: "Content Sharing" heading (no parenthetical) + two condensed bullets without intro paragraph, with different balancing-test wording. **Confirmed prose drift — older form in plugin.** | Forward-port plugin §3.8 heading + body verbatim from canonical lines 93-100 (replace lines 104-107 of plugin). |
| 10 | GDPR Policy §10 Article 30 register activity #11 (Web Platform content sharing): canonical present, plugin absent | Canonical `docs/legal/gdpr-policy.md:286,300-301`: "documents eleven processing activities" + activity #11 KB-sharing item with HTML comment markers. Plugin `plugins/soleur/docs/pages/legal/gdpr-policy.md:293,304-306`: "documents ten processing activities" + ends at activity #10. **Confirmed gap.** | Edit plugin line 293 from "ten" to "eleven"; append activity #11 (canonical line 300) after plugin's activity #10 (line 304), preserving HTML comment markers. |

**Net real edits:** 9 of the 10 rows (row 8 is no-op; documented as investigation closure).

## Files to Edit

1. **`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`**
   - Insert `(j)` push-notification bullet after line 108 (after `(i)` conversation-management).
   - Insert `(k)` Resend transactional-email bullet after the new `(j)`.
   - Append Resend processor row to Web Platform Processors table after Cloudflare row (currently line 162).
   - Extend cross-ref line 164 from "…`2.3(i)`." to "…`2.3(i)`, `2.3(j)`, and `2.3(k)`."
   - Bump hero `<p>Last Updated …</p>` (line 11) and body `**Last Updated:**` (line 21) to `2026-05-12` with one-line summary.

2. **`plugins/soleur/docs/pages/legal/privacy-policy.md`**
   - Insert §4.9 Push Notification Subscriptions block (HTML comment markers + heading + 5 bullets) between §4.8 (ends line 137) and `## 5. Third-Party Services` (line 139).
   - Insert §5.9 Resend (Web Platform Transactional Email) block (heading + 5 bullets) between §5.8 Cloudflare (ends line 205) and `## 6. Legal Basis for Processing` (line 207).
   - Bump hero `<p>Last Updated …</p>` (line 11) and body `**Last Updated:**` (line 20) to `2026-05-12` with one-line summary.

3. **`plugins/soleur/docs/pages/legal/gdpr-policy.md`**
   - Replace §3.8 (heading line 104 + body lines 106-107) with canonical §3.8 form (heading + intro + qualified bullets, canonical lines 93-100).
   - Edit line 293 "ten processing activities" → "eleven processing activities".
   - Append activity #11 KB-sharing item (canonical line 300, with HTML comment markers preserved) after plugin's activity #10 (line 304), before the closing "The register is maintained internally…" paragraph (line 306).
   - Bump hero `<p>Last Updated …</p>` (line 12) and body `**Last Updated:**` (line 22) to `2026-05-12` with one-line summary.

## Files to Create

None.

## Files NOT to Edit (Out of Scope)

- `docs/legal/data-protection-disclosure.md` — canonical, untouched
- `docs/legal/privacy-policy.md` — canonical, untouched
- `docs/legal/gdpr-policy.md` — canonical, untouched
- Other plugin-mirror legal docs (acceptable-use-policy, cookie-policy, disclaimer, terms-and-conditions, *.cla.md) — no inverse-direction drift identified in the issue gap inventory

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200 | jq -r --arg path "plugins/soleur/docs/pages/legal/" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'`

Result: **None.** No open code-review scope-outs touch `plugins/soleur/docs/pages/legal/`. The query was also run against `docs/legal/` for completeness — none returned. Repeat for individual file paths:

- `data-protection-disclosure.md`: 0 matches
- `privacy-policy.md`: 0 matches
- `gdpr-policy.md`: 0 matches

Recorded `None` so the next planner can see the check ran.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — DPD §2.3(j) and §2.3(k) present in plugin mirror.** `grep -nE '^\- \*\*\(j\)\*\*|^\- \*\*\(k\)\*\*' plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns 2 lines whose text matches canonical lines 100-101 verbatim (modulo a `diff` of the relevant blocks yielding no token-level divergence).
- [x] **AC2 — DPD §4.2 Resend processor row present.** `grep -n 'Resend Inc' plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns the row text identical to canonical line 156. The Web Platform Processors table now has 5 rows (Supabase, Stripe, Hetzner, Cloudflare, Resend).
- [x] **AC3 — DPD §4.2 cross-ref extended.** `grep -n 'consistent with Sections' plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns a line ending in "…`2.3(i)`, `2.3(j)`, and `2.3(k)`."
- [x] **AC4 — Privacy Policy §4.9 present.** `grep -nE '^### 4\.9 Push Notification Subscriptions$' plugins/soleur/docs/pages/legal/privacy-policy.md` returns exactly 1 hit; the 5-bullet block diffs zero against canonical §4.9.
- [x] **AC5 — Privacy Policy §5.9 present.** `grep -nE '^### 5\.9 Resend' plugins/soleur/docs/pages/legal/privacy-policy.md` returns exactly 1 hit; the 5-bullet block diffs zero against canonical §5.9.
- [x] **AC6 — GDPR Policy §3.8 body matches canonical.** `diff <(awk '/^### 3\.8/,/^---$/' plugins/soleur/docs/pages/legal/gdpr-policy.md) <(awk '/^### 3\.8/,/^---$/' docs/legal/gdpr-policy.md)` returns no output (zero token divergence in the §3.8 region delimited by the next `---` rule, which appears at canonical line 104).
- [x] **AC7 — GDPR Policy §10 activity count and #11 present.** `grep -nE 'eleven processing activities' plugins/soleur/docs/pages/legal/gdpr-policy.md` returns exactly 1 hit, AND `grep -nE '^11\. \*\*Web Platform content sharing\*\*' plugins/soleur/docs/pages/legal/gdpr-policy.md` returns exactly 1 hit.
- [x] **AC8 — `ten processing activities` no longer appears in plugin gdpr-policy.** `grep -c 'ten processing activities' plugins/soleur/docs/pages/legal/gdpr-policy.md` returns 0.
- [x] **AC9 — Last-Updated bumped on all 3 touched plugin-mirror files at BOTH locations (hero + body).** Per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`: each file has hero `<p>Effective February 20, 2026 | Last Updated May 12, 2026</p>` and body `**Last Updated:** May 12, 2026 (<one-line summary>)`. Verify: `grep -cE 'Last Updated May 12, 2026' plugins/soleur/docs/pages/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/privacy-policy.md plugins/soleur/docs/pages/legal/gdpr-policy.md` returns `2,2,2` (one hero, one body per file).
- [x] **AC10 — Canonical untouched.** `git diff --name-only main...HEAD -- docs/legal/` returns empty.
- [ ] **AC11 — PR body documents row 8 investigation closure.** PR body includes a section noting "GDPR §4.2 OAuth provider row: investigated; not a gap. Row was forward-ported in a prior PR and matches between canonical and plugin mirror."
- [x] **AC12 — Eleventy build succeeds.** `npm run docs:build` (root `package.json` script — verified at plan time: `"docs:build": "npx @11ty/eleventy"`) returns success and emits the 3 legal pages at the expected permalinks (`legal/data-protection-disclosure/`, `legal/privacy-policy/`, `legal/gdpr-policy/` under `_site/`).
- [x] **AC13 — Cross-document consistency.** Run `skill: soleur:legal-audit` (or invoke `legal-compliance-auditor` agent) scoped to the 3 plugin-mirror files. Expect zero P0/P1 findings on the forward-ported sections. Address any P0/P1 inline; defer P2/P3 to a follow-up issue.
- [ ] **AC14 — Closes #3666.** PR body contains `Closes #3666`.
- [ ] **AC15 — Semver label.** PR labeled `semver:patch` (docs-only change, no plugin component count change — README counts unchanged).

### Post-merge

- [ ] **AC16 — soleur.ai/legal/* pages render with forward-ported content.** After GitHub Pages deploy, verify by curl against `https://soleur.ai/legal/data-protection-disclosure/`, `/legal/privacy-policy/`, `/legal/gdpr-policy/` that the new sections appear in the rendered HTML.

## Test Strategy

Documentation-only PR; no unit/integration tests are introduced. Verification relies on the AC grep + diff harness above plus the Eleventy build gate (AC12) and the legal-compliance-auditor agent (AC13).

**No new test framework dependencies.** No CI workflow changes.

## Domain Review

**Domains relevant:** Legal (primary), Engineering (advisory — touches Eleventy plugin docs build path).

### Legal

**Status:** reviewed (carry-forward from PR-C #3662 AC13 framing)
**Assessment:** This forward-port consolidates disclosures already reviewed and approved under prior PRs (#3486-ish KB-sharing, push-notification; #3603 Resend). No new processing activities are introduced; no balancing tests need re-derivation; no DPAs require re-verification. The single sub-row needing CLO attention is the §3.8 prose-drift fix — verify that the canonical wording (with "(authenticated users)" / "(unauthenticated viewers)" qualifiers and the richer balancing-test paragraph) is the form to canonicalize on; this was approved at canonical-edit time and is now propagated to the plugin mirror. Drain criterion per PR-C R7 is satisfied by this PR.

### Engineering (advisory)

**Status:** reviewed (auto)
**Assessment:** Plugin-mirror docs are built by Eleventy under `plugins/soleur/docs/`. AC12 enforces the build gate. No JS/TS code, no schema, no migrations, no auth flow. No critical-CSS impact (no template changes). Eleventy build runs in CI on every PR per existing `.github/workflows/` gates (`critical-css-gate.yml` covers the docs site).

### Product/UX Gate

Not applicable. Tier: NONE. No new user-facing pages, no UI components, no flow changes. Plugin-mirror legal docs at soleur.ai/legal/* render via existing `base.njk` layout — page content changes are inline prose only.

## GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

**Canonical regex match:** No — `plugins/soleur/docs/pages/legal/**` does not match the schema/auth/API/`.sql` regex.

**Expanded trigger (a)-(d) check:**

- (a) New processing activity using LLM/external API on operator-session-derived data: **No** — disclosure-only change for existing activities.
- (b) Brand-survival threshold `single-user incident`: **No** — threshold is `none` per §User-Brand Impact.
- (c) New cron/workflow reading from `knowledge-base/project/learnings/` or `/specs/`: **No.**
- (d) New artifact distribution surface (plugin update, public PR body, package release): **No** — docs-site re-deploy is the existing publication path; no plugin component count change, no marketplace.json or plugin.json edit.

**Decision:** Skip GDPR gate silently per Phase 2.7. The forward-port reuses canonical disclosures that were themselves authored under the gate at their original-PR plan time (#3486-ish for KB-sharing/push, #3603 for Resend). No re-gating required for plugin-mirror sync.

## Phases

### Phase 0 — Pre-flight

- [x] Verify branch `feat-one-shot-forward-port-plugin-legal-docs-3666` is checked out (already verified at plan time).
- [x] Verify worktree is clean: `git status --short` returns no untracked or modified files outside `knowledge-base/project/{plans,specs}/`.
- [x] Re-fetch canonical heads to confirm no drift between plan time and work time: `git log --oneline -3 -- docs/legal/data-protection-disclosure.md docs/legal/privacy-policy.md docs/legal/gdpr-policy.md`. If a newer canonical commit changed any of the forward-port targets, re-run the Research Reconciliation table.

### Phase 1 — DPD forward-port

- [x] Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`:
  - Insert §2.3(j) bullet (canonical line 100, verbatim) after the `(i)` bullet (plugin line 108).
  - Insert §2.3(k) bullet (canonical line 101, verbatim) after the new `(j)`.
  - Append Resend row (canonical line 156, verbatim) to Web Platform Processors table after Cloudflare row.
  - Extend §4.2 cross-ref line to end at `…2.3(i), 2.3(j), and 2.3(k).` (canonical line 158 exact wording).
- [x] Bump dual Last-Updated lines (hero line 11, body line 21) to `Last Updated May 12, 2026` / `**Last Updated:** May 12, 2026 (forward-ported Web Platform push-notification §2.3(j), Resend transactional-email §2.3(k), Resend processor row in §4.2, and §4.2 cross-ref extension to (j),(k) from canonical per #3666)`.
- [x] Run AC1/AC2/AC3 verification greps; capture output for commit message footer.
- [x] Commit with message `docs(legal): forward-port DPD §2.3(j)/(k) push + Resend, §4.2 Resend row + cross-ref (#3666)`.

### Phase 2 — Privacy Policy forward-port

- [x] Edit `plugins/soleur/docs/pages/legal/privacy-policy.md`:
  - Insert §4.9 Push Notification Subscriptions block (canonical lines 130-142, verbatim, including HTML comment markers) between current §4.8 end (line 137) and current `## 5. Third-Party Services` heading (line 139).
  - Insert §5.9 Resend block (canonical lines 212-220, verbatim) between current §5.8 Cloudflare end (line 205) and current `## 6. Legal Basis for Processing` heading (line 207).
- [x] Bump dual Last-Updated lines (hero line 11, body line 20) to `Last Updated May 12, 2026` / `**Last Updated:** May 12, 2026 (forward-ported §4.9 Push Notification Subscriptions and §5.9 Resend from canonical per #3666)`.
- [x] Run AC4/AC5 verification greps; capture output for commit message footer.
- [x] Commit with message `docs(legal): forward-port Privacy Policy §4.9 push subs + §5.9 Resend (#3666)`.

### Phase 3 — GDPR Policy forward-port

- [x] Edit `plugins/soleur/docs/pages/legal/gdpr-policy.md`:
  - Replace §3.8 region (current lines 102-109 inclusive of HTML comment markers, heading, and two bullets) with canonical §3.8 region (canonical lines 91-100 inclusive of HTML comment markers, heading "Content Sharing (Knowledge Base Document Sharing)", intro paragraph, and two qualified bullets).
  - Edit "ten processing activities" → "eleven processing activities" at current line 293.
  - Append activity #11 KB-sharing item (canonical line 300, verbatim, with HTML comment markers) after plugin's activity #10 (current line 304), before the closing paragraph "The register is maintained internally…" (current line 306).
- [x] Bump dual Last-Updated lines (hero line 12, body line 22) to `Last Updated May 12, 2026` / `**Last Updated:** May 12, 2026 (forward-ported §3.8 KB-sharing canonical body form and §10 Article 30 register activity #11 Web Platform content sharing from canonical per #3666)`.
- [x] Run AC6/AC7/AC8 verification greps + diffs; capture output for commit message footer.
- [x] Commit with message `docs(legal): forward-port GDPR Policy §3.8 KB-sharing form + §10 Article 30 activity #11 (#3666)`.

### Phase 4 — Verification + cross-document audit

- [x] Run all AC greps from the pre-merge checklist; record results.
- [x] Run Eleventy build (AC12): `npm run docs:build` from repo root (verified at plan time: root `package.json` script `"docs:build": "npx @11ty/eleventy"`). Verify the 3 legal pages emit to expected permalinks under `_site/legal/`.
- [x] Invoke legal-compliance-auditor (AC13) scoped to the 3 plugin-mirror files. If P0/P1 findings surface, address inline. Re-run until 0 P0 findings.
- [x] `git diff --name-only main...HEAD -- docs/legal/` returns empty (AC10).

### Phase 5 — PR body + ship

- [ ] Draft PR body:
  - Title: `docs(legal): forward-port plugin-mirror to canonical — KB-sharing + push notifications + Resend (#3666)`
  - `Closes #3666`
  - Summary with reference to PR-C plan AC13 (`knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md:111`) as the originating directive.
  - Row 8 investigation closure: "GDPR §4.2 OAuth provider row was investigated; verified that the row already exists identically in both canonical and plugin mirror — it was forward-ported in a prior PR. No edit was required for this row in #3666."
  - `## Changelog` section per `plugins/soleur/AGENTS.md`: brief one-line description.
  - Label: `semver:patch`, `domain/legal`, `priority/p3-low`.
- [ ] Push branch; mark PR Ready.

## Risks

| # | Severity | Risk | Mitigation |
|---|----------|------|------------|
| R1 | P2 | Canonical drift between plan time (2026-05-12 morning) and work time → forward-ported text diverges from canonical head. | Phase 0 re-fetches canonical heads and re-runs Research Reconciliation table if a newer canonical commit touched the targets. |
| R2 | P2 | Eleventy build breaks on injected HTML comment markers `<!-- Added 2026-04-13: Push notifications -->` (Nunjucks/Eleventy treats some HTML-comment forms specially in `.md` files when nunjucks is the markdown engine). | AC12 catches at build. Mitigation: if break occurs, fall back to a plain `<!-- Push notifications -->` form (drop the date) and document the variance in commit footer. Verify against existing precedent: canonical has the same comment-marker form and ships, so this is unlikely to break. |
| R3 | P3 | legal-compliance-auditor surfaces a previously latent cross-document inconsistency (e.g., Buttondown row, CLA wording, retention dates) that this PR did not introduce. | Per `wg-when-an-audit-identifies-pre-existing` workflow gate: classify as pre-existing, file a follow-up issue, do not expand scope of this PR. |
| R4 | P3 | Forward-ported §3.8 prose drift between plugin (older form) and canonical (richer form) is large enough to warrant separate CLO review beyond auto-carry-forward. | Domain Review section explicitly flags §3.8 as the one sub-row needing attention. If CLO carry-forward is insufficient, escalate to legal-compliance-auditor pre-commit. |
| R5 | P3 | One of the 3 plugin-mirror dual Last-Updated lines is missed (hero or body). | AC9 grep-verifies `Last Updated May 12, 2026` appears exactly 2× per file (hero + body). |
| R6 | P3 | Future canonical edits to §2.3(j)/(k), §4.9, §5.9, §3.8, or §10 activity #11 will once again create asymmetry. | Out of scope for this PR. PR-C learning `2026-03-18-dpd-processor-table-dual-file-sync.md` already addresses the dual-file pattern; consider adding plugin-mirror to PR-C-style atomic-dual-edit precedent in a separate workflow-gate proposal. |

## Sharp Edges

- The HTML comment markers `<!-- Added 2026-04-10: KB sharing -->` / `<!-- End: KB sharing -->` / `<!-- Added 2026-04-13: Push notifications -->` / `<!-- End: Push notifications -->` are **load-bearing for provenance tracking**, not decorative. Preserve them verbatim during forward-port. Stripping them would erase the audit trail that ties the disclosure to its originating PR.
- The plugin-mirror Last-Updated convention requires **two** locations per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`: the hero `<p>Effective February 20, 2026 | Last Updated May 12, 2026</p>` AND the body `**Last Updated:** May 12, 2026 (...)`. Missing either breaks the rendered docs-site display (hero only) or the markdown source (body only). AC9 grep covers both.
- `### 3.8` heading text differs between canonical and plugin: canonical is "Content Sharing (Knowledge Base Document Sharing)" while plugin currently has "Content Sharing". When forward-porting, replace the heading text, not just the body. AC6 diff catches this.
- The §10 register count line is "documents ten/eleven processing activities" — a written-out numeral, not a digit. The grep AC8 looks for the literal word "ten"; if a future edit normalizes to digits ("10 processing activities"), this AC becomes a false negative. Spot-check the actual text after the edit, do not rely solely on grep.
- Row 8 (GDPR §4.2 OAuth provider row) is the **investigation row** — it is documented as no-op but must be explicitly mentioned in the PR body (AC11). Silently dropping it from the PR body would re-orphan the issue's open question.
- `legal-compliance-auditor` may surface cross-document references to "ten activities" elsewhere in the corpus (e.g., a learning file, a brainstorm, an old plan) — these are knowledge-base artifacts, not user-facing legal docs. Do **not** edit knowledge-base or learning files as part of this PR; they preserve historical record per the AGENTS.md retirement-cleanup learning class.
- Plan-prescribed grep AC9 uses `grep -cE 'Last Updated May 12, 2026'` for a count of `2,2,2` — note this is **case-sensitive** by default. If for any reason a touched file uses "Last updated" (lowercase u), the grep returns 0. Verify case-consistency at edit time.

## Out of Scope

- Edits to canonical `docs/legal/*` (this is the inverse-direction forward-port; canonical is source of truth here)
- Edits to other plugin-mirror legal docs (acceptable-use-policy, cookie-policy, disclaimer, terms-and-conditions, *.cla.md)
- New processing-activity disclosures (this is a sync PR, not a new-activity PR)
- DPA re-verification or vendor-contract changes
- Plugin component count changes (no new agents, skills, commands)
- README.md or plugin.json edits
- CHANGELOG.md edits (`semver:patch` will auto-bump; CI handles release at merge)

## Roadmap Reference

Phase: Post-MVP / Later (operational compliance maintenance). No roadmap milestone gate required for documentation-sync work.

## References

- Issue: #3666 — Forward-port canonical-vs-plugin legal-doc backlog (KB sharing + push notifications + Resend + OAuth row)
- Originating PR: #3662 (PR-C of umbrella issue #3603) — Privacy Policy §4.7 refresh + Article 30 register. Verified live 2026-05-12: PR #3662 state=MERGED; issue #3603 state=CLOSED.
- PR-C plan: `knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md` AC13 (line 111)
- Learning: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md` — dual-file sync gap pattern
- Learning: `knowledge-base/project/learnings/2026-03-20-eleventy-mirror-dual-date-locations.md` — dual Last-Updated locations
- Learning: `knowledge-base/project/learnings/2026-03-02-legal-doc-bulk-consistency-fix-pattern.md` — bulk legal-doc consistency pattern
- Learning: `knowledge-base/project/learnings/2026-02-20-dogfood-legal-agents-cross-document-consistency.md` — first-pass auditor finding rate
