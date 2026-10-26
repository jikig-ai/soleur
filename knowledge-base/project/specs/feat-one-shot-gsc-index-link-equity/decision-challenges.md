# Decision Challenges — feat-one-shot-gsc-index-link-equity

Headless one-shot planning run for the GSC "Crawled - currently not indexed"
validation-failure follow-up (#8143/#8144/#5616; trigger email 2026-10-26). This
harness has no Agent/Task tool, so the `soleur:plan-review` panel, the domain
leaders (CMO/CPO/spec-flow), and CTO rulings could not be spawned. Technical
rows carry `pending - assumed: <default>` per the technical-ruling-delegation
contract until the parent pipeline's `soleur:engineering:cto` consult lands.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Which issue gets `Closes` vs a duplicate-of comment: #8143 vs #8144 | technical | pending - assumed: `Closes #8143`, duplicate-comment on #8144 — #8143 is the earlier, richer filing (carries the /glossary/ sharpest-case and the #5616 non-duplicate analysis); #8144 is the scheduled-audit's near-verbatim duplicate of the same finding |
| #5616 (pillar↔cluster mesh) folded into this PR vs documented non-goal | operator (scope) | decided under operator delegation in the task brief ("decide whether ... #5616 belongs in this PR vs documented non-goals"), 2026-10-26: fold in — same root-cause class (link equity), same file set, ~4 small template edits; its compare-page/cluster targets sit in the same weak-equity region; splits cleanly if a reviewer disagrees |
| Learn dropdown carries ten children vs the five sketched in the issues | technical | pending - assumed: ten — #8144's AC is the stricter one ("Each of the ten pages is reachable from the global nav on every page"); five children would leave three pages nav-unreachable and the AC unmet |
| Scoped strengthening for the 5 still-unindexed URLs | technical | pending - assumed: `From the blog` group on the homepage rail links the 3 unindexed blog posts (/blog/soleur-vs-polsia/, /blog/why-most-agentic-tools-plateau/, /blog/ai-agents-for-solo-founders/); the 2 legal pages get nothing extra — they already carry a site-wide footerLegal link, so the marginal lever is spent and their non-indexing is a thin-content call no nav edit fixes |
| `/goal-primitive/` added to the homepage rail (beyond the literal ask) | technical | pending - assumed: include — census found it has zero inbound links anywhere on the site (same failure class as the bucket); one extra rail link in the Guides group |
| UX-gate tier and specialist coverage | technical | pending - assumed: BLOCKING tier stands (mechanical `**/*.njk` override on index.njk/pages edits); soleur:product:design:ux-design-lead's deliverable was produced in-process via the authenticated Pencil CLI (`knowledge-base/product/design/marketing/learn-nav-go-deeper-rail.pen`); soleur:product:spec-flow-analyzer + soleur:product:cpo + CMO consults deferred to a spawn-capable phase — recorded in `## Domain Review`, not silently skipped |
| Brand-survival threshold `aggregate pattern` | taste | assumed: aggregate pattern — a broken nav/rail harms many visitors' first impression cumulatively; no single-user data/workflow/money breach surface |
| `plan-review` reviewer panel not spawned (no Task tool in this harness) — does the plan need a panel before `soleur:work`? | technical | pending - assumed: no blocking panel required pre-work; residual disclosed here and in `## Domain Review`; `soleur:plan-review` may still run at the review stage |
| Blocking AskUserQuestion-style checks skipped (wireframe review pause, brainstorm pick, apply gate) | technical | pending - assumed: all headless arms — the session is a pipeline subagent with no TTY; every interactive gate resolved to its prescribed headless branch |
