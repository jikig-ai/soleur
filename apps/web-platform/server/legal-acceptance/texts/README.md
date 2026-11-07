# Legal texts

One committed file per key: `<key>.md`, LF line endings, a front-matter block with `version` (and optionally
`valid_until`), then the text the founder reads. The file name is the key. The hash recorded against a decision is the
sha256 of the file's raw bytes (`sha256sum <file>` gives the same value). See `../canonical.ts` and ADR-319.

Do not add a text here without a recorded sign-off on its wording. Today the sign-off is the CLO agent's ruling of
2026-11-07, which stands in for counsel on the operator's instruction (a v1 internal position; a human lawyer's review is
still owed), persisted in `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`. A text has
three obligations before it merges: a declared card kind in `LEGAL_TEXT_KIND` (`lib/legal-acceptance-copy.ts`; a text with no
declared kind renders no card), a row in the published pin (`PUBLISHED` in `test/legal-acceptance/registry-pins.test.ts`), and
no unfinished marker in its body or in the notices that restate its retention period.

## The pin rule

`PUBLISHED` is an append-only `{version: sha256}` history per key. After a text's first merge to main, a changed byte comes with
a new `version` and a new appended pin row; an existing row's sha is never edited, and editing one is rejected in review. The test
requires the keys the loader serves, the keys in `PUBLISHED` and the keys in `LEGAL_TEXT_KIND` to be the same set, and checks each hash twice
(through the loader and by an independent read of the file bytes). It proves consistency, not integrity: the text and its pin can be
edited in one diff. The hash, not the version label, is the authority, because the database keeps `UNIQUE (founder_id, key, text_hash)`.
If that is judged insufficient, add a base-SHA CI guard modelled on `tc-document-sha-guard` (tracked in #12366). A change to a published
file is a new version: the old hash stays valid for the decisions already recorded against it.

## What `accept` means for an acknowledgement text

For a text of kind acknowledgement, the stored choice value accept means only that the founder answered Yes to an acknowledgement of
that exact text version; it records no acceptance of terms and no consent. Anything that reads a decision row or a check result must read
the kind pinned for that text key in the registry before it interprets accept.

The committed texts are LF-only printable ASCII with no BOM (the byte audit in that test file); a text that needs other
characters needs that rule revisited first.

## How the texts reach the production image

The server is bundled with esbuild into `dist/server/index.cjs`, and the route handlers run from the Next build, so the
directory next to the compiled module does not contain `texts/`. The Dockerfile therefore copies this directory, byte
for byte, to `/app/server/legal-acceptance/texts`, and `resolveTextsDir` in `../canonical.ts` reads
`<cwd>/server/legal-acceptance/texts` when the module-relative directory is absent (the container working directory is
`/app`). Bytes are never rewritten, so `sha256sum <file>` equals the recorded `text_hash`. The `.dockerignore` `*.md` rule
matches only at the context root, so it does not drop this directory today; the re-include is belt-and-braces.
`test/legal-acceptance/registry-embedding.test.ts` builds a bundle with the production flags, lays it out like the
image and asserts that a fixture text loads and hashes to the known value. That covers the esbuild bundle layout; the
Next-compiled routes and pages rely on the same cwd convention.
