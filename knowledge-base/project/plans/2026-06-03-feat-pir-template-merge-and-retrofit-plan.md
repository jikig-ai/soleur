<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO infrastructure (no server, service, cron,
     vendor account, secret, DNS, cert, or firewall rule). This is an internal incident-authoring
     template + 4 internal ops documents. The IaC routing gate does not apply. -->
---
title: "feat: Merge richer PIR template structure and retrofit existing post-mortems"
date: 2026-06-03
type: enhancement
branch: feat-one-shot-postmortem-template-retrofit
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# feat: Merge richer PIR template structure and retrofit existing post-mortems

## Enhancement Summary

**Deepened on:** 2026-06-03

**Baseline verifications run at deepen time (all green pre-change):**

- `redact-sentinel.test.sh` → `Total: 19 pass, 0 fail`. The negative-baseline
  (`dashboard-error-postmortem.md`) exits 0 (CLEAN) today — confirms the AC4
  hard constraint's starting state is achievable; the retrofit must KEEP it
  clean.
- Both `dry-run.sh` fixtures exit 0 today.
- `pir.md` currently has **16** `{{TOKEN}}`s; `SKILL.md` Phase 4 table has 16
  rows — AC3 bidirectional parity holds today and must hold after the merge.
- **MTTR local-compute validated in this env:**
  `date -u -d "2026-05-18T16:55:00Z" +%s − date -u -d "2026-05-18T09:36:00Z" +%s`
  = 26340s = `7h19m`, exactly matching the cloudflare frontmatter window. The
  FR7 local-duration approach is feasible; no LLM-emitted duration needed.

**Key deepen findings folded in:**

1. The token contract is a THREE-way mirror, not two-way: `pir.md` ↔ SKILL.md
   Phase 4 table ↔ `dry-run.sh` heredoc. AC3 covers template↔SKILL; the
   heredoc is covered by AC5/AC7 (dry-run emits no raw `{{`). All three must
   move together — see the expanded Phase Order note.
2. The sentinel baseline being CLEAN today means the retrofit's ONLY sentinel
   risk is *introducing* a new token shape; it cannot "fix" a pre-existing
   hit because there are none. This narrows the AC4 risk surface.
3. `date -u -d` arithmetic confirmed available — MTTR/MTTD compute is a 2-line
   bash addition to both SKILL.md Phase 0 and `dry-run.sh`, with the empty
   `recovery_at` guard the only edge case.

### Precedent-Diff Gate (Phase 4.4)

No novel pattern-bound behavior (no SQL `SECURITY DEFINER`, no atomic-write
sequence, no lock/RPC/cron). The CANONICAL precedent for the change IS the
existing `pir.md` template + the `dry-run.sh` here-doc (which already inlines
the static section bodies — `dry-run.sh:172-230`). The merge EXTENDS this
established form; it does not introduce a new one. No scheduled job → the
Inngest-vs-GH-Actions check (Phase 4.4) does not apply.

## Overview

Improve the incident post-mortem (PIR) template at
`plugins/soleur/skills/incident/templates/pir.md` by MERGING the richer
section structure from the operator-provided reference template
(`/home/jean/Downloads/Post-Mortem Template 28e9e6a7a3c180638903e0d77bd7f2ba.md`)
into the existing template, WITHOUT dropping any of the existing template's
load-bearing GDPR/redaction/role-impact machinery. Then keep the substitution
contract consistent (`SKILL.md` Phase 0 + Phase 4, fixtures, dry-run) and
retrofit the 4 existing post-mortems under
`knowledge-base/engineering/ops/post-mortems/` to the merged shape "when
possible" (judgment per file; preserve all facts; mark missing facts as
`Unknown`/`N/A`, never fabricate).

**Direction (confirmed):** the reference template is a *donor of structure*;
the in-repo `pir.md` is the *recipient and source of truth*. Merge reference
sections INTO `pir.md`, never the reverse. The reference file is outside the
repo and is not edited.

This is an internal tooling + docs change. No application code, no
infrastructure, no schema, no regulated-data surface. `brand_survival_threshold: none`.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (direct plan entry). The ARGUMENTS block is
the spec. The following premises from the ARGUMENTS were verified against the
codebase at plan time:

| Claim (from ARGUMENTS) | Reality (verified) | Plan response |
|---|---|---|
| `pir.md` has GDPR frontmatter, Actor key, `{{SECRET_LEAK_PREAMBLE}}`, hypothesis table, role-impact, recovery-verification | Confirmed — all present (`pir.md:1-58`) | Preserve verbatim; merge new sections around them |
| SKILL.md Phase 4 has a substitution token table | Confirmed (`SKILL.md:111-128`, 16 tokens) | Extend with new tokens |
| `dashboard-error-postmortem.md` is the shape anchor | Confirmed — cited in `SKILL.md:20`, `ship/SKILL.md:816`, `plan/SKILL.md` | Retrofit it AND keep the anchor consistent |
| `dashboard-error-postmortem.md` is ALSO the sentinel negative-baseline | Confirmed (`redact-sentinel.test.sh:22` — MUST exit 0) | **Hard constraint**: retrofit must keep it sentinel-clean (see Sharp Edges) |
| Fixtures + dry-run.sh exercise the template shape | Confirmed (`test/fixtures/*.json`, `dry-run.sh` heredoc at `:173-229`) | Add new fields to fixtures + new sections to dry-run heredoc |
| `components.test.ts` asserts on template shape | FALSE — it only checks skill `description:` word budget; no template-shape assertion | No change needed to `components.test.ts` |
| 4 post-mortems exist under post-mortems/ | Confirmed (chat-rls, dashboard-error, sentry-phantom, cloudflare-526) | Retrofit all 4 per judgment |

