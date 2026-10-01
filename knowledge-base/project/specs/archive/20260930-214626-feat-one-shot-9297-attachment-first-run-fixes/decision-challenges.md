# Decision challenges — feat-one-shot-9297-attachment-first-run-fixes

Persisted by plan (headless). Taste / User-Challenge findings that were NOT silently final.
`ship` renders these into the PR body and files an `action-required` issue.

## User-Challenge

- **Server-assisted fix vs client-only fix.** The brief asked to "use `realConversationId` once the server has created the row" and offered client-only options (upload only after the real id is known, or disable/queue attach). Verified fact: `realConversationId` is the PENDING uuid from `session_started`; the `conversations` row is only created by the first `chat` message (`ws-handler.ts`, deferred creation), and that first `chat` is rejected when the @-stripped text is empty. So a client-only fix cannot deliver "attach on a fresh chat" or "upload first, send once". The plan therefore adds two small server changes: presign tolerates an unmaterialized UUID-shaped conversation id (own-folder path only, DB errors never fall through) and an attachments-only first message is accepted. Alternative (operator may choose instead): client-only — disable attach until the first text message has been sent and keep send-then-upload for first-run; no server surface, but #9297 item 2 stays unfixed and item 1 becomes "require a message".

## Taste

- **Tile error copy** (author's proposal; only the `unsupported_file_type` wording comes from the archived CPO proposal):
  - `file_too_large`: "File is empty or larger than 20 MB."
  - `unsupported_file_type`: "This file type isn't supported. You can attach images, PDFs, .md or .txt files."
  - `conversation_not_found`: "This conversation isn't ready for attachments yet. Remove the file and attach it again."
  - `not_a_workspace_member`: "You don't have access to attach files to this conversation."
  - `unauthorized`: "Your session expired. Sign in again to attach files."
  - `invalid_request` / `upload_failed` / unknown or network: "Upload failed. Check your connection and try again."
- **Product/UX gate tier ADVISORY (no `.pen` wireframe)** despite the mechanical UI-surface glob matching `components/**/*.tsx`: the diff is a disabled state on an existing control plus copy (Excluded: pure copy/state tweak). Tripwire: any new visible element re-opens BLOCKING. The deferred first-run failure notice is tracked in #9316.
- **Client validator message and 3s toast duration** from the archived proposal are intentionally left unchanged (outside #9297 item 3, which is about presign codes on tiles).
- **First-run upload failure semantics (CPO + UX panel, Taste).** The plan sends the typed message even when every pending upload failed (and sends nothing when there is no message); partial failure sends the survivors. The CPO and UX advisories recommend hold-and-re-stage instead: keep the message in the composer and hand the failed files back as error-state tiles (existing tile UI, reuses the new copy table) so the user never believes a file was attached when it was not. That needs a `ChatInput` prop/ref API and is tracked in #9316 (milestone moved to Phase 4 on the panel's advice). Operator may pull it into this PR; it would re-open the UX gate only if it adds a new visible element.
- **Upload-first latency.** The first user bubble now appears only after uploads finish (up to 5 x 20 MB, no progress UI). UX option 1: show the user's bubble optimistically with the attachments in the existing uploading-tile state and delay only dispatch. Accepted for this PR; measured in QA.
- **Rail title for a files-only first message** is "Untitled conversation". Deriving it from the first filename is a product/copy decision, not applied.
- **Disabled-paperclip affordance and message.** Spec uses `aria-disabled` + hidden described-by text (not native `disabled`) and the drop/paste message "Attachments are available once the conversation starts." The existing 3s auto-dismiss toast length is unchanged (WCAG 2.2.1 would prefer longer; out of scope).
- **Plan-review dispositions (mechanical, applied):** D2 tests moved to a new file (PR #9051 edits `ws-deferred-creation.test.ts`); presign shape check moved before the DB lookup and made lowercase-only (a `uuid` column makes `"new"` a 22P02 DB error); first-run files consumed only for fresh full-variant `"new"` conversations; post-upload connection/id re-check; source-grep drift test dropped; `uploadAttachments` guard and `"new"` literal dropped from `ChatInput`; no `logger.info` on the tolerant branch. **Not applied (disagreement, Taste):** simplicity + DHH preferred inlining `lib/first-run-send.ts` into the effect and inlining the copy map; kept as small modules to hold the `chat-surface.tsx` diff to a contiguous swap (conflict hotspot with #9051).
