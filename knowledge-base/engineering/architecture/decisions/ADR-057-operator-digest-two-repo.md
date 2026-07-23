---
title: "Operator-private weekly digest: two-repo, privilege-separated pipeline"
status: accepted
date: 2026-06-12
related: [5085, 5080, 5103]
related_adrs: [ADR-056]
related_plans:
  - knowledge-base/project/plans/2026-06-11-feat-operator-weekly-comprehension-digest-plan.md
related_specs:
  - knowledge-base/project/specs/feat-operator-weekly-digest/spec.md
brand_survival_threshold: single-user incident
---

# ADR-057: Operator-private weekly digest — two-repo, privilege-separated pipeline

## Context

The non-technical operator cannot keep pace with autonomous loops that ship
features, move money, and resolve incidents faster than a solo owner can track —
**business comprehension debt**. #5085 adds a weekly plain-language digest
("what your company actually did this week": built / money / broke / action
needed) synthesized from four internal sources (merged PRs, the expense ledger,
resolved post-mortems, open `action-required` issues).

This **inverts** the threat model of the shipped community release digest
(`cron-weekly-release-digest.ts`, #5080), which protects *outbound* exposure (no
private content in a public post). The operator digest deliberately **aggregates
private financial + incident + decision data**, so the load-bearing question is
*"can this aggregated private data reach a non-private surface?"*

Two codebase realities shaped the decision (verified at plan time):

- **`jikig-ai/soleur` is PUBLIC.** Generating the digest in soleur's own Actions
  runs would expose it in **public logs**, and a soleur issue is world-readable —
  the original spec's "private issue in the operator's repo" was unachievable there.
- **`claude-code-action` has two token contexts** (the App-installation token vs.
  the bash-bridge `GH_TOKEN`). A cross-repo `gh` read from inside the action can
  silently 403/return-empty under the App token (#3403), which would render
  "Nothing shipped" on an **auth failure** — a false-negative comprehension leak.

The brand-survival threshold is **single-user incident**: a leak exposes the
operator's finances/incidents; a silent failure makes them believe they are
caught up when they are not.

## Decision

1. **New private repo as the execution + delivery substrate.** A scheduled
   workflow lives in a NEW private repo `jikig-ai/operator-digest`; both its
   Actions logs and its digest issues are private. It checks out the **public**
   `jikig-ai/soleur` (`persist-credentials: false`) purely as the data source.
   Rejected alternative: generate in soleur (public logs + public issue).

2. **LLM-as-script, not a TS/bash synthesizer.** Synthesis is `SKILL.md` prose
   (`operator-digest`); bash is reserved for the deterministic scrub gate and the
   post. There is no JSON-parse seam — the skill *is* the model — so the community
   digest's TS-cron catches (`extractModelJson`, quadratic-regex, clock-in-step,
   pagination) do not transfer and are deliberately not imported.

3. **The agent cannot post.** Its `--allowedTools` allowlist omits the
   issue-create capability. The agent reads four sources, writes
   `$GITHUB_WORKSPACE/digest.md`, and STOPS. The only thing that posts is a
   deterministic workflow post-step. This closes the prompt-injection bypass: a
   malicious PR title / `action-required` body / ledger line cannot instruct the
   model to publish, because the model has no publish capability.

4. **Scrub is a GHA post-step, never an in-prompt assertion.** An in-prompt
   `exit 1` is swallowed (the run conclusion still reads `success`). The tuned
   fail-closed `digest-scrub.sh` runs as a `run:` step OUTSIDE the action: it
   HARD-ABORTS on secret classes, ABORTS on a foreign email domain (the
   customer-PII class), WARNS-only on UUID/IPv4 (legitimate in prose), and ABORTS
   on a grep error (real fail-closed — not the incident sentinel's per-pattern
   `|| true` fail-open). On abort, the post-step posts a **content-free** withheld
   notice so a withhold is operator-visible, not a silent absence.

