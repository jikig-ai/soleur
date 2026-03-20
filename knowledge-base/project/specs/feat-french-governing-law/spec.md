# Spec: Change Governing Law from Delaware to France

**Date:** 2026-03-02
**Brainstorm:** [2026-03-02-french-governing-law-brainstorm.md](../../brainstorms/2026-03-02-french-governing-law-brainstorm.md)
**Branch:** feat-french-governing-law

## Problem Statement

Soleur's Terms & Conditions and Disclaimer reference Delaware as the governing law jurisdiction, while the company is incorporated in France. This creates an inconsistency with the CLAs (which already use French law / Paris courts) and misrepresents the company's actual legal domicile.

## Goals

- G1: Replace all Delaware governing law references with French law / Courts of Paris
- G2: Simplify the tiered jurisdiction structure into a uniform French law clause with mandatory-law savings
- G3: Achieve cross-document consistency across the entire legal suite
- G4: Include a 30-day amicable resolution period before court proceedings

## Non-Goals

- Adding governing law clauses to documents that currently lack them (Privacy Policy, GDPR Policy, etc.) -- deferred to follow-up
- Reviewing enforceability of warranty/liability/indemnification clauses under French law -- separate audit
- Introducing ICC arbitration -- unnecessary complexity for a free product

## Functional Requirements

- FR1: T&Cs Section 14 must specify French law and Courts of Paris as default governing law and jurisdiction
- FR2: T&Cs Section 14 must include a 30-day amicable resolution clause before court proceedings
- FR3: T&Cs Section 14 must include a mandatory-law savings clause for EU/EEA consumers
- FR4: Disclaimer Section 8 must mirror the same governing law structure as the T&Cs
- FR5: Both `docs/legal/` and `plugins/soleur/docs/pages/legal/` copies must be updated in sync

## Technical Requirements

- TR1: No residual Delaware references in any legal document after the change (verified via grep)
- TR2: Both file locations must contain identical legal content (different frontmatter is expected)
- TR3: Post-change compliance audit must pass with no cross-document jurisdiction inconsistencies
