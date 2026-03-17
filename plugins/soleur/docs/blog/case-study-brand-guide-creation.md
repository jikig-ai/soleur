---
title: "From Scattered Positioning to a Full Brand Guide in Two Sessions"
date: 2026-03-10
description: "Soleur had informal positioning scattered across READMEs and commit messages. An interactive brand workshop produced a complete brand guide -- identity, voice, visual direction, and channel guidelines."
tags:
  - case-study
  - marketing
  - brand
  - company-as-a-service
---

Soleur had strong informal positioning language scattered across READMEs and commit messages -- "Company-as-a-Service," "infinite leverage," "soloentrepreneurs" -- but nothing formalized. No brand guide, no defined voice, no color palette, no typography system, no channel-specific tone guidelines. The README used marketing language that had never been tested against a framework. Without a brand guide, every piece of outbound content (Discord announcements, GitHub PR descriptions, documentation site copy, legal document tone) was a one-off decision, and consistency was accidental.

## The AI Approach

The brand was built through a multi-phase workflow using the marketing domain:

1. **Brand Architect Workshop** (2026-02-12): The `brand-architect` agent ran an interactive workshop covering mission, vision, positioning, voice, messaging pillars, and visual direction. This was not a template fill-in -- it was a structured conversation that produced decisions documented in a brainstorm.

2. **Visual Identity Exploration** (2026-02-13): Four distinct visual concepts were developed and evaluated -- Solar Forge (gold on dark, serif headlines), First Light (warm off-white, gradient), Stellar (deep blue, violet), and Solaris (amber gradient, geometric). Each was assessed against the brand positioning, competitive differentiation, and practical constraints. Solar Forge was selected for its alignment with the Tesla/SpaceX audacity positioning and its deliberate departure from the rounded-corner, pastel-gradient aesthetic of every other dev tool.

3. **Brand Guide Formalization**: The decisions were consolidated into a single structured document that became the source of truth.

4. **Voice Reviewer Integration**: The `brand-voice-reviewer` agent was created to audit outbound content against the guide before publishing.

## The Result

A 1,293-word brand guide covering:

- **Identity**: Mission statement, target audience definition, positioning ("not a copilot, not an assistant -- a full AI organization"), tagline ("The Company-as-a-Service Platform"), thesis statement.
- **Voice**: Brand voice definition (ambitious-inspiring), tone spectrum table across 5 contexts (marketing hero, product announcements, technical docs, community, error messages), do's and don'ts list with 7 directives each, example phrases for announcements, product descriptions, community replies, and system messages.
- **Visual Direction**: 9-color palette with hex values and usage roles (Solar Forge direction), 5-row typography system (Cormorant Garamond for headlines, Inter for UI, JetBrains Mono for code), style rules (sharp corners, no stock photos, subtle motion, generous whitespace).
- **Channel Notes**: Specific guidelines for Discord, GitHub, and website/landing page -- including structural patterns (hero pattern, section pattern, footer tagline).

The guide has been reviewed twice (last reviewed 2026-03-02) and governs all content across the project.

## The Cost Comparison

A brand strategy agency charges $5,000-15,000 for a brand guide of this scope. The low end covers a basic positioning workshop and style guide; the high end includes visual identity exploration with multiple concepts, channel-specific guidelines, and a tone of voice framework. Timeline is typically 4-8 weeks including discovery sessions, concept presentations, and revision rounds. A freelance brand strategist charges $2,000-5,000 for a lighter version. The AI-produced guide was created across two brainstorm sessions and a formalization step, with ongoing review cycles built into the system.

## The Compound Effect

The brand guide is the single most referenced document in the knowledge base. The legal documents use its voice guidelines. The documentation site implements its color palette, typography, and layout patterns. Discord announcements are reviewed against its tone spectrum. The competitive intelligence report's positioning recommendations reference it. The `brand-voice-reviewer` agent uses it as a runtime reference for content audits. Every new document or public-facing artifact inherits consistency from this one artifact without requiring the founder to remember or enforce brand rules manually. The 100th piece of content is as on-brand as the 1st.

## Frequently Asked Questions

<details>
<summary>Can AI create a brand guide?</summary>

Yes. Soleur's brand-architect agent runs an interactive workshop covering mission, vision, positioning, voice, visual direction, and channel guidelines. The output is a structured brand guide document — not a template fill-in but a set of decisions from a guided conversation.

</details>

<details>
<summary>How long does AI brand guide creation take?</summary>

The brand guide was produced across two brainstorm sessions and a formalization step. A traditional brand agency takes 4–8 weeks for the same scope. The AI-produced guide includes identity, voice, visual direction, and channel-specific guidelines.

</details>

<details>
<summary>Who is AI brand guide creation for?</summary>

Solo founders and small teams who need professional brand consistency without hiring a brand agency. The brand guide becomes the single source of truth that governs all content — legal documents, documentation, Discord announcements, and marketing copy.

</details>

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Can AI create a brand guide?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. Soleur's brand-architect agent runs an interactive workshop covering mission, vision, positioning, voice, visual direction, and channel guidelines. The output is a structured brand guide document — not a template fill-in but a set of decisions from a guided conversation."
      }
    },
    {
      "@type": "Question",
      "name": "How long does AI brand guide creation take?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The brand guide was produced across two brainstorm sessions and a formalization step. A traditional brand agency takes 4–8 weeks for the same scope. The AI-produced guide includes identity, voice, visual direction, and channel-specific guidelines."
      }
    },
    {
      "@type": "Question",
      "name": "Who is AI brand guide creation for?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Solo founders and small teams who need professional brand consistency without hiring a brand agency. The brand guide becomes the single source of truth that governs all content — legal documents, documentation, Discord announcements, and marketing copy."
      }
    }
  ]
}
</script>
