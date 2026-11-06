---
title: "CLO determination — Art. 4(12) assessment of the #11294 random_id log exposure"
type: clo-attestation
date: 2026-10-29
issue: 11294
related_issues: "10205"
attestation-authority: clo
status: "DRAFT v1 — internal CLO attestation (Soleur-as-tenant-zero v1), NOT external counsel advice. SIGNED-OFF PROVISIONAL by the CLO agent on 2026-10-29; operator retains an optional veto."
disposition: "SECURITY INCIDENT, NOT a presumed notifiable personal-data breach. Art. 4(12) first limb (a breach of security) is satisfied; the second limb (unauthorised access to personal data) is not established. Reachability alone does not start the Art. 33 clock. PROVISIONAL: every evidentiary limb is INCONCLUSIVE and none is certified clean. The who-viewed-the-logs limb has no instrument and is inconclusive by nature."
disposition_history: "SIGNED-OFF PROVISIONAL 2026-10-29 on open evidentiary limbs E1 (run-log census, partly run: counts only), E2 (use-of-key signals, not run), E3 (who viewed the logs, no instrument), E4 (copies outside the run logs: drift issues and comments, found by the census, not yet contained)."
signed_off_at: 2026-10-29
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-10-27T09:31:36Z — issue #11294 filed. The conservative date: the exposure was first noticed by a review, no monitor surfaced it, and an earlier date of awareness is not established."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 33 duty arose on the facts established to date, so nothing fell due 72h from the awareness anchor (2026-10-30T09:31:36Z computes the instant, no duty attaches to it). Re-opens with a FRESH 72h from awareness of any evidence that one of the exposed keys was used by a party outside the legitimate holders (see §If the finding flips)."
open_limbs: "four, all INCONCLUSIVE: (E1) the retained-run-log census; (E2) the use-of-key signals; (E3) who viewed the public logs, for which no instrument exists; (E4) copies of the printed values outside the run logs (public drift-issue bodies and comments)."
tier_classification: "Tier 1 — an internal determination record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged. No signed record is edited."
semver: "No TC_VERSION bump."
related_records: "`knowledge-base/legal/audits/2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md` (the standing rule: reachability alone does not start the Art. 33 clock); `knowledge-base/legal/audits/2026-09-30-8609-runtime-app-key-exposure-assessment.md` (the reachable-class method and the counts-only discipline); `knowledge-base/legal/audits/2026-10-28-clo-determination-11303-gated-tier-allowedtools-bypass.md` (precedent for indexing a security incident that is not a presumed breach)."
---

# CLO determination — #11294 `random_id` values printed in public Actions logs, Art. 4(12)

> **DRAFT v1. Internal CLO attestation, not external counsel advice.** It records the CLO
> agent's position on 2026-10-29 for the Art. 33(5) file. External counsel re-review is
> reserved for the triggers named in §If the finding flips. No signed record is edited by this
> record. It is append-only after merge (§Amendment convention).

## Verdict — a security incident, NOT a presumed notifiable personal-data breach. PROVISIONAL

