---
title: "Coherence has two invariants: build-integrity is statically checkable, cross-commit skew needs a digest-pinned birth path"
status: accepted
date: 2026-07-20
issue: 6575
supersedes: [ADR-082]
---

# ADR-128: coherence has two invariants — build-integrity is statically checkable; cross-commit skew needs a digest-pinned birth path

## Context

`local.host_scripts_content_hash` (`server.tf`) is a `filesha256` fold over
`local.host_script_files`. Terraform injects it into `user_data`; the boot path
recomputes it over the image's baked `/opt/soleur/host-scripts/` and compares:

```
[ "$GOT" = "$HOST_SCRIPTS_HASH" ] || exit 1
```

That line runs under the `set -e` armed earlier in `cloud-init.yml`, so a mismatch aborts
the **entire** `runcmd` at `stage=verify`. `runcmd` is once-per-instance, so no reboot
repairs it: no cloudflared connector, no deploy webhook, no monitors, no egress firewall.
On a single-origin fleet that is a total outage with no automated recovery.

Two issues contended over the one file that checked this. **#6575** listed
`web2-recreate-preflight.sh` for deletion as dead web-2 surface. **#6712** said the same
script was the only artifact standing between a fresh web-1 birth and a doomed `runcmd`.
Both readings were defensible because **the framing conflated two different invariants
under one word.** Separating them is what makes #6575 closable and #6712 not.

## Decision

### 1. Name the two invariants separately

| Invariant | What it catches | Where it is enforced |
|---|---|---|
| **Build-integrity** — the image's baked `/opt/soleur/host-scripts/` matches the repo tree it was built from | Dockerfile `COPY`-list drift; a post-`COPY` `RUN` mutating the baked directory; a duplicate `host_script_files` entry | **Statically**, in `plugins/soleur/test/cloud-init-user-data-size.test.ts` — the `Dockerfile <-> server.tf baked-set parity` describe, in the required bun shard. No image pull, no registry round-trip, no release-path coupling. |
| **Cross-commit skew** — the image Terraform computed `host_scripts_content_hash` against is the image the host actually pulls | An apply at commit `C_tf` while `:latest` points at `C_img` | **Nowhere, today.** Only closable by pinning `var.image_name` to a digest at create time. Owned by **#6730**. |

The distinction is not academic. Build-integrity is a property of **one commit** and is
therefore decidable by a test. Cross-commit skew is a property of the **relation between an
apply and a registry tag at apply time** — no build-time artifact can observe it.
`var.image_name` defaults to the mutable `ghcr.io/jikig-ai/soleur-web-platform:latest`
(`variables.tf`) while `host_scripts_content_hash` comes from the applying commit; nothing
in the repo forces those two to agree.

**#6712 therefore does not close with the web-2 sweep, and must not be marked closed.**
Its residual is live. Closing it needs a resolver plus a digest-pinned birth path — #6730's
scope, and the thing PR #6725's operator decision already deferred.

### 2. The verifier stays pure, and is retained host-agnostic

`host-image-coherence-preflight.sh` (renamed from `web2-recreate-preflight.sh`, comparison
and validation logic byte-unchanged) accepts **only** a pinned `repo@sha256` ref and `die`s
on anything else. Its digest-`die` branch must remain reachable — that is what its T3/T4
cases pin.

It is **not** generalized to accept a mutable tag. Doing so would move the TOCTOU closure
from *"structurally cannot re-resolve"* to *"the caller faithfully consumes the emitted
value"*, and would make the digest `die` branch dead code on the mutable arm — a weaker
guarantee sold as a generalization. Callers compose `resolve → verify → apply -var
image_name=<pinned>` instead. That composition is now written out as an executable command
chain in the `host_creates` HALT runbook, which is what keeps the verifier reachable.

### 3. The retention rule (uniform, replacing case-by-case judgement)

> **Retain a callerless verifier iff it is named as a step in a documented procedure an
> operator can execute today. Delete it otherwise — and preserve its design record in this
> ADR.**

The rule exists because "it might be useful later" retains everything and "it has no caller"
deletes load-bearing knowledge. Naming an *executable procedure* is the discriminator: a
script an operator can actually run today is live surface; one that only appears in prose is
a comment with a shebang.

