---
title: "fix(legal): trim DPD §4.2 Resend row Legal-Basis trailing push-subscription clause"
date: 2026-05-12
type: docs-cleanup
lane: procedural
issue: 3671
related_issues: [3666]
related_prs: [3669, 3662]
related_origin_commit: e5fbe668
priority: p3-low
domain: legal
deepened: 2026-05-12
---

## Enhancement Summary

**Deepened on:** 2026-05-12
**Method:** Subagent fan-out unavailable in this environment — applied agent lenses inline (legal-compliance-auditor sharp-edge, code-simplicity, pattern-recognition sibling-bug class scan, kieran convention-check, deepen-plan post-write checklist).
**Sections enhanced:** Acceptance Criteria (AC5/AC6 corrected), Research Insights (sibling-bug scan finding added), Risks (paraphrase-citation fix), frontmatter (issue/PR labeling corrected).

### Key Improvements

1. **AC5/AC6 corrected from expected `1` to expected `2`.** Live grep showed both Buttondown §2.3(e) AND push-subscription §2.3(j) use the `consent (Article 6(1)(a) GDPR)` form — the AC as originally written would have failed false-positive after a correct trim. Caught by Phase 6 "explicit string literals match across plan" check.

2. **Issue-vs-PR citations disambiguated.** #3666 and #3603 are issues (CLOSED); the merged PRs are #3669 (closes #3666) and #3662 (closes #3603) respectively. Several "PR #3666" references in the plan body were paraphrase errors. SHA `e5fbe668` verified live via `git log -1`.

3. **Sibling-bug class scan returned clean.** Pattern-recognition lens applied: only TWO §4.2 rows carry semicolon-split dual-basis (Cloudflare and Resend). Cloudflare's is legitimate (per learning `2026-03-20-cdn-dual-legal-basis-unauthenticated-traffic.md` — authenticated traffic uses contract performance, unauthenticated uses legitimate interest, per PR #912). Resend's was the only orphan. No other rows need editing. This is positive validation that the fix scope is tight and correct.

4. **All cited AGENTS.md rule IDs verified active.** `wg-when-an-audit-identifies-pre-existing`, `wg-use-closes-n-in-pr-body-not-title-to`, and `hr-weigh-every-decision-against-target-user-impact` all match `[id: <id>]` in AGENTS.* sidecars. No fabricated or retired IDs cited.

5. **All gates verified pass.** Phase 4.6 User-Brand Impact section present, threshold `none` valid (no sensitive-path diff per Check 6 regex). Phase 4.5 network-outage trigger absent. GitHub labels (`domain/legal`, `priority/p3-low`, `code-review`) verified live.

### New Considerations Discovered

- The orphan-clause failure mode (mixing per-data-element bases into a per-processor-relationship table cell) has happened exactly once in the DPD's history. The sibling-bug class scan shows the document's authors consistently keep per-element bases in §2.3 prose and per-relationship bases in §4.2 tables. The Resend row was the deviation; after this fix, the convention is uniform.

- A follow-up learning at /ship time may want to capture: "When forward-porting a legal doc that contains a known pre-existing inconsistency flagged by the auditor, the cleanup PR's AC must include the dual-file diff (`diff <(grep '| <row>' file1) <(grep '| <row>' file2)`) to enforce sync." This is already in AC7; the learning would generalize the pattern.

# Plan: fix DPD §4.2 Resend row legal-basis cleanup (#3671)

## Overview

Single-clause string trim in `Section 4.2 — Web Platform Processors`, Resend row, "Legal Basis" column. The trailing `; consent (Article 6(1)(a)) for push subscriptions` clause is orphan content — it describes Supabase-stored push-subscription data (§2.3(j) — endpoint URL, p256dh, auth keys), not the Resend processor (which only handles recipient email addresses + notification content). The clause was introduced as a copy-paste artifact in **PR #3662** (commit `e5fbe668`, which closed issue #3603 — "PR-C legal refresh for cc-soleur-go transcript persistence + DSAR audit") when the §2.3(j) push-notification activity and §2.3(k) Resend transactional-email activity were drafted in the same commit. The misplaced clause was forward-ported to the plugin-mirror by **PR #3669** (which closed issue #3666 — "Forward-port canonical-vs-plugin legal-doc backlog"; the audit deferral lives in that plan's Risks §R3) and now lives in both:

