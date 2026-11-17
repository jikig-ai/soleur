# Decision Challenges — feat-one-shot-12742-public-sdk-url-poll (#12742 item 1)

No CTO/Task-spawn capability was available in this planning session, so technical forks are
recorded here as `pending - assumed:` per the technical-ruling policy (never ask the operator a
technical question; record the assumed default when delegation is unavailable). Each row should be
ratified by the CTO agent before or during implementation.

| # | Fork | Status | Assumed default / rationale |
|---|------|--------|------------------------------|
| 1 | Sync-evidence mechanism: `apps { url error }` GQL + `sdk_sync`/`sdk_app_url` fields vs alternatives (deploys query, functions-derived signal, external ping) | pending - assumed | `apps { url error }` on the same loopback GQL: `error` is refreshed by the server's pollSDKs loop each cycle, so `ok` proves the LAST attempt succeeded (recent by construction); `sdk_app_url` doubles as item 4's stored-URL evidence. Exact GQL field names must be verified against the pinned Inngest version at implementation; schema drift fails loud via `__UNREADABLE__`. |
| 2 | F4(ii) remedy: sanitize `image_ref`/`cli_version` vs `countMatches(msg,' registry_fns=') != 1` alert predicate | pending - assumed | Sanitize (permitted either/or). A space-bearing free-text value corrupts `key=value` tokenization for EVERY consumer (host-state parser, heartbeat classifier, alert, greps); the SQL predicate protects only the one alert. Charset `[A-Za-z0-9_:.@/+-]` → `_`, in-file `tr` precedent. |
| 3 | Extend registry-empty alert to page on `sdk_sync=error` now vs defer | pending - assumed | Defer. The field has no production history until the replace lands; tuning a new page on the most sensitive paging surface pre-data risks alert fatigue. Responder-visible evidence ships in the same row; paging decision follows with data. |
| 4 | Preflight shape: new `tests/scripts/lib/inngest-public-sdk-url-preflight.sh` invoking `doppler run -- cloudflare-readonly.sh config-entrypoint` and judging the JSON projection, placed after credential load in both jobs | pending - assumed | Mirrors ADR-136 `preapply-entrypoint-gate.sh` (default-deny, `--from-file` test seam, distinct `::error::` arms, token never echoed). Wrapper requires the documented direct-exec invocation; the script execs that argv rather than shell-wrapping it. |
| 5 | `probe_schema` 9→10 bump forces `stale_schema` refusals on the CURRENT host until the owner's replace | pending - assumed | Accept. The dark gate's `stale_schema` correctly reports the host predates the emitter that can prove recent sync; it cannot block the owner dispatch (that path does not route through the gate). The refusal is the designed-for nudge toward the replace. |
| 6 | Preflight vacates the old gate's "before any credential" property | pending - assumed | Inherent: a live-mode check needs the CF credential. Protected property becomes "after `Load infra credentials`, before any terraform step, unconditional, fail-closed" — recorded so the parity pin asserts the NEW property, not the old. |
| 7 | Item-9 carrier-comment scope tension: brief excludes items 2–9, but item 9 says refresh "the next time that file changes for a real reason" — this PR is that time | pending - assumed (scope) | Refresh opportunistically in the same diff (zero marginal cost; leaving a known-stale comment inside an edited file contradicts the deferral's own trigger). Flagged for transparency. |
| 8 | Byte budget: workflow is 5 B under the 490,000-B gate | pending - assumed | Net-negative edit: remove ~660 B of confirm steps, add ~520 B of preflight steps; one-line comments only, rationale prose relocated to `apply-web-platform-infra-job-rationale.md` (the gate's own error text prescribes this relocation). Verify `wc -c` at PR time. |
| 9 | `sdk_sync` enum cardinality: `ok|error|no_apps` plus sentinels `n/a|__UNREADABLE__` vs richer states (e.g., per-app detail) | pending - assumed | Three states + two sentinels: enough to discriminate the four post-replace shapes (healthy / stale-registry / diagnostic boot / dead local API) without shipping response content. |
| 10 | Workflow `confirm:` input retained | pending - assumed | Keep: ~10 other targets consume `inputs.confirm`; only the two inngest jobs stop consuming it. Removing the input would be an unrelated dispatch-API change. |

## Cross-cutting notes

- `#10538` is **OPEN** — the issue body says "closed by #12737" but a later comment corrects it;
  do not restate it as closed in code comments or PR text.
- The issue's owner-dispatch preconditions (#10479 closed, #12726 resolved, `INNGEST_CUTOVER_FLIP`
  handled, fresh strict rule read, zot mirror pin, idle concurrency group) are item-2 scope and
  remain the owner's checklist, not this PR's.
