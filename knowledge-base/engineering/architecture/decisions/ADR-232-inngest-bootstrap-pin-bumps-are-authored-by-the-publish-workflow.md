# ADR-232: The `vinngest-v*` publish workflow authors its own cloud-init pin-bump PRs, authenticated as the `soleur-ai` App — never `GITHUB_TOKEN`, never a direct push to main

- **Date:** 2026-09-19

## Status

Provisional.

## Context

`deploy-script-tests` repeatedly went red after a newer `vinngest-v*` tag was
published, because the four `soleur-inngest-bootstrap` image pins in
`apps/web-platform/infra/cloud-init.yml` and `cloud-init-inngest.yml` lagged
the publish until a human noticed the advisory failure and bumped them by
hand (#8071; the v1.1.31 → v1.1.35 chore, later re-armed at v1.1.37). The
drift window was "until someone reads a red non-required check" — the check
is advisory by design, so the loop has no forcing function and every bump is
a manual re-derivation of tag, digest, and branch hygiene.

Issue #8359 asks for the recurring-class fix: when
`build-inngest-bootstrap-image.yml` publishes a tag and image, it should open
the pin-bump PR itself, with no operator action.

Four properties make the obvious implementations wrong:

**The trigger tag is not the target.** The workflow also fires on re-publish
of an older tag (backfill). Bumping to the *triggering* tag would let an old
re-publish silently downgrade the pin. The target must be recomputed as
semver-max over `vinngest-v*` — the identical pipeline the AC6 drift guard
uses (`git tag --list 'vinngest-v*' | sed | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'
| sort -V | tail -1`). Writer and checker compute "latest" the same way. Since
§7 (#8747) they can still disagree on whether to *pin* it: when the semver-max
tag is off main, the writer refuses it while the checker keeps demanding it,
until #8782 moves both onto tags merged into main.

**`GITHUB_TOKEN` cannot author the PR.** GitHub does not fire `pull_request`
(or `push`) events for commits authored by `GITHUB_TOKEN`, so a bot PR opened
under it would never run the required checks and could never merge — the
workflow would produce permanently stalled PRs, a strictly worse failure than
today's advisory redness. A personal access token is ruled out by the
repository's standing GitHub-App-not-PAT rule (hr-github-app-auth-not-pat):
a PAT is a personal credential with repo-wide reach, unaudited against the
installation boundary.

**The dedicated Inngest host pulls from zot, not GHCR.** The publish job
dual-pushes the image to GHCR (authoritative) and to the deny-all-public zot
host over the CF tunnel. If the zot mirror leg fails, merging a pin bump
points fresh provisioning at a reference the host cannot resolve. Auto-merge
is therefore conditional on the same run's mirror outcome, and a degraded
mirror leaves the PR open with a hold comment rather than silently merging a
bad pin.

**The pin surface is four sites in two files.** Each file carries a GHCR
reference (`IREF`) and a zot reference (`ZIREF`) with distinct variable
prefixes (`$ZURL`, `$ZOT_EP`). A partial rewrite — three of four sites, or a
tag-only reference — is the exact defect the bump exists to close, so the
script asserts exactly two substitutions per file and converges all four to
one compound `tag@sha256:` reference, idempotently.

## Decision

**1. The publish workflow owns the bump, in a `needs: build` job — no
scheduled reconciler.** `bump-cloud-init-pin` runs in
`build-inngest-bootstrap-image.yml` itself, consuming the build job's
`tag`/`digest`/`mirror_status` outputs. `needs: build` makes "image published"
the precondition rather than a race; a sibling tag-triggered workflow would
re-derive what the build already knows, and a cron reconciler would
reintroduce a bounded drift window — the class being eliminated. Concurrency
group `inngest-pin-bump` with `cancel-in-progress: false` serializes backfill
runs without dropping them.

**2. The target is semver-max `vinngest-v*`, not the triggering tag.** The
script re-runs the AC6 tag-selection pipeline against a `fetch-tags` checkout
of `main`, **refuses a target whose commit is not an ancestor of `main` (§7)**,
then cross-checks the signed digest against the crane-resolved digest **only
when the signed tag equals the semver-max target**. An
older-tag backfill therefore cannot fail the run on a mismatch that is
expected-by-construction, and cannot downgrade the pin.

**3. Authentication is a minted `soleur-ai` App installation token — never
`GITHUB_TOKEN`, never a PAT.** The mint lives in the composite action
`.github/actions/mint-soleur-ai-app-token` (RS256 over `GITHUB_APP_ID` +
`GITHUB_APP_PRIVATE_KEY` from Doppler `soleur/prd_terraform`, POST to
`/app/installations/<id>/access_tokens`, emitted as a masked step output) —
extracted when this job would have become the fourth copy of the inline
recipe — past the three-consumer threshold the
2026-05-25-app-jwt-inline-mint learning named (the third copy had landed
earlier without extraction; the three remaining inline sites stay as-is).
The job passes
the token as `GH_TOKEN` to the script. Separately, the job carries
`packages: read` and its own `docker/login-action` GHCR login: the
`soleur-inngest-bootstrap` package is private, `crane digest` reads it, and
the build job's login does not cross job boundaries — without this the bump
fails at digest resolution on every live run. GitHub *writes* still go
through the App token only; `packages: read` is a read scope. The script
refuses to run under `set -x` with `GH_TOKEN` set (the #7797
credential-trace class) before any traced command executes, and unsets
`GIT_TRACE*`/`GIT_CURL_VERBOSE` — git's own trace channels echo the
credential-bearing push URL the same way xtrace would.

**4. The bump is a PR authored by `soleur-ai[bot]`, never a direct push to
main.** Branch `soleur/inngest-pin-vX.Y.Z`, commit identity
`soleur-ai[bot] <273333864+soleur-ai[bot]@users.noreply.github.com>`, pushed
over the `x-access-token` remote. The PR body carries tag, digest, publishing
run URL, and `Ref #8359`. A human-authored tip on the bot branch is never
force-pushed (`branch-has-manual-commits`); a bot-authored tip may be
lease-updated. Stale `soleur/inngest-pin-*` PRs for *other* targets are
superseded (comment + close) only when their tips are bot-authored — the
script never closes a human-tipped PR. An existing PR for the target is
reused, not duplicated.

**5. Auto-merge is armed only when this run's mirror attests the target.**
`gh pr merge --auto --squash` runs only when the signed tag IS the semver-max
target AND the build job reported `mirror_status == ok`. `mirror_status`
attests the *triggered* tag's zot copy — a backfill of an older tag reports
`ok` for the wrong tag, so the arm requires `signed_tag == target` first.
Otherwise the PR gets a hold comment naming the verification needed. The
merge-arm itself is a warning, not a fatal — a PR left open is recoverable,
a failed run that hid the PR is not.

**6. Idempotent and fail-closed.** All four pins already at target+digest →
`result=noop`, no branch, no commit, no PR. Malformed arguments or a
non-converging rewrite → a stage-named fatal
(`args|resolve|ancestry|rewrite|push|pr`; merge-arm failures are `::warning` by
design, per §5), and the workflow's `if: failure()`
Slack step notifies. An unresolvable digest splits on the same boundary as
the merge gate: when the signed tag is NOT the semver-max target, the
target's own publish is probably still in flight and the run defers
(`result=skipped`, a `::warning::` that names the dead-publish remediation —
a tag outlives a failed build, so if that publish died before pushing its
image the deferral does not self-heal and the AC6 drift guard stays red);
when it IS the target, resolution failure is a `resolve` fatal —
nobody else is coming to fix it. `result=opened|existing|noop|skipped|error`
and `$GITHUB_STEP_SUMMARY` make each run's disposition readable without log
archaeology.

**7. Publish and bump both refuse a tag whose commit is not on `main` (#8747,
added 2026-09-24).** `vinngest-v1.1.39` was cut on a commit that existed only on
an unmerged PR branch. Its publish built an image from unreviewed bytes, and
its bump PR merged the pin 93 minutes before the source PR did. Every tag from
`v1.1.26` to `v1.1.39` had been cut the same way (16 of 44 tags are off `main`:
those 14 plus `v1.1.14` and `v1.1.24`).

- **The bump's `ancestry` stage is the authoritative check.** It runs before
  `crane`, resolves `refs/tags/vinngest-<target>^{commit}` explicitly (never
  the bare name), and refuses when: the checkout is shallow (or git cannot
  say), the tag does not resolve to a commit, the target is not an ancestor
  of the `main` checkout, `merge-base` exits other than 0/1, or the tag no
  longer names the commit the build checked out (below). When the off-main
  target is the tag `main` pins today, the refusal says so and forbids
  deleting or re-cutting it; otherwise it tells the operator to delete the tag
  and cut a NEW version on `main`, never a re-used name. A pin above every
  remaining tag (a deleted pinned tag) is refused at `resolve` as a downgrade.
  It is authoritative because the bump job checks out `main` and
  runs main's copy of the script. The caveat is that the job's own
  *definition* still comes from the tagged commit's YAML, so this holds only
  for branches whose copy of `bump-cloud-init-pin` is unmodified. The threat
  model is accident, not a hostile branch.
- **The bump is bound to the built commit.** The build job records the commit
  it checked out (`outputs.commit`), and the bump requires it as
  `--signed-commit`. When the signed tag is the target, the tag must still
  name that commit. Without this, a tag re-pointed while its first run was in
  flight would pin the first build's digest, because the signed and resolved
  digests would agree. A workflow copy that predates this change passes no
  `--signed-commit` and fails closed at `args`.
- **The pinned digest is bound to its build commit.** The build stamps
  `org.opencontainers.image.revision=<checked-out commit>` into the image
  config (so the digest covers it), and the bump reads it back with
  `crane config` and requires it to equal the target's commit. This is the
  only link between a digest and a commit on the `mirror_only` path, which
  builds nothing: without it, an image built from an off-main commit under a
  tag later re-pointed onto `main` would pass ancestry, the binding and the
  digest cross-check. An image with no label (every image before this change)
  is pinned only with auto-merge withheld.
- **The build job's inline refusal is defence-in-depth.** It judges `HEAD`
  against `refs/remotes/origin/main` (`fetch-depth: 0`) before
  `Build + verify + push`, so an off-main image is never built at all. The
  dispatch checkout is the fully qualified `refs/tags/<ref>`. A tag push runs
  the tagged commit's YAML (a dispatch runs the copy on the ref it was
  dispatched from), so a branch forked before this change carries no refusal.
  That branch can still build an image. It is not auto-pinned, because the
  bump refuses it, but it is not inert: see Residuals.
- **`mirror_only` is not refused.** It builds nothing and cannot move a
  digest. Refusing it would permanently strand the legacy off-main versions
  from zot backfill, a rollback path. The bump still judges the target
  however the run started.
- **Ancestry is an accident control, not a secret boundary.** Never admit the
  bump job to a protected environment through a tag-pattern deployment policy
  (the ADR-241 `infra-privileged` plan, #8209). That would run YAML written on
  a branch with Tier-B secrets, loaded before any ancestry step runs. The
  compatible shape is to dispatch the build from `main` (#4326).
- **Residuals.** An old `main` commit whose code was later reverted passes
  both checks. So does a tag re-pointed between two on-main commits. A
  hand-authored pin PR to an off-main tag is not covered by either check, and
  neither is `deploy-inngest-image.yml`, which deploys any published
  `vX.Y.Z` to the live host by tag with no ancestry check (#8780).

**Sequencing.** After this merges, the carrier-changing PR flow is: merge the
PR first, then tag the squash-merge commit on `main` (runbook
`inngest-server.md` §Bootstrap-image release). The target stays "semver-max over
all tags" until #8782 switches the bump and AC6 to tags merged into `main`.
That switch is safe only after the first on-main re-tag (`v1.1.40`).

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Tag-triggered sibling workflow (`on: push tags: vinngest-v*`) | Re-derives tag/digest the build job already has; races the image push it must follow |
| Scheduled reconciler cron | Reintroduces a bounded drift window — the class being eliminated — and adds an always-on surface for a publish-cadence event |
| `GITHUB_TOKEN` writes | Token-authored pushes fire no `pull_request` events; the PR would never run required checks and could never merge |
| PAT | Personal credential, repo-wide reach, no installation boundary — ruled out by hr-github-app-auth-not-pat |
| Direct push to `main` | Bypasses required review/checks for a credential class (the App token) that exists precisely so writes stay auditable |
| Bump to the triggering tag | Older-tag backfill would silently downgrade the pin; semver-max recompute is the only target the AC6 guard also accepts |
| Auto-merge unconditionally | A degraded zot mirror would merge a pin the dedicated host cannot pull — merging bad state faster is worse than holding a visibly-blocked PR |
| Fail the run when auto-merge can't arm | A green-PR-open state is recoverable; a failed run that swallowed the PR is not |
| Bump PR waits for (or is blocked by) the source PR (#8747) | No machine-readable link from a tag to "its" PR exists, and a wait adds a polling surface. Ancestry decides the same property from git alone. |
| Target = semver-max over `git tag --merged HEAD` now (#8747) | Resolves to `v1.1.25` today (every newer tag is off main), which would open a downgrade PR. Sequenced as #8782, after the `v1.1.40` re-tag. |
| Content equality instead of ancestry (#8747) | Tolerates in-PR tagging, but a squash with identical bytes is exactly what reviewers never saw as a commit. Recorded as a decision challenge on the PR. |

## Consequences

- The drift window after a publish shrinks from "until a human notices
  advisory red" to one CI run: the same publish that creates the drift opens
  its fix. **Amended 2026-09-24 (#8747):** for a PR that changes a baked
  carrier, the window now starts when that PR merges and lasts until someone
  tags `main`, because an in-PR tag is refused (§7). `main-health-monitor` may
  file `ci/main-broken` inside it; the signal is truthful. #4326
  (auto-mint on infra push to `main`) closes it.
- A second repository-write surface exists for the `soleur-ai` App token
  (the first is the `apply-github-infra` manifest/ruleset write). Both are
  least-scope: contents write to this repo, no `main` bypass, PR-mediated.
- Human edits on a bot branch are preserved, not clobbered — the operator
  keeps a takeover path that the automation respects.
- The old failure mode (advisory check red until noticed) remains as the
  *fallback*: if the job itself fails, AC6 redness is still the signal, now
  with a Slack notification on the publish workflow.
- End-to-end proof is deferred by construction: workflows cannot be
  dispatch-tested from a feature branch, so the first post-merge
  `vinngest-v*` publish is the live verification (AC14 in the plan).

## Amendment 2026-09-24 (#8747)

Added §7 and the `ancestry` stage (§2, §6). Until #8782 lands, an off-main
semver-max tag leaves `main` stuck in a loud, deliberate state: AC6 demands
that tag's pin, and the bump refuses to author it. When that tag is NOT the
one `main` pins, the refusal prints the delete command and deleting it clears
both. When it IS the pinned tag (the state right after this change merged:
`main` pins off-main `v1.1.39`), deleting it would break the live pin, so the
refusal forbids that and the way out is cutting a new, higher version on
`main` (the `v1.1.40` re-anchor).

## Verification

- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — fixture suite
  over real git repos with PATH-shimmed `crane`/`gh`, covering every Guard
  Contract row: happy path, noop, semver-max-over-older-signed-tag,
  signed/resolved digest mismatch, non-max backfill, partial pin state,
  tag-only refs, human- and bot-tipped branches (linked and unlinked-author
  shapes), existing PR, degraded mirror, merge-arm failure, merge-arm
  withheld on non-max signed tag, stale-PR supersede, human stale-PR
  preservation, malformed args, unresolved digest (fatal on-target,
  deferred off-target). §7 (#8747) adds rows over real git ancestry
  (plus the legacy-pin, downgrade and image-provenance cases):
  unmerged-branch tag, squash-merged content, off-main semver-max above an
  on-main signed tag, older off-main tag, true merge commit, tag on an older
  main commit, undecidable walk, missing tag commit, bare-name shadow,
  shallow checkout, re-pointed tag and missing `--signed-commit`. It also
  adds a harness that runs the build job's shipped record and refusal steps
  against fixture repos shaped like an actions/checkout tag checkout, and
  `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` pins the
  refusal's `mirror_only` gating.
- `.github/scripts/test/run-all.sh` — suite registered; Bash-only by
  construction for the required merge-group path.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC6/AC6b/
  Guard B unchanged; this PR does not move the pins.
- `scripts/regenerate-c4-model.sh` + `plugins/soleur/test/c4-model-freshness.test.sh`
  — the write-back is documented on the `github -> soleurMarketplace`
  App-write edge (self-relations are unrepresentable in the DSL).
