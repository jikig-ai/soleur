# Phase 0 RED record: hook, deny marker, framing hook (#12757)

I wrote the tests first and ran them against the unchanged `cron-bash-allowlist-hook.mjs` and
`cron-filing-deny-marker.ts`. Command:

```
./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts \
  test/server/cron-filing-deny-marker.test.ts test/server/inngest/cron-gh-output-framing-hook.test.ts
```

Pre-fix: RC=1, 637 tests, 530 passed, 107 failed. Post-fix: RC=0, 637 passed.

## Per group, pre-fix

| Group | Rows | RED (assertion) | Fails to load | Pass (control) |
|---|---|---|---|---|
| Guard 1 deny rows (14 paths x Write/Edit/MultiEdit) | 42 | 42 (all `allow`) | 0 | 0 |
| Guard 1 drift row (`AGENT_GIT_GLOBAL_CONFIG`) | 1 | 1 (allowed, so the reason was undefined) | 0 | 0 |
| Guard 1 must-pass (5 x 3) + Read `.gitconfig` regression | 16 | 0 | 0 | 16 |
| Guard 2 verb table (40) | 40 | 40: 36 allowed, 4 bug-fixer `switch` rows denied as "not allowlisted" (these 4 only check that the new reason comes first) | 0 | 0 |
| Guard 2 single irregular rows (8) | 8 | 8 (all allowed) | 0 | 0 |
| Guard 2 bare `git` + 2 flag-led rows | 3 | 3 (denied as "not allowlisted") | 0 | 0 |
| Separator table (5) | 5 | 5 (all allowed) | 0 | 0 |
| Verb-table harness, anti-vacuity, P5 (6), must-pass (9) | 17 | 0 | 0 | 17 |
| Allowlist census (1 equality + 86 lines) | 87 | 0 | 0 | 87 |
| `classifyNewRuleDeny` parity (3) | 3 | 1 (the Write parity row asserts decide() first, and decide() allowed the write) | 2 | 0 |
| `countNewRuleDenials` (5) | 5 | 0 | 5 | 0 |
| Existing rows in the three files | 410 | 0 | 0 | 410 |

## Rows that surprised me

- Of the 56 Guard 2 irregular rows, 49 were outright ALLOWED before the fix, not just denied
  with a different reason. Examples: `git '' checkout --no-overlay HEAD:.claude apps`,
  `git 'checkout -b' x` and `gh ' api' repos/jikig-ai/soleur/labels/../issues`. The padded
  `api` word skips both the dot-segment branch and `filingShape`.
- U+FEFF and U+2028 before `checkout` were both admitted. JS `\s` covers both characters, so
  the allowlist's normalised view saw a plain `git checkout`.
- `/home/soleur//.gitconfig` and `/home/soleur/./.gitconfig` already match the new `.gitconfig`
  pattern on the raw string. Only the two `.config/git` spellings and the
  `/usr/local//share/soleur/…` row need the `posix.normalize` arm. Mutant 6b confirms this: it
  kills those three rows and no others.
