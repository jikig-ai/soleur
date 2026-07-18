---
adr: 117
title: A heartbeat's arming claim must be executable — a monitor is fed, or honestly declared unfed
status: accepted
date: 2026-07-16
amends: ADR-103
supersedes: none
issue: 6537
---

# ADR-117: Executable heartbeat arming

## Context

`betteruptime_heartbeat.registry_prd` was provisioned on 2026-07-07 with `paused = true` as a
deliberate bootstrap step, to be unpaused "once the web-host probe cron ships". Nine days later it
was still paused, and the probe cron had never been written: `ZOT_HEARTBEAT_URL` had zero consumers
repo-wide. The registry — a deny-all, no-SSH host whose **only** liveness signal is a push beat —
had no liveness alarm at all, and `hcloud_server.registry` had just been replaced.

The instruction to unpause lived in a **code comment**. It had no owner, no deadline, and nothing
that could ever notice it had not been carried out.

Three properties made this invisible rather than merely undone:

1. **The comment was false, and stayed false.** It described a probe cron as shipped. Nothing
   executes a comment, so nothing contradicted it. Two other comments in this repo have been flatly
   false for months — one of them *inside* the guard built to prevent this class (#6242).
2. **A green sibling read as coverage.** `registry_disk_prd` (900s) was up, so the registry looked
   monitored. It pings on `df` alone, so it alarms host death by absence but stays green with zot
   dead.
3. **Source `paused` is not live `paused`.** These heartbeats carry `ignore_changes = [paused]`, and
   are additionally `OPERATOR_APPLIED_EXCLUSIONS` (untargeted), so the source value is decoupled from
   Better Stack twice over. `inngest_prd` is the proof: identical `paused = true` in HCL, live and
   `up`, because someone unpaused it out-of-band once its feeder existed.

The existing guard (ADR-103) classifies each heartbeat by an `arming` axis — but `arming` was
**prose**. It records which remediation class a heartbeat belongs to; it never asserted that anything
actually pings it. `registry_prd` was classified `web-host-cron` with an exempt_reason citing the
cron that did not exist. **The guard's own manifest restated the fiction.**

## Decision

**A heartbeat's arming claim must be executable.** Every row in the manifest
(`plugins/soleur/lib/heartbeat-manifest.ts`) carries a `feeder` field with exactly two legal shapes:

- `{kind: "cron" | "timer", evidence: {file, pattern}}` — **FED.** The evidence file must exist and
  contain the pattern. Checked by `grep -F` on every CI run. Delete or rename the feeder and the
  suite goes RED.
- `{kind: "none", url_secret, tracking_issue}` — **HONESTLY UNFED.** Costs an owning issue. If it
  names a `url_secret`, the guard asserts that secret still has **zero consumers**.

The 9-day middle — a provisioned monitor that nobody feeds and nobody owns — is what this forbids.

The invariant admits **two** legal resolutions for an unfed monitor: **feed it, or delete it.** A
monitor that cannot alarm is not a cheap monitor; it is a false claim of coverage, and it is worse
than no monitor because it reads as one.

### What this does NOT exclude — stated plainly, because the guard's limits are the honest part

An earlier draft of this ADR claimed "there is no third state". That was stronger than the guard
supports, and overclaiming here is the same failure mode as the comment that caused #6537. Two states
survive:

- **FED-but-inert** (`feeder.kind` is `cron`/`timer`, live `paused=true`). `registry_prd` sits here
  at merge, until the post-merge reprovision measures a beat and arms it. **No static check can
  detect this** — the manifest compares source to source, and `ignore_changes` decouples both from
  live. It is bounded by the nightly live-reconcile **built by #6549 item 2** (live once that PR
  merges — see the amendment under this section). Absent that layer the bound is a human one, which is
  exactly the weakness that produced #6537 — so it is named here rather than papered over.
