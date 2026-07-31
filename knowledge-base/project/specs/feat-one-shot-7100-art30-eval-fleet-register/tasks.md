# Tasks — Art. 30(1) entries for the Anthropic-egressing fleet, community republication, and CI surface

Derived from
[`knowledge-base/project/plans/2026-07-31-docs-art30-register-claude-eval-fleet-and-ci-surface-plan.md`](../../plans/2026-07-31-docs-art30-register-claude-eval-fleet-and-ci-surface-plan.md).
Issue **#7100**. Lane: `cross-domain` — **no `spec.md` exists for this branch, so the lane
defaulted fail-closed** per the plan skill's TR2 rule.

**Before anything else, read `## Decision Challenges` in the plan** (UC-1…UC-4). Two challenge
the docs-only scope; one records that PA-32 will state a live limb has no lawful basis.

**Scope (hard):** `knowledge-base/legal/**` plus this spec directory. No source file, no
workflow YAML, no `docs/legal/**`.

---

## Phase 0 — Preconditions (no writing until all pass)

- [x] 0.1 Re-derive the fleet enumeration with the plan's canonical probe block. Record the
      measured values in the LIA provenance section.
      **Expected:** 15 CLI crons · 13 `spawnClaudeEval` · 2 direct `resolveClaudeBin` ·
      20 substrate importers · 3 HTTP callers · **21-member union, with the two independent
      predicates identical (`diff /tmp/setA /tmp/setB` clean)**.
- [x] 0.2 **On any mismatch, the measurement wins** — stop authoring, rebuild the snapshot from
      the measurement, note the divergence in the LIA. Never reconcile by editing the plan.
- [x] 0.3 Confirm the next free PA number against `origin/main` (not the worktree):
      `git fetch origin main && git show origin/main:knowledge-base/legal/article-30-register.md | grep -nE '^## Processing Activity [0-9]+ — ' | tail -3`
- [x] 0.4 Re-verify workflow states: `gh workflow list --all | grep -iE 'fix-constraints|claude|pretooluse'`,
      and re-run `grep -rl 'secrets.ANTHROPIC_API_KEY' .github/` (expect **5** files).
- [x] 0.5 Re-verify the materialised-exposure figures (80 / 45 / 65 / 0 deletions / public / 2 forks).
      **Re-verify the file-write limb's live state** — #7075 links a digest that does not exist.
- [x] 0.6 Baseline `bash scripts/check-pa-22.sh` → exit 0 **before** any edit (AC11i).
- [x] 0.7 Read for house style: PA-17, PA-22, PA-27, PA-30; the PA-27 LIA and DPIA memo;
      `2026-07-07-beta-crm-lia.md` (Art. 14 section **and** its git-committed-PII rejection —
      the decisive precedent for D9); counsel review `2026-07-counsel-review-7086.md`.

## Phase 1 — Author the LIA

`knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md`

- [x] 1.1 Frontmatter per the LIA class + the DRAFT blockquote.
- [x] 1.2 Provenance section carrying every Phase 0 measurement with its command.
- [x] 1.3 **Arm A** — repo/engineering population (PA-22 reasonable-expectation precedent).
- [x] 1.4 **Arm B1** — community collection + Anthropic egress.
- [x] 1.5 **Arm B2** — republication. Must conclude **legitimate interest does not prevail as
      implemented**: necessity fails (C-13/16 *Rīgas satiksme*; EDPB Guidelines 1/2024), the
      Discord arm fails Recital 47 expectations, Art. 17 is not implementable against git
      history + 2 forks, and PA-30's LIA already rejected git-committed PII. Name R1–R5 as the
      conditions under which the conclusion would change.
- [x] 1.6 **Arm C** — CI contributors; include the CLA-coverage question (cross-ref PA-7).
- [x] 1.7 **Art. 14 section, per arm.** Overdue since ~2026-03-19. No Art. 14(5) exemption
      claimed; 14(5)(b) fails for Discord (Jikigai operates the guild) and GitHub commenters
      (reachable via README/CONTRIBUTING/issue templates); arguable only for HN + stargazers.
- [x] 1.8 **PA-17 trigger discharge** — state that the #4558 trigger fired ~5 months ago and
      was not honoured; cite `knowledge-base/legal/audits/2026-05-counsel-review-4558.md`.
- [x] 1.9 **External-authority rule.** WebFetch-verify every citation, record the verification
      date inline, drop anything unverifiable. EDPB **Guidelines 03/2026** = adopted 8 July
      2026 **for public consultation, open until 30 October 2026** — a draft, whose subject is
      scraping in the *generative-AI* context (collection limb analogous; training limb not).
      DPF: in force; *Latombe* T-553/23 dismissed 3 Sep 2025; appeal **C-703/25 P** pending.

## Phase 2 — Author the DPIA screening memo

`knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md`

- [x] 2.1 Frontmatter (`type: dpia-screening-memo`) + DRAFT blockquote.
- [x] 2.2 `| Criterion | Finding |` table over Art. 35(3)(a)–(c) + the WP248 rev.01 nine
      criteria + a CNIL-list check (France is the supervisory jurisdiction).
- [x] 2.3 **Do not prejudge.** PA-27 engaged 2 criteria; this activity plausibly engages 5+
      (systematic monitoring; matching/combining across 6 platforms; data of a highly personal
      nature — private-guild messages; involuntary subjects with no relationship at all;
      innovative technology; arguably "prevents exercise of a right" via the Art. 17
      impossibility). "Large scale" is the one clear miss — reason it honestly rather than
      adopting the source-count framing, which is not the WP243 test.
