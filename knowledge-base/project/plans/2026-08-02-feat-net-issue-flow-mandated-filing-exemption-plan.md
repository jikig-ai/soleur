# feat: net-issue-flow mandated-filing exemption

```yaml
date: 2026-08-02
type: feat
lane: cross-domain
issue: null
branch: feat-one-shot-net-issue-flow-mandated-filing-exemption
brand_survival_threshold: none
requires_cpo_signoff: false
plan_revision: v2 (post 6-agent review)
```

> Spec lacks valid `lane:` — defaulted to `cross-domain` (fail-closed per the `plan` skill's
> lane-validation step; the "TR2" label in that step belongs to the skill, not to this plan's own
> TR numbering below). No spec directory existed for this branch; no brainstorm within 14 days matched.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Enhancement Summary

**Deepened:** 2026-08-02 · **Panel:** 6 review agents + 2 deepen sweeps + precedent-diff gate

### Key improvements

1. **A pre-existing P0 was discovered and folded in.** The gate already exceeds the hook's
   `timeout 8` (measured 7.7–8.1 s; 1 of 3 runs returned `rc=124`, which the hook translates to
   `exit 0` — no deny, no telemetry). The blocking gate is intermittently a silent always-pass
   *today*. Fixing it is now a blocking prerequisite (FR0), because adding work to a gate with
   negative headroom would make it certain.
2. **The riskiest implementation assumption is now proven, not assumed.** The single-`jq`-pass
   predicate is verified against all six fixture shapes at **1.007 s** on the real 2 MB payload,
   with a committed reference implementation (RI-2).
3. **The latency was diagnosed rather than guessed** (RI-1): network is healthy at 0.449 s; the
   cost is pagination. "Raise the timeout" is therefore correct and no payload-shrink alternative
   exists.
4. **Four v1 claims asserted from documents were falsified by measurement** and corrected — the
   fail-closed guarantee (actually fail-*open* via a staged-index read), the adjacency claim
   (inverted — adjacency *is* the corpus convention), the ack-gate's scope (27 of 101 rules
   ungated), and the attribution readout (does not exist).
5. **Two User-Challenges are recorded, not applied** (`decision-challenges.md`) — both contradict
   explicit operator direction, so per ADR-084 they are surfaced with the operator's direction
   kept as the default.

### New considerations discovered

- `timeout(1)` is not universally present; the current hardcode is a latent **rc-127 dark
  tripwire**. FR0a adopts the repo's `TO=()` probe rather than only raising the number.
- `net-issue-flow.sh`'s fence-stripper lacks the fail-closed arm its two sibling gates carry —
  an existing divergence FR4 now closes.
- The suite has **no pass counter**, so the anti-vacuity floor cannot be added without one first.
- Emitting telemetry on `RC=124` has no precedent in the repo — it is novel here.

## Overview

Two repo gates are in genuine conflict:

- `wg-block-pr-ready-on-undeferred-operator-steps` **requires** a tracking issue for a bare
  operator action before `gh pr ready`.
- `plugins/soleur/skills/ship/scripts/net-issue-flow.sh` **blocks** any PR whose
  `NET = FILED - CLOSING` is `> 0`.

Neither documented exit applies: "fix inline" is a **size** test (`<=100` lines AND `<=4`
files) while the blocker is **authority** (an operator-only credential decision); "close
something" requires the filed issue to supersede an open one, and a mandated tracker
supersedes nothing. The only remaining exit is the blanket
`<!-- gate-override: net-issue-flow -->` marker, whose help text calls itself an
*"architectural-pivot deferral"* — which this is not.

**A gate whose only escape hatch requires mis-describing the escape gets overridden
reflexively. That is the failure mode this plan closes.**

This adds a narrow, corpus-derived, fail-closed exemption: an issue whose body carries
`Mandated-By: <rule-id>`, where `<rule-id>` is tagged `[mandates-filing]` in the merge-base
copy of `AGENTS.rules.md`, is subtracted from `NET` while staying fully visible in the
report. The blanket override stays working and unchanged.

**v2 status.** A six-agent review panel found **nine P0 defects** in v1, four of them in
claims v1 asserted from documents rather than measuring. All are folded in below. Two
findings could not be folded because they contradict explicit operator direction; both are
recorded in `decision-challenges.md` with operator direction kept as the default per ADR-084.

---

## P0-0 — BLOCKING PREREQUISITE: the gate already times out today

**Pre-existing defect, discovered while sizing this change.** Three consecutive runs of the
*unmodified* gate on this host:

| Run | Elapsed | rc |
|---|---|---|
| 1 | 7.7 s | 0 |
| 2 | **8.1 s** | **124 — TIMED OUT** |
| 3 | 8.1 s | 0 |

The hook wraps the gate in `timeout 8`, then does `[[ "$RC" -eq 1 ]] || exit 0`. A timeout
yields `RC=124` → **`exit 0`: no deny, no `emit_incident`, nothing distinguishing it from a
pass.** The blocking gate is already intermittently a silent always-pass — a fifth member of
the exact defect class its own header enumerates four times. The dominant cost is
`gh issue list --state all --limit 500` (~4.8 s, ~2 MB).

Per `wg-when-an-audit-identifies-pre-existing`, fixed **inline** (small, in a file already
being edited, and a hard precondition — you cannot add work to a gate with negative headroom):

These three are referenced throughout as both `P0-0a/b/c` and **`FR0a/b/c`** — same requirements,
two labels (the P0 label marks the prerequisite, the FR label marks it as a shipped requirement).

- **P0-0a / FR0a** Raise the hook's timeout to `25` — and do it via the repo's `TO=()` probe
  (`TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 25)`), **not** a hardcoded `timeout 25`.
  RI-3: the current hardcode is a latent rc-127 dark tripwire on hosts lacking `timeout(1)`.
- **P0-0b / FR0b** Emit telemetry on timeout: `[[ "$RC" -eq 124 ]] && emit_incident net-issue-flow warn "gate timed out — failed open"`, **before** the `|| exit 0`. No precedent exists for emitting on 124 — this is novel.
- **P0-0c / FR0c** Keep all new work inside the **existing single `jq` pass** — no per-issue
  subprocess loop (a 500-issue `awk` fence-strip loop measured ≥1.7 s of overhead alone; the
  verified single-pass predicate costs 1.007 s — RI-2).

