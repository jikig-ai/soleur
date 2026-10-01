---
title: Terraform Remote Backend on Cloudflare R2
status: active
date: 2026-03-27
---

# ADR-006: Terraform Remote Backend on Cloudflare R2

## Context

Both Terraform stacks used local backend with no locking and no backup. State was lost (issue #967). Need reliable, off-host remote state.

Writes are serialized per apply workflow by GitHub Actions concurrency groups, **not** by the backend — R2 does not support S3 conditional writes, so every backend block sets `use_lockfile = false`. That serialization is **partial**, and the amendment below enumerates where it does not reach.

## Decision

Cloudflare R2 as remote backend. Single bucket `soleur-terraform-state` with per-app key paths (e.g., `web-platform/terraform.tfstate`). Doppler-first secrets (only DOPPLER_TOKEN in GitHub Secrets, rest pulled at runtime). Every new Terraform root must include R2 remote backend block.

## Consequences

**Off-host durability — the #967 answer.** State survives loss of the machine that wrote it, which is what the local backend could not do. That is the benefit the decision was taken for, and it is unaffected by the correction below.

Per-app key paths enable clean multi-stack management. Zero egress cost (R2 has free egress). Requires `terraform import` for existing resources during migration.

There is **no point-in-time recovery**: a bad state write is not undoable from the backend. Recovery is config-revert, re-import, or a pre-apply state snapshot available only on terminal-side operations and scoped per root (see the amendment).

**One class has none of those three limbs: resources whose value exists only in state.** `apps/web-platform/infra/` declares 27 `tls_private_key` / `random_password` / `random_id` resources (LUKS passphrases, SSH and TLS keys, signing and webhook secrets). Config-revert cannot recover them — the config is a *generator*, not a record of the value — and re-import requires supplying the value the lost state was the record of. For these, the surviving copy is the **Doppler mirror** (`doppler_secret.workspaces_luks_key`, `git_data_luks_key`, `git_transport_ssh_private_key`, and siblings): re-adoption is `terraform import <address> "<value read from Doppler>"`. Anything with no mirror must be regenerated and redistributed to every consumer that trusts it. Establish this before assuming the three limbs cover a state loss on that root.

The durability gap is open and tracked at #7992.

## Amendment — 2026-09-09 (#7836)

**This ADR claimed a capability that has never existed.** `## Decision` read *"Cloudflare R2 as remote backend **with bucket versioning**"* and `## Consequences` read *"State loss eliminated via bucket versioning."* Both were false on the day they were written and remained so for roughly eighteen months, propagating into `infra/github/README.md` §"Phase 5 -- Rollback" and into a GDPR Article 30 register entry (PA12 §(f) and §(g)) as an Article 32 technical measure. The text above is corrected; this note records what was retired and on what evidence.

**The measurement.** Re-probed 2026-09-09 against `https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com` with `doppler -p soleur -c prd_terraform` credentials, exit codes captured on their own line rather than through a pipe:

- **control** `s3api list-objects-v2 --bucket soleur-terraform-state` -> **rc=0**, six objects listed
- `s3api list-object-versions --bucket soleur-terraform-state` -> **rc=254**, `An error occurred (NotImplemented) ... ListObjectVersions not implemented`
- `s3api get-bucket-versioning` -> **rc=254**, `AccessDenied` (token scope — not decisive on its own, which is precisely why the control call is the finding)

The passing control is what makes this conclusive: it is not an auth, endpoint or token-scope problem that a wider credential would fix. The bucket also holds no `.backup` objects — the S3 backend writes none server-side — so no second recovery substrate sits behind the gap. The contemporaneous evidence that the claim was wrong from the start is `knowledge-base/project/learnings/2026-03-21-terraform-state-r2-migration.md`, the migration that created this backend: it records `use_lockfile = false` because R2 does not support S3 conditional writes, and never claims versioning.

**Five roots, six objects.** `git grep -ln 'soleur-terraform-state' -- '*.tf'` resolves to five live roots; the control call lists **six** keys. The sixth, `telegram-bridge/terraform.tfstate`, is an orphan of a root deleted in `dccc56dee` (#1586) — 181 bytes, a post-`destroy` empty state, so it exposes no credentials. It matters for one purpose only: a `-force` push can clobber any of the **six** keys, so the wrong-root blast radius is six objects even though only five roots are live. #7836's title says "all six roots"; the roots are five and the objects are six.

**The state is not locked, and the correction must not say it is.** All five backend blocks set `use_lockfile = false` — `infra/github/main.tf`, `apps/cla-evidence/infra/main.tf`, `apps/web-platform/infra/main.tf`, `apps/web-platform/infra/sentry/main.tf` and `apps/web-platform/infra/rung2-rehearsal/main.tf`, whose comment is explicit that there is no state lock on this backend. So the original `## Context` carried a second defect alongside the versioning claim: it named *"no locking"* as a motivating problem, and the Decision implied R2 resolved it. R2 resolved neither.

**Where serialization does and does not reach.** `## Context` attributes serialization to the concurrency groups. Enumerated, because "partial" is otherwise unfalsifiable:

| Root | Serializer |
|---|---|
| `infra/github/` | `terraform-apply-github-infra` (`apply-github-infra.yml`) |
| `apps/web-platform/infra/` | `terraform-apply-web-platform-host`, shared verbatim by `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` (#4844) |
| `apps/web-platform/infra/sentry/` | `terraform-apply-sentry-infra-${{ github.ref }}` — **ref-keyed**, so two runs on different refs are not mutually exclusive against the same state key |
| `apps/web-platform/infra/rung2-rehearsal/` | `git-data-state` (`git-data-rung2-rehearsal.yml`), a third apply group |
| `apps/cla-evidence/infra/` | **none** — no apply workflow exists for this root |

`scheduled-terraform-drift.yml` uses group `terraform-drift`, disjoint from every apply group, and a terminal sits outside all of them by construction.

**R2 is not without an immutability primitive.** R2 Lock Rules (`PUT /accounts/{id}/r2/buckets/{name}/lock`) are real and already used in this repo at `apps/cla-evidence/infra/object_lock.tf`. They do not give point-in-time recovery — they cannot resurrect an overwritten object — which is why they do not close this gap. Note for any future design: a bucket-wide (`prefix: ""`) lock rule on `soleur-terraform-state` would be expected to make the live state key un-overwritable and so brick applies across all five roots. That is a prediction from the primitive's semantics, **not a measurement** — rehearse it on a scratch bucket before adopting it.

**The corrected recovery model.** State records what exists; it is not a lever on what exists. Restoring old state only makes Terraform *believe* the old set is live, and the next apply reconciles against the current config — rewriting the damage. So for a bad-config failure the recovery is a **config revert**, not a state rollback. `infra/github/README.md` §"Phase 5 -- Rollback" now routes by failure class: config revert first; `terraform import` when state is lost but resources are intact; revert-then-import when both; and `scripts/create-ci-required-ruleset.sh` when the ruleset is deleted outright. None of those four paths requires a pre-apply snapshot, which is what keeps that runbook operable today.

**The snapshot gesture is scoped per root.** Where a snapshot *is* taken (terminal-side operations, via `terraform state pull`), restoring it is not equally safe across the five backends this ADR governs. On `infra/github/` the managed resources are GitHub rulesets and repository objects — re-importable, and a post-restore apply re-converges. On `apps/web-platform/infra/` the state holds `hcloud_server`, `hcloud_volume`, the 27 state-only secrets named in `## Consequences`, and **18 `terraform_data` host provisioners**; a restore-then-apply there plans destroys and replacements against live infrastructure *and* re-fires host-mutating provisioners. Two members deserve naming because their failure is terminal rather than recoverable: `random_password.workspaces_luks` and `random_password.inngest_redis_luks`, whose own banner records that rotation *"IS NOT A RE-KEY, AND THAT IS A TERMINAL HAZARD (C19)"* — a regenerated passphrase does not re-key the existing LUKS header, permanently stranding the volume. A restore on the host roots is the *start of a reconcile*, not a rollback. There is no snapshot at all on the auto-apply path, because no human is present before the write.

**What this amendment does and does not claim.** It does not claim the durability gap is closed. It claims the record now matches the capability, and that the one gesture which works — a `terraform state pull` snapshot taken before a risky terminal-side apply — is written down accurately, with its refusal modes. The capability limb, an automatic pre-apply snapshot wired into the apply workflows, is deferred and tracked at **#7992**.

**Register anchors.** This is an amendment, not a supersession: the decision did not change, and `status:` stays `active`. **AP-003** (R2 remote backend for Terraform state) stands unmoved — the amendment narrows a consequence, not the principle or the hard rule that carries it (`AGENTS.md` Hard Rules is AP-003's canonical source; `hr-every-new-terraform-root-must-include-an` still directs every new root here). **AP-021** (diagnostic honesty, ADR-166) is the principle this failure is an instance of: *"a CI-emitted message may only name a cause the job MEASURED ... a cause measured ONCE is not a cause measured ALWAYS."* AP-021 is currently scoped to CI-emitted messages; this ADR named a capability nobody measured, and it propagated into a statutory register. Whether that scope should extend to architectural records is recorded for consideration in #7992.

> **Shape note.** This ADR is cited by `plugins/soleur/skills/architecture/references/adr-template.md` as the terse-three-section exemplar. With this amendment it is no longer a good example of that shape; the amendment is an audit record, not a fourth standing section. See that file's exemplar note.
