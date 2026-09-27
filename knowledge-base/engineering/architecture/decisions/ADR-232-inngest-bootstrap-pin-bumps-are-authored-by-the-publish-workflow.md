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
semver-max over `vinngest-v*` merged into `main`, with the identical selector
the AC6 drift guard uses (the `resolve` block of
`bump-inngest-bootstrap-pin.sh`; a fixture-suite equality row pins the two
copies). Since #8782 (2026-09-27), on a full-history checkout, writer and
checker agree on both "latest" and "pinnable": a tag is a candidate only once
its commit is reachable from the checked-out `HEAD`.

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

**2. The target is semver-max `vinngest-v*` merged into `main`, not the
triggering tag.** The script re-runs the AC6 tag-selection pipeline against a
`fetch-tags` checkout of `main`, **considering only tags merged into that
checkout (§7, #8782)**, then cross-checks the signed digest against the crane-resolved digest **only
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

**7. Publish refuses, and the bump never selects, a tag whose commit is not on
`main` (#8747, added 2026-09-24; bump side amended 2026-09-27, #8782).** `vinngest-v1.1.39` was cut on a commit that existed only on
an unmerged PR branch. Its publish built an image from unreviewed bytes, and
its bump PR merged the pin 93 minutes before the source PR did. Every tag from
`v1.1.26` to `v1.1.39` had been cut the same way (16 of 44 tags are off `main`:
those 14 plus `v1.1.14` and `v1.1.24`).

- **The bump excludes off-main tags by construction; that is the
  authoritative check.** The target is the semver-max over
  `git tag --merged HEAD` on the `ref: main` checkout, so a tag cut on an
  unmerged branch is never a candidate (#8782, 2026-09-27). `--merged` fails
  OPEN on a cut-off or unreadable history — rc 0 either way, tags below a
  shallow graft simply vanish, and a missing mid-history object is reported
  only on stderr while the tags above it are still listed — so a shallow
  checkout (or one where git cannot say) and any walk that writes to stderr
  are both refused at `ancestry` BEFORE resolution, and an empty merged set
  (a checkout without tags) is refused at `resolve`. All of this runs before
  `crane`. The
  `ancestry` stage then resolves `refs/tags/vinngest-<target>^{commit}`
  explicitly (never the bare name) and refuses a tag that no longer names the
  commit the build checked out (below). A pin above every merged tag — a
  legacy off-main pin, which `--merged` can never select, or a deleted
  pinned tag — is refused at `resolve` as a downgrade, with a remediation
  that forbids deleting or re-cutting the pinned tag and says to cut a NEW,
  higher version on `main`.
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
  bump never selects it, but it is not inert: see Residuals.
- **`mirror_only` is not refused.** It builds nothing and cannot move a
  digest. Refusing it would permanently strand the legacy off-main versions
  from zot backfill, a rollback path. The bump still judges the target
  however the run started.
- **Ancestry is an accident control, not a secret boundary.** Never admit the
  bump job to a protected environment through a tag-pattern deployment policy
  (the ADR-241 `infra-privileged` plan, #8209). That would run YAML written on
  a branch with Tier-B secrets, loaded before any ancestry step runs. The
  compatible shape is to dispatch the build from `main` (#4326).
- **"Off main" is a point-in-time verdict.** The build judges the triggering
  tag once, at push time; the bump and AC6 re-judge reachability on every run.
  A tag refused as off-main becomes a candidate the moment its commit reaches
  `main` some other way — a merge-commit or rebase merge of its PR (the
  repository allows both) — and then it has no image: AC6 reds `main`, and a
  bump for any older tag defers without self-healing. So an off-main tag must still be
  DELETED, not left in place; exclusion protects the pin, not the tag set.
- **Residuals.** An old `main` commit whose code was later reverted passes
  both checks. So does a tag re-pointed between two on-main commits. A
  hand-authored pin PR to an off-main tag is not covered by the bump; AC6
  reds it unless the PR (or a branch it descends from) carries the tag's own
  commit. `deploy-inngest-image.yml` deploys any published `vX.Y.Z` to the
  live host by tag with no ancestry check (#8780); a gate added there must
  anchor on `refs/remotes/origin/main`, never on `HEAD`, because a dispatch
  from a feature branch would make `--merged HEAD` accept that branch's tags.
- **Version allocation.** A new version must sort above EVERY existing
  `vinngest-v*` tag, off-main ones included, never merely above the merged
  max: an off-main name can never be reused (GHCR may hold its image), and
  #4326's auto-mint must follow the same rule.

**Sequencing.** After this merges, the carrier-changing PR flow is: merge the
PR first, then tag the squash-merge commit on `main` (runbook
`inngest-server.md` §Bootstrap-image release). The bump and AC6 switched to
tags merged into `main` on 2026-09-27 (#8782), after `main` re-anchored on the
on-main `v1.1.40` (`b8817ff1c4`).

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
| Target = semver-max over `git tag --merged HEAD` now (#8747) | **Adopted 2026-09-27 (#8782).** Rejected on 2026-09-24 only because it then resolved to `v1.1.25` (every newer tag was off main), which would have opened a downgrade PR; safe once `main` re-anchored on the on-main `v1.1.40`. |
| Anchor on `git tag --merged origin/main` instead of `HEAD` (#8782) | The writer's `HEAD` already is `main`. In PR CI a tag on the PR's own commit is visible to that PR and to branches descending from it, which is intended (AC6's `#8747:` diagnostic tells the author to delete it; `deploy-script-tests` is advisory). A stale local `origin/main` would mis-select, and one pipeline for writer and checker is simpler. **Re-evaluate when #6766/#6480 makes `deploy-script-tests` required:** a required AC6 would then block stacked PRs on another PR's tag, and the checker should move to `origin/${GITHUB_BASE_REF:-main}`. |
| Refuse an off-main *signed* tag in the bump (#8782) | Breaks the legacy `mirror_only` rollback path (a backfill of an off-main version must still reconcile the pin), and the build job already refuses a non-`mirror_only` off-main tag. Exclusion from the candidate set already keeps it out of the pin. |
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

## Amendment 2026-09-27 (#8782)

The bump target and the AC6 drift guard now take the semver-max over
`vinngest-v*` tags merged into `HEAD`, not over every tag:
`git tag --merged HEAD --list 'vinngest-v*'`. An off-main tag is excluded by
construction rather than refused, so it can no longer turn `main` and every
open PR red, nor block a legitimate bump to the highest on-main tag. §2, §7
and the Context paragraph are rewritten; the 2026-09-24 amendment above is
kept as the dated record of the interim state it describes. Three mechanisms
carry the change:

- History visibility is refused before resolution (§7): a shallow checkout,
  or any stderr from the `--merged` walk; AC6 refuses a shallow checkout too.
- One downgrade refusal replaces the legacy-off-main-pin and deleted-pin
  refusals, and it reads the higher of the two files' pins.
- The crane-failure deferral fires only for a target newer than the signed
  tag and not already pinned; every other registry failure is an error.
- The literal regex-parity rows become an equality check of the two 3-line
  selector blocks, plus rows pinning how the checker consumes its selector.

Merging it moved no pin: `main` already pinned `v1.1.40`, which is both the
merged max and the overall max.

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
  shallow checkout, re-pointed tag and missing `--signed-commit`. #8782
  turns the off-main rows into exclusion rows (the off-main tag never reaches
  `crane`, no branch, pin unchanged) and adds a target below a shallow graft
  (B9b), semver order `v1.10.0` > `v1.9.0` (B20), pre-release and four-part
  names excluded (B21), and the writer/checker selector byte-equality rows. It also
  adds a harness that runs the build job's shipped record and refusal steps
  against fixture repos shaped like an actions/checkout tag checkout, and
  `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` pins the
  refusal's `mirror_only` gating.
- `.github/scripts/test/run-all.sh` — suite registered; Bash-only by
  construction for the required merge-group path.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC6 selects
  the semver-max tag merged into `HEAD` (#8782) with the writer's selector
  byte for byte, and its DRIFT diagnostic distinguishes an off-main tag, a pin
  above every merged tag, and an ordinary missed bump. AC6b and Guard B are
  unchanged; neither PR moved the pins.
- `scripts/regenerate-c4-model.sh` + `plugins/soleur/test/c4-model-freshness.test.sh`
  — the write-back is documented on the `github -> soleurMarketplace`
  App-write edge (self-relations are unrepresentable in the DSL).
