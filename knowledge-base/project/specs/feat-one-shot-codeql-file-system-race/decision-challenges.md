# Decision Challenges — feat-one-shot-codeql-file-system-race

| Item | Class | Ruling |
|------|-------|--------|
| Per-alert disposition: fix vs leave-open-and-note | technical | Ruled by pipeline self-assessment, 2026-11-03: all five are genuine check→use TOCTOU patterns fixable with the repo's established one-descriptor idiom (precedent `1b60715d80`, `7a3f264e0e`); #301 is additionally a real production-path race weakening the file's documented symlink-refusal invariant. The four test-file sites are warning-level practical risk but the fix is cheaper than an operator sign-off round-trip, so all five are fixed and none dismissed. |
| Remediation idiom | technical | Ruled by pipeline self-assessment, 2026-11-03: `open`/`openSync` once + `fstat`/`fstatSync` + `readFile`/`readFileSync` on the same descriptor, `O_NOFOLLOW\|O_NONBLOCK` on the production path; `/proc/self/fd/N` re-opens for the two-consumer `#258` case (Node has no lseek; suite is already Linux-gated). Matches CodeQL's canonical "use file descriptors instead of file names" and merged repo precedent. |
| #10926 overlap on install-opencode-adapter.ts | technical | Ruled by pipeline self-assessment, 2026-11-03: different scope (npm-publish/vendor payload), no tracker link — proceed; whichever merges second rebases. |
