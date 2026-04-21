---
module: docs-tooling
date: 2026-04-19
problem_type: best_practice
component: markdownlint-cli2
symptoms:
  - "`npx markdownlint-cli2 --fix` rewrites a literal `+` character at the start of an indented prose continuation into `-`, silently converting an intended continuation line into what CommonMark parses as a nested list item"
  - "Original prose `  + \\`terraform_data.X\\` in \\`server.tf\\`` becomes `  - \\`terraform_data.X\\` in \\`server.tf\\`` after --fix, detaching the line from the surrounding bullet"
  - "No MD00X diagnostic is emitted for this transformation — the autofix is lossy"
root_cause: inadequate_documentation
resolution_type: prose_pattern
severity: low
tags: [markdownlint, markdown, prose-conventions, lint-pitfalls]
related_learnings:
  - 2026-04-19-markdownlint-fix-mangles-issue-ref-at-line-start.md
---

# markdownlint --fix silently converts literal `+` continuation to nested list marker

## Problem

Writing a bulleted list with a wrapped continuation that used `+` as a
literal "and" / "plus" glyph:

```markdown
- Do not SSH into the host to "fix" the jail config live -- the fix
  ships through Terraform (`apps/web-platform/infra/fail2ban-sshd.local`
  + `terraform_data.fail2ban_tuning` in `server.tf`). Per AGENTS.md
```

After `npx markdownlint-cli2 --fix`, the `+` became `-`:

```markdown
- Do not SSH into the host to "fix" the jail config live -- the fix
  ships through Terraform (`apps/web-platform/infra/fail2ban-sshd.local`
  - `terraform_data.fail2ban_tuning` in `server.tf`). Per AGENTS.md
```

CommonMark accepts `-`, `+`, and `*` as unordered-list markers. When a
continuation line begins with whitespace and a plus-sign-plus-space in a context where the
parser is already inside a list (the sequence `<indent>+<space>`), the
fixer normalizes the marker to the
first-level marker (`-`), unaware that the author intended a literal
glyph rather than a nested list item. No lint rule reports the
transformation.

## Solution

Rephrase to avoid the leading-`+` token on a wrapped continuation:

```markdown
- Do not SSH into the host to "fix" the jail config live -- the fix
  ships through Terraform: see
  `apps/web-platform/infra/fail2ban-sshd.local` and
  `terraform_data.fail2ban_tuning` in `server.tf`. Per AGENTS.md
```

Alternatives:

- Escape the plus: `\+` (clunky, non-standard).
- Move the `+` mid-line: `... local + terraform_data.X in server.tf`
  (keeps the glyph, avoids the column-0-after-indent position).
- Use "and" / "plus" as prose.

## Key Insight

CommonMark markers (`-`, `+`, `*`) are structural. Any prose that places
one of these characters at the start of an indented line — even as a
literal glyph inside parentheses — is ambiguous to the parser and
subject to silent autofix. Pattern-family with
`cq-prose-issue-ref-line-start` (line-start `#NNNN` parses as heading):
**markdown punctuation at column-0-after-indent is structural, not
literal.**

## Prevention

Add to the mental checklist for any `markdownlint --fix` run on narrative
prose: scan for indented-continuation lines beginning with `-`, `+`, `*`,
or `#` that are not intended as list markers / headings. Reword before
committing.

## Related

- `2026-04-19-markdownlint-fix-mangles-issue-ref-at-line-start.md` — same
  class: line-start CommonMark tokens get structural treatment.
- AGENTS.md `cq-prose-issue-ref-line-start` — narrower rule for `#NNNN`.
