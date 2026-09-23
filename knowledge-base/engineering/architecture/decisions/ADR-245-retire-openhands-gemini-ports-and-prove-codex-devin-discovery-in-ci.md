---
title: "Retire the OpenHands and Gemini ports; prove Codex and Devin discovery in CI"
status: active
date: 2026-09-23
---

## Context

Soleur ships one plugin tree to four supported harnesses — Claude Code, Grok Build, Codex and Devin — and carried two more as HAND-PORTED mirrors: `.openhands/` (69 tracked files: 63 skill ports, 5 hooks, `hooks.json`) and `.gemini/` (6). Nobody maintained either. They were never advertised in `plugins/soleur/docs/**`, `README.md` or any manifest, and `lib/harness.ts`'s `Harness` union never had a member for either, so no adapter, no routing contract and no gate treated them as live. What they did have was reach into live guards: a parity suite doubled every `.claude` hook assertion against its mirror, `worktree-write-guard.sh` carried an `.openhands/*` write allow, and two ratchet baselines and a `markdown-lint` root set named their paths.

> **Evidence arriving mid-flight, 2026-09-24.** While this PR was in its merge poll, #8631
> ("regenerate a conflicted C4 model in self-hosted repos") landed on `main` and edited BOTH
> `.claude/hooks/pre-merge-rebase.sh` and its `.openhands/hooks/pre-merge-rebase.sh` mirror —
> one improvement, written twice. It surfaced here as a modify/delete conflict against this
> branch's deletion. It is recorded because it is the cost this decision claims, observed
> rather than argued: a contributor with no interest in OpenHands paid a second edit to keep a
> tree nobody runs in step. The `.claude` copy carries the improvement, so retiring the mirror
> loses nothing; what it removes is the obligation to write it twice.

A hand port is a copy that decays silently. #8306 proposed fixing that by proving mirror COMPLETENESS — a census that asserts each port is a faithful copy, with an exemption list for the parts that are not. That reverses the burden: it spends gate budget keeping two unmaintained trees honest.

The second half of this decision is the gap that made the first half worth acting on. ADR-226 §"Per-harness discovery" recorded Codex and Devin as **declared uncovered**, citing #8306 — a mis-citation, since #8306 is about the mirrors. The real state was worse than the citation suggested: `scripts/codex-plugin-smoke.mjs` does call Codex's app-server `skills/list` and does fail on a name Codex did not report, which is genuine discovery — but it runs only by hand, it needs a pre-installed plugin in the operator's `~/.codex`, and it takes its expected set from `skills/` rather than from the manifest's declared roots. Devin had no equivalent at all. So the two harnesses whose ports we KEEP were the two with no standing evidence that they register anything.

## Considered Options

