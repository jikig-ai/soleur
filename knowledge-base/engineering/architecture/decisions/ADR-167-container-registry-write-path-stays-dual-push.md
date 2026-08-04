# ADR-167: The container-registry write path stays dual-push — GHCR is CI's backfill source, not a demotable archive

- **Status:** Proposed
- **Date:** 2026-08-04
- **Issues:** [#7247](https://github.com/jikig-ai/soleur/issues/7247) (OPEN, the measured blocker) · [#7248](https://github.com/jikig-ai/soleur/issues/7248) (OPEN, related, not a dependency)
- **Amends:** [ADR-096](./ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md) — scopes the 2026-07-30 amendment's read claim to hosts; its conclusion is unchanged
- **Clarifies:** [ADR-088](./ADR-088-control-plane-installation-token-minter-for-private-ghcr-reads.md) — arm-b's finding stands; its **scope** is stated explicitly
- **Applies:** [ADR-166](./ADR-166-a-ci-message-may-only-name-a-cause-the-job-measured.md) — to a *remedy* rather than to a message
- **Lineage:** [ADR-062](./ADR-062-container-memory-cap-and-restart-attribution.md) · [ADR-135](./ADR-135-pull-based-signed-config-refresh-for-dedicated-inngest-host.md)

## Status

**Proposed.** Not accepted: CPO sign-off (required at the declared `single-user incident`
threshold) has not been given, and adversarial review returned findings that narrow this ADR's
scope — see `## Scope: this is a hold, not a permanent topology decision`.

### Scope: this is a hold, not a permanent topology decision

A review panel's central objection is upheld: the evidence below supports **"do not re-route the
write path while zot is crash-looping"** — a *sequencing* claim with a lifetime of days — and an
earlier draft of this ADR overstated it into a permanent topology decision. It is restated as a
**conditional hold**:

> The dual-push topology stands **while #7247 is open**. Within **14 days of zot reaching a
> verified restart plateau**, the zot-first question is re-opened and decided against
> steady-state evidence, not against outage-window evidence.

The distinction matters because every failure row below was drawn from a window in which one leg
was pinned near-zero availability. That tells you which leg failed *during the outage*; it does
not settle each leg's steady-state contribution. Reading it as the latter is survivorship
reasoning, and this ADR no longer does.

## Context

On 2026-08-04 a proposal was raised to make CI push directly to zot and demote GHCR to a
best-effort archive whose failure would warn rather than block. The proposal rested on four
premises. Each was re-measured before this decision was taken; **three did not survive.**

### P1 — "Run 30913993850 failed at *Build and push Docker image* with a GHCR 403; the zot mirror step never ran." — **partially false**

The run is `run_attempt: 2`. On the re-run (completed 13:54:56Z) the **GHCR push succeeded** —
`cosign` pushed the signature to `ghcr.io/jikig-ai/soleur-***@sha256:4cc17eba…` at 13:52:04Z —
and the job died at **"Mirror image GHCR→zot (crane) + cosign-sign the zot digest."** The
mirror step ran three times and failed three times.

### P2 — "The 403's root cause is unknown." — **false; it is measured**

The quoted error was truncated immediately before the body that names the cause. The full
response (attempt 1, `21_Build and push Docker image.txt:802`):

```
denied: permission_denied: Error from intermediary with HTTP status code 403 "Forbidden" - with-body: {
  "documentation_url": "https://docs.github.com/free-pro-team@latest/rest/overview/rate-limits-for-the-rest-api#about-secondary-rate-limits",
  "message": "You have exceeded a secondary rate limit. Please wait a few minutes before you try again."
}
```

The cause is a **GitHub secondary rate limit**. It is transient by construction, the response
prescribes its own remedy, and the re-run confirmed it. GHCR returns `denied: permission_denied`
as its generic wrapper for a rate-limited push; the `Error from intermediary` prefix marks it as
an edge response, not a permission evaluation. The "authenticate-but-not-authorize" reading is
not supported.

> This is worth naming precisely because it is the ADR-166 failure mode occurring *inside the
> proposal to fix it*: a cause was asserted from a truncated message, and a topology change was
> proposed on top of it. ADR-166 governs what CI may *say*; this ADR extends the same discipline
> to what we may *do* — a remedy may only address a cause someone measured.

### P3 — "GHCR serves zero reads and is not a refill source." — **false**

GHCR serves reads — but the two candidates are **not** equally live, and an earlier draft of this
ADR asserted both flatly. Corrected:

1. **CI's own backfill read.** The release job's `crane copy ghcr.io/… → 127.0.0.1:5000` is an
   authenticated GHCR *read*, visible in the run log as
   `Copying from ghcr.io/jikig-ai/soleur-***:v0.249.5 to 127.0.0.1:5000/…` followed by
   `existing blob:` lines. This is also the recovery `reusable-release.yml`'s own `degraded()`
   prescribes: *"backfill via `crane copy GHCR→zot && cosign sign --yes <zot>@<digest>`, then
   re-run."*
   **Weight this read carefully — an earlier draft over-claimed it.** Review established two
   limits: (a) it is *partly circular* as evidence — the mirror step reads GHCR only because the
   same job pushed there seconds earlier, so under a zot-first topology the read is not *lost*,
   it is *unnecessary*; and (b) every `crane copy GHCR→zot` outside the release job is a **prose
   string an operator pastes** (`reusable-release.yml:1025, 1277, 1340`), not an automated
   consumer. Under `hr-never-label-any-step-as-manual-without`, "keep a second registry on the
   release critical path so a human has something to paste" is weak on its own.
   What survives: GHCR is the only place a **completed, signed** image exists when the mirror
   fails. That is a real recovery property. Whether it is the *cheapest* way to hold one is the
   open question this ADR now defers rather than settles — see §Alternatives.
2. **The ADR-135 config-refresh bundle** is GHCR-authoritative with a **GHCR-direct host pull**
   and a `continue-on-error` zot mirror — the inverse of the app-image topology.
   `build-inngest-config-bundle.yml:151` states it plainly: *"GHCR is authoritative for the v1
   GHCR-direct host pull (D-ZOT); the zot copy is a dark-safe convenience, so this step is
   continue-on-error."*
   **But this read is NOT live.** `model.c4:515` marks the `inngest -> ghcr` edge
   **`ADOPTING` (rides #6178 cutover, PR #6348)**. It is evidence that the inverse topology is a
   *sanctioned pattern in this repo*, and nothing more. It is a different OCI repo and a
   different artifact, and it must not be counted as a live consumer of the app-image path.
   *(Also: `model.c4` cites this channel as "ADR-136" in four places; ADR-136 is the pre-apply
   entrypoint-enumeration gate. The correct ordinal is **ADR-135**, corrected alongside this
   decision.)*

The reconciling distinction, which the record did not previously state: **hosts cannot read
GHCR; CI can.** ADR-088 arm-b is a finding about *host-side zero-touch* credentials. In-job,
`GITHUB_TOKEN` under `permissions.packages: write` (`reusable-release.yml:119`) reads the
repository's own packages — which is why the crane copy works at all.

### P4 — "GHCR can block 100% of releases." — **true in principle; not what happened**

| Run | Time (UTC) | GHCR push | zot mirror |
|---|---|---|---|
| 30900564194 | 10:25 | ✅ | ❌ |
| 30902554446 | 10:54 | ✅ | ❌ |
| 30913993850 att.1 | 13:28 | ❌ (rate limit) | skipped |
| 30913993850 att.2 | 13:43 | ✅ | ❌ |

Of the 12 most recent release runs, 8 failed. **Demoting GHCR would have prevented none of the
four failures above.** In every measured case zot failed; GHCR failed once, transiently.

### The measured blocker

L3→L7 verification (`hr-ssh-diagnosis-verify-firewall`): DNS healthy
(`registry.soleur.ai` → `188.114.96.2`/`.97.2`, Cloudflare anycast); edge and Cloudflare Access
healthy (`curl -sI` → `HTTP/2 403` with `cf-access-aud`, the correct response to an
unauthenticated probe — and CI's tokened `docker login 127.0.0.1:5000` **succeeded** at
13:52:16Z). The failure is the **origin dial**: cloudflared logged
`ERR failed to connect to origin error="websocket: bad handshake" originURL=https://registry.soleur.ai`
×4, same signature in run 30902554446.

Registry-host telemetry (`SOLEUR_ZOT_DISK`, self-pulled, 13:35–14:00Z) shows `zot_restarts`
climbing **4827 → 4938 = 111 restarts in 25.0 min ≈ 4.44/min** at a constant `boot_id` (the
container restarts; the host does not). This matches #7247.

**The restart cause is UNMEASURED and is not named here.** The telemetry positively *excludes*
OOM (`zot_oom_kills=0`, `oom_killed=false`, `exit_code=0`) and disk exhaustion (`pcent=54`,
`resize_ok=true`). Attribution is #7247's deliverable.

**#7248 observed live:** the same payload carries `ping_rc=0` and `state_status=running`
throughout — the read-path verdict graded GREEN while every push failed.

## Decision

**The container-registry write path stays dual-push: build → GHCR, then digest-preserving
`crane copy` GHCR → zot, with the zot leg release-blocking (ADR-096's 2026-07-30 amendment,
unchanged).**

1. **GHCR is not demoted.** It is retained for a load-bearing purpose the record did not
   previously state: it is the **staged copy from which zot is backfilled** when the mirror
   fails, and CI holds a working read credential for it. Demoting or removing the GHCR leg
   deletes the recovery path that the release workflow's own failure message prescribes.

2. **The "GHCR serves zero reads" claim is retired.** The dead read is **host-side**, not
   universal. `model.c4` and ADR-096's amendment are corrected accordingly.

3. **ADR-088 arm-b is not reopened.** Its finding stands verbatim. **No personal access token
   is reintroduced**; that credential class stays retired. What is added is a scope sentence:
   arm-b constrains host-side zero-touch credentials and says nothing about CI's in-job read.

4. **The only change made in response to the 403 is a bounded, *conditional* retry on the GHCR
   push**, gated on the secondary-rate-limit signature, with backoff sized to GitHub's own
   guidance ("wait a few minutes") rather than to the TCP-reset backoff used by the mirror step.
   A non-matching 403 continues to fail immediately. Each retry attempt emits a `::notice::`, so
   a rate-limited-but-recovered push becomes visible instead of silent.

5. **The actual blocker is not addressed here.** #7247 (why zot restarts) and #7248 (push-path
   health verdict) remain open and owned separately. This ADR does not close them and does not
   depend on them.

### Revisit trigger

**Mandatory (time-boxed):** re-open within **14 days of zot reaching a verified restart
plateau** (`scripts/followthroughs/zot-restart-plateau-6288.sh` returning `0`), and decide the
zot-first question against steady-state evidence. This fires regardless of the triggers below.

Additionally, re-open if **any** of the following is measured:

- **A GHCR push fails with a non-rate-limit signature.** *(Rewritten: an earlier draft said "the
  retry in (4) exhausts on a non-rate-limit signature," which is unsatisfiable by construction —
  a retry gated on the rate-limit signature never engages on a non-rate-limit failure, so it can
  never exhaust on one. The observable condition is the failure itself, not the retry's
  exhaustion.)*
- **Over any rolling 30-day window, releases blocked by the GHCR leg exceed those blocked by the
  zot leg.** ⚠️ **Not currently instrumented — this trigger is inert until it is.** The
  `::notice::` from (4) counts *recovered* attempts, not blocks; the zot leg emits
  `mirror_reason` but the GHCR leg emits no per-leg block label; and nothing aggregates a window.
  Making this measurable requires a per-leg `block_reason` output plus an aggregator. Until that
  ships, do not treat this trigger as live.
- **The `crane copy` GHCR→zot backfill stops working from CI**, which would remove the recovery
  property in (1). ⚠️ Also under-instrumented: `degraded()` emits `copy_v`/`copy_sha`/`copy_latest`
  per tag (`reusable-release.yml:1276-1277`), and those fire identically whether the **GHCR read**
  or the **zot write** failed. Splitting that label into read-side vs. write-side is a
  prerequisite for this trigger to mean anything.

The two ⚠️ triggers are recorded as **stated but inert**. An ADR whose expiry conditions cannot be
evaluated by anything it ships is a closed door with a comment on it — naming the gap is the
minimum honest treatment, and the mandatory time-box above is what actually guarantees a revisit.

## Consequences

**Positive**

- The recovery path (`crane copy GHCR→zot`) keeps a source. Under the rejected options it would
  have had none.
- The image is staged on a highly-available registry before it traverses a tunnel into a
  single self-hosted origin — failure of that origin leaves a complete, signed copy elsewhere.
- The measured failure class becomes both survivable (retry) and countable (`::notice::`).
- Three false statements are removed from the architecture record.

**Negative / accepted costs**

- GHCR remains able to block a release. This is accepted because the measured instance was
  transient and is now retried, and because the alternative removes the recovery source.
- Two registries remain in the write path — more surface, two credentials, a slower release.
  Accepted: the second registry is doing work (staging + backfill), not sitting idle.
- **Concentration risk is not reduced by this decision — and it was not going to be.** The
  tunnel and zot are already release-blocking by ADR-096's amendment. The proposal framed
  zot-primary as "stopping payment for a second point of failure that cannot help"; the
  measurement shows the second one *does* help (it holds the backfill source) and the *first*
  one is what is failing. Removing GHCR would concentrate risk onto the crash-looping component,
  not away from it.
- **The open deferral that would actually reduce it is [#6126](https://github.com/jikig-ai/soleur/issues/6126)**
  — *"zot registry HA + read-replicas (deferred from #6122)"*, OPEN at `priority/p3-low`. This
  ADR formally accepts a single point of failure whose named mitigation is sitting at the lowest
  priority tier. That juxtaposition should be uncomfortable, and it is recorded here rather than
  left implicit: **#6126's priority deserves re-evaluation** in light of a 21-hour outage that
  blocked five releases.
- **Both legs are serial and blocking, so `P(release) = P(GHCR) × P(zot)`.** Keeping GHCR on the
  blocking path can only *lower* nominal availability; it is justified only by the recovery
  property, which is why the untested artifact alternative above is load-bearing.
- **The topology is causally contributory to its own measured failure.** Each release makes three
  GHCR tag pushes, a cosign signature push, and three crane GHCR reads. Secondary rate limits are
  volume-triggered, so the dual-push shape helps produce the exact failure Decision (4) retries
  into. Not addressed here; noted so the next reader does not have to rediscover it.

**Neutral**

- Nothing about the host pull path changes. zot remains the sole pull path for the app image.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| **Push zot-first, GHCR best-effort (`continue-on-error`)** | **Corrected argument.** An earlier draft claimed GHCR "is the buildx `push: true` output target (`:740-746`)" — that citation is wrong: the targets are the `tags:` **list** at `:756-759`, and buildx pushes every entry, so adding a zot tag is one line. The real obstacle is documented in this repo already, at **`reusable-release.yml:805-806`**: *"the buildx container driver cannot reach the runner's 127.0.0.1 bridge listener, so adding a zot tag to build-push would not work."* CI reaches zot only through the CF-tunnel bridge on runner loopback. That is why the copy is runner-side `crane`. **Caveat, stated rather than hidden:** `docker/setup-buildx-action` accepts `driver-opts: network=host`, which would give the container driver the runner's loopback; `git grep -rn "driver-opts\|network=host" .github/` returns nothing repo-wide, so this is **untested here** and its interaction with `cache-to: type=gha` is unmeasured. The cost of this option is therefore *unmeasured*, not *proven high*. Separately, buildx fails the whole step on any tag failure, so option 1 still needs step separation to make GHCR best-effort. |
| **Build and push directly to zot; drop the crane hop** | Deletes the documented backfill by deleting its source; routes the entire upload through the currently-failing origin with no staged copy if it fails; and trades a transient, retryable, self-documenting failure for total dependence on the component that failed 3+ consecutive times that day. |
| **Keep dual-push but make the GHCR leg non-blocking** | Same structural objection as option 1. Additionally, *ignoring* a GHCR push failure would publish a release whose only image copy lives in a crash-looping registry — removing the backfill source at exactly the moment it is needed. Its intent is partially adopted in Decision (4), by retrying the measured failure class rather than ignoring it. |
| **Treat the 403 as a credential defect to repair** | There is no credential defect. The 403 is a secondary rate limit (P2). Repairing a working credential would be the ADR-166 failure applied to a remedy. |
| **Reintroduce a personal GHCR pull credential** | Out of bounds. That class was deliberately retired (#7071, ADR-088 arm-b) and nothing in this analysis argues for it: CI's read already works, and the host read is not what failed. |
| **Hold the staged copy somewhere other than GHCR** — `outputs: type=oci,dest=…` + `actions/upload-artifact` (90-day retention, digest-preserving, restorable via `crane push`), or simply rebuild from the same SHA against the `type=gha` cache | **NOT YET EVALUATED — and this is the option that decides whether Decision (1) stands.** An earlier draft of this ADR omitted it entirely while resting its central argument on GHCR being the *only* place a completed signed image lives. If an artifact-held OCI layout satisfies the recovery property, the backfill justification for keeping GHCR on the critical path dissolves. Open questions: does cosign's signature survive an OCI-layout round-trip; is 90-day retention sufficient; does the rebuild reproduce the digest bit-for-bit. **Resolving this is a precondition of promoting this ADR from Proposed to Accepted.** |

---

*Measurement provenance: GitHub Actions run logs for 30913993850 (both attempts), 30902554446,
30900564194, and the 12-run release history, retrieved via `gh run view --log` / `gh api
.../attempts/1/logs`; registry-host telemetry via `scripts/betterstack-query.sh` against the
`SOLEUR_ZOT_DISK` marker (Doppler `prd_terraform`, read-only); `dig` and `curl -sI` against
`registry.soleur.ai`. Workflow line references verified against `main` at d31d8a2c7.*
