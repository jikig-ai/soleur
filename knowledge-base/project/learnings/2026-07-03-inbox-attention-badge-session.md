# Learning: Inbox attention-count badge — hook-gated Bash chains, SWR warm-cache honesty, and block-removal consumer tracing

**Date:** 2026-07-03
**Branch:** feat-inbox-attention-badge
**PR:** #5931

## Problem

Move the dashboard email-triage "Needs attention" block off the Dashboard and
surface it as a count badge on the Inbox left-nav item. Purely presentational,
but `brand_survival_threshold: single-user incident` — the badge must never
under-represent unhandled statutory/legal/security triage items.

## Key Insights

### 1. A PreToolUse hook denial rejects the ENTIRE Bash tool call — stage before you commit

The `brand-hex-commit-gate` (and any PreToolUse hook) denies the **whole** Bash
command string. A `git add <files> && git commit -m …` chain that the gate
blocks means the `git add` **never runs** — the index silently keeps the
previous (stale, raw-hex) version of the file. The next "fixed" commit attempt
then re-fails against the *unstaged-fix* index, which looks baffling ("but I
edited the file!").

**Fix:** run `git add` as its own Bash call, verify with `git diff --cached`,
then `git commit` as a separate call. This is the same root cause as
[[2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn]]
(heredoc body + hook-gated `gh issue create` in one command) — generalize it:
**never chain a state-mutating prep step (`git add`, `cat > file`, `mkdir`)
before a hook-gated command in a single Bash call.**

### 2. The brand-hex gate scans COMMENTS, not just class strings

Three commit rejections in a row: `bg-[#2f2f2f]` (the className), then `#2f2f2f`
in the component's explanatory **comment**, then `#141414` in a **test**
comment. Raw hex anywhere in staged UI/test content trips the gate. When
introducing a design token, refer to it by name ("the soleur-bg-badge token"),
never quote its hex value in prose. (The token-definition file `globals.css` is
exempt by the commit gate, though the advisory anti-slop scanner still flags it
— a known false positive there.)

### 3. SWR honesty contract: omit on `data === undefined`, NOT on `error`

The first cut guarded the badge with `if (error || data === undefined) return
null`. Multi-agent review (code-quality) caught that on a **warm-cache transient
revalidation error** SWR keeps the last-good `data` AND sets `error` — the
`error ||` short-circuit then **blanks a known-good count**, and a vanished
badge reads as a false "0" (exactly the single-user incident the feature must
avoid). Fix: omit only when `data === undefined` (cold load / cold error); keep
rendering the last-good count on a background error, mirroring the list surface's
own stale-on-error UX. A `warnSilentFallback` on SWR `onError` keeps a
persistently-degraded count observable (`cq-silent-fallback-must-mirror-to-sentry`).

### 4. Removing a UI block: trace EVERY consumer of the block's data variable

Deleting the email-triage block (`page.tsx`) was not a self-contained deletion:
the block's `emailItems` variable was *also* load-bearing in two conversation-
less empty-state gates (`… && emailItems.length === 0 && …`). Removing the block
without those gates would not compile; removing them silently changes behavior
(a 0-conversation operator with pending items now sees the empty state, with the
items surfaced via the badge instead). `grep` every reference to the block's
data variable before declaring a block removal "just a deletion", and decide the
behavior change for each consumer deliberately.

### 5. Collapsed-rail count badge must not hijack the nav link's accessible name

In the icon-only collapsed rail the "Inbox" label span is `md:hidden`
(display:none), so a labelled corner-dot becomes the link's **entire** accessible
name — dropping "Inbox" (which sibling collapsed items get from `title`).
`aria-hidden` the collapsed dot (count stays a visual-only cue there); keep the
`aria-label` only on the expanded pill, where it composes with the visible label.

## Session Errors

1. **Hook denied whole `git add && git commit`** — the `add` never ran; index kept the stale raw-hex file. **Recovery:** stage in a separate Bash call, then commit. **Prevention:** never chain a state-mutating prep step before a hook-gated command in one Bash call (Insight 1).
2. **Commit blocked 3× by brand-hex gate** (className hex → comment hex → test-comment hex). **Recovery:** switch className to the token; drop the literal hex from comments. **Prevention:** refer to tokens by name in prose (Insight 2).
3. **Bash CWD drift** — the tool persists CWD; a re-`cd` and a repo-root grep failed. **Recovery:** use explicit/absolute paths. **Prevention:** prefer absolute paths in a worktree; don't assume CWD from a prior call.
4. **nav-states e2e gate uninstallable on ubuntu26.04-x64** (Playwright 1.58.2, no supported chromium). **Recovery:** confirmed the #5009 discriminators (diff doesn't touch the e2e spec; changed-surface unit tests green; failure at `browserType.launch`, pre-assertion) and deferred to CI's containerized e2e. **Prevention:** treat the local nav-states gate as best-effort on unsupported host OSes; CI is authoritative.
5. **Anti-slop BRAND-RAW-HEX false positive on `globals.css`** (token-definition file). **Recovery:** none needed — the authoritative commit gate exempts it. **Prevention:** recognize the token-def file as an expected anti-slop FP.

## Tags
category: workflow-patterns
module: apps/web-platform/dashboard
