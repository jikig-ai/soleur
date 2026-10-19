---
date: 2026-10-20
topic: art30-trigger-actuation
---

# Art. 30 re-verification trigger actuation

Tracked on #7893. Draft PR #10620. Branch `feat-7893-art30-trigger-actuation`. Tagged user-brand-critical (auto, per #5175). Lane `cross-domain`. This document is an internal draft. It is not a counsel-review attestation, and it does not change the compliance-posture row from "prose, not actuated" to "actuated."

## What We're Building

A blocking pull-request gate for the closed re-verification list on Processing Activity 8 §(f) of the Article 30 compliance register. The first slice actuates re-verification triggers 2, 4, and 5. Triggers 1, 3, 6, and 7 stay on #7893 with class `unactuated`. The slice is partial actuation of 2, 4, and 5. #7893 and the compliance-posture Active Items row stay open.

The defect #7893 names is still true on this branch. The compliance-posture row (Active Items, the cell that cites #7893) says the defect is the control: every re-verification trigger is still prose plus a register cell, and nothing fails when an anchor changes without a dated review entry. PR #7881 repaired the prose. It did not actuate the list.

"Register" in this document means the compliance artifact `knowledge-base/legal/article-30-register.md`. "Re-verification trigger" means one numbered item on that closed list. The list lives in `knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md` under "### Re-verification triggers" and is mirrored, with different predicates for items 3 and 4, in the PA-8 §(f) cell.

## User-Brand Impact

- **Artifact:** the Article 30 compliance register's PA-8 §(f) re-verification control, and the published privacy-policy retention sentences a data subject reads (`docs/legal/privacy-policy.md`, the operational-log retention bullet that states journald `SystemMaxUse=1G` and Better Stack 90 days).
- **Vector:** silent failure. The statutory record and the published policy can show a log-retention mechanism the product no longer uses, so one data subject, a regulator, or the operator relies on a false account.
- **Threshold:** `single-user incident`.
- **If this lands broken, the user experiences:** a privacy-policy retention sentence, and the Article 30 cell behind it, that describe a log-retention mechanism the running container no longer uses.
- **If this leaks, the user's data is exposed via:** no new collection. The harm is a false retention account. The gate reads git diffs of named config files. It does not read log bodies.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one data subject shown a false retention period is enough. The historical miss (#4786, 2026-06-02, corrected 2026-09-07) left the published sentences wrong for about three months.

## Why This Approach

The product outcome is the whole closed list. Done means re-verification triggers 1, 3, 6, and 7 actuate as well as 2, 4, and 5, and the published retention sentences are part of that shown answer. An in-repo slice may land first only while #7893 and the posture row stay open and the slice is not called done.

### Approach A: Named partial (chosen)

One new machine-readable manifest is the only predicate and anchor copy. A new blocking check fails the pull request when an in-scope anchor diff lacks an added review hunk in the PA-8 §(f) cell. The check covers triggers 2, 4, and 5. Ids 1, 3, 6, and 7 are present on the manifest with class `unactuated`. The allowed claim is partial actuation of 2, 4, and 5.

**Pros:**

- It would have failed the #4786 class of miss: a `docker run` flag change at the app-container invocation while the old anchor watched `daemon.json`.
- It is born blocking. The same pull request carries the review entry.
- It does not describe a path gate as the closed list.

**Cons:**

- Calendar review (1), the trigger-3 predicate, and the Better Stack source checks (6 and 7) remain unaudited by this gate.
- A comment-stripped flag match inside the two watched files can fire on a later non-app `--restart` in those files. A new file that launches `soleur-web-platform` with `--log-driver journald` will not fire. Both gaps are named.

**Best when:** the in-repo miss is the one this control can see today, and the rest of the list stays an open issue with an honest claim.

### Approach B: Call the in-repo gate done (rejected)

Ship the path gate, close #7893, and clear the posture residue.

The product outcome rejects this. A path gate cannot see the annual date, a vendor-console retention edit, or a new Better Stack source. Calling that the closed list would be a new false accountability claim. The compliance-posture row stays as written.

### Approach C: Narrow the closed list, or wait for every control (rejected)

Drop 1, 3, 6, and 7 from the ask, or refuse every in-repo gate until a calendar control, a vendor client, and a trigger-3 predicate exist.

Dropping what #7893 asked for would be an operator scope change, and the evidence does not force a drop. Waiting leaves the #4786 class unguarded. A vendor check on the pull-request path fails unrelated pull requests during an outage, or it fails open. Sequencing 1, 3, 6, and 7 on the open issue is the remainder.

Phase 1.2 asked the operator nothing. The open branches were technical or legal posture. The CTO re-ruled them on 2026-10-20. The CLO posture from the same brainstorm stands. No money, scope drop, or legal-risk acceptance remains.

## Key Decisions

