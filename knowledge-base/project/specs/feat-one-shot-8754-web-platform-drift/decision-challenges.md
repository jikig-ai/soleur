# Decision challenges — feat-one-shot-8754-web-platform-drift

Recorded headless by `soleur:plan` + `soleur:plan-review` (2026-09-25). These are informational:
each keeps the direction the plan adopted and says what a reviewer recommended instead.

## Taste — two PRs instead of one

- **Adopted:** PR-A (inngest firewall binding, no destroy, no ack) merges first; PR-B (standing
  drift tail, carries the one `[ack-destroy]`) follows.
- **Dissent:** DHH and the CTO devex pass would fold both into one PR to save a review/merge cycle,
  since PR-A's merge apply changes nothing new.
- **Why the split stands:** the inngest host has no Hetzner firewall today and #8833/#8834 make an
  inngest replace plausible within hours; the replace must carry the fix, and PR-B's destroy +
  import carry the only post-merge failure modes that could hold it up. Advisor, CTO (first pass),
  code-simplicity and architecture-strategist concur with the split.
- **If wrong, the cost is:** one extra review and merge cycle.

## Taste — destroy `ZOT_HEARTBEAT_URL` instead of forgetting it

- **Adopted:** destroy (bare `-target` on the orphaned address, `[ack-destroy]` in the squash body),
  matching the brief's direction ("before letting zot_heartbeat_url_prd be destroyed").
- **Dissent:** DHH would `removed{destroy=false}` (forget) to drop the ack machinery, the merge
  window and the cancelled-apply recovery; the cost is one dead secret left in Doppler `prd`.
- **If wrong, the cost is:** a merge-window constraint on PR-B and a documented recovery PR if its
  apply is cancelled.

## Taste — a forcing function for the "operator-applied exclusion" class (not in scope)

- **Adopted:** fix the eight members of the standing tail; file a follow-up.
- **Dissent:** the CTO devex pass recommends, in this change, turning `OPERATOR_APPLIED_EXCLUSIONS`
  (~70 entries) into a map from address to its apply route with a parity assertion, and a drift
  alarm when the same address drifts for 14+ days (#7316 went 7 weeks unnoticed).
- **Why deferred:** auditing ~70 entries' routes is a separate change with its own review; this
  run is item 1 of a sequenced backlog. Tracked by the follow-up issue the work phase files.
- **If wrong, the cost is:** the next never-applied exclusion drifts silently until the follow-up
  lands.
