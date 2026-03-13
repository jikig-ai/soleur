# Support Domain Spec

**Issue:** #266
**Branch:** feat-support-domain
**Date:** 2026-02-22

## Problem Statement

The Soleur plugin's "Company-as-a-Service" positioning requires a complete set of business domains. Support is a recognized gap. The prerequisites that previously blocked this addition (token budget, routing scalability) have been resolved.

## Goals

- G1: Add a Support domain with a CCO domain leader and 1 specialist agent (ticket-triage)
- G2: Move community-manager from Marketing to Support (better organizational fit)
- G3: Enable GitHub Issues triage via `gh` CLI integration
- G4: Maintain token budget under 2,500 words

## Non-Goals

- External helpdesk integration (Zendesk, Intercom, Linear)
- SLA tracking or escalation management
- knowledge-base-curator agent (deferred -- no FAQ content to curate yet)
- Inter-domain-leader disambiguation sentences (not the established convention)

## Functional Requirements

- FR1: CCO agent follows the 3-phase domain leader contract (Assess, Recommend/Delegate, Sharp Edges)
- FR2: ticket-triage agent classifies GitHub issues by severity and routes to correct domain
- FR3: community-manager agent retains existing Discord/GitHub functionality after move
- FR4: Brainstorm Phase 0.5 detects Support-relevant features and offers CCO assessment

## Technical Requirements

- TR1: Agent descriptions fit within remaining token budget headroom (~70 new words)
- TR2: One row added to brainstorm Domain Config table
- TR3: Docs data files updated (agents.js, style.css, skills.js)
- TR4: CMO description and delegation table updated to remove community-manager
- TR5: Triage skill and ticket-triage agent disambiguated
- TR6: Plugin version bumped (MINOR) with CHANGELOG and README updates
