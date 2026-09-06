---
title: "A learning, two working copies, and it still got re-derived wrong — the third one lost data"
date: 2026-09-04
category: workflow-issues
module: plugins/soleur/test
problem_type: test_failure
component: lefthook
symptoms:
  - "an ordinary git commit produced a foreign commit and my own commit never landed"
  - "a fixture's git add -A / git commit executed against the caller's branch"
  - "a case asserting 'this directory is not a repository' passed while proving nothing"
root_cause: environment_leak
severity: high
tags: [lefthook, git, environment-variables, test-isolation, worktree, knowledge-propagation, vacuous-test]
synced_to: [work]
---

# A learning, two working copies, and it still got re-derived wrong

## Problem

During PR5 of the ADR-194 cutover, an ordinary `git commit` on my feature branch
produced `dc681358e change` — a foreign commit sitting on a chain of
`base`/`change` fixture commits. My review commit never landed. Eight-plus
stacked fixture commits were on the branch.

The writer was `plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts`,
running under lefthook's pre-commit, spawning `git add -A` and `git commit` with
a raw `{...process.env}`.

## Root cause

`cwd` does not win over `GIT_DIR`. Git resolves the repository from `GIT_DIR` /
`GIT_WORK_TREE` / `GIT_INDEX_FILE` and only then falls back to discovery from the
working directory. **`git -C <dir>` does not save you either** — `-C` changes
directory, and `GIT_DIR` still overrides the result. Every git hook exports those
variables, and this repo's lefthook pre-commit runs the test suites.

Proven by controlled experiment in both directions, from one temp repo:

```
no GIT_DIR   ->  git commit --allow-empty -m base   lands in the fixture repo
GIT_DIR set  ->  the IDENTICAL call MOVED THE CALLER'S BRANCH TIP
```

Recovery was `git reset --mixed` to the last good SHA. The work survived in the
working tree. **It would not have survived `--hard`.**

## The part worth keeping

