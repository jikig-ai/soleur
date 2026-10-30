# Learning: a resolve pass over a provable subset is a false-resolve, and a projection fixture must model the real payload

## Problem

Two findings four+ review seats converged on in PR #11001 (the Better Stack
incident→GitHub-issue mirror), both invisible to a green harness:

1. **Resolve-on-subset.** `resolve_stale_issues` ran unconditionally after the
   filing pass. When the vendor read was paged (`pagination.next` non-null),
   page 1 was a PROVABLE SUBSET of the open-incident set — but mirror issues
   for page-2+ incidents were "untouched" and got closed with a false
   "resolved upstream" comment, on a mass-casualty day exactly when the mirror
   matters most. The header invariant "'untouched' means 'absent from the
   vendor's open list'" was true only in the unpaged case. Same defect class as
   the incident the file exists to fix (a detector that reads a partial signal
   as complete).
2. **Projection channel.** `attributes.url` was projected into the public
   issue body guarded only by `https://*`. For a *heartbeat* incident the
   vendor `url` IS the heartbeat ping URL — the beat capability the design
   promised never to echo. The test fixture modeled `url` as a harmless
   `incidents/<id>` page, so the ping-URL sentinel sweep gave false confidence:
   the real payload carries the secret through `url`, not `ping_url`.

## Solution

- Gate any resolve/close/delete pass on "the read was COMPLETE": skip resolve
  when paged; treat a saturated `--limit` list the same way (TRANSIENT, never
  a deduped map). Pin it with a fixture pairing partial-read + a live tracked
  row that must survive.
- Sanitize/vendor-shape-check every field before it enters a public artifact
  — including `id` (it lands in markers, ledgers, `awk -v`); drop fields whose
  semantics differ per row type rather than shape-guarding them by scheme.
- Fixture the REAL payload, not the readable one: if a sentinel sweep is
  meant to prove a secret can't leak, the fixture row must place the secret
  in the field production actually puts it in.

## Key Insight

"Untouched ⇒ absent" is only as true as the read's completeness. Any
reconciliation loop that closes/destroys on absence must prove the read was
total (unpaged + unsaturated) or skip destruction. And a projection is a
security boundary: every field in it needs a per-row-type semantics check,
because vendor field names lie about what they carry (heartbeat `url` = ping
URL = write capability).

## Session Errors

- Soak harness caught a self-inflicted `other: unbound variable` (edit added
  the use before the init) — re-run touched harnesses after every batch, even
  "comment-only" edits.
