---
date: 2026-07-15
category: best-practices
module: infra/ci
issue: 6416
pr: 6421
also_seen_in: [6454]
also_seen_pr: [6458]
tags: [destroy-guard, terraform, github-actions, followthrough, cloudflare-tunnel, false-verdict, cloud-init, required-checks]
---

# Learning: a guard, its gate, and its probe must each pin the thing they are named after

## Problem

#6416: `soleur-web-2` had no private-network IP, so the Cloudflare tunnel connector on it could
not reach zot at `10.0.1.30:5000`, and CI's zot mirror silently skipped on every release.

The fix was straightforward. **Everything built to guarantee the fix was not.** Four independent
P1s, each an instance of one shape: *an artifact that certifies a neighbour of the property it
claims to certify.*

> **§6-§8 were added the same day from #6454 / PR #6458** — a *different* CI gate, written by a
> different session, which reproduced this file's shape three more times **while this file already
> existed**. That is the most useful fact here: the shape is not rare, and writing it down did not
> inoculate the next author (me) against it. Read §6-§8 as evidence that this needs a mechanical
> litmus at authoring time, not a lesson one absorbs once.

## The generalizable lesson

> A guard that counts is not a gate. A test that pins the gate's INPUT does not pin the gate. A
> probe that finds no failure has not found success. An assert in a sibling session says nothing
> about the session that writes.

Each of these reads as true until you name the exact property and ask what would falsify it.

## Solution

### 1. "No double-count" is a COUNTING argument. It does not transfer to a gate.

`host_creates` selected `.change.actions == ["create"]` **exactly**, justified as: *"a `-replace`
serializes as `["delete","create"]` and is already counted by `resource_deletes` → no
double-count."*

That reasoning is sound for a counter that is **summed**. `host_creates` is not — the workflow's
`destroy_count` sums only the three original counters, and the HALT is evaluated independently.
**There was nothing to double-count against.** The exactness bought nothing and cost the
guarantee: a `-replace` *destroys and re-creates* a host, leaving it unattached exactly like a
fresh create, and read `0`.

Worse, the failure composed with the sibling gate. A replace trips `resource_deletes`, and the
destroy gate then **prints** *"Add `[ack-destroy]` to acknowledge"*. An author acking a
legitimate sibling change (a ruleset-rule removal in the same merge) would ack the host rebirth
through with it — **#6416 reproducing through the guard built to prevent it.**

