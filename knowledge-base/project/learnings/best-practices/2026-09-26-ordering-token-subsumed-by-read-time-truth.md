---
module: soleur:plan
date: 2026-09-26
problem_type: best_practice
component: plan_review
symptoms:
  - "issue #8966 prescribed a monotonic saveSeq token for HTTP/WS save-outcome ordering"
  - "plan review found every outcome application already reloads truth before applying"
  - "the ordering guarantee dissolved once GET-derived staleness was authoritative"
root_cause: mechanism-redundant-with-read-path
resolution_type: design_principle
severity: medium
tags: [plan-review, ordering, ws-frames, read-time-derivation, c4, mechanism-minimality]
---

# An ordering token is redundant when every consumer re-reads truth before applying

## Problem

Issue #8966 item 2 prescribed "a monotonically increasing save identifier carried through
both paths" to fix last-applied-wins races between an HTTP save response and a
`c4_diagram_saved` WS frame. The brainstorm accepted the mechanism; plan Phase 4.5's
advisor and the plan-review panel (DHH + code-simplicity, independently) demolished it:
`applySavedOutcome` does `await reload()` *before* applying every outcome, so once the
GET response carries an authoritative derived `stale` field, ordering tokens protect a
boolean that is no longer outcome-carried. The cut deleted ~12 files of plumbing
(WS schema, types, dispatcher, client watermark) *and* removed a hole the token itself
created (a superseded outcome minting the newest seq could resurrect a stale banner over
a fresh diagram).

## The principle

**Before designing an ordering/sequence token for event-vs-response races, check whether
the consumer already re-reads authoritative state inside the apply path.** If it does,
the race is cosmetic — the fix is making the read authoritative, not ordering the
out-of-order writes. Ordering machinery (minted seqs, wire fields, client watermarks,
rolling-deploy compatibility) is only warranted when the apply path must trust the
event's payload *without* a re-read.

Corollary surfaced the same day: when you *do* need ordering, mint at
**outcome-determination** (the ok-return), not call entry and not mid-write — both let a
later-determined outcome carry an earlier seq. And a per-key bucketed counter buys
nothing over a single wall-clock-floored counter when the keyspace is a singleton
(`isC4DiagramPath` admits one dir).

## Companions worth reusing

- **Tree-diff beats commit-ordering for "did X change since artifact Y".** Comparing the
  current Contents listing's blob shas against the newest artifact-commit's `git/trees`
  subtree is fixed ~3 calls regardless of file count, immune to `committer.date` skew
  (pusher-controlled — backdateable), and catches deletions that per-file newest-commit
  scans structurally miss.
- **A precedence contract needs three values:** `stale` present = authoritative, absent =
  untouched, and the failure path must emit *absent* (a `?? false` normalize-and-sync is
  the bug shape).
- **`gh issue create` filing-gate exits:** a deferral ≤100 lines/≤4 files is REFUSED at
  exit 2 (do it inline); small mandated deferrals must take exit 3 —
  `Mandated-By: <rule-id>` on its own line. Also: milestone flag first, and
  `Fix-Size:` needs bare digits (`~60` fails the regex and reads as absent).
- **Pencil headless:** `@pencil.dev/cli` is deprecated; `@pen.dev/cli` installs with
  `--ignore-scripts` (sharp postinstall fails on node-gyp). The `--agent claude` path
  shares the operator's weekly Claude subscription — when rate-limited, hand-authoring
  the `.pen` JSON (frame/text tokens from `knowledge-base/product/design/**`) satisfies
  the wireframe gate; the artifact is what the gate verifies.

## Session Errors

1. `write` of the plan file rejected by `iac-plan-write-guard.sh` — the Non-Goals line
   mentioned "installing graphviz" (a *rejected* alternative). Same false-positive class
   as the spec.md rejection earlier in the session; the `iac-routing-ack` opt-out is the
   designed exit.
   **Prevention:** add the ack proactively on any plan/spec that quotes a rejected
   infra-flavored alternative; flagged for guard owners as an overbreadth candidate
   (scanning Non-Goals sections).
2. `write` tool rejected an oversized payload (`missing required fields` — the JSON was
   truncated mid-content on a ~490-line file). **Prevention:** split documents >~300
   lines into `write` + heredoc `cat >>` appends, or write skeleton + `edit` sections.
3. `edit` failed on a stale `old_string` after the rejected write had left the file at
   skeleton state. **Prevention:** re-read the actual file after any rejected write —
   never assume prior content survived.
4. `gh issue create` denied three times (missing `--milestone`; then the filing gate —
   `~60` unparsed by the `Fix-Size` regex and the inline threshold refusing small
   filings). Resolved via `Mandated-By:` whole-line exit.
   **Prevention:** the companion list above; the exits are correct-by-design.
5. Pencil `check_deps.sh --auto` failed twice (deprecated package + sharp node-gyp
   build); `--ignore-scripts` on `@pen.dev/cli@0.3.8` landed it, then the agent path hit
   the weekly Claude limit. **Prevention:** the headless notes above; on this host the
   `.pen` artifact is the deliverable, not the generator.
