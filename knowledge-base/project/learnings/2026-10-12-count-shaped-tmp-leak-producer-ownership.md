# Learning: count-shaped /tmp leaks need producer ownership + a schema-attributable root, not a bigger reaper

## Problem

Issue #10017: `tmpfs-guard`'s count alarm reported ~7,558 top-level `/tmp`
entries — ~7,000 bare `tmp.*` files (agent-executed `mktemp` calls from
skill prose and untrapped scripts: resync-script copies, drafted commit
bodies, scratch text) plus ~650 `rung2-archive.*` dirs from the
birth-readiness gate's rehearsal-hash path. Size-based reaping could never
fix it — the entries are few-hundred-byte files, and a *count* of small
files is a different hazard class than bytes. Bare `tmp.*` is deliberately
`protected` in `tmp-classify.sh` (name-only attribution on a shared `/tmp`
measured ~1,500 false-positive candidates in #6991), so no reaper can touch
the dominant class at all.

## Solution

Producer-side ownership sweep (ADR-129): 23 test suites gained a
`SUITE_TMP` root + owning EXIT trap with all per-case allocs re-routed via
`mktemp -p "$SUITE_TMP"`; session-run producers gained EXIT traps;
function-local producers gained self-disarming `trap 'trap - RETURN; …'
RETURN`; the rung2 archive extractor dropped its deliberate bounded leak for
a basename-anchored RETURN-trap cleanup. Census dropped 70→36 with the
highwater ratcheted to match, and `--census-files` (list derived from the
SAME `census_all` pass that counts) made the member set enumerable.

The dominant class needed a different mechanism entirely: agent-executed
allocations are instructed by `.md` prose that no code census can see. The
CTO ruling's answer was not an allowlist (frozen, and name-signing a FILE
buys nothing — `tc_file_class` has only 3 rows and everything else reads
`unattributable`), but schema-root routing: `mktemp -d -t
soleur-run.$$.XXXXXXXX` mints a dir whose NAME attributes it
(`schema:<pid>`, regex-verified), contents inherit the attribution, and a
fresh Bash-call shell's `$$` is dead within seconds → dead-owner →
reapable by the Phase-4 purge timer past the age floor. The `rm` stays the
primary cleanup; the signed root makes a missed `rm` recoverable — the
first time this leak class had anything under the alarm.

## Key Insight

- **A `trap … RETURN` set inside a function DOES fire when the function
  runs under `$( )`** — measured, not reasoned (bash runs the substitution
  body in a subshell that still honors the arming shell's RETURN trap; it
  does NOT propagate into the caller). It must self-disarm (`trap -
  RETURN` first statement) because a RETURN trap is not function-scoped.
- **A sourced file can replace the sourcing test's EXIT trap** — both
  `test-helpers.sh` and `test-incident-sandbox.sh` COMPOSE via `trap -p`,
  but `content-publisher.sh` installs a plain `trap … EXIT` that clobbered
  the suite's SUITE_TMP trap. The residue leaf caught it; the fix is a
  combined handler re-armed AFTER the source. Any future "sweep traps onto
  files" pass must grep each file for `source` of a non-composing SUT.
- **`rm -rf "$(dirname "$X")"` is an unanchored destructive operand**: if
  the inner `mktemp -d` fails, `mktemp -p ""` falls back to a `/tmp`
  top-level file → `dirname` → `/tmp` → `rm -rf /tmp` at EXIT. The safe
  idiom is `rm -f "$X"; rmdir "$(dirname "$X")" 2>/dev/null` — `rmdir`
  refuses non-empty operands, so the degenerate case cannot delete a live
  dir. Every `rm`/`rmdir`/`rm -rf` operand in a trap or prose instruction
  needs either a basename anchor (`/*/rung2-archive.*`) or a
  refuse-on-weird-input verb.
- **systemd-tmpfiles `e`/`d` cannot express a count-shaped fix** — they age
  a matched directory's *contents*, never the top-level entry shells
  themselves; `rung2-archive.*/` empties but the dir still counts.
- A fix round can introduce a worse hazard than the one it removed — the
  `dirname`-rm-rf form was MY fix-round addition; the targeted-round seats
  exist precisely to catch that.

## Session Errors

1. **merge-pr/SKILL.md text corruption** — a partial string replace turned
   `something` into `somethinXPLACEHOLDERXg`; caught by diff-vs-index
   comparison and restored. **Prevention:** after a scripted replace,
   grep the file for the intended result AND diff --check; never trust a
   silent `str.replace`.
2. **likec4 example reordered deletion before consumption** — the first
   edit `rm`'d the temp output before the counts were read.
   **Prevention:** for "consume then delete" examples, write the read
   step first, then the delete — verify ordering against the example's
   own dataflow, not the diff's.
3. **Guessed path `.claude/hooks/lib/session-state.sh`** (does not exist;
   real file is `plugins/soleur/scripts/lib/session-state.sh`).
   **Prevention:** `git ls-files` the stem before citing a path — a
   remembered path is a hypothesis.
4. **Wrong runbook path guess** (`tmpfs-guard-install.md` found via grep,
   not the first tried path). **Prevention:** `git ls-files` the stem
   before citing a path — a remembered path is a hypothesis.
5. **Missed the non-composing-SUT trap clobber** — `test-content-publisher.sh`
   sources a file that installs its own EXIT trap; my SUITE_TMP trap was
   silently replaced and the suite root leaked. The residue canary's leaf
   delta arm caught it (delta==1). **Prevention:** in any trap sweep,
   grep each target for `source`/`."` of a SUT and check whether the
   sourced file installs a non-composing trap; the leaf registry now
   enforces this for the 23 swept suites.
6. **Silent no-op `str.replace` on an em-dash mismatch** — the ledger
   relabel pass reported success while matching zero rows; a later grep
   caught the stale "(no edit)" cells. **Prevention:** `assert
   s.count(old) == N` before every replace (done in the same-session fix
   scripts after this miss).
7. **`tc_schema_owner_pid` probe fed a full path** where the API takes a
   basename — empty output could have read as a classification miss.
   **Prevention:** check the callee's signature before writing the probe;
   a probe that can't return the looked-for value proves nothing.
8. **ship:926 composite edit broke the trap line** — a replacement put
   `; trap` inside a `#` comment, leaving the quoted handler as a bare
   command on the next line. Caught on read-back. **Prevention:** never
   carry a `; <keyword>` across a newline inside a replacement string —
   comments eat the rest of the line.
9. **Forwarded (pre-compaction):** spec `lane:` absent → defaulted to
   cross-domain; no Task/Agent tool in the plan subagent context →
   review panel applied inline; three rulings were `pending - assumed`
   until the CTO spawn resolved them.

## Prevention routing

- Error 5's class is now structurally covered: the 23 swept suites are
  registered `sh` leaves in `tests/scripts/test-scratch-residue.sh`, so a
  future trap-clobber fails the delta arm, and the ledger documents the
  non-composing-source check as sweep procedure.
- The normative `soleur-run.$$.XXXXXXXX` convention lives at
  `plugins/soleur/skills/work/references/work-scratch-sandboxes.md`
  §"Ad-hoc agent scratch" — the discoverable place an agent looks for
  scratch allocation rules.

## Tags

category: workflow-patterns
module: trap-ownership / tmp-classify / mktemp-census
