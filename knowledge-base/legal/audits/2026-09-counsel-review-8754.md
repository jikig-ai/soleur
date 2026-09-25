---
title: "Counsel review audit — #8754 / PR #8831 (the dedicated Inngest host ran without its declared deny-all cloud firewall: CLO determination, breach-register row, Art. 30 PA-13 §(e)/§(g) markers, DPIA/LIA corrections)"
type: counsel-review
date: 2026-09-25
issue: 8754
pr: 8831
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-25
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED subject to FOUR in-PR corrections (C1–C4, below) that the lead applies before merge. The determination's finding stands: NO PERSONAL-DATA BREACH ESTABLISHED under Art. 4(12); Art. 33 No; Art. 34 No; PROVISIONAL on L3 pending #8867 (OPEN). The corrections narrow statements; none changes a conclusion. Append-only discipline verified: a porcelain word-diff over all eight files deletes no token, and the two Art. 30 PA-13 markers sit in-cell under the sentences they supersede, which are kept verbatim."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — L1 interval 3 is still open. 'RESOLVED for intervals 2 and 3' / 'for 2026-08-12 onward' / 'for the second and third intervals' claim a window the 2026-09-25 Better Stack read does not cover. Narrow to 'up to the 2026-09-25 read' and require the same query to be re-run at the restored marker (breach-register R3/R4; determination addendum item 1; A4–A6 appended paragraph)."
  - "C2 — The activities sharing the Inngest store are named as a closed list that omits PA-16 and PA-17, both of which dispatch through `inngest.send`. Name them and mark the list open (breach-register R2; determination addendum item 3)."
  - "C3 — Outside the determination, the nftables filtering of :8288/:8289 in every interval is stated as fact, while L2 is INCONCLUSIVE for destroyed hosts. Qualify it as 'installed on every host by design; load measured on the live host only' (breach-register R1; Art. 30 PA-13 §(e) marker; A4–A6 appended paragraph; determination addendum item 2)."
  - "C4 — The determination defers the DPD clause (o) staleness to 'its own issue', and none exists. File it and cite it, and cite #8870 for the RECOMMENDED firewall drift assertion (determination addendum item 4)."
optional_precision_notes:
  - "O1 — 'created … after the July rotation': the project-key swap was PART of the rotation (learning §Solution). The inference is unaffected."
  - "O2 — Measured L3 narrowing: no inngest_host_replace ran in apply-web-platform-infra.yml between the exposure start and run 30555422462 (job started 2026-07-30T15:11:59Z); the 2026-07-27 dispatches 30247210123 and 30259798197 skipped it. One pre-exposure host was in service throughout and was destroyed 2026-07-30. Whether its root authorized_keys was rotated in place is for #8867."
  - "O3 — ADR-030's corrections omit the Redis loopback bind and do not say nftables covers only :8288/:8289 or that TCP 22 was reachable. The runbook correction is complete. Engineering record; not conditioned."
  - "O4 — The register row's Art. 33/34 cells read a bare 'No'. The Determination cell carries PROVISIONAL; the precedent's 're-opens with a FRESH 72h' wording would be fuller. Not conditioned."
  - "O5 — No compliance-posture.md row. Recommended, not conditioned (the #8248 O3 precedent)."
attests:
  - "knowledge-base/legal/audits/2026-09-25-8754-inngest-cloud-firewall-determination.md — as amended by the C1/C2/C4 addendum"
  - "knowledge-base/legal/breach-register.md — the 2026-09-25 row and its `related:` entry, as corrected by R1–R4"
  - "knowledge-base/legal/article-30-register.md — the two 2026-09-25 (#8754) in-cell Superseded markers in PA-13 §(e) and §(g) TOM (11)(a), the §(e) marker as corrected by C3"
  - "knowledge-base/legal/audits/2026-06-11-dpia-screening-operator-inbox-triage.md, knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md, knowledge-base/legal/legitimate-interest-assessments/2026-06-11-operator-inbox-triage-lia.md — the 2026-09-25 (#8754) correction blocks plus the C1/C3 appended paragraph"
