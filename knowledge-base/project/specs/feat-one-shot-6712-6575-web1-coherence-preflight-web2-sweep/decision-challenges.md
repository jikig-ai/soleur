# Decision Challenges — feat-one-shot-6712-6575

Recorded headless (one-shot pipeline, no operator attached). `/ship` renders these into the PR body
and files an `action-required` issue. Per ADR-084 / decision-principles, the operator's stated
direction is the default; these are surfaced, not silently applied.

---

## UC-1 — #6712 cannot honestly close in this PR

**Operator's stated direction:** *"Close #6712 and #6575 as one coupled change to the web-platform
infra apply surface. They must land together — resolving either alone produces a wrong end state."*

**What the plan does instead:** closes **#6575** only. #6712 stays OPEN with a comment recording the
new findings. Frontmatter is `closes: [6575]`, `refs: [6712, 6730]`.

**Why — the evidence, not a preference:**

1. **#6712's gap is an apply-time property that no artifact in this PR can observe.**
   `var.image_name` defaults to the mutable `ghcr.io/jikig-ai/soleur-web-platform:latest`
   (`variables.tf:67-71`) while `local.host_scripts_content_hash` comes from the *applying* commit.
   The hazard is skew between those two commits. Closing it requires pinning `var.image_name` to a
   digest at create time.

2. **There is no web-1 create path to pin.** Every automated route to `hcloud_server.web` terminates
   in the `host_creates > 0` HALT (`apply-web-platform-infra.yml:462-475`). **#6730** exists
   specifically to build that path and scopes it as *"an automated, image-pinned,
   attachment-complete path … from empty state."*

3. **This was already decided once.** PR #6725's plan
   (`2026-07-19-fix-warm-standby-web1-birth-halt-plan.md:110-149`) records an operator decision,
   backed by five of seven reviewers, deferring #6712's resolver work — *"the panel established
   there is no create path for a preflight to guard"* — and explicitly keeps #6712 OPEN.

4. **The framing's own two options are both unavailable.** Option (a) (a verifier that accepts a
   mutable tag) is the shape #6725 rejected as *"a weaker guarantee sold as a generalization."*
   Option (b) (pin like the recreate job) polls the *running* web-1's `/health .version`, which is
   empty on a fresh create — the mechanism exits 1 on exactly the path that needs it.

**What the PR does deliver toward #6712:** the verifier becomes host-agnostic with its logic
byte-unchanged; the `host_creates` HALT gains a complete, executable `crane digest` → verify →
`-var image_name=` chain so an operator-local birth *can* be verified today; and build-integrity
coverage is strengthened with two new static assertions.

**Decision requested of the operator:** confirm that closing #6575 alone — with #6712 left open,
annotated, and routed to #6730 — is acceptable. The alternative is to expand scope to include
#6730's birth path, which #6575's own sequencing rationale advises against (a prod-host-birth
capability inside a ~730-line deletion PR inverts the risk budget).

---

## UC-2 — Three framing premises were falsified and the plan does not implement them as written

Not a scope change, but the operator should know the plan deviates from the brief on points the
brief stated as verified fact:

| Framing said | Plan does | Why |
|---|---|---|
| "The `apply_target` enum drops **9 → 6**" | 9 → **7** | Only two options are removable; no third is named in #6575 or the retire plan. Making the arithmetic match 6 would require inventing a deletion. |
| "Delete the web-2 dead-boot Sentry alert" | **Comment rewrite only; the resource survives** | `sentry_issue_alert.web_terminal_boot_fatal` filters on `stage`, never on host. It is the *sole* no-SSH boot page for web-1 — and the only detector for the one failure mode this PR cannot prevent. |
| "This deletion relieves most of the accretion pressure behind a generic `scoped-apply-gate.sh` refactor" | **Records that it does not** | `scoped-apply-gate` has zero hits repo-wide. The real tracker is **#6574** (`-target` transitivity), whose hazard is a property of Terraform's graph, not of dispatch-job count. It survives this PR untouched at unchanged priority. |

Ten further premises were falsified; all are tabulated in the plan's § Research Reconciliation.

---

## UC-3 — The plan's own first draft was rejected by its deepen pass

Recorded for transparency, since it changed the PR's shape substantially.

Version 1 proposed a bake-time coherence gate in `reusable-release.yml`. Three review agents
independently rejected it and direct verification confirmed all three objections: it was
**near-tautological** (image and tree share a commit at `docker_build`, and list drift is already
caught by `cloud-init-user-data-size.test.ts:486-510`), it would have **poisoned `:latest`**
(`reusable-release.yml:596-599` pushes all three tags in one step, before the gate ran), and its
enabling premise was **false** (`terraform console` needs no credentials —
`infra-validation.yml:204-206`).

Consequence: ~155 lines of planned new code and test are not written, and the "coverage drops to
zero" premise that motivated them was itself false — coverage was never zero.
</content>
