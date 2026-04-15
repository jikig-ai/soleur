# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-04-14-fix-tagging-ux-enter-key-plan.md
- Status: complete

### Errors

None

### Decisions

- Root cause: React `onKeyDown` on textarea fires before `document.addEventListener("keydown")` in the dropdown -- deterministic ordering, not a race condition
- Fix approach: Add `atMentionVisible` prop to `ChatInput` to suppress Enter-to-send when dropdown is visible
- WAI-ARIA compliance: Fix aligns with W3C Combobox pattern where Enter on input selects active option when popup is open
- Deferred a11y improvements: `aria-expanded`, `aria-activedescendant`, Tab key handling documented as separate issues
- Template: MINIMAL -- focused bug fix with clear acceptance criteria

### Components Invoked

- soleur:plan
- soleur:deepen-plan
- Context7 MCP (React.dev, WAI-ARIA APG)
- Vercel React Best Practices skill
- markdownlint-cli2