- **FALSELY FED** — evidence that resolves but does not actually arm *this* heartbeat. The guard
  requires the declared **arming construct** (`systemctl enable --now <unit>`, a `- path:
  /etc/cron.d/<x>` drop-in) on a comment-stripped view, which excludes the cheap versions: a bare
  unit name that survives only in a comment, or generic boilerplate. It does **not** formally bind
  the evidence to the heartbeat it claims to feed — a row could name a *sibling's* arming construct
  and pass. Closing that needs a `url_binding` assertion (evidence file dereferences, or is baked
  from, `betteruptime_heartbeat.<name>.url`); the two delivery routes differ, so it is not one
  uniform check. Deliberately not built here.

The guard is calibrated against **laziness** (`""`, `"a"`, boilerplate). #6537 was not laziness — it
was a confident wrong claim. That gap is narrowed, not closed.

### The inverse assertion is the load-bearing half

The forward check (does the declared feeder exist?) only catches feeders that regress. It cannot
catch the #6537 shape, where the feeder **never existed**. So the `kind: "none"` rows assert the
negative: the URL secret must have zero consumers. The day someone ships a feeder for a heartbeat
still declared unfed, **CI goes red and forces the row — and the arming decision — to be reconciled**.

That is precisely the event that went unnoticed for `registry_prd`, in reverse. It is now a build
failure.

### Feeder detection is anchored on delivery, never on a name

An unfed row is proven unfed against **both** delivery routes this repo uses, and neither probe
matches a bare name:

- **Dereference** (`$VAR` / `${VAR}`) — the Doppler-secret route. A bare-name grep for
  `GIT_DATA_HEARTBEAT_URL` matches its own `name = "..."` definition and lines of operator prose
  (including one inside a `cat <<'HEALTH'` heredoc, and a `TODO` comment describing the feeder that
  does not exist). None is a feeder, so a name-anchored count reports a feeder that does not exist —
  reproducing the exact fiction this ADR kills. Positive control: `INNGEST_HEARTBEAT_URL` *is*
  dereferenced (`curl -fsS --max-time 10 "$INNGEST_HEARTBEAT_URL"`), and that heartbeat is the one
  actually armed and up.
- **Bake** (`<var>_url = betteruptime_heartbeat.<name>.url` passed into a `templatefile`) — the route
  #6537 itself introduced. `registry_prd`'s feeder bakes its URL and dereferences **nothing**, so a
  dereference-only guard would be structurally blind to the very shape this ADR canonizes. `value =
  ...url` is excluded: that is a `doppler_secret`/`output` definition, not a delivery.

(No count is stated for those bare-name hits on purpose: the number depends on scope and moves with
every edit — including this ADR's own. The test asserts the *discriminator* — bare name matches,
dereference does not — never a literal.)

### This decision does NOT rest on `ignore_changes = [paused]`

It rests on the **general** property that **source is not live**. `ignore_changes` is one mechanism;
being untargeted is another and would suffice alone (a source unpause on an unapplied resource is a
no-op regardless). Keying the rule on `ignore_changes` would leave the rule silently wrong for any
heartbeat that drops it while staying untargeted. The rule is: **no static check can prove a monitor
is armed; it can only prove a feeder exists.** Arming is verified by measuring a beat.

### Ordering is mandatory, not advisory

**Build the feeder → verify the beat → then leave it armed.** Never arm an unfed monitor and walk
away. This repo has already run that experiment: #6210 unpaused a monitor nothing fed and paged the
founder until it was re-paused. An unfed monitor that gets unpaused converts a silent gap into a
permanent false alarm, which trains the operator to ignore the alarm — strictly worse than the
silence it replaced.