This mechanism was already documented. `workflow-issues/2026-04-03-lefthook-git-
env-var-leak-breaks-tests.md` (#1454) describes it in full, five months earlier,
in the same directory. Its Prevention section is explicit:

> Use allowlist-by-exclusion (`!key.startsWith("GIT_")`) rather than hardcoding
> specific variable names — this is robust against future git env vars.

There were also two working implementations in the tree, in `welcome-hook.test.ts`
and `gdpr-gate-repo-scan.test.ts`.

A learning plus two correct copies still did not prevent a third file from
getting it wrong. **And my first fix was itself the wrong derivation** — I
hardcoded six GIT_* names, which is precisely what the April learning said not to
do. `GIT_CEILING_DIRECTORIES`, `GIT_NAMESPACE` and
`GIT_ALTERNATE_OBJECT_DIRECTORIES` all sit outside a six-name list and git honours
every one. I only read the prior learning because compound's related-docs step put
it in front of me — after I had already committed the inferior fix and filed the
issue.

The generalizable claim: **a helper that must be re-derived per file will
eventually be re-derived wrongly, and prose does not stop that.** Neither copy was
importable, so neither could propagate. The durable unit is the import, not the
fix and not the write-up. Where the class is mechanical, only an import or a lint
holds; documentation is what you write *in addition*.

## The second harm is quieter than the data loss

The file's last case runs the gate in a deliberately **non-git** directory, to
prove `git diff` fails for want of a repository. With `GIT_DIR` inherited that
directory **is** a repository, `git diff` succeeds, and the case proves nothing
while staying green.

A test asserting an absence, run in an environment that supplies the thing, does
not fail — it silently changes subject. Any fixture asserting "no repo here" has
the same inversion. Note the recursion: the vacated case's own subject was a
silent swallow.

## Why every normal signal missed it

Standalone `bun test` has no `GIT_DIR`, so the fixture is well-behaved **exactly
where anyone would look for the bug**. It misbehaves only under a hook. Same shape
as [the host discriminator built from an absence](./2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md):
the condition that breaks it is absent by construction from the environment
everyone tests in.

## Solution

`plugins/soleur/test/lib/git-clean-env.ts` — one shared helper, **prefix
exclusion**, carrying both incidents and the reasoning in its header. Adopted by
all three suites; the gdpr suite keeps its own `CI` / `ALLOW_PATHS` deletions and
delegates only the `GIT_*` work.

```typescript
export function gitCleanEnv(
  overrides: Record<string, string> = {},
): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (!k.startsWith("GIT_") && v !== undefined) env[k] = v;
  }
  for (const [k, v] of Object.entries(overrides)) env[k] = v;
  return env;
}
```

Verified 39/39 across all three suites with `GIT_DIR` deliberately set to the real
gitdir, 39/39 without, and the branch tip unmoved under both.

**Still open (#7822):** 10+ `*.test.sh` suites run `git commit|add|init` with no
scrub, several of them `.claude/hooks/*` suites — the ones most likely to run
*from* a hook. The lint matters more after this incident, not less, and should
also fail a hardcoded GIT_* name list, since that is the form that would have
caught my own fix.

## Prevention

- Import the shared helper; never re-derive it. Strip by **prefix**, never by name list.
- A fixture that spawns git must be run once with `GIT_DIR` deliberately set, asserting the caller's branch tip does not move. That is the assertion that would have caught this.
- Before fixing a class, grep the learnings for it. The prior write-up existed and I did not read it until after committing.
- When a defect recurs despite documentation, the finding is the propagation failure, not the defect.

## Session Errors

1. **A coarse grep passed off as a sweep.** Filter A (spawns git *anywhere* AND spreads `process.env` *anywhere*) returned 8 candidates; all three I opened were false positives — they mock at the module boundary and never spawn a child, so the git verbs were strings handed to a mock. Filter B (spawns a child AND hands it `process.env` AND invokes git) returned 1. **Recovery:** opened candidates before publishing the count; the real population turned out to be shell suites, not TS. **Prevention:** a candidate list is not a finding list — open enough to estimate the false-positive rate before you publish, and state which filter produced the number.

2. **Read `rc` after a pipe.** The harness `bash -c` has no `pipefail`, so `cmd | tail` reported rc=0 over a lint that exited 1. **Recovery:** capture to a file, read `$?`, then grep. **Prevention:** never read `$?` through a pipe; `hr-when-a-command-exits-non-zero-or-prints` assumes you can *see* the non-zero exit, and a pipe hides it.

3. **Ran a registered command in a variant form.** `lint-window-closure-assertion.py` without `--allowlist` produced 6 phantom FAILs; the literal registered form returned rc=0. Repeated later in the same session with `npx tsc`, which silently installed the deprecated `tsc@2.0.4` shim and returned a meaningless rc=0. **Recovery:** re-ran the registered form; used `bun test` where no tsconfig covers the directory. **Prevention:** run a registered command byte-for-byte as registered before believing a failure, and confirm a tool is the tool you think it is before believing a success.

4. **3 of 5 mutants survived the first battery.** No landing assertions; the cited anchor occurred TWICE in the file (a decoy), so a whole-file grep still passed after the real heading was renamed; and an `ssl` check was an OR whose limb matched a grep command I had myself written into the runbook. **Recovery:** hardened to heading-position + exactly-one + single-limb; 11/11 caught with a green control. **Prevention:** an instrument that can match its own documentation is not measuring the artifact.

5. **Broke a cited content anchor twice.** First cited a heading the same commit deleted; then repaired it by citing a heading renamed two edits later. **Recovery:** pinned mechanically in `pr5-anchor-integrity.test.sh`. **Prevention:** `cq-cite-content-anchor-not-line-number` says cite content but not that the anchor must survive *your own* diff — assert the anchor's position and count in the same commit that cites it.

6. **A derivation filtered a job name that does not exist.** `deploy-docs.yml` has one job (`deploy`); "Cloudflare Pages" is a *step*. The runbook's `PF_SHA` jq returned empty on every run, telling the operator "do NOT proceed" under a T+20 clock. **Recovery:** read the step; added a fail-loud rename assertion. **Prevention:** a derivation that can return empty must distinguish empty-because-absent from empty-because-mismatched, especially when empty reads as a stop signal.

7. **Filled `/tmp` to 0 MB** with sandbox copies including `node_modules` (1.9G + 985M). **Recovery:** removed only my own session-scoped paths, freed 2.9G, moved sandboxes to `/var/tmp` with minimal file sets. **Prevention:** never copy a repo wholesale into a sandbox; copy the file set under test.

8. **Worktree reaped twice** by a sibling `cleanup-merged` — a branch with zero commits ahead reads as merged. **Recovery:** recreated via `worktree-manager.sh` with the session-lease env vars. **Prevention:** create worktrees through the manager so the lease is set from the start.

9. **Three hooks ran with guards disarmed.** Five `hook_self_fault` rows this session across `background-poll-prefer-monitor`, `kb-domain-allowlist-guard` and `no-memory-write` — the last enforces a standing constraint of this session. **Recovery:** none available after the fact; recorded on #7275 with the root cause narrowed — `lib/hook-input.sh` splits out `jq_rc == 3` but collapses rc 5 (malformed document) with rc 0 (**empty stdin**) into one `unparseable` label. **Prevention:** split the two reasons; they have opposite owners, and the conflation is exactly why #7275 cannot say why it fires.

10. **A literal collided with my own comments three times.** `github-pages` appeared in explanatory prose I had just written, against an absence assertion I had also just written. One-off carelessness; the guard now pins it. **Prevention:** your own prose is inside the grep's search space.

11. **`cd` to the repo root twice**, changing the primary working directory. Recovered both times. One-off.

## Related

- [Lefthook GIT_* env var leak breaks tests](./workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md) — **the same mechanism, five months earlier.** The write-up this incident proves was not enough on its own.
- [I built a host discriminator out of an absence](./2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md) — absent-by-construction in the environment everyone tests in.
- [#7822](https://github.com/jikig-ai/soleur/issues/7822) — the remaining shell-suite population and the lint.
- [#7275](https://github.com/jikig-ai/soleur/issues/7275) — hooks running with guards disarmed.
- #7553 / #7652 — the sibling routes to the same damage (fixture `cd` fails; `git -C` operand empty). This is the third route: the cwd was correct and the *environment* pointed elsewhere.