| Option | What it buys | Why not / why |
|---|---|---|
| **Keep the ports, add an assert+exempt census** (#8306 shape 1) | The mirrors stay available and their drift becomes visible | Spends a permanent gate on two trees with no users, no adapter and no advertised support. The exemption list is the tell: it is a standing admission that the copy is not a copy. |
| **Generate the ports from source** (#8306 shape 2) | Removes hand-port drift by construction | Correct shape, wrong time. A generator is only worth building for a harness someone runs; neither has an adapter, so it would generate into a vacuum. |
| **Retire both ports** (CHOSEN) | Deletes the drift surface outright, narrows one write allow, and removes the doubling from the hook parity suites | Loses the option to demo Soleur on either without re-porting. The re-entry criterion below is what keeps that reversible on the right terms. |
| **Leave Codex/Devin discovery uncovered and just fix ADR-226's citation** | Free | The citation was the smaller error. "Declared uncovered" was a decision to stop looking; a harness that silently stops registering skills is invisible to every other gate in the repo. |
| **Promote the existing `codex-plugin-smoke.mjs` to CI** | Reuses working code | It cannot run hermetically (needs `~/.codex` state and a `projectHooks.length !== 2` precondition) and has no Devin arm. Left unchanged as the operator-local installed-plugin + hooks check. |
| **Make the new discovery gate a REQUIRED check now** | Strongest signal | It drives two vendor CLIs over the network on every PR. #8574 owns the soak and the promotion. |

## Decision

**1. The supported harness set is Claude Code, Grok Build, Codex and Devin.** `.openhands/` and `.gemini/` are deleted. `#8306` closes as obsolete: its scope was completeness for trees that no longer exist.

**Re-entry criterion — a hand port is not sufficient.** A harness re-enters the supported set only with (a) a `Harness` union member in `plugins/soleur/lib/harness.ts` and the adapter functions that implies, and (b) a GENERATOR for any per-harness tree. Never another hand-maintained copy. `knowledge-base/engineering/platform-portability-comparison.md` keeps the measurements as a historical record, banner-scoped to this date.

**2. Codex and Devin discovery is proven in CI by `harness-discovery`**, a non-required job that installs the plugin hermetically from the checkout and asks each vendor CLI what it registered.

Its scope, stated so nobody reads more into a green than it carries:

- It proves **registration** — the name is in the harness's skill list.
- It does **not** prove invocability. ADR-236 already records why: `codex exec` ignores `disable-model-invocation`, and `devin skills list` reports `[user]` vs `[user,model]`.
- It does **not** prove **which copy** was loaded. For `go`/`help`/`sync` the shim body differs from the canonical skill, and a single listing cannot distinguish them.
- It proves nothing about **uniqueness**. A newly added `codex/skills/plan/` is legitimately k=2 and passes here by construction. Cross-root collision policy stays with `components.test.ts` (ADR-224 decision 5, `ACKED_CROSS_ROOT_DUPES`).

**3. CI vendor-CLI policy**, binding on any gate that drives a third-party CLI **from this decision forward**. One pre-existing gate does not conform and is named rather than papered over: `grok-fidelity` pipes an unversioned `https://x.ai/cli/install.sh` into `bash` and its `grok --version` line prints a banner nothing compares against — and unlike `harness-discovery` it is a REQUIRED check, so a vendor release can red every PR in the repo with no pin to point at. #8615 tracks the retrofit; this ADR does not claim a universal the tree does not satisfy. The policy:

- **pins an exact version** and asserts the binary reports it, exiting 3 on drift. Measured 2026-09-23: `npm i -g @openai/codex@0.156.1`; Devin's top-level `install.sh` leaves `PINNED_VERSION` empty (latest), but the versioned `https://static.devin.ai/cli/<version>/setup.sh` serves 200 and is the pinned path. The two arms are pinned to different DEPTHS, which the job states rather than eliding: npm resolves `@openai/codex@0.156.1` to immutable published bytes, whereas a version in a URL is a NAME the vendor can re-serve, so the Devin arm adds a `sha256sum -c` content pin on the fetched setup script and refuses to execute a script whose digest moved. Both arms then assert the installed binary reports the pin.
- **treats UNRESOLVED as not-a-pass** (ADR-177). Exit 3 is reserved for a STRUCTURALLY unreadable listing — no `<skills_instructions>` marker, or zero `soleur:` lines. A listing that parsed but is missing names is a measured partial loss and exits 1 naming them; mapping "discovered < N" to exit 3 would report a real regression as "could not check" (AP-021).
- **stays non-required until a soak proves it stable.** #8574 owns promotion and carries the pin-freshness criterion: a monthly comparison against `npm view @openai/codex version` and Devin's current release. The drift is not hypothetical — this plan was written against Codex 0.155.1 and npm was at 0.156.1 a day later.

**Multiplicity is one mode per harness run.** A name declared in *k* roots may be listed once (the harness dedups) or *k* times (it is additive), but not a mixture. Checking "1 or *k*" per name independently passes a listing with `go` twice and `help` once — the loader ambiguity ADR-224 decision 5 exists to detect. Measured: Codex 0.156.1 is additive, Devin 3000.11.1 dedups.

**Two amendments this decision forces elsewhere**, because leaving them would make the repo contradict its own measurement:

- **ADR-224** said "**Devin — measured**: reports `/soleur:go` from `skills/` **and** `devin/skills/`" and "**Codex — inferred, NOT measured**". Both are now stale in opposite directions. Amended there.
- **ADR-226**'s "declared uncovered (#8306)" line loses the mis-citation and gains the accurate status: discovery is covered by an **advisory** job, and becomes enforcing when #8574 closes.

**What is NOT recorded here, deliberately.** The Devin wait primitive — that `get_output` cannot wait on an event, so a merge/deploy watch arms a background `run_subagent` exit-coded loop — is a fact about Devin's TOOLS, not about this decision. It lives in `devin/INSTRUCTIONS.md` with an amendment to **ADR-223** (Devin wire names). The per-gate map (test file → property → usual fix → tracker) lives in `plugins/soleur/test/README.md`: it changes every time a gate is added, and an ADR is not the home for a table with that lifecycle.

## Consequences

**Easier.** One tree to maintain per supported harness, with an adapter behind each. The hook parity suites assert the `.claude` behaviour directly instead of doubling it against a copy. A manifest that drops a declared root, or a harness that silently stops registering skills, now reds a CI job instead of reaching users.

**Harder.** Demoing Soleur on OpenHands or Gemini now costs a generator plus a `Harness` member, not a copy — which is the point, and is the cost the re-entry criterion makes explicit rather than incidental.

**Accepted risks, each with its own falsifier.**

- *Vendor output format drift.* Both parsers read a shape a vendor can change. The gate fails CLOSED on it: no marker and no `soleur:` lines is exit 3 UNRESOLVED, never a pass. The parsers' pure functions are unit-tested offline against synthesized fixtures, so a format change reds the live arm without taking the suite with it.
- *Pin staleness.* An exact pin is stale the day the vendor ships. #8574's monthly comparison is the mitigation and the owner.
- *A non-required job is ignorable.* True until #8574 closes. Stated rather than implied: until then, a red `harness-discovery` blocks no merge.
- *Non-required is not the same as consequence-free, and this was measured the wrong way round first.* "Non-required" governs the MERGE gate — the job is absent from the `test` aggregator's `needs:`. It does NOT govern `workflow_run.conclusion`, and `web-platform-release.yml` is triggered by `workflows: ["CI"]` and refuses to deploy when that conclusion is not `success` (its `ci_not_green` guard). So on a main push, an npm hiccup or a 404 on `static.devin.ai` would have reddened the CI run and SKIPPED that SHA's production deploy: a third-party network flake gating our own releases. `continue-on-error: true` on the job is what actually decouples them — the step still reds visibly on the check list while the run conclusion stays `success`. #8574's promotion MUST remove that line in the same change that makes the job required, because a required check that cannot fail the run is worse than no check.

## Cost Impacts

None. No new paid vendor, no tier change. The job adds roughly two CLI installs and two probes per PR run, inside a 10-minute ceiling with a 90-second cap per CLI call. Both vendor CLIs are free to install and are exercised auth-free — the Codex arm uses an isolated `CODEX_HOME`, and the Devin arm a scratch repo whose `.devin/config.json` declares a local `requiredPlugins` source, which is the path that needs no `devin auth login`.

## NFR Impacts

| NFR | Requirement | Container/Link | Impact |
|---|---|---|---|
| Testing | Automated coverage of the delivered artifact | `github` → `codex`, `github` → `devin` | **Improves.** Two harnesses moved from "declared uncovered" to an advisory per-PR check. Enforcing when #8574 closes. |
| Security | Least privilege on the write surface | `guardrails` container | **Improves, marginally.** `worktree-write-guard.sh` loses its `.openhands/*` allow — a narrowing, never a widening. |
| Observability | A failure is diagnosable from the log it produces | `harness-discovery` job | **Improves.** Every non-zero exit prints a distinct reason (`cli-missing`, `install-failed`, `version-mismatch:<got>!=<pin>`, `unparseable-output`, or a counted set mismatch) plus the first 4 KB of raw vendor output, so no artifact upload is needed. |
| Resilience | A third-party dependency cannot silently degrade the gate | `github` → vendor CLIs | **Risk introduced, bounded.** The job reaches the network on every run. Bounded by the 90-second per-call cap, the 10-minute job ceiling, non-required status, and fail-closed exit 3. |

## Principle Alignment

| Principle | Title | Status | Note |
|---|---|---|---|
| AP-021 | Do not name a cause you did not measure | **Aligned** | The exit taxonomy is the whole application: exit 3 means the listing was structurally unreadable, never "the set looks short". A partial loss is counted and named. |
| AP-025 / ADR-202 | Allowlist over blocklist | **Aligned** | The expected set is DERIVED from the manifest roots rather than listed, so the `go`/`help`/`sync` allowance expires on its own when #8236 deletes a root. No ack list. |
| ADR-236 | Registration is not invocability | **Aligned** | Restated in the scope above rather than quietly widened; the gate claims exactly what ADR-236 permits it to claim. |

## Diagram

`model.c4` gains the supply-chain edges this job creates — `github -> codex` and `github -> devin` ("CI installs a pinned CLI and asserts skill discovery"), alongside the existing `github -> sigstore` and `github -> ghcr` precedents. `github -> platform.grokBuild` is added on the same grounds: the `grok-fidelity` job has installed a vendor CLI over the network since it was written and that edge was never modelled. OpenHands and Gemini were never elements, so the retirement removes nothing from the model; the `guardrails` element's description loses its mirror clause.