**Litmus:** before narrowing a selector to avoid double-counting, ask *is this key a term in the
sum I am avoiding double-counting against?* If not, the argument does not apply. Then ask *what
does the OTHER gate tell the operator to do when this one abstains?* `reboot_updates` already
learned this (#5911's steer says "do NOT add `[ack-destroy]`"); host rebirth had not.

### 2. A test that mirrors the workflow in hand-written bash pins the FILTER, not the GATE.

`test-destroy-guard-counter-web-platform.sh` re-implements the workflow's bash in a helper. It
therefore pins the jq filter's counting — and nothing else. Proven at review by mutation:

```
# delete the ENTIRE host_creates HALT block from apply-web-platform-infra.yml
=== 33 passed, 0 failed ===
```

**The gate the PR existed to add could be deleted and every test stayed green.** The test *names*
claimed otherwise ("HALTs", "cannot bypass"). Adding a genuine ack bypass to the workflow also
stayed green — so `T29b`'s "ack-independence" proof was a tautology: the helper takes no
`head_msg`, so no message can change its output.

**Fix:** pin the gate's control flow against the workflow's literal bytes. The repo already had
the cure and this PR skipped it — `test-destroy-guard-regex-parity.sh`, whose own header says
*"CODEOWNERS gates approval but not content coherence — this script is the deterministic
coherence check."* The HALT's contract is three properties: **present**, **positioned above the
`destroy_count` sum** (position IS the ack-independence), and **in the numeric-parse
validation**. All three now fail RED on mutation while the counter suite stays green — which is
exactly why the check was needed.

Better still where available: `extract_run_block` (used by
`reusable-release-zot-mirror-retry.test.sh`) runs the REAL workflow block verbatim. That is why
its T4/T5 were the only non-vacuous new tests in the first pass.

### 3. A probe that finds no failure has not found success.

> **Post-merge addendum — the shipped probe had two more of these, found only against a REAL
> log.** Ten agents reviewed it and missed them, because they are unobservable until a real
> post-fix job log exists. (a) The degraded anchor required a literal `::warning::`, but GitHub
> **renders** a `::warning::` workflow command as `##[warning]` in the job log — so the anchor
> matched the emitter's echoed SOURCE and missed every real emit. (b) The liveness anchor
> `copied .* to 127.0.0.1:5000/` matched **the PR's own commit message**, which the release job
> log carries via the release-notes body and which quotes the anchor verbatim. Composed, they
> counted a genuinely degraded run as clean. Fixed in PR #6451.
>
> **Two rules fall out.** An anchor over a CI job log must be validated against a **real emit**,
> never the emitter's source — and must account for the platform **rendering** workflow commands
> (`::warning::` → `##[warning]`). And because the job log contains the PR/commit body, **any
> anchor a commit message could quote is unsafe by construction**; require an interpolated
> runtime value (`copied v[0-9]`) that only the real `echo` can produce.

The follow-through probe had **three false-verdict bugs found during work and two more at
review** — every one a different way to certify silence:

| Bug | Verdict it produced |
|---|---|
| `grep 'zot mirror degraded'` matched GitHub's **echoed run-block SOURCE** and the Slack step's message template | false **FAIL** on a healthy run |
| `gh api --jq` silently ignores jq's `--arg` → job lookup returned nothing | permanently **TRANSIENT** (could never PASS) |
| `test("Build and push Docker image")` also matched the auto-generated **"Post Build and push Docker image"** step → 3 TSV fields, mirror column shifted onto the post-step's `success` | **false PASS** against a run whose mirror skipped |
| `// "absent"` fell through to `ok++` when the mirror step didn't exist | **false PASS** → sweeper auto-closes #6416 while zot is not mirrored at all |
| the "shape guard" for the above: `[...][0]` + `// "absent"` make NF **always 2** | **dead code** — could never fire |

The fourth is the sharpest: it is **#6416's own defect class (absence read as health) reproduced
inside the probe built to prove #6416 fixed.**

**Fixes, all generalizable:**
- Anchor log greps on the **interpolated runtime value** (`for 127.0.0.1:5000/`), never the bare
  phrase — GitHub echoes each run-block's source into the job log, so the emitter's own text and
  any message *template* are in the haystack.
- Never read a step's `conclusion` when the step carries `continue-on-error` — the platform is
  contractually obliged to falsify it to `success`. Read `outcome`, or read a downstream effect.
- **Require a positive liveness marker before PASS.** "No failure found" and "the producer ran
  and succeeded" are different claims. A missing producer must be TRANSIENT, never clean.
- Anchor step-name matchers (`startswith` + `[0]` + a field-count assertion); GitHub injects
  `Post <name>` teardown steps that unanchored matchers swallow.

### 4. A guarantee about a session cannot be provided by a DIFFERENT session.

The in-band wrong-host tripwire asserted `$(hostname)` in its **own** `provisioner "remote-exec"`,
declared first, and claimed "FAIL-CLOSED BY CONSTRUCTION … aborts before any bytes land".
Declaration order was right; the conclusion did not follow. **Terraform dials a new SSH
connection per provisioner block**, and each dial re-enters the bridge → CF → an independent
connector selection. The assert proved only that *the assert's own session* reached web-1. It
halved wrong-host writes and turned the survivors into a **certified** green lie — strictly worse
than known-untrustworthy silence, because it is trusted.

It compounded three more ways: it keyed on runtime `$(hostname)`, which **ADR-082:196-199
explicitly rejected for this exact host pair** and `server.tf:236` calls "not guaranteed" — and
**web-1's value was never measured** (the issue measured *web-2's*). Its guard checked presence,
not the ordering its own message asserted (mutation: moving it below the `file` provisioner
stayed green). And it could not execute on that merge at all (no `triggers_replace` input
changed), so its first run would land on an unrelated future PR and taint 12 resources.

