---
title: "feat: Copy-all-to-clipboard button for the debug stream panel"
type: enhancement
branch: feat-one-shot-debug-stream-copy-button
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-12
---

# ✨ feat: Copy-all-to-clipboard button for the debug stream panel

## Overview

Add a single "Copy" control to the header row of the debug stream panel
(`apps/web-platform/components/chat/debug-stream-panel.tsx`) that serializes all
currently-rendered debug events to text and writes them to the clipboard. This is
a convenience affordance for the Soleur team reading the harness instruction
stream — it preserves the panel's existing READ-ONLY, team-only, ephemeral
semantics and adds no new data surface.

**The single load-bearing security invariant:** the copied text MUST be the
REDACTED body via `redactCommandForDisplay(event.body)` — the exact dual-gate the
render path already applies at `debug-stream-panel.tsx:57`. Copying raw
`event.body` would leak to the clipboard the secrets the UI deliberately
withholds on screen. Withheld events (body starts with `WITHHELD_PREFIX`,
`"[input withheld"`) are already placeholders and copy as-is (their
`redactCommandForDisplay` output is the placeholder text itself, unchanged).

**Scope is this one UI affordance ONLY.** The broader session resume / reconnect
architecture work is deferred to issue #5240 and is explicitly OUT OF SCOPE — no
edits to `server/`, `ws-handler`, `agent-runner`, reconnect logic, or the chat
state machine.

## Premise Validation

- **Cited issue #5240** (deferred reconnect work): out-of-scope by construction;
  this plan must not touch it. Not validating its state — it is a deferral
  boundary, not a dependency. No `gh` probe needed.
- **Cited file `apps/web-platform/components/chat/debug-stream-panel.tsx`**:
  confirmed present, read in full. Header toggle button is a single `<button>` at
  lines 129–154; `redactCommandForDisplay` import at line 4 and render use at
  line 57; `KIND_LABEL` at lines 36–40; `WITHHELD_PREFIX` at line 29 — all
  verified against the live file (line numbers were approximate in the brief and
  are now exact).
- **Cited symbol `redactCommandForDisplay`**: confirmed exported from
  `apps/web-platform/lib/safety/redaction-allowlist.ts:212` with signature
  `(command: string): string`; returns `""` for empty/non-string input.
- **Repo-capability claim (my own):** the existing test file
  `apps/web-platform/test/components/debug-stream-panel.test.tsx` EXISTS — this
  plan EXTENDS it, it does NOT create a new test file. Verified via
  `git ls-files`. A co-located `components/**/*.test.tsx` would be silently
  skipped (vitest jsdom `include` is `test/**/*.test.tsx` only).
- No other external premises to validate.

## Research Reconciliation — Spec vs. Codebase

The brief's line numbers were approximate; reconciled against the live file. No
spec file exists for this branch (`knowledge-base/project/specs/feat-one-shot-debug-stream-copy-button/`
is empty) — plan is the source of truth.

| Brief claim | Reality | Plan response |
|---|---|---|
| "button at ~lines 129-154" | Header `<button>` is exactly lines 129–154 | Place Copy as a SIBLING in the header row (see below) |
| "redactCommandForDisplay at line 57" | Confirmed: `DebugEventRow` redacts at line 57 | Serializer reuses the same call |
| "add a vitest+RTL test (co-located per repo convention)" | Repo convention for web-platform is **`test/**/*.test.tsx`**, NOT co-located; a `debug-stream-panel.test.tsx` already exists there | EXTEND the existing test file; do NOT co-locate |

## User-Brand Impact

**If this lands broken, the user experiences:** a "Copy" button that copies
nothing, copies the wrong/stale set, or — the failure that matters — copies the
RAW unredacted event bodies, placing API keys / tokens / secrets onto the
operator's system clipboard where any subsequent paste (a chat message, a
bug report, a screenshot tool's clipboard history) can exfiltrate them.

**If this leaks, the user's data is exposed via:** the system clipboard. The
debug stream is a Soleur-team-only diagnostic surface that intentionally redacts
secrets on screen; a copy path that bypasses `redactCommandForDisplay` reintroduces
exactly the leak the on-screen dual-gate was built to prevent. The clipboard then
propagates the secret out of the controlled render surface entirely.

**Brand-survival threshold:** single-user incident — one operator copying one
unredacted secret to their clipboard and pasting it anywhere is a credential-leak
incident. The redaction-parity invariant is the whole point of this feature; it is
not polish.

