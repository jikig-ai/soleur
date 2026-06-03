# Learning: merging a richer doc template into a skill-substitution contract

## Problem

Merging the operator-provided SRE-standard post-mortem structure into the
incident skill's `templates/pir.md` (adding Incident Overview, MTTR/MTTD,
Versions of Components, Lessons Learned, Action Items, etc.) is not a
single-file edit. The template declares a `{{TOKEN}}` contract consumed by two
other surfaces, and the new MTTR/MTTD local-compute introduced a silent-failure
class that multi-agent review caught.

## Solution

1. **Token contract is a THREE-way mirror.** Every `{{TOKEN}}` must appear in
   (a) `templates/pir.md`, (b) the `SKILL.md` Phase 4 substitution table, and
   (c) the `dry-run.sh` heredoc. The cheap gates: `comm -3 <(grep -oE
   '\{\{[A-Z_0-9]+\}\}' template|sort -u) <(... SKILL.md ...)` must be empty,
   and `grep -c '{{' <dry-run-output>` must be 0. Update all three in one pass.
2. **Local duration compute must guard calendar-invalid AND transposed input.**
   An ISO-8601 *format* regex (`[0-9]{2}` for month/day/hour) accepts month 13 /
   day 40 / hour 25, so `date -u -d` can still reject a regex-passing value;
   under `set -uo pipefail` (no `-e`) the failed `$(date …)` returns empty and
   the arithmetic emits a garbage/negative duration with a green exit. Capture
   the epoch with explicit failure handling and halt on a bad date OR a
   `recovery_at < detected_at` transposition — mirror the sibling Art.33
   deadline guard (`2>/dev/null || echo TBD`), don't leave the new block
   unguarded.
3. **Every new operator-prose field joins the first-pass redaction-sentinel
   enumeration.** Adding fields (`version_triggered`, `participants`, …) that
   flow into the draft OR get echoed to the transcript means adding them to the
   pre-echo sentinel scan. The first-pass scan must run BEFORE any phase echo
   (relocate it above Phase 0), since fields like `triggers[]` are printed
   during Phase 3 routing — a Phase-6-only scan leaks a planted secret two
   phases too late.
4. **Retrofit is restructure, never fabricate.** Map existing prose under the
   new headings; absent facts (revenue, MTTD-when-external) become
   `Unknown`/`N/A` with a one-line reason. Preserve every frontmatter field
   (additions only) and, for files with load-bearing audit trails (Phase 8/9),
   retrofit LIGHTLY — add the new top sections, preserve the bespoke blocks
   verbatim. When you add `recovery_at`, reconcile the existing
   `incident_window` end so the PIR doesn't carry two contradictory end
   timestamps.
5. **The sentinel negative-baseline is load-bearing.** `dashboard-error-postmortem.md`
   must stay `redact-sentinel.sh`-clean (Test 1 exits 0). Retrofit it LAST and
   re-run the test; never introduce a new email/UUID/IPv4/real-JWT/token shape,
   and don't "clean up" an existing grep-pattern literal into a realistic token.

## Key Insight

A template that feeds a substitution skill is the producer end of a contract
with at least two consumers (the skill's token table and its dry-run harness).
Treat a "just improve the template" request as a contract change: enumerate the
consumers, move them in lockstep, and gate the parity mechanically. New
local-compute over operator-supplied input inherits the skill's existing
trust-boundary obligations (format-validate, fail-loud, redact pre-echo) —
copy the sibling guard, don't reinvent a weaker one.

## Session Errors

- **iac-plan-write-guard blocked the plan Write on "operator-driven recovery"** — Recovery: rephrased + `<!-- iac-routing-ack: … -->` opt-out. Prevention: avoid `operator[- ]driven` phrasing in plan prose for non-infra changes.
- **Task tool unavailable in the planning subagent** — Recovery: deepen-plan gates run inline. Prevention: expected for general-purpose subagents; fold fan-out inline.
- **Edit/Write to worktree files failed "File has not been read yet"** — Recovery: Read the worktree-absolute path before editing. Prevention: parent-context reads of the bare-root synced mirror do NOT satisfy per-path file-state tracking in a worktree; always Read the worktree path first.
- **`&&`-chained `grep -c '{{'` broke the chain on a 0 count (exit 1)** — Recovery: re-ran with `set +e` / unchained. Prevention: when a zero match-count is the success condition, don't `&&`-chain on `grep -c`.
- **Edit anchored on a unicode arrow (`→`) mismatched** — Recovery: re-grepped exact bytes, used a shorter ASCII-only anchor. Prevention: anchor Edits on ASCII-only substrings when the target line contains unicode.

## Tags
category: best-practices
module: plugins/soleur/skills/incident
