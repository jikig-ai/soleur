# Resume prompt — ship #7095 PR-A, then #7103, then #7104

Paste the block below into a fresh session. It is self-contained: it assumes no memory of the
prior session and carries the constraints that are easy to get wrong.

**Order is deliberate.** PR-A restores production; #7103 hardens; #7104 fixes a defect in the
apply-verify gate. Do not start #7103 or #7104 until prod is confirmed deploying again — the
whole point of the PR-A/PR-B split is that the PR which can take the remediation channel offline
stays minimal.

---

```
Ship the #7095 production-outage fix, then work its two follow-ups in order.

## Step 1 — ship PR-A (do this first, and finish it before touching anything else)

cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-7095-host-pull-leg

Branch `feat-one-shot-7095-host-pull-leg`, draft PR #7097, 28 commits. Read
`knowledge-base/project/specs/feat-one-shot-7095-host-pull-leg/session-state.md` first — it has
the full root-cause evidence, every review finding and its disposition, and the reasoning behind
each deferral. The plan is
`knowledge-base/project/plans/2026-07-30-fix-web-host-doppler-token-revocation-broke-host-pull-leg-plan.md`.

State at handoff: three review rounds complete, all findings closed and mutation-proven. Gates
green on a clean tree — `scripts/test-all.sh` 239/239, `apps/web-platform/infra/run-registered-suites.sh`
87/87 (run it SOLO; under concurrent load `ci-deploy.test.sh` reds on contention, which was
confirmed, not assumed), `terraform fmt`/`validate` 0.

Run `/soleur:ship`. Do NOT hand-roll the merge.

Constraints that matter here:

- **Re-run BOTH exit gates before marking ready.** `test-all.sh` does NOT cover
  `apps/web-platform/infra/` and says so in its own preamble. Read the rc FILE, never the
  background-task notification's exit code — that reports the trailing command, and it lied
  twice in the prior session.
- **YOU poll merge → release → deploy.** Never ask the operator to watch CI. Claude: Monitor
  tool. This is a P1 outage fix; the deploy is the deliverable, not the merge.
- **The post-mortem stays `status: ongoing`.**
  `knowledge-base/engineering/operations/post-mortems/2026-07-29-v0244-1-published-green-with-an-unpullable-image-postmortem.md`
  moves to resolved ONLY when prod actually serves a new version. Verify with
  `curl -s https://app.soleur.ai/health | jq -r .version` — it read `0.244.0` against tag
  v0.246.1 at handoff. A merge is not a deploy.
- **#7095 does not auto-close on this PR.** Its Definition of Done includes the staleness
  alerting that lives in #7103. Use `Ref #7095`, not `Closes`.
- If the apply lands but the post-apply redeploy fails, the recovery is
  `terraform apply -replace=terraform_data.infra_config_handler_bootstrap` — a plain
  `workflow_dispatch` re-run is a NO-OP, because `-target` selects rather than replaces.

Self-pull all diagnostics (`hr-no-dashboard-eyeball-pull-data-yourself`): Better Stack
`SOLEUR_*` markers via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`,
`gh run view --log`, Sentry. Never ask the operator to paste logs or run probes.

## Step 2 — #7103 (only after prod is confirmed deploying)

`/soleur:go #7103` — the consolidated PR-B hardening tracker. Largest item is that 19 of 19 host
installers are pinned to `hcloud_server.web["web-1"]`; the invariant is `for_each` over
`var.web_hosts`. Also: `vector.toml` Source-4 entries plus `SyslogIdentifier=` stamps (an
allowlist entry without a stamp is a dead no-op), the `doppler_read_failed` terminal reason, a
credential-liveness probe folded into `web-zot-consumer-probe.sh`, consecutive-failure and
prod-staleness alerting, ADR-154, and both PIRs.

Two facts verified during PR-A that #7103 must not re-assume:
- `web-1.app.soleur.ai` and `web-2.app.soleur.ai` do NOT resolve (curl 000). The per-host origin
  probes the staleness condition wants do not exist as DNS today; `model.c4` describes them
  aspirationally.
- GHA `schedule:` jitter was measured up to 339 minutes over 58 days. Use the Inngest
  dispatch-hybrid substrate, not a raw cron — a 2h cadence cannot carry a 480-min monitor margin,
  and every false page is an unactionable email to a non-technical founder.

## Step 3 — #7104

`/soleur:go #7104` — the apply-verify step re-polls but never re-POSTs, so it cannot recover from
the documented nonce-1 webhook-restart race (`push-infra-config.sh:25-31`).

Read the issue body before designing: R22's original premise is FALSIFIED and recorded there. The
fix requires `continue-on-error` on a fail-closed gate whose latched false-green (#6594) is what
let this outage class hide — so the adjudication step must still fail closed, and that needs a
fixture proving it does when both passes fail. Getting this wrong converts a fail-closed gate into
a fail-open one, which is strictly worse than the race being fixed.

## One thing to carry into all three

Every defect found on this branch — a credential printed into CI logs, a `source` that would
execute `$(...)` under NOPASSWD sudo, a mitigation that blanked itself, a missed consumer, a
tautological test, two false safety claims — coexisted with fully green suites. The suites caught
one thing all session. Review and the exit gate caught the rest. Weight review accordingly, and
mutation-prove any guard you add: baseline green, mutant red, restore verified byte-identical
against a pristine backup. A mutation that fails to land reports the baseline, which reads exactly
like "the guard caught nothing to catch".
```

---

## Quick facts for whoever picks this up

| | |
|---|---|
| Worktree | `.worktrees/feat-one-shot-7095-host-pull-leg` |
| PR | #7097 (draft, 28 commits) |
| Prod version at handoff | `0.244.0` against tag `v0.246.1` |
| Root cause | web-1's boot-baked Doppler token revoked 2026-07-30T11:19:30.614Z |
| Gates | test-all 239/239, infra 87/87 (solo), tf fmt+validate 0 |
| Open follow-ups | #7103 (harden), #7104 (apply-verify re-POST) |
