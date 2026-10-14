---
title: "A credential fingerprint must hash the expanded PEM, not the env-form value — and a CI dispatch catches the path bug local tests cannot"
date: 2026-10-11
category: bug-fixes
tags: [github-app, jwt, doppler, fingerprint, ci, workflow, mu1]
module: scripts/probe-github-app-mint.sh
issue: 9995
related: [9972, 10058]
---

# A credential fingerprint must hash the expanded PEM, not the env-form value

## Problem

While building `scripts/probe-github-app-mint.sh` (#9995) — a canary that signs
the same App JWT the mu1 test mints — the fingerprint it printed was computed
over `GITHUB_APP_PRIVATE_KEY` *verbatim*. Review caught it: CI's
`pemFingerprint` (`apps/web-platform/server/github-app.ts`) hashes
`getPrivateKey()`'s return — the `\n`-**expanded** form. The two agree today
only because the stored value happens to carry real newlines; the moment an
operator stores the literal-`\n` variant, the probe's fp silently stops matching
the CI field it exists to correlate against — and the test suite was pinning
the wrong form.

## Fixes (all in review round `dc95590c1c`)

- Hash the expanded value (`EXP` through `$()` so awk's trailing newline does
  not leak in — the capture makes it byte-identical to `getPrivateKey()`).
- `exp` must be `now+540`, never `now+600`: GitHub rejects `exp > now+600` and
  a runner clock 1s ahead reds a healthy credential — the canary would
  reproduce the opaque-401 class it exists to prevent.
- PEM scratch prefers `${XDG_RUNTIME_DIR}` (tmpfs) over `$RUNNER_TEMP` — a
  SIGKILL'd step leaves a disk-backed 0600 file on self-hosted runners.

## The dispatch lesson

A branch dispatch of `scheduled-integration-suites.yml` caught what no local
test could: `bash ../scripts/probe-...sh` relative to the step's
`working-directory` (apps/web-platform) ENOENT'd in the runner context. The
file's own convention — `$GITHUB_WORKSPACE` — was already written down in an
adjacent step's comment (#9947). New workflow invocations of repo-root scripts:
absolute path first, branch dispatch as the wiring proof.

## Method to reuse

A fingerprint/fingerprint-correlation field is a *contract*, not a checksum:
find the producer it must agree with (`pemFingerprint` ↔ `getPrivateKey()`)
and hash the same bytes, in the same form, from the same source.
