# Decision challenges — feat-one-shot-md-txt-upload-support-attach-icon

Persisted by plan-review (headless). Taste / User-Challenge findings that were NOT auto-applied.
`ship` renders these into the PR body and files an `action-required` issue.

## User-Challenge

- **Split into two PRs (Button fix vs upload fix).** DHH, CTO and CPO advisories recommend shipping the Button-primitive fix (rendering blast radius ~45 sites) separately from the `.md`/`.txt` upload fix so a layout revert does not take the upload fix with it. The operator asked for both in one task, so the plan keeps one PR with two independently revertable commits. Default: one PR, separate commits. Operator may choose two PRs.

## Taste

- **Product/UX gate tier ADVISORY (no `.pen` wireframe)** despite the mechanical UI-surface glob matching. Rationale: style-regression restore of the shipped composer, design of record exists (`knowledge-base/product/design/concierge/chat-composer-repo-setup-states.pen`, `mobile-pwa/mobile-chat-surface-phase-1.pen`). Tripwire: any new glyph / tile geometry / redesigned post-send chip re-opens the gate to BLOCKING. Operator may require a wireframe instead.
- **Error copy.** CPO proposes replacing `"<name>" is not a supported file type.` with `"<name>" isn't supported. You can attach images, PDFs, .md or .txt files.` (built from the allowlist), and lengthening the 3s toast auto-dismiss to ~6-8s. User-visible copy; not applied.
- **Post-send attachment chip.** `components/chat/attachment-display.tsx` shows every non-image with a red document icon (reads as PDF/error). CPO/Kieran suggest a neutral icon for `.md`/`.txt`. Would change visible structure (see tripwire above); not applied.
- **Multi-file partial rejection message** ("2 files skipped") — optional, not applied.
