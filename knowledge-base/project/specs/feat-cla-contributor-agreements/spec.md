# Spec: Contributor License Agreement System

**Feature:** feat-cla-contributor-agreements
**Date:** 2026-02-26
**Status:** Draft
**Brainstorm:** [2026-02-26-cla-contributor-agreements-brainstorm.md](../../brainstorms/2026-02-26-cla-contributor-agreements-brainstorm.md)

## Problem Statement

Soleur uses BSL 1.1 and plans dual licensing, but has no mechanism defining the IP rights Jikigai receives when external contributors submit PRs. This blocks safe acceptance of external contributions and creates legal risk for commercial licensing.

## Goals

- G1: Establish clear, enforceable IP terms for all external contributions
- G2: Support Jikigai's dual licensing strategy (BSL + commercial)
- G3: Minimize contributor friction while maximizing legal protection
- G4: Automate CLA enforcement so maintainers don't need to manually check

## Non-Goals

- Full copyright transfer / IP assignment (license grant model instead)
- Retroactive CLA coverage for past contributions (none exist yet from external contributors)
- Broader legal doc audit (tracked separately)
- Organization-wide CLA (Soleur-specific for now)

## Functional Requirements

- **FR1:** Individual CLA document covering copyright license grant + patent grant
- **FR2:** Corporate CLA document for employer-authorized contributions
- **FR3:** GitHub CLA Assistant integration that blocks PR merge until CLA is signed
- **FR4:** Updated CONTRIBUTING.md with CLA requirement, signing instructions, and plain-language IP explanation
- **FR5:** Updated PR template with CLA reference
- **FR6:** CLA documents published on docs site (legal section)

## Technical Requirements

- **TR1:** CLA documents stored in `docs/legal/` with dual-location copies in `plugins/soleur/docs/pages/legal/`
- **TR2:** CLA Assistant configured via `.github/workflows/` or GitHub App settings
- **TR3:** Cross-document consistency with existing 7 legal documents (entity name, jurisdiction, contact info)
- **TR4:** DRAFT disclaimer on generated CLA documents (consistent with existing legal docs)
- **TR5:** Version bump (MINOR) for plugin -- legal policy addition

## Acceptance Criteria

- [ ] Individual CLA and Corporate CLA documents exist in both legal doc locations
- [ ] CLA Assistant GitHub Action/App blocks merge on unsigned PRs
- [ ] CONTRIBUTING.md explains CLA requirement with signing link
- [ ] PR template references CLA
- [ ] Plugin version bumped, CHANGELOG updated
- [ ] Cross-document consistency verified (entity name, jurisdiction, contact)
