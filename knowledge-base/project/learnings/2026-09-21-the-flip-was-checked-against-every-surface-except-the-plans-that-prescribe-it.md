---
title: The flip was checked against every surface except the plans that prescribe it
date: 2026-09-21
category: workflow-patterns
tags: [invocation-axis, disable-model-invocation, eval-harness, pre-registration, review, dry-run]
module: plugins/soleur
issue: 8290
pr: 8484
---

# Learning: The flip was checked against every surface except the plans that prescribe it

## Problem

#8290 moved operator-only skills to `disable-model-invocation: true`, which removes their descriptions
from the model's listing and makes the Skill tool refuse them. The K1 criterion ("no model-read surface
directs the agent to invoke it") was checked by Guard 1 over skills, agents, rules, hooks, workflows
and runbooks. It passed for 12 skills.

Two review seats then found, independently, that plans routinely prescribe `soleur:flag-create` and
`soleur:flag-set-role` as agent acceptance steps, and that `wg-plan-prescribed-skills-must-run-inline`
requires `soleur:work` to run them inline. After the flip, the agent would still hand-wire
`RUNTIME_FLAGS` so its feature compiled. The Flagsmith and Doppler halves would never exist, a
silently-off flag, and the operator's own `/soleur:flag-create` would then exit 1 because the name was
already in `server.ts`. Plans were outside the scan by design (they are artifacts, not instructions),
yet they are exactly the text a later session executes.

The same PR's B5 eval showed the measurement-side twin: a pre-registered `ANTHROPIC_MAX_TOKENS=300`
made every Opus 5 and Sonnet 5 answer empty, because both think by default. The lexical scorer read
empty as compliant, so two of three models would have been scored on nothing.

## Solution

- **The flip set was cut to 8 by a CTO ruling.** flag-create, flag-set-role, cron-list and cron-delete
  stay model-invocable and are pinned with reasons (`MUST_STAY_INVOCABLE`). ADR-236 now tells the next
  author to grep `knowledge-base/project/plans/` before flipping.
- **Guard 1 was hardened.** It refuses any non-boolean key value (Claude Code honours
  `yes`/`on`/`1`/`"true"`; the guard read `=== true`). It pins the line count of each acked site,
  asserts go.md names every flipped skill, and scans the CLAUDE.md/AGENTS.md files. Eight mutations
  were all caught, against a green control.
- **B5 was smoke-tested before spend.** A 9-call run at 300 tokens showed `finish=length` with 0
  characters; at 3000 the full grid ran. The verdict stayed the pre-registered INCONCLUSIVE, qualified
  "instrument validity limited" after review found scorer false positives. The instrument was not
  re-run with a changed scorer.
- **A constrained dry run of the rewritten go.md prose** found six sentences an agent could not follow
  that nine review seats had passed (for example, "stay model-invocable" read as routing although no
  routing row exists).

## Key Insight

A check over "surfaces the model reads" is incomplete if it omits the artifacts the model is told to
**execute**. Plans are data until a later session runs them, and then they are instructions. Before
removing a capability from the model, grep the plans for it: every hit is a pipeline the removal
breaks. The same shape recurred on the measurement side, where a parameter chosen for one model family
quietly zeroed the output of another. Smoke the real grid at its smallest size and read the outputs,
not the scores.

## Session Errors

