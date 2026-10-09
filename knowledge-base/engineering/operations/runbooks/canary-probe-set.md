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

## Canary sandbox DIAG bundle — why a sandbox canary failed (#9871, #9860)

`DEPLOY_ROLLBACK: bwrap sandbox non-functional ...` says THAT the blocking probe failed and keeps 200
characters of stderr. When the probe fails, or the faithful canary (`op=sandbox-canary`) reports
`sandbox_broken`, `ci-deploy.sh` also runs ONE bounded, read-only bundle inside the still-running canary
and emits it under the same `ci-deploy` journald tag, so it reaches Better Stack with no SSH. The two
triggers are mutually exclusive in one run (a legacy failure exits before the faithful canary runs), so a
deploy carries at most one bundle:

```text
SOLEUR_CANARY_SANDBOX_DIAG: image=<image>:<tag> trigger=<legacy|faithful> section=<name> val="<text|<empty>>"
```

`val` is last and quote-bounded; cut each line at the FIRST `section=` and read the rest as free text. It is
credential-scrubbed (`_cred_err_tail`, which keeps the LAST 200 characters, so every row is short on
purpose) and cannot change the deploy's exit code, state reason or teardown. Query:

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_CANARY_SANDBOX_DIAG \
  | jq -r '.raw | fromjson? | select(.SYSLOG_IDENTIFIER=="ci-deploy") | .message'
```

A complete bundle is fourteen rows: ten in-container sections, then `host`, `hostsec`, `kernel` and `done`.

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
| `sdk_probe` | the SDK's split-unshare argv (`--unshare-user --unshare-pid --proc /proc`) against `/usr/bin/bwrap` directly | the #9860 shape: `Can't mount proc on /newroot/proc: Operation not permitted` here with `direct_version rc=0` = namespace/mount creation denied (kernel/LSM posture). This argv is known to fail in the canary under `docker exec`, so the first stderr line decides, not the rc alone |
| `kernel_ns` | userns sysctls as the container sees them | `restrict=1` or `max=0` = host userns policy |
| `host` | the canary's `HostConfig`: `capadd`, `capdrop`, `priv`, `aa` (AppArmor profile) | a `SYS_ADMIN` cap-add or `priv=true` is a host-script defect |
| `hostsec` | the `SecurityOpt` entries, each cut to 40 characters | expect `apparmor=soleur-bwrap` and a `seccomp={...` entry. docker inlines the whole seccomp profile here, so it is cut; a missing `seccomp=` entry means the profile was not applied |
| `kernel` | host kernel and docker server version | version drift context |
| `done` | `exec_rc=<n> lines=<n> capped=<0\|1>` | `exec_rc=0 lines=10 capped=0` = the bundle completed. `exec_rc=124` = the exec timed out and the LAST sections are missing (they are the probes); any other non-zero = `docker exec` itself failed |

### Which hypothesis holds (H1-H5, from the plan)

