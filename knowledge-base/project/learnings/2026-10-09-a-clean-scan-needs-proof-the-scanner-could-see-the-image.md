# A clean scan needs proof the scanner could see the image, and a canary on a different input does not give it

**Issues:** #9826 (W3 image CVE scan), #9858 (monitor routing), #9825 (verify-migrations skipped) · **PR:** #9856 · **Date:** 2026-10-09

## Problem

The W3 plan gave the vulnerability scan a canary (a known-vulnerable coordinate that must be flagged) and a DB-age
check, and the CPO's three conditions were all implemented and tested. A four-seat review still found the scan
could read clean while blind, in four ways the plan's own gate list did not name:

1. **The canary scanned a purl, the target was an image.** If Grype cannot identify the image's OS it matches no distro
   advisories, exits 0 and prints `matches: []`: a valid digest, a fresh DB, a firing canary and a "clean" image. The
   canary proves the DB can match a coordinate, never that the cataloger saw this image. Fix: require `distro` in the
   report (`distro-unknown` is unmeasured). An exit-0 empty result is the worst case for any scanner.
2. **`doppler run --only-secrets X` passes an EMPTY value.** It fails only when the secret is missing, so a blank or
   rotated token ran the whole scan and shipped nothing, with a green heartbeat. In CI the sink must be required
   (`no-sink`), and the step that fetches the token must refuse an empty one.
3. **A public repo turns observability into disclosure.** The CTO ruling asked for a per-finding job summary and a JSON
   artifact; on a public repository both publish the production image's unpatched-package list. The design became
   counts-only in public and detail only in the private sink, with Grype's own stdout/stderr redirected to a 0700 file
   and failures classified into a fixed vocabulary (`auth`, `not-found`, `network`, `db`) from that file without
   printing any of it.
4. **A notify-only tracker must never exit 0.** The follow-through probe's exit 0 closes the tracker, and that tracker
   was the only open item carrying the human criteria (false-positive rate, triage, sign-offs). A closed issue reads as
   done. The convention has a notify-only vocabulary (2 not-yet, 3 cannot-establish, 5 action-required) for exactly this.

Process findings from the same session:

- **A scanner that walks `git ls-files` cannot see an untracked file.** The fixture-relative ratchet passed locally with
  the new script untracked and went red after the first commit. Run repo-wide ratchets on the COMMITTED tree (or
  `git add -N` first). The only guard that rule recognises is the canonical `assert_fixture_dir`, copied byte-for-byte.
- **A new Sentry cron monitor touches five registries**, none of them named in the plan: the routing map (the two-PR
  rule forbids routing it in the same PR, so file the routing issue immediately and cite it), the non-Inngest monitor
  set in `function-registry-count.test.ts`, the cron-count comment that `sentry-monitors-audit.test.sh` T25 greps, the
  C4 edge counts in `model.c4` (parity-gated), and a `README` count. A plan that adds a monitor should list them.
- **A `credentials_required` waiver raises a corpus baseline by design** (one reviewable diff line with PLACEMENT / TRUTH /
  NO SUBSTITUTE justification). Confirm the discoverability command is actually runnable first: `betterstack-query.sh
  <marker>` exits 64, the form is `--since/--grep/--limit`.
- **A mutation battery's survivors have two readings.** Of the first-run survivors, one (a duplicated write) was an
  equivalent mutant and was redone as a true reorder; the rest were fixture gaps (symmetric fixtures: medium == low;
  a wrong-length hex sha; a non-package gating row; a wrong-marker row that was ALSO invalid for another reason, so a
  second guard hid the first). Make the fixture differ on exactly the axis the mutant changes.
- **A test that runs the SUT must `cd` into its sandbox.** A mutant that removed the absolute-path guard wrote
  `relative-marker.json` into the repository root; the suite checked the wrong directory.

## Prevention

- For any scan/verification step, list what makes an exit-0 empty result indistinguishable from "clean" and require a
  positive signal about the TARGET (not a canary on a different input).
- In a public repo, treat job logs, summaries and artifacts as public output in the plan's User-Brand Impact section.
- A sink an operator must read needs a required-in-CI mode; an optional sink turns misconfiguration into green.
- Notify-only probes for trackers that hold human criteria; never exit 0.
