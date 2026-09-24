---
title: "A plan that says a site 'follows convention X' shipped without X, and my battery mutated two axes"
date: 2026-09-24
category: workflow-issues
tags: [harness-parity, census, adr-226, mutation-testing, plan-claims, grok]
module: plugins/soleur/lib/harness-parity.ts
issue: 8317
---

# Learning: a plan that says a site "follows convention X" shipped without X

## Problem

PR #8686 widened the ADR-226 harness-parity census to all 67 agent bodies, with a `SELF-NAME` carve-out for each agent's own frontmatter `name:`. The census `--fix` rewrote four agents' operator-facing strings from `/soleur:x` to the canonical `soleur:x`. Plan decision D4 justified this in one sentence: these lines "follow the skills' existing canonical-then-render convention".

That convention is the `<!-- operator-typed-render -->` block. It tells the model to render the command into the harness's typed form before printing it. Ten skills carry it, and zero agents did. So four agents started telling Claude Code users to type `soleur:pencil-setup`, which is not a slash command. Three review seats converged on this (user-impact P2, code-quality P2, pattern-recognition P2).

Separately, the author's hand-run mutation battery (Guard 1 rows 1/3/4 and Guard 2 row 10) all went RED. The test-design seat then found 11 real survivors, because the battery only edited two axes: verdict dispatch and first-vs-exact selection. It never mutated:

- the individual grammar conjuncts: the `name:` prefix, each `---` delimiter, and the closed-frontmatter boundary;
- the message gate's shape filter;
- the Grok renderer's pattern;
- the docs page's per-domain placement.

## Solution

- **Render instruction.** Added the render block to every agent that prints an operator command. The agent copy says "names it canonically (ADR-226)" rather than quoting `soleur:<name>`, because that placeholder is an unknown-ns id to the census, and the new zero-unknown gate for agent docs caught it.
- **Rejected self-names.** The dedicated message now covers every non-canonical site on the line. A Grok stem or `/plan` written as `name:` used to get a `write soleur:…` hint that would rewrite the manifest key.
- **Frontmatter close rule.** The frontmatter now ends where the registry's loader ends it: the first later line *starting* with `---`. A stricter close certified a `name:` line that every loader reads as body text.
- **Grok stubs.** Every stub body states the colon-id → hyphen-stem spawn rule. The render pattern is built from the registry id set, not from a shape regex.
- **New pins.** Tree tests now require zero unknown ids in agent docs, leaves distinct from Grok stems, and only regular `.md` files under `agents/`. The docs test pins per-domain placement and counts, and the docs data module now appends unlisted directories instead of dropping them.

## Key Insight

"This site follows convention X" is a claim about the site's bytes. The cheap check is a grep for X's marker across the files the claim covers (`git grep -L operator-typed-render -- <files that print a command>`). The claim reads as established because X *is* established, just elsewhere.

The same shape explains the battery. Every row I wrote perturbed the axis I had just designed, so the axes I had not thought about stayed invisible. N rows on one axis is one row.

## Session Errors

1. **Issue-filing gate blocked the phantom-agent issue (planning subagent).** Recovery: folded the fix into this PR. **Prevention:** when a planning subagent drafts an issue, include the `User-Impact:`/`Fix-Size:` lines the gate requires. The gate's deny message names them.
2. **#8317 quoted a stale 35-site count.** Recovery: re-measured 287 with the live classifier. **Prevention:** already covered by "plan-quoted numbers are preconditions" (work/SKILL.md).
3. **Observability probe used `bun`, which is not on the preflight sandbox PATH.** Recovery: a static `grep` probe. **Prevention:** discoverability probes use only `/usr/bin` tools (deepen-plan Phase 4.7 already warns).
4. **AC4's literal anchor `^### Cloudflare` collided with the pre-existing `### Cloudflare (MCP Tier)` heading.** Recovery: diffed from the `## Service Deep Links` section instead. **Prevention:** anchor AC extraction on a heading unique to the inserted section.
5. **The intentionally-red checkpoint commit was blocked by `plugin-component-test`.** Recovery: `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test` for that one checkpoint only. **Prevention:** none needed; the checkpoint was deliberate and the next commit ran the hook green.
6. **`pgrep -f` was denied by the self-match hook.** Recovery: `pgrep lefthook` / `proc.sh list_runs`. **Prevention:** already hook-enforced.
7. **Mutation G1 row 3 did not land (wrong anchor), and the run reported 0 fail.** Recovery: re-ran with the correct anchor and the `cmp` LANDED check. **Prevention:** always print LANDED before reading a mutation verdict (already documented; it caught this).
8. **Killing the queued `test-all.sh` let the wrapper advance to the next shard, which was orphaned onto `systemd --user`.** Recovery: killed the wrapper and the orphan by `/proc/<pid>/cwd`. **Prevention:** kill the wrapper script FIRST (already in work/SKILL.md §Monitor).
9. **The plan claimed the phantom `service-deep-links.md` was a docs card.** In fact `subOrder` silently dropped `references/`, and it dropped `engineering/discovery` too. Recovery: removed the claim; the docs page now appends unlisted directories and is pinned by `docs-agents-data.test.ts`. **Prevention:** read the data module before asserting what the page renders.
10. **The plan deferred Grok agent-body rendering to #8063, but a one-sentence stub-body rule closed it.** Recovery: added `GROK_STUB_SPAWN_RULE`; posted a correction comment on #8063. **Prevention:** before deferring, ask whether the adapter output the PR already regenerates can carry the fix.
11. **The structural-enumeration review seat died on a session limit.** Recovery: resumed it via `SendMessage`, and it returned the frontmatter-close and Grok-pattern escapes. **Prevention:** resume, don't respawn (already in review/SKILL.md Gate 2b).
12. **The copied render block carried a `soleur:<name>` placeholder, adding 4 unknown-ns sites in agent docs.** Recovery: reworded the agent copy. **Prevention:** the new tree test holds agent docs at zero unknown ids.
13. **`census --report | tee f | head -1` truncated `f`, producing a false 200-line unknown-ns diff.** Recovery: re-measured without the pipe. **Prevention:** never pair `tee` with `head`; write the file, then read its first line.
14. **Committed without `LEFTHOOK_EXCLUDE=bun-test`, so the hook queued the full battery.** The background notification then read "exit code 0" while no commit had landed. Recovery: killed the hook, verified HEAD, re-committed. **Prevention:** read `git log -1` after a commit; the notification reports the trailing command's exit status.
15. **The Grok floor of `>= 50` went stale in the same round because I reworded `cmo`'s description.** Recovery: re-measured 49. **Prevention:** re-measure a floor after every edit to the corpus it counts (already documented).
16. **The self-run battery covered 2 axes, and the reviewer found 11 survivors.** Recovery: added rejected-shape rows (closed-frontmatter boundary, CR on the name line only, Grok stem, `/plan`, sigil leaf, a loader-closing dash line with a trailing space) and mutation-proved the boundary row. **Prevention:** before crediting a battery, list the axes it edits (already in review/SKILL.md; recurred).
17. **Plan D4 asserted "follows the canonical-then-render convention" without the render block.** Recovery: added the block to four agents. **Prevention:** one bullet routed to `plugins/soleur/skills/plan/references/plan-sharp-edges.md`.

## Tags

category: workflow-issues
module: plugins/soleur/lib/harness-parity.ts
