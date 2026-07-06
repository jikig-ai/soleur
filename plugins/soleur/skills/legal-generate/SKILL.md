---
name: legal-generate
description: "This skill should be used when generating draft legal documents for a project or company. It gathers company context interactively, invokes the legal-document-generator agent, and writes markdown output."
---

# Legal Document Generator

Generate draft legal documents from company context. Supports 8 document types across US, EU/GDPR, and UK jurisdictions. All output is marked as a draft requiring professional legal review.

## Supported Document Types

- Terms & Conditions
- Privacy Policy
- Cookie Policy
- GDPR Policy
- Acceptable Use Policy
- Data Processing Agreement
- Data Protection Disclosure
- Disclaimer / Limitation of Liability

## Phase 0: Context Gathering

Use the **AskUserQuestion tool** to gather company context. Ask for:

1. **Company name** (required)
2. **Product/service description** (required) -- what the product does, who it serves
3. **Data practices** -- what user data is collected, how it is processed, stored, shared
4. **Jurisdiction** -- which legal frameworks apply (US, EU/GDPR, UK, or multiple)
5. **Contact information** -- email and/or physical address for legal notices

If the user provides arguments after the skill name (e.g., `/legal-generate privacy-policy`), use that as the document type selection and skip Phase 1.

## Phase 1: Document Selection

Use the **AskUserQuestion tool** to select a document type from the 8 supported types listed above.

## Phase 2: Generation

Invoke the `legal-document-generator` agent via the **Task tool** with the company context and selected document type:

```
Task legal-document-generator: "Generate a [document type] for [company name].
Company: [name]
Product: [description]
Data practices: [practices]
Jurisdiction: [jurisdiction]
Contact: [contact info]"
```

## Phase 2.5: Redaction Gate (BLOCKING — runs BEFORE inline presentation)

A generated legal draft can echo a secret or PII that was passed in as company context (a contact email, an API identifier pasted into a data-practices answer). **Presenting the draft inline in Phase 3 is a transcript write boundary** — the same fail-closed rule the incident skill enforces (`incident/SKILL.md` Phase 6): the sentinel must precede inline-emit, not just file-commit. So the redaction gate runs here, before the operator ever sees the draft.

1. Write the generated draft to a `mktemp` file (do NOT emit it inline yet).
2. Run the shared hardened engine against it. Resolve the path from the repo root — NOT a bare
   `../incident/...` relative path, which depends on the current working directory and, from the wrong
   CWD, exits `127` *outside* the shim (bypassing the shim's fail-closed exit-2 normalization):

   ```bash
   SENTINEL="$(git rev-parse --show-toplevel)/plugins/soleur/skills/incident/scripts/redact-sentinel.sh"
   [[ -r "$SENTINEL" ]] || { echo "legal-generate: redaction sentinel not found — halt (fail closed)"; exit 2; }
   bash "$SENTINEL" <draft-tmpfile>
   ```

   The engine is owned by the `incident` skill and shared cross-skill by relative reference (see ADR-095).

3. Dispatch on the exit code (fail-closed):
   - **exit 0 (clean)** — proceed to Phase 3 and present the draft.
   - **exit 1 (redaction needed)** — print the finding lines (each is meta-redacted; never the full token), revise/redact the offending context, regenerate, and re-run the gate until it exits 0. Do NOT present or write an un-cleared draft.
   - **exit 2 (cannot-evaluate)** — halt. The engine could not run (skill bug, `python3` absent, unreadable tmpfile). Do NOT present or write; surface the error.

No un-scanned draft ever crosses the transcript or lands on disk.

## Phase 3: Output

<decision_gate>

Present the generated document to the user. Use the **AskUserQuestion tool** with options:

- **Accept** -- Write to disk
- **Edit** -- Provide feedback to revise (return to Phase 2 with feedback)
- **Reject** -- Discard and exit

</decision_gate>

On acceptance, write the markdown file to the user-specified path or default `docs/legal/<type>.md` (e.g., `docs/legal/privacy-policy.md`).

Report: "Draft written to `<path>`. This document requires professional legal review before use."

## Important Guidelines

- All generated documents include mandatory DRAFT disclaimers -- do not remove them
- Gather context interactively every time -- do not assume context from previous sessions
- One document type per invocation -- to generate multiple types, run the skill multiple times
- Output format is markdown only -- Eleventy .njk wrapping is out of scope for this skill
- If the user asks for a document type not in the supported list, suggest the closest match or explain that the type is not supported
