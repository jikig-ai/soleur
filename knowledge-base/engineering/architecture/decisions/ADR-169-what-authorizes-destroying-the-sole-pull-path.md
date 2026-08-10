# ADR-169 — What authorizes destroying the sole pull path

- **Status:** accepted
- **Date:** 2026-08-05
- **Issue:** #7277
- **Supersedes:** the authorization condition recorded in ADR-096 for `registry-luks-recut` (that
  ADR is amended in place, not replaced)
- **Related:** ADR-087 (deploy-time signature verification), ADR-088 arm-b (GHCR pull credentials
  on hosts), ADR-096 clause (f) and clause (g), #7071, #7247, #6929, #6946, #6126, #6460

## Context

`registry-luks-recut` destroys the volume holding production's **only** container image store and
rebuilds it encrypted. The destroy is irreversible: there is no snapshot, no backup, no second
mirror and no export anywhere in the estate — `crane copy "${ZOT}`, `crane pull`, `crane export`
and `docker save` all return zero code hits.

Its pre-destroy gate (D10) authorized the destroy on the premise that **GHCR covered the
empty-store window**. Two independent failures ended that premise:

1. **The premise was retracted (#7071).** The host→GHCR edge is dead: the read PAT is revoked
   (`GET api.github.com/user` → 401) and the pull-token minter is disabled (403 DENIED). Nothing
   covers the window. It is a total pull outage until the store is refilled.
2. **The operand went dark.** `registry_pull_event ghcr-fallback` is emitted in `ci-deploy.sh`
   only inside the *success* branch of `_ghcr_pull_or_recover`, i.e. only after a **successful**
   GHCR pull. With the credential revoked it can never fire, so the operand that most directly
   measured "is the fallback healthy" is permanently zero.

On 2026-07-30 the gate was changed to refuse unconditionally. That was correct at the time and
wrong to leave standing: it made the recut unfireable during exactly the incident it exists to
recover from. As of 2026-08-05 zot is crash-looping (#7247, `pcent=89` and climbing,
`zot_restarts=9281`), nine consecutive releases are blocked, and production is serving a
2026-08-04 build. The recut is the only remaining lever, and its gate could not pass.

A second blocker sat above the refusal and nobody had named it: the arm that aborts when
`zot_served == 0`. That condition is what a crash-looping registry *produces*, so a minimal fix
deleting only the refusal would have shipped a second unfireable gate behind the first.

## Decision

**A recut is authorized only when CI has just proven, by executing it, that every image reference
production depends on can be re-materialised into an empty registry from GHCR — a source that
survives the destroy.**

The old premise is **not repaired**. It is replaced. The new criterion never claims the
empty-store window is *covered*; it claims the window is *ended*, by a restore that has just
succeeded in rehearsal and is then executed for real against the rebuilt store by a chained job.

### The independence criterion

> A gate on an irreversible destroy may not depend on the component whose failure motivates it.

This is the criterion that selected the design, and it is the one to apply to any future change
here. The chosen condition depends on **GHCR-read-from-CI**, which is *not* the failing
component: the release pipeline's failing half is the **push into prod zot** (measured, nine
consecutive `copy_v` failures), while its **GHCR-read half works** — `crane digest` returns a
digest byte-identical to the one in the failing run's own error text.

If GHCR-read-from-CI is genuinely broken, there is nothing to restore from and refusing is the
*correct* answer rather than a deadlock. That is the property that distinguishes this criterion
from the one it replaces.

## Alternatives considered

