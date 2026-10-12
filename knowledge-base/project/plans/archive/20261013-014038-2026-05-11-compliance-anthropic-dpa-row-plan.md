---
type: compliance
issue: 3594
blocks: 2720
source_pr: 3559
priority: p2-medium
domain: legal
created: 2026-05-11
date: 2026-05-11
deepened: 2026-05-11
branch: feat-one-shot-3594-anthropic-dpa
worktree: .worktrees/feat-one-shot-3594-anthropic-dpa
spec: knowledge-base/project/specs/feat-one-shot-3594-anthropic-dpa/tasks.md
requires_cpo_signoff: false
---

# compliance: add Anthropic processor row to Vendor DPA Status (#3594, blocks #2720)

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** 0 net additions; verification artifacts inlined; one ambiguity corrected
**Approach:** Proportionate deepen. A single-row documentary addition to a vendor-DPA registry, where the row values are *operator-verified facts*, does not warrant a 40-agent fan-out — the deepen-plan quality checks (rule-citation grep, label-existence grep, live PR/issue verification, sensitive-path regex match, Phase 4.5/4.6 gate fires) are the load-bearing gates for this plan class, and they have been applied directly below. This mirrors the pattern established by `2026-05-11-chore-compliance-posture-last-updated-bump-plan.md` (also a same-file metadata edit, also documentary-only) and `2026-05-09-fix-terraform-drift-seo-response-headers-and-deploy-pipeline-fix-3485-plan.md`.

### Phase 9 Quality-Check Verification Block

All verifications performed at deepen-pass time (2026-05-11). Outputs captured verbatim.

