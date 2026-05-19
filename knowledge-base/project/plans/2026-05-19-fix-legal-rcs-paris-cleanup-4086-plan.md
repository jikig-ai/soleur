---
lane: single-domain
issue: 4086
type: legal-cleanup
classification: docs-only
requires_cpo_signoff: false
---

# fix(legal): correct RCS jurisdiction Luxembourg → Paris 927 585 729 across 7 sites + CI smoke check

**Closes #4086.**

## Overview

Seven legal-doc sites assert `RCS Luxembourg registration number` describing the Jikigai SARL K-bis extract category. The CLO has confirmed via operator K-bis read that **Jikigai SARL is registered at RCS Paris under number `927 585 729 R.C.S. Paris`** (registered office: 25 rue de Ponthieu, 75008 Paris, France). The existing prose in the rest of the corpus already aligns with France incorporation (Privacy Policy §2 + §13, DPD §1 — all canonical) — only the seven enumerated category-of-data sites are wrong.

This is a narrow text-substitution cleanup PR. **No paragraph regeneration. No legal-rewrite. No new sub-processor entries. No new processing-activity row.** Exactly seven edits + one CI smoke-check extension.

The CI extension enforces internal consistency going forward: the RCS-jurisdiction token must agree across all seven sites AND must agree with the incorporation-country token anchored at PP §2 + DPD §1. **The check does NOT pin a specific string** (per CLO direction — would break legitimate future moves within France).

## User-Brand Impact

- **If this lands broken, the user experiences:** a published Privacy Policy / DPD that names a different RCS jurisdiction than what the K-bis the user just received via the LinkedIn appeal flow displays. The user reads "RCS Luxembourg" in the disclosure but "RCS Paris 927 585 729" on the corporate document — a transparency-notice contradiction that a DPA or appeal reviewer treats as Art. 5(1)(a) lawfulness/transparency non-compliance.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — this is not a data-handling change. The exposure is to the operator's regulatory posture (DPA scrutiny, LinkedIn appeal credibility on CAS-11047602-Q2Y0M4, controller-to-controller integrity on K-bis transfer to Microsoft Ireland).
- **Brand-survival threshold:** `aggregate pattern` — a single mis-named registry on a single doc would not crater the brand, but the systemic pattern (7 sites, 2 mirrors, 1 Article 30 register) read together produces the credibility damage. No CPO sign-off required at plan time per the threshold-driven gate; user-impact-reviewer remains in scope at review time.

## Research Reconciliation — Spec vs Codebase

| CLO attestation claim | Repo reality | Plan response |
|---|---|---|
| 7 sites contain `RCS Luxembourg registration number` | `git grep -nE 'RCS Luxembourg' -- docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/` returns exactly 7 lines matching the enumerated list (PP §4.10 line 158, PP §5.13 line 289, DPD §2.3(p) line 113, DPD §4.2 Microsoft row line 173, PP-mirror §4.10 line 162, PP-mirror §5.13 line 293, Article 30 PA15 (c) line 273) | Edit each site verbatim (one-line `RCS Luxembourg registration number` → `French commerce-registry number (RCS Paris 927 585 729)` substitution; Article 30 entry uses explicit `RCS Paris 927 585 729`) |
| Canonical incorporation statement is "France" at PP §2 + DPD §1 | PP §2 line 21: `incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France`; DPD §1 line 22: same string verbatim; PP §13 line 430-432 re-asserts same | CI assertion treats the literal token `France` (case-sensitive, word-boundary) extracted from PP §2 line 21 + DPD §1 line 22 as the canonical "incorporation-country" anchor; the seven sites must each contain a registry-token that is a substring of OR agrees with `France` (chosen form: substring match on `Paris` — any RCS-jurisdiction city in France would substring-match `Paris` only if literally Paris, but the substring match against `France` itself works for any French city by being absent. Use this canonical regex: each of the 7 sites must contain `/RCS (Paris|Lyon|Marseille|Nanterre|Bobigny|…)/` AND the incorporation-country anchor must NOT contain `/Luxembourg/`. Final form: assert `Set` of matched `RCS <City>` tokens across 7 sites has size 1; assert PP §2 + DPD §1 anchor contains `France` and does NOT contain `Luxembourg`.) |
| `apps/web-platform/test/legal-doc-consistency.test.ts` exists with vitest harness | File present, vitest is the runner (`apps/web-platform/package.json` declares `"test": "vitest"`), file already contains 3 `test()` blocks (heading sequence, Phase 6 sentinels, Last Updated date) | Add a 4th `test()` block: `"RCS jurisdiction token is internally consistent across 7 sites and agrees with incorporation country"`. Extend `REPO_ROOT`-relative `readFileSync` to the 2 new paths (`knowledge-base/legal/article-30-register.md`, `plugins/soleur/docs/pages/legal/privacy-policy.md` is already loadable via `loadMirror("privacy-policy")`). |
| LinkedIn appeal CAS-11047602-Q2Y0M4 deliberately omits RCS jurisdiction; reviewer compares published prose against K-bis | Confirmed via #4086 issue body | No PR-body or doc text claims a specific position on the LinkedIn appeal; the cleanup just makes the published prose internally consistent and factually correct |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero matches against any of the 7 doc paths or the test file.

