# Decision challenges — feat-one-shot-6178-soak-followthrough

Persisted headless per ADR-084 (plan Step 4.5 ran inside a Task subagent; no pause). The
operator's stated direction is the default and is what the plan implements.

## DC1 — `earliest=` on the #6178 directive (2026-09-19)

- **What you said:** enrol #6178 with
  `earliest=2026-09-22T13:23:00Z` (= SOAK_END), so the sweeper's first execution of
  `scripts/followthroughs/inngest-soak-6178.sh` is the day-7 reading.
- **What both signals recommend:** `earliest=2026-09-20T00:00:00Z` (enrollment time), keeping
  SOAK_END pinned inside the probe.
- **Why:** with `earliest=` at SOAK_END the very first run under the runner's `env -i`
  (ubuntu awk/jq/date, Cloudflare Access from Actions egress, Guard 3 secret forwarding) IS the
  verdict. Phase 6 proves the probe from a workstation and Phase 7's dry-run dispatch stops at
  the earliest gate before exec, so no runner-environment execution happens before the one that
  matters. An earlier `earliest=` costs two or three NOT YET comments on #6178 and buys three
  real sweeper readings, so a runner-only CANNOT ESTABLISH lands on day 5 with slack, not on
  day 7. It also makes the exit-2 branch live code rather than test-only.
- **What context we might be missing:** the operator may prefer a silent tracker until day 7,
  and the convention notes that non-0/1 verdicts comment daily with no dedup — three extra
  comments may be the cost the operator chose to avoid.
- **If we're wrong, the cost is:** three NOT YET comments on a public issue between 09-20 and
  09-22; if the operator's direction was right and we changed it, nothing about the verdict
  itself changes (the probe's date branch is pinned to SOAK_END either way).

Resolution needed by: the ship phase (the directive is appended at ship time, Phase 7). If
unresolved, the plan's value (`2026-09-22T13:23:00Z`) is used.

## Taste findings from the plan-review named panel (2026-09-19; surfaced, not applied)

Per ADR-084, named-panel (CTO-devex) findings that touch the operator-visible surface are
persisted rather than auto-applied. The plan implements none of these unless the operator says so.

- **T1 — a paste-able resume prompt at the END of the SOAK CLEAN block.** "dispatch the flip PR,
  release the four hcloud images, close #6178" are engineering verbs; the CTO-devex lens suggests
  ending the block with one `/soleur:go "…"` line naming the ADR flip, the four image ids via
  `doppler run -c prd_terraform`, and the close, printed LAST so it survives the sweeper's
  `tail -c 4000` and sits at the top of the fold. Cost if applied: one printf. Cost if not: the
  founder reads three verbs and opens the runbook.
- **T2 — pre-announce the day-7 comment.** One enrollment-time comment on #6178 ("expect a
  sweeper comment here on 2026-09-22 ~18:00Z; ACTION REQUIRED there is the normal outcome, not an
  incident") so the first sight of the heading is not a surprise. Cost: one `gh issue comment`.
- **T3 — the interim (NOT YET) branch is production-dead under `earliest=2026-09-22T13:23:00Z`.**
  The "UNEXPLAINED — investigate now, do not wait for day 7" arm is reachable only from the harness
  and from a workstation run; this is the same fork as DC1 above. If DC1 is resolved toward the
  earlier `earliest=`, T3 dissolves.
