---
title: "A denylist of tool names is a bypass list: pin the closed set of lines, scan the rendered form, and drive the guard in its own arm"
date: 2026-10-12
category: workflow-patterns
tags: [structural-tests, mutation-testing, closed-set, terraform-templatefile, guards, allowlist, review]
issue: 9786
pr: 10081
branch: feat-one-shot-9786-strip-plain-id-resolver
---

# Learning: a structural test over a destructive cloud-init path was bypassable three rounds running

## Problem

#9786 (PR #10081, parked draft) strips a dead plaintext-volume resolver arm from
`apps/web-platform/infra/cloud-init-inngest.yml`, the `user_data` of the sole Inngest scheduler
host, whose LUKS volume is the only copy of its data. The structural suite
(`inngest-redis-luks.test.sh`) is the only tier that runs locally, so it carries the property
"nothing in the template formats, wipes or mounts a device other than the one the resolver chose".

- Round 0: the guards matched one spelling in one window (`cryptsetup luksFormat`, `mkfs`, inside
  the first-boot heredoc). The structural seat listed 7 gaps.
- Round 1 widened the DENYLIST (T1.17a-e). Two seats then produced 25 destructive-shaped edits
  that stayed green: a runcmd list item, `sudo`, `then`, `/usr/sbin/mkfs.ext4`, `dd`,
  `cryptsetup erase`, `MAPPER="$DEV"`, a second `DEV=` assignment, and `echo "FATAL"; mkfs ...`
  on one line (the filter that skipped refusal messages also skipped the tail).
- Round 2 pinned CLOSED SETS (T1.17f-j). The verifier then showed the helper patterns could not
  see the template's own escape form: Terraform needs `$${x}` for a literal shell `${x}`, so a
  pattern for `${DEV}` or `${x:-y}` never matched a real line.

## Solution / Key Insights

1. **A denylist of command names is a list of the shapes you thought of.** Each new
   command-position shape (list item, `sudo`, `then`, path prefix, `dd`, an alias such as
   `cryptsetup erase`) is a fresh bypass, and widening the list per finding fixes the instance.
   The class fix is a closed set: normalise the file once (drop whole-line comments, join
   backslash continuations, trim indent), then require the set of lines that mention ANY
   device-touching token to EQUAL a reviewed literal list, whole-line and in order. A new line in
   any shape must edit that list in the same commit, and the failure prints a diff. Pin device
   variable assignments the same way, and deny the indirection forms the token list cannot see
   (`eval`, a variable or `${x:-y}` as the command, `sh -c`, `xargs`, `exec`, a redirect or `tee`
   to a device variable).
2. **Normalise to the form the consumer reads, then prove the patterns see it.** The helper
   patterns were written against the shell a human reads and run against the file Terraform
   reads. Collapse `$${` to `${` before scanning, and add a control row that feeds the escaped
   bypass shapes to the very patterns and requires a hit. Ask of any scan "what else did this
   file's escaping or templating encode in the bytes I match?"
3. **A guard is a statement, not a shape.** `[ '${cfg}' != prd ] || exit 1` as a one-literal
   denylist fails open for every other value, so the guard became an allowlist
   (`case '${cfg}' in rehearsal_*) ;; *) ... exit 1 ;; esac`). Pinning its head and tail text passed
   a guard whose middle never exits. A driver that ran the single line with `STAGE` unset passed
   `[ "$STAGE" != unpointed_raw_refused ] && exit 1`, which on the host (where the stage sets
   that literal one line earlier) falls through to `luksFormat` on `prd`. Drive the arm's own
   segment, from the label to the next statement, with the stage's real state preset and a
   sentinel after it, across the config values that must differ.
4. **A mutation script's anchor must be unique.** `text.replace(old, new, 1)` on a string that
   occurs earlier in the file mutates the wrong line and reports a false survivor (twice here,
   on a `; exit 1 ;; esac` that also ends an unrelated `volume_ids` check). Assert the anchor
   occurs once, assert the file changed, run the unmutated control first, restore from a
   backup and `cmp`.
5. **Say what the closed sets do not see.** Comment the residual in the test itself (a write on a
   line naming none of the tokens, via a new wrapper function or a command substitution) and name
   the backstop (the loopback tier on real devices, review). A comment that claims a general
   guard is the next reviewer's finding.

## Session Errors

1. **Widened a denylist per finding instead of closing the class** — Recovery: closed sets T1.17f-j
   plus 28 mutants — Prevention: when a seat reports one bypass shape of a token denylist, ask for
   the closed-set form before widening.
2. **Scan patterns written for the shell text, run on the Terraform source (`$${x}`)** — Recovery:
   `_norm_rendered` plus control row T1.17k — Prevention: scan the rendered form and add a control
   that feeds the escaped bypass shapes.
3. **Single-line guard driver with unset stage state** — Recovery: arm-segment drive (T1.16i) —
   Prevention: drive guards in their arm with the stage's state.
4. **First-occurrence replace in the mutation script hit an unrelated line (false survivors)** —
   Recovery: re-anchored on the guard's own message — Prevention: assert a unique anchor.
5. **ugrep rejected a `}|` alternative and printed empty counts** — Recovery: simplified the
   class to `[^[:alnum:]_]` — Prevention: read stderr of a measurement before trusting a zero.
6. **A ledger edit searched the escaped `—` while the file holds the literal dash**; the edit
   asserted and aborted before writing, but a concurrent lint printed PASS on the unchanged text —
   Recovery: read the traceback, redid it with the literal character — Prevention: write the file
   only after every replacement asserted, and confirm the diff before reading a lint result.
