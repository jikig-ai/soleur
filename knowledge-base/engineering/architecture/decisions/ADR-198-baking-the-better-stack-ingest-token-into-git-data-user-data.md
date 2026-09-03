---
title: "ADR-198 — baking the Better Stack ingest token into git-data user_data, at 0600 and on a capability test"
status: accepted
date: 2026-09-03
tags: [git-data, observability, secrets, user-data, betterstack, luks]
related_adrs: [ADR-096, ADR-147, ADR-149, ADR-152, ADR-163]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md
  - knowledge-base/engineering/operations/runbooks/betterstack-log-query.md
---

# ADR-198 — baking the Better Stack ingest token into git-data user_data

## Status

`accepted`. Implemented in #7460 (PR B of the #7570/#7534/#7544/#7481 harness work).

This is **not** a first-of-kind decision. `apps/web-platform/infra/inngest-host.tf` already bakes
this exact variable with the identical rationale — a pre-Doppler fallback so the earliest `runcmd`
can phone home. (ADR-096 does NOT record that bake — it records the container-registry
migration's own Doppler secret. The Inngest bake arrived in `4a2087f31`, PR #6310, without an ADR;
that gap is part of why this one exists.) The comment on the line above that bake reads
**`(weigh before widening use)`**. This ADR is the widening that clause anticipated, and its job is
to *discharge* the clause rather than re-decide the question.

## Context

### What was broken

`git-data-emit` gated its Better Stack POST on `BETTERSTACK_LOGS_TOKEN` being present in the
environment, which happened only under `doppler run`. Everything before that — `bootcmd`,
`write_files`, the Doppler install, the LUKS open — reached **Sentry only**. ADR-149 recorded the
consequence plainly: *"on a successful boot the only Better Stack row a git-data host produces is
`boot_complete` itself."*

That is why the last real rehearsal (run 30649892865, 2026-07-31) needed a hand re-query to find
its cause: it died at `stage:luks_open`, which is pre-Doppler, so the queryable channel had nothing.

### Coverage widens to EIGHT stages, not nine

#7460's title says nine. Measured: the `bootcmd` beacon is an inline bare `curl` to Sentry at
`cloud-init-git-data.yml`, emitted **before** `write_files`. The shared `/usr/local/bin/git-data-emit`
does not exist yet when it fires, so `stage:bootcmd_start` cannot reach Better Stack whatever token
is baked. Eight of the nine stages gain the second channel; the ninth is Sentry-only by
construction, not by configuration.

## Decision

Bake the ingest token into `user_data`, delivered as a **`0600 root:root` env file**
(`/etc/default/git-data-betterstack`) via `write_files`, sourced by the emitter only when the
environment does not already carry a fresher value.

### The rule a future author can apply

The first draft's rule was *"marginal access cost ≈ 0, because `doppler_token` is already baked and
the ingest token is derivable from it."* **That rule licenses baking the LUKS passphrase**, which
lives in the same `prd_git_data` config and which this repo deliberately keeps out. A rule that
does not sort the candidates is a rationalisation of a decision already made.

The rule is on the **capability** axis. A credential may be baked into `user_data` only if it
passes all three:

1. **Capability ceiling.** Write-only append to a telemetry sink — forged rows and quota burn.
   Not decrypt-every-user's-source-at-rest. `BETTERSTACK_LOGS_TOKEN` is ingest-only: reads are
   `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` and sink management is `BETTERSTACK_API_TOKEN`.
