---
module: release/observability plumbing
date: 2026-10-19
problem_type: craft_findings
component: journald→vector→betterstack + workflow annotations + job budgeting
symptoms:
  - "A discriminating probe emitted on container stdout lands at journald PRIORITY 6 — invisible to the Better Stack source arm that admits only PRIORITY {3,4} for ci-deploy.sh-tagged rows"
  - "A peer-supplied .error/.tag echoed into an `::error::` line line-splits a forged workflow command on a `\\n`"
  - "A serial second poll folded into the deploy job's 90m ceiling overflows on the ~160m worst case (4800s + 4800s)"
root_cause: sink_admission_rules_unmodelled
related_issues: [8743]
related_prs: [10577]
related_learnings:
  - knowledge-base/project/learnings/2026-10-19-the-fan-out-proved-acceptance-and-the-release-gate-read-only-web-1.md
tags: [journald-priority, better-stack, vector, workflow-annotation, command-injection, timeout-minutes]
---

# The sinks have admission rules — journald PRIORITY, the annotation alphabet, and the job ceiling

## Problem

Three small mechanics in the #8743 fix, none about the fix's logic — each decides
whether a signal or an action is *admitted* by the sink it was sent to:

1. **journald PRIORITY routing decides observability admission.** Under
   `webhook.service`, container stdout is recorded at PRIORITY 6 and stderr at
   PRIORITY 3; the Vector→Better Stack source's `include_matches.PRIORITY {3,4}` arm
   admits only the stderr stream for `ci-deploy.sh`-tagged rows. `PLUGIN_SEED_PROBE`
   emitted on stdout would have shipped NOWHERE — Docker demultiplexes the container's
   fd 2 to the client's stderr, so the probe goes out `>&2` inside the `-c` script.
2. **Peer/supply-side JSON fields are workflow-command injection surfaces.** A `\n` in a
   peer's `.error`/`.tag`/`.reason` echoes through into an `::error::` annotation and
   line-splits a forged workflow command. Fixed in the fix-round (b9282ef3b0): every
   extracted field is stripped to a safe alphabet before the annotation —
   `PEER_ERROR="${PEER_ERROR//[^A-Za-z0-9._ -]/}"`, `PEER_TAG` likewise, and
   `PEER_EXIT` via `| tr -cd '0-9-'` since a numeric field tolerates a tighter alphabet.
3. **A serial wait needs its own job ceiling.** The peer-verdict poll's first home was
   inside `deploy`'s `timeout-minutes: 90`, shared with web-1's own 4800s status poll —
   but the peer's deploy STARTS when web-1's ends and its wrapper is also 4800s, so the
   serial worst case is ~160m and a slow-but-healthy deploy would have been killed
   mid-peer-poll. The fix is structural, not a bigger number: a separate
   `verify-peer-deploy` job (`needs:`, own `timeout-minutes`) also releases the web-1
   swap lock at `deploy` end instead of outliving the peer wait — the new job only
   READS status and swaps nothing.

## Key Insight

Every sink a signal crosses has an admission rule the producer must know before
emitting: the journald priority your unit ships at (and which priorities the source
filter admits), the alphabet a workflow command line tolerates, the job ceiling your
serial waits must fit. Name the sink's admission rule when adding the emit/assert —
the cost of discovering it downstream is a probe that ships nowhere, a forged
annotation, or a gate killed mid-poll.

## Session Errors

Topical subset (full inventory in the sibling docker-cp learning):

1. **Peer-supplied fields reached `::error::` unsanitized** (caught in fix-round, not
   the first pass). Recovery: safe-alphabet strips at the extraction point.
   **Prevention:** the rule above — strip where the field is read, not at each echo.
2. **Peer poll budget assumed the deploy job's ceiling was shared headroom.**
   Recovery: separate job. **Prevention:** sum serial predecessors (web-1 poll + peer
   window) against the ceiling before reusing it.
3. **Serial N×3s peer curls vs caller's `--max-time 10`** — parallel slot files; see
   sibling learning.

## Recurring-vs-one-off triage

| item | recurring? | disposition |
|---|---|---|
| `::error::` field sanitization | recurring (security craft) | fixed inline; candidate for a hook/reference note |
| journald PRIORITY for discriminating probes | recurring (every future probe) | documented in code comment at the emit site + this learning |
| job-ceiling arithmetic | recurring (any added serial wait) | this learning |

## Route to definition

No plugin edit applied — `knowledge-base/`-only write boundary. Candidates:
`deploy-status-debugging.md` already documents the peers/error-slot taxonomy
(in-branch); the journald-PRIORITY rule belongs wherever the next `PLUGIN_*_PROBE`-style
emit is documented (candidate: the deploy skill's references).

## Related Issues

- Issue #8743, PR #10577 (fix-round commit b9282ef3b0 carries the sanitization).
