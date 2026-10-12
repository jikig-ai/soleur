# Decision challenges (plan phase, 2026-10-12)

Headless plan run: these are plan-review findings that argue the operator's stated scope or direction should change. The operator's direction is the default and the plan keeps it; each is persisted here for `ship` to render and for the operator to rule on. None is applied silently.

## C1. Peel `inngest-bootstrap.sh` out of this PR by default

- **Operator direction:** one combined PR including the heartbeat-URL conversion of `inngest-bootstrap.sh`.
- **Reviewer finding (DHH, simplicity):** it is the only slice whose merge is neither a no-op nor a web-1 probe re-delivery (it mints a `vinngest-v*` tag and builds an image through `infra-privileged`), it buys no live change until a host replace, its heredoc is the hardest site to test, and PR 10073 edits the same file.
- **Plan response:** kept in, as the last commit, peelable by `git revert`; the plan recommends peeling it if PR 10073 has not merged when implementation reaches that commit.
- **Cost of each choice:** keep = one tag mint plus a rebase collision with #10073; peel = item 2 of #9757 stays partly open (the umbrella stays `Ref`).
- **Ruling needed from:** operator, at the merge-approval step (or earlier if #10073 merges).

## C2. Cut the workflow htpasswd site (`apply-web-platform-infra.yml` ~2958)

- **Operator direction:** convert the workflow site along with the two cloud-init sites.
- **Reviewer finding (DHH):** the password is a per-run throwaway on an ephemeral runner, already masked; the step is dispatch-only and never exercised by the merge-triggered run; the file is within 26 KB of its size gate and shared with draft PR 7390.
- **Plan response:** kept (the exposure is the docker client's argv, the edit is one line and under 50 bytes, and the plan adds an offline stub-docker row for `-i`).
- **Cost of each choice:** keep = an untested-live path until the next `registry-luks-recut`; cut = a known argv-password site stays documented as a residual and Guard 3's floor drops to 3.
- **Ruling needed from:** operator, optional.

## C3. Move leads (b), (g) and (d) to a separate no-apply PR

- **Operator direction:** "plus review leads (a)-(h) in the issue body where tractable", in the one PR.
- **Reviewer finding (DHH):** (b) mask ordering, (g) body echoes and (d) docs do not put a credential on argv, and each grows the diff in the file that carries the census.
- **Plan response:** kept in (all tractable, none fires an infra apply: `scripts/cutover-inngest.sh` and runbooks are not apply paths), in the commit order's no-apply commits.
- **Cost of each choice:** keep = a larger diff (~38 files); cut = the umbrella #9757 cannot close until the follow-up lands.
- **Ruling needed from:** operator, optional.

## C4. Archive chore (D) as its own PR

- **Operator direction:** D is a chore inside this PR.
- **Reviewer finding (DHH):** the clean-checkout-and-cherry-pick ritual the script requires (branch-diff discovery would otherwise archive this PR's own plan) is more work than the archive and carries no review risk.
- **Plan response:** kept in this PR via the throwaway-worktree procedure.
- **Ruling needed from:** operator, optional.

## C5. Lead (h): fold into the existing opt-in row instead of a new gate

- **Operator direction:** lead (h) of #9757 (no gate runs real bash 3.2).
- **Reviewer finding (simplicity):** measured today, the helper already passes on `bash:3.2.57`; a digest-pinned always-on row is a rot liability.
- **Plan response:** adopted in reduced form: the existing opt-in `COMMUNITY_ARGV_DOCKER` row gains a `bash:3.2` run; no new always-on gate. This narrows the lead's literal ask ("a gate") to an opt-in gate.
- **Ruling needed from:** operator, optional.

## C6. Stage the registry template (B1, B2) as its own PR

- **Operator direction:** one combined PR including the cloud-init-registry.yml htpasswd conversion.
- **Finding (architecture review, verified):** `registry-host-replace-dispatch.yml` has a push trigger on `cloud-init-registry.yml` with no reviewer gate and no confirm token, so merging B1/B2 replaces the production registry host (the sole pull path) unattended, and the converted `htpasswd -Bin` boot block runs for the first time at that boot. The first plan draft (and the CTO assessment) said the edit had no live effect; both were wrong.
- **Plan response:** B1/B2 are the last, single, peel-before-merge commit (with their suites, battery rows and ADR text); the plan recommends shipping them as a separate PR right after this one so the replace can be timed and watched, and retires the first-execution risk offline (boot block rendered from the real YAML and run through `bash -s` on `ubuntu:24.04` + `apache2-utils`, failure arms included).
- **Cost of each choice:** one PR = one merge that also replaces the registry, with an unrelated read-only preflight that can refuse (then a hand re-fire); two PRs = a second review cycle and a second merge notice.
- **Ruling needed from:** operator, before the merge-approval step. This is the decision the brief asked to have surfaced before pushing code.

## Not-yet-specified candidates (roadmap fog, not issues)

None.
