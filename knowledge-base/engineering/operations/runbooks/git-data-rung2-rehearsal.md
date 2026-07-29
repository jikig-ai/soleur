# Runbook — the git-data rung-2 boot rehearsal

Boots the real git-data cloud-init once on a **throwaway** host, so the first real boot of
that template is not the production host holding every connected user's source code.

This is **not** a second DO-NOT-DISPATCH banner. The hold lives in `git-data-birth.md` and in
`git_data_rung2_rehearsal_gate`; this file only says how to run the rehearsal and how to read
what comes back.

## Dispatch

```bash
gh workflow run git-data-rung2-rehearsal.yml \
  -f confirm=REHEARSE-GIT-DATA -f dry_run=true
```

The workflow's own input descriptions are the source of truth for the flags — they are not
restated here, because a second copy drifts. Two human gates and nothing else: the
`web-platform-infra-apply` environment approval on the dispatch, and your review of the
evidence PR. There is no SSH anywhere in this route; the rehearsal host is never logged into.

Start with `dry_run=true`. It renders, plans, asserts the plan **creates only rehearsal
addresses and destroys nothing**, and stops. Re-dispatch with `dry_run=false` when you intend
to spend a real host (~€0.02, ~8 minutes).

## The three artifacts, and what each one rules out

| Artifact | What it establishes |
|---|---|
| **Source-liveness anchor** — any Better Stack row from any *other* host | The instrument works. Without it, zero rows from the rehearsal host is ambiguous between "booted dark" and "my query/credentials/source are broken", and reading it either way is a guess. |
| **`stage:boot_complete`** from the rehearsal host, four booleans positive | The boot reached its final stage with every invariant met. |
| **No `level:fatal`** from that host | Nothing in the chain hit its trap. Meaningful only *because* the anchor proved the channel is live. |

Each is written into the evidence file **with the query that retrieved it**. A result without
its question is unreproducible.

## Reading the outcome

The capture script is three-state, and the distinction is the point:

- **PASS (0)** — evidence written, uploaded as an artifact. Open a PR with it yourself;
  merging that PR is what releases the birth interlock.
- **FAIL (1)** — a fatal, or a false assertion. This is the failure class the whole route
  exists to find: it would have looked green from the `terraform apply`. No evidence written.
- **TRANSIENT (2)** — no verdict. **Not** evidence the host booted dark. Read the step output
  to see whether the anchor answered.

If the poll expires without a terminal answer, check **Sentry** before concluding anything:
everything before `doppler run` reaches Sentry only, because the emitter's Better Stack block
is gated on `BETTERSTACK_LOGS_TOKEN`, which exists only inside `doppler run`.

## If teardown fails

Re-dispatch with `teardown_only=true`. A surviving host is a paying box with a LUKS volume
attached; the scheduled drift workflow sweeps for the `soleur-git-data-rehearsal-` prefix
daily and files an issue, but the recovery is this arm, not a console click (a Terraform
destroy also reclaims the volumes and the scratch Doppler config).

## Two things that will mislead you

- **The evidence self-invalidates.** Its hash covers the cloud-init *and* all nine
  `file()`-bound payloads. Any later edit to what ships re-holds the birth, by design. The
  rung-2 PR check reports that on the PR that caused it rather than at dispatch time.
- **A clean rehearsal emits no `fatal`.** Do not go looking for one. The fatal channel is
  proven at rung 1 by `git-data-runcmd-rehearsal.test.sh`; rung 2 proves the real-host facts
  rung 1 cannot reach — TLS egress from a real host, a real `doppler run`, a real
  `cryptsetup luksOpen`.