5. **A tuned gate, not the incident sentinel.** `redact-sentinel.sh` over-aborts
   on benign first-party prose (`ops@jikigai.com` is literally in the ledger;
   UUIDs/IPs appear in incident prose) AND misses named PII ("Jane Doe"). The
   named-PII control is therefore **upstream** (L2: the skill emits incident
   SUMMARIES from PIR frontmatter/title/status only, never the body; money as
   amounts + vendor names only).

6. **Two token contexts aligned.** `github_token: ${{ secrets.GITHUB_TOKEN }}` in
   the action `with:` AND `env: GH_TOKEN: ${{ github.token }}` on the step, so the
   in-action cross-repo read does not silently 403 (#3403). No cross-repo PAT —
   the private repo's `GITHUB_TOKEN` reads public soleur (public → no grant) and
   writes issues to its own repo. The only secret is `ANTHROPIC_API_KEY`.

7. **No durable plaintext copy.** The post-step `rm`s `digest.md` after posting;
   never `actions/upload-artifact`; `show_full_output` OFF; no `cat`/`echo` of
   `digest.md` or `$ANTHROPIC_API_KEY`. (Retention control; minimization is L2.)

8. **Source-of-truth committed in soleur, executed in the private repo.** The
   workflow YAML, `digest-scrub.sh`, and the provisioning script are committed
   (and multi-agent-reviewed) in public soleur, then installed into the private
   repo by an idempotent bootstrap (`provision-operator-digest-repo.sh`,
   Doppler→stdin secret, fail-loud on empty). The brand-critical workflow gets
   review here even though it runs elsewhere. The asset MUST NOT live under
   soleur's own `.github/workflows/` (that would run it in public logs).

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Generate the digest in soleur's own Actions | soleur is PUBLIC: public logs + a world-readable issue leak the operator's private finances/incidents. |
| Reuse `redact-sentinel.sh` as the digest gate | Over-aborts on benign first-party prose (kills the digest on `ops@jikigai.com`, UUIDs, IPs) AND misses named PII. Needs a tuned gate + upstream L2. |
| Reuse `cron-weekly-release-digest.ts` (#5080) mechanism | Opposite threat model (outbound-safety vs. inbound-aggregation); closed input set vs. open internal set; no shared helper/webhook. |
| Let the agent post directly (`gh issue create` in the allowlist) | A prompt-injection in any read source could make the model publish, bypassing the entire scrub stack. Only the deterministic post-step posts. |
| In-prompt scrub assertion | An in-prompt `exit 1` is swallowed; the run still reports `success`. The gate must be a GHA post-step. |
| Terraform `github_repository` + `github_actions_secret` (the `provision-github` tenant pattern) | Disproportionate to one internal repo + one secret for V1. An idempotent gh-CLI bootstrap satisfies `hr-multi-step-post-merge-bootstrap-script` without a new TF root. |
| Cross-repo read via a PAT | Unnecessary: public soleur needs no grant; the private repo's own `GITHUB_TOKEN` writes its issues. Avoids a new long-lived credential. |

## Consequences

- The operator gets a private, plain-language weekly comprehension artifact with a
  four-layer fail-closed guardrail stack (L1 path scope, L2 summaries-only,
  L3 tuned scrub post-step, L4 no durable plaintext).
- A new durable copy of personal data exists (private-repo issues + 90-day Actions
  logs). Lawful basis = the same legitimate-interest basis as the source PIRs; the
  digest inherits source retention; no new processor beyond Anthropic (same posture
  as every other claude-code-action run). No Art. 33 trigger (the statutory clock
  lives in the incident skill).
- A drift surface: nothing *enforces* re-running the bootstrap, so a hand-edit to
  the deployed workflow can diverge from the soleur source-of-truth. Mitigated by a
  weekly discoverability check that diffs the deployed file against the committed
  asset and warns on divergence (not Terraform-grade, adequate for one workflow at V1).
- In-band liveness: each digest names the prior week's issue ("Last week: #N"); a
  missing back-reference is the operator-visible skipped-week signal. A scheduled
  workflow auto-disables after 60d repo inactivity — the weekly successful run (or a
  withheld-notice write) keeps the repo active.
- Section-expansion gated on a future read/engagement signal (deferred, R3a) — V1
  ships the four fixed sections.