1. `docs/legal/data-protection-disclosure.md:156` (canonical, GitHub-rendered)
2. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md:165` (Eleventy mirror, docs-site-rendered)

This plan trims the clause in both files atomically, bumps both Last-Updated lines (canonical has 1 location; the mirror has 2 — hero `<p>` + body markdown line — per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`), and ships one PR. No schema, code, or API surface is touched. No semantic change to the disclosure: §2.3(j)'s consent basis for push-subscription storage remains correct on the Supabase row, and the Resend row continues to disclose the legitimate-interest basis for transactional-email processing.

## User-Brand Impact

**If this lands broken, the user experiences:** A legal disclosure with an internally inconsistent processor table — Resend (transactional-email-only) is documented as holding a consent basis for push-subscription data that Resend does not process. A user reading §4.2 to understand what data Resend touches would conclude push-subscription endpoints flow to Resend, which is false.

**If this leaks, the user's data/workflow/money is exposed via:** No exposure vector. This is a text-only correction in a published disclosure; the underlying data flows are unchanged.

**Brand-survival threshold:** none

The disclosure is currently accurate in the aggregate (every processing activity is disclosed with a correct legal basis somewhere in the document) — the bug is a misplacement of one clause that an external auditor (or a careful user) could flag as a contradiction. No single-user incident materializes from this text inconsistency.

Per `plugins/soleur/skills/preflight/SKILL.md` Check 6, the `threshold: none` requires a scope-out reason ONLY when the diff touches a sensitive path. This diff touches only `docs/legal/data-protection-disclosure.md` and the mirror — neither matches Check 6 Step 6.1's sensitive-path regex (schemas, migrations, auth, API routes, `.sql`). No scope-out bullet required.

## Research Reconciliation — Spec vs Codebase

Issue body claims and codebase reality, verified at plan-draft time:

| Issue claim | Codebase reality | Plan response |
|-------------|------------------|---------------|
| Canonical `docs/legal/data-protection-disclosure.md:156` carries the offending clause | Verified via `grep -n "Resend" docs/legal/data-protection-disclosure.md` → match on line 156, full clause present | Edit confirmed at line 156 |
| Plugin-mirror `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` mirrors the clause | Verified → match on line 165 (mirror has hero block + frontmatter, shifting line numbers ~9 lines vs canonical) | Edit confirmed at line 165 |
| Push subscriptions live in Supabase (§2.3(j)) and the contract-performance basis for that data lives on the Supabase row | Verified: `§2.3(j)` (canonical line 100, mirror line 109) reads "Legal basis: consent (Article 6(1)(a) GDPR) — subscriptions are created only after explicit browser permission grant". The Supabase row in §4.2 carries "Contract performance (Article 6(1)(b))" for the broader Web Platform DB | Confirms the §4.2 trailing clause is the only place the orphan basis appears. After the trim, the consent basis for push subscriptions remains correctly documented in §2.3(j) (where it semantically belongs); §4.2's row-level basis is the processor-relationship basis (Supabase-as-processor under contract), which is distinct from the per-data-element basis in §2.3(j). No additional edits needed. |
| Origin: PR-C #3662 commit `e5fbe668` | `git log --oneline -- docs/legal/data-protection-disclosure.md` confirms `e5fbe668 docs(legal): PR-C legal refresh for cc-soleur-go transcript persistence + DSAR audit — #3603 (#3662)` is the most recent edit before today, consistent with the issue's origin claim | No action; provenance recorded. |