> **Corrected 2026-07-16, by executing it.** This section originally read *"measure a real beat →
> **then** unpause"*. **That is not implementable against Better Stack's API, and shipping it as
> procedure was this ADR's own defect** — an arming instruction nothing could carry out, in the ADR
> written because an arming instruction nothing carried out cost 9 days of blindness.
>
> Measured, not assumed (`GET /api/v2/heartbeats/<id>`): the resource exposes
> `{status, paused, paused_at, period, grace, updated_at, url, …}` — there is **no
> `last_heartbeat_at`**, and `/heartbeats/<id>/events` **404s**. A paused monitor reports
> `status: "paused"` and its `updated_at` never moves when a beat arrives. Verified against a live
> feeder mid-reprovision: `updated_at` stayed frozen at the provisioning timestamp throughout.
> **A beat is not observable while the monitor is paused.** The order the issue asked for cannot be
> performed.
>
> **What replaces it — bounded arm-and-watch with the rollback in the same process:**
> 1. Ship the feeder and reprovision the host.
> 2. `PATCH {"paused": false}`, then poll `status` every 10s.
> 3. `status: "up"` ⇒ a real beat landed; done.
> 4. No `up` by `period + grace − 10s` ⇒ **`PATCH {"paused": true}` immediately**, before the first
>    alert can fire. Diagnose; do not retry blind.
>
> This is NOT #6210's shape, and the distinction is the whole point: #6210 armed an unfed monitor and
> **left it armed**. Here the rollback is held for the entire window, so the worst case is bounded to
> at most one email (free tier: `policy_id = null`) — not a permanent page.
>
> **It was exercised on the first attempt and it worked.** The registry's `registry-host-replace`
> hit #6400's NIC race (`nic_ok=false` — the host booted with no `10.0.1.30`). The feeder correctly
> withheld its ping, arm-and-watch saw `pending` for 86s, rolled back at 86s, and **no alert fired**.
> After #6415's guard converged the NIC (`converged_by=reboot`), the re-arm went `up` in **11s**.
>
> The invariant survives the correction intact: **no static check can prove a monitor is armed; it
> can only prove a feeder exists.** Arming is still verified by a beat — the beat is just measured
> during a rolled-back-by-default arm, not before it.

### Amendment (2026-07-17, #6549 item 2): a live-reconcile to close the FED-but-inert gap

