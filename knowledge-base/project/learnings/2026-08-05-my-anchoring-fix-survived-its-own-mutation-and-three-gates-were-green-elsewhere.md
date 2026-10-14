---
category: test-failures
module: apps/web-platform/infra
issue: 7220
tags: [mutation-testing, drift-guards, sudoers, follow-through-probes, byte-budget, adjacent-property]
---

# Learning: my anchoring fix survived its own mutation, and three gates were green somewhere else

## Problem

Shipping the review findings for #7220 PR-B (the `daemon-reload` privilege grant). The operator's
brief already named the class: *every defect found was a check certifying a property adjacent to
the one it was named for, and my own mutation batteries were green throughout.* The session
reproduced that class four more times — twice in code I wrote **during** the fix.

## The four adjacent-property instances

**1. A lint that certified commands sudo would DENY.** `_lint_privileged_verbs` resolved every
call to the bare string `systemctl <verb>` and substring-grepped it against `Cmnd_Alias` lines.
That discards the UNIT and ignores the User_Spec. Measured against the pre-fix lint, all of these
returned `rc=0`:

```
$SYSTEMCTL_PRIV stop webhook.service       matched INNGEST_STOP's   "systemctl stop"
$SYSTEMCTL_PRIV restart nginx.service      matched INNGEST_RESTART's "systemctl restart"
$SYSTEMCTL_PRIV disable webhook.service    matched INNGEST_QUIESCE's "systemctl disable"
sudo /usr/bin/systemd-run <ANY argv>       resolved to the bare word "systemd-run"
```

A `Cmnd_Alias` with no `deploy ALL=(root) NOPASSWD:` grants nothing, so the lint blessed calls that
would be denied — and a denial is the exact `set -e` abort after delivery that the lint was named
to prevent.

**2. A test that proved the callee reads a variable, never that the caller sets it.**
`infra-config-red-alert.test.sh` set `INFRA_CONFIG_ALERT_RUN_URL`/`_SHA` **itself**. The workflow
exported `SECCOMP_ALERT_*`, copied from the seccomp precedent. Both were therefore always empty, so
every alert body ever filed omitted its Commit and CI-run lines *while its own prose told the
operator "the CI run linked below records exactly what was tried."* The link was never there, on
the one surface a non-technical operator reads.

**3. A follow-through probe whose PASS condition is the defect.** The activation soak counted
`action=failed reason=sudo_denied` rows toward PASS — and PASS auto-closes the tracked issue. It
would have closed the issue on the evidence of its own recurrence.

**4. The same shape one level up, in production.** #7220 itself had already been **auto-closed**,
because PR-A's fatal-channel probe exited 0 on *"the handler died and SAID WHERE."* That probe has
two PASS arms, and arm 1 (`n_fatal > 0` and attributed) is satisfied **by the defect continuing to
occur**. The issue body had predicted a mis-close from the *opposite* direction — "the PR-A probe
passes once the handler stops dying." It passes *while* it dies, as long as the death is
instrumented. Reopened; the ambiguity is filed as #7297.

## The part that mattered most: my own fix survived mutation

After rewriting the activation soak's marker matching, I mutation-tested it. Two mutations —
un-anchoring `unit=` and un-anchoring the marker's trailing colon — **survived**.

That is more informative than the fix. A surviving mutant means the fixtures were not testing the
property the anchoring existed for: the `action=` split alone already caught every row I had
written, so the anchoring was carrying no weight *in the test*. The remedy was fixtures, not more
anchoring.

Both turned out to be reachable on a real host. `infra-config-apply.sh` scrubs the `_STDERR`
`detail=` field to `A-Za-z0-9 ._:/=-` — a charset that **permits** the literal `action=failed`. So
free upstream systemctl text can contain it, and unanchored matching reads a diagnostic row as a
failed verdict: a false alarm paging the operator about a healthy host. The unit-field case is the
same shape via a future `RESTART_MAP` member whose name *contains* `vector.service`.

**A third mutation also survived and was left surviving, deliberately**: folding `failed` into the
success alternation changes no verdict, because the failure arm exits before the success arm is
consulted. That is a provably equivalent mutant, not a coverage gap — and saying which is which is
the point.

## Three pre-existing failures, each invisible to the gate that "covered" the diff

The recorded green state (`infra runner 88 PASS / 0 RED`, `parity 13/0`) was accurate about the
suites it named and silent about three real failures:

| failure | recorded | actual | found by |
|---|---|---|---|
| `web-host-provisioner-parity` | 13/0 | **12/1** | running it |
| cloud-init `user_data` vs the #6090 sub-cap | not run | **604 B over** at `7256d75c9` | `scripts/test-all.sh` |
| #7220's own state | open | **auto-closed** | `gh issue view` before shipping |

The parity failure: the destination extractor classifies a segment on its FIRST token, and this
PR's probe is `runuser -u deploy -- sudo -n /usr/bin/systemctl daemon-reload`. `runuser` is not in
`READONLY_VERBS`, so `/usr/bin/systemctl` was credited as a *delivered artifact* and the guard
demanded a fresh-boot writer for a binary the base image ships. Bisected to before `7256d75c9`;
`origin/main` was green throughout.

