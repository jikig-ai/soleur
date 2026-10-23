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
| 5 | Inngest link TLS layer (#10136, ADR-294), **only while `INNGEST_LINK_TLS` is on or `pending`**: five checks inside the canary container (an https `INNGEST_BASE_URL` in `docker inspect`; one in-container fetch of the URL the container was handed; a real in-container `inngest.send` of `soleur.tls-canary.ping`; a CA-withheld negative control; a non-empty registry over https) | a container that was handed https but cannot complete a verified handshake (empty or wrong CA file, missing `:8443` egress accept, Node not trusting the pinned certificate) — invisible to a host-side `curl --cacert`, which proves neither container egress nor Node trust | **adopting — enforced from the first flag-on deploy** |

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

### Registered: the Inngest link TLS layer (Layer 5, #10136, ADR-294)

This layer is the container-level proof that the flag flip works. It is skipped, silently and by design, while the resolver
chose the legacy link (flag absent): the default path is the old `http://10.0.1.40:8288` URL and nothing about it changed.

1. **When it runs:** whenever `resolve_inngest_link` resolved `https` (the flag is `1`, or an unexpired `pending:<epoch>` lease
   that `inngest-link-flip.yml` wrote before dispatching the release). It runs against the **canary** container, before the
   swap, so a failure refuses promotion and the old container keeps serving.
2. **The five checks, all inside the canary container (the host's own `curl --cacert` self-gate proves the host OUTPUT path and
   the pinned bytes only, never container egress or Node trust):**
   1. (`inspect`) `docker inspect` shows the canary's `Config.Env` holds exactly one `INNGEST_BASE_URL=` line, that line is
      `https://10.0.1.40:8443`, exactly one `NODE_EXTRA_CA_CERTS=` line, and that line is `/etc/soleur/inngest-ca.pem`. Docker keeps an
      env-file entry **and** a `-e` entry for the same key, so `ci-deploy.sh` scrubs both names from the env-file once per deploy
      (`inngest_link_scrub_env_file`, event `class=env_scrubbed`) and this check stays strict: a real duplicate still fails.
   2. (`health`, `events`) In-container `fetch` of the URL the container was actually handed succeeds: `/health`, and
      `/v1/events?limit=1` with the hashed-signing-key Bearer.
   3. (`send`) A real in-container `inngest.send` of the synthetic event `soleur.tls-canary.ping` is accepted. A test asserts no function
      under `apps/web-platform/server/inngest/functions/` triggers on that name, so the event does no work.
   4. (`negative_control`) A **negative control**: the same fetch with the CA withheld (`env -u NODE_EXTRA_CA_CERTS` in the same container) must FAIL
      with a verification error. A canary that cannot see this fail would pass vacuously on a container that trusts everything.
   5. (`registry`) The registry read over https is non-empty.
3. **What it does NOT prove:** the second prod host. web-1 and web-2 each run their own canary at their own deploy, so the per-host
   proof is each host's own canary; the web-host hook `inngest-tls-handshake` terminates on web-1 only.
4. **Counters are read only after both prod swaps complete.** Until the old prod container is drained it still dials `:8288`,
   so a `legacy_8288` read taken earlier is contaminated. T for the soak is the last prod swap plus the old-container drain (how to
   read it per host: [inngest-server.md](inngest-server.md), act A3).
5. **Failure reads (Better Stack only):** the failed release run's log carries one of two constant reasons, **not** the failing check:
   `canary_inngest_link_inspect_failed` (the `inspect` check: usually the container was handed the wrong environment, a composition defect and
   not a network or CA defect; `cause=inspect_failed` is the daemon call itself failing) or `canary_inngest_link_failed` (every in-container check: egress, TLS, registry). The check name and its
   cause are in the event the resolver logs:
   `INNGEST_LINK: class=canary_failed level=error check=<inspect|health|events|send|registry|negative_control|no_verdict>
   cause=<token>` (Better Stack, journald tag `ci-deploy`; Sentry `op=inngest-link`, tag `classification=canary_failed`). The cause is
   mapped inside the container from a fixed allowlist: `ECONNREFUSED`, `ECONNRESET`, `ETIMEDOUT`, `EHOSTUNREACH` and the like mean egress
   or the listener (a missing `:8443` accept reads as a timeout), a certificate code such as `DEPTH_ZERO_SELF_SIGNED_CERT` means Node did
   not trust the pinned file, `HTTP_<status>` means the listener answered badly, `EMPTY` means an empty registry, `other` is anything
   outside the list. For `inspect` the event reads `check=inspect cause=<token> url_lines=<n> url_https=<n> ca_lines=<n> ca_ok=<n>` (integers
   clamped to 99, never a value) and the cause is the first failing condition: `inspect_failed` (the canary vanished or the daemon call
   failed; on the same host read `--grep 'DEPLOY_ROLLBACK: canary failed'`, whose `reason=` separates a health failure from this one), `url_count` (`INNGEST_BASE_URL=` is not on exactly one line:
   with no `class=env_scrubbed` row on the same host in the minutes before it, a source the scrub does not cover reached the container; with
   one, the scrub was not the source; either way stop and file it, do not retry), `url_value` (one line, not the https URL: a non-https URL reached the container), `ca_count` or `ca_value` (the CA env is absent,
   duplicated or not the pinned path). No `canary_ok` or `canary_failed` row at all means the resolver returned `lease_expired` (http, the
   canary layer skipped) or the health check failed first. A `class=env_scrub_failed` row (`stage=read|write|recount`) beside it means the
   env-file could not be rewritten: a strict deploy aborted with reason `inngest_env_scrub_failed`, a non-strict one continued unchanged.
   For `negative_control` the cause is `accepted` (the container trusted without the CA), `other` (it failed, but not with a certificate-verification error) or `no_verdict`. The exact query
   is under "Resolver events" in [inngest-server.md](inngest-server.md) section "Link TLS (#10136)". The host-side `tls-health` row
   carries no handshake-failure counter (it was removed by ruling; do not look for `hs_fail_15m`).
6. **`canary_ok` proves the canary only.** The prod container is not inspected: its evidence is the post-swap `legacy_8288` counter read
   (item 4) and, per host, the `class=resolved` and `class=canary_ok` rows (see the per-host flip read in [inngest-server.md](inngest-server.md)).
7. **A broken gate blocks ordinary releases while the flag is on** (the resolver fails the deploy rather than downgrade to http).
   Rollback: `inngest-link-flip.yml` with `action=off`, then a redeploy.

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
jobs" on the release run, never `apply-deploy-pipeline-fix.yml` for the canary failure itself (it redeploys the already-running
tag and cannot ship past the gate; see the comment in `reusable-release.yml`) and never a host
command. (Delivering a CHANGED host `ci-deploy.sh` is the one thing that workflow is for: see "Reading absence" in the DIAG bundle section.)

## Canary sandbox DIAG bundle — why a sandbox canary failed (#9871, #9860)

