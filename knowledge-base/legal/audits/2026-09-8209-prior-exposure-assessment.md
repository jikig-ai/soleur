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
open_limbs: "five, all INCONCLUSIVE, none run in full (one L3 sub-limb run 2026-09-28, #8734; widened in-cell from \"none yet run\"): (L1) the read-only GitHub non-`main` run census; (L2) Doppler access logs for `prd_terraform` and `prd`; (L3) Hetzner actions (rescue, rebuild, volume attach) and a server created or rebuilt from retained snapshot image 411798619, the fourth route, #8734 [widened in-cell 2026-09-28 (#8734): the image-use sub-limb was run 2026-09-28 and is CLEAN within its window; L3 as a whole stays INCONCLUSIVE — see §Addendum — 2026-09-28 (#8734)]; (L4) the Cloudflare account audit log; (L5) the start of the exposure window, from the `prd_terraform` secret history. L1 must be gathered BEFORE operator step O13 — see §Evidence gathering order."
tier_classification: "Tier 1 — an internal assessment record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
addendum_2026_09_28: "The fourth L3 route (§Addendum — 2026-09-28 (#8734)). Hetzner snapshot image 411798619 (web-1 root disk, 2026-07-23) was deleted 2026-09-28T08:01:45Z (DELETE 204, GET 404). Its image-use sub-limb is CLEAN within [2026-07-23T15:34:04Z, 2026-09-28T08:01:45Z]; the `web-probes-read` token-read limb stays INCONCLUSIVE and its value-rotation determination is owed under #9122. L3 as a whole stays INCONCLUSIVE. Determination unchanged: REACHABILITY-ONLY, PROVISIONAL."
addendum_2026_09_30: "Pointer to the #8609 record (§Addendum — 2026-09-30 (#8609)), conditioned on the merge of PR #9263, which carries it. The soleur-ai RUNTIME key in `soleur/prd` (residual R1) is assessed in `knowledge-base/legal/audits/2026-09-30-8609-runtime-app-key-exposure-assessment.md`, not here. That record's K0 (the App key inventory) must precede this record's O13 App-key delete. Nothing above is amended. Determination unchanged: REACHABILITY-ONLY, PROVISIONAL."
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

