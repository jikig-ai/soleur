---
title: "chore: remove infrastructure identifiers from public legal documents"
type: fix
date: 2026-03-20
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

## Acceptance Criteria

- [ ] `Hetzner CX33, Helsinki` replaced with `Hetzner (Helsinki, Finland, EU)` in both GDPR Policy copies
- [ ] `Helsinki, Finland (hel1)` replaced with `Helsinki, Finland (EU)` in both Privacy Policy copies
- [ ] `hashed passwords (bcrypt via GoTrue)` replaced with `hashed passwords (managed by Supabase)` in both GDPR Policy copies
- [ ] No other content changes -- surrounding text remains identical
- [ ] Grep verification: zero matches for `CX33`, `hel1`, and `GoTrue` in `docs/legal/` and `plugins/soleur/docs/pages/legal/`

## Test Scenarios

- Given the GDPR Policy in `docs/legal/`, when searching for `CX33`, then zero matches are found
- Given the GDPR Policy in `plugins/soleur/docs/pages/legal/`, when searching for `GoTrue`, then zero matches are found
- Given the Privacy Policy in both locations, when searching for `hel1`, then zero matches are found
- Given the GDPR Policy in both locations, when reading the Hetzner hosting entry, then it contains `Hetzner (Helsinki, Finland, EU)` preserving the EU jurisdiction signal
- Given the GDPR Policy in both locations, when reading the Supabase entry, then it contains `hashed passwords (managed by Supabase)` preserving the sub-processor attribution

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
