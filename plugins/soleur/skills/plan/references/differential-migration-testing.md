# Differential migration testing

How to validate a rewrite, port, or replacement of a running system: run the old
system and the new system side-by-side on the same inputs, normalize the
non-semantic differences, and diff their outputs. The old system is the oracle.
When the diff is clean modulo a ledger of approved changes, delete the old
system.

This technique is the migration-shaped half of differential testing. The
`reproduce-bug` skill names the adjacent case (run the same input through an
old version and a new version of one system to isolate a regression); this doc
covers validating a whole-system replacement, which needs more apparatus: a
normalization contract, a replayed-traffic corpus, an approved-changes ledger,
and a delete-the-old exit criterion.

## When this applies

Use this when the feature rewrites, ports, or replaces a system that is still
running and still producing output someone depends on:

- A service or CLI re-implemented in a new language or framework.
- A pipeline moved to a new engine (same inputs, new internals).
- A subsystem replaced by an equivalent component with a different API.

This does NOT cover schema migrations (DDL changes to a live database). The
word "migration" here means replacing a runnable system, not `*.sql` migration
files, which have their own runbooks and defect-class documentation.

## The oracle: the old system is the control arm

The old system is the control arm in a control-vs-treatment pair — the same
shape the `eval-harness` skill uses to compare prompt variants, with the
existing system playing the control role. This is equivalent to property-based
testing where the property is output equivalence: for every input, the new
system's observable output equals the old system's.

Every mismatch is exactly one of two things:

1. A bug in the new system.
2. An intended behavior change — which must land in the approved-changes
   ledger (below), with a reason.

There is no third option. A difference with no ledger entry is a bug by
definition; the ledger is what keeps "different" from silently becoming an
acceptable state.

## Inputs: generated plus replayed

Hand-picked cases miss the edges a rewrite actually breaks on. Use two input
sources:

- **Randomly generated inputs** across the whole input domain — the
  property-testing pattern's generators, pointed at both systems instead of
  one. Cautions: bound the generator's entropy so every run actually varies
  (a generator whose stream is frozen produces one case while reporting many),
  assert generated members are valid inputs (an invalid member proves nothing
  about either system), and check the generator's coverage actually spans the
  domain (a generator over a subset reads as green over the whole).
- **Replayed live-traffic samples** — recorded requests, commands, or events
  from the running system, replayed against both. Real traffic carries the
  long tail no generator invents: weird encodings, legacy clients, inputs
  nobody remembered were possible.

Replayed inputs must be recorded, never resynthesized — a resynthesized input
is a guess about what production sends.

## Normalize before comparing

Before diffing, normalize away categories a human has declared non-semantic:

- Ordering that carries no meaning (unordered sets serialized in arbitrary
  order).
- Timestamps, run IDs, generated UUIDs.
- Whitespace and formatting differences.
- Absolute paths, hostnames, ports that differ by environment.

For structured output, canonicalize first (sorted keys, stable serialization)
so the diff compares content, not byte layout.

The inverse trap is over-normalization: every category you normalize away is a
category where real divergence becomes invisible. Normalize only what a human
has explicitly declared non-semantic, and keep the normalization list in the
harness where a reviewer can audit it.

## Compare the whole output set

Compare outputs as a bijection, not a subset. "Every new-system output matches
an old-system output" leaves deletions invisible — a behavior the new system
simply dropped reads as clean under a subset check. Diff the full output set
in both directions: nothing added without a ledger entry, nothing removed
without a ledger entry.

## The approved-changes ledger

Every accepted divergence is recorded in a ledger with:

- What differs (input, old output, new output).
- Why it is intended (the requirement or decision that changed the behavior).

The ledger does double duty: it is the mechanism that keeps "different" from
becoming silently acceptable during the migration, and it becomes the
migration's release-note / breaking-change list at the end. An empty ledger
means "identical behavior"; a non-empty ledger is the contract for what users
should expect to change.

## The loop

The working cycle:

1. Tweak the new system (or the corpus, or the normalization rules).
2. Run both systems over the input set.
3. Review the mismatches.
4. Fix the bug, or add an approved-changes ledger entry.
5. Repeat.

Keep the loop fast and deterministic. A slow loop gets run less often; a flaky
loop teaches its operator to retry until green instead of fixing the
divergence.

## Harness shapes

Two concrete shapes cover most migrations: a CLI diff harness over commands
and a recorded-fixture replay harness over captured traffic. Both are the
control-vs-treatment arm pattern with the old system as the control.

### CLI diff harness

When both systems are callable as commands (two binaries, two CLIs, an old
service and a new one behind a local port):

1. Build a corpus: generated inputs plus replayed samples.
2. Run the corpus through the old command and the new command, capturing each
   output.
3. Normalize both output sets.
4. `diff` the normalized sets as a bijection.
5. Triage every mismatch: fix or ledger.

### Recorded-fixture replay harness

When traffic can be captured (HTTP requests, message-queue events, job
invocations):

1. Record a sample of live traffic as fixtures.
2. Replay the fixtures against both the old and new deployments.
3. Capture and normalize both response sets.
4. Compare as a bijection; triage mismatches into fixes or ledger entries.

## Incremental migrations

When the migration is partial — strangler-fig cutovers, per-endpoint or
per-command replacement — scope the harness per migrated surface: the diff
compares only the slices the new system owns, and each cut slice retires its
old-system path. The ledger then records which surface each approved
divergence belongs to.

## Exit: delete the old system

The exit criterion is not "the diff has been clean for a while" — it is
deleting the old system. The harness is what gives you the confidence to wipe
it away. When the diff is clean modulo the ledger and every behavior has moved
over:

1. Stop the old system.
2. Remove its code, deployment, and the comparison harness with it.

Keeping both systems running is twice the work and two ways to break; a system
kept "just in case" still drifts, still gets paged, and still gets hit by
clients nobody rerouted.

## Sharp edges

- **Mocks must sit below the comparison seam.** A mock above the seam makes
  its own canned output the fixture — you diff your mock against your mock and
  get green forever. Stub infrastructure the harness does not compare (auth,
  clocks, storage backends); never stub either system's decision path.
- **Replayed traffic is production data.** Sanitize or scope the replay corpus
  before it leaves the capture environment — credentials, PII, and tenant data
  travel with recorded requests.
- **A sampled-once corpus is not coverage.** A green diff over inputs drawn
  once proves those inputs agree. Regenerate the corpus, grow the replay
  sample, and treat the run as an ongoing gate until the old system is gone.

Source: Addy Osmani, [Agentic Verification](https://addyo.substack.com/p/agentic-verification)
(differential-testing section) — the old system as oracle, random plus replayed
inputs, the approved-changes list, and the delete-the-old exit.