**Premise Validation note:** All cited in-repo artifacts (template, SKILL.md
phases, fixtures, dry-run, sentinel test, 4 PIRs) exist and hold. Two
divergences found, neither blocking: (1) `dry-run.sh:282` prints a STALE
`runbooks/${slug}-postmortem.md` write-path string (skill writes to
`post-mortems/`) — opportunistic fix folded in. (2) The `chat-rls` PIR cites
`knowledge-base/project/learnings/2026-06-02-rls-column-add-must-sweep-all-insert-sites-and-alert-op-is-not-the-user-failure.md`
which does NOT exist on disk — this is a pre-existing citation inside a file
being retrofitted; do NOT fabricate the learning and do NOT touch that citation
(out of scope; retrofit preserves existing prose). The forward reference
`wg-incident-detected-always-run-postmortem` in the chat-rls PIR is likewise
not in AGENTS*.md — pre-existing, out of scope.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this
touches an internal incident-authoring skill template and 4 internal ops
documents. The only "user" is the operator authoring a future PIR; a broken
template would surface as a malformed PIR draft at `/soleur:incident` Phase 4
(caught immediately in the inline review at Phase 7 before any commit).

**If this leaks, the user's data is exposed via:** N/A — the change adds no
new data path. The redaction sentinel (`redact-sentinel.sh`) and its
pre-inline-emit ordering (Phase 6) are PRESERVED unchanged; the new template
sections are static prose/placeholders that flow through the same sentinel
gate as today.

**Brand-survival threshold:** none — internal tooling + docs change, no
user-facing artifact, no credential surface, no billing path. `threshold:
none, reason: internal incident-authoring template + 4 internal ops documents; no production code, schema, or data surface touched.`

## Goals

1. Merge the reference template's richer structure into `pir.md` while
   preserving every load-bearing element.
2. Keep the `/soleur:incident` substitution contract internally consistent
   (Phase 0 capture ↔ Phase 4 token table ↔ template `{{TOKEN}}`s ↔ fixtures
   ↔ dry-run heredoc).
3. Compute MTTR/MTTD locally from timestamps (FR7 LLM-trust boundary), not
   from LLM-emitted durations.
4. Retrofit the 4 existing PIRs to the merged shape where the source data
   supports it; never fabricate missing facts.
5. Keep `dashboard-error-postmortem.md` as the canonical shape anchor AND
   keep it sentinel-clean (negative-baseline test stays green).
6. Verify the substitution contract via the incident skill's
   dry-run + sentinel tests.

## Non-Goals

