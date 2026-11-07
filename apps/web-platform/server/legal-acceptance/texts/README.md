# Legal texts

One committed file per key: `<key>.md`, LF line endings, a front-matter block with `version` (and optionally
`valid_until`), then the text the founder reads. The file name is the key. The hash recorded against a decision is the
sha256 of the file's raw bytes (`sha256sum <file>` gives the same value). See `../canonical.ts` and ADR-319.

Do not add a text here without counsel's sign-off on its wording. The one exception is a HELD DRAFT on a draft PR whose
CI-only merge guard (`test/legal-acceptance/founder-acceptance-record.test.ts`) stays red while any open item is left in the
text or in the card notice that states the same retention period, as `founder-acceptance-record` is until counsel's sign-off PR
replaces the placeholder in both, bumps `version` and adds the published `{version: sha256}` pin. The guard detects the draft
state; it is not proof of sign-off, and an admin or UI merge bypasses it, so the draft stays a DRAFT PR until counsel signs off. A change to a published file is a new version: the old hash stays valid for the decisions already
recorded against it.

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
