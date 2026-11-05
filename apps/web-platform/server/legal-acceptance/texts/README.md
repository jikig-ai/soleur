# Legal texts

One committed file per key: `<key>.md`, LF line endings, a front-matter block with `version` (and optionally
`valid_until`), then the text the founder reads. The file name is the key. The hash recorded against a decision is the
sha256 of the file's raw bytes (`sha256sum <file>` gives the same value). See `../canonical.ts` and ADR-319.

Do not add a text here without counsel's sign-off on its wording. A change to a published file is a new version:
the old hash stays valid for the decisions already recorded against it.

## How the texts reach the production image

The server is bundled with esbuild into `dist/server/index.cjs`, and the route handlers run from the Next build, so the
directory next to the compiled module does not contain `texts/`. The Dockerfile therefore copies this directory, byte
for byte, to `/app/server/legal-acceptance/texts`, and `resolveTextsDir` in `../canonical.ts` reads
`<cwd>/server/legal-acceptance/texts` when the module-relative directory is absent (the container working directory is
`/app`). Bytes are never rewritten, so `sha256sum <file>` equals the recorded `text_hash`. The `.dockerignore` keeps
`*.md` out of the build context in general and re-includes this directory.
`test/legal-acceptance/registry-embedding.test.ts` builds a bundle with the production flags, lays it out like the
image and checks that a fixture text loads and hashes to the known value.
