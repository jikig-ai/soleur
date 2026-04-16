# Learning: Module-scope constants to async state create hidden dependency bugs

## Problem

When refactoring a module-scope constant (`const FLAG = process.env.X === "1"`)
to an async state variable (`const [flag, setFlag] = useState(false)` + fetch),
existing `useEffect` and `useMemo` calls that read the constant without listing
it in their dependency arrays become silently broken.

The module-scope constant was available at its final value before any React
lifecycle ran, so omitting it from `[]` deps was harmless. The async state
starts as `false` and only becomes `true` after a fetch resolves — but effects
with `[]` deps run once at mount (when the value is still `false`) and never
re-run.

## Solution

After converting any module-scope value to React state, grep the file for every
reference to the new state variable and verify each appears in the dependency
array of any `useEffect`, `useMemo`, or `useCallback` that reads it.

Specific fixes in KB layout:

- `useEffect(() => { if (!kbChatFlag) return; ... }, [])` — added `kbChatFlag`
  to deps so sessionStorage restore fires when the flag becomes `true`
- `useMemo(() => ({ enabled: kbChatFlag, ... }), [...])` — added `kbChatFlag`
  to deps so the context value updates when the flag changes

## Key Insight

Module-scope constants are "free" in dependency arrays because they never
change. Async state is not. When migrating from one to the other, every
consumer must be audited for missing deps. React's exhaustive-deps lint rule
catches this, but only if enabled — and the existing code may have had the rule
suppressed or the linter configured to ignore constants.

## Tags

category: logic-errors
module: apps/web-platform