- **Slice.** Ruled by CTO agent, 2026-10-20: the first slice is a blocking partial actuation of re-verification triggers 2, 4, and 5. Triggers 1, 3, 6, and 7 stay class `unactuated` on #7893. The issue and the compliance-posture row stay open. The slice is not called done, and 1, 3, 6, and 7 are not a non-goal of #7893. Dissent: a partial gate can still be shown as if it were the register's answer, so a merge that closes #7893, clears the posture row, omits an invocation site, ships advisory, or says the closed list is actuated is a failed slice.
- **One predicate copy.** Ruled by CTO agent, 2026-10-20: one new machine-readable manifest is the only predicate and anchor copy. The runbook points at it when its wording changes. The Article 30 compliance register remains the record and may render the list. For as long as numbered enumerations remain, the only prose check is id-set equality of {1..7}. Compliance-posture cites numbers only. Sentence parity is not actuation: the two copies already disagree on items 3 and 4, and the trigger-2 miss was the wrong anchor (`daemon.json`), not a count mismatch. Dissent: id-set equality stays green when both enumerations share the same wrong anchor, which is why it is the closure check only.
- **Review entry.** Ruled by CTO agent, 2026-10-20: when an in-scope predicate fires, the same pull request adds a hunk in the PA-8 §(f) retention cell containing a non-empty `YYYY-MM-DD` date, every fired id, and some non-whitespace statement beyond that date and those ids. The gate checks that shape in the added hunk only. Passing it is not Art. 5(2) demonstrated. Automation does not write the entry, mark FIRED, or advance a next-due date. A date already in the cell, a pull-request comment, a runbook "reviewed" sentence, a retroactive FIRED mark, and a manifest or compliance-posture edit while §(f) is untouched do not pass.
- **Who writes the entry.** Ruled by CLO agent, 2026-10-20: the human entry carries the date of this review, who reviewed and in what role, which id fired and which anchor moved, the retention-relevant before and after, the Art. 30(1)(f) conclusion (the mechanism still holds, or this pull request updates it, or `NOT RECORDED` still holds and which bound governs), and whether the cell was amended or expressly confirmed. The gate does not search for those elements. For a Better Stack review, which this slice does not actuate, the entry would also carry the source id, the measured `logs_retention`, and the measurement date. The product outcome puts one more fact inside that before-and-after: whether the published privacy-policy retention sentences still match. The gate does not open `docs/legal/` and does not grade that sentence. Dissent: a non-empty sentence can still lack a real before and after. That gap stays with the human entry.
- **Trigger 3 and the flag check.** Ruled by CTO agent, 2026-10-20: id 3 stays class `unactuated`. The gate does not choose between the runbook's shipper-introduction wording and the register's "any change to `apps/web-platform/infra/vector.toml`." Triggers 2 and 4 are one check: an added or removed line in `apps/web-platform/infra/cloud-init.yml` or `apps/web-platform/infra/ci-deploy.sh` whose first non-whitespace character is not `#`, matching CLI `--log-driver`, `--log-opt`, or `--restart` in space form or `--flag=value`. `--log-driver` or `--log-opt` fires {2, 4}. `--restart` alone fires {4}. `daemon.json` keys are not trigger 2. Trigger 5 is any diff to `apps/web-platform/infra/journald-soleur.conf`, including `SystemKeepFree=` and `RuntimeMaxUse=`. The check does not claim the shell, unit, or TOML grammar is closed, and it does not crawl every `--log-driver` in the repo. A manifest-only edit does not exempt the guard. A manifest edit that drops a watched site, points 2 or 4 at `daemon.json`, or marks 1, 3, 6, or 7 `actuated` fails. Dissent: a later new file that runs the app container with `--log-driver journald` will not fire. A later v2 for a new shipper filename under `apps/web-platform/infra` is still not this slice, and it would still miss a new source block inside an already-watched file.
- **Current invocation sites (coordinates, not anchors).** App container: `cloud-init.yml` names `soleur-web-platform` with `--log-driver journald` and `--restart unless-stopped`. `ci-deploy.sh` names `soleur-web-platform-canary` with `--log-driver journald` and `--restart no`, and names `soleur-web-platform` with `--log-driver journald` and `--restart unless-stopped`. Comments in those two files that mention the flags, including the memory-cap comment in `ci-deploy.sh`, are not invocations. `cloud-init.yml` still writes `"log-driver": "json-file"` in `daemon.json`. Other `--log-driver journald` runs (registry host `cloud-init-registry.yml`, `egress-gateway-bootstrap.sh`) are outside this list. `journald-soleur.conf` holds `SystemMaxUse=1G`, `SystemKeepFree=2G`, and `RuntimeMaxUse=200M`.
- **What the gate does not become.** It is a new blocking check. It is not an edit to `scripts/lint-legal-registers.sh`, `scripts/lint-legal-scope-block-placement.sh`, `scripts/lint-legal-mirror-drift-baseline.sh`, or `scripts/probe-legal-corpus-truth.sh`. It does not extend `scripts/generate-article-30-register.sh` or turn `scripts/lib/betterstack-sources.sh` into the manifest. It reuses `legal_resolve_base` (exit 2 when the base cannot be decided) and does not add a second base-ref resolver or a second normaliser. Diff construction follows the `enforce` job in `.github/workflows/pr-quality-guards.yml`: three-dot against the base, `MERGE_GROUP_BASE_SHA` on `merge_group`, and a hard failure when that base is empty. That job's surface list is the DSAR export files only, so it does not already cover these anchors. #7892 stays a separate tracker. Flow 2 stays dormant. Journald `NOT RECORDED` is not replaced with a computed duration. The gate does not read log bodies. `soleur:gdpr-gate` runs at plan Phase 2.7 because the brand-survival threshold is `single-user incident`, and again at work Phase 2 exit if the diff grows a regulated-data surface or reads log bodies.
- **No new spend.** Better Stack stays the existing vendor line. No new client, credential, or poll is in this slice. The author of an anchor diff cannot satisfy the control from outside the PA-8 §(f) hunk. The dated in-cell change is written by the person reviewing in the legal role, in that same pull request.
- **Productize Candidate: `closed-list-actuation`.** The recurring shape is a closed numbered list whose machine-readable manifest fails a pull request that moves an anchor without a same-diff review entry. This brainstorm does not build that skill. The candidate is a follow-up issue and does not carry triggers 1, 3, 6, or 7 off #7893.
- **No UI.** Phase 3.55 does not apply. There is no page, component, or mail template.

