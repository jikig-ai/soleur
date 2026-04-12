---
title: "feat: upload progress indicator for chat attachments"
type: feat
date: 2026-04-12
---

# feat: upload progress indicator for chat attachments

## Overview

When attaching a file (PDF/image) in the chat input, there is no meaningful upload progress indicator visible to the user. The `PendingAttachment` interface already has a `progress` field, and a progress bar element exists in the JSX, but the actual upload uses `fetch()` which has no progress event support. Progress jumps from 0 to 50 (presign complete) to 100 (upload complete) with no intermediate feedback during the actual file transfer to Supabase Storage.

## Problem Statement / Motivation

For small files the jump is imperceptible. For larger files (PDFs up to 20 MB), the user sees a file chip appear with no feedback until the upload completes or fails. This creates uncertainty -- did the upload stall? Is it working? Should I retry? The upload-heavy flow (up to 5 files, up to 20 MB each) needs real-time feedback.

## Proposed Solution

Replace the `fetch()` PUT call with `XMLHttpRequest` to get granular `upload.onprogress` events during the actual file transfer. Keep the presign phase as `fetch()` (it transfers no file bytes). Map progress through two phases:

1. **Presign phase (0-10%):** Quick API call to get the signed URL
2. **Upload phase (10-100%):** Real byte-level progress from XHR `upload.onprogress`

Additionally, improve the visual indicator:

- Show an indeterminate state (pulsing/spinner) on the file chip immediately when added, before upload begins
- Add a percentage text label alongside the progress bar for explicit feedback
- Show a checkmark or completion state when upload finishes

## Technical Considerations

### Architecture

- **Single file change:** All modifications are in `apps/web-platform/components/chat/chat-input.tsx`
- **No API changes:** The presign route and storage upload URL are unchanged -- only the client-side upload mechanism changes
- **No new dependencies:** `XMLHttpRequest` is a browser built-in

### Why XHR over fetch + ReadableStream?

The `fetch()` API supports upload progress via `ReadableStream` body in some browsers, but:
- Browser support is inconsistent (Chrome 105+, no Safari support as of 2025)
- Supabase Storage signed URLs may not accept chunked transfer encoding
- `XMLHttpRequest.upload.onprogress` has universal browser support and is the proven pattern for upload progress

### Performance implications

None -- XHR and fetch perform identically for PUT uploads. The progress events fire on the browser's network layer with no additional overhead.

### Key files

- `apps/web-platform/components/chat/chat-input.tsx` -- upload logic and progress UI (primary change)
- `apps/web-platform/test/chat-input-attachments.test.tsx` -- test updates for XHR mock
- `apps/web-platform/lib/types.ts` -- no changes needed (AttachmentRef is unchanged)
- `apps/web-platform/app/api/attachments/presign/route.ts` -- no changes needed

## Acceptance Criteria

- [ ] When a file is added to the chat input, the file chip immediately shows a visual indicator that upload is pending (before send is pressed)
- [ ] When the user presses send, the progress bar on each file chip fills from 0-100% with granular increments during the actual upload (not just 0/50/100 jumps)
- [ ] A percentage label (e.g., "42%") is visible on or near each file chip during upload
- [ ] When upload completes, the progress bar transitions to a completion state (checkmark or green bar)
- [ ] When upload fails, the file chip shows the error state with red text (existing behavior preserved)
- [ ] The send button shows the existing spinner during upload (existing behavior preserved)
- [ ] Upload progress works correctly for multiple simultaneous file uploads (sequential upload per the existing pattern)
- [ ] No regressions in existing attachment tests (presign mock patterns may need updating for XHR)

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** N/A
**Pencil available:** N/A

#### Findings

Modification to existing chat input component. Progress indicator is a standard UX pattern. No new pages, flows, or components -- enhancement of existing attachment preview strip.

## Test Scenarios

- Given a user attaches a PNG file, when the file appears in the preview strip (before send), then the chip shows an "added" state with the filename (no progress bar yet -- file is not uploading)
- Given a user presses send with an attached file, when the presign API responds, then progress shows approximately 10%
- Given the PUT upload is in progress, when bytes are transferred, then the progress bar and percentage label update incrementally (not a single jump)
- Given the PUT upload completes, when progress reaches 100%, then the file chip shows a completion indicator
- Given the PUT upload fails (network error), when the error is caught, then the file chip shows red error text with the error message
- Given multiple files are attached, when send is pressed, then each file shows individual progress as it uploads sequentially
- Given a very small file (< 1 KB), when uploaded, then progress still transitions smoothly (0 -> 10 -> 100) without visual jank

## MVP

### `apps/web-platform/components/chat/chat-input.tsx`

Replace the `fetch()` PUT in `uploadAttachments` with an XHR wrapper:

```typescript
// Helper: upload with progress tracking via XHR
function uploadWithProgress(
  url: string,
  file: File,
  contentType: string,
  onProgress: (percent: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", url);
    xhr.setRequestHeader("Content-Type", contentType);

    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        const percent = Math.round((event.loaded / event.total) * 100);
        onProgress(percent);
      }
    };

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else {
        reject(new Error("Upload to storage failed"));
      }
    };

    xhr.onerror = () => reject(new Error("Upload to storage failed"));
    xhr.send(file);
  });
}
```

Update `uploadAttachments` to use the helper and map progress:

```typescript
// After presign succeeds, set progress to 10%
setAttachments((prev) =>
  prev.map((a) => (a.id === att.id ? { ...a, progress: 10 } : a)),
);

// Upload with real progress (10-100%)
await uploadWithProgress(
  uploadUrl,
  att.file,
  att.file.type,
  (uploadPercent) => {
    const mapped = 10 + Math.round(uploadPercent * 0.9);
    setAttachments((prev) =>
      prev.map((a) => (a.id === att.id ? { ...a, progress: mapped } : a)),
    );
  },
);
```

Update the progress UI in the attachment preview strip to show percentage:

```tsx
{att.error ? (
  <span className="text-xs text-red-400">{att.error}</span>
) : att.progress > 0 && att.progress < 100 ? (
  <div className="flex items-center gap-1.5">
    <div className="h-1 w-16 overflow-hidden rounded-full bg-neutral-700">
      <div
        className="h-full bg-amber-500 transition-all"
        style={{ width: `${att.progress}%` }}
      />
    </div>
    <span className="text-[10px] tabular-nums text-neutral-400">
      {att.progress}%
    </span>
  </div>
) : att.progress === 100 ? (
  <span className="text-xs text-green-400">Uploaded</span>
) : null}
```

### `apps/web-platform/test/chat-input-attachments.test.tsx`

Update the "calls onSend with attachments after successful upload" test to mock XHR instead of the second `fetch()` call. The presign `fetch()` stays mocked as-is. The XHR mock needs to simulate `upload.onprogress` events.

## References

- Related PR: #1975 (original attachment implementation)
- Related issue: #1961 (file attachments feature)
- MDN XMLHttpRequest upload progress: [XMLHttpRequest.upload](https://developer.mozilla.org/en-US/docs/Web/API/XMLHttpRequest/upload)