Without P0-0, every acceptance criterion below would sometimes be measuring a gate that never ran.

---

## Premise Validation

| Cited premise | Probe | Result |
|---|---|---|
| Merge `b5871b9f6` | `git log -1` | **Holds (framing nit).** Title is `fix(infra): the twice-daily drift scan reads ONE config and reports it as clean (#7152)`; the *filed* issue #7159 is the token-drift/read-token-shape decision. Same event. |
| The gates were in genuine tension | `gh pr view 7152` | **Confirmed verbatim** — body carries the override marker plus *"the two gates are in tension here."* |
| The filed issue supersedes nothing | `gh issue view 7159` | **Confirmed.** OPEN; `priority/p1-high, action-required, deferred-automation`. |
| Blocker is authority, not size | PR #7152 body | **Confirmed** — *"the blocker is authority, not size."* |
| Ordering: is the mandated issue even counted? | `createdAt` both | **Confirmed live.** PR `2026-08-01T20:43:50Z`, issue `2026-08-02T11:39:22Z` — ~15 h later, so it **is** in FILED; the exemption is not a no-op. |
| ADR-131 blocks this | Read ADR-131 | **Does not block** (`status: proposed`; Proposal 1 permits *"Existing ones may be fixed, tightened, merged, or deleted"*). Whether an exemption is a "fix" is a judgement the ADR must state plainly. |

## Research Reconciliation — claims corrected by measurement

Every row is a v1 claim that **measurement falsified**. Kept visible because v1 asserted them
from documents, and that is the pattern not to repeat.

| v1 claim | Measured reality | v2 response |
|---|---|---|
| *"A failed corpus read yields an empty set (fail-closed)."* | **FALSE — fail-OPEN and self-granting.** With `set -uo pipefail` and no `-e`, a failed `merge-base` yields an empty var, and `git show ":AGENTS.rules.md"` reads the **staged index** — the author's own copy — returning `rc=0` and **101 ids**. Non-empty, so the empty-set warn never fires. Defeats D2 entirely. | FR1 resolves the base explicitly, validates it as a SHA, and never lets a bare `:path` reach `git show`. |
| *Adjacency matching is falsified by the corpus.* | **INVERTED.** **0** of 101 rule lines end with a bracket tag; **42** carry a tag immediately after `[id: …]`. Adjacency **is** the convention. v1's "falsification" was an artifact of choosing an unconventional placement. | Per-line matching still correct (order-independent), but the justification is rewritten and the mutation rebuilt. |
| *The ack gate covers adding/removing the marker on any rule.* | **FALSE twice.** `GATED_PREFIX_RE = ^(hr\|wg)-` leaves **27 of 101** rules ungated; and a **new** rule id carrying the marker is additive → no ack **and no warning**, since `SECURITY_TAG_MARKERS` lacks `[mandates-filing]`. | FR1 restricts extraction to `^(hr\|wg)-`; FR2b adds the marker to `SECURITY_TAG_MARKERS`. |
| *"CODEOWNERS-owned WORM ack"* implies human review. | **Not enforced.** `.github/CODEOWNERS` says so itself: *"CODEOWNERS-review on main is a tracked operator follow-up."* No active ruleset requires code-owner review. It is a **self-authored, hash-bound CI attestation**. | ADR wording corrected to those words. |
| Telemetry makes reflexive use *"measurable from day one."* | **FALSE — no readout exists.** `rule-metrics-aggregate.sh` builds `rules[]` from `AGENTS.md` ids only, and line 319 filters `net-issue-flow*` out of `orphan_rule_ids` — the counts reach `rule-metrics.json` **nowhere**. `operator-digest` never reads that file. `.claude/.rule-incidents*` is gitignored and worktree-scoped (dies with `clean_gone`). The rule id would land in `rule_text_prefix`, free text nothing parses. | FR6 builds the readout, or the attribution framing is struck. See D5. |
| `timeout 8` is ample. | **FALSE** — 7.7–8.1 s; 1 of 3 runs timed out. | P0-0. |
| AC asserting the merge-base set == 2 ids, pre-merge. | **Structurally impossible.** merge-base is an ancestor of `origin/main`; tags land on the branch, so the set is ∅ for this PR's life — and the adjacency mutation is then indistinguishable (∅ either way). Four reviewers found this independently. | TR7 split into worktree-exactness and seam-derivation halves. |
| Phase 5.5 adds the `Refs #N` companion, so D3 is satisfied. | **FALSE — the companion is erased before the gate that reads it.** ship Phase 6 **full-replaces** the PR body with a template that has no `Tracks`/`Refs` carry-over, and the only invocation that blocks (the hook at `gh pr ready`) runs *after* Phase 6. | FR11. The happy path does not work without it. |
| FR10's remedy template can carry the claim. | **FALSE as written.** The template is `--body "…\n\n…"` in **double quotes** — `\n` is a literal backslash-n, so `Mandated-By:` lands mid-line and the anchored match fails. The prose-mention negative fixture would be green while the production writer is broken. | FR10 uses `--body-file`, with an end-to-end AC. |
| *"This plan files zero issues; its own net-issue-flow is 0."* | **FALSE.** ADR-084 / ship Phase 6 step 2.5 mandates an `action-required` issue for `decision-challenges.md`, filed in Phase 6 **before** `gh pr ready`. If its body names the PR, this PR is blocked by the gate it adds. | Named; this PR carries the blanket override and says so. |
| `COMPANION_REGEX` can be *"reused verbatim."* | **Impossible.** It matches any `#N`; the predicate needs *that* issue number, so it must interpolate — and without a right boundary `Refs #71590` satisfies `#7159`, reintroducing the gate's own measured defect #3. The `.ts` file is itself a drift-copy of prose in ship/SKILL.md. | FR3(c) pins the boundary form; parity guard noted. |
| `--state` is *"free"* in the existing call. | Not free — adding `state` changes the argv that Case 8 asserts against. | Noted in FR3(d). |
| The go-skill routing table needs checking. | `plugins/soleur/commands/go.md` has **zero** net-issue-flow references. | **No edit** (recorded so the check is visible). |
| The AGENTS index needs an edit. | `AGENTS.md` is pointer-only. | **No `AGENTS.md` edit.** |

