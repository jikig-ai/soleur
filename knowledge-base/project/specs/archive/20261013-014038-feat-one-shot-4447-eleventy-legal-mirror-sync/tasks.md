---
title: "Tasks: Sync Eleventy legal mirror DPD with canonical (#4447)"
date: 2026-05-25
plan: knowledge-base/project/plans/2026-05-25-docs-sync-eleventy-legal-mirror-dpd-plan.md
branch: feat-one-shot-4447-eleventy-legal-mirror-sync
lane: cross-domain
---

# Tasks: Sync Eleventy legal mirror DPD with canonical (#4447)

## Phase 0: Preconditions (RED — baseline evidence)

- [ ] 0.1. Confirm `pwd` == worktree root and `git branch --show-current` == `feat-one-shot-4447-eleventy-legal-mirror-sync`.
- [ ] 0.2. Run `bash apps/web-platform/scripts/check-tc-document-sha.sh; echo "exit=$?"` → record `exit=0` as baseline.
- [ ] 0.3. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts` → record 13 passing as baseline.
- [ ] 0.4. Run `diff docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md | wc -l` → record ~114 (the surface).
- [ ] 0.5. Snapshot canonical changesets to `/tmp/`:
  - [ ] 0.5.1. `git show b382cee0 -- docs/legal/data-protection-disclosure.md > /tmp/4417-canonical-dpd.diff`
  - [ ] 0.5.2. `git show af7bbb5b -- docs/legal/data-protection-disclosure.md > /tmp/4351-canonical-dpd.diff`
- [ ] 0.6. Capture mirror-only content: `diff docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md | grep -E "^> " > /tmp/mirror-only-content.txt`.

## Phase 1: Mirror forward-port (canonical → mirror) — SIX surgical edits

- [ ] 1.1. Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` §2.3(l) DSAR self-serve export (mirror line 111):
  - Replace short-form bullet with canonical's extended form from line 102.
  - MUST include verbatim: `Art. 15(4) author-only redaction (#4319, manifest schema 1.1.0)`, `MESSAGE_REDACT_FIELDS` constant ref + 13-column list, per-bundle salt-scoped pseudonym `member_<hex12>`, attachments cascade allowlist (orphan / foreign-author parents → fail-closed), `manifest.redactions[]` field, CI sentinel test reference `dsar-message-redact-fields-sweep.test.ts`.
- [ ] 1.2. INSERT §2.3(p) NEW BLOCK into mirror — full LinkedIn Company Page publication block from canonical line 115. Place between mirror's existing §2.3(o) (line 119) and §2.3(n) (line 120):
  - Sub-surface (i) Page operation (Community Management API, developer app 229658411, `LINKEDIN_ORG_ACCESS_TOKEN` 60-day OAuth bearer).
  - Sub-surface (ii) Page Insights aggregate consumption (joint controllers per CJEU C-210/16, EDPB Guidelines 07/2020).
  - Sub-surface (iii) K-bis business-verification (gérant, Jikigai SARL, RCS Paris 927 585 729, capital structure metadata) to Microsoft Ireland.
  - Legal bases, retention, sub-processors, Article 30 register PA-15 cross-reference.
- [ ] 1.3. Edit mirror §2.3(t) Template-authorization ledger (mirror line 126): replace SHORTER form with canonical's EXTENDED form from line 119:
  - Over-provision rationale: "(vs. cutting to 5) preserves Article 5(2) audit attribution distinguishability for future revocation drivers (three values — `regulator_ordered`, `vendor_tos_revoked`, `policy_violation` — have no v1 producer; `quarantine_retroactive` reserved for PR-I+1 #4216). Cheaper to add at mig 053 than ALTER later."
  - RLS owner-only policy names: `template_authorizations_owner_select` / `_insert`.
  - ADR-035 path: `knowledge-base/engineering/architecture/decisions/ADR-035-template-registry-code-static.md`.
  - ADR-036 fold provenance: "this entry captures the un-revocability + Article 5(2) attribution rationale formerly proposed as ADR-036 (folded here per plan §Phase 10 v2 review)".