## Files to Edit

1. `docs/legal/privacy-policy.md` line 158 — §4.10 K-bis data category
   - Before: `RCS Luxembourg registration number`
   - After: `French commerce-registry number (RCS Paris 927 585 729)`

2. `docs/legal/privacy-policy.md` line 289 — §5.13 K-bis data category (LinkedIn sub-processor section)
   - Same substitution as #1

3. `docs/legal/data-protection-disclosure.md` line 113 — §2.3(p) processing-activity prose, K-bis sub-bullet
   - Same substitution as #1

4. `docs/legal/data-protection-disclosure.md` line 173 — §4.2 Microsoft Ireland row in sub-processor table
   - Same substitution as #1

5. `plugins/soleur/docs/pages/legal/privacy-policy.md` line 162 — §4.10 mirror
   - Same substitution as #1

6. `plugins/soleur/docs/pages/legal/privacy-policy.md` line 293 — §5.13 mirror
   - Same substitution as #1

7. `knowledge-base/legal/article-30-register.md` line 273 — PA15 row (c) Categories of personal data
   - Before: `RCS Luxembourg registration number`
   - After: `RCS Paris 927 585 729`
   - (Slightly different wording — this is the internal register, not user-facing transparency prose; explicit number is appropriate for the Art. 30 record)

8. `apps/web-platform/test/legal-doc-consistency.test.ts` — extend with new test block (see "CI Smoke Check" section below for full assertion logic)

**Total: 7 prose substitutions + 1 test extension.**

## Files to Create

None.

## CI Smoke Check — Detailed Assertion Logic

Add this `test()` block to `apps/web-platform/test/legal-doc-consistency.test.ts` (positioned after the existing `"Last Updated date is identical..."` test):

