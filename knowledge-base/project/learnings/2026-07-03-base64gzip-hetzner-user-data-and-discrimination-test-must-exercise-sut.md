# Learning: base64gzip() is the Hetzner user_data over-cap fix; a discrimination test must exercise the SUT, not a bypass path

## Problem

Two reusable insights surfaced fixing #5927 (git-data cloud-init `user_data` ~41.7 KB, over Hetzner's 32,768-byte cap):

1. **How to fit an over-cap Hetzner `user_data`** without the web host's docker bake-and-extract (git-data runs no docker).
2. **A near-tautological "discrimination" test** that two orthogonal review agents (test-design-reviewer + code-quality-analyst) independently flagged: it *looked* like it guarded the critical property but exercised a bypass path, not the function under test.

## Solution

### 1. `base64gzip()` for Hetzner over-cap user_data

Wrap the whole render: `user_data = base64gzip(templatefile(...))`. Terraform's core `base64gzip()` = gzip-then-base64. This composes correctly against Hetzner's decode chain because **Hetzner base64-decodes `user_data` before cloud-init sees it** (cloud-init `DataSourceHetzner.maybe_b64decode`, added ≥20.3: *"Hetzner cloud does not support binary user-data. So here, do a base64 decode of the data if we can"*) → raw gzip bytes → cloud-init auto-gunzips → byte-identical `#cloud-config`. Because Hetzner rejects binary user-data, base64 is **mandatory**, so `base64gzip()` is the intended path, not a datasource gamble. Measured: 41,662 B raw → 16,447 B gzip → **21,932 B base64gzip** (the string stored against the cap) → ~10.8 KB headroom. Zero content edits — only the one expression changes. Highly-compressible shell payloads win big here; the web host's payload was 4.3× over even gzipped (hence bake-and-extract), so gzip-vs-bake is a per-host size question, not a mechanism preference.

### 2. A discrimination test must exercise the function under test

The size-guard's critical property (R2): the gzip model must gzip the **real** script bytes, not `"x".repeat(N)` placeholders (x-runs compress ~1000:1 → a re-inlined script would gzip to near-nothing and never trip the budget). The first-draft "discrimination" test injected real bytes through an `extraVars` parameter — but the render helper short-circuited `extraVars` *before* calling `modeledValue`, the function R2 actually depends on. So a regression of `modeledValue` back to placeholders would have kept that test green (the FLOOR assertion caught it, but the test's comment claimed a guarantee it didn't provide). Fix: assert `modeledValue(...)` returns the file's true base64 **directly** (`toBe`), so the test fails immediately if the SUT regresses.

## Key Insight

- **Encoding wrappers on a vendor pipeline are only sound if you can cite the vendor's decode step.** `base64gzip()` works on Hetzner because a specific cloud-init datasource base64-decodes; the same trick fails on datasources that pass raw bytes (AWS EC2 raw, LXC). Confirm the decode path in source before treating a gzip wrap as safe.
- **A test that injects a value through a bypass path proves nothing about the code that path bypasses.** If a test claims to guard property P provided by function F, it must call F. "The injected content raised the size" is satisfied by the injection, independent of F. Two orthogonal review agents converging on this is the signal that the test's *comment* is writing a check the *assertion* can't cash.
- **base64gzip is encoding, not encryption** — secrets stay recoverable from tfstate/API; any future secret-scanner over gzipped envelopes must `base64 -d | gunzip` first.

## Session Errors

1. **Bash CWD drift across calls** — `cd apps/web-platform/infra && terraform ...` in one call left the CWD elsewhere for the next call, and a later `bun test plugins/...` ran from the leftover infra dir → filter matched zero files. **Recovery:** re-run as `cd <worktree-root> && cmd` in a single Bash call, or use `terraform -chdir=<abs>` which is CWD-independent. **Prevention:** already documented (`work/SKILL.md`: "The Bash tool does NOT persist CWD across calls"); one-off, no new rule.

## Tags
category: integration-issues
module: apps/web-platform/infra, plugins/soleur/test
