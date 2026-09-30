# Tasks: fix .md/.txt uploads and restore composer attach/send icons

Plan: `knowledge-base/project/plans/2026-09-30-fix-md-txt-upload-support-and-attach-icon-plan.md`

## Phase 0: Reproduce and baseline

- [ ] 0.1 Reproduce missing paperclip/send icons in a real browser (dashboard first-run + conversation); record computed padding, button width, svg bounding box
- [ ] 0.2 Confirm compiled-CSS ordering with `@tailwindcss/node`; record how many census sites are wrong today
- [ ] 0.3 `git grep -n "px-6\|py-3" apps/web-platform/test` for bare-token Button class assertions
- [ ] 0.4 File tracking issue on Phase 4 milestone; add roadmap row extending 3.19/3.20; file the deferral issues listed under the plan's Non-Goals

## Phase 1: RED tests

- [ ] 1.1 `test/attachment-constants.test.ts` (resolver truth table, parity, single definition)
- [ ] 1.2 `test/validate-files.test.ts` (extension vs MIME, canonicalized File)
- [ ] 1.3 Update `test/presign-route.test.ts` (use `ATTACHMENT_EXTENSION_BY_TYPE`; md/txt; old-client `""` + `.md`; spoof rejected)
- [ ] 1.4 Update `test/cc-attachment-pipeline.test.ts` (md/txt on disk as .md/.txt; octet-stream + .md; .exe rejected)
- [ ] 1.5 Update `test/chat-input-attachments.test.tsx` (md/txt staged, MD tile label, presign contentType, accept attr, svg present in attach + send)
- [ ] 1.6 Update `test/command-center.test.tsx` (first-run composer accepts .md)
- [ ] 1.7 Update `test/upload-attachments.test.ts`, `test/kb-upload.test.ts`, `test/file-tree-upload.test.tsx` (.md accepted, accept attr, duplicate collision)
- [ ] 1.8 `test/components/button-layer.test.ts` (compile globals.css; layers) and `test/components/button-classes.test.tsx` (icon-only vs text classes); update `test/components/button.test.tsx`
- [ ] 1.9 e2e bounding-box assertions (svg width/height >= 16, `expect.poll`, fail-not-skip in CI) at 1440px and 390px: attach icon in `e2e/start-fresh-onboarding.e2e.ts` (send = control), real `ChatInput` attach/send/"@" in `e2e/cc-soleur-go-routing.e2e.ts`
- [ ] 1.10 `test/attachments-url-route.test.ts` (download option), pipeline tests (extension binding, untrusted header, raw-filename resolve), KB route tests (case, 1 MB, reserved names)

## Phase 2: Shared resolver

- [ ] 2.1 `lib/attachment-constants.ts`: add text types, `ATTACHMENT_EXTENSION_BY_TYPE`, `fileExtension()`, `resolveAttachmentContentType` (normalize MIME, `lastIndexOf(".") > 0`, extension decides md/txt over a text-tolerant reported set incl. `application/x-genesis-rom`, `text/html` excluded), explicit `ATTACHMENT_ACCEPT`

## Phase 3: Client

- [ ] 3.1 `lib/validate-files.ts`: resolve once; reject 0-byte; PDF cap from resolved type; return canonicalized File objects (keep lastModified)
- [ ] 3.2 `chat-input.tsx`: accept, tile label + title, `role="alert"` on toast, `p-0` on mobile "@" button
- [ ] 3.3 `dashboard/page.tsx`: accept + tile label; stop clearing attachError on partial-valid batch; verify attach Button

## Phase 4: Server

- [ ] 4.1 `presign/route.ts`: server-side resolve, resolved-type PDF cap + extension, delete `getExtension`
- [ ] 4.2 `attachment-pipeline.ts`: resolve from raw filename in validation loop, bind storagePath extension, write back `att.contentType`, untrusted-data header, sanitizer class, delete `EXT_MAP`
- [ ] 4.3 `app/api/attachments/url/route.ts`: `{ download: filename }` for non-image; record `curl -sI` nosniff check; `attachment-display.tsx` `<1 KB` label

## Phase 5: KB

- [ ] 5.1 `lib/kb-constants.ts`: add `md`, fix comment
- [ ] 5.2 `file-tree.tsx`: derive allowlist/accept from `KB_UPLOAD_EXTENSIONS`, use `fileExtension()`, `.md` > 1 MB message
- [ ] 5.4 `app/api/kb/upload/route.ts`: `fileExtension()`, lowercase stored extension, `.md` > `KB_MAX_FILE_SIZE` -> 413, reserved basenames refused
- [ ] 5.3 Verify uploaded `.md` is served by the markdown path (no `CONTENT_TYPE_MAP` entry)

## Phase 6: Button primitive

- [ ] 6.1 `globals.css`: `.soleur-btn` + `.soleur-btn-pad` in `@layer components`
- [ ] 6.2 `button.tsx`: emit `soleur-btn` always, `soleur-btn-pad` only when not icon-only; locality comment
- [ ] 6.3 Census (multi-line aware) + PR-body table; scripted visual QA vs `fff36b6172^`
- [ ] 6.4 `support-launcher.tsx` stale workaround sweep; hit-area classes on `error-card`, `pending-invite-banner`, `runtime-explainer-banner`, `select-project-state`
- [ ] 6.6 Declare `@tailwindcss/node` devDependency + lockfile (`npx --yes npm@11 install`)
- [ ] 6.5 `components/ui/README.md` paragraph + ADR-255 addendum

## Phase 7: Verification

- [ ] 7.1 `./node_modules/.bin/tsc --noEmit` from `apps/web-platform`
- [ ] 7.2 vitest (touched files, then component + unit projects); `scripts/check-button-primitive-sweep.sh`
- [ ] 7.3 Playwright e2e (authenticated project) + before/after screenshots at 1440px and 390px
- [ ] 7.4 Real `.md` attach -> send -> agent lists `<uuid>.md`; document iOS/Android picker check