2. **It must not defend a control the product publicly claims.** The privacy policy claims LUKS
   encryption-at-rest (#6588). A credential that defeats a published claim is never bakeable,
   whatever its derivability.
3. **Single-purpose to this host** — see the rejected alternative below, where this leg currently
   fails and is tracked rather than asserted.

**Leg (2) is already failed on this host, by an incumbent this ADR does not disturb.** `user_data`
bakes `doppler_token`; that token reads `prd_git_data`; that config holds `GIT_DATA_LUKS_KEY`;
that passphrase decrypts every user's source at rest. So a bakeable-credential rule stated as a
universal — "must not defend a control the product publicly claims" — condemns the standing
`doppler_token`, `ghcr_read_token` and `zot_pull_token` bakes too. The rule is therefore a test on
the credential's OWN ceiling, applied to a host whose worst credential is already baked; it is not
a proof that this host's aggregate posture is sound. Removing the `doppler_token` derivation path
is tracked at #7772 and is the reason `reevaluate_when` fires BEFORE the host is born.

`GIT_DATA_LUKS_KEY` fails (1) and (2). The ingest token passes (1) and (2), and (3) is the open
residual.

### Why 0600, and exactly what that buys

| Secret | Where it lands on the host | Mode |
|---|---|---|
| `doppler_token` | `/etc/default/git-data-doppler` | `0600 root` |
| `sentry_dsn` (incumbent) | baked inside `/usr/local/bin/git-data-emit` | **`0755 root:root` — world-readable** |
| Better Stack ingest token (this ADR) | `/etc/default/git-data-betterstack` | `0600 root` |

The first draft would have baked the ingest token into the emitter, i.e. at `0755`. The host
carries a `git` account whose forced-command wrappers serve every connected user's push, so
"marginal access cost ≈ 0" was **false for a file-read primitive**. It is true of metadata and
tfstate readers only.

Two corrections this ADR must not repeat:

- **This is the SECOND instance of the exposure, not a new class.** `sentry_dsn` is already baked
  inside that same `0755` file, and the secret half of a Sentry DSN is a write-only ingest key with
  the same blast radius. The `0600` treatment makes the new credential **better than the
  incumbent**, rather than merely not-worse.
- **`0600` does not defend against code execution.** `hcloud_firewall.git_data` declares **zero
  rules**, which under Hetzner semantics is inbound-denied and **egress fully open**. Any code
  execution as `git` can `curl` the metadata endpoint and read the entire `user_data` —
  `doppler_token`, `sentry_dsn` and this token alike. `0600` defends a *file-read-only* primitive
  (a path traversal in the transport wrapper, say). The closure that would restore the category for
  all three at once is an egress rule blocking the metadata IP for non-root UIDs; it is tracked,
  not claimed.

### The argv hole, closed on every path — including the one the first draft opened

`/proc/<pid>/cmdline` is world-readable on stock Ubuntu 24.04 and there is no `hidepid` anywhere in
the template, so a credential passed as `-H "Authorization: Bearer …"` is readable by any local
account that polls during an emit — which the file mode does nothing to prevent. There are
**three** credential-bearing POSTs on this host, not two: the emitter's Sentry POST, its Better
Stack POST, and the `bootcmd` beacon. All three pass their header through `curl -K -` on stdin.
This fixes the **incumbent** Sentry key at both of its call sites.

The POSTs were not the largest hole. `_devalue_luks`/`_devalue_bs` passed each secret to
`/usr/bin/sed` as an `-e` operand — an EXTERNAL process, ~20 of them per emit, far more often than
any POST. Measured on this host: `/proc/<pid>/cmdline` is mode `444`, `/proc/<pid>/environ` is
`400`. The LUKS passphrase is the sharper case, because it is not in `user_data` and not
retrievable from the metadata endpoint, so the "0600 does not defend against code execution"
concession below does not cover it: a pure **file-read** primitive — exactly what `0600` is
claimed to stop — reads it out of `/proc` during any post-Doppler emit, including the daily GC
timer. Both redactors now read their script from a `mktemp` `0600` file via `sed -f`.

### Considered: refresh the baked file from Doppler at boot

A post-Doppler `runcmd` could rewrite `/etc/default/git-data-betterstack` from the Doppler value:

```sh
( umask 077; printf 'BETTERSTACK_LOGS_TOKEN=%s\n' "$BETTERSTACK_LOGS_TOKEN" > /etc/default/git-data-betterstack )
```

`write_files` is a **per-instance** module, so it does not re-run on reboot and the refreshed file
persists. From boot N+1 the pre-Doppler stages would read a Doppler-fresh token, and the
`user_data` coupling would survive only for an instance's very first boot.

Not taken now, and the reason is not cost. With the Consequences corrected above, a rotation
already degrades rather than breaks, so this buys a narrower window than it first appears — and it
adds a write to the boot path whose failure mode (a partial write leaving an empty token) is
exactly the state this ADR just spent a section making observable. It is worth doing before the
host is born and is tracked at #7772 alongside the per-source token, under the same
`reevaluate_when`. Recorded here because leaving it unnamed would let the next reader believe the
ForceNew coupling is unavoidable, which it is not.

### The equivalence is point-in-time, not standing

Revoking `doppler_token` today closes the derivation path for every historical `terraform.tfstate`
version. A baked token is **directly readable and durable** until Better-Stack-side rotation —
which, because `user_data` is ForceNew with no `ignore_changes` (ADR-149, ADR-152 — **not** ADR-115,
which does not state this property), then requires a host replace. "Derivable through a revocable
indirection" and "directly readable and durable" are not the same posture, and the first draft
conflated them.

### Cross-host blast radius

Measured 2026-09-03 against the Better Stack API: **one** Logs source exists
(`soleur-inngest-vector-prd`, id 2457081). `var.betterstack_logs_token` fans out to the Inngest
host's bake and its Doppler project, the zot registry's Doppler secret, git-data's Doppler secret,
and the web host's Vector sink. So rotating after a git-data metadata leak darkens the web host's
shipper and the registry's, and requires **both** an Inngest host replace and a git-data host
replace. That is the remediation cost the first draft never priced.

### The new failure mode: mirrored, and what actually reads the mirror

After a Better-Stack-side rotation the pre-Doppler stages keep shipping on the **stale baked
token** and go dark — silently darkening exactly the stages this ADR widened coverage to. The old
`|| true` swallowed it whole.

The emitter now mirrors that failure to Sentry at `level:warning`, `stage:betterstack_ingest`,
carrying `token_source` (`baked`/`env`) and never the value
(`cq-silent-fallback-must-mirror-to-sentry`). Sentry is the right channel because it is
unconditional from the baked DSN and does not depend on the sink that just failed. The emitter's
exit contract is unchanged — `0` delivered, `1` transient, `2` structural, and only `2` refuses a
boot — so a second-sink failure never promotes into a boot failure.

**Written is not read, and an earlier draft of this section claimed detection that does not
exist.** As shipped, `stage:betterstack_ingest` reaches Sentry and is queryable there, and that is
all. It is NOT on an issue-alert rule: `sentry_issue_alert.git_data_boot_fatal` filters nine
`stage` values and this is not one of them, and that rule is a *fatal* router — adding a
`level:warning` stage to it is a paging-policy change, not a filter edit, so it is not made here.
The rehearsal's `_sentry_consult` does not see it either; that consult is pinned to `level:fatal`
by design, because its job is to catch a boot death the Better Stack read missed.

So today the mirror is a **queryable record for whoever is already looking**, which is the correct
claim and a weaker one than "not silent". Routing it — either its own low-severity rule or a
widened consult — is tracked at #7772 under the same pre-birth `reevaluate_when`. This matters
most in exactly the state the mirror exists for: the host is unborn, so nobody is watching a
dashboard yet, and the first boot is the one whose ingest failure would otherwise be discovered
by its absence.

The mirror is still worth shipping now rather than with its reader: `user_data` is ForceNew, so
the emit itself costs a destructive host replace after birth, while an alert rule is a
zero-downtime Terraform change at any time. Ship the expensive half in the free window.

## Alternatives Considered

**A per-source Better Stack token — REJECTED FOR NOW, TRACKED.** Better Stack issues ingest tokens
per source, and a dedicated git-data source would shrink forged-row blast radius to git-data's own
stream and satisfy leg (3) of the rule above. Under a `single-user incident` threshold, baking the
*lowest-trust* host's copy of a credential shared with three others is the wrong direction, and this
ADR does not pretend otherwise.

It is rejected on a measured obstacle, not on preference: the Better Stack provider in this repo is
`betterstackhq/better-uptime`, an **uptime** provider — Logs *sources* are not expressible in it,
and `apps/web-platform/infra/inngest.tf` already records that as an **"IaC gap"**. `variables.tf`
states the ingest token is minted at source and only *copied* into Doppler. So adopting per-source
means either a provider that does not exist here or an operator mint, which
`hr-all-infrastructure-provisioning-servers` forbids doing ad hoc. That is a work-stream, not a
variant of this change.

Re-evaluation trigger: **before the git-data host is born.** The host does not exist yet, so the
option stays free until birth — which is exactly when it stops being free, because `user_data` is
ForceNew.

**Bake into the emitter rather than an env file — REJECTED.** ~40–80 bytes cheaper and it was the
first draft's choice. With 19,636 B of headroom against a 32,768 B cap, byte cost is not the
deciding axis; **mode is**. See the table above.

## Consequences

- Eight of nine boot stages gain a queryable second channel. The rehearsal harness can attribute a
  pre-Doppler failure without a hand re-query.
- `user_data` grows 544 B (12,588 B on `origin/main` -> 13,132 B, both re-measured with
  `git-data-userdata-budget.sh`). Measured headroom after this change: **19,636 B** of
  32,768 B. The first draft asserted ~372 B and 19,808 B: a PROJECTION taken before the
  phase's own edits landed, presented in an ADR as a measurement. The CAP is gated by
  `git-data-userdata-budget.sh`; this figure is not, and goes stale on the next line added
  to the template.
- The template's sha256 changes, so any rung-2 evidence attested against the previous template is
  invalidated. **This PR must merge before the next rehearsal dispatch** — dispatching first would
  attest template A and force a second paid dispatch.
- Rotating the Better Stack ingest token DEGRADES pre-Doppler coverage until the next boot; it
  does not break the host and it does not require a replace. The Doppler copy still wins at
  runtime (`env` beats `baked`), so the post-Doppler stages pick the fresh value up on the next
  boot. Only `bootcmd_start`..`doppler_run` ship on the stale baked token until `user_data` is
  re-rendered. An earlier draft of this ADR said a rotation "requires a git-data host replace",
  contradicting the Decision section three screens above; that sentence was wrong and this is the
  measured behaviour. What DOES rest on a single line is `lifecycle { ignore_changes = [value] }`
  on `doppler_secret.git_data_betterstack_logs_token`: baked copy and Doppler copy come from the
  same variable, so without it the next apply reverts a rotated token on both paths at once.
  `git-data-rung2-rehearsal.test.sh` now pins it.
- `sentry_dsn` and this token both belong in the `## Encryption Posture` on-host store — a third
  store alongside `user_data` and `terraform.tfstate`, with its own mode and its own
  `does_not_defend`.
- Better Stack's processor DPA posture is recorded at `knowledge-base/legal/compliance-posture.md`.
  Linked, not duplicated. Chapter V is not engaged: both sinks are EU-resident.
