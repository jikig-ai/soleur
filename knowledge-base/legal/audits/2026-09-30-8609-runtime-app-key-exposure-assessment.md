---
title: "CLO assessment — prior exposure of the soleur-ai RUNTIME App private key held in Doppler `soleur/prd` (#8609, ADR-241 residual R1)"
type: clo-attestation
date: 2026-09-30
issue: 8609
attestation-authority: clo
status: SIGNED-OFF PROVISIONAL (CLO-agent-attested, Soleur-as-tenant-zero v1, 2026-09-30)
disposition: "REACHABILITY-ONLY — an Art. 33 ASSESSMENT, NOT a presumed breach. Follows the 2026-06-29 REACHABILITY-ONLY precedent (`knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`) and the #8209 record (`knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md`). No Art. 33(1), Art. 33(2), Art. 34 or contractual (Data Protection Disclosure §7.2) notification duty is recorded on the facts established to date. PROVISIONAL: every evidentiary limb K0–K4 is INCONCLUSIVE until shown clean, and K4 cannot be run by Jikigai at all."
disposition_history: "SIGNED-OFF PROVISIONAL 2026-09-30 on five open evidentiary limbs (K0 App key inventory, K1 non-`main` run census, K2 Doppler access and config logs, K3 org audit log and current boundary state, K4 third-party installation token issuance). No limb has been run at the date of this record."
signed_off_at: 2026-09-30
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-09-22 — the #8209 measurement session (`knowledge-base/project/plans/2026-09-22-feat-evict-privileged-terraform-credentials-plan.md`, §Measurements M1–M12), which established that `prd_terraform` is a branch config of `prd` and recorded this key's reachability as residual R1. #8609 was filed from it on 2026-09-23T13:27:39Z. The earlier date is taken, which is the conservative choice. No monitor surfaced this, and none could: every read is a legitimate read by a legitimate holder."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 33 duty arose on the facts established to date, so nothing fell due 72h from the awareness anchor. Re-opens with a FRESH 72h from awareness of any evidence of use surfaced by a limb below."
open_limbs: "five, all INCONCLUSIVE, none run: (K0) the soleur-ai App private-key inventory — fingerprint and added date of every key row, mapped to its holder; (K1) the read-only GitHub non-`main` run census over every workflow naming a `prd`-resolving Doppler token or a deploy-channel secret; (K2) Doppler access logs and the `soleur/prd` config log for `GITHUB_APP_PRIVATE_KEY`; (K3) the org audit log for `soleur-ai[bot]` administrative actions, plus the current deployment-branch-policy state; (K4) installation-token issuance on the two third-party installations, which Jikigai has no instrument to observe."
evidence_deadlines: "K0 BEFORE ANY soleur-ai App key row is deleted at GitHub: #8609 operator step R7 and #8209 operator step O13's App-key delete alike, because a delete destroys the row's added date. K1 BEFORE the 90-day Actions retention horizon (repository setting measured 2026-09-30: 90 days, which is also the maximum GitHub allows), and in any event at operator step R0b, before R1. The horizon is rolling: every day of delay loses a day at the far end of the census window. A closing K1 re-pull follows R6."
tier_classification: "Tier 1 — an internal assessment record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
related_records: "`knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md` (sibling: the DISTINCT soleur-ai key in `prd_terraform`, and the other three `prd_terraform` credentials); plan `knowledge-base/project/plans/2026-09-30-security-evict-runtime-app-key-from-prd-reachability-plan.md`; operator decision DC-1 in `knowledge-base/project/specs/feat-one-shot-8609-evict-runtime-app-key-prd/decision-challenges.md`."
---

# CLO assessment — #8609 prior exposure of the soleur-ai runtime App key in Doppler `soleur/prd`

## Verdict — REACHABILITY-ONLY. An Art. 33 **assessment**, not a presumed breach. PROVISIONAL

The facts established to date do not establish a personal-data breach under Art. 4(12). They
record no Art. 33(1) duty to the supervisory authority, no Art. 33(2) duty to the controllers for
whom Jikigai processes through the App, no Art. 34 duty to data subjects, and no duty under the
published Data Protection Disclosure §7.2 (Platform Breaches). The assessment is **PROVISIONAL**:
every evidentiary limb below is **INCONCLUSIVE** and expressly **not certified clean**.

