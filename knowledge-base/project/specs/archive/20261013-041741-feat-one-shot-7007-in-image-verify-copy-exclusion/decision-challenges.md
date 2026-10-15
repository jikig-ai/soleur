# Decision challenges — feat-one-shot-7007-in-image-verify-copy-exclusion

Recorded headless during `/soleur:plan` (ADR-084). `/ship` renders these into the PR body and
files an `action-required` issue.

## UC-1 — the fix specified in issue #7007 does not work; the plan deviates from it

**Operator's stated direction (issue #7007 "Proposed fix", repeated verbatim in the pipeline
prompt):**

```bash
( GLOBIGNORE="/src/node_modules:/src/infra/.terraform"; cp -r /src/* /build/; )
```

**Challenge:** this excludes `node_modules` but **not** `infra/.terraform` — the 247 MB directory
the issue names as its motivation. `GLOBIGNORE` filters the expansion of the `/src/*` glob;
`/src/infra/.terraform` is never in that expansion (only `/src/infra` is), and `cp -r` then
recurses into `/src/infra` on its own.

**Evidence (executed in-session, not reasoned):** on a synthetic fixture carrying
`node_modules/`, `infra/.terraform/`, `infra/sentry/.terraform/` and six dotfiles, the snippet
above produced a destination with `node_modules` **absent** and `infra/.terraform` **PRESENT**.
The cited precedent's own comment says the same thing in advance —
`apps/web-platform/infra/credential-persist-home-guard.test.sh` states *"The exclusion is
TOP-LEVEL-ONLY by construction … a nested `sub/.terraform` cannot be expressed here at all
(measured: a `GLOBIGNORE="$1/.terraform:$1/*/.terraform"` still copies the nested one)"*. The
precedent works because in that script the scanned root **is** `infra/`, so `.terraform` is
top-level; here the root is `apps/web-platform` and `.terraform` sits one level down.

**Plan's deviation:** a shared `apps/web-platform/scripts/lib/in-image-copy-src.sh` using
`tar --exclude=./node_modules --exclude=.terraform`, which both helpers call. Verified in the
pinned `node:22-slim` digest against the real tree: both directories excluded (plus the
not-yet-initialised `infra/sentry/.terraform`), all dotfiles and both `.terraform.lock.hcl` files
preserved, `diff -rq` parity clean, `/build` root-owned. Measured in the pinned digest against a
warm tree: **2.6 GB / 99,263 archive members → 30 MB / 2,974** (deterministic, reproduced exactly
on an independent re-run), wall clock ~18–28 s → ~0.25–0.5 s. Stated as a range because the
BEFORE arm's own spread is ~20% of its mean; an earlier "~57×" point estimate was withdrawn at
review as not derivable from the data. The win is LOCAL — both CI jobs are checkout-only, so in
CI the exclusions save nothing and the change is perf-neutral within noise.

**Nothing about the issue's goal changed** — both named directories are excluded, which the
proposed snippet would only half-achieve. Only the mechanism differs.

**Operator decision requested:** none required to proceed; recorded because the plan departs from
a mechanism the issue specified literally. If the `GLOBIGNORE` shape is wanted for consistency
with the sibling suite, say so and it can be re-scoped — but it would need a per-level stage for
`infra/` and another for `infra/sentry/`, and would still not cover a third root added later.

## UC-2 — the plan declines to make CI exercise this change on the paid path

Neither invoking gate's trigger regex names the helper scripts (`ci.yml`, *Detect capture-input
changes* / *Detect propagation-input changes*), so a PR touching only them fires neither gate.
Adding the helpers to those regexes would make this PR self-exercise — at the cost of a paid Haiku
turn on **every** future edit to these files, permanently, to re-prove copy logic the paid gates do
not actually validate (they validate the paid turn). The deepen pass corrected the cost from *two*
turns to **one**: `sdk-bump-sandbox-gate.sh` carries a second, internal `capture_trigger` regex
covering only `agent-runner-sandbox-config.ts`, `sandbox-canary.mjs` and `sandbox-canary-argv.json`,
so widening `ci.yml` alone would start the canary job and leave its capture a no-op — a gate that
structurally cannot fire. That makes the alternative a worse trade than it first appeared, not a
better one.

The plan instead ships a hermetic suite that executes the real copy artifact, plus an unpaid
in-image rehearsal proving whole-tree parity and a successful `npm ci` in the filtered `/build`.
The paid end-to-end path is **not run** and the PR body says so.

**Sharpened at review.** The observability reviewer made a better version of the counter-argument
than the plan had considered: the "canary half is structurally inert" finding argues against adding
**both** regexes, not against adding the **propagation** one. Propagation-only would cost one paid
Haiku turn per future edit to these files and would buy the sole real in-image execution of the
changed path — which is otherwise never exercised in CI at all. The plan's decline was kept because
reversing it unilaterally would override a recorded operator decision, not because the argument is
weak. It is the strongest case for the expansion and the operator should decide against it, not
against the weaker version.

**Operator decision requested:** confirm the trade (unpaid hermetic coverage over recurring paid
CI coverage), or ask for the trigger-set expansion — propagation-gate only, at one paid turn per
future edit to these two helpers plus the shared copy script.
