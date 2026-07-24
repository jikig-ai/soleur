---
title: Encryption posture is a design-time default, enforced by a resolvable-evidence ledger
status: accepted
date: 2026-07-24
related: [6588]
related_adrs: [ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn, ADR-117, ADR-119, ADR-129]
brand_survival_threshold: single-user incident
---

# ADR-140: Encryption posture is a design-time default, enforced by a resolvable-evidence ledger

## Context

`hcloud_volume.workspaces` (web-1 `/mnt/data`) was provisioned as plaintext `ext4` while
`docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` told data subjects it
was LUKS-encrypted (#6588). The gap survived for weeks for two structural reasons: nothing at
design time forced the encryption decision to be made and recorded, and nothing mechanical ever
compared the claim against reality — the legal docs were prose, the volume was a block device,
and no artifact joined them. Closing it cost a multi-day cutover: a sole-copy-data write freeze,
an operator-accepted irreversible discard of a 27-minute stranded-write window, and a separate
latent `readyz` peer-gate bug fix (#6879) before the cutover could even certify.

The goal here is that no future Soleur user — nor Soleur itself — repeats that. Encryption
posture (at-rest **and** in-transit) needs the same standing, mechanically-verified default that
observability, GDPR, and IaC routing already have.

## Decision

### The gate is three layers, not one

| Layer | Where | What it asserts | Blocking? |
|---|---|---|---|
| **Design** | `plan` §2.11 + `deepen-plan` §4.10 | The decision was *made and recorded* (a `## Encryption Posture` block: `at_rest` / `in_transit` / `exception`) | Halts the pipeline |
| **Static (Layer A)** | `scripts/lint-encryption-posture.py` → CI required check + `preflight` Check 12 | Every store/connection in the repo has a ledger row **whose cited evidence resolves to real code** | Required check |
| **Live (Layer B)** | `apps/web-platform/server/inngest/functions/cron-encryption-posture-reconcile.ts` → `.github/workflows/scheduled-encryption-posture-reconcile.yml` | The **actual** provider/host state matches the ledger | Fails the schedule → files an issue |

**A declaration-only gate (design + ledger, no live probe) is rejected.** It reproduces #6588
exactly: the legal docs *declared* LUKS while the volume was ext4. A gate that only reads the
repo — even a repo containing a ledger — is still, ultimately, a set of claims about itself. The
incident being encoded against was precisely a claim-vs-reality divergence, so Layer B (the live
reconcile) is mandatory, not optional polish.

### Evidence must be mechanically resolvable, never asserted, and never keyed by name similarity

For each store class, the ledger row names a citation and Layer A **resolves** it against real
code — an unresolvable or absent citation is a FAIL, not a warning. Critically, resolution is
never a name- or mount-path-similarity join. The namespace is adversarial by construction:
`hcloud_volume.workspaces` (plaintext, the #6588 volume) sits beside
`hcloud_volume.workspaces_luks` (LUKS, mapper `workspaces`) — under any string-similarity join,
`/dev/mapper/workspaces` matches the plaintext `workspaces` at least as well as its encrypted
sibling, so a row claiming `mechanism: luks` on the plaintext volume while citing its sibling's
apparatus would false-PASS, certifying the exact volume this feature exists to catch.

Every `hcloud_volume` ledger row therefore carries a `device_binding`: the Terraform resource
address of the volume **and** the `hcloud_volume_attachment` that carries it. The detector
reaches the LUKS citation chain **from that attachment** (attachment → host cloud-init/bootstrap/
cutover for that host → the `cryptsetup` site on that host) — never from a name match. This is
what makes "resolvable evidence" a real property rather than a grep that happens to pass today.

### The exception path is a ledger row, never a suppression comment

There is no silencing mechanism — no `# noqa`, no `--skip` flag, no `SKIP_*` env var, no
allowlist file. The only way past the gate for a genuinely plaintext store or an unverified
connection is a ledger row with `mechanism: plaintext-exception` (or `cert_verification: off`)
carrying a named `justification`, a `tracking_issue` (`^#[0-9]+$` — required, never silenced),
`reevaluate_when`, and a hard clock: `expires_on` (≤90 days from acceptance), enforced by Layer A
offline (date arithmetic only, no network, no issue-state dependency). An expired exception FAILs
the required check. Renewal is a dated, reviewable ledger diff — never a comment edit.
`tracking_issue` state (`CLOSED` while the exception is still live) is checked by Layer B and
demoted to a warning: rewarding "leave the tracking issue open forever" with a hard FAIL would
make routine backlog-draining break the gate, but a closed issue on a live exception is still a
signal worth surfacing.

### Layer A is hermetic and offline

The static detector runs with no network access and no credentials — `terraform state list`,
`git grep`, and file reads only. This is asserted, not just intended: the sweep is run under a
simulated shallow checkout and with no network reachable, and must produce the identical verdict
as a full clone with network access. Hermeticity is what makes Layer A safe to run as a required
check on every PR, including forks and bot PRs, without provisioning infra credentials into CI.

### Layer B uses the Inngest-dispatch hybrid, not a bespoke GitHub Actions cron

53 Inngest cron functions exist against 10 `.github/workflows/scheduled-*.yml` crons — Inngest is
the canonical scheduled-work path
([ADR-033](./ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md)), and
a `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` PreToolUse hook denies a bare new
`scheduled-*.yml` carrying a `schedule:`/`cron:` directive. An earlier draft of this design argued
a circularity exemption for a bespoke GitHub Actions cron: Layer B needs credential-heavy infra
tokens (Hetzner, Cloudflare, Supabase, Better Stack) that must not be parked on the app host, and
— the argument went — a verifier hosted on Inngest's own durable-queue substrate
(`hcloud_volume.inngest_redis`) would go dark exactly when that substrate is the problem. **That
circularity argument was unsound**: a plaintext AOF does not crash Inngest — the correlation
between "the volume Layer B audits is plaintext" and "Inngest is unavailable" is approximately
zero, not one. The residual risk is Inngest-trigger *availability*, not a load-bearing dependency,
and it is already covered by the existing `scheduled-inngest-health.yml` heartbeat.

ADR-033's own scope note is explicit on this point and names the correct shape directly:

> For a **credential-heavy infra cron** whose execution *must* stay in an ephemeral runner (e.g.
> `scheduled-terraform-drift`: terraform binary + R2/AWS/Doppler `prd_terraform` cloud-admin creds
> that must NOT be parked on the long-lived app host), Option C is the *correct* shape — only goal
> (a) "kill GHA scheduling jitter" applies; goal (b) "move execution in-process" is actively
> harmful. **Do not mis-cite this rejection as a blanket ban on Inngest→workflow_dispatch.**

Layer B therefore adopts the **Inngest-dispatch hybrid**:
`cron-encryption-posture-reconcile.ts` owns the schedule and dispatches
`scheduled-encryption-posture-reconcile.yml`, which keeps `on: workflow_dispatch:` only (no
`schedule:`/`cron:` directive) — so the `prefer-inngest` hook never fires, and no override hatch
or in-file justification block is needed. This is the same shape `cron-terraform-drift.ts` already
uses for the terraform-drift cron.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| **An `AGENTS.md` `hr-*` hard rule** | Two independent, measured blockers. **Budget:** `B_ALWAYS = 22900/23000` (≈100 bytes headroom); an index pointer line costs ≈50-60 bytes, leaving ≈40 — the next sibling PR would trip `[REJECT]` and block every commit. **Loader-class infeasibility (decisive):** this rule's trigger surface spans `*.tf` (→ `infra` class → loads `core + rest`) **and** `plugins/*/skills/*/SKILL.md` (→ `.md` → `docs-only` class → loads `core + docs-only`). A rule that must fire on both can only live in `AGENTS.core.md`, which has zero room; placing it in `rest` would make it a silent no-op on its own `docs-only` trigger. The insight is domain-scoped (infra/data-design turns only), so it routes into the owning skills and agents (`terraform-architect`, `platform-strategist`, `provision-hetzner`, `provision-cloudflare`) instead. |
| **An attribute-presence detector (`encrypted = true`)** | Structurally impossible for the stack in use: there is no `hcloud_volume` `encrypted` attribute (`hetznercloud/hcloud` v1.63.0, `.terraform.lock.hcl`; verbatim in `apps/web-platform/infra/workspaces-luks.tf` §SHARP EDGE and `git-data-luks.tf`). Such a detector would either be unpassable for every Hetzner volume, or — worse — satisfiable by a comment, which is the exact false-assurance shape the whole feature exists to prevent. |
| **A declaration-only gate (design + ledger, no live probe)** | Reproduces #6588 exactly: the legal docs *declared* LUKS while the volume was ext4. A gate that never checks live state cannot catch a claim/reality divergence — only a Layer B live reconcile can. |
| **Layer B as a bare GitHub Actions cron, with the `prefer-inngest` hook overridden** | The circularity argument for exempting Layer B from Inngest was unsound (see Decision, above) — a plaintext AOF does not crash Inngest. ADR-033's own scope note already names the correct shape (Inngest-dispatch → `workflow_dispatch`-only workflow) for exactly this class of credential-heavy infra cron; using the hook's override hatch here would have been citing a rejection that does not apply. |
| **Resolving `mechanism: luks` evidence by name/mount-path similarity** | Adversarial by construction: `hcloud_volume.workspaces` (plaintext) and `hcloud_volume.workspaces_luks` (encrypted) share a mapper name (`workspaces`) under any similarity join, so a row on the plaintext volume citing its sibling's apparatus would false-PASS — certifying the exact volume the feature exists to catch. Evidence must be reached via `device_binding` (the volume's own `hcloud_volume_attachment`), never a name match. |
| **`git merge-base`-scoped lint (new-entrants only)** | Goes vacuous on a `fetch-depth: 1` checkout and again after its own PR merges. The committed ledger provides "don't re-litigate accepted debt" without the history dependency. |
| **Advisory (non-required) CI job** | At a `single-user incident` brand-survival threshold, an advisory gate is no gate. Layer A is promoted to a required check via a byte-consistent coupling of edits in the same PR — see the **#6901 Amendment** below, which corrects this to a **five-site** coupling (not three) and pins the integration_id shape. |

## Consequences

- Every persistent store and cross-component connection introduced from this point forward
  carries a declared, mechanically-verified encryption posture from the first commit — the
  design gate halts before HCL is even generated (`platform-strategist`'s Decision Framework,
  `terraform-architect`'s generation defaults) and Layer A blocks merge if the declaration's
  evidence does not resolve.
- The ledger (`scripts/encryption-posture-ledger.json`) is the single join between "what the
  code does" and "what is publicly claimed" (`disclosed_as`) — the exact join #6588 lacked. A
  `plaintext-exception` or `cert_verification: off` row whose `disclosed_as` anchor resolves to
  text asserting encryption is itself a Layer A FAIL.
- This ADR remediates nothing by itself: no existing store's encryption posture changes as part
  of landing the gate. Findings from the one-time audit that seeded the ledger are tracked as
  separate issues, cross-linked `Ref #6588`, never `Closes #6588`.
- A future infra cron needing credential-heavy, ephemeral-runner execution has a named precedent
  (this ADR + `cron-terraform-drift.ts`) instead of re-litigating the Inngest-vs-GitHub-Actions
  question from scratch.

## C4 impact

`platform.infra.workspacesVolume`'s description and the `hetzner -> workspacesVolume`
relationship in `model.c4` are corrected in the same change (see `views.c4`/`model.c4` edits) to
reflect the 2026-07-23 LUKS cutover rather than the pre-cutover plaintext state — otherwise the
model itself would carry the same claim-vs-reality gap this ADR closes. No new container, actor,
or system is introduced; `inngest` (`model.c4:188`) already models the container Layer B's
dispatch function runs in.

## Amendment (2026-07-24, #6901)

Promoting the Layer A repo-sweep to a **required** check is a **five-site** byte-consistent
coupling, not the three coupled edits the alternatives table above states. The two omitted sites
are part of the #6049 synthetic-check drift-proof chain, bound byte-for-byte to the first three by
`plugins/soleur/test/required-checks-canonical-parity.test.sh`:

1. `.github/workflows/ci.yml` — the standalone `encryption-posture` job (extracted from
   `lint-bot-statuses` in #6901; already landed so the context begins to soak).
2. `scripts/required-checks.txt` — add the `encryption-posture` context.
3. `infra/github/ruleset-ci-required.tf` — add the `required_check` block and amend the ABI-count
   comment.
4. `scripts/ci-required-ruleset-canonical-required-status-checks.json` — the parity SSOT; the
   parity test asserts set-equality (⊆ and ⊇) with `required-checks.txt`, so 2 and 4 must land
   byte-consistent or the test reds.
5. `.github/actions/bot-pr-with-synthetic-checks/action.yml` — the synthetic-check adjudication;
   `CHECK_NAMES` is derived from `required-checks.txt`, so adding the name there auto-includes it,
   sound only while the sweep's scan surface (`encryption-posture-ledger.json` + `*.tf`/infra
   evidence) stays disjoint from the action's `ALLOWED_PATHS`.

**Integration_id shape.** The required-check must pin `integration_id 15368` (the GitHub Actions
app, which posts the `ci.yml` `run:` job's check-run) **and add** the context name to
`required-checks.txt` — the sound-by-unreachability fabrication precedent (`rule-body-lint` /
`sentry-destroy-required`). This is **not** CodeQL's OMIT-name + non-15368 shape: a `required_check`
pinned to a non-15368 id is never satisfied by a `run:` job's 15368 check-run, so GitHub would hold
every PR at `Expected — Waiting` forever (the CodeQL match mechanism in reverse).

**Measure-then-arm (ADR-117).** Arm only after the standalone `encryption-posture` context has
soaked a green streak across diverse PRs; the concrete N is a tunable recorded in the arming
tracking issue, deliberately **not** in this ADR (an ADR records the decision *shape*, not a
threshold). Residual risk: the parity test validates that the two files *agree*, not that 15368 is
the *correct* id — the arming PR must confirm with a live post-apply check that a real PR reaches
the `encryption-posture` required check as satisfied.
