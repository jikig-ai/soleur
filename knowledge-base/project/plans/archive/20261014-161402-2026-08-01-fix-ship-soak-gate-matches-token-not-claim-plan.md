---
date: 2026-08-01
type: fix
issues: [7056, 7087]
branch: feat-one-shot-7056-soak-gate-negation-strip
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
tags: [ship, gate-design, regex, false-positive, follow-through, duplication]
---

# fix: the soak-enrollment gate matches a token, not a claim (#7056, #7087)

> **Lane note.** `knowledge-base/project/specs/feat-one-shot-7056-soak-gate-negation-strip/spec.md`
> does not exist, so no `lane:` could be carried forward. Defaulted to
> `cross-domain` (TR2 fail-closed).

## Overview

`/ship` Phase 5.5's **Soak-Gated Follow-Through Enrollment Gate** blocks `gh pr ready`
and `gh pr merge --auto` when a PR (or its linked plan) declares a `post-deploy soak`
close-criterion for a tracker that is not enrolled in the follow-through sweeper. Its
signal regex leads with a **bare `soak` alternative**:

```text
SOAK_RE='soak|stays? (at )?(~?0|zero)|[0-9]+[- ]day[s]?( post-deploy| soak)|post-deploy (soak|verif|observ)|adopting[[:space:]]*(→|->|to)[[:space:]]*accepted|status[[:space:]]+flip'
```

A bare noun carries no claim, so the matcher cannot tell an assertion from its
negation, from a filename, or from the gate's own name. Two measured blocks:

| Issue | What matched | What the PR actually declared |
|---|---|---|
| **#7056** | the plan's own disclaimer — `Soak/follow-through enrollment: **not applicable** — no` | no soak; four trackers with no time-gated close criterion |
| **#7087** | the tracked filename `sandbox-canary-soak.test.sh`, in prose *disambiguating* which step builds an image | no soak; `## Post-merge` is literally `**None.**` |

Both were resolved with `<!-- gate-override: soak-followthrough-enrollment -->`. That is
the failure mode, not the remedy: #7087 records it directly — *"A blocking gate that
fires on a filename teaches operators to reach for the override reflexively, which is
strictly worse than no gate: the override then carries the authority of a considered
decision."*

This is the **third instance of one defect class** in the /ship gate family — matching a
token where a claim was meant. The Incident-PIR gate had it twice (#6813: bare
`incident` matched the `brand_survival_threshold: single-user incident` label present in
every such plan; #6665/#7003: bare `outage` matched the *names* of the
`Network-Outage` plan gate and the `Network-Outage Deep-Dive determination` heading).
That gate's remedy is the in-repo precedent this plan follows.

### Why it is worse than one override

The soak-disposition convention is real and in active use: the very plan that tripped
#7056 records *"Not applicable — trigger fired mechanically, disposition recorded rather
than skipped silently"* for its Encryption Posture section, and writes the analogous
soak disposition two sections earlier. So the better a plan documents that it needs no
soak, the more likely the gate blocks it. The cheapest way to pass becomes saying
nothing — which is exactly what the disposition-recording convention exists to prevent.

### Measured scale

Against the 40 most recent plans in `knowledge-base/project/plans/`:

| Regex | Plans that fire |
|---|---|
| current `SOAK_RE` | **21 / 40** |
| current, minus the bare `soak` alternative | **1 / 40** (and recall collapses — see §The chosen fix) |
| plans that fire **only** via bare `soak` | **20** |

Half of all recent plans carry the signal today. The gate's own name
(`Soak-Gated Follow-Through Enrollment Gate`), the sweeper script filenames
(`workspaces-luks-soak-6604.sh`, `web2-standby-soak-6459`), and plan-review decisions
(*"CUT the soak follow-through probe"*) all match.

---

## Premise Validation

Every premise cited by reference was probed before any research was dispatched.

| Premise (as given) | Probe | Verdict |
|---|---|---|
| #7056 open, unresolved | `gh issue view 7056` | **HOLDS** — `OPEN`, `closedByPullRequestsReferences: []` |
| #7087 open, unresolved | `gh issue view 7087` | **HOLDS** — `OPEN`, `deferred-scope-out` label |
| `SOAK_RE` duplicated in exactly 2 places | `grep -rn SOAK_RE` (whole repo) | **HOLDS** — `.claude/hooks/ship-soak-followthrough-gate.sh` + `plugins/soleur/skills/ship/SKILL.md`, byte-identical, plus a parity test |
| Incident-PIR gate is the precedent, merged 2026-07-23 | `git log -- scripts/ship-incident-pir-gate.sh` | **HOLDS** — commit `8466653c6`, 2026-07-23, *"fix: … and the ship Incident-PIR gate (#6798–#6802, #6813)"* |
| `sandbox-canary-soak.test.sh` is a real tracked file | `git ls-files` | **HOLDS** — `apps/web-platform/infra/sandbox-canary-soak.test.sh` |
| Dual `LC_ALL=C.UTF-8` + bare invocation must be preserved | read hook `ship-soak-followthrough-gate.sh` § soak-signal grep | **HOLDS** — the regex carries `→` (multibyte); the dual call is the locale hedge |
| Existing suite is green pre-change | `bun test …-enrollment-gate.test.ts` | **HOLDS** — 14 pass / 0 fail |

**One premise is partially STALE and is corrected below** — see Research Reconciliation
row 1. The issue frames the fix as a choice between two options; measurement shows
neither option, taken alone, closes the class. See *Alternative Approaches Considered*.

---

## Research Reconciliation — Spec vs. Codebase

