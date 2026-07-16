---
adr: 116
title: A heartbeat's arming claim must be executable — a monitor is fed, or honestly declared unfed
status: accepted
date: 2026-07-16
amends: ADR-103
supersedes: none
issue: 6537
---

# ADR-116: Executable heartbeat arming

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
  live. It is bounded only by the nightly live-reconcile deferred to #6549. Until that ships, the
  bound is a human one, which is exactly the weakness that produced #6537 — so it is named here
  rather than papered over.
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

**Build the feeder → measure a real beat → then unpause.** Never unpause first. This repo has already
run that experiment: #6210 unpaused a monitor nothing fed and paged the founder until it was
re-paused. An unfed monitor that gets unpaused converts a silent gap into a permanent false alarm,
which trains the operator to ignore the alarm — strictly worse than the silence it replaced.

## Consequences

- `registry_prd` reclassifies `web-host-cron` → `dedicated-host-boot`, so ADR-103's `replace_target`
  requirement now fires for it. **Intended**: cloud-init is per-instance, so the feeder reaches the
  host only on a fresh boot, which means the reprovision path is genuinely load-bearing. The existing
  `registry-host-replace` dispatch satisfies it.
- Adding a heartbeat now costs a `feeder` declaration. That is the point: the cost is a sentence, and
  it buys the property that the sentence is true.
- **Not closed by this ADR:** liveness from a *consumer's* perspective (can a client reach zot over
  the private net?) remains #6438 §1. The on-host beat cannot see that, and says so.
- **Not closed by this ADR:** a heartbeat paused in *live* Better Stack while its manifest row
  declares a working feeder. The guard is static; source is not live. Deferred to #6549 (a nightly
  reconcile in `scheduled-terraform-drift.yml`), which is the only layer that can close it.

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

**A nightly live-reconcile instead of a static guard.** Deferred (#6549), not rejected — it is the
only thing that can see live `paused`. But it is a different design (auth, flake tolerance, paging)
and would have been scope creep on a fix that was already shippable. Notably, an earlier draft of
this work proposed a nightly gate *around* the refusal to unpause, whose own quadrant table would
have stayed **silent** on the very monitor #6537 reported — a watchdog that would itself have been an
inert monitor, i.e. the exact class it existed to gate.

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