> **Superseded 2026-09-28 (#8734):** the `HCLOUD_TOKEN` row's "root on any host through rescue,
> rebuild or a volume re-attach" undercounts that credential's reach. It also reached the contents
> of web-1's past root disk, through a server built from retained snapshot image `411798619`. See
> §Addendum — 2026-09-28 (#8734).

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

  > **Superseded 2026-09-28 (#8734):** "These are the three" undercounts the routes. A fourth
  > route converts `HCLOUD_TOKEN` into the contents of web-1's root disk without touching a live
  > host: create or rebuild a server from retained snapshot image `411798619` (web-1's root disk
  > as of 2026-07-23). The limb now covers it. Its image-use sub-limb was run and is recorded in
  > §Addendum — 2026-09-28 (#8734); L3 as a whole stays INCONCLUSIVE.
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

> **Superseded 2026-09-28 (#8734):** "**None recorded yet.** No limb has been run at the date of
> this record." The second sentence stays true of 2026-09-23; the first no longer holds for one
> sub-limb. The
> L3 image-use sub-limb (retained snapshot image `411798619`) was run 2026-09-28 and is recorded,
> with its command surface and coverage verdict, in §Addendum — 2026-09-28 (#8734). Every other
> limb, and L3 as a whole, is still unrecorded here.

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

## Addendum — 2026-09-28 (#8734) — the fourth L3 route: snapshot image 411798619

**What this addendum annotates.** Four passages above:

- the frontmatter `open_limbs` text, which read "five, all INCONCLUSIVE and none yet run" and
  "(L3) Hetzner actions (rescue, rebuild, volume attach)";
- the §The fact pattern table's `HCLOUD_TOKEN` row, which read "root on any host through rescue,
  rebuild or a volume re-attach";
- the §L2-L5 L3 bullet, which read "These are the three that convert `HCLOUD_TOKEN` into root on a
  host";
- §Findings, which read "**None recorded yet.**"

The `open_limbs` text is widened in-cell; the other three carry Superseded markers. Nothing above is
otherwise amended.

### 1. The route

Hetzner image `411798619` was a snapshot of web-1's **root disk**. It was created
2026-07-23T15:34:04Z from server `123931471` by `scripts/cutover-inngest.sh` `op=backup`, with
labels `purpose=inngest-cutover-pre` and description `inngest-cutover-pre-20260723T153403Z`. It
held the `soleur/prd` secret values written to web-1's root disk on that date. Any holder of
`HCLOUD_TOKEN` could create or rebuild a server from it and read that disk. That is a route to
secret values and personal data that needs no rescue, rebuild or volume re-attach of a live host.

It was ADR-100's Inngest-cutover rollback substrate. It was **never** ADR-119's rollback anchor:
ADR-119 §(b) says not to take a pre-cutover Hetzner snapshot, and a server snapshot holds the root
disk only, never an attached volume.

### 2. The deletion

The image was deleted 2026-09-28T08:01:45Z, on the operator's explicit per-command go-ahead.
`DELETE /v1/images/411798619` answered `204`, the following `GET` answered `404 not_found`, and the
image action `delete_image` reads `status=success` at 08:01:45Z. The evidence record, including
the identity re-read made before the DELETE, is
<https://github.com/jikig-ai/soleur/issues/8734#issuecomment-5865894224>.

The Art. 5(2) destruction record for the web-1 snapshots lives on the unmerged PR #8626. It stays
`partial` until that PR lands, and this addendum does not call it complete.

### 3. The image-use sub-limb — CLEAN within [2026-07-23T15:34:04Z, 2026-09-28T08:01:45Z]

**Surface queried:** the Hetzner Cloud API for the project, read-only, `GET /v1/servers/actions`
(every page, deleted servers included), `GET /v1/images/actions` and `GET /v1/servers`. The action
set was 7 pages and 317 server actions spanning 2026-07-03T07:13:22Z to 2026-09-27T14:56:48Z. It
was pulled at 2026-09-28T07:56:04Z and again after the DELETE, at 08:01:46Z; at both pulls its
newest action was 2026-09-27T14:56:48Z, so no server action falls between that one and the DELETE.
Every assertion was a
`jq` expression with an exit status. Both pulls read:

- zero `rebuild_server` actions;
- 101 `create_server` actions, **every one** carrying an image resource, all of them image
  `161547269`, and none naming `411798619`;
- the only action naming `411798619` is its own `create_image`;
- no `delete_image` or `change_protection` action on it before the DELETE;
- `GET /v1/servers`: no live server built from it.

**Coverage verdict.** The window opens at the image's creation, because the image did not exist
earlier, so the action log's 2026-07-03 start does not limit this sub-limb. It closes at the
DELETE, because a deleted image cannot be used. Within that window the sub-limb is **CLEAN**.

**Why a CLEAN image-use limb bounds the in-image copy of `web-probes-read`.** The Hetzner Cloud API
offers no read of an image's contents other than booting a server from it by `create_server` or
`rebuild_server`. No such action named this image, so any copy of the `web-probes-read` service
token held inside the image (ADR-119's 2026-09-24 (#8705) addendum: "very likely") was never
materialised and never read through the image. Any other
holder of that token, through its live copies or through the Doppler side, is not reached by this
limb. That holder belongs to #8705's population, and is assessed under the token-read limb below.

### 4. The token-read limb — INCONCLUSIVE

`web-probes-read` is a read token on `soleur/prd` (created 2026-07-18, rotated under #8705 by PR
#8733). Whether it was used, outside its legitimate consumer, to read `soleur/prd`
values is not answered by any instrument run to date. The limb stays **INCONCLUSIVE**. Deleting the
image does not close it: the token route never depended on the image.

**Where the Art. 4(12) / Art. 33 assessment of that token route lives: nowhere yet.** #9122 is
framed as a value-rotation determination. This record's credentials and reachable class are
#8209's, not that token's, and `knowledge-base/legal/` holds no #8705 assessment and no
breach-register row for it. That assessment is owed. It belongs either in #9122's determination,
widened to cover Art. 33 as well as rotation, or in a record of its own with a breach-register row.
This addendum does not make it.

**`HCLOUD_TOKEN` was not readable through that token.** Measured read-only on 2026-09-28:
`HCLOUD_TOKEN` exists only in `soleur/prd_terraform` and is absent from `soleur/prd`, the config
`web-probes-read` was scoped to.

### 5. #8209's L3 as a whole stays INCONCLUSIVE

The image route is one sub-limb. The rest of L3 is not closed by it:

- volume attach and detach actions in #8209's window are unattributed;
- the two `enable_rescue` actions (2026-07-07 and 2026-07-14, both on servers other than web-1) are
  unattributed;
- nothing before 2026-07-03, where the retained action log starts, is covered.

### 6. Credential dispositions

- **`SUPABASE_SERVICE_ROLE_KEY`:** not rotated under #8734's image route (image-use CLEAN, image
  deleted before 2026-10-06); the token-route decision is owed under #9122.
- **`BYOK_ENCRYPTION_KEY`:** not rotated under #8734's image route (image-use CLEAN, image deleted
  before 2026-10-06); the token-route decision is owed under #9122. The CTO's concurrence, dated
  2026-09-28 in the #8734 plan and recorded here, has two conditions. The first, a re-pull of the evidence at deletion, is
  met by the 08:01:46Z pull above. The second, a mandatory rotation issue if the image outlived
  2026-10-06, is not engaged, because the image was deleted on 2026-09-28.
- **Both keys stay readable through the `web-probes-read` token route**, whose read limb is
  INCONCLUSIVE (§4). The image deletion does not close that route. #9122 names both keys,
  alongside `STRIPE_SECRET_KEY` and the other `soleur/prd` values.
- **Every other root-disk secret class the image held** is tied to the same CLEAN image-use limb
  and is not rotated under the image route: web-1's SSH host private keys (CI pins
  `local.web_1_ssh_host_key`), cloud-init `user-data`, the cloudflared tunnel credentials, the GHCR
  pull token and the Vector/Better Stack ingest token. A copy of any of them held in `soleur/prd`
  falls under #9122's token-route determination, not under this limb.
- **`STRIPE_SECRET_KEY`:** not triggered on the image route. #8705 left value exposure to #8734, so
  the token-route value-rotation determination had no owner. It is filed as the separate,
  operator-gated #9122, which covers the Stripe key, the service-role key, BYOK and the other
  `soleur/prd` values.
- **`GITHUB_APP_PRIVATE_KEY`:** not rotated under #8734; owed under #8209 R5 / R1.

### 7. Disposition unchanged

The record stays **REACHABILITY-ONLY** and **PROVISIONAL**. `art_33_triggered` and
`art_34_triggered` stay `false`. No limb has surfaced evidence of use, so §If the finding flips is
not engaged. If evidence of use of the image, or of the token, surfaces later, a FRESH 72h
Art. 33(1) clock runs from awareness of it, as §If the finding flips states.

## Addendum — 2026-09-30 (#8609) — pointer to the runtime-key assessment

**This addendum takes effect on the merge of PR #9263, which carries it.** If that PR closes
unmerged, this addendum is void and §Conditions / residual actions stands as written. Nothing above
is amended.

**What this addendum annotates.** The §Conditions / residual actions bullet "RESIDUAL R1 — the
soleur-ai RUNTIME key is NOT evicted by this work and stays reachable", and in particular its
sentence that "this record's reachable class applies to the runtime key with no change".

### 1. Where the runtime key's exposure is assessed

The runtime key's prior exposure is assessed in its own dated record,
`knowledge-base/legal/audits/2026-09-30-8609-runtime-app-key-exposure-assessment.md`, with its own
evidence limbs K0–K4 and its own index row in `knowledge-base/legal/breach-register.md`. It is not
assessed here, and this record's L1–L5 do not discharge it.

The sentence quoted above stays true of the **principals**: write collaborators on
`jikig-ai/soleur`, plus Apps installed on it holding `contents:write`. It does not carry over to
the **routes** or the **window**. The runtime key sits in the root config `prd`, so every
`prd`/`prd_*` branch-config repository-secret token and the branch-readable deploy channel reach
it, and its exposure window may start earlier than this record's. Those differences are why it has
a record of its own.

### 2. Two ordering constraints this record now shares

- **The #8609 K0 inventory precedes O13's App-key delete.** O13 deletes the `prd_terraform` key's
  row on the App settings page, and that delete destroys the row's added date. K0 reads every key
  row, this record's `prd_terraform` key included, so K0 is also the only evidence of when that key
  was created.
- **One class enumeration serves both records.** A single dated run of §The reachable class
  commands, recorded in both files, discharges that part of L1 here and of K1 there. The two run
  censuses do differ: K1's workflow set is wider. A single census over K1's set covers L1(b)'s set as
  well, provided each record states the workflow set it relied on.

### 3. One gap in §If the finding flips, recorded rather than corrected

§If the finding flips names Art. 33(1), Art. 33(2) and Art. 34. It does not name the published Data
Protection Disclosure §7.2 (Platform Breaches), which promises affected Users notice within 72 hours
"where feasible" of a breach affecting the Web Platform or the repository, with no Art. 33(1) risk
threshold on its face. If a limb here flips, §7.2 engages alongside Art. 33(2). The #8609 record
states this in its own §If the finding flips.

### 4. Disposition unchanged

The record stays **REACHABILITY-ONLY** and **PROVISIONAL**. `art_33_triggered` and
`art_34_triggered` stay `false`. The `GITHUB_APP_PRIVATE_KEY` bullet in §6 of the 2026-09-28
addendum ("owed under #8209 R5 / R1") stays accurate. The `prd_terraform` key is rotated under this
record's O13. The runtime key is rotated under the #8609 operator sequence (R1 to R7), and that
closure is recorded in the #8609 record, not here.
