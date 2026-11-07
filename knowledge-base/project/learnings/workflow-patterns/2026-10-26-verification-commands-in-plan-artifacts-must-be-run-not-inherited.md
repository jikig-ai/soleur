---
title: "Verification commands recorded in plan/tasks must produce the recorded result when run"
date: 2026-10-26
tags: [verification, plan-artifacts, uniq-d, grep-H, vacuous-check]
---

## Problem

A plan's Test Scenarios and tasks.md each recorded a "no double-booked publish_date" check that could not produce its recorded expectation:

- `grep -H '^publish_date:' *.md | sort -t: -k3 | uniq -d` is vacuous — `-H` prepends a unique filename, so `uniq -d` can never fire.
- `grep -h '^publish_date:' *.md | sort | uniq -d` always prints pre-existing published-corpus duplicates, contradicting a recorded "→ empty".

## Prevention

Run the exact command an artifact prescribes before recording its expected output. For per-item uniqueness assertions, assert per item (`for d in <dates>; do grep -h '^publish_date:' … | grep -c "publish_date: $d\$"; done` → `1` each) rather than a corpus-wide uniqueness claim — a corpus accumulates legitimate historical duplicates the check then false-positives on.

Companion shape hit in the same session: `gh ... --jq "#<text> \(.f)"` — a `#` reaching jq unquoted reads as a comment, yielding `missing query`; use `--jq '.f'` and prefix text in shell, not in jq.

Found by review panel on PR #11160 (one-shot arc-epilogue run); fixed inline.