**Cut, not patched** — the plan's own rule ("when both the simplification and correctness panels
fire on the same scope, prefer delete over fix"), the same rule that had already cut v1's P2b.

**Litmus:** before building a hard gate on a runtime primitive, `git grep` the ADR corpus for
that primitive — an ADR may have already rejected it for your exact case. And ask *which session
performs the write I am protecting?* If the answer is "a different one", the guard is detection
at best.

### 5. A rate quoted from a snapshot is a claim with a timestamp.

I measured 14 consecutive skipped mirrors and inferred *"the measured rate is 100% → something
**pins** `registry.` to one replica"*. A run succeeded ~40 minutes later, **falsifying pinning
outright** — a route pinned to a route-less connector can never succeed. The honest figure is
15/16 ≈ 94%: heavily skewed, not pinned, not the plan's ~50% either.

This mattered beyond bookkeeping: **six files had copied the `~50%` figure** the ADR of record
exists to refute — they disagreed with it before the PR merged. Single-source a measured rate to
one artifact and have every point-of-use *point* at it.

### 6. A counter whose two operands come from ONE pass cannot see under-discovery. (#6454, PR #6458)

Same session, different guard, same shape — and this one is worth adding because it shows the
lesson **does not transfer by being written down**. #6458 replaced a CI gate that schema-checked a
raw Terraform templatefile. Its headline property was *"discovery is structural, never a filename
allowlist"*, and its anti-rot guard was a counter:

```bash
[[ "$VALIDATED" -ne "$DISCOVERED" ]] && exit 5   # "machine-checkable evidence the gate RAN"
```

**Both operands derive from the same discovery pass.** So the counter can only detect loss
*after* discovery — it is mathematically blind to a template discovery never found. And discovery
used a line-based `grep -oP`, while `terraform fmt` happily accepts the wrapped call style:

```hcl
hooks_json = templatefile(
  "${path.module}/hooks.json.tmpl",
  { webhook_deploy_secret = var.webhook_deploy_secret }
)
```

Reproduced against the real corpus: `hooks.json.tmpl` **silently left the set**, the gate printed
a happy `rendered+validated 4/4 file(s)`, exit 0, and `terraform fmt` passed. `5/5` and `4/4` are
both "self-consistent". The claim "structural, never a filename allowlist" was true and
irrelevant: it was a **syntax allowlist**, narrower than Terraform's grammar.

**Litmus:** for any N/N-style completeness counter, ask *where does each operand come from?* If
both come from one pass, it proves the pass was internally consistent — not that the pass was
complete. Completeness needs a **second, independently-derived opinion** (here: count
`templatefile(` occurrences and require discovery to have parsed at least that many).

### 7. The independent opinion re-introduced the trap the SAME FILE documents. (#6454)

The fix for §6 was a floor: `grep -c 'templatefile(' *.tf` vs parsed referents. It red the correct
corpus — 9 vs 5 — because it counted **comments**: `ci-ssh-key.tf`'s prose says
``the `templatefile()` interpolation map so `cloud-init.yml`'s``, and one of the four was the
#6454 note the same PR had just written into `server.tf`.

The script's own header already documents the anchored, comment-proof pattern for *attribution*.
The knowledge was in the file and did not transfer, because it was filed as a fact about
attribution rather than **about any new token-grep over source**. A guard's own comments are part
of its input.

### 8. Registration is not environment: verify the RUNNER, not the wiring. (#6454)