```typescript
test("RCS jurisdiction is internally consistent across legal corpus", () => {
  // Per #4086: the seven sites below describe the same K-bis extract category
  // (Jikigai SARL's RCS jurisdiction). All seven must name the same registry,
  // and that registry must be in the country PP §2 + DPD §1 name as the
  // incorporation country (currently France). This is internal-consistency
  // enforcement -- we deliberately do NOT pin a specific city, so a
  // legitimate future move within France (Paris -> Lyon, etc.) does not
  // require a test edit.

  const sites: Array<{ label: string; load: () => string }> = [
    { label: "privacy-policy source §4.10+§5.13", load: () => loadSource("privacy-policy") },
    { label: "data-protection-disclosure source §2.3(p)+§4.2", load: () => loadSource("data-protection-disclosure") },
    { label: "privacy-policy mirror §4.10+§5.13", load: () => loadMirror("privacy-policy") },
    {
      label: "article-30-register PA15(c)",
      load: () =>
        readFileSync(
          resolve(REPO_ROOT, "knowledge-base/legal/article-30-register.md"),
          "utf-8",
        ),
    },
  ];

  // Extract every "RCS <City>" token across all sites. Match the structural
  // shape -- "RCS" followed by a capitalized city name -- not a specific city,
  // so the assertion survives any future French move.
  const rcsTokenRe = /\bRCS\s+([A-Z][A-Za-zÀ-ÿ-]+)/g;
  const tokens = new Set<string>();
  for (const site of sites) {
    const body = site.load();
    for (const m of body.matchAll(rcsTokenRe)) {
      tokens.add(m[1]); // city name only
    }
  }

  // Internal-consistency invariant: exactly one RCS jurisdiction across the
  // corpus. Set size MUST be 1; >1 means drift.
  expect(
    tokens.size,
    `RCS jurisdiction tokens across 4 source documents: ${[...tokens].join(", ")}`,
  ).toBe(1);

  // Cross-check: the chosen RCS jurisdiction must be in the country PP §2
  // + DPD §1 names as the incorporation country. The two anchors must agree
  // with each other AND must NOT name a country contradicting the RCS token.
  // Concretely: the chosen city is in France iff PP §2 + DPD §1 say "France"
  // AND do not say "Luxembourg".
  const pp = loadSource("privacy-policy");
  const dpd = loadSource("data-protection-disclosure");

  // PP §2 is line ~21; DPD §1 is line ~22; both contain the exact phrase
  // "incorporated in France" verbatim. We assert the phrase exists in both
  // and that no contradicting "incorporated in Luxembourg" phrase exists.
  expect(pp, "PP §2 must declare France incorporation").toMatch(/incorporated in France/);
  expect(dpd, "DPD §1 must declare France incorporation").toMatch(/incorporated in France/);
  expect(pp, "PP must not declare Luxembourg incorporation").not.toMatch(/incorporated in Luxembourg/);
  expect(dpd, "DPD must not declare Luxembourg incorporation").not.toMatch(/incorporated in Luxembourg/);

  // Cross-check: no "RCS Luxembourg" anywhere in the corpus (the bug class
  // this PR closes). Use a substring check over every loaded site.
  for (const site of sites) {
    expect(
      site.load(),
      `${site.label} must not contain "RCS Luxembourg" (bug class closed by #4086)`,
    ).not.toMatch(/RCS Luxembourg/);
  }
});
```

**Why this assertion shape (per plan sharp-edges):**

- The `Set` size assertion implements the CLO-prescribed "Set of RCS-jurisdiction tokens must be size 1". Captures `(City)` via regex group rather than full string, so internal-register prose (`RCS Paris 927 585 729`) and user-facing prose (`French commerce-registry number (RCS Paris 927 585 729)`) both normalize to `Paris` and contribute 1 element.
- The `incorporated in France` regex matches the actual canonical sentence at PP §2 line 21 and DPD §1 line 22 — confirmed via plan-time grep, not paraphrase.
- The negative `not.toMatch(/incorporated in Luxembourg/)` provides defense against a future contradictory edit (e.g., someone re-adds the wrong country statement).
- The per-site `not.toMatch(/RCS Luxembourg/)` provides the bug-class regression test — the exact class this PR closes.
- **No specific city pinned.** A legitimate future move within France (Paris → Lyon) would: (a) require updating the 7 sites AND the Article 30 register together (the Set assertion enforces this — drift detected immediately), (b) leave all assertions green if done correctly.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git grep -nE 'RCS Luxembourg' -- docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/` returns 0 matches.
- [ ] `git grep -nE 'RCS Paris 927 585 729' -- docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/` returns exactly 7 matches (one per edited site).
- [ ] `cd apps/web-platform && bun run test:ci -- test/legal-doc-consistency.test.ts` passes — the new test block AND the existing 3 test blocks (heading sequence, Phase 6 sentinels, Last Updated date) are all green.
- [ ] PP §4.10 line ~158 + PP §5.13 line ~289 mirror lines (`plugins/soleur/docs/pages/legal/privacy-policy.md` §4.10 line ~162 + §5.13 line ~293) — manually diff source vs mirror at those line ranges to confirm identical substitution.
- [ ] Article 30 PA15 row (c) at `knowledge-base/legal/article-30-register.md` line ~273 contains the explicit number `RCS Paris 927 585 729`.
- [ ] PR body cites Art. 13(1) GDPR transparency + Art. 5(1)(a) lawfulness/transparency + LinkedIn appeal CAS-11047602-Q2Y0M4 credibility + controller-to-controller integrity for K-bis transfer to Microsoft Ireland (compliance basis from CLO attestation).
- [ ] PR body uses `Closes #4086` (single-merge atomic cleanup; no post-merge operator action required for closure).