> **CPO sign-off required at plan time before `/work` begins.** The brand-survival
> threshold is `single-user incident`. CPO has been assessed in the Domain Review
> (Product/UX Gate). `user-impact-reviewer` will be invoked at review-time per the
> review skill's conditional-agent block.

## Implementation Phases

### Phase 1 — Serializer (pure function, testable in isolation)

Add a pure module-level helper in `debug-stream-panel.tsx` (above the component),
exported for direct unit testing:

```tsx
// debug-stream-panel.tsx (new, module scope)
// Serialize all events to clipboard text using the SAME redaction the render
// path applies (debug-stream-panel.tsx:57). NEVER serialize raw event.body —
// that would leak to the clipboard the secrets the UI withholds on screen.
// Withheld bodies ("[input withheld…") are already placeholders;
// redactCommandForDisplay returns them unchanged, so they copy as-is.
export function serializeDebugEvents(events: ChatDebugEventMessage[]): string {
  return events
    .map((event) => {
      const header = event.label
        ? `${KIND_LABEL[event.debugKind]} · ${event.label}`
        : KIND_LABEL[event.debugKind];
      const body = redactCommandForDisplay(event.body); // dual-gate, NOT raw
      return body ? `${header}\n${body}` : header;
    })
    .join("\n\n");
}
```

- Reuses `KIND_LABEL` (`tool` / `reasoning` / `result`), the optional `event.label`,
  and `redactCommandForDisplay` already in scope — no new imports.
- `redactCommandForDisplay` returns `""` for empty bodies (e.g. a `result` with no
  body); the `body ? … : header` guard mirrors the render path's `{body && …}` so
  an empty body emits just the header line, no dangling blank line.

### Phase 2 — Clipboard write with transient state + fallback

Inside `DebugStreamPanel`, add `const [copied, setCopied] = useState(false);` and a
`copyAll` handler modeled on the `share-popover.tsx:133-142` precedent (transient
2s "Copied" state, try/catch on the promise):

```tsx
const copyTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

const copyAll = useCallback(async () => {
  const text = serializeDebugEvents(events);
  const flagCopied = () => {
    setCopied(true);
    if (copyTimer.current) clearTimeout(copyTimer.current);
    copyTimer.current = setTimeout(() => setCopied(false), 2000);
  };
  // Guard: navigator.clipboard is undefined in insecure contexts / older
  // browsers. Fall back to the hidden-textarea + execCommand path.
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      flagCopied();
      return;
    } catch {
      // fall through to the legacy fallback below
    }
  }
  if (copyViaTextarea(text)) flagCopied();
}, [events]);
```

- `copyViaTextarea` is a small module-level helper: create a hidden `<textarea>`,
  set value, `select()`, `document.execCommand("copy")`, remove the node; return
  the boolean `execCommand` result. Wrap in try/catch (returns `false` on throw).
- Clear the timer on unmount via a `useEffect` cleanup to avoid a
  `setState`-after-unmount warning (the panel unmounts when `available` flips false).
- Handle the rejection path explicitly: the `try/catch` around `writeText` falls
  through to the textarea fallback rather than silently swallowing.

### Phase 3 — Render the Copy control as a header-row SIBLING

The header is currently a single `<button>` (lines 129–154) whose `onClick`
toggles expand. A `<button>` inside a `<button>` is invalid HTML and clicking the
inner one would also toggle expand. **Resolution:** restructure the header row into
a flex container holding the existing toggle `<button>` AND a separate Copy
`<button>` as siblings — Copy is OUTSIDE the toggle button entirely, so the two
controls are independent by construction (no `stopPropagation` reliance needed,
though the toggle remains a sibling, not an ancestor).

```tsx
<div className="flex w-full items-center justify-between gap-3 px-3 py-2">
  <button
    type="button"
    aria-expanded={expanded}
    onClick={() => setExpanded((v) => !v)}
    className="flex flex-1 items-center gap-2 text-left"
  >
    {/* existing label / count / disconnected spans unchanged */}
  </button>
  <div className="flex shrink-0 items-center gap-2">
    <button
      type="button"
      data-testid="debug-stream-copy"
      onClick={copyAll}
      disabled={events.length === 0}
      title={
        events.length === 0
          ? "No events to copy"
          : "Copy all debug events (redacted) to clipboard"
      }
      className="rounded-sm border border-soleur-border-default px-1.5 py-0.5 font-mono text-[10px] text-soleur-text-muted transition-colors hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-40"
    >
      {copied ? "Copied" : "Copy"}
    </button>
    <span className="text-[10px] text-soleur-text-muted">
      {expanded ? "Hide" : "Show"} · not saved
    </span>
  </div>
</div>
```

