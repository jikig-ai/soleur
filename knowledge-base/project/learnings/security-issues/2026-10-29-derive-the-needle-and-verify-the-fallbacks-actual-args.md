---
title: Derive the guard's needle from the canonical lib, and verify a fallback's actual arguments before accepting a coverage-regression finding
date: 2026-10-29
category: security-issues
module: inngest-health / Better Stack alert SQL + drift guards
tags: [betterstack, emitter, syslog-identifier, drift-guard, derived-needle, phone-home, inngest]
issue: 8874
pr: 11519
---

# Learning: derive the needle; verify the fallback's actual args

## Problem

Issue #8874: the LUKS wrong-volume alert's stored SQL anchored the probe marker
(`position(message,'SOLEUR_INNGEST_SERVER_PROBE') = 1` + `host_role=dedicated ` + negated devid)
but pinned no emitter — the one consumer the #8846/#8873 sweep left alone. `doppler` event-log
rows quote the marker verbatim and could satisfy the predicate (the position-1 anchor excluded
them only because each begins with `{` — payload accident, not a control).

## Solution

1. One conjunct, canonical literal:
   `AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'` — first conjunct
   after the time filter, matching the file's 8/8 probe-class sibling convention and the lib's
   `INNGEST_PROBE_EMITTER`.
2. The drift guard DERIVES its needles instead of re-pinning literals:
   `unset` + `source "$REPO/scripts/lib/inngest-probe-row.sh" || { FATAL; exit 2; }`, then the
   presence needle interpolates `${INNGEST_PROBE_EMITTER}` (and `${INNGEST_PROBE_MARKER}`), and
   the python mutation needles read `os.environ["MUT_EMITTER"]`. A coordinated tag rename that
   misses the .tf now goes RED — without derivation the literal copy stays green over a blind
   alert while the heartbeat feeder (which follows the updated lib) keeps beating.
3. Added the `exploration_id` identity pin every sibling guard already carried (one `line_is`
   row + one repoint mutation).

## Session Errors

- **Raw-SQL `SELECT *` UNION over hot remote() + s3Cluster archive → TYPE_MISMATCH.** The
  archive arm carries extra columns. Recovery: `SELECT dt, raw` in both arms, `_row_type = 1`
  on the s3Cluster arm only (`remote()` lacks the column — `UNKNOWN_IDENTIFIER`). Prevention:
  copy the established union shape from `scripts/betterstack-query.sh` docs /
  `scripts/lib/*-rows.sh` rather than composing `SELECT *`.
- **A review seat asserted a coverage regression from an unverified payload shape.** It claimed
  the probe's vector-down phone-home fallback emits `marker='SOLEUR_INNGEST_SERVER_PROBE'` rows
  that the new conjunct would newly exclude — a real P2 if true. The CTO ruling checked the
  call site's ARGCOUNT: `inngest-bootstrap.sh:1317` passes only `stage` + `detail`, so `marker`
  defaults to `SOLEUR_INNGEST_BOOT_STAGE`, the message never satisfied the position-1 anchor,
  and nothing was ever counted — a pre-existing blind edge, not a regression. The suggested
  OR-arm would have been dead code admitting zero live rows. Prevention: before accepting a
  "this conjunct newly excludes X" finding, grep the emission site's actual arguments and check
  whether the row ever satisfied the pre-existing predicate. Filed #11526 for the honest
  redesign.
- **`gh issue create` filing gate refused three invocations.** Required: `--milestone`, a
  literal absolute `--body-file` path the hook can read (not /tmp, not relative, no $VARS), and
  a filing exit (`--label meta/machinery` for guard/probe findings, `User-Impact:`+`Fix-Size:`
  pair, or `Mandated-By:` line). Prevention: machinery findings file with
  `--label meta/machinery` and a worktree-resident body file.
- **`emit-decision.sh` failed in a shell with `CLAUDE_PLUGIN_ROOT` unset.** Recovery: export the
  resolved plugin root once per exec block. Prevention: never let a shell assume the root is
  ambient.
- **An `edit` missed its anchor after earlier inserts shifted context.** Prevention: re-read the
  exact current lines before a mid-file edit when earlier edits moved line numbers.

## Prevention / reusable pattern

- In a drift guard, pin a literal that can drift out of sync by DERIVING the needle from the
  canonical constant, not by copying the literal — a literal needle is a third uncoupled copy.
- Guard-family coverage: `exploration_id`, source wiring, and mute knobs are the sibling
  convention's pin set; #11528 tracks the remainder.
