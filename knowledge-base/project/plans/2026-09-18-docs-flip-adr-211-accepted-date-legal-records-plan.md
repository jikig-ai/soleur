---
title: "docs(7960): flip ADR-211 to accepted and date the legal records, after the sweeper PASS"
date: 2026-09-18
slug: docs-flip-adr-211-accepted-date-legal-records
branch: feat-one-shot-8309-adr211-accepted-legal-records
issue: 8309
closes: [8309]
lane: procedural
type: docs
priority: p3-low
domain: engineering
brand_survival_threshold: none
---

# docs(7960): flip ADR-211 to accepted and date the legal records, after the sweeper PASS

## Enhancement Summary

**Deepened on:** 2026-09-18
**Sections enhanced:** Phases 1-4, Acceptance Criteria 2/8, Research Insights
**Research agents used:** git-history-analyzer (11 attribution claims probed live), legal-compliance-auditor (cross-document audit of every drafted sentence), architecture-strategist (ADR corpus + C4 consistency after the flip), verify-the-negative sweep (8 universal claims), plus the plan-time CLO ruling and the DHH/Kieran/code-simplicity panel. Skills fan-out: none applicable (no framework, no code). Halt gates 4.6-4.11: pass (pure-docs; threshold `none` with no sensitive path; no PAT, UI, store or guard deliverable).

### Key Improvements

