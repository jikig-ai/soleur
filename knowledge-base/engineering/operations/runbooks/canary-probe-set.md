---
title: Canary probe set contract
date: 2026-04-28
owners: engineering/ops
applies_to: apps/web-platform/infra/ci-deploy.sh
related_pr: 3014
---

# Canary probe set contract

The pre-swap canary check in `apps/web-platform/infra/ci-deploy.sh`
exists to reject a broken build BEFORE its container takes the
production port. The legacy contract (`/health` only) was insufficient
and shipped a broken bundle to prod (PR #3014 incident).

## SSR/client divergence (the load-bearing context)

`NEXT_PUBLIC_*` environment variables are inlined into the static
client bundle by Next.js's DefinePlugin at **build time**. The
`lib/supabase/client.ts` module-load validators run **only in the
browser**. So:

- A broken inlined value passes every server-side probe (`/health`,
  SSR-rendered HTML, server-render of `/dashboard` via the server
  Supabase module).
- The throw fires only after the browser parses the client bundle —
  visible to a real user, invisible to `curl`.

The probe contract below is layered specifically to close this blind
spot.

## Layered probes

| Layer | Probe | Catches | Status |
|---|---|---|---|
| 1a | `curl http://localhost:3001/health` returns 200 | container is alive | enforced |
| 1b | `curl http://localhost:3001/login` returns 200 with non-empty body | public route renders | enforced |
| 1c | `curl http://localhost:3001/dashboard --max-redirs 0` returns 200/302/307, body does NOT contain `data-error-boundary=` | middleware redirect or successful render; rejects SSR-rendered error.tsx | enforced |
| 2 | Headless chromium hydrates `/login` AND `/dashboard`; rejects on any `pageerror`, console.error, or `Unhandled error` event during hydration | client-only throws at module load (validators, polyfill incompatibilities, encoding mismatches) | **required — was D1, promoted post-#3014** |
| 3 | `apps/web-platform/infra/canary-bundle-claim-check.sh` fetches the deployed login chunk and asserts the inlined Supabase JWT has canonical claims (`iss=supabase`, `role=anon`, ref shape) | inlined build-arg corruption (the #3007 regression class) — runs without a browser, catches what Layer 1 cannot see | enforced |
| 4 | GitHub App key check (#8609), after the bwrap probes and last before promotion: the env-file holds exactly one `GITHUB_APP_PRIVATE_KEY` line that is not `EVICTED_SEE_ADR_241`, then `docker exec soleur-web-platform-canary /bin/sh -c '… exec /usr/bin/env -i PATH=… GITHUB_APP_ID=… GITHUB_APP_PRIVATE_KEY=… /usr/local/bin/node /app/scripts/github-app-key-probe.mjs'` (only those two variables reach an absolute-path node, so no `prd`-set `PATH`/`NODE_*`/`LD_*`/proxy/CA variable picks the interpreter or hooks TLS) prints exactly one of `github_app_key_probe=ok`, `github_app_key_probe=transport`, or `github_app_key_probe=rejected reason=<no_app_id\|unparseable_key\|http_401\|http_404\|wrong_app\|http_other>` | a missing, evicted, wrong or other-App key reaching production (`reason=canary_github_app_key_missing` / `canary_github_app_key_rejected`); `transport` and an absent script (rc 127) promote, each with a Sentry warning | enforced |

Layer 1 is the cheapest broad-coverage gate. Layer 2 is the ONLY layer
that exercises the production browser environment — including webpack's
`buffer@5.x` polyfill, which was the missing gate for the
`Buffer.from(_, "base64url")` regression class. Layer 3 covers
build-arg integrity (claim shape) but cannot detect runtime polyfill
incompatibilities. The post-#3014 incident (validator throws
`Unknown encoding: base64url` in the browser despite a canonical JWT)
forced Layer 2 from deferred to required.

## Body-content sentinel — structured marker

The shared `components/error-boundary-view.tsx` renders a stable
`data-error-boundary` attribute on the boundary container (`"root"` for
`app/error.tsx`, `"dashboard"` for `app/(dashboard)/error.tsx`). The
canary greps for `data-error-boundary=` — copy edits cannot disable the
gate. This catches **server-component** throws (which DO render error.tsx
during SSR). Client-only throws are caught by Layer 3.

## Adding a new probe

1. Add the route to the canary loop in `ci-deploy.sh`. Use the existing
   `curl --max-time 5` pattern.
2. Decide the success contract: HTTP status range AND body assertion.
3. Add a failure-mode test in `infra/ci-deploy.test.sh` (e.g.,
   `MOCK_CURL_<NAME>_5XX` env var → expect rollback trace).
4. Bump preflight Check 7 if the new probe is load-bearing for an
   incident class.

### Registered: the GitHub App key probe (Layer 4, #8609)

1. **Where:** `github_app_key_canary_check` in `ci-deploy.sh`, called after the bwrap/faithful
   sandbox probes and before the swap; the boot path runs the same probe, under the same `env -i`,
   in the booted container (`soleur-github-app-key-check`, `soleur-boot-emit` stage
   `github_app_key_*`). At boot, `github_app_key_ok` means the isolated key was fetched and
   accepted; a key GitHub accepts that came from the `prd` fallback emits `github_app_key_ok_fallback`
   (warning), so a fallback can never read as the isolated key.
2. **Success contract:** the probe's whole stdout is `github_app_key_probe=ok` (GET
   `https://api.github.com/app` → 200, `slug=soleur-ai`, `id=GITHUB_APP_ID`). `transport` and an
   absent script (rc 127) promote with a Sentry warning (`op=github-app-key`); `rejected` (with its
   closed `reason=`), or a non-zero exit with no verdict (other than 127), refuses. Verdict rules:
   `apps/web-platform/scripts/github-app-key-probe.mjs`.
3. **What `ok` does NOT prove:** the probe is code inside the image under test, so its verdict is
   key acceptance for an image whose provenance is already established (the cosign verify pinned to
   a `refs/heads/main` run, ADR-241 D10). Never read `probe=ok` as provenance evidence.
4. **Failure-mode tests:** `ci-deploy.test.sh` Guard 7 (`MOCK_GAK_PROBE_OUT` / `MOCK_GAK_PROBE_RC`)
   and `apps/web-platform/test/github-app-key-probe.test.ts`.
5. **Preflight Check 7:** not bumped — it gates the authenticated-surface probes, and this probe
   does not render a route. Read the outcome with no SSH (the status script needs the deploy-status
   credentials, so run it under Doppler; bare, it exits 3):
   `doppler run -p soleur -c prd_terraform -- bash apps/web-platform/scripts/github-app-key-status.sh`.
   Its `tag=`, `exit_code=` and `component=` lines say which deploy the verdict belongs to. web-2's
   boot verdict: `doppler run -p soleur -c prd -- scripts/sentry-issue.sh --host-events soleur-web-2
   --stage github_app_key_ok` (and the other `github_app_key_*` stages), with
   `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep
   GITHUB_APP_KEY_BOOT` as the fallback.

## Removing a probe

Probes are load-bearing safety nets. Removing one requires:

1. A linked PR explaining the failure class the probe was protecting
   against and how the new gate covers it.
2. Updating preflight Check 7 if the removed probe is referenced there.
3. Operator review (CTO + ops).

## Why /health alone is insufficient

`middleware.ts:18-20` short-circuits `/health` BEFORE the Supabase
session check runs. The route never imports
`@/lib/supabase/client`, so a broken inlined `NEXT_PUBLIC_SUPABASE_*`
value cannot affect `/health`'s response. This is why PR #3007's
broken bundle returned `200 OK` on `/health` for the entire outage
window — the canary contract said "go" and the swap proceeded.

## Blocking bwrap sandbox probe — reading its self-report (#8016, PR #8026)

The same canary stage runs a **blocking** `bwrap` probe (`docker exec soleur-web-platform-canary
bwrap … -- true`) whose failure rolls the deploy back with `reason=canary_sandbox_failed`. It is
distinct from the non-blocking faithful sandbox canary (ADR-079, `sandbox_canary: {verdict: …}`
payload) — the two share the word "sandbox" and nothing else. Since PR #8026 the probe reports
what it measured on one journald line per deploy, under `logger -t ci-deploy`:

```text
SANDBOX_PROBE_OK: bwrap sandbox verified in <image>:<tag> rc=0 ms=<n|unknown> cstate=<status> err_chars=<n> bwrap_err="<text|<empty>>"
DEPLOY_ROLLBACK: bwrap sandbox non-functional in <image>:<tag> rc=<n> ms=<n|unknown> cstate=<status> err_chars=<n> bwrap_err="<text|<empty>>"
```

**Query (no SSH; the only read path).** `ci-deploy` is on the Vector `host_scripts_journald`
allowlist, so both lines are in Better Stack Logs. The text lives in the decoded `message`
field — `raw` is double-encoded JSON, so grep after decoding, never on the raw line:

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 12h \
  --grep 'DEPLOY_ROLLBACK: bwrap sandbox non-functional' --grep 'SANDBOX_PROBE_OK: bwrap sandbox verified' \
  | jq -r '. as $r | .raw | fromjson | select(.SYSLOG_IDENTIFIER == "ci-deploy") | "\($r.dt) \(.message)"'
```

Filter on the decoded `SYSLOG_IDENTIFIER`, not a substring of the line: inngest ships
GitHub-webhook logs (issue and PR bodies quoting these markers) to the same source.

**Fields, and what each discriminates.** Everything before `bwrap_err=` is the trusted region;
`bwrap_err` is free text from the container's stderr and is emitted **last** so a consumer cuts
the line at the first `bwrap_err=` and reads the other fields from the region above it. Never
read `rc=` with a leading greedy `.*` or `grep -o … | tail -1` — the free text can contain `rc=0`.

| Field | Meaning | Read it as |
| --- | --- | --- |
| `rc` | exit status of `docker exec … bwrap` | `1` = bwrap's own failure **or** docker "no such container" (tie broken by `cstate` and the message); `126`/`127` = could not exec (missing binary / shared object — the text names it); `128+n` = the child was signalled (`137` = SIGKILL, what an OOM or a timeout looks like). **`rc=137` with `cstate=running`, `err_chars=0` and an `ms` equal to a passing run's was the PDEATHSIG race (#8016), now fixed by dropping `--die-with-parent` from the probe — HISTORICAL signature. After the fix any `rc=137` is unexplained — and now emails: the Better Stack alert `soleur-bwrap-probe-rollback-prd` (#9342) fires on any such row, and this row is its decode**; discriminate by `ms` (far from the passing mean = a hang or OOM, not an instant kill). Next suspects: OOM at the canary's 1536m cap, a host reaper |
| `ms` | wall time of the exec, or `unknown` when bash `EPOCHREALTIME` was unavailable | separates a fast refusal (tens of ms) from a killed hang (thousands); never fabricated |
| `cstate` | `docker inspect .State.Status` taken **before** teardown, or `unknown` | `running` + `rc=1` → bwrap failed inside a live container; `exited`/`unknown` + `rc=1` → the container was already gone |
| `err_chars` | length of the **raw** stderr before sanitization | `0` beside `128+n` = signalled child that printed nothing; treat `bwrap_err` as possibly truncated whenever this is anywhere near 200 — redaction changes length in both directions, so it is an approximate discriminator, not an exact one |
| `bwrap_err` | last ≤200 chars of stderr after sanitization | `<empty>` = bwrap said nothing (distinct from "we discarded it"); `<sanitize_failed>` = the sanitizer died and nothing was emitted; `<redacted:NAME>` = an env-file value was substituted; a marker may be bisected at the head by the 200-char tail |

The stdout copy of `bwrap_err` also reaches Better Stack under `SYSLOG_IDENTIFIER=webhook`
(`adnanh/webhook -verbose` re-logs the hook's combined output), late and unstructured; use the
`ci-deploy` line.

**Sanitization, so you know what you are not seeing.** The canary runs with `--env-file`, so
every prd secret sits in `Config.Env` and runc can format one into an error. `_cred_err_tail`
strips non-printable bytes, folds `"` to `'`, applies shape rules (Doppler `dp.*`, Stripe
`sk_/pk_/rk_live|test_`, JWT `eyJ…`, `ghp_/sbp_/dop_v1_/whsec_/xox?_`), then substitutes every
env-file value of ≥12 characters longest-first with `<redacted:NAME>`. Values under 12
characters and values that runc `%q`-escaped are outside the value arm; the shape rules remain.

