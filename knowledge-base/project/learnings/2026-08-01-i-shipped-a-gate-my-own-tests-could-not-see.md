# Every check I wrote certified something narrower than the claim it carried

- **Date:** 2026-08-01
- **Issue:** #7095 (production undeployable since 2026-07-29) · **PR:** #7133 · **Follow-ups:** #7103
- **Category:** test-failures / workflow-patterns
- **Related:** [ADR-154](../../engineering/architecture/decisions/ADR-154-repair-the-credential-channel-not-the-host.md),
  `cq-assert-anchor-not-bare-token`, `hr-no-dashboard-eyeball-pull-data-yourself`

## Problem

The PR's whole subject was a detector whose verdict **blocked nothing** — it fired three times
naming a dead credential while production stayed down for three days. I built the gate that makes
that verdict block, shipped it with a green suite, a 9-mutation battery reporting all-caught, 240/240
`test-all.sh`, clean shellcheck and zero new actionlint findings.

An 8-agent review then found eleven defects. The dominant one:

> **Deleting the entire liveness-gate step left my own test suite 30/30 green.**

Three agents proved it independently by mutation. Every other finding turned out to be the same
shape at a different layer.

## Root cause: the assertion and the property were not the same thing

### 1. The anchor matched my own comment

`W3`/`W4`/`W8` grepped bare identifiers — `ci_ssh_access_denied`, `REPLACE-CI-SSH-TOKEN`. Those
strings appear in the action's **header comment** (added by the same PR, listing all three reason
enums) and in the workflow's **dispatch-input description prose**. So the assertions passed on
documentation while the code they described was deletable.

The block's own preamble said, in as many words, *"every grep below anchors on a construct a COMMENT
cannot produce."* The three assertions immediately beneath it did not. `cq-assert-anchor-not-bare-token`
was **cited and not applied** — and the identical finding was already recorded one file over, in
`stock-preflight-coverage.test.ts`, which had fixed it by anchoring on `^\s*source\s+…`.

**Fix:** anchor on things a comment cannot produce — an emission (`^\s*echo "::error::<enum>`), a
shell comparison (`"$CONFIRM_RAW" != "…"`), a flag at flag position (`^\s*-replace=`).

The trap is structural, not careless: the moment a task requires both *"assert X"* and *"document
X"*, the two collide. Expect it whenever you write a comment explaining the thing you are asserting.

### 2. A count is invariant under substitution

`W6` asserted *"exactly 6 bridge call sites."* An agent pointed one caller at a different action and
added a spare `uses:` elsewhere. Total still 6. Suite green. A workflow that SSHes to a production
host had silently lost its gate — and the failure string `W6` *would* have printed described exactly
that, having never printed.

A cardinality assertion quantifies over a set and samples only its size. It is evadable by
substitution **and** brittle under legitimate growth (a 7th adopter reds it with a message blaming
duplication).

**Fix:** derive the sorted **filename list**. A dropped caller and a new adopter now both produce a
diff that names the file.

### 3. A clean verdict reached by exhausting negative branches

The gate read `dead` and `unverifiable` and never `live`. The detector reaches `exit 0` with
`live=dead=unverifiable=0` whenever key *names* enumerate but every value read returns empty — that
read's exit status is discarded upstream. So the gate could certify **zero pairs** and let terraform
proceed to destroy.

Worse, success was reached by falling through three `if`s. With counts as empty strings
(`[[ "" -gt 0 ]]` is false) every branch declines and the gate reports clean. The sibling ladder it
was copied from carries a belt for exactly this (`[[ -n "$verdict" ]] || verdict=unavailable`); the
copy dropped it.

**Fix:** assert the success condition **positively** — `live > 0 && dead == 0 && unver == 0` — and
fail closed on anything else.

## The part worth internalising: I broke three rules I had just written down

Each violation sits within a few hundred lines of where I stated the rule.

