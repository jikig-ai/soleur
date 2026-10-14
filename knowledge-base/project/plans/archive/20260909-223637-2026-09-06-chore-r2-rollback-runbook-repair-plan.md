---
title: "chore(infra): the documented Terraform state rollback cannot run — repair the runbook, ADR-006, and the Art. 30 register"
date: 2026-09-06
slug: chore-r2-rollback-runbook-repair
branch: feat-one-shot-7836-r2-no-object-versioning-rollback
issue: 7836
closes: [7836]
lane: cross-domain
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened:** 2026-09-09 · **Agents:** architecture-strategist, code-simplicity-reviewer,
spec-flow-analyzer, terraform-architect, legal-compliance-auditor, learnings-researcher.

The plan's two central calls survived review unchanged: **Option 2 is right, the deferral is right,
amendment-over-supersession is right.** The work was in stopping the correction from shipping *its own*
unmeasured claims — the very defect it exists to remove. Five findings changed the plan's shape:

1. **The recovery model was wrong, not just its mechanism (AC2).** `infra/github/` auto-applies on
   merge, so no operator is present to take a pre-apply snapshot — and state rollback does not fix a
   *live-resource* failure anyway, because step 3 re-applies the same bad config. Rebuilt as a failure
   taxonomy with **config-revert first**. None of the four real recovery paths needs a snapshot, which
   is what keeps the runbook operable today and the AC14 deferral coherent.
2. **ADR-006 carries TWO false limbs, not one (AC6).** The draft's replacement wording — "reliable,
   **locked**, off-host" — was itself false: all five backends set `use_lockfile = false`. It would
   have written a second non-existent capability into the ADR being corrected for a non-existent
   capability.
3. **`terraform state push` refuses the rollback case by construction (AC2b).** Lower serial needs
   `-force`; `-force` then disables the wrong-root lineage guard; and `state push` has no `-backup`,
   so the restore is itself a one-way door.
4. **PA12 §(g) asserts FIVE false Art. 32 safeguards, not one (AC9a)** — including item (8),
   *"No CI auto-apply"*, which misstates the authorization model of a production policy surface. A
   `[CORRECTION (#7836)]` stamp certifies the whole cell, so correcting one and leaving four is worse
   than not touching it. Plus a CRITICAL sub-processor mapping omission (AC16).
5. **Two ACs would have failed a CORRECT diff** — AC1 forbade the runbook from naming the command it
   retires, and AC10's sweep returned 200+ unbounded lines. Both rescoped.

