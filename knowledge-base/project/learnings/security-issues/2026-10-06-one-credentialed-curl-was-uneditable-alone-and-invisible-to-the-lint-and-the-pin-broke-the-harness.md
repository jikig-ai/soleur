# Learning: one credentialed curl can be uneditable in isolation and invisible to the lint at once, and a pin invalidates the harness that fed a synthetic URL

## Problem

"Add `--disable` and `--noproxy '*'` to every credentialed curl" included the Sentry DSN POST in
`cron-egress-enforce-probe.sh`. It could not be done in that file alone, and the lint that is meant to police it
cannot see it.

## Root cause

- A suite pins that exact `curl -m 10 --retry 3 -sf -X POST ...` line byte-identical to `soleur-host-bootstrap.sh`; a
  third copy sits in `workspaces-luks-emit.sh`, a file under a separate security review. A one-file edit reds the parity
  guard.
- Lint Rule D does not classify the curl: `X-Sentry-Auth` is not in its auth-header set and the key variable `$KEY` has
  no credential-name prefix. So green lint output said nothing about that curl.
- Separately, pinning the NIC guard's ingest URL made the existing harness's synthetic destination
  (`https://synthetic.invalid/ingest`) a REFUSED one, so every existing POST row would have flipped.

## Solution

Leave the Sentry curl byte-identical, file a lockstep follow-up with a re-evaluation trigger, and say so in the PR.
Derive the pinned literal in the test from its single source (`zot-registry.tf`) so the harness feeds the real pin and a
rotation reds the suite instead of silently degrading to "refused". Mutation note: a mutant that adds a posting branch
AFTER the existing `unpinned_url` catch-all survived because it is unreachable, an equivalent mutant; placed before the
catch-all it reds 12 rows. Place a branch mutation where it can run before calling a survivor a gap.

## Key insight

"Every X" in a brief quantifies over what the lint can see; the invisible members need their own enumeration. And a
destination pin is a change to the test fixture too: grep the harness for the old destination before adding the gate.

## Tags

category: security-issues
module: infra