1. **The keyring was misdiagnosed as locked last session.** The file is in a plaintext keyring format gnome-keyring rejects ("invalid or unrecognized format"). Recovery: read the daemon's journal. **Prevention:** when a secret-service consumer fails, read `journalctl --user` for the daemon before assuming a lock.
2. **The systemd-managed keyring daemon was replaced by an ad-hoc `--replace` instance.** Recovery: killed it and ran `systemctl --user start gnome-keyring-daemon`. **Prevention:** restart user daemons through systemd, never with `--replace` from a tool shell.
3. **`DOPPLER_TOKEN` was ignored while Doppler's saved config pointed at the keyring.** Recovery: pass an empty `--config-dir`. **Prevention:** pair `DOPPLER_TOKEN` with an empty `--config-dir` whenever the default config is broken.
4. **A Doppler CLI token passed as `--token` was printed by a `ps` check.** Recovery: switched to the environment variable; the operator was told to revoke and reissue. **Prevention:** never put a credential in argv, and never print full argv (`ps -o args`) of a credentialed process.
5. **The shared Anthropic key (CI and production) was out of credit.** Recovery: operator top-up. **Prevention:** separate keys with spend limits, tracked in #8505.
6. **The pre-registered 300-token cap emptied thinking-model answers, which scored compliant by omission.** Recovery: a 9-call smoke test before the paid run; cap raised to 3000. **Prevention:** eval-harness README "Per-run cost" now requires the smoke test.
7. **The spend estimate was 39% low** (12k assumed, 16.7k measured per call). **Prevention:** estimate from a measured prompt size (same README note).
8. **Guard 1 and K1 excluded plans,** so the flip broke agent pipelines. Recovery: the 8-skill set. **Prevention:** ADR-236 "Adding a user-invoked skill" now requires grepping plans.
9. **The B5 scorer had false positives, the verdict never gated truncation, and the battery's hash-lock tied CI to live rule bodies.** Recovery: archived, with a disclosed qualifier. **Prevention:** #8497 requires a validated scorer before any rerun.
10. **Guard 1 read the key as `=== true` while Claude Code reads it loosely.** Recovery: non-boolean values now fail. **Prevention:** match a guard's parse to the consumer's parse; the structural-enumeration seat found it by reading the binary's parser.
11. **skill-structure.md shipped an unmeasured "measured basis" (102/102, 4).** Recovery: measured 101/102 and 23. **Prevention:** a figure labelled "measured" needs its command run at write time.
12. **authoring-levers.md claimed the B5 verdict "governs" rule phrasing,** an overclaim of an INCONCLUSIVE result. Recovery: CTO-drafted wording. **Prevention:** re-read every sentence that cites a verdict once the verdict is known.
13. **`git checkout HEAD -- <files>` reverted an uncommitted fix** while redoing a conversion. Recovery: reapplied inside the redo script. **Prevention:** commit a verified fix before any restore touching the same files.
14. **A regex dropping blank lines before closing fences broke ambiguous nested fences.** Recovery: restore and redo with only the safe collapse, lint-checked. **Prevention:** lint immediately after any scripted markdown rewrite.
15. **Six unfollowable go.md sentences passed nine review seats.** Recovery: the constrained dry run. **Prevention:** already a `soleur:qa` note (dry-run rewritten skill prose); it held.
16. **The plan cited a deleted control** (`detection:` naming `rule-phrasing-verdict.cjs`) while `lint-guard-contract` was green. Recovery: an append-only plan amendment. **Prevention:** already a `soleur:qa` note (ls every named control); it held.
17. **The provisioning order listed in go.md contradicted the runbook it pointed at.** Recovery: re-ordered after reading the runbook. **Prevention:** when prose points at a source, copy the order from the source.
18. **The first Monitor grepped a progress line promptfoo never prints when not writing to a terminal.** Recovery: count rows in `~/.promptfoo/promptfoo.db`. **Prevention:** same README note.
19. **`doppler secrets names` is not a subcommand.** Recovery: `secrets --only-names`. **Prevention:** `<tool> <sub> --help` before first use.
20. **The first push was rejected non-fast-forward** (the draft-PR init commit). Recovery: confirmed one remote commit, then `--force-with-lease=<branch>:<sha>`. **Prevention:** already documented in one-shot Step 0c.
21. **Forwarded: a bare `/soleur:<name>` in plugin skill prose is red under the ADR-226 census.** **Prevention:** canonical `soleur:<name>` plus "the operator types" in plugin prose.
22. **Forwarded: lefthook's `bun-test` hook runs `scripts/test-all.sh`.** **Prevention:** commit with `LEFTHOOK_EXCLUDE=bun-test` under the operator constraint.
23. **Forwarded: a stream-json parser crashed after its raw capture was deleted.** **Prevention:** keep raw captures until the condensed evidence is verified.

## Tags

category: workflow-patterns
module: plugins/soleur