**Live PR/issue state cross-reference (PR #3559, issues #3594 / #2720):**

```bash
$ gh issue view 3594 --json state,title
{"state":"OPEN","title":"compliance: add Anthropic processor row to Vendor DPA Status (blocks #2720)"}

$ gh issue view 2720 --json state,title
{"state":"OPEN","title":"feat: add promotion loop to compound + compound-capture (self-improving-agent pattern)"}

$ gh pr view 3559 --json state,title,mergedAt
{"mergedAt":null,"state":"OPEN","title":"WIP: feat-compound-promotion-loop"}
```

**AGENTS.md rule citations — all active, none retired or fabricated:**

```bash
$ for id in hr-always-read-a-file-before-editing-it hr-gdpr-gate-on-regulated-data-surfaces wg-use-closes-n-in-pr-body-not-title-to; do
    grep -qE "\[id: $id\]" AGENTS.md && echo "ACTIVE: $id"
  done
ACTIVE: hr-always-read-a-file-before-editing-it
ACTIVE: hr-gdpr-gate-on-regulated-data-surfaces
ACTIVE: wg-use-closes-n-in-pr-body-not-title-to
```

(All three citations also absent from `scripts/retired-rule-ids.txt` — the retired-rule registry is the canonical guard against citing dead IDs.)

**Labels verified via `gh label list --limit 200`:**

```text
ACTIVE:  domain/legal, chore, domain/engineering, compliance/critical
ACTIVE:  priority/p0-critical, priority/p1-high, priority/p2-medium, priority/p3-low
MISSING: compliance/improvement   (NOT a real label as of 2026-05-11)
MISSING: priority/p2-high          (frontmatter typo — corrected to priority/p2-medium)
```

Plan body's Post-merge AC explicitly says "use `domain/legal` + `chore` (the `compliance/improvement` label does NOT exist as of plan time — operator can create it or use the existing labels)" — verified live, the gap is acknowledged inline rather than papered over.

**Sensitive-path regex (preflight Check 6 canonical) against the only edited file:**

```bash
$ SENSITIVE_PATH_RE='^(apps/web-platform/(server|supabase|app/api|middleware\.ts$)|apps/web-platform/lib/(stripe|auth|byok|security-headers|csp|log-sanitize|safe-session|safe-return-to|supabase)|apps/web-platform/lib/(legal|auth)/|apps/[^/]+/infra/|.+/doppler[^/]*\.(yml|yaml|sh)$|\.github/workflows/.*(doppler|secret|token|deploy|release|version-bump|web-platform|infra-validation|cla|cf-token|linkedin-token).*\.ya?ml$)'
$ echo "knowledge-base/legal/compliance-posture.md" | grep -E "$SENSITIVE_PATH_RE" || echo "NOT_SENSITIVE"
NOT_SENSITIVE
```

The `threshold: none` declaration in `## User-Brand Impact` is therefore valid **without** a scope-out bullet — the file is not under any of the canonical sensitive-path classes.

**Phase 4.6 (User-Brand Impact halt gate):** PASSES. Heading present, body non-empty (full bullets + threshold reason), threshold value is `none` (one of the three allowed values), file not in sensitive-path class. No telemetry emitted (gate only records on activation).

**Phase 4.5 (Network-Outage Deep-Dive):** Trigger word "handshake" matched, but inspection reveals every occurrence is the metaphorical `gdpr-gate handshake` (the operator-acknowledged critical-finding registration protocol in `plugins/soleur/skills/gdpr-gate/SKILL.md`), NOT a network/TLS/SSH handshake. The plan body does not propose any `ssh`, `terraform apply`, `curl`, network egress, or DNS resolution operation. No `provisioner "ssh"` / `provisioner "remote-exec"` / `connection { type = "ssh" }` resource in scope. No deep-dive needed; trigger is a false positive on documentary terminology overlap with the network-outage keyword set.

**AC numbering ambiguity resolved (Research Reconciliation row #2):**

```bash
$ git show 733c3a51:knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md | grep -nE "AC2[0-9]+" | head -5
83:  ... Plan-time `/soleur:gdpr-gate` invocation found 1 Important (Anthropic DPA gap, pre-existing systemic) + 3 Suggestions; folded as AC26 + Phase 4 inline disclosures.
96:  | `GDPR-Chapter-V` — Anthropic processor not in compliance-posture.md Vendor DPAs | Important | **AC26:** verify Anthropic DPA row present in `compliance-posture.md` before merge. ... |
730:- [ ] **AC23:** Anthropic processor row exists in `knowledge-base/legal/compliance-posture.md` Vendor DPAs (separate compliance/improvement issue lands first; #2720 ship blocked until then — AC26 from gdpr-gate findings). *(SHIP BLOCKER — tracking issue: #3594; #2720 cannot ship until #3594 PR lands the row.)*
```

Resolution: **AC23 is the visible Acceptance Criteria row in the #2720 plan; it cross-references AC26 from the gdpr-gate findings table.** Both reference the same gate (Anthropic DPA row presence). The issue body's "AC23" citation is correct; the plan's gdpr-gate findings table additionally tags it as "AC26 from gdpr-gate findings" for internal traceability. This PR closes the gate regardless of which number a reader pattern-matches on.

### Skills/Agents Considered and Skipped

Skipped with explicit rationale (each would be ceremony, not signal, on a documentary row addition where the row values are operator-verified facts):

- `soleur:gdpr-gate` — file edited is the *output surface* of the gate's critical-finding handshake, not a regulated-data source; per `hr-gdpr-gate-on-regulated-data-surfaces`, frontmatter/table-row edits to a docs-tree markdown file do not match the regex.
- `frontend-design`, `dhh-rails-style`, `andrew-kane-gem-writer`, `vercel-react-best-practices`, `supabase-postgres-best-practices`, `agent-native-architecture`, `dspy-ruby` — domain mismatch (no UI, no Ruby, no React, no Postgres, no agent surface, no DSPy).
- `claude-api` — no Anthropic SDK call, no model invocation, no caching surface. The plan is *about* the Anthropic DPA documentary state; it does not call the API.
- `web-design-guidelines` — no UI rendering.
- `security-review`, `simplify`, all engineering review agents (`architecture-strategist`, `security-sentinel`, `data-integrity-guardian`, `type-design-analyzer`, `code-quality-analyst`, `test-design-reviewer`, `agent-native-reviewer`, `git-history-analyzer`, `repo-research-analyst`, `framework-docs-researcher`, `best-practices-researcher`, `spec-flow-analyzer`) — every agent operates on diff content (code, schema, types, tests, contracts) or design surface; this PR's diff is exactly one row (`| Anthropic PBC | … |`) plus optional frontmatter date bump, with no behavior, schema, contract, type, test, security, or design surface. The Pre-merge `git diff --stat` AC (exactly 1 file, ≈1-3 insertions, 0 deletions outside the optional frontmatter date) is the verification a reviewer would perform anyway.
- `user-impact-reviewer` — `threshold: none` with justified reason; per the `requires_cpo_signoff: false` frontmatter, this is not single-user incident class. The conditional-agent block in `plugins/soleur/skills/review/SKILL.md` would not fire.
- `copywriter` — table row, not user-facing copy; no brand-voice surface.
- All learnings under `knowledge-base/project/learnings/` — filtered: the closest semantic matches are the plan-quality learnings (paraphrase-without-verification class, label-verification class, retired-rule-citation class). This deepen pass has *applied* all three classes directly: live PR/issue state grep, live label grep, live rule-citation grep — outputs inlined above.

### Key Improvements vs Plan-Skill Output

1. Frontmatter `priority` corrected from typo (`p2-high` → `p2-medium`, the actual canonical label).
2. AC numbering ambiguity (`AC23` issue-body vs `AC26` gdpr-gate-findings-table) resolved with verbatim `git show` grep — both numbers point to the same gate; PR body needs to acknowledge once but not "fix" anywhere.
3. Phase 4.5 false-positive trigger ("handshake" = gdpr-gate protocol, not network handshake) documented so a future deepen-plan reader does not re-flag.
4. Label gap (`compliance/improvement` does NOT exist) inlined in the Post-merge AC as a substitute-or-create choice, rather than silently shipping a `gh issue create --label compliance/improvement` line that would have failed at runtime.
5. All three AGENTS.md rule citations verified live as ACTIVE (not retired, not fabricated) with explicit `grep -qE "\[id: …\]" AGENTS.md` output preserved.

### New Considerations Discovered

- **`compliance/improvement` label does not exist.** Three Post-merge follow-up paths reference this label by intent (the #2720 plan's gdpr-gate-findings table mentions filing a "separate `compliance/improvement` issue"). If the operator decides to file the follow-up, they must either (a) create the label first via `gh label create`, or (b) substitute `domain/legal` + `chore` (the in-scope existing labels). The plan body now documents (b) as the default path.
- **PR #3559 is "WIP" titled.** Not `Draft` — title-string-prefixed. The Post-merge handoff (Phase 4, step 2: "Notify #3559's author / comment on PR #3559 that AC23/AC26 is closed") should mention the WIP prefix so the operator does not assume #3559 is already merge-ready. Once this row lands, the WIP→Ready transition + `gh pr ready` is #3559's author's call, not ours.
- **No Anthropic Files API surface in scope.** Cross-checked: `knowledge-base/project/brainstorms/2026-05-07-large-pdf-chapter-chunking-brainstorm.md` documents that Anthropic Files API was *rejected* on cost/legal grounds; chapter-chunking uses the standard `messages.create` flow already covered by Anthropic's existing DPA. The row this PR adds covers the `messages.create` surface; no Files API sub-processor reclassification work is owed. If Anthropic Files API is later adopted, that triggers a *separate* DPA-row refresh (sub-processor categories change), not a retro-edit to the row this PR lands.

---

## Overview

Single-row addition to the `## Vendor DPA Status` table in `knowledge-base/legal/compliance-posture.md`. The table currently lists six vendors (Hetzner, Supabase, Stripe, Cloudflare, Resend, Doppler, Google/osv.dev) but does **not** include Anthropic PBC — even though every `claude-code-action` workflow, the `gdpr-gate` skill's column-name probe, and the new compound-promotion-loop (#2720) all route processing through Anthropic.

PR #3559's plan-time `/soleur:gdpr-gate` invocation surfaced this as `GDPR-Chapter-V` **Important** severity (pre-existing systemic gap). PR #3559 is otherwise code-complete; AC23 of the compound-promotion-loop plan (`2026-05-11-feat-compound-promotion-loop-plan.md`) declares this row a hard merge-block.

This plan adds the row. It is a documentary change with operator-verification dependencies (Anthropic Console login to capture DPA version + transfer mechanism + region), no code surface, and no test surface. Operator action (verifying the DPA in the Anthropic Console) is a Phase 1 prerequisite captured as a Pre-merge AC checklist item.

## User-Brand Impact

**If this lands broken, the user experiences:** A `Vendor DPA Status` table that asserts an Anthropic row without operator verification — domain leaders (CLO, gdpr-gate critical-finding handshake) treat the row as authoritative when the underlying DPA status is in fact unconfirmed. Downstream: #2720 ships on a false-green compliance signal; a future GDPR Article 30 register audit reveals the gap. No end-user behavior regresses immediately; the failure mode is documentary drift between the posted row and the actual DPA contract state.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this edit adds a documentary row describing a transfer mechanism that already exists at runtime (every Anthropic API call from the repo). The row does not create new egress; it records the legal coverage of egress that has been live since the first `claude-code-action` workflow shipped. Posting a public row that names "Anthropic PBC" as a processor is the intended disclosure and is consistent with `docs/legal/gdpr-policy.md` Section 6 and Section 8 (which already list Anthropic as an international-transfer recipient).

**Brand-survival threshold:** none

**Reason for threshold none:** No regulated-data surface is touched. The edit adds rows to a docs-tree markdown file that is the *output surface* of the gdpr-gate handshake (per `plugins/soleur/skills/gdpr-gate/SKILL.md` "Critical-finding escalation flow"), not a regulated-data source. The compliance-posture.md file does not match the canonical sensitive-path regex in `plugins/soleur/skills/preflight/SKILL.md` Check 6 (no Doppler shell, no `apps/web-platform/server|app/api|middleware.ts`, no `apps/*/infra/`, no credential-handling workflow).

That said, **the operator MUST complete the Anthropic Console verification step** before the row is written — see `Phase 1`. The row's values (DPA Status, signed/verified date, transfer mechanism, data region) are operator-verified facts, not LLM-generated paraphrase. The plan does NOT prescribe fabricating row values; it prescribes a verification sequence that culminates in writing the row from the operator's captured artifacts.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Reality (verified) | Plan response |
|---|---|---|
| `knowledge-base/legal/compliance-posture.md` `## Vendor DPA Status` does NOT include an Anthropic row | Confirmed: 7 rows total (Hetzner, Supabase, Stripe, Cloudflare, Resend, Doppler, Google/osv.dev). `rg -n "Anthropic" knowledge-base/legal/compliance-posture.md` returns zero hits. | Add row as Phase 1. |
| AC23 of #2720 plan declares this row a ship blocker | Confirmed at `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md:83,96` ("AC26: verify Anthropic DPA row present in compliance-posture.md before merge"). Note: issue body cites "AC23"; the actual line in the plan numbers it as **AC26**. Both reference the same gate. | Document the AC23/AC26 numbering ambiguity in the PR body; the row's presence is what closes the gate, not the number. |
| Anthropic transfer mechanism most-likely EU-US DPF + SCCs; US-based region | Cross-referenced against `docs/legal/gdpr-policy.md:39,211` and `docs/legal/privacy-policy.md:280` — both already disclose Anthropic as a US-based recipient subject to international-transfer safeguards. `docs/legal/data-protection-disclosure.md:210` references third-party DPAs without naming Anthropic's transfer mechanism explicitly. | Operator MUST confirm the exact current transfer mechanism + region from the Anthropic Console / public DPA before writing the row values. The "most likely" wording in the issue body is a hypothesis, not authority. |
| The gap is pre-existing systemic | Confirmed: `rg "Anthropic" knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-skill-plan.md:428,442` shows the gdpr-gate skill plan already cited "Anthropic DPA already verified per existing posture" — but `compliance-posture.md` itself has no such row. The skill plan referenced a row that was never written. | Acknowledge the pre-existing systemic framing in PR body; do NOT widen scope to a retroactive audit of every dependent claim. |
| Source PR #3559 staged, 16 commits ahead of main, all tests pass | `gh pr view 3559 --json state,mergedAt` → `{"state":"OPEN","mergedAt":null}`. PR is open, not yet merged. | Land this PR first; #3559 unblocks on this merge per AC23/AC26. |

## Files to Edit

- `knowledge-base/legal/compliance-posture.md` — add one row to the `## Vendor DPA Status` table (insert after the Google/osv.dev row, before `## Vendored Code Provenance`). Bump `last_updated:` frontmatter to today's date (2026-05-11).

## Files to Create

None.

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200` + `jq -r --arg path "knowledge-base/legal/compliance-posture.md" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'`. Zero matches.

## Acceptance Criteria

### Pre-merge (PR)

- [x] Operator verification path: Sharp Edges fallback (b) — public Anthropic DPA URL — used in lieu of Anthropic Console UI access. Verbatim facts captured from:
  - `https://www.anthropic.com/legal/data-processing-addendum` (DPA effective **2025-02-24**, SCCs Modules 2+3 + UK IDTA + Swiss Addendum per § I.1, governing law Irish per § A.1.c, sub-processors at `trust.anthropic.com/subprocessors`)
  - `https://www.anthropic.com/legal/commercial-terms` (effective **2025-06-17**, § C "Data Privacy" auto-incorporates the DPA by reference — establishes `AUTO` status)
  - `https://www.anthropic.com/legal/privacy` (effective **2026-01-12**, US-based servers, Art. 46 GDPR contractual clauses)
  - **Correction vs issue body hypothesis:** Anthropic's current public DPA does NOT cite "EU-US Data Privacy Framework / DPF". The verbatim mechanism is SCCs + UK IDTA + Swiss Addendum. Row uses verbatim wording, not the issue body's "most likely" paraphrase.
- [x] One new row added to the `## Vendor DPA Status` table in `knowledge-base/legal/compliance-posture.md`, with all six columns populated from public-DPA-verified facts (no placeholder text, no `TBD`/`TODO`):
  - `Vendor`: `Anthropic PBC`
  - `DPA Status`: `AUTO`
  - `Signed/Verified`: `2026-05-11`
  - `Transfer Mechanism`: `SCCs Modules 2+3 + UK IDTA + Swiss Addendum (Art. 46 GDPR)`
  - `Data Region`: `US-based`
  - `Notes`: DPA effective date + Commercial Terms § C anchor + Irish governing law + sub-processor URL + in-repo consumption paths (`claude-code-action`, `gdpr-gate`, #2720) + single-user incident threshold reference + AC23/AC26 tag.
- [x] `last_updated:` frontmatter unchanged — already `2026-05-11` (today). No bump needed.
- [x] `git diff --stat` shows exactly 1 file changed in `knowledge-base/legal/compliance-posture.md`, 1 insertion, 0 deletions.
- [x] No other rows in the table modified — visual diff inspection confirms only the new Anthropic row is added.
- [ ] PR body uses `Closes #3594` and `Ref #2720` (per `wg-use-closes-n-in-pr-body-not-title-to`; #2720 is referenced but not closed by this PR). *(deferred to ship phase)*
- [ ] PR body explicitly notes the AC23/AC26 numbering ambiguity in #2720's plan and clarifies that this PR closes the gate regardless of which number is cited. *(deferred to ship phase)*
- [x] No `/soleur:gdpr-gate` invocation required: the diff adds row data describing an existing transfer relationship; it does NOT touch a regulated-data surface under `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex (no schema, no migration, no auth flow, no API route, no `.sql`).

### Post-merge (operator)

- [ ] Notify the #2720 PR author (or post on PR #3559) that AC23/AC26 is unblocked.
- [ ] If the operator captured an executed Anthropic DPA PDF during Phase 1, file it in the same private store used for the Hetzner / Supabase signed PDFs (see `knowledge-base/project/specs/feat-vendor-ops-legal/dpa-verification-memo.md` — operator-private, not committed to repo).
- [ ] If the Anthropic DPA exposes any new sub-processor categories that materially differ from the existing `docs/legal/gdpr-policy.md` Section 6 disclosure, file a follow-up `compliance/improvement` issue. Do NOT widen this PR's scope; the row addition is the contained closure.

## Domain Review

**Domains relevant:** Legal (CLO advisory)

### Legal

**Status:** advisory carry-forward (issue body + #2720 plan AC23/AC26 already capture the CLO framing)
**Assessment:** This is the documentary closure of the systemic gap CLO surfaced via the gdpr-gate handshake on #2720. The row addition aligns `compliance-posture.md` with the existing public disclosures in `docs/legal/gdpr-policy.md` Section 6 and `docs/legal/privacy-policy.md` §280, which have already named Anthropic as a US-based recipient subject to international-transfer safeguards. No new legal claim is created; existing claims are merely recorded in the vendor-DPA registry.

No Product/UX, Engineering, Marketing, Operations, Finance, or Security domains relevant — the change has no behavior surface, no UI, no schema, no test, and no runtime config.

**Brainstorm-recommended specialists:** None. No brainstorm exists for this work; the framing comes directly from #2720 plan and #3594 issue body.

**Skipped specialists:** None mandatory.

## GDPR / Compliance Gate

`/soleur:gdpr-gate` invocation skipped per `hr-gdpr-gate-on-regulated-data-surfaces`: the canonical regex covers schemas, migrations, auth flows, API routes, and `.sql` files. A row addition to a docs-tree markdown file (the *output* of the gdpr-gate handshake) does not match. Running the gate on this diff would be a false positive.

The plan itself is the *target* of a prior gdpr-gate finding (`GDPR-Chapter-V` Important, surfaced during #3559 plan-time). This PR is the operator-acknowledged write that closes that finding.

## Risks

- **Operator-captured row values drift from Anthropic's actual DPA.** Mitigation: the Pre-merge AC checklist forces the operator to log into the Anthropic Console and capture each field. Plan explicitly forbids hypothesis-as-fact: the issue body's "most likely" wording is research, not authority; the row values must be operator-verified.
- **Anthropic DPA terms change post-merge.** Mitigation: `last_updated:` frontmatter records the verification date; future gdpr-gate runs will surface drift if the recorded `Signed/Verified` date becomes stale. Out of scope for this PR.
- **Sub-processor surface expands.** Mitigation: if Phase 1 operator verification reveals Anthropic sub-processors (Google Cloud, AWS, etc.) not already disclosed in `docs/legal/gdpr-policy.md`, file a follow-up `compliance/improvement` issue. Do NOT widen this PR.
- **AC numbering ambiguity.** The issue body cites "AC23"; the #2720 plan numbers the gate as **AC26** (verified at line 96 of the plan). PR body must explicitly note this so the reviewer does not chase the wrong AC number.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan declares `threshold: none` with a justified reason; the file is not under the canonical sensitive-path regex.)
- Operator MUST NOT paraphrase the Anthropic DPA wording from memory or training data. Every row field must come from the Anthropic Console or the official Anthropic DPA URL captured at verification time. Paraphrase-without-verification is the documented #1 plan-drift failure class (see `knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`).
- Do NOT cite labels (`compliance/improvement`) in Pre-merge or Post-merge ACs without verifying they exist via `gh label list`. Verified at plan time: `compliance/critical` exists (color `#B60205`); `compliance/improvement` does NOT yet exist as a label. If the Post-merge follow-up issue is needed, use `domain/legal` + `chore` or create the label first.
- Do NOT widen scope to retroactive audits of other vendor rows (Resend, Doppler, Google/osv.dev) even though those entries also rely on `AUTO` ToS acceptance with similar evidence-gathering gaps. Each is its own issue; conflating them blocks the #2720 unblock path.
- The Anthropic Console's "DPA" surface may be behind a Team/Enterprise plan. If the operator's plan does not expose a DPA UI, fall back to: (a) the public Anthropic DPA URL at `https://www.anthropic.com/legal/commercial-terms` (verify the URL still resolves; capture via `curl --max-time 10 -sI <url>`), (b) the ToS section auto-accepting DPA terms, or (c) email `privacy@anthropic.com` to request a signed copy. Record which path was used in the row `Notes` field.

## Out of Scope

- Auditing every other repo location that references Anthropic without naming the DPA (`docs/legal/gdpr-policy.md`, `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`, and the various plan/brainstorm files). Those are stable disclosures; if they need updating, that is a separate documentary refresh.
- Updating the existing per-row `Last Updated` columns in the `## Legal Documents` table.
- Filing a DPIA (Article 35) for #2720 — already tracked as a separate Active Item with a 4-week operational-data window before formal assessment.
- Filing follow-up `compliance/improvement` issues for Resend/Doppler/Google rows that share the same `AUTO` evidence gap as Anthropic. Each is its own ticket; do not bundle.
- Any change to `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md` (the AC23/AC26 numbering inconsistency is documented in this PR body, not "fixed" in the source plan — that plan is already merged-context for #3559).
- Any code or workflow change to `claude-code-action` invocations, the `gdpr-gate` skill, or the compound-promotion-loop scripts. This PR is documentary only.

## Phases

### Phase 1 — Operator Anthropic Console verification

**This phase is operator-driven, not LLM-driven.** The agent does NOT fabricate row values; the operator captures them.

1. Operator logs into the Anthropic Console at `https://console.anthropic.com` → Settings → Legal → DPA (path may vary by plan tier).
2. Operator captures:
   - **DPA Status**: Is the DPA explicitly signed (download PDF), auto-accepted via ToS, or pending? Pick one of `SIGNED` / `AUTO` / `PENDING`.
   - **Signed/Verified date**: signature date if SIGNED; today's date (2026-05-11) if AUTO via ToS; today's date if PENDING (records the verification attempt).
   - **Transfer Mechanism**: read the actual DPA wording. Likely `EU-US DPF + SCCs` but verify; Anthropic's current public DPA URL is the authoritative source.
   - **Data Region**: typically `US-based`; verify whether Anthropic offers EU region for this account's plan tier.
   - **DPA version date** (for `Notes` field): from the captured PDF's header or the auto-accepted ToS version.
3. If the operator cannot access the DPA UI (e.g., plan tier does not expose it), follow the Sharp Edges fallback path (public DPA URL or `privacy@anthropic.com`).
4. Output of Phase 1: a 5-field artifact pasted into the operator's PR draft. No commit yet.

### Phase 2 — Apply the row + frontmatter bump

1. Read `knowledge-base/legal/compliance-posture.md` (re-read per `hr-always-read-a-file-before-editing-it`).
2. Use `Edit` tool to insert one row in the `## Vendor DPA Status` table, after the Google/osv.dev row (line 39), populated with operator-captured values from Phase 1.
   - Row template:
     ```
     | Anthropic PBC | <SIGNED|AUTO|PENDING> | YYYY-MM-DD | <transfer mechanism> | <region> | Holds claude-code-action workflow invocations, `gdpr-gate` skill column-name probes, compound-promotion-loop (#2720) clustering payloads, and other code-path Anthropic API uses. DPA version: <date or ToS section>. Single-user-incident threshold dependency for #2720. |
     ```
3. Bump `last_updated:` frontmatter to today's date if not already today.
4. Verify `git diff --stat` shows exactly 1 file changed in `knowledge-base/legal/compliance-posture.md`.
5. Visual diff verification: only the new row + (possibly) the frontmatter date line are modified.

### Phase 3 — Commit, PR, merge

1. Commit with message `compliance(legal): add Anthropic processor row to Vendor DPA Status (#3594)`.
2. Push, open PR with body:
   - `Closes #3594`
   - `Ref #2720` (cross-reference, do NOT use `Closes` — the #2720 plan ships independently after this row lands)
   - Note the AC23/AC26 numbering ambiguity explicitly.
   - Operator's Phase 1 verification artifact (DPA Status, dates, transfer mechanism, region, version).
3. Mark ready, queue `--squash --auto`.
4. Poll until MERGED, run `cleanup-merged`.

### Phase 4 — Post-merge unblock

1. Confirm the row is visible on `main`.
2. Notify #3559's author / comment on PR #3559 that AC23/AC26 is closed.
3. If operator captured an executed Anthropic DPA PDF, file it in the operator-private DPA store (same path as Hetzner/Supabase signed PDFs).
4. If Anthropic DPA exposed new sub-processors materially different from `docs/legal/gdpr-policy.md` Section 6 disclosure, file a follow-up `domain/legal` + `chore` issue (the `compliance/improvement` label does NOT exist as of plan time — operator can create it or use the existing labels).

## Test Scenarios

None. This is a documentary row addition; there is no behavior to assert.

**Why no test scaffolding:** Adding a test for "the row exists in the table" would be cosmetic — the Pre-merge `git diff --stat` AC plus visual diff inspection is the verification. The row's *values* are operator-verified facts, not LLM-generated; asserting them in a test would just re-encode the same operator paraphrase risk one layer further out. The gdpr-gate skill's own reader path treats the row's *presence* as the contract; the values are operator-trust.

## Hypotheses

N/A — this is not an investigation. The gap is documented verbatim in the issue body; the fix is a row addition.
