# Tasks — compound: gh run list truncation false ALL SETTLED (#6796)

Plan: `knowledge-base/project/plans/2026-07-23-compound-gh-run-list-truncation-false-settled-plan.md`

DOC-ONLY. Deliverable is exactly ONE learning file. No product code, no tests, no
source changes, no edits to `ship`/`postmerge`.

## Phase 1 — Author the learning file

- [ ] 1.1 Create the learning file under `knowledge-base/project/learnings/`
  (topic: gh-run-list truncation reports a false ALL SETTLED; author picks the
  write-time date in the filename).
- [ ] 1.2 Write YAML frontmatter matching the corpus convention: `module`,
  `date`, `problem_type: logic_error`, `component`, `symptoms` (list),
  `root_cause: wrong_assumption`, `severity`, `tags` (incl. `gh-cli`,
  `pagination`, `completion-detection`, `false-negative`, `monitoring`),
  `issue: 6796`, `synced_to: []`.
- [ ] 1.3 Write the body sections: Problem (broken loop + ~20-default vs 38
  runs), The tell (exactly-20-rows shape), Fix (`--limit 60` + `KNOWN_TOTAL`
  floor guard; floor never equality), Key insight ("nothing left" vs "nothing
  visible"), Cross-references, Sharp edge (review-boundary blindness).
- [ ] 1.4 Cross-references — encode the VERIFIED statement, not the original ask:
  robust pattern = *poll by identity, not by counting a capped source*
  (ship/postmerge poll loops are immune because they poll by run-ID/`headSha`,
  NOT via a floor guard); cite ship Phase 6.5 and the `2026-07-20-terraform-...`
  sibling; flag ship Phase 7 Step 2's completion-count as a latent same-class
  instance worth an operator follow-up (out of scope to fix here).

## Phase 2 — Verify acceptance criteria

- [ ] 2.1 `git diff --name-only origin/main...HEAD` (excluding plans/specs) lists
  only the one learning file.
- [ ] 2.2 Frontmatter parses; contains `issue: 6796` and `synced_to: []`.
- [ ] 2.3 `grep -c '^## '` ≥ 5; Fix section contains both `--limit` and
  `KNOWN_TOTAL`.
- [ ] 2.4 Every cited `knowledge-base/...md` path resolves (broken-link grep
  prints nothing).
- [ ] 2.5 No product/test/ship/postmerge file touched.
