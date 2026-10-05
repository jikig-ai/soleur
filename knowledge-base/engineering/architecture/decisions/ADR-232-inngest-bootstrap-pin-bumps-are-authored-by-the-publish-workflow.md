# ADR-232: The `vinngest-v*` publish workflow authors its own cloud-init pin-bump PRs, authenticated as the `soleur-infra` App — never `GITHUB_TOKEN` for the PR write, never a direct push to main

> **Title amended 2026-09-30 (#9262):** it read "authenticated as the `soleur-ai` App"; see the
> Amendment dated 2026-09-30 (#9262).

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
group `inngest-pin-bump` with `cancel-in-progress: false` serializes bump runs
and never cancels a running one. With three or more overlapping, GitHub drops
the intermediate PENDING runs, which is harmless because every run reconciles
to the merged max (#8782).

**2. The target is semver-max `vinngest-v*` merged into `main`, not the
triggering tag.** The script re-runs the AC6 tag-selection pipeline against a
`fetch-tags` checkout of `main`, **considering only tags merged into that
checkout (§7, #8782)**, then cross-checks the signed digest against the crane-resolved digest **only
when the signed tag equals the semver-max target**. An
older-tag backfill therefore cannot fail the run on a mismatch that is
expected-by-construction, and cannot downgrade the pin.

**3. Authentication is a minted `soleur-ai` App installation token — never
`GITHUB_TOKEN`, never a PAT.** (Scope, amended 2026-09-28 for #4326: this
governs the bump job's own writes and the publish path of a hand-pushed tag. The
§8 tag write uses the mint job's `GITHUB_TOKEN` on purpose, because its event
suppression keeps the tag's `push: tags` run silent.) The mint lives in the composite action
`.github/actions/mint-soleur-ai-app-token` (since renamed `mint-infra-app-token` and re-sourced in #9262; see the Superseded block below; RS256 over `GITHUB_APP_ID` +
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

> **Superseded 2026-09-30 (#9262), as to §3's heading, identity, source and scope:** **3.
> Authentication is a minted `soleur-infra` App installation token — never `GITHUB_TOKEN`, never a
> PAT.** The bump job declares `environment: infra-privileged` (ADR-241 D2: `main`-only branch
> policy, no reviewers) and mints through `.github/actions/mint-infra-app-token`, the composite
> renamed in #9262. The composite has one identity and one source, neither of them an input: it reads
> `GITHUB_INFRA_APP_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY` from `soleur-infra-privileged/prd`
> (project and config fixed in argv) with the environment secret `DOPPLER_TOKEN_INFRA_PRIVILEGED`.
> **Superseded 2026-10-03 (#9321), as to source and token:** the composite's source is now the
> validated `doppler-project` input (default `soleur-infra-app`, token `DOPPLER_TOKEN_INFRA_APP`); see
> ADR-241 D11 and its 2026-10-03 amendment.
> All four inputs (`doppler-token`, `installation-id`, `permissions`, `repositories`) are required,
> because an unscoped token of this App would carry `administration:write` and `secrets:write`.
> The bump requests installation `166065653`, `{"contents":"write","pull_requests":"write"}`,
> repository `soleur`; the `soleur-ai` mint it replaces was unscoped. The composite keeps the
> exact-grant check (granted permissions must equal the request plus `metadata:read`, and the
> repository selection must equal the request) and no longer refuses the `EVICTED_SEE_ADR_241`
> sentinel, because it never reads `prd_terraform`. Failure and success output: a sanitized
> `.message`; the `app-token` notice (see `action.yml`). **Scope:** this governs the bump job's
> writes and the §8 dispatch. The hand-pushed-tag publish path is gone and the §8 tag write keeps
> `GITHUB_TOKEN`; see the Amendment dated 2026-09-30 (#9262). The `packages: read` GHCR login and
> the `set -x` refusal are unchanged.

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

> **Superseded 2026-09-30 (#9262), as to §4's identity:** the PR is authored by
> `soleur-infra[bot]`, commit identity
> `soleur-infra[bot] <335404629+soleur-infra[bot]@users.noreply.github.com>` (bot user id
> 335404629), switched in place in `bump-inngest-bootstrap-pin.sh`. The two commits-API checks (the
> bot-tip test and the supersede sweep) read the `<slug>[bot]` form and compare against that
> identity. The two `gh pr list` author filters match `app/soleur-infra`, because
> `gh pr list --json author` reports an App author as `app/<slug>`. Before #9262 those filters
> compared against `soleur-ai[bot]`, so the "reuse the open PR" path had never matched in
> production; #9262 fixes that in passing. `soleur-infra[bot]` is on the `cla.yml` allowlist. There
> is no legacy read-side set for `soleur-ai[bot]`: the switch assumes no open `soleur/inngest-pin-*`
> PR or branch at merge time (plan AC5 checks it). A leftover `soleur-ai[bot]`-tipped pin branch is
> treated as human-tipped (`branch-has-manual-commits`, a `::warning::`, job green), and the pin
> drift guard staying red on `main` is what surfaces it.

**5. Auto-merge is armed only when this run's mirror attests the target.**
`gh pr merge --auto --squash` runs only when the signed tag IS the semver-max
target AND the build job reported `mirror_status == ok`. `mirror_status`
attests the *triggered* tag's zot copy — a backfill of an older tag reports
`ok` for the wrong tag, so the arm requires `signed_tag == target` first.
Otherwise the PR gets a hold comment naming the verification needed. The
merge-arm itself is a warning, not a fatal — a PR left open is recoverable,
a failed run that hid the PR is not.

> **Amended 2026-09-30 (#9262):** a `mirror_only` build never arms auto-merge, and disarms one an
> earlier run armed. The workflow passes `--mirror-only "$MIRROR_ONLY"` (bound from
> `inputs.mirror_only`) to the bump. When it is `true`: a **new** PR opens held, with a body line
> and a hold comment saying a `mirror_only` backfill cannot attest provenance; an **existing** PR
> for the target is reused, its branch refreshed, and its body keeps its original text. The script
> reads that PR's `autoMergeRequest`. If an earlier full build armed auto-merge, it runs
> `gh pr merge <n> --disable-auto`; if that fails, or the armed state cannot be read, it dies at
> stage `pr`. It then posts the hold comment on the existing PR too. The build's cosign step signs
> whatever digest the tag names at signing time, and `mirror_only` skips the build's ancestry
> refusal, so a digest pushed to the tag by branch-run YAML could otherwise be signed and
> auto-merged under `main`'s identity. A held `mirror_only` PR is merged by a human after review:
> `gh pr merge <n> --squash`.

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
  runs main's copy of the script. The caveat, for a hand-pushed tag (a tag-ref
  run), is that the job's own *definition* still comes from the tagged commit's
  YAML, so this holds only for branches whose copy of `bump-cloud-init-pin` is
  unmodified. A dispatched build (every auto-minted tag's first publish, §8)
  runs `main`'s copy of the job definition instead. The threat model is
  accident, not a hostile branch.

  > **Superseded 2026-09-30 (#9262):** there is no tag-ref run, and `infra-privileged` refuses the
  > bump job outside `main`, so every bump runs `main`'s job definition and script; see the
  > Amendment dated 2026-09-30 (#9262).
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

  > **Superseded 2026-09-30 (#9262):** a tag push starts nothing, and a branch dispatch runs that
  > branch's build job while its bump job is refused; see the Amendment dated 2026-09-30 (#9262).
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

**8. Auto-mint on `main` (#4326, amended 2026-09-27).** A push to `main` that
changes what the image would contain mints the next tag and publishes it, with
no human step. `.github/workflows/mint-inngest-bootstrap-tag.yml` drives
`.github/scripts/mint-inngest-bootstrap-tag.sh`; the script owns every decision.

- **Decision.** BASE is the semver-max `vinngest-v*` tag merged into `HEAD`,
  chosen by the §2 selector (identical modulo name, dir operand and
  indentation). Mint iff `HEAD`'s image inputs
  differ from BASE's. The inputs are the carriers (the union of both sides'
  `cp` staging lines, each compared by file mode and blob), the four baked pins (`inngest_cli_version`,
  `inngest_cli_sha256`, `vector_version`, `vector_sha256`, read with the build
  step's own patterns) and the Dockerfile heredoc. `HEAD`'s extraction is
  fail-closed: no carriers, a `cp`/`COPY` disagreement, anything but exactly
  one heredoc, or an empty inngest pin is a `decide` fatal, never a `noop`.
  Comparing against a tag, not the push's `before` SHA, is what makes a run
  that was dropped, skipped, or failed BEFORE the tag stage self-heal on the
  next qualifying push. A failure at or after the ref POST does not self-heal:
  the tag may exist, the next run takes it as BASE and decides `noop`, so its
  recovery is the runbook's post-POST row (check the remote, confirm no build
  run exists, dispatch once).
- **Allocation.** One patch above the numeric `X.Y.Z` prefix of EVERY
  `vinngest-v*` name on the remote (`git ls-remote`), suffixed or not (§7
  "Version allocation"). A component longer than 6 digits, or zero-padded, is
  refused. A failed `git ls-remote` is its own fatal (`ls-remote-failed`) in
  every stage that reads the remote, never "no such tag".
- **Tag.** An annotated tag object plus its ref, created over REST with the
  job's `GITHUB_TOKEN`. GitHub starts no workflow from a `GITHUB_TOKEN` event,
  so the tag's `push: tags` trigger stays silent and the image builds exactly
  once. A strict-named tag that already peels to `HEAD` on the remote (a human
  or a concurrent run, annotated or lightweight) ends `noop` and creates
  nothing. Once the ref POST has been attempted, any later fatal still reports
  the name with `tag_state=unknown`, because the ref may exist.

  > **Superseded 2026-09-30 (#9262):** with no tag trigger the image builds exactly once whoever
  > creates the tag; see the Amendment dated 2026-09-30 (#9262).
- **Dispatch.** `build-inngest-bootstrap-image.yml` is dispatched from `main`
  with `inputs.ref=<tag>`, once and never retried: a retry after a lost 2xx
  could start a second build and move the digest. The credential is the
  `soleur-ai` App installation token, scoped to `actions:write` on `soleur`
  through the composite's new `permissions`/`repositories` inputs. It is
  minted BEFORE the tag step, so a credential failure publishes nothing and
  the dispatch is the only step after the tag. The composite refuses a
  response whose granted scope differs from the request, and the script
  revokes the token (`DELETE /installation/token`) right after the POST. This
  is the "dispatch the build from main" shape §7 names as the one compatible
  with #8209.

  > **Superseded 2026-09-30 (#9262):** the credential is the `soleur-infra` App token, minted in
  > the `mint` job on `infra-privileged` (still before the tag step); see the Amendment dated
  > 2026-09-30 (#9262).
- **Failures** are stage-named (`args|ancestry|resolve|decide|allocate|tag|dispatch`)
  and post to Slack. A failed dispatch prints the one agent-runnable recovery,
  `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<tag>`,
  and never suggests deleting the tag, which is now the merged max.
- **Residuals.**
  - **R1:** unconfirmed whether GitHub refuses a tag ref on a commit that
    changes `.github/workflows/*` when the token lacks `workflows`. If it does,
    the run ends `reason=workflows-permission`, creates nothing, and the
    fallback is a hand-tag. Before #8209 that hand-pushed tag builds through
    `push: tags`. After #8209 removes `push: tags`, a hand-pushed tag starts
    nothing, so the post-#8209 fallback is two steps: hand-tag, then confirm
    no build run exists for the tag and dispatch it once,
    `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<tag>`.

    > **Superseded 2026-09-30 (#9262):** the post-#8209 two-step fallback is now the only one;
    > see the Amendment dated 2026-09-30 (#9262).
  - **R6:** a future tag ruleset on `vinngest-v*` needs a bypass for the
    GitHub Actions integration.
  - **R8:** a `vinngest-v*` tag cut on a PR-branch commit is refused by the
    build (off-main, so it has no image). If that commit later reaches `main`
    through a merge-commit or rebase merge, the tag becomes the merged max and
    the mint's BASE, and the mint compares against an image that was never
    built. Recovery: delete that tag per §7, then re-run the mint.
  - **R9:** build-step inputs outside the heredoc are not compared: the pin
    step's own logic, the `env`/`ARG` mapping from pins into the build, the
    `curl` download URL, the `docker build` flags, and the floating base image
    (`FROM alpine:<minor>` resolves to whatever that tag names at build time).
    A change to any of them merges without a mint. The backstop is tracked in
    #9082.
  - **R10:** the dispatch runs `main`'s workflow copy at dispatch time; if
    `main` moves in the seconds between checkout and dispatch, the next
    qualifying push re-decides.
  - **R13:** a dispatched build takes its recipe (the Dockerfile heredoc and
    every step) from `main`'s copy of the build workflow, not from the tag's
    commit. The mint compared the tag commit's recipe, so a recipe change that
    lands on `main` between the mint's checkout and the build's start is built
    under the OLDER tag's name. The window is one run's queue time; the push
    that carried the change mints again, so the newer tag is correct, but the
    older tag's image does not match its commit's recipe.
  - **R12:** two auto-mints in flight can leave a bump PR held (the
    `inngest-pin-bump` group keeps one pending job, so the surviving bump can
    target the newer tag with signed≠target). Recovery is a digest-preserving
    `mirror_only` dispatch of the max tag (runbook recovery table).
    **Amended 2026-09-30 (#9262):** that dispatch leaves the PR held (§5); review it, then
    `gh pr merge <n> --squash`.
- **Depends on strict ancestry (#8798).** A content-equality rule would
  re-admit in-PR tags, and with them a second publish of the same content.
- **Naming constraint (#8781).** A pre-merge candidate build must not use
  names under `refs/tags/vinngest-v*`, or it would enter this allocation.
- **After #8209.** Any human-created tag fires `push: tags`, which runs on
  the tag ref. Once #8209 binds the bump job to a main-only environment, the
  manual fallback is `gh workflow run mint-inngest-bootstrap-tag.yml --ref main`,
  and a hand-tag only for R1, as the two-step hand-tag-then-dispatch above.
  Removing `push: tags` from the build (alternative A5 below) is a
  prerequisite of #8209.

  > **Superseded 2026-09-30 (#9262):** #9262 is the change this bullet anticipated, and the
  > post-#8209 fallbacks it names are now current; see the Amendment dated 2026-09-30 (#9262).
- **Prerequisite before Guard A becomes required (#9081).** After a
  carrier-changing merge, `main`'s Guard A is red until the mint, build and
  bump land, and every PR based on that `main` inherits the red. That drift is
  not the PR's own, so #9081's PR-context exemption does not cover it. Once
  `deploy-script-tests` is a required check, every carrier change would freeze
  merges repo-wide for one publish cycle, and indefinitely if the mint fails.
  #9081 must therefore also add a **pending-publish arm**: a Guard A drift
  passes as `pending-publish` (with a notice) when it is fully explained by a
  publish in flight, meaning a `vinngest-v*` tag above the pin, merged into
  the checked commit, whose carriers equal that commit's (tagged, bump not yet
  merged), or a drift introduced by `main` commits newer than a bounded window
  that the mint has not yet had time to tag. Outside those conditions it stays
  red, so a failed or missed mint is still loud. Guard A must not become
  required before this arm exists.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Tag-triggered sibling workflow (`on: push tags: vinngest-v*`) | Re-derives tag/digest the build job already has; races the image push it must follow |
| Scheduled reconciler cron | Reintroduces a bounded drift window — the class being eliminated — and adds an always-on surface for a publish-cadence event |
| `GITHUB_TOKEN` writes | Token-authored pushes fire no `pull_request` events; the PR would never run required checks and could never merge. **Scoped to the PR write (#4326):** for the §8 tag write the same event suppression is WANTED, because it keeps the tag's `push: tags` run silent. **Superseded 2026-09-30 (#9262)** as to the tag write; see the Amendment dated 2026-09-30 (#9262). The PR-write reason stands. |
| PAT | Personal credential, repo-wide reach, no installation boundary — ruled out by hr-github-app-auth-not-pat |
| Direct push to `main` | Bypasses required review/checks for a credential class (the App token) that exists precisely so writes stay auditable |
| Bump to the triggering tag | Older-tag backfill would silently downgrade the pin; semver-max recompute is the only target the AC6 guard also accepts |
| Auto-merge unconditionally | A degraded zot mirror would merge a pin the dedicated host cannot pull — merging bad state faster is worse than holding a visibly-blocked PR |
| Fail the run when auto-merge can't arm | A green-PR-open state is recoverable; a failed run that swallowed the PR is not |
| Bump PR waits for (or is blocked by) the source PR (#8747) | No machine-readable link from a tag to "its" PR exists, and a wait adds a polling surface. Ancestry decides the same property from git alone. |
| Target = semver-max over `git tag --merged HEAD` now (#8747) | **Adopted 2026-09-27 (#8782).** Rejected on 2026-09-24 only because it then resolved to `v1.1.25` (every newer tag was off main), which would have opened a downgrade PR; safe once `main` re-anchored on the on-main `v1.1.40`. |
| Anchor on `git tag --merged origin/main` instead of `HEAD` (#8782) | The writer's `HEAD` already is `main`. In PR CI a tag on the PR's own commit is visible to that PR and to branches descending from it, which is intended (AC6's `#8747:` diagnostic tells the author to delete it; `deploy-script-tests` is advisory). A stale local `origin/main` would mis-select, and one pipeline for writer and checker is simpler. **Re-evaluate when #6766/#6480 makes `deploy-script-tests` required:** a required AC6 would then block stacked PRs on another PR's tag, and the checker should move to `origin/${GITHUB_BASE_REF:-main}`. That move, together with a Guard A exemption for a PR's own carrier change, is tracked as the named prerequisite #9081 (§8 closes only the `main`-side window). |
| §8: create the tag with the App token and let `push: tags` build it (#4326) | Works, but the run executes on the TAG ref, which #8209's main-only environment would refuse. **Moot since 2026-09-30 (#9262):** no tag starts a build; see the Amendment dated 2026-09-30 (#9262). |
| §8: App-token tag AND a dispatch | The App-created tag fires `push: tags` too, so the tag builds twice and the second build moves the GHCR digest. **Superseded 2026-09-30 (#9262):** the double build cannot happen; see the Amendment dated 2026-09-30 (#9262). |
| §8: `GITHUB_TOKEN` for both the tag and the dispatch | Mechanically sufficient (`workflow_dispatch` is exempt from the suppression). Not adopted because the operator's direction names the App token; recorded as decision challenge DC1 on the PR. The switch is mechanical: drop the App mint and give the job `actions: write`. |
| §8: skip auto-minted tags inside the build's push path by actor, then dispatch | Adds a gate keyed on an undocumented actor format; one more failure surface. |
| §8: remove `push: tags` and dispatch every build (A5) | Changes the manual release flow; belongs with #8209, which must retire tag-ref bump runs anyway. **Adopted 2026-09-30 (#9262):** `workflow_dispatch` is the build's only trigger; see the Amendment dated 2026-09-30 (#9262). |
| §8: detect change by push diff (`before..after`) | Loses events: a replaced pending run, the >3,000-file paths skip, a failed run. Tag-vs-HEAD self-heals any failure before the tag stage. |
| §8: carriers only, not pins or recipe | An `inngest_cli_version` or `alpine` bump would merge and never ship; Guard A sees neither. |
| §8: whole-file diff of `inngest.tf`, `vector.tf` and the build workflow | Every unrelated Terraform or comment edit would mint a release and open a bump PR. |
| §8: runs-list self-heal plus a dispatch retry | The runs list lags a dispatch, so the lookup can itself double-build. Recovery is one printed `gh workflow run` line. |
| §8: roll back the tag when the dispatch fails | After a lost 2xx the build may already hold the tag; deleting it burns a name GHCR may hold (§7). |
| Refuse an off-main *signed* tag in the bump (#8782) | Breaks the legacy `mirror_only` rollback path (a backfill of an off-main version must still reconcile the pin), and the build job already refuses a non-`mirror_only` off-main tag. Exclusion from the candidate set already keeps it out of the pin. |
| Content equality instead of ancestry (#8747) | Tolerates in-PR tagging, but a squash with identical bytes is exactly what reviewers never saw as a commit. Recorded as a decision challenge on the PR. |

## Consequences

- The drift window after a publish shrinks from "until a human notices
  advisory red" to one CI run: the same publish that creates the drift opens
  its fix. **Amended 2026-09-24 (#8747):** for a PR that changes a baked
  carrier, the window now starts when that PR merges and lasts until someone
  tags `main`, because an in-PR tag is refused (§7). `main-health-monitor` may
  file `ci/main-broken` inside it; the signal is truthful. #4326
  (auto-mint on infra push to `main`) closes it. **Amended 2026-09-27
  (#4326):** with §8 the window is one mint + build + bump cycle. A missed
  mint run for a carrier change is still caught, but by Guard A only: AC6
  compares the pin with the newest merged tag, which a missed mint never
  moves, so AC6 stays green. A missed mint for a pin- or recipe-only change is
  caught by neither, and neither is a mint failure when Slack is unset (#9082).
- A second repository-write surface exists for the `soleur-ai` App token
  (the first is the `apply-github-infra` manifest/ruleset write). Both are
  least-scope: contents write to this repo, no `main` bypass, PR-mediated.
  **Corrected 2026-09-27 (#4326):** the sentence above overstates it. The
  installation's grant is not least-scope, and an unscoped token carries all
  of it. Its full grant, read 2026-09-28 with
  `gh api /orgs/jikig-ai/installations --jq '.installations[]|select(.id==122213433)|.permissions'`:
  `actions`, `administration`, `checks`, `contents`, `issues`,
  `organization_projects`, `pages`, `pull_requests` and `secrets` **write**;
  `members`, `metadata`, `packages`, `repository_advisories` and
  `secret_scanning_alerts` **read**; no `workflows`; repository selection
  `all`. §8 adds a third CI write surface that is not PR-mediated: a tag
  created with `GITHUB_TOKEN`, and a build dispatch by the App scoped to
  `actions:write` on `soleur`.
  **Superseded 2026-09-30 (#9262):** neither the pin bump nor the dispatch uses the `soleur-ai`
  App any more; see the Amendment dated 2026-09-30 (#9262).
- **The human tag was a second content review, and §8 removes it (#4326).**
  Ancestry, the revision label and the mirror gate check where a tag sits,
  not what the image contains. After §8, anything merged to `main` that
  changes an image input becomes a published image and an auto-merged pin
  bump with no human step. **Merging to `main` is publishing.** `main`'s
  ruleset carries no approving-review rule: read 2026-09-28, its only rules
  are `deletion`, `non_fast_forward` and `required_status_checks`. So nothing
  requires that anyone reviewed the change. A PR review of a carrier change is
  a convention, not a gate. Anyone who can merge a PR whose required checks
  pass can publish an image and have it pinned.
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
  or any stderr from the `--merged` walk; AC6 refuses both too.
- One downgrade refusal replaces the legacy-off-main-pin and deleted-pin
  refusals, and it reads the higher of the two files' pins.
- The crane-failure deferral fires only for a target newer than the signed
  tag and not already pinned; every other registry failure is an error.
- The literal regex-parity rows become an equality check of the two 3-line
  selector blocks, plus rows pinning how the checker consumes its selector.

Merging it moved no pin: `main` already pinned `v1.1.40`, which is both the
merged max and the overall max.

## Amendment 2026-09-27 (#4326)

Added §8: auto-mint on `main`, the decision, allocation, tag and dispatch
rules, and residuals R1, R6, R8, R9, R10, R12 and R13. Also added: the #8798 and #8781
constraints and the #8209 fallback line; the §8 rows in Alternatives, where the
`GITHUB_TOKEN writes` row is now scoped to the PR write; a correction of the
Consequences least-scope sentence; and the removed-human-review consequence.
The title's "never `GITHUB_TOKEN`" is scoped to the PR write. A 2026-09-28
review pass added: the credentials-before-tag order, `tag_state=unknown` after
the ref POST, the scoped-token check and revoke, residuals R8 and R13, the
widened R9, the post-#8209 R1 fallback, the scopes of §3 and the §7 caveat, the
full App grant, the no-review-rule consequence, and the #9081 pending-publish
prerequisite. The
2026-09-24 Sequencing paragraph in §7 is kept as the dated record: the manual
tag it describes is now the fallback, and the runbook's recovery table says
when to use it. The first post-merge run (this change's own merge) decides
`noop`; the mint arm's live proof is the next carrier-changing merge (plan
AC14, pending until observed).

## Amendment — 2026-09-30 (#9262)

The pin bump and the auto-mint's build dispatch move from the Tier-A `soleur-ai` App mint
(`soleur/prd_terraform`, repo secret `DOPPLER_TOKEN`, no `environment:`) to the Tier-B `soleur-infra`
App on the main-only `infra-privileged` environment, as ADR-241 D5 and the #8209 plan already
directed. Before this change, #8209 step O10 (setting `GITHUB_APP_PRIVATE_KEY` in `prd_terraform` to
`EVICTED_SEE_ADR_241`) would have failed every pin bump and every auto-mint, because the shared
composite refused that sentinel; O10 was held on it. The inline dated markers above point here; this
is the one place the rationale is stated.

- **Identity and source.** Both jobs declare `environment: infra-privileged` (ADR-241 D2: `main`-only
  branch policy, no reviewers) and mint the `soleur-infra` App (installation `166065653`) through
  `.github/actions/mint-infra-app-token`, which reads the App's key from `soleur-infra-privileged/prd`
  with the environment secret `DOPPLER_TOKEN_INFRA_PRIVILEGED`. *(Superseded 2026-10-03, #9321: both
  jobs now hold only `DOPPLER_TOKEN_INFRA_APP` and the composite reads `soleur-infra-app/prd` by default;
  the 2026-09-30 sentence stays as written, ADR-241 D11 and its 2026-10-03 amendment carry the decision,
  and the structural fix the amendment's plan recorded as a deferral is adopted there.)* Each token is
  scoped on `soleur`:
  `{"contents":"write","pull_requests":"write"}` for the bump, `{"actions":"write"}` for the dispatch.
  The `mint` job keeps `if: github.ref == 'refs/heads/main'` as the accident gate; the environment is
  the boundary. Its credential steps still run after `Decide` and before `Create tag`.
- **`push: tags` is removed (A5 adopted).** `infra-privileged` refuses a tag-ref run, and §7 forbids
  a tag-pattern deployment policy, so the build's only trigger is `workflow_dispatch`. A hand-pushed
  tag starts nothing: it is published by one dispatch, after confirming no build run exists for it,
  which makes R1's two-step fallback the only one. The auto-mint and the runbook dispatch from
  `main`. A dispatch from another ref runs that ref's build job (it declares no environment), but
  `infra-privileged` refuses its bump job, so every bump that runs uses `main`'s job definition and
  script.
- **The tag write keeps `GITHUB_TOKEN`.** With no tag trigger its event suppression no longer changes
  what builds, and the App token is scoped to `actions:write`, which cannot write a tag.
- **`mirror_only` never arms auto-merge** and disarms one an earlier run armed (§5).
- **Grant widening.** The `soleur-infra` App's committed manifest
  (`apps/web-platform/infra/github-infra-app-manifest.json`) gains `actions: write` and
  `pull_requests: write` (ADR-241 D5). No API can change a live App's permissions, so the live
  widening is #8209 runbook step **O4c**, which precedes O10. Until O4c is done both jobs fail at the
  mint step, before any tag, push or PR.
- **Evidence (plan AC15, runbook O4c).** The bump path: one `main`-dispatched build whose
  `bump-cloud-init-pin` job concludes `success`
  (`gh run view <id> -R jikig-ai/soleur --json jobs --jq '.jobs[]|select(.name=="bump-cloud-init-pin")|.conclusion'`)
  with the `app-token` notice naming `app=soleur-infra installation=166065653` in its log. The mint
  path: the merge-triggered mint run concludes `success` on the merge SHA
  (`gh run list -R jikig-ai/soleur --workflow mint-inngest-bootstrap-tag.yml --event push --branch main -L1 --json headSha,conclusion`),
  which proves the job is admitted; its token path is proven by the next real auto-mint's notice.

The Status stays Provisional. Every superseded sentence above is kept, with a dated marker next to
it.

Plan: `knowledge-base/project/plans/archive/20261004-100500-2026-09-30-infra-retier-pin-bump-and-automint-to-infra-privileged-plan.md`.

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
- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` (§8, #4326) —
  fixture suite over a real working clone and bare origin, with a `gh` fake
  that replays the REST contracts (a real `git mktag` tag object, 422s derived
  from the origin's state). It pins: the decision rows (first and last
  carrier, each pin, recipe, carrier added and removed, bump-merge `noop`,
  comment-only edits, fail-closed extraction); allocation above off-main,
  suffixed and `v1.10`-vs-`v1.9` tags, including a 7-digit refusal and a
  concurrent human tag; tag and dispatch failures; per-mode credential
  isolation and the xtrace refusal; and parity with the §2 selector, Guard A's
  extractor and the build step's pin patterns. It also pins the mint
  workflow's triggers, job gate, checkout and per-step token binding, and the
  composite's scope-down body and its granted-scope check. Since the
  2026-09-28 review: exact-shape rows for every credential and write step, a
  check that every `steps.X.outputs.Y` names a real step and output, the
  credentials-before-tag order, per-step timeouts below the job cap, the
  `tag_state=unknown` path, `ls-remote` failures in dispatch and verify, the
  post-dispatch revoke, the file-mode compare, and a parity row pinning the
  strict tag regex to the build's "Validate dispatch ref". A temp-copy
  mutation battery covers the comparator, the remote tag source, the version
  sort, the re-read order, the mode compare and the verify `ls-remote` fatal.
  **Pending:** AC14, the first live mint.
  **Amended 2026-09-30 (#9262):** the composite under test is
  `.github/actions/mint-infra-app-token/action.yml`; see its `comp.*` rows and the mint job's exact
  rows in this suite (plan AC2, AC4), and the `soleur-infra[bot]`, `app/soleur-infra` and
  `g1.mirror-only-*` rows in `test-bump-inngest-bootstrap-pin.sh` (plan AC5). **Pending:** plan
  AC15, the first green Tier-B bump (runbook O4c).
- `.github/scripts/test/run-all.sh` — suite registered; Bash-only by
  construction for the required merge-group path.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC6 selects
  the semver-max tag merged into `HEAD` (#8782) with the writer's selector
  (identical modulo name, dir operand and indentation), and its DRIFT diagnostic distinguishes an off-main tag, a pin
  above every merged tag, and an ordinary missed bump. AC6b and Guard B are
  unchanged; neither PR moved the pins.
- `scripts/regenerate-c4-model.sh` + `plugins/soleur/test/c4-model-freshness.test.sh`
  — the write-back is documented on the `github -> soleurMarketplace`
  App-write edge (self-relations are unrepresentable in the DSL).