The two states this ADR named as surviving — **FED-but-inert** (live `paused=true` with a working
feeder) and the sibling **absent-live** shape (#6548) — were bounded by "a human one, which is
exactly the weakness that produced #6537." The #6549-item-2 PR builds the layer that machine-checks
that bound: a nightly `heartbeat-live-reconcile` job in `scheduled-terraform-drift.yml` pulls
`GET /api/v2/heartbeats` and reconciles the **live** `paused`/existence of each monitored heartbeat
against this manifest, flagging **two specific mismatch classes** — (a) a heartbeat live-`paused`
whose manifest `feeder.kind ∈ {cron,timer}` (and which does not carry an `arming_pending` deferral),
or (b) a non-`count`-gated heartbeat absent from the live payload. It does NOT prove general
source↔live agreement (it deliberately ignores, e.g., an unfed live-paused monitor); it flags those
two classes and no more, in the same spirit as this ADR's "What this does NOT exclude" section. It
only READS; it never unpauses. This is the **complement** to the static guard, not a replacement:
the static manifest proves a feeder exists in source (the forward + inverse checks above); the
live-reconcile is the only layer that can see live state.

> **Live once this PR merges (verified post-merge, not asserted here).** The reconcile job runs only
> from `main`, and its Sentry cron monitor (`scheduled-heartbeat-reconcile`) does not exist until
> `apply-sentry-infra.yml` auto-applies on merge — both are post-merge facts, confirmed by the plan's
> post-merge ACs, not by this text (stating not-yet-live work as shipped is the exact defect this ADR
> exists to condemn). The reconcile *logic* is verified pre-merge by a local read-only dry-run
> (plan Phase 6.2) and the unit suite; "the CI job runs" and "the monitor pages on a missed check-in"
> become true at merge + first dispatch. The `arming_pending` manifest field (added with the
> reconcile) keeps a deliberately-deferred monitor — e.g. `workspaces_luks` pre-cutover (#6604) —
> from being flagged as FED-but-inert, in this ADR's own executable-not-prose idiom.

ADR-117 is **amended, not superseded**: the manifest remains the source-of-truth substrate the
reconcile reads.

### Amendment (2026-07-18, #6438/#6548): the measure-then-arm PATCH is AUTOMATED into the apply workflow

This amendment records **only an automation delta**. The *decision* is unchanged: the
measure-then-arm sequence is exactly the one already in this ADR's **"Corrected 2026-07-16"**
section (`PATCH {"paused": false}` → poll `status` → roll back to `paused:true` on no `up` within
`period + grace − 10s`, fail-loud). #6438/#6548 do not add a new arming decision; they move that
existing decision from a hand-run procedure into
`.github/workflows/apply-web-platform-infra.yml`, so the new web-host consumer probes
(`web_zot_consumer`, `web_nic_guard`, and the newly-fed `git_data_prd`) arm without an operator
carrying the sequence out from memory — the same class of gap (an arming instruction nothing
executes) this ADR exists to condemn.

Three properties of the automation, and nothing beyond them:

1. **Op/state-gated, not every-apply.** The arm step runs the measure→PATCH cycle **only** when
   the target monitor is live-`paused==true` (`GET /api/v2/heartbeats/<id>`) **OR** its feeder
   `terraform_data` provisioner was replaced this apply (`triggers_replace`). A routine re-apply
   where the monitor is already `up` is a true no-op — it does not re-PATCH, and does not flake on
   a transient Better Stack blip. This is the gate that keeps the "Corrected 2026-07-16" procedure
   from becoming a per-apply liability.
2. **A dedicated Doppler-scoped write token, not the read path.** The PATCH authenticates with a
   `doppler_service_token.web_arm_write` exposed to CI as the `github_actions_secret`
   `DOPPLER_TOKEN_WEB_ARM`, over the **existing account-wide Better Stack provider token** (no new
   operator-mint variable — `hr-tf-variable-no-operator-mint-default`; mirrors the
   `inngest-arm-write-token.tf` precedent). The apply workflow's existing read-only "Best-effort
   heartbeat status" steps are **not** reused for the write — they swallow errors and return
   "unavailable", which is correct for an informational read and disqualifying for a gating write.
3. **Fail-loud, rollback held for the whole window.** On no fresh `up` beat within the deadline the
   step re-PATCHes `paused:true` immediately and **fails the apply** — it never leaves an unfed
   monitor armed (#6210's incident shape) and never continues green on "unavailable".

**Risk note — the write token's blast radius is account-wide, recorded honestly.** Better Stack
API tokens have **no per-monitor and no read/write scoping** — a token that can `PATCH` one
heartbeat can read and write **every** monitor, heartbeat, and on-call resource in the account.
The `web_arm_write` token is therefore **not** least-privilege at the Better Stack layer; the
**only** axis on which it is scoped is Doppler — it lives in a dedicated service token / config so
that *which CI jobs can read it* is controlled, even though *what it can do once read* is
unbounded. This is the same account-wide-R+W property ADR-115's arm path already carries; naming
it here keeps the arm-gate's true blast radius on the record rather than implying a monitor-scoped
credential that the vendor does not offer. Narrowing it further would require a per-resource
scoping axis Better Stack does not expose; if that changes, revisit.

The invariant is untouched: **no static check can prove a monitor is armed; it can only prove a
feeder exists.** Arming is still verified by a measured beat — the beat is now measured by the
apply workflow's op/state-gated step instead of by a human running the sequence by hand.

## Consequences

- `registry_prd` reclassifies `web-host-cron` → `dedicated-host-boot`, so ADR-103's `replace_target`
  requirement now fires for it. **Intended**: cloud-init is per-instance, so the feeder reaches the
  host only on a fresh boot, which means the reprovision path is genuinely load-bearing. The existing
  `registry-host-replace` dispatch satisfies it.
- Adding a heartbeat now costs a `feeder` declaration. That is the point: the cost is a sentence, and
  it buys the property that the sentence is true.
- **Not closed by this ADR:** liveness from a *consumer's* perspective (can a client reach zot over
  the private net?) remains #6438 §1. The on-host beat cannot see that, and says so.
- **Addressed by the #6549-item-2 live-reconcile (live post-merge):** a heartbeat paused in *live*
  Better Stack while its manifest row declares a working feeder — and the sibling absent-live shape
  (#6548). The static guard cannot see either (source is not live); the nightly
  `heartbeat-live-reconcile` job in `scheduled-terraform-drift.yml` reads live state and reconciles it
  against this manifest. See the amendment subsection under `## Decision`.

## Alternatives Considered

**Unpause `registry_prd` now (the issue's literal ask).** Rejected — and the issue's own ask #1
authorised the rejection ("if the probe cron is not in fact shipping pings, that is the real
finding"). Unpausing an unfed monitor pages every 60s forever; #6210 is that incident. The ask is
answered in the order it demanded: feeder first, measure, then arm.

**Keep `arming` as prose, fix the comment.** Rejected. The comment was *already* prose, and prose is
what failed — for 9 days, in a repo that had already codified this class in #6242. Fixing a false
comment with a truer comment leaves the failure mode fully intact.

**Forward-only grep (assert declared feeders exist).** Rejected as insufficient. It cannot catch a
feeder that never existed — the #6537 shape — and it goes silent exactly when someone ships a probe,
then false-fires at the person doing the right thing. The inverse assertion is what closes it.

**A nightly live-reconcile instead of a static guard.** Deferred at #6537, **built as the
#6549-item-2 complement** (live once that PR merges) — not a replacement. It is the only thing that can see live `paused`,
but on its own it is periodic (twice-daily) and vendor-availability-dependent, so it cannot replace
the static manifest's per-commit forward+inverse checks; the two layers are complementary (source
truth on every push, live truth twice daily). Splitting it out of #6537 was correct: it is a distinct
design (auth via `doppler secrets get --plain`, tri-state flake tolerance, creation-only paging) that
would have been scope creep on a fix already shippable. Notably, an earlier draft of this work
proposed a nightly gate *around* the refusal to unpause, whose own quadrant table would have stayed
**silent** on the very monitor #6537 reported — a watchdog that would itself have been an inert
monitor, i.e. the exact class it existed to gate; the shipped reconcile avoids that by keying on the
manifest `feeder.kind`, so a fed-but-paused monitor is flagged rather than tabulated-and-ignored.

**Extend the static parity test to read live Better Stack state (fold the reconcile into the existing
test).** Rejected. The parity test runs per-commit in CI with no vendor credentials and must stay
hermetic and offline-deterministic; giving it a network dependency on `uptime.betterstack.com` would
make every push flake on a Better Stack blip and leak the API token into the unit-test surface. The
live read belongs in a scheduled job with its own auth, retry/backoff, and paging semantics — kept
**separate** from the source-only guard precisely so the fast, hermetic per-commit check never
acquires a vendor dependency.

**Widen `period`/`grace` so a cron's 60s floor fits.** Rejected as structurally impossible, which is
worth recording: `betteruptime_heartbeat.registry_prd` is an `OPERATOR_APPLIED_EXCLUSION`, so a
resource edit could never apply. The feeder meets the existing 60/30 with a systemd timer instead —
mirroring `inngest_prd`, which runs the identical cadence against an identical monitor and is live.

## References

- Issue [#6537](https://github.com/jikig-ai/soleur/issues/6537) — the never-unpaused registry heartbeat.
- [ADR-103](./ADR-103-dedicated-host-boot-heartbeats-require-guarded-reprovision-path.md) — the `arming` axis this makes executable.
- [ADR-096](./ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md) — zot registry; its #6285 note ("that layer does not exist yet") is superseded by the on-host feeder.
- [ADR-115](./ADR-115-dedicated-host-private-nic-boot-convergence.md) — the private-NIC converger; the private-IP probe choice shares its root cause (#6400).
- #6210 — the unfed-monitor false-alarm incident that fixes the ordering.
- #6438 §1 — the consumer-perspective probe this does not close.
- #6548 — `git_data_prd`: the sibling unfed heartbeat, plus its unexplained live absence.
- #6549 — the two paid-tier webhook heartbeats + the deferred nightly live reconcile.
