---
title: The gate built to catch Docker-only build failures never ran in Docker, and nothing it said could block a merge
date: 2026-09-13
category: build-errors
tags:
  - docker
  - next-build
  - build-context
  - turbopack
  - import-meta-url
  - ci-required-checks
  - guard-window
issue: 8076
pr: 8136
broke_in_pr: 8074
related:
  - knowledge-base/project/learnings/2026-07-23-cross-root-import-passes-local-next-build-fails-docker-context.md
  - knowledge-base/project/learnings/2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md
  - knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md
---

# The gate built to catch Docker-only build failures never ran in Docker

## Problem

Post-merge verification of #8074 (`0f649dbfb`) found `Web Platform Release` run
34773058045 red at "Build and push Docker image":

```text
Error: Module not found: Can't resolve '../../../../.claude/hooks/lib/user-surface-taxonomy.txt'
```

Every pre-merge check on that PR was green, including `web-platform-build` — the job
created after the #2347/#2401 outage *specifically* to catch "builds locally, fails in the
Docker image". Production stayed on the prior image (`ef8b987f4`; a later `workflow_run`
release re-deployed it) for ~2.5 hours.

## Root cause — three layers, one shape

1. **The hook joined the bundle.** #8074 made `server/cron-filing-deny-marker.ts` import
   `filingShape` from the cron containment hook `cron-bash-allowlist-hook.mjs`, a
   standalone `node <file>` CLI. The deny-marker is imported by the substrate, which is
   imported by `app/api/inngest/route.ts` — so for the first time Turbopack compiled the
   hook. The #8074 comment justifying the import ("plain ESM with a CLI entry guard, so
   importing it runs nothing") is a claim about *load time*; nobody asked what the
   *bundler* now sees.
2. **`new URL("<rel>", import.meta.url)` is a static asset reference.** Turbopack (and
   webpack) resolve that spelling like an import. The hook used it for its taxonomy path,
   four levels above `apps/web-platform`. A full checkout has the file, so `next build`
   passed in CI; the Docker context is `apps/web-platform`, so it failed there.
3. **The gate that exists for this class could not see it, and could not block anyway.**
   `web-platform-build` ran `npm run build` on a full checkout — structurally blind to a
   build-context difference — and had been *advisory since creation*: never in the CI
   Required ruleset, never in the `test` aggregator's `needs:`. A red run would not have
   stopped auto-merge.