| Candidate | Depends on the failing component? | Verdict |
|---|---|---|
| Gate on a successful CI dual-push within N hours | **Yes.** The dual-push's failing half *is* the push into prod zot. A broken dual-push is the usual reason you need the recut. | **Rejected** — unavailable precisely when needed. |
| Require a second mirror to exist | No, but it does not exist and is not committed (ADR-096 clause (g); #6126 is explicitly "still not a commitment to build one"). | **Rejected** — a gate whose PASS condition is an unbuilt system is the unconditional refusal wearing a different hat. |
| Refuse until a GHCR **pull** credential is restored | No, but ADR-096 clause (c) rejects it structurally: no GHCR pull credential can be minted without a browser, and the App installation token can `docker login` but is DENIED `docker pull`. | **Rejected** — not obtainable; a permanent refusal. |
| **Pre-staged pins + rehearsed restore** | **No.** Depends on GHCR-read-from-CI, `crane`, a throwaway registry in the runner, and prod `/health` — which is served by already-running containers and survives a zot outage (measured `uptime` 91973 s spanning the crash-loop). | **Adopted.** |

### Rejected, and recorded because it is strictly stronger

Rehearsing against **production zot itself** before the destroy would additionally prove the
Cloudflare Tunnel, the live `ZOT_PUSH_*` credential, the real zot version and the real
`accessControl` — eliminating A4's admitted staleness residual. It is rejected because it
**depends on the component whose failure motivates the recut**: during a crash-loop that
rehearsal aborts exactly when the gate is needed. This is the independence criterion applied to
the design itself. A draft answered it with an advisory-degrading probe that *did* observe prod
zot; that probe was subsequently removed for reasons the asymmetry could not fix — see "Why there
is no live-sink predicate".

## The predicates, and the fail-open analysis for each

Every predicate has an explicit **could-not-measure** bucket that ABORTS, evaluated *before* any
comparison. The verdict switch has no default-pass arm.

| | Predicate | Verdict role | What would make it green while the thing it protects is broken, and the guard |
|---|---|---|---|
| **A0** | Inventory derived from production's own pins, with zero reads of zot | ABORTING | `/health` returns a version whose tag does not exist → A1 aborts. `/health` unreachable → could-not-measure → abort. A **cached edge response** carrying a previous version would satisfy a version-only check while the running build is unrestorable → `build_sha` is asserted as well, and `Cache-Control: no-cache` is sent. |
| **A1** | Every pin resolves at GHCR | ABORTING | A digest resolved against the wrong registry → guarded by a literal `ghcr.io/` prefix assertion plus a `^sha256:[0-9a-f]{64}$` shape check, so a 200 carrying a garbage body cannot produce a well-formed digest. |
| **A2** | Rehearsed restore into a throwaway registry | **POSITIVE — this is the pass condition** | Four inputs, four guards; see the table below. |
| **A3** | Non-vacuity floor | ABORTING | An **empty inventory** is the single most likely fail-open: every loop then passes and the gate goes green having proven nothing. Guarded by a declared source-level `FLOOR` compared against both the declared pin set and what was actually resolved. |
| **A4** | Sink credential graded live at the Cloudflare Access edge | ABORTING on a measured dead count | The grader makes **zero network calls** — it grades a JSON file the detector must write first. Grading without running the detector returns `unmeasured`, which degrades, producing a predicate that runs, prints and can never abort. Guarded by invoking the detector first, pinned by a test row plus a structural check. |

There is deliberately **no A5**. A draft carried one — a live write probe against production zot,
advisory-degrading. It was removed; see "Why there is no live-sink predicate" below.

### A2's fail-open inputs

| Fail-open input | Guard |
|---|---|
| The runner's local image cache satisfies a daemon-side pull, so the round-trip never touches the throwaway registry. | Verification reads back with `crane` against the registry HTTP API only; no daemon-side pull appears anywhere in the verification path (asserted mechanically). |
| The throwaway allows anonymous push, so the restore succeeds without authenticating and a credential failure against production stays invisible. | `defaultPolicy: []` mirrored from `cloud-init-registry.yml`, plus an explicit negative control asserting an unauthenticated request is refused **before** the rehearsal runs. |
| The throwaway runs a different zot build than production. | Pinned to the Terraform-declared image read through `local.zot_image`'s **arch ternary**, not `zot_image_amd64` directly — that matches today only because the registry type is amd64, and #6460 makes a `cax*` fallback live. |
| The rehearsal and the real restore drift apart. | One script, one entrypoint. They differ in exactly `--target` and the credential environment. There is no mode flag to drift. |

### Why verification is `crane validate --remote` and not `crane digest`

Measured 2026-08-05 against a real throwaway zot, with the layer blob evicted from the store:

```
crane digest            -> rc 0, PASS          # certifies an image no host can pull
crane validate --remote -> rc 1, BLOB_UNKNOWN
```

zot runs gc and dedupe, and `crane digest` is a manifest read, so a manifest can outlive its
layers. A digest-only round-trip is therefore a verification that **goes green on an unusable
restore** — the exact defect class this ADR exists to remove. This also narrows the open question
in `build-inngest-bootstrap-image.yml`'s dark-launch: `crane validate --remote` **does** speak
plain-HTTP to a loopback registry. It does not promote that dark-launch, whose own criterion is a
real run against prod zot.

## Why there is no live-sink predicate

A draft of this design carried an **A5**: an advisory-degrading live write against production zot,
aborting on `credential_rejected` and `wrong_digest`, degrading on everything else. Plan review R2
added it to close a real gap — the first draft answered "must not depend on the failing component"
by *never looking at it*, which is a weaker property than independence. **R2's finding was correct;
R2's remedy was not.** A5 is removed. This reverses a review decision, so it is recorded as a
reversal rather than a cleanup.

**The asymmetry was sound, and that is why it must be recorded here.** Only authorisation and
correctness failures aborting, while availability failures degrade, correctly inverts the
fail-closed rule for a predicate whose unmeasurability *is* the incident — an earlier draft that
put `connection reset by peer` in the ABORT bucket would have aborted on the literal failure text
of release run `30988480437`. A future reader will re-derive that asymmetry, find it valid, and be
tempted to re-add the predicate. **The asymmetry is not why A5 went.** It went on three
independent grounds, any one sufficient.

### 1. The dual of the independence criterion

The criterion above says a gate on an irreversible destroy may not depend on the component whose
failure motivates it. Its **dual** is the one A5 violates:

> A gate on an irreversible destroy may not **abort on a property of the component the destroy
> replaces.**

A5 graded two credentials at once. The **Cloudflare Access** half is already graded pre-destroy by
A4, scoped `--only REGISTRY_PUSH_ACCESS_TOKEN`, aborting on a measured dead count — and that
credential *survives* the destroy: it lives in `tunnel.tf` and is not among the recut's targets.
A5 added nothing there.

The only thing A5 added was the **htpasswd** half, `ZOT_PUSH_TOKEN` — and that is precisely the
credential plane the recut **rebuilds**. `/etc/zot/htpasswd` is baked once at boot from the Doppler
value (`cloud-init-registry.yml`), and `zot-registry.tf` states it verbatim: the server's
`replace_triggered_by` "replaces the host so the htpasswd is re-baked from the new value in the
SAME apply". The recut replaces that host while leaving the password resource untargeted, so the
rebuilt host bakes from the same unchanged value the restore job reads.

So a pre-destroy `credential_rejected` at the htpasswd layer means **the running host's bake has
diverged from Doppler** — and the remedy for that divergence *is a host replace*, i.e. this recut.
A5 would have aborted the recut and sent the operator to "fix `ZOT_PUSH_*` before re-firing",
away from the only remedy, on a symptom the remedy cures.

That is the same shape as the two failures this ADR already removes (the 2026-07-30 unconditional
refusal, and the `zot_served == 0` arm): **a gate that blocks the recovery on the condition the
recovery fixes.** A5 was the third instance, hiding inside the predicate added to prevent the class.

### 2. The distinction A5 rests on is undecidable on this transport

A5's whole design turns on separating an authorisation refusal from an origin outage. This repo has
already ruled that separation impossible on exactly this transport, and paid for the ruling:
**#7242 / ADR-166** — Cloudflare Access **admitted** every request while zot crash-looped, and the
`websocket: bad handshake` signature sent operators to rotate a credential that had been verified
live six minutes earlier. `cf-tunnel-registry-bridge` carries the finding in its own source: a bad
handshake "does NOT by itself distinguish an edge refusal from an origin that is down or
restarting."

A5 would have to make that call under **abort authority**, during a crash-loop. There is no safe
setting: classify the ambiguity as `credential_rejected` and the gate deadlocks during the
motivating incident; classify it as availability and the abort arm is unreachable in the only
scenario that matters, which is the dark-operand defect this whole change removes. A predicate
whose two settings are "deadlock" and "dark" has no correct setting.

### 3. Its only transport is fail-closed and cannot carry the asymmetry

`cf-tunnel-registry-bridge` exits 1 on a failed listener bind and on a failed `docker login`. Both
are availability-shaped failures during the incident, so bringing the bridge up inside the gate job
**aborts before the gate script runs** — availability aborting, at a layer A5's degrade arm cannot
reach. Rescuing that would need `continue-on-error` on a composite whose header calls itself
"setup only", plus a teardown, on the pre-destroy path, to feed a classifier ground 2 shows cannot
be written.

### Corroboration that the knob was never exercised

The removed code's own refusal message named `REGISTRY_GATE_SINK_CMD` while the production knob it
documented was `REGISTRY_SINK_PROBE_CMD`. A wiring that had ever run end-to-end would have surfaced
that mismatch. It is recorded, not repaired.

### What the gate gives up, stated plainly

It no longer observes production zot at all before destroying it. Accepted, because nothing about
zot's credential or serving plane survives the destroy except the Cloudflare Access edge — htpasswd,
`config.json`/`accessControl` and the store are all regenerated. The surviving half is measured
pre-destroy by **A4, which aborts**. The non-surviving half is measured post-destroy by
`registry_store_restore`, against the host it actually applies to, with a non-retryable exit-5 arm
naming rotation as the remedy and a bounded exit-3 retry that does not conflate it with tunnel
convergence.

A5 was trying to buy a pre-destroy guarantee about a post-destroy artifact. That guarantee is not
purchasable; A4 plus the chained restore already cover both halves at the points where each is
decidable.

**The authorization claim is unchanged by this removal.** A2 is the pass condition; A5 was
advisory. Removing an advisory predicate removes no claim — and that invariance is the check that
the removal is not a regression on what this gate asserts. What changes is the residual set.

## Named residuals

1. **A4's credential staleness is bounded, not eliminated — and the two halves are discharged
   differently.** A4 grades the CF Access service token; `ZOT_PUSH_TOKEN` (zot's own htpasswd
   credential, a different secret behind the same tunnel) can be stale independently. The
   **edge** half is bounded by A4, which aborts on a measured dead count. The **htpasswd** half is
   **discharged by construction rather than measured**: it does not survive the destroy, because
   the recut replaces the host and `zot-registry.tf`'s `replace_triggered_by` re-bakes
   `/etc/zot/htpasswd` from the same Doppler value in the same apply. A pre-destroy grade of it
   would therefore be a grade of an artifact that is about to be discarded — which is why the
   predicate that tried to do it was removed. What remains open is the *post*-destroy case, and
   that is measured by `registry_store_restore` against the rebuilt host, with a non-retryable
   exit 5 naming rotation.
2. **A2 does not prove host-side pull.** ADR-096 clause (f) makes exactly this distinction: the
   rebuilt host pulls over the private NIC with `ZOT_PULL_*`, no tunnel and no CF Access —
   a different transport and a different credential from anything this gate exercises. The
   compensating controls are D11's heartbeat-transition poll and the chained restore, both
   fail-loud.
3. **The `ghcr-fallback` emitter and its Sentry rule remain dark.** Dropping the operand from the
   gate satisfies #7277's acceptance criterion; the emitter is not re-plumbed here, deliberately
   (hoisting it would silently invert a documented semantic split between `ghcr-fallback` and
   `local-cache`, with no `.tf` diff for a reviewer to catch). Tracked separately. The
   compensating control is the chained restore, which *bounds the very window the alert was
   supposed to page on*.
4. **`registry-region-migrate` is an unguarded bypass to the same creates** (#6946): no confirm
   token, no id-pin, no live posture probe, no D10. An operator whose recut aborts can fire it
   instead. Wiring D10 there needs a posture probe and an id-pin it does not have — a materially
   larger change to a second destroy path, inside the PR that re-authorises the first. Scoped
   out and compensated in the runbook's promoted caveat.

## The `IMAGE_VERIFY_MODE=warn` dependency — declared, not assumed

The design's tolerance for any signature imperfection rests on `IMAGE_VERIFY_MODE` defaulting to
`warn` in `ci-deploy.sh`, where a verify failure runs the digest anyway. **That is a disabled
control, not a safety property.** A future flip to `enforce` changes the calculus and requires
this decision to be re-signed.

That said, this design does not *rely* on the tolerance: there is **no unsigned-restore arm**.
The restore copies each image's `sha256-<hex>` signature tag and asserts it is readable back from
the target, failing the restore if it is not. Phase 0.3 measured why copying is sound: the GHCR
signature is a **Sigstore bundle v0.3**, which binds to the image *digest*, not the legacy
simple-signing payload that pins `critical.identity.docker-reference` to a registry ref. Because
`crane copy` is digest-preserving and `ci-deploy.sh` verifies identity from the Fulcio
certificate against a digest ref, a copied signature verifies unchanged at a zot ref. The recut
job therefore needs **no `id-token: write`**, and no gate run writes to the public Rekor log.

## The falsifiable hypothesis this creates

The recut is being authorised on the belief that zot's crash-loop is caused by its **store**
(corruption, or the disk-pressure/gc interaction at `pcent=89`). That belief is not proven —
#7247 owns the diagnosis, and this gate deliberately reads **nothing** about zot's health, so its
correctness does not depend on the root cause being known.

But the recut is an experiment, and it has a falsifiable outcome:

> **If zot crash-loops again on a freshly-created, empty, just-restored store, the
> store-corruption hypothesis is REFUTED and the recut is not the lever.**

Record that outcome when the recut is fired. A second crash-loop on an empty store moves the
investigation to the daemon, the host, or the scheduler panic in
`pkg/scheduler.(*Scheduler).poolWorker` — and means further recuts are wasted destroys.

## Consequences

- The recut becomes fireable again, for the first time since 2026-07-30.
- The empty-store window changes character: from **unbounded** (ended only by an operator
  dispatching a release pipeline measured failing nine consecutive times) to **bounded by an
  automatic, fail-loud, resumable restore**. It is not eliminated — the zero-downtime blue-green
  path is ADR-096 clause (g)'s second-mirror arm (#6126) and remains out of scope.
- **The window's duration is not yet measured.** Phase 0.4 (per-pass wall-clock and peak runner
  disk for the full pin set) is a named unmeasured residual. The bound is currently *structural*
  — an explicit job timeout plus a resumable engine — not numeric. No artifact should state a
  numeric bound until it is measured.
- **The chained restore is a behaviour expansion of a production workflow.** `registry-luks-recut`
  now performs a multi-GB write into production's registry as part of its normal path. That is
  new blast radius, in a job that previously only provisioned. It is isolated in its own job with
  its own budget so it cannot consume the mutex-holding recut job's timeout.
- **Rollback narrows on the success path.** The restore carries only the `required` pin set
  (`FLOOR = 4`), and the host→GHCR edge is dead, so immediately after a recut there is no older
  image in the store to roll back to — while `ci-deploy.sh` treats rollback to an older image as
  a supported path. Recoverable by re-running the restore with a wider set, but it is a
  capability that degrades where nothing goes red.
- Closing #7277 does **not** make the recut fireable on its own: `stock_preflight_gate` still
  applies, and `cx23` was measured (2026-08-05) orderable in `nbg1-dc3` but **not** in `hel1-dc2` where this
  host runs (#6460).
  > **Superseded 2026-08-06 (#7309) — the conclusion holds, the stated reason does not.**
  > `stock_preflight_gate` derives the type from `var.registry_server_type` at run time
  > (`apply-web-platform-infra.yml`, `read_default`), so it now probes **`cpx22`**, not `cx23`
  > — and `cpx22` was ✓ at every recorded probe. Stock is no longer what holds the recut. The
  > remaining blockers are #7278 and #6929. **Probe `cpx22`**, not `cx23`, before any dispatch;
  > and re-probe every time, because a reading from a previous dispatch authorizes nothing.
- **ADR-096 clause (g) stays open.** This builds a *CI-mediated* restore; clause (g)'s two named
  remedies are a zero-touch-mintable GHCR pull credential and a second mirror. This is neither.

## Amendment 2026-08-06 — the independence criterion extends to authorizing INPUTS

The criterion as accepted governs **components**: a gate on an irreversible destroy may not
depend on the component whose failure motivates it. That is necessary and, as shipped, not
sufficient. It says nothing about where the gate's *inputs* come from, and a gate can satisfy it
completely while being unable to run at all.

Both D10 arms derived the `/health` URL — which decides **which host's** version set defines the
restore inventory — from a Doppler secret that exists in no config of the `soleur` project. The
component independence held perfectly: the read touched neither prod zot nor the release
pipeline's failing half. The gate was still unfireable, aborting at PREPARE before reaching the
destroy-guard, during exactly the incident it exists to recover from.

**Extension, scoped to ADDRESSING inputs.** Separate the two kinds of input a gate consumes:

- An **addressing input** selects *what gets measured* (which host's `/health`, which registry,
  which tag set). It must be (a) causal rather than a derived copy, and (b) resolvable from the
  artifact CI already checks out — so its absence cannot be confused with a permission error.
- A **measurement** is *what that thing says*. It must be live, or the gate proves nothing.

This scoping is load-bearing, and an earlier draft of this amendment got it wrong by omitting
it. Stated unqualified — "an authorizing input must be present in the checkout, and a live
credential store satisfies neither clause" — it condemns every predicate this ADR ADOPTED: A0
reads production `/health` over HTTP, A1 reads GHCR under a credential, A2 rehearses against a
live throwaway registry, A4 grades the sink credential at the Cloudflare Access edge. A1 is
additionally the live credentialed read this ADR defends as load-bearing. A future reader
applying the unscoped form would be obliged to reject the whole design.

What the D10 defect actually showed is narrower and survives the scoping: the *addressing*
input — which host defines the restore set — was read from a credential store, and the value it
looked for existed in no config. Component independence held perfectly throughout, and the gate
was still unfireable. So the component criterion was necessary and not sufficient.

Applied here: the base domain now derives from `apps/web-platform/infra/variables.tf` — the
variable Terraform actually applied — honouring `TF_VAR_app_domain_base` first so the value is
what production runs on rather than what it would run on absent an override.

**The PREPARE/VERDICT split this ADR does not model.** PREPARE is unconditional (the resume arm
is already destroyed and most needs an inventory); VERDICT is conditional and authorizes the
destroy. They therefore have different independence obligations, and VERDICT deliberately
**re-derives** rather than inheriting PREPARE's value: the arm that authorizes a destroy must not
depend on another step's state. Both now read the same committed source, so re-derivation is
cheap and cannot disagree.

**Why this was invisible.** A `run:` body is not executable by any unit suite, so the gate's 60
green rows and its 42-mutation battery all certified logic that the workflow reached through a
dead read. The wiring is now asserted statically
(`tests/scripts/test-registry-d10-workflow-wiring.sh`), including a residual-zero that spans
composite actions — scoping it to the workflow alone would leave a hole the exact shape of the
bug, because the restore leg runs inside one.


## Amendment 2026-08-09 — A2's blob-completeness obligation is PER CHILD

**The decision is unchanged.** A recut is still authorized only when CI has just proven, by
executing it, that every image reference production depends on can be re-materialised into an
empty registry from GHCR. What this amendment settles is a question the original text left
implicit: *what does "blob-verified" mean for a MULTI-MANIFEST image?*

### What happened

The first live A2 rehearsal (2026-08-09, Actions run 31333047132) failed, and the dispatch
aborted safely with `verdict=REFUSED predicate=A2` — nothing destroyed. The restore engine exited
`6` (could-not-classify) on:

```
crane: Error: validating children: failed to validate image
Manifests[1](sha256:0aa3be0e…): validating layers: gzip: invalid header
```

`registry-restore-from-ghcr.sh` verification 2 ran a single `crane validate --remote` over the
whole reference. `ghcr.io/jikig-ai/soleur-web-platform` is a buildx OCI **index**, and its
`manifests[1]` is an attestation manifest (`vnd.docker.reference.type=attestation-manifest`,
`platform: unknown/unknown`) whose one layer is `application/vnd.in-toto+json` — plain JSON,
never gzipped. `crane validate` walks index children and attempts to gunzip every layer.

Validating that child digest **directly at GHCR** — a registry the recut never writes to —
reproduced the failure identically. That is what established it as a **validator false positive**
rather than store corruption, and it is the measurement this amendment rests on.

### The refinement

Blob completeness is verified **per child**, at the sink:

- **Platform children** keep the full `crane validate --remote`. Unchanged.
- **Attestation children** are verified by **blob presence** (`crane blob`, which fetches bytes
  without decompressing them), for the config blob and every layer the child declares.
- **Non-index IMAGE references** keep the single-validate path unchanged.
- **The cosign signature** is verified by blob presence, like an attestation child — and it is
  itself an INDEX. Measured at GHCR 2026-08-10 (`soleur-web-platform:v0.249.4`), the referrers tag
  `sha256-<hex>` resolves to an `application/vnd.oci.image.index.v1+json` with neither `.config`
  nor `.layers`, whose child carries `artifactType: application/vnd.dev.sigstore.bundle.v0.3+json`.
  So the signature is neither a "non-index reference" nor a child of the image index; it is a third
  thing, and the bullet above said the opposite until #7410. Reading it as a plain manifest is
  exactly what shipped a checker that fail-closed on a healthy signature and refused the recut on
  run 31392395980. The walk descends **one** level, from a digest-pinned root.
- A named `LAYERFORMAT` class maps a residual `gzip: invalid header` to exit **4** ("do not
  deploy"), so exit 6 stays reserved for shapes the engine genuinely cannot name.

This **narrows** the check; it does not skip anything. An attestation child whose blob is absent
still fails, and the test suite carries that as an explicit negative control precisely so a later
reader cannot mistake the narrowing for a skip.

### Why this strengthens the independence criterion rather than weakening it

The real restore runs the **same engine on the same code path** as the rehearsal. Without a
pre-destroy rehearsal, the recut would have destroyed the store and only then met this failure —
leaving production with an empty store, no pull path (the host→GHCR edge has been dead since
2026-07-30), and an unclassified exit 6 to diagnose under outage. The gate refused for a reason
that was *wrong about the store* but *right about the restore*: the restore genuinely could not
complete, and A2 is the predicate that says so before anything is destroyed.

That is the ADR's governing rule working as designed — *a gate on an irreversible destroy may not
depend on the component whose failure motivates it*. A2 depends on a **throwaway** registry, not
on prod zot, which is exactly why it could fail informatively while prod zot was unusable.

### The residual this exposes

A2's guard *logic* was well covered — and both suites still had **zero** occurrences of
attestation, in-toto, or gzip. They were hermetic and stayed green against a shape production has
had all along. This is the same hermetic-fixture gap that let the `APP_DOMAIN_BASE` read ship
(corrected 2026-08-06): a suite that never instantiates the real input shape cannot fail on it.
Recorded here as a standing caution for the remaining cold surfaces — the **post-destroy real
restore over the CF Tunnel** in particular, which by construction cannot be rehearsed before a
destroy and therefore has no positive control at all.

### Rejected alternative — uniform blob-presence for EVERY child

Considered and not taken: drop `crane validate` entirely and verify every child the way
attestation children are verified — read the child manifest, then `crane blob` its config and
every layer.

It is genuinely attractive. It deletes the attestation-detection branch (and with it the
`platform.architecture: unknown` assumption below), deletes the nested-index hazard, leaves one
code path with one failure semantics, and — measured, not estimated — roughly halves the bytes:
`crane validate` reads each layer TWICE, once via `Compressed()` for the layer digest and again
via `Uncompressed()` for the diffID, which on a remote layer is a second blob GET. For this
image that is 3.86 GiB per entry against 1.93 GiB of distinct content.

It was rejected because of what it drops, not what it costs. `crane validate` additionally walks
the tar structure, checks diffID/rootfs consistency, rejects duplicate file paths, and checks
manifest/config self-consistency. Those are real verification properties on the children a host
actually pulls. Blob presence plus content-digest integrity is the right floor for a child no
host ever fetches (an attestation, a signature); it is a weaker check than the one platform
children get today, and A2 is the predicate that authorizes an irreversible destroy.

Recorded here rather than filed as work: this is a decision about verification depth, and the
next reader will re-derive the same option from the same measurement. If the empty-store window
ever becomes the binding constraint, the cheaper lever is memoising verification 2 by
`dst_digest` — the required pin set resolves three tags to ONE index digest, so the same content
is currently verified three times — which costs no coverage at all.

### Amendment 2026-08-10 (#7410) — the signature root, and what the walk does NOT establish

Two corrections to the amendment above, both from a nine-agent review of the fix:

- **The walk is rooted at a DIGEST, not the referrers tag.** The first cut read the signature at
  its tag and justified that in a comment with "there is no digest to pin it by". That was false —
  both the GHCR digest and the sink digest are read a few lines earlier and were discarded. A tag
  read is not byte-verified, so content-addressing the children below it bought integrity relative
  to a root nobody had checked. The engine now asserts GHCR/sink digest parity for the signature
  (mirroring what verification 1 has always done for the image) and then walks from the digest ref.
- **`depth` must be threaded by every caller already inside a walk.** Defaulting it at the
  attestation call site reset the counter one level down, so the engine walked TWO index levels
  while its own comment claimed one — turning a shape the previous revision refused into a PASS.
  The nested-index refusal in verification 2 keys on the PARENT's declared `mediaType`, which no
  registry enforces against the child's body, so `verify_blobs_of`'s own fail-closed die was the
  body-based backstop behind it. Removing that backstop was the regression.

### Three narrowings this amendment does not close

- **A config alone is not evidence.** The blob walk now requires a child to declare at least one
  LAYER. Without that, a sigstore bundle child whose payload layer had been evicted verified green
  by fetching its config — which is `application/vnd.oci.empty.v1+json`,
  `sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a`, the hash of `{}`, an
  object every registry holds by construction. The narrowing that remains: the engine verifies the
  bundle blob is PRESENT and hashes correctly. It does not parse it, so it cannot say the signature
  is over the right subject. A2 asserts the pull path is re-materialisable, not that `cosign verify`
  will succeed.


- **`platform.architecture: unknown` as an attestation signal** is an assumption, not a measured
  invariant. Both it and the `vnd.docker.reference.type` annotation come from the same BuildKit
  attestation-storage convention. The disjunction protects against either one changing; it does
  not protect against both changing at once, which would reclassify an attestation child as a
  platform child and reintroduce the gunzip failure through the `crane validate` arm. The
  mutation battery carries a row per disjunct so neither can be silently dropped.
- **The platform-child floor asserts existence, not completeness.** `n_platform > 0` proves the
  index contains at least one image a host could pull. It does not prove the EXPECTED platforms
  are present: an index that silently lost its arm64 child still passes. That is acceptable for
  A2 as ADR-169 scopes it — the predicate is "the pull path can be re-materialised", not "every
  platform is intact" — but it is a narrowing of the plain-language reading, so it is stated
  here rather than left to be discovered.
