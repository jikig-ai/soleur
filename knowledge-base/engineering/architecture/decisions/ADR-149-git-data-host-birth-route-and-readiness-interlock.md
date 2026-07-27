# ADR-149 — The git-data host birth route and its readiness interlock

- **Status:** Accepted
- **Date:** 2026-07-27
- **Issue:** #6977
- **Amended by:** #7003 (operator decisions DC-2, DC-3 — 2026-07-27)
- **Supersedes / amends:** amends ADR-145 (`## Consequences`)
- **Related:** ADR-068 (multi-host workspaces), ADR-103 (operator-applied exclusions),
  ADR-115 (dedicated-host boot convergence), ADR-130 (vendor-scope probes), ADR-143
  (active-active web ingress), ADR-148 (web-host replace)

## Context

`soleur-git-data` is the shared bare-repo store for ADR-068's multi-host workspaces. It has
been declared in IaC since Phase 3 and **has never existed**: an authenticated
`terraform state list` returns 201 addresses and zero git-data members.

No automated route could create it, and the reason is structural rather than an oversight.
`git-data-host-replace` refuses a first birth three separate ways:

1. its `server_replaced` counter requires `actions ⊇ {delete, create}`, and a birth is
   `["create"]`;
2. its `luks_passphrase_touched` arm fires on a **create** of the passphrase, not only a
   rotation;
3. its five-member allow-set produces `out_of_scope ≥ 6` against an eighteen-address birth
   fan-out.

That gate's safety argument rests on **"preserved by omission"** — an untargeted resource
cannot be planned for destroy. On a birth that argument *inverts*: an omitted address is a
**missing** resource, not a protected one. The two operations are therefore siblings by
shape and opposites by contract, and widening one to cover the other would destroy the
property that makes it worth having.

<!-- lint-infra-ignore start -->
The only remaining route was an untargeted `terraform apply` from an operator laptop,
which runs neither the destroy-guard nor the stock preflight. A plan of that shape taken
2026-07-27 carried **nine destroys**. That is a standing violation of
`hr-all-infrastructure-provisioning-servers` and
`hr-fresh-host-provisioning-reachable-from-terraform-apply`.
<!-- lint-infra-ignore end -->
<!-- The region above describes the PRE-EXISTING broken state this ADR REMOVES; it is
     not a prescribed step. The whole point of the decision below is that no operator
     ever runs that apply again. -->


## Decision

