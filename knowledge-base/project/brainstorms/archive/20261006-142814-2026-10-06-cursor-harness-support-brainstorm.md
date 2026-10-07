---
date: 2026-10-06
topic: cursor-cli-harness-support
issue: 9608
deferred_issues: [9611, 9610, 9609]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Cursor CLI harness support

In this document, **harness** means a host agent runtime named by the `Harness` union in `plugins/soleur/lib/harness.ts`. The word is not in `knowledge-base/project/glossary.md`. It does not mean a test harness.

## What We're Building

A Soleur plugin the operator installs from this repository and runs in the Cursor CLI. The operator outcome matches Codex, Devin, and Grok Build: `/go` classifies and runs the canonical phases, `/sync` is on the menu, and every other skill and agent is reachable under a `soleur-` name. The canonical skill tree stays the source. Cursor names and agents are generated from it.

Two changes. The first adds the plugin, the names, and the harness arm, and states that hooks do not run. The second ports the full guard set onto the Cursor CLI protocol. The plugin is supported when that second change is green: `/go` classifies, one pipeline skill finishes its gates, one agent spawn runs or is explicitly refused, and the guards fire.

## Why This Approach

Codex, Devin, and Grok are three adapters over one tree (path-shared skills, thin entry shims, and generated Grok agents). Copying any one tree onto Cursor repeats the hand-port ADR-245 retired. Cursor skill names are `[a-z0-9-]+` and share one `/` menu with built-ins. `/go` and `/sync` are free. `/plan`, `/help`, `/review`, and `/shell` are Cursor CLI built-ins (slash-command reference, fetched 2026-10-06), so every other Soleur name is prefixed.

The operator rejected one combined change, and rejected putting a README block in the first change. Two steps keep a first merge from being described as support while hooks are still a copied file that does not fire (ADR-223).

## Key Decisions

- **Runtime:** Cursor CLI only. The editor agent is a later slice. Cloud Agents stay out of this plan.
- **Names:** `/go` and `/sync` stay bare. Everything else is `soleur-` prefixed (`/soleur-help`, `/soleur-plan`, `/soleur-review`, agents such as `/soleur-engineering-cto`). The operator's words: "commands /go and /sync are not prefixed, everything else is prefixed."
- **Hooks:** the full guard set. Step 1 states that hooks do not run. A copied Claude or Devin `hooks.json` must not ship as if it ran.
- **Install:** a setup step adds the plugin from the local path, the same idea as Codex and Devin. A second machine installs from the git repository. No cursor.com marketplace listing.
- **Plan shape:** "Two steps, support only at the end."
- **Public copy:** no README, getting-started, comparison, FAQ, or battlecard sentence in either step. The public install sentence waits until step 2 is green.
- **Legal wording,** when a sentence is written: "a Soleur plugin that runs in Cursor" and "not affiliated with or endorsed by Anysphere." The Terms parenthetical is a Tier 2 PATCH only after `harness.ts` has the arm. No Anysphere processor or DPA row. `soleur:gdpr-gate` stays off unless the plan touches the regulated-path regex or stores a Cursor token.
- **Tree:** no hand-copied skill tree (ADR-245). No second copy of skill `description:` lines (`SKILL_DESCRIPTION_WORD_BUDGET = 2413`). Prefixed names are a Cursor-side map.
- **Closed work:** #6320 and #8299 stay closed.
- **Productize Candidate:** `new-harness-adapter` checklist. Codex, Devin, and Grok already landed as this same class of work. Follow-up issue, not a pivot.
- **Phase 3.55:** skipped. `ui-surface-terms.md` excludes this scope (CLI plugin, instructions, hooks). No pages, components, flows, or email.
- **Milestone:** Post-MVP / Later. Roadmap Phase 4 is founder validation of the cloud product. Phase 5 is the desktop browser-automation app. Neither is this adapter.

## Open Questions

Parked measurements. They are not operator choices.

- The `detectHarness` marker on the Cursor CLI is unmeasured. Do not invent a `CURSOR_*` name. Until it is measured, the session must not be described as recognized.
- The hook envelope, which registries load, and the tool names are unmeasured. Step 2 measures them, then ports the guards. A guard that cannot be shown to fire is not support.
- The wait primitive is unmeasured. Do not copy Devin's poll text or Grok's AwaitShell.
- Whether the plugin `skills` key replaces discovery, adds to it, or dedupes is unmeasured (ADR-224). Do not copy Codex's skills array until that is measured.
- A discovery CI job belongs only if a pinned Cursor CLI can list skills. If it is added: non-required, `continue-on-error`, until a soak (ADR-245).

(out of scope) Cursor IDE editor agent. Deferred issue.

(out of scope) Cloud Agents. Legal prose does not name that path until it is measured.

(out of scope) Public marketplace. Separate contract (BSL-1.1 versus Publisher Terms). Not a deferred ticket.

## User-Brand Impact

- **Artifact:** the Cursor CLI commands the operator types (`/go`, `/sync`, and `soleur-` prefixed skills and agents).
- **Vector:** a partial adapter dead-ends that operator, or a public sentence claims support the product does not keep.
- **Threshold:** single-user incident.
- Tagged **user-brand-critical** (auto, per #5175).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Ship a project-local adapter with one load path and honest refusals. No public sentence until `/go` classifies, one pipeline skill finishes, one agent spawn runs or is refused, and the guards fire. The operator narrowed v1 to the CLI and required the full guard set, in two steps.

### Legal

**Summary:** Draft, not legal advice. An in-repo adapter is the same legal class as Codex, Devin, and Grok: no Anysphere processor row, and marketplace publish is a different contract. The Terms parenthetical is a Tier 2 PATCH only after `harness.ts` has the arm (attestation 8119, 2026-09-13).

### Engineering

**Summary:** Cursor cannot load this plugin unchanged. Add a `Harness` member and a generator (ADR-245), and run `/architecture create 'Add Cursor as a fifth supported harness'` during planning, before implementation. Measure the CLI before any env name, hook binding, or skills-key array. Model tier inherits, as on Codex and Devin.

### Marketing

**Summary:** No public sentence and no comparison, battlecard, getting-started, or README edit in this work. The live FAQ answers Cursor as side-by-side use. After step 2 is green, one FAQ sentence is the only required public correction, and only if the operator still wants a public line.

## Capability Gaps

Checked on `feat-cursor-harness-support` at `ae29dba` (2026-10-06).

- No `cursor` member. `rg -n 'export type Harness' plugins/soleur/lib/harness.ts` returned `export type Harness = "claude" | "grok" | "codex" | "devin" | "unknown";`.
- No plugin, repo config, or instructions. `plugins/soleur/.cursor-plugin`, `.cursor`, and `plugins/soleur/cursor/INSTRUCTIONS.md` are absent, and `git ls-files` of those paths printed nothing.
- No open adapter issue. `gh issue list --repo jikig-ai/soleur --state open --limit 20 --search 'cursor in:title'` returned #9329, #5821, #2057, #1588 (battlecard reminders), #9110 (blog stats), and #3026 (command-center pagination). `gh issue list --search 'cursor adapter'` returned no issues.

## Next Steps

→ Use `/plan` for implementation detail. During planning, create the architecture decision before any product code. Draft PR #9598 is the empty branch only.
