---
title: "Earned-green preflight required for reachable-surface content gates"
status: accepted
date: 2026-07-23
issue: 6882
supersedes: null
---

## Context

Bot-authored PRs never trigger CI (GitHub prevents the loop), so
`.github/actions/bot-pr-with-synthetic-checks` derives `CHECK_NAMES` from
`scripts/required-checks.txt` and posts an **unconditional green** synthetic check-run
(`integration_id` 15368) for every listed name. Listing a *content-scoped* gate — one whose
verdict depends on what the diff contains — therefore fabricates a pass on exactly the PRs
the gate cannot inspect. This is the #6049 auto-fabrication guard.

Two prior gates resolved this by argument rather than by code:

| Gate | Guarded surface | Recorded argument |
|---|---|---|
| `rule-body-lint` (#6103 / ADR-092) | `AGENTS.{core,docs,rest}.md` | outside the action's `ALLOWED_PATHS` |
| `sentry-destroy-required` (#6589 / ADR-031 amendment) | `apps/web-platform/infra/sentry/**` | outside the action's `ALLOWED_PATHS` |

Both are labelled FABRICATED-NOT-EARNED and are sound because the fabricated assertion is
**vacuously true**: no bot PR can produce a diff the gate would reject. Each carries a
tripwire comment of the form *"the residual goes LIVE the instant `<path>` is added to
`ALLOWED_PATHS`."*

#6882 proposed promoting a third content-scoped gate — the resolvable-credential-path guard
(`scripts/lint-credential-path-literals.py`), which exists because a real incident:
`preflight/SKILL.md` Check 10 contained a home-relative literal path to the operator's live
Doppler CLI config, and Claude Code's harness auto-attached that file into model context,
reading a live `dp.ct.*` token into session transcripts.

The issue enumerated only two options (reproduce the scan in the action's preflight, or
exclude the check from synthesis via a non-15368 `integration_id`) and did not mention the
twice-used third option above.

## Decision

**A content-scoped required check may rely on the fabricated-but-unreachable argument ONLY
where `ALLOWED_PATHS ∩ SCAN_DIRS = ∅`, and that intersection MUST be re-derived per gate —
never inherited from a prior ADR.** Where the intersection is non-empty, the synthetic green
MUST be **earned**: the composite action reproduces the scanner over its own staged paths in
the Phase-4 "Secret-safety ceiling" and fails loud before pushing a branch, opening a PR, or
posting any synthetic.

For `credential-path-guard` the intersection is **non-empty**. Its
`SCAN_DIRS = ("plugins", "knowledge-base")` over tracked `*.md` (minus `**/archive/**`)
includes `knowledge-base/project/weakness-digest.md`, which is one of exactly two paths in
`ALLOWED_PATHS`. Reusing the unreachability precedent would have been its first application
to a **reachable** surface — the precise failure the #6049 guard exists to prevent. The gate
is therefore registered with an earned green (`action.yml` Phase-4), and
`plugins/soleur/test/required-checks-canonical-parity.test.sh` **Test 8** asserts the
reproduction exists *and* precedes the check-run POST.

**Reachability is the intersection of two independently-mutable sets, and the existing
tripwires watch only one of them.** Every tripwire comment to date keys on `ALLOWED_PATHS`
edits. The other input — the *scanner's* reach over a bot-writable path — can widen without
`ALLOWED_PATHS` changing at all: `scripts/weakness-miner.sh` currently emits only
`basename` of learning paths plus tag labels and counts, but an obvious readability
improvement (emit each learning's frontmatter *title* instead) would make the surface
materially reachable overnight and **fire nothing**. A soundness argument that depends on a
bash script's `echo` format staying frozen is not a control; a preflight is.

This ADR **amends, and does not reverse,** ADR-092 and the ADR-031 2026-07-17 amendment:
their unreachability arguments remain correct for their own surfaces.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Non-15368 `integration_id` (the issue's option B) | **Rejected — it is a deadlock, not an exclusion.** GitHub Actions jobs always post under 15368; requiring a context under a different integration id leaves no producer at all for bot PRs (which never trigger CI), so every bot PR stalls pending forever. `CodeQL` is not a counterexample: GHAS (57789) posts it independently of Actions, which is exactly why it is deliberately omitted from `required-checks.txt`. |
| Reuse the fabricated-but-unreachable precedent | **Rejected on evidence.** `ALLOWED_PATHS ∩ SCAN_DIRS ≠ ∅` at `weakness-digest.md`, so the fabricated assertion would not be vacuously true. |
| Shrink `ALLOWED_PATHS` to restore unreachability | **Rejected.** It would break the `weakness-miner.yml` loop that writes the digest — trading a CI change for a product-loop regression. |
| Promote the whole `lint-bot-statuses` job | **Rejected.** The job runs seven steps; two are deliberately non-blocking (ADR-129's tempfile ratchet, with #6752 open) and one carries a live carve-out (#6751). Promoting the container silently reverses those decisions. The gate was split into its own job instead. |
| Promote in `--changed --base` mode | **Rejected.** #6880 drained the grandfathered backlog to zero, so full-scan passes today; a full-scan green asserts "the repository is clean" rather than "this diff is clean", and drops the merge-base dependency (`github.base_ref` is empty on `merge_group`). |

## Consequences

- One additional public-ABI ruleset context (19 → 20 Actions contexts). Per ADR-032 Sharp
  Edge 1 the job **name** is public ABI across `ci.yml`, `scripts/required-checks.txt`, the
  canonical JSON, and `infra/github/ruleset-ci-required.tf`; a rename silently un-requires
  the gate until all four are updated in the same PR.
- Open PRs predating the merge will block on the new context until rebased — the expected
  transitional cost of adding any required check.
- `lint-bot-statuses` remains advisory. Promoting any of its remaining six steps requires
  re-deriving this ADR's intersection test for each content-scoped step first.
- The full-scan mode is only sustainable while the backlog stays at zero; it is self-enforcing
  (any PR reintroducing a resolvable path is blocked).
- Future content-scoped gates inherit a decision procedure, not a precedent to copy.

## C4 impact

**None.** Enumerated against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors:** none added — the change alters which CI check blocks a merge,
  not who participates.
- **External systems / vendors:** none added. `github = system "GitHub"` (`model.c4:230`) is
  already modeled `#external`, described as *"Source control, CI/CD, issue tracking, and
  releases"* — CI/CD is within that element's stated responsibility.
- **Containers / data stores:** none touched; this is CI configuration and repo-tracked IaC.
- **Actor↔surface access relationships:** unchanged; no element description is falsified.
- The only CI-adjacent relationship in the model (`model.c4:424`, `github -> cloudflare`)
  concerns the **Cloudflare** rulesets API — a different concept from GitHub branch rulesets.
