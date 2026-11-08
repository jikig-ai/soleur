# Legal texts

One committed file per key: `<key>.md`, LF line endings, a front-matter block with `version` (and optionally
`valid_until`), then the text the founder reads. The file name is the key. The hash recorded against a decision is the
sha256 of the file's raw bytes (`sha256sum <file>` gives the same value). See `../canonical.ts` and ADR-319.

Do not add a text here without a recorded sign-off on its wording. Today the sign-off is the CLO agent's ruling of
2026-11-07, which stands in for counsel on the operator's instruction (a v1 internal position; a human lawyer's review is
still owed), persisted in `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`. A text has
three obligations before it merges: a declared card kind in `LEGAL_TEXT_KIND` (`lib/legal-acceptance-copy.ts`; a text with no
declared kind renders no card), a row in the published pin (`PUBLISHED` in `test/legal-acceptance/registry-pins.test.ts`, shaped
`{ kind, versions: { "<version>": "<sha256>" } }` with the `kind` equal to the `LEGAL_TEXT_KIND` entry), and no unfinished marker in its
body or in the notices that restate its retention period (the always-on marker check and the forbidden-claims check run over EVERY text
the loader serves, not only the first one).

Adding a second text, step by step:

1. Write `<key>.md`. `version` is an ISO calendar date (`YYYY-MM-DD`): the pin test picks the highest version by string order, so a free-form
   label such as `v10` sorts below `v9`. The first body line is the title; for an acknowledgement text it is shown in quotes on the card, so it
   starts with a letter or digit, has no double quote and is at most 120 characters (otherwise the card falls back to a label derived from the
   key).
2. Declare the kind in `LEGAL_TEXT_KIND` and add the `PUBLISHED` row with the sha256 of the final bytes (`sha256sum`).
3. The card notice and the request-changes notice (`LEGAL_COPY.cardNotice`, `requestChangesNotice`) are shared by every text and state the
   5-year retention ruled for this record. A text with a different period needs its own ruling and a change to those pinned notices first.
4. If the kind is not `terms`, add the key to `WA_NON_TERMS_KEYS` in `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh`: a recorded Yes on an
   acknowledgement cannot back a production hold (a test cross-checks the list with `PUBLISHED`).
5. The records (Art. 30 register, LIA, attestation, ADR-319) are per text; see the CLO ruling file for the shape.

The `kind` of a key is immutable once a hash is published: flipping `acknowledgement` to `terms` would re-word the founder's recorded Yes as
"You accepted the updated ...". Changing it is a review-blocking change that needs a CLO ruling.

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