does_not_attest:
  - "knowledge-base/engineering/operations/runbooks/inngest-server.md and knowledge-base/engineering/architecture/decisions/ADR-030-*.md 2026-09-25 corrections (read for consistency; consistent)"
  - "ADR-100's 2026-09-25 addendum, the Terraform change, and Guard 1 (technical controls; counsel attests the records' statements about them, not their correctness)"
  - "The July 2026 incident's own Art. 4(12) determination (#8867), on which L3 depends"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(1) The post-replace check passes: restored markers are appended at every record carrying a 2026-09-25 (#8754) marker, with the C1 Better Stack re-read for interval 3's tail recorded alongside. Any non-zero count re-opens this review. (2) The #8867 determination lands: L3 closes or flips by dated addendum to the determination, and this attestation is re-read against it. (3) Any evidence of a successful SSH login on an Inngest host other than the operator's legitimate path: a FRESH 72h Art. 33(1) clock, Art. 34 re-run, Art. 33(2) notices re-derived per C2. (4) External counsel re-review: the first arm's-length user whose data sits in the Inngest store exercising rights on this incident, any affected data subject outside the EEA, or any regulated-industry tenant on the store."
---

# Counsel review audit — #8754 / PR #8831 (Inngest host without its cloud firewall)

This file is the evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #8831
(issue #8754). The gate fired on the `knowledge-base/legal/` records this PR adds or amends. The
brand-survival threshold is `single-user incident`. The CLO agent is the v1 attestation authority,
and the operator holds an optional veto.

## Scope and limit check

- **Append-only.** `git diff --word-diff=porcelain origin/main...HEAD` over the eight in-scope
  files shows no deleted token. The Art. 30 PA-13 §(e) and §(g) TOM (11)(a) markers are inserted
  in-cell, dated 2026-09-25, cite #8754, and keep the superseded sentences verbatim. The three
  DPIA/LIA blocks and the runbook and ADR-030 blocks are appended.
- **The public surface is not engaged.** `git diff --stat origin/main...HEAD -- docs/legal plugins/soleur/docs/pages/legal`
  is empty. The five #7387 gates are not engaged.
- **Merge-conditioning is stated.** Every record says the binding takes effect when "the change
  tracked in #8754 merges" and that the host in service gains it at its next replacement. None says
  in the past tense that it has landed.
- **No `[DRAFT — pending CLO/counsel review` markers** appear in the diff (`grep -c` returns 0).
- **Citations are by name, not by line.** Code is cited by resource and file name
  (`hcloud_firewall.inngest`, `inngest-nftables.sh`, `inngest-redis.conf`, Guard 1). No record cites
  a line number.
- **Production was untouched by this review.** No terraform, hcloud, doppler or gh write was run.
  Reads only: `gh run view`, the run log, `gh issue view`.

## Drift table

| # | Claim | Checked against | Verdict |
|---|---|---|---|
| D1 | Zero-rule deny-all firewall | `inngest-host.tf`, `resource "hcloud_firewall" "inngest"`: no rule blocks | Holds |
| D2 | Accepted residual recorded 2026-07-08 | origin/main comment above `resource "hcloud_firewall_attachment" "inngest"`, introduced 2026-07-08 (c890464ce5, 9c208a7941) | Holds |
| D3 | Re-binding applies 30623984560 and 34330222965; the quoted 2026-07-31 reason | `gh run view`: 2026-07-31 10:33:57Z→10:34:39Z and 2026-09-09 08:38:26Z→08:40:45Z, both successful dispatches. The run log carries the quoted reason string. | Holds |
| D4 | Intervals, replace counts, 65 of 78 days | Arithmetic 21.5 / 27.4 / ≥15.7 days; 18+5+13 = 36 jobs; 78 days from 2026-07-09 to 2026-09-25 | Holds (job counts relied upon) |
| D5 | nftables: `policy accept`, drops only `:8288`/`:8289` from non-web sources, oneshot re-assert | `cloud-init-inngest.yml`: `inngest-nftables.sh`, `inngest-nftables.service`, `systemctl enable --now` | Holds |
| D6 | Redis closed by its loopback bind | `inngest-redis.conf`: `bind 127.0.0.1 -::1`, `protected-mode yes` | Holds |
| D7 | SSH is key-only and authorises `hcloud_ssh_key.default` | `01-hardening.conf`; `hcloud_server.inngest` `ssh_keys`; no cloud-init authorized keys; `deploy` user has no keys | Holds |
| D8 | Fix: `firewall_ids` at ServerCreate; `removed` block with `destroy = false`; Guard 1 | `inngest-host.tf`; `inngest-host.test.sh` "GUARD 1 (#8754)" | Holds |
| D9 | L1: intervals 2 and 3 have 0 `Accepted publickey` and 0 `session opened` from `soleur-inngest`; interval 1 has no rows | Better Stack read of 2026-09-25 (operator-supplied evidence) | Accurate for 2026-08-12→2026-09-25. **Over-covers interval 3, which is still open → C1** |
| D10 | The 2026-07-30 host shipped zero rows | ADR-100 2026-08-12 addendum | Holds |
| D11 | sshd not shipped off-host before 2026-07-28 | PR #7039, apply run 30361817302 (2026-07-28T13:04Z) | Holds |
| D12 | L3: project key created 2026-07-28 11:12:39Z; only earlier-born hosts could carry the exposed key | `ssh_keys` is create-time; `ignore_changes = [ssh_keys]` applies in place only; no other key injection | Holds (O1, O2) |
| D13 | Operator key was the only root key on the Inngest host; non-use evidence covers web-1 only | Learning `2026-07-28-vscode-folderopen-task-rce-and-fleet-wide-key-rotation.md` §4, §Outcome | Holds |
| D14 | Store shared by PA-14, PA-21, PA-22, PA-27, PA-31 | Art. 30: PA-16 dispatches at `inngest.send`; PA-17 §(e) names the Inngest dispatcher | **Under-inclusive → C2** |
| D15 | DPD clause (o) claims no cloud firewall on the dedicated host | `docs/legal/data-protection-disclosure.md` (o): its "provider firewall" limb covers only the co-located deployment | Holds. **The follow-up issue does not exist → C4** |
| D16 | nftables filtered `:8288`/`:8289` "in those intervals" (register row, Art. 30 §(e), DPIA/LIA) | L2 INCONCLUSIVE for destroyed hosts | **Stated as fact → C3** |
| D17 | Standing-rule recommendation | #8870 OPEN | Tracked. **Not cited → C4** |
| D18 | L3 pending | #8867 OPEN | Holds |

## Findings

- **F1: the determination is sound on Art. 4(12).** A declared control that was not in force is a
  vulnerability, not an outcome. No data-bearing surface became reachable from the internet:
  - the ingest ports were covered by nftables, as designed;
  - Redis was covered by its loopback bind;
  - `/v1/*` was covered by Inngest's software loopback gate.

  The one reachable surface, sshd, is key-only, and its shipped log shows no successful login for
  the covered window. This applies the standing rule of the 2026-06-29 and 2026-09-23 register rows:
  reachability alone does not start the Art. 33 clock. Art. 34 is assessed on its own facts.
- **F2: L3 is correctly held PROVISIONAL.** The key authorised on the host was treated as exposed
  while the host was in interval 1. Only the #8867 determination can say whether a root session could
  reach personal data, directly or through the Doppler tokens and backend connection strings
  provisioned to the host. The narrowing evidence does not close L3, and the records do not claim it
  does. Two pieces of narrowing evidence exist: the project-key timestamp, and a measured absence of
  replaces during the exposure (O2).
- **F3: C1.** An interval that is still open cannot be certified in full. The post-replace check is
  where interval 3 ends, so it is where its L1 read must end too.
- **F4: C2.** The activity list matters only if the finding flips, but at that point it decides who
  receives an Art. 33(2) notice. A closed list that omits two Inngest-routed activities would
  under-notify.
- **F5: C3.** The determination keeps "held throughout, subject to L2". The satellite records drop
  the qualifier and state the unmeasured limb as fact, which over-claims protection. A qualifier
  restores parity.
- **F6: C4.** A deferral needs a tracking issue. #8870 already exists for the drift assertion.
- **F7: no lawful-basis, purpose, recipient or transfer change.** Hetzner is the same EU processor.
  No TC_VERSION bump. No published document changes.

## Conditions

These are in-PR text. Each anchor was verified unique with `grep -cF`.

**R1–R4, `knowledge-base/legal/breach-register.md` 2026-09-25 row (C1, C2, C3), replace in place:**

- R1: ``:8288`/`:8289` were filtered by host-local nftables, and Redis was bound to loopback |``
  → ``:8288`/`:8289` were filtered by host-local nftables (installed on every host by design; its load measured on the live host only — L2), and Redis was bound to loopback |``
- R2: `PA-13 and the activities sharing the dedicated Inngest store (PA-14, PA-21, PA-22, PA-27, PA-31)`
  → `PA-13 and the activities whose events or run state the dedicated Inngest store holds (named: PA-14, PA-16, PA-17, PA-21, PA-22, PA-27, PA-31; not a closed list — a flip re-derives it before any Art. 33(2) notice)`
- R3: `for 2026-08-12 onward the host's shipped sshd log records no successful login, only rejected attempts.`
  → `from 2026-08-12 to the 2026-09-25 read, the host's shipped sshd log records no successful login, only rejected attempts.`
- R4: ``L1 is RESOLVED for intervals 2 and 3 (Better Stack, 2026-09-25: 0 `Accepted publickey`, 0 `session opened` from `soleur-inngest`).``
  → ``L1 is RESOLVED for interval 2 and for interval 3 up to the 2026-09-25 read (Better Stack, 2026-09-25: 0 `Accepted publickey`, 0 `session opened` from `soleur-inngest`); the rest of interval 3 is read when the restored marker is appended.``

**`knowledge-base/legal/article-30-register.md` PA-13 §(e) 2026-09-25 marker (C3), replace inside this PR's marker:**

- ``In those intervals, the public boundary for `:8288`/`:8289` was the host-local nftables chain;``
  → ``In those intervals, the public boundary for `:8288`/`:8289` was the host-local nftables chain (installed on every host by design; its load was measured on the live host only);``

**The two DPIA screenings and the LIA (C1, C3), append after each file's final line:**

```
>
> Two precisions to this correction, added 2026-09-25 before merge. The nftables statement describes
> the chain as provisioned on every host; its load was measured on the live host only, and on the
> destroyed hosts it cannot now be measured. The SSH-log statement covers the third interval only up
> to the 2026-09-25 read; the rest of that interval is read when the firewall is measured restored.
```

**The determination (C1, C2, C4), append a dated addendum** with four items:

1. L1 interval 3 is covered only up to the 2026-09-25 read; the query is re-run at the restored marker.
2. The L2 qualifier travels with every nftables statement.
3. PA-16 and PA-17 join the open list of activities on the store; the list is re-derived on a flip.
4. Pointers to #8870 and to the clause (o) issue filed under C4.

**C4, file the clause (o) follow-up** before merge and cite its number in addendum item 4.

O1–O5 are non-blocking.

## Verification commands (re-runnable from the worktree)

- `git diff --word-diff=porcelain origin/main...HEAD -- knowledge-base/legal/ knowledge-base/engineering/operations/runbooks/inngest-server.md knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md | grep -c '^-[^-]'` → 0 (append-only).
- `git diff origin/main...HEAD | grep -c 'DRAFT — pending'` → 0.
- `grep -n 'policy accept\|tcp dport { 8288, 8289 }' apps/web-platform/infra/cloud-init-inngest.yml` → the D5 chain.
- `grep -n '^bind' apps/web-platform/infra/inngest-redis.conf` → `bind 127.0.0.1 -::1` (D6).
- `grep -n 'firewall_ids\|from = hcloud_firewall_attachment.inngest\|destroy = false' apps/web-platform/infra/inngest-host.tf` → D8.
- `gh run view 30623984560 --log | grep -m1 -o 'Incident 2026-07-27/28.\{0,120\}'` → the quoted reason (D3).
- `for r in 30247210123 30259798197; do gh run view $r --json jobs --jq '.jobs[]|select(.name=="inngest_host_replace")|.conclusion'; done` → `skipped` ×2 (O2).
- `grep -cF 'from 2026-08-12 to the 2026-09-25 read' knowledge-base/legal/breach-register.md` → 1 after R3; `grep -cF 'for interval 3 up to the 2026-09-25 read' knowledge-base/legal/breach-register.md` → 1 after R4.
- `grep -cF 'PA-16, PA-17' knowledge-base/legal/breach-register.md` → 1 after R2.
- `grep -cF 'its load was measured on the live host only' knowledge-base/legal/article-30-register.md` → 1 after C3.
- `for n in 8754 8867 8870; do gh issue view $n --json state -q .state; done` → OPEN ×3.