Also: the GDPR-gate waiver was **removed** (a hard-rule waiver cannot rest on an agent's paraphrase),
and one "deferred" capability turns out to be **already implemented** in `apply-sentry-infra.yml`.

## Overview

`infra/github/README.md` §"Phase 5 -- Rollback" opens by listing prior state versions in R2. That
call returns `NotImplemented`, so step 2 — which restores by `versionId` — has no input, and the
documented recovery procedure cannot be executed. A runbook that names an impossible command is worse
than no runbook: it is read during an incident, by someone who will spend their first minutes
discovering it does not work.

The claim did not originate in that README. It originates in **ADR-006**, which records the decision
as *"Cloudflare R2 as remote backend **with bucket versioning**"* and its consequence as *"State loss
eliminated via bucket versioning."* Both have been false since the decision was taken. The README is
downstream; so is a **GDPR Article 30 register entry** that lists the same non-existent capability as
an Article 32 technical measure.

This is split from the #7826/#7829/#7834 Sentry PR
(`2026-09-06-chore-sentry-adoption-cleanup-plan.md`), which shares no file, gate or failure mode with
it and carries a merge hold on an unrelated Sentry apply.

## Research Insights

### Measurement M4 — R2 object versioning, re-probed 2026-09-06

Credentials `doppler -p soleur -c prd_terraform`, endpoint
`https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com`:

- **control** `s3api list-objects-v2 --bucket soleur-terraform-state` → rc=0, six objects listed
- `s3api list-object-versions --bucket soleur-terraform-state` → `An error occurred (NotImplemented)
  … ListObjectVersions not implemented`, rc=254
- `s3api head-object --key web-platform/sentry/terraform.tfstate` → 200
- `s3api get-bucket-versioning` → `AccessDenied` (token scope; not decisive alone — which is exactly
  why the control call matters)

The control is the finding: this is **not** an auth or endpoint problem a wider token would fix.
The 2026-09-04 measurement recorded in #7836 still holds, re-measured rather than trusted.

### Measurement M5 — re-probed again 2026-09-09 [Updated 2026-09-09]

Phase 0 of this plan was executed before any edit, on the branch that carries it. Same credentials,
same endpoint, exit codes captured on their own line rather than through a pipe:

- **control** `s3api list-objects-v2 --bucket soleur-terraform-state` → **rc=0**, the same six objects
- `s3api list-object-versions --bucket soleur-terraform-state` → **rc=254**,
  `An error occurred (NotImplemented) … ListObjectVersions not implemented`
- `s3api get-bucket-versioning --bucket soleur-terraform-state` → **rc=254**, `AccessDenied`
  (token scope — not decisive alone, which is why the control is the finding)
- `s3api head-object --key github/terraform.tfstate` → **rc=0**

Cloudflare has **not** shipped R2 object versioning in the interval. The plan keeps the shape it was
written in: make the docs true. Had this returned rc=0, the plan would have changed shape instead.

The bucket also holds **no `.backup` objects** — the S3 backend does not write one server-side — so
there is no second recovery substrate hiding behind the versioning gap. Six objects, six live
current-state files, no history of any kind.


### The blast radius is narrower than the issue claims

Issue #7836 says *"every Terraform root in this repo has a rollback runbook that cannot run."* Measured:
**exactly one root has a rollback section at all.** Four of five live roots have none and two have no
README. `git grep -l 'list-object-versions\|versionId'` over live surfaces returns three files, one
of which is a carved-out spec artifact.

Also: the bucket holds six state objects but `git grep -ln 'soleur-terraform-state' -- '*.tf'`
resolves to **five** roots — `telegram-bridge` was removed in `dccc56dee` (#1586). The sixth object is
an orphan of a deleted root.

### The correct replacement gesture already exists in this repo

`knowledge-base/engineering/operations/runbooks/moved-block-wedge-cutover-5887.md` documents the one
state-recovery gesture that actually works: `terraform state pull > /tmp/tfstate.pre-<op>.$(date +%s).json`
before the risky apply (*"keep off-host"*), and `terraform state push` to restore. It is an
**operator-taken snapshot**, not point-in-time recovery — the distinction the replacement text must
make plainly.

### Institutional learnings that bind this correction [Added 2026-09-09]

Four learnings apply directly; each changed an AC above.

- **`2026-07-20-a-correction-pr-verified-the-old-claim-was-gone-not-that-the-new-one-was-supported.md`**
  — *"Every sweep AC was an absence assertion … nothing asserted presence-with-provenance."* This
  plan was exactly that shape until **AC15** was added.
- **`2026-03-21-terraform-state-r2-migration.md`** — the migration that created this backend records
  `use_lockfile = false` because *R2 does not support S3 conditional writes*, and never claims
  versioning. It is the contemporaneous evidence that **ADR-006 overstated the capability on the day
  it was written**, and the source for AC6's second false limb.
- **`2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md`** —
  *"Shipping the workflow without touching the ADR would have left a `git grep` trap: a future agent
  finds an ADR that says X alongside a workflow that does Y, and treats the older ADR as
  authoritative."* This is why ADR-006 is in scope rather than the README alone.
- **`2026-06-04-art-30-pa-citation-must-be-grep-validated-against-register.md`** — *"The plan's
  PA-number is a precondition to verify, never a fact."* PA12 §(f) and §(g)(4) were read from the
  register rather than inherited from the issue; both were confirmed present verbatim.

### The house precedent for the corrected wording is already written

`.github/workflows/apply-sentry-infra.yml` (do **not** edit — owned by PR 7866) already carries the
honest form, anchored at *"Nor is R2 a restore path."*, naming the `NotImplemented` result, the
measurement date, the passing control, and #7836. The replacement text should read like this.

### Surfaces found at plan review that the first draft missed

`knowledge-base/legal/article-30-register.md` PA12 asserts the non-existent capability twice, once as
a **GDPR Art. 32 technical and organisational measure**:

- §(f) Retention: *"prior versions are retained per R2 bucket versioning (rollback path documented in
  `infra/github/README.md` Phase 5)"*
- §(g) TOMs (Art. 32) item (4): *"**R2 backend versioning + TLS** (ADR-006) — state-file
  confidentiality + rollback substrate"*

Both cite documents this PR corrects **by name**, so correcting the README and ADR-006 without the
register would leave a GDPR register pointing at two documents for a claim neither makes any more.
The register has an established amendment convention in the same entry:
`[2026-08-20 CORRECTION (#7624): this cell previously read…]`.

Two lower-stakes surfaces carry an unmeetable criterion:
`knowledge-base/project/specs/feat-terraform-state-mgmt/spec.md` has an open
`- [ ] R2 bucket versioning is enabled`, and its `tasks.md` carries a **checked**
`- [x] 1.3 Enable bucket versioning — deferred (R2 versioning API TBD)`.

## Alternative Approaches Considered

[Updated 2026-09-09] #7836's "Done when" offers two non-exclusive options and leaves the choice open.
That choice is a technical fork, decided and justified here rather than escalated
(`hr-technical-fork-is-not-an-operator-question`). The first draft of this plan acted on Option 2
without recording why the others were rejected; this section closes that gap.

| Option | Verdict | Why |
|---|---|---|
| **1a — enable R2 bucket versioning** | **Refuted by measurement** | M5, re-probed 2026-09-09: `list-object-versions` → rc=254 `NotImplemented` while the control `list-objects-v2` → rc=0 on the same credential and endpoint. There is no toggle to flip. This is not a token-scope problem a wider PAT would fix. |
| **1b — scheduled copy to a *new* versioned store** | **Rejected on blast radius** | `terraform.tfstate` holds provider credentials in plaintext. Copying it to a second store multiplies the secret-bearing surface by one whole vendor: a new credential, a new egress path, a new encryption-posture obligation, and a new Art. 32 TOM to defend — to fix a documentation defect. The register entry this PR *narrows* would have to be widened instead. |
| **1c — scheduled copy to a *timestamped key in the same bucket*** | **Right idea, wrong trigger — deferred, tracked** | Strictly better than 1b: same store, same credential, same posture, no new vendor; versioning emulated in key-space (`github/history/terraform.tfstate.<epoch>`). But a **scheduled** copy recovers only to the last cron tick, and the failure mode is *"an apply just wrote bad state"* — so the damage window is the cron interval, by construction. The gesture that actually defends this failure is a **pre-apply** snapshot, which is exact. |
| **2 — make the docs true** | **Adopted — this PR** | Discharges the issue's "Done when" on its own, removes an active incident-time hazard immediately, and carries zero apply risk. |

### Why the capability work is not folded into this PR

The correct capability-restoring design is not the issue's "scheduled copy" but an **automatic
pre-apply snapshot** wired into the apply workflows (`apply-github-infra.yml`,
`apply-web-platform-infra.yml`, `apply-sentry-infra.yml`, `apply-deploy-pipeline-fix.yml`) plus the
manual runbook path. That is real infrastructure work with its own design surface: a key scheme, a
retention/lifecycle policy (timestamped keys grow without bound), a restore procedure, an IaC routing
decision per `hr-all-infrastructure-provisioning-servers`, and its own Encryption Posture and
Observability sections.

Three reasons it ships separately rather than here:

1. **It needs a rehearsal substrate and a per-root disclosure analysis — not "it cannot be
   validated". [Rewritten 2026-09-09 — the first form asserted an unmeasured impossibility, which is
   this PR's own thesis violated.]** Validation *is* possible: the write leg is read-only ("the
   pre-apply object exists and is byte-equal to `terraform state pull`"), and the restore leg has a
   rehearsal substrate already in-repo — `apps/web-platform/infra/rung2-rehearsal/` holds **a
   distinct state key** and exists precisely as a control. The real obstacles are (a) that rehearsal
   surface is additional design work, and (b) **this repository is PUBLIC** (verified
   `visibility: PUBLIC`), so the artifact route needs a **per-root** disclosure analysis: the sentry
   precedent concluded *"the incremental disclosure is nil"* **for that root's contents**, whereas
   `web-platform` state carries `random_password.git_data_luks`, `random_password.registry_luks`,
   `tls_private_key` and every provider token in plaintext. That is the strongest reason to defer, and
   the first draft never named it.
2. **Holding the correction behind it keeps the impossible command in the runbook** for the entire
   duration of the infra work — during which the runbook may actually be read.
3. **The two changes are SEQUENTIAL, not disjoint.** This PR edits markdown; that one edits
   workflows and adds a retention policy — but it will *re-edit* §Phase 5 and *re-amend* ADR-006, since
   the manual gesture becomes the fallback to an automatic one. Sequential dependency, so still
   correct to split — but the first draft's "share no file" was wrong.

**One of the four workflows already implements it.** `apply-sentry-infra.yml` runs
`terraform state pull > "${RUNNER_TEMP}/sentry-state-pre.json"` under *"Capture PRE-apply state
(forensics)"*, with short retention and a secret-sentinel sweep. So the deferred work has a working
exemplar — the design surface is smaller than the first draft implied, and that file must be struck
from the "wire it into these four" list.

### Substrates named and rejected, so the deferred issue need not re-derive them

| Substrate | Verdict |
|---|---|
| **Backend replacement** (HCP Terraform / AWS S3) — the only option giving native versioning **and** locking | Already scoped out at `specs/feat-terraform-state-mgmt/` §Out of scope (*"Migration to HCP Terraform or AWS S3"*). Cite that rejection rather than omitting the option. |
| **R2 Lock Rules** — R2's native immutability primitive, `PUT /accounts/{id}/r2/buckets/{name}/lock` | **Real, and already used in this repo** (`apps/cla-evidence/infra/object_lock.tf`, 10-year age-based). Does **not** give PITR — it cannot resurrect an overwritten object — so it does not fix #7836. **The ADR amendment must not conclude "R2 offers no immutability primitive."** Sharp edge for the deferred design: a bucket-wide (`prefix: ""`) rule on `soleur-terraform-state` would make the live state key un-overwritable and **brick every apply on all five roots** — prefix-scope to `*/history/` only. |
| **`errored.tfstate`** — written to the working dir when Terraform cannot persist state after an apply | A genuine second substrate for a *distinct* failure mode. `git grep errored.tfstate` → **zero hits repo-wide**: no runbook names it and no workflow uploads it, so on the CI path it **dies with the runner**. Cheap to fix; belongs in the deferred issue. |
| **Local `terraform.tfstate.backup`** | Does **not** exist with remote state, though three `.gitignore` files still list it (vestigial from the pre-#967 local-backend era). Say so once, or a future reader hunts for a file the `.gitignore` promises. |
| **Workspace state** (`env:/`, `workspace_key_prefix`) | Unused — all five roots use the default workspace. Half a sentence so nobody proposes it. |
| **GitHub Actions artifact capture** | Precedented in `apply-sentry-infra.yml`, but gated per-root on the public-repo disclosure analysis above. |

Triaged inline per `wg-defer-only-after-inline-triage`; filed per `wg-when-deferring-a-capability-create-a`
and asserted by **AC14**.

**Re-evaluation criteria for the deferred issue** — act on whichever fires first:

- Cloudflare ships R2 object versioning (re-run M5's probe pair; the control call is the tell), which
  collapses the work to enabling a flag; **or**
- any Terraform root gains an unattended auto-apply path where no operator is present to take a
  manual `terraform state pull` first; **or**
- a state-corruption incident actually occurs on any root — at which point the manual gesture has
  demonstrably not been enough.

### What this PR does *not* claim

It does not claim the durability gap is closed. It claims the **documentation now matches the
capability**, and that the one gesture which works — an operator-taken `terraform state pull`
snapshot before a risky apply — is written down accurately. ADR-006's amendment note must say the
gap is open and tracked, not that a snapshot is equivalent to point-in-time recovery.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is documentation. The harm it
*prevents* is the incident case: an operator following an inoperable runbook during a state
emergency, burning their first minutes on a command that cannot work.

**If this leaks, the user's data is exposed via:** no new exposure. No store, credential or egress
path changes.

**Brand-survival threshold:** `none` — documentation-only, touching no sensitive code path.
*Scope-out note:* `threshold: none, reason: the change edits five markdown documents and no
executable surface; the only behavioural effect is that an operator reads accurate instructions.*

## Acceptance Criteria

> **[Restructured 2026-09-09 after deepen-plan review.]** The first draft swapped the *state-acquisition
> mechanism* inside a recovery model it had inherited without testing. Review established that the
> model itself is wrong for this root (AC2). The ACs below are rebuilt around the corrected model.

### The finding that reshaped this plan

`infra/github/` **auto-applies on merge**: `apply-github-infra.yml` runs
`terraform apply -auto-approve -input=false tfplan` on push to `main` under `infra/github/*.tf`, and
the README says so itself — *"No terminal-side `terraform apply` is required for any normal flow."*

Two consequences the first draft missed:

1. **An operator-taken pre-apply snapshot cannot be taken on this path.** There is no moment a human
   sits at a terminal before the write. A runbook built on "restore the snapshot you took" would have
   been *honest and still inoperable* — relocating the impossibility from "R2 has no versioning" to
   "no human was present." That is the same defect in a new costume.
2. **State rollback does not fix the failure Phase 5 opens with.** Phase 5 says *"If a Terraform apply
   broke the ruleset"* — a **live-resource** problem. State records what exists; it is not a lever on
   what exists. Restoring old state only makes Terraform *believe* the old set is live, and step 3's
   `apply` then reconciles against **the current (bad) config that triggered the apply** — rewriting
   the damage. The correct recovery is a **config** rollback.

**AC2 — §"Phase 5 -- Rollback" is rebuilt as a failure taxonomy, config-revert first.**
The section must route the operator by *which failure they have*, not present one gesture:

| Failure | Recovery |
|---|---|
| Bad config applied → live ruleset wrong (**the common case**) | `git revert` the offending commit, merge; auto-apply reconciles |
| State lost/corrupted, resources intact | `terraform import` — the ids are hardcoded (`soleur:14145388`, `soleur:13304872`, `soleur-marketplace`) |
| State corrupted **and** config bad | revert first, then import (or push a snapshot, if one exists) |
| Ruleset deleted outright | `scripts/create-ci-required-ruleset.sh` — the repo's self-described *"documented DISASTER-RECOVERY restore path"* |

**None of the four requires a pre-apply snapshot.** That is what makes the runbook operable today
with no new infrastructure, and it is why AC14's deferral remains coherent (see AC14).

**AC2b — where `terraform state push` IS documented, its refusal modes are documented with it.**
Terraform refuses a state whose `serial` is lower than the remote's (needs `-force`) and refuses
outright on a `lineage` mismatch. A restored snapshot is **always** older than the state a bad apply
just wrote, so the naive gesture errors on its first command. Measured: `lineage`, `serial` and
`-force` appear **nowhere** in any runbook — including
`knowledge-base/engineering/operations/runbooks/moved-block-wedge-cutover-5887.md`, the runbook this
gesture was to be copied from, which carries the identical omission. Document the caveat here; a
follow-up to correct the source runbook rides on the AC14 issue.
Three further hazards must be written down with it, none of which the first draft carried:

- **`-force` disables the wrong-root guard.** Five roots share `soleur-terraform-state`, and the
  precedent's snapshot filenames are all `/tmp/tfstate.pre-*.json`. `-force` skips the lineage check,
  so pushing the *wrong* root's snapshot over `github/terraform.tfstate` **succeeds silently**.
  Require an identity assertion first: compare `.lineage` between the snapshot and a fresh
  `terraform state pull`, confirm `.serial` is lower (that is *why* `-force` is needed, not a reason
  to abort), and confirm the working directory is the intended root.
- **`state push` has no `-backup` flag** (unlike `state mv`/`state rm`), so the restore is itself a
  one-way door. **Pull the current bad state to a second file BEFORE pushing the snapshot** —
  otherwise a wrong restore destroys the only copy of the post-apply state, including resources the
  bad apply legitimately created.
- **A snapshot restores the RECORD, not the WORLD.** Terraform persists state incrementally, so a
  half-succeeded apply leaves real resources the restored state does not know about; the next apply
  duplicates them or errors `already exists`. Reconcile with `terraform plan` plus `import`/`state rm`
  before applying.

> Concurrency hazard: with `use_lockfile = false` (AC6) a terminal-side `state push` races any
> concurrent CI apply with no mutual exclusion — an operator's terminal sits outside every
> concurrency group by construction. Note also that `scheduled-terraform-drift.yml` uses group
> `terraform-drift`, **disjoint** from `terraform-apply-github-infra`, so serialization is partial
> even between CI jobs. Check for an in-flight run (`gh run list --workflow=… --json status`) before
> pushing.

**AC2e — the ADR amendment scopes the gesture PER ROOT.** ADR-006 governs all five backends, and
`state push` is not equally safe across them. On `infra/github/` the resources are a GitHub ruleset —
fully re-importable, and a post-restore `apply` re-converges idempotently. On
`apps/web-platform/infra/` the state holds `hcloud_server`, `hcloud_volume`,
`random_password.git_data_luks`, `random_password.registry_luks` and `tls_private_key`; there the
same restore-then-`apply` sequence plans **destroys and replacements against live infrastructure**.
AC4's preserved *"`apply` — NOT `apply -refresh-only`"* caveat is correct for the ruleset root and
dangerous if read as universal. The amendment must say a restore on the host roots is the **start of
a reconcile, not a rollback**.

**AC2c — the pre-write instruction appears where it is read BEFORE the write.**
Any snapshot or caution the recovery depends on must also appear in §"Authorization model:
apply-on-merge", §"Phase 1 -- First apply", or §"Phase 2 -- Subsequent applies" — the sections an
operator reads *before* acting. A recovery precondition that appears only in the recovery section is
too late by construction.

**AC2d — new §Phase 5 establishes its own preconditions.** The old steps were self-contained
`aws s3api` calls runnable from anywhere. Every replacement gesture needs cwd `infra/github/`, a prior
`terraform init`, and `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` exported for backend auth — none of
which §Phase 5 establishes; the only such sequence sits ~70 lines earlier under a conditional lead-in.
Give §Phase 5 its own `cd` + `export` + `init` preamble, written for a **cold terminal at 3am**.

**AC1 — the runbook PRESCRIBES no impossible command.**
No *command the operator is told to run* may call `list-object-versions` or restore by `versionId`.
Scope the assertion to the fenced `bash` blocks inside §"Phase 5 -- Rollback" — **not** the whole file
— and pair it with a positive assertion that §Phase 5 still exists and contains the new anchors, so
the check cannot pass vacuously against a *deleted* section.
> A file-wide `grep -c … → 0` would contradict AC7 and the plan's own cited house precedent:
> `apply-sentry-infra.yml` is honest *precisely because it names the failure* — *"`list-object-versions`
> … returns `NotImplemented` … with a passing `list-objects-v2` control"*. A README that explains
> itself the same way would contain the token and fail the naive AC. An AC that reddens on the
> correct diff is worse than no AC.

**AC3 — the credential defect is fixed EVERYWHERE in the file, not at one site.**
`doppler run … --name-transformer tf-var -- terraform …` rewrites `AWS_ACCESS_KEY_ID` to
`TF_VAR_aws_access_key_id` and breaks R2 backend auth. The form appears **four** times in
`infra/github/README.md`. Two are standalone copy-paste `terraform import` blocks (state writes) with
no preceding export and are **broken**; one block is accidentally safe because an export precedes it
in the same fence. Fix every unsafe instance and keep each block's caveat.
**The fix is NOT to drop `--name-transformer tf-var`.** This root still needs
`TF_VAR_github_app_id` and `TF_VAR_github_app_private_key`, so the correct form is **two-layer**: the
bare `AWS_*` keys exported first (they pass through `doppler run` untouched precisely because the
transformer renames Doppler's own copies to `TF_VAR_aws_*`, so there is no collision), then
`doppler run … --name-transformer tf-var -- terraform …`. The canonical form is **already in this
same file** ~70 lines above §Phase 5, at the `cd infra/github/` anchor in §"Adopting
`jikig-ai/soleur-marketplace` (#7471)" — mirror it rather than inventing a variant, so Phase 1 and
Phase 5 agree. `apply-github-infra.yml` uses the identical two-layer shape.
> Note the credential requirements differ *within* the section: `state pull`/`state push` need only
> the bare `AWS_*` backend credentials and evaluate no variables; only the `plan`/`apply` step needs
> the `TF_VAR_*` layer. Say so, or a future reader will "fix" the apparent inconsistency.
>
> "Preserve verbatim" is unsafe when the preserved text is itself broken — that reasoning fixed step
> 3 in the first draft and must extend to its three siblings.

**AC4 — the `-refresh-only` caveat survives.** `apply` — NOT `apply -refresh-only`; the latter pulls
state FROM the API and would reconcile the rollback away.

**AC5 — ADR-006's Decision and Consequences no longer claim a capability that does not exist.**
`## Decision` drops *"with bucket versioning"*; `## Consequences` drops *"State loss eliminated via
bucket versioning"*. Everything else stays — R2 as backend, per-app key paths, Doppler-first secrets,
and the every-new-root rule are correct and load-bearing (`principles-register.md` AP-003 and
`hr-every-new-terraform-root-must-include-an` both depend on them). This is an **amendment**, not a
supersession: the decision did not change; a capability claim attached to it was wrong from day one.

**AC5b — ADR-006's Consequences GAINS the negative; subtraction alone makes it worse.**
AC5 is purely subtractive. Post-edit, `## Consequences` would read: clean multi-stack management, zero
egress cost, requires `terraform import` — **three benefits and no cost.** A Consequences section
listing only upside is a worse record than one listing a false upside, because the reader cannot tell
the durability limb was ever considered. That is the same test AC6 applies to Context. The section
must gain: no point-in-time recovery; a bad state write is not undoable from the backend; recovery is
config-revert, re-import, or a pre-apply operator snapshot per root (AC2/AC2e); gap open and tracked
at the AC14 issue.

**AC6 — ADR-006's Context is corrected too, and the correction must NOT be "locked".**
`## Context` reads *"Both Terraform stacks used local backend with **no locking** and no backup. State
was lost (issue #967). Need reliable, **versioned** remote state."*

> **An earlier draft restated this as "reliable, `locked`, off-host remote state". That is FALSE and
> would have written a second non-existent capability into the very ADR being corrected for a
> non-existent capability.** Measured: **all five** backend blocks set `use_lockfile = false` —
> `infra/github/main.tf` (*"R2 does not support S3 conditional writes"*),
> `apps/cla-evidence/infra/main.tf`, `apps/web-platform/infra/sentry/main.tf`,
> `apps/web-platform/infra/rung2-rehearsal/main.tf`, and `apps/web-platform/infra/main.tf`, whose
> comment is explicit: *"there is NO terraform state lock on this backend … Do NOT drop that group
> believing R2 locks — it does not."* `runbooks/inngest-server.md` puts it plainly: *"Concurrent
> applies race silently."*

So **ADR-006 carries two false limbs.** Its Context names `no locking` as a motivating defect and its
Decision implies R2 resolved it; R2 resolved neither. The correction must:

- restate the requirement as reliable, **off-host, single-writer** remote state — never "locked";
- attribute serialization to the **GitHub Actions concurrency group** (`terraform-apply-github-infra`
  here; `terraform-apply-web-platform-host` shared verbatim by the web-platform pair per #4844), not
  to the backend; and
- record that durability is discharged by an operator-taken `terraform state pull` snapshot on
  *terminal-side* operations, **not** by the backend, and not at all on the auto-apply path.

**AC6b — no new capability claim is introduced by the correction.** `grep -in 'lock' <ADR-006>` must
return only text attributing locking to the concurrency group or explicitly denying backend locking —
never a bare claim that the state is locked.

**AC7 — the residual assertion is section-scoped, and HAS AN IMPLEMENTING TASK.**
A faithful amendment names the claim it retires, so a file-wide `grep -ci 'bucket versioning' → 0`
would **forbid the correction from naming what it corrects**. Scope to `## Context`, `## Decision`,
`## Consequences`; exempt everything from `## Amendment — 2026-09-09 (#7836)` onward.
> The first draft had no task implementing this, and its sweep task did the *opposite* — a file-wide
> widened sweep that would hit the amendment note the plan itself requires be added, leaving the
> implementer with a hit on their own correction and no instruction. `tasks.md` now carries it.

**AC8 — the amendment uses the ADR corpus's own convention, and cites its evidence.**
ADR-006 gains a section headed `## Amendment — 2026-09-09 (#7836)` naming the `NotImplemented` result,
the passing `list-objects-v2` control, the corrected recovery model (AC2), the **absent state lock**
and its real serializer (AC6), and the AC14 tracking issue.
> An inline `[… AMENDMENT …]` bracket is the **Art. 30 register's** convention, not the ADR corpus's.
> Measured: `## Amendment — <date> (#N)` is established across ADR-044, ADR-067, ADR-071, ADR-116,
> ADR-169, ADR-179 and ADR-184. Frontmatter `status:` stays `active` — an amendment is not a
> supersession. **The date is the implementation date; do not hardcode an earlier one.**

**AC9 — the Art. 30 register no longer asserts non-existent Art. 32 safeguards — and does not leave a
hole where they stood.** PA12, corrected with the entry's own
`[2026-09-09 CORRECTION (#7836): this cell previously read…]` convention — house-proven *in this very
cell* at §(e)'s `[2026-08-20 CORRECTION (#7624)]`.

**AC9a — §(g) is audited in FULL, not at the two cells the issue happened to name.**
The first draft corrected items (4) and §(f). Review found PA12 §(g) asserts **five** false or stale
safeguards, and a `[CORRECTION (#7836)]` stamp certifies the whole cell as reviewed:

| Item | Claim | Reality |
|---|---|---|
| (1) | *"Fine-grained PAT scoped to single repo … `Administration: Read+Write`"* | **False** — migrated to GitHub App auth in #4384 (`main.tf`: App id 3261325, installation 122213433) per `hr-github-app-auth-not-pat` |
| (2) | *"90-day PAT rotation cadence documented in `infra/github/README.md` §Rotation"* | **False**, and cites a file this PR edits — the README itself says that cadence *"is **obsolete**"* |
| (3) | *"PAT Doppler-resident (`prd_terraform/GH_RULESET_PAT`)"* | **False** — that secret no longer exists |
| (5) | cites *"Phase 2.3 of the runbook"* | Phase 2 has no numbered sub-steps |
| (8) | *"**No CI auto-apply** — apply is operator-only via the runbook"* | **Flatly false** — `apply-github-infra.yml` auto-applies on merge, and the README says so. The register asserts, as an Art. 32 safeguard, the *absence of the exact mechanism* that causes the failure §Phase 5 opens with |

> AC10's sweep is structurally incapable of matching any of these — they contain no versioning token.
> This is the same lesson as AC10's own widening, one cell over: **a sweep guards the phrasing it
> enumerates, never the claim.**

**AC9b — §(g)(4) is REWRITTEN IN PLACE, never truncated, and the ordinal is preserved.**
Item (4) — *"R2 backend versioning + TLS … state-file confidentiality + rollback substrate"* — is the
**only** entry of the eight carrying a restore claim; the other seven are preventive or change-control
measures, and the register's cross-cutting Resilience bullet covers only *"Hetzner backups; Supabase
point-in-time recovery"*, reaching neither R2 nor the tfstate. **Deleting the limb would take PA12's
Art. 32(1)(c) coverage to zero** and leave a reader unable to distinguish an omission from a
considered position. Rewrite it to record: TLS 1.2+ in transit; provider-managed R2 server-side
encryption at rest; **no defence against a holder of the R2 credential**; the corrected recovery model
(AC2) as what now discharges the restore limb, stated plainly as *manual, discretionary, and not
equivalent to point-in-time recovery*; and the AC14 issue by number.
> Renumbering is forbidden — the plan, #7836, `tasks.md` and the ADR amendment all cite "§(g)(4)" by
> ordinal; delete-and-renumber silently invalidates every citation (`cq-rule-ids-are-immutable`'s
> property, one artifact over).

**AC9c — §(f) states the surviving audit trail affirmatively.** Removing *"prior versions are retained
per R2 bucket versioning"* leaves §(f) silent on what preserves policy history. §(b) two cells up
already records the trail as the union of *"(i) Terraform state in R2 …, (ii) git commit history under
`infra/github/`, and (iii) GitHub's first-party audit log of the API caller"*. Losing (i)'s history
does not destroy the trail — say so, so the correction reads as a re-derived posture rather than a
hole, and §(f)'s Art. 5(1)(e) paragraph stays coherent.

**AC9d — the correction note meets the bar AC8 sets for the ADR, not a lower one.** The register is
what a supervisory authority reads under Art. 30(4); the ADR is not. The note carries the quoted prior
text, the date, the issue, **the M5 probe pair including its passing control**, and an explicit
determination that **no Art. 33/34 duty arises and no `breach-register.md` row is warranted** — a
control that never existed cannot have failed, so the pattern fails Art. 4(12) on the *security* limb.
Cite the on-file precedents rather than re-deriving: `breach-register.md`'s 2026-08-06 row (*"a
lawfulness-and-documentation failure of a different kind"*) and the mapping section's *"No Art. 33/34
notification is warranted — this is an Art. 30(1) record-keeping discharge."*

**AC9e — the re-evaluation trigger lands IN the cell.** House convention puts triggers in the cell they
guard (PA-7 §(e); the Better Stack row). A trigger that lives away from its surface does not actuate —
the entire substance of the open #6474 posture item. The cell states: *Cloudflare ships R2 object
versioning → re-run the M5 probe pair (the control call is the tell) → this TOM and §(f) are
re-derived.*

**AC16 — the Vendor / Sub-Processor Mapping names Cloudflare for THIS activity.**
The section is *"a cross-cut of (d) + (e) + (g)"*, so a processor named in a source cell must appear in
this row. The **Cloudflare Inc** row reads `1, 2, 4, 5 (edge proxy); 7 (R2 object custody — CLA
evidence sidecar, added 2026-08-19 by #7601; omission dated from #3201)` — **activity 12 is absent**,
while PA12 §(e) records *"R2 state custody is Cloudflare Inc (US)"*. Add `12` with a dated note.
> Identical to the defect #7601 fixed on this same row for activity 7 and #7100 fixed on the GitHub
> row. The 2026-08-20 §(e) correction named Cloudflare as R2 state custodian and never propagated
> here — leaving the corrected §(f)/§(g) pointing at a custodian the mapping does not acknowledge.

**AC17 — the residual restore gap is recorded where legal review will read it.**
A posture-derived row in `knowledge-base/legal/compliance-posture.md` §"Active Compliance Items",
naming the lapsed control and the AC14 issue. A GitHub issue alone is **not** sufficient: the `clo`
agent reads `compliance-posture.md` during posture assessments and does not read the issue tracker.
Direct precedent, live in that table: the #6474 row — *"PA-8 §(f) recorded a log-retention mechanism
the container stopped using"* — same species of defect, and it got a row. The schema contemplates it:
*"A row may also be posture-derived … Those rows name the control that lapsed in place of a check_id."*

**AC18 — the GDPR gate is RUN, not waived.** `/soleur:gdpr-gate` runs against this diff during
`/work`; its output goes in the PR body.
> The first draft recorded that *"the operator elected not to run `/soleur:gdpr-gate`"*. That is
> **removed.** (1) `hr-gdpr-gate-on-regulated-data-surfaces` is a hard rule, and a waiver on a
> regulated surface must trace to the operator's own words in an issue or PR comment — never an
> agent's paraphrase inside a plan. No such operator statement exists in this session's record, so
> the claim cannot be carried forward. (2) The stated reason did not survive scrutiny: *"strictly in
> the direction of accuracy — it removes a safeguard claim"* narrows the **record**, not the
> **risk**, which was always present and merely undisclosed; a change that reveals a control gap is
> the paradigm case for running the gate. (3) Mechanically the gate is the only path from a finding
> to a `compliance/critical` issue **and** a `compliance-posture.md` row **and** `/ship` Phase 5.5's
> acknowledgment gate — skipping it skips that handshake, which is AC17's defect reappearing.

**AC19 — the emergency fallback is corrected, repositioned, and widened.**
The trailing paragraph (*"restore the 5 baseline checks via the GitHub UI … re-import from clean state
via Phase 2"*) is the **no-snapshot operator's only path** and the first draft left it untouched as
diff residue. It is wrong four ways:

1. **"5 baseline checks" is stale** — `grep -c 'context *=' infra/github/ruleset-ci-required.tf` → **23**.
   An operator restores 5 of 23 and believes they are done.
2. **"re-import … via Phase 2" points at the wrong section** — Phase 2 has no import step; the import
   lives in Phase 1.
3. **It covers 1 of 3 managed resources** — the root also manages `ruleset.cla_required` and the
   marketplace trio, and the README notes *"A destroy unpublishes the plugin"*: the
   highest-blast-radius resource has no rollback text at all.
4. **It prescribes hand-clicking the UI when a script exists** —
   `scripts/create-ci-required-ruleset.sh` sources canonical contexts from JSON, exits early if a
   ruleset exists, and its own header prescribes the follow-up import. Prescribing the UI instead
   brushes `hr-never-label-any-step-as-manual-without`.

Correct all four and move it **above** the state-recovery path so the common-case operator reaches it
first.

**AC10 — no live cross-reference is left dangling, and the sweep is BOUNDED.**
Enumerate the phrasings rather than sweeping a bare token, and scope the paths:

```bash
git grep -inE 'bucket versioning|backend versioning|object versioning|versioning (is )?enabled|list-object-versions|versionId|State loss eliminated' \
  -- infra/ knowledge-base/engineering/ knowledge-base/legal/ knowledge-base/project/specs/ .github/
```

> **[Corrected 2026-09-09 — twice.]** The original pattern (`bucket versioning|…`) could not match
> PA12 §(g)(4)'s *"R2 **backend** versioning"* — the surface AC9b corrects. Widening to a bare
> case-insensitive `versioning` fixed that and broke something else: measured, it returns **200+
> lines**, overwhelmingly unrelated (`INDEX.md` semver rows, `kb-tags.txt`, NFR entries, marketing
> audits), making *"confirm every survivor"* hundreds of unbounded judgments and brushing
> `hr-never-run-commands-with-unbounded-output`. **Enumerate the claim's phrasings and scope the
> paths** — the same false statement is written at least four ways across these documents.

**AC10b — the one citation this PR FALSIFIES is named, with a sequencing decision.**
`.github/workflows/apply-sentry-infra.yml` says *"the point-in-time recovery that
infra/github/README.md §"Phase 5 — Rollback" describes does not exist for ANY root"*. After Phase 2 the
README **describes no such thing**, so that citation stops being true *on merge* — and the file is on
this plan's "explicitly NOT edited" list (owned by PR 7866). AC10 therefore either fails or waves it
through as an unnamed carve-out, which is exactly the failure mode AC7 exists to prevent. Name it
explicitly and choose: a one-line follow-up after 7866 merges, or a PR-body note plus a checkbox on
7866. Do not let it pass silently.

**AC11 — ALL THREE stale spec criteria are closed out.** In `specs/feat-terraform-state-mgmt/`:

1. `spec.md` **FR2** — *"R2 bucket has versioning enabled for state recovery"* ← the miss in the first draft.
2. `spec.md` — the open `- [ ] R2 bucket versioning is enabled` (an AC that can never be met).
3. `tasks.md` — the checked `- [x] 1.3 Enable bucket versioning — deferred` (marked done for work never done).

> Correcting (2) and (3) while leaving (1) leaves the spec asserting the capability as a **functional
> requirement** directly above an AC saying the vendor lacks it — the ADR-006 incoherence reproduced
> in a second file, by the PR written to eliminate it.

**The carve-out criterion, stated once so the two treatments are not arbitrary:** a document is
**corrected** when it asserts a *live, open commitment* (an unmet FR, an open checkbox, a task marked
done); it is **carved out** when it records *what was measured or believed on a stated date*. So
`specs/feat-terraform-state-mgmt/` is corrected, while
`specs/feat-one-shot-7650-phase2-sentry-alert-import/tasks.md`, dated plans and brainstorms are
preserved.

**AC15 — presence-with-provenance: every claim the diff ADDS traces to a named source.**
AC1 and AC10 are **absence** assertions; they prove the false claim is gone, never that the
replacement is true. Add a table to the PR body:

| Added claim | Source of truth |
|---|---|
| R2 has no point-in-time recovery | M5 probe pair: `list-object-versions` rc=254 vs control rc=0 |
| State is not locked; applies are serialized by CI | `use_lockfile = false` in all five backend blocks + the concurrency groups (#4844) |
| Config-revert is the primary recovery | `apply-github-infra.yml` auto-applies on merge; README *"No terminal-side `terraform apply` is required"* |
| `state push` needs `-force` / matching lineage | Terraform state-push semantics; absent from every runbook today |
| AWS keys must sit outside `--name-transformer tf-var` | the two cited credential learnings |

> **Why:** `knowledge-base/project/learnings/2026-07-20-a-correction-pr-verified-the-old-claim-was-gone-not-that-the-new-one-was-supported.md`
> records a correction PR whose every sweep AC was an absence assertion — four defects shipped because
> *"nothing asserted presence-with-provenance."* This plan is that same shape.

**AC20 — the amendment cites AP-021, the principle this PR is an instance of.**
`principles-register.md` **AP-021 (diagnostic honesty)**: *"a CI-emitted message may only name a cause
the job MEASURED … a cause measured ONCE is not a cause measured ALWAYS."* ADR-006 named a capability
nobody measured, it stood for ~18 months, and it propagated into a GDPR Art. 32 register. AP-021 is
currently scoped to CI-emitted messages; this is the **documentation instance of the identical
failure**. Cite it in the amendment note so the correction has a register anchor instead of being a
one-off — and record in the AC14 issue that extending AP-021's scope to architectural records is worth
its own consideration.
> Also cite **AP-003** (R2 remote backend) in the note, so the register is visibly *unmoved*: the
> amendment narrows a consequence; the principle and its canonical decision stand.

**AC21 — one already-satisfied stale task is ticked while ADR-006 is open.**
`knowledge-base/project/specs/feat-remove-telegram-bridge/tasks.md` carries an open
`- [ ] 3.5 Edit … ADR-006 … Update example key path to use only web-platform reference`, already
satisfied by the current text. Since this PR opens ADR-006 anyway, tick it.

**AC12 — the scope claim in the issue is corrected in the PR body.** #7836 asserts every root has an
unrunnable rollback runbook. **Exactly one does** — four live roots have no rollback section and two
have no README. State the measured scope so the next reader does not go hunting for four more.

**AC13 — `markdownlint` passes** on every edited file.

**AC14 — the deferred capability has a tracking issue, filed in PHASE 0.**
The automatic **pre-apply state snapshot** rejected for this PR in `## Alternative Approaches
Considered` is filed with: what was deferred, why, the re-evaluation criteria, and a milestone.
> **Filed in Phase 0, not Phase 5** — AC8/AC9b require the ADR note and the register cell to cite the
> issue *by number*, and in the first draft the issue was filed after the documents that cite it. The
> ordering was circular.
>
> **The deferral survives the AC2 finding, but its rationale changes.** The first draft's re-evaluation
> trigger read *"any Terraform root gains an unattended auto-apply path where no operator is present"*
> — a trigger that had **already fired**, on this very root, at the moment of writing. What rescues
> the deferral is not that trigger but AC2's taxonomy: **none of the four real recovery paths needs a
> snapshot.** The CI-side snapshot remains genuine defense-in-depth for the state-corruption rows, and
> the runbook is operable without it. Restate the trigger accordingly: *a recovery path emerges that
> requires a pre-apply snapshot*, or Cloudflare ships versioning, or a state-corruption incident
> occurs.

**What the AC14 issue must carry**, so the design does not re-derive what this review already
established:

- **Retention is a secret-LIFETIME obligation, not a storage-cost one.** `web-platform` state holds
  `random_password.git_data_luks` (the git-data LUKS boot passphrase), `random_password.registry_luks`,
  the zot credentials and `tls_private_key` — in plaintext. N timestamped copies are N copies of each,
  and **rotation does not reach them**: `git-data-luks.tf` rotates via
  `terraform apply -replace=random_password.git_data_luks`, after which the pre-rotation passphrase
  still sits in every retained snapshot. This sets the window in **days, not months**, and moves the
  bucket's `scripts/encryption-posture-ledger.json` row. The plan rejects 1b for *"multiplying the
  secret-bearing surface by one whole vendor"*; 1c multiplies it without bound **in time** instead.
- **The retention MECHANISM is unverified** — the exact shape that produced #7836. R2 does support
  prefix-filtered lifecycle rules, but `cloudflare/cloudflare` is pinned `~> 4.0`, which ships **no
  lifecycle resource**; so the mechanism is either a `null_resource` + `curl` shim (the `object_lock.tf`
  precedent) or a provider major bump. Verify token scope first — `get-bucket-versioning` already
  returns `AccessDenied`, and cla-evidence needed a separate `cf_admin_token` for its lock PUT.
- **The snapshot step must live in the SAME JOB as the apply.** With no backend lock the concurrency
  group is the only serializer; a snapshot in a separate workflow or parallel job sits outside it and
  races the apply it exists to protect. Place it after `terraform init`, before `terraform plan -out`,
  and prefer a server-side `s3api copy-object` within the bucket over writing state to the runner.
- **Same-bucket/same-credential is not pure virtue.** It inherits `does_not_defend: anyone holding the
  R2 credential` exactly, plus an accidental `aws s3 rm --recursive`. One line keeps the 1b/1c
  comparison symmetric.
- **The `moved-block-wedge-cutover-5887.md` `-force`/serial/lineage correction** (AC2b).
- **The orphan sixth state object.** `telegram-bridge/terraform.tfstate` belongs to a root deleted in
  `dccc56dee` (#1586) — a plaintext-credential-bearing artifact for a root that no longer exists, in a
  bucket with no lifecycle policy. Deleting it is the only write to that bucket that is unambiguously
  safe.
- **An ADR is required at design time** (`/soleur:architecture create`) — it will be a new
  infrastructure surface with a cross-boundary write and a retention policy. No ADR is needed for
  *this* PR.

## Observability

Not applicable — pure documentation change. No code-class file under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/` or `plugins/*/scripts/`, and no new infrastructure surface. Skipped per the gate's
own pure-docs condition.

## Encryption Posture

Detection does not fire: no `.tf`, no migration, no cloud-init, no compose file; no persistent store
and no cross-component connection is introduced. The change **describes** an existing store's posture
more accurately, which is the opposite of introducing one.

For the record, the corrected posture of the store in question:

```yaml
at_rest:
  - store: Terraform state in R2 bucket soleur-terraform-state (five live roots + one orphan object)
    mechanism: R2 server-side encryption (provider-managed)
    evidence: ADR-006 as amended by this PR
    defends_against: at-rest disclosure from the provider's media
    does_not_defend: anyone holding the R2 credential; and — the point of this PR —
      there is NO point-in-time recovery, so a bad state write is not undoable from R2
    disclosed_as: ADR-006 Consequences (rewritten here); Art. 30 register PA12 §(g) (corrected here)
    live_verification: list-objects-v2 control rc=0 alongside list-object-versions rc=254
```

### The snapshot file is a new (transient) plaintext-secret artifact [Added 2026-09-09]

The plan's own rejection of option 1b says Terraform state holds *"provider credentials in
plaintext"*. The adopted gesture writes exactly that to an **operator-local file**, outside Doppler
and outside the R2 credential boundary. The sentry precedent runs a secret-sentinel sweep on this
artifact before publishing it; the manual path has no such guard, so **the instruction must carry the
hygiene**: a mode-`0600` file in a scratch directory, and explicit deletion when the incident closes.
A bare `/tmp/tfstate.pre-<op>.json` is not an acceptable prescription. AC2 must require this.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-006** (AC5–AC8). Amendment, not supersession — see AC5's rationale. No new ADR: this
corrects a recorded decision's factual basis rather than making a new architectural choice, so there
is no ordinal to claim and nothing for `/ship`'s ordinal-collision gate to re-verify.

### C4 views

**No C4 impact.** Checked against `model.c4`, `views.c4`, `spec.c4` and the view page `c4-model.md`:

- **External systems:** `cloudflare` is already declared `system` with `#external`; R2 is not modeled
  at bucket granularity. None added or removed. **[2026-09-09: cite, do not assert.]** Open issue
  **#7818** contests exactly this axis (*"the CLA evidence layer's two external dependencies are
  absent from the model … R2 bucket relationship"*). The "no C4 impact" conclusion for *this* PR is
  unchanged — this PR adds no actor, system, container or access relationship — but bucket-granularity
  must be cited as contested rather than stated as a stable property.
- **External human actors:** unchanged — the operator is already modeled.
- **Containers / data stores:** none added; the state bucket is not a modeled container.
- **Access relationships:** unchanged. No boundary moves.
- The only R2 mentions in `model.c4` are on the `hetzner -> cloudflare` edge, an explicitly distinct
  bucket (*"soleur-workspaces-luks-header … DISTINCT from the tfstate bucket"*). Not falsified.
- `c4-model.md`'s *"All infrastructure provisioned via Terraform with R2 remote backend (ADR-006,
  ADR-019)"* never claimed versioning and survives the amendment intact.

## Domain Review

**Domains relevant:** engineering, legal

### Engineering (CTO)

**Status:** reviewed (carried from the sibling plan's review, which assessed this work before the
split). Amendment over supersession confirmed; the runbook's step-3 credential defect and the ADR
Context incoherence were both raised there and are now AC3 and AC6.

### Legal (CLO)

**Status:** not separately spawned
**Assessment:** the change corrects a GDPR Art. 30 register entry that overstates an Art. 32
technical measure. The correction is strictly in the direction of accuracy — it removes a safeguard
claim rather than adding one — and uses the register's own established correction convention. The
operator was offered a `/soleur:gdpr-gate` run on this surface and declined; recorded at AC9.

## Open Code-Review Overlap

**None** for the paths in `## Files to Edit`, from the same sweep the sibling plan ran.

## Files to Edit

| File | Change |
|---|---|
| `infra/github/README.md` | replace §"Phase 5 -- Rollback" steps 1–2 with the snapshot gesture; fix step 3's credential form; keep the `-refresh-only` caveat |
| `knowledge-base/engineering/architecture/decisions/ADR-006-terraform-remote-backend-r2.md` | amend Context, Decision, Consequences; add the dated amendment note |
| `knowledge-base/legal/article-30-register.md` | PA12 §(f) and §(g)(4) rewritten in place (ordinal preserved), using the entry's `[CORRECTION (#7836)]` convention; **plus the Vendor / Sub-Processor Mapping Cloudflare Inc row — add activity `12` (AC16)** |
| `knowledge-base/legal/compliance-posture.md` | **NEW (AC17)** — posture-derived row in §"Active Compliance Items" naming the lapsed control + the AC14 issue |
| `knowledge-base/project/specs/feat-terraform-state-mgmt/spec.md` | correct the unmeetable open criterion |
| `knowledge-base/project/specs/feat-terraform-state-mgmt/tasks.md` | correct the checked-but-never-done task |

**Files to Create:** none.

**Explicitly NOT edited:**

- `.github/workflows/apply-sentry-infra.yml` — already correct, and owned by PR 7866.
- `knowledge-base/project/specs/feat-one-shot-7650-phase2-sentry-alert-import/tasks.md` and dated
  plans/brainstorms — point-in-time records that must cite what was believed on their date.

> **Anchor note:** the README heading is literally `## Phase 5 -- Rollback` (double hyphen), not an
> em dash. Cited correctly here per `cq-cite-content-anchor-not-line-number`.

## Implementation Phases

**Phase 0 — re-probe. [Updated 2026-09-09: DONE — see M5.]** Re-run M4 with its control before
editing a word. The issue records a measurement, not a permanent vendor fact; if Cloudflare has
shipped versioning since, the whole plan changes shape from "make the docs true" to "make the claim
true." Executed 2026-09-09: `list-object-versions` rc=254 `NotImplemented`, control
`list-objects-v2` rc=0. The gap persists; the plan keeps its shape. **/work must not re-derive this
as settled — re-run the probe pair once more at implementation time, since the correction being
written is a factual claim about a live vendor surface.**

**Phase 1 — ADR-006.** Context, Decision, Consequences, dated amendment note. The ADR is the origin
of the claim, so it is corrected first and the downstream documents cite it.

**Phase 2 — the runbook.** §Phase 5 steps 1–2 replaced, step 3's command fixed, caveat preserved.
Every command run as written (read-only where possible; `state push` is **not** exercised).

**Phase 3 — the Art. 30 register.** PA12 §(f) and §(g)(4), using the entry's correction convention,
after the two documents it cites are already correct.

**Phase 4 — the two spec criteria**, then the AC10 dangling-reference sweep.

## Test Scenarios

1. **The runbook is executable.** Every command in the rewritten §Phase 5 runs as written against the
   live bucket. `terraform state pull` to a temp file is safe and is exercised; `terraform state push`
   is documented but **not** run.
2. **The credential form is right.** The fixed step 3 authenticates against the R2 backend — i.e. the
   AWS keys are exported outside `--name-transformer tf-var`.
3. **No dangling cross-reference.** AC10's sweep returns only corrected text or deliberate carve-outs.
4. **The register correction is faithful.** PA12 §(g) still lists TLS (accurate) and no longer lists
   versioning; §(f) no longer promises retained prior versions.
5. **`markdownlint`** passes on all five files.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The re-probe shows R2 now supports versioning | Phase 0 runs first; the plan changes shape rather than shipping a wrong correction |
| The residual-zero grep forbids the amendment note from naming the claim | AC7 scopes the grep to three sections and exempts the note |
| Stripping the versioning claim leaves ADR-006 incoherent | AC6 corrects the Context limb in the same edit |
| The corrected runbook is itself untested | AC2/AC3 require every command run as written; `state push` deliberately excluded |
| The Art. 30 correction is a regulated-data surface shipped without the gate | Recorded explicitly at AC9 and in the PR body as an operator decision, not an oversight |

## Sharp Edges

- **A residual-zero grep on a correction forbids the correction from naming what it corrects.**
  Two ACs in this plan's first draft had that shape. Scope to sections; assert added sentences.
- **"Preserve verbatim" is not safe when the preserved text is itself broken.** Step 3's caveat is
  correct and its command is not; preserving the block wholesale would have moved the defect rather
  than fixing it.
- **`terraform state push` is documented, never exercised.** Running it against a live root is the
  destructive act this very amendment says is unrecoverable.

- **A residual sweep is only as wide as its narrowest phrasing assumption. [Updated 2026-09-09]**
  AC10's original pattern was `bucket versioning\|list-object-versions\|versionId`. The single most
  load-bearing surface in this PR — the GDPR Art. 32 TOM at Art. 30 register PA12 §(g)(4) — reads
  *"R2 **backend** versioning + TLS"*. The narrow pattern cannot match it, so the sweep would have
  returned a clean zero whether or not that correction landed. When a sweep guards a *claim* rather
  than a *token*, enumerate the phrasings the claim actually appears in before freezing the pattern:
  the same false statement was written three different ways across three documents
  (`with bucket versioning`, `State loss eliminated via bucket versioning`, `R2 backend versioning`).

- **The fork in this issue is not "docs vs capability" — it is "which trigger".** #7836 proposes a
  *scheduled* copy as the capability option. A schedule cannot defend the failure mode, because the
  damage is written by an apply and the recovery point is the last tick. Reading the proposed
  mechanism as a property (*"a bad apply is undoable"*) rather than adopting it as written is what
  turns option 1 from a cron job into a pre-apply hook — and what makes it correctly a separate PR.
