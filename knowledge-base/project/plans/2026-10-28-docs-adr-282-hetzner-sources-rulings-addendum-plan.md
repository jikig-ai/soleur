---
title: "docs(adr): ADR-282 second addendum 2026-10-28, Hetzner sources read, CTO and CLO rulings, owner-side asks"
date: 2026-10-28
slug: adr-282-hetzner-sources-rulings-addendum
branch: feat-one-shot-9927-adr-282-hetzner-sources-rulings-addendum
issue: 9927
type: docs
lane: single-domain
---

# docs(adr): ADR-282 second addendum 2026-10-28, Hetzner sources read, CTO and CLO rulings, owner-side asks

Detail level: MINIMAL. Docs only; one append to one file. PR #11434 (draft). Work item 7(c) of the Inngest LUKS epic #9927. `Ref #9927` and `Ref #10112` only; no closing keyword in the PR title or body. Standing rules: read-only (no Hetzner or Doppler write, no terraform apply, no host replace); CI is the gate (owner decision 2026-10-27); never print values, diffs or personal data; technical forks go to `soleur:engineering:cto`, legal forks to `soleur:legal:clo`, never to the founder.

## Overview

Append ONE section, `## Addendum - 2026-10-28 (#9927), second`, at the end of `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (today it ends with the first `Addendum - 2026-10-28 (#9927)` block, last line the "Owner-side follow-ups" paragraph). Append-only (0 removed lines), status stays `accepted`, no new ordinal, no edit to any earlier addendum or dated cell. The section records four things, each with an evidence class (measured / documented, not measured / not measured) and a date:

1. The five sources the 2026-10-23 addendum lists as unread, read on the work-phase fetch date: Hetzner terms and conditions, Hetzner projects documentation, Hetzner Cloud changelog, Terraform hcloud provider documentation on delete protection, and the same documentation on project deletion. Per source: what it says (short verbatim quotes) about project deletion, account closure or suspension, retention after closure, and delete protection; a source that cannot be fetched is recorded as "could not fetch, not measured".
2. `Ruled by CTO agent, 2026-10-28:` follow-up (d) (off-project ciphertext copy) deferred, not declined, with its trigger; the epic item 4 flip-token design gap; the standing status of items 2 and 3.
3. The CLO draft ruling of 2026-10-28 (v1 internal attestation, not legal advice) with build conditions and unanswered facts.
4. The two owner-side follow-ups that stay owner-only and not started, with the capture checklist and the written support question.

The rulings are inputs. The CTO and the CLO are NOT re-run here.

## Enhancement Summary

**Deepened on:** 2026-10-28 (light pass; docs-only, every fact pre-measured). No domain, skill or review agent fan-out was spawned: the change is one append to an internal ADR, the CTO and CLO rulings are inputs, and extra agents add cost without recall. Plan-review panel not run: one file, no mechanism to cut; the Property List and Cut List carry that question.

**Halts checked.** 4.6 User-Brand Impact present, threshold `none` with scope-out (the ADR path is not in the sensitive-path regex). 4.7, 4.9, 4.11, 4.13 not triggered (no code, UI, guard or autonomous task). 4.8 PAT sweep: no hits. 4.10 not triggered: the plan introduces no store or connection (it records a deferred, unbuilt one). 4.12 Scope Check present once (unfenced), no `unmapped` row, Split Assessment has a Recommendation line.

**Verified live this pass.** Rule ids cited exist in `AGENTS.md` (`cq-cite-content-anchor-not-line-number`, `cq-assert-anchor-not-bare-token`). PRs #11260, #11414, #10889, #10524 are MERGED. Baseline on the untouched ADR: `bash scripts/markdown-lint.sh <ADR>` prints "1 file(s) clean." and `bash scripts/check-adr-ordinals.sh` passes, so a later red is attributable to the append. Collision pre-check for #9927: open PRs naming it are #11434 (this one), #11427 (key-probe alert window) and #11381 (inngest@4 upgrade); `gh pr diff --name-only` shows neither of the other two touches the ADR-282 file. Open code-review overlap on the ADR path: none (200-issue snapshot).

**New considerations from this pass (folded into the sections below).**

- **Owner-only classification (`hr-never-label-any-step-as-manual-without`).** The brief assigns follow-ups (b) and (c) to the owner. Basis recorded for the addendum: the Hetzner console member list has no API endpoint (first 2026-10-28 addendum, "console only"), and the console sits behind login and sign-in protection, which is credential entry; the support question must be sent from the owner's Hetzner account. A browser attempt was NOT made at plan time (the browser MCP servers failed to connect in this session), so the addendum must say "classified owner-side by the invoking brief and the first 2026-10-28 addendum", not "verified unautomatable". Do not strengthen it.
- **Hook pitfall.** The plan-write guard blocked the first draft of this file because it reproduced a Doppler secret-write command string from `flag_set`. The ADR text must also cite `flag_set` by function name and effect ("writes `INNGEST_CUTOVER_FLIP` under the host token"), never the command line.
- **Two heading styles coexist.** Older addenda use an em dash; the 2026-10-26 and first 2026-10-28 headings use a hyphen. The new heading uses the hyphen exactly as briefed (`## Addendum - 2026-10-28 (#9927), second`).
- **Provider-doc sentence scope.** The index "Delete Protection" sentence about the provider lifting the lock concerns Terraform destroy; it is the repo's own design premise and not evidence about Console project deletion (already in Sharp Edges).

## Research Insights

**Premise Validation (Phase 0.6, run 2026-10-28, plan time).** Cited issues, checked with `gh issue view <n> --json title,state` (titles only): #9927 OPEN; #10112 OPEN; #8528 OPEN ("legal: Art. 17 erasure reaches neither copy of the Inngest Redis AOF ... CLO determination on processing scope"); #7671 OPEN ("legal: the LUKS-header R2 bucket (Cloudflare US custody) appears in no Art. 30 activity"); #6890 CLOSED, NOT_PLANNED, closed 2026-10-24T18:48:10Z ("hardening: split write capability off the deploy-readable Inngest boot token (root-only flip token via systemd drop-in)"); #11266 OPEN (owner hold, probe delivery); #11265 OPEN (standalone keeper at the next host replace); #10889 MERGED; #11414 MERGED (first 2026-10-28 addendum); #10524 MERGED (item 5). Collision pre-check for the ADR path is repeated at deepen time. No premise was stale.

**Claims in the brief verified against the repo or the issue (each must be re-verified by the work phase before the sentence is written):**

| Brief claim | Reality at plan time | Plan response |
|---|---|---|
| #9927 body carries item 1b, edited 2026-10-28 | Body has "Added 2026-10-28 (CTO and CLO rulings)", item "1b ... Deferred, not declined", trigger "2027-01-08; a Hetzner written answer ...; the next planned `apply_target=inngest-host-replace`"; issue `updatedAt` 2026-10-28T17:33:25Z. | Cite "item 1b of the #9927 body (edited 2026-10-28)". Do NOT edit the body. |
| Item 3 declined by CTO 2026-10-15 | #9927 triage comment of 2026-10-15, row 3: "DECLINED (automation)", "Ruled by CTO agent, 2026-10-15: a repair route is a new key-writing path ...; keep the runbook's escalate-to-owner route". | State as recorded; cite the comment date. |
| Item 4 needs a flip-token design | `apps/web-platform/infra/inngest-cutover-flip.sh`, function `flag_set()` (about line 265): it writes `INNGEST_CUTOVER_FLIP` into the soleur-inngest prd config through the Doppler CLI, and its comment says the scoped soleur-inngest boot token (`DOPPLER_TOKEN`, EnvironmentFile) authorizes the write. `inngest-host.tf` (about line 279) `resource "doppler_service_token" "inngest"` has `access = "read/write"`. | Cite by function name and anchor text, not only line number (`cq-cite-content-anchor-not-line-number`). "Unless the flag is terminal or the write is split off" is the CTO's wording; record it as ruled, not as a repo fact. |
| #6890 (split-token tracker) auto-closed NOT_PLANNED on 2026-10-24 | Confirmed: CLOSED, NOT_PLANNED, 2026-10-24T18:48:10Z. | Say "closed NOT_PLANNED on 2026-10-24"; do not say who or why (not read). |
| "Item 2 header repair blocked behind the host replace and the CLO-gated header backup" | Item 2 (probe) is merged (#11260), delivery is the owner hold #11266, the standalone keeper is #11265 at the next host replace; the ADR's 2026-10-26 addendum says "'No recovery' in the loss-mode table stands until the legal-gated header backup ships". There is no header repair route in the repo. | Write: item 2 ships detection only; any header repair route needs the host replace (#11265) and the CLO-gated header backup (item 1). Reconciliation noted; do not invent a repair mechanism. |
| Art. 30 register and DPD 6.4 already treat R2 as a US-importer Chapter V transfer | `knowledge-base/legal/article-30-register.md` (CLA archive row, cell (e)): "Cloudflare Inc (R2 object custody) — third country: the United States ... Chapter V transfer irrespective of where the objects rest". `docs/legal/data-protection-disclosure.md` section 2.3(n): "the `WEUR` location hint is a placement preference, not a jurisdictional restriction -- see Section 6.4"; its sub-processor row says "Held by Cloudflare, Inc. (US) -- DPF + SCCs + CBPR, see 6.4". Section 6.4 itself lists Cloudflare (CDN) under DPF and SCCs and does not name R2. | Cite the Art. 30 cell (e) and DPD 2.3(n) plus the 6.4 Cloudflare line, by anchor text. Do not say "6.4 names R2". |
| CLO 2026-10-15 conditions for header-only copy | #9927 triage comment 2026-10-15, row 1: "separate EU bucket and token (never tfstate, Doppler or anything holding the passphrase), write-only host credential, retain only the current header ...". | "Header-only stays permitted on the 2026-10-15 conditions" is recorded as ruled; the premise correction (R2 is not an EU provider) is recorded next to it as ruled. |

**Pre-research reachability probe (read-only, 2026-10-28, plan time; the work phase MUST redo the reads and cite its own fetch date, counts and quotes).** HTTP status and size only, no content recorded:

| Source | URL | Probe |
|---|---|---|
| Terms and conditions | `https://www.hetzner.com/legal/terms-and-conditions/` | 200; the page text has 0 occurrences of "project", 15 of "terminat", 1 of "suspen" (a spam clause). It is the general Hetzner Online T&C; read the termination and data-after-termination clauses and record exactly what they say, including that they may not mention Projects or Volumes. |
| Projects documentation | `https://docs.hetzner.com/cloud/general/faq/` (section "What are Projects and how can I use them"). No dedicated Projects page exists at `/cloud/projects/overview/` (404), `/cloud/general/projects/` (404), `/cloud/general/overview/` (404) | 200. A WebSearch summary says the FAQ lists four roles (Owner, Admin, Member, Restricted) and that no page on deleting a project turned up. A search summary is NOT a source: the work phase fetches the FAQ and quotes the role text itself, or records "not found in the page read". Record the FAQ under this row as the projects documentation and say in one clause that the 2026-10-23 addendum had used it for a narrower question. |
| Cloud changelog | `https://docs.hetzner.cloud/changelog` | 200, about 800 KB of a client-rendered page. Plain tag stripping is noisy; use WebFetch with a targeted prompt (project, delete protection, account) and, if that fails, record "could not fetch, not measured". `https://docs.hetzner.cloud/whats-new` also exists. |
| Terraform hcloud provider, delete protection | `https://raw.githubusercontent.com/hetznercloud/terraform-provider-hcloud/main/docs/index.md`, section "Delete Protection"; `docs/resources/volume.md` and `docs/resources/server.md` (`delete_protection` argument, "(Optional, bool)"); registry page `https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/volume` returned 200 | Index section reads (plan time): the API allows protecting resources "by putting a 'lock' on them"; "this does not protect deletion from Terraform itself, as the Provider will lift the lock in that case"; it points at `prevent_destroy`. That matches the ADR (the guards, not the flag, defend against Terraform). |
| Terraform hcloud provider, project deletion | `docs/resources/` directory listing via the GitHub contents API (public) | 28 resource files (certificate, firewall, floating_ip, load_balancer, network, primary_ip, server, snapshot, ssh_key, storage_box, volume, zone and similar); no file named `project`. The statement to record is "no project resource in the provider's `docs/resources` listing on the fetch date", an absence claim scoped to that listing. |

**Property List (Phase 0.6b).** (P1) A reader of the ADR can see, per previously unread source, what it said about project deletion, closure or suspension, retention and delete protection, with date and short verbatim quotes, or that it could not be fetched. (P2) The CTO and CLO rulings of 2026-10-28 are on the record in the ADR with the exact triggers and conditions, so the decision does not live only in an issue body. (P3) No sentence claims protected resources survive, or block, a project delete or account closure unless a read source says so. (P4) The owner-side asks (b) and (c) are written down ready to use (checklist and support text), marked owner-only and not started. (P5) Every unmeasured item stays listed as unmeasured.

**Cut List.** (a) A new ADR ordinal: P1 to P5 are served by a second addendum; the 2026-10-26 and first 2026-10-28 addenda set the precedent (no ordinal, `accepted` unchanged). (b) Editing the first 2026-10-28 addendum's "Owner-side follow-ups" paragraph to mark (1) and (2) as carried here: cut, append-only; the new section points back instead. (c) Editing the `inngest-server.md` runbook "no known access" A6 row: out of file scope; the addendum only names that the owner check supplies that list. (d) A new tracking issue for follow-up (d): cut, it is already tracked in the #9927 body item 1b (edited 2026-10-28) which this task must not edit again. (e) Re-running the CTO or CLO: cut, rulings are given.

**Learnings applied.** Evidence-class vocabulary and "not found in the pages read, never 'Hetzner has no such behaviour'" from the 2026-10-22 and 2026-10-23 addenda. Cite code by anchor text, not line number (`cq-cite-content-anchor-not-line-number`). Absence claims name the exact listing or page searched (`cq-assert-anchor-not-bare-token`).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; the engineering record could overstate what Hetzner documents about project deletion, or misstate a legal ruling, and a later build or no-build decision on an off-project copy of the sole-copy Inngest store could rest on it.
**If this leaks, the user's data is exposed via:** no vector; the addendum quotes public Hetzner text, repo paths and issue numbers; no token value, account id, member name or email, personal data or diff.
**Brand-survival threshold:** none. threshold: none, reason: documentation-only append to an internal ADR that quotes public vendor text and records already-given rulings, and names no credential, person or account.

## Implementation (single phase, `soleur:work`)

Work from this worktree only. Keep fetched page text in the scratchpad, never in the repo.

1. **Read the five sources** (table above). Order: T&C, FAQ projects section, changelog, provider index "Delete Protection", provider resource listing plus `volume.md`. For each, WebFetch (curl for raw GitHub files is acceptable) and write down, from the page text only: (i) project deletion, (ii) account closure or suspension, (iii) retention after closure, (iv) delete protection; each cell is a short verbatim quote (about 25 words max) or the words "not found in the page read". Record the fetch date (the real date of the work run), the URL and, for the T&C and FAQ, the section heading. If a fetch fails or returns a shell page with no readable text, write "could not fetch, not measured" for that source. Do not infer across sources: a quote about deleting a server is not a quote about a project. If a source says protected resources do or do not block a project delete, quote it and label it documented, not measured; otherwise write nothing that implies either.
2. **Re-verify the repo facts** the rulings cite (premise table above) at work time: the `flag_set` anchor and the read/write token resource, #6890 state, #8528, #7671, #11266, #11265 titles and state, the 2026-10-15 triage comment rows 1 and 3, the #9927 body item 1b text (read-only `gh issue view 9927 --json body`; print only the lines needed, do not edit it).
3. **Append the addendum** (draft shape below) to the end of the ADR. Target about 45 to 60 lines. No em dashes in new prose (match the 2026-10-26 and first 2026-10-28 headings: hyphen, not em dash). Heading exactly `## Addendum - 2026-10-28 (#9927), second`. Use the vocabulary "measured", "documented, not measured", "not measured", "could not fetch, not measured".
4. **Local checks** (cheapest first; CI is the gate; rc 6 is not a pass):
   - `bash scripts/markdown-lint.sh knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`; if it refuses to run, state that and leave it to the CI markdownlint job, do not substitute an unpinned runner.
   - `bash scripts/check-adr-ordinals.sh`.
   - `bash plugins/soleur/test/sole-copy-drift-check.test.sh` (reads the ADR for `Hetzner id 106903269`; an append cannot break it, run to confirm).
   - `bash apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh` (the ADR path is in `infra-validation.yml`'s PR path list; it pins `**UNVERIFIED first.**`, untouched).
   - Append-only proof: `git diff origin/main -- <ADR> | grep -c '^-[^-]'` returns 0; `git diff --stat origin/main...HEAD` shows only the ADR and files under `knowledge-base/project/{plans,specs}/`.
   - Leak check on the added lines: no token shapes, no email addresses, no `@` mentions.
5. **PR #11434 body** (rendered by `soleur:ship`; do not post comments from this phase): lists Measured (with dates) and Not measured separately, `Ref #9927`, `Ref #10112`, no closing keyword (a grep for close/fix/resolve followed by `#` over the body returns nothing), a short block repeating the support-question text and the capture checklist for the owner, and a line that #9927 stays open. Nothing is posted to #9927 from the work phase.

### Draft shape of the addendum (wording is the implementer's; every fact comes from step 1 or 2, and bracketed items are filled from the work-phase reads)

```text
## Addendum - 2026-10-28 (#9927), second

Appended; nothing above is edited and the status stays `accepted`. No new ordinal. Follows the first 2026-10-28 addendum (#11414). The five sources the 2026-10-23 addendum lists as unread were read on [work date] (public pages and files only; no Hetzner API call with a credential, no console access, no write, no live test). Evidence classes as in the 2026-10-22 addendum.

| Source (URL, section) | Project deletion | Account closure or suspension; retention after closure | Delete protection | Evidence class | Date |
| Terms and conditions | "[quote]" or not found in the page read | "[quote]" ... | "[quote]" or not found | documented, not measured / could not fetch, not measured | [date] |
| Projects documentation (cloud FAQ, "What are Projects ...") | ... | ... | ... | ... | [date] |
| Cloud changelog | ... | ... | ... | ... | [date] |
| Terraform hcloud provider: delete protection (index section, volume and server resources) | n/a | n/a | "[quote: lock; does not protect deletion from Terraform itself]" | documented, not measured | [date] |
| Terraform hcloud provider: project deletion (resources listing) | [no project resource in the listing on [date]] | n/a | n/a | documented, not measured | [date] |

Result paragraph: [one sentence stating whether any source says protection blocks, or survives, a project delete or account closure; if none does, say none of the five does, and that the 2026-10-23 planning posture and the accepted residual stand]. Claim limits: "documented" means the text exists on the date read, not that Hetzner behaves so.

Ruled by CTO agent, 2026-10-28: follow-up (d), an off-project copy of the volume's ciphertext, is deferred, not declined. A header-only copy does not help a project loss, because the ciphertext dies with the project; header plus ciphertext does. Trigger, the earliest of: 2027-01-08; a Hetzner written answer that delete protection does not survive a project delete or account closure; the next `apply_target=inngest-host-replace`. Tracked in the #9927 body (item 1b, edited 2026-10-28). Epic item 4 (host token downgrade, `doppler_service_token.inngest` read/write to read) also needs a flip-token design: the on-host `flag_set` in `apps/web-platform/infra/inngest-cutover-flip.sh` writes `INNGEST_CUTOVER_FLIP` under the host token, so a read-only token breaks the flip unless the flag is terminal or the write is split off; #6890, the split-token tracker, was closed NOT_PLANNED on 2026-10-24. Item 3 (automated repair route) stays declined (CTO, 2026-10-15). Item 2 ships detection only; a header repair route is blocked behind the host replace (#11265) and the CLO-gated header backup.

CLO draft ruling, 2026-10-28 (v1 internal attestation, not legal advice): [ciphertext copy allowed in principle, retention N <= 30 days, recommended 14; not in the Cloudflare account that holds the Terraform state (a second copy of the passphrase sits in tfstate); provider not chosen, no Art. 28 instrument on file; premise correction: Cloudflare R2 is not an EU provider (Art. 30 register cell (e), DPD 2.3(n) and 6.4 treat it as a US-importer Chapter V transfer); header-only stays permitted on the 2026-10-15 conditions]. Build conditions: [seven, as given]. Unanswered facts: [six, as given].

Owner-side follow-ups, owner-only, not started: (1) read-only console check ... capture checklist [counts and roles only]; (2) written question to Hetzner support, text: "[the given text]".
```

Capture checklist for follow-up (1), to be written into the addendum in this form (counts and roles only, never names or emails): date and time (UTC) of the check; number of members; count per role (Owner, Admin, Member, Restricted, as the console labels them); number of Owners and of Admins; whether sign-in protection (two-factor) is enabled for the account and, if the console shows it, how many members have it; whether API tokens are visible and how many per permission level (count only, never a value); who recorded it (the owner) and where it is filed (the A6 "no known access" record in `knowledge-base/engineering/operations/runbooks/inngest-server.md`, owner-signed). Console only, no API endpoint.

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (append only, after its last line)

## Files to Create

- `knowledge-base/project/plans/2026-10-28-docs-adr-282-hetzner-sources-rulings-addendum-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-9927-adr-282-hetzner-sources-rulings-addendum/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9927-adr-282-hetzner-sources-rulings-addendum/session-state.md` (pipeline state, written by `soleur:one-shot`)

## Open Code-Review Overlap

None at plan time (check repeated at deepen time against a 200-issue `code-review` snapshot, `jq contains` on the ADR path).

## Architecture Decision (ADR/C4)

Skipped: the addendum records evidence and already-given rulings; it makes no new decision and changes no actor, system or relationship. Checked against the C4 model: Hetzner Cloud is already the `hetzner` container, Cloudflare R2 and Doppler are already modeled; a deferred, unbuilt off-project copy adds no edge. No new ordinal (the amendment-by-addendum precedent of 2026-10-26).

## Domain Review

**Domains relevant:** legal (rulings supplied; not re-run)

### Legal

**Status:** reviewed (ruling supplied by the invoking brief, 2026-10-28)
**Assessment:** The CLO draft ruling is recorded in substance as a v1 internal attestation, not legal advice. This change adds no processing activity and builds nothing; the GDPR gate (`soleur:gdpr-gate`) is not triggered: the path is not a regulated-data surface and no store, flow, schema or distribution surface is created. The legal build conditions (a CLO determination on #8528; #7671 resolved or the bucket added to the Art. 30 register; DPA on file) are listed as conditions of a deferred build, not satisfied here.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Append ONE dated addendum (`## Addendum - 2026-10-28 (#9927), second`)" [brief] | Overview; Implementation step 3; Files to Edit | mapped |
| 2 | "Append-only (0 removed lines), status stays accepted, no new ordinal" [brief] | Implementation step 4 (append-only proof); AC 1 | mapped |
| 3 | "Read the existing 2026-10-23 and first 2026-10-28 addenda first and match their style and evidence-class vocabulary" [brief] | Research Insights; Implementation step 3 | mapped |
| 4 | "(1) Read, with fetch date, the sources the 2026-10-23 addendum lists as unread ... could not fetch, not measured" [brief] | Implementation step 1; source table; AC 2 | mapped |
| 5 | "Do not claim protected resources survive or block a project delete unless a source says so" [brief] | Implementation step 1; AC 3 | mapped |
| 6 | "(2) CTO ruling 2026-10-28 ... Verify each claim against the repo/issue before writing it" [brief] | Premise table; Implementation step 2; AC 4 | mapped |
| 7 | "(3) CLO draft ruling 2026-10-28 ... Verify cited issue numbers exist via `gh issue view <n> --json title,state`" [brief] | Premise Validation; Implementation step 2; AC 5 | mapped |
| 8 | "(4) Owner-side follow-ups remain owner-only and not started ... Put the capture checklist and the support text in the addendum or a short block in the PR body" [brief] | Capture checklist; draft shape; Implementation step 5; AC 6 | mapped |
| 9 | "PR body and addendum state measured vs not measured with dates; Ref #9927 and Ref #10112 only, never a closing keyword" [brief] | Implementation step 5; AC 7 | mapped |
| 10 | "Do NOT edit the #9927 issue body again. Do not post comments yet" [brief] | Implementation steps 2 and 5; AC 8 | mapped |
| 11 | "Files in scope: only the ADR-282 file and the plan/spec artifacts" [brief] | Files lists; AC 8 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Append the addendum | asks 1-2 | asked |
| Read the five sources | ask 4 | asked |
| Re-verify repo and issue facts | ask 6 ("Verify each claim against the repo/issue before writing it") | asked |
| Capture checklist wording (fields list) | ask 8 ("Put the capture checklist ... in the addendum") | asked |
| Local checks (markdownlint, ordinals, drift suite, import-rehearsal suite, leak check) | ask 9 ("never print ... values") | inferred - justification: the ADR path is in `infra-validation.yml`'s PR path list, so CI runs these suites on any ADR edit; running them locally shows a red before CI does |
| `tasks.md` | ask 11 | inferred - justification: the plan skill's save-tasks contract requires `tasks.md` beside the plan |

### Split Assessment

- Subsystems touched: 1 - knowledge-base (ADR, plan, spec)
- Planned files: 4 | Estimated changed lines: about 55 in the ADR plus plan and tasks
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] The ADR gains exactly one new final section `## Addendum - 2026-10-28 (#9927), second`; `git diff origin/main -- <ADR> | grep -c '^-[^-]'` is 0; the frontmatter, Status block, every earlier addendum and every dated cell are unchanged; the frontmatter `status` is still `accepted`.
- [ ] The addendum has one row per source for all five sources (T&C, projects documentation, Cloud changelog, provider delete-protection docs, provider project-deletion docs), each with URL, fetch date (the real work date) and, for every one of the four topics, a short verbatim quote or "not found in the page read"; any unfetchable source reads "could not fetch, not measured".
- [ ] No sentence in the addendum claims protected resources survive, or block, a project delete or account closure unless a quoted source sentence says so; the result paragraph states plainly what the five sources do and do not settle.
- [ ] The CTO ruling is recorded as `Ruled by CTO agent, 2026-10-28:` with: (d) deferred, not declined, and the header-only versus header-plus-ciphertext reason; the three-part earliest-of trigger; tracking in the #9927 body item 1b (edited 2026-10-28); the item 4 flip-token gap citing `flag_set` and `INNGEST_CUTOVER_FLIP`; #6890 closed NOT_PLANNED 2026-10-24; item 3 declined 2026-10-15; item 2 detection only. Each cited fact was re-verified at work time.
- [ ] The CLO draft ruling is recorded as a v1 internal attestation, not legal advice, with N <= 30 days (recommended 14), the tfstate-account exclusion with its reason, no provider chosen and no Art. 28 instrument, the R2-is-not-an-EU-provider correction, the header-only 2026-10-15 conditions, all seven build conditions, and all six unanswered facts (credential delivery channel marked as a CTO question). Issue numbers #8528 and #7671 were checked with `gh issue view <n> --json title,state` and are cited with their open state on the check date.
- [ ] Follow-ups (1) console check and (2) support question are marked owner-only, not started; the capture checklist asks counts and roles only (never names or emails) and notes that it supplies the member list the A6 "no known access" record in `inngest-server.md` needs; the support question text equals the given draft word for word; it is also in the PR body for the owner.
- [ ] PR body: Measured and Not measured with dates (2026-10-28 for plan-time facts, the real date for the source reads), `Ref #9927`, `Ref #10112`, no closing keyword, #9927 stays open.
- [ ] Only the ADR and files under `knowledge-base/project/{plans,specs}/` changed; the #9927 body was not edited and no comment was posted; no Hetzner or Doppler write, terraform command, host action or personal data was involved; `check-adr-ordinals.sh` and `sole-copy-drift-check.test.sh` exit 0, markdownlint on the ADR exits 0 or its refusal is stated and CI's markdownlint job is green.

## Test Scenarios

No executable browser or API steps. Verification is the shell checks in Implementation step 4, each read-only. Mutation view of the one machine-checkable property (append-only): editing any existing ADR line makes the removed-line count non-zero; the count is the proof. A second machine-checkable property: the ADR's existing machine-read anchors (`Hetzner id 106903269`, `**UNVERIFIED first.**`) are untouched; the two suites above fail if an edit removes them.

## Sharp Edges

- A fetched page that renders client-side (the changelog) can return a shell with no content; record "could not fetch, not measured", never fill from memory or from a search summary.
- Do not turn "documented" into "Hetzner behaves so". T&C general clauses about "account" or "contract termination" are not statements about Cloud Projects or Volumes unless the clause says so; say what the clause covers.
- An absence claim is scoped to the exact page or listing read ("no project resource in the provider's `docs/resources` listing on [date]"), never "Hetzner/Terraform has no such behaviour".
- The provider doc sentence "the Provider will lift the lock" concerns Terraform destroy, not a Console project delete; do not use it as evidence on project deletion.
- Do not paraphrase the rulings into stronger claims: "deferred, not declined" and "allowed in principle" are the exact strengths; "recommended 14" is a recommendation, N <= 30 is the bound.
- The ADR path is in `infra-validation.yml`'s PR path list: CI runs the infra guard suites on this docs-only PR. A red there is not caused by the append unless an anchor the suites grep for was edited (none is touched).
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `none` with a scope-out reason.
- Rc 6 is not a pass. Work only in this worktree, never the root checkout.
- Owner-side wording: say "classified owner-side by the invoking brief" for follow-ups (1) and (2); no browser attempt was made at plan time, so do not write "verified unautomatable" (`hr-never-label-any-step-as-manual-without`).
- Cite `flag_set` by function name and effect; do not paste the Doppler command line into the ADR (the plan-write guard blocks it in plans, and the string adds nothing the anchor does not).