| I wrote | I then did | Distance |
|---|---|---|
| ADR-154 §3: *"probe the transport before the destroy"* | checked the Doppler write token **inside** the sync step, i.e. after the irreversible apply | same PR |
| Bridge gate comment: *"DEAD and UNVERIFIABLE must not share a code path"* (the #7127 defect) | branched the re-mint halt gate on the bare exit code | ~4000 lines |
| AC10: *"assert this positively"* | reported clean by fall-through | same file |

Writing a principle down does not transfer it to the next code you write. The mechanism that caught
all three was an outside reader, not the author's intent.

The same shape produced the security defect: the constitution says never run a Doppler secret-write
without redirecting stdout (the CLI prints the entire remaining config; **`--silent` is not one of
the accepted mitigations**), the repo's own canonical script for that exact operation uses
`--silent` **and** `>/dev/null 2>&1` — and I cloned the workflow sibling that omitted it rather than
the script that had it right. On a **public** repo. The PreToolUse hook later blocked my own `grep`
for containing the command string: it guards Bash calls, not committed YAML.

**Generalisable:** when cloning a pattern, clone the one that is *canonical for the operation*, not
the one that is *nearest in the file you are editing*. And a rule you read this session is not a
rule you have applied.

## Asserting instead of measuring

Four claims in my own prose did not survive re-derivation:

| Claim | Measured |
|---|---|
| 8 consecutive failed releases | **15** — then **16** four hours later |
| "three of the eight postdate the fix" | **two** of the fifteen |
| "three fires across three days" | three fires spanning **24h across two calendar days** |
| "reproduced identically on a second run" | the run history contains **no second run** |

And a fifth: both the ADR and the plan said `app.soleur.ai` is *"served over :443 through the
tunnel."* It is not — `tunnel.tf` declares exactly three ingress hostnames (`deploy.`, `registry.`,
`ssh.`) plus a 404 catch-all; `app` is a CF-proxied A record straight to web-1, covered by no Access
application. **The conclusion (serving surface untouched) was right; the mechanism was wrong** — and
a wrong mechanism is worse than a missing one, because the next reader reuses it.

**A count restated in prose rots.** "15" was correct when written and wrong within four hours,
because it grows for as long as the channel is dark. Re-anchored on the last successful run id,
which does not move.

## Prevention

1. **For every assertion, name the mutation that satisfies it while violating the property.** If you
   cannot, the assertion is pinned to spelling, not behaviour. Litmus: delete the thing the test is
   named for and re-run — green means it pins nothing.
2. **Never let your own mutation battery be the last word.** Mine reported 9/9 caught. It covered the
   mutations I imagined; the vacuities lived in the axes I did not think to mutate (prose sites,
   count-preserving swaps). Instruct the reviewer to *find what the battery missed*, not to re-run it.
3. **Build the second battery from other people's counterexamples.** Round 2 here was assembled
   entirely from agent findings — 10 mutations, green control baseline, per-mutation landing check
   (`diff -q` vs pristine). All 10 caught. A mutation that does not land reports a false result in
   both directions.
4. **Prefer membership over cardinality** in any "all N of X" guard.
5. **Assert success positively.** Reaching a success branch by exhausting failure branches means
   every unmodelled state reports success.
6. **Re-derive every number before it ships,** and prefer an anchor that cannot move (a run id) over
   an integer that can.

## Session Errors

1. **W3/W4/W8 anchored on bare tokens their own file's comments contain** — gate fully deletable at
   30/30 green. Recovery: re-anchored on emissions/comparisons/flag positions; added W10.
   **Prevention:** litmus above; `cq-assert-anchor-not-bare-token` needs a worked counterexample, not
   just a citation.
2. **W6 asserted a count, not a membership** — count-preserving caller swap survived.
   Recovery: derive the sorted filename list. **Prevention:** prevention #4.
3. **`doppler secrets set` with no stdout redirect on a public repo** (2 new sites + 2 pre-existing
   cloned from). Recovery: redirected all four. **Prevention:** the existing PreToolUse hook covers
   Bash but not committed YAML — an actionlint/CI grep over `.github/**` would close it.
