# Learning: Testing transient React state in async upload flows

## Problem

When testing upload progress UI, the "Uploaded" completion state (progress=100) was set by
`uploadAttachments` but immediately cleared by `handleSubmit`'s `finally` block calling
`setAttachments([])`. React batched both state updates, so the intermediate "Uploaded" text
never rendered in the test DOM. The test timed out waiting for text that was set and cleared
within the same microtask chain.

## Solution

Separate the XHR completion signal from the progress event in the test mock. Fire
`onprogress({ loaded: 100, total: 100 })` via `setTimeout(0)` to set progress=100, but
hold the `onload` callback behind a manually-triggered function (`completeUpload`). This
creates a window where React renders the progress=100 state (which shows "Uploaded" text)
before the XHR promise resolves and `handleSubmit` clears attachments.

```typescript
let completeUpload: () => void;
mockXhr.send.mockImplementation(() => {
  setTimeout(() => {
    mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 100, total: 100 });
  }, 0);
  completeUpload = () => mockXhr.onload?.();
});

// Assert intermediate state
await waitFor(() => {
  expect(screen.getByText("Uploaded")).toBeInTheDocument();
});

// Release completion to let handleSubmit finish
completeUpload!();
```

## Key Insight

When testing transient UI states in async flows (progress indicators, loading spinners,
success flashes), you must control the timing of the async resolution separately from the
state update that produces the UI. If both happen in the same microtask, React may batch
them and the intermediate state never renders. The pattern: fire the state update via
`setTimeout(0)`, hold the promise resolution behind a manual trigger, assert the
intermediate state, then release.

## Session Errors

1. **Wrong script path for setup-ralph-loop.sh** — Used `./plugins/soleur/skills/one-shot/scripts/` instead of `./plugins/soleur/scripts/`. Recovery: tried correct path. Prevention: the one-shot skill should specify the absolute path in its instructions.

2. **CWD drift after npx vitest** — Running `npx vitest` from `apps/web-platform` changed CWD, causing subsequent `git add` to fail on relative paths. Recovery: used absolute paths from worktree root. Prevention: always use absolute paths for git commands, or `cd` back to worktree root after test runs.

3. **Dev server Supabase env vars missing** — QA browser scenarios skipped because `SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_URL` are not in the Doppler `dev` config. Recovery: skipped browser QA, relied on unit test coverage. Prevention: add Supabase env vars to Doppler dev config, or document the QA prerequisite.

4. **Transient state untestable in initial test design** — First "Uploaded" test used `setTimeout(() => mockXhr.onload?.(), 0)` which resolved the XHR immediately, clearing the attachment before React rendered. Recovery: separated progress event from onload using manual trigger pattern. Prevention: documented in this learning.

## Tags

category: test-failures
module: chat-input
