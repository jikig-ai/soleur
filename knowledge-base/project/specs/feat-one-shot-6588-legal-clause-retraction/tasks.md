---
title: "Tasks — #6588 legal half: retract, re-scope, escalate"
plan: knowledge-base/project/plans/2026-07-24-fix-6588-legal-clause-retraction-plan.md
issue: 6588
lane: cross-domain
brand_survival_threshold: single-user incident
amended: 2026-07-24
---

# Tasks — #6588 legal clause retraction

Derived from the finalized (post-plan-review, **post-amendment**) plan. **The plan's
`## Site Matrix` is authoritative for every site reference below** — do not re-derive site lists
from prose.

> **AMENDED 2026-07-24 (operator decision).** Deliverable 3 no longer adds an affirmative
> plaintext-disclosure sentence to any published legal document. The operator's UC-3 hold
> (PR #6918) was re-raised with the revisit-trigger analysis and **reaffirmed**. D3 is now
> *reaffirm the hold and escalate #6808*. **No task below may add a disclosure sentence or a
> scope-to-live qualifier to `docs/legal/**` or the Eleventy mirrors** — AC4 asserts their
> absence. Deliverables 1, 2 and 4 are unchanged.

## Phase 0 — Live re-verification (BLOCKING)

- [ ] 0.1 Dispatch `gh workflow run workspaces-luks-verify.yml` (do **not** set `seed_workspace_count`).
- [ ] 0.2 Wait for completion; capture the run id + conclusion
      (`gh run list --workflow=workspaces-luks-verify.yml --limit 1 --json databaseId,conclusion`).
- [ ] 0.3 Confirm `device_type=crypto_LUKS`, `mount_source=/dev/mapper/workspaces`, `escrow=ok`,
      `header=readable`, `workspace_count=8 expected=8`.
- [ ] 0.4 **If RED → switch to the DEGRADED-SCOPE branch** in plan §Phase 0 (retract clause (d)
      instead of re-scoping; strike **AC3** — **AC4 and AC15 still stand**; DC-1 stays OPEN;
      `Ref` not `Closes`; file P0 incident; say so in the #6808 escalation comment).
- [ ] 0.5 Re-assert #6570 / #6808 / #6897 / #3723 still OPEN. Capture **#6808's current labels**
      (`gh issue view 6808 --json state,labels`) — AC15 asserts a delta against them.
- [ ] 0.6 Record `python3 scripts/lint-encryption-posture.py --repo-sweep` baseline (expect PASS).

## Phase 1 — Union-anchor site inventory

- [ ] 1.1 Run the union-anchor grep across the 6 published files; reconcile against the plan's
      Site Matrix. Any divergence ⇒ `main` moved; re-reconcile before editing.
- [ ] 1.2 Extend the same sweep to `knowledge-base/legal/article-30-register.md` and
      `knowledge-base/legal/compliance-posture.md`.
- [ ] 1.3 Confirm the `eu-fsn-3` / Better Stack carve-out is excluded from any `Falkenstein` sweep
      (`pp:379`, mirror `:378`, `dpd:103`, mirror `:112` are TRUE claims — do not touch).
- [ ] 1.4 Apply the claim-family litmus per site.

## Phase 1.5 — Audit trail first

- [ ] 1.5.1 Create `specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` with the
      Deliverable-3 User-Challenge record. **All five elements (AC11):** (i) the #6918 UC-3 hold;
      (ii) the revisit-trigger analysis as put to the operator (*"if the teardown slips materially,
      revisit Path 2"*; #6808 OPEN ⇒ soak clock not started ⇒ earliest cure "#6808 fix + 7 days",
      no committed date); (iii) the operator's **REAFFIRMATION** of the hold on 2026-07-24;
      (iv) the CLO's contrary recommendation (B1) recorded as **overridden, not deleted**; (v) the
      accepted residual with **#6808** as its tracking issue.
      *(Ordering rationale: no reversal to guard — it is written first because Phase 5's escalation
      comment quotes it and the CLO attestation cites it.)*
- [ ] 1.5.2 Create `site-dispositions.md` — 16 rows (8 canonical + 8 mirror), per-claim disposition.

## Phase 2 — Canonical body edits

Work **one claim family at a time across all files**, not one file at a time.
**Deliverables 1 + 2 only.** No site gets a plaintext-disclosure sentence and no site gets a
scope-to-live (*"stored **live** workspace git data …"*) qualifier — that was the retracted D3.

- [ ] 2.1 `dpd:189` processor table (highest-grade: Art. 13(1)(e) / 30(1)(d)) — retract (a)(b)(c) +
      web-2; **keep the LUKS claim as-is** (table cell), re-anchored so it does not dangle.
- [ ] 2.2 `pp:298` — retract (a)(b)(c) + web-2 (**"has been in Falkenstein"** phrasing); keep LUKS
      re-anchored so it does not dangle.
- [ ] 2.3 `pp:519` §11 — retract (a)(b)(c); drop the "spans more than one Hetzner host" premise;
      keep the LUKS claim standing unconditioned on the live single-host topology.
- [ ] 2.4 `gdpr:44` — retract (a)(b)(c) (**note word order: "a dedicated host for per-workspace git
      data"**) + web-2; drop multi-host premise; keep LUKS.
- [ ] 2.5 `dpd:276` — retract (a)(c) + web-2; drop multi-host premise; keep LUKS.
      (**Carries LUKS — verified.**)
- [ ] 2.6 `pp:489`, `gdpr:318` — retract multi-host premise + web-2. **Add no LUKS claim.**
- [ ] 2.7 `dpd:318` — correct the Hetzner two-DC transfer claim ("Helsinki … and Falkenstein").
- [ ] 2.8 **Self-check before leaving this phase:** run AC4's disclosure anchor over the three
      canonicals — it must return **0**. The one-vs-two-backstops question
      (`hcloud_volume.git_data`) is **NOT resolved in this PR**; it is carried into the #6808
      escalation comment (task 5.5) for whoever writes the deferred Path-2 wording.

## Phase 3 — Mirrors, banner, dates

- [ ] 3.1 Mirror every Phase-2 edit (hand-maintained; **no generator**). Sites: `pp` `:297/:475/:500`,
      `dpd` `:186/:261/:301`, `gdpr` `:53/:306`.
- [ ] 3.2 Banner, all 6 files, in order: **(a) annotate** — append the retraction marker at the END
      of the July-2 segment (immediately before `Previous: June 30, 2026`), never mid-segment;
      **(b) demote** `**Last Updated:** July 16, 2026 (` → `Previous: July 16, 2026 (`;
      **(c) prepend** the new `**Last Updated:** July 24, 2026 (…). ` head.
- [ ] 3.3 **Do NOT sync mirror banners to canonical** — mirrors legitimately carry truncated history
      (18/17/17 vs 12/13/11 `Previous:` occurrences). Edit in place only.
- [ ] 3.4 Set the new date at **9 sites**: 3 canonical body, 3 mirror body, 3 mirror hero `<p>`.
- [ ] 3.5 Verify no `##`/`###` heading changed; if any did, mirror it exactly.
- [ ] 3.6 Apply the §4c style decision — **`Ref #6588`** (resolved by history: the `Ref #NNNN
      (<branch-slug>)` form was adopted 2026-06-10 and supersedes the 2026-05-12 learning) —
      uniformly to the banner head and any body-prose `Ref`. Record the supersession in the PR body.

## Phase 4 — Mechanical pins (ledger FIRST, SHA LAST)

- [ ] 4.1 Ledger `disclosed_as` **×2** → content anchors: `stores[0]` (dead `:519` anchor —
      `grep -c "519"` is 0) and `connections[0]` (`dpd:316`).
      **`stores[2]` (`hcloud_volume.workspaces`) must be BYTE-UNCHANGED** — including
      `exception.justification`. It was in scope only for the retracted D3; with the hold
      reaffirmed, `not-publicly-claimed` is trivially correct (AC8).
- [ ] 4.2 Re-run `python3 scripts/lint-encryption-posture.py --repo-sweep` (expect PASS).
- [ ] 4.3 **THEN** `sha256sum` the 3 canonicals; paste full 64-char values into `LEGAL_DOC_SHAS`.
- [ ] 4.4 `bash apps/web-platform/scripts/check-tc-document-sha.sh` (expect exit 0).
- [ ] 4.5 **Invariant:** no `docs/legal/**` byte may change after 4.3. If one does, redo 4.3–4.4.
- [ ] 4.6 File the one-line issue against **#6893** for the linter's honest-under-claim blind spot
      (§Risks R4b — it is a **latent blocker on the deferred Path-2 wording**, not exercised here).
      Do **not** edit `scripts/lint-encryption-posture.py` in this PR.

## Phase 5 — Registers, DC-1, escalation, attestation

- [ ] 5.1 `article-30-register.md` — residual-zero: `(g)` TOMs `:50` + `:68` (replace items 13–16 /
      17–20 with the measure that IS true, do not merely delete), `(d)` Recipients `:47`,
      `(e)` Transfers `:48` + `:163`, Vendor mapping `:426`. Re-grep PA identity before editing.
      **The register is INTERNAL and still names the retained plaintext backstop as a residual**
      (§4d — unchanged by the amendment; only *published* text is held). Do not "harmonise" the
      register down to match the published docs.
- [ ] 5.2 `compliance-posture.md:80` — drop `git-data host CAX11`; clear present-tense `web-2`.
      **No #3723 Art. 17 gate is added to this file** (cut at plan-review) — see 5.6.
- [ ] 5.3 `nfr-register.md:522` — correct (non-blocking, AC9b). **`:521` is not touched.**
- [ ] 5.4 DC-1 in `specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` → RESOLVED; record the
      2026-07-23 certification, this PR's retraction, and the **lapsed** 2026-07-23 reopen trigger.
- [ ] 5.5 **ESCALATE #6808 — Deliverable 3's shipped half (AC15).** Use the exact commands in plan
      §3c. In order:
      - [ ] 5.5.1 Re-verify state first: `gh issue view 6808 --json number,state,labels,title`
            (`hr-before-asserting-github-issue-status`).
      - [ ] 5.5.2 `gh issue comment 6808 --body "$(cat <<'EOF' … EOF)"` with the §3c body. It MUST
            name **#6588**, **this PR** (substitute the real URL for `<PR_URL>`), the **reaffirmed
            hold**, and state that #6808 now gates a **live published over-claim** — not merely a
            monitoring gap. Carry the open `hcloud_volume.git_data` one-vs-two-backstops
            precondition into the comment.
      - [ ] 5.5.3 `gh issue edit 6808 --add-label "priority/p1-high" --add-label "type/security"
            --remove-label "priority/p2-medium"`. **Not `p0-critical`** — see §3c for why
            (p0 = "drop everything" contradicts the operator's hold-and-proceed decision; zero
            arms-length data subjects today). Record the p0 trigger in the thread: if #3723
            onboards a first arms-length user while #6808 is open.
      - [ ] 5.5.4 Verify AC15: re-read labels and the last comments from the issue itself.
- [ ] 5.6 Post the Art. 17 erasure-reachability gating note as a **comment on #3723** (not in the diff).
- [ ] 5.7 CLO agent writes `knowledge-base/legal/audits/2026-07-counsel-review-6588.md`
      (**not** an operator task). It MUST record block **B1 as recommended, overridden by the
      operator, and residually accepted**, with #6808 as the tracker (AC12) — an attestation that
      omits its own overridden block fails the AC.

## Phase 6 — Verification

- [ ] 6.1 `bash apps/web-platform/scripts/check-tc-document-sha.sh`
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts`
- [ ] 6.3 `python3 scripts/lint-encryption-posture.py --repo-sweep`
- [ ] 6.4 `bun test plugins/soleur/test/marketing-content-drift.test.ts`
- [ ] 6.5 `./node_modules/.bin/eleventy --dry-run` (repo-root pinned binary, **never `npx`**)
- [ ] 6.6 Full suite (`bash scripts/test-all.sh`); **grep the log for `FAIL` / `× `** — do not trust
      a background runner's exit code.
- [ ] 6.7 **AC4 gate — the hold held.** Across the 6 published files,
      `grep -nEi "rollback backstop|pre-cutover|plaintext volume|unencrypted volume|superseded .{0,30}volume|stored \*\*live\*\* workspace|older, unencrypted"`
      returns **0**, and `git diff origin/main -- <6 files>` adds no line matching it.
- [ ] 6.8 Walk **AC1–AC15** and tick each with its evidence (AC15 = the #6808 escalation).