Add a dedicated, gated `git-data-host-create` dispatch target mirroring ADR-145's web-host
birth: additive-only, stock-preflighted, with an **inverted** gate (the per-PR
`host_creates > 0` HALT is not removed, it is inverted into "create exactly the one host
that was authorized, and nothing else").

**Ship the route now and hold it with a mechanical interlock**, rather than waiting for
#6982. The alternative — hold the capability by not building it — was considered and is
recorded under *Alternatives*.

### Three deltas from ADR-145, each evidenced

| ADR-145 (web) | Here (git-data) | Why |
|---|---|---|
| `for_each` over `var.web_hosts`; gate takes a host key | **Singleton**; `def allow:` takes no argument | There is one git-data host. The parity test uses the unparameterized extractor as a result. |
| Image digest pinned; coherence preflight; amd64 assert | **None of it** | git-data has no image variable and no `host_scripts_content_hash`. Omitted rather than faked. |
| No LUKS boot dependency | **A LUKS boot dependency** | `cryptsetup luksOpen` needs `GIT_DATA_LUKS_KEY` present in Doppler at first boot. |

A fourth difference is an advantage rather than a delta:
`hcloud_firewall_attachment.git_data` is `server_ids = [hcloud_server.git_data.id]`, a
direct singleton, where the web equivalent is `[for h in hcloud_server.web : h.id]`. **No
other `hcloud_server` can enter this gate's transitive closure**, so no birth dispatch can
power-cycle a live serving host. The gate's reboot arm is therefore a synthesized-fixture
backstop here, not live coverage — recorded so nobody later reads it as protection it is
not providing.

### The birth-readiness interlock

`cloud-init-git-data.yml` emits **nothing** off-host. Measured against the web host's
cloud-init: `sentry_dsn` 0/9, `vector` 0/14, `betterstack` 0/2, `journald` 0/7,
`heartbeat` 0/1, `trap on_err` 0/1.

Combined with the fact that **nothing in the boot path fails closed** — the Doppler install
`runcmd` has no `set -e`, and the LUKS block's `set -euo pipefail` is line 1 of the heredoc
that `doppler run` *executes*, so on a missing or wrong-arch binary it never runs at all —
this yields the property that motivates the whole design:

> **A green `terraform apply` and a dark host are indistinguishable for git-data.**

ADR-145's readiness gates presuppose the host reports; its R2–R5 boot poll has no analogue
here because there is nothing to poll. So the route refuses to apply until an emitter
exists.

**Mechanism:** a sourced, suite-covered gate
(`tests/scripts/lib/git-data-birth-readiness-gate.sh`) whose sentinel is the terraform
interpolation `${sentry_dsn}` in **non-comment** template text. That choice is
load-bearing: `templatefile` fails on a variable the caller does not supply, so the marker
cannot exist without `git-data.tf` actually threading the DSN into the host — wiring the
sentinel *is* the work. A comment-only back-reference to #6982 is explicitly permitted and
is asserted **not** to release the gate. This mechanism is **interim**; checklist item 7
mandates its replacement by a direct assertion on the emitter resource once #6982 defines one.

**Scope-honest claim:** the interlock makes a dark boot unreachable **from this route**. It
does not make it impossible — a break-glass laptop apply is unaffected by anything in this
repository. An earlier draft said "impossible"; that overstated it.

### Interlock release checklist — #6982 inherits this

1. Ship the off-host emitter and thread `sentry_dsn` through `git-data.tf`'s `templatefile`
   vars block.
2. Confirm the emitter's credential is reachable within
   `doppler_service_token.git_data`'s **single-config** scope. An emitter reading its DSN
   from Doppler is dark *by construction* today; wiring the sentinel without this releases
   the gate and changes nothing observable.
3. Add any new address the emitter introduces to **all three** of: the `-target` set, the
   gate's `def allow:`, and `GIT_DATA_BIRTH_TARGET_BASES`.
4. Provide a post-apply signal to replace ADR-145's dropped R2–R5 boot poll. Note the
   partial signal that already exists: `web-git-data-probe.service` runs on the web host
   and ships to Better Stack via Vector journald, emitting
   `SUPPRESS ping: 10.0.1.20:22 UNREACHABLE` today. On a successful birth those lines stop.
   It observes reachability, not boot correctness, so it is a floor to build on rather than
   the signal itself.
5. **Produce `GIT_DATA_SSH_HOST`** (`doppler_secret.git_data_ssh_host`, cut from #6977 as a
   feasibility regression — see *Alternatives*). Without it `resolveGitDataSshHost()` throws
   in production on every account deletion, so the birth converts a dormant Art. 17 path
   into a 100 %-false-alarm one. Residual 2 below has the measurement.
   **Operator decision, 2026-07-27 (DC-3): the cut stands, and this is where it lands.** Two
   mechanical constraints ride with it. First, it MUST single-source the address from
   `hcloud_server_network.git_data.ip` — never a fresh copy of the `10.0.1.20` literal. (The
   nearest precedent is #6415, which removed exactly such a duplicate on the sibling
   `hcloud_server_network.registry`; note it routed that resource through a `local` that still
   holds the string, so this mandate goes one step further and reads the resource attribute
   itself.) Second, its `OPERATOR_APPLIED_EXCLUSIONS` entry MUST land in the **same change**,
   because it is the absence of that entry that makes `terraform-target-parity.test.ts` red on
   landing and drives the remedy that wedges `main`.
6. Correct the `hcloud_firewall_attachment.git_data` entailment rule if it has not already
   been corrected — see *Requirement arm split by entailment*.
7. **Replace this interlock's mechanism with a direct assertion on the emitter resource, and
   delete the cloud-init text sentinel.** Operator decision, 2026-07-27 (DC-2). Once this issue
   defines the emitter as a real Terraform resource,
   `tests/scripts/lib/git-data-birth-readiness-gate.sh` must assert **that resource** rather than
   grep template text, and the `${sentry_dsn}` sentinel must be **removed**, not kept alongside
   it. This answers `dhh-rails-reviewer`'s *"prose with a `grep` wrapper"* and
   `architecture-strategist`'s structural objection at the root rather than by wrapping them. The
   falsification recorded under DC-2 does **not** license skipping this: what it killed was
   reading `heartbeat-manifest.ts`'s already-true `kind: "timer"` declaration — not reading the
   emitter's own resource, which cannot exist before this issue creates it. Until then the
   `${sentry_dsn}`-pinned sentinel stays exactly as shipped. **Accepted cost: a mandated interlock
   rewrite, not an optional cleanup.** Note that completing this retires the only mechanical check
   on item 1's threading — the replacement asserts a different fact — so item 1 is **absorbed**
   here, not left unenforced.
8. Clear the DO-NOT-DISPATCH banner in `git-data-birth.md`. *(Terminal: the runbook clears it only
   when every item above is done.)*

**The gate mechanically enforces only the THREADING half of item 1** — that `sentry_dsn`
reaches non-comment template text, which `templatefile` makes impossible to fake. It cannot
verify the emitter actually *emits*: a non-comment line that merely references the variable
releases it. The remaining items are not machine-checked at all, and the gate's own success message
says so. A gate believed to cover more than it does is worse
than one whose scope is written down.

### Requirement arm split by entailment

The gate demands `creates == 1` for the **three** addresses whose STATE IDENTITY is the
server (the NIC and both volume attachments), an **outcome** assertion for the firewall
attachment, and mere **presence** (`create` ∨ `no-op`) for the other thirteen.

**`.id`-reference is not the property that governs entailment — state identity is**, and
the two diverge on exactly one member. `hcloud_firewall_attachment`'s terraform ID is the
FIREWALL's id (provider v1.63.0, `internal/firewall/attachment_resource.go`), and its read
evicts only when the *firewall* is nil. So when the server is destroyed outside terraform —
the exact scenario the TOO LOOSE case below describes — the attachment survives refresh
with `server_ids` emptied and the re-birth plans an in-place **update**, not a create.
Demanding a create there aborts the re-birth with a wrong diagnosis and wedges it, which is
the TOO STRICT failure arrived at from the other direction. It therefore asserts the
outcome (`server_ids` ends at length 1, bound to this plan's own firewall), which holds on
both a first birth and a re-birth. The web precedent states this reasoning for its own
fleet attachment; an earlier draft of this ADR dropped it.

`depends_on` is an ordering edge and entails nothing — only `.id` references qualify, and
then only when state identity follows.

This is the most consequential contract in the design, because getting it wrong breaks the
gate in both directions:

- **Too strict → a permanent wedge.** `random_password.git_data_luks` is dependency-free
  and lands in Terraform's first wave. On a dispatch whose server create fails after it
  lands, the re-dispatch re-plans it as `no-op`, so a gate requiring its create aborts on
  every retry forever. The replace gate cannot rescue the operator either (it needs a
  delete on a resource that does not exist), leaving only the laptop apply this work
  exists to eliminate.
- **Too loose → it authorizes the ADR-115 catastrophe.** Host born, data written, host
  destroyed outside Terraform, volumes retained, passphrase absent from state: a gate that
  *mandates* a fresh passphrase hands the host a new key, `isLuks` declines to reformat,
  and the existing at-rest data is permanently unopenable.

### Two ordering edges added to the IaC

- `hcloud_server.git_data` now `depends_on` `doppler_secret.git_data_luks_key`. There was
  no edge in **either** direction: the service token is upstream, but a token is an
  authorization to *read* the config, not evidence the config *contains* the key. Terraform
  was free to boot the host first, and the resulting failure is silent.
- The three SSH `doppler_secret`s now `depend_on` `hcloud_server.git_data`. The remove
  key's **presence is the arming switch** for Art. 17 erasure (`removeGitDataRepo` is
  deliberately not gated on the store flag — flag-gating erasure would strand PII across a
  rollback window), so a partial apply landing that key without the host makes every
  account deletion file a **false** "Art. 17 erasure failed" Sentry event.

### `prd_git_data` is provisioned, not hand-created

The config was verified **absent** and both Doppler writes target it. It is now
`doppler_config.git_data_prd`. Capability was **probed, not inferred**: a live
`POST /v3/configs` for a throwaway branch config returned `200` with `root:false`, and the
throwaway was deleted (ADR-130 shape — a branch config is a distinct API surface from the
`doppler_environment` this token already provisions).

The already-exists mode was measured too: it **errors** (`400 "Name is already in use"`)
rather than adopting, so a hand-created config makes the birth apply fail and the remedy is
`terraform import`, not a re-dispatch.

## Consequences

- git-data has an executable birth route for the first time. It is held, and the hold is
  mechanical rather than procedural.
- The `hr-all-infrastructure-provisioning-servers` violation is closed for this host.
- One human step is **deleted** rather than documented (the Doppler config), so the
  post-merge operator checklist for this work is genuinely empty.
- A new per-target gate adds maintenance surface. Mitigated by extracting the shared
  fail-closed preamble (`plan-gate-preamble.sh`); issue #6997 covers retrofitting it into
  the **eight** gates that carry neither the readability nor the classifiability check.
  The count is re-derived, not remembered — earlier revisions of this ADR said "five" and
  the preamble header said "seven", and both were wrong. Re-derive before citing it:
  `grep -l 'local plan_json' tests/scripts/lib/*gate*.sh | xargs grep -L plan_gate_assert_readable`.
  Three further gates (`web-host-birth`, `web-host-replace`, `stock-preflight`) carry
  equivalent INLINE checks, so their retrofit is pure deletion and changes no safety
  property; the eight are the fail-open tier and are the priority.

### Residuals, accepted and recorded

1. **ADR-115 guest-convergence gap.** A tfplan assertion proves Terraform *planned* the NIC
   attach; it never proves the guest *configured* it. git-data is barred from ADR-115's
   remedy (the reboot primitive), so the only repair for a mis-converged guest is
   replacement.
2. **The Art. 17 false-alarm is UNCONDITIONAL after any birth, not contingent on a partial
   one.** An earlier draft of this residual said "a birth where the server lands but the NIC
   does not still arms the remove key against an unroutable `10.0.1.20`". That is wrong for
   production, and the correction matters because it changes who must act.

   `resolveGitDataSshHost()` returns the `10.0.1.20` default **only when
   `NODE_ENV !== "production"`**; in prd it throws. `GIT_DATA_SSH_HOST` has **no producer
   anywhere in the repo** — `doppler_secret.git_data_ssh_host` was cut to #6982 (see
   *Alternatives*). So after **any** successful birth plus the next `ci-deploy`, the remove
   key is present, the arming switch is on, and **every** account deletion throws and files
   a false "Art. 17 erasure failed" Sentry event — deterministically, whether or not the NIC
   landed.

   The reasoning that hid this was in the DC-3 disposition: *"`depends_on` guarantees it can
   never land without the server."* True, and it is the wrong direction — `depends_on`
   guarantees the key **co-lands with** the server, and co-landing is precisely the harmful
   state. "Unreachable today" was true; "unreachable once this route is used" was not.

   Consequence: **`GIT_DATA_SSH_HOST` must be produced before the first dispatch**, and it
   is item 5 of the release checklist below. It was absent from the checklist entirely,
   so #6982 could have satisfied every listed item and still shipped this.