This is the **fourth** instance of the class (#5890, #6860, #7666/release `1edf7a62`,
#8074). The 2026-07-23 learning's stated defense — "guard the boundary mechanically at PR
time" — had been written down and never built.

## Solution

- **Hook:** `resolve(dirname(fileURLToPath(import.meta.url)), …)`, computed lazily inside
  the exit-2 `try` (a module-init throw in a bundle with `import.meta.url` undefined would
  take down `/api/inngest` — every cron — not one hook run). Verified in the **real**
  `docker build --target builder` locally: main's hook rc=1 with the exact error, fixed
  hook rc=0.
- **Gate runs the release's build:** `web-platform-build` now runs
  `docker/build-push-action` `target: builder` from the `apps/web-platform` context, with
  `plugins/soleur` vendored exactly as the release does (release `1edf7a62` failed on a
  vendored `.ts` — a class only a vendored context can see). Measured 1m52s cold in CI vs
  1m53s–2m00s for the full-checkout job it replaced.
- **Gate can block:** it is the 4th leg of the `test` aggregator (`needs` + `env` +
  `entries` — the loop's own documented "one-line edit"), with guard rows R1f (red build
  alone → rc 1, names itself) and R1g (`skipped` build alone → rc 1, the fail-open the
  header forbids), mutation-proven by dropping the 4th entry (29/31 → 31/31).
- **Class guard closed:** `test/docker-context-import-containment.test.ts` (the guard the
  2026-07-23 learning produced) had three gaps that let this exact shape through: `.mjs`
  not walked, `new URL(…, import.meta.url)` not extracted, and a target ABOVE the app root
  never flagged (`.dockerignore` cannot name it, so `isExcludedFromContext()` is
  structurally false). All three closed; mutation: main's hook → the sweep names the file
  and the climb.

## Key insights

- **A gate that runs in a richer environment than the one it certifies is a full-checkout
  lint wearing a build's name.** "Passes on a full checkout" and "passes in the build
  context" are different facts; only the context can answer the second. If the release
  builds a Docker stage, the PR gate must build that stage.
- **"Advisory since creation" is a state a gate can sit in for months without anyone
  noticing, because green-and-advisory looks identical to green-and-required.** Before
  crediting any check as protection, ask: is it in the ruleset or the aggregator's
  `needs:`? (`git log -S <job> -- infra/github/ scripts/required-checks.txt` and the
  aggregator's `needs:` list answer in seconds.)
- **When a file changes WHO compiles it, re-review it as if it were new.** The hook was
  correct as a CLI. Importing it into a bundle changed its reader, and every
  bundler-specific spelling in it became live. Ask "what does the bundle now contain, and
  which of its idioms does the bundler interpret?"
- **A class guard is only as wide as its extractor.** The existing guard covered
  `import … from` in `.ts` files; the incident arrived as `new URL(…)` in an `.mjs` file
  climbing above the root. Enumerate the forms the producer can take (extension × syntax ×
  direction), not the one the last incident used.

## Session errors

1. **The #8074 review (12 seats, 45 findings) never asked what the bundle contained after
   the deny-marker started importing the hook.** A comment about load-time behaviour was
   accepted as if it covered the bundler. — Recovery: this hotfix. — **Prevention:** review
   SKILL.md Sharp Edge (routed): when a diff adds an import edge from bundled code to a
   file that was previously a standalone script/CLI, enumerate that file's
   bundler-interpreted idioms (`new URL(…, import.meta.url)`, `require.resolve`,
   `import.meta.resolve`, `__dirname` climbs) and check each against the build context.
2. **Two unfaithful reproduction instruments before the faithful one.** An rsync copy with
   a symlinked `node_modules` hit a Turbopack "symlink points out of the filesystem root"
   panic; a hardlinked copy compiled but then failed TypeScript on `test/` files the real
   context excludes via `.dockerignore`. Neither could have reproduced the release. —
   Recovery: run the real `docker build --target builder`. — **Prevention:** when the
   failing surface is a Docker stage and Docker is available, build the stage; an
   approximation of a build context is a different context.
3. **I wrote two false causal comments into `ci.yml`.** "Read-only reuse of the release's
   deps layer" (the release exports `mode=min`, runner-stage layers only — zero `CACHED`
   steps on the job's first run) and a timeout justified by a local "~4m warm" figure that
   CI measured at 1m52s cold. Four review seats found the first independently. —
   Recovery: `cache-from` removed, comments rewritten from CI measurements. —
   **Prevention:** for every causal claim a workflow comment adds, cite the run id it was
   measured on; a mechanism inherited from a sibling workflow's config is a claim to run,
   not a fact.
4. **`gh run list --commit <short-sha>` printed nothing, silently.** — Recovery: pass the
   full 40-char SHA (`git rev-parse`). — **Prevention:** treat an empty `gh` listing as
   "wrong query" until a known-positive query on the same shape returns rows.
5. **The post-merge Monitor died mid-watch**: another session's `cleanup-merged` removed
   the #8074 worktree the monitor's shell was `cd`'d into (`Unable to read current working
   directory`). — Recovery: re-armed from the repo root. — **Prevention:** a long-lived
   monitor's cwd must be the repo root or `/var/tmp`, never a worktree that `cleanup-merged`
   can reap once its PR merges.
6. **The security-sentinel seat stalled for 600 s** (stream watchdog) and was resumed with
   one `SendMessage`; it then reported normally. — **Prevention:** none needed beyond the
   review skill's existing resume-don't-respawn rule, which worked.
7. **A hand-maintained count in a user-visible string:** the aggregator's success line
   `"All three shards green."` and the guard test's CONTROL needle both encoded the leg
   count; adding a 4th leg required editing both, and a grep for the old string surfaced
   only historical plans. — **Prevention:** when adding a member to an enumerated set, grep
   for the set's CARDINALITY spelled as a word or number, not only its member names.
8. **Bash-tool cwd persistence bit twice** (`cd apps/web-platform` in one call made the next
   call's repo-root paths fail). — One-off; use absolute paths or `cd` in the same call.
9. **I ran `lint-fixture-content.mjs` over a file outside its own glob** and read its two
   findings on `cron-bash-allowlist-hook.test.ts` as pre-existing debt the pre-commit hook
   would block on; the hook's glob (`lefthook.yml`) never includes that file, and neither
   does CI's `secret-scan.yml` pattern. — One-off; an instrument pointed at a file it does
   not own returns findings that are not findings.

## Recurring-vs-one-off triage

| item | recurring? | disposition |
|---|---|---|
| 1 bundle-membership question missing from review | recurring | route to review SKILL.md (Sharp Edge) |
| 2 unfaithful repro instrument | recurring | this learning's Key insight; no rule (Docker is the instrument) |
| 3 false causal comments in ci.yml | recurring (documented class) | fixed inline; covered by AP-021 / compound Phase 0.5 gate |
| 4 `gh run list --commit` short SHA | one-off | noted |
| 5 monitor cwd in a reapable worktree | recurring | fixed by re-arming from root; noted in ship Sharp Edges (routed) |
| 6 stalled seat | one-off | existing resume rule worked |
| 7 count literal in success line | one-off | fixed inline |
| 8 cwd persistence | one-off | noted |
| 9 lint run out of scope | one-off | noted |
| the advisory gate (never required) | recurring | fixed inline (aggregator leg) |
| class guard gaps (`.mjs`, `new URL`, above-root) | recurring | fixed inline |