1. **Art. 4(12), first limb — a breach of security: SATISFIED.** Terraform printed the `id`
   attribute of `random_id` resources into the logs of a **public** repository's workflow runs.
   For `random_id` that attribute is the key material itself, in base64url (the issue title of
   #11294 states this). The Art. 32(1)(b) confidentiality measure for twelve secrets failed.
   This is conceded, not contested.
2. **Art. 4(12), second limb — unauthorised access to personal data: NOT ESTABLISHED.** No
   third party is shown to have read a value, and no one is shown to have used one.
3. **Reachability alone does not start the Art. 33 clock.** This is the standing rule of the
   7797 determination, restated in `knowledge-base/legal/statutory-response-catalog.md`
   §`breach-art33` first-response step 4. It applies here, **but this is a weaker case than
   7797 and than 8609**, for the reason in §The reachable class below: the readers who could
   see the logs are not a small named set. They are any GitHub account holder able to view a
   public repository's Actions logs, and the GitHub log-access rules that decide who that is
   have **not been verified** for this record.
4. **Art. 33 and Art. 34 are recorded as not engaged.** Only the **Art. 33(5)** internal record
   is owed, and this file and its register row are that record.
5. **Re-opener.** Any evidence that one of the exposed keys was used by a party outside its
   legitimate holders starts a **fresh** 72h from awareness of that evidence.

## Why a record of its own

The post-mortem route is wrong for the same two mechanical reasons the 7797 record gives
(`plugins/soleur/skills/incident/SKILL.md` forbids a register row for a PIR whose
`art_33_triggered` reads `false`; `scripts/lint-legal-registers.sh` carries exactly one
out-of-producer literal). A determination under `audits/**` needs no waiver and no gate change.
The 2026-10-28 #11303 row is the precedent for indexing a security incident that is not a
presumed breach, with the label stating so.

## The fact pattern

| Fact | Source |
|---|---|
| Terraform prints `[id=<value>]` on refresh, plan and apply lines for managed resources. For `random_id` the `id` is the base64url encoding of the random bytes, so the printed value **is** the secret | #11294 (title and body); terraform provider behaviour |
| The twelve `random_id` resources, all in `apps/web-platform/infra/` | below |
| `random_password` resources print `[id=none]`, not the value. They are **not** exposed by this mechanism, including `inngest_redis_password_dedicated` | provider behaviour (the `id` of `random_password` is the literal `none`), not separately measured; the census counts only `random_id` addresses followed by a value-shaped id |
| The repository `jikig-ai/soleur` is **public**. Actions logs of a public repository are visible to anyone permitted to view them (rules unverified, below) | repository visibility; GitHub documentation not re-read for this draft |
| Retention of run logs is **90 days**, the maximum GitHub allows | `gh api repos/jikig-ai/soleur/actions/permissions/artifact-and-log-retention`, read 2026-10-29: `days: 90`, `maximum_allowed_days: 90` |
| Values are **not** reproduced in this record, nor any length or digest of them | this record |

The exposed resources and what each key authorises, as declared in the Terraform source. This
is a reading of the source, not a test, and the CTO confirms the capability column:

| Resource | File | What holding the value authorises |
|---|---|---|
| `random_id.inngest_signing_key_prd`, `_dev` | `inngest.tf` | Inngest signing key: signs and verifies traffic between the Inngest server and the app's serve route |
| `random_id.inngest_event_key_prd`, `_dev` | `inngest.tf` | Inngest event key: sends events that trigger functions |
| `random_id.inngest_manual_trigger_secret_prd`, `_dev` | `inngest.tf` | Bearer for `POST /api/internal/trigger-cron` |
| `random_id.inngest_signing_key_dedicated`, `random_id.inngest_event_key_dedicated` | `inngest-host.tf` | The dedicated Inngest host's own pair. **Printed by the `inngest-host` job (an unfiltered apply with no `add-mask`): treat as exposed** |
| `random_id.github_webhook_secret` | `github-app.tf` | HMAC secret that authenticates GitHub webhook deliveries to the app |
| `random_id.egress_audit_ingest_token` | `egress-audit.tf` | Authenticates rows posted to the egress-audit ingest (ADR-288: anything able to read the app environment can forge rows) |
| `random_id.kb_drift_ingest_signing_key` | `kb-drift.tf` | Signs KB-drift ingest posts |
| `random_id.tunnel_secret` | `tunnel.tf` | See the next paragraph |

**`tunnel_secret` is a weak ground for rotation, and the record says so.** The CTO ruled on
2026-10-29 that the printed `random_id.tunnel_secret` **probably is not the live tunnel
secret** (an inference, unverified): `tunnel.tf` carries `lifecycle { ignore_changes = [secret,
config_src] }` and records that the original live secret "is irrecoverable". A Terraform-only
replace of `random_id.tunnel_secret` is therefore a **no-op on the live tunnel**. A real
rotation is a tunnel replacement plus a web-2 rebuild, roll-forward only, with the deploy, CI
SSH and registry-push paths offline until it completes. **Rotating the tunnel does not affect
end-user traffic:** `app.` is an A record to web-1 (`dns.tf`) and only the `deploy.`, `ssh.`
and `registry.` hostnames use the tunnel. The tunnel therefore goes **last, in its own
window**, and only if the owner decides the weak ground is worth the outage of the
operator-facing paths.

## Determination

### Limb 1 — a breach of security: SATISFIED

Twelve secrets were rendered in cleartext into a stream that is public by construction. That is
a failure of the Art. 32(1)(b) confidentiality measure. It does not depend on anyone having
read the logs.

### Limb 2 — leading to unauthorised access to personal data: NOT ESTABLISHED

No reader of the logs is identified, and no use of any key is shown. The census (below)
establishes **where the values are**, which is a fact about exposure. It does not establish
that anyone looked. Art. 4(12) reaches "unauthorised **access to**" personal data, so the test
is what the keys **unlock** and whether anyone used them. The Inngest keys sit in front of the
execution plane that carries job and event payloads which can include user identifiers (the
2026-06-29 Inngest determination records the same data class for the same plane). The webhook,
ingest and trigger secrets let a holder inject or trigger, not read, and the Inngest signing
key's reach into payloads depends on the serve-route design, which this record does not
re-derive. Had use occurred, severity would not be negligible. As in 7797 and 8609, the
**likelihood** prong carries the conclusion, and it is not measured.

### The reachable class, stated precisely, and why this is the weaker case

7797 and 8609 were bounded by a small, named reachable class (the operator's own session, or
write collaborators and installed Apps on the repository). **This one is not.** Run logs of a
public repository are viewable by the public, or at least by any signed-in GitHub account, and
**which of those it is has not been verified** in this record. Treat the class as "any GitHub
account holder" until that is checked. The mitigating facts are only these: the values are
buried among tens of thousands of log lines per run; no external report, abuse signal or
unexpected use is known; and the values are keys to internal planes whose use leaves traces
the instruments in §Evidence limbs can look for. None of that is a measurement. The wider
class is why the evidence limbs matter more here than in 7797, and why E3 is recorded as
inconclusive by nature rather than as a gap to be closed.

### Art. 33(1) risk assessment, recorded in the alternative

| Limb | Assessment |
|---|---|
| Type | Confidentiality of credentials. Integrity engaged if a key was used to inject or trigger |
| Nature and sensitivity | Operational telemetry and job payloads on a small, operator-adjacent population. No special categories systematically |
| Ease of identification | Payloads can carry user identifiers. Not measured for this plane in this record |
| Severity | Non-trivial if used (trigger arbitrary functions, forge webhooks and ingest rows). Not engaged if unused |
| Volume | Not measured |
| Special characteristics | Alpha stage; operator-adjacent population |
| Likelihood of receipt by an unauthorised party | **Not measured, and not measurable for the reader limb.** Low is asserted, not shown |

**Result on the alternative framing: unlikely to result in a risk to the rights and freedoms
of natural persons, conditional on the likelihood limb, which is open.**

### Art. 34

Art. 34 requires a high risk and is a strictly higher bar. It is assessed on its own facts and
not inferred from the Art. 33 result. It is not reached: no breach is established, so no high
risk arises. If a limb flips, Art. 34 is re-run, not inherited.

## Evidence limbs (all PROVISIONAL, none certified clean)

**Discipline, carried over from the 8609 record and load-bearing.** No instrument may read,
print, copy or store a secret value or any log content. The 8609 record put
`gh run view --log` out of scope for its own limbs. This record needs a count of matches inside
logs, so it authorises **one narrow exception**: the log stream is piped straight into an
`awk` program that emits only job names and integers; the stream is never displayed, never
redirected to disk, and never held in a shell variable beyond the pipe. A legal record that
gathers a value has created a second copy of the exposure it assesses. An instrument that
cannot answer is recorded **UNAVAILABLE and the limb INCONCLUSIVE**, never clean.

| Limb | What it establishes | Instrument | Status 2026-10-29 |
|---|---|---|---|
| E1 | Which retained runs contain printed values, and in which job | counts-only run-log census (below) | RUN for 17 workflows, SAMPLED for 7, INCONCLUSIVE beyond the horizon and for earlier attempts of re-run runs. Needs a closing re-pull after Fix A merges (printing continued to 2026-10-29T07:37Z) |
| E2 | Whether any key was used by a party outside its holders | the signals below | NOT RUN, INCONCLUSIVE |
| E3 | Who viewed or downloaded the logs | none known to the CLO: no per-viewer log-access record for a public repository is known to be exposed to the owner (to be confirmed in the same check as the log-access rules) | NO INSTRUMENT, INCONCLUSIVE BY NATURE |
| E4 | Copies of the values outside the run logs | counts-only scan of issue bodies, comments, artifact names, step-summary writers | RUN FOR ISSUES; see §Copies outside the run logs |

### E2 — the use-of-key signals (named now; not run at the date of this record)

Each is a read of a trace the legitimate holders also leave, so each result needs the
legitimate pattern subtracted first:

- **Inngest:** runs with no app origin; serve-route signature anomalies (signature failures or
  successes from unexpected source); function runs triggered by an event nobody sent.
- **GitHub webhook:** delivery ids in the app's delivery log that do not appear in the GitHub
  App's recent-deliveries list.
- **Manual trigger:** `POST /api/internal/trigger-cron` calls with no matching dispatch in the
  `trigger-cron` skill history or a workflow.
- **Egress-audit and KB-drift ingest:** rows from a source that is not the same-host hop or the
  KB-drift walker.
- **Cloudflare:** the tunnel's connector list and the account audit log, for a connector or an
  event that does not map to web-1, web-2 or a CI runner.

Where an instrument is unavailable it is recorded **UNAVAILABLE, INCONCLUSIVE**.

### E1 — the run-log census

**Method.** The workflows that can print the values were found by reading the repository: every
workflow that runs `terraform plan`, `apply`, `refresh` or `show`, directly or through a
script, plus every workflow that dispatches such a job (including the `inngest-host`,
`inngest-host-replace`, `registry-host-replace` and drift jobs of `apply-web-platform-infra`).
Runs created on or after 2026-07-30 were listed (the 90-day retention horizon on 2026-10-29 is
2026-07-31). For each run, `gh run view <id> --log` was piped into `awk`, which counted lines
matching `\[id=` per job, and separately lines pairing a `random_id` address with a
value-shaped id (base64url, 16 characters or more). Only run ids, workflow names, job names,
timestamps and integers were kept. **No log text was displayed or stored.**

**Result (read 2026-10-29, counts only).** 17 workflows were enumerated in full, 1,433 runs
since 2026-07-30: 1,242 were read; 175 had no jobs and so have no log by construction
(cancelled or startup-failed before any job started); 16 had jobs but no readable log, 12 of
them created on 2026-07-30 or 2026-07-31 at the retention horizon, the other 4 unreadable for
a reason not established. **905 runs contain at least one `\[id=` line (116,505 lines), but
most of those are ids of resources that are not secrets (server, DNS and firewall ids).
686 runs contain at least one value-shaped `random_id` line (6,383 lines).** The earliest of
them is 2026-07-31T09:50Z (the horizon, so the true start is earlier and lost), and the latest
is **2026-10-29T07:37:03Z: the printing was still happening on the day of this record.**

| Workflow | Job | Runs with value lines | Lines | Which resources |
|---|---|---|---|---|
| `apply-web-platform-infra` | `apply` | 482 | 4,874 | nine of the twelve on every run (the six Inngest prd/dev keys and manual-trigger secrets, `github_webhook_secret`, `kb_drift_ingest_signing_key`, `tunnel_secret`); `egress_audit_ingest_token` in 102 of them |
| `apply-web-platform-infra` | `inngest_host` | 3 | 6 | the dedicated Inngest pair only |
| `apply-web-platform-infra` | `inngest_backstop_retire` | 3 | 33 | the dedicated pair plus nine of the others (all but `egress_audit_ingest_token`) |
| `apply-web-platform-infra` | `web_host_replace` | 13 | 13 | `tunnel_secret` |
| `apply-web-platform-infra` | `vector_redeliver` | 2 | 2 | `tunnel_secret` |
| `apply-deploy-pipeline-fix` | `apply` | 88 | 97 | `tunnel_secret` |
| `scheduled-terraform-drift` | `drift-check (apps/web-platform/infra)` | 89 | 1,314 | every resource except `egress_audit_ingest_token`, including the dedicated pair in about 55 of the 89 runs; latest run 2026-09-24T06:00Z |
| `inngest-provision-rehearsal` | `rehearse`, `teardown` | 6 | 44 | the **rehearsal root's own** throw-away keys, not production values (listed because the rule is "every `random_id` print") |

680 runs carry production values (503 + 88 + 89) and 6 carry only rehearsal values.
The `inngest_host_replace`, `registry_host_replace`, `git_data_host_replace`,
`git_data_host_create` and `registry_luks_recut` jobs of `apply-web-platform-infra` were read
too (28, 19, 16, 2 and 1 runs): their logs hold `[id=` lines but **no** value-shaped
`random_id` line (an inference from the job scopes, not a tested cause). The dedicated pair is
therefore exposed through `inngest_host`, `inngest_backstop_retire` and `drift-check` only.
No `random_id` value-shaped line was found in `apply-github-infra` (16 runs),
`apply-git-data-root-key`, `git-data-rung2-rehearsal` (17), `cutover-inngest` (44),
`git-data-cutover` (33), `registry-host-replace-dispatch` (24), `workspaces-luks-cutover` (3),
`workspaces-luks-verify` (95), `zot-image-mirror` (93), `inngest-link-flip` (4),
`inngest-host-state` (1), `registry-zot-inventory` (2) or `web-host-escrow-diagnose` (4).
Seven further workflows that mention `doppler run` or poll on a schedule were **sampled, not
enumerated** (`infra-validation`, `scheduled-prod-version-drift`, `scheduled-zot-restart-loop`,
`apply-delivery-gap-follower`, `apply-inngest-rls`, `restart-inngest-server`,
`diagnose-inngest-verify`; 58 runs sampled in total): no value-shaped `random_id` line in any
(`infra-validation`'s `plan (apps/web-platform/infra)` job prints `[id=` lines but no
`random_*` address in the 14 runs sampled). A sample proves nothing about the unsampled runs;
it is recorded as supporting, not as closure. 15 sampled `infra-validation` runs had no
readable log.

**Run ids.** The per-run table (run id, workflow, created_at, job, `\[id=` count,
`random_*` address count, value-shaped count) is held by the owner outside the repository and
regenerates from the method above. It is not committed: it is ids and integers only, but it is
a working file. The delete lists derived from it are 680 runs carrying production values, 6
rehearsal-only runs, and 2 further multi-attempt runs of in-scope workflows whose earlier
attempts were not scanned.

**Coverage limits.** Runs older than 90 days are gone; the exposure window before the horizon
is **INCONCLUSIVE for good**. GitHub caps a filtered run listing at 1000 results, so a
workflow with more than 1000 runs since 2026-07-01 was listed by date and the horizon checked
against the oldest run returned. A log that could not be read after three attempts is counted
as **unread** and never as clean. `gh run view --log` shows the latest attempt only: 11 runs
of the in-scope workflows have more than one attempt, and their earlier attempts were **not**
scanned. The census is a snapshot: printing continued to 2026-10-29T07:37Z, so a **closing
re-pull after Fix A merges** is required before the run-log limb can be closed.

### E4 — copies outside the run logs

Same discipline as E1: a `jq` or `awk` predicate evaluates the text inside the pipe and emits
only numbers, logins and timestamps. Candidates were the issues carrying the `infra-drift` or
`action-required` label (876 issues) plus every issue and pull request GitHub search returned
for a `random_id` resource address (577: 78 issues, 499 pull requests). Issue bodies, issue
comments and pull-request conversation comments were counted. **Not counted:** pull-request
review comments, commit comments, wiki, discussions, and the edit history of any body or
comment.

| Surface | Items with value-shaped lines | Lines | Notes |
|---|---|---|---|
| Public issue **bodies** | 74 issues | 641 | drift ledger issues; the body carries the refresh lines of one plan |
| Public issue **comments** | 234 comments on 38 issues, all by `github-actions[bot]` | 2,434 | created 2026-03-21 to **2026-10-29T06:02:11Z**; the newest are on the open drift ledger issue #10835, which the scheduled drift workflow comments on daily (16 comments since 2026-10-20) |
| Pull-request **comments** | 498 comments on 498 of 499 candidate pull requests, all by `github-actions[bot]` | 4,910 | created 2026-05-19 to 2026-09-23; that path appears to have stopped |

Across the labelled issue scan the values are few: **14 distinct values across the 12
resources**, one each except `tunnel_secret`, `inngest_signing_key_dedicated` and
`inngest_event_key_dedicated`, which have two (a superseded value in each case, which fits a
replaced state; an inference). The distinct-value count covers the issue scan only, not the
pull-request comments. The comment ids (732) and issue numbers are held with the run-id
tables outside the repository.

## Copies outside the run logs — a finding that changes the containment plan

Deleting run logs is **not** sufficient containment. The same values sit in **732 bot
comments and 74 issue bodies** of this public repository (§E4 above). The scheduled drift
workflow (`scheduled-terraform-drift.yml`) posts a plan output to a public issue (its own
comment in the workflow says so), and **the open drift ledger issue #10835 received a
`github-actions[bot]` comment carrying value-shaped lines at 2026-10-29T06:02Z**, consistent
with that workflow's daily run (the source workflow of the comment is inferred from the
author, the issue and the time, not read from the comment). The workflow's run logs had
stopped showing values (last value-shaped log line 2026-09-24). The
comment path and the log path are therefore two different surfaces, and a fix that redacts the
logs does not necessarily stop the comments. These issue bodies and comments are public, are
not subject to the 90-day horizon, can be indexed and cached by third parties, and keep their
edit history. The owner must decide, separately, whether to delete the comments, edit the
issue bodies and purge the edit history. The filing paths that wrote them (the drift ledger
comment and issue-body steps, and the historical pull-request plan comment, which appears to
have stopped on 2026-09-23) must be fixed in the same change as the log redaction, or the
next drift run writes the values again.

