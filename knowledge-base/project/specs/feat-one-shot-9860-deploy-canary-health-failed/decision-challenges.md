# Decision challenges - feat-one-shot-9860-deploy-canary-health-failed

Persisted by the headless plan run for `ship` to render (ADR-084). The operator's stated direction is the default; these are the places the plan departs from it, with evidence.

## 1. Brief premise corrected: v0.332.4 / v0.332.5 / v0.333.0 were NOT built after the #9838 fix

- Stated direction: "tags v0.332.4, v0.332.5 and v0.333.0, built after that fix, still fail the same way, so there may be a second cause."
- Evidence: `git rev-parse web-v<ver>^{commit}` gives b7fa93724a, 460ee5813c, d7dee46bb0, none of which contain ceb1c6c1ba (#9838); Better Stack shows the identical `ERR_INVALID_ARG_TYPE` stack for each. The misreading comes from `gh run view` `headSha` on `workflow_run` runs being main HEAD at trigger time.
- Disposition: corrected in the plan (Research Reconciliation, Phase 0.1). A second cause does exist, but it first appears on v0.333.1 (`canary_sandbox_failed`).

## 2. Suggested fix direction differs: dedicated capped bwrap copy (issue #9871) is not adopted in this PR

- Stated direction (relayed from #9871): keep `/usr/bin/bwrap` cap-free, give the outer wrap a dedicated capped copy, pin `agent-outer-wrap.ts` and founder scripts to it.
- Evidence: a local run on the deploy base image (bubblewrap 0.8.0, uid 1001, bounding set carrying the caps) shows the capped copy fails with the same `Unexpected capabilities but not setuid` guard, so the copy does not make the outer wrap work; it would add a SYS_ADMIN carrier that cannot run and a path change across code, scripts, fixture and audit.
- Disposition: the plan keeps the half that unblocks the deploy (cap-free `/usr/bin/bwrap`), drops the file cap entirely (Option O1), and routes the capped-copy / setuid / root-helper candidates to a re-spike issue measured as uid 1001 in the real image. Challengeable: if the operator wants the copy kept for later wiring, it is a small additive change after the unblock.

## 3. Scope: the `--cap-add SYS_ADMIN` removal and the outer-wrap canary skip stay IN this PR (as an independently revertable second commit)

- Earlier in this planning run the CTO and simplicity reviews recommended splitting them out (image-only unblock). Architecture and security review overturned that with evidence: the host `ci-deploy.sh` gained `--cap-add` at 12:11:34Z (apply run 37928426862), after the last passing probe, so an image-only fix deploys "no file cap + SYS_ADMIN bounding", which prod never ran; the grant also activates a `caps:[CAP_SYS_ADMIN]` seccomp include rule; and the unprovisioned outer-wrap canary would page Sentry on every deploy and FAIL a soak tracker that the sweeper reopens.
- Disposition: Commit A (image) unblocks alone; Commit B (host script, cloud-init, constant-gated canary skip, comments) is revertable on its own. Challengeable: if the operator prefers the minimal unblock, drop Commit B and accept the named unverified delta plus the alert noise.