A corollary that the sweep proved matters: **a runbook line reading "run the preflight" does
not satisfy the rule.** The preflight refuses the mutable `:latest` an operator holds, by
design, so that instruction is unactionable by construction. The procedure must carry the
full command chain.

Applied in this sweep:

| Artifact | Verdict | Why |
|---|---|---|
| `host-image-coherence-preflight.sh` + test | **Retained** | Named in the `host_creates` HALT chain, executable today. |
| `resolve-web1-known-good-tag.sh` + test | **Retained** | Both of its former runtime callers (`apply-web-platform-infra.yml`'s recreate job and `deploy-status-fanout-verify.sh`) were deleted here, so at review it was momentarily callerless — which would have FAILED the retention rule below. It is retained because it is now **named in an executable operator procedure**: `runbooks/web-host-birth.md` step 1 uses it to pin web-1's known-good running version instead of mutable `:latest`. Retention rule satisfied by wiring, not by exception. |
| `deploy-status-fanout-verify.{sh,test.sh}` | **Deleted** | No procedure names it; both callers gone; its `ROSTER_COUNT -ne 2` invariant is falsified by the retire independently. Design record below. |
| `lb-weight-gate.{sh,test.sh}` | **Deleted** | No procedure names it and its subject — a second origin to weight — no longer exists. Design record below. |

### 4. Build-integrity gets two cheap static assertions, not a bake-time gate

Added to the existing required-check parity test: **(A)** no `RUN` between the host-scripts
`COPY` and the end of the runner stage writes into `/opt/soleur/host-scripts/` (the
ownership-only `chown -R 1001:1001` form is allow-listed with its reason); **(B)**
`host_script_files` contains no duplicates — the Terraform side hashes an enumerated list
while the boot side hashes files found on disk, so a duplicate makes the two constructions
disagree permanently.

## Preserved design records of the deleted gates

Recorded here so #6730 does not have to rediscover them.

### `deploy-status-fanout-verify.sh` — the `.tag` last-write-wins trap

The trap is **not** about fan-out. It is about which field you read to learn what image a
host is running, and it will bite anything that reaches for the obvious one.

`https://deploy.<domain>/hooks/deploy-status` exposes a `.tag` slot. That slot is a **single
last-write-wins object** (`ci-deploy.sh`'s `write_state`) stamped by several *independent*
writers: a web-platform deploy, an inngest restart, a git-lock sweep. When a non-web writer
owned it — e.g. an inngest watchdog restart stamping
`{component:inngest, tag:latest, exit_code:0}` — a consumer reading `.tag` got the non-semver
string `latest` and hard-aborted (`got 'latest'`) while the host was perfectly healthy.
Compounding it: `.tag` is the state file's **last-attempt** tag, not the actually-running
image (ADR-079 amendment, #5955).

**The fix, and the pattern to reuse:** resolve a host's running tag from its public
`/health` `.version` — the baked `BUILD_VERSION` of the container actually running — which
never touches the shared slot and is therefore immune to writer contention.
`apply-deploy-pipeline-fix.yml` had already adopted exactly this for the identical
"`.tag`=latest wedge". `resolve-web1-known-good-tag.sh` is that resolver, and is retained.

Two further shape lessons from the same script, worth keeping:

- **Keep network I/O in the caller and decision logic in the script.** The bounded `curl`
  retry lived in the workflow; the semver guard lived in the script, which is what made it
  fixture-testable. That seam is the reason the resolver survives the sweep at all.
- **A staleness gate must never advance its own baseline on retry.** Only a completion whose
  `start_ts` advanced past the *original* pre-trigger baseline counted. Advancing the
  baseline on a re-trigger would have filtered a late-arriving success from an earlier
  in-flight cycle and added clock skew on top.

Its `ROSTER_COUNT == 2` single-peer guard is the honest part to note as *dead*, not
preserved: `reason == ok ⟹ the peer accepted` holds only with exactly one peer besides
web-1. On a single-host roster the premise is vacuous, which is precisely why the script goes
rather than getting a one-line patch.

### `lb-weight-gate.sh` — the ADR-068 §(c) shape-only gate

Recorded in the **ADR-068 §(c)** sense: it was the *programmatic, fail-closed, shape-only*
check for both §(c) weight-flip conditions, reading **only injected env** (no Doppler calls —
the Doppler-sourcing entry point was to ship with the deferred cutover orchestrator, its only
caller). Condition A was owner-side relay config-shape (`SOLEUR_PROXY_BIND` non-empty;
`SOLEUR_PROXY_PEER_ALLOWLIST` parses to a non-empty set with `parseProxyPeerAllowlist`
parity; `SOLEUR_HOST_ROSTER` parses with `loadHostRoster` parity **plus** fail-closed checks
the loader lacks, since the loader silently degrades to `{}` — reject non-object, invalid
JSON, duplicate key, blank key, blank/non-string value; the standby must be a roster
`host_id`; allowlist peers ⊆ roster addresses). Condition B was the git-data cut-over shape
(`GIT_DATA_STORE_ENABLED == "true"` plus the `GIT_DATA_LUKS_CUTOVER_AT` soak marker, where
absent / malformed / future-dated / soak-not-elapsed all fail closed).

**The design idea worth keeping is the anti-overclaim mechanism.** On success the gate
printed `requires_runtime_bind_probe=true` and a SHAPE-ONLY banner, specifically so that no
consumer — CI or orchestrator — could read exit 0 as "safe to flip weight". It proved
config-shape in Doppler, never that a listener had bound or that container env was live. Any
future multi-origin work (#6459) should reproduce that split rather than let a shape check
quietly become an authorization.

**Why it was deleted rather than patched.** Removing only its `has("web-2")` line would have
left a gate that **passes on a single-host roster** — green-lighting a weight flip to a
nonexistent host. A gate whose subject is gone does not become safer by having its subject
check removed.

## Alternatives considered

**A bake-time coherence gate in `reusable-release.yml`** (this work's own first draft).
Rejected on three independently verified grounds. *(i) Near-tautological* — at `docker_build`
the image and the checkout are the same commit by construction, so the only reachable failure
is list drift, which the parity test already catches earlier and with a better diagnostic (it
names the drifting file; a hash gate prints two opaque 64-hex strings). *(ii) It poisons
`:latest`* — the release job pushes `:v<next>`, `:<sha>` and `:latest` in one
`build-push-action` step, and the gate ran *after* that, so a gate failure would leave the
mutable default pointing at a known-incoherent image. The safety mechanism would have
manufactured the exact single-user incident it existed to prevent. Fixing that properly means
restructuring to `push-by-digest` + post-verify `crane tag` — a release-pipeline redesign.
*(iii) Its enabling premise was false* — it justified a bash hash-recompute script by claiming
`terraform console` needs credentials, but `host_scripts_content_hash` is a pure function of
`path.module` + `filesha256`, and `infra-validation.yml` already proves
`terraform init -backend=false` evaluates it without a Hetzner token or the R2 backend.

**Generalize the verifier to accept a mutable tag.** Rejected — see Decision §2. Also
rejected by PR #6725's recorded decision.

**Pin a digest on create paths "the way the recreate job did".** Rejected: that mechanism
polls the **running** web-1's `/health .version`. On a fresh create there is no running
web-1, `RUNNING_VERSION` is empty, and the script exits 1. It is structurally unavailable on
exactly the path that needs it.

**A Terraform `lifecycle.precondition` requiring a pinned `var.image_name`.** Rejected:
preconditions evaluate during plan on **every** apply including no-op refreshes, and the
routine merge apply passes `:latest`, so this breaks every merge. Terraform also cannot read
inside an image, so it can express *pinning* but never *coherence*.

**Delete the verifier outright**, since all its callers vanish. Defensible, and argued for at
review. Rejected because the retention rule's condition is met, and because deleting it would
leave #6730 to re-derive a byte-exact match to the boot-side comparison — the highest-risk
part to get subtly wrong.

**Build the web-1 birth path here.** Rejected: #6730 owns it. Folding a prod-host-birth
capability into a ~730-line deletion PR inverts the risk budget.

## Consequences

- **Coverage is strictly greater at every commit, and never zero.** Before: one live
  list-parity test plus one unreachable dispatch verifier. After: the same list-parity test,
  two new assertions, and a verifier named in an executable runbook chain.
- **#6712 stays open with its hazard named rather than quietly absorbed.** A reader who sees
  a large web-2 sweep merge should not conclude the coherence problem is solved.
- **The one failure mode this decision cannot prevent has a detection arm.** Boot-side
  `cloud-init.yml` aborts at `stage=verify` and the terminal block emits
  `soleur-boot-emit <stage> fatal`, paging via `sentry_issue_alert.web_terminal_boot_fatal`.
  That alert filters on `stage`, **never on host**, so it is host-generic and is retained —
  it is web-1's sole no-SSH boot page. Deleting it as "web-2 surface" was proposed and
  refused; only its comment was web-2-specific.
- **A safety-shaped mechanism that cannot fire is not a safety mechanism.** The rejected gate
  would have printed `COHERENT` forever for structural reasons. Before shipping a guard, ask
  what input makes it go red; if the honest answer is "none", it is decoration with a failure
  mode.

**Revisit trigger:** #6730 landing a digest-pinned web-1 birth path. At that point the
cross-commit-skew row becomes enforceable — compose `resolve → verify →
-var image_name=<pinned>` on the birth path — and #6712 becomes closable on evidence rather
than on argument.

## C4 impact

Reviewed all three model files (`model.c4`, `views.c4`, `spec.c4`).

- **External human actors:** none added or removed.
- **External systems / vendors:** none added. GHCR is already modeled, and no registry edge
  is introduced (the bake-time gate that would have added one is rejected above).
- **Containers / data stores:** none. `warm_standby` and `web_2_recreate` were workflow jobs,
  not C4 containers.
- **Actor↔surface access relationships:** unchanged.
- **Element descriptions falsified:** none by this decision. `model.c4`'s single
  `warm standby` mention already records web-2's 2026-07-17 retirement correctly and
  describes no live element; one stale line-number citation into the deleted job was
  re-anchored to content.

## Carried-forward requirements for the #6730 birth path (MUST)

Deleting `web_2_recreate` removed assertions that were **never web-2-specific** and that
nothing re-implements today. They are recorded here as binding acceptance criteria for the
digest-pinned web-1 birth path #6730 builds. Until that path exists, the operator
pinned-image chain in the `host_creates` HALT carries them as explicit manual steps.

| # | Requirement | Why it is not optional |
|---|---|---|
| R1 | `SENTRY_DSN` MUST be non-empty in Doppler `prd_terraform` **before** any host is created. | The pre-extraction boot stages read ONLY the baked `${sentry_dsn}`; doppler is not installed yet, so its documented fallback is dead code at that point. An empty DSN means the host boots **dark** — a fresh-boot failure emits nothing and pages nobody. This is the exact zero-emit blind spot #6090 closed. |
| R2 | The birth path MUST surface fresh-host Sentry events after the create. | A green apply is not a green boot. Without the surfacing step a host that died in cloud-init looks identical to one that came up. |
| R3 | R2's reader MUST query the **EU** host `de.sentry.io`. | The project is EU-resident; a US `sentry.io` query against it returns empty — indistinguishable from "no errors". |
| R4 | R2's reader MUST filter events client-side via a regex derived from `QUERY`. | The `/projects/../events/` endpoint ignores `message:` search and returns 0 for events that demonstrably exist. Passing `query=` there is a silent false-negative. |
| R5 | R2's step MUST run `if: always()`. | A success-only surface cannot report the failure it exists to catch. |

Provenance: these were AC14 / AC8 / AC8b / AC13 / AC16 in
`apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`, asserted against the
`web_2_recreate` job. That file records the same loss inline at the deletion site. Re-add
executable assertions there the moment an automated create path exists — a requirement that
lives only in prose is one refactor away from being forgotten.

## References

- Issues #6575 (swept here), #6712 (stays OPEN — cross-commit skew), #6730 (digest-pinned
  birth path), #6574 (`-target` transitivity, unrelated and unchanged), #6425
- ADR-082 → `superseded-in-part` by this ADR; its Item 4 (image digest pin + signature
  verification) remains **in force but UNMET**, owned by #6730
- ADR-114 hazard #5 — the delivery-channel hazard this decision re-scopes host-agnostically
- ADR-068 §(c) — the weight-flip conditions `lb-weight-gate.sh` checked
- ADR-079 amendment (#5955) — the original `.tag`-is-last-attempt finding
- ADR-096 — `OPERATOR_APPLIED_EXCLUSIONS`, the routing the `host_creates` HALT falls back to
