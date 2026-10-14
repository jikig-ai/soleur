# Spec: Update "What Is Company-as-a-Service?" Blog Post

## Problem Statement

The published CaaS category-defining article contains "first CaaS platform" claims that may be contested after Polsia's emergence, and lacks acknowledgment of the autonomous vs. founder-in-the-loop philosophical split that is Soleur's key differentiator.

## Goals

- G1: Remove or soften chronological "first" claims that risk being inaccurate or appearing unaware
- G2: Introduce the autonomous vs. founder-in-the-loop distinction as a category observation
- G3: Acknowledge CaaS category validation by multiple entrants (strengthens the thesis)
- G4: Maintain the article's evergreen, educational tone

## Non-Goals

- Naming specific competitors (Polsia, SoloCEO, Tanka) in the article
- Adding a competitors section or comparison table of CaaS providers
- Writing a separate comparison blog post (future work)
- Rewriting the article structure or tone

## Functional Requirements

- FR1: Reword "the first platform built on this model" (line 13) to remove chronological claim
- FR2: Reword FAQ answer "Soleur is the first company-as-a-service platform" (line 159) to describe approach without claiming exclusivity
- FR3: Add 1-2 sentences about the philosophical split (autonomous vs. founder-in-the-loop) in or near the "How Company-as-a-Service Works" section
- FR4: Add 1-2 sentences in "The Future of Company-as-a-Service" section acknowledging category validation
- FR5: Update the CaaS row in the comparison table to hint at philosophical variants

## Technical Requirements

- TR1: All edits must preserve existing Eleventy frontmatter pattern (title, description, date, tags only)
- TR2: All edits must pass the citation verification rule -- no new statistics without linked sources
- TR3: JSON-LD FAQ schema must be updated if FAQ answer text changes
- TR4: Keyword density for "company-as-a-service" must remain at 0.3-0.4% (~8-12 mentions in ~3,000 words)
