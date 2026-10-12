# Non-Technical Founder Voice

**Date:** 2026-03-29
**Status:** Approved
**Issue:** #1004

## What We're Building

Dual-register voice system for Soleur: keep the technical builder voice for engineering channels (HN, GitHub, Discord), add a parallel "general" register for non-technical founders on the website, LinkedIn, X/Twitter, and onboarding content. Plus an `--audience` flag for the content-writer skill.

## Why This Approach

The brand guide speaks exclusively to technical builders. The content-writer skill has no mechanism to vary voice by audience. Business validation confirmed non-technical founders want Soleur but hit "this isn't for me" at every touchpoint. The ICP was annotated for softening but never rewritten.

The fix is not "make everything less technical" — it's "add a second register while preserving the technical voice where it belongs."

## Key Decisions

### Decision 1: Dual thesis framing

Keep "It's an engineering problem. We're solving it." for technical channels. Add a parallel thesis for non-technical channels (e.g., "Running a company alone shouldn't mean doing everything alone." or "It's a capacity problem. We're solving it.").

### Decision 2: "Non-technical" covers both sub-segments

The general register targets anyone who isn't a developer — from "uses ChatGPT but not CLI" to "completely non-technical business founders." One register, written for the least technical reader.

### Decision 3: Content-writer gets --audience flag

Add `--audience` parameter (`technical` | `general`, defaults to channel-appropriate). Phase 2 reads audience-specific voice rules from brand guide. Adjusts vocabulary, explanation depth, and proof point selection.

### Decision 4: Fold into #1004

This work is incorporated into the existing brand guide review issue (#1004) as additional acceptance criteria, not a separate issue.

## Scope of Changes

### Brand guide updates

- Add "Non-Technical Founder" row to Tone Spectrum table
- Add parallel thesis for non-technical channels
- Add audience-segmented example phrases (technical vs. general)
- Add "Who is Soleur for?" section with explicit segments
- Add business-outcome proof points for general register (e.g., "saves 15 hours/week on marketing, legal, and ops" vs. "420+ merged PRs")
- Define plain-language glossary for key terms (agents, skills, knowledge base, compounding)

### Content-writer skill updates

- Add `--audience` parameter (`technical` | `general`)
- Read audience-specific voice rules from brand guide
- Adjust vocabulary density, explanation depth, proof point selection

### Marketing strategy ICP

- Rewrite the annotated-but-never-updated ICP to reflect both segments

## Open Questions

None — design approved.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Marketing (CMO)

**Summary:** The gap is validated by user research. The brand guide has one register (technical builder). The content-writer skill has no audience parameter. The CMO recommends dual-register approach: add a second voice register for non-technical founders while preserving the technical voice for engineering channels. Five key tensions identified: identity vs. accessibility, beachhead vs. expansion, channel appropriateness, thesis framing, and content-writer skill architecture. Website landing page copy changes should involve conversion-optimizer for layout review.
