---
title: Fresh offline recovery-image build proposal
date: 2026-10-09
pr: 9051
status: prepared-for-explicit-authorization-not-executed
---

## Scope and authorization

Maintenance was green at source `70b6d1a4d92a42dad406a8d87899668f105043a5`:
all 25 required checks passed, including the CI and tenant aggregates.
The next recovery build remains held. The historical `27c04a95` one-use
rehearsal authorization is consumed and cannot authorize a new candidate.

A fresh task-owned proposal is prepared in ignored scratch at
`.soleur/current-source-recovery-proposal-20261009/prepare.py`. It is an
execution artifact, not committed reusable tooling. Its immutable full source
SHA and explicit one-build selector must match the reviewed command. It checks
HEAD and tracked build inputs before proceeding. Documentation-only commits
require repinning the proposal; they do not establish a new build result.

The proposed action is one offline application compile and local image build,
followed by filesystem-only mount/hash probes. It starts no Web app or database
and performs no recovery rehearsal, provider/authentication call, image push,
deployment, account/settings change or shared write. All later holds remain.

## Read-only preparation evidence

At the inspected source, the current lockfile SHA-256 is
`b6fb597acc1e8df40ac63390dd3b41e9376b0bd9ce4e1ec9ecd778983818536f`.
Read-only cache hashing verified 1,357 eligible archive entries, with zero
required entries missing and six optional entries unavailable. No archive was
downloaded or copied during the audit. The Node 22.22.1 base image exists
locally at immutable ID
`sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d`.

Tracked compiler-import inspection established the export set: all
`apps/web-platform`, all `plugins/soleur`, and
`scripts/lib/frontmatter-strip/strip.ts`. Generated `next-env.d.ts` is not a
tracked export prerequisite. The preview originally refused tracked `.npmrc`
files. Key-only inspection identified the public `min-release-age` setting;
admission now allows only that numeric setting from pinned source. Other npm
options and tracked environment files remain refused. Private configuration
and credential values are not inspected.

## Proposed controls and limits

The runner consumes an exclusive authorization marker before source export,
scratch staging or container mutation. It uses a fresh candidate directory,
refuses reuse, stops on failure and grants no automatic retry. Compilation uses
network `none`, pull `never`, a read-only container root, dropped capabilities,
no new privileges, a non-root user, two CPUs, 6 GiB memory and a 4 GiB Node heap.
The work deadline is 2,700 seconds, with shorter individual stage bounds and
separately bounded owned-container cleanup. Disk writes include an exported
source/cache/runtime payload and a local image; several GiB may be used.

Builder/runtime installs use locked offline dependencies and `--ignore-scripts`;
runtime omits dev dependencies. Next compilation uses `--webpack`. Local image
assembly creates, copies into and commits an unstarted container, avoiding the
historical raw-image-ID BuildKit registry lookup. Its source label, six runtime
artifacts and full plugin manifest are verified independently in the local
image. Probes run only filesystem/hash checks, never application entrypoints.

This would prepare an application image, not establish production runner
parity. Production npm install scripts, default Next build mode, global
CLI/browser/system dependencies, bwrap capabilities/outer wrapping, infrastructure
readiness, observability and full Supabase historical/auth/storage substrate
remain unqualified. The synthetic rehearsal needs separate authorization after
successful build admission. The remaining acceptance chain remains current-source
and full-production recovery, authenticated screenshots, eligible routine
consumer, permitted mode-specific Web/CLO evidence, then full review/promotion.

No build, image/container mutation, SQL or rehearsal has executed as part of
this proposal. Codex remains default-off, customer content blocked and PR #9051
draft with auto-merge disarmed. Subscription and OpenAI assistant usage are
separate from local compute; Soleur disclaims warranty for runtime cost.
