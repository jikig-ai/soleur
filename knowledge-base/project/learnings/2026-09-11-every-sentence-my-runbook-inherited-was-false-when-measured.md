---
date: 2026-09-11
issue: 7946
pr: 8075
category: security-issues
module: rotate-sentry-actions-ro-token, sweep-followthroughs, lint-shell-trace-credential-refusal, lint-followthrough-varq-ban
tags: [credentials, sentry, runbook, inherited-claims, mutation-testing, guard-residue, rule-c, guard-3]
---

# Learning: every sentence my runbook inherited was false when measured

## Problem

PR #8075 retired the personal Sentry token from sixteen files under `scripts/followthroughs/`
and the fresh-host boot-trail, minted a dedicated read-only Internal Integration, and wrote
the rotation runbook plus an ADR-031 amendment. The **code** shipped green through 26 targeted
suites. The **prose** shipped three sentences that were each false at the moment they were
written, and every one sat in a document a future rotation executes:

1. Runbook step 2, from the vendor doc: "Sentry auto-issues the first token on save."
   Measured at the mint: the Tokens panel was empty after save; *New Token* had to be clicked.
2. ADR-031 amendment, from the sibling paragraph it extended: "`event:read` exposes production
   event context (emails, IPs, breadcrumbs)." Measured (`GET …/projects/jikigai-eu/web-platform/events/`,
   20 events): `user.email` and `user.ip_address` are null on all twenty — the privacy policy's
   pseudonymised-`userIdHash` posture holds. What is exposed is titles, messages and tags.
3. The same amendment, written during compound: "the Glossary's ingest-only note on
   `de.sentry.io` predates this reading." The Glossary already carried a 2026-09-03 (#7481)
   correction saying exactly what I had just measured. I had read the sentence I was
   contradicting and not the blockquote under it.

Three hits of one class in one run — the #7310 class
(`2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them.md`).
The mechanism is the same each time: the sentence arrived already-established from somewhere
else (a vendor doc, a sibling paragraph, my own memory of a section), so it read as fact and
skipped the measurement every *number* in the same document got.

## The second class: every guard I wrote had a residue its own spelling could not see

The review panel's findings on the guards were not "the guard is wrong" but "the guard covers
the one spelling you wrote a regex for":

| Guard | What I wrote | What review found it blind to |
|---|---|---|
| Rule C empty predicate | `[ -n "" ]` / `[[ -n '' ]]` | `test -n ""`, `[ ! -z "" ]`, `[ "" ]`; the check ran *after* the `not referenced` return, so a file whose only credential name was deleted in the same edit was never checked; `${V:+}` (empty alternate) and `-z "${V:+x}"` (inverted) both read as guards; a limb surviving in a **comment** counted as a guard |
| varq-ban rule 2 | `for f in "$TARGET_DIR"/*.sh` | any non-`.sh` file, any subdirectory — the "anywhere under" claim in two docs was false |
| Sweeper Guard 3 | `^[A-Z][A-Z0-9_]*$` on the secret name | locale-dependent bracket range; `PATH`/`LD_*`/`BASH_FUNC_*` are well-formed names the sweeper must never forward; the malformed token was quoted **verbatim** into a public comment |
| Boot-trail unbound branch | `::warning::` on both job outcomes | a *successful* apply whose verdict cannot be read is the error case the step exists for |

The common shape: I enumerated the defect I had just seen and wrote a matcher for it, then
tested the matcher against that one fixture. The property ("this predicate can never fire",
"this name is banned here", "this token is safe to forward") has a grammar wider than the
instance, and a guard whose fixture is the instance passes its own mutation row while the
rest of the grammar walks through.

## Solution

**Prose:** each sentence was replaced with its measurement, in place, and the measurement
recorded (`phase-0-scope-probe.md`, the ADR amendment, runbook step 2). The rotation script
now logs the token's length and last four characters so the "which row is stored" question
the auto-issue claim was answering is answered from evidence instead.

**Guards:** each matcher was widened to the grammar and given a fixture per spelling plus a
dispatch mutant per mechanism (`# rule2-grep`, `# rule2-count`, `EMPTY_PREDICATE` degenerated,
`INVERTED_GUARD` degenerated, comment-keeping window). Two mutation-row mechanics surfaced:

- **The mechanism must sit on a line whose deletion leaves the program well-formed.** Deleting
  `done < <(grep …)` produced a syntax error, which is neither a pass nor a fail. The grep now
  lives on a standalone `rule2_hits=$(…)` assignment with an initialiser above it.
- **A mutation anchored on the SUT's textual shape rots with the SUT.** `^EMPTY_PREDICATE = re\.compile\(.*\)$`
  stopped matching when the regex became multi-line; only the row's own "mutation did NOT
  land" guard prevented a vacuous green. Keep that guard on every dispatch row.

One more measurement changed a rationale after it was written: the CRLF row's comment said
the stripped `\r` would make the *secret name* fail validation. Running the strip-less copy
showed the *script path* fails the on-disk check first and the tracker is skipped under a
green run with no comment — a worse outcome, and the row's discriminating assertion had to
move from the exit code to the posted comment.

## Key Insight

**A sentence inherited from a vendor doc, a sibling paragraph, or your memory of a section is
a claim you have not made yet.** For every causal or universal sentence a diff ADDS to a
document someone will execute (a runbook step, an ADR "exposes X", a Glossary note), name the
command that falsifies it and run it before the sentence lands — the same discipline every
number already gets. Corollary: before writing "the sibling section says X", read the sibling
section to its end; corrections live in blockquotes under the sentence they correct.

