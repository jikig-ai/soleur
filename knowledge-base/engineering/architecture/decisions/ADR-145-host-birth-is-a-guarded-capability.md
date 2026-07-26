# ADR-145: A host-birth path is a guarded capability, not a removed tripwire

- **Status:** accepted
- **Date:** 2026-07-26
- **Issue:** #6730 (no automated route can create `hcloud_server.web`). Related: #6416 (the birth-without-NIC incident the HALT exists for), #6090/#6575 (the baked-DSN dark-boot class), #6712 (apply-time image skew), ADR-080 (stale-image `stage=verify` abort).
- **Amends:** ADR-128 (its R1–R5 preamble said the pinned-image chain in the `host_creates` HALT carries those MUSTs "until that path exists" — it now exists and carries them itself).
- **Extends:** ADR-068 (multi-host web cluster), ADR-143 (host lifecycle — this is the *birth* half; ADR-143 owns replacement and drain).
- **Plan:** `knowledge-base/project/plans/2026-07-25-feat-web-host-birth-path-plan.md`

## Context

`hcloud_server.web` could not be created by any automated route. Every path that reaches it
HALTs on `host_creates > 0`:

- the per-PR `apply` job (#6416),
- `apply-deploy-pipeline-fix.yml` (#6718),
- `workspaces-luks-cutover`, whose gate requires zero actions on the web-1 server.

<!-- lint-infra-ignore start: the sentence below NAMES the laptop-run apply in order to record it
     as the defect this ADR closes. It is the problem statement, not a prescribed step — the
     decision is precisely that this path stops being the remedy. Same actor+imperative
     co-occurrence the linter matches on, inverted in meaning. -->
The only documented remedy was an operator-local `terraform apply` from a laptop, which
violates `hr-fresh-host-provisioning-reachable-from-terraform-apply` and
`hr-never-label-any-step-as-manual-without`.
<!-- lint-infra-ignore end -->

This stopped being theoretical on 2026-07-25, when `web-2` landed in `var.web_hosts` on main
while the host did not exist. The per-PR `apply` job then HALTed on **every** merge to main.
The wedge was live, and the only way out went through a laptop.

### Why the HALT is correct and must stay

The obvious fix — weaken the tripwire — is the wrong one, because the HALT is not a
bureaucratic obstacle. It encodes a specific, measured failure:

`-target` is transitive at the resource level, so the per-PR apply's allow-list reaches
`hcloud_server.web` (via `cloudflare_record.app` and `hcloud_firewall_attachment.web`) but
**not** `hcloud_server_network.web`, which is not in the allow-list. A host born on that path
comes up with no private-network IP and — because hcloud provider 1.63.0 documents that
`hcloud_firewall_attachment` (unlike `hcloud_server.firewall_ids`) does not attach before
first boot — transiently no firewall. That is #6416, verbatim.

And the blast radius of getting a birth wrong is asymmetric in a way that matters more than
usual: a host born on an image whose baked `/opt/soleur/host-scripts` disagree with the
applied `local.host_scripts_content_hash` aborts its entire cloud-init `runcmd` at
`stage=verify` — no cloudflared, no deploy webhook, no monitors, no egress firewall.
`runcmd` is **once-per-instance**, so no reboot repairs it. The host is dark until replaced.

A birth is therefore not a routine apply that happens to create something. It is an
operation whose failure mode is unrecoverable-by-retry, on the resource class with the
highest blast radius in the repo.

## Decision

**The `host_creates` HALT is retained on every non-birth route. Exactly one dispatch job is
granted the capability, and it pays for it with gates.**

`apply_target=web-host-create` (in `.github/workflows/apply-web-platform-infra.yml`) is that
job. The tripwire is not removed on this path either — it is **inverted**. "Must never create
a host" becomes "must create exactly the one host that was authorized, and nothing else",
enforced by a sourced gate (`tests/scripts/lib/web-host-birth-gate.sh`) that PASSes only when:

| Condition | Why it is not redundant with the others |
|---|---|
| exactly 1 `hcloud_server` create | A zero-create plan is a no-op the gate must not rubber-stamp; two is a `-target` set that escaped scope. |
| the created address == the requested key | A count-only check passes a plan that births exactly one host that is **not** the one authorized. `web-1` is the singleton behind the `app.soleur.ai` A record. |
| 0 destroys (incl. `forget`) | A replace is `["delete","create"]` — one create to a naive counter, while destroying a live host. |
| 0 reboot-forcing in-place updates | The birth targets `hcloud_firewall_attachment.web`, a singleton over `[for h in hcloud_server.web : h.id]`, which drags every web host into the plan. A `placement_group_id`/`server_type` delta on web-1 power-cycles the sole live origin with zero destroys and a create-count of exactly 1. |
| 0 changes outside the host's ten-address fan-out | Subsumes nested-block shrinkage without re-implementing five provider-schema-shaped counters that drift on the next provider major. The one `cloudflare_*` member — `cloudflare_record.app`, the apex A record, which must re-point on a web-1 birth — is a flat record with no nested rule arrays, so it carries none of the shrinkage surface those counters exist for. Every `cloudflare_ruleset` remains out of scope entirely. |

**A new dispatch job inherits nothing.** The per-PR HALT is a separate inline copy in the
`apply` job whose `if:` is mutually exclusive with every dispatch job. So this gate is not
defense-in-depth behind an existing check — for this path it is the only check, and
`plugins/soleur/test/terraform-target-parity.test.ts` pins the job⇄gate pairing so a future
refactor cannot silently unhook it.

Three further gates, each mapping to an already-observed failure:

1. **ADR-128 R1** — `SENTRY_DSN` asserted non-empty in Doppler `prd_terraform` *before any
   create*, failing closed on an **unreadable** secret as well as an empty one. The
   pre-extraction boot stages emit through the baked `${sentry_dsn}` and nothing else
   (doppler is not installed yet, so its documented fallback is dead code). An empty DSN
   means a failed birth leaves no signal at all.
2. **Digest pin + coherence preflight** — the image is resolved once to an immutable
   `@sha256` ref (from the tag web-1 is actually running, read off-host from its public
   `/health`), and `host-image-coherence-preflight.sh` proves its baked host-scripts
   recompute to the applied hash *before* anything is created. If `/health` is unreadable
   the job aborts rather than falling back to `:latest`: that would trade a retryable
   failure for a permanent one.
3. **R2–R5 boot surfacing** — a green `terraform apply` is not a green boot, and the two are
   indistinguishable without asking Sentry. The job POLLS `de.sentry.io` (R3), filters
   client-side (R4 — the events endpoint ignores `message:` search and returns 0 for events
   that provably exist), and runs `if: always()` (R5).

   The poll, rather than a single read, is load-bearing and was not obvious: `cloud_init_complete`
   is the last line of cloud-init's `runcmd`, and the host's own declared budget is
   `SOLEUR_FRESH_BOOT_WINDOW_SECONDS=900`. A read issued when `terraform apply` returns
   therefore fires roughly fifteen minutes before the signal it looks for can exist, and
   prints "the host genuinely emitted nothing" — the same words a genuinely dark host
   produces. That version satisfied R2's letter while inverting its purpose. The job now waits
   for a terminal state (complete, a fatal, or the deadline) and **fails the run** on either
   bad outcome, which is what makes ADR-128's R2 a signal rather than a step.

The sole human authorization is the `web-platform-infra-apply` GitHub environment's
required reviewer, which holds the job in "Waiting" before its first step. That environment
is now declared in Terraform (`apps/web-platform/infra/web-host-birth-environment.tf`) so its
reviewer set is covered by the DP-11 F8 non-empty-reviewers guard; untracked, it could have
been emptied in the UI, and a zero-reviewer environment auto-approves.

## Alternatives Considered

**(a) Weaken the `host_creates` HALT globally.** Rejected. It is the cheapest fix and it
reintroduces #6416 exactly: the per-PR apply reaches the server but not its
`hcloud_server_network` attachment, so the host it births has no private IP and, transiently,
no firewall. The HALT is not friction to be reduced; it is the encoding of an incident.

<!-- lint-infra-ignore start: the alternative below is REJECTED. It names the laptop-run apply to
     explain why it was not chosen; the whole paragraph is a record of a path not taken. -->
**(b) Keep the operator-local `terraform apply`.** Rejected — this is the rule violation the
work closes. It also does not survive contact with the wedge: with `web-2` declared and
absent, *every* merge to main HALTs until a human is at a laptop with prod credentials.
Retained only as a break-glass appendix in the `host_creates` HALT text and the runbook, for
when the dispatch itself is unavailable.
<!-- lint-infra-ignore end -->

**(c) Auto-birth on merge whenever a new key appears in `var.web_hosts`.** Rejected. It
removes the wedge with no human in the loop, which means an unattended create of a billing
host on the production network as a side effect of merging a variables file. The failure
mode (a dark host that no reboot repairs) is precisely the kind that should not be reachable
without someone deciding it should happen.

**(d) Reuse a sibling gate (`web2-retire-gate.sh`, the luks-cutover gate).** Rejected, and
worth naming because the files look interchangeable. The retire gate requires
`host_creates == 0` — the exact inverse of this contract. Grading a birth against a retire
allow-set is grading it against the wrong operation; the retire gate's own header carries
that warning, and the parity test now asserts the birth job sources no sibling gate.

**(e) Count Cloudflare nested-block deletions inside the birth gate** (mirroring the per-PR
`nested_deletes` counter). Rejected in favour of the allow-set. The per-PR path legitimately
changes Cloudflare resources, so only shrinkage is suspicious there; this path changes none
of them, so "no such address may appear at all" is both stronger and immune to the provider
v4→v5 schema drift already documented as pending.

## Consequences

- Web-host birth is reachable from CI, closing the
  `hr-fresh-host-provisioning-reachable-from-terraform-apply` violation for web hosts.
- Adding a key to `var.web_hosts` still HALTs every subsequent merge until the host is born —
  the wedge is now resolvable by a reviewed dispatch instead of a laptop, but the ordering
  constraint remains and the HALT text says so.
- The pinned digest is honoured at create time only. `hcloud_server.web` carries
  `lifecycle.ignore_changes = [user_data, ssh_keys, image, placement_group_id]`, so a later
  routine apply passing `:latest` will not drift it back. This is intended: the pin is a
  property of the birth, not a standing constraint.
- ADR-128's R1–R5 are now implemented in a job rather than carried by prose in a HALT
  message. That ADR's preamble is amended accordingly.
