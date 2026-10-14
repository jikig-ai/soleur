<!-- Inspired by mattpocock/skills/skills/productivity/writing-for-agents/SKILL.md, mattpocock/skills/skills/productivity/writing-for-agents/SKILL-MECHANICS.md and mattpocock/skills/.agents/invocation.md (MIT, Copyright (c) 2026 Matt Pocock). -->
# Authoring Levers

Four levers decide whether an agent runs a skill the same way twice. Reach for this file when
drafting or reviewing a `SKILL.md`, a reference, an agent file, or an always-loaded rule. The
running example is a synthetic skill, `my-deploy-skill`, that ships a container to a server.

## Leading words

A leading word is one short token for a concept the model already learned in pretraining. Used
consistently, it carries a whole behaviour in a single word, so the prose around it can shrink.

Soleur already runs on a few. `red` in `reproduce-bug` turns "a check you trust" into a binary state:
the command either goes red on this bug or it does not. `drain` in `drain-prs` and
`drain-labeled-backlog` says "empty the queue, item by item, until nothing is left" without a
paragraph of explanation.

How to use the lever:

- Look for a phrase that recurs, or a sentence that circles one idea. Replace it with a single
  word the model already knows, then use that word every time.
- Prefer an existing word to a coined one. A coined word brings no prior meaning, so you pay for its
  definition in tokens.
- Put the word in both places it works: the body (so each step pulls the same behaviour) and the
  description (so the prompt that should fire the skill shares its vocabulary).

For `my-deploy-skill`, "verify the new container answers health checks, and roll back if it does
not" becomes one word used at every step: the deploy is **green** or it is rolled back.

**Negation.** A prohibition names the behaviour it forbids, and naming it puts that behaviour in
front of the model. Pair every prohibition with the positive target, and lead with the target:
"write the health-check result to the PR body" beats "do not skip the health check". Keep a bare
prohibition only as a hard guardrail with no positive form, and even then state what to do instead.
This lever comes from the model vendors' prompting guidance, not from a Soleur measurement.
Soleur's attempt to measure it on its own always-loaded rules (B5, #8290) was inconclusive with
limited instrument validity. ADR-236 records it and #8497 tracks a rerun. Apply the lever to new
text; do not rewrite existing rules for phrasing alone.

## The two loads (context vs cognitive)

Each pointer you add is paid from one of two budgets.

- **Context load** is what the model carries on every turn: each skill description, each line of
  an always-loaded rule. It costs tokens and attention whether or not the skill fires.
- **Cognitive load** is what a human carries: knowing a thing exists and when to reach for it. It is
  the right cost where human judgement should gate the action, and the wrong one anywhere else.

A skill with no path to it from the model rides entirely on the human remembering it.

### The invocation choice

Ask one question of every skill: **could the model usefully reach for this on its own, or must
another skill reach it?** If either is true, the skill stays model-invocable. If only a human ever
fires it, mark it user-invoked and stop paying context load for it.

`disable-model-invocation: true` removes the description from the model's always-loaded skill
listing. Measured on Claude Code 2.1.278:

- the description is absent from the listing;
- the Skill tool refuses with a `tool_use_error` that tells the model to ask the user to type
  `/plugin:skill`;
- the user's slash command still runs, both headless and in the interactive TUI.

ADR-236 holds the rest and is the single source for it: the three necessary conditions (K1-K3,
where K3 means the model can still reach the capability another way, or it is deliberately
operator-only), each harness's behaviour (the flag is inert on Codex and Grok), the headless-refusal
policy (stop and file an `action-required` issue naming the command; never re-run the skill's steps
by hand), and the sites that move together when a skill is flipped.

"Operator tooling" and "only a human should fire it" are different properties. A skill that an
always-loaded rule lists as the agent's own tool, a skill plans prescribe as an agent step, or a
read-only audit the agent must pull itself before acting, stays model-invocable however
operator-flavoured it looks. `my-deploy-skill` would qualify for the flag only if no other skill's
steps call it and no founder reaches it from the web.

## Co-location (vs duplication, single source of truth)

Co-location is about placement inside one file: a concept's definition, its rules, and its caveats
sit under one heading. Reading any part of it brings the rest along. Scattering the same concept
across three sections makes the model assemble it, and it will sometimes assemble it wrong.

Duplication is a different failure: one meaning written in two places. The copies drift, both cost
tokens, and the repetition inflates the concept's apparent importance. Give every meaning exactly
one authoritative home, a single source of truth, and point at it. For `my-deploy-skill`, the
rollback rule lives once, under `## Rollback`, and the deploy steps link to that section instead
of restating it.

The repository itself is also authoritative. A command's `--help`, a `package.json` script, or the
directory layout answers a lookup better than a copy in prose, which goes stale silently. Write
down what the agent cannot discover by looking: the convention nobody encoded, the reason behind a
choice, the trap the config hides.

Structure follows the same rule. Markdown headings structure a skill body; XML tags are optional
semantic wrappers inside a section and never replace headings (see `skill-structure.md`).

## Criterion demand (clarity AND demand)

Every step ends on a completion criterion, and a criterion has two independent properties.

- **Clarity**: is the finished state unambiguous to the agent? "The deploy looks healthy" invites
  stopping early. "`curl -fsS $HOST/health` returned 200 three times, 10 seconds apart" does not.
- **Demand**: how much the criterion asks for. "Report the deploy status" asks for a sentence.
  "Every service in the compose file answered its health check, and each result is in the PR body"
  forces the agent to enumerate the services, check each one, and write the results.

A clear criterion that demands little still produces thin work, and a demanding one that is vague
still ends early. Write criteria that are both: checkable by a command or a count, and exhaustive
over the set the step covers. When a fuzzy criterion keeps ending a step early, sharpen the
criterion first; moving the later steps out of view helps only across a real context boundary, such
as a subagent dispatch or a hand-off.