`DEPLOY_ROLLBACK: bwrap sandbox non-functional ...` says THAT the blocking probe failed and keeps 200
characters of stderr. When the probe fails, when the faithful canary (`op=sandbox-canary`) reports
`sandbox_broken`, or when the deploy-time SDK Bash smoke reports `sdk_bash_smoke_failed` (#10453), `ci-deploy.sh` also runs ONE
bounded, read-only bundle inside the still-running canary per trigger and emits it under the same `ci-deploy` journald tag, so it
reaches Better Stack with no SSH. `legacy` is exclusive of the other two (a legacy failure exits before the faithful canary and the
smoke run), but `faithful` and `sdk_smoke` can both fire on one deploy (both are report-only and run in sequence), so a deploy
carries at most one `legacy` bundle OR up to one `faithful` and one `sdk_smoke` bundle; group rows by `trigger=` before reading:

```text
SOLEUR_CANARY_SANDBOX_DIAG: image=<image>:<tag> trigger=<legacy|faithful|sdk_smoke> section=<name> val="<text|<empty>>"
```

`val` is last and quote-bounded; cut each line at the FIRST `section=` and read the rest as free text. It is
credential-scrubbed (`_cred_err_tail`, which keeps the LAST 200 characters, so every row is short on
purpose) and cannot change the deploy's exit code, state reason or teardown. Query:

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_CANARY_SANDBOX_DIAG \
  | jq -r '. as $r | .raw | fromjson? | select(.SYSLOG_IDENTIFIER=="ci-deploy") | "\($r.dt) \(.host_name) \(.message)"'
```

Group rows by host, `image=` and `trigger=`; one bundle ends at its `done` row, so read the H-rows below only against a bundle whose `done` has arrived (Vector lag can surface `kdeny` before `sdk_probe`).

A complete bundle is sixteen rows: eleven in-container sections, then `host`, `hostsec`, `kernel`, `kdeny` and `done`.

| section | what it shows | reads as |
|---|---|---|
| `id` | uid/gid of the exec user | expect `uid=1001 gid=1001` |
| `proc` | `CapInh/Prm/Eff/Bnd/Amb`, `NoNewPrivs`, `Seccomp` of the container shell | non-zero `CapPrm`/`CapEff` for a non-root uid means caps reached the exec user, which bubblewrap 0.8.0 refuses; `Seccomp=2` means a filter is installed (always true here: it does not separate AppArmor from seccomp) |
| `lsm` | AppArmor profile and mode | `unconfined` or a missing profile points at the host profile, not the image |
| `files` | mode/owner/size of `/usr/bin/bwrap` and the shim, `command -v bwrap`, `readlink -f` | a setuid bit or wrong owner is an image defect |
| `caps` | `getcap` for `/usr/bin/bwrap` and the shim | `bwrap=none` is clean. Only a `cap_` token means file caps; getcap error text (`No such file or directory`) is not a cap. Since #9874 the Dockerfile build aborts on any file cap, so a `cap_` token now means a stale image (check `prov`) or a bypassed build guard. `getcap=absent` means the tool is missing from the image |
| `prov` | `BUILD_SHA` / `BUILD_VERSION` baked into the image | differs from the tag's commit = a stale image behind a newer tag (#9886) |
| `direct_version` | `/usr/bin/bwrap --version` with the shim bypassed | `rc=126` = execve refused (file caps vs. bounding set, LSM, seccomp); a version line = exec is fine |
| `direct_probe` | the blocking (legacy) probe argv run against `/usr/bin/bwrap` directly | passes while the shimmed probe fails = the shim; fails the same = kernel/LSM posture. Under `trigger=faithful` it always passes (the legacy probe already did): read `sdk_probe` instead |
| `sdk_probe` | the SDK's split-unshare argv (`--unshare-user --unshare-pid --proc /proc`) against `/usr/bin/bwrap` directly | corroborating evidence only. Its healthy-canary baseline is UNMEASURED (a healthy deploy emits no bundle, and the #4932 note in `ci-deploy.sh` records that adding these flags to the BLOCKING probe rolled back deploys), so a `Can't mount proc on /newroot/proc: Operation not permitted` line here may be an artifact of the canary container's posture (docker's default masked `/proc`), which production shares: if so it is the real condition and not an `exec` artifact (see H6). Read it as H3 only together with `direct_version rc=0`, a `kernel_ns` userns restriction (`restrict=1` or `max=0`) and the faithful canary's own `reason`. The first bundle that carries a pass on a healthy canary should be recorded here as the baseline. **Measured contrast (2026-10-10, local docker, same image digest, bubblewrap 0.8.0, uid 1001, the repo seccomp profile):** this argv prints `Can't mount proc on /newroot/proc: Operation not permitted` under docker's DEFAULT masked `/proc` and passes with `--security-opt systempaths=unconfined`; read `sdk_noproc` next to it |
| `sdk_noproc` | `sdk_probe`'s argv with `--proc /proc` removed (`--unshare-user --unshare-pid --dev /dev --bind / /`), same binary, same event | the control for `sdk_probe`. `sdk_noproc rc=0` with `sdk_probe rc=1` isolates the fresh-procfs mount as the failing operation on the real host kernel (H6). Both failing = the failure is not the procfs mount (H3 beyond `--proc`, H7, H8). It is also the first measurement of a procfs-free argv, the shape one candidate fix would take. It proves the MECHANISM inside the canary, not what tenants experience (both probes run under `docker exec`): tenant impact is a separate read (Better Stack rows from `CONTAINER_NAME=soleur-web-platform`, Sentry) |
| `kernel_ns` | userns sysctls as the container sees them | `restrict=1` or `max=0` = host userns policy |
| `host` | the canary's `HostConfig`: `capadd`, `capdrop`, `priv`, `aa` (AppArmor profile) | a `SYS_ADMIN` cap-add or `priv=true` is a host-script defect |
| `hostsec` | the `SecurityOpt` entries, each cut to 40 characters | expect `apparmor=soleur-bwrap` and a `seccomp={...` entry. docker inlines the whole seccomp profile here, so it is cut; a missing `seccomp=` entry means the profile was not applied |
| `kernel` | host kernel and docker server version | version drift context |
| `kdeny` | one bounded, credential-scrubbed read of the HOST kernel stream: `src=<journal\|dmesg\|none> j=<state> d=<skip\|state> total=<n> hits=<n> mproc=<n> [fields]` | see "Reading `kdeny`" below. `mproc>=1` with `operation='mount'` and `fstype='proc'` = the AppArmor profile denied the mount (H7); `mproc=0` is neutral, never evidence of absence (see "Reading `kdeny`") |
| `done` | `exec_rc=<n> lines=<n> capped=<0\|1> bytes=<n>` | emitted even when the exec failed. `exec_rc=0 lines=11 capped=0` = the bundle completed (`lines` > 11 with `exec_rc=0` = a multi-line value spilled into `raw` rows; still complete). `124` = the exec timed out and the LAST sections (the probes) are missing; `137` = it ignored the TERM and the 3 s kill-after fired; `127` = `docker` or `timeout` missing; `141` (or `1`) with `bytes` near 8192 = OUR 8 KiB read cap, not an exec failure (`capped=1` alone is the separate 16-row cap and says nothing about `exec_rc`); any other non-zero = `docker exec` itself failed |

### Which hypothesis holds (H1-H8, from the plans)

| H | Hypothesis | Rows that decide it |
|---|---|---|
| H1 | The image still has `cap_sys_admin+ep` on `/usr/bin/bwrap` (stale or mis-built), and the bounding set lacks SYS_ADMIN, so execve is EPERM | `caps` has a `cap_` token; `prov` BUILD_SHA is the pre-fix commit (48d5144cf4), not the tag's; `direct_version rc=126` |
| H2 | Exec is denied by LSM (AppArmor) or seccomp, independent of file caps | `caps` = `bwrap=none` AND `direct_version rc=126`, with `proc` `Seccomp=2` and `lsm` naming the profile |
| H3 | Exec works; namespace/mount creation is denied (the `Can't mount proc` shape, #9860) | `direct_version rc=0` AND `sdk_probe` (or `direct_probe` under `trigger=legacy`) failing with a namespace/mount error, AND `kernel_ns` shows a restrictive userns policy or the faithful canary's `reason` names the mount (`sdk_probe` alone cannot decide it: see its row) |
| H4 | The shim, not bwrap, is the culprit | `direct_probe rc=0` while the shimmed probe failed (`trigger=legacy` only) |
| H5 | Container posture drift | `host` (`capadd`/`capdrop`/`priv`/`aa`) and `hostsec` differ from the `docker run` in `ci-deploy.sh` |
| H6 | docker's masked `/proc` makes the kernel refuse a fresh procfs inside the user namespace (a silent EPERM: no kernel log line). Became fatal when the shim started requiring `--proc /proc` on every SDK argv (#9768) | `sdk_noproc rc=0` AND `sdk_probe rc=1` in the same event, and no `systempaths=` entry in `hostsec` (`kdeny` is neutral for H6: `mproc=0` and an unreadable stream read alike). Corroborated by the local repro in the `sdk_probe` row. Tie-breaker with H7 when `kdeny` is unreadable: an AppArmor denial returns EACCES (the logged `error=-13`) while bwrap reported EPERM (`Operation not permitted`), and `apparmor-soleur-bwrap.profile` carries an unconditional `mount,`, so EPERM plus an unreadable `kdeny` makes H6 PROBABLE and H7 not excluded, never confirmed. Treat H6 as presumed tenant-impacting until a live read says otherwise. A different subsystem (agent sandbox shim, ADR-075/272): open a separate issue, do not weaken the `/proc` mask here (it is the cross-tenant control from #9723). **RESOLVED by #10032 (ADR-075 addendum 2026-10-11):** the shim no longer emits `--proc` — it drops every procfs mount at `/proc` (the vendored tail bind included), keeps/appends `--tmpfs /proc` as the realized mask, and re-homes command-side `/proc/self/fd/N` refs as literal `--ro-bind` mounts. A fresh-procfs EPERM can no longer be emitted by the shim by construction; `sdk_probe`/`sdk_noproc` remain valid posture probes of docker's masked `/proc`, but their `--proc`-carrying shape no longer mirrors what the shim emits — read a `sdk_probe` failure on a post-#10032 deploy as the posture class it measures, not as the deployed shape |
| H7 | The `soleur-bwrap` AppArmor profile denies the mount | `kdeny` `mproc>=1` with `operation='mount'` and `fstype='proc'` in its fields, in the same bundle as a failing `sdk_probe`. Strongest with `src=journal` (a 5-minute window). `src=dmesg` is not time-bound and `mproc` is host-wide (the production container shares the profile), so a hit there is suggestive only: check it against the event time. H6 and H7 can coexist, so also read `sdk_noproc` |
| H8 | Seccomp denies an unlisted syscall (a newer bwrap/glibc path) | not decidable from the kernel stream: the profile's default action is ERRNO and silent unless it logs, in which case a `type=1326` record raises `hits` (its `syscall=` field names it). The static profile reading (`seccomp-bwrap.json`) is the evidence: `mount`, `umount2`, `pivot_root` are unconditionally allowed |

H1 is excluded only when `caps` is `bwrap=none`; `done` must read `exec_rc=0` first, or the rows that decide H2-H4 may be missing.

### Reading `kdeny`

The journal rung reads through a fixed-argv sudoers grant (#10045, `KDENY_KERNEL_STREAM`: `sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat`, `timeout` outside sudo), so on a grant-bearing host the expected reading is `src=journal j=ok` — every granted read writes a `sudo: deploy : ... COMMAND=` audit record into the same journal. On a host without the grant (rollout window, stale birth) sudo's own denial signature — `sudo:`-prefixed (sudo-rs) or `Sorry,`-prefixed (GNU) — falls back to the pre-grant unprivileged read — `noaccess`/`empty` there is the old degraded contract, not a new failure class. "Could not read" is a different fact from "read it, nothing there". The row names which, per rung (`j=` journal, `d=` dmesg; `d=skip` when the journal answered):

| state | meaning |
|---|---|
| `ok` | at least one real line and rc 0 (or an anchored denial read before a non-zero exit): the kernel text was READABLE. It does not prove audit records reach this stream (see below); `total=400` (or fewer when the 64 KiB cap bit first) means the window is saturated and a denial may have scrolled out |
| `empty` | rc 0, no hint, no lines. systemd 261 prints NOTHING for a user outside `adm`/`systemd-journal`, so this is indistinguishable from a quiet window: it is NOT a healthy reading |
| `noaccess` | the tool's own hint (`Hint: You are currently not seeing messages` with its two continuation lines, `No journal files were opened`, `dmesg: read kernel buffer failed`, or `Failed to ... Permission denied` / `Operation not permitted`) and no real lines. `-- No entries --` style banners are neither hints nor lines, so they read `empty` |
| `absent` / `timeout` / `error` | rc 127 / rc 124 or 137 (each rung is cut at 3 s; lines already read are discarded) / any other non-zero rc, with or without lines (error text is not a kernel line) unless an anchored denial was already read. Only the reader's own exit code is checked: a failing `tac`/`head` stage is not itself reported (it reads `empty`, or `error` when the reader takes SIGPIPE) |

`src=none j=noaccess d=noaccess` means the kernel log carried neither answer and H6/H7 are undecided by it — `sdk_noproc`, `hostsec` and the local repro carry the diagnosis. Post-grant this reading is ALSO a delivery signal: the host may not have the grant yet (rollout window or a stale birth) — the provisioner FATAL or a re-run of the bridge's `runuser -u deploy -- sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat` execute probe is the arbiter; a persistent `noaccess` on a post-rollout host is a delivery failure to investigate, not a datum. `hits` counts `apparmor="DENIED"` and seccomp `type=1326` records among the newest 400 lines of the last 5 minutes (journal) or of the ring buffer (dmesg), capped at 64 KiB, newest first. A bare `profile="soleur-bwrap"` is NOT a hit test: the production container shares that profile. The fields come from a closed key set (`operation profile fstype error info requested_mask denied_mask syscall`) with no `name`, `comm` or `pid`, so no tenant file name reaches Better Stack. printk ratelimiting can drop records, and a silent ERRNO leaves none, so `mproc=0` narrows the field and never closes it.

Four more limits on reading `j=ok`:

- **Audit routing.** If auditd (or journald-audit) is active, AppArmor and seccomp records go to the audit stream and not the kernel text, so `j=ok hits=0 mproc=0` can be a false negative. No field reports whether audit routing is active, so treat `mproc=0` as always neutral; the H6 rule rests on `sdk_noproc`, `sdk_probe`, `hostsec` and the EPERM tie-breaker, not on `mproc=0`.
- **Anchoring.** A hit is an audit record (a line starting `audit: type=1400|1326 audit(<ts>:<n>):` then a space, after dmesg's optional `[ts]` prefix and its space), so printk lines that merely echo tenant text cannot raise `hits`. `hits>=1` with `mproc=0` is a different denial: read the first hit's `operation=` field before concluding anything.
- **Spoofing.** The reads are line-based. A tenant-influenced string that reaches the kernel log with an embedded newline could in principle start a line that looks like an audit record, so `hits` and the fields are diagnostic hints, not authenticated evidence. What can reach Better Stack is bounded: a closed key set, `fstype` limited to a short token, and 130 characters of fields. Weigh `mproc>=1` together with a failing `sdk_probe` in the same bundle and `src=journal`, never alone.
- **Row shapes.** `section=kdeny val="<empty>"` means `_canary_kdeny_read` itself failed inside its substitution (not `j=empty`). A bundle with `lines=10` and no `sdk_noproc` or `kdeny` row came from the previous script (ten in-container rows plus four host rows), not an incomplete bundle.

**Reading absence.** The anchor for "a bundle should exist" is `trigger=legacy`: a `DEPLOY_ROLLBACK: bwrap sandbox
non-functional` row; `trigger=faithful` has no rollback row, its anchor is the `sandbox-canary` Sentry event or the
`Faithful sandbox canary (non-blocking): verdict=sandbox_broken` line; `trigger=sdk_smoke` has no rollback row either, its anchor is the
`SDK Bash smoke (non-blocking): verdict=sdk_bash_smoke_failed` line / `SANDBOX_CANARY_FAIL: verdict=sandbox_broken
reason=sdk_bash_smoke_failed` journald row and the `sandbox-canary` Sentry event it posts. Then query the three row kinds together
(`--grep` is repeatable and OR-combined):

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --limit 200 \
  --grep DEPLOY_ROLLBACK --grep SOLEUR_CANARY_SANDBOX_DIAG --grep DEPLOY_SCRIPT_SHA \
  | jq -r '.raw | fromjson? | select(.SYSLOG_IDENTIFIER=="ci-deploy") | [.host_name, .message[0:150]] | @tsv'
```

| Rows seen | Meaning |
|---|---|
| a `done` row with `exec_rc` != 0 and `lines=0` | the bundle ran and the exec failed (read `exec_rc` above) |
| a `done` row with `exec_rc=0` and `lines=0` | the exec ran and printed nothing: not an exec failure, a broken container shell or image (check `prov` on an earlier deploy's bundle, then the image) |
| no `done` and no DIAG rows, and the newest `DEPLOY_SCRIPT_SHA` for that host differs from the repo's | the host still runs the previous `ci-deploy.sh` (it is delivered by `apply-deploy-pipeline-fix`, whose run can be evicted by a pending `apply-web-platform-infra` run in the shared concurrency group, #8167): the bundle never ran |
| no `done` and no DIAG rows, and the SHA equals the repo's | the shipping path or the `--since` window, not the bundle (`done` is emitted even when the exec fails): check Vector lag and the archive window |

Parity check: `bash scripts/check-deploy-script-parity.sh --bs-only` needs no web-1 credentials (it self-wraps in
Doppler). The default runs both arms; the status arm (`--status-only` is web-1 only and is an alternative to
`--bs-only`, not an addition) needs `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` exported
from Doppler `soleur` / `prd_terraform`, the recipe in the `Verify deploy-script parity` step of
`.github/workflows/apply-deploy-pipeline-fix.yml`. On drift the remedy is `gh workflow run apply-deploy-pipeline-fix.yml`,
a production-delivery dispatch that needs explicit per-command authorization from the operator (it is an agent action,
not a manual step).

## Faithful sandbox canary — #8752 hardening verdicts

`sandbox_canary.verdict` in deploy-state (and its Sentry `op=sandbox-canary` event) now covers the
sandbox-hardening pair, not only sandbox-build health. Decoding `reason` (all `sandbox_broken` reset
the consecutive-pass soak and are reported as a Sentry event plus a journald row; `canary_infra_error` rows hold the soak and never
roll back. **None of the inner canary's reasons emails anyone:** no Terraform Logs alert keys on `op=sandbox-canary` for the inner
canary (the only alert on that op is `faithful_canary_sandbox_broken`, which requires `reason=sdk_bash_smoke_failed`) and
`apps/web-platform/infra/sentry/` carries no rule for it, so a `sandbox_broken` here is visible only as the `op=sandbox-canary` Sentry
event and the `SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=<reason>` journald row (live Sentry rules that are not in the repo
are unreadable to the read-only tokens and were not checked). This includes `unixdeny_filter_bypass`, `unixdeny_artifact_unusable`,
`base_denies_af_unix` and `base_artifact_unusable`: a defect in the dark, flag-OFF variant artifact (or in the base artifact the AF_UNIX
control runs against) resets the #5875 base soak BY DESIGN, because the variant is verified on the same canary verdict and ledger as the
base posture; it surfaces as a Sentry event and a journald row, not as an email):

| `reason` | Meaning | First move |
|---|---|---|
| `userns_filter_bypass` | Nested `unshare -U` ran INSIDE the replayed sandbox — the shared seccomp filter is not engaged (shim absent/misrouted) | `bash apps/web-platform/scripts/bwrap-userns-seccomp-probe.sh` in the canary image; check `op=sandbox-hardening-selfprobe` |
| `userns_filter_overbroad` | A forked child failed inside the filtered sandbox — the filter denies more than nested userns | Regenerate/verify the artifact (`gen-bwrap-userns-seccomp.mjs --check`); do NOT weaken the filter to unblock |
| `fd_hygiene_bypass` | The in-sandbox fd census exceeded `4 + #fd-valued-argv-options` — an unreferenced fd leaked past the shim's sweep | Inspect `bwrap-shim:` lines + the shim's preserve-set arity table |
| `unixdeny_filter_bypass` | Under the unixdeny artifact the in-sandbox probe CREATED an AF_UNIX socket (ENOENT on connect) - the variant's `socket(AF_UNIX)` deny is not engaged (#10455 a) | `node apps/web-platform/scripts/gen-bwrap-userns-seccomp.mjs --check` in the canary image; the flag must stay OFF until this is green |
| `unixdeny_artifact_unusable` | The shim refused the variant artifact (`bwrap-shim:` line: absent or unreadable `/app/infra/bwrap-userns-clone3-unixdeny.bpf`) - with the flag ON every no-egress session would die with exit 65 | Check the Dockerfile COPY and the `.dockerignore` bang; do NOT turn the flag on |
| `base_denies_af_unix` | Under the BASE artifact `socket(AF_UNIX)` was denied - egress sessions' proxy bridges would break | Base artifact drifted from `origin/main` bytes: regenerate with the generator and re-run `bwrap-userns-seccomp.test.ts` |
| `base_artifact_unusable` | The shim refused the BASE artifact in the AF_UNIX control probe (`bwrap-shim:` line) - every session would fail to start, flag or no flag | Check the Dockerfile COPY of `infra/bwrap-userns-clone3-deny.bpf` and the `.dockerignore` bang, and read the `bwrap-shim:` line for the exact refusal |
| `args_fd_closed` | The `--args <fd>` transport probe failed — the SDK's real spawn shape broke (shim closed the argv fd) | Every agent spawn fails too; treat as deploy-blocking |
| `bwrap_shim_refused[: <detail>]` | The shim itself exited 65 (`bwrap-shim:` marker) — artifact or real bwrap missing in the image; **post-#10032 also fires on unresolvable command-side `/proc/self/fd/N` refs** (deleted/non-file/procfs-resident/absent fd — including a command that merely *mentions* the path), and on `/proc`-mounting argvs lacking `--unshare-pid`/`--unshare-user`. The verdict's `detail` field (folded into the deploy-state reason as `bwrap_shim_refused: bwrap-shim: <first refusal line>`) names the class | `probeAgentSandboxHardening` fields (`shim`, `filter`, `bpfBytes`) cover the artifact/binary-missing classes; the `bwrap-shim:` line names the rest |

## SDK Bash smoke and the `helper_userns_eperm` denial (#10445)

> **Status (2026-10-19): the deploy-time `sdk_bash_smoke` is implemented and report-only (#10453).** `run_sdk_bash_smoke` in
> `ci-deploy.sh` runs it in the canary container on every web-platform deploy, records a verdict in its own ledger
> (`/mnt/data/ci-deploy-sdk-bash-smoke.json`) surfaced as `.sdk_bash_smoke` on `/hooks/deploy-status`, and pages through the
> `faithful_canary_sandbox_broken` Better Stack alert. It never rolls back and never changes the deploy's exit code. Promotion to a
> blocking gate is #10548 (5 green verdicts over at least 3 days with the coverage field). Also in place: the runtime
> `agent_sandbox_bash_denial` alert, the pre-merge wrapped-command guards (`test/sandbox-wrapped-command-runtime.test.ts` and the
> wrapped-command/census arms of `infra/sandbox-masked-proc-docker.test.sh`), the probe parity suite
> (`test/sdk-bash-probe-parity.test.ts`) and the soak-gated promotion's own stateless verdict script,
> `sdk-bash-smoke-verdict-10548.sh`.
>
> **Revert order.** Revert this PR as a whole. A partial revert must revert the smoke commits (`sdk-bash-probe.mjs`,
> `run_sdk_bash_smoke`) before, or together with, the artifact/server commits; reverting only the artifact leaves the smoke setting a
> selector to a missing file: every deploy then emits `sdk_bash_smoke_failed` and the paging email while production runs base.

**Why this exists.** The faithful canary above replays the captured bwrap SETUP argv and ends in `-- true`, so it
never runs the process the Agent SDK wraps around every sandboxed Bash command
(`ARGV0=apply-seccomp /proc/self/fd/<N> <shell> -c <cmd>`). From 2026-10-06 the shim's seccomp filter denied
`unshare(CLONE_NEWUSER)`, which that embedded helper needs, and every hosted Bash call failed while
`sandbox_canary` read `verdict=pass` (ADR-079 addendum 2026-10-16; PIR
[`hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md`](../post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md)).
A green `sandbox_canary` therefore certifies the bwrap setup only; it is NOT evidence that Bash works.

**How the smoke is decoded (implemented, #10453).** `sdk_bash_smoke` is a separate object in `/hooks/deploy-status` (read it with the
call pattern in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`, no SSH): `verdict`, `reason`, `coverage`,
`consecutive_pass`, `first_pass_at`, `consecutive_infra_error`, `checked_at`. It runs ONE real Bash command
(`echo SDK_SMOKE_$(printf %s '<per-run nonce>' | tr 0-9a-f a-f0-9)`: the tool_result must carry the TRANSFORMED nonce, so a result that
only quotes the command text cannot pass) end to end through the SDK's own wrapper path and the shipped shim, inside the CANARY container
(never the live prod container), under `/usr/bin/env -i` with an explicit allowlist, a decoy `ANTHROPIC_API_KEY` and the container's real
`HOME`, under a 150 s host `timeout` (`SDK_BASH_SMOKE_TIMEOUT`) above the probe's 120 s internal cap. The smoke makes TWO canary
`docker exec`s, each under its OWN cap: one pre-exec (`test -f <probe> || exit 66; printf %s "$HOME"`) that checks the probe file
and reads the container's real `HOME`, capped at 20 s (`SDK_BASH_SMOKE_PREEXEC_TIMEOUT`), then the probe run itself under the 150 s cap.
The smoke's total time is therefore bounded by `SDK_BASH_SMOKE_PREEXEC_TIMEOUT` + `SDK_BASH_SMOKE_TIMEOUT` (170 s by default), plus the
bounded DIAG bundle after a failure page. The probe (`infra/lib/sdk-bash-probe.mjs`, `SMOKE=1`)
computes its own verdict: `pass` requires the transformed nonce echoed in the real tool_result, a non-error result and coverage
`sdk_wrapper_shim_prodtuple` (the shim on `PATH`, a sock_filter-sized artifact at the pinned path). **Coverage means the shim on PATH,
the pinned `buildAgentSandboxConfig` literal and the variant artifact under the no-egress shape. It does not cover the SDK child env,
query options, the outer-wrap spawn, or the flag-OFF base.** The smoke workspace is also a `mkdtemp` under `/tmp`, not a path under
the denied `/workspaces` root, so the production mount shape (tmpfs-mask of the denied workspaces root, then a re-bind of the session's
own workspace) is NOT exercised by the smoke; the real-bwrap tests exercise it (`test/sandbox-isolation.test.ts` direct tier, which also
runs in the canary as `run_workspace_isolation_probe`, and `test/sandbox-wrapped-command-runtime.test.ts`, which points
`WORKSPACES_ROOT` at a temp root). It is non-blocking (`wg-dark-launch-deploy-gates`):
`run_sdk_bash_smoke || true`, no verdict rolls back or aborts. It runs AFTER the GitHub App key gate (its own `CANARY_HEALTHY` check), so a smoke OOM or a probe still running after a host-cap timeout cannot fail that gate and roll back a deploy.

**Headroom obligation (before promotion to blocking, #10548).** The canary runs with `--memory 1536m --memory-swap 1536m` and already hosts the Next server; the smoke adds a node probe, a stub HTTP server, the SDK CLI and a bwrap'd Bash child with no measured headroom. Before promoting the smoke to a blocking gate, record the canary cgroup's `memory.peak` and the `oom_kill` counter in `memory.events` during a smoke run. Requirement: zero OOM kills and peak below 80% of 1536 MiB. Documentation obligation only; nothing measures it today.

| `verdict` / `reason` | Meaning | First move |
|---|---|---|
| `pass` | A real wrapped Bash command ran green through the shim and its nonce came back. `coverage` is `sdk_wrapper_shim_prodtuple`: a verdict without that field certifies nothing about the wrapper | None. Promotion needs 5 green verdicts over at least 3 days (ADR-079, tracker #10548) |
| `sdk_bash_smoke_failed` | Bash WAS dispatched and no verified nonce came back: an error result, a clean result without the nonce (`no_nonce`), a thrown SDK error (`dispatched_then_error`, or `sandbox required but unavailable` even before dispatch), no tool_result (`dispatched_no_tool_result`), a hang (`hung_after_dispatch`), the host cap firing AFTER the probe printed `SDK_BASH_DISPATCHED` (`host_timeout_150s`), or any other non-zero `docker exec` rc whose output already carries the `SDK_BASH_DISPATCHED` LINE (`probe_rc_<N>_after_dispatch`: Bash was handed to the SDK, so a death after that is the #10445 shape, not an infra hiccup; the marker, not the rc, decides, 124 included), EXCEPT rc 137 and 143 (SIGKILL / SIGTERM: the OOM killer, a container stop or a deploy-side signal), which are `smoke_infra_error` / `probe_killed_rc_<N>` (see the infra row). Signature-independent: a new error wording cannot go silent. A journald row `SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=sdk_bash_smoke_failed: <detail> ... (op=sandbox-canary; ...)` pages `faithful_canary_sandbox_broken` (one row per failed deploy) and a Sentry event (`op=sandbox-canary`, level error) is posted | Read `reason` (the first sandbox error line, scrubbed) and the `SOLEUR_CANARY_SANDBOX_DIAG` rows with `trigger=sdk_smoke` that follow the page. `apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted` is this incident: confirm `network.allowAllUnixSockets` is still set and that no SDK bump changed the helper-selection condition (`vendored-bwrap-tail` tests). Do NOT carve a `CLONE_NEWUSER` exception in the filter: a seccomp filter cannot key on the caller, so it re-opens nested userns for every sandboxed process (undoes #8752) |
| `smoke_infra_error` / `probe_absent` | The ONE pre-exec (`test -f <probe> \|\| exit 66; printf %s "$HOME"`, capped at `SDK_BASH_SMOKE_PREEXEC_TIMEOUT`, 20 s) answered rc 66, and ONLY rc 66 is `probe_absent`: the probe file is missing in the canary image (an image that predates the probe, or a Dockerfile/`.dockerignore` regression). Every other non-zero pre-exec rc is a different row: `preflight_rc_<N>` (docker's own 125/126/127, a missing canary container answering 1, ...; docker's first scrubbed stderr line follows the colon), and the cap's 124 is `host_timeout_before_dispatch: preflight` (a wedged daemon, before Bash could be dispatched) | New script with an old image is expected once. Persistent: check the Dockerfile COPY of `infra/lib/sdk-bash-probe.mjs` and its `.dockerignore` bang (`test/sdk-bash-probe-parity.test.ts` pins both) |
| `smoke_infra_error` / `preflight_rc_<n>`, `docker_exec_rc_125\|126\|127`, `probe_rc_<n>`, `probe_killed_rc_137\|143`, `no_result_line`, `container_home_unresolved`, `nonce_unavailable`, `host_timeout_before_dispatch`, `sdk_module_unavailable`, `stub_server_failed`, `nonce_missing_or_malformed` | The smoke itself could not run or print a verdict (daemon trouble, node missing, the pre-exec failing with a non-66 rc, the probe crashed BEFORE printing `SDK_BASH_DISPATCHED`, no `SDK_BASH_RESULT` line, no `/dev/urandom` nonce, or the 150 s host cap firing before the probe printed `SDK_BASH_DISPATCHED`). `probe_killed_rc_137\|143` is the one row where the marker WAS printed: the probe was SIGKILLed / SIGTERMed after dispatch (the OOM killer, a container stop, a deploy-side signal), which says nothing about Bash, so it holds the soak instead of paging. Otherwise Bash was never dispatched (any other non-zero rc AFTER that marker line is `sdk_bash_smoke_failed`, above) | No signal; holds the soak and never pages. The reason carries docker's first stderr line |
| `smoke_infra_error` / `coverage_replay_only` | A pass-shaped result whose coverage was not the shim-and-wrapper tuple (the shim is not the `bwrap` on `PATH`, or the artifact is missing/unreadable). A HOLD: `consecutive_pass` does not move | Treat as not-yet-proven; inspect `probeAgentSandboxHardening` (`op=sandbox-hardening-selfprobe`) and the faithful canary's hardening verdicts |
| `smoke_infra_error` / `ledger_write_failed` | The verdict could not be recorded (the `/mnt/data` ledger is unwritable, read-back mismatch). Never reported as a pass; a real FAILURE still pages. A failed write ALSO emits the stale warning at once (`SDK_BASH_SMOKE_STALE`, prior counter + 1) with its own wording, "SDK smoke ledger write failed (consecutive_infra_error not advanced)" (the counter did not advance in the ledger, so it is not reported as "N deploys in a row"), because a ledger that cannot be written cannot accumulate the counter that would otherwise raise it. A `sdk_bash_smoke_failed` verdict whose write failed tries to DELETE the stale ledger so an old `consecutive_pass` cannot keep reading as a soak this failure should have reset, but only a record that carries the smoke's own ledger stamp and is older than this run (`checked_at` < the run's start), and only when the ledger directory is writable: the `rm` needs the permission whose absence usually broke the write. When the directory is not writable the old record survives and the next pass can read its stale counters; the page and the stale warning still fire | Check `/mnt/data` space and ownership via the deploy-status fields; the journald row `SDK_BASH_SMOKE: ledger_write_failed` names the file |

**The stale warning.** `smoke_infra_error` never pages by email, so a dead probe needs another consumer. At three consecutive infra
errors (`consecutive_infra_error >= 3`) the deploy emits a journald row `SDK_BASH_SMOKE_STALE: consecutive_infra_error=<n> last_reason=...`
and a Sentry WARNING (`op=sandbox-canary`, `event=sdk_bash_smoke_stale`): recorded in journald and Sentry, flagged on the #10548 tracker by
the follow-through at 3 consecutive infra errors, not emailed. The #10548
follow-through (`scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh`) reads the same counter from `/hooks/deploy-status` and exits 1
(FAIL, `probe is blind`) at `consecutive_infra_error >= 3`, which flags the #10548 tracker; 1-2 infra errors stay a retry (exit 2). Treat it as
"the deploy-time Bash check is blind"; the next green or failed verdict resets the counter. **Caveat for the first week:** the #10548
directive carries `earliest=2026-10-26T00:00:00Z`, and the sweeper does not run the script before that date, so until then a blind probe
is visible only in journald and Sentry (and in `/hooks/deploy-status` for anyone who reads it).

**No-SSH reads.** (1) `/hooks/deploy-status` `.sdk_bash_smoke`; (2) journald rows `SDK_BASH_SMOKE: verdict=... reason=... coverage=...`
(one per deploy, the `ci-deploy` tag) through the Better Stack query in
[`betterstack-log-query.md`](./betterstack-log-query.md#standing-alarms-over-this-source-log-content-recurrence-alarms); (3) the soak
verdict, which needs the signing secret and the Cloudflare Access pair (`WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`,
`CF_ACCESS_CLIENT_SECRET`, the three names in the script header and in the #10548 directive):

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh
```

It prints ONE line starting `sdk_bash_smoke` and reads the HMAC-signed, Cloudflare-Access-gated deploy-status request (the response is not
signed). Exit codes (per the sweeper contract, `scripts/sweep-followthroughs.sh`): **it never exits 0**, because exit 0 would make the
sweeper CLOSE the tracker and #10548 also tracks the promotion itself and the operator-authorized flag decision, which no script can observe.
`5` = ACTION REQUIRED (soak complete: at least 5 consecutive green verdicts over at least 3 days, latest verdict `pass`, coverage
`sdk_wrapper_shim_prodtuple`; the sweeper treats 5 as notify-only: it comments, leaves the issue open, and on an already-closed issue
comments without reopening), `1` = FAIL (a recorded `sdk_bash_smoke_failed`, OR `consecutive_infra_error >= 3`, the stale escalation above),
`2` = TRANSIENT (unreachable endpoint, soak not complete, 1-2 infra errors, a pass without full coverage, a non-numeric counter, or a
complete soak whose ledger `checked_at` is more than 3 days old: `reason=ledger_stale`, because a frozen ledger is not evidence). The script
also exits `78` when it is run under `bash -x` with a live credential bound (declined before any request). A human
closes #10548 after the promotion change and the flag decision are done, and REMOVES the `follow-through` label at that point: exit 5
comments ACTION REQUIRED at every sweep on an open tracker (and on a closed one that still carries the label), so a finished soak with the
label left on is a daily comment. The ledger is the smoke's OWN file: the deploy-status frame is
shared by every component's deploy, so soak accounting never reads it.

**Config parity.** The probe carries a literal sandbox config and seccomp-selector path (the production image has no TypeScript).
`test/sdk-bash-probe-parity.test.ts` deep-equals the literal with `buildAgentSandboxConfig(...)` for the no-egress shape and prints the
diff and the exact line to change on drift; it also pins the selector path to the shim default, the Dockerfile COPY and the
`.dockerignore` bang. The egress shape is exercised pre-merge by the real-SDK arm of `test/sandbox-wrapped-command-runtime.test.ts`,
not by the deploy smoke.

**First move on a `helper_userns_eperm`** (the runtime classifier code on the `op=bash-tool-result` mirror, paged by
`agent_sandbox_bash_denial`, see
[`betterstack-log-query.md`](./betterstack-log-query.md#standing-alarms-over-this-source-log-content-recurrence-alarms)).
Executable without `sdk_bash_smoke`: (1) run the alert's Query block in that runbook for `rows`, `users` and the
first timestamp (and its positive-control query if the count is zero); (2) read `/hooks/deploy-status` for
`sandbox_canary` and the deployed tag, remembering a green canary does not certify the wrapper; (3) `rows` from more than
one user is real and fleet-wide, so check that `network.allowAllUnixSockets` is still set in
`agent-runner-sandbox-config.ts` and the SDK version (`sandbox_canary.sdk_version`), and re-run the pre-merge proofs
(`test/sandbox-wrapped-command-runtime.test.ts` and the wrapped-command arms of `infra/sandbox-masked-proc-docker.test.sh`);
(4) make a real hosted Bash call and read the result; (5) a single user's rows are either a tenant echoing the line (the accepted limitation below) or a real regression seen by the only active tenant; step (4) decides, never the user count. Read `sdk_bash_smoke` alongside `sandbox_canary`
in step (2): a red smoke plus multi-user rows is conclusive. If a rollback of the sandbox posture is ever considered, the shim
kill-switch needs explicit CTO acknowledgement and a time box; it is not a routine step.

**Which helper step failed, and what the tenant sees (#10455 c, e).** The helper embedded in the vendored `claude` binary
prints `apply-seccomp: <step>: <strerror>` on a failing step. Measured on `claude-agent-sdk` 0.3.284 (the same 17 strings
are in `claude-code` 2.1.293): 16 `<step>` literals plus the errno-less `observe sendmsg failed`. Runtime order,
recorded 2026-10-19 with an `LD_PRELOAD` interposer around the helper (not recalled from source):
`unshare(CLONE_NEWPID|CLONE_NEWNS)` attempt, `unshare(CLONE_NEWUSER)`, `write /proc/self/setgroups`, `write
/proc/self/uid_map`, `write /proc/self/gid_map`, `unshare(CLONE_NEWPID|CLONE_NEWNS) after userns`, `fork` (the PID-namespace
init), then in the init `prctl(PR_SET_DUMPABLE)`, `mount(MS_PRIVATE)`, `mount(/proc)`, `prctl(PR_CAP_AMBIENT_CLEAR_ALL)`,
`fork(worker)`; the worker then runs `prctl(PR_SET_NO_NEW_PRIVS)`, `prctl(PR_SET_SECCOMP)`, `execvp`; both waiting
processes print `waitpid` AFTER the tenant command ran. All 16 are classified (`helper_userns_eperm` for the userns step,
`helper_step_eperm` for the rest) and page `agent_sandbox_bash_denial`. The 15 steps before the tenant command
(`HELPER_STEPS_PRE_COMMAND`: everything above up to and including `execvp`) can trigger the tenant notice; only `waitpid`
(`HELPER_STEPS_POST_COMMAND`), which prints after the command ran, never does. (CTO ruling 2026-10-19: widened from the 11 steps
before `fork(worker)`, because the measured order runs `fork(worker)`, both `prctl` steps and `execvp` before the tenant command;
flip `execvp` out to make it 14 only if a measured argv shows the helper execs the tenant argv directly.) A test re-reads the binary's strings and reds when this list and the binary disagree in either direction, so an SDK
bump that adds a step surfaces in CI rather than as an unclassified line.

In autonomous sessions the streamed `command_stream` text of a Bash result that is, as a whole, ONE error-flagged
pre-exec sandbox line is replaced by: "Platform notice: command execution
is temporarily unavailable on our side. This is a platform issue, not a problem with your project." The rewrite needs that single
line to START with `bwrap:` plus a space (and carry EPERM / `Operation not permitted`), or to be an exact-allowlisted `apply-seccomp: <step>:
Operation not permitted` line for one of the 15 pre-command steps (any classified helper step except `waitpid`); a line that merely
CONTAINS "bwrap" (`rm: cannot remove 'bwrap': Operation not permitted`) is never rewritten. The mirror event is
emitted first from the raw output. The SDK-visible tool_result is not rewritable, so the model still sees the raw line and a
system-prompt directive (`BASH_UNAVAILABLE_PROMPT_DIRECTIVE`) tells it not to echo it, to retry the same command ONCE only
when it is read-only or idempotent, and after a second failure to stop and say to try again later. The directive is a prompt, not code:
it triggers only on a FAILED Bash call (result marked as an error) whose whole output is ONE line starting `apply-seccomp:` or `bwrap:`
and ending in `Operation not permitted`. The retry is
model-compliance based (the SDK turn cap bounds a non-compliant loop); non-autonomous sessions rely on the directive alone.

**Scope of the signal (CTO ruling E, 2026-10-19).** The `agent_sandbox_bash_denial` alert and the notice rewrite cover cc-soleur-go
sessions only. The legacy runner has no tool_result observer, so a helper EPERM there is neither mirrored nor paged. A variant-induced
AF_UNIX EPERM has no signal on either runner. (Routing, `server/conversation-routing.ts` and `server/ws-handler.ts`: a conversation whose
`active_workflow` is NULL parses to routing `legacy` and runs on the legacy runner, `agent-runner.ts` `startAgentSession` /
`sendUserMessage`; a conversation with `soleur_go_pending` or `soleur_go_active` routing runs on cc-soleur-go,
`dispatchSoleurGoForConversation`.) The #10455 open item "Legacy agent-runner loop has no tool_result observer" stays open and gains
"variant-EPERM signal".

**Accepted forgery limitation.** The runtime classifier reads Bash `tool_result` text, which a tenant controls.
The arm matches only the exact helper line (`apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted`,
line-anchored, nothing trailing), is debounced per user (keyed with the error code), and the alert filters on the helper
`sandboxErrorCode`s, so a tenant-printed `bwrap` line cannot reach it. A tenant CAN still print an exact helper line and
keep one incident open, suppressing new pages (see the alert's entry in `betterstack-log-query.md`; mitigation tracked
in #10455). The same forgery can reach the tenant notice: the notice requires the SDK's error flag, a single non-blank
line and a pre-command helper step, but a command that ran and exited non-zero can print that line. That residual is accepted, which
is why the notice does not claim the command did not run. The deploy-time smoke (#10453), not tenant text, is the authoritative signal; the email only prompts the check above. The wake path for both alerts is email-only on
the Better Stack free tier until the ADR-260 Slack integration is verified.

**Slack wake check, run 2026-10-19 (#10455 d), read-only.** Two reads with the read-only token (Doppler `soleur/prd_terraform`,
`BETTERSTACK_API_TOKEN_READONLY`; counts and flags only, nothing written):
`GET https://uptime.betterstack.com/api/v2/slack-integrations` answered HTTP 200 with one `slack_integration` entry (it answered
`{"data":[]}` before #9168, see `app-database-readiness-alarm.md`), and `GET https://telemetry.betterstack.com/api/v2/alerts?per_page=50`
listed 17 Logs alerts (the 16 Terraform-managed ones plus the hand-made "Output utilization high"), every one with
`escalation_target = {team_id, team_name}` (or `current_team`), `email = true` and `push`, `call`, `sms` all `false`. Verdict: **an
integration exists at account level; delivery of Logs alerts to Slack is not provable from the API** (no field ties a Logs-source alert
to a Slack channel), so both alerts stay documented as email-only and nothing here claims that Slack wakes. To repeat the check, re-run
those two reads with the token on curl's stdin as a header, never in argv (the pattern of `app-database-readiness-alarm.md`, Diagnose
step 2: `--disable --noproxy "*" --header @-`), one URL per call, summarised with `jq` so nothing large prints:

```bash
doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" \
  | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://uptime.betterstack.com/api/v2/slack-integrations' | jq '.data | length'
doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" \
  | curl --disable --noproxy "*" -sS --max-time 30 --header @- "https://telemetry.betterstack.com/api/v2/alerts?per_page=50"' | jq '.data | length'
```

What an agent cannot establish is whether the dashboard routes team alerts to the connected Slack workspace; that is a
property of the dashboard integration settings, not of anything this repository applies, and it stays open on #10455.

## Tenant-visible: no-egress AF_UNIX deny (#10455 a), runtime flag `agent-sandbox-unix-deny`

**State (2026-10-19): the flag is OFF; nothing changes for tenants until it is turned on.** Enabling is a production write that needs a
green deploy `sdk_bash_smoke` (the smoke runs the no-egress tuple with the unixdeny artifact selected, so a variant that breaks Bash start
shows as `sdk_bash_smoke_failed` on the deploy that carries it) and the operator's explicit authorization at that time (#10548). Rollback is
flipping the flag OFF. With a healthy Flagsmith an OFF flip reaches new queries in about 60 s with no restart; to be safe against a Flagsmith outage the **rollback is complete only when BOTH hold:** (a) `soleur:flag-list` shows Flagsmith OFF AND the Doppler mirror
`FLAG_AGENT_SANDBOX_UNIX_DENY=0` (the flip writes Flagsmith first and the Doppler `dev` and `prd` mirrors after it; an ON flip writes the mirror to
`1`), and (b) the container has restarted since, because the container environment IS the Flagsmith-failure fallback (`runtimeEnvFallback` in
`lib/feature-flags/server.ts` answers from `FLAG_AGENT_SANDBOX_UNIX_DENY` when the Flagsmith read fails). If Flagsmith is down during the
incident the OFF write cannot land (the flip exits before the Doppler mirror), and a failed read falls back to the container's mirror, which stays
`1` until a redeploy with Doppler at `0`: a failed Flagsmith read does NOT by itself resolve OFF. Only the resolver's own failures (a throw or its 300 ms
timeout) resolve OFF. With a healthy Flagsmith, flipping the flag OFF takes effect on new queries after up to about 60 s (the 30 s resolver memo in
`server/resolve-sandbox-unix-deny.ts` on top of the 30 s flag cache in `lib/feature-flags/server.ts`); a slow or failed read can hold the previous or OFF answer
for up to 30 s more, so re-check after 60 s before concluding the flip failed. An active cc-soleur-go conversation keeps the artifact it started with
until the idle reaper closes it: the reaper runs every 300 s and closes a conversation after 10 min of inactivity, so an idle conversation is
reaped 10 to 15 minutes after its last activity (a conversation parked on a prompt, `awaitingUser`, is skipped), while a conversation in ACTIVE use
reuses its warm query and never idles, so a user who hits `Operation not permitted` stays on the variant until they start a NEW conversation. The legacy
runner picks it up on the next message after the flip window. A restart is the only way to force it, and it is not routine. The rollback latency to state in the #10548
enable request: new queries about 60 s (healthy Flagsmith); an open conversation up to 10 to 15 minutes after its last activity, or never while it stays in use (tell
the user to start a new conversation).

**Enable request must contain** (CTO ruling G, 2026-10-19: the flag stays GLOBAL and the enable is a staged, operator-attended
procedure; a per-organisation cohort was deferred, not built). The #10548 request is incomplete without every item:

1. **Blast radius, stated in the request.** The flag is global (anonymous identity), so ONE write flips every no-egress session at once:
   the whole legacy runner (it never carries a GitHub token or a web-egress handle, so every legacy session is no-egress) plus every
   repo-less or no-web cc-soleur-go session. There is no partial rollout.
2. **A named rollback owner and the exact rollback command** (the owner types the OFF write of `soleur:flag-set-role`: flag
   `agent-sandbox-unix-deny`, role `prd`, `off`; the agent prepares its `--dry-run` preview).
3. **Rollback latency:** new queries about 60 s (healthy Flagsmith; the rollback is complete only with the Doppler mirror at `0` and a container
   restart, see the State paragraph above); each open cc-soleur-go conversation 10 to 15 minutes after its last activity, or until the user starts a
   NEW conversation if it stays in use.
4. **An operator-attended soak of at least 30 minutes after the flip.** The variant has NO telemetry of its own: nothing emits
   `socket: Operation not permitted` or `PermissionError` to Sentry (`classifyBashSandboxFailure` returns null for a plain socket EPERM, and the
   legacy loop has no tool_result observer), so there is nothing to watch for those strings. The soak is the per-runner manual probes in item 5
   plus support intake (user reports tied to the flip time). Keep watching `agent_sandbox_bash_denial`, which covers the `apply-seccomp:` helper
   lines only.
5. **A post-flip smoke of real tenant-style Bash from a NEW conversation on EACH runner path** (an open session never exercises the new
   posture): `echo ok`; `git status`; `node -e 1`; and the AF_UNIX connect below, run on each runner path:
   `node -e "require('net').connect('/tmp/soleur-no-such.sock').on('error',e=>console.log(e.code))"`, which prints `EPERM` under the variant
   and `ENOENT` under the base artifact (the image is `node:22-slim` and its `Dockerfile` installs `ca-certificates git bubblewrap socat qpdf jq openssh-client libcap2-bin`
   (plus `curl` and `gh` in a later layer) and installs no `python3`, `psql`, `gpg` or `tmux`, so a Python probe cannot run there). A tenant who
   installs other runtimes into their workspace is affected the same way (see the tenant-visible list below). The alert is not the check.
   Routing (`server/conversation-routing.ts`, `server/ws-handler.ts`): a conversation whose `active_workflow` is NULL (routing `legacy`) runs
   on the legacy runner (`agent-runner.ts`); one with `soleur_go_pending` / `soleur_go_active` routing runs on cc-soleur-go
   (`cc-dispatcher.ts`). **Open item (tracked on the #10548 enable request, not executable today):** a new conversation is routed as
   `soleur_go_pending` (`ws-handler.ts` creates the routing at ~:1850; ~:1284 and ~:1315 only map a NULL value to pending when persisting), so the legacy-runner check needs a conversation with a NULL `active_workflow`
   that may not be creatable from the product UI; the author of the enable request must establish how to obtain one (or record that the legacy
   runner cannot be exercised) before the request is sent. This runbook established the routing rule from the code, not a UI path. The cohort stage for the flag and a variant-EPERM signal are deferred to #10604.
6. **Abort criteria:** any non-AF_UNIX command failing, or any tenant report, means roll back first and diagnose after.
7. **The enable sequence:** (a) run `soleur:flag-list` first (it shows code wiring and the live Doppler dev/prd values with drift
   detection; the Doppler mirror `FLAG_AGENT_SANDBOX_UNIX_DENY` is not verified by this runbook). (b) Create the Flagsmith feature with the
   create skill's `--flagsmith-only` mode, which is operator-typed: the flag is already code-wired (`RUNTIME_FLAGS` in `lib/feature-flags/server.ts`
   and `FLAG_AGENT_SANDBOX_UNIX_DENY=0` in `apps/web-platform/.env.example`), and a plain create stops at its "already appears in server.ts" exit-1
   precheck. The `soleur:flag-create` skill states: "`--flagsmith-only` creates **only** the Flagsmith feature for a flag that is
   **already code-wired** ... It skips the server.ts / `.env.example` / Doppler mutations **and** the 'already appears in server.ts' exit-1
   precheck". Its `<ARGS>` are `agent-sandbox-unix-deny --flagsmith-only` (default OFF: no `--dev-on`, no `--prd-on`); the agent first runs the
   same with `--dry-run`, then prints the typed-`yes` write command for the operator (exit 64 in an agent shell is by design, ADR-249).
   (c) Flip dry-run, agent-runnable: `soleur:flag-set-role agent-sandbox-unix-deny prd on --dry-run`. (d) Flip `prd` ON, operator-typed.
   (e) Verify with `soleur:flag-list` and the post-flip smoke in item 5.
8. **The dev-segment trap.** The anonymous identity resolves to the `prd` segment (`ANON_IDENTITY.role = "prd"` in
   `lib/feature-flags/server.ts`), so a dev-only flip is a no-op for this flag, and every flag write touches BOTH Flagsmith environments
   (dev and prd) whichever role it names. Nobody should treat `dev on` as a canary: it changes nothing a tenant or a test session sees.
9. **Two rollout facts the tenant-facing answer depends on.** (a) The ambient `SOLEUR_BWRAP_SECCOMP_BPF` incident override loses to the flag for
   no-egress sessions (the selector is assigned after the allowlist copy in `buildAgentEnv`), so to use that override flip the flag OFF first.
   (b) Variant assignment can differ per conversation, because egress is derived from best-effort handles: a GitHub installation-token mint
   failure is non-fatal (`cc-dispatcher.ts`, `op=mint-gh-token`) and a web-egress forwarder spawn failure proceeds zero-egress, so an
   entitled tenant can get the AF_UNIX-deny artifact for one conversation and working AF_UNIX in the next. The `seccompArtifact: base|unixdeny`
   field (the artifact the session's sandbox config is PAIRED with at build time; a spawn-time correction toward base or an ambient override
   is applied later) appears in exactly two places: (1) the host-local per-dispatch `tenant-deny` info log line (`feature=agent-sandbox`,
   `op=tenant-deny`), which needs host log access and is not queryable in Better Stack or Sentry (the log pipeline keeps level 40 and above);
   and (2) the `extra` of the classified `bash-tool-result` mirror event (Sentry and Better Stack), which exists only when a classified
   `apply-seccomp:` / `bwrap:` denial line was mirrored. A plain socket EPERM is NOT classified, so no event is emitted for the failure this
   flag causes: tie a user report to the flag-flip time and the session's egress state, not to a log field.

**Release-notes line (dated, for the release that turns the flag ON).** `2026-10-19 - Sandbox: shell commands in projects without outbound
network access can no longer open Unix-domain sockets (for example a local Postgres or Redis socket path, Node or other
runtimes' local IPC listeners, ssh-agent or SSH ControlMaster; and, if you install them in your workspace, Python multiprocessing
Manager, Pool or ProcessPoolExecutor on Python 3.14 and later where the default start method is forkserver, gpg-agent for
signed git commits, tmux or screen). Pipes, socketpair and normal networking checks are unchanged;
sessions with GitHub or web access are not affected.` (GitHub
release bodies are generated from the merged PR text and the in-app Releases page sanitizes security wording, so the line is carried in the
PR body, which is the release-notes source of record; there is no committed changelog file.)

**Support runbook line.** A user report of `Operation not permitted` from a Unix-socket workload (`psycopg2` to a local socket,
`redis-cli -s`, a Node or other local IPC listener, `ssh-agent` or SSH ControlMaster (`openssh-client` is in the image); and, only when the tenant
installs them into their workspace, `multiprocessing.Manager()`, `multiprocessing.Pool` or `ProcessPoolExecutor` on Python 3.14 and later (the default
forkserver start method talks over a Unix socket), `git commit -S` through `gpg-agent`, `tmux` or `screen`, a D-Bus
client) in a session with no GitHub token and no web access, dated after the flag was
turned on, is this change, not a bug: tell the user the workload needs a TCP address on loopback (works inside the per-command network
namespace) or a session with outbound access; engineering confirms with `soleur:flag-list` (flag `agent-sandbox-unix-deny` ON) and by the
absence of `apply-seccomp:` helper rows for that user (those are a different failure). To roll back for everyone, set the flag OFF (`soleur:flag-set-role
agent-sandbox-unix-deny prd off`, operator-authorized). The flip reaches new queries after up to about 60 s (30 s resolver memo plus the 30 s flag cache) with a healthy Flagsmith (see the State paragraph for the Doppler-mirror and restart conditions of a complete rollback); an active cc-soleur-go conversation keeps the artifact it started with until the idle reaper closes it (10 to 15 minutes after its last activity) or the container restarts, and a conversation in active use never idles, so the support answer is "fixed for NEW conversations: ask the user to start a new conversation; an open one may stay affected". After the flip, confirm with a real hosted Bash call from a NEW conversation; an open session never exercises the new posture. A plain socket EPERM is not classified or mirrored, so the `seccompArtifact: base|unixdeny` field cannot confirm a user report (see item 9 above for where it does appear); tie the report to the flag-flip time and the session's egress state. **Incident-time seccomp override:** with the flag ON, an ambient `SOLEUR_BWRAP_SECCOMP_BPF` is ignored for no-egress sessions (the selector is set after the allowlist copy), so flip the flag OFF FIRST, then apply the override; an override equal to the unixdeny path on an egress session is reset to the base artifact with a Sentry warning (`op=seccomp-agreement`).

**Reading the probes.** Boot: `op=sandbox-hardening-selfprobe` now carries `unixdenyFilter` beside `filter`; an `ok: false` with
`unixdenyFilter: false` means the image lacks the variant artifact (flag must stay OFF). Deploy: the three hardening reasons above.

## Runtime Bash synthetic (#10455 b, ADR-079 addendum 2026-10-22)

One real wrapped Bash call, every 15 minutes, in the RUNNING web container on each web host; a per-host Better Stack heartbeat
(`soleur-web-bash-synthetic-<host>`, period 900 s, grace 1800 s) is pinged only on a verified pass. It exists because the deploy smoke above sees
only a sandbox that is broken AT deploy (#10445 lasted ten days between deploys).

**Read it without SSH.**

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep web-bash-synthetic
```

Expected on a healthy host: `SOLEUR_WEB_BASH_SYNTHETIC verdict=pass reason=ok … consecutive_no_ping=0`, one row per run per host
(`host_name` tells web-1 from web-2). The heartbeat itself is in Better Stack Uptime, which pages by email when it goes missing.

| Signal | Meaning | What to do |
|---|---|---|
| heartbeat missing, journal rows under `web-bash-synthetic` but NONE carrying a `SOLEUR_WEB_BASH_SYNTHETIC` marker | the unit starts and dies BEFORE the script's first journal line: a Doppler/token failure (`doppler run`'s stderr ships under the tag, systemd's `Failed with result` row ships from the `systemd` identifier), a missing or unreadable `/etc/default/web-bash-synthetic`, or the xtrace refusal (exit 78) | read the stderr rows for the cause; fix the Doppler secret or the env file (a web-1 token rotation re-fires the installer; web-2's derived file only changes on a host replacement) |
| heartbeat missing, no journal rows at all | the DETECTOR is dead: timer stopped, host dark, or Vector broken | check host health first (web uptime monitors and the host's own Vector rows). A STOPPED timer is not restarted by re-running apply (the installer's `triggers_replace` hashes the four delivered files plus, on web-1, the token): a merge that changes any of `web-bash-synthetic.{sh,service,timer}` or `sdk-bash-verdict.sh` re-fires `systemctl enable --now` on both hosts, and so does a `-replace` rotation of the probe token on web-1. Only if neither is possible is host access the last resort |
| `/fail` incident, `verdict=fail` | Bash was dispatched and no verified nonce came back: the #10445 shape. `detail=` carries the probe's reason | treat as a sandbox outage; compare with the `agent_sandbox_bash_denial` alert and the deploy smoke ledger |
| `verdict=no_ping reason=deploy_lock` | a deploy holds the lock; normal for the length of a deploy | none unless `consecutive_no_ping` keeps climbing |
| `reason=container_down` (`detail=container not found` or `container not running`) / `container_restarted` | no container, or it was replaced or stopped during the run (a deploy swap) | none for one run; persistent means the web container is down. A dark docker DAEMON is NOT this row: it journals `infra_error detail=docker_inspect_rc_1: …` |
| `reason=memory_pressure` | the container's memory is at or above 70 % of its cap (sampled at the start and again right before the probe exec; the detail names the stage); the run did not exec into it. The probe tree adds 172-293 MB of cgroup memory, see the ADR addendum | investigate the container memory, not the synthetic |
| `reason=memory_pressure_host` | the HOST's `MemAvailable` is below 700 MB (on a 4 GB web host the container cap is the whole host); same two sample points; the run did not exec | investigate host memory, not the synthetic |
| `reason=selector_unresolved` (journal `selector=unresolved`) | the dispatcher's flag read did not answer within the resolver's 3 s budget (Flagsmith slow or down, or the read fell back to the env mirror), so the host refuses to guess which artifact to test. `infra_error detail=selector_unresolved: no single sentinel line` is a different case: the resolver's output itself was malformed | none for one run; persistent means the flag service or the container's Flagsmith env is broken, and the beat goes dark after about 45 minutes. The fallback is visible here, never a silent `selector=base` |
| `reason=selector_mismatch` | the probe reported a different `selector` than the host asked for (a stale probe in the image, or the selector env not reaching it) | treat as an image/probe skew: redeploy the web image that carries the current probe |
| `reason=verdict_lib_absent` | `sdk-bash-verdict.sh` is not on the host (the SSH install block that delivers it has not run since the lib was added), so the host cannot map the probe result and claims nothing. | Re-run the web-host install via an infra apply; the same blindness applies to the deploy smoke until then (ADR-079 addendum, known limitation; #10777). |
| probe `infra` reason `cli_tmp_path_too_long` | the probe's scratch config dir path exceeds the SDK CLI's 44-byte temp-path limit, so the probe refused to run rather than fall back to the shared `/tmp/claude-<uid>`. | Check the container's `TMPDIR`/`/tmp` mount: the scratch base must be short (`/tmp`). |
| `reason=probe_absent` | the running image predates the probe or the resolver bundle (this reason now comes only from the pre-exec presence check) | expected on the first merge until the new image is deployed |
| `verdict=fail`, `detail=host_timeout_<N>s` | Bash hung after dispatch; N is the cap that fired (150 only when the host cap fired, else the in-container 130) | treat as a sandbox outage |
| `reason=host_timeout_before_dispatch` | docker stalled or node did not start before Bash was handed to the SDK | a daemon-level problem, not a Bash result |
| `reason=infra_error`, `detail=probe_killed_rc_137` / `_143`, or `cli_child_killed: …` from the probe | the probe exec was killed after dispatch (the kernel OOM killer, a container stop, a deploy signal); this is not a Bash result, so it does not page `/fail` | with `memory_pressure*` rows around it, treat as memory; alone, look for a deploy or container restart at that minute |
| `reason=infra_error`, `detail=…` | everything else that is not a claim: docker error, bad selector output, unreadable lock table, replay-only coverage | read `detail=` |
| `reason=no_heartbeat_url` | the per-host URL secret or key name is missing or malformed (a `SOLEUR_CREDENTIAL_REFUSED script=web-bash-synthetic` row says which). The key name must be `WEB_BASH_SYNTHETIC_URL_<HOST>`, and the URL is pinned to `https://uptime.betterstack.com/api/v1/heartbeat/<token>` with no query: if Better Stack ever changes its heartbeat host this unit goes dark until the pin in `web-bash-synthetic.sh` is updated | fix the Doppler secret or the env file |
| `[wbs] WARN: heartbeat ping FAILED (ok\|fail, url_present=yes)` next to `verdict=pass` or `verdict=fail` | the verdict is good but BOTH curl attempts to Better Stack failed (egress, a revoked or 404 heartbeat URL, Better Stack down). The beat will go dark in about 45 minutes even though the sandbox is healthy, and a real `/fail` would not have reached anyone | check Better Stack reachability and that the heartbeat still exists (`arm-heartbeats.sh --status soleur-web-bash-synthetic-<host>`); do not read the missing beat as a sandbox outage while this row is present |

`consecutive_no_ping=<n>` in the journal separates a long deploy lock from a dead host: the beat goes dark after about 45 minutes either way,
and the journal tells which. `selector=` is the artifact the dispatcher's resolver chose (`base` until the `agent-sandbox-unix-deny` flag is on);
`masks_missing=<n>` counts masked dirs that did not exist in the production container (informational, they belong to real sessions); a `pass` with
`masks_missing>0` journals `coverage=prodtuple_partial` because it tested a weaker config than production.

**Arming.** The beats are born paused. `arm-heartbeats.sh` unpauses each host's beat after a measured ping with a 300 s window and a soft landing.
Arming is PROBABILISTIC: the cadence is 900 s against a 300 s window, so a healthy synthetic lands a beat inside one apply's window with p ~ 1/3 per
host, and an unlanded beat is a `::warning::` that is not a fault on its own. The journal separates the cases: `reason=probe_absent` means the image
carrying the probe's resolver is not running yet; `verdict=pass` means the synthetic is healthy and the window was missed. A beat that stays paused is
watched by the twice-daily `heartbeat-live-reconcile` job (its `fed-but-paused` class) and by `arm-heartbeats.sh --status`; no post-merge check does.
Manual arming: `arm-heartbeats.sh --status soleur-web-bash-synthetic-<host>` for the id, then `--arm-one soleur-web-bash-synthetic-<host> --id <id>`.

## Outer-wrap canary - RETIRED 2026-10-19 (#10454)

The deploy-time outer-wrap arm (`run_outer_wrap_canary`, deploy-state key `outer_wrap_canary`, ledger
`/mnt/data/ci-deploy-outer-wrap-canary.json`, Sentry `op=sandbox-canary-outer-wrap`, soak script
`tenant-outer-wrap-soak-5863.sh`, promotion tracker #9797) is retired. Ruled by CTO agent, 2026-10-19: DEMOTE
(ADR-079 addendum 2026-10-19). Do not look for an `outer_wrap_canary` key on `/hooks/deploy-status` any more. The ledger file
`/mnt/data/ci-deploy-outer-wrap-canary.json` remains on every host, inert (nothing reads or writes it any more): a re-introduction of the
arm must use a NEW ledger name or delete that file first, otherwise it would inherit the old `consecutive_pass` and `first_pass_at`.

**Why.** Its pass condition requires `elevation=privileged` (a file-cap'd `/usr/bin/bwrap` plus
`--cap-add SYS_ADMIN`). ADR-075's 2026-10-09 addendum (#9874, operator-ratified) dropped that elevation on purpose,
and `AGENT_OUTER_WRAP` is flag-off in production, so the arm reported `wrong_elevation_userns` on every deploy by
design. A permanently red report-only signal teaches people to ignore report-only signals, and its first move
("check `getcap` / `--cap-add SYS_ADMIN`") pointed away from the intended posture. Accepting `elevation=userns` was
rejected: it would turn the canary green on the mechanism its own code comment calls wrong.

**What stays, and who consumes it.**

| Kept piece | Live consumer |
|---|---|
| `sandbox-canary.mjs --replay-outer` and `classifyOuterWrapReplayVerdict` | test-only (re-introduction path, #9773): `test/sandbox-canary.test.ts` (fixture validation, `{{ROOT}}` substitution, verdict classifier); no production caller remains; the masked-proc docker suite deliberately does NOT run it (its header says so) |
| `infra/agent-outer-wrap-argv.json` fixture and its Dockerfile/`.dockerignore` bakes | Read by `test/agent-outer-wrap.test.ts` and `test/c4-render-argv-fixture.test.ts`, by `scripts/sandbox-canary.mjs` (the default fixture path of `--replay-outer` / `--smoke-outer`) and by the `sandbox-canary-soak.test.sh` fixture checks. `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` only NAMES the file (in its trigger regex and its error text); it does not read it |
| `scripts/tenant-isolation-inner-probe.sh` shared payload | `agent-outer-wrap.ts` (opt-in boot self-probe), `test/agent-outer-wrap.test.ts`, and `sandbox-canary.mjs --replay-outer` (`test/sandbox-canary.test.ts`) |
| `agent-outer-wrap.ts` | the `AGENT_OUTER_WRAP` flag path (off in production) |
| `sandbox-canary.mjs --smoke-outer` | `sandbox-canary-verify-in-image.sh`, the CI capture-gate job that guards the fixture |

**Property no longer measured at deploy.** The outer-wrap realized mount table (own workspace visible, sibling
workspaces absent inside the wrap) is no longer replayed per deploy. Cross-workspace read/write isolation is still
measured by `run_workspace_isolation_probe` (`test/sandbox-isolation.test.ts`, direct tier) in the canary; the
outer-wrap table itself is covered only by the static pins (`test/agent-outer-wrap.test.ts`, `test/c4-render-argv-fixture.test.ts`) until the arm returns.
That is acceptable because `AGENT_OUTER_WRAP` is flag-off in production.

**Re-evaluate or delete.** On 2026-12-19, or when #9773 Stage 1 (the executor topology) ships, whichever comes first:
either bring the arm back with a pass criterion defined by that topology (re-add a `run_canary_replay "--replay-outer"`
call with its own ledger, deploy-state key and soak script, and a new ADR addendum), or delete the kept pieces above.

The PIR keeps its historical sentence about the standing red rows untouched.

## Cross-workspace isolation canary — report-only soak (#2640)

A third probe shares the word "sandbox" with the two above and is distinct from both:
`run_workspace_isolation_probe` in `ci-deploy.sh` runs the **direct tier** of
`test/sandbox-isolation.test.ts` (cross-workspace read/write isolation with sibling trees — the
property the faithful canary's single captured argv cannot exercise) inside the canary container:

```text
timeout <cap> docker exec -w /app soleur-web-platform-canary \
  /usr/bin/env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp \
  CI=true SOLEUR_ISOLATION_TEST_HOST=1 SOLEUR_ISOLATION_TIERS=direct SOLEUR_ISOLATION_IN_IMAGE=1 \
  /usr/local/bin/vitest run --config test/vitest.canary.config.ts
```

(`SOLEUR_ISOLATION_IN_IMAGE=1` self-skips FR7b — in-image PATH `bwrap` is the
deployed shim and its control arm needs the real binary; see the design note.)

It is called `|| true` after `run_faithful_sandbox_canary` inside the `CANARY_HEALTHY`
block — **report-only** (dark-launch per `wg-dark-launch-deploy-gates`): it logs, writes state and
pages Sentry on a red verdict, but a failing verdict never rolls back the deploy. Promotion to
blocking is a tracked follow-up (see the design note,
`knowledge-base/engineering/operations/runbooks/workspace-isolation-canary-probe.md`).

**Verdict classes** (docker-exec rc classification mirrors `run_faithful_sandbox_canary`):

| Verdict | rc | Meaning | Sentry | First move |
|---|---|---|---|---|
| `pass` | 0 | direct-tier suite green in the canary | no | — |
| `workspace_isolation_failed` | other non-zero | suite reported a real isolation failure (or a vacuous green — `reason=vacuous_green_no_tests_passed`) | **page** | `reason` carries vitest's first `FAIL <file> > <test>`/`AssertionError` line (or docker's first stderr line as fallback) — read it on `/hooks/deploy-status` `.workspace_isolation.reason` or the `WORKSPACE_ISOLATION_FAIL:` journald line; reproduce locally with `SOLEUR_ISOLATION_TIERS=direct npx vitest run test/sandbox-isolation.test.ts` (host-side: FR7b runs there — it is skipped in-image) |
| `workspace_isolation_timeout` | 124 | host-side `timeout` fired (suite hung, e.g. bwrap deadlock) | **page** | the in-container vitest may outlive the killed `docker exec` until the canary is stopped; check `WORKSPACE_ISOLATION:` reason for the timeout's stderr tail |
| `canary_infra_error` | 125/126/127 | could not exec (pre-tooling image, missing vitest) | no — state only | expected during the dark-launch window; a *persistent* stream means the image lacks the probe payload (Dockerfile `COPY`/`npm -g vitest` drift) — soak holds, nothing pages by design |

The verdict + reason alone must suffice for triage — the probe's `docker exec`
runs with `env -i` (no prod env inside the suite), so `reason` is safe to quote
verbatim in incident notes.

**State and surfaces.** `write_workspace_isolation_state` persists the verdict to
`/mnt/data/ci-deploy-workspace-isolation.json` (atomic, always returns 0) and accumulates the soak
fields `consecutive_pass` (increments on `pass`, resets on `workspace_isolation_failed` /
`workspace_isolation_timeout`, **holds** on `canary_infra_error`) and `first_pass_at` — the same
accumulation `write_sandbox_canary_state` performs, so the promotion probe is a stateless GET.
`cat-deploy-state.sh` merges the file into the `/hooks/deploy-status` payload as
`.workspace_isolation`, and every run logs a `WORKSPACE_ISOLATION:` line under `logger -t ci-deploy`
(the Better Stack query shape in the bwrap-probe section applies verbatim — grep on the decoded
`message` after `fromjson`, filter `SYSLOG_IDENTIFIER == "ci-deploy"`).

**Promotion contract.** The committed soak checker
`scripts/followthroughs/workspace-isolation-verdict-2640.sh` reads `.workspace_isolation` off
`/hooks/deploy-status` and reports PASS only when `consecutive_pass >= 5` AND the span since
`first_pass_at` is >= 3 days; a recorded `workspace_isolation_failed` or
`workspace_isolation_timeout` verdict is a FAIL (investigate before promoting — do not flip the
call site to blocking while either stands).

## References

- AGENTS.md `wg-when-fixing-a-workflow-gates-detection`
- `plugins/soleur/skills/preflight/SKILL.md` Check 7
- `plugins/soleur/skills/preflight/SKILL.md` Check 5 Step 5.4 (Layer 3 source)
- PR #3014 — incident remediation
