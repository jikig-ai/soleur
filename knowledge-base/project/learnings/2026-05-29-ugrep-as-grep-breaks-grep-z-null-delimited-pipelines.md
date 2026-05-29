---
title: "Host `grep` is ugrep — `grep -z` silently no-ops NUL-delimited skill pipelines"
date: 2026-05-29
category: integration-issues
module: skills/review (anti-slop), any skill using `grep -z`
tags: [grep, ugrep, null-delimited, anti-slop, review, false-clean, environment]
severity: P2
---

# Learning: `grep -z` matches nothing because the host `grep` is ugrep

## Problem

During `/soleur:review` of the invite-accept fix, the anti-slop Tier-1 scanner
hook reported **"no matching files"** for two changed files that clearly match
its path filter:

- `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx`
- `apps/web-platform/app/(public)/invite/[token]/page.tsx`

The anti-slop collector in `plugins/soleur/skills/review/SKILL.md` is:

```bash
mapfile -d '' -t CHANGED_FILES < <(
  git diff --name-only -z origin/main...HEAD |
    grep -zE '(apps/web-platform/(app|components)/.*\.(tsx|jsx|css)|plugins/soleur/docs/.*\.(njk|css))$' || true
)
```

The first hypothesis was a regex quirk with Next.js route-group segments
(`(public)`, `[token]`). That was **wrong** — the empirical tests showed even a
plain substring (`grep -zE 'invite-actions'`) returned NOMATCH, while the same
pattern **without** `-z` matched fine.

## Root Cause

The host `grep` is **ugrep 7.5.0**, not GNU grep:

```
$ grep --version
ugrep 7.5.0 x86_64-pc-linux-gnu +sse2; -P:pcre2jit; -z:zlib,bzip2,zstd,brotli,7z,tar/pax/cpio/zip
```

In **ugrep, `-z` means `--decompress`** (search inside compressed archives:
zlib/bzip2/zstd/brotli/7z/tar/zip). In **GNU grep, `-z` means `--null-data`**
(treat input as NUL-separated lines). So `grep -z` on this machine tries to
*decompress* the NUL-delimited path list as an archive, finds no archive
member, and matches nothing — for **any** input, not just route-group paths
(locale-independent; reproduced under `LC_ALL=C`).

**Impact:** the review anti-slop scanner silently scans **zero files** on this
operator's machine. It always prints "no matching files" → a **false-clean** that
masks real anti-slop findings on every web-platform/docs PR reviewed here. Any
other skill step that uses `grep -z` for GNU NUL-delimited matching has the same
silent failure.

## Solution

For this PR the change was manually verified slop-free (gold gradient, not
purple→blue; `transition-opacity`/`transition-colors`, not `transition-all`; no
`hover:scale-105`), so no finding was missed. The durable fix lives in the review
skill (filed as a follow-up issue): the collector must not depend on `grep -z`.

Two portable rewrites that work under both GNU grep and ugrep:

```bash
# Option A — translate NUL→newline, then plain grep (no -z):
git diff --name-only -z origin/main...HEAD | tr '\0' '\n' |
  grep -E '<pattern>'

# Option B — paths can't contain newlines in this repo, so drop -z entirely:
git diff --name-only origin/main...HEAD |
  grep -E '<pattern>'
```

If NUL-delimited input is genuinely required, ugrep spells it `--null-data`
(long form), which GNU grep also accepts — so `grep --null-data` is portable
where `grep -z` is not.

## Key Insight

`-z` is one of the few short flags whose **meaning differs between GNU grep and
ugrep**. On any host where `grep` resolves to ugrep, GNU-style `grep -z`
pipelines fail **silently** (no error, empty output) — the worst failure mode
for a gate, because "0 findings" reads as "clean." Prefer `tr '\0' '\n' | grep`
or the long-form `--null-data`; never the short `-z` in committed skill scripts.
Cross-ref: the `./node_modules/.bin/<tool>`-over-`npx` and pinned-runner rules —
same class of "the binary you got is not the binary you assumed."

## Session Errors

1. **`grep -z` silently matched zero files (host grep = ugrep 7.5.0).**
   - Recovery: manually verified the diff is slop-free; pinned root cause via
     `grep --version` + isolated grep variants (with/without `-z`, with/without
     `$`, under `LC_ALL=C`).
   - Prevention: filed an issue to replace `grep -z` in the review anti-slop
     collector with a `tr '\0' '\n' | grep` (or `--null-data`) form; this
     learning documents the environment trap for any future `grep -z` use.
