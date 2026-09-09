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

1. **It cannot be validated without the act this PR declares unrecoverable.** Proving a restore path
   works means writing state back to a live root. Today that is the one-way door the whole issue is
   about. The honest runbook is the *precondition* for building the snapshot safely, not a companion
   to it.
2. **Holding the correction behind it keeps the impossible command in the runbook** for the entire
   duration of the infra work — during which the runbook may actually be read.
3. **The two changes share no file and no failure mode.** This PR edits five markdown documents. That
   one edits workflows and adds a retention policy.

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
*Scope-out note:* `threshold: none, reason: the change edits four markdown documents and no
executable surface; the only behavioural effect is that an operator reads accurate instructions.*

## Acceptance Criteria

**AC1 — the runbook contains no impossible command.**
`grep -c 'list-object-versions\|versionId' infra/github/README.md` → `0`.

**AC2 — the replacement gesture is the one that works, and is stated as a snapshot not a recovery.**
§"Phase 5 -- Rollback" steps 1–2 are replaced by `terraform state pull` to an off-host file taken
**before** the risky apply, and `terraform state push` to restore. The text states plainly that R2
provides **no** point-in-time recovery, so taking the snapshot is the operator's responsibility ahead
of time. Assert the sentences the diff **adds**, not only the removals.

**AC3 — step 3's command is fixed, not preserved verbatim.**
The surviving step must not carry `doppler run … --name-transformer tf-var -- terraform plan/apply`.
Two learnings record that exact form failing — *"No valid credential sources found"* for the S3/R2
backend, and *"`--name-transformer tf-var` broke backend auth"* — because it rewrites
`AWS_ACCESS_KEY_ID` to `TF_VAR_aws_access_key_id`. The AWS keys must be exported **outside** the
transformer.
> The first draft said "preserve step 3 verbatim" for the sake of its caveat. That would have added
> prose saying the keys must be outside the transformer while preserving a command that puts them
> inside — leaving the runbook self-contradictory and still inoperable, now at step 3 instead of
> step 1. **Preserve the caveat, fix the command.**

**AC4 — the `-refresh-only` caveat survives.** The runbook still warns: `apply` — NOT
`apply -refresh-only`; the latter pulls state FROM the API and would reconcile the rollback away.

**AC5 — ADR-006's Decision and Consequences no longer claim a capability that does not exist.**
`## Decision` drops *"with bucket versioning"*; `## Consequences` drops *"State loss eliminated via
bucket versioning"*. Everything else in the decision stays — R2 as backend, per-app key paths,
Doppler-first secrets, and the every-new-root rule are all correct and load-bearing (two live
citations depend on them: `principles-register.md` AP-003 and the hard rule
`hr-every-new-terraform-root-must-include-an`). This is an **amendment**, not a supersession: the
decision did not change, a capability claim attached to it was wrong from day one.

**AC6 — ADR-006's Context is corrected too, or the ADR is left incoherent.**
`## Context` currently ends *"Need reliable, versioned remote state."* Strip the versioning limb from
Decision and Consequences alone and the ADR reads: a requirement for versioned state, a decision that
does not provide it, and no acknowledgment of the gap — a worse record than the original error, which
at least was self-consistent. Restate the requirement as reliable, **locked**, off-host remote state,
and have the amendment note record that the durability limb is discharged by an operator-taken
`terraform state pull` snapshot, not by the backend.

