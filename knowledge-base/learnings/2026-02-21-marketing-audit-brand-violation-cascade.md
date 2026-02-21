# Marketing Audit: Brand Violation Cascade Patterns

Date: 2026-02-21
Type: learning
Feature: feat-marketing-audit

## Problem

A comprehensive marketing audit of soleur.ai and the GitHub repository (CMO agent, 20+ gaps identified) required fixing brand voice violations across 15+ files. What appeared to be isolated fixes turned out to be cascading -- a single prohibited term appeared in 10+ locations across docs, legal, commands, and knowledge-base. The brand guide existed but contained no enforcement mechanism at file creation time.

Several discoveries mid-implementation expanded scope beyond the original plan and revealed structural gaps in how the codebase manages brand consistency, counts, and legal document locations.

## Solution

### 1. Brand violations cascade -- plan for full surface coverage

A single prohibited term ("AI-powered") was found in 10+ files: docs pages, legal documents, commands, SKILL.md files, and knowledge-base entries. Fixing one file does not complete the work. When auditing brand compliance, treat it as a whole-codebase grep exercise first, not a file-by-file review.

Rule: Before starting brand fixes, run a grep for each prohibited term across the full repo. List all affected files at the start. This prevents mid-implementation scope surprises.

### 2. Legal docs have dual locations -- both must move together

Legal documents exist in two locations:
- `docs/legal/` -- root-level copies (used by the worktree during development)
- `plugins/soleur/docs/pages/legal/` -- Eleventy source files, compiled into the site

Both must be updated in sync. Editing only the Eleventy source leaves stale content in the root copies (and vice versa).

### 3. Term bans need boundary exception rules

The word "plugin" appears in legitimate contexts: CLI commands (`claude plugin install`), legal defined terms ("the Plugin"), and technical installation docs. A blanket prohibition breaks these cases. When adding a prohibited term to a brand guide, always write the exception rule at the same time as the prohibition.

### 4. Component counts drift silently across multiple files

Counts for agents and skills were stale in 8+ files. There is no automated mechanism to propagate count updates. Mitigation: Keep counts in one canonical location and reference them by description in prose-heavy files like legal docs.

### 5. SpecFlow analysis expands scope -- this is expected and valuable

SpecFlow found 5 additional violation files and identified a legal-analytics conflict: privacy policies stated "no analytics" while Plausible was planned. Catching contradictions before shipping legal documents is high-value.

### 6. Vision content belongs on the website, not the README

Cold visitors on GitHub read READMEs for install instructions -- not brand vision. Moving the 42-line manifesto to a /vision page improved both the README (under 80 lines) and the website (richer content).

## Key Insight

Brand enforcement is a codebase-wide grep problem, not a document review problem. The dual-location legal doc pattern and silent count drift are both instances of redundant copies of truth with no sync mechanism. Reducing redundancy is more durable than better auditing.

## Tags

brand, audit, marketing, legal, documentation, drift, enforcement, specflow, README, counts
