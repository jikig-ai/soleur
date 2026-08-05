---
title: "fix: derive and encode a PASS condition for the registry-luks-recut D10 gate"
date: 2026-08-05
issue: 7277
branch: feat-one-shot-7277-d10-gate-pass-condition
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: the D10 gate has no valid PASS condition — derive one, encode it, rehearse it (#7277)

> `lane:` note — no `knowledge-base/project/specs/feat-one-shot-7277-d10-gate-pass-condition/spec.md`
> exists, so no `lane:` could be carried forward. Defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary (deepen-plan, 2026-08-05)

**Halt gates:** 4.6 User-Brand Impact **pass** · 4.7 Observability **pass** (all 5 fields populated,
no `ssh` in `discoverability_test.command`) · 4.8 PAT-shaped variables **pass** (no matches) ·
4.9 UI wireframe **skip** (no UI surface) · 4.10 Encryption Posture **pass** (no boilerplate) ·
4.5 Network-Outage **fired** → deep-dive section added · 4.55 Downtime & Cutover **fired** →
zero-downtime evaluation added · 4.4 scheduled-work precedent **N/A** (no scheduled job introduced).

**Verify-the-negative sweep — 12 of 12 absolute claims independently confirmed** against the
codebase (emit-site cardinality, absence of any backup/snapshot/sync/second-mirror, the credential
grader's network-free contract, the `crane validate` dark-launch, the crane pin-parity list,
`IMAGE_VERIFY_MODE` fail-open, `DOPPLER_TOKEN_PRD` absence, the job budget and permissions, both
inngest image pins, the four-pattern retention policy, `registry_region_migrate`'s five missing
guards, and the single `github -> ghcr` edge + the `cx33`/`cx23` disagreement). No premise in this
plan is unverified.

### Key improvements from the deepen pass

1. **A4 was itself a dark predicate — caught and fixed.** `zot_mirror_verdict` makes **zero** network
   requests; it grades a JSON file the detector must produce first. Sourcing only the grader returns
   `unmeasured` → DEGRADE, i.e. a predicate that runs, prints, and can never abort. A4 now
   explicitly runs `check-cloudflare-token-drift.sh` first, with a suite row pinning the abort.
2. **A4's verdict vocabulary is now mapped to the grader's own documented arms**, including the
   sentence that makes the independence claim structural rather than argued: `live` is *"where a
   crash-looping or otherwise unreachable origin lands."*
3. **A2's `crane validate --remote` contribution re-scoped honestly** against the dark-launch's real
   promotion criterion (a real run against prod, which a throwaway is not), and promoted from "free
   bonus" to a **hard Phase-0 dependency** — if it does not work against the throwaway, A2 has no
   blob verifier and needs a named fallback.
4. **Network-Outage deep-dive** answers all four layers from run artifacts, and names the gap it
   leaves: the reset is consistent with the crash-loop but does not prove causation — which is why
   the chosen PASS condition reads nothing about zot's health.
5. **Downtime & Cutover** evaluates the zero-downtime path (blue-green via a second registry),
   states plainly that it *is* ADR-096 clause (g)/#6126 and therefore out of scope, and records what
   this plan actually changes: the window goes from **unbounded** to **bounded by an automatic,
   fail-loud restore**.
6. **Pin-parity registration re-scoped:** the `CRANE_SHA256` check iterates a workflow-only set and
   asserts on the assignment form, so covering a `.sh` means widening the iterated set, not
   appending a name.

## Overview

`scripts/registry-pull-path-health.sh` (the D10 pre-destroy gate on the
`registry-luks-recut` dispatch) ends in an unconditional `exit 1`. No input passes it, so the
zot store cannot be recut at all — and the recut is the only remaining lever against a
crash-looping registry.

This plan derives, encodes, tests and **rehearses** a replacement authorization condition, and
removes the runbook's blocked-state banner. It does **not** fire the recut.

**The chosen PASS condition, in one sentence:** *a recut is authorized only when CI has just
proven, by executing it, that every image reference production depends on can be re-materialised
into an empty registry from GHCR — a source that survives the destroy.*

That is candidate #2 from the issue ("pre-stage the live digests outside the destroyed volume and
gate on a rehearsed restore"), **verified against the code rather than adopted on the issue's
say-so** — see [Research Reconciliation](#research-reconciliation--claims-vs-codebase) and
[Why this criterion](#why-this-criterion-and-not-the-other-three).

### The two defects, and what this plan does about each

| Defect | Disposition |
|---|---|
| **(1) The authorising premise is retracted.** D10 authorised a destroy on "GHCR covers the empty-store window". Since #7071 the host→GHCR edge is dead (read PAT 401, minter 403 DENIED). | The premise is not repaired — it is **replaced**. The new criterion never claims the window is covered. It claims the window is *ended*, by a restore that has just been executed successfully in rehearsal and is then executed for real by the same job. |
| **(2) The operand is dark.** `registry_pull_event ghcr-fallback` is emitted at `ci-deploy.sh` line 1918, which is the first statement inside `if _ghcr_pull_or_recover "$perr"; then` — i.e. only after a *successful* GHCR pull. | **The signal is dropped from the gate** (the acceptance criterion explicitly permits "fixed **or** the signal is dropped"). The whole Sentry-counter arm goes with it — see [What is removed](#what-is-removed-and-the-defense-relaxation-analysis). The emitter and its Sentry rule are handled as a named residual, not silently. |

### The blocker nobody has named yet, which this plan must also clear

Removing the unconditional refusal is **not sufficient**. The arm immediately above it aborts when
`zot_served == 0`:

```
::error::registry-pull-path-health: ABORT — the pull path is UNOBSERVED in the last 24h …
```

The runbook already records that this is *"what you will most likely see during an actual zot
outage … so during a crash-loop you get THIS, not `REFUSING`"*. So a minimal fix that only deletes
the refusal leaves the gate **still unfireable in exactly the incident it exists to recover from**.
Any plan that touches only the last block ships a second unfireable gate. This one removes the
entire zot-health arm.

## Research Reconciliation — claims vs. codebase

| Claim (issue / task brief) | Reality, measured | Plan response |
|---|---|---|
| `ghcr-fallback` "is emitted only inside the SUCCESS branch of a GHCR pull" | **True, and stronger.** `registry_pull_event ghcr-fallback` occurs exactly once in `apps/web-platform/infra/ci-deploy.sh`, as the first statement of the `then` block of `if _ghcr_pull_or_recover "$perr"; then` (in `pull_image_with_fallback`). `_ghcr_pull_or_recover` returns 0 only immediately after a successful `docker pull`. It is *additionally* gated on `ZOT_ACTIVE == 1`. | Drop the operand from the gate. Record the emitter/alert residual. |
| "the issue judges [candidate 2] strongest — VERIFY against the code" | **Verified, and the verification changed its shape.** There is no backup, snapshot, `extensions.sync`, R2 backend, second mirror, export, or digest manifest anywhere: `crane copy "${ZOT}` / `crane pull` / `crane export` / `docker save` return zero code hits. Nothing in-tree can answer "what is currently in zot". **But** `crane copy` GHCR→zot is registry-to-registry and digest-preserving, and a purpose-built no-rebuild backfill lever already exists (`build-inngest-bootstrap-image.yml`, `mirror_only: true`) — for one image only. So candidate 2 is not just "strongest", it is **implementable today by generalising an existing, working mechanism**. | Adopt, and build the restore engine as a generalisation of the existing `mirror_only` lever. |
| "pre-stage the live digests **outside the destroyed volume**" | Reading the digest list **out of zot** would make the gate depend on zot being up — the failing component. The live catalog is unreadable during a crash-loop. | **Do not read zot.** Derive the restore set from GHCR + committed config + production's own `/health`. See [Inventory derivation](#a0--inventory-derivation-aborting). |
| ADR-096 clause (g) is a broader debt than #7277 | **True, and clause (g) was already updated on 2026-08-04** to name #7277/#7278 and to state explicitly: *"Do not read the presence of #7277/#7278 as ownership."* | The ADR-096 amendment must **not** flip clause (g) to resolved. Explicit AC. |
| the registry `user_data` cap breach is fixed | **Verified:** commit `d0295964f` — *"the registry user_data was 1,860 B over Hetzner's cap, so no registry host could be provisioned (#7280)"*. | No action; premise holds. |
| production is UP but stale | **Verified live 2026-08-05:** `GET https://app.soleur.ai/health` → `{"status":"ok","version":"0.249.4","build_sha":"f838839ef11119ac46f4d38ccf926472dee393a8","uptime":91973,…}`. `soleur.ai/health` is the **docs** site and 404s — do not use it. | `/health` on `app.soleur.ai` is the inventory cross-check source. Its 25.5 h uptime is direct evidence that `/health` survives a zot outage. |
| the release pipeline is blocked for 9 runs | **Verified:** 9 consecutive `failure` on `web-platform-release.yml` since the `success` at 2026-08-04T11:09; latest 2026-08-05T08:18. The failing job is `release / release`; `migrate`/`deploy`/`verify-migrations`/`live-verify` all `skipped`. | Confirms the mirror's **push-into-prod-zot** half is what is broken; its **GHCR-read** half is not implicated. Load-bearing for the criterion's independence claim. |
| GHCR still holds the images and can serve them | **Measured 2026-08-05 from the planning workstation**, not inferred: `crane digest ghcr.io/jikig-ai/soleur-web-platform:latest` → `sha256:b04096d3bfb639c60be267da11bfd831cb332d295363f7a0d8224eb303be75e5`, rc 0. Negative control on the same binary: `crane manifest ghcr.io/jikig-ai/<nonexistent>` → `MANIFEST_UNKNOWN: manifest unknown`. | The source arm of the design is real, and the `NOTFOUND` stderr shape for A1's classifier is now measured text. **Scope this correctly:** it proves GHCR is readable with *a* credential from *a* host — **not** that the recut job's `GITHUB_TOKEN` + `packages: read` can do it. That is a distinct claim and stays a Phase 0.2 probe (`hr-verify-repo-capability-claim-before-assert`). |
| closing #7277 makes the recut fireable | **False.** The runbook's own Related section: #7277 is *"necessary … but not sufficient"* — the recut also runs `stock_preflight_gate`, and `var.registry_server_type` defaults to `cx23`, recorded as orderable in 0 of 3 EU datacenters (#6460). A live probe on 2026-08-05 shows `cx23` orderable in `nbg1-dc3` but **not** `hel1-dc2`, where this host runs. | Deleting the blocked-state banner **must not** be allowed to make the runbook claim fireability it does not have. Dedicated AC. |
| there is a bypass around this gate | **`registry-region-migrate` accepts a similar create shape with no confirm token, no id-pin, and no live probe** (ADR-096 accepted residual #6946). An operator whose recut ABORTs can fire it instead. | Named; disposition decided in [Scope boundaries](#scope-boundaries-explicit). |

## User-Brand Impact

**If this lands broken, the user experiences:** a `registry-luks-recut` that is authorized by a
green gate, destroys production's only container registry store, and cannot be refilled — after
which every host reboot, host replacement and deploy fails `image_pull_failed`. The already-running
containers keep serving until the first restart, then `app.soleur.ai` returns nothing at all. This
is not a degraded experience; it is the product being gone, with no rollback (the destroy is
irreversible and there is no snapshot, backup or second mirror anywhere in the estate).

**If this leaks, the user's data/workflow is exposed via:** the gate reads `ZOT_PUSH_TOKEN`, a
Cloudflare Access service-token pair and a Doppler token. An unguarded `::add-mask::` emit outside
a runner prints the live prd credential to the operator's terminal — the exact footgun the current
script guards at its `GITHUB_ACTIONS` check, which must survive the rewrite.

**Also user-facing, and not derivable from the paragraphs above** (added at CPO sign-off, 2026-08-05):

- **The success path narrows the rollback surface.** The restore carries only the `required` pins
  (`FLOOR = 2`) and the host→GHCR edge is dead (#7071), so a rebuilt host can pull nothing outside
  that set. `ci-deploy.sh` treats rollback to an older image as a supported, must-stay-functional
  path. Consequence: immediately after a recut, if the next release is bad there is no earlier image
  in zot to roll back to. Recoverable by re-running the restore engine with a wider set — but it is
  a capability that degrades on the **success** path, where nothing goes red.
- **The window's risk is not confined to the failure path.** During it, any unrelated restart — OOM,
  a Hetzner host event, a Docker daemon restart, a kernel update — converts a no-visible-impact
  window into a hard outage. This appears in Downtime & Cutover but belongs here, in the section
  reviewers actually read.
- **The window has no stated duration.** "Bounded" is asserted throughout and quantified nowhere.
  Phase 0.4 (the wall-clock measurement) is a named unmeasured residual, so the bound is currently
  *structural* (a job timeout + a resumable script), not *numeric*.
- **#7286 (inngest down, uninvestigated) intersects this window.** `soleur-inngest-bootstrap` is a
  required pin, so the window lands on the scheduled-work path. If crons and armed reminders are
  already not firing, the user-visible consequence is silently missed time-based commitments.

**Brand-survival threshold:** `single-user incident`.

CPO sign-off is required at plan time before `/work` begins, and `user-impact-reviewer` is invoked
at review time. **Sign-off obtained 2026-08-05 — see [Product/UX Gate](#productux-gate).**

## Why this criterion, and not the other three

| Candidate | Depends on the failing component? | Verdict |
|---|---|---|
| Gate on a successful CI dual-push within N hours | **Yes.** The dual-push's failing half *is* the push into prod zot (9 consecutive `copy_v` failures). A broken dual-push is the usual reason you need the recut. | Reject — unavailable precisely when needed. This is the issue's own objection, and the measured run history confirms it. |
| Require a second mirror to exist | **No**, but it does not exist and is not committed (ADR-096 clause (g); #6126 is "still not a commitment to build one"). | Reject — a gate whose PASS condition is an unbuilt system is the unconditional refusal wearing a different hat. |
| Refuse until a GHCR **pull** credential is restored | **No**, but ADR-096 clause (c) rejects it *structurally*: no GHCR pull credential can be minted without a browser; the App installation token can `docker login` but is DENIED `docker pull`. | Reject — not obtainable; would be a permanent refusal. |
| **Pre-staged digests + rehearsed restore** | **No.** Depends on GHCR-read-from-CI (working — it is the mirror's source half), `crane`, a throwaway registry in the runner, and prod `/health` (served by already-running containers, independent of zot). | **Adopt.** |

**The independence claim, stated precisely.** The criterion depends on GHCR-read-from-CI. That is
*not* the component whose failure motivates the recut — the recut is motivated by zot's store or
daemon failing. If GHCR-read-from-CI is broken there is genuinely nothing to restore from, and
refusing is the correct answer, not a deadlock.

## The gate's new shape

Five predicates. Each has an explicit **could-not-measure** bucket that ABORTS, and each
bucket is evaluated **before** any comparison. The verdict switch has no default-pass arm.

### A0 — inventory derivation, from production's OWN PINS (ABORTING)

Derive the restore set with **zero reads of zot**, and **derive it from what production actually
pins — never by re-deriving zot's retention policy**:

- a **source-level declared** pin set, each entry `{repo, how-the-tag-is-derived, required|conditional}`:
  - `jikig-ai/soleur-web-platform` → `v<version>` where `version` comes from
    `GET https://app.soleur.ai/health`. **required.** The `v<version>` shape is not a convention —
    `reusable-release.yml` literally constructs `"${IMAGE}:v${VERSION}"`, and the tag was verified
    present (`v0.249.4` is in `crane ls ghcr.io/jikig-ai/soleur-web-platform`, measured 2026-08-05).
  - `jikig-ai/soleur-inngest-bootstrap` → the tag pinned in `apps/web-platform/infra/cloud-init.yml`
    (`v1.1.24` at time of writing, read from the file, never hard-coded in the gate). **required.**
  - `jikig-ai/soleur-inngest-config` → the ref named by the Terraform-promoted
    `INNGEST_CONFIG_DIGEST` pointer, **conditional** (see below).
- plus `latest` per repo **only if** the boot path actually pulls it — resolved at Phase 0, not
  assumed.

**`soleur-inngest-config` must be `conditional`. The conclusion holds; the evidence originally
given for it did not, and was replaced (2026-08-05, second session).**

The original evidence was `crane ls ghcr.io/jikig-ai/soleur-inngest-config` returning
`NAME_UNKNOWN: repository name not known to registry`. **That measurement cannot support the
claim**, for the reason this plan documents everywhere else: an *uncredentialed* read cannot
distinguish "absent" from "not visible to this credential", and GHCR packages are private. It was
also taken against the **tags** API, which is not the API the gate uses. Re-measured properly:

| probe | result |
|---|---|
| `crane digest …/soleur-web-platform:latest` (positive control, private repo, same keychain) | **rc 0**, digest returned — so the credential works |
| `crane ls ghcr.io/jikig-ai/soleur-inngest-config` (credentialed) | rc 1 `NAME_UNKNOWN` |
| `crane digest ghcr.io/jikig-ai/soleur-inngest-config:latest` (credentialed) | rc 1 `MANIFEST_UNKNOWN` |
| `doppler secrets -p soleur -c prd_terraform` | `INNGEST_CONFIG_DIGEST` **does not exist** — the Terraform-promoted pointer is unprovisioned |
| `gh run list --workflow=build-inngest-config-bundle.yml` | **`[]` — the producer has never run** (control: the same query returns runs for `apply-web-platform-infra.yml`) |

The decisive evidence is the last row, and it is credential-independent: the producing workflow is
`workflow_dispatch`-only and has never been dispatched, so nothing was ever pushed. `model.c4`
marking that edge ADOPTING (riding the #6178 cutover) is consistent with this.

**Consequence, and note it is the OPPOSITE of what the blocker anticipated:** the entry stays
`conditional` and `FLOOR` stays **4**. It is not promoted to `required`. A gate that listed it as
required would abort forever on a repo that does not exist, **creating exactly the new deadlock
this plan exists to remove**.

**Also corrected:** the derivation was named `terraform-digest-pointer` while `resolve_tag()`
returns the literal tag `latest` — it never read the pointer. Since the pointer secret does not
exist, reading it was never possible; the derivation is renamed to say what it does. So: `required` entries abort on `NOTFOUND`; `conditional` entries
record a declared skip — and **the floor counts only `required` entries**, so a conditional skip can
never make the gate vacuous. The disposition lives in the declaration, so "declared but never
counted" stays unrepresentable in source — the same discipline the current script applies to
`WATCHED`.

**Rejected: deriving the set by reducing `crane ls` output with zot's retention keep-set.** Three
measured reasons. (a) It reimplements a policy that lives in `cloud-init-registry.yml`
`storage.retention` and will drift — the first draft of this plan already transcribed it wrongly,
dropping the `sha256-.*` / `mostRecentlyPushedCount: 50` signature rule (there are 382 such tags on
`soleur-web-platform` today). (b) It is *harmful*: `build-inngest-bootstrap-image.yml` records that
retention "can evict out of order under the ADR-096 crane-copy backfill path", and pushing ~11 tags
per repo in one burst into a fresh store with hourly gc and keep-5 is the maximal-pressure case —
the restore could evict the very tag cloud-init pins. (c) It buys nothing: production pins a handful
of refs, and those are the whole restore obligation.

*What makes A0 green while the thing it protects is broken?* (a) `/health` returns a version whose
tag does not exist at GHCR — A1 fails `NOTFOUND` → ABORT; (b) `/health` is unreachable — that is
could-not-measure → ABORT, evaluated before any comparison. That is **not** a zot-induced deadlock:
`/health` is served by an already-running container (measured `uptime` 91973 s, spanning the entire
crash-loop), so a zot outage does not take it down. (c) A `required` entry is silently downgraded
to `conditional` by a careless edit — guarded by the floor being a separate declared constant that
must equal the count of `required` entries, asserted at source level.

### A1 — source proof (POSITIVE) — an early abort and a classifier, not an independent predicate

For every `{repo, tag}` in the set, resolve a digest from CI: `crane digest ghcr.io/<repo>:<tag>`.
Accept only a value matching `^sha256:[0-9a-f]{64}$`, and only when the ref literally begins
`ghcr.io/`.

**Framing correction:** `crane copy` performs the same source resolution, so A1 does not prove
anything A2 does not. Its real value is narrower and still worth having: it aborts on a GHCR outage
*before* containers are started, and it produces the operator-facing classified message. Treat it as
A2's precondition, not as a fifth independent leg.

*Exit-code state space — enumerated, not assumed.* `crane` exits non-zero for **all** of
`MANIFEST_UNKNOWN`, `UNAUTHORIZED`, `DENIED`, `NAME_UNKNOWN`, DNS/TLS/network failure, and
binary-missing. A bare `rc != 0` therefore means none of those specifically. Classify from stderr
into `{OK, NOTFOUND, DENIED, NETWORK, MALFORMED, UNKNOWN}`; **every** non-`OK` token aborts, each
with its own message. `UNKNOWN` is the default arm and aborts loudest — an unclassified failure must
never read as either "absent" or "fine". Measured stderr shapes (2026-08-05, local `crane`):
missing tag → `MANIFEST_UNKNOWN: manifest unknown`; missing repo → `NAME_UNKNOWN: repository name
not known to registry`.

**Do not re-derive this from scratch.** `build-inngest-bootstrap-image.yml`'s mirror block already
implements the whole pattern and three non-obvious properties a fresh derivation will miss: reading
the digest **through a file** rather than `$(...)` (because the `retry` helper's `::notice::` output
pollutes stdout), filtering with `grep -oE '^sha256:[0-9a-f]{64}$'`, and capturing stderr through
`tr '\n' ' '` as a **workflow-command injection guard**. It also already splits
`parity_unmeasured` from `parity_mismatch` — precisely A1's `UNKNOWN`-vs-`NOTFOUND` discipline,
already written and reviewed. Lift it; cite it.

*What makes A1 green while broken?* A digest resolved against the wrong registry (a cached or
mis-typed auth). Guarded by the literal `ghcr.io/` prefix assertion plus the digest-shape regex; a
200 carrying a garbage body cannot produce a well-formed digest.

### A2 — rehearsed restore against a throwaway registry (POSITIVE)

**What A2 is and is not.** A2 proves the restore *script* is correct against a real registry HTTP
API — argv, auth, ref construction, digest parity, blob completeness. It does **not** touch the
Cloudflare Tunnel, the live `ZOT_PUSH_*` credential, the rebuilt host, or the private-NIC pull path.
**The load-bearing element of this plan is the chained post-D11 real restore (Phase 3)** — that is
what exercises the actual path with the actual credentials against the actual sink. A2 is its
pre-destroy safety net, not its equal.

**Rejected alternative, recorded because it is strictly stronger and a reviewer will ask for it:**
rehearse against **production zot itself** before the destroy. `crane copy` is idempotent and skips
blobs the destination already holds, so restoring already-present refs is close to a no-op — and it
would prove the tunnel, the live credential, the real zot version and the real `accessControl`,
eliminating A4's admitted stale-credential residual. **It is rejected because it depends on the
component whose failure motivates the recut:** during a zot crash-loop that rehearsal aborts exactly
when the gate is needed. This is the plan's own independence criterion applied to itself, and it
must be written into the ADR.

In the same job, **before** anything is destroyed:

1. start a throwaway zot in the runner, pinned to the **same image production runs** — read through
   `zot-registry.tf`'s `local.zot_image = local.registry_arch == "arm64" ? zot_image_arm64 :
   zot_image_amd64` ternary, **not** the `zot_image_amd64` variable directly. It matches today only
   because `cx23` is amd64, and #6460 makes a `cax*` fallback live; a bare `amd64` read would
   silently rehearse a different zot build. Config derived from `cloud-init-registry.yml` — same
   `htpasswd` auth shape, same `accessControl` (`defaultPolicy: []`), only paths and credentials
   substituted;
2. run **the same restore script** the post-recut path will run
   (`scripts/registry-restore-from-ghcr.sh`), targeting the throwaway;
3. verify with **`crane validate --remote`**, not `crane digest`. `build-inngest-bootstrap-image.yml`
   already records in writing that a manifest read proves the **manifest**, not the **blobs** — zot
   gc can evict a layer, yielding *green digest parity and `blob unknown` at the host's
   `docker pull`*. A digest-only round-trip is therefore a gate that goes green on an unusable
   restore, the exact defect class this plan exists to remove.

   `crane validate --remote` is already **dark-launched, non-blocking** in that file, and its
   warning states the promotion criterion precisely: *"Either zot gc'd a layer (a pin would fail at
   docker pull with 'blob unknown') **OR** crane validate does not speak plain-HTTP to the loopback
   bridge the way copy/digest do. Resolve which BEFORE promoting this to a gate."*

   **Scope this contribution honestly.** The dark-launch's actual promotion criterion is *"once
   `blob_validate=ok` has been observed on ≥1 **real run** (any trigger), delete this branch and
   restore the blocking form"* — a run of **that** workflow against **prod** zot. A throwaway in the
   recut job is not that. What the throwaway *does* settle is the narrower disjunct: it is direct
   plain-HTTP loopback with no `cloudflared`, so a successful validate rules out
   "crane validate can't do plain-HTTP loopback at all", leaving only cloudflared-specific
   behaviour. Real narrowing; **not** grounds to promote the dark-launch.

   **And it is a hard Phase-0 dependency, not a bonus.** If `crane validate --remote` does not work
   against the throwaway, A2 has no blob-completeness verifier and needs a named fallback (e.g.
   pulling each blob by digest via the registry API and comparing lengths). Probe it in 0.4 before
   committing A2's verification method;
4. assert, per restored digest, that its **cosign signature tag is present** in the throwaway (see
   the signature rule in Phase 0.3 — this is not optional, see below).

*What makes A2 green while broken?* Four inputs, each with a named guard:

| Fail-open input | Guard |
|---|---|
| The runner's local Docker image cache satisfies a `docker pull`, so the round-trip never touches the throwaway registry. | Read back with `crane digest` against the registry HTTP endpoint (crane does not consult the Docker daemon), into a per-run random repository namespace. **Do not use `docker pull` anywhere in the verification path.** |
| The throwaway allows anonymous push (`defaultPolicy: ["read","create"]`), so the restore succeeds without authenticating and a credential failure against prod stays invisible. | Generate an `htpasswd` with the same `htpasswd -Bbn` form and pin `defaultPolicy: []`; a negative control in the test suite asserts an unauthenticated restore FAILS. |
| The throwaway runs a different zot version than prod, so a version-specific ingest bug is invisible. | Pin the throwaway to the Terraform-declared digest and assert in the test suite that the pin is read from `zot-registry.tf`, not a literal. |
| The rehearsal script and the real restore script drift apart. | One script, one entrypoint; the only difference is the target URL and credentials. A test asserts the workflow's rehearsal step and its real-restore step invoke the same path. |

**Named residual, not eliminated:** A2 proves the restore works against a reachable zot over the CF
Tunnel transport. It does **not** prove the *rebuilt* host will be reachable, nor that hosts can
pull from it — ADR-096 clause (f) makes exactly this distinction (different transport: private NIC,
no tunnel, no CF Access; different credential `ZOT_PULL_*`). The compensating controls are D11's
heartbeat-transition poll and the chained real restore in Phase 3, both fail-loud.

### A3 — non-vacuity floor (ABORTING)

`|required entries| == |digests resolved| == |validated in the rehearsal| == FLOOR`, where `FLOOR` is
a declared constant **with a stated value and a stated derivation** — not a placeholder. Given the
A0 pin set, `FLOOR = 2` at time of writing: `soleur-web-platform` at prod's `/health` version, and
`soleur-inngest-bootstrap` at the `cloud-init.yml` pin. `soleur-inngest-config` is `conditional` and
does **not** count (it does not exist at GHCR — measured). Raising `FLOOR` is the deliberate act
that admits a new required image; an under-set floor is the vacuity hole this predicate exists to
close, so the value must be justified in the same line it is declared.

**The arity self-check applies to the PIN SET, not to the tag list.** The current script's
`(( ${#WATCHED[@]} != 3 ))` idiom works because `WATCHED` is a literal array in source. Under A0's
derive-from-prod's-pins design the **pin set is again a source-level declaration**, so the idiom
transfers exactly: assert `|declared required pins| == FLOOR` in source. It would **not** have
transferred to the rejected derive-from-`crane ls` design, where the set is computed at runtime and
there is no source arity to pin — a detail worth recording, because applying the idiom there would
have been cargo-culting an assertion that cannot hold.

*Why this predicate exists at all:* the single most likely way this gate fails open is an **empty
inventory** — every `for` loop then passes and the gate goes green having proven nothing. This is
the anti-vacuity role the old `zot_served >= 1` denominator carried, re-pointed at an instrument
that is available during an outage.

### A4 — sink-credential VALIDITY, graded live at the Cloudflare Access edge (ABORTING)

An earlier draft made A4 a non-emptiness check on `ZOT_PUSH_USER`, `ZOT_PUSH_TOKEN`,
`REGISTRY_PUSH_ACCESS_TOKEN_ID`, `REGISTRY_PUSH_ACCESS_TOKEN_SECRET` and `APP_DOMAIN_BASE` read from
Doppler `soleur/prd`, and asserted that staleness was *"not eliminable pre-destroy without pushing
to prod zot"*. **That assertion was false, and it was the most dangerous sentence in the plan** —
it is a proxy (the secret is *present*) standing in for the invariant (the secret *works*), on the
one predicate whose failure ends in a permanently empty store.

**The repo already contains a live grader for exactly this credential class, and it does not touch
zot.** `reusable-release.yml`, factored into `scripts/zot-mirror-diagnosis.sh`
(`zot_mirror_verdict`, `zot_mirror_unverifiable_cause`) and unit-tested, verifies the registry-push
CF Access service token **at the Cloudflare Access edge**. Its own verdict strings say what it
proves:

> `live)  … Cloudflare Access admitted these exact credentials on registry.soleur.ai. If the zot mirror still fails, the credential is ruled OUT by measurement.`
> `stale) ::warning::The registry-push CF Access service token is MEASURED DEAD in at least one Doppler config. The zot mirror step later in this job will very likely fail with mirror_reason=bridge.`

**A4 becomes: run that grader.** Read at deepen-plan time, `scripts/zot-mirror-diagnosis.sh`
`zot_mirror_verdict(rc, json_file)` echoes a **closed four-value vocabulary**, and its own header
documents each arm. Map them directly:

| Verdict | Its documented meaning (verbatim) | A4 |
|---|---|---|
| `live` | *"the detector probed the credential and Cloudflare Access ADMITTED it. Rotation is ruled OUT by measurement. **This is where a crash-looping or otherwise unreachable origin lands.**"* | **PASS** |
| `stale` | *"a MEASURED dead count (json .dead > 0). Rotation genuinely is the remedy, and **this is the only arm on which that is true**."* | **ABORT** |
| `unverifiable` | *"a measured 'could not tell' … **NOT an accusation**: the detector's own cause vocabulary all carries 'Do NOT rotate'."* | **DEGRADE** — log, do not abort |
| `unmeasured` | *"nothing was checked, or the verdict file could not be read/parsed, or the exit code and the counts contradict each other. **Ranks nothing.**"* | **DEGRADE** — log, do not abort |

That bolded sentence on `live` is why this satisfies the independence criterion **by construction,
not by argument**: the grader's own author already established that a crash-looping origin lands on
`live`. The Cloudflare Access edge is up whether or not zot is.

**It also already implements the exit-code discipline this task demanded, so do not re-derive it.**
Its header records the trap verbatim: the underlying detector *"exits 1 for `DEAD_N > 0 ||
UNVERIFIABLE_N > 0` — so mapping rc=1 to 'stale' prints 'the token is STALE, rotate it' about a
token nothing measured. The counts come from the JSON; rc only distinguishes 'ran' from 'could not
run at all' (exit 2)."* A missing JSON key reads as a `-1` sentinel, **never** as 0, because
*"treating 'the file did not report this' as 'the count was zero' would manufacture `live` out of a
file that measured nothing"*; and the final arm requires **positive evidence** rather than absence
of bad news. Consuming this function is strictly safer than writing a new classifier.

**`zot_mirror_verdict` MEASURES NOTHING BY ITSELF — A4 must run the detector first.** Verified at
deepen-plan: the function makes **zero** network requests (its own header says *"No network, no side
effects"*); it is pure arithmetic over a JSON file **already produced** by
`check-cloudflare-token-drift.sh --json-file`. So A4 is two steps, and the order is load-bearing:

1. run the detector, capturing **both** its exit code and its `--json-file` output;
2. `zot_mirror_verdict "$rc" "$json_file"`.

**Skipping step 1 does not fail — it returns `unmeasured`, which A4 maps to DEGRADE.** A4 would then
be a predicate that runs, prints, and can never abort: precisely the dark-operand defect this whole
plan exists to remove, reintroduced in the predicate meant to close it. Pin it with a suite row that
asserts A4 aborts on a `stale` fixture **and** a structural check that the gate invokes the detector,
not just the grader.

**Sourcing constraint (load-bearing):** the file's header states it *"must NOT `set -euo pipefail`"*
because it is sourced into steps already running under `bash -eo pipefail`. The gate must source it
without altering that, and must not wrap it in a subshell that swallows the verdict.

Read credentials via `DOPPLER_TOKEN_PRD`, **not** the `prd_terraform`-scoped `DOPPLER_TOKEN` — the
composite bridge action documents that distinction explicitly. **`DOPPLER_TOKEN_PRD` is referenced
zero times in `apply-web-platform-infra.yml` today** (it exists only in the release and
inngest-build workflows), and this is not a reusable-workflow call so `secrets: inherit` does not
apply. Wiring it is a Phase 3 task with its own AC — without it A4 aborts on every dispatch, which
would be a *new* unfireable gate.

*What makes A4 green while broken?* The Access token is live but `ZOT_PUSH_TOKEN` (zot's own
htpasswd credential, a different secret behind the same tunnel) is stale. A5's authenticated write
is what closes that; A4 and A5 grade two different credentials on the same path and neither
subsumes the other.

*Health-URL derivation:* A0 must build the `/health` URL from `APP_DOMAIN_BASE` rather than
hard-coding `https://app.soleur.ai/health`, or the `APP_DOMAIN_BASE` read is decorative and the two
sections disagree about where "committed config" ends.

### A5 — sink proof (ADVISORY-DEGRADING, never deadlocking) — the predicate the first draft missed

**Why this exists.** The first draft of this plan had *no predicate that observed prod zot at all*.
It answered "must not depend on the failing component" by never looking at it — which is a different
property, and a much weaker one. It would have authorised destroying a sink it had never observed,
then chained into that sink **the exact `crane copy` write with a measured 9-out-of-9 failure
record**. The run log of `30988480437` is decisive about which half fails:

```
BRIDGE_OUTCOME: success
Error: Patch "http://127.0.0.1:5000/v2/jikig-ai/soleur-***/blobs/uploads/…": write: connection reset by peer
##[error]zot mirror FAILED at stage 'copy_v' … zot did not receive the 'v0.249.5' tag
```

crane had already **read** the GHCR blobs in order to PATCH them upward — so GHCR-read-from-CI
works, the bridge came up, and the **prod-zot write** is what dies.

**The probe, pre-destroy, non-destructive:** bring up the CF Tunnel bridge (the existing composite
action), `docker login` (which `cf-tunnel-registry-bridge` already performs), read the catalog, and
attempt **one** small write — `crane copy` of an already-present ref is near-idempotent because
crane skips blobs the destination holds. Classify the outcome:

| Outcome | Verdict |
|---|---|
| write succeeds | **PASS.** A4's staleness residual is now *measured*, not assumed. The tunnel, the CF Access pair, `ZOT_PUSH_TOKEN` and the script are proven end-to-end against the real sink. |
| reachable, credential **REJECTED** — `401`/`403`/`DENIED` from zot's htpasswd/`accessControl`, or a CF Access admission refusal | **ABORT.** A credential failure is *independent of zot's health*: it means the post-destroy restore cannot work no matter how healthy the rebuilt host is. This is exactly the state A4 could never see, and the state in which a destroy is unrecoverable. |
| write **completed but produced the wrong digest** | **ABORT.** A measured correctness failure, not an availability one. |
| **unmeasurable** — origin unreachable, tunnel down, timeout, `connection reset by peer` mid-upload, 5xx, or unclassifiable | **PROCEED, with a named and logged degradation** (`sink_probe=unmeasured` in the run summary and the step summary). |

**The bucket boundary is the single most dangerous line in this plan and it must be drawn exactly
here.** An earlier draft of this table put *"reset mid-upload"* in the ABORT bucket. That is wrong,
and wrong in the direction that recreates the very deadlock this plan exists to remove: run
`30988480437`'s failure is literally `write: connection reset by peer` on the blob PATCH. Under that
draft the gate would ABORT **today**, during the incident, for the same reason the old gate did.
Availability failures of the sink are the *motivating condition*; only **authorisation** and
**correctness** failures — which are orthogonal to zot's health — may abort.

This makes A5 the **inverse** of the fail-closed rule used everywhere else in the gate, deliberately:
elsewhere "cannot measure" means "cannot prove safe"; here the *un*measurability **is** the incident.
Encode the asymmetry with a comment saying exactly that, and pin it with a test row, or a future
reader will "fix" it back into a deadlock.

*What makes A5 green while broken?* A write that succeeds against a zot which then panics on its
next scheduled gc pass (`gcInterval: 1h`) — a throwaway or a single probe never reaches a scheduled
cycle. Not closable pre-destroy; named, and it is why A5 is a *floor*, not a guarantee.

**A5 also replaces the one role of the removed defense that was otherwise landing unreplaced** —
see role B in [What is removed](#what-is-removed-and-the-defense-relaxation-analysis).

## What is removed, and the defense-relaxation analysis

Removed from the verdict: the three Sentry `WATCHED` counters (`ghcr-fallback`, `local-cache`,
`zot-gate-degraded`) **and** the `registry:"zot"` denominator. Per the defense-relaxation
discipline, each role the old defense carried is accounted for:

| Old role | Status | Replacement |
|---|---|---|
| A — "the GHCR fallback path is degraded ⇒ do not destroy" | Premise retracted (#7071); there is no fallback path to be degraded. | None needed. The surviving concern — *is the source still able to serve?* — is answered far more directly by **A1**. |
| B — "`ZOT_ACTIVE=0`, the fleet is running entirely on GHCR" | Today this state means the fleet cannot pull at all. It is a reason **to** recut, not to block one. | None needed; blocking on it is the deadlock this plan removes. |
| C — anti-vacuity: "prove we observed anything at all" | **Load-bearing. Preserved.** | **A3**, which is a *positive* observation of the thing that matters and is available during a zot outage — unlike the denominator, which is zero exactly then. |

The gate keeps its two structural safety properties verbatim: **fail-closed on any unmeasurable
input**, and the `GITHUB_ACTIONS`-guarded `::add-mask::` emit (an unguarded mask emit prints the
live prd credential to the operator's terminal, because the runbook tells them to run this script
locally).

## Implementation Phases

### Phase 0 — preconditions (probe, do not assume)

Every item is a command whose output is pinned into the plan/PR before code is written.

0.1 **`crane` availability and the exact stderr strings** for `MANIFEST_UNKNOWN`, `UNAUTHORIZED`
and a DNS failure, so A1's classifier is written against measured text, not guessed text. Reuse
`reusable-release.yml`'s `install_crane()` verbatim — `CRANE_VERSION="v0.20.2"`,
`CRANE_SHA256="c14340087103ba9dadf61d45acd20675490fd0ccbd56ac7901fc1b502137f44b"`, download +
`sha256sum -c` + `tar`. Do **not** `go install` (the recut job's own comments already record that
crane is not preinstalled). `crane` is present on the planning workstation, so the stderr strings
can be captured locally before any CI run.

0.2 **`packages: read` sufficiency.** Confirm the workflow's `GITHUB_TOKEN` with `packages: read`
can `crane ls`/`crane digest` all three private GHCR repos. The recut job currently inherits
workflow-level `permissions: contents: read` only; sibling jobs in the same file already declare
`packages: read`, so the pattern exists.

0.3 **Signatures are part of the restore obligation — NOT an optional arm.** An earlier draft of
this plan offered "the restore does not sign; `IMAGE_VERIFY_MODE=warn` makes that non-fatal" as an
acceptable fallback. **That arm is deleted.** It relaxes a fleet-wide supply-chain control on the
recut path *because a different control happens to be disabled*, with no predicate going red —
which is the exact defect class this plan exists to remove. The coupling is stated in
`cloud-init-registry.yml` itself: deploy-time `cosign verify` fetches the signature **by tag from
the same registry it pulls the image**, so a kept image's signature must never be absent (ADR-087).
And `reusable-release.yml` records that **a bare `crane copy` does not write the signature
referrer**.

So the restore must produce, per restored digest, a valid signature in the target. Two mechanisms;
Phase 0 picks one by probe, and either way A2 asserts per-digest signature presence:
  - **Copy the `sha256-<digest>.sig` tag from GHCR.** These exist — `crane ls
    ghcr.io/jikig-ai/soleur-web-platform` shows `sha256-b04096d3…` alongside the `latest` digest
    `sha256:b04096d3…` (measured 2026-08-05). Cheapest, no OIDC. **Must be probed, not assumed:**
    the simple-signing payload pins `critical.identity.docker-reference` to the GHCR ref, so
    `cosign verify` against a zot ref may reject it. That is why the release path re-signs rather
    than copying. Measure whether the repo's verify invocation actually checks `docker-reference`.
  - **Re-sign** (`cosign sign --yes "${TARGET}@${DIGEST}"`, keyless), requiring `id-token: write` on
    the job — the same permission `reusable-release.yml` already uses for this purpose. Rehearsal
    caveat: keyless signing writes to the **public Rekor log on every gate run**; rehearse with
    `--tlog-upload=false` and verify with `--insecure-ignore-tlog` so the rehearsal exercises
    OIDC + sign + push without polluting a public transparency log. Record that as a deliberate,
    named rehearsal/real difference.

  **Named dependency, to be declared in the ADR rather than left as a footnote:** the design's
  tolerance for any signature imperfection rests on `IMAGE_VERIFY_MODE` defaulting to `warn` in
  `ci-deploy.sh`, where a verify failure runs the digest anyway. That is a *disabled control*, not a
  safety property, and a future ENFORCE flip changes the calculus. Note that the plan's cited
  precedent (`build-inngest-bootstrap-image.yml` `mirror_only: true`) ships **unsigned** — it has no
  `id-token:` permission — so it is a precedent for the copy mechanics only, never for the signing
  half. That half comes from `reusable-release.yml`'s `sign` stage.

0.4 **Throwaway-zot feasibility AND a transfer/disk budget for the FULL pin set** — not one image.
Start the Terraform-pinned zot image (read through the `local.zot_image` arch ternary) in the runner
with a generated htpasswd, then run the whole restore for the real pin set and **record wall-clock
and peak disk**. The web-platform image is ~1.5–2 GB per version per `cloud-init-registry.yml`, and
a GitHub-hosted `ubuntu-24.04` runner has limited free space on the volume carrying the workspace
where the throwaway `rootDirectory` lives. Two numbers come out of this probe and both feed Phase 3:
the per-pass duration (against the job budget) and the peak footprint (against runner disk).

0.5 **`/health` shape and freshness.** Already measured (see Research Reconciliation). Re-confirm at
work time, pin the field names the parser depends on, send `Cache-Control: no-cache`, and
**cross-check `build_sha` as well as `version`** — a cached edge response carrying a previous
`version` would otherwise satisfy the membership assertion while the actually-running build is
unrestorable.

0.6 **A5's sink-outcome classification strings.** Capture, from the release workflow's own failing
run logs and from a deliberate bad-credential attempt, the exact text that distinguishes
*credential rejected* (`401`/`403`/`DENIED`, CF Access refusal) from *availability failure*
(`connection reset by peer`, timeout, 5xx). A5's abort/degrade boundary is drawn on these strings,
so they must be measured, never guessed — a misclassification in one direction deadlocks the
recovery lever and in the other authorises an unrecoverable destroy.

### Phase 1 — the restore engine (write the test first)

Create `scripts/registry-restore-from-ghcr.sh`.

- **Contract:** `--target <registry-host:port> --tags-from <manifest.json>`, reading credentials
  from the environment. Emits a per-entry line and a machine-readable summary.

#### `--rehearse` re-scoped — the flag is DELETED (work-phase deviation, 2026-08-05)

The plan gave `--rehearse` exactly one defined effect: select `cosign sign --tlog-upload=false`
(verify with `--insecure-ignore-tlog`) so a gate run does not pollute the public Rekor log — and
warned that without a defined semantic the flag is either vacuous or violates A2's anti-drift guard.

**Phase 0.3 measured the signature mechanism to be `crane copy` of the `sha256-<digest>` tag, so
nothing signs at all** (the GHCR signature is a Sigstore **bundle v0.3** bound to the image digest,
not a simple-signing payload pinning a registry ref — see `phase-0-probe-evidence.md` §0.3). With no
`cosign sign` in the engine, the flag's only defined effect has no referent.

Two replacements were considered and **rejected on measurement**:

- *Make `--rehearse` assert a loopback target, and its absence assert a non-loopback one.* **Wrong —
  it cannot discriminate.** The real restore also targets `127.0.0.1:5000`, because CI reaches prod
  zot through `cloudflared access tcp` on loopback by design (this plan's own Encryption Posture
  says so). Both sides are loopback plain-HTTP; the guard would have been unfalsifiable.
- *Keep it as a label on the summary line.* That is the "does nothing" arm the plan already rejected;
  the emitted `target=` field already discriminates rehearsal from real in the log.

**Resolution: delete the flag.** The two invocations then differ in exactly `--target` and the
credential environment — which is *verbatim* the property A2's anti-drift guard asks for
(*"one script, one entrypoint; the only difference is the target URL and credentials"*). This is
simpler than the plan's design and satisfies the same invariant more directly. The suite asserts the
workflow's rehearsal and real steps invoke the same script path and differ only in those two inputs.

**AC14 is amended accordingly** (see Acceptance Criteria): "without `--rehearse`" would be
trivially-true-and-meaningless against a script with no such flag, which is the ceremony class the
plan's own R13 cut.
- **Exit codes, fully enumerated** (no bare `1` for "something went wrong"):
  `0` all restored **and** verified · `2` source unavailable · `3` sink unavailable ·
  `4` verification mismatch · `5` credential unreadable · `6` could-not-classify (UNKNOWN).
  **Each code needs a reader.** Six enumerated codes consumed as a single boolean is a contract
  nobody can act on: the workflow step must branch its `::error::` text on the code, and the runbook
  must carry one operator action per code (AC19).
- **Verification is intrinsic, not a caller's job:** the script does not exit 0 until it has read
  every reference back out of the target with `crane validate --remote` (blobs, not just the
  manifest) and matched digests.
- **Resumable by contract:** safely re-runnable after a partial pass. `crane copy` is idempotent and
  skips blobs the destination holds, so this is nearly free — but assert it with a suite row that
  runs the script twice and expects the second pass to be a clean no-op. This is what makes a
  timed-out or cancelled restore recoverable rather than a half-populated registry.
- **Reuse, do not re-derive.** `build-inngest-bootstrap-image.yml`'s mirror block already implements
  the copy spine and three non-obvious properties: digest read **through a file** (its `retry`
  helper's `::notice::` pollutes stdout), `grep -oE '^sha256:[0-9a-f]{64}$'` filtering, and stderr
  captured through `tr '\n' ' '` as a **workflow-command injection guard**. It also splits
  `parity_unmeasured` from `parity_mismatch` — A1's `UNKNOWN`-vs-`NOTFOUND` discipline, already
  written. Lift and cite. Note the precedent covers the **copy** half only: that workflow ships
  **unsigned** (no `id-token:` permission), so the signing half comes from `reusable-release.yml`.
- The real value of a script (over generalising that YAML block in place) is not "one image to
  three": that block is ~285 lines of inline `run:` inside a job, with a hardcoded `IMAGE`, a
  `degraded()` that **exits 0**, and a step `id` + `mirror_status` output documented as
  must-not-change with four downstream consumers. The value is extracting untestable inline YAML
  into a script with a suite.

New suite `tests/scripts/test-registry-restore-from-ghcr.sh`, following the shape of
`tests/scripts/test-registry-pull-path-health.sh` (self-contained, `set -uo pipefail`, inline
`pass`/`fail`/`check`, banner + counters, argv-dispatching stubs so a stub that ignores its
arguments cannot pass). **Register it in `scripts/test-all.sh` next to the existing D10 entry** —
`scripts/lint-orphan-test-suites.sh` covers `scripts/*.test.sh` only and will not catch an
unregistered `tests/scripts/test-*.sh`.

### Phase 2 — rewrite the gate

Rewrite `scripts/registry-pull-path-health.sh` **in place** (same path — the runbook's done-signal
is `grep -c "no valid PASS condition" scripts/registry-pull-path-health.sh`, and deleting the file
makes that grep error rather than return 0). Implement A0–A4, drop the Sentry arm, keep the
fail-closed and mask-guard properties. Add test seams mirroring the existing
`REGISTRY_PULL_HEALTH_QUERY_CMD` idiom, one per external dependency, each able to emit every
classified status token **including `UNKNOWN`**.

Rewrite `tests/scripts/test-registry-pull-path-health.sh`:

- **the suite's first duty stays "prove the gate CAN go red"** — a positive control per abort
  cause (≥8: empty inventory, floor breach, `/health` unreachable, `/health` version absent from
  the set, A1 NOTFOUND, A1 DENIED, A1 UNKNOWN, A2 digest mismatch, A2 unauthenticated-push
  negative control, A4 credential unreadable);
- **and then, new and non-negotiable, a green row** asserting `rc == 0` on the all-good fixture.
  The current suite has no such row, which is how an unpassable gate shipped with 23 green
  assertions. Without this row the rewrite could ship the same defect;
- structural greps: the arity self-check exists; the verdict switch has no default-pass arm; every
  `::add-mask::` still has `GITHUB_ACTIONS` within 2 lines above it (measured on a
  comments-stripped copy, as today);
- the `${#WATCHED[@]} != 3` structural grep and the 4-arg stub arms are removed **together** with
  the array they pin.

### Phase 3 — wire it into the dispatch

`.github/workflows/apply-web-platform-infra.yml`, job `registry_luks_recut`:

- job-level `permissions:` adding `packages: read` (+ `id-token: write` per 0.3);
- **wire `DOPPLER_TOKEN_PRD` into this workflow.** It is referenced zero times here today. Without
  it A4 cannot read `soleur/prd` and aborts on every dispatch. Own AC.
- **Split the step into an unconditional PREPARE step and a conditional VERDICT step.** This is
  load-bearing and the first draft got it wrong: crane install, the inventory derivation and the
  pinned-manifest artifact must live in a step that runs on **both** arms, because the resume arm
  (`probe_result == 'absent'`) is *already destroyed and empty* — it is the arm that most needs a
  restore, and it has no inventory if derivation lives inside the skipped step. Only the **verdict**
  (A2/A4/A5, which authorise a destroy) stays behind
  `if: steps.posture.outputs.probe_result != 'absent'`.
- **Correct the resume-arm skip's stated reason.** The workflow comment justifies the skip as
  *"running the gate here would abort on `ghcr-fallback` events the incomplete recut itself
  produced"*. After this rewrite the gate reads no `ghcr-fallback`, no `local-cache`, no zot health
  and no Sentry — **that reason is falsified by the gate change, not by the emitter**, so the
  "review-before-editing" note elsewhere in this plan does not cover it. The skip remains correct
  (there is nothing left to authorise once the volume is already gone), but the encoded reason must
  be replaced with the true one. Three further `ghcr-fallback` references in this job (the D10
  comment block, the resume-path skip notice, the post-destroy ordering constraint) are stale for
  the same reason and are in scope — not just the summary's "PAGES" claim.
- **Cheap gates before expensive ones.** The A2 rehearsal is now the most expensive step in the job,
  and `stock_preflight_gate` — which will abort **both** journeys while `cx23` is unavailable in
  `hel1-dc2` — runs *after* it. Move any cheaply-evaluable precondition ahead of the rehearsal, or
  add a pre-rehearsal stock probe, so a dispatch that cannot possibly proceed does not first move
  multiple GB. (`stock_preflight_gate` itself needs `tfplan.json` and cannot simply be hoisted; a
  standalone availability probe can.)
- **run the real restore after D11's heartbeat-transition poll — in a SEPARATE JOB chained by
  `needs:`, not as another step in `registry_luks_recut`.** This is the load-bearing element of the
  whole plan (A2 is its pre-destroy safety net, not its equal), and it must not share the recut
  job's budget. `timeout-minutes: 30` there is explicitly load-bearing — the job holds the
  fleet-wide apply mutex, and its own comment states that D11's 150 s + 480 s bound sits strictly
  below the timeout *"so its diagnostic wins over an opaque cancellation"*. Adding a multi-GB
  restore inside that budget breaks the invariant, and a timeout is a **cancellation**: store
  destroyed, restore half-applied, no `::error::`, and the `Dispatch summary` — the only emitter of
  the new volume id, without which the next recut is blocked — never runs. A partially populated
  registry is worse than an empty one, because tag lookups succeed for some refs and not others.
  Splitting the job gives the restore its own budget, releases the mutex before the slow part, and
  keeps the recut job's cancellation semantics intact.
- **The restore script must be resumable** — safely re-runnable after a partial pass. `crane copy`
  is idempotent, so this is nearly free, but it must be asserted, not assumed.
- **Decide the restore job's `if:` explicitly.** D11 carries no `if:`, so a following step would
  default to `success()`. The restore must run on the resume arm too (that arm *is* the empty-store
  state it exists to end), which is why the PREPARE step above is unconditional.

  **The restore step must retry on exit 3 (sink unavailable) with a bounded backoff.** D11 proves
  the rebuilt *host* checked in; it does not prove the **Cloudflare Tunnel route** has re-converged
  onto the replaced origin — `model.c4` describes that edge as origin-relative, resolved by
  whichever connector replica answers, and the same file records a 2026-08-03 case (#7242) where
  Access admitted the request while the origin was not serving. So the first restore attempt after
  a host replace is expected to be able to fail on convergence timing, and a single-shot fail-loud
  step would report a false "restore broken". Bound the retry strictly below the job's
  `timeout-minutes: 30` budget (which already holds the fleet-wide apply mutex), and fail loud on
  exhaustion — never `continue-on-error`;
- **correct the dispatch summary — and make it conditional.** It currently tells the operator the
  empty-store window *"PAGES"* via `registry_pull_event registry=ghcr-fallback`. That page **cannot
  arrive** — the same dark-operand defect. Telling an operator to expect a page that cannot come is
  worse than saying nothing. Three constraints on the replacement:
  - The summary step carries `if: always()`, so a flat *"the chained restore runs"* would print
    verbatim on every path where it did **not** run — D11 failed, job cancelled, resume arm. Branch
    the text on the restore job's actual outcome.
  - **Keep the operator exit**, do not delete it. Per the repo's own principle that *a CI-emitted
    message may only name a cause the job measured*, the summary must not promise a bounded window
    the job has not yet measured against production. Present the chained restore as the primary path
    **and** retain a manual exit.
  - **But the retained exit must be truthful.** Both the summary and the runbook currently say
    *"end it immediately: `gh workflow run web-platform-release.yml -f bump_type=patch`"* — the
    pipeline this plan measured failing **9 consecutive times**. Point the manual exit at
    `scripts/registry-restore-from-ghcr.sh` (via a re-run of the restore job), not at a release.

### Phase 4 — records

- **ADR** (see [Architecture Decision](#architecture-decision-adrc4)).
- **ADR-096 amendment**, following the house convention (strike in place with `~~…~~` + a dated
  marker, never delete; content-anchored citations; end with an explicit `Status stays **Adopting**.`):
  - record the new authorization condition and why the old one could not be repaired;
  - **strike the stale escrow rationale.** Anchor it by content, not line number
    (`cq-cite-content-anchor-not-line-number`): the paragraph beginning *"Escrow deliberately
    omitted"*, whose reasoning is *"passphrase loss ⇒ recreate + re-fill from GHCR, so escrow buys
    nothing"*. That rests on the same premise struck earlier in the same section and has never been
    marked. **Strike it — but do NOT repair the conclusion in this PR.** Repairing it would rest the
    escrow-omission argument on a CI-mediated restore that, at merge time, has never once succeeded
    against production. Rebuilding an authorising premise on an untested capability is precisely the
    defect this PR exists to fix. Let the escrow conclusion stand on its independent ground, and
    make the repair contingent on the first successful A5/real-restore run;
  - **amend the COLD VEHICLE paragraph.** It enumerates *"the Sentry pull-path query"* among four
    never-executed live surfaces. After this rewrite that surface does not exist, and four new ones
    do (GHCR-read-from-CI under `packages: read`; the throwaway-zot rehearsal; the `/health` parse;
    the post-destroy real restore into a fresh prod zot over the tunnel). Leaving it unamended
    leaves the ADR naming a live surface that is gone;
  - **clause (g) stays open.** It already states *"Do not read the presence of #7277/#7278 as
    ownership"*. Closing #7277 does not give production a fallback. Explicit AC below.
- **Runbook** `registry-luks-recut-6929.md`:
  - delete the ⛔ banner; rewrite *"Why it is blocked"* as *"What authorizes a recut"*;
  - update the failure-mode table: remove the `REFUSING` and `UNOBSERVED` rows, add a row per new
    abort class, **and add a row per restore exit code** (`2` source unavailable, `3` sink
    unavailable, `4` verification mismatch, `5` credential unreadable, `6` unclassifiable) with the
    operator action for each. Six enumerated exit codes with one boolean consumer and no operator
    mapping is a contract nobody can act on. The runbook's *"If it finishes but the registry never
    comes back"* section lists two causes; **"the restore failed after the store was destroyed" is
    the highest-stakes new failure mode in the design and is not among them**;
  - rewrite *"The empty-store window"* around the chained restore, and replace the
    `web-platform-release.yml -f bump_type=patch` instruction (a pipeline measured failing 9×);
  - **rewrite cold-vehicle check 1.** It currently runs
    `doppler run -c prd_terraform -- bash tests/scripts/test-registry-pull-path-health.sh` and names
    *"a rotated `SENTRY_AUTH_TOKEN`"* as the failure mode. Both stop describing the gate. Add
    cold-vehicle checks for the four new live surfaces; check 5 (*"schedule the fire immediately
    before a planned release"*) is obsoleted by the chained restore;
  - **promote the stock-preflight caveat to the top — with the bypass warning attached.** Deleting
    the banner removes what currently stops an operator at line 5. The recut's own abort text and
    the runbook both then route them onward: *"if the type is unavailable in this region generally,
    use `registry-region-migrate` instead"* — a job with **no confirm token, no id-pin, no live
    posture probe and no D10** (ADR-096 accepted residual #6946). The promoted caveat must say so
    explicitly, or the banner's removal converts a hard stop into a signpost to the unguarded
    destroy path.

## Hypotheses

The task description contains the token `SSH` (in the constraint *"no SSH in runbooks"*), which
mechanically triggers the network-outage checklist. The checklist's L3→L7 ordering is answered
below rather than opted out of, because the plan does add a network dependency (CI→GHCR, CI→zot):

1. **L3 — firewall / allow-list.** Not implicated, with an artifact: the release pipeline's failure
   is at `copy_v` *after* the CF Tunnel bridge step succeeded (`bridge` is a distinct, earlier
   stage label that did not fire), and the 9 failing runs all reached the mirror step. Packets
   reach the origin. No `hcloud firewall` change is proposed.
2. **L3 — DNS / routing.** Not implicated: `app.soleur.ai/health` resolved and returned 200 with a
   JSON body during this planning session. Registry reachability from CI is via
   `cloudflared access tcp` to `registry.soleur.ai`, unchanged by this plan.
3. **L7 — TLS / proxy.** The CI→zot leg is plain HTTP over loopback into `cloudflared`
   (crane/cosign treat loopback as insecure by design); the CI→GHCR leg is HTTPS with default cert
   verification. Neither is modified. **A1's `NETWORK` classifier is the plan's own L7 probe** and
   aborts rather than guessing.
4. **L7 — application.** The failing component is zot itself, panicking in
   `pkg/scheduler.(*Scheduler).poolWorker` with `zot_oom_kills=0` — an application-layer fault, not
   a transport one. Diagnosing *which* scheduler task panics is **#7247's** work, not this plan's
   (see [Scope boundaries](#scope-boundaries-explicit)).

Ordering discipline is satisfied: no service-layer hypothesis is advanced ahead of the L3/L7 checks.

## Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The plan body contains `connection reset by peer` and `SSH`, so the checklist fires. Layer status,
each with an artifact rather than an assertion:

| Layer | Status | Artifact |
|---|---|---|
| **L3 — firewall allow-list** | **Verified not implicated.** | Release run `30988480437` logs `BRIDGE_OUTCOME: success` — the CF Tunnel bridge came up and reached the origin before the failure. Packets arrive. No `hcloud firewall` change is proposed by this plan, and the recut's own network path (CF Access service token → `cloudflared` → connector → `10.0.1.30:5000`) is unchanged. |
| **L3 — DNS / routing** | **Verified.** | `GET https://app.soleur.ai/health` resolved and returned a 200 JSON body during planning (2026-08-05). `crane digest ghcr.io/jikig-ai/soleur-web-platform:latest` resolved from the same network. |
| **L7 — TLS / proxy** | **Verified not implicated, and instrumented.** | CI→GHCR is HTTPS with default cert verification (a digest resolved successfully). CI→zot is plain HTTP over `127.0.0.1:5000` into `cloudflared` **by design** — crane/cosign treat loopback as insecure, and the TLS leg is the Access edge. Neither is modified. A1's `NETWORK` classifier and A5's degrade bucket are this plan's own L7 instrumentation: they abort or degrade rather than guessing. |
| **L7 — application** | **Verified — this is the fault layer.** | `Error: Patch "http://127.0.0.1:5000/v2/.../blobs/uploads/…": write: connection reset by peer` — the origin **reset an established, admitted connection mid-upload**. That is zot dying, not a packet-filter drop: a firewall block would refuse at connect, not reset mid-PATCH. Corroborated by the Go panic in `pkg/scheduler.(*Scheduler).poolWorker` with `zot_oom_kills=0`. |

**Ordering discipline satisfied:** no service-layer hypothesis is advanced ahead of the L3/L7
checks, and the L3 checks are answered from run artifacts, not from "obvious".

**The gap this leaves, named:** the reset is *consistent with* a crash-looping origin but does not by
itself prove the panic causes the reset. That is #7247's diagnosis, not this plan's — and it is
precisely why the chosen PASS condition reads **nothing** about zot's health. The gate's correctness
does not depend on the crash-loop's root cause being known.

## Downtime & Cutover (deepen-plan Phase 4.55)

**Trigger:** the plan does not itself apply Terraform, but it authorises an operation that
power-cycles and replaces a serving resource (`-replace` of `hcloud_server.registry` +
`hcloud_volume.registry` + its attachment) and takes production's **sole** container pull path
offline. The gate fires on the operation the plan gates.

**The offline-inducing operation and its surface.** The recut destroys the zot store volume and
replaces the host. During the window, no host can pull any image: not a reboot, not a replacement,
not a deploy. Already-running containers keep serving, so there is no *immediate* user-visible
outage — but the fleet is one restart away from one, with no rollback.

**Zero-downtime path — evaluated, and this is the honest answer.** A blue-green cutover exists in
principle and is strictly better: provision a **second** registry host with an encrypted volume,
refill it from GHCR via the same restore engine, cut the fleet's `ZOT_REGISTRY_URL` over, then
retire the plaintext original. No window at all. **It is out of scope because it *is* ADR-096
clause (g)'s second-mirror arm** (#6126, "still not a commitment to build one") — building it here
would be exactly the silent scope expansion this plan's boundaries forbid, and it is a multi-day
infrastructure build, not a gate fix.

**Residual downtime accepted, with the bound stated.** The recut therefore keeps a window, but this
plan changes its character in the way that matters:

| | Before this plan | After |
|---|---|---|
| Window length | Unbounded — *"nothing you control ends it"*; it lasts until someone dispatches a release | Bounded by the chained restore job, which runs automatically and fails loud |
| Ending mechanism | An operator manually dispatching `web-platform-release.yml` — a pipeline measured failing 9 consecutive times | `scripts/registry-restore-from-ghcr.sh`, rehearsed in the same run minutes earlier |
| Observability | A page that **cannot arrive** (the dark `ghcr-fallback` operand) | Per-exit-code `::error::` on the restore job + D11's heartbeat-transition poll |

**Per-stage verification and rollback.** Rollback of the destroy itself is impossible — that is the
premise. So the plan's compensating controls are all *pre*-destroy (A0–A5, which abort before
anything is lost) and *post*-destroy fail-loud (D11, then the restore job). The restore script is
required to be resumable specifically so a partial pass is recoverable by re-running rather than by
recovering state.

**Sign-off.** Accepting a bounded window on a `single-user incident` surface is a CPO sign-off item,
already required by the threshold. Scheduling remains as ADR-096 has it — fire immediately before a
planned release — though the chained restore makes that a preference rather than the load-bearing
mitigation it used to be.

## Architecture Decision (ADR/C4)

Detection fires: this plan changes **what authorizes an irreversible destroy of production's sole
pull path**, and introduces a new restoration path. That is a trust/authorization boundary change
and a new integration pattern.

### ADR

**New ADR, provisional ordinal `ADR-169`** — *"What authorizes destroying the sole pull path."*
Re-derived against `origin/main` at Phase 0: highest ordinal `ADR-168`, gaps at 144 and 167,
no local-only ordinals, and the corpus contains historical duplicates (027, 030, 031, 033, 038) so
`max+1` is the convention, not the only hazard. **This number is provisional**: ordinals have
collided three times recently and `adr-ordinals` is not a required check, so `/ship` must re-derive
it against a freshly-fetched `origin/main` immediately before merge. On renumber, sweep the whole
feature artifact set in the same edit —
`grep -rn 'ADR-169' knowledge-base/project/{plans,specs}/feat-one-shot-7277-d10-gate-pass-condition/`
plus the script headers, the runbook, the workflow comments and any AC naming the ordinal.

Content: the four candidates and why three were rejected; the independence criterion ("a gate on an
irreversible destroy may not depend on the component whose failure motivates it"); the fail-open
analysis per predicate; the two named residuals (A4 credential staleness; A2 not proving host-side
pull, per ADR-096 clause (f)).

Plus an **in-place amendment to ADR-096** (no new ordinal claimed) per Phase 4.

### C4 views

**This change HAS C4 impact.** All three of `model.c4` (624 lines), `views.c4` (62) and `spec.c4`
(54) were read in full for this plan — not grepped. The enumeration:

| Enumerated | Modeled today? | Action |
|---|---|---|
| External human actor | Operator fires the dispatch — already modeled. | None. |
| External system — **GHCR** | `ghcr = system "GitHub Container Registry" { #external … }`. | **Description must be corrected** — see falsified claims below. |
| External system — **GitHub / CI** | `github = system "GitHub"`, description *"Source control, CI/CD, issue tracking, and releases"*. There is **no dedicated CI/runner element**; CI behaviour lives entirely in `github -> …` edge labels. | Express the new behaviour as edges, not a new element. |
| External system — **Sigstore/Rekor** | `sigstore` exists; `github -> sigstore` edges already model keyless signing of the released image digest and the config bundle. | Extend an edge label only if Phase 0.3 lands on the re-signing arm. |
| Container / data store — **zot** | `zotRegistry = system "Self-hosted zot registry" { #selfhosted }`. **The store volume has no node of its own** (unlike `workspacesVolume`) — the object this recut destroys is not represented as an element. | Correct the description; do not invent a volume node in this PR. |
| Access relationship — **CI reads GHCR** | **MISSING.** There is exactly **one** `github -> ghcr` edge and it is push-only (`docker buildx push` + `crane copy`). No CI→GHCR *read* edge exists. *(An earlier draft of this table said "both `github -> ghcr` edges" — there is one. Corrected at plan review; the miscount is why the C4 edit must re-verify against the file rather than against this table.)* | **Add** an edge. |
| Access relationship — **CI writes zot** | **MISSING as a direct edge.** CI's dual-push is modeled only inside the `github -> tunnel` label. | Extend that label, or add a `github -> zotRegistry` edge — decide at work time; do not leave the restore path unmodeled. |

**Element descriptions this change falsifies, and must correct in the same edit:**

- `zotRegistry` — *"The 60 GB store volume re-fills ONLY from a fresh CI dual-push — **NOT from
  GHCR**."* A CI-mediated GHCR→zot restore makes this literally false. Adjacent: *"every
  recut/replace of this volume takes production's only pull path offline for the gap"* becomes
  conditional — the gap is now bounded by the chained restore's runtime, not by the next release.
- `ghcr` — *"It receives every image and can serve none."* Falsified the moment CI successfully
  pulls a digest from GHCR. And *"no zero-touch GHCR pull credential can exist"* is scoped by
  ADR-088 arm-b to **App installation tokens on hosts**, but reads as absolute; it must be scoped
  explicitly or it will be quoted against this design.
- `hetzner -> ghcr` (the DEAD EDGE) — *"Every traversal ends `image_pull_failed`"* stays **TRUE**
  and must **not** be deleted. But *"Do NOT read this edge as redundancy … there is none"* becomes
  misleading once a CI-mediated restore exists: redundancy exists, off this edge and not at
  host-pull latency. Scope the sentence to the host edge.
- ~~`github -> ghcr` — describes GHCR as *"(authoritative)"* with *"a best-effort zot mirror"*,
  inverted relative to zot's "SOLE pull path" description; worth correcting.~~ **RETRACTED at plan
  review.** That edge is not about the web-platform image: its subject is the **config-refresh
  bundle**, published *"to GHCR (authoritative) + a best-effort zot mirror (continue-on-error,
  GHCR-direct host pull in v1)"* — and the live `inngest -> ghcr` pull edge confirms the bundle is
  pulled GHCR-direct. The description is **correct for its subject**, and "correcting" it would make
  the model wrong. Left untouched.
- `zotRegistry` also carries a **stale server type** — it says the host is sized `cx33`, while
  `variables.tf` records the #6497/#6463 revert to `cx23`. Correct it in the same edit: the cx23
  fact is load-bearing for the `stock_preflight_gate` blocker this plan promotes into the runbook.

**The DEAD EDGE is load-bearing evidence FOR this design, not against it.** It is `hetzner -> ghcr`
— **host** → GHCR. Its own closing sentence names the blocker as *"a non-personal GHCR pull
credential, which ADR-088 arm-b shows cannot exist today"* — a statement about the **host's**
credential class. A CI job's `GITHUB_TOKEN` in the `jikig-ai/soleur` repo context is a different
class, and nothing in `model.c4` asserts CI cannot read GHCR. (The model already carries a live
GHCR *pull* edge, `inngest -> ghcr`, as ADOPTING — an existing internal tension worth citing.)

**`views.c4` needs no `include` edit** — `ghcr`, `zotRegistry` and `github` all already appear in
both the `context` view and the `containers of platform` view, so new edges between them render
without a views change.

**The validation gate is NOT the one the generic mandate names.**
`apps/web-platform/test/c4-code-syntax.test.ts` tests the CodeMirror tokenizer and
`c4-render.test.ts` tests `renderC4Model`'s CLI lifecycle — **neither validates model content**.
The gate that will go red is `plugins/soleur/test/c4-model-freshness.test.sh`, run in CI's
`test-scripts` job via `bash scripts/test-all.sh scripts`: it renders the `.c4` sources with
`likec4@1.50.0` and **byte-diffs the committed
`knowledge-base/engineering/architecture/diagrams/model.likec4.json`**. Any `model.c4` edit must
ship a re-rendered `model.likec4.json` in the same commit, with the likec4 version matching the pin
guarded by `c4-likec4-version-pin.test.ts`. Do not casually alter the cron-monitor counts in the
`github -> sentry` edge label — `plugins/soleur/test/c4-count-parity.test.sh` (#7209) gates them.

### Sequencing

No sequencing gap: the decision is true the moment the gate ships. The ADR is `accepted`, not
`adopting`.

## Infrastructure (IaC)

No new infrastructure. The plan adds no server, service, cron, vendor account, DNS record, TLS
cert, secret, firewall rule or monitoring webhook. It consumes existing Doppler secrets read-only
and existing Terraform-declared endpoints.

**No `terraform apply` is prescribed, targeted or otherwise.** The registry host carries a standing
pending-REPLACE in any untargeted plan (`user_data` is ForceNew with no `ignore_changes`), and a
live 2026-08-05 probe shows `cx23` orderable in `nbg1-dc3` but **not** `hel1-dc2` where this host
runs — a recreate there fails on stock. The recut dispatch's own `-replace`/`-target` set is
untouched by this plan.

**Sentry Terraform is deliberately not edited** (see Residuals) — so no `apply-sentry-infra.yml`
run is required by this PR.

## Encryption Posture

```yaml
at_rest:
  - store: throwaway zot rootDirectory in the GitHub Actions runner
    mechanism: none-required-ephemeral
    evidence: created under the runner's per-job workspace, destroyed with the runner VM at job end
    defends_against: nothing (no persistence)
    does_not_defend: a compromised runner during the job window can read the copied public-ish image layers
    disclosed_as: not a data store; no user data, no secrets at rest — image layers only
    live_verification: the rehearsal step's cleanup asserts the directory is removed before job end
  - store: none other
    mechanism: n/a
    evidence: the plan creates no persistent store; the digest manifest is a job-scoped artifact, not a durable record
    defends_against: n/a
    does_not_defend: n/a
    disclosed_as: n/a
    live_verification: n/a
in_transit:
  - connection: CI runner -> ghcr.io (crane ls / digest / copy)
    tls: TLS 1.2+
    cert_verification: on
    does_not_defend: does not prove the *host* can reach GHCR (that edge is dead per #7071)
    disclosed_as: pre-existing edge, already used by the release mirror's source half
  - connection: CI runner -> registry.soleur.ai (cloudflared access tcp -> zot)
    tls: TLS to the Cloudflare Access edge; the runner-local hop is plain HTTP over 127.0.0.1:5000 by design
    cert_verification: on (Access edge); n/a for the loopback hop
    does_not_defend: does not prove a host can pull over the private NIC with ZOT_PULL_* (ADR-096 clause (f))
    disclosed_as: pre-existing edge, identical to the release mirror's sink half
  - connection: CI runner -> throwaway zot on 127.0.0.1
    tls: none
    cert_verification: n/a
    does_not_defend: nothing; loopback within one ephemeral VM
    disclosed_as: rehearsal only, never carries production credentials
exception: none
```

## Observability

```yaml
liveness_signal:
  what: the D10 gate's own per-predicate verdict lines and the restore script's machine-readable summary, both in the dispatch run log and the GitHub step summary
  cadence: per dispatch (this is an operator-fired workflow, not a scheduled job)
  alert_target: the workflow run's failure status; the recut is operator-initiated and watched
  configured_in: .github/workflows/apply-web-platform-infra.yml (job registry_luks_recut) and scripts/registry-pull-path-health.sh
error_reporting:
  destination: GitHub Actions annotations (::error::) plus non-zero job exit; the chained restore step is fail-loud
  fail_loud: true
failure_modes:
  - mode: inventory empty or below the floor (the gate proves nothing)
    detection: A3's three-equal-counts assertion plus the source-level arity self-check
    alert_route: ::error:: + job failure; asserted by a positive-control row in the test suite
  - mode: GHCR unreadable from CI (source gone)
    detection: A1 classifier tokens NOTFOUND / DENIED / NETWORK / UNKNOWN
    alert_route: ::error:: naming the classified cause + job failure
  - mode: could-not-measure (crane missing, malformed output, /health unreachable)
    detection: the UNKNOWN default arm, evaluated before any comparison
    alert_route: ::error:: + job failure; never renders as a PASS
  - mode: restore silently loses signatures, so restored images fail cosign verify at pull time
    detection: A2 verifies the signature path per the Phase-0 decision rule; ci-deploy emits cosign_verify_event on the host side
    alert_route: ::error:: in the gate; cosign_verify_event -> Sentry from the host
  - mode: recut succeeds, registry never comes back
    detection: D11 registry-heartbeat-poll (requires a heartbeat transition, not a level)
    alert_route: job failure + the existing Better Stack heartbeat
  - mode: chained real restore fails after a successful recut (empty store persists)
    detection: the restore script's exit code, branched per code (2 source / 3 sink / 4 mismatch / 5 credential / 6 unclassifiable) by the separate needs-chained restore job
    alert_route: a per-code ::error:: naming the operator action + job failure, so the empty-store window can never end silently
  - mode: recut job cancelled at timeout mid-restore, leaving a half-populated registry and no summary
    detection: eliminated by construction — the multi-GB restore no longer runs inside registry_luks_recut's mutex-holding 30-minute budget, and the restore script is resumable
    alert_route: the restore job's own failure status; the recut job's Dispatch summary still emits the new volume id
  - mode: sink credential measured dead before the destroy
    detection: A4's live CF-Access grader (zot_mirror_verdict = stale)
    alert_route: ::error:: + gate abort; nothing is destroyed
logs:
  where: GitHub Actions run log + step summary; host-side pull events continue to land in Sentry (feature:supply-chain op:image-pull) and journald -> Vector -> Better Stack
  retention: GitHub Actions default; Better Stack per its existing table retention
discoverability_test:
  command: gh run view <run-id> --log --job "registry_luks_recut" | grep -E 'registry-(pull-path-health|restore-from-ghcr):'
  expected_output: one classified verdict line per predicate (A0..A4) and one summary line per restored reference — no SSH
```

## Acceptance Criteria

### Pre-merge (PR)

1. `grep -c "no valid PASS condition" scripts/registry-pull-path-health.sh` returns **0**, and the
   file still exists at that exact path (a deleted file makes this grep error, not return 0).
   **Self-reference trap:** the rewritten header will want to explain its own history, and the
   literal phrase is the natural way to do it. It must not appear anywhere in the file — not in a
   comment, not in a quoted retraction. Refer to it as *"the 2026-07-30 unconditional refusal"*.
   The runbook's done-signal is a whole-file count, not a scope-limited one.
2. The ⛔ blocked-state banner is deleted from
   `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`, and
   `grep -c "THIS DISPATCH CANNOT CURRENTLY BE FIRED" <runbook>` returns 0.
3. The runbook names the **remaining** blocker (`stock_preflight_gate` / `cx23` availability, #6460)
   so the banner's removal does not create a false fireability claim. Verified by a content grep on
   the file — not a positional one; where the sentence sits is a style question, whether it is
   present is the criterion.
4. **THE criterion — state it first when reporting.** `tests/scripts/test-registry-pull-path-health.sh`
   contains an asserted **green row**: `rc == 0` on the all-good fixture. Verified by a grep of the
   suite source for the green-fixture case name. *A suite with 23 green assertions and no green row
   is exactly how an unpassable gate shipped. Everything else here is secondary to this.*
5. The suite contains a positive control for **each of the ten** abort classes enumerated in
   Phase 2, and each asserts its specific classified message, not a bare non-zero rc. Plus a row
   pinning A5's abort/degrade asymmetry in **both** directions: credential-rejected → abort,
   connection-reset → degrade-and-proceed.
6. `bash tests/scripts/test-registry-restore-from-ghcr.sh` is registered in `scripts/test-all.sh`
   (grep the runner for the suite path) — `scripts/lint-orphan-test-suites.sh` covers
   `scripts/*.test.sh` only and will not catch an unregistered `tests/scripts/test-*.sh`.
6b. The new script's `CRANE_SHA256` is covered by the pin-parity check in
   `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`. **Note the shape before
   editing:** that check asserts on the *assignment* (`^[[:space:]]*CRANE_SHA256="<sha>"`,
   deliberately — *"a bare whole-file match is satisfied"* otherwise) and iterates a variable named
   `$wf`, i.e. it is currently **workflow-scoped**. Adding a `.sh` path means widening the iterated
   set, not just appending a filename. The repo already carries three near-identical
   `install_crane` / `CRANE_VERSION` / `CRANE_SHA256` blocks guarded only by this grep; an
   unregistered fourth copy drifts silently.
7. `bash scripts/test-all.sh scripts` is green. (This subsumes the "passes" half of AC4 and AC6;
   those criteria carry only their distinctive greps.)
8. The Sentry arm is gone, asserted mechanically rather than by judgement:
   `grep -c 'sentry\.io\|SENTRY_AUTH_TOKEN\|WATCHED\|sentry_count' scripts/registry-pull-path-health.sh`
   returns **0**. (The header MAY still explain *why* `ghcr-fallback` was dropped — a grep for that
   token alone would false-fail a correct file, which is the trap AC1 documents.) The D10 workflow
   step no longer reads `SENTRY_AUTH_TOKEN`.
9. No `docker pull` appears in **any** verification path — the local-image-cache fail-open. Scope is
   all three surfaces, not just the gate:
   `grep -c 'docker pull' scripts/registry-pull-path-health.sh scripts/registry-restore-from-ghcr.sh`
   is 0 for both, and the workflow's throwaway-zot verification step uses `crane`, not `docker`.
10. The gate's verdict switch has no default-pass arm: the last `case` arm aborts. Asserted by a
    structural grep in the suite.
11. The `GITHUB_ACTIONS`-guarded `::add-mask::` property survives **in the rewritten suite** — the
    comments-stripped structural test is carried forward, not dropped. (Phase 2 rewrites that suite,
    so "the existing test" has no referent at merge; the criterion is that the assertion survives
    the rewrite.)
12. **All four** stale `ghcr-fallback` sites in `.github/workflows/apply-web-platform-infra.yml` are
    corrected — the D10 comment block, the resume-path skip notice, the post-destroy ordering
    constraint, and the summary's "PAGES" claim. Three of them are falsified by the **gate** change,
    not by the emitter, so the "emitter untouched ⇒ these stay correct" reasoning does not cover
    them. `actionlint` is clean and every edited `run:` block passes `bash -c` extraction (do **not**
    run `bash -n` on the YAML).
13. The recut job declares the permissions Phase 0 established **and wires `DOPPLER_TOKEN_PRD`**
    (referenced zero times in this workflow today; `secrets: inherit` does not apply because this is
    not a reusable-workflow call). The gate is split into an **unconditional PREPARE** step (crane
    install + inventory derivation + pinned-manifest artifact) and a **conditional VERDICT** step
    still carrying `if: steps.posture.outputs.probe_result != 'absent'`, so the resume arm has
    restore inputs. The skip's *stated reason* in the comment is rewritten (the old one cites
    `ghcr-fallback` events the new gate never reads).
14. The real restore runs in a **separate job chained by `needs:`**, invoking
    `scripts/registry-restore-from-ghcr.sh` without `continue-on-error`, with an explicit `if:` that
    covers the resume arm. `registry_luks_recut`'s `timeout-minutes: 30` is unchanged and no multi-GB
    transfer runs inside it. **Amended at work time** (see [`--rehearse` re-scoped](#--rehearse-re-scoped--the-flag-is-deleted-work-phase-deviation-2026-08-05)):
    the original clause read "without `--rehearse`", which is trivially true against a script that
    has no such flag. The criterion it was reaching for is the anti-drift one, so it is now: the
    rehearsal step and the real-restore step invoke the **same script path** and differ in exactly
    `--target` and the credential environment — asserted by a suite row.
14b. The restore job carries an explicit `timeout-minutes`, and a restore failure or timeout is
    fail-loud (per-exit-code `::error::` + job failure). Where the wall-clock is unmeasured
    (Phase 0.4 residual), no artifact may state or imply a numeric bound that was never measured.
    *(CPO sign-off condition 1.)*
15. A4 invokes the live CF-Access credential grader (`scripts/zot-mirror-diagnosis.sh`
    `zot_mirror_verdict`), not a non-emptiness check: `grep -c 'zot_mirror_verdict\|zot-mirror-diagnosis'`
    in the gate or its workflow step is ≥ 1, and a suite row asserts `stale` → abort.
16. Every restored digest has a signature present in the target, asserted by the rehearsal — and
    `grep -c 'IMAGE_VERIFY_MODE.*warn' <plan-or-ADR>` shows the `warn`-mode dependency is declared,
    not that an unsigned-restore arm exists. There is no unsigned fallback arm.
17. ADR-096 carries the amendment. **Clause (g) still reads as open debt** —
    `grep -c "unowned constraint" <ADR-096>` returns **2** (the measured pre-change value, both
    inside clause (g)) and no added line asserts the debt is resolved. The escrow paragraph is
    struck in place with a dated marker and its conclusion is **not** repaired in this PR.
18. C4: `model.c4` carries the corrected `zotRegistry` description (including the `cx33` → `cx23`
    server-type fix), the scoped `ghcr` and `hetzner -> ghcr` wording, and the new CI→GHCR-read and
    CI→zot-restore relationships; the `github -> ghcr` config-bundle edge is **unmodified**;
    `grep -c "NOT from GHCR" model.c4` returns **0** (measured pre-change value: 1);
    `model.likec4.json` is re-rendered with `likec4@1.50.0` in the same commit and
    `bash plugins/soleur/test/c4-model-freshness.test.sh` is green.
19. The runbook carries a failure-table row per restore exit code (2/3/4/5/6) with an operator
    action for each, a row for *"the restore failed after the store was destroyed"*, a rewritten
    cold-vehicle check 1, and a stock-preflight caveat that names `registry-region-migrate` as an
    **unguarded** bypass. No remaining instruction points the operator at
    `web-platform-release.yml -f bump_type=patch` as the way to end the empty-store window.

### Post-merge (operator)

None. Every step above is executable in-session or in CI.

**Automation-feasibility statement:** the recut *dispatch* is deliberately not fired by this PR —
that is a separate operator-gated `workflow_dispatch` and is out of scope by instruction, not by
automation limitation.

## Plan Review Revisions

Four reviewers ran against plan v1 (`architecture-strategist`, `spec-flow-analyzer`,
`code-simplicity-reviewer`, `cto`) — the escalated panel for `single-user incident`. All findings
below are **mechanical/correctness class** and were auto-applied. Recorded because several of them
are exactly the defect the plan exists to prevent, committed by the plan itself.

| # | Finding | Applied |
|---|---|---|
| R1 | **A4 verified a proxy.** "Non-empty secret" stood in for "the credential works", and the plan asserted this was *"not eliminable pre-destroy"*. **False** — `scripts/zot-mirror-diagnosis.sh` / `reusable-release.yml` already grade the registry-push CF Access token **at the Access edge**, with no zot dependency. | A4 rewritten to run that grader; `stale` → ABORT. |
| R2 | **No predicate observed the sink.** "Must not depend on the failing component" had been collapsed into "must not look at it", leaving a gate that authorises destroying a sink it has never observed. | **A5 added** — pre-destroy authenticated write to live prod zot. |
| R3 | **A5's first-draft verdict table put `connection reset` in ABORT** — the literal signature of the incident (run 30988480437). Would have deadlocked the gate today. | Boundary redrawn: only **authorisation** and **correctness** failures abort; availability failures degrade. |
| R4 | **A0 reimplemented zot's retention policy and transcribed it wrongly**, dropping the `sha256-.*` (cosign signature) rule; and restoring ~11 tags/repo is the maximal-pressure case for the out-of-order eviction the repo already warns about. | Replaced with **derive-from-production's-pins**. |
| R5 | **Signatures were an optional arm.** Phase 0.3 offered "don't sign; `warn` mode makes it non-fatal" — relaxing a supply-chain control because a different control is disabled, with nothing going red. | Arm **deleted**; per-digest signature presence asserted; `warn`-mode declared as a named dependency. |
| R6 | **A2 verified with `crane digest`** — a manifest read, which the repo already records as not proving blob presence (`blob unknown` at host pull with green parity). | Switched to `crane validate --remote`; the loopback throwaway also answers that check's dark-launch open question for free. |
| R7 | **AC13 and AC14 were jointly unsatisfiable.** Crane install + inventory derivation sat inside the D10 step, which is skipped on the resume arm — the arm that most needs a restore. | PREPARE/VERDICT split; restore `if:` made explicit. |
| R8 | **`timeout-minutes: 30` is a deliberate mutex budget** and v1 spent it on two multi-GB restores; a cancellation leaves a half-populated registry and suppresses the summary that emits the new volume id. | Real restore moved to a **separate `needs:`-chained job**; script made resumable; Phase 0.4 now budgets the full set. |
| R9 | **Deleting the banner routes the operator to `registry-region-migrate`**, which has no confirm token, no id-pin, no posture probe and no D10. | #6946 decided now (not self-contained — no posture step to feed D10); compensated in the runbook's promoted caveat. |
| R10 | **Two false C4 claims.** There is **one** `github -> ghcr` edge, not two; and its "(authoritative)" wording is **correct for its subject** (the config-refresh bundle) — "correcting" it would have made the model wrong. | Both retracted in place; a stale `cx33` server type found and added. |
| R11 | **Runbook cold-vehicle check 1 is falsified** by the rewrite (it names a rotated `SENTRY_AUTH_TOKEN`), and both runbook and summary tell the operator to end the window with a pipeline measured failing 9×. | Added to the edit list with ACs. |
| R12 | **The ADR-096 escrow repair rested on an untested capability** — rebuilding an authorising premise on something that has never succeeded against prod. | Strike only; repair made contingent on a first successful real restore. |
| R13 | AC ceremony (`AC15`–`AC20` in v1): ordinal greps, "file didn't change" assertions, plan-self-validation, an AC that could not fail (*"reflects the corrected wording"*), and one that **could not pass** (it cited a `spec.md` the plan's own lane note says does not exist). | Cut or given measured expected values. 21 ACs → 19, with the green row promoted to first. |
| R14 | A fourth unguarded copy of the `install_crane` / `CRANE_SHA256` spine. | Registered in the existing pin-parity test (AC6b). |
| R15 | Cheap gates after expensive ones — `stock_preflight_gate` aborts *after* a multi-GB rehearsal. | Pre-rehearsal availability probe added to Phase 3. |

**Reviewer-roster note for the PR:** because the risk is fleet-wide and infra-shaped rather than
per-user, add `observability-coverage-reviewer` (fail-loud on the chained restore; no-SSH runbook),
`platform-strategist` (the mutex/timeout budget) and `silent-failure-hunter` (the six-code exit
contract) to the review panel alongside the threshold-mandated `user-impact-reviewer`.

**One reviewer claim checked and NOT applied:** that `install_crane` is only version-pinned, not
SHA-pinned. It is SHA-pinned — `reusable-release.yml` carries
`CRANE_SHA256="c14340087103ba9dadf61d45acd20675490fd0ccbd56ac7901fc1b502137f44b"` and a
`sha256sum -c -` verification step. The plan's wording stands.

## Domain Review

**Domains relevant:** Engineering (CTO) **and Product (CPO)**. An earlier revision of this line read
*"Product NOT relevant"* on the strength of the mechanical UI-surface override not firing. That was
a **contradiction with this plan's own frontmatter** (`requires_cpo_signoff: true`) and it is
corrected here: the UI-surface test is the trigger for a *UX* review, not for a
`brand_survival_threshold: single-user incident` sign-off, which turns on user-facing blast radius
rather than on whether a `.tsx` file is touched. The UI-surface override still does not fire —
`## Files to Create` and `## Files to Edit` contain no `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any other UI-surface path — so no `.pen` wireframe is required and
`ux-design-lead` is correctly not invoked. Legal, Marketing, Finance,
Sales, Operations, Support: not relevant (no vendor spend change, no user-facing copy, no new
recurring cost — the plan consumes existing Doppler secrets and existing GitHub Actions minutes).

### Engineering (CTO)

**Status:** reviewed (assessment folded into Risks, Scope boundaries and the Hypotheses section).

### Product/UX Gate

**UX half:** not applicable — the mechanical UI-surface override did not fire, so no `.pen`
wireframe is required and `ux-design-lead` is correctly not invoked.

**Product half — CPO sign-off (2026-08-05): SIGNED OFF, with seven binding conditions.**
Scope: this authorizes *shipping the gate*, **not** *firing the recut*.

*Rationale (CPO).* The status quo is not the safe option — it is an unbounded empty-store exposure
that has already begun: production frozen on the 2026-08-04 build across 9 consecutive failed
releases, zot at `pcent=89` and climbing with ~6.5 GB headroom, and the only mechanism that would
end that state today is an operator dispatching the very pipeline measured failing 9 of 9 times.
This plan does not create the empty-store risk; it converts an unbounded, operator-dependent,
unobservable window into a bounded, automatic, fail-loud one. Blocking on the zero-downtime
blue-green path (#6126 / ADR-096 clause (g)) would hold the *worse* version of the same risk for a
multi-day build while the disk fills. The plan is signable **specifically because of** A5's
abort/degrade boundary and A4's `live` arm; without those it would be the same deadlock in new
clothes.

*Conditions — all must hold in the shipped work or the sign-off lapses:*

1. **The window gets a number.** The restore job carries an explicit `timeout-minutes`, and restore
   failure or timeout must page. Where Phase 0.4's wall-clock is unmeasured, say so rather than
   implying a bound that was never measured.
2. **Phase 0.9 is a blocker, not a degrade** — green, or a named blob-completeness fallback recorded
   before Phase 2. Same standing for 0.2/0.3/0.4/0.7. *(0.9 resolved green at work time; 0.3 and 0.7
   resolved; 0.2 and 0.4 carried as named residuals with their failure mode shown to be a safe
   abort — see `phase-0-probe-evidence.md`.)*
3. **AC4 (asserted green row) and A3's source-level `FLOOR` both ship.** A gate that cannot pass
   repeats the defect; a gate that passes on an empty inventory is worse than the one replaced.
4. **The four unenumerated user-facing consequences are added to `## User-Brand Impact`** and, where
   operator-facing, to the runbook. *(Applied — see that section.)*
5. **The recut is not dispatched by this PR**, and AC3 holds: deleting the banner must not let the
   runbook read as fireable while `stock_preflight_gate` / `cx23`-in-`hel1-dc2` still denies it.
6. **The `IMAGE_VERIFY_MODE=warn` dependency is declared in the ADR.** A future `warn`→`enforce`
   flip voids this sign-off's calculus and requires re-signing.
7. **Scope stays inside the stated boundaries.** Any expansion into ADR-096 clause (g), the second
   mirror, or `registry-region-migrate` voids the sign-off.

*Roadmap note (not scope here):* the blue-green second mirror is the right destination, not the
right next step. Once the recut lands and the pipeline unblocks, #6126 is what removes this whole
class of decision — it should not stay a non-commitment indefinitely.

### GDPR / Compliance Gate (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor`
before merging.**

**Invocation reason:** trigger (b) — the plan declares `brand_survival_threshold: single-user
incident`. The canonical regulated-data regex
(`^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)`)
matches **zero** files in `## Files to Create` / `## Files to Edit`. Triggers (a), (c) and (d) do
not fire: no LLM/external-API processing of operator-session data, no new cron reading
`learnings/` or `specs/`, no new artifact distribution surface.

**Findings:** no `Critical` and no `Important` findings. The plan introduces no personal data, no
schema column, no FK to `users`, no new non-EEA vendor, and no special-category field. The only
data crossing a boundary is OCI container-image content (`crane copy` GHCR→zot).

- `Suggestion` — **Art. 32 security of processing.** The gate and the restore script both handle
  live production credentials (`ZOT_PUSH_TOKEN`, a Cloudflare Access service-token pair, a Doppler
  token). The plan already carries the mitigation as an acceptance criterion: the existing
  `GITHUB_ACTIONS`-guarded `::add-mask::` property must survive the rewrite, asserted by a
  comments-stripped structural test (AC11), and the new restore script must not echo credentials.
  No further action; recorded so the concern is visible rather than assumed.

No `compliance-posture.md` row and no `compliance/critical` issue are required.

## Test Strategy

Runner: plain `bash` suites under `tests/scripts/`, matching the existing convention. No new test
framework, no new dependency. `scripts/test-all.sh` discovery is a **manual** `run_suite` list —
register the new suite explicitly.

The suite's contract, stated so a reviewer can check it: **prove the gate can go red, per cause,
before proving it goes green** — and prove it goes green at least once. The current suite honours
only the first half, which is exactly how an unpassable gate shipped green.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The rewrite ships a *new* gate that cannot pass (the same class of defect). | AC4: a mandatory asserted green row on the all-good fixture. |
| The rewrite ships a gate that passes vacuously on an empty inventory. | A3 + the source-level arity self-check + a positive-control test row. |
| A "could not measure" outcome reads as safe. | Every classifier's default arm is `UNKNOWN → abort`, evaluated before any comparison; asserted structurally. |
| Local Docker cache makes the rehearsal green while the registry round-trip is broken. | Verification uses `crane` against the registry HTTP API only; `docker pull` is banned from the verification path by AC9. |
| Deleting the banner makes the runbook claim a fireability `stock_preflight_gate` still denies. | AC3. |
| `registry-region-migrate` remains an unguarded bypass to the same creates (#6946). | Named in the ADR; disposition in Scope boundaries. |
| The dark `ghcr-fallback` Sentry alert survives this PR. | Named residual with a tracker; compensated by the chained restore, which bounds the window the alert was supposed to page on. |
| ADR ordinal collision. | Re-derived at ship against a freshly-fetched `origin/main`, with a whole-artifact sweep on renumber. |

## Scope boundaries (explicit)

- **ADR-096 clause (g) is NOT expanded into.** This plan builds a *CI-mediated* restore. Clause
  (g)'s two named remedies are a zero-touch-mintable GHCR **pull** credential and a **second
  mirror**; this is neither. Clause (g) stays open and #6126 remains the second-mirror tracker.
  What does change is that "re-fill from GHCR" stops being a retracted premise and becomes a tested
  capability *for CI* — which is why the ADR-096 escrow paragraph can be repaired rather than
  merely struck.
- **`zot_last_err` tail widening stays with #7247** — deliberately, not silently. The chosen PASS
  condition reads nothing about zot's health, so the truncated Go panic header has no bearing on
  the gate. Folding it in would mix a registry-host diagnostic into the PR whose correctness is
  most load-bearing, and it lands on a different surface with a different deploy path (it only
  takes effect on a host rebuild — which is what the recut does, so it is naturally #7247's or a
  follow-up's payload, sequenced *after* this gate exists).
- **The `ghcr-fallback` emitter and its Sentry rule are not re-plumbed here — and the reason is
  measured, not preference.** The acceptance criterion is satisfied by dropping the operand from
  the gate. Hoisting the emit above the GHCR attempt was investigated and rejected on three
  findings:
  1. **It would silently invert a documented semantic split.** `issue-alerts.tf` states the tag's
     contract explicitly — *"`ghcr-fallback` means 'zot missed but GHCR served' … a `local-cache`
     event means NEITHER registry served, a categorically different (and worse) condition."*
     Hoisting redefines `ghcr-fallback` as merely "zot missed", re-merging by stealth the very
     distinction `local_cache_reload_rate` was split out to preserve — **with no `.tf` diff for a
     reviewer to catch it**, because the rules match on tag key/value only and never on message
     text.
  2. **It would falsify a mid-incident operator instruction with no test to catch it.**
     `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` defines the signal as
     *"a host attempted zot and the pull failed, then fell back"* and uses it as a revert-decision
     predicate. That prose goes wrong on a hoist and nothing in CI notices.
  3. **`apps/web-platform/infra/sentry/` is applied FULL-ROOT with no `-target=`, automatically on
     push to `main`.** Any `.tf` follow-on lands unreviewed-by-plan on merge.

  Disposition: **fix inline only the false "this window PAGES" claim** in the dispatch summary (a
  promised page that cannot arrive is worse than silence), and file/reference a tracker for the
  emitter + alert as the #7248 sibling class. The compensating control for the dark alert is the
  chained restore, which *bounds the very window the alert was supposed to page on*.
- **`registry-region-migrate` (#6946) — decided NOW, not deferred to work Phase 0.** The evidence is
  already in hand and the answer is *not self-contained*: the new D10 verdict consumes
  `steps.posture.outputs.probe_result`, and `registry_region_migrate` has **no posture step and no
  volume-id input to probe with** (it carries only the sourced `registry_region_migrate_gate` plus
  `stock_preflight_gate`, and its budget is `timeout-minutes: 20`). Wiring D10 there means also
  giving it a posture probe and an id-pin — a materially larger change to a second destroy path,
  inside the PR that re-authorises the first one. **Scope out, and compensate in prose:** the
  runbook's promoted stock-preflight caveat must state that the documented workaround has none of
  the recut's guards (see Phase 4). Add a note to #6946 recording that #7277 tightened the recut
  while this bypass stayed open, so the residual is re-evaluated rather than quietly inherited.
- **`scheduled-zot-restart-loop.yml`'s auto-filed issue bodies still assert the retracted premise
  — named, not fixed here.** Its private-NIC remediation body tells a mid-incident operator
  *"Deploys still succeed via the ADR-096 GHCR atomic fallback"* and instructs them to gate a host
  replace on `--grep ghcr-fallback --grep local-cache`. Both are the #7071 retraction: the fallback
  is dead and `ghcr-fallback` cannot fire, so that check reads CLEAN unconditionally and the
  operator fires a replace *"blind on an already-doubly-degraded pull path"* — the exact failure the
  paragraph warns against. This is a different workflow, a different dispatch
  (`registry-host-replace`), and outside #7277's scope; it is recorded here so it is not lost, and
  belongs with the emitter/alert tracker. The identical claim **is** fixed inline in the recut
  summary because that file is already being edited (edit-locality, not inconsistency).
- **The recut is not dispatched.** No `gh workflow run apply-web-platform-infra.yml` appears in any
  deliverable.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 64 issues; none of
their bodies mention `scripts/registry-pull-path-health.sh`,
`knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`,
`tests/scripts/test-registry-pull-path-health.sh`, `apps/web-platform/infra/ci-deploy.sh`,
`.github/workflows/apply-web-platform-infra.yml`, or `ADR-096`.

## Files to Create

- `scripts/registry-restore-from-ghcr.sh`
- `tests/scripts/test-registry-restore-from-ghcr.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md` *(ordinal provisional)*

## Files to Edit

- `scripts/registry-pull-path-health.sh` — rewrite the verdict (in place, same path).
- `tests/scripts/test-registry-pull-path-health.sh` — rewrite the contract rows; add the green row.
- `scripts/test-all.sh` — register the new suite next to the existing D10 entry.
- `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` — add the new script to the
  `CRANE_SHA256` pin-parity list so the fourth copy of the crane spine cannot drift silently.
- `.github/workflows/apply-web-platform-infra.yml` — job permissions; the D10 step; a post-D11
  chained restore step; correct the false "PAGES" summary claim.
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — delete the banner;
  rewrite the blocked section, the failure table and the empty-store window; promote the
  stock-preflight caveat.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
  — in-place amendment; strike the stale escrow rationale; leave clause (g) open.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — correct the `zotRegistry` and
  `ghcr` descriptions; scope the `hetzner -> ghcr` DEAD-EDGE "no redundancy" sentence to the host
  edge; add the CI→GHCR-read and CI→zot-restore relationships. `views.c4` and `spec.c4` need **no**
  edit (all three elements are already included in both views).
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` — re-render with
  `likec4@1.50.0` in the same commit, or `plugins/soleur/test/c4-model-freshness.test.sh` goes red.

### Files to review-before-editing (touched by the same tag/vocabulary, likely unchanged)

`.github/workflows/apply-web-platform-infra.yml` also references `ghcr-fallback` at the resume-path
skip notice, a post-destroy ordering constraint, and the summary; `.github/workflows/scheduled-zot-restart-loop.yml`
greps both signals; `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` uses the
tag as a revert predicate. Because the emitter is **not** hoisted, all of these should remain
correct — confirm rather than assume.

## Related

- #7277 — this issue
- #7247 — the crash-loop that exposed it; owner of the `zot_last_err` tail widening
- #7071 — the change that retracted the premise
- #6929 — the recut vehicle
- #6946 — the `registry-region-migrate` bypass residual
- #6126 — the second-mirror arm of ADR-096 clause (g)
- #7278 — the missing in-place restart lever (usually what you actually wanted)
- #6460 — `cx23` availability, the remaining blocker after this one