- No public-facing PIR summary (Phase 5 stays deferred to #3732).
- No change to the redaction sentinel regex classes or its exit-code contract.
- No change to the Art. 33/34 gate logic (Phase 2) or the COMMIT-PIR token gate.
- No fabrication of revenue/MTTD/MTTR/participant data the source PIRs do not
  contain — those become `Unknown` / `N/A` with a one-line reason.
- No new AGENTS.md rule (the `wg-incident-detected-always-run-postmortem`
  forward reference is out of scope).
- No creation of the missing RLS learning file cited by the chat-rls PIR.

## Merged Template Design

The merge interleaves the reference template's sections with the existing
machinery. Section ORDER in the merged `pir.md` (preserving existing anchors,
adding new ones):

1. **YAML frontmatter** — UNCHANGED set of existing fields
   (`title, date, incident_pr, incident_window, suspected_change,
   brand_survival_threshold, status, triggers, art_33_triggered,
   art_34_triggered, art_33_deadline, {{CLASSIFICATION_OVERRIDE_BLOCK}}`)
   PLUS new optional fields (see "New tokens" below). All existing GDPR
   fields stay — `hr-gdpr-gate-on-regulated-data-surfaces`.
2. **Actor key** — UNCHANGED (`agent` / `agent-with-ack` / `human`).
3. `{{SECRET_LEAK_PREAMBLE}}` — UNCHANGED (REVOKE FIRST, TR2).
4. **Incident Overview** — NEW (`{{INCIDENT_OVERVIEW}}`, 1-2 sentence summary).
5. **Status** — NEW prose mirror of frontmatter `status`
   (resolved / unresolved but ended / ongoing). Sourced from
   frontmatter, not a new token (avoid duplicate-source drift).
6. **Symptom** — UNCHANGED (`{{SYMPTOM}}`). Kept distinct from Incident
   Overview: Overview = 1-2 sentence executive summary; Symptom = full
   operator prose.
7. **Incident Timeline** — MERGE. Keeps the existing `## Timeline` Actor/Time/Action
   table (load-bearing: redaction-sentinel scans it, Actor key feeds it).
   ADDS three sub-fields above the table: **Start Time** (`{{DETECTED_AT}}`),
   **End Time** (`{{RECOVERY_AT}}`, new), **Duration (MTTR)** (`{{MTTR}}`, new,
   locally computed). The reference's "Order of Events" maps onto the existing
   Actor/Time/Action table (no duplicate list).
8. **Participants and Systems Involved** — NEW (`{{PARTICIPANTS}}`).
9. **Detection (+ MTTD)** — NEW (`{{DETECTION_METHOD}}` how detected:
   monitoring vs external/manual; `{{MTTD}}` locally computed, new).
10. **Triggered by** — NEW (`{{TRIGGERED_BY}}`: user / system / market / provider).
11. **Root-cause hypothesis (triage)** — UNCHANGED hypothesis TABLE
    (`{{ROOT_CAUSE_HYPOTHESIS}}`). Reconciliation with 5-Whys: the table is
    the *triage-time* artifact (competing hypotheses + evidence + status);
    the 5-Whys is the *post-resolution final* artifact. Both kept — the table
    feeds Phase 1 diagnosis, the 5-Whys feeds the post-mortem analysis.
12. **Resolution** — NEW (`{{RESOLUTION}}`: which actions resolved it).
13. **Recovery verification** — UNCHANGED (cite green run / dashboard / query,
    not eyeball — `hr-no-dashboard-eyeball-pull-data-yourself`).
14. `---` divider → **Incident Post-Mortem Analysis** (reference's H1 split).
15. **Root Cause(s) — 5-Whys** — NEW (`{{ROOT_CAUSE_5WHYS}}`). The final
    root cause via 5-Whys, distinct from the triage hypothesis table.
16. **Versions of Components** — NEW: version that triggered
    (`{{VERSION_TRIGGERED}}`) + version that restored (`{{VERSION_RESTORED}}`).
17. **Impact details** — MERGE/RECONCILE:
    - **Services Impacted** — NEW (`{{SERVICES_IMPACTED}}`).
    - **Customer Impact** — RECONCILED with the existing role-based
      "Who was affected (by role)" section. **Decision: keep the role-based
      enumeration as the canonical Customer Impact** (per learning
      `2026-05-06-user-impact-section-by-role-not-surface.md` — by ROLE not
      surface). Retitle the merged section
      **"Customer Impact (by role)"** so it satisfies BOTH the reference's
      "Customer Impact" slot AND the role-enumeration learning. Do NOT add a
      second free-text Customer Impact block — that would duplicate and invite
      surface-based drift. The 6 role rows
      (Prospect / Authenticated app user / Legal-document signer / Admin via
      Access / Billing customer / OAuth installation owner) are preserved
      verbatim as the section body (kept static; SKILL.md does not substitute
      per-role).
    - **Revenue Impact** — NEW (`{{REVENUE_IMPACT}}`; default placeholder
      `Unknown / N/A` when uncaptured).
    - **Team Impact** — NEW (`{{TEAM_IMPACT}}`).
18. **Lessons Learned** — NEW, three sub-headings: **Where we got lucky**
    (`{{LUCKY}}`), **What went well** (`{{WENT_WELL}}`), **What went wrong**
    (`{{WENT_WRONG}}`).
19. **Follow-ups** — UNCHANGED (`## Follow-ups` checklist).
20. **Action Items** — NEW (`{{ACTION_ITEMS}}`: GitHub issues to prevent
    recurrence — logs, tests, alerts, automation, docs, PRs). Reconciled with
    Follow-ups: Follow-ups = the running checklist during the incident;
    Action Items = the enumerated GitHub-issue list to file. Keep both per the
    reference, but the merged template notes they may overlap and the author
    should not duplicate (one bullet per concern, cross-referenced).

**Placeholder convention:** every new section gets a `{{TOKEN}}` so the
substitution contract is mechanical. Sections the operator may legitimately
leave empty (Revenue Impact, Team Impact, Version Restored, MTTD when
externally detected) default to `Unknown` / `N/A` with a one-line reason —
NEVER blank, so a retrofit or a fresh PIR never silently drops a section.

## MTTR / MTTD local computation (FR7)

Per FR7 LLM-trust boundary, durations are computed locally from timestamps,
never trusted from an LLM-emitted blob. Add to `SKILL.md` Phase 0 capture:

- `recovery_at` — ISO-8601 UTC, validated against the SAME regex as
  `detected_at` (`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`)
  before substitution. Optional (empty → status not yet resolved → MTTR `TBD`).
- `monitoring_detected_at` — ISO-8601 UTC, optional. When detection was via
  monitoring, MTTD = `monitoring_detected_at − incident_start`. When detection
  was external/manual, MTTD = `Unknown (external/manual report)`.

Compute (SKILL.md Phase 0 "Compute locally" block + dry-run.sh):

- `MTTR` = `recovery_at − detected_at`, rendered as a human duration
  (e.g. `7h19m`). Use `date -u -d` epoch subtraction:
  `mttr_secs=$(( $(date -u -d "$recovery_at" +%s) - $(date -u -d "$detected_at" +%s) ))`,
  then format. Guard: if `recovery_at` empty → `MTTR = TBD (status not resolved)`.
- `MTTD` = as above; guard for the external/manual case.

These are computed in the skill (and in `dry-run.sh`), substituted into
`{{MTTR}}` / `{{MTTD}}`. The template carries the placeholders only.

## New substitution tokens (SKILL.md Phase 4 table additions)

Every new `{{TOKEN}}` in the template MUST get a row in the Phase 4 table and
(where operator-supplied) a Phase 0 capture line. New tokens:

| Token | Source |
|---|---|
| `{{INCIDENT_OVERVIEW}}` | Phase 0 `incident_overview` (operator prose, sentinel-scanned + sed-escaped) |
| `{{RECOVERY_AT}}` | Phase 0 `recovery_at` (ISO-8601 validated; default `TBD`) |
| `{{MTTR}}` | Computed locally from `recovery_at − detected_at` |
| `{{MTTD}}` | Computed locally; `Unknown (external/manual)` when not monitoring-detected |
| `{{PARTICIPANTS}}` | Phase 0 `participants` (default `Operator (single founder)`) |
| `{{DETECTION_METHOD}}` | Phase 0 `detection_method` enum: `monitoring \| external \| manual` |
| `{{TRIGGERED_BY}}` | Phase 0 `triggered_by` enum: `user \| system \| market \| provider` |
| `{{RESOLUTION}}` | Phase 0 `resolution` (operator prose) |
| `{{ROOT_CAUSE_5WHYS}}` | Phase 7 review (operator fills, default `TBD`) |
| `{{VERSION_TRIGGERED}}` | Phase 0 `version_triggered` (repo + version/PR/SHA) |
| `{{VERSION_RESTORED}}` | Phase 0 `version_restored` (default `N/A — not yet restored`) |
| `{{SERVICES_IMPACTED}}` | Phase 0 `services_impacted` |
| `{{REVENUE_IMPACT}}` | Phase 0 `revenue_impact` (default `Unknown / N/A`) |
| `{{TEAM_IMPACT}}` | Phase 0 `team_impact` (default `Unknown / N/A`) |
| `{{LUCKY}}` / `{{WENT_WELL}}` / `{{WENT_WRONG}}` | Phase 7 review (default `TBD`) |
| `{{ACTION_ITEMS}}` | Phase 7 review (default `TBD — file as GitHub issues`) |

All operator-prose tokens (`incident_overview`, `participants`, `resolution`,
`services_impacted`, `revenue_impact`, `team_impact`) flow through the SAME
sed-metacharacter escaping + first-pass sentinel scan as `title`/`symptom`
(SKILL.md LLM-trust boundary section). Add them to the
"run through sed-escaping / first-pass sentinel" enumeration so a `&`/`/` in
operator prose cannot corrupt the template and a pasted secret cannot reach
the transcript un-redacted.

## Retrofit plan (4 PIRs, judgment per file)

The merged template's NEW sections are additive; retrofit means restructuring
existing prose under the new headings + filling new sections from existing
facts, marking gaps `Unknown`/`N/A`. Preserve ALL existing factual content and
every existing frontmatter field.

### A. `dashboard-error-postmortem.md` (the anchor + sentinel negative-baseline)

- **Highest-risk file.** It is (a) cited as the canonical shape anchor in
  `SKILL.md:20`, `ship/SKILL.md:816`, `plan/SKILL.md`, and (b) the sentinel
  negative-baseline (`redact-sentinel.test.sh:22` — MUST exit 0).
- Retrofit to the merged shape so it remains the faithful anchor. It already
  has: hypothesis table, Confirmed Root Cause, Phase 1/2 diagnosis,
  Recovery Verification, Why-both-gates-failed table, Follow-up issues table.
- Map existing → new: "Three failures, one incident" + first para → Incident
  Overview; existing root-cause table → Root-cause hypothesis (triage);
  Confirmed Root Cause → Root Cause(s) 5-Whys (reframe as 5-Whys); the
  v0.58.1→v0.58.2 detail → Versions of Components; Why-both-gates-failed →
  Lessons Learned (What went wrong); Follow-up issues table → Action Items;
  add Customer Impact (by role) — derive 6 role rows from the facts
  ("every authenticated visitor to /dashboard"). MTTR = `22:37:08Z − 22:22Z`
  ≈ `~15m` (compute exactly); MTTD = `Unknown (external/manual — direct
  browser report)`; Revenue Impact = `Unknown / N/A`; Triggered by = `system
  (deploy of PR #3007)`.
- **HARD CONSTRAINT — keep sentinel-clean.** After retrofit, run
  `bash plugins/soleur/skills/incident/scripts/redact-sentinel.sh
  knowledge-base/engineering/ops/post-mortems/dashboard-error-postmortem.md`
  and confirm exit 0. The file currently contains JWT-shaped grep patterns
  (`eyJ...` at `:129`), a decoded `iss=supabase` payload (`:271`), DSN-shaped
  strings, and a Supabase ref `ifsccnjhymdmidffkzhl` — these pass TODAY because
  they don't match the sentinel's *anchored* token classes (the `eyJ` pattern
  is inside a grep-pattern literal, not a real 3-segment JWT; the ref is not a
  UUID). **Any retrofit edit MUST NOT introduce a new email, UUID, IPv4, or
  real token shape.** Do NOT "clean up" the example payload into a realistic
  token. Re-run the full `redact-sentinel.test.sh` after the edit (Test 1 is
  this file).

### B. `chat-rls-workspace-id-outage-postmortem.md`

- Already near-conformant: has hypothesis table, Timeline, Recovery
  verification, Contributing factors, Follow-ups, Who-affected-by-role,
  Prevention, an Update section.
- Add: Incident Overview (from Symptom first sentence); Status (prose,
  `resolved`); Detection (+ MTTD) — `external/manual (user report)`, MTTD
  `Unknown (~3 weeks silent; first signal was user report 2026-06-02 16:11Z)`;
  Triggered by `system (migration 059)`; Participants `Operator (single
  founder) + Claude Code agent; systems: Supabase Postgres, web-platform chat
  dispatch`; Resolution (from the PR #4831 + #4839-fix prose); Versions of
  Components — triggered `migration 059` (+ `053` for template_id), restored
  `PR #4831` / `#4839-fix`; Services Impacted `interactive chat message
  persistence`; Revenue Impact `Unknown / N/A (pre-revenue; single
  founder/tenant-zero)`; Team Impact `~3 weeks silent breakage, ~6h triage
  including one misdiagnosis`; Lessons Learned (got-lucky: only tenant-zero
  affected; went-well: #4816 noise reduction surfaced the real error;
  went-wrong: 4 contributing factors already enumerated → map). Customer
  Impact: the existing Who-affected-by-role becomes "Customer Impact (by
  role)". Action Items: map the existing Follow-ups list.
- `art_33/34` already `false` with rationale — preserve verbatim.

### C. `sentry-phantom-ingest-destination-unreachable-postmortem.md`

- Most complex (Phase 8 recovery-completeness gates, Phase 9 correction).
  Retrofit LIGHTLY — judgment call: this file's bespoke Phase 8/9 structure is
  load-bearing audit-trail content that must NOT be flattened into the generic
  template. **Decision: add the new top-of-file sections (Incident Overview,
  Status, Detection+MTTD, Triggered by, Participants, Resolution, Versions of
  Components, Impact details incl. Customer-Impact-by-role rename, Lessons
  Learned, Action Items) but PRESERVE Phase 8 + Phase 9 + the existing
  Root-cause table / Timeline / Recovery-verification / Who-affected-by-role
  verbatim.** The classification_override block stays. MTTR = the window is
  `2026-03-28 → 2026-05-21` but "resolution" is the Phase 9 reattribution, not
  a service restore — render MTTR as `N/A (no service outage — phantom-ingest
  reattributed to operator-owned org; see Phase 9)` with a one-line reason.
  MTTD = `~49 days (external/manual — surfaced during A2 brainstorm prereq)`.
  Triggered by `provider (Sentry region-routing + ingest permissiveness) +
  system (PR #1235 DSN introduction)`. Revenue Impact `Unknown / N/A`.
- Sentinel note: this file contains a real operator email (multiple
  occurrences), a bot email, org IDs, a proxy-user email. **It is NOT the
  negative-baseline** (only `dashboard-error` is), so the sentinel test does
  not gate it — but DO NOT add new emails/UUIDs/IPs during retrofit, and run
  the sentinel against it post-retrofit as a courtesy check (expected: it
  reports the pre-existing emails; acceptable because this file is not the
  test baseline — record the pre-existing hits so reviewers know they predate
  this PR).

### D. `soleur-ai-marketing-site-cloudflare-526-ssl-outage-2026-05-18-postmortem.md`

- Has hypothesis table, Timeline, Recovery verification, Follow-ups,
  Who-affected-by-role, classification_override.
- Add: Incident Overview; Status (`resolved`); Detection+MTTD —
  `external/manual`, MTTD `Unknown (visitor-facing; first detected
  2026-05-18T09:36Z — no marketing analytics/alert)`; Triggered by
  `provider (Let's Encrypt cert expiry) + latent IaC defect`; Participants
  `Operator (single founder); systems: Cloudflare, GitHub Pages, Let's
  Encrypt`; Resolution (from PR #3986 prose); Versions of Components —
  triggered `latent defect from initial IaC PR #3974`, restored `PR #3986`;
  Services Impacted `soleur.ai marketing site (apex + www)`; Revenue Impact
  `Unknown / N/A`; Team Impact `~7h19m hands-on recovery`; Lessons
  Learned (got-lucky: app.soleur.ai on separate origin unaffected; went-wrong:
  zone toggle not IaC-managed + no cert-expiry monitor; went-well: fix-forward
  within the window). MTTR = `09:36:00Z → 16:55:00Z` = `7h19m` (matches the
  frontmatter window — compute and confirm). Customer Impact (by role): rename
  existing Who-affected-by-role. Action Items: map existing Follow-ups.

## Files to Edit

- `plugins/soleur/skills/incident/templates/pir.md` — merge new sections +
  new `{{TOKEN}}`s, preserve all existing machinery.
- `plugins/soleur/skills/incident/SKILL.md` — Phase 0 capture (add new
  operator fields + `recovery_at` / `monitoring_detected_at` local-compute
  lines + MTTR/MTTD computation); Phase 4 token table (add every new token);
  LLM-trust-boundary section (add new prose tokens to the sed-escape +
  first-pass-sentinel enumeration). Keep the `description:` UNCHANGED (no word
  budget risk; verify with `bun test plugins/soleur/test/components.test.ts`).
- `plugins/soleur/skills/incident/scripts/dry-run.sh` — parse new fixture
  fields; compute MTTR/MTTD locally; emit the new template sections in the
  Phase 4 heredoc so the draft matches the new template shape; fix the stale
  `runbooks/` → `post-mortems/` write-path string at `:282`.
- `plugins/soleur/skills/incident/test/fixtures/dry-run-incident.json` — add
  the new operator fields (`incident_overview`, `recovery_at`,
  `monitoring_detected_at`, `participants`, `detection_method`,
  `triggered_by`, `resolution`, `version_triggered`, `version_restored`,
  `services_impacted`, `revenue_impact`, `team_impact`). Synthetic only
  (`cq-test-fixtures-synthesized-only`).
- `plugins/soleur/skills/incident/test/fixtures/dry-run-secret-leak.json` —
  same field additions (secret-leak path still exercises the new shape).
- 4 PIRs under `knowledge-base/engineering/ops/post-mortems/` — retrofit per
  section A-D above.

## Files to Create

- None. (Plan + tasks.md are created by the planning workflow.)

## Open Code-Review Overlap

Queried open `code-review`-labeled issues for the planned file paths:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for p in plugins/soleur/skills/incident/templates/pir.md plugins/soleur/skills/incident/SKILL.md \
         plugins/soleur/skills/incident/scripts/dry-run.sh \
         knowledge-base/engineering/ops/post-mortems/dashboard-error-postmortem.md; do
  jq -r --arg path "$p" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

None — to be confirmed at /work Phase 0 (run the query; record `None` or fold-in/acknowledge/defer per match).

## Acceptance Criteria

### Pre-merge (PR)

1. `plugins/soleur/skills/incident/templates/pir.md` contains ALL existing
   load-bearing elements — verified by grep returning ≥1 each:
   `art_33_triggered`, `art_34_triggered`, `art_33_deadline`,
   `brand_survival_threshold`, `{{CLASSIFICATION_OVERRIDE_BLOCK}}`,
   `{{SECRET_LEAK_PREAMBLE}}`, `Actor key`, `agent-with-ack`, `Recovery
   verification`, and the role-impact rows (`Prospect`, `Authenticated app
   user`, `Legal-document signer`, `Admin via Access`, `Billing customer`,
   `OAuth installation owner`), AND the triage `## Root-cause hypothesis` table
   header (`| Hypothesis | Supporting evidence | Disconfirming evidence |
   Status |`).
2. `pir.md` contains the new section headings: `Incident Overview`, `Detection`,
   `MTTD`, `Triggered by`, `Resolution`, `Versions of Components`,
   `Services Impacted`, `Customer Impact`, `Revenue Impact`, `Team Impact`,
   `Where we got lucky`, `What went well`, `What went wrong`, `Action Items`,
   and a `5` (5-Whys) marker in the Root Cause analysis section.
3. **Token contract closed both ways:** every `{{TOKEN}}` in `pir.md` appears
   in the SKILL.md Phase 4 table, and every token row in the Phase 4 table
   appears in `pir.md`. Verify with the diff:
   ```bash
   comm -3 \
     <(grep -oE '\{\{[A-Z_0-9]+\}\}' plugins/soleur/skills/incident/templates/pir.md | sort -u) \
     <(grep -oE '\{\{[A-Z_0-9]+\}\}' plugins/soleur/skills/incident/SKILL.md | sort -u)
   ```
   returns empty (every template token is referenced in SKILL.md and vice-versa).
4. `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` exits 0
   (`Total: N pass, 0 fail`) — **Test 1 (negative-baseline on the retrofitted
   `dashboard-error-postmortem.md`) MUST stay green.**
5. `bash plugins/soleur/skills/incident/scripts/dry-run.sh
   plugins/soleur/skills/incident/test/fixtures/dry-run-incident.json` exits 0
   and stdout contains the new section headings (Incident Overview, Detection,
   MTTR, Versions of Components, Customer Impact, Action Items) AND a computed
   MTTR/MTTD value (not a raw `{{TOKEN}}`).
6. `bash plugins/soleur/skills/incident/scripts/dry-run.sh
   plugins/soleur/skills/incident/test/fixtures/dry-run-secret-leak.json` exits
   0 and still shows the REVOKE-FIRST secret-leak preamble (preamble logic
   untouched).
7. No raw `{{TOKEN}}` leaks into dry-run output: `grep -c '{{' /tmp/pir-dry-run.txt`
   returns 0 (every token the dry-run handles is substituted).
8. All 4 retrofitted PIRs preserve their existing frontmatter fields (diff
   shows no frontmatter field REMOVED — only additions). Verify per file that
   `art_33_triggered`, `art_34_triggered`, `brand_survival_threshold`, `status`
   still present.
9. `dashboard-error-postmortem.md` is still referenced as the anchor in
   `SKILL.md:20` (grep `dashboard-error-postmortem` returns the anchor line
   unchanged) — the retrofit did not break the canonical-shape reference.
10. `bun test plugins/soleur/test/components.test.ts` passes (skill
    description word budget unaffected — `description:` not edited).
11. The stale `runbooks/${slug}-postmortem.md` string in `dry-run.sh:282` is
    corrected to `post-mortems/` (`grep -n 'runbooks/.*postmortem' dry-run.sh`
    returns nothing).

### Post-merge (operator)

None — no infra apply, no migration, no external-service config. The PR is
self-contained (template + skill + tests + docs). There are no operator-only
steps.

## Research Insights

**PIR-template conventions (the reference template follows standard SRE
practice):** the donor sections map onto well-established blameless-postmortem
conventions — MTTR (Mean Time To Recovery) and MTTD (Mean Time To Detect) are
Google-SRE-standard incident metrics; the 5-Whys is the canonical root-cause
technique; "Where we got lucky / What went well / What went wrong" is the
standard blameless retro triad. Adopting them aligns Soleur's PIRs with
industry norms without inventing bespoke structure. The one Soleur-specific
deviation we PRESERVE is the role-based Customer Impact enumeration (learning
`2026-05-06-...`), which is *stronger* than the reference's free-text "Customer
Impact" because it forces per-population blast-radius analysis.

**Code-simplicity guardrail (avoid over-tokenizing):** not every new section
needs operator input at Phase 0. Sections filled only during the Phase 7
post-resolution review (5-Whys, Lessons Learned triad, Action Items) get a
`{{TOKEN}}` with a static `TBD` default — they do NOT need a Phase 0 capture
prompt. Only the sections an operator can answer at incident-open time
(overview, participants, detection method, triggered-by, version-triggered)
get a Phase 0 line. This keeps Phase 0 short (the <60s classification budget)
and avoids prompting for data that does not exist yet. Status is sourced from
frontmatter (no new token) — one source of truth.

**Retrofit fidelity (do-not-fabricate is the dominant constraint):** every
retrofit section maps to existing facts in the source PIR or to an explicit
`Unknown`/`N/A` with a one-line reason. The four files were read end-to-end at
plan time; per-file mappings in the Retrofit plan above cite the specific
existing prose each new section is derived from. The `sentry-phantom` file's
Phase 8/9 audit trail is preserved verbatim (light-touch retrofit) because
flattening it into the generic Lessons Learned would lose load-bearing
GDPR/recovery-gate provenance.

## Test Strategy

Existing test infra (no new framework): `redact-sentinel.test.sh` (bash,
`set -uo pipefail`, PASS/FAIL counter — confirmed installed convention) and
`dry-run.sh` (bash). `components.test.ts` runs under the repo's existing test
runner (`bun test`, confirmed by AGENTS.md skill checklist). No new test files
required; extend the two fixtures and re-run the two bash harnesses + the
component test.

RED→GREEN ordering: edit `pir.md` (new shape) → update SKILL.md Phase 4 table
→ update dry-run heredoc + fixtures → run dry-run (will fail on
unsubstituted `{{TOKEN}}` until heredoc covers all) → iterate to green →
retrofit `dashboard-error` LAST among the 4 and immediately re-run
`redact-sentinel.test.sh` (negative-baseline gate).

## Phase Order (load-bearing)

1. **Template first** (`pir.md`) — it declares the `{{TOKEN}}` contract that
   everything downstream consumes.
2. **SKILL.md Phase 4 table + Phase 0 capture** — consumes the template's
   token set; must come after the template so the AC3 bidirectional diff is
   meaningful.
3. **Fixtures + dry-run heredoc** — consumes both; run dry-run to verify.
   **Three-way mirror (deepen finding):** the token set lives in THREE places —
   `pir.md`, the SKILL.md Phase 4 table, and the `dry-run.sh` heredoc. A token
   added to the template but missed in the heredoc surfaces as a raw `{{TOKEN}}`
   in dry-run output (AC7 catches it); missed in the Phase 4 table surfaces in
   the AC3 `comm` diff. Update all three in the same pass.
4. **Retrofit the 3 non-baseline PIRs** (chat-rls, sentry-phantom,
   cloudflare-526) in any order.
5. **Retrofit `dashboard-error` LAST**, then immediately run the sentinel
   test. Doing it last isolates a sentinel-test regression to this single
   edit.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal incident-authoring tooling
template + 4 internal ops documents. No UI surface (no file under
`components/**`, `app/**/page.tsx`, etc.), no schema/migration/auth/API
(GDPR Phase 2.7 skipped — the change touches a GDPR-*aware* template but adds
no regulated-data processing surface; the existing Art. 33/34 machinery is
preserved unchanged), no infrastructure (Phase 2.8 skipped; IaC routing-ack in
frontmatter comment), no code-class file under `apps/*/server|src|infra` or
`plugins/*/scripts` introducing a runtime surface (Phase 2.9 Observability
skipped — `dry-run.sh` is a test/doc-harness, not a production runtime; no
liveness signal applies).

## Observability

This plan touches no production runtime. `dry-run.sh` and `redact-sentinel.sh`
are test/authoring harnesses (run by the operator/CI, never deployed); the
template and 4 PIRs are static docs. There is no liveness signal, no
error-reporting destination, and no runtime failure mode to alert on. The
"discoverability" of correctness is the test suite itself, runnable with NO
ssh:

```yaml
liveness_signal:
  what: N/A — no runtime process; correctness is verified by the test suite, not a heartbeat
  cadence: on every CI run / pre-merge
  alert_target: CI red/green (existing repo test gate)
  configured_in: plugins/soleur/skills/incident/test/redact-sentinel.test.sh + dry-run.sh
error_reporting:
  destination: test stderr + non-zero exit (no Sentry — this is build-time tooling)
  fail_loud: yes — redact-sentinel.test.sh exits non-zero on any FAIL; dry-run.sh exits 1 on unsubstituted token / sentinel hit
failure_modes:
  - mode: template token unsubstituted (drift between pir.md and SKILL.md/dry-run)
    detection: AC3 bidirectional comm diff + AC7 `grep -c '{{'` on dry-run output
    alert_route: CI red on the dry-run / sentinel test
  - mode: retrofit introduces a sentinel-triggering secret/PII shape into the negative-baseline
    detection: redact-sentinel.test.sh Test 1 (negative-baseline on dashboard-error-postmortem.md)
    alert_route: CI red
logs:
  where: CI job logs (test stdout/stderr); no persistent runtime logs
  retention: per the repo's CI log retention (GitHub Actions default)
discoverability_test:
  command: bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh && bash plugins/soleur/skills/incident/scripts/dry-run.sh plugins/soleur/skills/incident/test/fixtures/dry-run-incident.json
  expected_output: "Total: N pass, 0 fail" from the sentinel test AND exit 0 from the dry-run with no raw '{{' tokens in stdout
```

## Sharp Edges

- **The sentinel negative-baseline is `dashboard-error-postmortem.md`.**
  `redact-sentinel.test.sh:22` asserts this exact file exits 0 (clean). The
  retrofit MUST NOT introduce any email, UUID (8-4-4-4-12 hex), IPv4
  dotted-quad, real 3-segment JWT, or `sk_`/`pk_`/`whsec_`/`ghp_`/`sk-ant-`
  token shape. The file's existing `eyJ...` (a grep-pattern literal, not a real
  JWT) and the decoded `iss=supabase` example pass TODAY — do NOT "improve"
  them into realistic tokens. Run the sentinel against the file AND the full
  test harness after the edit. Retrofit this file LAST.
- **Status is sourced from frontmatter, not a new token.** Do not add a
  `{{STATUS_PROSE}}` token — the prose Status section reads from the existing
  `status:` frontmatter to avoid two sources of truth drifting.
- **Customer Impact ≠ a second free-text block.** Reconcile the reference's
  "Customer Impact" with the existing role-based "Who was affected" by
  RENAMING to "Customer Impact (by role)" and keeping the 6 role rows. Adding a
  separate free-text Customer Impact reintroduces the exact surface-vs-role
  blind spot that learning `2026-05-06-user-impact-section-by-role-not-surface.md`
  exists to prevent.
- **Hypothesis table AND 5-Whys both stay.** They are different artifacts
  (triage-time competing hypotheses vs. post-resolution final root cause). Do
  not collapse one into the other.
- **MTTR/MTTD are computed locally, never LLM-emitted** (FR7). The template
  carries `{{MTTR}}`/`{{MTTD}}` placeholders only; the skill + dry-run compute
  them from validated ISO-8601 timestamps. When `recovery_at` is empty →
  `MTTR = TBD`; when detection is external/manual → `MTTD = Unknown
  (external/manual)`. Guard the `date -u -d` subtraction against an empty
  `recovery_at` (no spurious epoch-0 duration).
- **sentry-phantom retrofit is LIGHT.** Its Phase 8 (recovery gates) + Phase 9
  (Gate 3b correction) are load-bearing audit-trail content — add the new
  top-of-file sections but PRESERVE Phase 8/9 verbatim. Do not flatten them
  into the generic Lessons Learned.
- **Do not fabricate.** Revenue Impact, MTTD-when-external, participants, and
  component versions the source PIRs do not contain become `Unknown` / `N/A`
  with a one-line reason — never invented.
- **dry-run.sh writes the draft via a here-doc, not `sed`** (`:172-230`). The
  new sections must be added to the heredoc (not a sed substitution table) —
  the heredoc already inlines the static section bodies. Keep it consistent:
  the dry-run heredoc is a faithful mirror of the template, so AC5/AC7
  (no raw `{{` in output) hold by construction.
- **A pre-existing dangling citation lives in `chat-rls`** (the missing
  `2026-06-02-rls-column-add...` learning). It is out of scope; do not
  fabricate the learning and do not edit that citation.