3. **Empty-store Art. 17 silent success.** Post-birth and pre-cutover the store is empty and
   `git-data-remove.sh` is idempotent, so an erasure request exits 0 and records **success**
   for a repo the store never held. Closing this needs a birth-completion marker the app can
   read — #6982/#5274 scope.
4. **The interlock does not bind the break-glass path.** By construction.

## Alternatives considered

| Alternative | Verdict |
|---|---|
| Widen `git-data-host-replace` | **Rejected.** Its safety argument is "preserved by omission", which inverts on a birth. ADR-145 records the same rejection for web. |
| Keep the untargeted laptop apply | **Rejected** — the violation this closes; a plan of that shape carried nine destroys. |
| Inline the gate in the workflow YAML | **Rejected on evidence.** Untestable, and it fails the parity job⇄gate pairing. An earlier draft then shipped the *interlock* inline, contradicting itself; corrected. |
| Ship the route with no interlock, hold by convention | **Rejected.** A capability held only by prose is held until the first person who reads the runbook and not the plan — and #6982 contains items ADR-115 makes unfixable after birth. |
| Target the heartbeat too | **Rejected.** The feeder already shipped and is web-host-resident; creating a monitor this route cannot arm is the #6537 fed-but-paused shape. #6548 owns it. |
| Include `doppler_secret.git_data_ssh_host` | **Cut** — a feasibility regression: it would make `terraform-target-parity.test.ts` red on landing, and the natural remedy drags `hcloud_server.git_data` into the per-merge plan and wedges every merge to `main`. Moved to #6982. **The operator upheld the cut on 2026-07-27 (DC-3)**, adding two mechanical constraints now recorded in release-checklist item 5: single-source the address from `hcloud_server_network.git_data.ip`, and land the `OPERATOR_APPLIED_EXCLUSIONS` entry in the same change. The dissent and the decision are recorded in `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md` (PR #6989). |
| Ship gate + suite now, enum + job in #6982 | **Considered and declined by the operator.** It would delete the interlock entirely by removing the capability, but #6977 would no longer deliver an executable route and would close on a partial. Recorded as DC-1. |