The plan claimed gate correctness *"is proven by the fixture suite, which runs inside
`guard-script-fixture-tests`: REQUIRED, path-filter-free, every PR and merge_group"*. Every clause
was verified and **every clause was true** — the `test-*.sh` glob picks it up, the job runs
`run-all.sh`, and `"Bash fixture tests for guard scripts"` is a required context in
`ruleset-ci-required.tf`.

What nobody checked: that job is `runs-on: ubuntu-latest` + `checkout` + `run-all.sh`. **No
terraform. No cloud-init.** All 22 fixtures exited 6 (tooling absent) and the REQUIRED,
path-filter-free check went red — blocking every PR in the repo, docs-only included. The suite had
never once executed the render path in CI, so the single most valuable fixture (*"a gate that
cannot fail is not a gate"*) had never run.

Two second-order notes:
- **Fail-closed is what surfaced it.** The script exits 6 rather than self-SKIPping (*an advisory
  test may skip; a gate may not*). A self-SKIP would have been green and proven nothing — the
  §3 shape ("a probe that finds no failure has not found success") one layer up.
- **The obvious fix was wrong.** Adding apt to that job puts a package-mirror dependency on the
  **merge-queue critical path for every PR in the repo** to protect five infra files. A required,
  path-filter-free, `merge_group` job is a shared resource. Correct move: rename the suite out of
  the auto-glob, run it from a job that already has the tooling, and record the bash-only contract
  where the glob lives so it cannot regress.

**Litmus:** for any suite you register into a job, read the job body. Registration answers *will it
be invoked*; only the runner answers *can it run*.

## Prevention

- **Guard/gate:** if a counter feeds an independent gate rather than a sum, do not narrow its
  selector with a double-count argument. Enumerate the full action vocabulary
  (`["create"]`, `["delete","create"]`, `["create","delete"]`, `["forget"]`, …) and state, per
  shape, which gate catches it and whether that gate is ack-bypassable.
- **Completeness counters:** name where each operand comes from. Two operands from one pass prove
  self-consistency, never coverage. Add an independently-derived floor.
- **New token-greps over source:** a guard sees its own comments. Anchor on the syntactic
  construct, never a bare token — including in guards you add to a file that already documents
  this for a neighbouring pattern.
- **Registered suites:** read the runner. A true registration claim (glob + job + required
  context) says nothing about whether the tools exist on that box.
- **Gate tests:** a hand-written mirror of workflow bash cannot pin the workflow. Either run the
  real block (`extract_run_block`) or assert the gate's control flow against literal bytes
  (presence + position + fail-closed validation). Mutation-test each property.
- **Probes:** require a positive liveness marker; treat producer-absence as TRANSIENT; anchor on
  interpolated values; never trust `conclusion` under `continue-on-error`.
- **Rates:** re-run before quoting; single-source the figure; write the falsifier into the
  artifact ("do not re-quote X").
- **Runtime primitives:** grep the ADR corpus before gating on one.

## Session Errors

### From #6454 / PR #6458 (the §6-§8 session)

Recorded because the pattern is the point: **13 of these are the author's own defects in a gate
written to end this defect class**, and every one was caught by multi-agent review or real CI —
none by the author.

**Forwarded from `session-state.md` (pre-compaction, plan phase):**

1. **Planning subagent terminated early** — "You've hit your session limit". No Session Summary
   emitted. **Recovery:** plan body verified on disk (frontmatter + Overview + ACs + Test
   Scenarios); resumed from plan-review rather than re-running plan. **Prevention:** one-shot's
   Step 1-2 fallback worked as designed; external limit, no workflow change.
2. **That subagent returned text not matching its return contract** (a review-shaped fragment for
   a planning task). **Recovery:** discarded as a stray transcript fragment, not used as input.
   **Prevention:** already covered — a subagent result that does not match the contract is
   evidence of a dead agent, never data.

**Defects in the fix itself (all fixed inline):**

3. **Discovery was a line-based grep → silent false-green.** See §6. **Prevention:** §6 litmus.
4. **The N/N counter could not see it** — both operands from one pass. See §6.
5. **The independent floor counted its own comments** — 9 vs 5, red the correct corpus. See §7.
6. **Six false-reds on correct Terraform**: one-line map (exit 4), nested `})` at col 0 (exit 2),
   brace inside a string value (exit 2), `%{ if !x }` (exit 2), `%{ if a && b }` (exit 2),
   `%{~ if` left-strip (exit 2). **Prevention:** a gate that reds a correct file IS the defect
   class; enumerate ordinary shapes of the grammar you parse and fixture each. All six are now
   pinned (F11-F14b, F20, F21).
7. **Registered the suite into a job with no tooling.** See §8.
8. **The "inert" comment broke a size budget** — verified rendered content, never size.
   **Prevention:** see `best-practices/2026-07-14-cloud-init-templatefile-escaping-…` §COMMENT-FROZEN.
9. **Shipped a false "one-line admin follow-up" claim**, citing a precedent that refutes it.
   **Prevention:** see `2026-03-20-github-required-checks-skip-ci-synthetic-status` §path-filtered.
10. **`grep -n` omits the filename when handed exactly ONE file** → the line number parsed as the
    filename. Caught by a fixture (single-`.tf`); the real infra roots ship many `.tf` and would
    have masked it forever. **Prevention:** `-H` whenever a grep's output is parsed as `file:line`.
11. **`grep -z` output is NUL-separated → a downstream grep says "binary file matches"** and
    prints nothing. **Prevention:** `-a` + `tr '\0' '\n'` between a `-z` producer and any
    text-mode consumer.

**Test-authoring errors (the fixtures were wrong, not the code):**

12. **F6a's stub comment reproduced VERBATIM call syntax** — indistinguishable from a real call
    site by any regex, so it tested a case the design cannot defend. **Recovery:** mirrored
    `ci-ssh-key.tf`'s REAL prose shape (`templatefile()` and the filename in one comment, never
    adjacent). **Prevention:** a fixture for a comment-vs-code trap must reproduce the REAL
    comment, not an idealised one.
