---
name: legal-audit
description: "This skill should be used when auditing existing legal documents for compliance gaps, outdated clauses, missing disclosures, and cross-document consistency. It scans a project for legal documents, invokes the legal-compliance-auditor agent, and displays findings inline. Triggers on \"legal audit\", \"audit privacy policy\", \"check legal compliance\", \"review legal documents\", \"legal-audit\", \"legal benchmark\", \"benchmark legal compliance\", \"regulatory checklist\", \"compare legal documents\"."
---

# Legal Compliance Auditor

Scan a project's existing legal documents and audit them for compliance gaps, outdated clauses, missing disclosures, and cross-document consistency. Findings are displayed inline in the conversation.

## Phase 0: Discovery

Scan the project for existing legal documents. Search common locations:

- `docs/legal/`
- `legal/`
- `pages/legal/`
- Root directory files matching: `terms*`, `privacy*`, `cookie*`, `gdpr*`, `disclaimer*`, `acceptable-use*`, `dpa*`

Use the **Glob tool** with patterns like `**/legal/**/*.md`, `**/privacy*`, `**/terms*`.

Present the discovered documents and use the **AskUserQuestion tool** to confirm scope:

"Found N legal documents. Audit all of them, or select specific files?"

If no legal documents are found, report: "No legal documents found in this project. Use `/legal-generate` to create them."

## Phase 1: Context

Use the **AskUserQuestion tool** to ask which jurisdictions to audit against:

- US
- EU/GDPR
- UK
- Multiple (specify)

Read each document in the confirmed scope.

## Phase 2: Audit

Invoke the `legal-compliance-auditor` agent via the **Task tool** with all documents and jurisdiction context.

If the user's input includes the word `benchmark` (either via `args` parameter or natural language), append the benchmark trigger to the Task prompt. Otherwise, send the standard audit prompt unchanged.

**Standard audit prompt:**

```
Task legal-compliance-auditor: "Audit the following legal documents for [jurisdiction] compliance.

Documents:
[Include full content of each document]

Check each document individually for compliance gaps, then cross-reference all documents for consistency."
```

**Benchmark audit prompt** (append to the standard prompt above):

```
"Additionally, run benchmark mode: check against the GDPR Art 13/14 regulatory disclosure checklist and compare against peer SaaS policies."
```

## Phase 3: Report

<critical_sequence>

Display all findings inline in the conversation. NEVER write audit findings to files -- this is a hard requirement for open-source repositories.

</critical_sequence>

After displaying findings, use the **AskUserQuestion tool**:

- **Fix Critical/High** -- Generate fix suggestions for the most severe findings
- **Done** -- End the audit

If "Fix Critical/High" is selected, present specific text changes the user can apply to address each Critical and High finding. The user applies fixes manually.

## Important Guidelines

- Audit findings are conversation-only -- never persist to files in the repository
- Cross-document consistency checks only run when 2+ documents are in scope
- If a document references another document type that does not exist in the project, flag it as a CRITICAL finding
- Do not modify the audited documents -- only report findings and suggest fixes