No spec-vs-codebase divergence detected.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` filtered by `contains("data-protection-disclosure")`, `contains("docs/legal/")`, and `contains("plugins/soleur/docs/pages/legal/")` returns ONLY this issue (#3671). No other open code-review issue touches the files this plan edits.

**Disposition:** None — only self-match.

## Files to Edit

1. `docs/legal/data-protection-disclosure.md`
   - Line 156: trim Resend row "Legal Basis" column.
   - Line 12: bump Last-Updated annotation.

2. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
   - Line 165: trim Resend row "Legal Basis" column.
   - Line 11 (hero `<p>` tag): bump Last-Updated annotation.
   - Line 21 (body `**Last Updated:**` markdown line): bump Last-Updated annotation.

## Files to Create

None.

## Implementation Phases

### Phase 1 — Canonical edit

Edit `docs/legal/data-protection-disclosure.md`:

- Line 156, Resend row, "Legal Basis" column:
  - Before: `Legitimate interest (Article 6(1)(f)) for transactional notifications; consent (Article 6(1)(a)) for push subscriptions`
  - After: `Legitimate interest (Article 6(1)(f)) for transactional notifications`

- Line 12, Last-Updated annotation:
  - Before: `**Last Updated:** May 12, 2026 (added per-message \`usage\` jsonb token-consumption and cost metadata to Section 2.3(i) Web Platform conversation management activity)`
  - After: `**Last Updated:** May 12, 2026 (trimmed Section 4.2 Resend row Legal Basis column to remove misplaced push-subscription consent clause; push-subscription consent basis remains correctly disclosed in §2.3(j))`

  Date stays May 12, 2026 (same day) — the annotation reflects the most recent change. If multiple May 12 edits accumulate, the annotation can be chained or replaced; here we replace the prior annotation cleanly (the §2.3(i) usage-jsonb change is already in git history and remains documented there).

### Phase 2 — Plugin-mirror edit

Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`:

- Line 165, Resend row, "Legal Basis" column: identical trim to Phase 1.

- Line 11 (hero `<p>` tag):
  - Before: `<p>Effective February 20, 2026 | Last Updated May 12, 2026</p>`
  - After: unchanged (same date — the hero displays the date only, not the annotation; nothing to bump)

- Line 21 (body `**Last Updated:**` markdown line):
  - Before: `**Last Updated:** May 12, 2026 (forward-ported Web Platform push-notification §2.3(j), Resend transactional-email §2.3(k), Resend processor row in §4.2, and §4.2 cross-ref extension to (j),(k) from canonical per #3666)`
  - After: `**Last Updated:** May 12, 2026 (trimmed Section 4.2 Resend row Legal Basis column to remove misplaced push-subscription consent clause; cleanup per #3671 of forward-port #3666)`

  Hero `<p>` keeps `Last Updated May 12, 2026` (no colon, no annotation) — the hero is a banner; the annotation lives in the body line per the established convention. Per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`, both the hero AND body lines must be checked even when only the body annotation changes — the hero MAY need bumping if the date itself changes. Here, the date is unchanged (still May 12, 2026), so the hero is untouched.

### Phase 3 — Verification

Run the verification ACs in §Acceptance Criteria. No build is strictly required, but `npx @11ty/eleventy --serve --quiet` on the plugin docs MAY be run as a smoke check that the Eleventy mirror still builds (per `plugins/soleur/skills/deploy-docs/SKILL.md`). This is OPTIONAL because the edit does not change frontmatter, layout, permalink, or any structural shape — only a row-cell string within prose.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — Canonical clause removed:**

    ```bash
    grep -c "consent (Article 6(1)(a)) for push subscriptions" docs/legal/data-protection-disclosure.md
    ```

    Expected: `0` (was: `1` before edit).

2. **AC2 — Mirror clause removed:**

    ```bash
    grep -c "consent (Article 6(1)(a)) for push subscriptions" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
    ```

    Expected: `0` (was: `1` before edit).

3. **AC3 — Canonical Resend row Legal Basis is exactly the trimmed form:**

    ```bash
    grep -c "| Resend Inc.*Legitimate interest (Article 6(1)(f)) for transactional notifications |" docs/legal/data-protection-disclosure.md
    ```

    Expected: `1`.

4. **AC4 — Mirror Resend row Legal Basis is exactly the trimmed form:**

    ```bash
    grep -c "| Resend Inc.*Legitimate interest (Article 6(1)(f)) for transactional notifications |" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
    ```

    Expected: `1`.

5. **AC5 — §2.3(j) push-subscription consent basis untouched (canonical):**

    ```bash
    grep -c "consent (Article 6(1)(a) GDPR)" docs/legal/data-protection-disclosure.md
    ```

    Expected: `2`. Two legitimate occurrences of this exact string exist in §2.3 prose:
    - §2.3(e) Buttondown newsletter (canonical line 95): "The legal basis for email address processing is consent (Article 6(1)(a) GDPR), verified through a double opt-in confirmation email."
    - §2.3(j) push notifications (canonical line 100): "Legal basis: consent (Article 6(1)(a) GDPR) -- subscriptions are created only after explicit browser permission grant."

    Sanity: confirms the trim removed the §4.2 Resend row occurrence (which uses `consent (Article 6(1)(a))` WITHOUT the `GDPR` suffix — note the per-element §2.3 prose ALWAYS includes `GDPR`, while §4.2 table cells DO NOT) WITHOUT stripping either of the two legitimate §2.3 bases. Pre-edit grep count is also `2` (the §4.2 row's no-`GDPR` form is excluded by the regex); the count stays at `2` post-edit because we are only stripping a `(Article 6(1)(a))` (no `GDPR`) occurrence, never a `(Article 6(1)(a) GDPR)` occurrence.

6. **AC6 — §2.3(e) + §2.3(j) consent bases untouched (mirror):**

    ```bash
    grep -c "consent (Article 6(1)(a) GDPR)" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
    ```

    Expected: `2` (mirror lines 104 §2.3(e) + 109 §2.3(j)). Same rationale as AC5.

7. **AC7 — Canonical and mirror Resend rows are bit-identical (modulo whitespace):**

    ```bash
    diff <(grep '| Resend Inc' docs/legal/data-protection-disclosure.md) \
         <(grep '| Resend Inc' plugins/soleur/docs/pages/legal/data-protection-disclosure.md)
    ```

    Expected: empty (zero divergence). The two files are dual-sourced (root for GitHub render, Eleventy for docs site); per `2026-03-18-dpd-processor-table-dual-file-sync.md`, every processor-table change must touch both.

8. **AC8 — Canonical Last-Updated body annotation reflects this change:**

    ```bash
    grep -c "trimmed Section 4.2 Resend row Legal Basis" docs/legal/data-protection-disclosure.md
    ```

    Expected: `1`.

9. **AC9 — Mirror Last-Updated body annotation reflects this change:**

    ```bash
    grep -c "trimmed Section 4.2 Resend row Legal Basis" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
    ```

    Expected: `1`.

10. **AC10 — Hero `<p>` Last-Updated date unchanged (mirror only):**

    ```bash
    grep -cE "Effective February 20, 2026 \| Last Updated May 12, 2026" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
    ```

    Expected: `1`. (Date is unchanged; hero needs no bump.)

11. **AC11 — Both Last-Updated locations in mirror share the same date** (per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`):

    ```bash
    grep -nE "Last Updated[: *]+May 12, 2026" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
    ```

    Expected: 2 matches (hero `<p>` at line 11, body `**Last Updated:**` at line 21). Per learning `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md` §Session Errors #2: this regex tolerates both punctuation forms (hero has no colon, body has `:**`). Using a literal `'Last Updated May 12, 2026'` regex would match only the hero — `[: *]+` covers both shapes.

12. **AC12 — No other `Resend` row in either file** (sanity: the edit did not accidentally produce two Resend rows or break the row structure):

    ```bash
    grep -c "^| Resend Inc" docs/legal/data-protection-disclosure.md
    grep -c "^| Resend Inc" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
    ```

    Each expected: `1`.

13. **AC13 — Eleventy build smoke check (OPTIONAL but recommended for legal docs):**

    From the worktree root, run `cd plugins/soleur/docs && npx @11ty/eleventy --quiet` and confirm exit code `0`. Optional because the edit is row-cell prose only — no frontmatter, layout, permalink, or template change. Skip if Eleventy is unavailable locally; CI will re-run.

14. **AC14 — Commit message follows convention:** `docs(legal): trim DPD §4.2 Resend Legal-Basis column — remove orphan push-subscription clause (#3671)` and PR body uses `Closes #3671`.

### Post-merge (operator)

None. This is a docs edit that goes live the moment it lands on `main` (GitHub renders `docs/legal/` directly; Eleventy build in CI publishes the mirror to GitHub Pages on the next docs-deploy run).

## Domain Review

**Domains relevant:** legal

### Legal (CLO)

**Status:** reviewed (inline, plan-time assessment)
**Assessment:** This is a non-substantive correction. No new processing activity is being disclosed or removed; the §2.3(j) consent basis for push-subscription storage remains correctly disclosed on the Supabase row (which is the actual processor for that data). §4.2's Resend row continues to disclose the only legal basis Resend's processing requires — legitimate interest for transactional email under Article 6(1)(f). The pre-edit state was internally inconsistent (table column claimed Resend held push-subscription consent it does not hold); the post-edit state is consistent and continues to satisfy Article 13/14 GDPR transparency requirements. No new contract, sub-processor disclosure, or breach-notification surface is impacted. No CLO sign-off required for a typo-class trim that improves accuracy; the legal-compliance-auditor that flagged this during the PR #3669 review (which forward-ported the canonical-side clause to the plugin-mirror — issue #3666) has already provided the CLO-equivalent advisory.

No specialist needed beyond the auditor's existing flag.

### Product (CPO)

**Status:** not relevant.

No user-facing UI surface is changed. The disclosure text reaches users only via the docs site; the change is a clarifying correction that removes a contradictory clause. Mechanical escalation check: no new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files are added — tier is **NONE**.

### CTO / Architecture

**Status:** not relevant. No code, schema, migration, infra, or contract surface touched.

### Other domains (CMO / CRO / CFO / CSO / CISO)

**Status:** not relevant. Single-clause docs trim with no marketing, conversion, financial, security, or sales surface implication.

## GDPR / Compliance Gate

This plan edits a GDPR-disclosure document but does NOT touch any of the canonical regex surfaces (`schemas`, `migrations`, `auth flows`, `API routes`, `.sql`). Also reviewing the four expanded triggers:

- **(a) New LLM/external-API processing on operator-session data:** No.
- **(b) Brand-survival threshold `single-user incident`:** No — threshold is `none`.
- **(c) New cron/workflow reading `knowledge-base/project/learnings/` or `specs/`:** No.
- **(d) New artifact distribution surface (plugin update, public PR body, package release):** No new surface — the docs-site mirror is an existing surface, and this edit only corrects a previously-published clause without adding new disclosures.

**Skip the `/soleur:gdpr-gate` invocation.** Plain text correction in a published disclosure that removes a misstatement; gate-fire is not warranted. The legal-compliance-auditor that originally flagged this during PR #3669 review (which closed issue #3666) IS the gate that fired for this class.

## Research Insights

### From `2026-03-18-dpd-processor-table-dual-file-sync.md`

> The DPD's dual-file pattern (Eleventy source for the docs site build, root copy for GitHub rendering) means every structural change must touch both files in the same PR.

Applied to this plan: AC7 enforces bit-identical Resend rows across canonical and mirror.

### From `2026-03-20-eleventy-mirror-dual-date-locations.md`

> When updating "Last Updated" dates on legal documents, the Eleventy mirror files in `plugins/soleur/docs/pages/legal/` contain TWO date locations that must both be changed: a hero `<p>` tag in the HTML wrapper, and a body markdown line.

Applied to this plan: AC10 + AC11 verify both hero and body locations. Date unchanged today (May 12, 2026 stays — both hero and body already read May 12), so neither location needs a date bump; only the body annotation changes to reflect the new edit.

### From `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`

This learning (filed yesterday from PR #3669, the immediate forward-port predecessor of this cleanup) carries two transferable session-error rules:

1. **AC region MUST equal edit-instruction region.** This plan uses targeted `grep -c` over distinguishing substrings — NOT region-replacement awk-diff. So the awk-region trap does not apply here. Sanity check: the `grep -c "| Resend Inc.*"` ACs (AC3, AC4) are line-anchored to the Resend row only; no neighboring section is in scope.

2. **Date-grep ACs spanning hero+body must tolerate both punctuation forms.** Applied to AC11 above: regex is `Last Updated[: *]+May 12, 2026`, matching both `Last Updated May 12, 2026` (hero) and `**Last Updated:** May 12, 2026` (body).

### From issue body & code reality

- The §2.3(j) push-notification activity (canonical line 100, mirror line 109) discloses the consent basis at the data-flow level (subscription endpoint stored on the Web Platform DB after explicit browser permission grant).
- The §4.2 Supabase row carries `Contract performance (Article 6(1)(b))` for the broader Web Platform processing relationship — Supabase is the processor for the database that holds the push subscription, but the per-data-element legal basis lives in §2.3(j).
- The §4.2 Resend row carries `Legitimate interest (Article 6(1)(f))` for transactional notifications — the only basis Resend's processing requires.

This three-way structure (per-activity basis in §2.3, per-processor relationship basis in §4.2) is the established DPD pattern; the orphan clause was the only deviation from it.

### Wrapper-vs-curl / paper-resolution: N/A

No workflow wrapper or CI machinery involved. No FR/AC paper-resolution to police — every AC cites a `grep` invocation against a named file path.

### Sibling-bug class scan (pattern-recognition lens, added at deepen-pass)

Question: are there OTHER §4.2 rows with the same copy-paste contamination pattern (per-data-element basis leaked into a per-processor-relationship cell)?

Scan via `grep -E "^\| .+ \|.+ \|.+ \|.+;.+ \|" docs/legal/data-protection-disclosure.md` (rows whose Legal Basis column contains a semicolon, indicating dual-basis):

- **Cloudflare Inc** (canonical line 155): `Contract performance (Article 6(1)(b)) for authenticated users; legitimate interest (Article 6(1)(f)) for unauthenticated traffic`. **LEGITIMATE.** This is a Cloudflare-specific dual-flow established by PR #912 ("harmonize Cloudflare dual legal basis"), captured in learning `2026-03-20-cdn-dual-legal-basis-unauthenticated-traffic.md`. Authenticated traffic is contractually performed; unauthenticated traffic (anonymous visitors to the marketing site routed through the same proxy zone) is processed on the legitimate-interest basis of running the proxy. Both clauses describe what Cloudflare itself does, on its own row.
- **Resend Inc** (canonical line 156): the orphan being fixed.

**Result: clean.** No other row carries the same failure mode. The DPD's convention is uniform: per-element bases live in §2.3 prose with the `(Article 6(1)(a) GDPR)` form (note `GDPR` suffix), per-processor-relationship bases live in §4.2 table cells with the `(Article 6(1)(a))` form (no `GDPR` suffix). The Resend row was the sole deviation — semicolon-splitting a per-element clause into a §4.2 cell while also mis-attributing the clause's subject (push subscriptions don't flow through Resend). After this fix, the convention is bit-uniform.

### Verified live at deepen-pass

- **PR #3662** (`MERGED`, closed issue #3603): `git log -1 e5fbe668` confirms `docs(legal): PR-C legal refresh for cc-soleur-go transcript persistence + DSAR audit — #3603 (#3662)`.
- **PR #3669** (`MERGED`, closed issue #3666): the forward-port that mirrored the canonical orphan clause into `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.
- **Issue #3666** (`CLOSED`): "Forward-port canonical-vs-plugin legal-doc backlog (KB sharing + push notifications + Resend + OAuth row)".
- **Issue #3603** (`CLOSED`): "hardening: cc-soleur-go transcript persistence — cross-tenant invariants, abort flush, migration affordance, privacy refresh".
- **SHA e5fbe668**: verified.
- **AGENTS.md rule IDs cited** (`wg-when-an-audit-identifies-pre-existing`, `wg-use-closes-n-in-pr-body-not-title-to`, `hr-weigh-every-decision-against-target-user-impact`): all match `[id: <id>]` in AGENTS.* sidecars — none retired, none fabricated.
- **GitHub labels prescribed** (`domain/legal`, `priority/p3-low`, `code-review`): all 3 verified via `gh label list --limit 200 | grep -E "^(<label>)\b"`.

### AC self-consistency check (Phase 6 explicit-strings rule)

Live grep counts against the pre-edit state:

| AC | Expected | Live count (pre-edit) | Expected (post-edit) | Status |
|----|----------|------------------------|----------------------|--------|
| AC1 (canonical clause removed) | 0 | 1 | 0 | ✓ delta of 1 |
| AC2 (mirror clause removed) | 0 | 1 | 0 | ✓ delta of 1 |
| AC3 (canonical trimmed row exists) | 1 | 0 (current row ends with `push subscriptions \|`) | 1 | ✓ delta of 1 |
| AC4 (mirror trimmed row exists) | 1 | 0 | 1 | ✓ delta of 1 |
| AC5 (canonical `(Article 6(1)(a) GDPR)` untouched) | 2 (CORRECTED from 1) | 2 | 2 | ✓ no-change |
| AC6 (mirror `(Article 6(1)(a) GDPR)` untouched) | 2 (CORRECTED from 1) | 2 | 2 | ✓ no-change |
| AC7 (dual-file Resend row diff) | empty | empty (both files share the orphan today) | empty | ✓ stays empty |
| AC8 (canonical Last-Updated annotation) | 1 | 0 | 1 | ✓ delta of 1 |
| AC9 (mirror Last-Updated annotation) | 1 | 0 | 1 | ✓ delta of 1 |
| AC10 (mirror hero date unchanged) | 1 | 1 | 1 | ✓ no-change |
| AC11 (mirror Last-Updated locations match) | 2 | 2 | 2 | ✓ no-change |
| AC12a (canonical `^\| Resend Inc` rows) | 1 | 1 | 1 | ✓ no-change |
| AC12b (mirror `^\| Resend Inc` rows) | 1 | 1 | 1 | ✓ no-change |

All ACs are now consistent with the live state and the expected post-edit state. AC5/AC6 were corrected — pre-deepen they prescribed `1`, which would have failed false-positive (the §2.3(e) Buttondown line also matches the `(Article 6(1)(a) GDPR)` regex).

## Risks

1. **R1 — Forgotten dual-file sync.** Mitigation: AC1+AC2+AC7 explicitly enforce both files share the trim. Per `2026-03-18-dpd-processor-table-dual-file-sync.md`, the dual-file pattern is the most common DPD edit miss.

2. **R2 — §2.3(j) accidentally collateral-damaged by an over-broad `sed`.** Mitigation: edit instructions specify exact `before` / `after` strings on named lines; AC5+AC6 verify the §2.3(j) consent basis survives.

3. **R3 — Hero date forgotten on mirror.** Mitigation: AC10 + AC11 enforce both hero and body locations. (Here, the date is unchanged — but the convention enforcement still applies.)

4. **R4 — Awk-region trap from #3669 learning.** N/A — this plan uses targeted line/substring greps, not region-replacement awk-diffs. Recorded here for completeness because the predecessor PR hit it.

5. **R5 — Last-Updated annotation conflicts with a same-day landed change.** Both files currently carry a May 12 annotation about a DIFFERENT change (canonical: `usage` jsonb in §2.3(i); mirror: forward-port from #3666). Replacing the annotation drops the prior history from the surface line, but the prior changes remain in git history and the relevant section bodies (§2.3(i) for usage, §2.3(k) for the forward-port). This is the established convention — Last-Updated annotates the most recent change, not a running log. Mitigation: AC8 + AC9 verify the new annotation lands; reviewer can confirm prior changes are still represented in git history via `git log -- <file>`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`. (Threshold for this plan: `none` with documented reasoning.)

- The `Last Updated` date stays May 12, 2026 (same calendar day). If the work phase crosses into May 13 UTC before merge, the date MUST be bumped on both hero (mirror) AND body (canonical + mirror) per `2026-03-20-eleventy-mirror-dual-date-locations.md`. The work skill should re-check the date at commit time.

- The §4.2 Resend row sits inside a markdown table. Editing must preserve column count (5 columns: Processor / Processing Activity / Data Processed / Legal Basis / Sub-processor List). Use `Edit` with the exact full-line `before` / `after`; do NOT hand-edit cell-by-cell.

- AC5/AC6 anchor on `(Article 6(1)(a) GDPR)` (note the `GDPR` suffix) specifically because the broader `Article 6(1)(a)` appears in §4.2 rows (Buttondown, the Resend row's pre-trim state, etc.) without the `GDPR` suffix. The §2.3(j) line is the only place the consent basis is annotated with `GDPR` per the per-activity disclosure convention. If a future edit removes the `GDPR` suffix from §2.3(j), AC5/AC6 will silently misfire.

## Test Strategy

No automated tests — this is a docs string edit. Verification is the 14 ACs above. The legal-doc class is verified by:

1. Mechanical `grep -c` ACs (AC1-AC12).
2. OPTIONAL Eleventy build (AC13).
3. Reviewer eyeballing the rendered `_site/legal/data-protection-disclosure/index.html` if the Eleventy build is run locally.

CI's existing docs-build workflow will exercise the Eleventy path on the PR; no test-runner change required.

## Plan Tier

**MINIMAL** — single-file class, single-clause edit, no API surface, no schema, no migration, no new behavior. Two files because of the canonical-vs-mirror dual-source pattern.

## Acceptance / Done

PR merges with:

- All 14 ACs green
- `Closes #3671` in PR body (canonical close on merge; no post-merge operator step)
- Single commit on the branch (or rebased to one) with the conventional title above
- Forward-port consistency preserved (mirror and canonical Resend rows bit-identical)