- The "Hide/Show · not saved" label moves OUT of the toggle button into the sibling
  group (it was previously the toggle button's trailing span). The toggle button now
  holds only the title/count/disconnected cluster and remains full-clickable for
  expand/collapse via `flex-1`.
- **Independence:** clicking Copy must NOT toggle expand. Because Copy is a sibling
  `<button>`, not a descendant of the toggle, its click never bubbles into the
  toggle's `onClick`. This is the structural guarantee the brief asked for. (A
  belt-and-suspenders `e.stopPropagation()` in `copyAll`'s wrapper is acceptable but
  not required given the sibling structure; do NOT nest.)
- **Disabled when no events:** `disabled={events.length === 0}` with a `title`
  tooltip. The Copy button is visible whenever the panel is (it sits in the header,
  which renders regardless of `expanded`), but is non-interactive with no events.
- Styling matches the header: `text-[10px]`, `font-mono`, `soleur-*` tokens,
  border + hover transition mirroring `DebugEventRow`'s kind-label chip.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `serializeDebugEvents` is exported and, for an event whose RAW `body`
  contains a secret token, the returned string contains the redaction marker (e.g.
  `[redacted-key]`) and does NOT contain the raw secret substring. Verified by the
  new unit/RTL test (see Test Scenarios T1).
- [ ] AC2 — Clicking the Copy control calls `navigator.clipboard.writeText` exactly
  once with the serialized REDACTED text; the written argument does NOT contain the
  raw secret. Verified by T1.
- [ ] AC3 — A withheld event (`body` starts with `"[input withheld"`) serializes to
  its placeholder text unchanged in the copied output. Verified by T2.
- [ ] AC4 — Clicking Copy does NOT change `aria-expanded` on the toggle button (the
  panel does not expand/collapse). Verified by T3.
- [ ] AC5 — The Copy control has `data-testid="debug-stream-copy"`, is `disabled`
  when `events.length === 0`, and shows transient "Copied" text after a successful
  write (reverting to "Copy"). `disabled` state verified by T4.
- [ ] AC6 — Header markup contains NO nested `<button>` (Copy is a sibling of the
  toggle). Verified by T3 reading `aria-expanded` only on the toggle, plus a DOM
  assertion that the toggle button has no descendant `[data-testid="debug-stream-copy"]`.