**AC7 — the residual-zero grep is section-scoped, not file-wide.**
A faithful amendment note in house style names the claim it retires (*"this ADR previously claimed
bucket versioning…"*), so a file-wide `grep -ci 'bucket versioning' → 0` would **forbid the
correction from naming what it corrects**. Scope the assertion to the `## Context`, `## Decision` and
`## Consequences` sections and exempt the dated amendment note.
> This is the same defect as the count-based AC in the sibling Sentry plan, and the same one the
> repo's own learning warns about: *"a residual-zero count AC certifies the wrong property."*

**AC8 — the amendment note is dated and cites its evidence.** ADR-006 gains a
`[2026-09-06 AMENDMENT (#7836): …]` note naming the `NotImplemented` result, the passing
`list-objects-v2` control, and the replacement gesture.

**AC9 — the Art. 30 register no longer asserts a non-existent Art. 32 safeguard.**
`knowledge-base/legal/article-30-register.md` PA12 §(f) and §(g)(4) are corrected using the entry's
existing `[YYYY-MM-DD CORRECTION (#7836): this cell previously read…]` convention. §(g)(4) must no
longer list *"R2 backend versioning"* as a technical measure; the TLS half of that item is accurate
and stays. §(f)'s retention claim must no longer say prior versions are retained, and its
cross-reference must point at the corrected Phase 5 gesture.
> This is a regulated-data surface. The operator elected not to run `/soleur:gdpr-gate` separately;
> that choice is recorded here and in the PR body rather than left implicit.

**AC10 — no live cross-reference is left dangling.** After the edit, every document citing
`infra/github/README.md` Phase 5 or ADR-006 for a rollback/versioning claim cites text that still
makes that claim. Verify by re-running the sweep:
`git grep -in 'versioning\|list-object-versions\|versionId' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/brainstorms' ':!**/archive/**' ':!node_modules'`
and confirming every survivor is either corrected or a deliberate carve-out.

> **[Updated 2026-09-09] The pattern was widened from `bucket versioning` to a case-insensitive bare
> `versioning`, because the narrow form could not see the single most important surface in this PR.**
> PA12 §(g)(4) reads *"**R2 backend versioning** + TLS"* — the phrase is `R2 backend versioning`, not
> `bucket versioning`, so the original AC10 sweep returns zero hits on it whether or not AC9 was done
> correctly. A residual sweep that structurally cannot match the surface it is meant to guard is a
> sweep that certifies the wrong property. Verified: `grep -c 'bucket versioning'` against the
> register's PA12 §(g) cell → `0`, while the false claim is plainly present.

**AC11 — the two stale spec criteria are closed out.**
`specs/feat-terraform-state-mgmt/spec.md`'s open `- [ ] R2 bucket versioning is enabled` (an AC that
can never be met) and `tasks.md`'s checked `- [x] 1.3 Enable bucket versioning — deferred` are
corrected to record the measured vendor limitation, not left as an eternally-open criterion and a
task marked done that never happened.

**AC12 — the scope claim in the issue is corrected in the PR body.** #7836 asserts every root has an
unrunnable rollback runbook. Exactly one does. The PR body states the measured scope so the next
reader does not go looking for four more.

**AC13 — `markdownlint` passes** on every edited file.

**AC14 — the deferred capability has a tracking issue, not a promise. [Updated 2026-09-09]**
The pre-apply state-snapshot capability rejected for *this* PR in
`## Alternative Approaches Considered` is filed as its own issue before this PR is marked ready,
carrying: what was deferred, why it is not folded in here, the named re-evaluation criteria, and a
milestone. The ADR-006 amendment note references it, so the record says *"this gap is open and
tracked"* rather than implying the operator snapshot is the permanent end state.
A deferral without a tracking issue is invisible (`wg-when-deferring-a-capability-create-a`).

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

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-006** (AC5–AC8). Amendment, not supersession — see AC5's rationale. No new ADR: this
corrects a recorded decision's factual basis rather than making a new architectural choice, so there
is no ordinal to claim and nothing for `/ship`'s ordinal-collision gate to re-verify.

### C4 views

**No C4 impact.** Checked against `model.c4`, `views.c4`, `spec.c4` and the view page `c4-model.md`:

- **External systems:** `cloudflare` is already declared `system` with `#external`; R2 is not modeled
  at bucket granularity. None added or removed.
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
| `knowledge-base/legal/article-30-register.md` | PA12 §(f) and §(g)(4), using the entry's `[CORRECTION (#7836)]` convention |
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
