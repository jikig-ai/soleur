---
title: "I built a freshness cadence on a bot that never ran, and my mutation battery certified a gate that could not fire"
date: 2026-08-05
category: workflow-patterns
module: apps/web-platform/infra
issue: 7282
pr: 7283
tags: [supply-chain, mutation-testing, vacuous-guard, false-comment, observability, review-panel]
---

# I built a cadence on a bot that never ran, and my battery certified the gate

#7282 asked for three things: bump the sole-pull-path zot registry pin (18 releases /
~18 months stale), read the changelog for schema breaks, and give the pin a cadence so it
could not silently rot again. All three shipped. What is worth recording is that an 8-agent
review found **18 blocking defects** past a green 15-assertion gate, a green 12/12 self-run
mutation battery, a 262/263 full-suite exit gate, and clean `actionlint` + `shellcheck` — and
that **five of them each invalidated a claim the PR made about itself**.

The defects clustered precisely where the prose claimed the strongest coverage. That is the
through-line, and it is the part that generalises.

---

## 1. A config file is not a running system — and the AC can certify the config instead of the execution

The first draft built the cadence on Renovate: a `customManagers` entry in `renovate.json5`,
which sits at the repo root and reads as active supply-chain coverage.

**Renovate has never run against this repository.** Measured: zero Renovate-authored PRs
across the repo's full history (`gh pr list --state all -L 300` grouped by author returns
`deruelle 259, app/dependabot 17, Elvalio 12, app/soleur-ai 9, app/github-actions 3`), and no
"Dependency Dashboard" issue — which `config:recommended` creates at onboarding. The file
configured a GitHub App that was never installed, and had been inert since #820.

Had it shipped, the cadence would have been **100% dead and silently so** — a `customManagers`
regex evaluated by nobody, on the sole pull path.

The sharper half: **the draft's own acceptance criterion would have passed.** AC5 was
`npx renovate --platform=local --dry-run=lookup`, which proves the regex parses. It cannot
prove any bot executes it in production, and no bot does. That is the
"guard that tested the one case that cannot happen" shape reproduced at *plan* level, inside
the plan meant to prevent it.

**Rule.** Before naming any bot, App, or external service as a mechanism owner, prove it has
**executed here** — group the PR history by author, and look for the artifact the tool creates
at onboarding. Then ask of every AC: *does this validate a CONFIG, or an EXECUTION?*

