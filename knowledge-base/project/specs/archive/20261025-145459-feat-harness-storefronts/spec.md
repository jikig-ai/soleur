---
feature: harness-storefronts
issue: 11035
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/archive/20261025-145459-2026-10-24-harness-storefronts-brainstorm.md
status: no-go
---

# Feature: Do not publish Soleur as an always-on teammate listing

## Problem Statement

The question was whether Soleur should be published so a customer can run it as a Grok Bot, an OpenAI Dot, or a Gemini teammate. The answer is no.

Those products are always-on teammates with a cloud computer and the customer's logins. Soleur's review gates assume an interactive coding session. Packaging the plugin directory does not move those gates onto a bot or a dot. Phase 4 demand measurement is open (#1439, 2 of 10 as of 2026-09-28). The business-validation verdict remains PIVOT.

## Goals

- Record the no-go so a later session does not reopen a listing from a cold start.
- Keep the existing harness adapters as the distribution: Grok Build, Codex, and the Antigravity CLI.
- Leave publisher contracts unaccepted and Jikigai's processor and controller roles unchanged.

## Non-Goals

- A Grok Bot or Cursor marketplace listing.
- An OpenAI app, plugin, or custom-skill pack so a customer's Dot runs these skills.
- A Gemini Agent Gallery listing, a claim under the name "Gemini Duets", or a Claude Duet substitute.
- A new harness adapter, a `.gemini/` tree, or a `Harness` union member.
- A Grok Build catalog pull request.
- Operator dogfood of the founder's own bot.
- A getting-started copy change.
- A publisher account at xAI, OpenAI, or Google.
- Acceptance of Cursor Marketplace Publisher Terms, OpenAI App Developer Terms, or a customer Art. 28 DPA for this surface.
- Any edit to Privacy, the Data Protection Disclosure, or the GDPR Policy that names these vendors as a supported configuration.

## User-Brand Impact

- **Artifact:** a Soleur listing that would act as a customer's always-on teammate on a third-party agent product.
- **Vector:** one founder loses files or credentials, or the teammate sends, pays, commits, or writes legal or finance text without Soleur's review gate.
- **Threshold:** single-user incident

## Functional Requirements

### FR1: No Grok Bot listing

Publish no plugin through the Grok Bot submit form. That form is this operator no-go. Publish no plugin through the Cursor marketplace. ADR-274 already rejects that listing as a separate contract.

### FR2: No OpenAI Dot listing

Publish no OpenAI app or plugin whose purpose is a customer's Dot running Soleur skills. The Codex adapter that already runs inside a Codex session stays as it is.

### FR3: No Gemini teammate claim

Publish no Gemini agent listing. Make no public claim that a Gemini agent runs Soleur. Do not treat Claude Duet as that product. "Gemini Duets" stays an unresolved name.

### FR4: Existing coding-agent distribution stays

Grok Build, Codex, and the Antigravity CLI remain the supported way to run Soleur. This spec does not change those adapters, their manifests, or their docs.

## Technical Requirements

### TR1: Publisher contracts stay unaccepted

Cursor Marketplace Publisher Terms and OpenAI App Developer Terms are not accepted by this spec. No pull request may vendor those click-wraps into the repo as if they had been signed.

### TR2: No new Jikigai processing role

Add no vendor SDK, no environment variable, and no Soleur endpoint whose purpose is executing these skills inside a customer's Grok Bot, Dot, or Gemini agent. The draft CLO ruling (2026-10-24, not legal advice) prohibits the Grok Bot and Dot limb. A Gemini listing is not yet knowable: do not list.

### TR3: Supported-configuration pages stay silent on these vendors

Privacy, the Data Protection Disclosure, and the GDPR Policy move together, with CLO review, before any of these vendors is named as a supported configuration. This spec does not make that edit.

### TR4: Live record stays unarchived

These files stayed on the live path until the operator asked to land the record. `archive-kb.sh` did not move this directory, or the sibling brainstorm, during compound on draft PR #11033. This ship archived both on 2026-10-25. The decision record is the deliverable.

## Verification

- The brainstorm and this spec exist on `feat-harness-storefronts`.
- No file under `plugins/soleur/{codex,cursor,devin,opencode,antigravity}/` changes in the decision commit.
- No `.gemini/` directory is added.
- No publisher-account secret, SDK dependency, or new environment variable is added.
