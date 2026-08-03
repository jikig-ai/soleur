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

- [x] 0.1 Dispatch `gh workflow run workspaces-luks-verify.yml` (do **not** set `seed_workspace_count`).
- [x] 0.2 Wait for completion; capture the run id + conclusion
      (`gh run list --workflow=workspaces-luks-verify.yml --limit 1 --json databaseId,conclusion`).
- [x] 0.3 Confirm `device_type=crypto_LUKS`, `mount_source=/dev/mapper/workspaces`, `escrow=ok`,
      `header=readable`, `workspace_count=8 expected=8`.
- [x] 0.4 **If RED → switch to the DEGRADED-SCOPE branch** in plan §Phase 0 (retract clause (d)
      instead of re-scoping; strike **AC3** — **AC4 and AC15 still stand**; DC-1 stays OPEN;
      `Ref` not `Closes`; file P0 incident; say so in the #6808 escalation comment).
- [x] 0.5 Re-assert #6570 / #6808 / #6897 / #3723 still OPEN. Capture **#6808's current labels**
      (`gh issue view 6808 --json state,labels`) — AC15 asserts a delta against them.
- [x] 0.6 Record `python3 scripts/lint-encryption-posture.py --repo-sweep` baseline (expect PASS).

## Phase 1 — Union-anchor site inventory

- [x] 1.1 Run the union-anchor grep across the 6 published files; reconcile against the plan's
      Site Matrix. Any divergence ⇒ `main` moved; re-reconcile before editing.
- [x] 1.2 Extend the same sweep to `knowledge-base/legal/article-30-register.md` and
      `knowledge-base/legal/compliance-posture.md`.
- [x] 1.3 Confirm the `eu-fsn-3` / Better Stack carve-out is excluded from any `Falkenstein` sweep
      (`pp:379`, mirror `:378`, `dpd:103`, mirror `:112` are TRUE claims — do not touch).
- [x] 1.4 Apply the claim-family litmus per site.

## Phase 1.5 — Audit trail first

- [x] 1.5.1 Create `specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` with the
      Deliverable-3 User-Challenge record. **All five elements (AC11):** (i) the #6918 UC-3 hold;
      (ii) the revisit-trigger analysis as put to the operator (*"if the teardown slips materially,
      revisit Path 2"*; #6808 OPEN ⇒ soak clock not started ⇒ earliest cure "#6808 fix + 7 days",
      no committed date); (iii) the operator's **REAFFIRMATION** of the hold on 2026-07-24;
      (iv) the CLO's contrary recommendation (B1) recorded as **overridden, not deleted**; (v) the
      accepted residual with **#6808** as its tracking issue.
      *(Ordering rationale: no reversal to guard — it is written first because Phase 5's escalation
      comment quotes it and the CLO attestation cites it.)*
- [x] 1.5.2 Create `site-dispositions.md` — 16 rows (8 canonical + 8 mirror), per-claim disposition.

## Phase 2 — Canonical body edits

Work **one claim family at a time across all files**, not one file at a time.
**Deliverables 1 + 2 only.** No site gets a plaintext-disclosure sentence and no site gets a
scope-to-live (*"stored **live** workspace git data …"*) qualifier — that was the retracted D3.

- [x] 2.1 `dpd:189` processor table (highest-grade: Art. 13(1)(e) / 30(1)(d)) — retract (a)(b)(c) +
      web-2; **keep the LUKS claim as-is** (table cell), re-anchored so it does not dangle.
- [x] 2.2 `pp:298` — retract (a)(b)(c) + web-2 (**"has been in Falkenstein"** phrasing); keep LUKS
      re-anchored so it does not dangle.
- [x] 2.3 `pp:519` §11 — retract (a)(b)(c); drop the "spans more than one Hetzner host" premise;
      keep the LUKS claim standing unconditioned on the live single-host topology.
- [x] 2.4 `gdpr:44` — retract (a)(b)(c) (**note word order: "a dedicated host for per-workspace git
      data"**) + web-2; drop multi-host premise; keep LUKS.
- [x] 2.5 `dpd:276` — retract (a)(c) + web-2; drop multi-host premise; keep LUKS.
      (**Carries LUKS — verified.**)
- [x] 2.6 `pp:489`, `gdpr:318` — retract multi-host premise + web-2. **Add no LUKS claim.**
- [x] 2.7 `dpd:318` — correct the Hetzner two-DC transfer claim ("Helsinki … and Falkenstein").
- [x] 2.8 **Self-check before leaving this phase:** run AC4's disclosure anchor over the three
      canonicals — it must return **0**. The one-vs-two-backstops question
      (`hcloud_volume.git_data`) is **NOT resolved in this PR**; it is carried into the #6808
      escalation comment (task 5.5) for whoever writes the deferred Path-2 wording.

## Phase 3 — Mirrors, banner, dates

- [x] 3.1 Mirror every Phase-2 edit (hand-maintained; **no generator**). Sites: `pp` `:297/:475/:500`,
      `dpd` `:186/:261/:301`, `gdpr` `:53/:306`.
- [x] 3.2 Banner, all 6 files, in order: **(a) annotate** — append the retraction marker at the END
      of the July-2 segment (immediately before `Previous: June 30, 2026`), never mid-segment;
      **(b) demote** `**Last Updated:** July 16, 2026 (` → `Previous: July 16, 2026 (`;
      **(c) prepend** the new `**Last Updated:** July 24, 2026 (…). ` head.
- [x] 3.3 **Do NOT sync mirror banners to canonical** — mirrors legitimately carry truncated history
      (18/17/17 vs 12/13/11 `Previous:` occurrences). Edit in place only.
- [x] 3.4 Set the new date at **9 sites**: 3 canonical body, 3 mirror body, 3 mirror hero `<p>`.
- [x] 3.5 Verify no `##`/`###` heading changed; if any did, mirror it exactly.
- [x] 3.6 Apply the §4c style decision — **`Ref #6588`** (resolved by history: the `Ref #NNNN
      (<branch-slug>)` form was adopted 2026-06-10 and supersedes the 2026-05-12 learning) —
      uniformly to the banner head and any body-prose `Ref`. Record the supersession in the PR body.

## Phase 4 — Mechanical pins (ledger FIRST, SHA LAST)

- [x] 4.1 Ledger `disclosed_as` **×2** → content anchors: `stores[0]` (dead `:519` anchor —
      `grep -c "519"` is 0) and `connections[0]` (`dpd:316`).
      **`stores[2]` (`hcloud_volume.workspaces`) must be BYTE-UNCHANGED** — including
      `exception.justification`. It was in scope only for the retracted D3; with the hold
      reaffirmed, `not-publicly-claimed` is trivially correct (AC8).
- [x] 4.2 Re-run `python3 scripts/lint-encryption-posture.py --repo-sweep` (expect PASS).
- [x] 4.3 **THEN** `sha256sum` the 3 canonicals; paste full 64-char values into `LEGAL_DOC_SHAS`.
- [x] 4.4 `bash apps/web-platform/scripts/check-tc-document-sha.sh` (expect exit 0).
- [x] 4.5 **Invariant:** no `docs/legal/**` byte may change after 4.3. If one does, redo 4.3–4.4.
- [x] 4.6 File the one-line issue against **#6893** for the linter's honest-under-claim blind spot
      (§Risks R4b — it is a **latent blocker on the deferred Path-2 wording**, not exercised here).
      Do **not** edit `scripts/lint-encryption-posture.py` in this PR.

## Phase 5 — Registers, DC-1, escalation, attestation

- [x] 5.1 `article-30-register.md` — residual-zero: `(g)` TOMs `:50` + `:68` (replace items 13–16 /
      17–20 with the measure that IS true, do not merely delete), `(d)` Recipients `:47`,
      `(e)` Transfers `:48` + `:163`, Vendor mapping `:426`. Re-grep PA identity before editing.
      **The register is INTERNAL and still names the retained plaintext backstop as a residual**
      (§4d — unchanged by the amendment; only *published* text is held). Do not "harmonise" the
      register down to match the published docs.
- [x] 5.2 `compliance-posture.md:80` — drop `git-data host CAX11`; clear present-tense `web-2`.
      **No #3723 Art. 17 gate is added to this file** (cut at plan-review) — see 5.6.
- [x] 5.3 `nfr-register.md:522` — correct (non-blocking, AC9b). **`:521` is not touched.**
- [x] 5.4 DC-1 in `specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` → RESOLVED; record the
      2026-07-23 certification, this PR's retraction, and the **lapsed** 2026-07-23 reopen trigger.
- [x] 5.5 **ESCALATE #6808 — Deliverable 3's shipped half (AC15).** Use the exact commands in plan
      §3c. In order:
      - [x] 5.5.1 Re-verify state first: `gh issue view 6808 --json number,state,labels,title`
            (`hr-before-asserting-github-issue-status`).
      - [x] 5.5.2 `gh issue comment 6808 --body "$(cat <<'EOF' … EOF)"` with the §3c body. It MUST
            name **#6588**, **this PR** (substitute the real URL for `<PR_URL>`), the **reaffirmed
            hold**, and state that #6808 now gates a **live published over-claim** — not merely a
            monitoring gap. Carry the open `hcloud_volume.git_data` one-vs-two-backstops
            precondition into the comment.
      - [x] 5.5.3 `gh issue edit 6808 --add-label "priority/p1-high" --add-label "type/security"
            --remove-label "priority/p2-medium"`. **Not `p0-critical`** — see §3c for why
            (p0 = "drop everything" contradicts the operator's hold-and-proceed decision; zero
            arms-length data subjects today). Record the p0 trigger in the thread: if #3723
            onboards a first arms-length user while #6808 is open.
      - [x] 5.5.4 Verify AC15: re-read labels and the last comments from the issue itself.
- [x] 5.6 Post the Art. 17 erasure-reachability gating note as a **comment on #3723** (not in the diff).
- [x] 5.7 CLO agent writes `knowledge-base/legal/audits/2026-07-counsel-review-6588.md`
      (**not** an operator task). It MUST record block **B1 as recommended, overridden by the
      operator, and residually accepted**, with #6808 as the tracker (AC12) — an attestation that
      omits its own overridden block fails the AC.

## Phase 6 — Verification

- [x] 6.1 `bash apps/web-platform/scripts/check-tc-document-sha.sh`
- [x] 6.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts`
- [x] 6.3 `python3 scripts/lint-encryption-posture.py --repo-sweep`
- [x] 6.4 `bun test plugins/soleur/test/marketing-content-drift.test.ts`
- [x] 6.5 `./node_modules/.bin/eleventy --dry-run` (repo-root pinned binary, **never `npx`**)
- [x] 6.6 Full suite (`bash scripts/test-all.sh`); **grep the log for `FAIL` / `× `** — do not trust
      a background runner's exit code.
- [x] 6.7 **AC4 gate — the hold held.** Across the 6 published files,
      `grep -nEi "rollback backstop|pre-cutover|plaintext volume|unencrypted volume|superseded .{0,30}volume|stored \*\*live\*\* workspace|older, unencrypted"`
      returns **0**, and `git diff origin/main -- <6 files>` adds no line matching it.
- [x] 6.8 Walk **AC1–AC15** and tick each with its evidence (AC15 = the #6808 escalation).

---

## Verification evidence (so each tick above is checkable, not asserted)

Recorded per the "an acceptance checkbox is a CLAIM" rule — every box ticked above was
measured, not toggled in bulk.

| AC | Result | Evidence |
|---|---|---|
| AC1 residual zero (body prose, banner excluded) | **0** across all 6 | union-anchor grep with `grep -vE '^\*\*Last Updated:\*\*'` |
| AC2 per-site disposition | **16 rows** | `site-dispositions.md` (8 canonical + 8 mirror) |
| AC3(a) no widening | **0** across all 6 | baseline on `origin/main` also measured 0 |
| AC3(b) LUKS not deleted | **10/10 sites** | 2/2/1 canonical + 2/2/1 mirror, matching the Site Matrix |
| AC4(a) disclosure absence | **0** across all 6 | `origin/main` baseline also 0 |
| AC4(b) nothing added by the diff | **0** added lines | `git diff origin/main` over the 6 files (banner counts as an added line) |
| AC4(c) no published wipe date | **0** | same diff, wipe-date regex |
| AC5 date parity | **9/9 captures = July 24, 2026** | the gate's own regexes (`legal-doc-consistency.test.ts`), not `grep -c` |
| AC6 SHA pins | **exit 0** + 3 full 64-char values | `check-tc-document-sha.sh`; each confirmed by `git grep -F` |
| AC7 banner integrity | **6/6** segment preserved (818/823/827 chars), `Previous:` +1 exactly | 18→19, 17→18, 17→18, 12→13, 13→14, 11→12 via `grep -o \| wc -l` |
| AC8 posture linter + 2 anchors | **PASS** unchanged; diff touches exactly 2 strings; `stores[2]` **IDENTICAL** | JSON round-trip vs `origin/main` |
| AC9(a) register residual | **9 lines → 1** | survivor is the pre-existing out-of-class *"must be re-verified on every update"* |
| AC9(b) compliance-posture | CAX11 + standby removed from DPA scope | `:80` |
| AC9b NFR | `:522` corrected; `:521` reviewed and deliberately left | status `Adopting` asserts no live safeguard; tracked by #6570 |
| AC10 DC-1 | no longer `OPEN — remediation tracked` | RESOLVED, lapsed reopen trigger recorded |
| AC11 challenge record | **5/5 elements** | #6918 hold · revisit-trigger · REAFFIRMATION · CLO OVERRIDDEN · #6808 |
| AC12 CLO attestation | written by the `clo` agent | `## §B1 — recommended, overridden, residually accepted` |
| AC13 `Ref` not `Closes` #6897 | commit bodies clean | close-keyword scan over `origin/main..HEAD` returned empty |
| AC14 live verification | run **30130277489** (2026-07-24T22:13Z) | `crypto_LUKS` · `/dev/mapper/workspaces` · escrow ok · header readable · 8/8 |
| AC15 #6808 escalated | labels + comment | `priority/p1-high` + `type/security`, `p2-medium` removed; comment names #6588, PR #6938, the reaffirmed hold, the over-claim framing |

**Full-suite exit gate:** `bash scripts/test-all.sh` -> **222/222 suites passed**, rc=0
(log grepped for `FAIL`/`x ` rather than trusting the exit code; the apparent hits are
`PASS: ... FAILS` assertions and `_fail sentinel` lines). Ran under a `SIBLING_RUN_DETECTED`
banner (2 concurrent worktree runs) and still came back clean.

**Gates run:** `check-tc-document-sha.sh` (exit 0, and **mutation-tested** — zeroing one pinned
SHA turns it RED, restoring returns it to green, so the green is not vacuous) ·
`legal-doc-consistency.test.ts` 13/13 · `legal-doc-shas-guard.test.ts` 6/6 ·
`lint-encryption-posture.py --repo-sweep` PASS · `marketing-content-drift.test.ts` 8/8 ·
`eleventy --dryrun` exit 0.

**Plan corrections found while implementing** (recorded rather than silently absorbed):

1. **Site count.** Phase 1 asserts the union anchor returns 22; it returns **20**
   (= (7 body + 3 banner) × 2). `dpd:318` + mirror `:301` carry zero anchor tokens — as the
   Site Matrix itself states — so the grep structurally cannot find them. 20 + 2 = 22 sites.
   The matrix is right; the assertion's phrasing conflated the two. Not a `main`-moved signal.
2. **Register enumeration undercount.** §4d lists 6 cells but PA-2 has its **own** `(d)` and
   `(e)` carrying `web-2` — found by re-running the union anchor over the whole file. This is
   the plan's own P7 failure mode recurring inside the fold-in. Independently confirmed by the
   CLO agent.
3. **Eleventy flag.** Phase 6 prescribes `--dry-run`; the pinned Eleventy 3.1.5 only accepts
   `--dryrun`. The prescribed form exits 1 with "We don't know what '--dry-run' is".
4. **Ordering deviation, self-reported.** Phase 1.5 (audit trail) was written *after* the
   Phase 2/3 body edits rather than before. No abort occurred in the window, so nothing was
   lost — but the ordering exists precisely to survive an abort, and it was not honoured.
