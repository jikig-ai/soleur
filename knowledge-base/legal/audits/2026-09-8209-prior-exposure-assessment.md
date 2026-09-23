---
title: "CLO assessment — prior exposure of the four privileged Terraform credentials reachable from Doppler `prd_terraform` (#8209)"
type: clo-attestation
date: 2026-09-23
issue: 8209
attestation-authority: clo
status: SIGNED-OFF PROVISIONAL (CLO-agent-attested, Soleur-as-tenant-zero v1, 2026-09-23)
disposition: "REACHABILITY-ONLY — assessment, NOT a presumed breach. Following the 2026-06-29 REACHABILITY-ONLY precedent (`knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`). No Art. 33 duty and no Art. 34 duty are recorded on the facts established to date. PROVISIONAL: every evidentiary limb is INCONCLUSIVE until shown clean."
disposition_history: "SIGNED-OFF PROVISIONAL 2026-09-23 on five open evidentiary limbs (GitHub run census, Doppler access logs, Hetzner actions, Cloudflare account audit log, exposure-window start). No limb has been run at the date of this record."
signed_off_at: 2026-09-23
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-09-22 — the measurement session recorded in `knowledge-base/project/plans/2026-09-22-feat-evict-privileged-terraform-credentials-plan.md` (§Measurements, M1-M12), which established that `prd_terraform` is a branch config of `prd` and that a repository-level CI secret reads it. No monitor surfaced this; no monitor could, because every read is a legitimate read by a legitimate holder."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 33 duty arose on the facts established to date, so nothing fell due 72h from the awareness anchor. Re-opens with a FRESH 72h from awareness of any evidence of use surfaced by a limb below."
open_limbs: "five, all INCONCLUSIVE and none yet run: (L1) the read-only GitHub non-`main` run census; (L2) Doppler access logs for `prd_terraform` and `prd`; (L3) Hetzner actions (rescue, rebuild, volume attach); (L4) the Cloudflare account audit log; (L5) the start of the exposure window, from the `prd_terraform` secret history. L1 must be gathered BEFORE operator step O13 — see §Evidence gathering order."
tier_classification: "Tier 1 — an internal assessment record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
---

# CLO assessment — #8209 prior exposure of the `prd_terraform` privileged credentials

## Verdict — REACHABILITY-ONLY. An Art. 33 **assessment**, not a presumed breach. PROVISIONAL.

The facts established to date do not establish a personal-data breach under Art. 4(12), and
record no Art. 33 (supervisory authority) or Art. 34 (data-subject) notification duty. The
assessment is **PROVISIONAL**: every evidentiary limb below is **INCONCLUSIVE** and expressly
**not certified clean**. The disposition becomes final only when the limbs are recorded, and
#8209 does not close before that (plan AC17).

This record follows the **REACHABILITY-ONLY precedent** of
`knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`
(the Supabase `soleur-inngest-prd` RLS determination) and the standing rule the
`2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md` record restates: **reachability
alone does not start the Art. 33 clock.** It departs from the 2026-06-29 record in one material
respect, recorded here rather than left to be inferred — that determination rested primarily on an
**absent exploitation precondition** (a key that was never published). No such ground is available
here. The credentials were live, valid and nameable by a workflow throughout. What bounds this
matter instead is the **reachable class** below, which is small, named, and not the public.

## The fact pattern

Doppler config `soleur/prd_terraform` is a **branch config of `prd`** (measured, plan M1), and the
repository-level CI secret `DOPPLER_TOKEN` reads it. Any workflow on any branch of the **public**
repository `jikig-ai/soleur` could therefore name a secret that resolves to that config, which
held four credentials whose reach goes far past Terraform:

| Credential | Reach |
|---|---|
| `DOPPLER_TOKEN_TF` | a workplace **personal** token that reads every Doppler project, including the isolated `soleur-git-data-root` |
| `CF_API_TOKEN_R2` | account-wide Cloudflare R2 |
| `HCLOUD_TOKEN` | read/write Hetzner, which is root on any host through rescue, rebuild or a volume re-attach |
| `GITHUB_APP_PRIVATE_KEY` | a distinct private key of the **same** soleur-ai App (plan M3/M4), which holds 3 installations, 2 of them outside `jikig-ai` (plan M5) |

Two further paths reached the git-data root key: the repository secret
`DOPPLER_TOKEN_GIT_DATA_ROOT`, and the state object
`web-platform/git-data-root-key/terraform.tfstate`, which the `prd_terraform` R2 backend keys read
(plan M7: listing `soleur-terraform-state` with those keys returns all seven state objects).

The personal data ultimately reachable through those credentials is recorded at Art. 30 **PA-36**
(per-workspace bare-repository store of connected-repository content) and **PA-2** (workspace
content on web-1), and, through the App key's two third-party installations, repository content of
connected users. Severity, had access occurred, would be non-trivial. As in the 2026-06-29
precedent, it is the **likelihood** prong that is doing the work here, not the severity prong.

## The reachable class, stated precisely

