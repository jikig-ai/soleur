# Decision Challenges — feat-one-shot-12418-oracle-stale-base

Planning ran in a pipeline subagent with no Task/Agent spawn tool, so technical forks that the
delegation rule would route to `soleur:engineering:cto` are recorded as `pending - assumed` —
the ship-phase remedy is to spawn the CTO (at most two attempts) and convert each row to a
`Ruled by CTO agent, <date>:` cell before merge.

| Item | Class | Ruling |
|------|-------|--------|
| `base_sha` output on pull_request — emit the resolved merge-base SHA or keep emitting `HEAD^1` (p1) while `diff_base` becomes the merge-base | technical | Ruled by CTO agent, 2026-11-09: emit the resolved merge-base SHA - zero workflow consumers (audit-only output per ci.yml:370) and the field's documented meaning is the base the diff ran against, so emitting p1 would record a base nothing diffed |
| Live-base resolution order — try payload `pull_request.base.sha` (verified resolvable) first then `git fetch origin $PR_BASE_REF`, or fetch unconditionally | technical | Ruled by CTO agent, 2026-11-09: fetch unconditionally (git fetch --no-tags origin $PR_BASE_REF to FETCH_HEAD) - payload-first leaves the event-to-run staleness window the fix exists to close (merge-base of a stale-but-resolvable base.sha yields itself), while unconditional fetch is always-current, one code path, and fail-closed on fetch failure |
| Tombstone shape for retired-probe comments — drop the basename and cite `#9728`, or keep the full script path in dated comments | technical | Ruled by CTO agent, 2026-11-09: drop the basename and cite #9728 - the residual-reference AC is a universal zero grep over scripts/ .github/ .claude/ plugins/ and no gate greps comments for the basename as a live-reference check (follow-through-directive-gate validates new directive script= paths against disk, not comments) |
| ADR-276 — append a dated amendment note recording the #12418 diff-base correction, or leave the ADR untouched | technical | Ruled by CTO agent, 2026-11-09: append a dated amendment note to ADR-276 - the ADR is live (status: adopting), append-only by its own governance, and its scope-bound text names HEAD^1 as the pull_request base, so an unamended record would diverge from shipped behavior; the note must scope the change to diff-base derivation only since the shape guard and HEAD^1 driver sourcing stay |