## Open Questions

- Trigger 3's predicate wording, when a later control on #7893 actuates id 3. The gate must not pick it by parsing either prose copy. `(later control on #7893)`
- The mechanism for the annual review (1) and the Better Stack source checks (6 and 7). A pull-request path gate cannot see them. A separate scheduled compare of `GET /api/v2/sources` for team `520508` was noted as a possible later control and is not designed here. `(later control on #7893)`
- The sentence that points the runbook at the manifest, if the implementation pull request edits that section. That sentence is CLO wording. The gate checks id-set equality while the numbered enumerations remain, and it does not parse the sentence. `(CLO wording at plan)`

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

Marketing, Sales, Finance, and Support were assessed and omitted. This is an operator-facing CI and compliance control, with no campaign, no pipeline motion, no support surface, and no new spend. Finance's omit is that no new spend was found, not a missing finance review.

### Product

**Summary:** Done is the whole closed list, including 1, 6, and 7, and trigger 3 is part of that outcome. The published privacy-policy sentences are part of the shown answer. An in-repo slice may land first only while #7893 and the posture row stay open and the slice is not called done. Narrowing the list to what a path gate can see, or calling that gate the list, fails the outcome.

### Legal

**Summary:** Internal draft, not advice, and not an attestation. A forced ISO date does not demonstrate Art. 5(2). The copies disagree today: register item 3 is any change to `apps/web-platform/infra/vector.toml` (FIRED 2026-06-02, #4786); the runbook item 3 is introduction of promtail, vector, fluent, filebeat, or rsyslog. Register item 4 is a container restart-policy change affecting the log path; the runbook item 4 names `--restart`, `--log-driver`, or `--log-opt`. `promtail` and the eighth-item closure sentence are absent from the register cell. The closure sentence is runbook-only: adding an eighth re-verification trigger updates the PA-8 §(f) row and the runbook in the same pull request. One manifest is the predicate copy. The honest claim for this slice is partial actuation of 2, 4, and 5. Changing the posture row to "actuated" needs its own attestation. Do not read log bodies. Do not replace `NOT RECORDED` with a computed duration.

### Engineering

**Summary:** The re-ruling on 2026-10-20 is Items A through D in Key Decisions. The hit predicate is a closed, comment-stripped flag match on the two app-container files, plus any diff to `journald-soleur.conf`. It is not a repo-wide denylist, and it does not claim to close host edits, unit syntax, or TOML. No existing script diffs an anchor and demands a review entry. No machine-readable copy of this list exists outside Markdown. `logs_retention` appears under `knowledge-base/` only.

### Operations

**Summary:** No new vendor and no provisioning. The cost is delay on the infra pull request that touches an anchor, until the PA-8 §(f) hunk is in that diff. Annual "next due 2027-05" and the vendor checks have no writer that amends PA-8 today. `scheduled-expenses-verify-by.yml` and the follow-through sweeper are the wrong shape. #7893's 2026-12-07 re-assess is also unenrolled. Watching all of `ci-deploy.sh` is the wrong direction. The written check is the flags. No capability gap: the missing piece is this gate, not a platform primitive.

## Next Steps

→ `/plan` #7893. Spec: `knowledge-base/project/specs/feat-7893-art30-trigger-actuation/spec.md`. The implementation pull request must not use a closing keyword for #7893.