**Confirmed correct in v1** (do not re-litigate): 23 assertions across 14 cases (ship/SKILL.md's
"18" is stale); `_emit warn` not `transient`; ADR-155 free; rule bodies 313 B/364 B → 331 B/382 B
against the 600 B cap; `B_ALWAYS` 42547/46000; the soak probe reads global GitHub counts and is
**unaffected**; `startswith("net-issue-flow")` does cover both new ids.

## User-Brand Impact

**If this lands broken, the user experiences:** either the status quo (a pipeline blocking on a
filing another gate mandates, resolvable only by writing a false justification) or — worse — a
blocking gate that silently always-passes, letting backlog growth resume under a green check.
P0-0 shows that branch is **already live** intermittently.

**If this leaks:** no exposure vector. Reads public repo metadata and a committed corpus; writes
no user data, touches no credential.

**Brand-survival threshold:** `none` — repo-internal tooling, no user-facing surface, no
regulated data, no sensitive path per the preflight Check 6 regex.

## Open Code-Review Overlap

**#7105** (*Phase 7 false all-clear on >20 workflow runs*) cites `net-issue-flow.sh` only as a
**positive precedent** for `--limit 500`. **Disposition: Acknowledge** — different concern,
different file; this plan preserves the pin. No other planned path matched the 62 open
`code-review` issues.

## Design Decisions

### D1 — Corpus tag, matched per rule line, scoped to the ack-gated prefixes

Derive qualifying ids from **rule lines** carrying `[mandates-filing]`, extracting that line's
`[id: X]`, **restricted to `^(hr|wg)-`** so the derived set is by construction a subset of the
ack gate's coverage (`GATED_PREFIX_RE`). Per-line and order-independent — not because adjacency
is unconventional (it is the convention: 42 of 101), but because per-line is robust to placement
and must survive a `**Why:**` suffix.

No rule-id list in the script. Rejected: a hardcoded list (the forbidden second pin); a prose
heuristic (measured over-permissive — matches `wg-when-a-test-runner-crashes-segfault-oom`, a
three-way disjunction, and `wg-defer-only-after-inline-triage`, which *restricts* filing); a
GitHub label (a bare label anyone can add is the blanket override with extra steps).

### D2 — Merge-base corpus, with an explicit SHA guard

`MB="$(git merge-base origin/main HEAD 2>/dev/null)"`; require `[[ "$MB" =~ ^[0-9a-f]{7,40}$ ]]`
before use; on failure the set is empty **and** the warn fires. **A bare `:path` must never reach
`git show`** — that reads the staged index (measured: 101 ids, `rc=0`), silently restoring the
same-PR self-grant D2 exists to prevent, in a non-empty form the warn cannot see.

Merge-base rather than `origin/main` tip because `lint-rule-bodies.py` already decided it for the
sibling gate (*"MUST be the merge-base … NOT origin/main tip"*).

Stated plainly: the exemption does **not** work on the PR that introduces a tag, and every branch
open when this merges reads a pre-tag merge-base until rebased — so the rollout emits
`Mandating rules: 0` as routine noise for days. Correct behaviour; the ADR must say so.

### D3 — Corroboration: the PR body names the issue (honest framing)

Require the fence-stripped PR body to match `(Tracks|Refs)[[:space:]]+#<N>([^0-9]|$)` — the right
boundary is mandatory. Also require the issue OPEN (`.state == "OPEN"`, positive equality; a
missing `state` must fail closed).

**Corrected from v1: this is not "two-party corroboration."** It restates the two conditions
`wg-block-pr-ready-on-undeferred-operator-steps` already enforces, and after FR10 both halves
become automatic byproducts of complying with two other gates. The predicate really means *"this
issue was filed through the sanctioned remedy template."* Its one genuine contribution is
**bounding the count** — each exempt issue needs its own companion, so one acknowledgement cannot
stamp six issues. Keep it for that, and describe it accurately.

### D4 — Tag set (operator direction; recorded challenges)

Corpus sweep against *"a compliant outcome requires an issue to exist — no inline-only path
satisfies it"*: **TAG** `wg-block-pr-ready-on-undeferred-operator-steps`; **TAG**
`wg-when-deferring-a-capability-create-a` (operator direction — **challenged by three reviewers**,
see `decision-challenges.md` DC-1). Qualifying but not tagged initially:
`wg-when-tests-fail-and-are-confirmed-pre`, `wg-pm-class-followthrough-for-operator-dogfood`.
Mixed, not tagged: `wg-when-an-audit-identifies-pre-existing`,
`wg-record-recurring-vendor-expense-before-ready`. Excluded (disjunction / restriction):
`hr-ship-message-no-operator-checklist`, `wg-when-a-test-runner-crashes-segfault-oom`,
`wg-defer-only-after-inline-triage`.

**Filing-site inventory (new in v2 — the sweep covered rules, not filing sites).** Most issues are
filed from SKILL.md phase mandates with **no rule id, which can never be tagged**: the CMO
content-opportunity and website-framing gates (which file *automatically, headless*), the ADR-084
decision-challenge issue, and the review-finding gate. Every such site is a **permanent
blanket-override case**. This is why FR7 is load-bearing, and the ADR must name the untaggable
class rather than implying the exemption generalizes.

### D5 — Telemetry, and the attribution claim