The reach is **not** "the public", and the record must not be read as saying so. The repository is
public, but naming a repository secret from a workflow requires a run that GitHub will hand secrets
to. That is:

1. **Write collaborators** — every principal with `push` on `jikig-ai/soleur`, because a push to a
   branch of the repository is what causes a workflow run on a non-`main` ref to receive the
   repository secret set; and
2. **GitHub Apps installed on `jikig-ai/soleur` holding `contents:write`**, because such an App can
   create the branch and the workflow file that names the secret.

**Fork pull requests never received secrets.** A `pull_request` event from a fork runs with a
read-only `GITHUB_TOKEN` and **no** repository secrets, which is GitHub's documented default and
is not configurable away at this repository. That is what keeps the class at (1) and (2) rather
than at "any GitHub account". The census in L1 below is scoped accordingly and must record the
fork/non-fork split rather than assume it.

The two enumerations that fix the class are themselves read-only, and are limbs of L1:

```bash
R=jikig-ai/soleur

# (1) write collaborators — LOGINS AND A COUNT, nothing else
gh api "repos/$R/collaborators" --paginate \
  --jq '[.[] | select(.permissions.push == true) | {login, role: .role_name}]'

# (2) Apps installed on the org holding contents:write
gh api /orgs/jikig-ai/installations \
  --jq '.installations[] | select(.permissions.contents == "write") | "\(.app_slug)\t\(.id)\t\(.target_type)"'
```

## Evidence gathering order — L1 precedes operator step O13

**GitHub Actions logs and run records expire at 90 days.** The L1 census must therefore be
gathered and recorded in this file **before** operator step O13 of
`knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`, and before O12.
Rotation does not destroy the evidence, but the 90-day horizon does, and every day the sequence
waits is a day of census window lost at the far end. The runbook's Order constraints carry the
same rule ("The evidence limbs of the prior-exposure assessment precede O12 and O13").

## L1 — the read-only GitHub evidence limb (counts and run ids ONLY)

**Discipline, and it is load-bearing.** Every command below returns run identifiers, refs, event
names, actors, timestamps and counts. **No command in this limb reads a log body, and none may.**
`gh run view --log`, `gh api …/logs` and any download of a run archive are **out of scope for this
record**: a workflow log can contain a masked-but-recoverable value, and a legal record that
gathers one has created a second copy of the exposure it is assessing. If a log body ever becomes
necessary, that is a separate, separately-authorised step and it is not this one.

### L1(a) — the workflow set

The census covers every workflow that references `DOPPLER_TOKEN`, `DOPPLER_TOKEN_PRD`,
`DOPPLER_TOKEN_GIT_DATA_ROOT`, `DOPPLER_TOKEN_WRITE` or any `prd_*` token. The set is derived from
the repository rather than from memory:

```bash
grep -rlE 'secrets\.(DOPPLER_TOKEN(_PRD|_WRITE|_GIT_DATA_ROOT)?)\b|toJSON\(secrets\)' \
  .github/workflows/ | sed 's|.github/workflows/||' | sort > /tmp/8209-workflow-set.txt
wc -l < /tmp/8209-workflow-set.txt
```

`toJSON(secrets)` is in the pattern deliberately: it names every secret at once without naming any
of them, and it is the form a census anchored on literal names would miss (the precedent is
`tests/scripts/test-git-data-root-token-census.sh`, which matches it for the same reason).

### L1(b) — the non-`main` run census

For each workflow file in that set, every run on a ref other than `main`, reported as identifiers
and counts:

```bash
R=jikig-ai/soleur
while read -r wf; do
  gh api "repos/$R/actions/workflows/$wf/runs" --paginate \
    --jq '.workflow_runs[]
          | select(.head_branch != "main")
          | [env.WF // "", (.id|tostring), .head_branch, .event, .created_at,
             (.head_repository.fork|tostring), .actor.login] | @tsv'
done < /tmp/8209-workflow-set.txt | tee /tmp/8209-nonmain-runs.tsv | wc -l
```

Recorded in §Findings as: **total count**, **count per workflow**, **count per actor**, the
**fork / non-fork split**, and the **run ids**. Nothing else from a run record is transcribed.

### L1(c) — runs whose head commit touched `.github/workflows/**`

The sharp subset: a run on a non-`main` ref whose head commit **changed a workflow file** is the
shape that would introduce a new secret reference. The commit API is keyed by SHA, so this
resolves for commits on **deleted branches** too, which is why it is asked by SHA and not by ref:

```bash
cut -f2,3 /tmp/8209-nonmain-runs.tsv | while read -r run_id branch; do
  sha=$(gh api "repos/$R/actions/runs/$run_id" --jq '.head_sha')
  n=$(gh api "repos/$R/commits/$sha" \
        --jq '[.files[]?.filename | select(startswith(".github/workflows/"))] | length')
  [ "${n:-0}" -gt 0 ] && printf '%s\t%s\t%s\t%s\n' "$run_id" "$branch" "$sha" "$n"
done | tee /tmp/8209-workflow-touching-runs.tsv | wc -l
```

