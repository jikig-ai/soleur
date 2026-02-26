# Brainstorm: Contributor License Agreement and IP Assignment

**Date:** 2026-02-26
**Status:** Complete
**Participants:** CLO (legal assessment), repo-research-analyst, learnings-researcher

## What We're Building

A Contributor License Agreement (CLA) system for the Soleur repository that:

- Defines the IP rights Jikigai receives when external contributors submit PRs
- Supports both Individual and Corporate contributor types
- Includes copyright license grant and express patent grant
- Enforces CLA signing automatically via GitHub CLA Assistant before merge
- Updates CONTRIBUTING.md with clear IP and licensing terms

## Why This Approach

### The Problem

Soleur uses BSL 1.1 (source-available, not OSI-approved open source). When someone submits a PR today, there is no mechanism defining what license their contribution is made under. This creates three concrete risks:

1. **Dual licensing fragility:** Jikigai plans to offer commercial licenses. Without a CLA, contributor code cannot be re-licensed under commercial terms -- each contributor retains copyright with at most an implied BSL 1.1 license.
2. **Change-date conversion risk:** BSL 1.1 converts to Apache 2.0 after 4 years. While this is more permissive (low legal risk), the absence of explicit contributor consent creates ambiguity.
3. **Patent exposure:** BSL 1.1 has no express patent grant. A contributor could submit patented code and later assert patents against users.

### Why CLA Over Alternatives

- **DCO (Developer Certificate of Origin):** Does not grant relicensing rights. Insufficient for BSL + dual licensing.
- **IP Assignment (full copyright transfer):** Overkill. May be unenforceable in some EU jurisdictions (France/Germany moral rights). Creates maximum contributor friction.
- **CLA with copyright license grant:** Industry standard for BSL projects (CockroachDB, Elastic, HashiCorp, MariaDB). Grants Jikigai a perpetual, irrevocable license to use, modify, and relicense contributions under any terms. Contributor retains their copyright. Includes express patent grant.

## Key Decisions

1. **CLA type:** Copyright license grant (not assignment). Contributor retains copyright, grants Jikigai broad perpetual license including relicensing rights.
2. **Scope:** Both Individual CLA and Corporate CLA to handle employer-owned IP situations.
3. **Enforcement:** GitHub CLA Assistant (free GitHub App). Automated PR check blocks merge until CLA is signed. One-click signing via GitHub OAuth.
4. **Patent clause:** Express patent grant included in CLA covering contributed code.
5. **Timing:** Implement before first external contribution (one interested contributor exists but hasn't submitted yet). No retroactive signatures needed.
6. **CONTRIBUTING.md update:** Add CLA requirement, link to signing process, plain-language explanation of IP terms.

## Open Questions

1. **CLA text drafting:** The CLA documents are legal instruments requiring professional legal review (same as the existing 7 legal docs marked DRAFT). Should we use Apache ICLA/CCLA as a starting template adapted for BSL, or draft from scratch?
2. **CLA storage:** Where to host the signed CLAs? Options: GitHub CLA Assistant stores signatures, or a separate tracking mechanism. Privacy implications for a public repo.
3. **Org-wide vs. repo-specific:** Should the CLA cover all Jikigai repositories or just Soleur? Org-wide is more future-proof but potentially premature.
4. **Existing legal docs consistency:** All 7 current legal docs are DRAFT. Should this trigger a broader legal review cycle, or should CLA be added independently?

## Context

- **License:** BSL 1.1 (Jikigai, France). Change date: 4 years per version. Change license: Apache 2.0.
- **Existing legal docs:** ToS, Privacy Policy, Cookie Policy, GDPR Policy, AUP, DPA, Disclaimer (all DRAFT).
- **Prior art:** Community contributor audit brainstorm (2026-02-10) discussed community infrastructure but never addressed CLA/IP.
- **Learnings applied:** Dual-location update pattern (docs/legal/ + plugins/soleur/docs/pages/legal/), cross-document consistency audit needed, BSL migration classified as MINOR version bump.