| Claim as given | Reality on `origin/main` | Plan response |
|---|---|---|
| "the plan template *encourages* stating the soak disposition (`disposition recorded rather than skipped silently`)" | That exact phrase belongs to the **Encryption Posture** section of the tripping plan, not the soak section. `plan/SKILL.md` §2.9.1 is **conditional** — it mandates the *enrollment deliverable* when a soak exists and is silent about recording an N/A disposition. | The incentive-inversion argument **still holds** (a conscientious author who records the N/A gets blocked; the Observability and Encryption gates both mandate explicit N/A dispositions, so the habit is house style) — but it is a *convention* effect, not a template mandate. The fix targets the matcher, **not** the template. Amending §2.9.1 to prescribe a canonical N/A string was considered and rejected: it would couple the gate to one literal, which is the same brittleness in a new place. |
| "drop the bare `soak` alternative" is the cheapest-correct fix (#7056) | A recall survey of ~70 prose soak declarations found **17+ genuine declarations matched ONLY by bare `soak`** — `One-week soak`, `After a prod soak`, `after a 24h soak`, `when the soak holds`, `the soak window`, `1 dev-day soak`, `gated on the PR-1 soak`, `soaking, tracked #6901`. | **Reject option 1 as stated** — but the first draft's replacement (claim-shaped alternatives) was measured *worse*: recall 42→22 of 50 enrolled plans. Chosen instead: keep the bare noun, add a structural left-delimiter. Recall 41/50. See §Plan Review Revisions. |
| "strip negation contexts, mirroring the incident-PIR gate" is the alternative (#7056) | The negation strip alone leaves **#7087 unfixed** (a filename is not a negation) and leaves the gate's own name matching. | **Reject option 2 as the whole fix**, adopt it as one of two layers. Measured: it is *independently load-bearing* — see next row. The gate-name strip the first draft added alongside it was measured dead **and** harmful (it deletes the canonical enrollment heading) and is cut. |
| Implied: fixing the bare `soak` alternative is sufficient | Measured false. `No post-deploy soak is required for this change` and `no 7-day soak is needed here` still fire, via the **retained, pre-existing** `post-deploy (soak…)` and `[0-9]+[- ]day[s]?( soak)` alternatives. | Both mechanisms are required. This is the plan's central finding and is pinned by fixture `negated-criterion-soak.md`. |
| The two `SOAK_RE` copies "MUST stay byte-identical" and a drift guard would help | A drift guard already exists (`test("SOAK_RE is byte-identical …")`). Learning `2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md`: *"A parity test over two copies detects drift; one copy makes it **unrepresentable**. Prefer removing the second copy over pinning it."* | **Do not add a second drift guard — remove the second copy.** Extract the scan into `scripts/ship-soak-signal-gate.sh`, which OWNS the regex; hook + SKILL both invoke it. |
| Files in scope: SKILL.md, hook, test, hooks README | All four confirmed. `scripts/` and `plugins/soleur/test/fixtures/` additions are new. | Scope extended by 2 created paths, justified in Phase 2. |

---

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` returned no issue
whose body names any of: `plugins/soleur/skills/ship/SKILL.md`,
`.claude/hooks/ship-soak-followthrough-gate.sh`,
`plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts`,
`.claude/hooks/README.md`, `scripts/ship-incident-pir-gate.sh`.

---

## User-Brand Impact

**If this lands broken, the user experiences:** one of two failure directions, both
agent-facing rather than end-user-facing. Over-strip → the gate goes silent and a
soak-gated tracker rots open on human memory (the 2026-06-29 regression the gate was
built for: PR #5671/#5673 and PR #5675/#5689). Under-strip → `gh pr ready` keeps
denying on correct PRs and the operator keeps pasting an override, which is the
authority-laundering harm #7087 names.

**If this leaks, the user's data/workflow/money is exposed via:** no exposure vector.
The change touches a local PreToolUse matcher, a repo-root shell script, skill
documentation, and tests. No credential, no user data, no network egress, no persistent
store, no new external surface.

**Brand-survival threshold:** `none`

- `threshold: none, reason:` the diff touches no path in the canonical
  `SENSITIVE_PATH_RE` (`plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1) —
  `.claude/hooks/**`, `scripts/**`, `plugins/soleur/**` are all outside it — and the
  gate governs agent merge flow, never user-facing runtime.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Developer-workflow tooling. The decision worth naming is
*precision-vs-recall posture for a blocking gate*. The Incident-PIR gate documents
`fail-toward-PIR` (over-produce, the operator adjudicates). This gate goes the other way.

**The divergence rests on asymmetry of harm, NOT on backstops.** An earlier draft of this
plan justified it by claiming four other surfaces catch the miss-mode. That claim was
checked and is **false** — recorded here rather than quietly deleted, because the
temptation to reach for it will recur:

| Cited "backstop" | What it actually gates | Catches an unenrolled prose soak? |
|---|---|---|
| `plan` Phase 2.9.1 | proactive, honor-system; per Research Reconciliation row 1 it is *conditional* and silent on N/A | **No** — this gate exists *because* the honor system failed |
| `/ship` Phase 7 Step 3.5 | `⏳`-marked test-plan items only | **No** — `ship/SKILL.md` says verbatim that Step 3.5 misses prose soaks, which is why this gate was built. Citing it is circular |
| `follow-through-directive-gate.sh` | fires on `gh issue create --label follow-through`; validates a directive on a tracker that *already claims* enrollment | **No** — an unenrolled tracker never reaches it |
| `scheduled-followthrough-sweeper.yml` | sweeps trackers carrying the directive | **No** — sweeps only the already-enrolled set |

The real argument, which stands on its own: the **false-fire mode is measured** (two
blocks, both resolved by override) and its harm is *irreversible and epistemic* — every
reflexive override drains the meaning of the override, so the gate degrades the very
signal it depends on. The **miss-mode is hypothetical here and recoverable** — a tracker
stays open until someone notices, which is bad but fixable. Precision bias is therefore
correct, and it is deliberately the opposite call from the sibling gate.

**Accepted consequence, stated plainly:** after this change, a soak declared in a shape
that matches none of the claim alternatives has **no mechanical detector anywhere in the
repo**. The four surfaces above will not catch it. That is the price of the precision
bias, it is paid knowingly, and it must be repeated in the script header and
`.claude/hooks/README.md` — because this plan will be archived and those two files are
where the next reader looks.

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire: no path in
`## Files to Create` / `## Files to Edit` matches the UI-surface term list or glob
superset (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). Product
domain assessed **NONE**.

---

## Architecture Decision (ADR/C4)

**No ADR required.** This adopts an existing in-repo pattern (`scripts/ship-incident-pir-gate.sh`,
#6813) rather than deciding a new one; it reverses no ADR and introduces no ownership,
substrate, resolver, or trust boundary. A competent engineer reading the current ADR
corpus + C4 would not be misled about the system after this ships.

### C4 views — no impact (enumeration cited)

All three model files were **read in full**, not grepped for the feature's noun:
`knowledge-base/engineering/architecture/diagrams/{spec.c4, views.c4, model.c4}`.

| Category | Enumerated for this change | Already modeled? |
|---|---|---|
| External human actors | none introduced (`founder`, `emailSender`, `betaContact`, `contributor` unchanged) | yes — `views.c4` `view context` |
| External systems / vendors | none — the scan is pure local text→exit-code; the surrounding enrollment check's existing `gh` calls are unchanged | yes (`github`) |
| Containers / data stores | none — no store, no queue, no volume | n/a |
| Actor↔surface access relationships | none — no change to who may run or bypass the gate; the override token and env escape are unchanged | n/a |
| Components touched | `platform.engine.hooks` ("Hook Engine", `model.c4`) and `platform.plugin.ship` ("ship skill", `model.c4`) | **yes** — both already declared and both already in `views.c4` `view components of platform.plugin` |

The change alters a matcher *inside* two already-modeled components and adds no element,
no `#external` tag, no relationship edge, and no `view … include` line. No element
description is falsified by it. **No `.c4` edit is in scope.**

---

## Observability

```yaml
liveness_signal:
  what: emit_incident wg-pm-class-followthrough-for-operator-dogfood, on FOUR outcomes — deny, override, fault, scanner-missing. Today it fires on deny ONLY, which is why the gate cannot currently observe its own dark mode; adding the other three is in scope (Phase 3).
  cadence: per `gh pr ready` / `gh pr merge --auto` invocation
  alert_target: .rule-incidents.jsonl, consumed by the weekly rule-usage aggregator
  configured_in: .claude/hooks/ship-soak-followthrough-gate.sh
error_reporting:
  destination: hook stderr, surfaced inline to the agent as the deny reason; plus the incidents ledger
  fail_loud: deny path yes. Fail-OPEN paths (scanner missing, scanner fault) currently exit 0 silently — this plan makes each emit a stderr line and an incident record, because after extraction "gate dark" becomes a live mode that is byte-identical to "gate passed"
failure_modes:
  - mode: over-strip / silenced matcher — real enrolments stop signalling
    detection: AC1's recall floor over the ground-truth enrolled set, run in CI; plus the FIRE-direction fixtures and the widening/span-swap mutants in the AC18 matrix
    alert_route: CI test job on every PR
  - mode: under-strip — the gate keeps denying correct PRs
    detection: AC2's bounded FP ratio + the QUIET-direction fixtures
    alert_route: CI test job on every PR
  - mode: scanner absent or non-executable (new single point of failure created by the extraction)
    detection: hook emits stderr + an incident record and fails open; AC12 asserts both; AC17 asserts the script exists and is executable
    alert_route: incidents ledger + CI
  - mode: scanner harness fault (a strip stage errors) reading as a clean no-signal
    detection: reserved exit 2 with a distinct hook arm; AC11 asserts a fault exits 2, never 1
    alert_route: incidents ledger + CI
  - mode: override fires without an operator decision (a PR that merely quotes the token)
    detection: AC13 + the anchored, post-strip override check; emit_incident on every override
    alert_route: incidents ledger
logs:
  where: .rule-incidents.jsonl (repo-local, gitignored); the deny text in the agent transcript
  retention: existing incidents.sh rotation; unchanged
discoverability_test:
  command: "printf 'op:founder-ambiguous stays at ~0 for 7 days post-deploy\\n' | bash scripts/ship-soak-signal-gate.sh; echo \"exit=$?\""
  expected_output: "SOAK-SIGNAL: yes + the matched line, exit=0. And for `printf 'Soak/follow-through enrollment: **not applicable**\\n' | …` -> no stdout, exit=1."
```

No `ssh` anywhere in the discoverability test.

### Soak Follow-Through Enrollment

Not applicable — this plan declares no time-gated close criterion. #7056 and #7087 close
when the fixed matcher lands and its fixtures pass; there is nothing to observe after
deploy. Disposition recorded rather than skipped silently.

> Under the **current** matcher this paragraph trips the gate. Under the fixed matcher it
> still may, because the chosen design keeps the bare noun — and that is accepted, not a
> bug: draft 1 eliminated the self-trip with a gate-name strip that silenced real
> enrolments (§Plan Review Revisions R5). The override exists for gate-editing PRs and,
> used there, it means something.

---

## Encryption Posture

Not applicable — the plan introduces no persistent store and no new cross-component
connection. Detection did not fire: no `.tf`, no `supabase/migrations/*.sql`, no
`cloud-init*.yaml`, no `docker-compose*.yaml` in scope. Disposition recorded rather than
skipped silently.

---

## The chosen fix

> **This section was rewritten after plan review.** The first draft proposed replacing
> the bare `soak` noun with ~6 "claim-shaped" alternatives. Measured against ground
> truth, that design **darkened the gate on 28 of 50 really-enrolled plans**. It is
> rejected. See §Plan Review Revisions for the full reversal and the measurement that
> forced it — the wrong design is recorded there rather than deleted, because the
> reasoning that produced it was superficially compelling and will recur.

**Two layers, plus one strip already present.** Both are measured against a real
positive set, not a curated phrase list:

1. **A structural left-delimiter on the bare noun.** Keep the bare `soak` alternative —
   it carries the recall — but refuse to match it glued to an identifier:
   `(^|[^[:alnum:]_-])soak`. One character class retires the entire filename/identifier
   class (`sandbox-canary-soak.test.sh`, `workspaces-luks-soak-6604.sh`,
   `web2-standby-soak-6459`) in a single stroke — **this is the whole of #7087's fix**.
   It is the structural-delimiter discipline of
   `knowledge-base/project/learnings/2026-05-07-post-build-token-gates-false-positive-on-worktree-paths.md`
   (*"Prefer tokens with structural delimiters … over bare substrings"*).
2. **Negation stripping — as a SPAN, not a line.** Remove text where a negation
   **directly governs** the soak (within 3 tokens) or where an explicit
   `not applicable` / `N/A` / `none` disposition is recorded. This is **#7056's fix**,
   and it is independently load-bearing: `No post-deploy soak is required` and
   `no 7-day soak is needed here` fire through *retained, pre-existing* alternatives
   that no amount of noun-shaping can reach.

   **Span removal (`sed`), never whole-line `grep -v`.** A line-drop swallows any real
   declaration sharing a line with a disposition — measured:
   `Soak enrollment: none yet — the 14-day soak begins at deploy.` and
   `No soak is needed for the docs half; the runtime half stays at ~0 for 7 days post-deploy`
   both go **dark** under a line-drop and both **fire** correctly under span removal.
   PR bodies are not hard-wrapped, so long mixed lines are the norm, not the exception.
3. **Inline `` `code` `` span stripping** *(new, one `sed`)* — mirrors the precedent's
   stage 2 (*"same reason, for backticked tokens"*). Helps #7087 and keeps quoted
   regexes/filenames as data.

Fenced-code stripping already exists and moves into the script (see Phase 2).

### Two layers from the first draft were measured and CUT

- **Claim-shaping (an enumerated whitelist of nouns that may follow `soak`).** Cut. It
  is an open-ended maintenance tax where every unanticipated phrasing is a *silent*
  detection loss with no failing test — and it already missed the repo's own word for
  the deliverable (`the soak probe`). Measured cost: recall **42 → 22** of 50.
- **The gate's-own-name strip.** Cut, for two independent reasons. It is **dead code**
  once the bare noun is delimited (six probe strings containing the gate name in every
  form produce identical verdicts with and without it), and it is **actively harmful**:
  `Soak follow-through enrollment` is not only the gate's name, it is the canonical
  **section heading real plans use to declare enrollment** (`### Soak follow-through
  enrollment (Phase 2.9.1)`). Stripping it deletes a true positive.

### The precedent, cited from the source

`scripts/ship-incident-pir-gate.sh` builds its haystack through a four-stage strip
before matching, and its comment block states the reasoning verbatim:

```bash
haystack="$(cat \
  | awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; next} !f{print}' \
  | sed 's/`[^`]*`//g' \
  | sed -E 's/[Nn]etwork-[Oo]utage//g' \
  | grep -vaiE '^brand_survival_threshold:|Brand-survival threshold:|If this lands broken|If this leaks|if this lands|would break|could break|Network-Outage Deep-Dive')"
```

Stage 1 strips fences (*"regexes/config/SQL quoted in a plan are DATA, not an incident
report"*), stage 2 strips inline code spans (*"same reason, for backticked tokens"*),
stage 3 strips the gate's NAME (*"Gate NAMES are stripped below (not added to a negative
lookahead) so the token cannot reach OUTAGE_RE at all"*), stage 4 strips structural
labels and hypothetical framing. Crucially, the same file also **removed the bare token
outright** — `# Past-tense … NO bare 'incident' (it matches the threshold literal and
'incidental')`. The precedent did **both** things the issue offers as alternatives.
`ship/SKILL.md` invokes it as:

```bash
if printf '%s\n%s' "$PR_TEXT" "$PLAN_TEXT" | bash "${CLAUDE_PLUGIN_ROOT:-.}/../../scripts/ship-incident-pir-gate.sh"; then
```

and `plugins/soleur/test/ship-incident-pir-gate.test.ts` `spawnSync`s the **shipped**
script against 9 both-direction fixtures — *"a drift between the tested gate and the
shipped gate is structurally impossible."*

### Verified candidate

Derived and measured during planning (Phase 1 re-derives and re-measures; treat this as
a verified starting point, **not** a frozen literal):

```bash
# ONE alternative changed from the shipped regex: the bare noun gains a structural
# left-delimiter, retiring the whole filename/identifier class (#7087). Everything
# else is byte-identical to what ships today.
SOAK_RE='(^|[^[:alnum:]_-])soak|stays? (at )?(~?0|zero)|[0-9]+[- ]day[s]?( post-deploy| soak)|post-deploy (soak|verif|observ)|adopting[[:space:]]*(→|->|to)[[:space:]]*accepted|status[[:space:]]+flip'

# Negation must DIRECTLY govern the soak (<=3 tokens), or be an explicit disposition.
# Applied as a SPAN removal via sed, never a line drop (see §The chosen fix).
# Delimiter is @ — NEGATION_RE contains `n/a`, so s/…/…/ is a syntax error.
# Case is inlined per-class: sed has no -i equivalent.
NEGATION_RE='(^|[[:space:]])[Nn][Oo][[:space:]]+([[:alnum:]#~._-]+[[:space:]]+){0,3}[Ss][Oo][Aa][Kk]|[Ss][Oo][Aa][Kk][^.]{0,50}([Nn]ot applicable|[Nn]ot needed|[Nn]ot required|[Nn]/[Aa])|([Ss][Oo][Aa][Kk]|[Ff]ollow-[Tt]hrough)[^:]{0,40}:[[:space:]]*(\*\*)?[[:space:]]*([Nn]ot applicable|[Nn]/[Aa]|[Nn]one)'
```

Pipeline: fences (fail-closed) → inline `` `code` `` → `NEGATION_RE` span removal →
`SOAK_RE`. Measured during planning against **ground truth**, not a curated phrase list.

**Ground truth = the 50 plans that actually enrol a probe**
(`grep -rlE 'scripts/followthroughs/[a-z0-9-]+\.sh' knowledge-base/project/plans/*.md`).
This is a free, real, in-repo positive set. Recall against it is the number that matters,
because the gate's worst failure is going dark.

| Design | Recall (of 50 enrolled) | FP proxy (40 recent plans) |
|---|---|---|
| shipped regex today | 42 / 50 | 21 / 40 |
| issue option 1 (delete bare `soak`) | ~4 / 50 | 1 / 40 |
| **first draft — claim-shaped, 3 layers** | **22 / 50** ❌ | 5 / 40 |
| **chosen — delimiter + span-negation** | **41 / 50** ✅ | **14 / 40** |

The chosen design holds recall flat (−1 vs today) while cutting false positives by a
third. The first draft bought its low FP number by silencing more than half the real
enrolments — and its ACs all passed anyway, which is the deeper lesson recorded in
§Plan Review Revisions.

**Decisive cases, all verified:**

| Input | Verdict |
|---|---|
| `Soak/follow-through enrollment: **not applicable** — no time-gated close criterion.` | QUIET ✅ (#7056) |
| `` not at `sandbox-canary-soak.test.sh`, which builds nothing `` | QUIET ✅ (#7087) |
| `not at sandbox-canary-soak.test.sh` (un-backticked) | QUIET ✅ (delimiter, not the strip) |
| `No post-deploy soak is required for this change` | QUIET ✅ |
| `op:founder-ambiguous stays at ~0 for 7 days post-deploy` | FIRE ✅ |
| `Soak enrollment: none yet — the 14-day soak begins at deploy.` | FIRE ✅ (span, not line) |
| `No soak is needed for the docs half; the runtime half stays at ~0 for 7 days post-deploy` | FIRE ✅ (span, not line) |
| `### Soak follow-through enrollment (Phase 2.9.1)` | FIRE ✅ (no gate-name strip) |

**Retroactive application, measured at plan time** (`wg-when-fixing-a-workflow-gates-detection`
— the two real PRs this gate wrongly blocked):

| Plan | current matcher | fixed pipeline |
|---|---|---|
| #7034 — `2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md` | **1 hit → BLOCKS** (the #7056 report) | **0 hits → passes** |
| #7072 — `2026-07-29-chore-triage-seven-orphan-infra-suites-plan.md` | **2 hits → BLOCKS** (the #7087 report) | **0 hits → passes** |

Both false positives are retired by the design as specified. AC11 re-runs this against the
*shipped* script rather than the planning pipeline.

---

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/ship-soak-signal-gate.sh` | The scan. stdin → exit 0 + `SOAK-SIGNAL: yes` when a soak is CLAIMED; exit 1 silently otherwise. **Owns** `SOAK_RE` + the strips. Sibling of `scripts/ship-incident-pir-gate.sh`; distinct basename from the hook so the two are never confused. |
| `plugins/soleur/test/fixtures/ship-soak-signal-gate/*.md` | 12 synthesized both-direction fixtures (enumerated in Test Scenarios). Named after the **script**, per the PIR precedent. |
| `.claude/hooks/ship-soak-followthrough-gate.test.sh` | Composed-seam test driving the **hook** end-to-end with a `gh` stub (AC15). Precedent: `.claude/hooks/ship-unpushed-commits-gate.test.sh`. Register in `scripts/test-all.sh`. |

## Files to Edit

| Path | Change |
|---|---|
| `.claude/hooks/ship-soak-followthrough-gate.sh` | Pipe the raw corpus into the script (the script owns all strips — delete the local fence awk). Resolve via `git rev-parse --show-toplevel`. Three-valued exit branch; loud fail-open. Anchor the override check and run it after the strips. Guard the plan path against `..`. Fold hit-lines into the deny text. Fix the truncated `emit_incident` reason (R7). |
| `plugins/soleur/skills/ship/SKILL.md` | Replace the §Detection `SOAK_RE=` + `SOAK_HIT=` block with the script invocation, mirroring the Incident-PIR call shape at §"Incident-signal scan". Add a `**Why:**` sentence citing #7056 + #7087. |
| `plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts` | Delete the `soakRe()` scraper and the byte-identity parity test (the second copy is gone — parity is unrepresentable, not asserted). Add a `spawnSync` harness over the shipped script + the 11 fixtures. Re-anchor the two prose assertions that referenced `SOAK_RE=`. |
| `.claude/hooks/README.md` | Rewrite the `SOAK_RE is kept **byte-identical**…` bullet to describe single ownership; add the false-positive history + the `SOAK-SIGNAL` exit contract. |

---

## Implementation Phases

### Phase 0 — Preconditions (no edits)

1. Baseline both suites green: `bun test plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts` (14 pass) and `…/ship-incident-pir-gate.test.ts`.
2. **Re-measure the two baselines that every AC is relative to**, on current `main`:
   recall of the shipped regex over the ground-truth enrolled set (plan time: 42/50) and
   its FP count over the 40-plan window (plan time: 21/40). Record both.
3. Read `scripts/ship-incident-pir-gate.sh` end to end. Mirror: `set -uo pipefail`,
   herestring-not-pipe for `grep -q`, and its exit discipline. Do **not** mirror its fence
   awk (no `END` check → fails open) or its `${CLAUDE_PLUGIN_ROOT:-.}` path fallback
   (resolves outside the checkout).

### Phase 1 — RED: fixtures and harness first

Per `cq-write-failing-tests-before`.

1. Author the 11 synthesized fixtures under
   `plugins/soleur/test/fixtures/ship-soak-signal-gate/` plus
   `backticked-declaration-known-bypass.md`. No real emails, prod-shape UUIDs, or tokens;
   never copy #7034's or #7072's real plan (`cq-test-fixtures-synthesized-only`).
2. Add the `spawnSync` harness (FIRE ⇒ status 0 + marker; QUIET ⇒ status **exactly** 1;
   empty stderr both ways).
3. Add the **measurement harness** for AC1/AC2 — a scratch runner that scores any
   candidate matcher against the ground-truth set and the FP window in one pass. This is
   what makes the recall floor executable, and it must exist before any regex is written.
4. Confirm RED.

### Phase 2 — GREEN: extract the scan into a script that owns the regex AND all strips

1. Create `scripts/ship-soak-signal-gate.sh`. Header comment: what it is, the #7056/#7087
   false positives it retires, the exit contract, the accepted backtick-bypass residual,
   the "an unenrolled prose soak has no other mechanical detector" consequence, and *why
   each strip stage exists*.
2. **The script owns every strip; consumers pipe raw text.** Stages: fences (indent-tolerant
   anchor `/^[[:space:]]*```/` **with** `END { if (f) exit 2 }` and a fail-closed fallback
   to the unstripped body) → inline `` `code` `` spans (single-quoted `sed`, SC2016 note)
   → `NEGATION_RE` **span** removal (`sed -E "s@…@@g"`, case inlined). No gate-name strip.
3. Match with `grep -aiE` under `LC_ALL=C.UTF-8`, then again under `LC_ALL=C` (the current
   "bare" second pass is not a C-locale fallback at all in a UTF-8 env, so the hedge it
   claims does not exist today). `-a` on every grep.
4. Exit contract: **0** = signal → print `SOAK-SIGNAL: yes` **plus** the matched lines;
   **1** = clean no-signal, no stdout; **2** = harness fault (a strip stage failed).
   Check each stage's status rather than inferring fault from an empty haystack.
5. `chmod +x`. Confirm GREEN on all fixtures, then run the AC18 mutation matrix.

Rationale for extraction over a second parity guard
(`2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md`):
*"A parity test over two copies detects drift; one copy makes it unrepresentable. Prefer
removing the second copy over pinning it."* Moving **all** strips (not just the regex)
is what honours that — draft 1 would have taken fence-strip copies from 2 to 3 while
deleting the only parity pin.

### Phase 3 — Wire the two consumers

1. **Hook.** Resolve the script via `"$(git rev-parse --show-toplevel)/scripts/…"`. Delete
   the local fence-strip awk from the `CORPUS` build (the script owns it now); keep only
   body fetch + plan resolution + append. Guard the plan path against traversal
   (`[[ "$PLAN" == *..* ]] && PLAN=""`). Branch on exit: 0 → enrollment check; 1 → exit 0;
   ≥2 → stderr + `emit_incident … fault` → exit 0. Missing script → stderr +
   `emit_incident` → exit 0. Fold the script's stdout hit-lines into the deny `REASON`.
2. **Hook, override check.** Move it *after* the strips and anchor it to a standalone
   line: `grep -qE '^[[:space:]]*<!--[[:space:]]*gate-override:[[:space:]]*soak-followthrough-enrollment[[:space:]]*-->[[:space:]]*$'`,
   and `emit_incident … override` when it fires.
3. **SKILL.md.** Same invocation and same override check (the twins currently disagree —
   the SKILL has no mechanical override or env check at all). Keep the `COMBINED` corpus
   assembly minus the fence awk. Add the `**Why:**` sentence citing #7056 + #7087 and the
   measured recall/FP numbers.

**Phase order is load-bearing:** the script (contract producer) must exist before its
consumers are rewired.

### Phase 4 — Docs, tests, retroactive application

1. `.claude/hooks/README.md`: replace the byte-identity bullet with single-ownership + the
   three-valued exit contract + the named backtick-bypass residual + the "no other
   mechanical detector" consequence.
2. Delete the `soakRe()` scraper and the byte-identity parity test. Replace the two prose
   assertions with anchors a comment cannot satisfy: `gateSection` must contain
   `ship-soak-signal-gate.sh` **and** `SOAK-SIGNAL`, both in the AC18 matrix.
3. Add `.claude/hooks/ship-soak-followthrough-gate.test.sh` (AC15) and register it in
   `scripts/test-all.sh`.
4. Fix the hook's truncated `emit_incident` reason string (R7).
5. Retroactive application (AC21) + full suite.

## Acceptance Criteria

### Pre-merge (PR)

**Recall first.** The gate's worst failure is going dark, and the first draft of this plan
proved that a precision-only AC set passes with a silenced matcher. AC1 is therefore the
primary gate.

- **AC1 — RECALL FLOOR (primary).** Over the ground-truth positive set
  `grep -rlE 'scripts/followthroughs/[a-z0-9-]+\.sh' knowledge-base/project/plans/*.md`,
  the shipped script signals on **no fewer plans than the currently-shipped regex does**,
  measured in the same run over the same set. Baseline at plan time: **42 / 50**; chosen
  design: **41 / 50**, so the AC is stated as `new >= old - 1`. A matcher that silences
  real enrolments fails this even if every other AC passes.
- **AC2 — PRECISION, as a bounded ratio with a non-zero floor.** Over the same 40-plan
  window, measuring old and new in one run: `new < old && new >= 1`. Baseline 21; chosen
  design 14. Do **not** pin an absolute count — measured across six sliding windows the
  absolute number ranges 5–11, so a fixed `≤6` is a snapshot, not an invariant. The
  `new >= 1` floor is what makes a dark gate fail this AC.
- **AC3 — the #7056 required pair.** A plan declaring a real soak exits 0 with
  `SOAK-SIGNAL: yes`; a plan declaring `Soak/follow-through enrollment: not applicable`
  exits 1 with empty stdout.
- **AC4 — the #7087 pair.** A plan whose only soak token is the filename
  `sandbox-canary-soak.test.sh` exits 1 — in **both** the backticked and the bare form.
  The bare form is the one that proves the structural delimiter, not the code-span strip.
- **AC5 — negated criterion.** `No post-deploy soak is required` and
  `no 7-day soak is needed here` exit 1, proving the negation strip reaches claims that
  fire through *retained* alternatives.
- **AC6 — the negation strip is a SPAN, not a line.**
  `Soak enrollment: none yet — the 14-day soak begins at deploy.` and
  `No soak is needed for the docs half; the runtime half stays at ~0 for 7 days post-deploy`
  both exit **0**. Mutation: swapping the `sed` span removal for `grep -v` must turn this
  RED. This is the highest-value single assertion in the set — under a line drop both
  strings go silently dark.
- **AC7 — strip bound.** `no P0 incidents during the 7-day soak` exits 0 (the ≤3-token
  bound). Mutation: widening to `{0,6}` must turn it RED.
- **AC8 — the canonical enrollment heading still fires.**
  `### Soak follow-through enrollment (Phase 2.9.1)` — the heading real plans use to
  *declare* enrollment — exits 0. Mutation: adding any gate-name strip must turn this RED.
- **AC9 — fence strip is load-bearing and fail-CLOSED.** (a) A soak claim inside a
  balanced fence exits 1. (b) A soak claim after an **unbalanced** (unclosed) fence exits
  **0** — the fail-closed fallback to the unstripped body. Mutation: dropping
  `END { if (f) exit 2 }` must turn (b) RED. Do not copy the precedent's awk verbatim: it
  has no `END` check and fails *open* here.
- **AC10 — inline-code strip is load-bearing.** A soak claim appearing only inside a
  backtick span exits 1.
- **AC11 — exit contract is three-valued and each value has a reader.**
  `printf 'nothing\n' | bash <script>` exits exactly **1** with empty stdout. A harness
  fault (e.g. `PATH` without `awk`) exits **2**, never 1. The hook distinguishes them:
  0 → enrollment check, 1 → silent pass, ≥2 → stderr line + `emit_incident … fault`,
  then fail-open. Mutation: collapsing the `*)` arm into `1)` must turn this RED.
- **AC12 — missing script is loud.** With the script absent the hook exits 0 (fail-open,
  never crash an operator's merge) **and** emits a stderr line naming the resolved path
  **and** an `emit_incident` record. A gate that goes dark identically to a gate that
  passes is the failure shape this whole plan is about.
- **AC13 — the override cannot be triggered by quoting it.** A PR body that *mentions*
  `gate-override: soak-followthrough-enrollment` inside a fence or a backtick span does
  **not** bypass the gate; a body carrying the HTML comment on its own line does, and
  emits an `emit_incident … override` record. Today the check is an unanchored substring
  grep against the **raw** body, so this plan — which quotes the token repeatedly — would
  self-bypass the hook entirely, and no script-level AC could ever see it.
- **AC14 — path resolution is inside the current checkout.** Both consumers resolve the
  script via `"$(git rev-parse --show-toplevel)/scripts/…"`. Assert, with
  `CLAUDE_PLUGIN_ROOT` unset and cwd at (a) the repo root and (b) this worktree, that the
  resolved path exists and lies inside the *current* checkout. The precedent's
  `${CLAUDE_PLUGIN_ROOT:-.}/../../scripts/` resolves to the **main checkout** from a
  worktree (violating `hr-when-in-a-worktree-never-read-from-bare`) and to two levels
  *above* the repo from a plain root — where `bash` exits 127 and the gate goes silently
  dark. Do not mirror it.
- **AC15 — the composed hook path is executed by a test**, not just the script. Add
  `.claude/hooks/ship-soak-followthrough-gate.test.sh` (precedent:
  `.claude/hooks/ship-unpushed-commits-gate.test.sh`) with a `gh` stub on `PATH`, covering
  AC12, AC13, AC11's fault arm, deny-with-hit-lines, and allow-when-enrolled. Register it
  in `scripts/test-all.sh`. AC3–AC11 test the unit; this tests the seam.
- **AC16 — diagnosability.** On a signal the script emits the matched lines alongside the
  marker, and the hook folds them into the deny text. Because the strips *delete* text,
  either blank stripped lines instead of dropping them (to keep offsets true) or emit
  matched **text** without line numbers — pick one explicitly and say which. Silently
  wrong line numbers on a diagnostic gate are worse than none.
- **AC17 — single ownership.**
  `git grep -lE "^[[:space:]]*SOAK_RE=" -- '*.sh' 'plugins/**' '.claude/**' | wc -l` → **1**,
  and that path is the new script. Scoped to executable surfaces: `knowledge-base/**` is
  deliberately excluded because plans quote regexes as data — this plan file itself
  carries two column-0 `SOAK_RE=` lines inside fences.
- **AC18 — mutation matrix is executable.** Ship a committed table
  `mutant-id | operator (delete-alternative | delete-stage | widen-bound | swap-span-for-line) | target | expected-killer-fixture`,
  with every fixture named as an expected killer at least once. Any fixture with no killer
  row is deleted. Deletion-only mutants model under-strip; the dark-gate mode needs the
  widening and span→line operators.
- **AC19 — binary-safe.** Every `grep` in the new script passes `-a`. A corpus containing
  a NUL byte still fires. (`grep` resolves to GNU grep in the hook but to a `ugrep`
  wrapper with `-I` on the agent's Bash path; without `-a` the two disagree and the
  SKILL path goes silent.)
- **AC20 — full suite green:** `bash scripts/test-all.sh`.
- **AC21 — retroactive application** (`wg-when-fixing-a-workflow-gates-detection`): the
  #7034 plan (`knowledge-base/project/plans/2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md`)
  and the #7072 plan (`knowledge-base/project/plans/2026-07-29-chore-triage-seven-orphan-infra-suites-plan.md`)
  each exit 1 through the shipped script. Note both are **PRs**, not issues.
- **AC22** — PR body carries `Closes #7056` and `Closes #7087` (body, not title, per
  `wg-use-closes-n-in-pr-body-not-title-to`), and records the measured recall/precision
  numbers, the mutation matrix, and the AC21 result.

### Post-merge (operator)

**None.** No infrastructure, no migration, no vendor state, no secret.

---

## Test Scenarios

All fixtures live in `plugins/soleur/test/fixtures/ship-soak-signal-gate/` — named after
the **script** under test, matching the PIR precedent's `fixtures/ship-incident-pir-gate`,
not after the hook. All are **synthesized** plan-shaped prose
(`cq-test-fixtures-synthesized-only`); the real #7034/#7072 plans are used read-only in
AC21 and are never copied in.

| Fixture | Direction | Pins | Killer for mutant |
|---|---|---|---|
| `real-soak-declaration.md` | **FIRE** | numeric-window claim | smoke only — no mutant; kept as the AC3 positive |
| `soak-disposition-not-applicable.md` | QUIET | disposition strip (#7056 pair) | `delete-stage:negation` |
| `soak-filename-backticked.md` | QUIET | inline-code strip | `delete-stage:inline-code` |
| `soak-filename-bare.md` | QUIET | **structural left-delimiter** (#7087's real fix) | `delete-alternative:delimiter` |
| `negated-criterion-soak.md` | QUIET | negation reaching *retained* alternatives | `delete-stage:negation` |
| `negation-span-not-line.md` | **FIRE** | span removal vs line drop | `swap-span-for-line` |
| `negation-adjacent-real-soak.md` | **FIRE** | the ≤3-token bound | `widen-bound:{0,3}->{0,6}` |
| `enrollment-heading-fires.md` | **FIRE** | no gate-name strip exists | `add-stage:gatename` |
| `fenced-claim-quiet.md` | QUIET | fence strip is load-bearing | `delete-stage:fence` |
| `unbalanced-fence-real-soak.md` | **FIRE** | fail-CLOSED fallback | `delete-clause:END-exit-2` |
| `binary-corpus-real-soak.md` | **FIRE** | `grep -a` on every stage | `delete-flag:-a` |

Harness contract (mirrors `ship-incident-pir-gate.test.ts`): FIRE ⇒ `status === 0` **and**
stdout contains `SOAK-SIGNAL: yes`; QUIET ⇒ `status === 1` **exactly** (never merely
non-zero — a crash, a `spawnSync` failure, and a bash syntax error all produce non-zero,
and under a "non-zero" assertion every one of them reads as a clean pass while the gate is
dead). Assert empty **stderr** in both directions too: a `sed`/`grep` warning is the
symptom of a malformed strip. Each fixture is fed independently via stdin.

Two things the fixture set deliberately does **not** cover, recorded so they are choices
rather than oversights:

- **The backtick bypass.** Wrapping a real declaration in `` ` `` makes it invisible.
  This is an accepted, *named* residual — the gate already ships two sanctioned bypasses
  (the HTML-comment override and the env escape), and the adversary here is an agent
  taking the cheapest path, not an attacker. Pinned by `backticked-declaration-known-bypass.md`
  (QUIET) and named in the script header + `.claude/hooks/README.md` so the bypass is
  *legible*, which is #7087's actual lesson.
- **Span-join synthesis.** Removing a span can in principle join surrounding text into a
  new match. No case was constructible, and it errs toward firing rather than dark, but
  the fixture set should probe it once.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Over-strip → the gate goes dark.** The highest-cost mode, and draft 1 demonstrates it is not hypothetical: it silenced 28 of 50 real enrolments while every AC passed. | **AC1** makes recall over the ground-truth enrolled set the primary, CI-run gate — the only assertion that could have caught draft 1. Plus five FIRE-direction fixtures and the widening / span→line mutants in AC18's matrix. AC2's `new >= 1` floor means a matcher signalling on nothing also fails. |
| **The extraction creates a new single point of failure.** The regex cannot be absent today; after this it can. `scripts/` is agent-writable, and deleting the scanner is cheaper for a blocked agent than enrolling a tracker — and leaves no artifact in the PR body. | Fail-open (never crash an operator's merge) but **loud**: stderr + `emit_incident` on both the missing-script and fault arms (AC12, AC11). AC17 pins existence + exec bit. |
| **The extraction moves the bug into the seam.** *"Extracting verdict logic into a tested script and leaving the glue untested moves the bug, it doesn't kill it."* | **AC15** adds a composed hook-level test with a `gh` stub — AC3–AC11 test the unit, AC15 tests the seam. This matters more than usual because the quoted-override bypass (AC13) is invisible to any script-level test. |
| **The gate's green path has never been exercised.** The current suite string-matches Markdown and has never run the matcher. | The new harness runs the shipped script in both directions; the hook test runs the composed path. First time this gate's decision logic is executed by a test at all. |
| **`set -eo pipefail` in the hook misreading a clean `exit 1` as failure.** | Branch on the exit inside a `case`, never letting `set -e` see it; a reserved exit 2 keeps "fault" distinguishable from "no signal". |
| **Fence-strip copies going 2 → 3 while the only parity guard is deleted**, with the script and the hook using different anchors and desyncing. | The script owns **all** strips; consumers stop stripping entirely. One anchor, one fail-closed rule, no desync — and it makes AC9 true of the composed path, not just the unit. |
| **Basename confusion** between the hook and the scanner. | Distinct basename `ship-soak-signal-gate.sh`; fixtures directory named after the script; both headers cross-reference. |
| **The enrollment triad remains duplicated** between hook and SKILL and is now unguarded (the parity test is deleted). | Out of scope for this PR and stated as such rather than left silent. If it is not extracted here, file it — do not describe the drift surface as closed. |

---

## Plan Review Revisions

Recorded rather than silently rewritten, because the reversal is the most useful thing in
this document.

**R1 — the first draft's central design was wrong, and its own ACs could not see it.**
Draft 1 replaced the bare `soak` noun with ~6 "claim-shaped" alternatives (adjacency to a
duration, a temporal preposition, or a state verb), plus a gate-name strip. It was
verified against a hand-curated 19-phrase positive list and a 40-plan false-positive
window, and it passed everything: 19/19 positives, 10/10 negatives, FP rate 21→5, and a
clean self-pass.

Plan review measured it against a positive set the draft never used — the 50 plans that
actually enrol a probe — and found recall had collapsed from **42/50 to 22/50**. The
design was silencing more than half of all real enrolments, which is precisely the
"gate goes dark" mode the draft's own Risks table called the regression the gate exists
to prevent.

Two mechanisms, both self-inflicted:

- the noun whitelist did not include `probe`, the repo's own word for the deliverable
  (`measured at day 7 by the soak probe`);
- the gate-name strip deleted `Soak follow-through enrollment` — which is not merely the
  gate's name but the **canonical heading plans use to declare enrollment**. In at least
  one really-enrolled plan that heading is the *only* soak token in the file.

**The generalisable failure:** the draft measured *precision* on a real corpus and
*recall* on a list it had written itself. A positive set derived from the same reasoning
as the matcher cannot falsify the matcher. The ground-truth set was free, in-repo, and
one `grep` away the whole time. AC1 now makes recall the primary gate so this cannot
recur.

**R2 — layers cut.** Claim-shaping and the gate-name strip are removed. #7087 is fixed
by a single character class (`(^|[^[:alnum:]_-])soak`) that refuses hyphen-glued matches;
#7056 is fixed by the negation strip. Net matcher change: **one alternative edited, one
strip added** — against ~700 characters of regex in draft 1.

**R3 — the negation strip became a span removal.** Draft 1 dropped whole lines. Measured:
that silently darks `Soak enrollment: none yet — the 14-day soak begins at deploy.`

**R4 — AC set rebuilt around recall.** Draft 1's AC9 pinned an absolute FP count (`≤6`)
with no recall floor — a matcher signalling on *nothing* satisfied it. Replaced by AC1
(recall floor vs the shipped regex) and AC2 (bounded FP ratio with a `>= 1` floor).

**R5 — AC10 (the PR must not block itself) is dropped as a requirement.** It was a
plan-generated goal appearing in no issue, and it was the direct driver of the gate-name
strip. The precedent gate explicitly accepts this residual for its own subject-matter
PRs. The override exists for exactly this case.

**R6 — seam findings folded in** (path resolution via `git rev-parse --show-toplevel`;
three-valued exit contract with a reader for each value; loud fail-open; anchored
override check; composed hook-level test; `grep -a` everywhere; span-safe `sed`
delimiter). Each is an AC above.

**R7 — an unrelated bug found in the hook while reading it.** Its `emit_incident` call
passes a truncated, copy-pasted reason string belonging to a different rule
(`"PRs adding operator-only routes, cross-origin form-POST, c"` — cut mid-word). Fix
inline while the file is open; it also invalidates the `## Observability` block, which
cites this call as the liveness signal.

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.**
- **Recall is the axis that matters, and it is the one a precision AC cannot see.** The
  first draft of this plan scored 5/40 on false positives — its best number — while
  silencing 28 of 50 real enrolments, and *every one of its 21 ACs passed*. Any future
  change to this matcher must be measured against the ground-truth positive set
  (`grep -rlE 'scripts/followthroughs/[a-z0-9-]+\.sh' knowledge-base/project/plans/*.md`)
  before it is measured against anything else. AC1 exists to make that non-optional.
- **An enumerated whitelist of nouns that may follow `soak` is a permanent, silent
  maintenance tax.** Every unanticipated phrasing becomes a detection loss with no
  failing test. The first draft's whitelist already missed `probe` — the repo's own word
  for the enrollment deliverable. Do not reintroduce it.
- **`Soak follow-through enrollment` is a section HEADING, not just the gate's name.**
  Real plans use it to *declare* enrollment (`### Soak follow-through enrollment (Phase
  2.9.1)`). Any gate-name strip deletes a true positive. `enrollment-heading-fires.md`
  is the fixture that fails if someone adds one.
- **The negation strip must remove a SPAN, never a line.** PR bodies are not
  hard-wrapped; a line drop swallows any real declaration sharing a line with a
  disposition. Both `Soak enrollment: none yet — the 14-day soak begins at deploy.` and
  `No soak is needed for the docs half; the runtime half stays at ~0 for 7 days post-deploy`
  go dark under `grep -v` and fire correctly under `sed`.
- **`NEGATION_RE` contains `n/a`, so `sed s/…/…/` is a syntax error.** Use `@` as the
  delimiter. And inline the case classes (`[Ss]oak`) — `sed` has no `-i` equivalent. Both
  bit a reviewer who tried it; the failure mode was an empty haystack and a silent
  `exit 1`, i.e. a dark gate that looks like a pass.
- **The inline-code strip must be single-quoted.** `sed -E "s@\`[^\`]*\`@@g"` in double
  quotes makes bash run the backticks as command substitution. Carry the precedent's
  `# shellcheck disable=SC2016` comment across verbatim.
- **Neither existing gate's fence handling is correct alone — take one half from each.**
  The soak hook is fail-closed on an unbalanced fence but blind to indented fences; the
  PIR gate strips indented fences but fails *open* on an unbalanced one. Copying either
  verbatim ships a defect. The script owns fence stripping; the consumers stop doing it,
  so there is one anchor and one fail-closed rule rather than two state machines that can
  desync.
- **The override check runs on the RAW body and is an unanchored substring grep**, so a
  PR that merely *quotes* `gate-override: soak-followthrough-enrollment` bypasses the
  whole gate — including this PR, which quotes it repeatedly. Anchor it to a standalone
  HTML-comment line, run it after the strips, and `emit_incident` when it fires. An
  override that triggers with no operator decision behind it is the #7087 harm in its
  purest form.
- **The ReDoS-safety of any bounded repetition here is by construction, and fragile.**
  If a future edit reintroduces `(<class>+<sep>+){0,N}`, the inner class must exclude
  whitespace while the separator requires it — that is what makes the decomposition
  unambiguous. `grep -E` is a DFA and will hide a bad edit; the blow-up only appears on
  port to `grep -P`, JS, or Python. Pin the invariant in a comment.
- **`SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE=1` cannot be set as an inline command prefix.**
  PreToolUse hooks are spawned by Claude Code, not by the agent's shell, so
  `VAR=1 gh pr ready` never reaches the hook. The deny text and README both currently
  promise it works. Fix the docs to require an exported session var or a `settings.json`
  `env` entry — do **not** make the hook read the token out of `$CMD`, which would turn
  an operator escape into an agent-writable one.
- **Residual, accepted and named:** a real declaration wrapped in backticks is invisible
  to the gate, and a PR whose *subject* is this gate still discusses soaks in prose and
  may signal. The PIR gate documents the same residual for itself. The override exists
  for that case, and used there it means something.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| **Claim-shaping — replace the bare noun with an enumerated whitelist of following nouns/prepositions** (this plan's own draft 1). | **Measured and rejected.** Recall over the ground-truth enrolled set collapsed 42/50 → 22/50. It is an open-ended maintenance tax where every unanticipated phrasing is a silent detection loss, and it already missed `probe`. Full record in §Plan Review Revisions R1. |
| **A gate's-own-name strip** (draft 1, layer 2c). | **Measured and rejected.** Dead once the bare noun is delimited, *and* harmful: `Soak follow-through enrollment` is the canonical heading plans use to declare enrollment. |
| **Option 1 as stated in #7056** — drop the bare `soak` alternative, keep only criterion-encoding forms. | Measured recall cost is unacceptable: **17+ genuine declarations** match *only* via bare `soak` (`One-week soak`, `After a prod soak`, `after a 24h soak`, `when the soak holds`, `the soak window`, `1 dev-day soak`, `gated on the PR-1 soak`, `soaking, tracked #6901`). It also does **not** fix the negated-criterion class: `No post-deploy soak is required` and `no 7-day soak is needed` still fire through *retained* alternatives. Adopted in **spirit** (the bare noun goes) but not in **form** (it is replaced, not deleted). |
| **Option 2 as stated in #7056** — keep bare `soak`, strip negation contexts only. | Does not fix **#7087**: a filename is not a negation. Does not fix the gate-name class (#6665 shape), which this very PR would trip. Adopted as **layer 3 of 3**, where it is independently load-bearing. |
| **Both regex layers, but keep the two copies + add a second drift guard.** | Directly contradicted by `2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md`: *"A parity test over two copies detects drift; one copy makes it unrepresentable. Prefer removing the second copy over pinning it."* The copies share more than `SOAK_RE`; pinning one literal guards the seam already considered and leaves the rest open. Also: with two copies there is no executable seam, so the #7056-mandated fixture pair could not be written as a behavioural test at all. |
| **Amend `plan/SKILL.md` §2.9.1 to prescribe a canonical N/A disposition string the gate strips by literal.** | Couples the gate to one template literal — the same brittleness in a new place, and it would silently fail on every plan predating the amendment. The matcher should be robust to negation *generally*. |
| **Negative lookahead / lookbehind instead of stripping.** | Bash ERE (`grep -E`) has neither. Switching to `grep -P` would add a PCRE dependency the repo does not otherwise require, and the precedent explicitly chose stripping: *"Gate NAMES are stripped below (not added to a negative lookahead) so the token cannot reach OUTAGE_RE at all."* |
| **Delete the gate.** | The enrollment rot it prevents is real and measured (PR #5671/#5673, PR #5675/#5689 — both trackers left to rot on human memory). The defect is precision, not purpose. |
| **Leave #7087 to its own PR** (it carries `deferred-scope-out`). | Rejected — see below. |

### #7087 bundling disposition: **BUNDLED**

Both issues are the same defect, in the same regex, in the same two files, with the same
root cause (*matching a token instead of a claim*), and the same measured remedy. Three
concrete reasons beyond convenience:

1. **The layer that fixes #7087 is a prerequisite for #7056's fix to ship at all.** The
   inline-code and gate-name strips are what stop *this PR* from blocking itself (AC10).
   #7087's fix is not adjacent work — it is load-bearing for the merge.
2. **#7087's own suggested remedy is the structural change this plan makes** — *"Move the
   soak scan into `scripts/ship-soak-followthrough-gate.sh` with an exit-code contract
   (0 = signal, 1 = no signal), so it is testable"* plus both-direction fixtures. Doing
   #7056 without it means writing the fixture pair twice.
3. Fixing one without the other means a **second PR touching the same lines** within
   days, and re-litigating the same recall/precision trade-off with the first PR's
   fixtures already frozen.

No conflict was found between the two fixes; they compose. `Closes #7087` goes in the PR
body alongside `Closes #7056`. #7087's `deferred-scope-out` label should be removed at
merge — its recorded re-evaluation trigger (*"when the next PR is blocked by this gate on
a filename-only match, or when the gate script lands, whichever is first"*) is satisfied
by this PR.

---

## Rule Compliance

| Rule | How this plan complies |
|---|---|
| `cq-write-failing-tests-before` | Phase 1 authors fixtures + harness and confirms RED before Phase 2 writes the script. |
| `cq-test-fixtures-synthesized-only` | All 11 fixtures are synthesized plan-shaped prose. Real plans (#7034, #7072) are used **only** as read-only retroactive verification in AC11, never copied into `fixtures/`. |
| `cq-cite-content-anchor-not-line-number` | Every citation in the new script/test/README anchors on a symbol or content anchor (`ship/SKILL.md` §"Incident-signal scan", `SOAK_RE=`), never `<file>:NNN`. |
| `cq-assert-anchor-not-bare-token` | AC1 anchors on `^\s*SOAK_RE=`, not the bare token. AC8 mandates mutation-testing every new assertion. |
| `wg-when-fixing-a-workflow-gates-detection` | Phase 4 step 2 + AC11 retroactively apply the fixed gate to #7034 and #7072. |
| `wg-use-closes-n-in-pr-body-not-title-to` | AC17. |
| `rf-review-finding-default-fix-inline` | #7087 is folded in rather than deferred. |
| `hr-never-label-any-step-as-manual-without` | Post-merge operator steps: none. |