The byte-budget failure is the sharper lesson: it is caught **only** by
`plugins/soleur/test/cloud-init-user-data-size.test.ts`, which lives **outside** the infra runner.
So `run-registered-suites.sh` at 91/91 and six green infra suites were all structurally blind to
it. "The infra runner is authoritative for an infra diff" is false for cross-cutting gates.

## Key Insight

Three rules, in order of how much they cost to learn:

1. **When a mutation survives, say which kind it is.** Either the fixtures don't exercise the
   property (fix the fixtures) or the mutant is equivalent (prove it and move on). "Survived" is
   never a result you leave unlabelled — it is the only signal that distinguishes a guard doing
   work from a guard that happens to be adjacent to one.
2. **A test that supplies the input it is checking proves nothing about the supplier.** If the test
   sets the env var, the mock, or the fixture that production must provide, derive the expected set
   *from the consumer* and assert the *producer* sets it.
3. **A probe whose PASS arm can be satisfied by the failure it watches for will close the issue it
   gates.** Enumerate the PASS arms and ask, for each: is this state distinguishable from the
   defect? If not, that arm is TRANSIENT, not PASS.

And the framing that ties them together: **the authoritative gate for a diff is not the runner
named after the diff's directory.** Byte budgets, mirrored-file parity, and issue state all live
outside it.

## Session Errors

- **`pkill -f 'web-host-provisioner-parity-mutation'` killed the invoking shell (exit 144).** The
  pattern matched the pkill command line itself. Recovery: re-issued the edit, then reaped stragglers
  with a `pgrep` loop that skips `$$`. **Prevention:** already an AGENTS rule; the miss was applying
  it only to the documented example and not to my own pattern. Use `pgrep`+`kill` with a self-PID
  guard, never `pkill -f`.
- **`git checkout -- apps/web-platform/infra/cloud-init.yml` discarded a verified, uncommitted trim.**
  Cost a full re-derivation of a measured edit. **Prevention:** the "commit each verified unit
  immediately" rule exists for exactly this; I held a verified edit across a measurement loop that
  itself mutated the working tree.
- **Heredoc'd an issue body into the SAME Bash call as a hook-gated `gh issue create`.** The hook
  denied the whole call, so the heredoc never ran and the retry failed `no such file`.
  **Prevention:** already documented — write the body with the Write tool first, then run `gh` alone.
- **A python heredoc broke on nested `"""` when splicing a block that itself contained triple
  quotes.** **Prevention:** splice such blocks from a file rather than embedding them in a heredoc.
- **Set `ALERT_MIN_ASSERTIONS=27` against an actual 29 while the comment claimed zero headroom** — so
  the drop-an-assertion mutation still passed. Caught by running that mutation. **Prevention:** derive
  the floor from the measured count in the same step that writes it; never hand-count.
- **Set `ACTIVATION_MIN_ASSERTIONS=16` against an actual 15**, so the suite failed its own floor on
  first run. The floor caught my miscount, which is the argument for zero headroom.
- **CWD drifted across Bash calls** (`cd apps/web-platform/infra` persisted), producing a confusing
  `No such file or directory`. **Prevention:** absolute paths, or `cd <abs> && cmd` in one call.
- **The scratchpad dir did not exist, so `git show … > "$S/f.sh"` failed** and my probe printed
  `UNREADABLE` for both candidate SHAs — I nearly concluded both blobs were absent from the object
  store. **Prevention:** `mkdir -p` the destination in the same command that writes to it, and treat
  "both candidates failed identically" as a harness smell, not a finding.
- **Spent three attempts probing the parity guard's internals** (exec'ing its embedded python) before
  switching to driving the REAL guard against a sandbox via `SOLEUR_INFRA_DIR`. The guard exits early
  on a parse failure, so partial-exec never reached the function under test. **Prevention:** when a
  guard exposes a sandbox override, drive the whole guard through it; do not re-implement its
  harness.
- **The AC6 lint rewrite was swallowed into the merge commit** because I staged the test file before
  committing the merge, leaving a message that under-described its own diff. Recovery: amended to
  describe both. **Prevention:** commit the merge resolution alone, then the feature edit.
- **Wrote an assertion anchored on `10-inngest`, a literal the DropInPaths probes do not contain.**
  The new assertion failed on its first run. **Prevention:** grep the target for the anchor before
  asserting on it — the same content-anchor discipline the assertion itself was enforcing.
- **Renamed `restart_rows` → `ok_rows` and left one reference behind**, which would have been an
  unbound-variable abort under `set -u`. Caught by reading the diff before running.

## Prevention

- Mutation-prove every guard on a **sandbox copy**, assert the mutation **landed** (`diff` against a
  pristine backup) before trusting any result, and treat a baseline-identical count as UN-RUN.
- For each surviving mutant, record `equivalent` or `fixture-gap` explicitly in the commit body.
- Before shipping against an issue, run `gh issue view <N> --json state` — an auto-closing
  follow-through may have closed it on evidence you would not accept.
- Run `scripts/test-all.sh` even when the directory-specific runner is green; read its **preamble
  and epilogue**, not just `rc`.
