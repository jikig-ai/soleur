# Decision challenges: feat-one-shot-8548-blog-undecided-vs-forgotten

These decisions were settled during headless planning (`soleur:plan`, 2026-09-25) where a specialist recommended something else, or where the handoff left the call to the founder. They are recorded under ADR-084 so the founder can see them outside this session. `ship` renders this file into the PR body.

---

## DC-1: No founder-facing section on the blog index in this PR

**Classification:** Taste (CMO recommendation not taken)

**Decision:** the post is tagged `ai-agents`, which places it under the index's existing "What is Company-as-a-Service?" section beside the two other founder posts. `plugins/soleur/docs/pages/blog.njk` is not edited.

**The CMO recommended** a new "Founder Playbooks" section, keyed on a `founder-playbook` tag, with a matching category pill and an exclusion in the Engineering Deep Dives filter. The reasoning was that every new post now follows the founder brief, so this is the section that will grow. It also said that tagging the post `case-study` or `ai-agents` mislabels it.

**Why the plan did not take it:**

- The property the handoff asked for is that the post does not land in "Engineering Deep Dives". The existing routing tag already delivers that.
- Editing any `*.njk` page triggers the plan's UI-surface gate, which requires a wireframe review.
- The handoff calls the index change "a separate call".

**What a founder-facing section would also fix:** a pre-existing mis-bucketing. `blog.njk` matches tags case-sensitively and routes only `CaaS`, `ai-agents`, `comparison` and `case-study`. Founder posts tagged `company-as-a-service` but not `CaaS` land in "Engineering Deep Dives". The founder playbook `2026-05-14-how-to-run-every-department-with-ai-agents.md` is one of them.

**If the founder wants the section:**

- the change is one blog-index page, about 22 lines;
- remove the `ai-agents` tag from this post in the same change, because there it does layout work, not content work.

---

## DC-2: The `ai-agents` tag chip is visible on a founder post

**Classification:** Taste (copywriter recommendation not taken)

**Decision:** keep `ai-agents` among the post's tags.

**The copywriter recommended** dropping it. Tags render as visible chips, and "agents" is jargon for this reader.

**Why it stays:** it is the only plain-words tag that routes the post out of "Engineering Deep Dives" without editing the index page (see DC-1). The brand guide's glossary defines "agents" for general readers, and the two sibling founder posts carry the same chip. If DC-1 is taken, this tag goes too.

---

## DC-3: Founder review of the draft before it publishes

**Classification:** User-Challenge (the handoff reserved this call for the founder)

**Context:** the 2026-09-25 handoff on #8548 said to "run the jargon scan on the draft before asking for founder review" and "the final call on the angle is yours". The previous draft was rejected at exactly that review. Merging this PR publishes the post. The next day at 14:00 UTC, the scheduled X, Discord, Bluesky and LinkedIn posts go out. Those social posts cannot be taken back.

**What the pipeline does by default:** the one-shot run was started with an explicit brief that fixed the angle, opening line, CTA and channels, so planning proceeds on that brief. Before the draft is final it passes three checks:

- the jargon scan;
- the fact-checker;
- a copywriter voice pass.

**Recommendation:** hold the merge until the founder has read the rendered draft on the PR, because the social posts are irreversible. If the founder is satisfied with the brief-level approval, merge as normal.

The plan-review panel split on this:

- the CMO and CTO argued the review should be a condition of merging, not just a recommendation;
- the code-simplicity reviewer argued the merge click already is that review.

The founder has a day between the merge and the social posts. Setting the distribution file to `status: draft` in that window stops the thread.

---

## DC-4: "just" in the operator-specified opening line

**Classification:** User-Challenge (the brand guide and the operator's own words conflict)

**Decision:** the opening keeps the founder's words verbatim: "I lose track of what I decided and what I just forgot."

**The CMO flagged** that `brand-guide.md` `### Do's and Don'ts` bans "just" because it "minimizes the ambition". It proposed "I lose track of what I decided and what I forgot."

**Why the words stay:** the brief specified this sentence as the founder's own words, and the operator's direction is the default under ADR-084. The alternative is one word shorter. If the founder prefers it, the change touches this sentence alone.

---

## DC-5: Keep the dated filename and its Terraform redirect row

**Classification:** Taste (a code-simplicity reviewer's cut not taken)

**Decision:** the post uses the dated filename `<YYYY-MM-DD>-parked-vs-forgotten-ideas.md`. It also adds its `seo-bulk-redirects.tf` row, which is applied automatically on merge.

**The code-simplicity reviewer recommended** an undated filename. Six older posts are undated, and Guard 1 checks only date-prefixed files. An undated filename would make this a content-only PR with no production edge change.

**Why the plan did not take it:**

- The handoff lists the redirect row as a deliverable of this PR.
- content-writer's default path is dated, and every recent post is dated.
- The dated URL was never live, because the permalink strips the date. The row exists only for the convention and the Guard 1 parity check. It is additive and reverts by deleting the row.
