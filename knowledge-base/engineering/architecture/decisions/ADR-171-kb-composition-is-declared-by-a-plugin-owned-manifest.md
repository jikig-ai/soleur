# ADR-171 — Knowledge-base composition is declared by a plugin-owned manifest, and the boundary that forces it also bounds observability

- **Status:** adopting
- **Date:** 2026-08-06
- **Related:** #7332 (PR 1 — the producers this contract describes; PR 2 — the manifest itself);
  #7342 (controller/processor determination — governs claim 3, see 3a)
- **Supersedes:** nothing
- **Issue:** #7332
- **Enforced by:** `plugins/soleur/test/c4-from-components.test.ts` +
  `plugins/soleur/test/kb-coverage.test.ts` (both in the `bun` shard) and
  `plugins/soleur/test/c4-from-components.test.sh` +
  `plugins/soleur/test/domain-model-*.test.sh` (auto-globbed into the `scripts`
  shard by `scripts/test-all.sh`). The manifest's own parity + drift gates land
  with PR 2 and are **not** claimed here.

`status: adopting` is deliberate: PR 1 builds the producers this contract
describes, PR 2 builds the manifest itself. Recording the contract now is what
lets the two be designed once rather than twice.

## Context

Soleur tells a customer what a knowledge base should contain in four places that
do not agree, and it produces only a fraction of it. On the measured baseline
(`2my8r9ry2t-wq/Skouer`) the knowledge base was **23 entries, 100% under
`project/`** — no C4 model, no domain-model register. That is exactly `/soleur:sync`'s
declared output surface, so the gap is a missing-producer gap rather than a
de-duplication one.

The obvious fix — have the web platform and the plugin read one shared
declaration — is not available, and the reason is structural rather than stylistic.

## Decision

**Knowledge-base composition is declared by a manifest the plugin owns**
(`plugins/soleur/kb-blueprint.json`, PR 2), copied byte-identically into
`apps/web-platform/` and consumed through a hand-authored typed module using
`satisfies` — the existing `app/internal/github-app-init/page.tsx` +
`infra/github-app-manifest.json` pattern, which already ships with a parity test
and a drift-guard cron.

Three facts make the alternatives unavailable.

**1. A cross-boundary import is impossible, not merely unprecedented.**
`apps/web-platform/Dockerfile:10` is `COPY . .` with build context
`apps/web-platform` (`.github/workflows/web-platform-release.yml:88`), so
`plugins/` is not in the build context at all. An import from `apps/web-platform/`
into `plugins/` passes `tsc`, passes vitest, and fails only at release build —
the worst possible place to discover it.

**2. A generated TypeScript mirror cannot catch the drift it exists to catch.**
A generated type regenerates to match a renamed field, so `tsc` goes green across
exactly the change the mirror was introduced to detect. The copied JSON plus a
parity test is the mechanism; a generated `.ts` is not.

**3. Two writers share one directory, so generation must be non-destructive.**
`/soleur:architecture` writes `spec.c4` / `model.c4` / `views.c4` cwd-relative
(`plugins/soleur/skills/architecture/SKILL.md`), and the agent sandbox pins
`cwd = workspacePath`. The producer therefore emits a **distinct composing file**
(`generated-components.c4`) and never writes the canonical three names.

Precedence rule: **a hand edit always wins** — but it is enforced by three different
mechanisms, and conflating them is how the first implementation shipped a reporting
gap. `generated-components.c4` is header-guarded (refuses to overwrite a file whose
first line is not the `GENERATED` header). `spec.c4` / `views.c4` / `c4-model.md` are
seeded only when ABSENT via `O_CREAT|O_EXCL`, so an existing one is never touched —
they carry no header, and `c4-model.md` could not (it is markdown). `model.likec4.json`
carries none either (JSON) and is a regenerable lockfile, so it is rendered **off-tree**
and published only when the verdict is not `failed`; replacing it after a successful
render is correct, and replacing it after a failed one destroyed a committed artifact
until #7332's review caught it. Any target that is a symlink is refused outright.

Each refusal is reported in the run marker, and the counters distinguish a refusal
(`skipped=`) from the normal steady state of a seed artifact already existing
(`seeded=`) — collapsing those made every repeat sync read as degraded.

A fourth distinction is worth recording because it is easy to collapse: the
runtime read via `getPluginPath()` (`apps/web-platform/server/plugin-path.ts:42`,
used at `agent-runner.ts:1116`) and a build-time static JSON import solve
different problems at different times. The Docker fact above forecloses the
build-time direction only; it says nothing about the runtime one.