| H | Hypothesis | Rows that decide it |
|---|---|---|
| H1 | The image still has `cap_sys_admin+ep` on `/usr/bin/bwrap` (stale or mis-built), and the bounding set lacks SYS_ADMIN, so execve is EPERM | `caps` has a `cap_` token; `prov` BUILD_SHA is the pre-fix commit (48d5144cf4), not the tag's; `direct_version rc=126` |
| H2 | Exec is denied by LSM (AppArmor) or seccomp, independent of file caps | `caps=none` AND `direct_version rc=126`, with `proc` `Seccomp=2` and `lsm` naming the profile |
| H3 | Exec works; namespace/mount creation is denied (the `Can't mount proc` shape, #9860) | `direct_version rc=0` AND `sdk_probe` (or `direct_probe` under `trigger=legacy`) failing with a namespace/mount error; `kernel_ns` / `kernel` show the userns policy |
| H4 | The shim, not bwrap, is the culprit | `direct_probe rc=0` while the shimmed probe failed (`trigger=legacy` only) |
| H5 | Container posture drift | `host` (`capadd`/`capdrop`/`priv`/`aa`) and `hostsec` differ from the `docker run` in `ci-deploy.sh` |

H1 is excluded only when `caps` is `bwrap=none`; `done` must read `exec_rc=0` first, or the rows that decide H2-H4 may be missing.

**Zero DIAG rows after a `DEPLOY_ROLLBACK` line** is NOT yet a finding: the host may still run the previous
`ci-deploy.sh` (it is delivered by `apply-deploy-pipeline-fix`, whose run can be evicted by a pending
`apply-web-platform-infra` run in the shared concurrency group, #8167). Check parity first:
`bash scripts/check-deploy-script-parity.sh` (both arms: `/hooks/deploy-status` `ci_deploy_sha256` for web-1
and the newest `DEPLOY_SCRIPT_SHA` row per host). Drift means a re-dispatch of `apply-deploy-pipeline-fix`, which needs explicit operator
authorization; parity with no DIAG rows means the bundle itself failed (look for a lone `section=raw` row or a
`done` row with a non-zero `exec_rc`).

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

## Outer-wrap canary — #5863 arm-F verdicts

`outer_wrap_canary.verdict` in deploy-state (Sentry `op=sandbox-canary-outer-wrap`) covers the
tenant filesystem isolation arm — the mountns-only outer bwrap built from
`infra/agent-outer-wrap-argv.json` inside the canary container (file-cap'd `/usr/bin/bwrap` +
`--cap-add SYS_ADMIN` on the docker run). Report-only during dark launch; the soak lives in
`/mnt/data/ci-deploy-outer-wrap-canary.json` and promotion is tracked by #9797.
`canary_infra_error` rows hold the soak; `sandbox_broken` resets + pages.

| `reason` | Meaning | First move |
|---|---|---|
| `isolation_probe_failed` | The shared payload saw the synthetic sibling or another `FAIL:` inside the realized wrap — the mount table LEAKS | The table is unsound — do not promote; diff `buildOuterWrapArgv` against the fixture; rerun `bash apps/web-platform/scripts/agent-outer-wrap-debug.sh <ws>` locally |
| `wrong_elevation_userns` | `isolation_ok` but `elevation=userns` — bwrap took the implicit-userns fallback, NOT the file-cap'd mountns the arm requires (fatal to the inner sandbox, Phase 0) | Check `getcap /usr/bin/bwrap` in the image + `--cap-add SYS_ADMIN` on the docker run; the Dockerfile's end-stage audit should have caught a missing cap |
| `wrong_elevation_unreported` | `isolation_ok` but no `elevation=` marker — a drifted payload cannot green | `scripts/tenant-isolation-inner-probe.sh` must print `elevation=<privileged\|userns>` before the verdict line |
| `bwrap_operation_not_permitted` | bwrap could not build the mountns (EPERM on mount/userns) — file-cap posture regressed or the seccomp/AppArmor profile denies it | Check the loaded seccomp profile (`seccomp_profile_loaded_matches_host` on deploy-state) and AppArmor `soleur-bwrap` |
| `bwrap_shim_refused` | The #8752 PATH shim rejected the replay (should never run — the replay pins `/usr/bin/bwrap`) | A PATH-resolved `bwrap` leaked into the replay path — check `sandbox-canary.mjs` for a non-absolute spawn |
| `isolation_probe_failed` on `ptrace_scope` | `/proc/sys/kernel/yama/ptrace_scope` was 0 — shared `/proc` becomes a full mountns oracle for sibling sessions | Re-pin `kernel.yama.ptrace_scope=1` on the host (the #9723 residual only holds while yama restricts ptrace) |
| `probe_output_missing` | The payload ran but printed no verdict — an empty/truncated payload file | Confirm `COPY --from=builder /app/scripts/tenant-isolation-inner-probe.sh` + the `.dockerignore` re-include |
| `bwrap_spawn_enoent` / `bwrap_spawn_*` / `bwrap_exit_*` / `docker_exec_rc_*` | Infra flake, never sandbox signal — the soak holds | Transient; if persistent check `sandbox-canary.mjs` is baked in the image |
| `fixture_missing` / `fixture_invalid` | `infra/agent-outer-wrap-argv.json` absent or schema-rejected (incl. `{{ROOT}}`-confinement violations on prep entries) | Regenerate via `test/agent-outer-wrap.test.ts` Guard 2; schema is `outer-bwrap-v1` |

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

It is called `|| true` after `run_faithful_sandbox_canary` and `run_outer_wrap_canary` inside the `CANARY_HEALTHY`
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