4. **Write-token verified after the irreversible apply.** Recovery: moved above the plan as an
   authenticated round-trip. **Prevention:** for any destroy, list preconditions and assert each
   *before* the first destructive step.
5. **Halt gate collapsed DEAD/UNVERIFIABLE.** Recovery: same three-way ladder as the bridge gate.
   **Prevention:** when a rule says "every consumer", enumerate the consumers.
6. **Gate could report clean having measured nothing.** Recovery: require `live > 0`.
7. **Four unmeasured numbers + one wrong mechanism in ADR/plan prose.** Recovery: re-derived all;
   re-anchored the rotting count.
8. **Heredoc body at column 0 broke two workflow YAMLs.** Recovery: indented into the block scalar so
   YAML strips it and bash still sees `PY` at column 0. **Prevention:** parse every touched YAML
   after editing — caught by my own check, not by review.
9. **Three mutation-harness bugs** (two `expect` strings matched pass-text, one `sed` anchor had the
   wrong indent) — each reported a false SURVIVED/DID-NOT-LAND. Recovery: fixed and re-ran.
   **Prevention:** verify the instrument before reading its output.
10. **Edited the ADR under a running `test-all.sh`.** The result described the pre-edit tree.
    Recovery: committed and ran all four ADR-reading gates against the edit. **Prevention:** confirm
    clean, launch, then do not edit — or kill the run.
11. **Nearly reported a false finding from GitHub's echoed run-block source** — grepping a failed
    run's log for `resend_api_key_unset` matched the `if [[ -z … ]]` line GitHub echoes as step
    *source*; the masked `RESEND_API_KEY: ***` showed the secret was present. Recovery: verified
    before claiming. **Prevention:** a log grep must distinguish executed output from echoed source.
12. **Collision gate missed two OPEN sibling PRs** (#7127, #7115) — its body probe is `--state
    merged`. Recovery: found them by inspecting sibling worktrees at session start. **Prevention:**
    probe open PRs touching the same paths, not only merged ones.
13. **deepen-plan gates 4.8/4.9 false positives** (forwarded from the planning subagent) — a
    pre-existing Doppler credential read as a GitHub PAT; a gate matched its own glob list.
14. **IaC-routing guard blocked the initial plan Write** (forwarded) — triggered by a
    rejected-alternative row mentioning hand-editing. Behaved as designed.
15. **The gate this PR shipped was verified as delivered and never as ACTIVE** (appended
    2026-08-02 while implementing #7103 R2; the omission this list originally had). The session
    confirmed the corrected drop-ins landed with the right bytes on `web-1` and treated that as the
    fix being in effect. systemd reads a drop-in only when its unit is (re)started, and nothing
    restarted `vector.service` or `inngest-heartbeat.service` — so both kept running the revoked
    credential while every signal the session had said the repair was complete. It is the same
    defect class as the entries above (an assertion that cannot observe the thing it claims), one
    layer out: the assertions were about FILES, and the claim was about PROCESSES.
    Recovery: #7146 folds unit reconciliation into the handler, grades it on effect rather than
    exit code, and reports a per-unit verdict the CI gate adjudicates (ADR-158).
    **Prevention:** when a change's stated outcome is a running process behaving differently, no
    file-level assertion discharges it — assert the process (`ExecMainStartTimestamp` advanced,
    `ActiveState` active), or say plainly that activation is unverified.

## Placement note

No new `AGENTS.rules.md` rule is proposed. The dominant insight is already covered by
`cq-assert-anchor-not-bare-token` (**already-enforced** under the placement gate — the failure was
application, not absence), and the membership-vs-cardinality and positive-assertion rules are
**domain-scoped** to test authoring. Both route to the `review` skill's defect-class catalogue
instead. Budget was not the constraint: the linter reports `[OK] B_ALWAYS=42547`, exit 0.
