# Legal texts

One committed file per key: `<key>.md`, LF line endings, a front-matter block with `version` (and optionally
`valid_until`), then the text the founder reads. The file name is the key. The hash recorded against a decision is the
sha256 of the file's raw bytes (`sha256sum <file>` gives the same value). See `../canonical.ts` and ADR-319.

Do not add a text here without counsel's sign-off on its wording. A change to a published file is a new version:
the old hash stays valid for the decisions already recorded against it.
