# Learning: a permission table is not the endpoint's behaviour, and the first production run is the only test of a token scope (#7122)

## Problem

#9596 moved the community-monitor spawn to a read-scoped GitHub installation token (`contents`, `issues`,
`pull_requests` read). Plan Spike S2 "confirmed the read-permission set" against the app manifest and
GitHub's per-endpoint table. After merge, the first manual run showed `GitHub | failed | script-error`:
`GET /repos/{o}/{r}/stargazers` answers `403 Resource not accessible by integration` for that token, on REST
and GraphQL. Probing token permission sets against the live installation showed only `contents: write`
unlocks it; every read-level permission, alone or combined, fails. The documented table says the endpoint
needs no special permission.

## Solution

- Treat that one response as a known limit of the read-only token: `repo-stats` reports
  `new_stargazers_count: null` plus a closed `stargazers_unavailable` warn in the collector sidecar; any other
  stargazers failure stays a hard failure (the message AND `HTTP 403` must both match, since a rate limit
  also prints a 403).
- Enforce it in the handler, not the prompt: a draft that says github `collected` is forced to
  `partial`/`auth` with its other numbers kept. Three review seats independently found that leaving the
  null-to-0 mapping to the model published an unmeasured `0` as a measurement whenever the model ignored it.

## Key Insight

A scope check made against a table is a claim about documentation. For each endpoint the unattended path
calls, mint the real narrowed token and call the real endpoint before merge; a probe takes a minute and
the alternative is learning it from the first scheduled run. Separately: when a fix tells a model to map an
unavailable value to a number, the number is indistinguishable from a measurement downstream, so the
deterministic channel (here the sidecar warn) must carry the fact and the handler must act on it.

## Session Errors

1. **Spike S2 verified permissions against the manifest and docs, not against the endpoints.** Recovery:
   per-permission probes against the live installation after the first run. **Prevention:** probe each
   collector endpoint with the narrowed token as part of the plan's token-scope spike.
2. **The first draft of the fix relied on the prompt alone for the null-to-0 mapping.** Recovery: review
   (security, data-integrity, architecture) converged; the handler now enforces it. **Prevention:** any
   "unavailable becomes 0" instruction needs a deterministic carrier.
3. **The new tests used a stderr shape `gh` does not produce and had no non-403 negative control.** Recovery:
   test-design review; fixtures now use the captured `gh: ... (HTTP 403)` form plus rate-limit and
   non-403 controls. **Prevention:** capture the real tool output once and fixture that.
4. **A prompt edit containing a backtick followed by a semicolon ended the prompt template early in a source
   test that slices on that pair.** Recovery: reworded. **Prevention:** none beyond the existing test.
