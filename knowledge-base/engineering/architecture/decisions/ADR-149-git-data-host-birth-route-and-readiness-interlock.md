# ADR-149 — The git-data host birth route and its readiness interlock

- **Status:** Accepted
- **Date:** 2026-07-27
- **Issue:** #6977
- **Amended by:** #7003 (operator decisions DC-2, DC-3 — 2026-07-27); #7025 (DC-6 — the
  rung-2 rehearsal route, shipped unfired, 2026-07-29); #8128 (item 8 discharged — 2026-09-13);
  #7884 (ADR-222 — reason (c)'s object cap superseded by a measured count — 2026-09-15)
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
   instructs that it be cleared only when every OTHER item in this checklist is done. Read as
   "above", this would exclude items 9 and 10, which sit below it and are both preconditions —
   the disposition tables are authoritative on which are discharged.)*
9. **Confirm the SIZING before the first birth** (added by #6982). The checklist had no
   sizing item and neither does the runbook's pre-dispatch table — step 7's stock preflight
   checks **orderability**, never **adequacy**. `user_data` is ForceNew and a `server_type`
   change routes through the DESTRUCTIVE `git-data-host-replace`, so the shape has to be
   right at birth. ADR-068's D-SIZE addendum records the decision (`cpx22`, unmeasured,
   sized for the burst with the burst now bounded by W4's git config + the gc timer).
10. **Assert the SSH authorization map is three distinct keys held by the three matching
    authorities** (added by #8009, CPO condition C1). `cloud-init-git-data.yml` pins three
    DIFFERENT forced commands — the transport wrapper, the provisioner, and
    `git-data-remove.sh`, which is the Article 17 erasure path — to three DIFFERENT pubkey
    variables. (Citation precision: ADR-068 designs the TRANSPORT and PROVISION authorities;
    the ERASE authority is designed in `apps/web-platform/server/git-data-replication.ts`,
    whose `removeGitDataRepo` calls it "a THIRD authority distinct from provision/transport",
    and it appears as a payload in ADR-152. ADR-068 names `GIT_REMOVE_SSH_PRIVATE_KEY` exactly
    once, inside a blast-radius argument, and `git-data-remove.sh` not at all — a false
    citation propagates further than a missing one.) The three pubkey
    variables. `rung2-rehearsal/rehearsal.tf` sets all three to one `tls_private_key`.
    **That is not merely uncovered; it makes the defect invisible.** Because the three were
    ALREADY identical in the rehearsal, a production edit collapsing them is a **no-op**
    there: `stage:boot_complete` still emits, no `level:fatal` appears, the evidence still
    records PASS, and `RUNG2_TEMPLATE_SHA256` moves, so the file even looks freshly
    re-rehearsed. In production the same edit gives the **transport** key — held by the web
    app for ordinary push and fetch — the `git-data-remove.sh` forced command; sshd matches
    by key and takes the first match, so it never surfaces as a failure, only as the
    transport identity being able to erase a user's repositories.
    `git_data_authorization_map_gate` closes it **statically**, over the production
    Terraform root, so it needs no live host and no paid rehearsal — which matters because
    the evidence hash binds 13 files and any drift buys another Hetzner rehearsal.
    **What it does not buy, recorded here so it is not mistaken for coverage:** it proves
    what the root RENDERS, never what a live host HONOURS. Runtime routes to the erase
    capability — an `authorized_keys2` fall-through, `core.hooksPath` ownership, an unpinned
    `AcceptEnv` — are properties of a running host and of files that host owns; a static
    walk structurally cannot see them, and they are tracked separately rather than closed
    here. The gate also runs on `git-data-host-replace`, which is the only route a collapse
    can travel once the host exists — but that job has no `environment:` and therefore no
    `deployment_branch_policy`, so `workflow_dispatch` runs the selected ref and the gate is
    supplied by the branch it polices. It holds against an accidental collapse merged and
    dispatched from `main`; it does **not** hold against a deliberate actor with repository
    write. **The compensating control, which makes that narrower than it sounds:** the gate also
    runs against the LIVE production root on every pull request, as arm B23 of
    `tests/scripts/test-git-data-birth-readiness-gate.sh`, which `scripts/test-all.sh` registers —
    so a collapse or permutation cannot reach `main` without first reddening the required `test`
    context. The branch-supplied gate on the replace path is the second line of defence, not the
    only one.
    **One accepted deviation, recorded rather than left to be rediscovered:** principle AP-026
    holds that a CI path whose job is to RECORD supplementary evidence must never gate on that
    evidence. The `needs: [git_data_birth_disclosure]` edge is that shape. It is accepted because
    AP-026 scopes to pull requests and merge authority, while this is an operator dispatch where
    the veto costs one re-dispatch and produces a red run with no Approve button — a legible
    refusal, not a silent one — and because the same disclosure also reaches the operator through
    the `apply_target` input description, which GitHub renders before any job exists.

### Disposition — #8010 (2026-09-19): the rung-2 gate resolves the run it names

The #8043 disposition below records this as open, in the row headed *"A voided attestation is
DELETED, never rewritten"*: `git_data_rung2_rehearsal_gate`'s only provenance check was a regex
that `RUNG2_EVIDENCE_URL` **looks like** an Actions run URL — it never fetched the run. A hand-typed
URL, a URL naming somebody's unrelated run, and a URL naming a `dry_run=true` dispatch that
uploaded nothing all passed identically. This closes that finding. It extends the interlock
decision rather than reversing it, so there is **no new ADR**.

**The five new steps, in the pinned order** — local before network, and the cheap network call
before the expensive-to-be-wrong one, so an offline operator sees file defects first and the
common refusal costs one request:

| # | Step | Reach |
|---|---|---|
| A | `jq` / `curl` / `tar` present | local |
| B | Sentry verdict is `CLEAN`, or `UNAVAILABLE` plus a run-bound ack | local |
| C | `GET /actions/runs/<id>`: `path`, `event`, `head_branch`, `status`, `conclusion`, `head_sha` | network |
| D | `head_sha` reachable in this checkout, and the archived tree at it re-hashes to the claim | local git |
| E | `GET /actions/runs/<id>/artifacts`: a `git-data-rung2-boot-evidence` entry | network |

**Identity is asserted by four facts together, and the fourth is the one that matters.** The
workflow `path`, the `workflow_dispatch` `event` and the `head_branch` of `main` say the run was
*this* route; the **capture artifact** (step E) is what says the run actually spent a host,
because a `dry_run=true` dispatch also concludes `success` and satisfies the other three. Without
step E the gate would release on a plan-only rehearsal.

**`conclusion == success` is required**, and the earlier caveat that a conclusion says nothing
about the capture no longer applies: with step E present, a `success` conclusion plus an evidence
artifact is a statement about a run that captured. **Accepted consequence, recorded rather than
mitigated:** the artifact uploads before teardown, so a *failed teardown after a good capture*
yields a red run and therefore no usable evidence. The operator pays a second host. That is the
correct direction for this gate — the alternative is releasing a production birth on a run whose
own conclusion is `failure` — and the rehearsal runbook's *After a PASS* now leads with
`gh run watch` so the operator learns it before downloading rather than after committing.

**The run-bound acknowledgement is the only way `UNAVAILABLE` releases.** Grammar:
`RUNG2_SENTRY_CROSSCHECK_ACK=<run-id>:<reason>`, where the run-id must equal the one parsed from
`RUNG2_EVIDENCE_URL`, the reason must be non-empty after trimming, and the reason may not contain
`#` (the gate's trailing-comment strip would truncate it). Binding the ack to the run is what stops
it from becoming a permanent blanket waiver copied forward into the next evidence file. A `FATAL`
verdict has no acknowledgement path at all, and the capture's never-consulted branches now write
`NOT_RUN`, which nothing rescues — a cross-check that never ran must not commit bytes identical to
one that ran and degraded. **Tripwire, recorded here because nothing enforces it:** the ack is
meant to be rare. Two consecutive evidence files carrying one means the second channel is
structurally broken rather than momentarily quiet, and the remedy is `SENTRY_ISSUE_RO_TOKEN`'s
scope, not a third ack. If that pattern appears, the ack path is doing the opposite of its job.

**Every CI call site resolves the run ANONYMOUSLY.** No workflow in this repository grants
`actions: read` today, so an authenticated attempt would 403 and the anonymous path is the
operative one everywhere — at 60 requests/hour per IP, shared behind NAT on hosted runners. The
gate is fail-closed on that, which is the correct direction, and every could-not-measure token
names its own remedy rather than a generic one. Two of the gate's three CI callers cannot be
edited this cycle (`apply-web-platform-infra.yml` is over GitHub's 500 KB workflow-file limit,
#8361), which is **why the gate emits its own `::error::` annotation**: the callers' fixed text is
otherwise the only signal an operator would see. Granting `actions: read`, threading `GH_TOKEN`,
and converting the three call sites' binary `if !` into a tri-state that separates an instrument
failure from a HOLD is filed as this cycle's blocker issue, milestone `Phase 4: Validate + Scale`,
and is cited from the `RUN_RATE_LIMITED` message itself.

**Residuals, accepted and recorded.**

1. **The Sentry verdict is still a human-committed string.** Steps C–E bind the *run*; nothing
   binds `RUNG2_SENTRY_CROSSCHECK` to anything outside the file. The capture writes it, an
   operator commits it, and the gate reads what was committed.
2. **Artifact-record retention past ~110 days was measured once and is undocumented by the
   vendor.** That is why the *absence* of an artifact record on an old run is a could-not-measure
   token (`RUN_ARTIFACT_RECORD_UNREADABLE`) rather than a refusal: the gate cannot tell "this run
   uploaded nothing" from "GitHub no longer keeps the answer".
3. **The producer is unbound.** The hash roster binds neither the rehearsal workflow nor the
   capture script, so what the gate proves is *"a workflow at that path ran on `main` and produced
   a boot-evidence artifact"* — not that the producer itself was unmodified. A
   `RUNG2_PRODUCER_SHA256` recomputed at the run's `head_sha` is the recorded next step.
4. **The downgrade shape passes every check honestly.** Revert the infra tree to an older state
   and cite the older genuine run that matches it: steps A–E all pass, because every fact asserted
   is true. Only Guard 4 ARM 2 sees it, and that arm is advisory until `deploy-script-tests`
   becomes a required check.

**Future considerations** — recorded here beside the deferred check-run idea (binding the Sentry
verdict to something outside the file, i.e. a check-run output written by the rehearsal workflow):
an **attestation-based** alternative, `actions/attest-build-provenance` in the rehearsal workflow
plus a committed Sigstore bundle verified by the gate. It would replace steps C–E's live API reads
with an offline cryptographic verification, which removes the anonymous-rate-limit failure mode
and the retention residual at once, and would bind the producer (residual 3) as a side effect. Not
taken now: it adds a signing dependency and a bundle format to a gate whose present job is to stop
being fooled by a regex, and the live read is the smaller change that closes the finding.

**Operator-facing effect.** `git-data-rung2-rehearsal.md` gains the token-to-remedy table, the
`--ref main` dispatch and the two-PR payload-change sequence; `git-data-birth.md` gains the
fallback order for a `RUN_*` HOLD on the birth and replace routes and retires its claim that the
gate ignores `RUNG2_SENTRY_CROSSCHECK`.

### Addendum — #8189 (2026-09-15): a root authority beside item 10's three keys

Item 10 and the #8009 disposition account for **three** SSH authorities on git-data, each a distinct
key with a fixed forced command. #8189 adds a **distinct root** authority, and this record carries it
so the accounting stays complete. It is not the only root authority: `hcloud_ssh_key.default` (the
operator's public key) has been delivered as a root login key, with no forced command, by every create
of `hcloud_server.git_data`, including the host born 2026-09-14, and the create gate requires exactly
that key and the root key. Item 10's three-key count never covered it; a count of "four" would read
as complete, so none is given. As of this addendum the authority is declared, not delivered: the
root-key apply, the fingerprint PR and the replace all run after #8189 merges, each with its own
authorization, so the entries below are written in the future tense.

- **What it is.** `tls_private_key.git_data_root` (ED25519) in the separate root
  `apps/web-platform/infra/git-data-root-key/`. Once delivered, it **will authenticate as root**, with
  **no forced command**, so it will be able to bypass every git-principal measure item 10's map
  protects.
- **Where it will be held.** Once the root-key apply runs: the Doppler project `soleur-git-data-root`
  (not `prd`), and that root's R2 state object.
- **How it will reach the host.** Only through `hcloud_server.git_data`'s create-time `ssh_keys`, as a
  Hetzner key object labelled `soleur-role=git-data-root`, at the next replace. Both the birth and the
  replace gate call `git_data_root_key_arm`, which refuses a create unless a committed fingerprint file
  matches the one resolved key. Until that file is committed, every birth and replace refuses.
- **What it does not change.** `git_data_authorization_map_gate` still asserts exactly three distinct
  forced-command keys, correctly assigned. The root key is not a fourth `git` slot and is not in
  `cloud-init-git-data.yml`, so the rung-2 hash does not move.
- **Approval.** #8009 C1 was re-approved for this addition by CPO and CTO. Custody limits and residuals
  are in ADR-220, "Amendment log".

### Addendum — #6680 (2026-09-15): F9's "operator root key" does not exist

The #8043 disposition's F9 row says the root paths for the real fence hook are "a host replace
(cloud-init) or the operator root key the cutover already uses". The second half is false: the
cutover never held a root key on git-data (ADR-220, Context). A host replace is the only root
delivery path for the real fence hook. The same stale claim ("the operator root path the cutover
uses") sits in the comments of the hash-bound `git-data-pre-receive.sh` and
`git-data-pre-receive-placeholder.sh`. They are left untouched here,
because editing them moves the rung-2 hash, and the fix is tracked in #8189.

> **Superseded 2026-09-15 (#8189), as to where the fix is tracked:** #8189 left both hash-bound files
> untouched, and the stale comment is carried by a comment on #8093 for its next batch.

### Disposition — #8128 (2026-09-13): item 8 discharged — the banner is cleared

| Item | Status |
|---|---|
| 8 — clear the banner | **DONE** by PR #8128, on the sequence #8043 prescribed and nothing shorter: a fresh rehearsal dispatched from `main` `15fd63aff` (run [34768256297](https://github.com/jikig-ai/soleur/actions/runs/34768256297), `dry_run=false`, environment-approved, verdict PASS — `stage:boot_complete` with `luks_mounted=yes repo_root=yes hooks_path=yes provision=yes nft_metadata_drop=yes`, no `level:fatal`, teardown verified against the Hetzner API); its evidence committed ALONE in PR #8126 (Guard 4 provenance PASS, template sha256 `5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1`, equal to `main`); then this banner PR. `RUNG2_SENTRY_CROSSCHECK=UNAVAILABLE` (run-pinned liveness window on a quiet project; the gate ignores that key — #8010). The runbook now opens with a release record in the banner's place. |

**Checklist effect.** Every item is now DONE, DISCHARGED, or recorded NOT SATISFIABLE AS
WRITTEN (item 7). #7025's second checkbox reads "tick ADR-149 checklist item 7" — written
before the #6982 disposition recorded item 7 as not satisfiable; the item that checkbox
describes (the banner clear) is item 8, and this row is its tick. Nothing in this change
dispatches a birth: the only control left on
`apply_target=git-data-host-create` is the `web-platform-infra-apply` environment approval,
measured `prevent_self_review: false`, one reviewer, `can_admins_bypass: true` — one human, not
two parties — plus the three static interlocks, which self-invalidate the moment a bound input
moves.

### Disposition — #8043 (2026-09-11): six hash-bound hardening items, and what they cost the evidence

Six defects on the git-data host were fixed as ONE change because each edits a file inside the
13-file `RUNG2_TEMPLATE_SHA256` binding: F6 (a comment framing the three SSH pubkeys as
identity-shaped), F7 (the `git` account owned its own authorization map), F8 (an Art. 17 erasure
could report success over an unmounted store), F9 (`core.hooksPath` pointed at a git-writable
directory), F10 (five wrapper comments claiming `AcceptEnv` is empty), F11 (the stage's only ssh
unit action named `sshd`, which ubuntu-24.04 does not have). Moving them together costs one
fresh rehearsal instead of six. Four decisions belong here rather than in the plan:

| Decision | Record |
|---|---|
| **The ssh unit is `ssh`, and only git-data is edited** | ubuntu-24.04 ships ssh socket-activated: `ssh.socket` is `Accept=no` (one long-lived `sshd -D`, so no per-connection re-read makes a drop-in effective), and `Alias=sshd.service` is instantiated only when `ssh.service` is enabled — under socket activation, never. `systemctl restart sshd` therefore failed rc=5 on every boot, fail-open. The rename is safe on a console-less host because `ssh.socket` carries no `Conflicts=ssh.service` (the listener stays bound; a failed start does not close port 22); it adds a bounded wait (`Type=notify` + `ExecStartPre`, ≤ `DefaultTimeoutStartSec` 90 s) above the LUKS stage, to be read from the fresh rehearsal's boot wall-clock delta. **Fleet decision — git-data only:** `hcloud_server.web` has `ignore_changes = [user_data]` (an edit is inert); `inngest` and `registry` are ForceNew on LIVE hosts (a destructive replace); `grok_dogfood` renders no ssh action. The siblings load the drop-in at the daemon's first start regardless, so they are *noisy, not unhardened* — except inngest's next `runcmd` item, `inngest-boot-phone-home.sh sshd-restarted`, a positive attestation for an action that fails every boot. Filed at load-bearing severities (#8043 FR17). |
| **A voided attestation is DELETED, never rewritten** | `git-data-rung2-boot-evidence.env` was deleted by this change rather than edited to the moved digest. Editing would make a void attestation look freshly re-rehearsed — the exact failure the gate exists to prevent and one it structurally cannot catch: `git_data_rung2_rehearsal_gate`'s only provenance check is a regex that `RUNG2_EVIDENCE_URL` *looks like* an Actions run URL; it never fetches the run (#8010). Deletion is fail-closed in both directions: the gate HOLDs on an absent file, and the CI freshness step (advisory — `deploy-script-tests` is not a required check) returns to its dormant-by-design arm instead of reddening on the moved hash. "Rehearse first" was not available either: the rehearsal environment deploys from `main` only, so the evidence could not be refreshed before the change landed. A provenance gate now enforces the shape (birth-time arm inside the rehearsal gate; advisory PR-range arm in CI); the multi-commit residual — a bound-file edit in one commit and the hash in another, landed by any non-squash method — is #8010's. |
| **The hash binds SOURCE, not the render** | `git_data_rung2_user_data_sha256()` hashes the template and the nine payloads as committed, while `local.git_data_rationale_strip` (ADR-152) strips comment lines at render time. So a comment-only edit (F6, F10) that never reaches the host voids a paid attestation exactly as a code edit does — which is why this batch had to be six items wide, and why a future rung-2 evidence design should consider binding the RENDER. Recorded as a finding, not changed here. |
| **The `git` login shell is a real shell, not git-shell** | Found at review (measured in the pinned image): sshd runs a `command=` as `<login shell> -c "<command>"`, and git-shell accepts only its four built-ins, so with `shell: /usr/bin/git-shell` every forced command — transport, provision, and the Art. 17 erasure — exited 128 `fatal: unrecognized command`. Nobody had ever connected to the host, so nothing had measured it; the ownership suite's runtime arm created its user with `/bin/sh` and could not see it either. Now `shell: /bin/sh`, the bootstrap reads the shell back and refuses a restricted one, the suite creates its user with the template's shell and runs a REAL forced command through sshd (R9), and ADR-068's "per-key `command=` overrides the login shell" is corrected. The confinement is the three-line forced-command map the authorization gate pins; a restricted shell only decided whether the forced command could run at all. Pre-existing, hash-bound, folded into this batch for the same reason the batch exists. |
| **F9 retires the pipeline-iterable hook delivery** | With `$HOOKS_DIR` at `root:git 0750` and `pre-receive` installed `root:root`, no git-uid channel can deliver the real CAS fence that `git-data-pre-receive-placeholder.sh` says "ships via the web-platform deploy pipeline" (no workflow references it; it was never built). The only root paths are a host replace (cloud-init) or the operator root key the cutover already uses. Recorded so a future author does not loosen F9 to make a git-uid delivery work. |
| **The authorization-map gate's ownership arm was measured wrong and flipped** | The arm required `owner: git:git` on the rationale that any other owner is "unreadable by sshd or writable by a second principal". Measured in the pinned image: a `root:root 0644` map in a `root:git 0750` `.ssh` authenticates; `root:root 0600` does NOT (sshd opens the file under the target user's uid — "Permission denied", every push refused). The arm now requires `root:root` / `'0644'` (checklist item 10's control, tightened; the three-distinct-keys assertion is unchanged). |

| **Review pass (#8052): four host-trust seams closed while the hash was already moving** | The ten-seat review measured, in the pinned image: (1) root's weekly gc set `safe.directory=$REPO_ROOT/*` system-wide, and the trailing-`/*` form needs git ≥ 2.46 — 24.04 ships 2.43.0, where it matches nothing, so every run failed every repo (rc 128 "dubious ownership") and reported success; `git-data-gc.sh` now passes `-c safe.directory="$repo"` per command and `gc_report` is on the warning rule. (2) The gc lock sat in `/var/lock` (`/run/lock`, 1777): a git-uid pre-created file makes root's open fail under `fs.protected_regular`; moved to `RuntimeDirectory=git-data-gc`. (3) A repo-local `core.hooksPath` (git-writable) outranks the system value the bootstrap sets, so code-exec-as-`git` could unfence one workspace without touching the root-owned hook; the transport wrapper now execs `git -c core.hooksPath=$HOOKS_DIR <verb>`, the one scope repo config cannot override. (4) The transport wrapper — the forced command that WRITES user source — had none of the store-mounted/root-on-store guard provision and remove carry; it does now, with `.cutover-freeze` honoured by all three, `rm -rf --one-file-system` on the erasure, and the per-workspace lock never unlinked (unlink-while-held let a sibling hold a fresh inode). Each is hash-bound; landing them here costs nothing the batch was not already paying. |

**Checklist effect.** Items 1–7, 9 and 10 are unchanged in status. The rung-2 evidence that
satisfied item 8's precondition (landed by #8002 from run 33888071954, dated 2026-09-04 —
the ADR's last word on item 8 before this disposition was #7025's "unproducible") is void by
construction (the template moved) and has been deleted; item 8 (#7025) is therefore
**re-armed**, and since this change its precondition also carries the evidence's commit
PROVENANCE (Guard 4: the evidence's last commit must touch no bound file, read from a
non-shallow checkout) — the sequel is a fresh rehearsal dispatched
from `main`, its evidence PR, then the banner PR, then the birth. Nothing in this change
dispatches a rehearsal or a birth.

### Disposition — #8009 (2026-09-10)

| Item | Status |
|---|---|
| 10 — the authorization map is three distinct keys, correctly assigned | **DONE.** `git_data_authorization_map_gate`, wired as a third interlock on BOTH `git_data_host_create` and `git_data_host_replace`, and asserted on every pull request by a live-tree arm in `tests/scripts/test-git-data-birth-readiness-gate.sh`. Measured non-vacuous rather than read: 26 of 26 mutation rows driven non-zero against a copy of the live root, 0 survivors — including both 2-swaps and the 3-cycle, which are perfectly bijective and pass every cardinality predicate. Item 8 (clearing the banner) now depends on this item too. |

### Disposition — #6982 (2026-07-27)

| Item | Status |
|---|---|
| 1 — emitter + `sentry_dsn` threaded | **DONE.** One `/usr/local/bin/git-data-emit` (ADR-147's #6982 addendum records why it is a file and not an inline function). |
| 2 — credential reachable in the token's single-config scope | **DONE, and it found a live boot-breaker.** The probe measured that `doppler run --config prd` under a `prd_git_data`-scoped token **exits 1** with `GIT_DATA_LUKS_KEY` absent — so `doppler run` was exiting BEFORE exec'ing the LUKS heredoc, its `set -euo pipefail` ran zero times, and the host would have booted dark with sshd up. Both invocations corrected to `--config prd_git_data`. This is exactly the "dark by construction" trap this item exists to catch, and it was sitting inside the file the interlock inspects. |
| 3 — new addresses registered | **DONE, and the item understated the work: there are SIX sites, not three.** The gate carries `def allow:` (a PERMISSION set) *and* a separate hardcoded PRESENCE loop (a COMPLETENESS set) that nothing extracted, so a three-of-four edit was fully green — an address PERMITTED to change but not REQUIRED to appear, which is Residual 2's harm hiding behind a PASS. Set is 18 → 20. |
| 4 — post-apply signal | **DONE, host-side.** `stage:boot_complete` from `git-data-bootstrap.sh` **plus a poll that reads it** inside the birth job (`if: always()` at the time; since PR #8171 gated on the apply step's outcome — it runs after a green or failed apply, never after a skipped one). A producer with no reader is not a signal. |
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
| Target the heartbeat too | **Rejected — verdict STANDS, on stronger and partly different evidence (#6982, D-HB).** The recorded reason (*the feeder already shipped and is web-host-resident; creating a monitor this route cannot arm is the #6537 fed-but-paused shape*) is now *partly stale on the feeding half*: the feeder shipped, `web-git-data-probe.service` runs `doppler run` per tick and resolves its URL by indirection through `GIT_DATA_HEARTBEAT_URL_KEY`, so the URL would propagate within one 60 s tick with no `ci-deploy` redeploy, and `heartbeat-manifest.ts` carries the row with no `arming_pending`. Three findings replace it, any one disqualifying. **(a) It would wedge every merge to `main`:** the `arm_one` call for `git_data_prd` lives in the PER-MERGE `apply` job, not a birth-only step, and no-ops today only because the address is absent from tfstate — the moment the heartbeat exists, every merge unpauses it, polls 230 s, and on no-beat rolls back and returns non-zero. That converts the health of an unborn, flag-off host into a merge-blocking dependency for the whole repository. **(b) It would prove the wrong thing:** `web-git-data-probe.sh` names its own limit — a TCP connect-and-close to :22 proves the port is OPEN, not that git transport SERVES — and sshd is up before `runcmd` runs, so a host whose Doppler download 404'd, whose LUKS never mounted and whose bootstrap died ANSWERS ON :22 AND BEATS GREEN. **(c) Object cap:** live Better Stack holds 7 heartbeats + 3 monitors against a vendor-page reading of a single shared pool of ten. Item 4 is satisfied HOST-SIDE instead, by the `stage:boot_complete` emit plus a poll that reads it. #6548 keeps ownership and receives these three findings. **Amended 2026-09-15 (#7884):** the (c) reading is superseded by measurement. The twice-daily reconcile prints `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=<n> heartbeats=<n> total=<n>`, and live held 4 monitors + 9 heartbeats = 13 objects that day, which contradicts a single shared pool of ten. See [ADR-222](./ADR-222-better-stack-database-readiness-pager-and-live-inventory.md). |
| Include `doppler_secret.git_data_ssh_host` | **Cut from #6977; SHIPPED in #6982, and the feasibility regression was not structural.** The wedge is real only under the remedy *"give the new secret a per-PR `-target` line"* — which is not what any of its five sibling secrets do; they sit in `OPERATOR_APPLIED_EXCLUSIONS` with no per-PR target. Sourcing the value from a STATIC local rather than the computed NIC attribute leaves no edge that can reach the server, so the address is plannable and appliable with the host absent. **The operator upheld the cut on 2026-07-27 (DC-3)** and attached two mechanical constraints, recorded in release-checklist item 5: single-source from `hcloud_server_network.git_data.ip`, and land the `OPERATOR_APPLIED_EXCLUSIONS` entry in the same change. Both are now met: **DC-5 was REVERSED during #6982's review** (see the reversal note above) and the value reads `hcloud_server_network.git_data.ip` as mandated. The divergence argument — that the computed attribute is unappliable pre-birth — did not survive contact with the actual `-target` lines, which already include the NIC. The #6977 dissent is in `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md` (PR #6989); the operator's decision upholding it was added to that same file by #7003. |
| Ship gate + suite now, enum + job in #6982 | **Considered and declined by the operator.** It would delete the interlock entirely by removing the capability, but #6977 would no longer deliver an executable route and would close on a partial. Recorded as DC-1. |
<!-- lint-infra-ignore end -->

## Amendment — 2026-09-17 (#8178): item 4's reader had never read

Item 4 is satisfied host-side by *"the `stage:boot_complete` emit plus a poll that reads
it"*, and the disposition row above records it **DONE**. The producer half held. The
reader half had never once succeeded.

**Measured.** On both real birth dispatches every one of the 20 polls returned `rc=22`
(`curl --fail-with-body` on an HTTP >= 400): run
[34822248580](https://github.com/jikig-ai/soleur/actions/runs/34822248580) (apply skipped
by the birth gate) and run
[34836141887](https://github.com/jikig-ai/soleur/actions/runs/34836141887) (apply SUCCESS,
host born). In the second, the host was genuinely dark: it died at `gitdata_doppler_dl`
about 20 s into runcmd and never emitted `boot_complete`. The job went RED saying *"the
birth is UNVERIFIED"*, and the poll could not have told a dark host from a healthy one.
The step ran `betterstack-query.sh … 2>/dev/null`, so the response body never reached the
log and the cause was unrecoverable from `gh run view`.

**Cause: a stale SQL API connection.** The step bound the three repository secrets
`secrets.BETTERSTACK_QUERY_*`, last written 2026-07-03. They hold the SQL API connection
created 2026-06-01, and git-data's Logs source (2734275) was created 2026-09-03. A Better
Stack connection does not cover sources created after it (#7867, resolved 2026-09-09), so
every read against the git-data table answered HTTP 500 `CLUSTER_DOESNT_EXIST`, which
`--fail-with-body` reports as the same `rc=22` as a 401. The fix for #7867 created a new
connection and wrote it only to Doppler `prd_terraform`, which the step's own error text
had always named. The identical query succeeds under `doppler run -p soleur -c
prd_terraform` (measured 2026-09-17 and 2026-09-18, `rc=0` on the UNION and on each arm).
ADR-192's `## Addendum — 2026-09-18 (#8178)` retires its "never stored a row" reading of
that error.

**A correction to this PR's own first draft.** An earlier revision of this amendment said
the 20 x 30 s budget was too short because run 34836141887's `boot_complete` landed
`15:27:24`, 2 m 37 s after the poll gave up. That row came from the NEXT host: replace run
[34861860722](https://github.com/jikig-ai/soleur/actions/runs/34861860722) finished its
apply at `15:27:06`, 18 s before the row. With working credentials the birth would have read
`silent`, which was correct. Measured healthy boots report `boot_complete` 8-13 s after runcmd
starts, and runcmd starts 3-10 s after apply ends. So the budget stays at 20 x 30 s, about
30x the measured latency. The job `timeout-minutes` is raised instead, and each read is
capped at 45 s, so a slow read path ends in a verdict rather than a cancelled job with none.

**A premise nobody had asserted: `git_data_host_replace` had no poll at all**, and it is
the path that actually runs. Birth is once-ever, so with a live host present every later
boot comes through replace, and one completed green on 2026-09-16 having verified
nothing. Its apply step also carried no `id:`, so a copied poll's `steps.apply.outcome`
would have resolved to `''` and the poll would have been skipped. Both jobs are now wired,
and both `Dispatch summary` steps turn an apply/poll outcome pair that did not produce a
verdict (including an empty outcome) red.

**What item 4 now means.** The reader is
`scripts/lib/git-data-boot-signal-poll.sh`, driven hermetically by
`tests/scripts/test-git-data-boot-signal-poll.sh`. It reports three outcomes: `received`
/ `silent` / `unreadable`. The verdict rests on the FINAL read, and the summary line
`answered=N/M` says how many reads answered. `silent` is a statement about the host;
`unreadable` measures nothing about it. stdout and stderr go to separate files, so a
reader's error echo can never reach the match buffer. The failure log carries rc, a
classification, the body's byte LENGTH and a scrubbed stderr line, never the body, because
this repository is public and a ClickHouse auth body carries half a Basic-auth pair.

**The read is anchored to the run.** Both jobs stamp `BOOT_TRAIL_SINCE` immediately before
their apply, and the poll refuses to run without a well-formed anchor
(`VERDICT=refused-no-anchor`). The rule: *a readiness verdict filtered by `host_name` is
scoped to the host, not the host generation, so its read must be bounded by an anchor
stamped before the action that creates the generation.* No back-skew is subtracted. `dt` is
assigned by Better Stack at ingest (the emitter's POST body carries none), so the only clock
comparison is Better Stack's against the runner's, and both are NTP-synced. An earlier
revision subtracted 120 s, which let a replace queued behind another replace accept the
previous generation's row. The rule is recorded as principle **AP-027**.

**Accepted residual, stated rather than hidden.** Time is the only thing separating two host
generations: the `boot_complete` row carries no per-host identity. If a previous host is still
booting when the next replace starts (its own poll ended `silent`, and a replace was queued or
re-dispatched), its late `boot_complete` can be ingested after the new anchor and before the
destroy, and the new poll would then accept it. That needs a previous boot slower than the
10-minute budget plus a dispatch inside that window; measured healthy boots report in 8-13 s.
Closing it needs a generation id (the Hetzner server id) in the emit and in the `WHERE`
clause, which changes `user_data` (ForceNew) and so rides the next change to the emitter.

**Closure is event-gated.** No suite can show the read working from a real runner. #8178
closes on the first post-merge git-data dispatch whose poll answers, judged by
`scripts/followthroughs/git-data-boot-poll-8178.sh`, and not on a `boot_complete` row (one
already existed before the fix).

A producer with no reader is not a signal; a reader that has never read is not a reader.
