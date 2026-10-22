# Learning: a Doppler branch config does not inherit a key created after the branch, and the "fix" for that trusted repo prose on the wrong side

## Problem

PR #10501 (Inngest link TLS, Ref #10136) ships a Tier-B job that writes a flag
(`INNGEST_LINK_TLS`) as a Terraform-managed secret in Doppler `soleur/prd`, with its
source of truth in the `prd_terraform` branch config (read by every untargeted plan as
`TF_VAR_inngest_link_tls`).

Two review seats independently reasoned that `prd_terraform` is a branch of `prd` and
inherits it, so deleting the `prd_terraform` override on `off` re-exposes the inherited
value and the rollback can never empty the variable. Both cited repo documents
(ADR-241:275, a 2026-07-07 learning). The round-4 fix therefore dropped the
`prd_terraform` write and passed the value as an explicit `TF_VAR_...` instead. The next
review round found the repo also says the opposite (tunnel.tf:276-281, ADR-164,
scheduled-terraform-drift.yml:1107: the two key sets are "not in a superset relation"),
and under that reading the round-4 design made every untargeted plan (drift detector,
infra-validation, operator full apply) plan a destroy of the live flag.

## Solution

Settled by one measurement instead of a third reading of prose:
`doppler secrets --only-names -p soleur -c prd_terraform` (names only, no values) lists
170 names and does NOT contain `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET`, which are
Terraform-written keys that exist in `prd`. A key created in `prd` after the branch is
not inherited. The job writes the source key into `prd_terraform` first again, verifies
it, deletes it for `off` without swallowing a failure and re-checks absence after the
apply, and still passes `env TF_VAR_inngest_link_tls=<value>` after `doppler run` so the
job is correct under either inheritance behaviour. Tests model both worlds with a
stateful fake `doppler`.

## Key Insight

A fact about an external system (what a vendor's config layer inherits, what a
snapshot contains, what a tool prints) is settled by one read-only measurement, not by
which repo document you cite. Both the design and the panel cited prose and disagreed;
the fix replaced a working design with one correct only under the unmeasured reading,
and every fixture agreed with the implementation. Measure first, name the command in
the plan, and when a fix reverses an earlier design, re-ask what fact the reversal
assumes.

Related review findings in the same PR, all of the same family ("a control satisfied by
its own fixtures"):

- A security guard (the Doppler scope check) was relaxed so mock snapshots lacking the
  `DOPPLER_PROJECT`/`DOPPLER_CONFIG` lines would pass, leaving only a warning that
  notifies nobody. The compensating control (a persisted last-scheme memory) had no
  consumer until it was made a gate: absent metadata + flag absent + last scheme https
  now fails closed.
- The CA trust anchor was installed before the self-gate that justifies trusting it,
  and in non-strict states where no gate runs. Order is validate, self-gate the
  candidate, install, and install nothing at all when the flag is absent.
- File-selected suites cannot see repo-global lints. The affected gate found a flip
  script missing from the argv-bearer manifest, a soak probe missing from the Better
  Stack emitter-read allowlist, a runbook read with no covering edge in the kb-consumer
  ratchet, and a new repo-reading vitest missing from the repo-wide manifest. Run the
  affected gate once on the final tree before arming the merge.

## Session Errors

- **Doppler inheritance settled by prose on both sides; round-4 redesign reversed in round 6.**
  Recovery: names-only measurement, source key restored with the explicit override kept.
  **Prevention:** a plan or fix that depends on an external system's behaviour names the
  read-only command that measures it and records the output; "both documents say so" is
  not a measurement.
- **Scope guard relaxed to fit fixtures.** Recovery: fail closed when the downgrade
  memory says https. **Prevention:** before relaxing a guard to make a mock pass, ask what
  consumes the compensating signal; a warning with no routed alert is not a control.
- **Trust anchor installed before its gate.** Recovery: validate, self-gate on the
  candidate, then install. **Prevention:** for any file that becomes a trust anchor, list
  the states in which it is installed and which gate runs in each.
- **Repo-global lints invisible to selected suites (argv-bearer S4 manifest, emitter-read
  ALLOW, kb-consumers edge, repo-wide manifest).** Recovery: fixed from the affected
  gate's failure text. **Prevention:** run `test-all.sh --affected` once on the final tree
  before the merge; a green file-selected set is not that.
- **Hooks blocked three commands** (an issue filing without a `Mandated-By` line, `pgrep -f`,
  a command that listed the stash). Recovery: reworded. **Prevention:** none beyond the
  hook text.
- **Two subagents returned stray fragments; two were interrupted by a restart or rate
  limit.** Recovery: resumed with SendMessage after reading their worktree diff.
  **Prevention:** the brief asks for the report in the final message; verify a short
  return is a report before treating the seat as done.
- **Ran a ratchet while the gate ran (shared TMPDIR) and got 27 false failures.**
  Recovery: re-ran alone, 30/30. **Prevention:** never run suites concurrently with the
  gate; redirect stdin (`< /dev/null`) for backgrounded suites, since a fake `docker`
  that reads stdin hangs them.
- **A pre-existing environmental failure in the gate** (`git-data-runcmd-rehearsal`, an
  `apt-get` inside its docker fixture, file untouched by the PR). Recovery: identified
  from `FIXTURE_APT_CAUSE`, left for CI.

## Tags
category: workflow-issues
module: infra, inngest, doppler, review