13. **F13/F14/F14b rendered a bare `#cloud-config`** on the false arm — legitimately "not a YAML
    dict", so they failed for a reason unrelated to the bool typing under test. **Prevention:**
    when testing a directive, keep a key OUTSIDE the directive so both arms stay valid.
14. **F21 used `%{~`, which strips the PRECEDING newline** and glued `false` to `runcmd:`.
    **Prevention:** `%{~` is not a cosmetic variant; to test typing without whitespace semantics
    confounding it, use a JSON template.
15. **A bare-runner PATH simulation was so austere it broke `grep` itself** → "command not found"
    read as a suite failure. **Prevention:** simulate a missing tool by removing ITS directory
    from PATH, not by allowlisting a hand-picked binary set.

**Tooling traps (each already documented; this session CONFIRMS them):**

16. **Bash-tool CWD persisted after `cd`** → later relative paths resolved under the wrong root.
    **Prevention:** already in `work/SKILL.md` — chain `cd <abs> && <cmd>` in one call.
17. **`cmd | tail; echo $?` reported tail's exit (0)**, masking a real exit 2. **Prevention:**
    already in `work/SKILL.md` — `rc=$?` immediately, then inspect.
18. **`git diff origin/main` (two-dot) showed 31 files** including sibling PRs' work; three-dot
    showed the real 7. **Prevention:** already in `review/SKILL.md` — three-dot for branch scope.
