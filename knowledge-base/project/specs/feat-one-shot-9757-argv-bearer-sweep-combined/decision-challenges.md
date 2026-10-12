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

## Not-yet-specified candidates (roadmap fog, not issues)

None.
