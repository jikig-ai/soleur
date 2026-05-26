---
title: "tr does not interpret \\xHH hex escapes — use octal \\NNN"
date: 2026-05-11
category: best-practices
tags: [bash, shell-portability, sanitation, log-injection]
related_pr: 3555
related_issues: [3544, 3561]
component: scripts/lib
---

# tr does not interpret `\xHH` hex escapes — use octal `\NNN`

## Problem

(2-4 sentences) When implementing `strip_log_injection` for the daily ruleset bypass audit (#3544), the RED tests for `bypass_actors_drift` and `canonical_file_missing` failed with mangled mode strings (`bypass_actors_drit`, `canonical_ile_missing`). The sanitation helper used `tr -d '\r\n\f\v\x7f'` — the same idiom present in `.github/workflows/scheduled-github-app-drift-guard.yml:283`.

## Root cause

POSIX/GNU/uutils `tr` interpret backslash escapes inside their argument, but the supported set is restricted to `\NNN` (1–3 octal digits), `\a \b \f \n \r \t \v \\`. The `\xHH` hex form is NOT recognized. `tr -d '\x7f'` is therefore parsed as `tr -d 'x7f'` — strip every `x`, `7`, and `f` byte. DEL (0x7F) is left intact.

Empirical repro on this system (uutils coreutils 0.2.2):
```
$ echo "drift_xyz_7f_DEL_$(printf '\x7f')_end" | tr -d '\r\n\f\v\x7f' | od -c | head -1
0000000   d   r   i   t   _   y   z   _   _   D   E   L   _ 177   _   e
```
Note `drift` → `drit` (f stripped), `xyz` → `yz` (x stripped), `7f` → `` (both stripped), DEL=`\177` survives. The fix:
```
$ echo "..." | tr -d '\r\n\f\v\177' | od -c | head -1
0000000   d   r   i   f   t   _   x   y   z   _   7   f   _   D   E   L
```

## Fix

Replace `\xHH` hex escapes with octal `\NNN` form in tr argument sets:

```bash
# Wrong (silently strips x/7/f literals):
tr -d '\r\n\f\v\x7f'

# Right (strips DEL byte 0x7F):
tr -d '\r\n\f\v\177'
```

The drift-guard precedent (`.github/workflows/scheduled-github-app-drift-guard.yml:283`) carries the same latent bug. Fixed in PR #3555's new `scripts/audit-ruleset-bypass.sh:75`; precedent fix tracked separately in #3561.

## Detection signal

The bug is silent in normal operation — the alphabet of strings being sanitized determines whether anyone notices. `bypass_actors_drift` happened to contain an `f`; `app_id_mismatch` does not. **Reliable test:** add an assertion that sanitizing a known-good string (no control bytes) returns it byte-identical:

```bash
[[ "$(printf 'drift_xyz_7f' | strip_log_injection)" == 'drift_xyz_7f' ]]
```

This passes on octal `\177`; fails on hex `\x7f`.

## Prevention

- When porting a sanitation helper between scripts, run an identity-preservation test against a string containing literal `x`, `7`, `f`, plus any other letters that match the hex alphabet.
- Default to `\NNN` octal for any non-printable byte in `tr` argument sets. The `\xHH` form looks portable because shells interpret it inside `$'…'` (ANSI-C quoting), but `tr` does NOT — the bytes pass through unmolested and become a literal char-set.
- When a review agent disputes an empirically verified claim with theoretical reasoning (e.g., "POSIX tr supports hex"), re-run the repro before accepting the agent's framing.

## Session Errors (encountered during PR #3555)

- **`tr '\x7f'` mangled failure_mode literals.** Recovery: switched to `\177` octal. Prevention: above test pattern.
- **PreToolUse `security_reminder_hook.py` blocked first workflow Write.** Recovery: hook exits 2 once per session then allows; retry succeeded. Prevention: hook message is advisory not blocking — read the exit-2 message as "ack and retry" rather than "hard fail."
- **actionlint exit=1 from SC2016 on markdown backticks inside printf.** Recovery: added `# shellcheck disable=SC2016 # markdown backticks, not command substitution`. Prevention: when a printf format string contains markdown backticks, add the disable directive proactively.
- **Edit tool rejected `compliance-posture.md` without prior Read.** Recovery: Read then Edit. Prevention: already AGENTS.md `hr-always-read-a-file-before-editing-it`; defensive habit-only.
- **test-all.sh reported 30/32 → 32/32 across reruns due to bun-test rate-limit flake.** Recovery: re-ran; bun tests stabilized via their fallback path. Prevention: bun-test fallback registers transient API failures even when the test eventually passes — if recurrent, file an issue to make the fallback path silent or async.
- **git-history-analyzer agent disputed `tr '\xHH'` claim with theoretical reasoning.** Recovery: re-ran empirical test, agent claim falsified, kept the `\177` fix. Prevention: when an agent contests an empirical claim with theoretical reasoning, re-run the empirical test before accepting the agent's framing.

## References

- PR #3555 — daily ruleset bypass audit (R15 follow-up D1)
- Issue #3544 — origin issue for the daily audit
- Issue #3561 — drift-guard precedent fix
- `scripts/audit-ruleset-bypass.sh:75` — corrected sanitation helper
- `scripts/lib/canonicalize-bypass-actors.sh` — shared jq projection
- `.github/workflows/scheduled-github-app-drift-guard.yml:283` — precedent with latent bug (tracked in #3561)
- coreutils `tr` info page: `info coreutils 'tr invocation'` — confirms only `\NNN` octal is supported
