---
title: "chore: remove infrastructure identifiers from public legal documents"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 3
**Research performed:** Completeness audit across all legal documents, cross-document consistency check, T&C pattern alignment verification

### Key Improvements

1. Added completeness verification -- confirmed DPD, Cookie Policy, AUP, CLAs, and Disclaimer are clean of the targeted identifiers
2. Identified and documented additional infrastructure strings (`AES-256-GCM`, `JWT`, `Docker`, `eu-west-1`) that were evaluated and correctly excluded from scope
3. Added cross-document consistency verification step and "Last Updated" date update requirement
4. Added post-change verification for T&C alignment consistency

### New Considerations Discovered

- The GDPR Policy line ~268 also contains `AES-256-GCM` and `Docker containers` -- these are intentionally retained (encryption standard is a security assurance, Docker is ubiquitous)
- The GDPR Policy line ~87 also references Hetzner in Helsinki but already uses the correct pattern ("Hetzner in Helsinki, Finland (EU-only)") -- no change needed
- The "Last Updated" frontmatter in both GDPR Policy and Privacy Policy should be updated to reflect the change date

---

# chore: remove infrastructure identifiers from public legal documents

Security review (#892, found during #736) identified that companion legal documents over-disclose operational infrastructure identifiers. The T&C gets this right ("Hetzner servers in Helsinki, Finland (EU)") but the GDPR Policy and Privacy Policy leak server types, datacenter zone codes, and authentication stack details.

## Changes

Three text replacements across four files (dual-file sync: `docs/legal/` source + `plugins/soleur/docs/pages/legal/` Eleventy copy).

### 1. GDPR Policy -- server type removal

**Files:**
- `docs/legal/gdpr-policy.md` (line ~268)
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` (line ~277)

**Before:** `Hetzner CX33, Helsinki`
**After:** `Hetzner (Helsinki, Finland, EU)`

**Rationale:** `CX33` reveals the exact compute tier (4 vCPU / 8 GB RAM / 160 GB SSD). The replacement preserves the legally required geographic disclosure (EU processing, no international transfer) without exposing the server specification.

### 2. Privacy Policy -- datacenter zone removal

**Files:**
- `docs/legal/privacy-policy.md` (line ~169)
- `plugins/soleur/docs/pages/legal/privacy-policy.md` (line ~178)

**Before:** `Helsinki, Finland (hel1)`
**After:** `Helsinki, Finland (EU)`

**Rationale:** `hel1` is Hetzner's internal datacenter zone identifier. The replacement preserves the EU jurisdictional signal required for GDPR compliance while removing the operational detail.

### 3. GDPR Policy -- authentication stack removal

**Files:**
- `docs/legal/gdpr-policy.md` (line ~266)
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` (line ~275)

**Before:** `hashed passwords (bcrypt via GoTrue)`
**After:** `hashed passwords (managed by Supabase)`

**Rationale:** `bcrypt via GoTrue` reveals the hashing algorithm and authentication service component. The replacement preserves the security assurance (passwords are hashed, managed by the declared sub-processor) without disclosing implementation details.

### Research Insights

**Cross-document consistency audit results:**

The following legal documents were verified clean of the three targeted identifiers (`CX33`, `hel1`, `GoTrue`):

| Document | CX33 | hel1 | GoTrue | Status |
|---|---|---|---|---|
| `terms-and-conditions.md` | clean | clean | clean | Already uses correct pattern |
| `data-protection-disclosure.md` | clean | clean | clean | No matches |
| `cookie-policy.md` | clean | clean | clean | No matches |
| `acceptable-use-policy.md` | clean | clean | clean | No matches |
| `corporate-cla.md` | clean | clean | clean | No matches |
| `individual-cla.md` | clean | clean | clean | No matches |
| `disclaimer.md` | clean | clean | clean | No matches |

**Other infrastructure strings evaluated and excluded:**

| String | Location | Decision | Rationale |
|---|---|---|---|
| `AES-256-GCM` | GDPR Policy line ~87, ~268 | Retain | Encryption standard is a security assurance users benefit from; does not reveal operational attack surface |
| `JWT` | GDPR Policy line ~266 | Retain | Industry-standard protocol name; ubiquitous and does not reveal implementation details |
| `Docker containers` | GDPR Policy line ~268 | Retain | Ubiquitous technology; does not reveal attack surface |
| `eu-west-1` | Privacy Policy, GDPR Policy, DPD | Retain | Always paired with human-readable "Ireland, EU"; AWS region codes are public knowledge; issue #892 only targets `hel1` which lacks the EU qualifier |

**T&C alignment verification:**

The T&C uses two patterns for Hetzner references:
- Line 76: "Hetzner servers in Helsinki, Finland (EU)" -- matches our target
- Line 141: "Hetzner (Helsinki, Finland, EU)" -- exact match for our replacement text

The replacement `Hetzner (Helsinki, Finland, EU)` aligns with the T&C line 141 pattern exactly.

**Dual-file sync considerations (from learning `2026-03-18-dpd-processor-table-dual-file-sync.md`):**

Both file locations must be updated in the same commit. Key differences between locations:
- `docs/legal/`: Has `type`, `jurisdiction`, `generated-date` frontmatter; uses `.md` relative links
- `plugins/soleur/docs/pages/legal/`: Has `layout`, `permalink`, `description` frontmatter; uses `/pages/legal/*.html` absolute links; wrapped in `<section>` HTML tags

For this task, only body text changes -- no link or frontmatter format differences apply. The replacement strings are identical in both locations.

**"Last Updated" date handling:**

Both the GDPR Policy and Privacy Policy have a `**Last Updated:**` line in their frontmatter area. This line should be updated to reflect the current date (2026-03-20) with a brief change description. The date format follows the existing pattern: `March 20, 2026 (removed infrastructure identifiers from processing descriptions)`.

## Acceptance Criteria

- [ ] `Hetzner CX33, Helsinki` replaced with `Hetzner (Helsinki, Finland, EU)` in both GDPR Policy copies
- [ ] `Helsinki, Finland (hel1)` replaced with `Helsinki, Finland (EU)` in both Privacy Policy copies
- [ ] `hashed passwords (bcrypt via GoTrue)` replaced with `hashed passwords (managed by Supabase)` in both GDPR Policy copies
- [ ] No other content changes -- surrounding text remains identical
- [ ] Grep verification: zero matches for `CX33`, `hel1`, and `GoTrue` in `docs/legal/` and `plugins/soleur/docs/pages/legal/`
- [ ] "Last Updated" date in GDPR Policy and Privacy Policy updated to 2026-03-20 in all four files
- [ ] Cross-document consistency: `AES-256-GCM`, `JWT`, `Docker`, `eu-west-1` confirmed intentionally retained (no changes)

## Test Scenarios

- Given the GDPR Policy in `docs/legal/`, when searching for `CX33`, then zero matches are found
- Given the GDPR Policy in `plugins/soleur/docs/pages/legal/`, when searching for `GoTrue`, then zero matches are found
- Given the Privacy Policy in both locations, when searching for `hel1`, then zero matches are found
- Given the GDPR Policy in both locations, when reading the Hetzner hosting entry, then it contains `Hetzner (Helsinki, Finland, EU)` preserving the EU jurisdiction signal
- Given the GDPR Policy in both locations, when reading the Supabase entry, then it contains `hashed passwords (managed by Supabase)` preserving the sub-processor attribution
- Given the GDPR Policy in both locations, when reading the "Last Updated" line, then it reflects the 2026-03-20 date
- Given the Privacy Policy in both locations, when reading the "Last Updated" line, then it reflects the 2026-03-20 date
- Given all legal documents in both locations, when searching for `AES-256-GCM`, then existing matches remain unchanged (intentionally retained)

## Context

- Issue: [#892](https://github.com/jikig-ai/soleur/issues/892)
- Found during: security review for #736
- The T&C already uses the correct pattern: "Hetzner servers in Helsinki, Finland (EU)" -- these changes align companion documents
- Dual-file sync pattern documented in learning `2026-03-18-dpd-processor-table-dual-file-sync.md`
- Bulk consistency pattern documented in learning `2026-03-02-legal-doc-bulk-consistency-fix-pattern.md`

## Scope Exclusions

- Internal documents (`knowledge-base/operations/expenses.md`, `knowledge-base/project/specs/`, `knowledge-base/project/plans/`, `knowledge-base/project/learnings/`) are NOT in scope -- these are private operational records where the infrastructure identifiers serve a legitimate documentation purpose
- No changes to the T&C (already correct)
- No changes to other legal documents (DPD, Cookie Policy, AUP, CLAs, Disclaimer) -- verified no matching strings

## References

- Related issue: [#892](https://github.com/jikig-ai/soleur/issues/892)
- Security review: #736
- T&C reference pattern: `874021b` (commit `chore(legal): update T&C for web platform cloud services`)