**Closing #8016.** The self-report named the SHAPE of every rollback (`rc=137`, empty stderr,
`cstate=running`); reproducing it locally named the cause: a spawn-timing race between
`docker exec`'s short-lived runc parent and the `PR_SET_PDEATHSIG(SIGKILL)` that `--die-with-parent`
arms, not a sandbox failure. The probe no longer passes that flag (mechanism, measurements and repro loop:
`knowledge-base/project/learnings/bug-fixes/2026-10-01-docker-exec-pdeathsig-race-sigkills-bwrap-probe.md`)
and #8016 is closed by the fix PR. The follow-through sweeper that watched it
(`scripts/followthroughs/bwrap-probe-selfreport-8016.sh`) is retired in the same PR, together with
its test, registration and the issue's `follow-through` label (the sweeper's closed-set pass would
otherwise reopen a COMPLETED issue on the first matching row). **A recurrence therefore does not
reopen it.** Detection is the Better Stack Logs alert `soleur-bwrap-probe-rollback-prd` (#9342; it emails
on any matching row from any deploy host), with the release-failure email, the workflow
`::error::` annotation and the query above as the secondary routes. The alert does **not** cover a rollback
whose `logger` call failed (that line then reaches Better Stack only as an unmatched `SYSLOG_IDENTIFIER=webhook`
row) or a stopped `ci-deploy` shipper, so silence from it is not proof of no rollback: cross-check the release
run's `::error::` annotation (`reason=canary_sandbox_failed`) and the `SANDBOX_PROBE_OK` query. Remediation for a recurrence is GitHub's "Re-run failed
jobs" on the release run, never `apply-deploy-pipeline-fix.yml` (it redeploys the already-running
tag and cannot ship past the gate; see the comment in `reusable-release.yml`) and never a host
command.

