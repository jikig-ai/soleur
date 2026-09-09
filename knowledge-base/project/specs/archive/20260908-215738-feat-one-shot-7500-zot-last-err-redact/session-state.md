# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-08-arch-zot-last-err-redact-decision-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

Four self-inflicted defects were caught by plan review and corrected in-flight. Each is
recorded in the plan rather than quietly fixed. They are forwarded here because compound's
Phase 0.5 inventory must see them even after this context is compacted.

1. **The `redact()` probe measured the wrong thing.** The mixed-blob case used a `Cookie`
   fixture — a name on the `CRED_HDRS` *denylist* — so a denylist success was read as an
   allowlist success. Re-measured with `X-Secret`: on a realistic multi-line blob `redact()`
   takes its non-JSON branch and emits the header **in the clear at RC=0**. Root cause is a
   real asymmetry in the existing shipper: the JSON branch is an allowlist (`HDR_KEEP`), the
   non-JSON branch is a denylist (`CRED_HDRS`). This forced per-line application and is the
   plan's largest single correction.
   **Prevention:** a redaction probe must use a fixture that is absent from every list the
   code consults; a fixture drawn from the denylist cannot distinguish the two branches.

2. **The ADR premise was false, and was inherited rather than checked.** The CTO agent's claim
   that ADR-184 establishes `redact()` was accepted without verification. It does not —
   `redact()`, `CRED_HDRS` and `HDR_KEEP` appear in **zero** ADRs. Reversed from "amend
   ADR-184" back to minting ADR-211.
   **Prevention:** this is the inherited-framing class in compound's Phase 0.5 bullet list —
   for every causal claim a sibling artifact supplies, name the command that falsifies it and
   run it. One `grep` over `decisions/` refuted this.

3. **The two-control justification was falsified by its own scoping.** The "3-hour historical
   window" argument dies on `boot_id=$NEWEST_BOOT`: a host replace always brings a new boot, so
   pre-fix rows are unreachable by construction.
   **Prevention:** when justifying a control by a time window, check whether an existing scope
   predicate already makes that window unreachable.

4. **The headline measurement was understated ~5x** (actual: 100 comments / 36 `headers:{` /
   13 `clientIP`; claimed: "~20 / twenty / ~7") — the same defect class the plan opens by
   criticising in the issue.
   **Prevention:** count with a command, never from recall, before a number enters prose.

Parent-supplied context was also partly wrong and was corrected by the plan: the seeded
`user_data` figure of 13,136 B is stale (measured 13,692 B), and "8,000 B" is a headroom
*floor*, not an allowance. The parent's structural findings (two separate host scripts;
`redact()` has one call site; field name and terminal position load-bearing) held.

Two pre-existing conditions recorded, not actioned: the gdpr-gate corpus is 121 days stale
(`POSTURE_FAIL`, tracked at #7255/#7857), and Better Stack's Art. 28(3) instrument is
unexecuted (#7825/#7529).

### Decisions

- **Adopted Option 4 plus a tier gate — none of the issue's three options.** Share `redact()`
  **per line**, but discard its fail-closed drop semantics: degrade the single `zot_last_err`
  field and still ship the other 26. Add a tier gate suppressing tier 4, which produced ~100%
  of measured header exposure while naming a cause zero times in 21 hours.
- **Cost is not a decision input, and the issue's framing was wrong twice.** Measured 13,692 B
  stored against a 20,000 B budget. Tier gate +40 B, narrow scrub +44 B, full redactor +64 B —
  the "cheaper" option saves 20 bytes out of 6,308 of headroom. The dominant cost is ForceNew,
  which every option pays identically.
- **A second egress the issue never mentions, and it is worse than the one it does.** The
  restart-loop alarm publishes the raw tail into a **public** GitHub issue. Independently
  verified by the parent on #7272: 100 comments, 36 carrying header objects, 13 carrying
  `clientIP`. No credential leaked — all 23 `Authorization` occurrences render
  `Authorization:[******]` (zot's own masking) with zero long base64 adjacent, and all 13
  `clientIP` values are RFC1918 `10.0.x.x`. The exposure is bounded, but only by the single
  upstream default the sibling emitter's allowlist exists to not depend on.
- **Split by delivery latency.** Phase A (public egress) ships with zero infrastructure cost;
  Phase B is inert until the next host replace. The plan schedules no replace, so incremental
  downtime is zero.
- **Brand-survival threshold `single-user incident`** (CPO ruling), decided on the ladder's
  text rather than on probability — a gate *upgrade*, since `aggregate pattern` would buy
  fewer reviewers.

### Components Invoked

`soleur:plan` · `soleur:deepen-plan` · `soleur:gdpr-gate` · agents: `learnings-researcher`,
`Explore`, `cto`, `clo`, `cpo`, `code-simplicity-reviewer`, `architecture-strategist`,
`spec-flow-analyzer`, `kieran-rails-reviewer` (`dhh-rails-reviewer` relevance-gated out — no
Ruby/Rails) · gates: 4.5, 4.55, 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, `lint-guard-contract.py`,
`lint-infra-no-human-steps.py`, `c4-count-parity.test.sh`, `registry-userdata-budget.sh`,
`lint-orphan-test-suites.sh`

## Collision Gate (re-probed post-plan)

- Plan frontmatter `issue: 7500`, `closes: 7500` — identical to the ref cleared at Step 0a.5.
  No newly-discovered target to re-probe.
- PR #7444 surfaced in both the `linked:issue` and body-text probes. Cleared by direct
  measurement, not heuristics: #7444's `closingIssuesReferences` is `[7440]`, and on fresh
  `origin/main` the `ZOT_LAST_ERR` assignment passes through zero `redact` calls while
  `redact()` retains exactly one call site, in the sibling host script.
