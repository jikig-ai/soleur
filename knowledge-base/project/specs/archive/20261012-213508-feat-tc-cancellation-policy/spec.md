# Spec: T&C Subscription Cancellation and EU Withdrawal Policy

**Issue:** #893
**Priority:** P3
**Branch:** feat-tc-cancellation-policy
**Brainstorm:** [2026-03-20-tc-cancellation-policy-brainstorm.md](../../brainstorms/2026-03-20-tc-cancellation-policy-brainstorm.md)

## Problem Statement

The T&C references paid subscriptions (Sections 2, 4.3, 13.1b) but contains no subscription lifecycle language — no cancellation terms, no refund policy, no account deletion handling, and no EU withdrawal right compliance. These clauses must exist before paid subscriptions go live.

## Goals

- G1: Users understand how to cancel and what happens when they do
- G2: Comply with EU Consumer Rights Directive 2011/83/EU (14-day withdrawal)
- G3: Protect the company from refund disputes with clear discretionary policy
- G4: Handle account deletion with active subscription gracefully

## Non-Goals

- Checkout UX for EU withdrawal waiver consent (separate issue)
- Billing system implementation
- Pricing tier design

## Functional Requirements

- **FR1:** New Section 5 "Subscriptions, Cancellation, and Refunds" in T&C
- **FR2:** Cancellation clause: cancel takes effect at end of current billing period, access retained through paid period, no refund
- **FR3:** Account deletion clause: deletion with active subscription triggers cancellation at period end, data deleted per privacy policy
- **FR4:** EU withdrawal clause: Art. 16(m) waiver with explicit consent at purchase for immediate access; without consent, access delayed 14 days
- **FR5:** Refund clause: refunds may be issued at company discretion, no automatic entitlement
- **FR6:** Cross-references from Sections 4.3 and 13.1b to new Section 5
- **FR7:** Renumber subsequent sections (current 5-16 become 6-17)

## Technical Requirements

- **TR1:** Update `docs/legal/terms-and-conditions.md` (source) with new section and renumbering
- **TR2:** Update `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy copy) in sync
- **TR3:** Preserve link format differences between source (`.md` relative) and Eleventy copy (`/pages/legal/*.html` absolute)
- **TR4:** Update all internal section cross-references affected by renumbering

## Acceptance Criteria

- [ ] New Section 5 contains all five clause types (cancellation, deletion, EU withdrawal, refund, definitions)
- [ ] All subsequent sections renumbered correctly
- [ ] Cross-references from 4.3 and 13.1b point to new Section 5
- [ ] Both file copies updated and in sync
- [ ] No broken internal links
