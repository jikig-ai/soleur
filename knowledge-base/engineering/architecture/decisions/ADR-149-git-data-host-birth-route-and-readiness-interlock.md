# ADR-149 — The git-data host birth route and its readiness interlock

- **Status:** Accepted
- **Date:** 2026-07-27
- **Issue:** #6977
- **Amended by:** #7003 (operator decisions DC-2, DC-3 — 2026-07-27); #7025 (DC-6 — the
  rung-2 rehearsal route, shipped unfired, 2026-07-29)
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
3. its five-member allow-set produces `out_of_scope ≥ 6` against a twenty-address birth
   fan-out (eighteen when this ADR was written; #6982 added two Doppler secrets).

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
is asserted **not** to release the gate. This mechanism is **interim**; the release-checklist item
titled *"Replace this interlock's mechanism with a direct assertion on the emitter resource"*
mandates its replacement once #6982 defines one.

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
   mechanical constraints ride with it. First, `doppler_secret.git_data_ssh_host` MUST
   single-source the address from
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
   delete this gate's `${sentry_dsn}` text check.** Operator decision, 2026-07-27 (DC-2). Once
   **#6982** defines the emitter as a real Terraform resource,
   `tests/scripts/lib/git-data-birth-readiness-gate.sh` must assert **that resource** rather than
   grep template text, and the gate's text check must be **removed**, not kept alongside it.
   **What is deleted is the gate's grep, not the interpolation it greps for:** the `${sentry_dsn}`
   interpolation in `cloud-init-git-data.yml` is required by item 1 and must stay — removing it
   would un-wire the DSN and recreate the dark-host condition this ADR exists to close. This
   answers `dhh-rails-reviewer`'s *"prose with a `grep` wrapper"* and `architecture-strategist`'s
   structural objection at the root rather than by wrapping them. The falsification recorded under
   DC-2 does **not** license skipping this: what it killed was reading `heartbeat-manifest.ts`'s
   already-true `kind: "timer"` declaration — not reading the emitter's own resource, which cannot
   exist before #6982 creates it. Until then the `${sentry_dsn}`-pinned sentinel stays exactly as
   shipped. **Accepted cost: a mandated interlock rewrite, not an optional cleanup.**
   **Two consequences to carry, not to assume away.** (a) Completing this retires the only
   mechanical check on item 1's threading. The replacement asserts a *different* fact — that a
   Terraform resource exists, not that `sentry_dsn` was threaded into the host's cloud-init — so
   item 1's threading becomes mechanically unenforced unless the replacement also asserts it.
   That is an accepted consequence of the decision, recorded here so it is not mistaken for
   coverage. (b) The gate today runs BEFORE the plan, on a cloud-init path, so an operator learns
   the route is held in seconds without contacting a provider (see
   `apply-web-platform-infra.yml`). A resource assertion that reads the plan must move after the
   plan step and forfeits that fast refusal; one that greps `git-data.tf` source keeps it but is
   still text-grepping. Which to choose is #6982's call — the pre-plan placement is worth
   preserving if it can be.
   **If #6982 ships the emitter without introducing a Terraform resource to assert**, this item is
   not satisfiable as written: the sentinel stays, and that outcome must be recorded here before
   item 8 is cleared.
8. Clear the DO-NOT-DISPATCH banner in `git-data-birth.md`. **Since #6982 this item is no
   longer held by prose alone:** releasing the `${sentry_dsn}` sentinel gate (item 1) retired
   the only mechanical hold, so #6982 added a SECOND interlock,
   `git_data_rung2_rehearsal_gate`, which the dispatch job runs alongside the first. It
   requires committed rung-2 boot evidence hash-bound to the template being dispatched, and
   re-holds automatically on any later edit to `cloud-init-git-data.yml`. #7025 carries rung 2
   and lands that evidence. *(Terminal: `git-data-birth.md`
   instructs that it be cleared only when every item above is done.)*
9. **Confirm the SIZING before the first birth** (added by #6982). The checklist had no
   sizing item and neither does the runbook's pre-dispatch table — step 7's stock preflight
   checks **orderability**, never **adequacy**. `user_data` is ForceNew and a `server_type`
   change routes through the DESTRUCTIVE `git-data-host-replace`, so the shape has to be
   right at birth. ADR-068's D-SIZE addendum records the decision (`cpx22`, unmeasured,
   sized for the burst with the burst now bounded by W4's git config + the gc timer).

### Disposition — #6982 (2026-07-27)

| Item | Status |
|---|---|
| 1 — emitter + `sentry_dsn` threaded | **DONE.** One `/usr/local/bin/git-data-emit` (ADR-147's #6982 addendum records why it is a file and not an inline function). |
| 2 — credential reachable in the token's single-config scope | **DONE, and it found a live boot-breaker.** The probe measured that `doppler run --config prd` under a `prd_git_data`-scoped token **exits 1** with `GIT_DATA_LUKS_KEY` absent — so `doppler run` was exiting BEFORE exec'ing the LUKS heredoc, its `set -euo pipefail` ran zero times, and the host would have booted dark with sshd up. Both invocations corrected to `--config prd_git_data`. This is exactly the "dark by construction" trap this item exists to catch, and it was sitting inside the file the interlock inspects. |
| 3 — new addresses registered | **DONE, and the item understated the work: there are SIX sites, not three.** The gate carries `def allow:` (a PERMISSION set) *and* a separate hardcoded PRESENCE loop (a COMPLETENESS set) that nothing extracted, so a three-of-four edit was fully green — an address PERMITTED to change but not REQUIRED to appear, which is Residual 2's harm hiding behind a PASS. Set is 18 → 20. |
| 4 — post-apply signal | **DONE, host-side.** `stage:boot_complete` from `git-data-bootstrap.sh` **plus a poll that reads it** inside the birth job (`if: always()`). A producer with no reader is not a signal. |
| 5 — `GIT_DATA_SSH_HOST` | **SHIPPED, BOTH CONSTRAINTS MET.** `doppler_secret.git_data_ssh_host` ships and its `OPERATOR_APPLIED_EXCLUSIONS` entry lands in the same change (second constraint). The first constraint — single-source from `hcloud_server_network.git_data.ip` — is now met **as written**: the value reads that computed attribute. #6982's first draft shipped `local.git_data_private_ip` and recorded the divergence as DC-5 on the grounds that the computed attribute is unappliable pre-birth; **review refuted that** and the divergence was reversed before merge. See the DC-5 reversal note below. |
| 6 — firewall entailment | **ALREADY DISCHARGED on `main`**, verified rather than assumed: the gate splits the attachment out of the entailed loop and asserts the OUTCOME (`server_ids` ends at length 1). No code change. |
| 7 — replace the interlock mechanism (DC-2) | **NOT SATISFIABLE AS WRITTEN — recorded here per this item's own instruction.** #6982 ships the emitter as a FILE inside `user_data` (`/usr/local/bin/git-data-emit`), not as a Terraform resource: git-data has no bake path, so there is no resource to assert. ADR-147's #6982 addendum records that divergence. Per item 7's closing clause the `${sentry_dsn}`-pinned sentinel therefore **stays exactly as shipped**, and this recording is the precondition item 7 places on clearing item 8. |
| 8 — clear the banner | **DELIBERATELY NOT DONE.** Moved to its own follow-up PR (**#7025**) whose precondition is the W12 rung-2 rehearsal evidence. A PR merges atomically, so a banner cleared in the final commit clears at the same instant as the untested code it is supposed to be downstream of. **STILL OPEN after #7025** — see the #7025 disposition below: that PR shipped the *route* that produces the evidence, deliberately unfired, and the same atomicity argument applies to it with equal force. |
| 9 — sizing | **DONE** (ADR-068 D-SIZE). |

### Disposition — #7025 (2026-07-29): the rung-2 rehearsal route, shipped UNFIRED

Item 8's precondition — rung-2 boot evidence — had **no producer**. Verified rather than
assumed: `grep -rln 'rung2\|rung-2' .github apps/web-platform/infra tests scripts` returned
only the apply workflow and the gate/test pair. Nothing booted a throwaway host and nothing
captured the artifacts, so the gate was waiting on something that could only have happened as
a hand-run laptop procedure.

#7025 ships **the route, not the run**, mirroring how `registry-luks-recut` shipped as an
unfired vehicle:

- `.github/workflows/git-data-rung2-rehearsal.yml` — `workflow_dispatch` only, confirm token
  `REHEARSE-GIT-DATA`, `dry_run` default **true**, `teardown_only` recovery arm,
  `permissions: contents: read`.
- `apps/web-platform/infra/rung2-rehearsal/` — a separate Terraform root (**DC-6**).
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — three-state capture that
  writes the evidence file only on PASS.

**Item 8 remains OPEN, and item 7 is untouched.** The atomicity argument that moved item 8
out of #6982 applies to #7025 unchanged: a banner cleared in the same PR that builds the
harness clears at the same instant as the never-executed harness it is supposed to be
downstream of. The evidence file is deliberately not committed, both interlocks still hold,
and the banner stays up.

**CORRECTION (2026-07-30, first dispatch).** The route as merged **shipped unable to produce
evidence at all**, so item 8's precondition stayed unproducible rather than merely unmet.
Measured on the first real dispatch (run 30560266736, `dry_run=false`, 2026-07-30): the
capture step's bounded poll executed **one of its twenty attempts** and the step exited 2
3.4 seconds after it began. GitHub invokes a bare `run:` as `bash -e {0}`, and the step's
`set -uo pipefail` does not clear that inherited `-e` — omitting a flag from `set` cannot
unset what the invocation already applied — so under `pipefail` the TRANSIENT rc=2 that the
poll exists to retry killed the step. Since attempt 1 fires minutes before cloud-init can
emit `stage:boot_complete`, rc=0 was unreachable, PASS was unreachable, and no dispatch could
have released `git_data_rung2_rehearsal_gate`. Teardown and the Hetzner survivor assertion
both ran, so the host was reclaimed and the failure left nothing behind.

This is the same shape as the vehicle-shipped-unfired argument above, one level down: the
harness merged, and the thing that could only be learned by *running* it was that it could
not run. Fixed under `Ref #7025` (`set +e` / pipeline / `rc=${PIPESTATUS[0]}` / `set -e`,
in that order — `set -e` is a builtin, therefore a pipeline, therefore it resets
`PIPESTATUS`), together with a behavioural guard that executes the extracted step body,
because the 43-assertion drift suite was fully green against the broken poll.

Nothing in `## Decision`, the interlock's contract, or the alternatives table changes.

**A clarification of item 4's *"poll that reads it"*, and a second fix.** The #6982
disposition row above already names the birth job explicitly, so item 4 was not ambiguous
there; what lacked a location was the Alternatives-table restatement (*"Item 4 is satisfied
HOST-SIDE instead, by the `stage:boot_complete` emit plus a poll that reads it"*). For the
record: that poll is the **birth-job** poll in `apply-web-platform-infra.yml`, step *"Poll
for the git-data boot-completion signal"* — not the rung-2 capture poll, which did not exist
when item 4 was written.

That birth poll carried the same defect on the higher-stakes path. Its
`out=$(bash scripts/betterstack-query.sh …); rc=$?` died at the assignment under the
inherited errexit, so the `rc=$?` capture, the `[[ $rc -eq 0 ]]` guard and the
`poll ${i}/20: rc=${rc}` fall-through retry were all unreachable — one transient Better Stack
error (a rate limit, a 5xx, its own `exit 64`) killed the birth job mid-poll with no
annotation instead of retrying. Its empty-result path returns 0, which is why the common path
polled fine and hid it. Fixed inline in the same change: the operator reaches it on the very
next dispatch after rung 2 passes.

#### DC-6 — the rehearsal runs in a SEPARATE Terraform root

`-target` is **transitive on dependencies**. A rehearsal address referencing any prod
`git_data` attribute would drag `hcloud_server.git_data` into the plan closure, and a
rehearsal apply reaching that address would create the production git-data host outside the
birth route — bypassing its environment reviewer, its confirm token, both interlocks and its
`-target` allow-set. That host would hold every connected user's source code and would have
been born by a workflow whose approval prompt said "rehearsal".

Alternatives considered:

| Option | Disposition |
|---|---|
| `count`-gated resources in `apps/web-platform/infra/` | **Rejected.** Looks equivalent, is not — this is the same `for_each`-over-target-excluded-map hazard, and `count = 0` does not remove an address from a plan closure reached through a reference. |
| A throwaway Hetzner account/project | **Rejected.** No such isolation exists in this account. |

**The isolation claim is NARROWER than an earlier draft stated,** and the correction is
recorded here in the same register the sentinel gate's own header already had to use once
("an earlier draft said *impossible*; that overstated it"). A separate state file is
structural **only for Terraform's managed-resource lifecycle**. It does not isolate: the
Hetzner project credential, the Doppler project (only the *config* is scratch), the Sentry
project (deliberately — the rehearsal must exercise the real channel), or the parent root's
push-triggered apply (mitigated by a `paths` negation, which is a workflow property, not a
state one).

**Named residual — teardown garbage collection.** Nothing outside the workflow's
`if: always()` destroy and the new orphan sweep DETECTS a resource the rehearsal state has
forgotten. `terraform plan` reports on resources *in state*, so a host lost from state is
invisible to every plan in this repository, forever. The sweep therefore asks the Hetzner API
directly and fails closed on an unreachable API. An earlier draft claimed the existing
scheduled drift run would surface such a host; that was false on two counts (its matrix
excludes this root, and plan cannot see off-state resources) and the claim was struck rather
than weakened.

#### The hash binds SOURCE FILES, not render vars — recorded, not assumed away

`RUNG2_TEMPLATE_SHA256` is a hash-of-hashes over the cloud-init template plus every
`file()`-bound payload. It does **not** bind the `templatefile` arguments, so a rehearsal that
diverged on the wrong one produces hash-valid evidence for a boot production would not get.
`doppler_arch` and `doppler_sha256` are the sharp case: they select which binary is downloaded
and which checksum verifies it, so a mis-derived pair verifies the tarball it just chose and
passes — the #6570 boot-brick class, rehearsed away rather than rehearsed.

Closed by **declaration**, not by inference: the capture script writes `RUNG2_VAR_DIVERGENCE`
and the gate refuses any entry outside a **closed, identity-only** allowlist (`host_name`, the
two volume ids, the Doppler token and config name, the three pubkeys). An unrecognised name
refuses too — a typo'd or newly-introduced var is exactly where "not on a deny list" and
"safe" come apart.

#### Consequential decision: the render moved to a shared module, and the gate followed

Avoiding a third copy of the templatefile map was not cosmetic. The evidence hash is over
**source files**, so two copies that drift produce a **byte-identical hash for a different
render** — the rehearsal would attest a payload it did not boot, and the attestation would
verify. The self-invalidation property this whole binding exists to provide does not fire on
that class at all.

So `modules/git-data-userdata/` now owns the strip expression and the map, and both roots call
it. That **forced** a change the plan did not spell out: the gate derived its payload set by
grepping `git-data.tf` for `file("${path.module}/…")`, which the move empties — tripping the
floor-of-10 `ABORT`. The derivation now reads the module's `main.tf` and resolves against the
module directory. The hash **value** is unchanged across the move only because of the
path-invariance fix below.

#### A shipped defect fixed in passing: the hash was not path-invariant

The derivation piped resolved *paths* through `xargs sha256sum`, whose output embeds each
path. Measured on the live tree, identical bytes hashed three ways:

| Invocation form | Hash |
|---|---|
| `apps/web-platform/infra/<name>` | `aa1447f2b3bfa964707e1d8a0f51f866b0de1b917eb628a92575d6fe52349ff3` |
| `<name>` (cwd = `infra`) | `dcaa128171114639a3d011c77fe354510f03903ed547d8851a3075c5dd677733` |
| `/abs/path/<name>` | `b77f4998413b684860aa6dd55f69b089ab0c1818962628625ab8fd7dc4b89a59` |

Production invokes the gate with `${GITHUB_WORKSPACE}/…`; a capture script or a laptop run
does not. Evidence captured at one cwd would have read `STALE EVIDENCE` **forever**, and the
message would have blamed a template edit that never happened — a diagnosis that is both
actionable and false. Now hashes `<sha>  <basename>` under `LC_ALL=C`, with a basename-
uniqueness guard (a collision would silently bind the evidence to fewer files than ship). Free
to fix only because no evidence file exists yet; after the first one is committed, changing the
derivation invalidates it.

#### The release checklist's "Sentry event from the fatal channel" was unsatisfiable

The runbook's release condition demanded a Sentry event *from the fatal channel* as evidence of
a **successful** rehearsal. The fatal channel fires only on failure — a clean boot emits `info`
— so that clause could be met only by a rehearsal that failed, or by fabricating it. Corrected
in the runbook: the fatal channel is proven at **rung 1** by `git-data-runcmd-rehearsal.test.sh`
(the trap fires and emits `fatal`), and rung 2's job is the real-host facts rung 1 cannot reach
— TLS egress from a real host, a real `doppler run`, a real `cryptsetup luksOpen`.

Related, and it changed the capture design: `stage:bootcmd_start` reaches **Sentry only**. It is
a bare `curl` in `bootcmd`, which runs before `write_files`, so `/usr/local/bin/git-data-emit`
does not exist yet. That half still holds.

> **Superseded in part by #7460 (ADR-198).** The sentence that followed — "the emitter's Better
> Stack block is gated on `BETTERSTACK_LOGS_TOKEN`, present only under `doppler run`. On a
> successful boot the **only** Better Stack row a git-data host produces is `boot_complete`
> itself" — is the exact claim ADR-198 quotes as its problem statement. The token is now baked
> at `0600` in `user_data`; eight of the nine stages reach Better Stack. Only `bootcmd_start`
> remains Sentry-only, and that is by construction, not by token availability. The plan specified anchoring the empty-query discipline
on `bootcmd_start`; that anchor is a strict prerequisite of the thing it anchors and would have
returned zero rows on a perfect rehearsal, forever, reading as a dark boot. The capture script
anchors on **source liveness** instead (any row from any *other* host), which separates "the
host was silent" from "the instrument was broken" — the only two readings that matter.

#### DC-5 REVERSED — item 5's mandated mechanism IS satisfiable (#6982 review, 2026-07-29)

The subsection below argued that reading `hcloud_server_network.git_data.ip` makes the secret
unappliable in the pre-birth window, and recorded the divergence as DC-5. **That reasoning was
refuted during #6982's review and the code now reads the mandated computed attribute.**

The refutation: the secret's ONLY `-target` line is the birth job, which already targets BOTH
`hcloud_server.git_data` and `hcloud_server_network.git_data` — so the new edge drags nothing
into any plan that exists. And there is no pre-birth window to protect, because the secret is
created BY the dispatch rather than before it. The mandated form is also strictly stronger: it
closes Residual 2, since a birth that lands the server but not the NIC can no longer publish an
address nothing answers on.

The original argument is preserved below as the record of what was believed and why, not as a
live claim. Where it says the mechanism "is not satisfiable", read "was believed unsatisfiable,
and is not".

#### (superseded) Item 5's mandated mechanism is not satisfiable pre-birth

DC-3's mandate — *single-source from `hcloud_server_network.git_data.ip`* — and this
checklist's own **"produce it BEFORE the first dispatch"** requirement (Residual 2) cannot both
hold. `hcloud_server_network.git_data` depends on `hcloud_server.git_data.id`, so a secret that
reads its `ip` attribute cannot be planned or applied while the host is absent — which is the
entire window in which the secret has to exist. Reading the attribute would also restore the
very `-target`-closure edge to `hcloud_server.git_data` that DC-3 cited as its reason for
cutting the resource from #6977.

`local.git_data_private_ip` (`git-data.tf`) resolves both: it is the **single** source both
`hcloud_server_network.git_data.ip` and the secret read, so no second `10.0.1.20` literal
exists anywhere in the repo, and the secret carries no edge to the server. The mandate's stated
harm (*"never a fresh copy of the `10.0.1.20` literal"*) is closed; its prescribed mechanism is
not used. Surfaced to the operator rather than decided silently — recorded as **DC-5** in
`knowledge-base/project/specs/feat-one-shot-6982-git-data-pre-birth-hardening/decision-challenges.md`.

**The gate mechanically enforces only the THREADING half of item 1** — that `sentry_dsn`
reaches non-comment template text, which `templatefile` makes impossible to fake. It cannot
verify the emitter actually *emits*: a non-comment line that merely references the variable
releases it. The remaining items are not machine-checked by this gate, and its own success message
says so. A gate believed to cover more than it does is worse
than one whose scope is written down.

### Requirement arm split by entailment

The gate demands `creates == 1` for the **three** addresses whose STATE IDENTITY is the
server (the NIC and both volume attachments), an **outcome** assertion for the firewall
attachment, and mere **presence** (`create` ∨ `no-op`) for the other **fifteen** (thirteen
until #6982 added `doppler_secret.git_data_ssh_host` and
`doppler_secret.git_data_betterstack_logs_token`). 1 + 3 + 1 + 15 = the twenty-address
fan-out below. The presence set is the gate's own list, and
`tests/scripts/test-git-data-host-birth-gate.sh` pins it against the fixture as a set in
both directions, so this number cannot drift silently:

```
awk '/for present_addr in/,/; do$/' tests/scripts/lib/git-data-host-birth-gate.sh \
  | grep -coE '"[a-z0-9_]+\.[a-z0-9_]+"'          # => 15
```

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
  fail-closed preamble (`plan-gate-preamble.sh`). **#6997 completed the retrofit**: of the
  **thirteen** gates that grade a plan document, **eleven** now call the preamble. The two
  that do not — `stock-preflight-gate.sh` and `web-host-replace-gate.sh` — are tracked in
  **#7044**.

  The count is re-derived, not remembered — earlier revisions of this ADR said "five" and
  "eight", and the preamble header said "seven"; all were wrong. Re-derive before citing:

  ```bash
  grep -l 'local plan_json' tests/scripts/lib/*gate*.sh \
    | xargs -r grep -LE '^\s*plan_gate_assert_readable'
  ```

  **The form this ADR published before #6997 was vacuous, and the fix is not cosmetic.**
  A bare `grep -L plan_gate_assert_readable` is a PRESENCE check: every retrofitted gate
  contains that literal inside its `if ! declare -F plan_gate_assert_readable` re-source
  guard, so a gate that *sources* the preamble and never *calls* it satisfied the published
  command and reported clean. That is precisely the "sourced but not invoked" vacuity the
  retrofit had to be proved against, sitting inside the command meant to police it. The
  `^\s*` anchor matches the call form, which `if ! declare -F …` does not. `xargs -r` is
  equally load-bearing: without it an empty first stage leaves `grep -L` with no operands
  and it reads STDIN (measured: `printf '' | xargs grep -L PAT` prints `(standard input)`
  and exits 0), so a broken glob reports clean rather than failing.

- **CORRECTION.** An earlier revision of this ADR stated that `web-host-birth`,
  `web-host-replace` and `stock-preflight` "carry equivalent INLINE checks, so their
  retrofit is pure deletion and changes no safety property". **Reading them disproved it**,
  and #6997 acted on the corrected reading:

  - None of the three carried the preamble's `(.change.actions | length) > 0` conjunct, so
    an entry with `"actions": []` passed all three. That is the **measured** hole: a happy
    18-address birth plan that also carried `hcloud_server.web["web-1"]` with
    `"actions": []` and `"after": null` — a destroy of the singleton behind `app.soleur.ai`
    — scored `destroys=0, out_of_scope=0` and **PASSED**.
  - `web-host-birth` and `stock-preflight` used the NEGATIVE-search form
    (`if jq -e '[…|select(bad)] | length > 0'`), which reads a jq **error** as "condition
    false" — so a scalar `.change` reported the plan classifiable.
  - `stock-preflight`'s readability check is `jq -e '.resource_changes'`, a truthiness test
    rather than a type test.
  - Conversely `web-host-replace-gate.sh` carried a conjunct the shared helper did **not**
    (`all(.change.actions[]; type == "string")`, closing a nested-array case), so
    retrofitting it onto the helper as it stood would have been a **regression**. #6997
    added that conjunct to the helper first, before any gate moved.

  So `web-host-birth`'s retrofit was a strict strengthening, not a deletion. It was folded
  into #6997's scope; the other two are deferred to #7044.

- **Priority by call sites, not by tier label.** `stock-preflight-gate.sh` is sourced **8×**
  by `apply-web-platform-infra.yml` — more call sites than any gate #6997 retrofitted —
  while `web2-retire-gate.sh`, named in #6997's original priority set, is sourced by **no
  workflow at all** and is documented in-repo as test-only. The "lower-priority readability
  tier" label understated the first and overstated the second.

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
   is the release-checklist item titled *"Produce `GIT_DATA_SSH_HOST`"* above. It was absent
   from the checklist entirely, so #6982 could have satisfied every listed item and still
   shipped this.

   The DC-3 disposition was **upheld by the operator on 2026-07-27**, with its scope corrected
   to the pre-birth window only — see the DC-3 RESOLVED block in
   `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`.
   The acceptance recorded there does not extend to the post-birth state this residual describes.

   **#6982 disposition: DISCHARGED, and the feasibility trap dissolved.** DC-3 read the
   `depends_on` mechanism as killing the proposal outright. It does not — it bites only
   under the remedy *"give the new secret a per-PR `-target` line"*, which is not what any
   of its five sibling secrets do; they sit in `OPERATOR_APPLIED_EXCLUSIONS` with no per-PR
   target at all. Sourcing the value from a **static local** (`local.git_data_private_ip`)
   rather than the computed `hcloud_server_network.git_data.ip` removes the last edge that
   could reach the server. That is a divergence from DC-3's mandated mechanism, and it is
   recorded — with the reason the mandate is not satisfiable in the pre-birth window it
   applies to — under *Item 5's mandated mechanism is not satisfiable pre-birth* above.

   The secret ships with **NO `depends_on`**, and that is the direct application of this
   residual's own correction: `depends_on` guarantees co-landing, co-landing is the harmful
   state for the ARMING SWITCH (the remove key), and this secret is the **antidote**. Having
   no dependencies at all also puts it in Terraform's first wave while the remove key waits
   on the server — so the antidote is ordered BEFORE the arming switch by construction,
   which is a stronger guarantee than the `depends_on` it replaces.
3. **Empty-store Art. 17 silent success.** Post-birth and pre-cutover the store is empty and
   `git-data-remove.sh` is idempotent, so an erasure request exits 0 and records **success**
   for a repo the store never held. Closing this needs a birth-completion marker the app can
   read — #6982/#5274 scope.

   **#6982 disposition: PARTIALLY DISCHARGED.** The birth-completion marker this residual
   needs now exists — `stage:boot_complete`, emitted host-side with its four assertions. So
   the remaining work is a design against a signal that exists rather than an open question,
   and it is bound to the `GIT_DATA_STORE_ENABLED` cutover (not to a date and not to the
   birth): per the CLO panel the "success" record is substantively accurate while the store
   genuinely holds nothing.
4. **The interlock does not bind the break-glass path.** By construction.

## Alternatives considered

<!-- lint-infra-ignore start -->
| Alternative | Verdict |
|---|---|
| Widen `git-data-host-replace` | **Rejected.** Its safety argument is "preserved by omission", which inverts on a birth. ADR-145 records the same rejection for web. |
| Keep the untargeted laptop apply | **Rejected** — the violation this closes; a plan of that shape carried nine destroys. |
| Inline the gate in the workflow YAML | **Rejected on evidence.** Untestable, and it fails the parity job⇄gate pairing. An earlier draft then shipped the *interlock* inline, contradicting itself; corrected. |
| Ship the route with no interlock, hold by convention | **Rejected.** A capability held only by prose is held until the first person who reads the runbook and not the plan — and #6982 contains items ADR-115 makes unfixable after birth. |
| Target the heartbeat too | **Rejected — verdict STANDS, on stronger and partly different evidence (#6982, D-HB).** The recorded reason (*the feeder already shipped and is web-host-resident; creating a monitor this route cannot arm is the #6537 fed-but-paused shape*) is now *partly stale on the feeding half*: the feeder shipped, `web-git-data-probe.service` runs `doppler run` per tick and resolves its URL by indirection through `GIT_DATA_HEARTBEAT_URL_KEY`, so the URL would propagate within one 60 s tick with no `ci-deploy` redeploy, and `heartbeat-manifest.ts` carries the row with no `arming_pending`. Three findings replace it, any one disqualifying. **(a) It would wedge every merge to `main`:** the `arm_one` call for `git_data_prd` lives in the PER-MERGE `apply` job, not a birth-only step, and no-ops today only because the address is absent from tfstate — the moment the heartbeat exists, every merge unpauses it, polls 230 s, and on no-beat rolls back and returns non-zero. That converts the health of an unborn, flag-off host into a merge-blocking dependency for the whole repository. **(b) It would prove the wrong thing:** `web-git-data-probe.sh` names its own limit — a TCP connect-and-close to :22 proves the port is OPEN, not that git transport SERVES — and sshd is up before `runcmd` runs, so a host whose Doppler download 404'd, whose LUKS never mounted and whose bootstrap died ANSWERS ON :22 AND BEATS GREEN. **(c) Object cap:** live Better Stack holds 7 heartbeats + 3 monitors against a vendor-page reading of a single shared pool of ten. Item 4 is satisfied HOST-SIDE instead, by the `stage:boot_complete` emit plus a poll that reads it. #6548 keeps ownership and receives these three findings. |
| Include `doppler_secret.git_data_ssh_host` | **Cut from #6977; SHIPPED in #6982, and the feasibility regression was not structural.** The wedge is real only under the remedy *"give the new secret a per-PR `-target` line"* — which is not what any of its five sibling secrets do; they sit in `OPERATOR_APPLIED_EXCLUSIONS` with no per-PR target. Sourcing the value from a STATIC local rather than the computed NIC attribute leaves no edge that can reach the server, so the address is plannable and appliable with the host absent. **The operator upheld the cut on 2026-07-27 (DC-3)** and attached two mechanical constraints, recorded in release-checklist item 5: single-source from `hcloud_server_network.git_data.ip`, and land the `OPERATOR_APPLIED_EXCLUSIONS` entry in the same change. Both are now met: **DC-5 was REVERSED during #6982's review** (see the reversal note above) and the value reads `hcloud_server_network.git_data.ip` as mandated. The divergence argument — that the computed attribute is unappliable pre-birth — did not survive contact with the actual `-target` lines, which already include the NIC. The #6977 dissent is in `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md` (PR #6989); the operator's decision upholding it was added to that same file by #7003. |
| Ship gate + suite now, enum + job in #6982 | **Considered and declined by the operator.** It would delete the interlock entirely by removing the capability, but #6977 would no longer deliver an executable route and would close on a partial. Recorded as DC-1. |
<!-- lint-infra-ignore end -->