- [ ] 1.4. Edit mirror §5.3 Web Platform Data Subject Rights (mirror lines 219-228):
  - Replace short bullet (a)-(f) with canonical's detailed form (lines 216-232).
  - Self-serve hint sentence: `For data processed through the Web Platform ... through either the self-serve flow at /dashboard/settings/privacy (where applicable) or by contacting <legal@jikigai.com>:`.
  - 8-item account-profile sub-list under (a): account profile, conversations + messages, message attachments (with co-member visibility caveat), KB share links, team/agent display names, BYOK encrypted credentials, BYOK usage audit log, workspace files.
  - Per-bullet channel labels: (b)/(d)/(f) Email channel; (c) "Self-serve via the Delete Account dialog in `/dashboard/settings` or by email"; (e) self-serve at `/dashboard/settings/privacy` with manifest.json schema details.
  - Exclusion-list sentence at end of (a): "Excluded from the export, with reason: DSAR-itself audit metadata ..., operational concurrency / rate-limit / revocation / mint-rate tables..., and push notification subscriptions...".
- [ ] 1.5. Edit mirror §10.3 Web Platform Account Deletion (mirror lines 342-346): insert sub-bullets (f)-(i) from canonical lines 353-356:
  - (f) Any in-flight DSAR export job is aborted (status flipped to `failed` with reason `account_deleted_during_export`).
  - (g) Storage objects under `chat-attachments/<your-id>/` and `dsar-exports/<your-id>/` are removed; co-uploader attachments in shared-workspace conversations retained under Article 6(1)(f) shared-asset legitimate interest (#4318, mig 068); `messages.user_id set to NULL via public.anonymise_departed_user_across_workspaces`.
  - (h) DSAR audit log `dsar_export_audit_pii` PII columns anonymised via security-definer RPC gated by per-transaction GUC.
  - (i) LinkedIn-published content carve-out (Article 17 limitation, 5-business-day deletion request via Page admin UI, EDPB Guidelines 5/2019 best-effort cascade).
- [ ] 1.6. Edit mirror Last-Updated chain (line 21): replace the compressed summary with canonical's longer narrative from line 12 (preserves Article 30(1) audit-trail completeness — the migration 064 LAWFUL_BASIS header context, `to_regclass` precondition note, the #4287 AFTER-trigger PA-20 mechanics, `actor_user_id` session GUC, etc.).
- [ ] 1.7. Verify mirror still ends with the Eleventy njk closing scaffold (`</div></div></section>`) and frontmatter is intact.

## Phase 2: ~~Canonical back-port~~ **(REMOVED per deepen-pass round-2)**

Skip — canonical is unchanged by this PR. Deepen-pass round-2 diff inventory confirmed canonical has no surface where the mirror is uniquely ahead (mirror's Last-Updated chain compression is a strict subset of canonical's narrative).

## Phase 3: Frontmatter + cosmetic reconciliation

- [ ] 3.1. Verify mirror hero date: `grep -n "Last Updated May 25, 2026" plugins/soleur/docs/pages/legal/data-protection-disclosure.md` → expect 1 match (the `<p>` hero).
- [ ] 3.2. Verify body Last-Updated date parity: `grep -c "\*\*Last Updated:\*\* May 25, 2026" docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` → expect `1` per file.
- [ ] 3.3. Run the residual-diff confirmation:

  ```bash
  diff \
    <(awk '/^---$/{c++;next} c>=2' docs/legal/data-protection-disclosure.md) \
    <(awk '/^---$/{c++;next} c>=2' plugins/soleur/docs/pages/legal/data-protection-disclosure.md \
      | sed -E '/^<\/?(section|div|h1|p)/d')
  ```

  Confirm any remaining lines are only (a) link-form differences (`legal/foo.md` vs `/legal/foo/`), (b) host-form differences (`https://soleur.ai` vs `https://www.soleur.ai`). Anything else is a sync gap → return to Phase 1 / 2.

## Phase 4: Extend the body-equivalence guard

- [ ] 4.1. Edit `apps/web-platform/scripts/check-tc-document-sha.sh` Step 1:
  - Declare `BODY_EQUIVALENCE_DOCS=("terms-and-conditions" "data-protection-disclosure")` near the top of the file (alongside `EXPECTED_COUNT`).
  - Replace `if [ "$doc" = "terms-and-conditions" ]; then` (in Step 1 only) with a membership check helper:

    ```bash
    needs_body_equivalence() {
      local d="$1"
      for x in "${BODY_EQUIVALENCE_DOCS[@]}"; do
        [ "$x" = "$d" ] && return 0
      done
      return 1
    }
    ```

    Use `if needs_body_equivalence "$doc"; then`. PRESERVE the existing T&C-specific `TC_VERSION` bump bypass logic (which is in Step 3, not Step 1).
- [ ] 4.2. Re-run `bash apps/web-platform/scripts/check-tc-document-sha.sh; echo "exit=$?"` → expect `exit=0`.
- [ ] 4.3. If the body-equivalence check fails for DPD with a non-trivial residual diff, inspect the diff and either (a) refine the Phase 1 forward-port to close the gap, or (b) extend `normalize_plugin` / `collapse` with additional doc-agnostic sed rules that the DPD specifically needs. Justify each new sed rule in a comment.

## Phase 5: SHA literal verification (no refresh expected)

- [ ] 5.1. Compute current canonical DPD SHA: `sha256sum docs/legal/data-protection-disclosure.md` → expect `04a2d796aff50f8457451b088c048a3c6cdf7eb84c9dacdbd01d5b42735a1d02` (deepen-time verified — canonical is unchanged by this PR).
- [ ] 5.2. Verify `apps/web-platform/lib/legal/legal-doc-shas.ts` already contains that literal (no edit needed).
- [ ] 5.3. Re-run `bash apps/web-platform/scripts/check-tc-document-sha.sh; echo "exit=$?"` → expect `exit=0`. The body-equivalence step now runs for DPD (Phase 4); the canonical-SHA-pin step still passes against the unchanged literal.

## Phase 6: Regression smoke test (vitest)

- [ ] 6.1. Add a new test case to `apps/web-platform/test/legal-doc-shas-guard.test.ts` inside the existing `describe("check-tc-document-sha.sh: drift-class smoke", ...)` block. Pattern:

  ```ts
  test("data-protection-disclosure: mirror body drift fails the guard", () => {
    const tmp = tmp; // beforeEach-provided
    const mirrorPath = join(tmp, "plugins/soleur/docs/pages/legal/data-protection-disclosure.md");
    const body = readFileSync(mirrorPath, "utf8");
    // Mutate a load-bearing line that body-equivalence MUST detect:
    writeFileSync(mirrorPath, body.replace("Art. 15(4)", "Art. 15(5)"));
    const result = runGuard(tmp);
    expect(result.status).toBe(1);
    expect(result.stderr + result.stdout).toMatch(/data-protection-disclosure.*body drift|body.*drift.*data-protection-disclosure/i);
  });
  ```

  (The exact text-match is permissive because the script emits the doc name + "body drift" in either order depending on the loop iteration.)
- [ ] 6.2. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-shas-guard.test.ts` → expect all cases pass.
- [ ] 6.3. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts` → expect 13 cases pass (no regression to existing heading-sequence test).

## Phase 7: Eleventy build verification

- [ ] 7.1. From REPO ROOT: `npm run docs:build`.
- [ ] 7.2. Confirm: `test -f _site/legal/data-protection-disclosure/index.html && echo "PAGE PRESENT"`.
- [ ] 7.3. Confirm: `grep -F "Art. 15(4)" _site/legal/data-protection-disclosure/index.html | head -1` → expect ≥1 match.
- [ ] 7.4. Confirm: `grep -F "mig 068" _site/legal/data-protection-disclosure/index.html | head -1` → expect ≥1 match.

## Phase 8: Review + ship

- [ ] 8.1. Invoke `/soleur:review` with `legal-compliance-auditor` agent routed in. The agent reads both canonical + mirror DPDs and confirms:
  - Art. 15(4) sub-block is semantically identical between files.
  - Mig 068 cascade narrative is semantically identical between files.
  - No cross-document inconsistency is introduced (DPD ↔ Privacy Policy ↔ GDPR Policy ↔ `knowledge-base/legal/article-30-register.md`).
- [ ] 8.2. Address review findings inline per `rf-review-finding-default-fix-inline`. Re-push.
- [ ] 8.3. Invoke `/soleur:ship`:
  - Set `semver:patch` label (docs-only).
  - Confirm PR body contains `Closes #4447` on its own line, plus `Ref #4417` and `Ref #4351`.
  - Confirm Changelog section is present.
- [ ] 8.4. Mark PR ready; auto-merge per ship Phase 7.
