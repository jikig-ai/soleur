# Session State

## Plan Phase

- Plan file: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-billion-dollar-solo-founder-pillar/knowledge-base/project/plans/2026-04-22-feat-billion-dollar-solo-founder-pillar-plan.md`
- Status: complete

### Errors

One course-correction during deepen-plan: a false-positive grep hit (`pillar` as a tag value in one post) was re-verified via anchored `grep -rn "^pillar:"` which correctly returned zero hits — no existing pillar frontmatter in any blog post, confirming the capability gap is real.

### Decisions

- **Capability gap scoped inline.** The `_includes/pillar-series.njk` + `_data/pillars.js` + conditional include in `blog-post.njk` are Phase 1 of this PR (the brainstorm's only open capability gap). No separate PR.
- **FAQPage JSON-LD is hand-written in the markdown body**, not extended into `blog-post.njk` layout — scope-local to keep the shared layout stable. Escape rule documented at the `<\/` in-string level, with literal `</script>` as the real block terminator.
- **Eleventy build command corrected** from `npm run build` to `npm run docs:build` (the `package.json` script actually declares `docs:build` and runs `cd ../../../ && npx @11ty/eleventy`; config lives at repo root).
- **Companion post link-up is belt-and-suspenders**: pillar-series include renders on both posts via frontmatter, plus a hand-written lead-in paragraph in the companion's first 200 words guarantees spec FR6 even if the include regresses.
- **Word-count budget verified self-consistent.** FAQ 1,500 + stack 700 + remaining 1,300-2,300 = 3,500-4,500 (floor sums exactly to 3,500, ceiling to 4,500).
- **Dual-rubric scorecard template absence de-risked.** If template sibling PR hasn't landed by ship time, inline the rubric structure from the 2026-04-21 audit in the scorecard artifact rather than blocking.

### Components Invoked

- skill: soleur:plan
- skill: soleur:deepen-plan
- WebSearch (Medvi facts, Amodei prediction)
- Bash/Read/Grep repo-research
