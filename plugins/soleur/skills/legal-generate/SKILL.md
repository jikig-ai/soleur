---
name: legal-generate
description: "This skill should be used when generating draft legal documents for a project or company. It gathers company context interactively, invokes the legal-document-generator agent, and writes markdown output. Triggers on \"legal generate\", \"generate privacy policy\", \"generate terms\", \"create legal documents\", \"draft legal\", \"legal-generate\"."
---

# Legal Document Generator

Generate draft legal documents from company context. Supports 7 document types across US, EU/GDPR, and UK jurisdictions. All output is marked as a draft requiring professional legal review.

## Supported Document Types

- Terms & Conditions
- Privacy Policy
- Cookie Policy
- GDPR Policy
- Acceptable Use Policy
- Data Processing Agreement
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

Use the **AskUserQuestion tool** to select a document type from the 7 supported types listed above.

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