Static reading of the workflows: none of the infrastructure workflows uploads a plan or a
`terraform show` output as an artifact (the artifacts they upload are rehearsal evidence,
registry restore pins and suite logs); the one `GITHUB_STEP_SUMMARY` write that touches a
Terraform step carries a fixed disclosure text. Both are **static readings, not measurements**,
and the artifact listing endpoint for this repository returns HTTP 500, so artifacts are
recorded as **UNAVAILABLE at repository level, INCONCLUSIVE**.

## Sequence, and why the order is what it is

1. **Fix A, the redaction PR, first.** Printing must stop before anything else, or every
   later step is overwritten by the next run. It must cover the run logs **and** the drift
   issue filing path (see above).
2. **Census, then owner-authorised deletion of the retained run logs.** The census is the
   evidence and is taken first because deletion destroys it. Deleting the logs is
   **containment of the window only**: it shortens how long the values stay readable. It does
   not end the exposure, because a value read earlier stays usable, and it destroys the
   instrument that could show which runs carried which value. The census counts are recorded
   here before any delete.
3. **Rotation route, then owner-gated rotation.** Rotation is what ends the exposure
   (a past exposure stops mattering from the rotation on; it is not remediated by it). The
   rotation route is built and reviewed first; each rotation is then an owner decision.
