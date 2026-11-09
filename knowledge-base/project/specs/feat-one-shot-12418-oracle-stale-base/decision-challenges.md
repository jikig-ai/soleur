# Decision Challenges — feat-one-shot-12418-oracle-stale-base

Planning ran in a pipeline subagent with no Task/Agent spawn tool, so technical forks that the
delegation rule would route to `soleur:engineering:cto` are recorded as `pending - assumed` —
the ship-phase remedy is to spawn the CTO (at most two attempts) and convert each row to a
`Ruled by CTO agent, <date>:` cell before merge.

| Item | Class | Ruling |
|------|-------|--------|
| `base_sha` output on pull_request — emit the resolved merge-base SHA or keep emitting `HEAD^1` (p1) while `diff_base` becomes the merge-base | technical | pending - assumed: emit the merge-base SHA - the output is audit-only (zero consumers of needs.oracle-selection.outputs.base_sha in .github/workflows/) and its documented meaning is "the base the diff ran against", which after the fix is the merge-base; emitting p1 would record a base nothing diffed |
| Live-base resolution order — try payload `pull_request.base.sha` (verified resolvable) first then `git fetch origin $PR_BASE_REF`, or fetch unconditionally | technical | pending - assumed: payload-first with fetch fallback - a resolvable base.sha costs zero network and is usually current; the fetch arm exists because checkout does not fetch a base tip that advanced past the merge ref, and either arm converges through merge-base(HEAD^2, resolved) |
| Tombstone shape for retired-probe comments — drop the basename and cite `#9728`, or keep the full script path in dated comments | technical | pending - assumed: drop the basename, cite the issue - it makes the residual-reference AC a clean universal zero on scripts/, .github/, .claude/, plugins/ rather than a conditional grep that must enumerate its own exemptions |
| ADR-276 — append a dated amendment note recording the #12418 diff-base correction, or leave the ADR untouched | technical | pending - assumed: append the note - ADR-276's scope-bound text names `HEAD^1` as the pull_request base, so the recorded authority would otherwise diverge from the shipped derivation; the record is append-only and the precedent retirement left it untouched only because nothing it claimed had changed |