1. Three more falsified sentences found and marked — ADR-211's *Primary re-evaluation trigger* bullet ("the one that is going to happen. Tracked at #7960"), and the audit's Finding 1 ("one of which is inert") and re-evaluation bullet 3 ("Layer 1 is inert"). The census now covers every present-tense inert claim in the corpus (verified by two independent sweeps).
2. The pre-delivery corpus is described correctly: rows before the 2026-09-17 replace carried no `redact()`; rows on the 09-17 boot `78111e0e…` are corroboration, unproven either way; retention is the 90-day `logs_retention` of source `2457081`, not "both sources". The earlier "2026-08-12 to 2026-09-18" window was wrong on both ends and is gone.
3. The amendment carries the evidence pointer (#7960 comment `5731215695`) and enumerates every site it retracts, mirroring ADR-184; the audit's item-4 note anchors its voice and is conditioned on this change rather than asserting a merged state.

### New Considerations Discovered

- Every attribution in the plan (PR #8272 = `f5ad46390`; #7960 close and PASS literal; runs 35353167115 / 35354131746; #7514 = `19bbdb768`; #7455; #7772; #8218; #8082/#8248/#8275 hunks; learning `pr: 8153`) verified live — none contradicted.
- The C4 edge text lives in the relation title, not the truncated drawn label — no visible diagram diff is expected.
- Declined (bounded PR): an optional clause on the `zotRegistry -> betterstack` edge describing the producer redaction on the warehouse egress; a shorter CLO-authored `open_limbs:` value. Both are recorded here for a later pass, not for #8309.

## Overview

The `#7960` follow-through probe (`scripts/followthroughs/zot-last-err-redact-7500.sh`) PASSed on
2026-09-18 and the sweeper closed the tracker. Four records still describe ADR-211 Layer 1 (the
producer-side `zot_last_err` redaction) as inert, or as believed-delivered-but-unprovable. This
plan dates those records forward — append-only for prose, in-cell for frontmatter fields — and
flips ADR-211's `status:` to `accepted`, following the ADR-184 (#7514) precedent exactly. Docs and
model files only; no product code, no infra.

**Trigger evidence (verified live during planning, 2026-09-18):**

- `gh issue view 7960 --json state,closedAt` → `CLOSED`, `2026-09-18T14:10:59Z`.
- Newest sweeper comment (`github-actions`, 2026-09-18T14:10:58Z) is the PASS heading; the script
  exited 0 with `verdict=r3_pass proof=err_redact_rev boot=3b70b6ae-e7d5-4218-993f-6d39c563a422 tier4=3 leaking=0`.
- The delivering replace: workflow run 35353167115, job `registry_host_replace`, completed
  2026-09-18T14:03:52Z; first row on boot `3b70b6ae…` at 14:04:35Z with `err_redact_rev` in the
  trusted region. Delivering PR #8272 merged as `f5ad46390` at 13:46:53Z with #7960 still OPEN.

**What the PASS proves, and what it does not** (from the script header and ADR-211 §Delivery proof —
every entry this plan appends must carry the same scope limit, or it is the overclaim ADR-211 exists
to prevent):

- Proves: on the newest boot, a row in the trusted region carries `err_redact_rev ≥ 1` (Phase B
  producer is running), and every tier-4 row (`fallback`/`suppressed`) in the 24h window — 3 of
  them — carries no header structure (no header map with a key, no address-valued `clientIP`, no
  bracketed credential-header value).
- Does not prove: tiers 1-3 per-line `redact()` (covered pre-merge by
  `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`, never read back from the
  warehouse); anything about the pre-delivery warehouse corpus (rows before 2026-09-18 that reached
  Better Stack with no `redact()` in the path — 90-day retention, PA-8 §(f)); and nothing re-grades
  the stream after the PASS (the sweeper skips an issue it closed itself).

## Research Insights

**Premise validation (Phase 0.6).** #8309 OPEN, no closing PR. #7960 CLOSED by the sweeper PASS
(above). ADR-211 on `origin/main` reads `status: adopting` (frontmatter line 3) with the amended
trigger "flips to Accepted when the #7960 probe PASSes on a boot PROVEN by `err_redact_rev`" — the
trigger fired. The three files the issue names exist at the cited paths. The probe script exists
and its header documents the exit contract quoted above. Adjacent OPEN issue #8218 targets the same
register file but different sentences (git-data host, PA-1 §(g)(13) / PA-2 §(g)(17) / PA-2
replication row) and has no PR — **out of scope**, not folded in (its own trigger was not
verified here and the operator asked for #8309 to be its own reviewed PR).

**Census — the issue under-counted the set (the `hr` "grep the mechanism, not the inventory"
class).** The issue says "both cells carrying the INERT bracket". `grep -inE 'inert|registry-host-replace'`
over the register finds the inert delivery-state posture asserted in **five** cells, and one more
in the C4 model:

| # | File | Anchor sentence (content anchor, not line number) |
|---|---|---|
| 1 | `knowledge-base/legal/article-30-register.md` PA-8 §(c) | `**[Delivery state, added 2026-09-08 (#7500): the PRODUCER-side control (ADR-211 Layer 1) is INERT AND NOT IN FORCE until the next \`registry-host-replace\`` |
| 2 | same, PA-8 §(d) | `The PRODUCER-side control is NOT in force and is inert until the next \`registry-host-replace\` (ADR-096).` |
| 3 | same, PA-8 §(g) | `**DELIVERY STATE -- LAYER 1 IS INERT AND IS NOT IN FORCE.**` … `must not be read as a description of current processing until a dated delivery entry is appended, in the shape of the 2026-08-13 (#7455) entry at §(d)` and, later in the same cell, `DELIVERY STATE — LAYER 1 REMAINS INERT AND IS NOT IN FORCE until the next registry-host-replace` |
| 4 | same, Vendor Mapping — Better Stack s.r.o. row | `but it is **INERT until the next \`registry-host-replace\`**, so until a dated delivery entry is appended the quoted sentence still describes what actually reaches this source` |
| 5 | same, Vendor Mapping — GitHub Inc row | `**[Delivery state, added 2026-09-08 (#7500): … INERT AND NOT IN FORCE until the next \`registry-host-replace\`` |
| 6 | `knowledge-base/engineering/architecture/diagrams/model.c4`, `github -> publicReader` edge | `(ADR-211 Layer 1 — INERT until the next registry-host-replace, so this edge is currently guarded by the denylist alone)` |

Cells 2 and 4 are the two the issue names (they are the only two matching the exact phrase
`INERT until`). Cells 1, 3, 5 assert the identical posture in other words; cell 3 is the one the
register itself and the CLO audit's re-evaluation trigger designate for the dated delivery entry.
Row 6 is the #7514 precedent's AC7 class (that PR removed `INERT UNTIL A PROVISIONING EVENT` from
`model.c4`). All six are in scope; none is a new mechanism.

A repo-wide sweep of every file naming `zot_last_err` (`git grep -il zot_last_err`, excluding
plans/specs/learnings/archive) found no other present-tense inert/unprovable claim: the hit in
`knowledge-base/legal/audits/2026-08-counsel-review-7440.md` is a dated review scope statement, not
a posture claim; `scripts/followthroughs/zot-last-err-redact-7500.sh` already frames "inert" as
historical.

**Audit file — every field the closure touches.** In
`knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md` the open
limb is referenced by three frontmatter fields, not one: `open_limbs:` (the limb itself),
`art_33_deadline:` ("A BREACH finding on the open limb below would start a FRESH 72h"), and
`disposition:` ("One evidentiary limb NOT RUN and recorded as open"). The body references it at
§"The open evidentiary limb", §"What I am explicitly NOT attesting to" items 2 and 4 ("It is inert"),
and §"Re-evaluation triggers" bullets 2 ("A `registry-host-replace` firing … A dated delivery entry
must be appended to PA-8 §(g)") and 4 ("The open warehouse limb being run"). Learning
`2026-09-14-closing-a-limb-by-decision-is-not-closing-it-clean-and-the-cell-still-has-to-change.md`
(#7945 / PR #8153) is the exact prior incident: an `open_limbs` change left `art_33_deadline` still
pointing at "the open limb", and corrections were narrated in blockquotes but never applied to the
cell. Rule carried forward: **frontmatter fields are cells — change them in-cell; body sentences
are append-only — mark them with a dated marker under the sentence.** Deepen-pass sweep added two
more audit sentences to mark (Finding 1 "one of which is inert"; re-evaluation bullet 3 "Layer 1
is inert") and one ADR bullet (*Primary re-evaluation trigger*); Phases 1 and 3 carry them.

**Precedent for the ADR flip.** ADR-184 (#7514, commit `19bbdb768`): frontmatter
`status: adopting` → `status: accepted`; a parenthetical on the flip-condition line pointing to the
amendment; an `## Amendment 2026-08-12 — first PASS observed (status ACCEPTED)` section appended
at the end quoting the run verbatim in a fenced `text` block, with the workflow run id; the
`model.c4` edge and `model.likec4.json` regenerated in the same PR. Its ACs were literal greps on
`^status: accepted` / `^status: adopting`, the amendment heading, the run literals, and
`bash plugins/soleur/test/c4-model-freshness.test.sh`.

**Register cell convention.** All five register targets are single-line table cells. The
register's dated-entry shape inside a cell is an inline bold bracket — see the
`**[2026-08-13 UPDATE (Ref #7455): the INERT posture recorded immediately above is SPENT — this channel is LIVE.** …]`
entry in PA-8 §(d) — appended before the cell's closing ` |`. A `>` blockquote cannot live inside a
GFM table cell, so the issue's `> **Superseded …**` shape applies to the ADR and the audit (prose
files), and the bracket shape applies to the register.

**Gates that run on these paths** (repo research):

- `scripts/lint-legal-registers.sh` (blocking since PR #7881): (a) no standalone `TBD`/`TODO`/`XXX`/`FIXME`
  in the register files (inline code exempt); (b) canonical-source pointers resolve; (c) the
  audit is already on the determination-index waiver list — no change needed there.
- `scripts/lint-infra-no-human-steps.py` scans `knowledge-base/engineering/architecture/decisions`
  (so ADR-211) and `knowledge-base/project/plans` (so this file): a human-actor word paired with
  an infrastructure-mutation verb on the same or adjacent line, outside a fenced block, is a
  reject (its token lists live in the script's `ACTOR_RES` and `IMPERATIVE_RES` pattern tables — read
  them there; this plan does not reproduce them, per #7003). The quoted run goes in a fenced
  block; the amendment prose names the workflow run by id and never an actor.
- `plugins/soleur/test/c4-model-freshness.test.sh` byte-diffs `model.likec4.json` against a fresh
  render (`bash scripts/regenerate-c4-model.sh`); `plugins/soleur/test/c4-count-parity.test.sh` gates
  the cardinalities embedded in edge prose. The `model.c4` edit changes one edge's description, no
  counts.
- `lefthook.yml` regenerates `knowledge-base/INDEX.md` on any `knowledge-base/**/*.md` change —
  the diff-scope AC must list it.
- No test pins ADR-211's status or the register's row/pipe structure
  (`git grep -n 'ADR-211' -- tests plugins scripts .github apps/web-platform/test` → comments and
  the probe only).
- Ship Phase 5.5 Counsel-Review CLO-Attestation Gate fires only when a legal path changes AND
  (threshold `single-user incident` OR a `[DRAFT — pending CLO/counsel review` marker is present).
  Neither holds here, so it does not fire; the CLO review of the wording is done at plan time
  (§Domain Review) instead.

**Institutional learnings applied** (paths verified on disk):

- `knowledge-base/project/learnings/2026-09-15-my-legal-record-said-the-change-had-landed-inside-the-pr-that-lands-it.md`
  — a diff-scope AC must list the pipeline-written files (`INDEX.md`, `session-state.md`); an
  in-PR record is conditioned on the merge, never past tense about the PR itself. Here every
  dated entry is about an event that already happened (the 14:10:58Z PASS), so past tense is
  correct for the event and the entries must not say anything about this PR having merged.
- `knowledge-base/project/learnings/2026-08-13-a-rider-is-only-valid-while-its-vehicle-is-still-pending.md`
  — record delivery as dated fact with the vehicle named (run 35353167115), not as "merged".
- `knowledge-base/project/learnings/2026-09-14-closing-a-limb-by-decision-is-not-closing-it-clean-and-the-cell-still-has-to-change.md`
  — in-cell for frontmatter, marker under every superseded sentence in every sibling file, and
  sweep `art_33_deadline` when `open_limbs` changes.
- `knowledge-base/project/learnings/2026-08-12-unfired-triggers-and-the-adr-that-superseded-its-own-tracker.md`
  — verify the trigger state before acting on it (done: §Overview).
- `knowledge-base/project/learnings/2026-06-04-art-30-pa-citation-must-be-grep-validated-against-register.md`
  — every anchor sentence in the census table was grepped from the file, not paraphrased from the
  issue.

**Property list (Phase 0.6b).**

- P1. Every record asserting Layer 1 is inert / unprovable carries a dated superseding entry that
  states it is proven delivered, with the PASS's scope limit, and the superseded sentence is
  preserved verbatim.
- P2. ADR-211's machine-readable `status:` reflects that its own flip condition fired, and the
  firing run is quoted.
- P3. The CLO attestation's frontmatter no longer asserts an open limb the PASS closed, and every
  field and sentence that referenced that limb is consistent with the new value.
- P4. Every citation of the probe is by script name, never by line number
  (`cq-cite-content-anchor-not-line-number`).
- P5. The diff is bounded to records: the four files above plus the regenerated `model.likec4.json`
  and `knowledge-base/INDEX.md`.

**Cut list.** None. The four mechanisms the issue names each buy one property (status flip → P2;
dated appends → P1; limb closure → P3; script-name citation → P4) and no existing mechanism buys
any of them — the sweeper closes the tracker but writes no record. The additional edits this plan
adds (three more register cells, the C4 edge, the audit's sibling frontmatter fields) are further
instances of P1/P3, not new mechanisms.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "both cells carrying the INERT bracket" | Five register cells plus one `model.c4` edge assert the posture (census above) | Append to all five cells; amend the C4 edge; regenerate `model.likec4.json` |
| `> **Superseded YYYY-MM-DD (#7960): …**` shape for the register | Targets are single-line table cells; the register's in-cell convention is `**[…]**` | Bracket shape in the register; `>` blockquote shape in ADR-211 and the audit |
| "close the `open_limbs` entry that waits on delivery" | The limb is the un-read **warehouse corpus**; the PASS reads the post-delivery tier-4 rows only | Narrow in-cell per the CLO ruling (§Domain Review): closed IN PART — the post-delivery tier-4 half closes on the PASS; the pre-delivery corpus stays recorded as unread, with its 90-day age-out |
| Docs only, three files | Also `model.c4` (+ regenerated JSON) and `INDEX.md` (regenerated by lefthook) | Listed in Files to Edit and in the diff-scope AC |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` (65 issues)
piped through `jq --arg path` for `knowledge-base/legal/article-30-register.md`, `ADR-211`,
`2026-09-08-clo-attestation-7500`, and `zot-last-err-redact-7500.sh` returned no match.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — these are internal
  controller records (`knowledge-base/legal/**`, an ADR, the C4 model). The failure mode is a
  legal record that overstates what the PASS proved (e.g. "Layer 1 proven" without the tier-4
  scope limit), which a supervisory-authority reader could later hold against the controller.
  Every appended entry carries the scope limit verbatim to prevent that.
- **If this leaks, the user's data is exposed via:** no new data path. The PR moves no bytes; it
  records that a redaction control is now in force. The one way it could widen exposure is by
  weakening the sink denylist's standing ("Layer 2 is now a backstop") in a way that invites a
  later PR to remove it — the §(g) entry states explicitly that Layer 2 stays in force.
- **Brand-survival threshold:** `none`

## Implementation Phases

### Phase 1 — ADR-211: flip and amend

File: `knowledge-base/engineering/architecture/decisions/ADR-211-zot-last-err-redaction-at-the-producer-and-the-sink.md`

1. Frontmatter: `status: adopting` → `status: accepted`. Add `8309` and `8272` to
   `related_issues:`.
2. Under the `## Status` bullet that ends `See "Delivery proof" under Decision.]**`, append a new
   bracket (do not edit the earlier ones):
   `**[Accepted 2026-09-18 (#8309): the amended trigger fired — see "Amendment 2026-09-18" at the end of this ADR.]**`
3. Under the Delivery-state bullet's existing `> **Superseded 2026-09-18 (#7960):** …` blockquote
   (which cites the 2026-09-17 replace and boot `78111e0e…`, 272 rows, unproven), append a one-line
   pointer blockquote of the same shape as the Status bracket — the facts live once, in the
   Amendment (ADR-184's body brackets are pointers too), but the two replaces must stay distinct:
   `> **Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS):** a SECOND replace (2026-09-18, PR #8272, run 35353167115, boot \`3b70b6ae…\`) delivered the proof key and the probe PASSed — see *Amendment 2026-09-18* at the end of this ADR. The 09-17 boot's 272 rows remain corroboration, not proof.`
4. Append at the end of the file, mirroring ADR-184's amendment section:

   ````markdown
   ## Amendment 2026-09-18 — first PASS observed (status ACCEPTED)

   **Status flip:** `adopting → accepted`. The amended trigger recorded under *Status* — the
   #7960 probe PASSing on a boot PROVEN by `err_redact_rev` — was met at
   **2026-09-18T14:10:58Z** (sweeper run 35354131746, closing #7960 at 14:10:59Z):

   ```text
   zot-redact[#7960]: verdict=r3_pass proof=err_redact_rev boot=3b70b6ae-e7d5-4218-993f-6d39c563a422 tier4=3 leaking=0
   PASS: producer delivered (proof: err_redact_rev) — 3 tier-4 row(s) on boot 3b70b6ae-e7d5-4218-993f-6d39c563a422
         in 24h, none carrying header content.
         SCOPE: this grades the TIER-4 GATE half of ADR-211 Layer 1 -- the tier the gate changes.
         Per-line redact() at tiers 1-3 is covered pre-merge by the producer suite, not here.
   ```

   Layer 1 is delivered on boot `3b70b6ae…` per this ADR's own proof key (`err_redact_rev` in
   the trusted region, bound to the gate by the producer suite in CI — "evidence for, not proof
   of" is the contract under *Delivery proof*, and the CI pairing is what makes it a guarantee)
   and the tier-4 gate graded clean — 3 rows in 24h, 0 leaking. Per-line `redact()` at tiers
   1-3 is asserted by the producer suite pre-merge, not by this readback; nothing re-grades
   after the PASS. Vehicle: PR #8272 (`f5ad46390`, merged 13:46:53Z with #7960 still open);
   replace run 35353167115 job `registry_host_replace` complete 14:03:52Z; first row on the
   new boot 14:04:35Z. This is the second replace since adoption — the first (2026-09-17, boot
   `78111e0e…`) is recorded under *Delivery state* and stays corroboration.
   ````

   Also append to the amendment, after the paragraph above: `Evidence is posted on #7960 (comment
   \`5731215695\`, 2026-09-18T14:10:58Z) rather than living only in this file. Sites this amendment
   retracts, each carrying its own dated marker: the Status bullet, the Delivery-state note, the
   Primary re-evaluation trigger bullet, and the C4 \`github -> publicReader\` edge.`
5. Under Consequences, append to the bullet that opens `**Primary re-evaluation trigger: the next
   \`registry-host-replace\`.**` (it ends `Tracked at #7960.` plus an earlier-draft bracket) a
   bracket — NOT the `Superseded 2026-09-18 (#8309 trigger` literal, so AC3 stays at 1:
   `**[Fired: 2026-09-17 (boot \`78111e0e…\`, corroboration) and 2026-09-18 (run 35353167115, boot \`3b70b6ae…\`, proof key); #7960 closed on the PASS — see *Amendment 2026-09-18*. The standing re-evaluation triggers are now the severity-escalation (firewall) trigger below and the zot-image-bump residual under "nothing re-grades the warehouse stream".]**`
   An accepted ADR whose named primary trigger has fired and whose tracker is closed, with no
   successor named, is the ADR-184 "rider with a departed vehicle" shape.

   Do not write "PROVEN delivered" anywhere in the ADR: the *Delivery proof* subsection under
   Decision states the token is evidence, and the CI pairing is the guarantee (CLO ruling, §Domain
   Review).

   Prose in this section must not pair a human-actor token with an infra imperative
   (`lint-infra-no-human-steps.py` scans this directory); the run quote sits in the fenced block.

### Phase 2 — Article 30 register: five dated in-cell entries

File: `knowledge-base/legal/article-30-register.md`. For each of the five cells in the census
table, append — immediately before the cell's closing ` |`, after the last existing bracket — the
canonical entry below. Never edit the superseded sentence. Locate each cell by its anchor sentence
(Edit tool `old_string` = the unique tail of the cell ending in ` |`), never by line number.

Canonical entry (CLO-ruled wording, §Domain Review; the per-cell clause is inserted before "The
superseded sentence…"):

`**[Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS): the INERT posture recorded immediately above is SPENT — Layer 1 is DELIVERED per its proof key.** `registry_host_replace` (workflow run 35353167115) completed 2026-09-18T14:03:52Z on boot `3b70b6ae-e7d5-4218-993f-6d39c563a422`; `scripts/followthroughs/zot-last-err-redact-7500.sh` PASSed 2026-09-18T14:10:58Z (proof `err_redact_rev`; tier4=3, leaking=0) and closed #7960. SCOPE: the PASS grades the tier-4 gate on the newest boot over 24h only; per-line `redact()` at tiers 1-3 is asserted pre-merge by `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`, never by warehouse readback; nothing re-grades the stream after the PASS. Both controls are now in force. <per-cell clause> The superseded sentence is preserved unaltered as the record of the merge-time state.]**`

Per-cell clause:

- §(c) and GitHub Inc row: `Read this cell as describing two controls in force: Layer 2 since merge (2026-09-08), Layer 1 from that boot.` (§(c) additionally: `The open evidentiary limb named above is narrowed 2026-09-18, not closed — see the attestation.`)
- §(d): `The sink denylist is no longer the only control in front of this public channel; it is the backstop, and the producer output reaching it is the tier-gated, allowlisted sample.`
- §(g): `Layer 2 is now the backstop on the public egress, not the sole control; Layer 1 is the authoritative control on both egresses (ADR-211 Consequences). This is the dated delivery entry this cell said must be appended, in the shape of the 2026-08-13 (#7455) entry at §(d), and it discharges that condition.` — ONE entry for the cell (it carries the inert sentence twice — do not append twice), appended at the cell's END like every other cell, so the register's date order holds: the cell continues past the `…currently operating.]**` bracket with later-dated entries (`**[2026-09-09 (#7947)…`), and a 2026-09-18 entry belongs after them. Its opening words "the INERT posture recorded above" reach both earlier sentences.
- Better Stack row: `The quoted 2026-08-12 sentence ("payload-integrity sanitizer only") no longer describes what reaches this source; from boot 3b70b6ae… the tier-gated, allowlisted sample does. Rows already held from before that boot are unchanged and age out under the 90-day retention recorded at the 2026-09-04 (#7772) correction.`

The §(c) sentence "recorded as an open evidentiary limb in the attestation cited above" stays TRUE
(the limb is open in part — Phase 3) and gets no marker.

Constraints: no standalone `TBD`/`TODO`/`XXX`/`FIXME` tokens; no line numbers; every path in
backticks; after the edit re-verify the row counts as the attestation's Finding 3 did (PA-8 rows
and Vendor Mapping rows unchanged — AC5). Three other open PRs (#8082, #8248, #8275) also append
to this file — #8275 touches the §(d) cell. Appending at the cell's end is the minimal-conflict
shape; if the rebase conflicts on §(d), keep both brackets in date order.

### Phase 3 — CLO attestation: narrow the limb in-cell, mark the sentences

File: `knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md`.
CLO ruling: the limb closes **IN PART** — the post-delivery tier-4 half closes on the PASS (a
stronger test than the limb stated, on a 3-row sample); the pre-delivery corpus (2026-08-12 →
2026-09-18, unredacted; ADR-211 records 1,792 of 2,598 pre-Phase-B `fallback` rows carrying
header STRUCTURE — structure, not a value-level finding either way) stays unread at value level,
tiers 1-3 are never warehouse-read, and the unread half ages out under the 90-day retention by
2026-09-18 + 90d (≈2026-12-17) whether or not read. The record must say that rather than let it lapse silently.

1. Frontmatter, in-cell (each a one-line YAML double-quoted scalar):
   - `open_limbs:` → `"ONE, NARROWED 2026-09-18 (#8309). Closed IN PART by scripts/followthroughs/zot-last-err-redact-7500.sh PASS 2026-09-18T14:10:58Z on boot 3b70b6ae-e7d5-4218-993f-6d39c563a422 (proof err_redact_rev; tier4=3, leaking=0): the 3 post-delivery tier-4 rows on that boot in the 24h window carry no header map, no address-valued clientIP. STILL OPEN: the pre-delivery corpus (every SOLEUR_ZOT_DISK row before boot 3b70b6ae still within retention — rows before the 2026-09-17 replace carried no redact(); rows on the 09-17 boot 78111e0e are corroboration, unproven either way; ADR-211 records 1,792 of 2,598 pre-Phase-B fallback rows carrying header STRUCTURE) is unread at value level, and tiers 1-3 are never warehouse-read. Ages out under the 90-day logs_retention of source 2457081 (measured 2026-09-04, #7772) by 2026-09-18 + 90d (≈2026-12-17) whether or not read. See §The open evidentiary limb, 2026-09-18 note."`
   - `art_33_deadline:` — replace `on the open limb below` with `on the still-open half of the limb below (narrowed 2026-09-18, #8309)`; the rest of the value unchanged.
   - `disposition:` — it is currently a PLAIN (unquoted) scalar, and a `: ` inside a plain scalar breaks YAML. Wrap the whole value in double quotes (the existing text contains no `"`) and append ` [2026-09-18 (#8309) — that limb is NARROWED; closed in part by the follow-through PASS, the pre-delivery corpus and the tiers 1-3 readback stay open.]` inside the quotes.
   - No `amended:` key: no audit file in the corpus carries one and nothing consumes it; the
     in-cell change plus the dated blockquotes are the record. (CLO suggested it; declined for
     minimality.)
2. Under §"The open evidentiary limb — stated rather than implied", after its last paragraph
   (the one ending `and says so in the register.`), append this blockquote verbatim (CLO text;
   leave one blank line before it; wrap at 100 cols but keep the bold heading on its first line):

   > **Narrowed 2026-09-18 (#8309 trigger — Phase B follow-through PASS): the limb is closed IN PART, not in full.** `scripts/followthroughs/zot-last-err-redact-7500.sh` PASSed 2026-09-18T14:10:58Z and closed #7960: on boot `3b70b6ae-e7d5-4218-993f-6d39c563a422` (delivered by `registry_host_replace`, workflow run 35353167115, 2026-09-18T14:03:52Z), 3 tier-4 rows in 24h, none carrying a header map, an address-valued `clientIP`, or a bracketed credential-header value. That satisfies the closure condition for post-delivery tier-4 rows — a stronger test than the one stated, on a 3-row sample. It does NOT read the pre-delivery corpus this paragraph describes (every `SOLEUR_ZOT_DISK` row before boot `3b70b6ae…` still within retention: rows before the 2026-09-17 replace carried no `redact()`, and rows on the 09-17 boot `78111e0e…` are corroboration, unproven either way; ADR-211 records 1,792 of 2,598 pre-Phase-B `fallback` rows carrying header STRUCTURE — structure, not a value-level finding either way), and it never reads tiers 1-3 (pre-merge suite only). No regression re-grade runs after the PASS. The unread half ages out under the 90-day `logs_retention` of source `2457081` (measured 2026-09-04, #7772) by 2026-09-18 + 90d (≈2026-12-17); if it lapses unread, this note is the record that it was never read, not that it was clean. What would reopen this determination is unchanged.

3. Under §"What I am explicitly NOT attesting to" item 4 (`It is inert.`), append
   `> **Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS):** "It is inert" was true on 2026-09-08 and is false now. Layer 1 is delivered on boot \`3b70b6ae…\` (probe PASS, proof \`err_redact_rev\`, tier4=3 leaking=0, tier-4 gate only). The register records delivery in every place it recorded inertness (five cells) in the same change as this note; I still do not attest to Layer 1's correctness beyond that readback — tiers 1-3 rest on the producer suite. (CLO agent, plan-time review 2026-09-18; the 2026-09-08 sign-off date above is unchanged.)`
4. Under Finding 1's sentence ending `answered by the controls at PA-8 §(g) — one of which is inert. See Finding 3.`, append
   `> **Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS):** "one of which is inert" was true on 2026-09-08; Layer 1 is delivered on boot \`3b70b6ae…\` (tier-4 gate graded clean — see item 4 under §What I am explicitly NOT attesting to).`
5. Under §"Re-evaluation triggers" bullet 3 (ending `since it survives Layer 2 and Layer 1 is inert.`), append
   `> **Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS):** Layer 1 is delivered; an unanticipated header name is now dropped by the producer allowlist at tiers 1-3 (suite-asserted) and withheld by the tier-4 gate (PASS-graded). This trigger now guards producer regression, which nothing re-grades after the PASS.`
6. Under §"Re-evaluation triggers" bullet 2 (`A registry-host-replace firing`), append
   `> **Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS):** fired 2026-09-18 (run 35353167115). The dated delivery entry is appended at PA-8 §(g) and at the four sibling cells that carried the inert posture, in the same change as this note.`

Two other limb references stay TRUE under partial closure and get no marker: §"What I am
explicitly NOT attesting to" item 2 ("See the open limb above" — it is still open in part) and
§"Re-evaluation triggers" bullet 4 ("The open warehouse limb being run" — the pre-delivery half
can still be run).

**Rendering rules for every appended blockquote (ADR and audit).** The ADR's existing
`> **Superseded 2026-09-18 (#7960)**` note is 2-space-indented inside the `- **Delivery state:**`
list item: insert a bare `  >` line between it and the new note and keep the 2-space indent, or the
two merge by lazy continuation. In the audit, item 4 is a numbered-list item (3-space continuation)
and trigger bullet 2 is a 2-space bullet: indent the new blockquote 3 spaces under item 4 and 2
spaces under the bullet, with a blank line before it, or an unindented `>` ends the list. When
wrapping at 100 cols keep each `Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS):`
literal on ONE line — the ACs count lines. Every `` \` `` sequence in this plan's code spans is
a plain backtick in the pasted text.

The `Superseded 2026-09-18 (#8309 trigger` literal therefore appears four times in the body
(items 3, 4, 5 and 6) and the limb note is headed `Narrowed 2026-09-18 (#8309 trigger` — AC8 counts both.

### Phase 4 — C4 model edge + regenerate

File: `knowledge-base/engineering/architecture/diagrams/model.c4`, `github -> publicReader` edge.
Replace the parenthetical `(ADR-211 Layer 1 — INERT until the next registry-host-replace, so this edge is currently guarded by the denylist alone)`
with `(ADR-211 Layer 1 — DELIVERED 2026-09-18, see ADR-211 Amendment 2026-09-18; the denylist here is the backstop, not the only guard)`. The model is a diagram label, not the evidentiary record — run ids, boots and verdicts live in ADR-211 and the register, so the edge points there. The parenthetical lives in the relation *title* (edge-detail panel and `model.likec4.json`), not on the drawn label, which is truncated at ~197 chars — expect no visible diagram diff.
Then `bash scripts/regenerate-c4-model.sh` and commit `model.likec4.json`. The pre-commit hook
does this too; the test is the authority.

### Phase 5 — Verification

The Acceptance Criteria are the verification; run them in order. `bash scripts/test-all.sh`
runs at its usual `/work` exit point and is not restated here.

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-211-zot-last-err-redaction-at-the-producer-and-the-sink.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
- `knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt` (all three regenerated and staged by the lefthook `generate-kb-index` hook)

## Files to Create

None.

## Acceptance Criteria

Let `ADR=knowledge-base/engineering/architecture/decisions/ADR-211-zot-last-err-redaction-at-the-producer-and-the-sink.md`,
`REG=knowledge-base/legal/article-30-register.md`,
`AUD=knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md`,
`C4=knowledge-base/engineering/architecture/diagrams/model.c4`.

### Pre-merge (PR)

1. `grep -c '^status: accepted' "$ADR"` returns `1` and `grep -c '^status: adopting' "$ADR"` returns `0`.
2. `grep -c '^## Amendment 2026-09-18' "$ADR"` returns `1`, and that section contains the literals
   `verdict=r3_pass`, `3b70b6ae-e7d5-4218-993f-6d39c563a422`, `tier4=3 leaking=0`, `35353167115`, and `5731215695`;
   and `grep -c '^\s*- \*\*Primary re-evaluation trigger' "$ADR"` returns `1` with `grep -c 'Fired: 2026-09-17' "$ADR"` returning `1`.
3. `grep -c 'Superseded 2026-09-18 (#8309 trigger' "$ADR"` returns `1` (the Delivery-state blockquote).
4. `grep -c 'Superseded 2026-09-18 (#8309 trigger' "$REG"` returns `5`, and each of the five
   census anchor sentences still appears verbatim: `grep -c 'INERT AND NOT IN FORCE until the next' "$REG"` returns `2`
   (§(c) and GitHub row), `grep -c 'is NOT in force and is inert until the next' "$REG"` returns `1`,
   `grep -c 'LAYER 1 IS INERT AND IS NOT IN FORCE' "$REG"` returns `1`, `grep -c 'REMAINS INERT AND IS NOT IN FORCE' "$REG"` returns `1`,
   `grep -c 'INERT until the next .registry-host-replace.\*\*' "$REG"` returns `1` (the `.` wildcards stand for the backticks in the cell — a backslash-escaped backtick is a buffer anchor in GNU grep, not a literal).
5. Every new entry in `$REG` sits inside its table cell: `grep -c '^|' "$REG"` is unchanged from
   `git show origin/main:"$REG" | grep -c '^|'` (no new table row; a `wc -l` comparison is deliberately not used — sibling PRs #8082/#8248/#8275 add lines to this file and would flip it on rebase).
6. Gates exit 0: `bash scripts/lint-legal-registers.sh`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; `bash plugins/soleur/test/c4-model-freshness.test.sh` (`c4-count-parity.test.sh` has no row for the `github -> publicReader` edge and the edit changes no cardinality; it still runs inside `test-all.sh`).
7. `$AUD` frontmatter, in-cell: `grep -c '^open_limbs: "ONE, NARROWED 2026-09-18 (#8309)' "$AUD"` returns `1`
   and `grep -c '^open_limbs: "ONE\. The Better Stack' "$AUD"` returns `0`;
   `grep -c '^art_33_deadline:.*narrowed 2026-09-18' "$AUD"` returns `1` and
   `grep -c 'on the open limb below would start' "$AUD"` returns `0`;
   `grep -c '^disposition: ".*NARROWED' "$AUD"` returns `1`; and the frontmatter still parses:
   `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]).read().split("---\n",2)[1])' "$AUD"` exits 0.
8. `grep -c 'Superseded 2026-09-18 (#8309 trigger' "$AUD"` returns `4` (NOT-attesting item 4,
   Finding 1, re-evaluation bullets 2 and 3) and `grep -c 'Narrowed 2026-09-18 (#8309 trigger' "$AUD"` returns `1`
   (the limb section); the original sentences `was NOT read for this`, `It is inert.`,
   `one of which is inert`, `and Layer 1 is inert`, and `A .registry-host-replace. firing` are still present (`grep -c` ≥ 1 each; `.` wildcards for the backticks). The limb section
   itself (not just the frontmatter) carries the figures:
   `sed -n '/^## The open evidentiary limb/,/^## Two pre-existing/p' "$AUD" | grep -c '1,792'` returns `1`,
   and the same pipe with `2026-12-17` returns `1`.
9. `grep -c 'INERT until the next registry-host-replace' "$C4"` returns `0` and
   `grep -c 'see ADR-211 Amendment 2026-09-18' "$C4"` returns `1`.
10. Script-name-only citation: in the diff, every occurrence of `zot-last-err-redact-7500.sh` is
    not followed by `:<digits>` or the word `line`:
    `git diff origin/main...HEAD | grep -E '^\+' | grep -cE 'zot-last-err-redact-7500\.sh(:[0-9]+|.{0,12}\bline\b)'` returns `0`.
11. Diff scope: `git diff origin/main...HEAD --name-only` is a subset of the eight paths in
    §Files to Edit plus `knowledge-base/project/plans/2026-09-18-docs-flip-adr-211-accepted-date-legal-records-plan.md`,
    `knowledge-base/project/specs/feat-one-shot-8309-adr211-accepted-legal-records/tasks.md`,
    and `knowledge-base/project/specs/feat-one-shot-8309-adr211-accepted-legal-records/session-state.md`.
    No file under `apps/`, `scripts/`, `plugins/`, `.github/`, or matching `*.tf` appears.

(`Closes #8309` / `Ref #7960` / `Ref #8272` in the PR body are `/ship`'s job under `wg-use-closes-n-in-pr-body-not-title-to`, not an AC here.)

## Domain Review

**Domains relevant:** legal

### Legal (CLO)

**Status:** reviewed
**Assessment:** the `clo` agent was briefed at plan time with the trigger evidence, what the probe
does and does not grade, the five-cell census, the 90-day retention bound, and the 1,792/2,598
pre-Phase-B structure figure (the facts that cut against a full closure), and read all three
files. Rulings, all folded into the phases above:

1. **Attestation limb — closed IN PART.** The prospective (post-delivery tier-4) half closes on the
   PASS; the pre-delivery corpus stays unread at value level, tiers 1-3 are never warehouse-read,
   and the unread half ages out by ≈2026-12-17 — the record must say so rather than lapse
   silently. Exact `open_limbs:` value and the three body blockquotes are the CLO's text
   (Phase 3). CLO also proposed an `amended:` frontmatter key — declined (no precedent, no
   consumer; recorded in Phase 3).
2. **Register — all five cells, no exceptions.** Each independently asserts current processing;
   the 2026-09-08 attestation chose repetition over cross-reference, so supersession is repeated
   at the same five points. One entry per cell (§(g) carries the sentence twice). §(g) must state
   the Layer 2 shift (backstop, not sole control) because the cell conditions "backstop against
   producer regression thereafter" on delivery. The §(c) "open evidentiary limb" sentence stays
   true and gets no marker. Canonical entry and per-cell clauses are the CLO's text (Phase 2).
3. **ADR-211 — "PROVEN delivered" objection sustained in part.** The ADR's own *Delivery proof*
   says `err_redact_rev` is evidence, and the CI pairing is the guarantee; the amendment must say
   "delivered per this ADR's own proof key … and the tier-4 gate graded clean — 3 rows in 24h,
   0 leaking", never "PROVEN". Two omissions in the brief the CLO caught and the plan now carries:
   the Status bullet needs its own dated bracket (or the prose contradicts the machine field), and
   the new Delivery-state note must keep the 2026-09-17 replace (boot `78111e0e…`, 272 rows,
   corroboration) distinct from the 2026-09-18 replace that delivered the proof key.
4. **Brief corrections:** the audit section is titled "What I am explicitly NOT attesting to";
   the retention figure is recorded under the 2026-09-04 (#7772) correction — cite #7772.

Draft material; v1 internal sign-off, external re-review per the attestation's standing triggers.
The ship Phase 5.5 counsel-review gate does not fire (threshold `none`, no DRAFT marker); this
plan-time review is the legal review of record for the wording.

## Test Scenarios

Docs only — the ACs above are the test battery. The two executable gates are
`scripts/lint-legal-registers.sh` and `plugins/soleur/test/c4-model-freshness.test.sh`.

## Risks & Mitigations

- **Overclaim in a legal record.** Every entry carries the PASS's scope limit verbatim and names
  the vehicle; the superseded sentence is never edited.
- **Rebase conflict on §(d) with #8275.** Both append at the same cell's end; resolution is
  "keep both brackets, this one last". Not a correctness risk.
- **Regenerated artifacts drift.** `model.likec4.json` and `INDEX.md` are regenerated by
  script/hook, and the freshness test is the authority.

## Alternatives Considered

| Option | Verdict |
|---|---|
| Append only to the two cells the issue names | Rejected — three sibling cells and the C4 edge assert the same posture; leaving them reads as three live inert claims beside two superseded ones. |
| Close `open_limbs` to `none` | Rejected by the CLO ruling — the PASS reads post-delivery tier-4 rows only; the pre-delivery corpus read the limb describes was not run. Narrow, do not zero. |
| Fold in #8218 | Rejected — different sentences, unverified trigger, operator asked for a bounded PR. |

## Plan Review Revisions (2026-09-18)

Eng panel (DHH, Kieran, code-simplicity); named panel not activated (no UI, product, market, or
code surface). Applied as Mechanical: Delivery-state and C4 texts cut to pointers (one fact, one
home — ADR-184 shape); AC14/AC15 and the `amended:`-absence grep cut, AC6/10/12 folded; `wc -l`
half of AC5 dropped (sibling PRs flip it on rebase); `kb-tags.txt`/`kb-categories.txt` added to the
diff-scope set (the lefthook hook stages all three); §(g) append point fixed to the cell's end in
date order; `disposition:` must be double-quoted (a `: ` in a plain scalar breaks YAML — AC7 now
parses the frontmatter); backtick-escaped grep patterns replaced with `.` wildcards (a `\`` is a
buffer anchor in GNU grep); the CLO limb blockquote pasted verbatim; rendering rules for nested
blockquotes; 90-day arithmetic written out (≈2026-12-17); two audit limb references recorded as
still-true. Declined as Taste: shortening the CLO-authored `open_limbs:` value (the CLO ruled the
wording; a frontmatter cell that is true and points would also pass AC7 — revisit only if the CLO
re-rules); trimming Research Insights (deepen-plan reads it).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`
  Phase 4.6; it is filled above.
- `lint-infra-no-human-steps.py` scans this plan file and ADR-211: keep actor tokens away from
  infra imperatives outside fenced blocks.
