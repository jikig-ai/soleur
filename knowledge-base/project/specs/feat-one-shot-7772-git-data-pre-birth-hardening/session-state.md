# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-03-feat-git-data-pre-birth-hardening-plan.md
- Status: complete
- Plan artifact: complete (selector=branch) — 22 H2 sections, zero duplicates, `closes: 7772`
- Scope verified: only `knowledge-base/project/{plans,specs}/` touched vs merge-base 99eeebfef

### Errors
- Playwright MCP failed to connect at session start. ROOT CAUSE (parent session, measured):
  the server was alive under a DIFFERENT live Claude session (PID 1510702) holding the single
  shared profile `~/.cache/playwright-mcp-profile`; the launch wrapper's pkill pattern
  (`[b]in/playwright-mcp`) matches only the leaf node process, not the `npm exec` parent, so
  concurrent sessions collide by construction. Profile has since been released (no procs, no
  Singleton locks). MCP tools remain unavailable to THIS session (a dead MCP server is not
  re-established mid-session). Item A does not need it.
- `plugin:github:github` MCP failed to connect (400, malformed auth header). Worked around
  with the `gh` CLI throughout.
- Plan-write guard blocked twice; the second block was valuable — it surfaced that the Doppler
  secret-write CLI verb prints all remaining secrets to stdout. Fixed with `--silent` + redirect.
- Planning agent self-inflicted a ~840-line splice duplication; detected and repaired. Verified
  clean here (zero duplicate H2s).

### Decisions
- Item A NOT blocked. #7772's and ADR-198's "operator mint" premise is false. Confirmed
  independently by the parent session: `POST /api/v1/sources` -> HTTP 422
  (`missing required attributes: ["name"]`) under `BETTERSTACK_API_TOKEN`, i.e. the credential
  is accepted and only the body was rejected; a re-list confirmed the probe created nothing.
  Cause of the mis-framing: a suffix-variant sibling secret, `BETTERSTACK_API_TOKEN_READONLY`,
  exists alongside the write-capable account-wide token. Both `/api/v1` and `/api/v2` return
  200. No Playwright, no operator step.
- D1 — the rehearsal ships to the NEW source; the closed 8-member divergence allowlist is NOT
  widened (the premise's wording is falsified, the pin stays true). Requires renaming the
  REHEARSAL ROOT's variable too — it resolves by Doppler name transformation, so re-pointing
  only prod would silently leave the rehearsal on the shared source.
- D2 — Item B (nftables metadata egress closure) ships INLINE, not as a 10th `file()` payload,
  avoiding silent floor decay across four payload-count suites. Recorded as a trade (forfeits
  byte-identity checking), not a free win.
- D5 — the ingest URL is a `local`, not a second no-default variable.
- ADR-198's fourth item (refresh baked token from Doppler at boot) triaged OUT with a
  correction: its proposed `runcmd` is once-per-instance, so it runs at the one moment the baked
  and Doppler values are identical and cannot deliver its stated benefit.

### Carried into /work (parent-session findings, verify before relying on)
- The Better Stack API reports `ingesting_host = s2457081.eu-central-1a.betterstackdata.com`
  for source 2457081, while the repo hardcodes `s2457081.eu-fsn-3.betterstackdata.com`
  (`zot-registry.tf`, `vector.toml`). Take the NEW source's ingest host from the create
  response; do not pattern-match off the old literal.
- Empirical claims from planning that /work must re-exercise rather than inherit: the nftables
  rule loads on git-data's exact image, root reaches the metadata endpoint while non-root is
  dropped with an un-ruled control still reaching, and `nft -f` MERGES rather than replaces
  (which contradicts the inngest precedent the design copied).

### Components Invoked
soleur:plan, soleur:deepen-plan, Explore x4, learnings-researcher, architecture-strategist,
security-sentinel, terraform-architect, code-simplicity-reviewer, user-impact-reviewer,
general-purpose (26-claim verification sweep), WebFetch/WebSearch, lint-infra-no-human-steps.py,
lint-guard-contract.py, live Better Stack / Hetzner / Doppler probes, containerised nft validation