Emit `_emit bypass` under rule_id **`net-issue-flow-mandated-filing--<rule-id>`** (still covered by
the aggregator's `startswith("net-issue-flow")` prefix) so per-rule attribution lives in the
**structured** `rule_id`, not the unparsed `rule_text_prefix`. Record `flipped=true|false` so
exemptions that did not change the verdict do not inflate the count.

**The attribution claim requires a readout, or it must be struck.** Measured: those counts reach
`rule-metrics.json` nowhere and `operator-digest` never reads it. Since attribution is the entire
argument distinguishing this from "just reword the help text", FR6 **must** add a
`summary.gate_exemptions` block to Stage C of `rule-metrics-aggregate.sh` (~15 lines). If cut, the
ADR and PR body must say *"this narrows the override; attribution is future work"* — not *"this is
the instrument ADR-131 asks for."* Shipping the framing without the readout is the one thing this
plan must not do.

## Architecture Decision (ADR/C4)

**Create `ADR-155` — "Cross-gate exemption markers in the always-loaded rule corpus."** Ordinal
free but **provisional**; on renumber sweep this plan and `tasks.md`, not just the ADR.

The decision is the **class boundary**: `[compliance-tier]`, `[skill-enforced:]`,
`[hook-enforced:]` describe *how a rule is enforced*; `[mandates-filing]` is the first marker
granting authority over a **different** gate. Must record: the D4 criterion, enumeration, and the
untaggable filing-site class; the D2 merge-base rationale **and** its index-fallback hazard; D3's
corrected framing; the corrected ack-gate scope (`^(hr|wg)-` only, new ids ungated until FR2b,
CODEOWNERS review not enforced); and an **AP-017 deviation note** — the additive-new-rule lane
AP-017 designates as *safe* becomes a route to gate-exemption authority.

Honest-limitation section must also name two cheaper, **unattributed** paths the exemption cannot
see: filing the issue **before** the PR exists (excluded by the `createdAt` filter — free `NET 0`,
no telemetry), and writing `Closes #N` without closing. The instrument measures only agents who
choose the honest path, and currently makes the honest path strictly harder than the dishonest one.

**C4: no impact.** All three `.c4` files read in full. All 4 external actors (`founder`,
`emailSender`, `betaContact`, `contributor`) and all 17 external systems enumerated; the only one
touched is `github` ("Source control, CI/CD, **issue tracking**, and releases"), already reached by
`claude -> github` and `engine -> github`. Every edited element (`ship`, `hooks`, `skills`, `kb`)
is already declared; no description is falsified; no `include` line changes. Pre-existing and out
of scope: the `AGENTS.rules.md` / ADR-151 injection plane is unmodelled, and `skills` says
"61 workflow skills" against 96 on disk.

## Observability

```yaml
liveness_signal:
  what: emit_incident rows under net-issue-flow-mandated-filing--<rule-id> (bypass) and net-issue-flow (warn, incl. the new timeout row)
  cadence: per gh pr ready / gh pr merge on a net-positive PR
  alert_target: summary.gate_exemptions in rule-metrics.json (BUILT BY FR6 — does not exist today)
  configured_in: net-issue-flow.sh (_emit) + ship-net-issue-flow-gate.sh (timeout row) + rule-metrics-aggregate.sh Stage C
error_reporting:
  destination: stdout report + emit_incident JSONL
  fail_loud: PARTIAL — and the caveat is the point. Through the hook, RC!=1 exits 0, so a timeout or crash is a SILENT pass. P0-0b adds the missing timeout telemetry; without it "fail_loud" is false through the only path that blocks.
failure_modes:
  - mode: merge-base unresolvable -> git show ":path" reads the STAGED INDEX (fail-open, self-granting, non-empty)
    detection: explicit SHA guard; set forced empty; warn event
    alert_route: gate blocks; warn under net-issue-flow
  - mode: gate exceeds the hook timeout -> RC=124 -> exit 0, no deny, no telemetry (LIVE TODAY)
    detection: P0-0b RC=124 telemetry row + Phase 0 wall-clock budget
    alert_route: warn under net-issue-flow
  - mode: marker on an ungated prefix (27 of 101) or a brand-new rule id -> authority with no ack
    detection: FR1 restricts to ^(hr|wg)-; FR2b adds the marker to SECURITY_TAG_MARKERS
    alert_route: CI red on rule-body-lint; AC5
  - mode: partial-corpus staleness (n=1 when 2 expected) — one rule silently stops exempting
    detection: report prints the derived IDS, not just a count
    alert_route: visible in every report
  - mode: exemption too permissive (silently always-passes)
    detection: negative-direction fixtures; assertion floor; seam derivation
    alert_route: CI red
logs:
  where: gate stdout (into the hook deny payload) + .claude/hooks/lib/incidents.sh JSONL (NB gitignored + worktree-scoped — which is why FR6's aggregator readout is required, not optional)
  retention: existing incidents.sh rotation
discoverability_test:
  command: bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh 7152
  expected_output: "Mandating rules: N (<ids>, merge-base <sha>)" plus CLOSING / FILING / EXEMPT / REJECTED / NET lines
```

No remote-shell access in any verification path.

## Research Insights (deepen pass — all measured, not asserted)

### RI-1 — The latency is PAGINATION, not network and not payload

The 4.5. network-outage gate fired on the `timeout` keyword. Worked properly, it answers whether
"raise the timeout" is even the right fix:

| Probe | Elapsed | Bytes |
|---|---|---|
| Trivial API call (`gh api rate_limit`) | **0.449 s** | — |
| `gh issue list --limit 500 --json number,body,createdAt` | **4.127 s** | 1,995,967 |
| Same, **without** `body` | 2.675 s | 25,502 |

**L3/L7 are healthy** — a trivial authenticated call round-trips in 0.449 s, so this is not a
connectivity symptom and the L3→L7 checklist has no applicable hypothesis. Stripping 98.7% of the
payload saves only 1.45 s, so the cost is **5 sequential paginated REST calls**, not transfer.

**Consequence:** raising the timeout (FR0a) is correct, and there is **no payload-shrink
alternative** — bare-`#N` matching requires the bodies. The gate has a hard ~4.1 s floor.

### RI-2 — The single-`jq`-pass predicate is verified, with a reference implementation

FR0c's "one `jq` pass" constraint was the riskiest assumption in the plan. It is now **proven**.
A 25-line predicate — `strip_fences` via `reduce`, anchored multi-line `Mandated-By:` extraction,
`ascii_downcase`, set membership, `state == "OPEN"`, and the bounded companion match — is committed
at `knowledge-base/project/specs/<branch>/reference-predicate.jq` and was validated against all six
fixture shapes:

| Fixture | Result |
|---|---|
| CRLF body + `Refs #7159` + OPEN | exempt ✓ |
| claim inside a fenced block | not exempt ✓ |
| two `Mandated-By:` lines | not exempt ✓ |
| CLOSED issue | not exempt ✓ |
| real-but-untagged id (`cq-*`) | not exempt ✓ (claim still surfaced for the `Rejected:` line) |
| PR body has only `Refs #71590`, issue is `#7159` | **not exempt ✓** — the `([^0-9]\|$)` boundary holds |

**Measured cost: 1.007 s** over the real 500-issue / 2 MB payload — versus the ≥1.7 s a 500-iteration
`awk` subprocess loop was measured at. Total budget: **4.1 s (pagination) + 1.0 s (jq) + ~0.9 s
(`gh pr view` ×2) ≈ 6.0 s**, exactly at AC11's ceiling and far under the raised timeout.

### RI-3 — Precedents to adopt (precedent-diff gate)

- **Reading a committed blob** — `.claude/hooks/pencil-collapse-guard.sh` uses a threefold guard:
  `rev-parse --show-toplevel || echo ""` + empty-check, `ls-files --error-unmatch`, then
  `git show … || exit 0`. `.claude/hooks/cla-signed-author-gate.sh` adds
  `git rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || exit 0` **and** a refname
  arg-injection guard (`[[ ! "$REF" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$REF" == -* ]]`). FR1 adopts both.
- **The index-read hazard is a real, deliberate precedent.** `.claude/hooks/brand-hex-commit-gate.sh`
  uses `git show ":$f"` *on purpose* — "so a poisoned-but-unstaged worktree edit cannot whitelist
  colours". This confirms `:$f` vs `HEAD:$f`/`<ref>:$f` is a semantic the repo already distinguishes,
  and that FR1's guard is closing a genuine footgun rather than a hypothetical one.
- **Fence-stripping — adopt the fail-closed shape.** `.claude/hooks/ship-operator-step-gate.sh` and
  `ship-soak-followthrough-gate.sh` both end with `END { if (in_fence) exit 2 }` plus an
  unstripped-fallback. **`net-issue-flow.sh`'s own Shape B has neither** — it silently accepts an
  unbalanced fence. FR4's jq port must fail closed on an unbalanced fence, closing a divergence that
  exists today. No jq fence-stripper exists in the repo; RI-2's is the first.
- **`timeout` is not universally present — FR0a must not just raise the number.**
  `.claude/hooks/supabase-loopback-warn.sh` documents that hardcoding `timeout` produced **rc 127 and
  a dark tripwire** on hosts lacking it, and uses `TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 10)`.
  The net-issue-flow hook **hardcodes `timeout 8` today** and carries exactly that latent hazard.
  FR0a adopts the `TO=()` probe. Emitting telemetry *on* RC=124 has **no precedent** — it is novel here.
- **`summary:` block (FR6)** — follow `scripts/rule-metrics-aggregate.sh` Stage C. In-scope jq vars:
  `$schema`, `$generated_at`, `$enriched`, `$counts`, `$drops`, `$cutoff`, `$known_ids`, `$orphan_ids`.
  Large payloads go via `--rawfile` + `fromjson`, scalars via `--argjson`/`--arg`. `--dry-run` prints
  `{schema, generated_at, summary}`, so a new key surfaces there automatically.
- **Stubbing `git` on PATH (TR1)** — `.claude/hooks/session-rules-loader.test.sh` is the precedent:
  resolve `REAL_GIT=$(command -v git)` **before** shimming, use an **unquoted** heredoc so it
  interpolates, and `exec "$REAL_GIT" "$@"` so only the targeted subcommand fails. Note
  `net-issue-flow.test.sh` stubs `gh` with a **quoted** heredoc — a `git` stub cannot copy that shape,
  because the suite still needs real `git`.
- **Assertion floor (TR6)** — exactly one precedent: `scripts/lint-workflow-step-env-refs.test.sh`
  (`# ANTI-VACUITY FLOOR (#7138)`), `MIN_ASSERTIONS=69`, placed after the totals line and before the
  `FAIL > 0` exit. Its comment settles the `>=`-vs-`==` question this plan had internally contradicted:
  *"A FLOOR (-lt), not equality, so the suite grows without churn; lower it only deliberately."*
  **Blocker for /work:** `net-issue-flow.test.sh`'s `pass()` only *prints* — there is no pass counter
  to floor against, so TR6 must add one first.

## Functional Requirements

- **FR0 — P0-0a/b/c.** Timeout raise **via the `TO=()` probe, not a hardcoded `timeout`** (RI-3 — the current hardcode is a latent rc-127 dark tripwire on hosts without `timeout(1)`); RC=124 telemetry (novel — no precedent); single-`jq`-pass constraint, proven feasible at 1.007 s by RI-2. Blocking prerequisite.
- **FR1 — Derivation.** Per-line marker match; id extraction restricted to `^(hr|wg)-`; SHA-guarded merge-base corpus; no rule-id list in the script; a bare `:path` must never reach `git show`.
- **FR1b — Visibility.** Print `Mandating rules: <n>  (<ids>, merge-base <short-sha>)` — **the ids, not just a count**; a blocked agent cannot otherwise discover the qualifying set, and the ids come from merge-base so printing them in the *report* is not a smuggling vector (the *help text* still uses only the `<rule-id>` placeholder). Distinguish "read failed" from "read OK, zero tagged" **and give each its own telemetry rule_id** — `net-issue-flow-mandated-filing-corpus-unreadable` and `net-issue-flow-mandated-filing-zero-tagged` (both `warn`; both covered free by the aggregator's `startswith("net-issue-flow")` prefix). v1 required the distinction in the report but assigned no rule_id, so the two cases were indistinguishable in telemetry — the exact "cannot tell never-fired from fail-opened" defect this gate's header condemns.
- **FR2 — Tagging.** Marker onto the two rule bodies (ids immutable). Same commit: `lint-rule-bodies.py --write` + one ack row per rule (`<id>|<sha256>|<date>|<PR>|<reason>`, non-empty reason). **Ack rows need a PR number that does not exist at Phase 1** — open the PR first, or write the row at ship time; the file is WORM.
- **FR2b — Close the ack-scope hole.** Append `"[mandates-filing]"` to `SECURITY_TAG_MARKERS` in `scripts/lint-rule-bodies.py` so a new marked rule emits the mandatory-human-review annotation and a tag DROP is loud.
- **FR3 — Exemption predicate**, all in one `jq` pass. Exempt iff: (a) the **fence-stripped** issue body has **exactly one** line matching `^[ \t\r]*Mandated-By:[ \t\r]*<id>[ \t\r]*$` — `\r` is mandatory (measured: a CRLF body, which GitHub returns for web-authored text, fails without it, silently and fail-closed); two claim lines is NOT exempt, else a valid id launders an invalid one; (b) the `ascii_downcase`d id ∈ the FR1 set (jq `capture` preserves case; `m` means dot-matches-newline, not multiline anchors); (c) the fence-stripped PR body matches `(Tracks|Refs)[[:space:]]+#<N>([^0-9]|$)`; (d) `.state == "OPEN"` (positive equality; absent state fails closed — `--json` gains `state`, which changes the argv Case 8 asserts).
- **FR4 — Fence-strip both corpora** inside the `jq` pass, **failing closed on an unbalanced fence** (RI-3: the two sibling hook gates carry `END { if (in_fence) exit 2 }`; `net-issue-flow.sh`'s own copy does not — this closes an existing divergence). The PR body must be stripped **before** the companion match (v1 placed the exemption above `PR_BODY_SCAN`, so a fenced `Refs #N` would have corroborated).
- **FR5 — Honest report.** `Closing:`/`Filing:` keep true counts. Always-emitted `Exempt:` line, plus a **`Rejected:` line per non-exempt FILED issue naming the cause** — six distinct causes otherwise collapse into `Exempt: 0`, and this is the highest-leverage debuggability line available. `NET = FILED - EXEMPT - CLOSING`. Claims are scanned **inside** the FILED set, so v1's intersection/clamp language is **cut** (unreachable, and it made its own test case unconstructible). Needs a new formatter — `_fmt` word-splits a bare number list and cannot carry pairs.
- **FR6 — Telemetry + readout.** Per D5, including `summary.gate_exemptions`. If cut, strike the attribution framing everywhere.
- **FR7 — Blanket override untouched.** Cases 2, 6, 11, 12 pass unmodified.
- **FR8 — Help-text reframe in BOTH remedy blocks.** v1 edited only the hook; `net-issue-flow.sh` prints its **own** `(a)/(b)/(c)` block and is what `discoverability_test` runs. Both get: the reframe, a `(d)` mandated-filing option, placeholder-only `<rule-id>`, and an explicit **untagged-rule dead-end message** — an agent whose rule is not tagged must be told the exemption is unavailable and why, or it loops guess→block→guess. Preserve the four hook-suite needles.
- **FR10 — Writer via `--body-file`.** ship/SKILL.md's remedy template emits `Mandated-By:` on its own line from a file, not `--body "…\n…"`. **Additive only** — keep `deferred-automation` and `type/chore`, or the mandating gate's own re-run check fails and the agent is blocked by both gates with no exit. Do not rename the `[skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]` anchor (`lint-agents-enforcement-tags.py` validates it).
- **FR10b — The `work` filing site is a LIVE WRITER and must also emit the claim.** `work/SKILL.md` (anchor: the `gh issue create --label type/chore --body "deferred-automation backlog item; re-evaluate when: …; playwright-attempt: …"` block) is **not** the prose copy v1 assumed — it is the site that actually files `deferred-automation` issues for `wg-block-pr-ready-on-undeferred-operator-steps` **and** the capability-deferral path. It carries the identical double-quoted-`\n` defect FR10 fixes in `ship/SKILL.md`. **If only `ship/SKILL.md` gets FR10, issues filed through the `work` path carry no `Mandated-By:` line and the exemption never fires on the path that files most of them.** Same `--body-file`, additive-only treatment as FR10. This also supplies the requirement DC-1 option (c) points at.

- **FR12 — Correct `review/SKILL.md`'s restated threshold.** It paraphrases the arithmetic — *"a PR that opens more issues than it closes is a workflow failure, not a normal review outcome"* (immediately above its `net-issue-flow.sh` link). Under FR5's `NET = FILED - EXEMPT - CLOSING` that sentence becomes **false as written**: a PR may now open more issues than it closes and legitimately pass. v1 wrongly listed this file as safe. Reword to name the exemption.

- **FR11 — Preserve the companion across Phase 6.** ship Phase 6's body template must carry forward every `(Tracks|Refs) #N` line and every `gate-override` marker. Without this the happy path cannot work, and the pre-existing `ship-operator-step-gate.sh` is silently broken the same way.

**Cut from v1** (review-driven): the `NET_ISSUE_FLOW_RULES_SRC` env seam (a production self-grant
vector with no telemetry — stub `git` on PATH instead, matching the suite's existing I/O-boundary
discipline); the intersection/clamp; the `work/SKILL.md` edit (a second prose copy with no test);
the soak-probe FAIL-text prose edit — but **do** fix its `rule_id net-issue-flow` lookup
instruction, which will miss both new ids.

## Testing Requirements

- **TR1** Existing shape: stub `gh` **and `git`** on PATH, `CASE_RC` per case, no `producer | grep -q`. The `git` stub must follow `session-rules-loader.test.sh` — `REAL_GIT` resolved **before** shimming, **unquoted** heredoc, `exec "$REAL_GIT" "$@"` delegation — **not** the suite's existing quoted-heredoc `gh` shape, because the suite still needs real `git` (RI-3).
- **TR7a** Tag exactness against the **worktree** corpus (proves the tag shipped; satisfiable pre-merge). **TR7b** Derivation against fixture corpora through the stubbed `git` (proves per-line matching, catches a loose regex). v1's single TR7 tried to be both and was unsatisfiable at merge-base.
- **TR3** Both directions. Positive: valid claim + companion + OPEN; and a **CRLF** body (regression pin for the `\r` fix). Negative, each exit 1: unknown id; real-but-untagged id; **ungated-prefix (`cq-*`) id carrying the marker**; retired id; prefix-extension (`…-steps-v2`); malformed; **two `Mandated-By:` lines**; fenced claim; prose mention; bare `#N` companion only; fenced companion; no companion; `Refs #71590` vs `#7159`; CLOSED issue; **absent `state`**; **merge-base unresolvable** (must be NOT exempt **and** must not read the index).
- **TR4** Assert exit code and parsed output only; anchor on the line form per `cq-assert-anchor-not-bare-token`.
- **TR5** Mutation-prove each: delete the exemption block (headline); drop `^(hr|wg)-`; drop the SHA guard (must red the index-fallback case); drop `\r`; accept two claim lines; drop the companion boundary; drop OPEN; drop fence-strip on either corpus; make a read failure yield the full set; delete a test case (floor).
- **TR6** Assertion floor `>=` the baseline **23** — not `==`. v1 contradicted itself, and an exact pin is a hand-maintained magic number bumped by rote, exactly how `18` survived to 23. The repo's sole precedent settles it: `scripts/lint-workflow-step-env-refs.test.sh` (`# ANTI-VACUITY FLOOR (#7138)`) uses `-lt` and states *"A FLOOR (-lt), not equality, so the suite grows without churn."* Adopt its placement — after the totals line, before the `FAIL > 0` exit — and its comment convention (record the measured vacuity that motivated the number). **Blocker:** `net-issue-flow.test.sh`'s `pass()` only prints; there is **no pass counter to floor against**, so TR6 must add one before the floor can exist.
- **TR8** All 23 existing assertions and the hook suite pass unmodified; the four remedy needles survive FR8.

## Implementation Phases

**Phase 0 — Preconditions.** Baseline suite (expect 23 ALL PASS); hook suite; `B_ALWAYS`; per-rule
caps; **wall clock (`time bash net-issue-flow.sh <PR>`, budget ≤6 s)**; ack-row shape.
**Counting trap (measured):** `grep -cE '(^|[; ])pass '` returns **24**, not 23 — the `fail` message
on the `--limit 500` case contains the words *"must pass"*. Use `grep -cE '(^|[;[:space:]])pass "'`.
A floor pinned at 24 reds the suite on the first run.
**Phase 0.5 — FR0.** Timeout raise + RC=124 telemetry. Prerequisite.
**Phase 1 — Corpus contract.** FR2, FR2b, ack rows, `--check --base "$(git merge-base origin/main HEAD)"`, budget lint.
**Phase 2 — RED tests.** TR3 / TR6 / TR7a / TR7b.
**Phase 3 — GREEN.** FR1, FR1b, FR3, FR4, FR5 in the single `jq` pass.
**Phase 4 — Mutation battery** (TR5), re-timing after each.
**Phase 5 — Writers and docs.** FR8 (both blocks), FR10, FR11, FR6 readout.
**Phase 6 — ADR-155.**
**Phase 7 — Exit gate.** Full suite; `lint-rule-ids.py`; `lint-agents-enforcement-tags.py`;
aggregator smoke; **re-measure wall clock**.

## Acceptance Criteria

Every command must be exit-code-safe: `grep -c` returning 0 **exits 1**, so absence checks use
`! grep -q` (v1's would have read as harness failures).

- **AC1** Suite exits 0, ALL PASS, assertion count `>=` 23 plus new cases.
- **AC2** Deleting the exemption block reds the suite (headline mutation).
- **AC3** TR7a: the worktree corpus derives exactly the 2 expected ids. **AC3b** TR7b: fixture corpora prove per-line matching and reject a loose regex.
- **AC4** With `origin/main` unresolvable: NOT exempt, **the index is not read**, and the warn fires.
- **AC5** A `cq-*` rule carrying the marker yields NOT exempt (ack-scope containment).
- **AC6** A CRLF-bodied valid claim IS exempt; a two-claim-line body is NOT.
- **AC7** `Refs #71590` does not satisfy `#7159`.
- **AC8** `! grep -qi 'architectural-pivot deferral'` in **both** the hook and `net-issue-flow.sh`. **The `-i` is mandatory and was a measured vacuity in v1:** the hook says `architectural-pivot deferral` (lowercase) while `net-issue-flow.sh`'s header says `Architectural-pivot deferrals` (capital, plural) — measured, the case-sensitive form returns `0` on that file, so half of AC8 passed with **zero edits**. Also assert the `(d)` option and untagged-rule message in both, and that all four hook needles survive.
- **AC9** `lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` exits 0; `SECURITY_TAG_MARKERS` contains the marker.
- **AC10** Budget lint `[OK]`; both bodies under 600 B.
- **AC11** Full-gate wall clock `<= 6 s` on a 500-issue list, measured after Phase 3 and again at Phase 7; hook `timeout` is `25`; an RC=124 run emits a warn row.
- **AC12** Report prints `Mandating rules: N (<ids>, merge-base <sha>)`, an `Exempt:` line in both directions, and a `Rejected:` line naming the cause per non-exempt FILED issue.
- **AC13** `Filing:` is not reduced by exemptions (1 filed / 1 exempt → `Filing: 1`, `Net: +0`).
- **AC14** FR10's **real** template output, fed through FR3's matcher, matches (catches the `\n`-in-double-quotes defect); the template still contains `deferred-automation` and `type/chore`.
- **AC15** ship Phase 6's body template preserves `(Tracks|Refs) #N` and `gate-override` markers.
- **AC16** `rule-metrics-aggregate.sh` does not exit 5 **and** `summary.gate_exemptions` is present with per-rule counts — or, if FR6 is cut, the attribution framing is absent from the ADR and PR body.
- **AC17** ship/SKILL.md no longer claims `18 assertions` or a `transient` fail-open.
- **AC18** ADR-155 contains sections for: the class boundary, the untaggable filing-site class, the corrected ack-gate scope, the AP-017 deviation, and the honest-limitation list. *Checkable: grep the five headings.*

**Post-merge (operator): none for the feature.** One **automated** follow-through must be enrolled,
not left to memory: assert the merge-base derivation returns 2 once merged (unverifiable pre-merge
by construction — D2). v1's flat "Post-merge: None" was wrong.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The gate already fails open under load** (measured, live) | FR0; all new work in one `jq` pass; wall clock is an AC, measured twice. |
| **A failed merge-base silently self-grants via the index** | FR1 SHA guard; AC4, mutation-tested. |
| **Marker on an ungated prefix or new rule id = authority with no ack** | FR1 `^(hr\|wg)-` + FR2b; AC5. |
| **The attribution justification has no readout** | FR6 builds it, or the framing is struck. Not optional — it is what distinguishes this from a reword. |
| **The happy path is broken by Phase 6 body replacement** | FR11 + AC15. |
| **This PR is blocked by the gate it adds** (its own decision-challenge issue) | Named; this PR carries the blanket override and says so in the body. |
| **`wg-when-deferring-…` makes the gate advisory for the largest filing category** | Three reviewers challenged it; DC-1 records it with operator direction as default. **The day-zero exemption rate was never measured** — DC-1 names the one-session `gh` query that answers it. |
| **Rollout emits `Mandating rules: 0` noise** for branches open at merge | Expected and stated; the warn detail distinguishes read-failure from zero-tagged. |
| **Cheaper unattributed bypasses exist** (file-before-PR; `Closes` without closing) | Cannot be fixed here; named in the ADR so the numbers are not over-read. |

## Non-Goals

Documented in-place per `wg-when-deferring-a-capability-create-a`; none becomes an issue.

- Enforcement at the filing site (FR10 teaches the writer; enforcement stays at ship).
- Tagging the four additional qualifying candidates (recorded in the ADR).
- A general `[mandates-filing]` vocabulary validator (TR7a/b cover the failure that matters).
- Covering the untaggable SKILL.md filing sites — structurally impossible; they remain blanket-override cases by design.
- Modelling `AGENTS.rules.md` in C4; the stale "61 workflow skills" description.

## Domain Review

**Domains relevant:** Engineering. Product/UX Gate **not triggered** (mechanical UI-surface scan
over Files-to-Edit/Create: no match — bash, markdown corpus, skill docs, ADR; tier **NONE**).
GDPR **skipped** (no regulated-data surface; none of the four expansion triggers). IaC
**reviewed, no infrastructure**. Encryption Posture **skipped** (no store, no new connection).

### Engineering

**Status:** reviewed (6-agent panel). **Assessment:** the mechanism is sound and the conflict is
real, but v1 was *"strongest exactly where it did probes and weakest exactly where it reasoned
from documents"* — the ack gate's scope, CODEOWNERS enforcement, the aggregator's output, and the
hook's time budget were all asserted rather than measured, and all four were wrong in the
permissive direction. All folded in. Two findings contradict operator direction and are recorded,
not applied.

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/skills/ship/scripts/net-issue-flow.sh` | FR1, FR1b, FR3, FR4, FR5, FR6, FR8 (its own remedy block) |
| `.claude/hooks/ship-net-issue-flow-gate.sh` | FR0a/b (timeout + RC=124 telemetry), FR8 |
| `AGENTS.rules.md` | FR2 — marker on two rule **bodies** |
| `.claude/rule-body-hashes.txt`, `.claude/rule-weakening-acks.txt` | regenerated manifest + two ack rows |
| `scripts/lint-rule-bodies.py` | FR2b — `SECURITY_TAG_MARKERS` |
| `plugins/soleur/test/net-issue-flow.test.sh` | TR1, TR3, TR4, TR6, TR7a, TR7b |
| `plugins/soleur/skills/ship/SKILL.md` | FR8, FR10, FR11; `18 assertions` + `transient` corrections |
| `scripts/rule-metrics-aggregate.sh` | FR6 — `summary.gate_exemptions` |
| `scripts/followthroughs/filed-per-pr-soak-6769.sh` | fix the `rule_id net-issue-flow` lookup instruction |
| `plugins/soleur/skills/work/SKILL.md` | **FR10b — restored.** Its `gh issue create` block is a LIVE WRITER (same `\n` defect), not the prose copy v1 assumed |
| `plugins/soleur/skills/review/SKILL.md` | **FR12 — restored.** Restates the `NET > 0` threshold in prose, which FR5's arithmetic falsifies |

## Files to Create

`ADR-155-*.md`; `specs/<branch>/run-mutations.sh` + `mutations.py` (shipped in place of a
point-in-time `mutation-evidence.md`, which cannot be re-run); `specs/<branch>/tasks.md`;
`specs/<branch>/decision-challenges.md` (already written).

**Not edited (checked):** `plugins/soleur/commands/go.md` (verified **0** net-issue-flow references;
also inside an `eval-gate:block:go-routing` sentinel), `AGENTS.md` (verified pointer-only — every
non-blank line is the index sentence or a bare `- [id: …]`), `compound/SKILL.md` (advisory paraphrase
only — no remedies, no threshold arithmetic).

> **v1 listed `work/SKILL.md` and `review/SKILL.md` here and was wrong on both** — see FR10b and
> FR12. `work/SKILL.md` is the live writer for the very rule being tagged, so cutting it would have
> shipped a reader with no writer on the path that files most mandated issues.

## Sharp Edges

- **Never let a bare `:path` reach `git show`** — it reads the staged index and turns a
  fail-closed guard into an author-controlled fail-open, non-empty enough that the warn never fires.
- **The hook's `timeout` is a silent always-pass**: `RC != 1` exits 0 with no telemetry. The gate
  measured 7.7–8.1 s against `timeout 8`.
- **Adjacency is the corpus convention** (42 of 101 tags sit right after `[id:]`); 0 rule lines end
  with a tag. v1 claimed the opposite.
- **GitHub returns CRLF bodies.** A `[ \t]`-only anchor silently fails closed on a correct claim.
- **`grep -c` returning 0 exits 1** — absence ACs must use `! grep -q`.
- Rule ids are immutable; bodies only. **Any** `hr-*`/`wg-*` body edit needs an ADR-092 ack against
  the **merge-base**, and the ack file is WORM (needs a PR number that does not exist at Phase 1 —
  sequence accordingly).
- The ADR ordinal is provisional; on renumber sweep the plan **and** `tasks.md`.
- The archived `specs/feat-one-shot-6769-…/mutation-evidence.md` also says "18 assertions" — a
  point-in-time record; do **not** sweep it.
- Quoting gate-trigger tokens in plan prose can trip the plan-write IaC guard.