4. **`tunnel_secret` last, in its own window**, for the reasons in §The fact pattern.

None of the deletions or rotations is performed or authorised by this record.

## Notification — controller decision recorded 2026-10-29

**No notification is made at this date, and none is owed on the facts established to date.**

- **Art. 33(1)** — no duty. Reachability without evidence of use is not an Art. 4(12) breach.
- **Art. 33(2)** — not engaged on these facts (no personal-data breach is established).
- **Art. 34** — no duty. No breach is established, so no high-risk assessment arises.
- **Art. 33(5)** — **owed, and discharged by this record and its register row.**
- **Data Protection Disclosure §7.2 and the alpha annex §8.1** — **not engaged**, unless and
  until a personal-data breach is signed. Their notice promises are conditioned on "a breach".

## If the finding flips

If E2 (or any other source) surfaces evidence of **use** of an exposed key by a party outside
its holders, or the census shows a value outside the places this record knows about:

1. A **FRESH 72h Art. 33(1) clock** starts from awareness of that evidence. It does not run
   from 2026-10-27.
2. Art. 33(2) processor notification to affected controllers is assessed (the alpha-tester
   position in the 2026-08-06 determination), and **DPD §7.2 and annex §8.1 engage** for
   affected Users once a personal-data breach is signed.
3. **Art. 34 is re-run, not inherited.**
4. External counsel re-review is triggered.

## Conditions and residual actions

- **REQUIRED — Fix A before any other step** (§Sequence).
- **REQUIRED — the census is recorded here before any run log is deleted.**
- **REQUIRED — the drift-issue copies** are an owner decision, taken with the redaction change.
- **REQUIRED — verify GitHub's log-access rules** for public repositories (who can view and
  download logs, with and without sign-in) and record the answer in an addendum. Until then
  the reachable class is "any GitHub account holder".
- **REQUIRED — CTO confirmation** of the capability column and of the tunnel statements above.
- **CONDITIONAL — E2** is run before the keys are rotated where an instrument's trace would be
  reset by the rotation, and in any case before this record is closed.
- **PROCESS — register cross-reference.** Indexed at
  `knowledge-base/legal/breach-register.md`. The index is a pointer, not a copy: this file is
  canonical.

## Amendment convention

This record is **append-only** after merge. A limb result, a changed disposition, a notice
decision or a correction is added as a dated addendum below. The addendum cites the text it
annotates and amends nothing above it, and a superseded sentence gets a
`> **Superseded <date> (#N): …**` marker beneath it. Code and records are cited by function,
constant, section or anchor name, never by line number.
