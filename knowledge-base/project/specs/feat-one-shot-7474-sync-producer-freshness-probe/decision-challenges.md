# Decision Challenges — feat-one-shot-7474-sync-producer-freshness-probe

Persisted headless per ADR-084. `ship` renders these into the PR body and files an
`action-required` issue. Nothing here was auto-applied as Mechanical.

---

## UC1 — The plan changes the marker token the issue specified

**Class:** User-Challenge (changes operator-stated direction)

**Issue #7474 asked for:** `SOLEUR_SYNC_PRODUCER_MISSING producer=$p reason=stale-install`

**Plan does:** `SOLEUR_SYNC_PRODUCER_MISSING producer=<p> affects=<area> reason=absent-from-verified-root`

**Why challenged:** the guard observes only that a path is absent under an already-verified
root. `stale-install` is an inference, and the plan's own measurement (H3) makes plain staleness
the *least* reachable generator — `commands/` and `scripts/` ship in one payload at one SHA, so a
merely-old install runs its own old `sync.md`, whose invocations match its own `scripts/`. Both
existing `reason=` tokens in `sync.md` name observations, never causes. Three reviewers
independently reached the same conclusion.

**Cost if the operator disagrees:** one token rename; no structural change.

---

## UC2 — The plan moves the check from a Phase 0 loop to per-invocation-site guards

**Class:** User-Challenge (changes operator-stated mechanism)

**Issue #7474 asked for:** a loop probing all three producers "immediately AFTER the identity
gate", plus an instruction to the agent to report rather than surface the raw ENOENT.

**Plan does:** guards each of the 6 invocation sites inline, with no Phase 0 fence edit at all.

> **Superseded at /work, 2026-08-11.** The plan specified the one-liner
> `[ -f "…" ] && bun "…" || echo "…"`. Measured: when the producer is **present but exits
> non-zero**, that form falls through to the `||` and reports it MISSING — a confidently wrong
> remedy, which this plan's own `## User-Brand Impact` ranks as the worst outcome. Shipped as
> `if [ -f "…" ]; then <invoke>; else echo "…"; fi`. `T0l` pins the semantics rather than the
> syntax, via a form-agnostic block extractor, so reintroducing the rejected form goes RED
> naming the producer instead of becoming invisible.

**Why challenged:** the Phase 0 form cannot *prevent* the invocation — bash carries no state
across fences, so the skip could only ever be an instruction, and a marker above a bare death is
still a bare death. It also fires false markers on `/soleur:sync conventions`, which invokes no
producer, and separates the guard from its invocation contrary to ADR-179 decision 5
("the gated invocation must be fail-closed in isolation"). The per-site form is fewer moving
parts and is actual enforcement.

**Preserved from the ask:** the named marker, the operator-facing diagnosis instead of a raw
ENOENT, and the untouched identity gate (the issue's emphatic non-goal).

**Cost if the operator disagrees:** the Phase 0 loop can be added back additively as an early
summary, but it should not be the only thing between a missing producer and the ENOENT.

---

## UC3 — The plan rewrites the operator-facing remedy sentence the issue drafted

**Class:** User-Challenge (changes operator-stated copy)

**Issue #7474 asked for:** *"the installed Soleur plugin predates these producers — update the
plugin itself, not just the marketplace"*

**Plan does:** a four-property message (observation → remedy → fallback → what still worked)
that names the missing file, locates the fault in Soleur rather than the user's project, and
adds an explicit "if that doesn't clear it, report it" branch.

**Why challenged (CPO, sign-off review):** the drafted sentence asserts the same unproven cause
UC1 removes from the token — and asserts it in the half the founder actually reads. Under H1
(torn payload) reinstalling reproduces the same payload; the operator follows Soleur's own
instruction, it fails, and trust burns. That is worse than a bare error. The drafted sentence
also uses "producers", a term internal to this plan, and names no command.

---

## T1 — Where the update-path UX defect gets filed

**Class:** Taste (CPO)

The SHA-divergence *mechanism* is deferred to #7452 and that is not contested. But #7452 sits in
**Post-MVP / Later** behind 1027 open issues, which for this cycle is indistinguishable from
unfiled — while the actual user pain ("updating the marketplace does not update an installed
plugin, and nothing says so") is live on the only surface with a real user.

**Plan does:** keeps the mechanism on #7452, and files the update-path UX defect as its own
issue in **Phase 4: Validate + Scale**. Also assigns #7474 to Phase 4 (currently no milestone).

> **Superseded at /work, 2026-08-11.** The mechanism deferral to #7452 landed as planned, and
> #7474 is assigned to Phase 4. The separate Phase 4 **issue** was NOT filed: the
> `code-simplicity-reviewer` CONCUR gate DISSENTed, on two grounds verified before adopting —
> the work is 3 files / ~25 lines (inside the fix-inline threshold), and a milestone issue in
> *this* tracker could never be closed, because the two-step update behaviour belongs to the
> Claude Code plugin harness. Shipped instead as docs in the same PR (`README.md` `## Updating`,
> `plugins/soleur/README.md` `## Known Issues`, `docs/pages/getting-started.njk`), with the
> harness half sent upstream as `feature-request-plugin-update-surfaces-install-divergence.md`.
> Net issue flow **−1** rather than 0.

**Note on scope — corrected at review.** Whether closing #7474 resolves the *reported* incident
depends on which generator was at work, and the plan's own hypothesis table does not settle it:

- Under **H2** (instruction/payload split — rated PLAUSIBLE *and consistent with the report*,
  since the reporter saw `SOLEUR_ROOT_OK=1`, a gate that only exists post-#7443, while
  `installed_plugins.json` held a pre-#7443 SHA) the reporter's next run executes a `sync.md`
  carrying these guards against the same stale root, the marker fires, and the incident **is**
  resolved.
- Under **H3** (a merely-old install running its own old `sync.md`) it is not.

An earlier draft of this note asserted the H3 conclusion flatly. That is the same error class
UC1 refuses on `reason=stale-install` — reasoning from the least-supported branch — pointed the
other way, and it under-sold the change.

---

## T2 — Anti-vacuity floors left as exact-equality (decision recorded, not taken)

**Class:** Taste (CTO)

Both sync suites use exact-equality floors (`expect(assertions).toBe(8)`, `EXPECTED_CASES=9`)
while ~14 sibling suites use the shared `gate_assert_ran` harness, whose own comment says:
*"A FLOOR, NOT EQUALITY. The count is developer-incremented, so `-eq` would turn every newly-added
assertion into a spurious failure and train people to bump the number without reading it."*

Adding a case today produces `ran 10 of 9 cases — a case was deleted or its counter neutered`,
which is directionally wrong for someone who just added one.

**Plan does:** bumps both floors and leaves the pattern alone — flipping two suites' assertion
semantics is scope creep on a P2 diagnostic fix. Recorded here so the next change does not pay
the same tax with no trace of why.
