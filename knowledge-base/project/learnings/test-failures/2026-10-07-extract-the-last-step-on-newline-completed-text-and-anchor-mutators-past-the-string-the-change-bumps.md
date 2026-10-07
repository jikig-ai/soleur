---
title: A last-step extractor bounded on \Z needs the trailing newline; sentinel-keyed mutator anchors break on the bump they test
date: 2026-10-07
category: engineering
tags: [test-harness, extraction, mutation-testing, main-health-monitor, anchors]
symptoms: [a step-block extractor returns "" only for the workflow's last step, a mutation battery reports "anchor not found" after the feature legitimately bumps its own sentinel]
module: testing
synced_to: []
component: testing_framework
problem_type: test_failure
resolution_type: code_fix
root_cause: regex boundary on a newline-free string tail; anchors keyed to the literal the change was REQUIRED to touch
severity: low
---

# Learning: extracting the last block of a joined string needs the newline back; mutator anchors must sit past the line the change bumps

## Problem

Two independent extraction failures surfaced while building #9082's monitor-watch
rows (`plugins/soleur/test/main-health-monitor-workflow.test.sh`) and the #9393
cron-egress delivery (`apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`).

**1. `_step_block` could not see the last step.** The suite's helper extracts a
workflow step's body with

```python
re.search(r'^      - name: ' + re.escape(name) + r'\s*$'
          r'(?P<b>(?:.*\n)*?)(?=^      - (?:name|uses):|\Z)', stripped, re.M)
```

`stripped` is a `"\n".join(...)` of non-comment lines — it NEVER ends in a
newline. `(?:.*\n)*?` can only consume lines that end in `\n`, so it cannot
swallow the file's final line; and `\Z` only fires at true end-of-string, which
is reachable only after that line. The result: every step extracted fine except
`Sentry check-in (final)` — the workflow's LAST step — for which the helper
returned `""`. A consumer asserting "the heartbeat reads the mint verdict"
failed on first run with a misleading "the Sentry check-in does not read the
verdict": the verdict was there, the extractor could not reach it. Same-shape
latent bug awaits any future extraction of a final list member anywhere a
`join`-built string meets a `\Z`/`$` bound.

**2. Mutation anchors keyed to the string the feature bumps.** The parity
mutation battery injected credential material / scripts-args / single-line
inline arrays by anchoring replacements on the literal text
`"dpf-web2-remote-exec-v1"` and on the old `mkdir` line. The feature under test
was REQUIRED to bump the sentinel (v1 -> v2, the lockstep rule) and to widen the
mkdir (add /etc/soleur). Five mutators (M4b/M4c/M4d/M4f/M4g) failed to land —
`assert old in s` — not because the guard weakened but because the anchor was
the thing the diff legitimately edited. A first scripted repair then wrote the
pre-mutation buffer (`s` instead of `s2`), silently no-opping the fix.

## Solution

- Bound the extraction on **newline-completed text**: `re.search(..., stripped + "\n")`.
  Costless for every mid-file step, correct for the last one.
- Anchor mutators on **drift-stable neighbours**, never on the literal the change
  under test is obligated to edit: the credential-injection mutators now anchor
  on `file("${path.module}/web-2-ssh-host-key.pub"),` (a line no sentinel bump
  touches), and the mkdir mutators carry the post-change mkdir body.
- After a scripted multi-site edit, assert the NEW text is present before moving
  on — `assert new in s` would have caught the stale-buffer write immediately.
- `grep -oE` cannot match across newlines for destination extraction — use
  `grep -A1` and take the following line (the earlier fix in the same session).

## Session Errors

1. `_step_block` returned `""` for the last step (the `\Z` bound could not fire
   on join-built text) — a consumer row false-failed before the root cause was
   read. **Prevention:** newline-complete the searched text, or grep the line
   directly when the target is the file tail.
2. Five mutator anchors (`"dpf-web2-remote-exec-v1"`, the old `mkdir` line)
   broke on the feature's own required edits. **Prevention:** anchor on a
   neighbour line the feature cannot legitimately touch; when bumping a
   sentinel, grep the mutation battery for the old literal in the same pass.
3. A scripted anchor repair wrote the unmodified buffer (`s` for `s2`) — the
   "fix" persisted nothing. **Prevention:** assert `new in s` immediately after
   the replacement.
4. `grep -oE` was first used to extract a destination from a two-line
   source/destination pair — `grep -o` is line-local and can never span the
   newline. **Prevention:** `grep -A1` then extract the following line.
5. One transient `RESULT: 337 passed, 1 failed` in
   `cron-egress-firewall.test.sh` (row unidentified — the buffer was lost
   before the FAIL line was read); two subsequent runs green at 338/338.
   **Prevention:** capture failing-suite output to a file (`> out.txt 2>&1`)
   before grepping, so a one-off row is identifiable.
6. The MWd behavioural battery's first draft left `$BEHAVE_DIR` unexpanded
   inside a quoted stub heredoc (the child env does not inherit it). **Prevention:**
   bake the path into the generated stub, and mutation-drive the battery itself
   before trusting it (the polarity-swap drive caught and proved the rows).

## Prevention

- Extraction helpers bounded on `\Z`/`$` over `join`-built strings: search
  `text + "\n"` — a one-line robustness fix now in `_step_block`.
- Mutator anchors belong on lines the guarded change is NOT expected to touch;
  when a feature owns a lockstep sentinel, the anchor is its neighbour.
- Behavioural batteries get their own mutation drive before sign-off, same as
  the guards they pin.