- [ ] AC7 — No import of any `@/server/*` module is added (the pino client-bundle
  trap, TR6 — the file's header comment). `grep -n "@/server" apps/web-platform/components/chat/debug-stream-panel.tsx` returns zero new lines.
- [ ] AC8 — Typecheck passes: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] AC9 — The debug-stream test suite passes:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel.test.tsx`.

### Post-merge (operator)

- None. Pure client-side code change against an already-provisioned surface;
  `web-platform-release.yml` restarts the container on merge to main touching
  `apps/web-platform/**`. No migration, no infra, no secret.

## Test Scenarios

Extend the EXISTING file `apps/web-platform/test/components/debug-stream-panel.test.tsx`
(do NOT create a new co-located test — vitest jsdom `include` is `test/**/*.test.tsx`;
a `components/chat/*.test.tsx` would never run). Mock `navigator.clipboard` per test.

**Mock strategy (no existing `navigator.clipboard.writeText` precedent in the
suite):** stub with `vi.stubGlobal` / `Object.defineProperty` on `navigator`:

```tsx
const writeText = vi.fn().mockResolvedValue(undefined);
beforeEach(() => {
  Object.defineProperty(navigator, "clipboard", {
    value: { writeText }, configurable: true, writable: true,
  });
  writeText.mockClear();
});
```

- **T1 — redacted, not raw (AC1/AC2):** event with raw `body` = `{"x":"<ANTHROPIC>"}`
  (reuse the existing split-concatenation `ANTHROPIC` fixture to dodge push-protection,
  `cq-test-fixtures-synthesized-only`). Click `getByTestId("debug-stream-copy")`,
  assert `writeText` called once, `writeText.mock.calls[0][0]` contains `[redacted-key]`
  and does NOT contain the raw `ANTHROPIC` substring.
- **T2 — withheld placeholder (AC3):** event with `body` = `"[input withheld: failed redaction probe]"`.
  Click Copy; assert the written text contains that placeholder string verbatim.
- **T3 — Copy does not toggle expand (AC4/AC6):** render collapsed (default). Capture
  `aria-expanded` (`"false"`) on the toggle button. Click Copy. Re-read
  `aria-expanded` — still `"false"`. (Optionally assert the panel's event list did
  not mount.)
- **T4 — disabled with no events (AC5):** render with `events={[]}`. Assert
  `getByTestId("debug-stream-copy")` has `disabled === true`; clicking it does not
  call `writeText`.
- **T5 (optional) — fallback path:** delete `navigator.clipboard` (set to `undefined`),
  spy on `document.execCommand`. Click Copy; assert `execCommand("copy")` was invoked.
  Skip if happy-dom does not implement `execCommand` cleanly — the guard's correctness
  is covered structurally; do not block the PR on this.

## Files to Edit

- `apps/web-platform/components/chat/debug-stream-panel.tsx` — add
  `serializeDebugEvents` + `copyViaTextarea` module helpers; add `copied` state,
  `copyAll` handler, timer ref + cleanup effect; restructure header row into a flex
  container with toggle `<button>` + sibling Copy `<button>`. Add `useCallback` to the
  React import (already imports `useState`/`useEffect`/`useMemo`/`useRef`).
- `apps/web-platform/test/components/debug-stream-panel.test.tsx` — add a
  `describe("DebugStreamPanel — Copy control")` block with T1–T4 (T5 optional) and the
  `navigator.clipboard` mock.

## Files to Create

- None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` queried; no open scope-out
names `debug-stream-panel.tsx` or its test. (If the corpus is unreachable at /work
time, re-run the two-stage `gh --json` + standalone `jq --arg` form per the plan
skill's Phase 1.7.5.)

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none
**Pencil available:** N/A — no NEW user-facing surface

This modifies an EXISTING component (`debug-stream-panel.tsx`) by adding one
control to an existing header row. It creates no new page, no new component file,
no new flow. The mechanical UI-surface override fires (edits a `components/**/*.tsx`
file) → Product is forced relevant, but the change is ADVISORY tier: a convenience
button on an existing, team-only, dev-cohort-gated diagnostic panel. No new
`components/**` FILE is created (the escalation-to-BLOCKING trigger), so no `.pen`
wireframe is required. The control reuses the existing header's tokens and scale;
no new visual language. Pipeline context → auto-accepted.

#### Findings

The single product/brand concern is the redaction-parity invariant, fully captured
in `## User-Brand Impact` and gated by `user-impact-reviewer` at review-time. No
copy/persuasion surface (no marketing or emotional copy), so no copywriter gate.

## Observability

Skipped — this plan's Files-to-Edit are a client component (`components/`) and its
test only; no file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or
`plugins/*/scripts/`, and no new infrastructure surface. Per Phase 2.9 skip
condition (client-render-only change, no new error path reaching a server logger),
no `## Observability` schema is required. The clipboard write's failure path is
user-local (a button that doesn't flip to "Copied"); there is no server-side error
channel to wire to Sentry/Better Stack.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, is `TBD`/placeholder, or
  omits the threshold fails `deepen-plan` Phase 4.6. This plan's section is filled
  with concrete artifact + vector + `single-user incident` threshold.
- **Test file location is load-bearing.** A co-located `components/chat/debug-stream-panel.test.tsx`
  is silently never run — vitest jsdom `include` is `test/**/*.test.tsx` only
  (`apps/web-platform/vitest.config.ts:60`). Extend the EXISTING
  `test/components/debug-stream-panel.test.tsx`. The brief's "co-located per repo
  convention" wording is wrong for this repo; reconciled above.
- **Typecheck command:** use `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`,
  NOT `npm run -w apps/web-platform typecheck` (no root `workspaces` field).
- **Test runner:** use `./node_modules/.bin/vitest run`, NOT `bun test`
  (`apps/web-platform/bunfig.toml` sets `pathIgnorePatterns = ["**"]`).
- **Redaction parity is the invariant, not a proxy.** The test MUST assert the
  written clipboard text does NOT contain the RAW secret substring (negative
  assertion), not merely that it contains `[redacted-key]`. A serializer that
  appends the redacted form while ALSO leaking the raw body would pass a
  contains-`[redacted-key]` check but fail the does-NOT-contain-raw check. Both
  assertions are required (T1).
- **`navigator.clipboard` guard for happy-dom.** happy-dom may not define
  `navigator.clipboard` by default; the component's `navigator.clipboard?.writeText`
  optional-chaining guard is what lets the fallback path exist, and the test must
  define the mock BEFORE rendering. Do not assume the global exists.
- **No `stopPropagation` crutch for a nested button.** The fix is structural
  (sibling buttons), not behavioral (`stopPropagation` on a nested button). Do NOT
  ship a `<button>` inside a `<button>` — it is invalid HTML and React will warn
  in dev. AC6 guards this.
