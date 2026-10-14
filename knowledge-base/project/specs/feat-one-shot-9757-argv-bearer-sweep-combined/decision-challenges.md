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

## Resolution (2026-10-12)

Appended after the work phase; the challenges above are the dated plan-phase record and are not edited.

- **C1 (peel `inngest-bootstrap.sh`): PEELED.** Not because of PR 10073 but on a measurement made while building it: editing `inngest-bootstrap.sh` reddens `GuardA` in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` by design (a baked carrier drifts from the pinned `vinngest-v*` tag) until a new tag is minted and the pin bumped, so the commit cannot be green inside this PR. The finished commit is preserved as `b48247d559` on the local branch `keep/9757-inngest-heartbeat-argv` and is tracked in #10120. #9757 item 2 stays partly open (`Ref`, not `Closes`).
- **C2 (workflow htpasswd step): KEPT, as built.** One line in `apply-web-platform-infra.yml` (`printf '%s' "$RP" | docker run --rm -i httpd:2.4-alpine htpasswd -Bin "$RU"`), proved offline by a refusing stub docker row and the real-binary suite `apps/web-platform/infra/htpasswd-stdin.test.sh` (which also shows that without docker's own `-i` the hash covers an empty password). The step is dispatch-only, so it is first exercised live by the next `registry-luks-recut` dispatch.
- **C3 (leads (b), (g), (d) in this PR): KEPT, as built.** (a), (b) and (g) are in the held-back HMAC commit (mask shape check before every `::add-mask::`, one bounded scrubbed first line instead of four raw body echoes); (d) is the docs and runbooks commit. Measured residual of (g): four raw `echo "$BODY"` sites remain (capture, inventory, 2.0 registry-probe, 2.6 doublefire-probe), outside the four sites the lead named; recorded in the ADR-280 addendum.
- **C4 (archive chore inside this PR): KEPT, as planned.** Done from a throwaway clean worktree of `origin/main` and cherry-picked, so the branch-diff discovery did not archive this PR's own plan.
- **C5 (lead (h), reduced form): KEPT, as built.** The existing opt-in `COMMUNITY_ARGV_DOCKER` row in `community-argv.test.sh` also runs the oracle under the `bash:3.2` image; no new always-on gate. It is evidence, not a gate, because the switch is set nowhere in CI.
- **C6 (registry template B1/B2): STAGED OUT by operator ruling, "separate PR after this one".** Tracked in #10119. The S6 recurrence row carries a three-entry residual allowlist (the three registry-template lines) that the follow-up deletes; it shrinks by deletion only. Merging this PR therefore does not replace the registry host.
- **Deviation recorded in the ADR addendum.** The heartbeat curls carry `--disable --noproxy '*'` because lint Rule D requires it for any curl taking `--config -`; the plan's `-q`-only text is superseded.

## Not-yet-specified candidates (roadmap fog, not issues)

None.
