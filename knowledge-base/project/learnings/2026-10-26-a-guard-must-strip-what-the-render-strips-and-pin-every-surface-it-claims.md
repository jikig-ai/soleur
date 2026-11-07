# Learning: a guard over rendered text must use the render's own strip, and every surface it claims needs a row that dies without it

## Problem

PR #11139 (#11080) trimmed the Inngest `user_data` template and extended Guard 3 (`inngest-carrier-vocabulary.test.sh`) to scan the template for the retired LUKS-cutover trio. Two guard defects survived the first review round and were found only by fix-round and verification seats:

1. `strip_render` removed comment lines with `[[:space:]]`, but the render's `inngest_rationale_strip` (`inngest-host.tf`) strips only a whole-line `#` followed by a space, tab or nothing, with leading blanks of space or tab. A form-feed-led or `#<FF>` line is KEPT by the render and shipped to the host, yet the guard treated it as a comment and never saw it.
2. The header claimed `infra-config-install.sh` (embedded verbatim in the render via `indent(6, ...)`) was "scanned the same way", but no row failed when that scan was removed. Deleting `|| "$rel" == "$INSTALL_REL"` left the suite green.

## Solution

- `strip_render` is byte-wise: `LC_ALL=C grep -vE $'^[ \t]*#([ \t].*)?$'`. A `terraform console` harness ran the real regex against 30 one-line inputs (CR, VT, FF, NBSP, U+2028, `#x`, `#!`, `## x`) and showed zero divergences.
- A literal 0x0C row (`trio-template-formfeed-led-line`) and an install-script hash-bang row (`trio-install-script-hashbang-line`) each die when the clause they pin is reverted; the floor rises with each row (67 to 69).
- Comment-only template edits cost 0 B because the render strips `# ` lines, so prose moved to comments did the trimming (headroom 280 B to 800 B).

## Key Insight

A scanner that claims to judge "what reaches the host" has two jobs: match the render's strip exactly (same regex, same byte class, same locale), and carry one mutation row per surface it claims, because a claim in a header is satisfied equally by a guard that scans the surface and one that does not. Name the edit that removes the claim and say which row reds; if none does, the claim is prose.

## Session Errors

- **`pgrep -f` blocked by a hook, rejecting the whole Bash call (the edit and the launch in it never ran) while a Monitor read a stale rc file.** Recovery: redo without pgrep and with fresh result dirs. **Prevention:** keep hook-blocked tokens out of compound commands; write the rc file before any reader polls it.
- **Fixture counts drifted from the code they pinned (T5 hard-coded 13 `docker cp`; C0 inventory 174 vs 168).** Recovery: recalibrate from executed numbers. **Prevention:** make the failure message say what to update when the pinned list changes (done for T5).
- **Runbook restage diagnosis said a failed restage leaves the token file empty; the script leaves it absent.** Recovery: corrected in the runbook and template comments. **Prevention:** for each causal sentence a diff adds, run the command that would falsify it (existing review rule).
- **`strip_render` wider than the render regex; install-script scan unpinned.** Recovery: byte-wise strip plus two rows. **Prevention:** see Key Insight.
- **A multi-file Python edit script asserted a precondition after earlier files were already written, leaving a partial write.** Recovery: re-ran only the unwritten part after reading `git diff --stat`. **Prevention:** assert every precondition before the first write.
- **The worktree directory disappeared mid-session; cause not established.** Recovery: `git worktree add` from the pushed branch; nothing lost because every commit was pushed. **Prevention:** push after every commit so a lost worktree costs nothing.

## Tags

category: test-failures
module: apps/web-platform/infra (inngest user_data, Guard 3)
