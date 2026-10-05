# ADR-230: Temporary debug probes are `[DEBUG-<hex4>]`, never `SOLEUR_*` sentinels

- **Date:** 2026-09-19
- **Issue:** #8288

## Status

Accepted.

## Context

Soleur's one log-marker class is permanent. `SOLEUR_*` sentinels are defined only by their
enforcement — `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts` extracts them
from container logs into Better Stack and Sentry, and its drift-guard test reds on an emitted
marker the regex does not know. That class had no removable counterpart: an agent instrumenting
code mid-diagnosis reached for the only vocabulary the repo taught it, and the realistic failure
was a `SOLEUR_DEBUG_*` line — a temporary probe spelled like a permanent marker, which either
registers a telemetry row for a five-minute question (against the operator's marker-population
caution) or trips the drift guard, or is committed by a `test-fix-loop` checkpoint and ships.
Nothing asked, before a checkpoint, a stage or a PR, whether a probe was still in the tree.
`reproduce-bug` (#8288) imports a tagged-probe discipline from the peer `mattpocock/skills`
`diagnosing-bugs` skill; three skills and one CI suite enforce it, so its home cannot be one skill file.

## Decision

Two marker classes, distinguished by lifetime. This table is the **single normative copy**; skills
cite this ADR and carry only spelling, mint, decision rule and cleanup — no SKILL.md reproduces it.

| Dimension | Removable probe | Permanent marker |
|---|---|---|
| Spelling | `[DEBUG-<hex4>]` — exactly four hex characters, bracketed | `SOLEUR_[A-Z_]+`, matched by `MARKER_RE` |
| Mint | Once per investigation, pure bash: `printf '[DEBUG-%04x]\n' $((RANDOM % 65536))` — no `openssl` on a founder-repo path | Registered by hand in `MARKER_RE` and its drift-guard test before the first emit |
| Lifetime | Dies with the fix; removed before any **push**, not only before commit | Outlives the fix: a recurring class or a blind surface |
| Readers | The investigating agent, in the transcript or a local log tail | Better Stack / Sentry via `MARKER_RE`; the operator digest |
| Decision rule | The signal is needed only to answer this bug's question | The signal must still fire after the bug is closed (`reproduce-bug` Phase 1's blind-surface bullet) |
| Payload (R58) | The discriminator only — booleans, lengths, ids, hashes. Never an env value, header, request body, PII or raw user-controlled string: a probe removed before merge has already reached log retention if a preview deploy ran (CWE-532), and user input in a log line is CWE-117 | Whatever the registered row declares, reviewed at registration |
| Cleanup | `git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- ':/' ':(top,exclude)knowledge-base/**/*.md'` prints nothing — top-anchored (the whole repo from any cwd; a `-- .` pathspec run from `apps/web-platform` silently scopes to that subtree), tracked and untracked, either case, no `-I` (a NUL byte or `-diff` attribute would hide a match). Out of its window by design: ignored files (never committed or pushed), submodules (`--untracked` and `--recurse-submodules` are mutually exclusive), a tag assembled by string concatenation, and a tag outside the four-hex shape | None; removal is a registration change with its own review |
| Never `SOLEUR_` | A probe is **never** spelled with a `SOLEUR_` prefix, however temporary; a `SOLEUR_[A-Z_]*DEBUG` emitted on any call-form this tree uses (`echo`/`printf`/bash `log "`, `console.<level>(`, pino `log.<level>({ KEY:`, `logger.<level>(`, `process.std{out,err}.write(`, python `print(`) is a defect Soleur's CI catches; a form outside that list is caught by the prose rule and review, not by the suite | A marker is never spelled `[DEBUG-…]` |
| Placeholder discipline | Prose writes `<hex4>`, never a concrete four-hex tag, so the cleanup grep stays silent on the docs describing it | Prose names the marker literally; the drift guard is the reader |

The exclusion is `knowledge-base/**/*.md`, not the directory: a learning may quote a real tag, and
executables under `knowledge-base/` are still swept. Tree-wide beats diff-scoped because a probe
committed by an earlier checkpoint is in the tree and not in the patch.

## Enforcement sites

1. `soleur:reproduce-bug` Phase 9 (Cleanup) — the grep runs after the Phase 8 report and before the
   loop script is committed; output means probes remain.
2. `soleur:test-fix-loop` — before **every checkpoint commit** and again before the success-row
   `git add -A`; on output, remove the probes and re-run the suite (a probe removal is not a fix
   and never stages as one). This is the site that stops a probe from ever being committed.
3. `soleur:ship` Phase 5.4 — an executed gate (output blocks the PR), the last skill to touch a tree
   before a PR; on a founder repo it is the only pre-PR site.
4. `plugins/soleur/test/debug-probe-residue.test.sh` (Soleur CI) — two predicates over every
   tracked file outside `knowledge-base/**/*.md`: no real `[DEBUG-<hex4>]` tag (either case), and
   no **emitted** `SOLEUR_[A-Z_]*DEBUG` on the call-forms listed in the table (a
   `process.env.SOLEUR_DEBUG_*` read is excluded per line), with in-suite positive controls for
   every listed form, plus a population floor.

The `action-required` label that `reproduce-bug` applies for a `no correct seam` finding is read by
`soleur:operator-digest`, which today runs against Soleur's own repository; on a founder's repo it
is a labelled issue the agent surfaces at the next session, not a digest line.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Prefix grep (`\[DEBUG-`) | Reds on every document naming the convention, this ADR included; the shape of a real tag is the property, not its prefix |
| Diff-scoped grep | Misses a probe committed by an earlier checkpoint; the tree is the population |
| Fold into ADR-071 | Wrong home — that is the import-boundary gate's ADR, and a third consumer (`ship`, `test-fix-loop`) must find the taxonomy without reading a scaffold ADR |

## Consequences

- An agent mid-diagnosis has an unambiguously temporary vocabulary and four sites where a
  leftover probe is caught before it ships; `MARKER_RE` gains no row from debugging work.
- Documentation of the convention must use `<hex4>`; a concrete tag in a skill or ADR reds
  Soleur's CI by design.