## The observability boundary is a consequence of the composition boundary

Ruled at #7332 Phase 0.2 after measuring the ingest path end to end.

**1. The build-time fact generalizes.** The same boundary that makes a manifest
import impossible means plugin code cannot import Soleur's Sentry client, its
pino logger, or any sink — by construction, not as an accident of packaging.
`plugins/`-side error reporting is therefore a stdout marker, never
`reportSilentFallback` (which lives in `apps/web-platform/server/observability.ts`).

**2. String coupling is a distinct and weaker crossing, and it was still
rejected.** `apps/web-platform/server/git-lock-marker-telemetry.ts` reaches
plugin-emitted sentinels through an exact-match string allowlist (`MARKER_RE`,
`:93`), not an import — so it does **not** contradict claim 1. It is nonetheless a
coupling: a sentinel renamed in `plugins/` silently un-mirrors unless the
allowlist and its drift guard
(`apps/web-platform/test/git-lock-marker-telemetry.test.ts:177-212`, which scrapes
sentinels from only two shell scripts) are updated in lockstep. It is admissible
**only** for sentinels emitted on the hosted surface, where a producer actually
runs. Adding an entry for a sentinel with no hosted producer creates a dead
allowlist line in a file that is read as an inventory of live channels — the
failure `apps/web-platform/infra/vector.toml` names explicitly for
`inngest-boot-phone-home`.

**3. The consent boundary is stricter than the build boundary, and it is the
operative one.**

First, a correction to how #7332 originally reasoned about this, because the
corrected version is the load-bearing one. Phase 0.2 claimed the Better Stack path
was unreachable for "two independent reasons": the exact-sentinel `MARKER_RE`, and
`.claude/settings.json` registering no PostToolUse `Bash` matcher. The second reason
is true of the LOCAL CLI and **false as a claim about this code**. `plugins/soleur/**`
is vendored into the production image and executed there:
`apps/web-platform/server/agent-runner-query-options.ts` loads
`plugins: [{ type: "local", path: trustedPluginPath }]` — default
`/app/shared/plugins/soleur` — and registers `{ matcher: "Bash", hooks:
[createGitLockMarkerHook(…)] }` in the SAME options object, and
`auto-sync-trigger.ts` dispatches `/soleur:sync --headless` through it. So on the
hosted surface exactly ONE thing separates these markers from Better Stack: a regex.

**Layer 7 is therefore a property of the EXECUTION surface, not of the file's
location in the repo.** The same source file is layer 7 when a customer runs it and
layers 1–6 when the platform does.

