---
module: System
date: 2026-04-10
problem_type: integration_issue
component: tooling
symptoms:
  - "Playwright browser_click on React Select combobox fails with 'element is outside of the viewport'"
  - "React Select dropdown options not selectable via standard Playwright click even with 2000px viewport"
  - "Downshift combobox fill() does not trigger search filter"
root_cause: config_error
resolution_type: workflow_improvement
severity: medium
tags: [playwright, cloudflare, react-select, downshift, viewport, workaround]
---

# Troubleshooting: Cloudflare Dashboard React Select Comboboxes Unreachable via Playwright

## Problem

When automating Cloudflare API token creation via Playwright MCP, the permission level dropdowns (React Select) and zone resource selectors are consistently reported as "outside of the viewport" even after `scrollIntoViewIfNeeded()` succeeds and the viewport is set to 2000px height.

## Environment

- Module: System-wide (Playwright MCP + Cloudflare Dashboard)
- Affected Component: Cloudflare dashboard API token creation form
- Date: 2026-04-10

## Symptoms

- `browser_click` on React Select `input[aria-label="Permissions levels"]` times out with "element is outside of the viewport"
- Increasing viewport to 2000px does not help — the element is inside an overflow container
- `fill()` on Downshift combobox inputs replaces the value without triggering the search filter
- Zone Resources dropdown opens (`aria-expanded="true"`) but renders zero options

## What Didn't Work

**Attempted Solution 1:** Increase viewport to 2000px height via `browser_resize`

- **Why it failed:** The React Select elements are inside a CSS overflow container within the CF dashboard. The viewport size is irrelevant — the container clips the element.

**Attempted Solution 2:** Click parent container of the React Select input

- **Why it failed:** Clicking the parent div opened the dropdown but the "Read" option was still unreachable via standard Playwright click.

**Attempted Solution 3:** Use `fill()` on Downshift permission combobox

- **Why it failed:** `fill()` sets the input value directly without dispatching character events. Downshift and React Select filter by keystroke events, not input value changes.

## Session Errors

**Playwright browser_click timeout on React Select combobox**

- **Recovery:** Switched to JavaScript `dispatchEvent(mouseDown)` + keyboard navigation
- **Prevention:** When CF dashboard React Select elements are outside the viewport, skip standard click and use JS dispatch from the start

**Downshift combobox fill() silent failure**

- **Recovery:** Used `pressSequentially()` with `slowly: true` to type character by character
- **Prevention:** Always use `pressSequentially` (not `fill`) for Downshift/React Select search inputs — they require keystroke events to trigger filtering

**Zone Resources dropdown rendered zero options**

- **Recovery:** Accepted "All zones" since the account has only one zone
- **Prevention:** Document this as a known limitation; for single-zone accounts, "All zones" is functionally equivalent

## Solution

Two-part workaround:

**For Downshift permission search inputs:** Use `pressSequentially` with character-by-character typing to trigger the search filter, then click the first `[role="option"]` from the listbox.

```javascript
// Type to filter (triggers Downshift search)
await lastPermInput.pressSequentially(permSearch, { delay: 40 });
await page.waitForTimeout(700);
// Click first filtered option
const option = page.locator('[role="listbox"] [role="option"]').first();
await option.click();
```

**For React Select level dropdowns:** Use JavaScript `evaluate` to focus the input and dispatch a `mouseDown` event on the control container, then use keyboard ArrowDown + Enter to select.

```javascript
await page.evaluate(() => {
  const levelInputs = document.querySelectorAll('input[aria-label="Permissions levels"]');
  const lastInput = levelInputs[levelInputs.length - 1];
  lastInput.scrollIntoView({ block: 'center' });
  lastInput.focus();
  const container = lastInput.closest('[class*="ValueContainer"]')
    || lastInput.parentElement.parentElement;
  container.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
});
await page.keyboard.press('ArrowDown');
await page.keyboard.press('Enter');
```

## Why This Works

1. **Downshift** uses `onInputValueChange` which fires on keystroke events. `fill()` sets `value` directly, bypassing the React synthetic event system. `pressSequentially` dispatches individual `keydown`/`keypress`/`keyup` events that Downshift listens to.

2. **React Select** renders its dropdown options in a portal or overflow-hidden container. Playwright's `click()` requires the element to be in the main viewport, but the React Select control container intercepts `mouseDown` events to open the dropdown. Dispatching `mouseDown` via JavaScript bypasses the viewport check entirely. Once the dropdown is open, keyboard navigation works because React Select handles `ArrowDown`/`Enter` on the focused input.

## Prevention

- When automating CF dashboard forms with Playwright, assume React Select elements will be unreachable via standard click. Start with the JS dispatch approach.
- Use `pressSequentially` (not `fill`) for any search/filter input that uses Downshift or React Select.
- For zone-scoped token restrictions on single-zone accounts, accept "All zones" rather than fighting the unresponsive zone selector.

## Related Issues

- See also: [2026-03-21-cloudflare-api-token-permission-editing.md](../2026-03-21-cloudflare-api-token-permission-editing.md)
- See also: [2026-03-25-check-mcp-api-before-playwright.md](../2026-03-25-check-mcp-api-before-playwright.md)