This record applies the standing rule restated in
`knowledge-base/legal/audits/2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md`
and applied by the 2026-06-29 precedent and the #8209 record: **reachability alone does not start
the Art. 33 clock.** Like the #8209 record, and unlike the 2026-06-29 one, it cannot rest on an
absent exploitation precondition. The key was live, valid and nameable by a workflow throughout.
What bounds the matter is the **reachable class** below, which is small, named, and not the public.

## Why a record of its own, not an addendum to #8209

The #8209 record's §Conditions says of residual R1 that its reachable class "applies to the
runtime key with no change". That sentence is right about the **principals** and does not make
this key's exposure assessed there. Four facts differ, and each changes what must be measured:

1. **A distinct key.** `prd_terraform` overrides `GITHUB_APP_PRIVATE_KEY` with a different
   private key of the same App (#8209 plan M3/M4). The #8209 record assesses that key. The key
   assessed here is the one in the root config `prd`, which the web app uses to mint installation
   tokens for every connected user.
2. **Wider read paths.** The #8209 exposure ran through the repository secrets that resolve
   `prd_terraform`. This key is readable through **every** repository secret whose Doppler token
   resolves `prd` or any `prd_*` branch config, because a branch config inherits its root. The
   #8609 plan measured that set as `DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN` (`prd_terraform`),
   `DOPPLER_TOKEN_WEB_ARM` (`prd_terraform`), `DOPPLER_TOKEN_KB_DRIFT` (`prd_kb_drift_walker`) and
   `DOPPLER_TOKEN_DRIFT_MAP` (one read token per `soleur` config, `prd` included). It also reached
   the web host through the branch-readable deploy channel, which delivers every `prd` secret to
   the image it deploys (plan §Non-Goals, #6129).
3. **An earlier window start.** The key has sat in `prd` since it was added there, which may
   predate `prd_terraform`'s credentials. The start is not known (see §The exposure window).
4. **A different closure instrument.** This key is closed by the #8609 rotation (a new key
   generated into an isolated Doppler project, the old key deleted at GitHub), not by #8209 O13.

## The fact pattern (measured 2026-09-30)

| Fact | Source |
|---|---|
| The soleur-ai App's runtime private key is held as `GITHUB_APP_PRIVATE_KEY` in Doppler `soleur/prd` | #8609 plan §Consumers and delivery path |
| It is readable by every `prd`/`prd_*` branch-config repository-secret token, from a workflow on any branch of the **public** repository `jikig-ai/soleur` | #8609 plan §Overview and Reconciliation row 3 |
| The App holds, among its write permissions, `administration`, `contents`, `secrets`, `actions` and `pull_requests` write | measured 2026-09-30; permission set in `apps/web-platform/infra/github-app-manifest.json` |
| The App has 3 installations (organisations), 2 of them outside `jikig-ai` | measured 2026-09-30; #8209 plan M5 |
| `administration:write` on `jikig-ai/soleur` lets a key holder rewrite any environment's deployment-branch policy, which is the enforcement point of the ADR-241 Tier-B boundary | ADR-241 D2 and residual R1 |
| Doppler keeps the old value in the config's version history after a delete, so deleting the secret alone does not end the exposure | #8609 plan §Problem Statement; CTO finding F6.1 |
| No evidence of use has been gathered. That is what K1–K3 do; K4 cannot be done | this record |
| The eviction mechanism is draft PR #9263 (PR-A). It has not merged at the date of this record | GitHub, read 2026-09-30 |

Step names R0–R8 are those of the #8609 operator sequence (plan §Operator Sequence (R0–R8)).

The personal data reachable through the key is **repository content of connected users** on all
three installations, two of them third-party, together with whatever a holder could reach by using
`administration:write` and `secrets:write` to defeat the Tier-B boundary. That chain leads to the
credentials the #8209 record assesses and, through them, to Art. 30 **PA-36** and **PA-2**. On
`jikig-ai/soleur` the App's `administration:write` also reaches the branch-protection state Art. 30
**PA-12** records. Severity, had access occurred, would be non-trivial. As in both precedents, the
**likelihood** prong is doing the work, not the severity prong.

## The reachable class, stated precisely

The class of **principals** is the #8209 record's, and it is not "the public":

1. **Write collaborators** on `jikig-ai/soleur`, because a push to a branch is what causes a
   workflow run on a non-`main` ref to receive the repository secret set; and
2. **GitHub Apps installed on `jikig-ai/soleur` holding `contents:write`**, because such an App can
   create the branch and the workflow file that names the secret.

**Fork pull requests never received secrets.** A `pull_request` run from a fork gets a read-only
`GITHUB_TOKEN` and no repository secrets. The census records the fork/non-fork split rather than
assuming it.

The same principals reach the key by two **routes**, and K1 covers both:

- **(a) Naming a `prd`-resolving Doppler token** in a workflow on a non-`main` ref.
- **(b) The deploy channel.** A branch run that names the deploy-webhook secret and the Cloudflare
  Access pair can ship an image to web-1, which the deploy then starts with every `prd` secret
  (#6129; the image-verification mode is `warn`).

The class enumeration commands are the #8209 record's §The reachable class, unchanged. **One run
serves both records:** a single dated enumeration, recorded in each, discharges that part of #8209
L1 and of K1.

## The exposure window

- **Start: unknown, open-ended at the near end.** K0 gives a lower bound: the key cannot have
  been in `prd` before its row's added date on the App settings page. K2(b) gives the precise
  start: the date `GITHUB_APP_PRIVATE_KEY` was first set in `soleur/prd`. Until one of them is
  recorded, this record does not state the window's duration.
- **End of new reads: operator step R6**, the delete from `soleur/prd`, and only if R6's own
  verification passes (every `prd`/`prd_*` config returns not-found).
- **End of the exposure: operator step R7.** A copy taken during the window stays usable until
  GitHub rejects the old key. The window closes when a JWT signed with the old key gets `401`
  from `GET /app`, not when the secret is deleted.

Neither end has happened. Both are future steps of the #8609 operator sequence, and their
recording belongs to PR-B.

## Evidence limbs K0–K4

**Discipline, carried over from the #8209 record and load-bearing.** Every instrument below returns
identifiers, names, fingerprints, dates and counts. **No instrument reads a secret value or a
workflow log body, and none may.** `gh run view --log`, `gh api …/logs`, a run-archive download or
a Doppler read that prints a value are out of scope for this record: a legal record that gathers a
value has created a second copy of the exposure it assesses. An instrument that cannot answer is
recorded **API-UNAVAILABLE — limb INCONCLUSIVE**, never as clean (the ADR-197 error named by the
2026-09-03 addendum to the 2026-06-29 precedent).

| Limb | What it establishes | Instrument | Deadline | Status 2026-09-30 |
|---|---|---|---|---|
| K0 | Every private-key row of the soleur-ai App, with its fingerprint and added date, mapped to a holder (`prd` runtime, `prd_terraform`, or other); the installation-id set | operator step R0: a read of the App settings page, `GET /app/installations`, and DER-SHA-256 fingerprints computed in memory | **Before any App key row is deleted at GitHub** — R7 here and #8209 O13's App-key delete alike | NOT RUN — INCONCLUSIVE |
| K1 | Runs on non-`main` refs of every workflow that names a `prd`-resolving token or a deploy-channel secret, with the fork split and the workflow-touching subset | read-only `gh api` census (below) | **At R0b and before R1, inside the 90-day retention horizon; closing re-pull after R6** | NOT RUN — INCONCLUSIVE |
| K2 | (a) Reads of `soleur/prd*` by identity and time; (b) the date `GITHUB_APP_PRIVATE_KEY` first appeared in `soleur/prd` | Doppler access logs, if the workplace plan exposes them, and the `soleur/prd` config log | Before #8609 closes; K2(a)'s own retention is recorded first | NOT RUN — INCONCLUSIVE |
| K3 | (a) Administrative actions by `soleur-ai[bot]` on the org and repository; (b) whether the deployment-branch policies stand as declared today | org audit-log API; environment and branch-policy reads | Before #8609 closes | NOT RUN — INCONCLUSIVE |
| K4 | Installation tokens minted for the two third-party installations by anyone other than the web app | none available to Jikigai | n/a | INCONCLUSIVE — cannot be run by Jikigai |

### K0 — the App key inventory

Run at operator step R0, before anything else in the sequence. GitHub has no REST endpoint that
lists an App's private keys, so the inventory is a read of the App's settings page (the operator
sequence records the Playwright attempt and its fallback). Recorded here: each row's fingerprint and added
date, the holder it maps to, and the installation-id set. Values are never recorded.

**A row that maps to no holder stops the sequence.** It is attributed if it can be, to a
legitimate holder with a dated reason. If it cannot be attributed, it is treated as evidence under
§If the finding flips, and the fresh 72h clock runs from the moment that attribution fails.

K0 serves the #8209 record too: the `prd_terraform` key's row and its added date are the only
record of when that key was created, and #8209 O13 deletes that row.

### K1 — the non-`main` run census (counts and run ids ONLY)

The #8209 record's L1(b)–(c) commands are reused **unchanged**, over a wider workflow set:

```bash
grep -rlE 'secrets\.(DOPPLER_TOKEN[A-Z0-9_]*|WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_(ID|SECRET))\b|toJSON\(secrets\)' \
  .github/workflows/ | sed 's|.github/workflows/||' | sort > "$K1_DIR/8609-workflow-set.txt"
wc -l < "$K1_DIR/8609-workflow-set.txt"
```

The pattern over-includes on purpose. It takes every `DOPPLER_TOKEN*` secret, not only the five the
plan measured as `prd` readers. A workflow drops out only when every token it names is shown to
resolve a config other than `prd` or `prd_*`, and each such exclusion is recorded with its reason.
`toJSON(secrets)` is included for the #8209 record's reason: it names every secret without naming
any. The registry push credentials are part of route (b) as well, and their secret names are added
from the repository at census time.

`$K1_DIR` is a directory outside the repository. Any file this record cites stays unchanged. A
later re-pull writes **new** filenames and does not overwrite a cited file.

Recorded in §Findings: the total count, the count per workflow and per actor, the fork/non-fork
split, the run ids, the workflow-touching subset (L1(c)'s commit-by-SHA method, with the count of
runs that can no longer be resolved), and the census's coverage start date.

**Coverage limit, stated now.** Runs older than 90 days before the census date are gone and cannot
be recovered. K1 can at best be **CLEAN within [census date minus 90 days, census date]**. Any part
of the exposure window before that is INCONCLUSIVE for good.

**Closing re-pull after R6.** A census taken at R0b cannot see runs between R0b and R6, and the
key stays branch-readable until R6. A second pull after R6's verification passes, restricted to
runs created after the first pull's newest run, closes that gap.

### K2 — Doppler logs

- **K2(a) — access logs.** First record whether the workplace's Doppler plan exposes read-access
  logs for `soleur/prd*` at all, and their retention. If it does not, K2(a) is API-UNAVAILABLE and
  INCONCLUSIVE. If it does, record the reads by identity and timestamp over the window, and flag
  any identity that is not a known consumer.
- **K2(b) — the config log.** The date `GITHUB_APP_PRIVATE_KEY` was first set in `soleur/prd`, and
  each later change to it, by date and actor. Only the log id, the timestamp, the actor and the
  names of changed secrets are kept. A field that carries a value is never selected.

### K3 — administrative actions and the boundary's current state

- **K3(a) — org audit log.** Actions by `soleur-ai[bot]`, as counts per action name over the
  window, with the #8209 record's L1(d) method (`gh api /orgs/jikig-ai/audit-log`, phrase
  `actor:soleur-ai[bot]`). The org audit-log API is a GitHub Enterprise Cloud surface. If it
  refuses, K3(a) is API-UNAVAILABLE and INCONCLUSIVE.
- **K3(b) — current state.** For each Tier-B environment, the deployment-branch policy as it reads
  today, compared with the ADR-241 declaration (`gh api repos/jikig-ai/soleur/environments` and
  each environment's `deployment-branch-policies`; names only). This shows the boundary stands as
  declared at the moment of the read. It **cannot** show that a policy was never rewritten and then
  restored, and it is recorded with that limit.

### K4 — third-party installation token issuance

A holder of the key could mint installation tokens for the two third-party installations and use
them against those installers' repositories. Any trace of that would be in the installers' own
audit logs, which Jikigai cannot see. No instrument available to Jikigai is known to the CLO at the
date of this record that lists the installation tokens minted for an installation. The web app's
own telemetry records only the web app's own mints. K4 is therefore **INCONCLUSIVE and cannot be
run by Jikigai**.

This has one consequence, stated now so it is not discovered later: **this record cannot become
final by showing every limb clean.** It can become final only by a controller decision that closes
K4 as **INCONCLUSIVE-BY-DECISION**, never as CLEAN, following the 2026-09-14 (#7945) precedent in
`knowledge-base/legal/breach-register.md`. "Provisional" and "inconclusive" are separate axes. That
decision is not made here.

## Findings

**None recorded yet.** No limb has been run at the date of this record. Each limb's result lands in
a dated addendum below, with the instrument that produced it and a coverage verdict naming the
surface actually queried.

## Notification — controller decision recorded 2026-09-30

**No notification is made at this date, and none is owed on the facts established to date.**

- **Art. 33(1)** — no duty. Reachability without evidence of use does not establish a breach under
  Art. 4(12), and the standing rule applies.
- **Art. 33(2)** — no duty. Jikigai is the processor toward the two third-party installers for the
  repository content the App reaches (the #8209 record's analysis). Art. 33(2) is engaged when the
  processor becomes aware of a personal-data breach, and none is established.
- **Art. 34** — no duty. No breach is established, so no high-risk assessment arises.
- **Data Protection Disclosure §7.2** — not engaged. Its promise to notify affected Users within
  72 hours is conditioned on "a breach". On these facts none is established.

**Voluntary courtesy notice — operator decision DC-1, OPEN.** A voluntary notice to the two
third-party installers is legally defensible, because K4 can never be measured and the repository
is public. The CPO recommends sending one after PR-B. Whether to send it is a product and trust
decision, recorded as DC-1 in
`knowledge-base/project/specs/feat-one-shot-8609-evict-runtime-app-key-prd/decision-challenges.md`.
**Default if no decision is recorded: no notice is sent**, and this section is the record of that
default. If a notice is sent:

1. Its wording is reviewed by the CLO before it is sent.
2. It does not say "no indication of misuse", "no evidence of misuse" or anything similar unless K1,
   K2 and K3 are recorded here, and it says that the installers' own logs, K4, were not visible to
   Jikigai.
3. It is not framed as an Art. 33(2) or DPD §7.2 notification. It is sent voluntarily. Framing it
   as a statutory notice would state a breach this record does not find.
4. Its date, recipients and wording are recorded in a dated addendum here.

## If the finding flips

If any limb surfaces evidence of **use** of this key by a principal outside the reachable class,
or use inconsistent with the web app's legitimate minting, or an App key row that cannot be
attributed (K0):

1. A **FRESH 72h Art. 33(1) clock** starts from awareness of that evidence. It does not run from
   the 2026-09-22 anchor.
2. **Art. 33(2) notification to the two third-party installers** follows without undue delay. That
   duty is not conditioned on the Art. 33(1) risk threshold.
3. **Data Protection Disclosure §7.2 engages** for affected Users (notice within 72 hours where
   feasible, through the repository and direct communication). On its face that published promise
   is not conditioned on the Art. 33(1) risk threshold either.
4. **Art. 34 is re-run, not inherited.** It is assessed on the facts of the flipped limb.
5. **A K3 flip is also a #8209 flip.** A rewrite of a deployment-branch policy defeats the Tier-B
   boundary, and that re-opens the #8209 record's credentials under its own §If the finding flips.

## Conditions / residual actions

- **REQUIRED — K0 before any App key delete; K1 inside the retention horizon.** See
  `evidence_deadlines` above and the order constraints of the #8609 operator sequence (plan
  §Operator Sequence; its canonical copy moves to
  `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` in PR-A).
- **REQUIRED — rotation, not only eviction.** Because Doppler keeps the value in version history, a
  move without rotation closes nothing against a copy already taken. The #8609 plan generates a new
  key into an isolated Doppler project (R1) and deletes the old key at GitHub last (R7). R7's `401`
  probe on the old key is what closes the exposure window. Rotation does not remediate a past
  exposure. It makes a past exposure stop mattering from then on.
- **CONDITIONAL — the mechanism.** If PR #9263 merges, it ships the mechanism and the runbook
  sequence and closes nothing. R1 closes only when the operator sequence is measured: the old key's
  JWT gets `401`, and the App lists exactly one key. Both are recorded in PR-B, together with this
  record's closure addendum and the Article-30 markers (Cross-Cutting "Secrets management" and PA-12
  §(g)(3)). None of them is recorded here.
- **REQUIRED — the disposition is not final while any limb is INCONCLUSIVE**, and K4's route to
  finality is the decision described under §K4.
- **PROCESS — register cross-reference.** Indexed at `knowledge-base/legal/breach-register.md`. That
  index is a pointer, not a copy: this file is the canonical record. Tracked as an Active Item in
  `knowledge-base/legal/compliance-posture.md`.

## Amendment convention

This record is **append-only**. A limb result, a changed disposition, a notice decision or a
correction is added as a dated addendum below. The addendum cites the text it annotates and amends
nothing above it, and a superseded sentence gets a `> **Superseded <date> (#N): …**` marker beneath
it. Code and records are cited by function, constant, section or anchor name, never by line number.