- [x] 2.4 If the honest run concludes a **full DPIA is required**, say so, record that Art.
      35(1) requires it *prior to* processing (so it is overdue), and file deferred item 5.
      Note that R1–R4 collapse several criteria at once — remediation may be the better path.
- [x] 2.5 Named accepted residuals + pinned re-screening triggers.

## Phase 3 — Author PA-31 / PA-32 / PA-33 and amend PA-17

- [x] 3.1 Insert the three entries between PA-30's closing `---` and `## Register Maintenance`.
      Current-generation 10-row schema in canonical order; `(h) DSAR` row required on all three.
- [x] 3.2 **PA-31** — egress predicate + dated 21-member snapshot; tiered `(b)`; the
      input-vs-output distinction with verbatim directives **and** counter-directives; `(d)`
      naming Anthropic, GitHub Inc and **Sentry** (bounded tail, unscrubbed for handles);
      `(f)` naming the Anthropic 30-day default under the unsigned Zero-Retention amendment
      **and** the self-hosted Inngest store's no-automatic-deletion posture.
- [x] 3.3 **PA-31 `(g)` — the accuracy traps.** Scope the allowlist TOM to the 13 hooked
      members; name `cron-daily-triage` + `cron-follow-through-monitor` as unhooked with the
      Tier-2 egress firewall as sole compensating control; assert affirmatively that **no PII
      scrub exists** on Anthropic-bound content (do **not** inherit PA-22's
      `sanitizePromptString` TOM); frame the grandchild-process gap as two measures at two
      layers; describe teardown as fail-open; give the env-var range (4–6, one member 18);
      never present a prompt directive as a technical measure.
- [x] 3.4 **PA-32** — the republication entry. `Lawful basis` records the Art. 6(1)(f)
      unavailability (AC2a). Plus the CLO Q5 limbs: "the general public" + GitHub Inc as
      recipients (inverting PA-17); the *Lindqvist* C-101/01 note that publication is **not** a
      Chapter V transfer; `(f)` as an Art. 5(1)(e) finding; Art. 22 negative determination;
      Art. 5(1)(b)/6(4) purpose compatibility; Art. 15/20 and Art. 21(1) cross-refs; the
      Discord Developer Policy limb; the non-EU threshold line. Cite the `.[:120]` vs
      "under 100 chars" discrepancy as two distinct mechanisms.
- [x] 3.5 **PA-33** — membership by `secrets.ANTHROPIC_API_KEY` (5 files), each with trigger
      class and workflow state; `claude-code-review.yml` flagged as `disabled_manually` **and**
      as GitHub API state invisible to source inspection, with date + method. Record that
      `ci.yml` also fires on `push:[main]` and `merge_group`, so PA-33 is not PR-only.
- [x] 3.6 **Amend PA-17** — (a) dated trigger-fired note pointing at PA-32; (b) correct the
      `(c)` "display-only" carve-out; (c) narrow the `(g)` render-time-redaction claim.
- [x] 3.7 Extend the **Anthropic PBC** Vendor Mapping row, **preserving the
      `Anthropic.*PA-22.*autonomous` token order**; replace the prose gestures
      (`claude-code-action` CI, compound-promotion-loop #2720) with PA references.
- [x] 3.8 Bump `last_reviewed`; add a `## Register Maintenance` counsel item if Phase 2 lands
      on the full-DPIA arm.

## Phase 4 — Reconcile the downstream records

- [x] 4.1 `anthropic.md` — `register_activity_refs: [PA-22, PA-27, PA-31, PA-32, PA-33]`;
      remove the `INCOMPLETE` marker; correct `role:`; **correct the stale enumeration** in the
      2026-07-30 bullet (13 not 15 `spawnClaudeEval`; 20 importers; 3 HTTP callers; 5 CI files);
      add a dated resolution note.
- [x] 4.2 `compliance-posture.md` — changelog comment at the top of the reverse-chron block;
      rewrite the `#7100` parenthetical in the Anthropic row; Active Items rows for the open
      residuals (Art. 14 overdue, R1–R5, drift guard, hook gap); bump the Art. 30 register row's
      Last Updated in `## Legal Documents`; bump `last_updated` frontmatter.

## Phase 5 — File deferred issues, then verify

- [ ] 5.1 File the **unconditional** deferred items (0, 1, 1a, 2, 3, 4, 6, 7, 8, 9) with
      re-evaluation criteria and a roadmap milestone. Item 5 (full DPIA) **only** on arm (ii).
- [ ] 5.2 Wire each issue number into the PA `(g)` tails, the LIA, and the
      `compliance-posture.md` Active Items rows.
- [ ] 5.3 Run the full Acceptance Criteria (AC1 … AC17). Use the **flag-based** `awk`; the
      naive `/start/,/end/` range self-matches and returns a heading-only body.
- [ ] 5.4 AC13 resolver — the only permitted `BROKEN:` line is the deferred sweep path.
- [ ] 5.5 `bash scripts/check-pa-22.sh` → exit 0 **after** the Vendor-row edit (AC11i).
- [ ] 5.6 AC2 collision re-check against `origin/main` **after the final rebase**.
- [ ] 5.7 AC17 scope check — diff confined to `knowledge-base/legal/**` and
      `knowledge-base/project/{plans,specs}/**`.