That makes the consent argument the one doing the work. Soleur's Better Stack sink is
fed by Soleur's own prod container journald (`vector.toml`
`[sources.app_container_journald]` → `[sinks.betterstack]`). Code executing on a
customer's self-hosted CLI has no route to it, and must not be given one. Any future
hosted-quality telemetry for self-hosted runs must be **customer-owned** (a sink
configured under the customer's own account) and opt-in — never a Soleur-owned default.

**3a. Reconciled against the controller/processor determination (#7342), which
landed on `main` after this ADR was drafted.** An earlier revision of claim 3 asserted,
freestanding, that such shipping "makes Soleur a data controller for data it never
disclosed collecting." That conclusion **survives** — but it is no longer this ADR's
to assert, and its unqualified form was imprecise. The authority is
`knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md`,
whose §2 machine/key/purpose test governs:

- Purpose is what selects the posture. A Soleur-owned sink serving **Soleur's** purpose
  is **Posture C — CONTROLLER** (Art. 4(7); Art. 28(10)), requiring an LIA, an Art. 6
  basis, and an **Art. 14** notice route. §1 limb (ii) records a live instance that is
  this case almost verbatim: reading a tester's `knowledge-base/` git tree "to measure
  knowledge-base growth as a **Jikigai** product metric."
- The **credential limb is the one the original phrasing missed.** §2 enters **Posture B
  — PROCESSOR** (Art. 28(3) instrument required *before* processing) the moment tester
  content reaches a Jikigai machine, credential, **or account** — and it "fires without
  anyone noticing, because no file moves." A Better Stack ingest token shipped inside
  `plugins/soleur/**` is exactly that credential. So a Soleur-owned default sink leaves
  **Posture A** — the only posture requiring no instrument, and the only one the
  published documentation describes — regardless of purpose.

**The refuted second reason is replaced by an independent one, so this decision is
again carried by more than the consent argument alone.** The determination's §4 egress
evidence rests on a claim it recorded as falsifiable in one grep over `plugins/soleur/`:
"**no automatic or background telemetry; all egress is explicitly operator-invoked**."
That sentence is what keeps §4(a)'s finding — "the published position remains TRUE
within its scope" — standing for `docs/legal/data-protection-disclosure.md`,
`gdpr-policy.md`, and `privacy-policy.md`. A Soleur-owned default telemetry sink in
`plugins/soleur/**` would be an unattended, non-operator-invoked egress path and would
**falsify that published claim directly**. Layer 7 therefore now protects a documented
compliance position, not only a consent argument.

**Two limits, recorded rather than glossed.** (i) The determination is
`status: draft-requires-counsel-review` with disposition **BLOCKED** pending its §11 —
it is founder-grade internal sign-off, not external advice, so this ADR cites it as the
governing internal determination and not as settled law. (ii) Its C9 requires the
determination be re-run *before* a second alpha tester is onboarded; if it is re-run and
the postures move, claim 3a is stale and must be re-reconciled.

**This ADR's own baseline is a Posture C act.** The Context section's measurement of
`2my8r9ry2t-wq/Skouer` — "23 entries, 100% under `project/`" — is the tester's private
repository read for a Jikigai product purpose. That is the processing recorded as
**PA-35** in the Art. 30(1) register and assessed in
`knowledge-base/legal/legitimate-interest-assessments/2026-08-06-alpha-tester-repo-observation-lia.md`.
It is covered there; it is named here so the ADR does not read as though its evidence
arrived from nowhere.

**4. Therefore plugin-emitted observability is layer 7 (`cli-stdout-artifact`).**
The synchronous stdout marker **plus** a deterministic artifact committed to the
customer's own repository carrying the same fields, because stdout alone does not
survive the session. Layer 7 is defined in
`plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`.

**Re-entry condition,** recorded so it is not rediscovered: when the hosted
headless-sync path (`triggerHeadlessSync`,
`apps/web-platform/server/auto-sync-trigger.ts`) is serving again **and** a hosted
producer for these markers actually ships, `MARKER_RE` may be widened for the
hosted surface only — and the drift guard at
`git-lock-marker-telemetry.test.ts:177-212` must be extended to cover the emitting
file in the same change. The widening and the guard extension land together or
not at all.

## Consequences

- PR 1 ships producers, a coverage summary, and a layer-7 signal. It needs none of
  the manifest machinery, which is why the split is at the CLI/hosted line.
- The generated model is **not visible in the KB viewer until its PR merges**: the
  viewer reads the GitHub source of truth, not the on-disk clone
  (`apps/web-platform/app/api/kb/c4/project/route.ts:73-81`), because a clone
  holding un-pushed commits goes permanently stale. Headless sync commits locally
  and opens a PR.
- The dependency convention the C4 producer consumes is now **specified**
  (`dependencies:` frontmatter in the component template) rather than emergent.
  Until #7332 it existed only as a prose placeholder, and Soleur's own component
  docs satisfied it 0 times out of 4.
- Validation gates on the diagnostic stream **and** element count **and**
  relationship count. The third is the one that catches the real failure: a
  link-free corpus renders valid, non-empty, diagnostic-clean output that is a
  diagram of disconnected boxes. Reported as `degraded`, never `failed` — the docs
  are the defect, not the run.
- Both-gates validation is safe only while `likec4@1.50.0` is pinned, because the
  diagnostic wording is version-specific. That is precisely why
  `apps/web-platform/server/c4-render.ts:193-195` refuses stderr gating for the
  runtime save path, which cannot pin the CLI. A drift guard asserts the pin
  against both precedents.

## Alternatives considered

- **Build-time import from `plugins/`** — impossible (claim 1). Fails only at
  release build.
- **Generated TypeScript mirror** — cannot catch its own drift (claim 2).
- **Widening `MARKER_RE` for the sync markers** — rejected on three independent
  grounds: it buys telemetry on a surface PR 1 ships no producer for, it creates a
  permanently-dead allowlist entry, and on the CLI half it would be a consent
  violation.
- **A customer-configured sink (e.g. their own Sentry DSN)** — the correct
  long-run answer for hosted-quality telemetry without a consent problem, since
  the data never leaves the customer's control. Opt-in configuration and a new
  consent surface; out of scope for #7332 and deliberately unbuilt.
- **Replacing the canonical three `.c4` filenames** — rejected: two writers, one
  directory (claim 3).
