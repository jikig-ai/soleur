---
title: Plugin identity is the commit SHA, and distribution is a dedicated marketplace repo
status: active
date: 2026-08-12
amends: ADR-017
related_adrs: [ADR-017, ADR-178]
---

# ADR-182: Keyless manifests, and a dedicated marketplace source

## Context

The plugin's delivery path could not deliver. Both defects were measured on a real install, not
inferred (#7471); the full readings live in
`knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/measurements.md` and are
cited here by section rather than restated.

**Defect 1 — the updater no-ops and reports success.** `plugin.json` and the marketplace entry both
carried a frozen `0.0.0-dev` sentinel, per ADR-017. `claude plugin update soleur@soleur` printed
`✔ soleur is already at the latest version (0.0.0-dev)` and exited **0**, leaving a cache three
months stale — 64 skills against 96 at source, and `scripts/lib/session-state.sh` absent entirely.
An operator following the documented upgrade path got a green checkmark and no new code. That is
the worst shape of failure available, because it is indistinguishable from success.

**Defect 2 — the marketplace refresh cannot complete, and destroys the checkout when it fails.**
`claude plugin marketplace add jikig-ai/soleur` clones the whole monorepo. Measured at **329 s**
(§1.6/2B.6) against the CLI's default 120,000 ms timeout — **~2.7× over**, so the failure is
deterministic rather than flaky. On failure the updater moves the existing checkout to `.bak`,
starts a fresh clone, and on timeout leaves `~/.claude/plugins/marketplaces/soleur/` holding only a
`.git` with one object and no HEAD; a later invocation removes the directory and the `.bak` with it.

> **Corrected 2026-08-12 (#7489).** The paragraph above is kept verbatim rather than rewritten,
> because deleting it would destroy the datum the correction is about. It is right on cost and wrong
> on mechanism, and the destruction half is now un-reproduced. Readings in
> `knowledge-base/project/specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/measurements.md`.
>
> - **The steady-state refresh is an incremental `git pull`, not a clone.** The marketplace
>   checkout's reflog on the live operator install records one clone followed by repeated
>   `Fast-forward` pulls. So `clones the whole monorepo` describes the ADD path, not every refresh.
> - **The 181 MiB / 329 s figures stand where they were measured** — the initial
>   `marketplace add`, and the re-clone the CLI falls back to when a refresh cannot reconcile in
>   place. Applying `--sparse` to an EXISTING checkout is one such trigger, measured three ways
>   (planted sentinel gone, `.git` inode changed, `sparse-checkout` file appeared; arm 6). On the
>   monorepo that forced re-clone is the 329 s operation, which cannot finish under the 120 s
>   default. A FRESH add with `--sparse` is unaffected and fast.
> - **The destruction half is NOT REPRODUCED on CLI 2.1.228.** Three independent forced-failure
>   instruments each left the checkout and a planted sentinel intact and produced no `.bak` (arm 5).
>   The `.bak` rename and the paired `rm` exist as strings in the 2.1.228 bundle, but a string is not
>   a behaviour, and the branch never executed. The claim is recorded as un-reproduced on this
>   version rather than withdrawn — the asymmetry favours keeping the warning. Operator-facing
>   consequence: the runbook, `## Symptom 2`.

Defect 1 meant installed users silently ran without the lock/lease layer ADR-178 ships. Defect 2
meant **no** plugin fix reached them by the documented path, and every future fix inherited it.

## Decision

**1. No plugin manifest carries a `version` key.** Not `plugins/soleur/.claude-plugin/plugin.json`,
not `.claude-plugin/marketplace.json`'s `plugins[0]`, not the published distribution manifest.
(`marketplace.json`'s *top-level* `version` is the manifest-format version and stays — different
field, different meaning.)

The mechanism, measured in a controlled two-arm experiment (§1.9): `claude plugin update` compares
**version strings**. With no key, the CLI records the plugin's **commit SHA** as its version, so the
string changes with every commit and the comparison detects the update. With a constant key the
string never changes, the comparison always comes back equal, and the update short-circuits.

**2. Distribution moves to a dedicated additive marketplace repo, `jikig-ai/soleur-marketplace`.**
Public, three files, ~39 KB. Its single plugin entry uses a `git-subdir` source pointing at
`plugins/soleur` in the monorepo, so an install materialises the plugin subtree alone. Measured on
the published repo (§2B): `marketplace add` **13 s**, `install` **33 s**, **9.66 MiB** total,
against a 50 MiB fail-closed threshold and the 181 MiB full clone.

The entry is deliberately **unpinned** — no `ref`, no `sha` — diverging from the 42crunch and adobe
entries in `claude-plugins-official`, which pin both. A constant pin is a frozen sentinel wearing
different clothes, and it would reintroduce defect 1 by a different route.

**3. The repo is Terraform-managed in the existing `infra/github/` root**, adopted by an idempotent
first-apply import alongside the existing ruleset imports. It is not managed by `gh repo create`
after bootstrap, and not by `provision-github` (which provisions *tenants*: DPA gate, deployment
reviewers, App consent install — none of which apply).

**4. Release and distribution are decoupled.** A release publishes nothing to the marketplace repo.
Because the entry is keyless, its manifest is release-invariant: it changes only on a deliberate
shape change.

**5. `jikig-ai/soleur` remains a valid marketplace, de-advertised rather than retired.** Existing
installs keep working; the documented install path points at the new source, with the monorepo path
demoted behind a disclosure carrying the timeout mitigation.

**Disposition, 2026-08-12 (#7489).** `scripts/plugin-legacy-resolver-probe.sh` found exactly one
install still resolving to `jikig-ai/soleur` — project-scoped to a repository other than this one —
and two registrations, both carrying `autoUpdate: true`. The arm taken was **migrate that install
onto the published channel**, run from its own `projectPath` with `--scope project`.

**Taken under the ATTACHED branch**, and the branch is recorded because it determines who decided.
The session ran in the main agent loop with an operator present rather than inside a subagent, so
the question was put once and answered by the operator. Because the install was project-scoped to a
*different* repository, migrating it changes another project's tooling — that is a judgment call,
not a chore, and executing it unasked would have been the wrong default. Had the run been headless
the arm executed would have been **C** (write nothing), with the question and Phase 2's verdicts
appended to `decision-challenges.md` for the operator instead. The two arms that were offered
alongside A carried their measurement status with them: arm B was presented with an explicit
`unverified` label on both mechanisms it depends on, rather than as an equal option. What was
**accepted**, and is the other half of this decision, is that the monorepo marketplace entry stays
live and published (see the rejected retire-the-entry alternative below for why removing it buys
nothing). The probe now returns `clean` — 0 registrations, 0 installs, 0 unresolvable installs — so
#7489's stronger closing condition is met by measurement rather than by decision. `clean` is a
statement about the machines probed; the beta population is one machine, and that coincidence stops
holding the moment it grows.

**6. The published distribution path gets a SECOND control: a delivery canary that asserts delivered
CONTENT.** The drift check above reads the **pointer**; the canary reads what an installer actually
receives. It installs `soleur@soleur-marketplace` into a scratch `HOME` on a CI runner and makes
three independent assertions — **completeness** (the delivered file list compared as a *set* against
what `main` serves under `plugins/soleur`, with an explicit cardinality assertion, because the
historical defect was under-delivery at 64 skills against 96 and a subset comparison cannot see it),
**integrity** (per-file digest against the repository's own tree at the commit the install resolved,
materialised with `git archive` from the checkout the job already holds), and **freshness** (the
delivered commit equals `main` HEAD, no tolerance window).

The integrity transport was chosen by measurement, after two alternatives were tried and rejected in
that order: per-file fetches from `raw.githubusercontent.com` (~890 sequential requests — unfinished
after 30 minutes against a 15-minute job budget, with intermittent failures on files that return 200
in isolation), then a whole-repo `codeload` tarball (timed out at 300 s having received 28 MB of
~181 MiB). `git archive` needs no network at all and completes the full comparison in **117 s**,
measured green at `compared=896 expected=896`. The tradeoff is stated rather than buried: the
reference is now the repository's git objects rather than what a CDN serves for the same commit.
Those cannot differ in content — a commit sha is a content address — and the delivery path under
watch is the CLI's clone, which reads git too. What is no longer covered is a CDN serving something
other than git for a given sha, which was never this guard's threat model. No
metadata field participates in any verdict: `claude plugin list --json` is a **projection** of
`installed_plugins.json` — verified by mutating that file and watching the CLI output change verbatim
— so reading the CLI does not escape the metadata. `installPath` is consumed as a location and
`gitCommitSha` only as the reference pin.

This is **not** a refinement of Decision 5, which is about the legacy monorepo entry. It changes the
**control topology** of the published path: until now a single daily two-`curl` manifest check was the
entire control surface, and it can pass in full while every install receives nothing — which is
defect 1's exact shape, a green signal over an undelivered tree. Its shape is a **second job** in the
existing `scheduled-marketplace-drift.yml`, publishing findings as job outputs, with the issue-filing
step and the Sentry heartbeat both extended to consider its verdict (as written, both gated on the
manifest step alone, so a canary-only failure would have filed nothing and checked in `ok`).

**Accepted risk of Decision 6.** The canary downloads a Claude Code CLI and materialises executable
plugin content inside a workflow that also holds `issues: write`. That is a real widening of what runs
in a token-bearing workflow, and the workflow header's "pure GH op … reads two public URLs
unauthenticated" characterisation does not survive it. The mitigation is topological rather than
procedural: the canary job carries `permissions: contents: read` only and consumes no secrets
(measured — `marketplace add` and `install` both succeed with `ANTHROPIC_API_KEY`,
`ANTHROPIC_AUTH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN` all unset), while the write-capable filing step
stays in the sibling job and consumes the canary's verdict through **job outputs** rather than sharing
its process.

**Bearing on the posture tracked at #7493.** That issue's alternatives frame the space as **detection
versus prevention**, and its two deferred options — Terraform owning the manifest's contents, and a
push ruleset on the marketplace repo — are the prevention. The canary is a second **detection**
control, on a different signal (delivered bytes, not the pointer), so it removes the case where the
pointer is correct and the delivery is not. It does **not** convert detection into prevention:
nothing here stops an unreviewed edit, it only makes a wider class of them observable within a day.
#7493 stays open on its own terms.

## Consequences

**Delivery works, measured on the shipped article rather than a fixture.** Both the falsification
gate (§1.0) and the published-repo run (§2B) are recorded, and task 6.5 re-runs the threshold after
merge — a fixture passing while the published thing fails is precisely the gap this ADR closes.

**Minimisation is retired by construction, not by argument.** The subtree boundary was verified as a
boundary rather than a size coincidence (§1.0): `knowledge-base/` and `scripts/` exist at both
levels, so file counts were compared directly (16/16/9,045 and 15/15/292). The Art. 30 register and
the counsel-review memoranda live under repo-root `knowledge-base/` and are no longer delivered to
every installer. **Not retired:** anyone still on the monorepo entry, whose `autoUpdate: true`
cannot be revoked remotely.

**The published manifest is unreviewable by construction.** The marketplace repo has no CI, no
review, and no CODEOWNERS. `scheduled-marketplace-drift.yml` carries its controls — a daily
unauthenticated check asserting the entry stays keyless, that `source.path`/`source.url` still name
`plugins/soleur` in `jikig-ai/soleur`, and that the plugin manifest still resolves at `main` (which
catches a monorepo reorganisation, the one drift event the marketplace repo cannot observe about
itself), plus the delivery canary of Decision 6, which asserts what an install actually receives
rather than what the manifest claims. Detection latency is up to 24 h on both.

**Two marketplaces, two caches, one documented migration.** The plugin id changes to
`soleur@soleur-marketplace` for new installs. The migration sequence deliberately contains no
`marketplace add jikig-ai/soleur` step, which is what makes it usable *from* the broken state; it
was rehearsed end to end (§1.6/2B.6) and all four commands succeed under the default timeout.
`uninstall` and `marketplace remove` leave ~9.6 MiB of orphaned plugin cache with no CLI verb to
reclaim it — the same class as the 374 MiB `soleur.bak` orphan the issue reported. And because the
cache directory is named for the resolved version, which is now a commit SHA, **each update
materialises a NEW directory and leaves the previous one behind** (measurements.md §1.2/1.3 records
`0.0.0-dev` surviving the migration). So the orphan is per-update, not one-time. §1.2/1.3 did not
measure the steady-state footprint, so the growth rate is implied rather than quantified; it is
recorded here as a known cost rather than discovered later.

> **Corrected 2026-08-12 (#7489), on the migration actually performed.** Two figures above are
> narrower than the reading. `marketplace remove` reclaimed the **378 MiB checkout itself** — only
> the plugin cache was orphaned — and that orphan measured **26 MiB**, not ~9.6 MiB, because two
> version directories had accumulated, which is the per-update growth this paragraph predicted
> observed once. Reclaim procedure: the runbook's `## Symptom 2`, print-then-delete.

**Version metadata leaves the plugin's own record.** `installed_plugins.json` reports the commit SHA
in place of a semantic version. Release tags remain the human-facing version via GitHub Releases.

**A third manifest exists outside this repo**, reachable by no CI check here except the drift job.

**Accepted trade, stated because it is a real reduction in review coverage.** Three
`claude-code-action` workflows that ship into users' generated CI — `operator-digest`, both
`schedule` templates — plus this repo's own `test-pretooluse-hooks` now install the plugin via
`soleur-marketplace`. Those workflows carry `ANTHROPIC_API_KEY`, a `GITHUB_TOKEN` with
`issues: write`, and the plugin they install ships executable hooks and skills. `jikig-ai/soleur` is
protected by the `ci_required` and `cla_required` rulesets managed in `infra/github/`;
`soleur-marketplace` is protected by nothing but Terraform ownership of its *settings*. The
mitigating facts: the marketplace repo holds only a **pointer** — the executable code still comes
from `jikig-ai/soleur` through the `git-subdir` source, which is protected — and the drift job now
asserts the pointer's url, source type, pin-absence, entry count and entry name, so a repoint is
detected within 24 h. Detection is not prevention, and the two alternatives above are the
prevention. Until one of them lands, this is an accepted risk rather than an unnoticed one — tracked at #7493.

## Alternatives considered

- **Publish a real version per release, instead of removing the key.** Rejected: it puts a
  cross-repo write on the release critical path, creating a half-shipped-release failure mode where
  the tag exists but delivery is stale. Removing the key makes the manifest release-invariant and
  deletes the failure mode rather than monitoring it.
- **Raise the clone timeout only.** Rejected as a fix, retained as a stopgap: it makes a 329 s clone
  survivable but leaves every install paying it, including the GitHub Actions runners in users'
  generated workflows, on every scheduled run.
- **Replace `jikig-ai/soleur` as the marketplace.** Rejected — that breaks every existing install.
  The additive shape was the point of the challenge that produced this decision.
- **A new dedicated Terraform root.** Rejected: duplicates a backend, provider, auth path, and apply
  pipeline that `infra/github/` already has, and would trigger the new-root R2 backend rule.
- **Terraform owning the manifest's CONTENTS via `github_repository_file`.** Not rejected on
  merit — deferred, and recorded here because a future reader would otherwise assume it was never
  considered. It is the one option that converts detection into prevention: the manifest would live
  in this monorepo under review, CODEOWNERS and required checks, and drift would be auto-reconciled
  by the next apply instead of surfacing as an issue up to 24 h later. It does not reintroduce
  release-path coupling, because the write lives in `apply-github-infra.yml` rather than the release
  path. Costs: the App needs `contents: write` on that repo, and a Terraform-managed file on a
  default branch interacts with branch protection. Tracked as follow-up work rather than shipped
  untested inside a delivery fix.

  > **SHIPPED 2026-08-12 (#7493)**, with one clause of the above CORRECTED rather than carried
  > forward. Both stated costs cleared against the live API: the `soleur-ai` App holds
  > `contents: write` at `repository_selection: all`, and the branch-protection interaction is
  > resolved by declaring the App an `Integration` bypass actor — so its write is the *reviewed*
  > path, since the content originates in this monorepo behind CI and CODEOWNERS.
  >
  > **The correction: "drift would be auto-reconciled by the next apply" was false as written.**
  > `apply-github-infra.yml` carries no `schedule:` — it fires on `push: main` touching
  > `infra/github/*.tf`, `infra/github/.terraform.lock.hcl`, `infra/github/soleur-marketplace-manifest.json`
  > (added by #7493 — the `*.tf` glob does not match a `.json` sibling) or the destroy-guard
  > filter, plus `workflow_dispatch`. "The next apply" could therefore be weeks away, so this option as
  > described bought *ownership without timeliness*, and the daily drift check remained the faster
  > signal. #7493 makes the claim true by shipping the reconcile arm below rather than by
  > restating it.
  >
  > A cost this entry did not anticipate: `github_repository_file` has no `keep_on_destroy`, so
  > destroying it DELETES the published manifest. `archive_on_destroy` on the repository does not
  > cover a file inside it.
  >
  > A gap it also did not anticipate: putting the manifest under Terraform makes a bad SOURCE
  > publishable, and — once the reconcile arm exists — *republishable daily* while a
  > published-vs-source byte-diff reports in-sync. #7493 therefore also ships
  > `marketplace-manifest-guard`, an always-run blocking check on the source file. Ownership
  > without a pre-merge gate would have been a downgrade.
- **A `github_repository_ruleset` restricting pushes to the marketplace repo.** Same disposition and
  the same reason. It would be the direct answer to the review finding below, and it is cheap —
  `infra/github/` already manages two rulesets. It is deferred because an untested ruleset shipped
  inside this PR could either break the unattended apply pipeline or lock the sole maintainer out of
  the repo, and neither failure is one this change should risk.

  > **SHIPPED 2026-08-12 (#7493).** The lock-out risk was the real one, and it was settled by
  > MEASUREMENT on a disposable repo rather than by reasoning — two reviewers reached opposite
  > conclusions from the same documentation.
  >
  > Measured: a `pull_request` rule with `required_approving_review_count = 1` and the human bypass
  > actors in `bypass_mode = "pull_request"` REFUSED the sole maintainer's own merge
  > (`reviewDecision: REVIEW_REQUIRED`, *"the base branch policy prohibits the merge"*), leaving
  > only an `--admin` override. Moving those actors to `bypass_mode = "always"` restores direct
  > push, which is what preserves the emergency path on the repo a broken install is fixed
  > *through*. That deviates from the two sibling rulesets and the deviation is deliberate.
  >
  > The approval count is not optional: `required_approving_review_count` has no schema default at
  > provider 6.12.1, so omitting it yields 0 — and `claude` and `entire` hold `pull_requests: write`
  > alongside `contents: write`, so a zero-approval PR requirement does not close their write paths
  > at all. A first implementation shipped exactly that and claimed otherwise.
  >
  > Honest scope: this raises the bar from one App acting alone to two Apps colluding. Fully closing
  > that residual requires narrowing the `claude` / `entire` installations to selected repositories,
  > which is tracked separately. `deletion` and `non_fast_forward` are the unconditional part.
- **Hand-maintained manifest with no drift check.** Rejected: the artifact is unreviewable and its
  silent-failure detector would otherwise be "a new user tries to install and it fails", which at a
  beta population of one may not fire for weeks.
- **Retire the `jikig-ai/soleur` marketplace entry** — delete or empty its
  `.claude-plugin/marketplace.json` so the legacy channel stops resolving (Decision 5's other arm).
  Rejected on a measured reason rather than a preference: **the marketplace checkout is cloned before
  the manifest is read**, so removing the manifest reduces nobody's clone cost. A stranded install
  still pays the same 181 MiB / 329 s and then finds no entry at the end of it — strictly worse than
  finding one. Retiring would only block NEW installs on the slow path, and the READMEs already
  de-advertise that path behind a disclosure. It buys nothing for the population it would aim at, and
  breaks the population Decision 5 exists to protect.

Alternatives for **Decision 6** (the delivery canary), kept separate because they are about the
control topology of the published path rather than about the manifest:

- **Extra steps inside the existing `check` step or job.** Not implementable rather than merely
  worse: `findings=()` and `sanitize()` are shell locals of that step's `run:` block and do not
  survive a step boundary, and `scripts/marketplace-drift-check.test.sh` extracts that step by id and
  executes it hermetically with no network — canary logic placed there would run in that suite with
  no `claude` binary present.
- **A whole new workflow.** Rejected: the existing file already carries the cron, the
  `sentry-heartbeat` check-in, the issue file/close loop and the serialised concurrency group. A new
  file would move `c4-count-parity.test.sh`'s workflow counts, need a new `sentry_cron_monitor`, and
  need a full-root `apply-sentry-infra.yml` apply. A second **job** in the existing file is
  count-neutral — those counters count workflow *files* and distinct slug values — and was verified
  as such.
- **Scheduling `test-pretooluse-hooks.yml`, which already installs the published plugin.** The
  nearest existing mechanism, and kept as prior art. Rejected because it asserts hook *behaviour*
  rather than delivered content, and it runs through `claude-code-action` with `ANTHROPIC_API_KEY`,
  where the canary was measured to need no credentials at all.
- **A second job — accepted.** It is the only one of the four that gets a different privilege and
  timeout profile from a two-`curl` check while keeping the write-capable filing step out of the
  process that materialises executable content.

## Amends ADR-017

ADR-017 established version-from-git-tags and, in service of it, froze the manifest version fields
at `0.0.0-dev`. **The freezing is superseded; the git-tag sourcing is not.** Versions still come
from tags via `version-bump-and-release.yml`, and feature branches still never bump them. What
changes is that the fields are *absent* rather than *frozen constants* — ADR-017's own mechanism for
avoiding drift turned out to be the mechanism that stopped delivery, because a constant is exactly
what makes the updater's comparison always succeed.

## Rollback

**Not "re-add the key" — and the reason is stronger than it first appears.** For the *pre-fix*
population that edit is undeliverable, because it would have to travel through the broken refresh.
For the population this ADR creates it is worse than undeliverable: an install on
`soleur-marketplace` has a working refresh and its recorded version is a SHA, so re-adding a
`version` key produces a string that differs from the recorded SHA, the comparison fires, and the
update **does** deliver — once. It then records the constant, and every subsequent update compares
equal forever. Re-adding the key is a self-delivering one-way brick, not a no-op; do not read it as
harmless-because-inert.

The real rollback is `remove → re-add → reinstall` against the new marketplace — which Phase 2B
makes cheap: re-adding costs ~39 KB rather than 181 MiB.
