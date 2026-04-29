---
module: web-platform / canary
date: 2026-04-29
problem_type: integration_issue
component: ci_canary_probe
symptoms:
  - "canary-bundle-claim-check.sh exits 1 with 'no JWT found in login chunk' against a healthy production bundle"
  - "Layer 3 canary probe wired into ci-deploy.sh has been silently skipped on every deploy since it was added"
  - "Bundle-content assertion false-negatives after a transitive dependency byte-change"
root_cause: hardcoded_chunk_path_invalidated_by_webpack_content_hash
severity: high
tags: [webpack, chunk-splitting, canary, bundle-content-gate, content-hash, ci-cd, supabase, layer-3]
related_pr: 3015
follow_up_issue: 3033
synced_to: []
---

# Webpack chunk-relocation silently invalidates bundle-content canary assertions

## Problem

While verifying recovery for issue **#3015**, running the Layer 3 canary
script against production produced a false-negative result that took the
recovery verification off-script:

```bash
$ bash apps/web-platform/infra/canary-bundle-claim-check.sh https://app.soleur.ai
canary-bundle-claim-check: no JWT found in login chunk
$ echo $?
1
```

Sentry digest for the relevant features showed zero events in the last
24h. Server startup events confirmed `v0.58.2` (PR #3017's deploy) was
live. `curl /dashboard` returned the expected `307` auth redirect. Every
other piece of evidence said the bundle was fine. Yet the script that
exists specifically to assert the canonical anon-key claims was failing.

The script (`apps/web-platform/infra/canary-bundle-claim-check.sh`) had
this hardcoded path filter:

```bash
CHUNK_PATH=$(grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' "$LOGIN_HTML" | head -1)
```

Today's prod login chunk
(`/_next/static/chunks/app/(auth)/login/page-f2f3d55448d7908c.js`,
4762 bytes) contains zero JWT and zero supabase URL. Manual inspection
of all chunks linked from `/login` HTML found the canonical anon JWT in
a different shared async chunk:

```bash
$ grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' \
    /tmp/3015-debug/8237-323358398e5e7317.js | head -1
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIs...
$ # decoded payload:
{"iss":"supabase","ref":"ifsccnjhymdmidffkzhl","role":"anon","iat":1773675703,"exp":2089251703}
```

Bundle was healthy; script was wrong about *where* to look.

## Root Cause

**Webpack's chunk-splitting is content-hash sensitive.** Any byte change
in any module — including a transitive dependency the login page never
references directly — re-runs the splitter and can move modules across
chunk boundaries. PR #3017 changed exactly one file
(`apps/web-platform/lib/supabase/validate-anon-key.ts`, replacing
`Buffer.from(..., "base64url")` with an `atob`-based decode). That
module-content delta cascaded through Next.js's chunk splitter and
relocated the Supabase init out of the login route's page chunk into
a shared async chunk (`/_next/static/chunks/8237-...js`). The PR's
commit subject mentions "Layer 2 promotion" — that wording refers to a
canary-probe-set runbook update, not a deliberate code-level chunk
restructure. **The chunk relocation was emergent, not intended.**

Consequences:

1. **Path-coupled grep fails closed.** The script's documented design
   says it fail-closes on absence ("the canary treats absence as failure
   to avoid fail-open on a bundling change that moves the supabase init
   out of the login chunk"). That choice is correct in principle, but
   pairing it with a hardcoded `app/(auth)/login/page-*.js` filter means
   *any* future webpack reshuffle — Next.js upgrade, transitive-dep
   bump, even a unrelated lib change that touches a shared module —
   will false-fail the canary.

2. **Compounding silent gap.** The same audit found the script has
   been silently skipped on every CI deploy since it was added in PR
   #3014: `apps/web-platform/infra/ci-deploy.sh:279` references the
   script via `CANARY_LAYER_3_SCRIPT=/app/shared/apps/web-platform/infra/...`
   but the canary container's docker run only mounts
   `-v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro` (lines
   263, 378). There is no `apps/` mount, so the `[[ -x
   $CANARY_LAYER_3_SCRIPT ]]` gate is always false and Layer 3 is
   skipped without raising any signal. Layer 3 has caught zero
   regressions in production because it has run zero times.

   The path-fragility bug only surfaced *because* this verification
   ran the script manually. If the volume mount had been added (in
   isolation) without broadening the path filter, every deploy from
   #3017 onward would have had its canary swap blocked by a
   false-negative `canary_layer3_jwt_claims` failure.

## Solution

Filed as **#3033** with three fix components:

1. **Mount fix** in `apps/web-platform/infra/ci-deploy.sh` lines
   262-263 and 377-378 — add
   `-v /mnt/data/apps/web-platform/infra:/app/shared/apps/web-platform/infra:ro`
   (or restructure the script under the `plugins/soleur` mount that
   already exists).
2. **Script fix** in `apps/web-platform/infra/canary-bundle-claim-check.sh`
   — broaden chunk discovery: fetch all chunks referenced from the
   `/login` HTML (the script already fetches it once) and grep across
   all of them for `eyJ...` until one decodes to a valid JWT
   structure. Alternative: resolve the chunk that imports
   `@supabase/supabase-js` via Next.js `__NEXT_DATA__` runtime
   metadata.
3. **Regression test** with two fixtures (pre-#3017 login-chunk-inlined
   layout, post-#3017 vendor-chunk-inlined layout) so the script's
   assumption is locked-in by test rather than implicit knowledge.

Until #3033 lands, the recovery-verification protocol for #3015-class
follow-throughs uses **manual JWT extraction from all chunks linked
from `/login`** as a substitute for the script — see runbook
`knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`
"Recovery Verification" block for the worked example.

## Key Insight (generalizable)

**Bundle-content gates that grep for runtime-inlined values must scan
every client chunk reachable from the entry point — never hardcode a
single chunk-path glob.** Webpack content-hashing rebalances chunks on
any byte change in a transitive dependency; coupling an assertion to
one specific chunk path means the assertion ages out the next time
anything in the dep graph changes.

This generalizes beyond Next.js: any bundler that emits
content-hashed output (Vite, esbuild, Rollup, Parcel) will exhibit
the same pattern. Same applies to source-map sentinel checks and
"is X tree-shaken out" assertions.

A second compounding lesson: **a CI gate that has never been observed
firing is a CI gate that does not exist.** When wiring a new
canary/preflight/lint check, run it through to a known-failing input
on day one (an artifact, a dirty branch, a synthetic regression
fixture) and confirm CI logs show the expected fail signal — not just
that the wiring exists in the script. The mount-missing gap (#3033
gap #1) would have been caught immediately by a "deliberately fail
the new probe and watch CI block" check.

## Prevention

- For Layer-3-style bundle-content gates: prefer scanning all linked
  chunks over a single hardcoded path. If a single path is the
  cheapest implementation, accompany it with a comment naming the
  webpack invariant the path depends on, and add a test fixture per
  expected layout.
- Ship every new CI gate with an observed-failure dry-run as part of
  the merge-time evidence (e.g., a one-line CI log excerpt showing
  the gate firing on a synthetic regression input). "Wired up
  correctly" is not the same as "observed working."
- For canary scripts that mount-depend on host paths, gate execution
  on file-presence + a positive `--self-check` mode that exercises
  the assertion against an embedded fixture before declaring the
  canary "passed". Absence-as-pass is fail-open; absence-as-fail
  with no mount is fail-closed-but-silent. Both are bad without an
  observed-firing dry-run.
- When running infrastructure scripts manually as part of a
  verification pass, always interpret a script-level failure as
  "needs investigation," not "regression detected" — the script's
  own assumptions can rot independently of the system under test.

## Session Errors

The /one-shot pipeline that surfaced this issue accumulated a number
of independent process gotchas. Each is documented here so future
sessions don't re-run them.

- **Sentry API org-slug confusion.** First curl used `jikig-ai`
  (matching the GitHub org); correct Sentry slug is `jikigai`. Two
  probe calls wasted on rediscovery. **Recovery:** GET
  `/api/0/organizations/` to enumerate accessible orgs. **Prevention:**
  when a third-party REST API 404s on first call, hit the
  auth-discovery endpoint before retrying with manual guesses.
- **Bash CWD did not persist.** Initial
  `bash apps/web-platform/infra/canary-bundle-claim-check.sh` ran
  from the bare repo root and exit-2'd because the path was
  relative. **Recovery:** chained `cd <worktree-abs-path> && ...`
  in a single Bash call. **Prevention:** in worktree pipelines,
  prefix every Bash invocation with `cd <abs-path> &&` (already
  covered by `cq-for-local-verification-of-apps-doppler` lineage).
- **SSH alias `prod-web` did not resolve.** Runbook example uses
  `ssh prod-web` but no `Host prod-web` block in `~/.ssh/config`.
  **Recovery:** pulled IP `135.181.45.178` from `admin-ip-drift.md`
  runbook + identity file from `~/.ssh/deploy_ed25519`.
  **Prevention:** runbooks should hardcode the IP + identity-file
  pair the agent needs, OR link to a known SSH config snippet.
- **`priority/p1` label rejected by `gh issue create`.** Canonical
  is `priority/p1-high`. **Recovery:** `gh label list | grep
  priority` to find the right name. **Prevention:** already covered
  by `cq-gh-issue-label-verify-name`.
- **Tried to commit screenshot to gitignored `artifacts/` path.**
  `.gitignore` line 68 ignores `artifacts/`. **Recovery:** moved
  to `screenshots/` and added negation rule
  `!knowledge-base/engineering/ops/runbooks/screenshots/**/*.png`.
  **Prevention:** before placing a committed artifact, run
  `git check-ignore -v <path>` to confirm visibility.
- **Invalid YAML frontmatter.** Wrote
  `status: closed: 2026-04-29 (verified via #3015 follow-through; ...)` —
  unquoted second colon makes `yaml.safe_load` raise
  `mapping values are not allowed here`. **Recovery:** split into
  separate `status:`, `closed_on:`, `closed_via:` fields.
  **Prevention:** when adding a value containing YAML control
  chars (`:`, `[`, `]`, `{`, `}`, `,`, `#`, `&`, `*`, `!`, `|`,
  `>`), quote it or split into separate fields.
- **Plan misattributed commit→PR numbers.** Wrote
  `a1f229c5 (#3017), 92e8b3d5 (#3018)` from memory; truth is
  `a1f229c5 (#3016), 92e8b3d5 (#3017), 62581167 (#3018)`. Caught
  by git-history-analyzer review agent. **Recovery:** re-ran
  `git log --oneline` to verify. **Prevention:** when citing
  commit→PR mappings in docs, derive both from a fresh
  `git log --oneline` in the same workflow rather than from
  memory.
- **Runbook overstated PR #3017 as a deliberate code restructure.**
  Wrote "PR #3017 relocated the Supabase init out of the login
  chunk into a shared async chunk" — the diff only changed
  `validate-anon-key.ts` (decode method); the chunk relocation
  is emergent webpack content-hash drift. Caught by
  git-history-analyzer review agent. **Recovery:**
  `git show 92e8b3d5 --stat` showed the diff scope; rewrote the
  attribution to acknowledge the chunk move as an emergent
  side-effect rather than an intentional refactor.
  **Prevention:** when attributing a structural effect to a PR,
  confirm the diff actually contains that structure change, not
  just a trigger byte.

## See Also

- `runtime-errors/2026-04-29-buffer-base64url-throws-in-client-bundle.md` — the underlying decode bug PR #3017 fixed.
- `runtime-errors/2026-04-28-module-load-throw-collapses-auth-surface.md` — why the original `/dashboard` outage spread (postmortem #3014).
- `bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md` — sibling regression that motivated Layer 3.
- `implementation-patterns/2026-03-28-canary-rollback-docker-deploy.md` — canary swap mechanics.
- `security-issues/canary-crash-leaks-env-file-ci-deploy-20260406.md` — separate canary failure mode.
- Runbook `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md` "Recovery Verification" block — worked example of manual substitution while #3033 is open.
- GitHub issue **#3033** — proposed mount + script-broadening fix.