19. **A mutation-test restore never ran** — the harness 2-min timeout killed the command *before*
    the trailing `cp /tmp/sut.bak`, leaving the SUT mutated on disk. The suite had **hung**,
    because the removed guard let awk read stdin. **Prevention:** `review/SKILL.md` already
    prescribes a `cp` backup; the NEW mechanism is that a hang can eat the restore itself — so
    restore in a SEPARATE call, and give the harness a `timeout` so a hang returns a verdict
    instead of consuming the window.
20. **Included `git stash list` in a probe** → the guardrail denied the whole Bash call.
    **Prevention:** working as designed; `hr-never-git-stash-in-worktrees` denies even the
    read-only form. Use `git rev-parse --verify --quiet refs/stash`.
21. **Mistyped a worktree path in an Edit** (dropped a path segment) → "File does not exist".
    One-off. **Prevention:** none warranted.


- **Plan v1 asserted five claims that review falsified** (P2b would have broken CI's only path to
  prod via the bridge's `-d "$SERVER_IP"` NAT match; P3's fix wouldn't reach the Slack line
  because step outputs are namespaced by step id; one root-cause puller named when there are two,
  the decisive one unremovable; counts asserted without running them; ADR-068 claimed to omit an
  invariant it states verbatim). — **Recovery:** plan-review + realism passes corrected each
  before /work. — **Prevention:** already covered by the plan's verify-the-negative pass; the
  residue is that /work must still re-run every plan-quoted number (it did, and found more).
- **Plan skipped its own Phase 0.6 ADR-corpus grep**, re-proposing a shape ADR-068:378-384 had
  explicitly rejected. — **Recovery:** panel caught it; P2b cut. — **Prevention:** the same grep
  would have caught the `$(hostname)` primitive ADR-082 rejected. Extend the Phase 0.6 grep from
  "has this ALTERNATIVE been rejected?" to "has this PRIMITIVE been rejected?".
- **`host_creates` fail-open on `-replace`** (P1). — **Recovery:** widened to `index("create")`;
  T30 flipped from asserting the replace passes to asserting it HALTs. — **Prevention:** §1 above.
- **The HALT was untested; deleting it left 33/33 green** (P1). — **Recovery:** HALT contract
  added to the regex-parity coherence check, mutation-proven. — **Prevention:** §2 above.
- **T32 was vacuous for the new key and I knew it.** I observed it passing *before* `host_creates`
  existed and shipped it anyway. — **Recovery:** review re-derived it; documented as covering the
  jq-parse path, not the numeric-validation path. — **Prevention:** a RED-phase signal that fires
  and is *recorded* must be acted on, not narrated. "It passes for a different reason" is a
  finding, not a footnote.
- **The tripwire was unsound on four counts** (P1). — **Recovery:** cut; design moved to #6441.
  — **Prevention:** §4 above.
- **Five probe false-verdict bugs** (2 P1). — **Recovery:** all fixed; probe verified RED against
  live data. — **Prevention:** §3 above.
- **`git add -A` committed `.tmp-seo-test-site` test artifacts** while the suite was running. —
  **Recovery:** `git rm --cached` + follow-up commit. — **Prevention:** already ruled
  (`hr-never-git-add-a-in-user-repo-agents`); the aggravator is running `test-all.sh` concurrently
  with staging. Stage explicit paths, never `-A`, while a suite is generating fixtures.
- **ADR-113 ordinal collided with a sibling that landed mid-flight.** — **Recovery:** renumbered
  to ADR-114 and swept 11 files + 2 issue bodies; deliberately did **not** sweep a sibling plan
  whose ADR-113 refs mean main's concierge ADR. — **Prevention:** the plan predicted this; the
  residue is that a blind `s/ADR-113/ADR-114/g` would have corrupted the sibling. Scope an ordinal
  sweep to files in your own diff.