## Faithful sandbox canary — #8752 hardening verdicts

`sandbox_canary.verdict` in deploy-state (and its Sentry `op=sandbox-canary` event) now covers the
sandbox-hardening pair, not only sandbox-build health. Decoding `reason` (all `sandbox_broken` reset
the consecutive-pass soak and page; `canary_infra_error` rows hold the soak and never roll back):

| `reason` | Meaning | First move |
|---|---|---|
| `userns_filter_bypass` | Nested `unshare -U` ran INSIDE the replayed sandbox — the shared seccomp filter is not engaged (shim absent/misrouted) | `bash apps/web-platform/scripts/bwrap-userns-seccomp-probe.sh` in the canary image; check `op=sandbox-hardening-selfprobe` |
| `userns_filter_overbroad` | A forked child failed inside the filtered sandbox — the filter denies more than nested userns | Regenerate/verify the artifact (`gen-bwrap-userns-seccomp.mjs --check`); do NOT weaken the filter to unblock |
| `fd_hygiene_bypass` | The in-sandbox fd census exceeded `4 + #fd-valued-argv-options` — an unreferenced fd leaked past the shim's sweep | Inspect `bwrap-shim:` lines + the shim's preserve-set arity table |
| `args_fd_closed` | The `--args <fd>` transport probe failed — the SDK's real spawn shape broke (shim closed the argv fd) | Every agent spawn fails too; treat as deploy-blocking |
| `bwrap_shim_refused` | The shim itself exited 65 (`bwrap-shim:` marker) — artifact or real bwrap missing in the image | `probeAgentSandboxHardening` fields (`shim`, `filter`, `bpfBytes`) say which |

## References

- AGENTS.md `wg-when-fixing-a-workflow-gates-detection`
- `plugins/soleur/skills/preflight/SKILL.md` Check 7
- `plugins/soleur/skills/preflight/SKILL.md` Check 5 Step 5.4 (Layer 3 source)
- PR #3014 — incident remediation
