# Learning: a whitespace fixture that collapes to empty tests nothing — and the fix it meant to pin

PR #12648 / issue #12579 — unsuppressing the `enqueuePullRequest` rejection reason
in `.github/scripts/bump-inngest-bootstrap-pin.sh`.

## Problem

Two fixture-construction traps surfaced during the #12579 review arc, both caught
by fix-round seats rather than the suite itself:

1. **A loud-fail stub arm must still guard the selector.** Adding a `*)` arm to
   `case "${MOCK_GH_ENQUEUE_FAIL:-0}"` that echoes `$MOCK_GH_ENQUEUE_FAIL` raw
   crashed under `set -u` on the *default* path — `0` isn't in the arm list, so
   an unset selector falls into `*)` and the unguarded expansion dies. The new
   `g1.enqueue:position` row (added for a different finding) caught it because
   the crash made the success-path enqueue "reject" — the rejection warning even
   surfaced the stub's own error text, a live demo of the feature under test.
   Fix: `0) ;;` fallthrough + `${MOCK_GH_ENQUEUE_FAIL:-<unset>}` in the `*)` text.

2. **Whitespace-only stderr survives nothing by accident.** A fixture meant to
   exercise the whitespace-fallback guard emitted `printf '\n'` — but `$(...)`
   command substitution strips ALL trailing newlines, so `enq_out=""`,
   byte-identical to the truly-empty arm. The row passed under BOTH the new
   `[[ -n ${enq_reason//[[:space:]]/} ]]` guard and a plain `:-` check —
   coverage-vacuous. The discriminating input is `printf ' '` — a space survives
   capture, flattens/strips to `" "` (non-empty → `:-` misses it), and trips the
   `[[:space:]]`-strip guard. `\t` would NOT work — it's `[:cntrl:]`, deleted
   before the check.

## Also learned

- The affected-gate runner (`gate-or-skip.sh` → `test-all.sh --affected`) can
  legitimately run 40+ min. Wrapping it in `timeout 600` kills the parent while
  the orphaned `test-all.sh` keeps the output pipe open — the verdict is lost
  AND the run still burns the wall time. Run it unwrapped in the background.
- Review dedup found the same whitespace-fallback defect in FIVE seats'
  independent reports — high-confidence signal the class was real, not stylistic.
- `enqueuePullRequest` semantics confirmed: admission gates on the required-check
  SET; refusal ~5s after PR open is expected. ADR-270 addendum records it.

## Prevention

- For every guard assertion, name the mutation that turns it red — and for
  fixture INPUTS, verify the input survives the capture channel (command
  substitution strips trailing newlines).
- New `*)`/loud-fail arms under `set -u`: guard every expansion in the arm's
  own echo text, and make the default selector (`0`/unset) an explicit
  fallthrough arm.
- Never wrap `gate-or-skip.sh` in a short timeout — it is the long pole by
  design; background it instead.

## Session Errors

Ten items (see conversation): the herestring-empty-fallback bug; an AC check
whose sed range caught a sibling `2>/dev/null`; ruling-gate placeholders; a
filing-config rejection; a deepen-pass false trigger; a param-expansion
sanitizer that kept tabs/ESC; the `*)` unguarded-var crash; the `printf '\n'`
coverage-vacuous fixture; a wrong script path; the killed gate verdict.

## Evidence

- Suite: `SOLEUR_FIXTURE_PACKED=1 bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh`
  → 734 pass, 0 fail, `MIN_ASSERTIONS=734`.
- Review: 8-seat panel + 8-seat fix round + verification pass; 0 P1/P2, 12 P3s
  all fixed inline; trailers `Reviewed-By-Soleur` + `Reviewed-Fix-Round`.