- **My ordinal-collision check misread `grep -c`'s exit code as a match count** (`… | grep -c X ||
  true` printed `1` meaning "no match, exit 1"). — **Recovery:** re-checked by listing filenames.
  — **Prevention:** the plan's own Sharp Edges already warn `grep -c` returning 0 exits 1. Verify
  an ordinal by **listing filenames**, never counting them.
- **"14/14 → pinned" was falsified 40 minutes later** (§5). — **Recovery:** re-measured to 15/16;
  correction recorded in the ADR rather than silently edited. — **Prevention:** §5 above.
- **PR body and two commit bodies carried auto-close traps** (`closes #6416`, `auto-closes
  #6416`) — meta-content *about* closing, which GitHub's word-boundary parser matches through the
  hyphen. Would have auto-resolved issue #6416 at squash merge while the harm was live, defeating
  the `Ref`-not-`Closes` discipline the tasks file explicitly chose. — **Recovery:** rewrote the
  body and both commit messages (`auto-resolves issue #N`).
  > **It happened FIVE times in one session**, by an author who had just written the rule down:
  > (1) the PR body, (2)+(3) two commit bodies, (4) the commit that captures THIS learning
  > (*"…that would have closed #6416 at merge"* — while describing the trap), and (5) the body of
  > the follow-up PR that fixes the probe (*"the probe is what auto-resolves #6416 on soak
  > evidence"* — describing the correct behaviour, with auto-merge already queued, so that one
  > would actually have fired).
  >
  > **Every single one was prose describing the correct behaviour.** That is the point: the
  > natural way to *write about* an auto-close is to use the keyword next to the number. Intent
  > cannot avoid this trap, vigilance cannot, and having authored the rule minutes earlier cannot.
  > Only a mechanical scan catches it. The scan is one `grep -oniE`; the failure is silent and
  > irreversible at merge.
  — **Prevention:** the rule exists (2026-06-29 learning) and `/ship`'s `auto-close-scan.sh`
  catches commit bodies — but it runs at **ship**, and both the PR body (authored at review) and
  the compound commit (authored after) precede it. **Run the scan at every authoring site, not
  just the merge boundary:** `grep -oniE '\b(close[sd]?|fixe?[sd]?|resolve[sd]?) +#[0-9]+'` over
  the text you just wrote, before `gh pr edit` and before `git commit`. Note it cannot be
  delegated to intent — all three of mine were sentences *warning about* auto-closing.
- **A review agent restored `server.tf` from HEAD, undoing my deliberate cut** mid-review
  (it read my revert as contamination). — **Recovery:** detected via `git diff origin/main` and
  re-applied; committed immediately to protect it. — **Prevention:** already documented in
  `review/SKILL.md` ("Concurrent mutating agents contaminate the shared worktree"). Residue: the
  hazard is bidirectional — agents can undo the *parent's* edits too, not just leave their own.
  Commit deliberate reverts before spawning or resuming mutation-capable agents.
- **My own verification greps were wrong repeatedly** — `!= 'success'` matched my own explanatory
  comment; `grep -icE 'FAILED'` matched every "0 failed" summary (198 false hits); an AC check
  false-reported MISSING on case/escaping. — **Recovery:** re-checked by parsing YAML and
  separating comment lines from code. — **Prevention:** the repo already documents "grep
  assertion over a script body false-matches its own comments". The residue: I hit it while
  *verifying a fix for that exact class*. When a check reports a surprising result, suspect the
  check first.
- **A background command's "exit code 0" notification reported my trailing `echo`**, not the
  suite. — **Recovery:** read `EXIT=` from the log. — **Prevention:** already ruled; the residue
  is that the notification text is actively misleading — always grep the log.

## Related

- ADR-114 (this PR) — one tunnel, many connectors; ingress must be origin-relative
- ADR-082:196-199 — rejected runtime `$(hostname)` as a host discriminant (the rejection this
  PR's tripwire re-proposed)
- ADR-068:354-357, :378-384 — already stated connector nondeterminism; already rejected per-host
  tunnels
- #6440 (audit), #6441 (I2 + the cut tripwire's better design), #6442, #6443
- `2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md`