**A guard's fixture must be the grammar, not the instance.** After writing a matcher for the
defect you saw, list the other spellings the language allows for the same defect and add one
fixture each; the review panel found four to five per guard here, and none needed a new idea
— only a wider `re`.

## Prevention

- Runbook/ADR claims about vendor behaviour ("auto-issues", "exposes", "ingest-only") are
  measured at the moment they are written and cite the measurement; the review skill's
  prose-falsifier rule applies to compound-phase edits too.
- Every guard PR carries a "spellings" list per matcher (test forms: `[`, `[[`, `test`;
  negations; empty alternates; inversions; comment placement) with a fixture per row.
- Dispatch mutants delete a standalone marker line; every mutation row keeps its "did NOT
  land" guard.

## Session Errors

1. **`sed '\|…\|d'` deleted nothing** — Recovery: Python. — Prevention: one-off; use a
   non-`|` delimiter or Python for path-bearing patterns.
2. **G2-M3 mutation did not land, twice** (escaped quotes; then a multi-line regex broke the
   single-line anchor) — Recovery: the row's own guard reported it; anchor rewritten with `/ms`.
   — Prevention: keep the "mutation did NOT land" guard on every dispatch row; anchor on a
   marker comment rather than the SUT's syntax where possible.
3. **Sweeper suite died silently under `set -e` in `g3_run`** — Recovery: `bash "$sut" … || rc=$?`.
   — Prevention: `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`.
4. **guard-vacuity ARM 10d rejected a case counter inside verdict helpers** — Recovery: pass/fail
   terminal + `assert_*` wrappers moving `TOTAL` at the call site. — Prevention: ADR-193 shape
   from the first line of a new suite.
5. **AC13d bare `doppler` grep false-failed on `doppler_retry`; AC13i tripped on my own comment**
   — Recovery: anchor on `doppler (secrets|run)|DOPPLER_TOKEN`, comments reworded. —
   Prevention: `cq-assert-anchor-not-bare-token`; never put the banned literal in a comment
   next to the assertion that bans it.
6. **Plan AC literal counts drifted three times (AC-12, AC-24)** — Recovery: explicit
   amendments with the re-measured value. — Prevention: derive counts (`awk` over rows) or
   anchor on `^\s*source` rather than a bare token, then quote the command in the AC.
7. **`test-all.sh` rc=4 (sibling gate in flight)** — Recovery: 26 targeted suites. —
   Prevention: expected; run targeted suites and say which commit the full run covered.
8. **Filing gate refused `gh issue create` twice (body via shell var) and refused a deferral
   as inline-sized** — Recovery: body in its own step; deferral fixed inline. — Prevention:
   `wg-defer-only-after-inline-triage` is doing its job; write the body to a file first.
9. **Rotation probe instrument wrong three ways** (`.links.regionUrl` on `/api/0/`, org-events
   without `field=`, a monitor slug that does not exist) — Recovery: fixed before the live
   run; probe table collapsed to one row per (host, endpoint class). — Prevention: dry-run
   every probe row against the real host before it becomes a cutover gate.
10. **"Sentry auto-issues the first token on save" was false** — Recovery: *New Token*
    clicked; runbook, ADR and tasks.md corrected. — Prevention: Key Insight §1.
11. **`statsPeriod=7d` invalid on the project-issues endpoint** (masked on main by the dead
    slug's 404) — Recovery: `14d`. — Prevention: a dead destination masks every later error;
    re-exercise a probe end to end after moving its host or slug.
12. **Write tool "file modified since read"** on the rotation-script rewrite — Recovery:
    heredoc via Bash after confirming disk == HEAD. — Prevention: one-off.
13. **The PreToolUse credential guard blocked a Bash heredoc twice because the heredoc's
    prose quoted the snapshot subcommand it guards** (the runbook sentence; then this file's
    own error list) — Recovery: reworded the runbook sentence; wrote this file with the Write
    tool. — Prevention: accepted (the hook matches command text and is fail-closed by design);
    documentation that names the guarded command goes through the Write tool, not a heredoc.
14. **CRLF fixture emitted raw CR into JSON** — Recovery: doubled backslashes so jq decodes the
    escape. — Prevention: one-off; `printf` inside a JSON literal needs the escape, not the byte.
15. **CRLF row's rationale was wrong** (name vs. script path) — Recovery: ran the strip-less
    copy, corrected the comment, moved the discriminating assertion to the posted comment. —
    Prevention: Key Insight §1 applies to test-row comments.
16. **Dispatch mutant produced a syntax error** (deleted `done < <(…)`) — Recovery: standalone
    assignment line with initialiser. — Prevention: Solution §mutation mechanics.
17. **Scratch copy of the infra suite resolved `$DIR` to the scratchpad** — Recovery: `DIR`
    pinned to the real tree. — Prevention: one-off; a mutant copy of a `$DIR`-relative suite
    must pin `DIR`.
18. **shellcheck SC2078 on an intended-defect fixture** — Recovery: disable directive with
    reason. — Prevention: one-off.
19. **`lint-trap-tempfile-ownership` red on my own `mktemp`; vacuity ledger 47→48 on the new
    floor** — Recovery: owning trap; file promoted in `guard-vacuity-floor.test.sh`. —
    Prevention: run the two lints before committing any suite that allocates a tempfile or
    gains its first floor.
20. **Two unmeasured claims in the ADR-031 amendment** ("exposes emails, IPs"; "the Glossary
    predates this reading") — Recovery: measured (20 events, PII null) and read the Glossary's
    2026-09-03 blockquote; both sentences replaced. — Prevention: Key Insight §1.
21. **Forwarded (plan phase): Playwright MCP + GitHub MCP failed to connect** — Recovery: not
    blocking; `agent-browser` path primary. — Prevention: none needed.
