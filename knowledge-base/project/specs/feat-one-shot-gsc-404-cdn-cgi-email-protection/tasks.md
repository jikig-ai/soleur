# Tasks — fix GSC "Not found (404)" `/cdn-cgi/l/email-protection`

Derived from
`knowledge-base/project/plans/2026-07-20-fix-gsc-404-cdn-cgi-email-protection-plan.md`
(post-plan-review). Read the plan's **Sharp Edges** before starting — several encode
traps a draft of this plan already fell into.

**Change set is intentionally 2 files.** If you find yourself editing `validate-seo.sh`,
`apps/web-platform/infra/**`, or adding a `scripts/followthroughs/` probe, stop — all three
were explicitly cut by plan review. See plan §Files to Edit.

---

## Phase 0 — Preconditions

- [ ] 0.1 Confirm branch: `git branch --show-current` →
      `feat-one-shot-gsc-404-cdn-cgi-email-protection`
- [ ] 0.2 Confirm the baseline suite is green before touching anything:
      `bun test plugins/soleur/test/validate-seo.test.ts` → expect **21 pass, 0 fail**.
      (This suite must still be green at the end — AC5.)
- [ ] 0.3 Read `plugins/soleur/docs/robots.txt` (3 lines) and
      `plugins/soleur/test/validate-seo.test.ts` (for the `bun:test` import style to mirror).
      Per `hr-always-read-a-file-before-editing-it`.

## Phase 1 — RED: the gate

- [ ] 1.1 Create `plugins/soleur/test/robots-cdn-cgi.test.ts` using `bun:test`
      (mirror the import line at `plugins/soleur/test/validate-seo.test.ts:1`).
      Resolve `plugins/soleur/docs/robots.txt` relative to the test file, not to CWD.
- [ ] 1.2 Assertion A — anchored, case-insensitive directive:
      `robots.txt` matches `/^\s*disallow:\s*\/cdn-cgi\//im`.
      Anchored per `cq-assert-anchor-not-bare-token`; case-insensitive per RFC 9309.
- [ ] 1.3 Assertion B — no Googlebot-specific stanza:
      `robots.txt` does **not** match `/^\s*user-agent:\s*googlebot/im`.
      *Why:* Googlebot obeys the `*` group only when no Googlebot group exists; without
      this, assertion A could pass while the directive is inert for the one crawler
      this work targets.
- [ ] 1.4 Assertion C — passthrough intact: `eleventy.config.js` contains the
      `robots.txt` passthrough-copy line (currently `eleventy.config.js:69`).
      Match on the content anchor, not the line number (`cq-cite-content-anchor-not-line-number`).
- [ ] 1.5 Record the Cloudflare-Images condition as a **comment in this test file**:
      if image transformations are ever adopted, `Allow: /cdn-cgi/image/` must be added
      above the `Disallow`. **Do not put this note in `robots.txt`** — see plan Sharp Edges
      (it makes any `cdn-cgi/image` grep self-falsifying).
- [ ] 1.6 Confirm RED: `bun test plugins/soleur/test/robots-cdn-cgi.test.ts` → assertion A fails.

## Phase 2 — GREEN: the fix

- [ ] 2.1 Edit `plugins/soleur/docs/robots.txt` to the exact form in plan §Phase 2 step 3:
      `User-agent: *` / `Allow: /` / blank / 2-line vendor-citation comment /
      `Disallow: /cdn-cgi/` / blank / `Sitemap: …`.
      Keep the comment to the two lines specified — no internal repo paths on a public file.
- [ ] 2.2 Confirm GREEN: `bun test plugins/soleur/test/robots-cdn-cgi.test.ts`
- [ ] 2.3 Confirm the gate can FAIL (AC2): temporarily delete the `Disallow` line, re-run
      the test, observe failure, restore the line, re-run, observe pass.
      Do not skip — this is the anti-`7f84318dc` check.
- [ ] 2.4 Build: `npx @11ty/eleventy`
- [ ] 2.5 Verify the artifact (AC3):
      `grep -iE '^\s*disallow:\s*/cdn-cgi/' _site/robots.txt`
- [ ] 2.6 Verify no regression in the existing SEO gate (AC4), exactly as `deploy-docs.yml:75`
      invokes it: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` → exit 0
- [ ] 2.7 Verify the untouched suite is still green (AC5):
      `bun test plugins/soleur/test/` → the 21 `validate-seo` tests still pass

## Phase 3 — Follow-ups the plan defers (do not fold into the diff)

- [ ] 3.1 File a tracking issue for the **CTA fallback rendering defect** (plan §Deferred):
      `getting-started.njk:22` renders `[email protected]` where a copyable address
      belongs; same for `pricing.njk:275`. Include the recommended fix
      (`<!--email_off-->` + `ops at jikigai dot com`) and the explicit warning **not** to
      use bare plaintext. Label `domain/marketing`, `chore`.
- [ ] 3.2 File the **28-day GSC re-check** follow-up issue (AC12), due merge+28d:
      re-check the "Not found (404)" report and confirm all four rows cleared.
      Note in the body that a `scripts/followthroughs/` probe is **not** usable — GSC
      exposes no API for coverage-validation state.
- [ ] 3.3 Optionally file the "Book intro" CTA → booking-link conversion follow-up
      (`decision-challenges.md` §Also noted). Low priority, separate concern.

## Phase 4 — Ship

- [ ] 4.1 Verify AC6: `git diff --name-only origin/main...HEAD` contains **no**
      `apps/web-platform/infra/` paths.
- [ ] 4.2 PR body uses **`Ref #3379`**, not `Closes` (AC7). #3379 is not resolved here.
- [ ] 4.3 Ensure `/ship` surfaces
      `knowledge-base/project/specs/feat-one-shot-gsc-404-cdn-cgi-email-protection/decision-challenges.md`
      into the PR body and files the `action-required` issue (UC-1 Option C, UC-2 CTA fix).
- [ ] 4.4 Post-merge operator steps are AC8–AC12 in the plan. Note AC11 (GSC "Validate Fix")
      is genuinely human-only — GSC has no validation-trigger API. Do not re-litigate
      automating it; the justification is recorded inline in the plan.

---

## Acceptance criteria mapping

| AC | Task |
|---|---|
| AC1 (gate assertions) | 1.2, 1.3, 1.4 |
| AC2 (gate can fail) | 2.3 |
| AC3 (built artifact) | 2.5 |
| AC4 (no validator regression) | 2.6 |
| AC5 (existing suite green) | 0.2, 2.7 |
| AC6 (no infra diff) | 4.1 |
| AC7 (`Ref #3379`) | 4.2 |
| AC8–AC12 (post-merge operator) | 4.4 |
