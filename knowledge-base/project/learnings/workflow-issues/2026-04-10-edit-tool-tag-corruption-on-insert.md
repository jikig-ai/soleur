---
module: System
date: 2026-04-10
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Edit tool merged closing tag character with replacement text, producing orphaned < on one line and tag attributes on the next"
  - "QA dev server failed to start due to missing Supabase env vars in Doppler dev config"
root_cause: logic_error
resolution_type: workflow_improvement
severity: low
tags: [edit-tool, tag-corruption, jsx, qa-environment, doppler]
---

# Troubleshooting: Edit Tool Tag Corruption When Inserting JSX Blocks

## Problem

When using the Edit tool to insert a new JSX block before an existing `<a` tag in layout.tsx, the replacement text absorbed the `a` from `<a`, producing `<` on one line and `href=` on the next -- invalid JSX that would fail at compile time.

## Environment

- Module: System (development workflow)
- Affected Component: Edit tool usage in JSX files
- Date: 2026-04-10

## Symptoms

- After Edit, line 157 showed bare `<` instead of `<a`
- The `href` attribute appeared on the next line without a tag name
- Would have caused a Next.js compilation error if not caught

## What Didn't Work

**Direct solution:** The problem was identified immediately by reading the file after the edit and fixed with a follow-up Edit call.

## Session Errors

**Wrong script path for ralph loop setup**
- **Recovery:** Corrected path from `./plugins/soleur/skills/one-shot/scripts/` to `./plugins/soleur/scripts/`
- **Prevention:** The one-shot skill should use a consistent base path variable rather than hardcoding paths.

**Edit tool corrupted `<a` tag during JSX insertion**
- **Recovery:** Read the file after edit, spotted the corruption at line 157, applied a targeted fix
- **Prevention:** When inserting content before an existing tag, include the full opening tag in the `new_string` to avoid the Edit tool merging characters across the boundary. Always read the file after inserting near tag boundaries.

**Architecture review agent rate limited**
- **Recovery:** Proceeded with 3 of 4 review agents (security, simplicity, test design all completed)
- **Prevention:** Unavoidable during high-usage periods. The review skill's rate-limit fallback gate handled this correctly.

**QA dev server failed to start (missing Supabase env vars)**
- **Recovery:** Skipped browser QA scenarios per graceful degradation rules. Unit tests provided coverage.
- **Prevention:** Supabase env vars (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) should be added to the Doppler `dev` config to enable local QA.

## Solution

When the Edit tool inserts a block before an existing tag, ensure the `old_string` captures the full tag being preserved and the `new_string` includes it completely:

```tsx
// WRONG: old_string ends right before the tag character
old_string: "        <div className=\"...\">\n          <a"
new_string: "        <div className=\"...\">\n          {email && <p>...</p>}\n          <"
// Result: <a becomes < on one line, href on next

// RIGHT: old_string includes more context, new_string preserves full tag
old_string: "        {/* Footer links */}\n        <div className=\"...\">\n          <a"
new_string: "        {/* Footer links */}\n        <div className=\"...\">\n          {email && <p>...</p>}\n          <a"
```

## Why This Works

The Edit tool performs string replacement. When the `new_string` ends with a partial tag (`<`), it concatenates with whatever follows in the file. By including the complete tag name in both `old_string` and `new_string`, the replacement preserves the tag integrity.

## Prevention

- After any Edit that inserts content adjacent to HTML/JSX tags, read the surrounding lines to verify tag integrity
- Include complete tags (not partial) in both old_string and new_string boundaries
- Be especially careful with self-closing tags and tags that start immediately after the insertion point

## Related Issues

No related issues documented yet.