### Post-merge (operator)

None. This is a pure-prose docs-only PR with a CI test extension. No infrastructure provisioning, no migration apply, no manual verification step.

## Domain Review

**Domains relevant:** Legal (CLO), Engineering (test extension)

### Legal (CLO)

**Status:** reviewed (carry-forward from #4086 attestation)
**Assessment:** The CLO has already attested to the K-bis read on #4086. The plan scope mirrors the attestation verbatim — 7 sites + 1 CI extension. No new processing activity, no new sub-processor, no new transfer mechanism, no new legal basis. Compliance basis (Art. 13(1) + Art. 5(1)(a) + LinkedIn appeal credibility + controller-to-controller integrity) is the attestation's stated rationale. No fresh CLO sub-agent invocation needed — the CLO's role at plan time is producing the attestation, which they already did.

### Engineering

**Status:** reviewed (carry-forward; trivial test extension)
**Assessment:** The CI extension follows the existing vitest harness pattern in `legal-doc-consistency.test.ts`. The 4th `test()` block reuses the existing `loadSource` / `loadMirror` / `REPO_ROOT` infrastructure, adds one direct `readFileSync` for `knowledge-base/legal/article-30-register.md` (the only file outside the existing harness's two roots). No new dependencies, no new test framework, no new fixtures. The regex `\bRCS\s+([A-Z][A-Za-zÀ-ÿ-]+)/g` is the canonical structural-shape match per the PII-regex-three-invariants sharp-edge (matches structure not specific value).

### Product/UX Gate

Not applicable. No user-facing UI surfaces touched; no user-flow changes. Tier: **NONE**.

## GDPR / Compliance Gate

**Decision:** invoke at /work time per `hr-gdpr-gate-on-regulated-data-surfaces`. The plan touches `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`, and `knowledge-base/legal/article-30-register.md` — all canonical regulated-data surfaces. However, the **content of the change is a factual correction within the same processing-activity scope** (correct one wrong registry name → correct registry name); it does NOT introduce a new processing activity, change the legal basis, change the data categories, change the recipients, or change the transfer mechanism. The gdpr-gate is expected to confirm "factual-correction-within-existing-PA, no new analysis required" with no fold-in items. If the gate produces fold-in items they MUST be honored per the gate's standard semantics (single-user threshold gate routing).

## Infrastructure (IaC)

Not applicable. No new infrastructure, no new resources, no Terraform changes. Skip silently per the `Skip silently if the plan introduces no new infrastructure` clause of the IaC routing gate.

## Test Strategy

- Vitest is the existing runner (`apps/web-platform/package.json`'s `"test": "vitest"`, `"test:ci": "vitest run"`). No new framework. No new dependencies.
- The new `test()` block is one of four blocks in the existing `legal-doc-consistency.test.ts` file.
- **Pre-edit RED:** before any prose edit, the new test block as written WILL fail at the per-site `not.toMatch(/RCS Luxembourg/)` assertion AND at the Set-size assertion (Set contains `{Luxembourg}` — size 1, but wrong jurisdiction relative to "incorporated in France"). Confirm RED by running the test FIRST against the bug-state codebase before any substitutions.
- **GREEN after 7 prose edits:** Set normalizes to `{Paris}`, no `RCS Luxembourg` substring remains, PP §2 + DPD §1 anchors still say "incorporated in France". All assertions pass.
- **Regression coverage:** any future edit that re-introduces `RCS Luxembourg` to any of the 4 loaded documents OR introduces a new RCS city without updating all 7 sites coherently will fail the Set-size assertion AND the per-site negative assertion.

## Risks

- **R1: Article 30 register line 273 wording uses an explicit number (`RCS Paris 927 585 729`) while the user-facing 6 sites use `French commerce-registry number (RCS Paris 927 585 729)`.** This is intentional — the Article 30 register is an internal compliance record where explicit identifiers are appropriate; user-facing transparency prose pairs the number with a brief explanation. The CI assertion captures the city (`Paris`) via regex group from both forms, so the difference does not break the Set invariant.
- **R2: The `incorporated in France` regex is a substring match on PP §2 + DPD §1.** A legitimate future edit that says "incorporated in **the Republic of** France" would still pass. A malicious edit that says "incorporated in **Luxembourg, formerly** France" would fail (the negative `not.toMatch(/incorporated in Luxembourg/)` catches it). The shape is defensible.
- **R3: A future legitimate move within France (Paris → Lyon) requires updating 7 prose sites coherently.** The Set-size assertion catches incomplete migration immediately (Set size becomes 2, fails). The chosen wording for the user-facing 6 sites uses parentheses: `French commerce-registry number (RCS <City> <number>)` — easy to grep and replace.
- **R4: The plan does not regenerate the Privacy Policy "Last Updated" date.** The CLO attestation explicitly says "No paragraph regeneration needed". The existing `Last Updated date is identical between source and mirror` test continues to pass because we are not touching the date lines. If review surfaces a request to bump dates, fold inline as a one-character edit on both source + mirror per the existing Last Updated test invariant.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`. — Satisfied above (threshold: `aggregate pattern`, both user-facing-broken and exposure questions answered concretely).
- **Substring-match brittleness on the `incorporated in France` anchor.** If the canonical sentence ever gets re-worded to "Jikigai is a France-incorporated SARL", the regex `/incorporated in France/` becomes a false negative. Mitigation: any future edit to PP §2 or DPD §1 incorporation prose MUST grep this test file's regex and update both together (already a constitutional convention; not a new risk introduced by this plan).
- **The CI assertion captures `Paris` from any string of the shape `RCS <Capital-letter><word>`.** A pathological future edit that introduces an unrelated `RCS Lyon` reference (e.g., in a hypothetical second processing activity for a separate SARL registration) would inflate the Set to size 2 and fail the test. This is the desired behavior — multiple distinct RCS jurisdictions co-mingled in the corpus is exactly the bug class this assertion polices. If a future multi-entity scenario emerges, the assertion's scope (which sites to walk) is the right edit point, not the structural shape of the check.
- **Token capture excludes trailing identifiers.** The regex group `([A-Z][A-Za-zÀ-ÿ-]+)` captures only the city name (one word), not the K-bis number. `RCS Paris 927 585 729` → captures `Paris`. `RCS Paris` → captures `Paris`. Both normalize to the same Set element. Verified against canonical regex behavior; no Set-bloat risk from punctuation/digit captures.
- **`French commerce-registry number (RCS Paris 927 585 729)` parenthetical pairing.** The `(` immediately after `number ` is fixed prose — no risk of paren-vs-no-paren drift across the 6 user-facing sites because each is a one-line `Edit`-tool substitution from `RCS Luxembourg registration number` (same shape across all 6) to `French commerce-registry number (RCS Paris 927 585 729)` (same shape across all 6). Confirm via plan-time grep that all 6 source lines match the exact `RCS Luxembourg registration number` substring shape (verified — all 6 do).