**Corollary.** The file was deleted rather than left in place. It was not inert-but-harmless:
it made a repo-wide gap read as covered. `docker:pinDigests` and
`helpers:pinGitHubActionDigests` advertised rotation of every Actions SHA and base-image
digest; **none has ever rotated**. Deleting it did not create that gap, it stopped hiding it
(tracked in #7288). And the correction has to reach the *generator*, not just the derived
comment: two learnings and `plugins/soleur/skills/review/SKILL.md` still instructed readers to
*"check `renovate.json5` for whether a bot mutates it"*, which is how a wrong threat model
reaches the next guard author.

---

## 2. A mutation battery scores the gate's INPUTS. It cannot see the gate's own dispatch layer.

Two distinct failures, found a day apart.

**(a) Vacuous green.** The gate's terminal contract was `[[ "$FAIL" -eq 0 ]]`. Neutering
`pass()` and `fail()` to no-ops produced `RESULT: 0 passed, 0 failed` and **exit 0** — CI green
having asserted nothing. The battery's ten mutations all perturbed the gate's *inputs* (the
`.tf`, the sidecar, a follower file), so every one was observed *through* the assertion layer.
Nothing it did removed that layer.

Fixed with a `MIN_ASSERTIONS` floor — **a floor, not equality**. `-eq` turns every legitimately
added assertion into a spurious failure, which trains people to edit the number without
reading it.

**(b) The floor does not close it either, and the battery certified that too.** Neutering
`fail()` **alone** leaves `PASS` at its full count while the gate becomes permanently incapable
of emitting a drift verdict. And `run_mutation` accepted **any `rc != 0`** as "detected", so it
reported **12/12** with every line `rc=2` and none `rc=10` — over a file whose header insists 2
(detector failure) and 10 (drift) must never be conflated.

Fixes, both needed:
- the battery asserts the **expected rc** plus a per-check **marker**, so a label becomes an
  assertion rather than a `printf` argument;
- the gate carries a **positive control** that calls `pass()` and `fail()` once and verifies
  both counters moved, before any verdict is trusted. A count cannot detect a dead counter
  from the inside.

**Rule.** When a PR arrives carrying its own green mutation matrix, that is evidence about the
mutations its author imagined. Audit the **axes** it never touches — the dispatch layer, the
guarded set's cardinality, the harness itself — not the count it reports.

---

## 3. A coherence gate is not a staleness gate

Every check in the new gate compared artifacts to each other: pin form, cross-arch version
agreement, digest distinctness, sidecar↔pin equality. **A coherent downgrade of every file
back to v2.1.2 — the exact 18-releases-stale state the PR existed to escape — was green**,
because coherence is preserved by a downgrade.

The one age signal read a human-typed capture date that the sidecar's own Refresh recipe
sanctions re-stamping, so re-stamping every 89 days kept a stale pin green forever. The sidecar
declared a hard floor (*"Do not fall back below v2.1.19"*) and **nothing read it**.

**Rule.** For any gate named after a property, ask which of its assertions actually measures
that property rather than internal agreement. Then write the mutation that satisfies every
coherence check while violating the named one.

---

## 4. When a claim spans two artifacts that can be wrong TOGETHER, ask what binds either to reality

The gate's checks bound each digest to its own arch, and the header spent eighteen lines
explaining why that was "the entire point". It closes a swap in **one** file relative to the
other. Transpose the digests in the `.tf` **and** the sidecar and everything passes — form,
version coherence, distinctness, per-arch sidecar↔pin equality — because **nothing in the
committed file set binds a digest to an arch**.

That is not a contrived input. The sidecar's own `## Bump procedure` step 2 says update both
*together*, so one paste session produces exactly this.

Closed over the network, where it is decidable: `zot-linux-amd64` and `zot-linux-arm64` are
**distinct OCI repositories**, so a manifest digest resolves only within its own. Measured
anonymously against ghcr.io — correct pairing **HTTP 200**, swapped **HTTP 404**. The probe
lives in the poll step (which already has network); the offline gate stays network-free and its
header now states the boundary instead of overclaiming.

**The confidence was the mechanism of the miss.** The eighteen-line rationale is exactly what
stopped anyone writing the two-file mutation — the battery mutated the two digests *because
the comment pointed at them*.

---

## 5. Three comments stated a failure mechanism that measurement refuted — in a PR about false comments

They claimed a swapped digest boots the wrong-arch binary and `exec format error`s. Measured:
the pull **404s `MANIFEST_UNKNOWN`**, no container is ever created, and the host reports
`zot_image_digest=unknown state_status=unknown`.

Same outage, different on-host signature — and **the signature is what an operator greps for**,
so the wrong mechanism sends them hunting telemetry that will never appear.

---

## 6. Telemetry that ships INSIDE `user_data` cannot report the pre-apply state

The new `zot_image_digest` field was justified as making the staged-vs-applied divergence
visible. It cannot: the field ships inside `user_data` alongside the pin, so it **arrives with
the host replace** — the same event that applies the pin.

Proven rather than argued: `zot_uptime_s` and `zot_last_err_src` landed on `main` a day earlier
through the identical `write_files` path, and the live Better Stack rows contain neither. The
running host is two `user_data` generations behind.

The field is still worth having — post-apply it identifies the running binary and discriminates
crash-loop causes — but the plan's *expected pre-apply output*, and the risk row resting on it,
were void by construction. An empty query result is now documented as the **expected**
pre-apply observation, distinguished from "host dark" and "telemetry broken".

---

## 7. A grep aimed at LIVE claims keeps colliding with TRUE statements about the past

Three instances in one PR:

- **AC8** widened to `zot-registry.tf:[0-9]+` repo-wide would have failed on a post-mortem and
  a learning file whose statements are true *as history* — and the pressure to green it would
  have driven rewriting a post-mortem titled *"a false comment shipped the bug then plan, guard,
  ADR and tests each restated it"*.
- **AC11** tripped on my own correction note, which *quotes* the stale literals to record what
  changed.
- **check 7** anchored on a bare `zot vX.Y.Z` and reported all-clear while `ci-deploy.test.sh`
  carried the **parenthesized** `pinned zot (v2.1.2)` — a live instance of the exact defect it
  was written for.

**Rule.** The fix is never to delete the history or widen the carve-out. Anchor on something
only a live claim can produce: an assignment (`^\s*name\s*=`), a call shape, a current-state
parenthetical. History may name the old values; the live claim may not.

---

## 8. Naming a harness to avoid CI auto-globbing routes around a merge-blocking gate

The mutation battery was named `zot-image-staleness.mutation.sh` "so it does not auto-glob into
CI runners". That is backwards here: five of five sibling bash batteries are
`*-mutation.test.sh` **and registered**, the one `.mutation.py` precedent is Python (where the
*extension* is the mechanism, not the name), and `test-infra-suite-registration.sh` makes
registration merge-blocking while its own header states that auto-globbing is the feature —
*"a harness in THIS directory is auto-globbed and therefore cannot be orphaned."*

Under the old name no gate could see the file, no runner enumerated it, and no orphan reporter
would ever have named it. Renamed and registered.

**And when a gate refuses your accommodation, that is usually the gate working.** Registering
the byte-budget check with `continue-on-error:` inside `deploy-script-tests` was rejected by the
registration gate, correctly — there, registration must imply execution. The answer was a
separate job, not deleting the objection.

---

## 9. Process: what the panel bought, and why the author could not have found it

Eight agents, ~18 blocking findings, all fixed inline, zero filed as scope-out. Cross-confirmed:
two agents found the unpinned arch selector independently, two found the coordinated swap.

The findings the author could *not* have reached alone share a shape: they required either
(a) running the real thing (the GHCR 404, the live Better Stack rows, the coherent-downgrade
mutation), or (b) disbelieving a sentence the author had written to explain why something was
safe. Every "the entire point of these checks" comment was a place a reviewer had to push back
on the reasoning rather than verify the code under it.

**Practical takeaways for the next review-spawn prompt:**
- Tell `test-design-reviewer` to find the vacuity the battery **missed** — never to re-run its
  mutations.
- Name the enumeration explicitly (the union members, the set the claim quantifies over), or
  agents echo the author's single-value framing back as a pass.
- Ask per guard: *name an implementation a reasonable engineer might write next that satisfies
  this assertion while violating the property.*

---

## Session Errors

1. **The planning subagent terminated on an API weekly limit** mid-run, never emitting its
   Session Summary, and no `session-state.md` was written.
   **Recovery:** the skill's partial-artifact recovery path — the plan body was on disk, so
   work resumed from it rather than re-running plan from scratch.
   **Prevention:** the recovery path worked as designed; no change proposed.

2. **`deepen-plan` never ran.** The recovery jumped from the partial plan artifact straight to
   `/work`, and the omission was not stated until a resumed subagent surfaced it hours later.
   **Recovery:** the plan was subsequently reviewed by eight agents, which is stronger coverage
   than deepen-plan provides.
   **Prevention:** when the plan phase is recovered from a partial artifact, explicitly
   enumerate which mandated sub-steps did **not** run, in the same message that reports the
   recovery — a skipped step that is never named cannot be re-decided.

3. **A P0 false premise reached a shipped plan draft** (Renovate installed). See §1.
   **Prevention:** §1's rule — prove execution, not configuration.

4. **`actionlint` and `shellcheck` were first reported "clean" from `head`'s exit status**, not
   the tool's; the binary had also been reaped from `/tmp` between uses, so one run did not
   execute at all.
   **Recovery:** re-ran with explicit `out=$(...); rc=$?` capture.
   **Prevention:** never read a tool's verdict through a pipe into `head`/`tail`; capture the
   command's own rc and print it. This is the documented `EXIT=$rc` discipline applied to lint
   tools rather than test runners.

5. **An exit-gate red was initially assumed pre-existing** because "my diff touches no inngest
   file" — which was true and insufficient. The file was byte-identical to `main` and the
   failure was still mine: a new *non-test* file carried a heartbeat-URL literal the guard
   forbids anywhere under `infra/`.
   **Recovery:** proved causation by moving the file aside (rc=0) and restoring it (rc=1).
   **Prevention:** "my diff does not touch that file" is not a causation argument when the
   guard scans a *directory*. Prove it by removal.

6. **I printed a check for "does the suite read any file I changed", it listed two files, and I
   appended a line asserting nothing was listed.** The conclusion survived scrutiny (both were
   prose, not reads) but was written before reading the output.
   **Prevention:** a check is only worth running if its output is allowed to change the
   conclusion. Read it before writing the summary sentence.

7. **AC7's bound was set at ≤120 B before measuring**; the measurement returned 136 B.
   **Recovery:** the bound was corrected to the measurement *and the correction recorded*,
   rather than the measurement being trimmed to fit.
   **Prevention:** a bound quietly relaxed to match its own result is not a bound. State it
   from the measurement, or record the widening explicitly.

8. **AC8 asserted "today this returns exactly one hit"; it returns nine.** See §7.
   **Recovery:** re-scoped to the files this PR edits; the eight pre-existing citations in
   untouched files are surfaced in the PR body rather than swept in.
   **Prevention:** when WIDENING an assertion's pattern, re-run it before writing the
   sentence that says what it returns. The widening and the count claim were written in the
   same edit, and only the pattern was thought about.

9. **A resumed subagent misattributed the entire implementation** to review agents acting
   outside a plan-only scope, reported a breach that never happened, and **committed that claim
   to `tasks.md`**.
   **Recovery:** verified against `git log`, corrected the note in place, deleted the
   local-only tag whose message asserted the same thing.
   **Prevention:** treat a resumed agent's account of history as a **claim to verify against
   `git log`**, not as testimony. An agent whose context predates the current state can only
   infer what happened while it was gone, and a plausible inference committed to a file is
   indistinguishable from a fact to the next reader.

10. **Mechanical one-offs**, each caught immediately and fixed: two `sed` delimiter collisions
    (`|` inside the pattern), a YAML block scalar broken by a closing quote at column 0,
    `$A[[:space:]]` parsed as array expansion (SC1087), a `needs.detect-changes.outputs.infra`
    property that does not exist, and a first-draft mutation that tested a harmless case rather
    than a defect-revealing one.
    **Prevention:** none proposed — these are the normal cost of writing shell and YAML, and
    every one was caught by the tool that exists to catch it.

11. **A pre-existing flake was discovered** while verifying: `git-data-runcmd-rehearsal.test.sh`
    T5's mutation arm depends on a real network download, so a slow download aborts the chain
    before `chmod` and the guard reports itself vacuous. Measured 4 pass / 2 fail across 6 runs
    on this branch vs 44/44 on a clean `origin/main` checkout.
    **Recovery:** confirmed pre-existing before dismissing; filed **#7291**.
    **Prevention:** it fails *safe*, which is right — but a required check that depends on a
    third-party download will keep reddening unrelated PRs.

## Related

- ADR-096 "Pin freshness" amendment — the decision of record
- #7287 — the blocked production apply (ordered path, recut before host-replace)
- #7288 — the repo-wide rotation gap the inert config was hiding
- #7291 — the network-dependent flake found while verifying
- `2026-07-29-my-guard-tested-the-one-case-that-cannot-happen-in-production.md` (superseded in
  part by §1 — its Renovate mechanism never existed here)
- `2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md`