A `404` from the commit call is itself a datum: the commit object is gone (branch deleted **and**
garbage-collected), so that run is recorded as **not resolvable**, not as clean. The count of
non-resolvable runs is reported beside the rest.

### L1(d) — org audit-log events, where the API exposes them

Collaborator, permission and App-installation events over the window:

```bash
for p in 'action:repo.add_member' 'action:repo.update_member' 'action:repo.remove_member' \
         'action:integration_installation.create' 'action:integration_installation.repositories_added' \
         'action:integration_installation_request.create'; do
  printf '%s\t' "$p"
  gh api /orgs/jikig-ai/audit-log -X GET -f phrase="$p" -f per_page=100 --paginate \
    --jq 'length' 2>/dev/null | paste -sd+ - | bc || echo 'API-UNAVAILABLE'
done
```

**The org audit-log API is a GitHub Enterprise Cloud surface.** If it answers `404`/`403` on this
plan, that is recorded as **API-UNAVAILABLE — limb INCONCLUSIVE**, and expressly **not** as a
clean result. This is the ADR-197 error the 2026-09-03 addendum to the 2026-06-29 precedent names:
an instrument that cannot answer must not be read as answering "nothing happened".

## L2-L5 — the limbs gathered outside GitHub

These are recorded in §Findings when they are run. Each is read-only and each prints no value.

- **L2 — Doppler access logs** for `soleur/prd_terraform` and `soleur/prd`: reads of the four
  names, by identity and timestamp, over the window.
- **L3 — Hetzner actions**: `rescue`, `rebuild` and volume `attach`/`detach` actions on any
  project server over the window. These are the three that convert `HCLOUD_TOKEN` into root on a
  host.
- **L4 — the Cloudflare account audit log**: R2 token use and any token creation over the window.
- **L5 — the start of the exposure window**, from the `prd_terraform` secret history: the date
  each of the four names first appeared in that config. Until L5 is recorded, the window is
  **open-ended at the near end** and this record does not state its duration.

## Findings

**None recorded yet.** No limb has been run at the date of this record. This section is where each
limb's result lands, each with its own date, the command that produced it, and a coverage verdict
naming the surface actually queried — the discipline Art. 30 PA-8 §(g) now requires of any Art. 33
evidentiary chain, after the 2026-09-03 addendum to the 2026-06-29 precedent established that an
access-log zero from an uninstrumented source was never evidence.

## If the finding flips

If any limb surfaces evidence of **use** of one of these credentials by a principal outside the
reachable class, or use inconsistent with the legitimate CI path:

1. A **FRESH 72h Art. 33(1) clock** starts from awareness of that evidence. It does not run from
   the 2026-09-22 anchor above.
2. **Art. 33(2) processor notification applies to the two third-party installers** of the
   soleur-ai App (plan M5: 3 installations, 2 outside `jikig-ai`). Jikigai acts as **processor**
   toward those installers for the repository content the App can reach, and Art. 33(2) requires
   notification to the controller without undue delay — that duty is not conditioned on the
   Art. 33(1) risk threshold.
3. **Art. 34 is re-run, not inherited.** Art. 34 requires *high* risk to rights and freedoms and
   is assessed on the facts of the flipped limb, not carried over from this record's conclusion.

## Conditions / residual actions

- **REQUIRED — L1 before O12 and O13.** The 90-day expiry is the reason. Recorded in the runbook's
  Order constraints and in plan AC10b.
- **REQUIRED — rotation of every reachable credential (plan R5, AC16).** Rotation is not
  remediation of a past exposure; it is what makes a past exposure stop mattering going forward.
  Each rotation carries its own negative probe (a `401`/verify-failure on the old value).
- **REQUIRED — the disposition is not final while any limb is INCONCLUSIVE** (plan AC17).
- **RESIDUAL R1 — the soleur-ai RUNTIME key is NOT evicted by this work and stays reachable.**
  `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY` in Doppler **`prd`** are the App's live runtime
  identity, and `prd_terraform` inherits from `prd`. That copy is readable by `DOPPLER_TOKEN_PRD`
  and by every `prd_*` branch-config repository secret. The App additionally holds
  `administration:write` on `jikig-ai/soleur`, so a holder could rewrite any environment's
  deployment-branch policy and defeat the Tier-B boundary this work builds. **The Tier-B boundary
  is therefore NOMINAL until R1 closes**, and this record's reachable class applies to the runtime
  key with no change. Tracked as residual R1 (#8209, class recorded at #6167) and as a row in
  `knowledge-base/legal/compliance-posture.md`.
- **PROCESS — register cross-reference.** This assessment is indexed at
  `knowledge-base/legal/breach-register.md`. That index is a pointer, not a copy: this file is the
  canonical record.

## Amendment convention

This record is **append-only**. A later limb result, a changed disposition or a correction is
added as a dated addendum below, which cites the text it annotates and amends nothing above it.
The convention is the 2026-06-29 precedent's, and it is why that file carries two addenda rather
than two rewrites.
