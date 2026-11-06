---
title: "Decision challenges — feat-one-shot-11362-arc-synthesis"
branch: feat-one-shot-11362-arc-synthesis
plan: knowledge-base/project/plans/2026-10-28-content-testsuite-arc-synthesis-plan.md
issue: 11362
---

# Decision Challenges

Recorded during the planning phase of the one-shot pipeline. Technical and
taste rows were ruled by a single batched `soleur:engineering:cto` spawn in
Rule mode on 2026-10-28 (evidence-checked against the repository).

| Item | Class | Ruling |
|------|-------|--------|
| Exact publish date inside the brief's Nov 19–26 window | operator (schedule) | 2026-11-19 proposed — first open Thursday slot after the Nov 17 committed item; AC12 keeps filename, frontmatter, redirect key and publish_date coherent if the operator moves the slot at review |
| Distribution hold mechanism for the window | technical | Ruled by CTO agent, 2026-10-28: `status: parked` + `publish_date: 2026-11-19` + notify-only probe `scripts/followthroughs/parked-green-synthesis-11362.sh` - verified `isReadyDraft` requires `status === "draft"` and excludes parked (`content-promotion.ts:181-187`), so `draft` would promote ~Oct 29 while parked stays inert yet its `publish_date` still reserves Nov 19 via `occupied` (`cron-content-publisher.ts:292`); probe exit vocabulary matches the sweeper contract (`sweep-followthroughs.sh:4-10`) and the plan states the exit-2-until-`published` semantic explicitly |
| Post title — issue headline #4 vs the brief's marked-lead #1 | taste | Ruled by CTO agent, 2026-10-28: "First We Made 'Green' Mean Something. Then We Made It Fast." - the issue title and proposed pipeline row already carry it and it is the only candidate encoding the honesty-before-speed arc thesis; headline #1 ("A Skipped Test Counted as a Pass…") is retained in the Draft Spec as the writer's re-angle option |
| LinkedIn Personal T+4–7d stagger vs single publish_date per file | technical | Ruled by CTO agent, 2026-10-28: all four channels publish on the window date, one file - the contract carries one `publish_date` per file (`content-promotion.ts:37-43`) and the #10902 hub shipped `linkedin-personal` same-day on a single date; a separate scheduled LinkedIn-only file would work mechanically but splits one post's distribution across two calendar rows without corpus precedent |
| Closing technical link target | taste | Ruled by CTO agent, 2026-10-28: `https://github.com/jikig-ai/soleur/issues/10971` - the public epic's close comment enumerates all twelve children and PRs, the only single URL proving "twelve merges, zero broken mains"; matches the recorded HN convention of submitting the technical write-up |
| OG image generator — PIL vs gemini-imagegen | technical | Ruled by CTO agent, 2026-10-28: deterministic PIL, 1200×630, `#1a1a1a` + gold geometry, textless - canonical per `learnings/best-practices/2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md` and the shipped #10939 sibling card; no reusable PIL generator script exists, so the work phase writes the generator inline and pattern-matches the shipped PNGs in `plugins/soleur/docs/images/blog/`; gemini-imagegen stays unavailable (#10940 OPEN) |
