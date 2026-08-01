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
| current `SOAK_RE` | **20 / 40** |
| current, minus the bare `soak` alternative | **1 / 40** |
| plans that fire **only** via bare `soak` | **19** |

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
| "drop the bare `soak` alternative" is the cheapest-correct fix (#7056) | A recall survey of ~70 prose soak declarations found **17+ genuine declarations matched ONLY by bare `soak`** — `One-week soak`, `After a prod soak`, `after a 24h soak`, `when the soak holds`, `the soak window`, `1 dev-day soak`, `gated on the PR-1 soak`, `soaking, tracked #6901`. | **Reject option 1 as stated.** Replace the bare noun with **claim-shaped** alternatives rather than deleting the concept. Verified to preserve 18/18 of those declarations (see Phase 1). |
| "strip negation contexts, mirroring the incident-PIR gate" is the alternative (#7056) | The negation strip alone leaves **#7087 unfixed** (a filename is not a negation) and leaves the gate's own name matching. | **Reject option 2 as the whole fix**, adopt it as one of three layers. Measured: it is *independently load-bearing* — see next row. |
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
`fail-toward-PIR` (over-produce, the operator adjudicates). This gate must go the other
way — its miss-mode is backstopped by four other surfaces (`plan` Phase 2.9.1 proactive
enrollment, `/ship` Phase 7 Step 3.5's `⏳` scan, `follow-through-directive-gate.sh`,
and the daily sweeper), while its false-fire mode has no backstop at all and actively
degrades the override's meaning. Biasing for precision is therefore correct here and is
the opposite call from the sibling gate — recorded so the divergence is deliberate, not
drift.

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
  what: the gate's own rule-application telemetry — `emit_incident wg-pm-class-followthrough-for-operator-dogfood <applied|deny>` via .claude/hooks/lib/incidents.sh
  cadence: per `gh pr ready` / `gh pr merge --auto` invocation
  alert_target: .rule-incidents.jsonl, consumed by the weekly rule-usage aggregator
  configured_in: .claude/hooks/ship-soak-followthrough-gate.sh (emit_incident call, unchanged by this plan)
error_reporting:
  destination: stderr of the PreToolUse hook, surfaced inline to the agent as the deny reason
  fail_loud: true for the deny path; the scan script exits 1 (clean no-signal) vs any other non-zero (harness fault) so a caller can tell them apart — the exit-code contract this plan adds
failure_modes:
  - mode: over-strip — the scan never signals, soak trackers silently rot
    detection: the FIRE-direction fixtures in plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts (a green suite with a dead matcher is unrepresentable because every fixture is mutation-tested)
    alert_route: CI test job on every PR
  - mode: under-strip — the gate keeps denying correct PRs
    detection: the QUIET-direction fixtures, plus AC9's corpus-rate assertion over the 40 most recent plans
    alert_route: CI test job on every PR
  - mode: the extracted script is missing / not executable at hook run time
    detection: the hook fail-opens (exit 0) rather than crashing the operator's merge; the test asserts the script exists and is owner-executable
    alert_route: CI test job on every PR
logs:
  where: .rule-incidents.jsonl (repo-local, gitignored); the deny text itself in the agent transcript
  retention: rotated by the existing incidents.sh rotation; no change
discoverability_test:
  command: "printf 'op:founder-ambiguous stays at ~0 for 7 days post-deploy\\n' | bash scripts/ship-soak-signal-gate.sh; echo \"exit=$?\""
  expected_output: "SOAK-SIGNAL: yes  /  exit=0   (and for `printf 'Soak/follow-through enrollment: **not applicable**\\n' | …` → no stdout, exit=1)"
```

No `ssh` anywhere in the discoverability test.

### Soak Follow-Through Enrollment

Not applicable — this plan declares no time-gated close criterion. #7056 and #7087
close the instant the fixed matcher lands and its fixtures pass; there is nothing to
observe after deploy. Disposition recorded rather than skipped silently.

> Note the recursion: under the **current** matcher the paragraph above would itself
> trip the gate. Under the fixed matcher it does not — AC10 pins exactly that.

---

## Encryption Posture

Not applicable — the plan introduces no persistent store and no new cross-component
connection. Detection did not fire: no `.tf`, no `supabase/migrations/*.sql`, no
`cloud-init*.yaml`, no `docker-compose*.yaml` in scope. Disposition recorded rather than
skipped silently.

---

## The chosen fix

Three layers. Each closes a residual the other two cannot, and this was **measured**,
not reasoned:

1. **Claim-shaping** — replace the bare `soak` alternative with alternatives in which
   the noun carries a claim: adjacency to a duration, a temporal/gating preposition, or
   a state verb/noun. Structural constraint: `soak` may only match when preceded by
   whitespace or start-of-line, never glued to a hyphen. That one constraint retires the
   whole identifier/filename class (`sandbox-canary-soak`, `web2-standby-soak-6459`,
   `workspaces-luks-soak-6604.sh`) without needing any strip — the
   structural-delimiter discipline of
   `knowledge-base/project/learnings/2026-05-07-post-build-token-gates-false-positive-on-worktree-paths.md`
   (*"Prefer tokens with structural delimiters … over bare substrings"*).
2. **Artifact stripping** — before matching, strip (a) fenced code blocks *(already
   done)*, (b) **inline `` `code` `` spans** *(new)*, (c) **the gate's own name**
   *(new)*. Layer (c) is not hypothetical: this very PR's body and plan name the gate
   repeatedly, and #6665 is the precedent — a gate name is not an event.
3. **Negation stripping** — drop lines where a negation **directly governs** the soak
   (within 3 tokens) or where an explicit `not applicable` / `N/A` / `none` disposition
   is recorded. Bounded at 3 tokens so that
   `no P0 incidents during the 7-day soak` — a real declaration containing "no" —
   **survives**.

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
# Claim-shaped soak signal. `soak` never matches hyphen-glued (filenames/identifiers).
# STRONG temporal preps (after|until|once|during|through|gated on|to) allow <=3
# intervening tokens; the WEAK prep `of` allows ZERO — see Sharp Edges.
SOAK_RE='stays? (at )?(~?0|zero)|[0-9]+[- ]day[s]?( post-deploy| soak)|post-deploy (soak|verif|observ)|adopting[[:space:]]*(→|->|to)[[:space:]]*accepted|status[[:space:]]+flip|(^|[[:space:]])soak(s|ing|ed)?[[:space:]]+(window|clock|period|begin|complet|hold|pass|show|elaps|expir)|(after|until|once|during|through|gated on|to)[[:space:]]+([[:alnum:]#~._-]+[[:space:]]+){0,3}soak(s|ing|ed)?([[:space:]]|[.,;:)]|$)|of[[:space:]]+soak(s|ing|ed)?([[:space:]]|[.,;:)]|$)|day[s]?[- ]soak|[0-9]+[- ]?(h|hr|hrs|hour|hours|week|weeks|wk|month)s?[- ](post-deploy|soak)|(one|two|three|four|a|an)[- ](day|week|month|hour)[- ]?soak|(^|[[:space:]])soaking'

# Negation must DIRECTLY govern the soak (<=3 tokens), or be an explicit disposition.
NEGATION_RE='(^|[[:space:]])no[[:space:]]+([[:alnum:]#~._-]+[[:space:]]+){0,3}soak|soak[^.]{0,50}(not applicable|not needed|not required|n/a)|(soak|follow-through)[^:]{0,40}:[[:space:]]*(\*\*)?[[:space:]]*(not applicable|n/a|none)'

# The gate's own NAME is not a claim (#6665 precedent: gate names are stripped, not
# lookahead-excluded, so the token cannot reach SOAK_RE at all).
GATENAME_RE='[Ss]oak-[Gg]ated [Ff]ollow-[Tt]hrough [Ee]nrollment( [Gg]ate)?|soak-followthrough-enrollment|ship-soak-[a-z-]*gate|[Ss]oak [Ff]ollow-[Tt]hrough [Ee]nrollment'
```

Full pipeline (fences → inline `` `code` `` → `GATENAME_RE` → `NEGATION_RE` → `SOAK_RE`),
measured during planning:

| Check | Result |
|---|---|
| True soak declarations that FIRE | **18 / 18** (incl. every phrasing the recall survey flagged as bare-`soak`-only) |
| False-positive strings that stay QUIET | **10 / 10** (incl. #7056 and #7087 verbatim) |
| 40-plan corpus signal rate | **20 → 5** |
| This plan file itself (AC10) | **QUIET** |

---

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/ship-soak-signal-gate.sh` | The scan. stdin → exit 0 + `SOAK-SIGNAL: yes` when a soak is CLAIMED; exit 1 silently otherwise. **Owns** `SOAK_RE` + the strips. Sibling of `scripts/ship-incident-pir-gate.sh`; distinct basename from the hook so the two are never confused. |
| `plugins/soleur/test/fixtures/ship-soak-followthrough-gate/*.md` | 11 synthesized both-direction fixtures (enumerated in Test Scenarios). |

## Files to Edit

| Path | Change |
|---|---|
| `.claude/hooks/ship-soak-followthrough-gate.sh` | Replace the inline `SOAK_RE` + dual `grep -qiE` with a pipe of `"$CORPUS"` into the extracted script; branch on its exit. Preserve the dual-locale invocation **inside the script**. Fail-open if the script is missing/unreadable. |
| `plugins/soleur/skills/ship/SKILL.md` | Replace the §Detection `SOAK_RE=` + `SOAK_HIT=` block with the script invocation, mirroring the Incident-PIR call shape at §"Incident-signal scan". Add a `**Why:**` sentence citing #7056 + #7087. |
| `plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts` | Delete the `soakRe()` scraper and the byte-identity parity test (the second copy is gone — parity is unrepresentable, not asserted). Add a `spawnSync` harness over the shipped script + the 11 fixtures. Re-anchor the two prose assertions that referenced `SOAK_RE=`. |
| `.claude/hooks/README.md` | Rewrite the `SOAK_RE is kept **byte-identical**…` bullet to describe single ownership; add the false-positive history + the `SOAK-SIGNAL` exit contract. |

---

## Implementation Phases

### Phase 0 — Preconditions (no edits)

1. `bun test plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts` → **14 pass / 0 fail** (recorded baseline).
2. `bun test plugins/soleur/test/ship-incident-pir-gate.test.ts` → green (the precedent harness this mirrors).
3. Re-read `scripts/ship-incident-pir-gate.sh` end to end. Match its `set -uo pipefail`,
   its herestring-not-pipe discipline (*"a piped `grep -q` under pipefail can SIGPIPE on
   an early match and invert the result"*), and its exit-code contract.
4. Confirm `.claude/hooks/ship-soak-followthrough-gate.sh` resolves the repo root as
   `$(dirname "${BASH_SOURCE[0]}")/../..` (it already uses `$(dirname …)/lib/incidents.sh`).

### Phase 1 — RED: fixtures + failing tests first

Per `cq-write-failing-tests-before`. Write the 11 fixtures and the `spawnSync` harness
**before** the script exists; the suite must fail for the right reason (script absent),
then fail on the *old* behaviour once a stub lands.

1. Author the 11 fixtures under `plugins/soleur/test/fixtures/ship-soak-followthrough-gate/`.
   **Synthesized only** (`cq-test-fixtures-synthesized-only`) — plan-shaped prose written
   for the test, never copied from `#7034`'s or `#7072`'s real plan. No real emails, no
   prod-shape UUIDs, no tokens.
2. Add the harness, modelled on `ship-incident-pir-gate.test.ts`'s `signals()`: assert
   exit 0 **and** `SOAK-SIGNAL: yes` on stdout for the FIRE direction; assert exit **1**
   (not merely non-zero) with empty stdout for the QUIET direction, so a crash can never
   read as a clean no-signal.
3. Re-derive and re-measure the two regexes against the fixtures **and** against the
   40-most-recent-plans corpus. Do not paste the planning literals unverified — re-run
   the measurement and record the numbers in the PR body.
4. Confirm RED.

### Phase 2 — GREEN: extract the scan into a script that owns the regex

Create `scripts/ship-soak-signal-gate.sh`:

- Header comment: what it is, the #7056/#7087 false positives it retires, the exit
  contract, and *why* each strip stage exists — mirroring the precedent's comment
  discipline so the next editor cannot delete a stage without reading its reason.
- Strip order: fences → inline `` `code` `` spans → the gate's own name → negation /
  disposition lines.
- **Fence handling must take the better half from EACH gate — do not copy either
  verbatim.** Measured during planning:

  | Behaviour | soak hook (today) | PIR gate | required |
  |---|---|---|---|
  | Unbalanced fence (opened, never closed) | **fail-closed** — `END { if (in_fence) exit 2 }` makes the caller fall back to the *unstripped* body | **fail-open** — no `END` check, so the entire tail after the opening fence is silently swallowed | **fail-closed** (keep the soak hook's `END`) |
  | Indented fence (inside a list item) | **missed** — anchors `/^```/` at column 0, so the fenced body is scanned as prose | **stripped** — anchors `/^[[:space:]]*```/` | **stripped** (take the PIR anchor) |

  Copying `ship-incident-pir-gate.sh`'s awk verbatim would convert this gate's
  fail-closed unbalanced-fence handling into fail-open — a silent gate-darkening
  regression introduced *by following the precedent*. This is the copy-adaptation drift
  class from `2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md`,
  arriving through the front door.
- Then the dual-locale match, **preserved** from the hook: once under
  `LC_ALL=C.UTF-8`, once without (the regex carries `→`).
- `echo "SOAK-SIGNAL: yes"` **plus the line-numbered matched lines** (`grep -niE … | head -5`),
  then `exit 0`; bare `exit 1` with no stdout otherwise.

  **Do not reduce this to an exit code alone.** The SKILL gate today captures
  `SOAK_HIT=$(grep -niE "$SOAK_RE" "$COMBINED" | head -5)` — the `-n` and the `head -5`
  exist so the operator can see *which* lines tripped it. Both #7056 and #7087 were
  adjudicated precisely by reading that list and finding the only hit was a disclaimer
  or a filename. An exit-code-only contract would delete the evidence the operator needs
  to judge a fire, on the exact gate whose problem is unjustified fires. The PIR gate
  prints only its marker; this one must print the marker **and** the hits.
- `chmod +x`.

Rationale for the extraction over a second parity guard, in the repo's own words
(`2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md`):
*"When you copy-adapt a block, the whole block is a drift surface, not just the part you
already decided was risky. The fix is one copy, not two pinned copies."* The two current
copies share more than `SOAK_RE` — they share the corpus build, the fence-strip awk, and
the tracker-enrollment triad. Pinning one literal guards the seam already thought about
and leaves the adjacent seams open.

### Phase 3 — Wire the two consumers

1. **Hook.** Replace the `SOAK_RE` block with the script call; fail-open (`exit 0`) if
   the script is absent or unreadable, consistent with every other fail-open arm in that
   hook. Do not let `set -eo pipefail` read a clean `exit 1` as a failure.
2. **SKILL.md.** Replace §Detection's regex block with the invocation, in the same shape
   as the Incident-PIR call. Keep the `COMBINED` corpus build (the plan-file resolution
   is still the skill's job). Add the `**Why:**` sentence.

**Phase order is load-bearing:** the script (contract producer) must exist before the
hook and SKILL (contract consumers) are rewired, or Phase 3 is dead code even though the
PR merges atomically.

### Phase 4 — Docs + retroactive application

1. `.claude/hooks/README.md`: rewrite the byte-identity bullet; record the false-positive
   history and the exit contract.
2. **Retroactive gate application** (`wg-when-fixing-a-workflow-gates-detection` — *"Gate
   fixed" is not done; "gate fixed AND missed case remediated" is done*): run the fixed
   scan against the two plans that exposed the gap —
   `knowledge-base/project/plans/2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md`
   (#7034) and #7072's linked plan — and record in the PR body that both now produce **no
   signal**. This is a read-only verification against real artifacts; the *fixtures* stay
   synthesized.
3. Run the full suite: `bash scripts/test-all.sh`.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `scripts/ship-soak-signal-gate.sh` exists, is owner-executable, and is the
  **only** file in the repo containing a `SOAK_RE=` assignment:
  `grep -rln "^\s*SOAK_RE=" --exclude-dir=.git . | wc -l` → `1`, and the single path is
  `./scripts/ship-soak-signal-gate.sh`. (Anchored on `^\s*SOAK_RE=`, not the bare token,
  per `cq-assert-anchor-not-bare-token` — prose mentioning `SOAK_RE` must not satisfy it.)
- **AC2** — The **required #7056 fixture pair** passes: a plan declaring a real soak
  exits 0 with `SOAK-SIGNAL: yes`; a plan declaring
  `Soak/follow-through enrollment: not applicable` exits 1 with empty stdout.
- **AC3** — The **#7087 fixture** passes: a plan whose only soak token is the filename
  `sandbox-canary-soak.test.sh` (both backticked and bare) exits 1.
- **AC4** — The **negated-criterion fixture** passes: `No post-deploy soak is required`
  and `no 7-day soak is needed here` exit 1 — proving the negation strip is load-bearing
  independently of the claim-shaping.
- **AC5** — The **strip-bound fixture** passes: `no P0 incidents during the 7-day soak`
  exits **0** — proving the negation strip did not swallow a real declaration.
- **AC6** — The **recall fixture** passes: a plan whose soak is declared only in prose
  with no numeric window (`One-week soak`, `after a prod soak`, `when the soak holds`)
  exits 0.
- **AC7** — The **gate-name fixture** passes: a plan that names
  `Soak-Gated Follow-Through Enrollment Gate` and quotes `SOAK_RE` inside a fenced block,
  and declares no soak, exits 1.
- **AC8** — Every fixture is **mutation-tested**: deleting the corresponding regex
  alternative or strip stage turns at least one test RED. A fixture that stays green
  under mutation pins nothing (`cq-assert-anchor-not-bare-token`); record the mutation
  matrix in the PR body.
- **AC9** — Corpus rate: over the 40 most recent files in
  `knowledge-base/project/plans/`, the shipped script signals on **≤ 6** (baseline: the
  current regex signals on **20**). Recorded as a measured number in the PR body, not a
  claim.
- **AC10** — **This PR's own body and plan produce no signal.** Piping the PR body
  concatenated with this plan file into the shipped script exits 1. (Without the
  gate-name and fenced-block strips, the PR that fixes the gate is blocked by the gate.)
- **AC11** — Retroactive application: the #7034 plan
  (`…2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md`) and the #7072 plan
  each exit 1 through the shipped script.
- **AC12** — Exit-code contract: `printf 'nothing here\n' | bash scripts/ship-soak-signal-gate.sh`
  exits **exactly 1** with empty stdout — never 0, never 2, never a crash.
- **AC13** — The dual-locale invocation survives extraction: the script matches the
  `adopting → accepted` alternative both with and without `LC_ALL=C.UTF-8`
  (`grep -c 'LC_ALL=C.UTF-8' scripts/ship-soak-signal-gate.sh` ≥ 1, plus a fixture whose
  only signal is the `→` form).
- **AC14** — The byte-identity parity test and the `soakRe()` scraper are **deleted**
  from `plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts`, and
  `plugins/soleur/skills/ship/SKILL.md` invokes the script (`grep -c 'ship-soak-signal-gate.sh'`
  ≥ 1 in both SKILL.md and the hook).
- **AC15** — `.claude/hooks/README.md` no longer claims byte-identity; it documents
  single ownership and the `SOAK-SIGNAL` exit contract.
- **AC16** — Full suite green: `bash scripts/test-all.sh`.
- **AC17** — PR body carries `Closes #7056` and `Closes #7087` (in the **body**, not the
  title, per `wg-use-closes-n-in-pr-body-not-title-to`).
- **AC18** — **Weak-preposition bound.** The `prose-about-soaks.md` fixture exits 1,
  while `in the first 24h of soak` still exits 0 — proving `of` is pinned to zero
  intervening tokens and the strong temporal prepositions are not. Mutation: widening
  `of` to the ≤3-token arm must turn this RED.
- **AC19** — **Unbalanced fence stays fail-closed.** `unbalanced-fence-real-soak.md`
  (an opening ``` with no closing fence, a real soak declaration after it) exits **0**.
  Mutation: dropping the `END { if (in_fence) exit 2 }` fallback must turn this RED —
  without it the tail is swallowed and the gate goes dark.
- **AC20** — **Indented fences are stripped.** `indented-fence-quoted-soak.md` (a fenced
  block indented inside a list item, containing a soak declaration and nothing else)
  exits **1**. Mutation: reverting the anchor to `/^```/` must turn this RED.
- **AC21** — **Diagnosability.** When the script signals, it emits the matched lines
  (line-numbered, capped) so the operator can see *why* it fired. Piping
  `real-soak-declaration.md` through it yields at least one `N:` line-numbered match
  alongside `SOAK-SIGNAL: yes`. The hook and SKILL surface those lines in the deny text.

### Post-merge (operator)

**None.** No infrastructure, no migration, no vendor state, no secret. The hook and
script are read from the working tree on the next `gh pr ready`.

---

## Test Scenarios

All fixtures live in `plugins/soleur/test/fixtures/ship-soak-followthrough-gate/` and
are **synthesized** plan-shaped prose (`cq-test-fixtures-synthesized-only`).

| Fixture | Direction | Pins | Retires |
|---|---|---|---|
| `real-soak-declaration.md` | **FIRE** | numeric-window claim (`stays at ~0 for 7 days post-deploy`) | — (#7056 required pair, positive) |
| `soak-disposition-not-applicable.md` | QUIET | disposition strip | **#7056** (required pair, negative) |
| `soak-filename-only.md` | QUIET | whitespace-precedence constraint + inline-code strip | **#7087** |
| `negated-criterion-soak.md` | QUIET | negation strip over a *retained* alternative (`no post-deploy soak`, `no 7-day soak`) | the class option 1 alone leaves open |
| `negation-adjacent-real-soak.md` | **FIRE** | the 3-token bound on the negation strip (`no P0 incidents during the 7-day soak`) | over-strip regression |
| `prose-soak-no-numeric-window.md` | **FIRE** | claim-shaped alternatives (`One-week soak`, `after a prod soak`, `when the soak holds`) | the 17-declaration recall loss of option 1 |
| `gate-name-and-fenced-regex.md` | QUIET | gate-name strip + fence strip | the #6665 class, and AC10 (self-block) |
| `adopting-accepted-arrow.md` | **FIRE** | the multibyte `→` alternative under both locales | AC13 |
| `prose-about-soaks.md` | QUIET | the weak-preposition bound (`a recall survey of ~70 prose soak declarations`, `the soak gate fired`, `CUT the soak follow-through probe`) | prose *about* soaks reading as a declaration |
| `unbalanced-fence-real-soak.md` | **FIRE** | fail-closed fallback on an unclosed fence (`END { if (in_fence) exit 2 }`) | the fail-open regression a verbatim PIR-awk copy would introduce |
| `indented-fence-quoted-soak.md` | QUIET | the indent-tolerant fence anchor `/^[[:space:]]*```/` | fenced-as-data content inside a list item scanned as prose |

Harness contract (mirrors `ship-incident-pir-gate.test.ts`): FIRE ⇒ `status === 0` **and**
stdout contains `SOAK-SIGNAL: yes`; QUIET ⇒ `status === 1` **and** stdout empty. Asserting
`status === 1` rather than "non-zero" is what keeps a crash from reading as a pass.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Over-strip → the gate goes dark**, and a soak tracker rots (the exact 2026-06-29 regression the gate exists for). A gate that fails silently looks identical to a gate doing its job. | Four FIRE-direction fixtures, all mutation-tested (AC8). AC9 asserts the corpus rate falls to a *non-zero* floor, not to zero — a matcher that signals on nothing would fail it. Additionally the miss-mode retains four backstops: `plan` §2.9.1, `/ship` Phase 7 Step 3.5, `follow-through-directive-gate.sh`, the daily sweeper. |
| **Regex over-fitted to the fixtures.** | Phase 1 step 3 re-derives and re-measures against the *corpus* (40 real plans) as well as the fixtures. AC9 is a corpus assertion, not a fixture assertion. |
| **The extraction moves the bug into the seam** — the composition (hook → script) is untested even though the script is. `2026-07-17-…parity-pin.md`: *"Extracting verdict logic into a tested script and leaving the glue that calls it untested moves the bug, it doesn't kill it."* | AC10 and AC11 exercise the composed path against real artifacts, not just the unit. The hook's fail-open arm for a missing script is asserted explicitly. |
| **The gate's green path has never been exercised.** The current suite is documentation-shape only — it string-matches Markdown and has never run the matcher. Same shape as the permanently-red gate in the 2026-07-17 learning: *"a gate that fails closed for the wrong reason is a gate that has never demonstrated it can pass."* | The new harness runs the shipped script in **both** directions. This is the first time this gate's decision logic is executed by a test at all. |
| **`set -eo pipefail` in the hook misreads a clean `exit 1` as a failure.** The precedent's header calls this out as the foot-gun the old inline `A && B && echo` chain carried. | Phase 3 branches on the exit inside an `if`, never letting `set -e` see it — the shape used at `ship/SKILL.md` §"Incident-signal scan". |
| **Basename confusion** between `.claude/hooks/ship-soak-followthrough-gate.sh` (the hook) and the new scanner. | Distinct basename `ship-soak-signal-gate.sh`, matching the `ship-incident-pir-gate.sh` naming family; both file headers cross-reference each other. |
| **Fixture prose accidentally trips the FIRE/QUIET direction of a *different* fixture** when the suite concatenates. | Each fixture is fed to the script independently via `spawnSync` stdin — never concatenated. |

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Fill it
  before requesting deepen-plan or `/work`.
- **This plan's own artifacts are inside the gate's scan corpus.** The PR body and this
  plan file both discuss soaks at length. Every regex literal in this plan lives inside a
  fenced block on purpose, and AC10 pins the self-pass. If /work moves a regex out of a
  fence into prose, the PR blocks itself — and the fix will look like a gate bug rather
  than a formatting slip.
- **Do not "simplify" by re-inlining the regex into the hook.** The two-copy shape is
  what this plan retires; a future editor who finds the extra indirection annoying will
  be re-creating the drift surface, not removing ceremony.
- **The negation strip's 3-token bound is load-bearing, not a magic number.** Widening it
  swallows `no P0 incidents during the 7-day soak`; removing it entirely re-opens #7056.
  `negation-adjacent-real-soak.md` is the fixture that fails if someone widens it.
- **Prepositions are not interchangeable: strong temporal ones bound a claim, weak ones
  do not.** `after|until|once|during|through|gated on|to` genuinely mark a soak as a
  gating condition, so they tolerate ≤3 intervening tokens. `of` does not — it is the
  ordinary genitive, so `of ~70 prose soak declarations` (prose *about* soaks) matched
  under a ≤3-token allowance. Found by running the pipeline against **this plan file**
  during planning, not by reading it. `of` is therefore pinned to **zero** intervening
  tokens, which still catches the real declaration `in the first 24h of soak`. If a
  future editor adds a preposition to the ≤3-token arm, they must re-run the AC10
  self-check — a weak preposition there silently re-opens the whole class.
- **Neither existing gate's fence handling is correct on its own — take one half from
  each.** The soak hook is fail-closed on an unbalanced fence but blind to indented
  fences; the PIR gate strips indented fences but fails *open* on an unbalanced one.
  Copying either verbatim ships a defect. Both directions are pinned by
  `unbalanced-fence-real-soak.md` (AC19) and `indented-fence-quoted-soak.md` (AC20);
  measured during planning, not assumed.
- **The scan must print the matched lines, not just an exit code.** The evidence the
  operator reads to decide whether a fire is legitimate is exactly the `grep -n` hit
  list. Reducing the contract to exit-code-only would, on this gate specifically, remove
  the diagnosability that made #7056 and #7087 adjudicable at all.
- **Residual, accepted:** a PR whose *subject* is this gate still discusses soaks in
  prose and can signal — the same fail-toward-gate residual `ship-incident-pir-gate.sh`
  documents for itself (*"a plan whose SUBJECT is incident detection still discusses
  outages in prose and may signal"*). AC10 pins that *this* plan passes; it does not
  promise every future gate-editing PR will. The override exists for that case, and used
  there it means something.
- **This gate's precision bias is the opposite of the Incident-PIR gate's.** That gate
  documents *"when uncertain, the gate fires (fail-toward-PIR)"*. Copying that posture
  here would re-create #7056. The divergence is deliberate and is justified in
  §Domain Review — do not "harmonize" the two.

---

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
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
