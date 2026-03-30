# Tasks: fix(review) - Rate Limit Fallback

## Phase 1: Implementation

### 1.1 Add Rate Limit Fallback section to SKILL.md

- **File:** `plugins/soleur/skills/review/SKILL.md`
- **Action:** Insert new `### 2. Rate Limit Fallback` section after `</conditional_agents>` and before `### 4. Ultra-Thinking Deep Dive Phases`
- **Content:**
  - `<decision_gate>` tag wrapping the detection logic
  - Check: all parallel agent outputs empty or contain rate-limit error indicators
  - If all failed: perform inline review covering security, architecture, performance, simplicity
  - If any succeeded: proceed normally (binary gate, no per-dimension fallback)
  - Note documenting this as expected fallback behavior
  - Note: section renumbering is out of scope (predates this change)

## Phase 2: Validation

### 2.1 Run markdownlint

- **Command:** `npx markdownlint-cli2 --fix plugins/soleur/skills/review/SKILL.md`
- **Gate:** Must pass with zero errors

### 2.2 Verify acceptance criteria

- [ ] "Rate Limit Fallback" section exists in SKILL.md
- [ ] Fallback triggers only when ALL agents fail
- [ ] Inline review covers 4 dimensions
- [ ] Uses `<decision_gate>` XML tag
- [ ] Markdown lint clean
