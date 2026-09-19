# ADR-230: The `vinngest-v*` publish workflow authors its own cloud-init pin-bump PRs, authenticated as the `soleur-ai` App — never `GITHUB_TOKEN`, never a direct push to main

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
| sort -V | tail -1`), so the writer and the checker cannot disagree on what
"latest" means.

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
of `main`, then cross-checks the signed digest against the crane-resolved
digest **only when the signed tag equals the semver-max target**. An
older-tag backfill therefore cannot fail the run on a mismatch that is
expected-by-construction, and cannot downgrade the pin.

**3. Authentication is a minted `soleur-ai` App installation token — never
`GITHUB_TOKEN`, never a PAT.** The mint lives in the composite action
`.github/actions/mint-soleur-ai-app-token` (RS256 over `GITHUB_APP_ID` +
`GITHUB_APP_PRIVATE_KEY` from Doppler `soleur/prd_terraform`, POST to
`/app/installations/<id>/access_tokens`, emitted as a masked step output) —
extracted when this job became the fourth copy of the inline recipe, the
threshold the 2026-05-25-app-jwt-inline-mint learning named. The job passes
the token as `GH_TOKEN` to the script. Separately, the job carries
`packages: read` and its own `docker/login-action` GHCR login: the
`soleur-inngest-bootstrap` package is private, `crane digest` reads it, and
the build job's login does not cross job boundaries — without this the bump
fails at digest resolution on every live run. GitHub *writes* still go
through the App token only; `packages: read` is a read scope. The script
refuses to run under `set -x` with `GH_TOKEN` set (the #7797
credential-trace class) before any traced command executes.

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
(`args|resolve|rewrite|push|pr|merge`), and the workflow's `if: failure()`
Slack step notifies. An unresolvable digest splits on the same boundary as
the merge gate: when the signed tag is NOT the semver-max target, the
target's own publish is still in flight and the run defers
(`result=skipped`, a `::notice::`) rather than paging on a self-healing
race; when it IS the target, resolution failure is a `resolve` fatal —
nobody else is coming to fix it. `result=opened|existing|noop|skipped|error`
and `$GITHUB_STEP_SUMMARY` make each run's disposition readable without log
archaeology.

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

## Consequences

- The drift window shrinks from "until a human notices advisory red" to one
  CI run: the same publish that creates the drift opens its fix.
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

## Verification

- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — fixture suite
  over real git repos with PATH-shimmed `crane`/`gh`, covering every Guard
  Contract row: happy path, noop, semver-max-over-older-signed-tag,
  signed/resolved digest mismatch, non-max backfill, partial pin state,
  tag-only refs, human- and bot-tipped branches (linked and unlinked-author
  shapes), existing PR, degraded mirror, merge-arm failure, merge-arm
  withheld on non-max signed tag, stale-PR supersede, human stale-PR
  preservation, malformed args, unresolved digest (fatal on-target,
  deferred off-target).
- `.github/scripts/test/run-all.sh` — suite registered; Bash-only by
  construction for the required merge-group path.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC6/AC6b/
  Guard B unchanged; this PR does not move the pins.
- `scripts/regenerate-c4-model.sh` + `plugins/soleur/test/c4-model-freshness.test.sh`
  — the write-back is documented on the `github -> soleurMarketplace`
  App-write edge (self-relations are unrepresentable in the DSL).
