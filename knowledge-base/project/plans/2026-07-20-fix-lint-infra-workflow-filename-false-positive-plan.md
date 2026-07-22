---
title: "fix: lint-infra-no-human-steps — a CI workflow FILENAME must not satisfy the infra-imperative sentinel"
date: 2026-07-20
type: fix
issue: 6771
branch: feat-one-shot-6771-lint-infra-workflow-filename-fp
lane: procedural
brand_survival_threshold: none
---

> **SUPERSEDED IN PART — read this before trusting the recommendation below.**
>
> This plan makes **option 2** (anchoring the `-target … apply` imperative on
> terraform/tofu/opentofu adjacency) the primary fix, on the strength of a measured
> "~45 latent false positives removed" vs option 1's ~8. **That premise is false and
> option 2 was reverted.** Reading all 41 lines option 2 removes shows ~29% are GENUINE
> human-run infra steps it silences — including one in a runbook — because the natural
> phrasing omits the tool name.
>
> What shipped is **option 1 only** (filename neutralization), plus a `STRONG_ACTOR_RE`
> suppression that closes option 1's own narrow false-negative. The binding record is
> [ADR-132](../../engineering/architecture/decisions/ADR-132-infra-sentinel-neutralize-filenames-not-tool-anchors.md);
> the task-level delta is the AMENDMENT section in
> [tasks.md](../specs/feat-one-shot-6771-lint-infra-workflow-filename-fp/tasks.md).
>
> Also stale below: the Phase 3 carve-out sweep names 7 regions (derived under the
> anchored script); only **2** are freed by what shipped. And the "overlap by 4"
> arithmetic in the measurement section is wrong — the two transforms do not compose
> additively; measured overlap is 5.
>
> The issue author's original preference order (filenames first) was correct. Plan-quoted
> measurements are preconditions to re-derive, not facts.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO infrastructure. Every
     "operator runs …" / "SSHes into …" string below is a TEST FIXTURE — the
     positive-control prose the linter under repair must keep flagging. There is
     no server, secret, cron, DNS record, vendor, or runtime process here. -->

# fix: a CI workflow FILENAME (`apply-*.yml`) satisfies the infra-imperative sentinel

Closes #6771. Ref #6749.

## Enhancement Summary

**Deepened:** 2026-07-20 · **Reviewers:** correctness (Kieran), simplicity · **Gates:** 4.4-4.9

### Key improvements from review

1. **P0 fixed — AC4's greps were wrong.** `grep -c 'opentofu)..b\.\*?-target'` returns 0 on a
   *correctly fixed* file (BRE `..b` demands three characters where the text has `\b`), so the
   AC would have blocked the very fix it verifies. Replaced with `grep -cF` fixed-string forms,
   both verified pre- and post-fix.
2. **P1 fixed — a `.yml`-only fast path silently breaks `.yaml`.** Prose and code disagreed;
   an implementation matching the prose passes all six original fixtures and still flags
   `reboot-web-hosts.yaml`. Prose corrected and a seventh fixture added to catch it.
3. **P1 fixed — my own subset claim was false.** 8 + 45 ≠ 49: the two options overlap by 4,
   so neither set contains the other. Opt1 uniquely removes 3 lines. Corrected, with the
   three specific files named.
4. **P1 fixed — absolute timing and hit-count ACs are machine- and corpus-dependent.**
   Observed baselines span 32-73 s across hosts, and this PR adds its own artifacts to the
   scanned corpus. Replaced with a relative 1.25× bound and a delta assertion.
5. **P1 fixed — AC7's subset comparison must run pre-sweep.** Phase 3 removes carve-outs,
   which legitimately adds hits under the old script and would corrupt the diff.
6. **P1 fixed — Phase 1's RED count was wrong** (three, not four).

### Open question resolved

Opt2 alone **does** fix the reported repro (verified: exit 0 on the #6749 line). Opt1 is
therefore supplementary. It is kept on an argued basis, with the dissent recorded in
§Option evaluation so a reviewer can overrule it cheaply.

## Overview

`scripts/lint-infra-no-human-steps.py` flags prose as "prescribes a human-run infra
step" when the only infra-imperative token it matched is the **filename of the CI
workflow that makes the step non-human**. Two independent defects compose:

<!-- lint-infra-ignore start: the table below DISSECTS THE FALSE POSITIVE — each cell
     quotes the token the sentinel wrongly matched. Quoting the defect is not committing it. -->
| Half | Pattern | What it actually matched |
|---|---|---|
| actor | `\boperator\b` | the possessive *"the operator's value"* |
| imperative | `-target\b.*?\bappl(?:y\|ies\|ied)\b` | `-target=` … **`apply`**`-web-platform-infra.yml` — a *filename* |
<!-- lint-infra-ignore end -->

The `apply-` prefix satisfies `\bappl(y|ies|ied)\b` because the following `-` is a
word boundary. Separately, `-target … apply` is the **only** imperative in the set
with no `terraform`/`tofu` tool anchor.

Every other imperative is anchored (`\b(?:terraform|tofu|opentofu)\s+appl…`,
`… destroy`, `… taint`, `… import`). The un-anchored `-target … apply` is the
outlier, and it is the one that fires on prose that *correctly documents CI-driven
applies* — which is the repo's dominant way of describing this. Because CI runs
`--changed`, these are latent: they only fire when a doc edits a nearby line, at
which point the author adds a `lint-infra-ignore` carve-out. Each carve-out is a
permanently blind region in a P0 gate.

**Decision: land BOTH fix options.** They address different failure classes and
neither subsumes the other. Measurements below (§Option evaluation) were taken
against the live corpus, not reasoned about.

## Research Reconciliation — issue claims vs. measured reality

| Issue claim | Measured reality | Plan response |
|---|---|---|
| Option 1 preferred over option 2 | **Option 2 is the higher-yield fix by ~5×**: opt1 removes 8 latent FP lines corpus-wide, opt2 removes 45, both together 49. The sets **overlap but neither contains the other** — opt1 uniquely removes 3, opt2 uniquely removes 40. Opt1 frees 2 carve-out regions, opt2 frees 8 (opt1's 2 ⊂ opt2's 8). | Land both; opt2 is the primary, opt1 is the general filename-class guard. Recorded as a deliberate divergence from the issue's stated preference order. |
| — (reviewer challenge) | **Opt2 alone fixes the reported repro** — verified by running the #6749 line verbatim against an opt2-only build: exit **0**. Opt1 is therefore *supplementary*, not mandatory. | Keep opt1 anyway, on its 3 unique removals + the future-filename class. This is a judgement call, recorded openly rather than hidden behind the aggregate number. |
| Strip filenames "prior to the imperative scan" | The actor half has the identical failure mode (`operator-*.yml`, `founder-*.yml`, `manually-*.yml`). No such workflow exists **today** (`ls .github/workflows/` → only `apply-*.yml` matches any sentinel token), but the class is symmetric. | Neutralize once per line, feeding **both** halves — not the imperative half only. |
| Cleanup: "re-evaluate the carve-out added in #6749" | 60 carve-out regions exist repo-wide; 8 are freed by the fix; **7 of those 8 verify clean in-context** (see Phase 3). | Sweep the 7. The 8th (`2026-07-12-…:155`) is retained — see the adjacency hazard below. |
| — (not in issue) | Substituting the filename with the **empty string** can CREATE matches by bringing fragments into adjacency (`terraform foo.yml applies` → `terraform  applies` matches `\bterraform\s+appl\b`). | Substitute a single `_` (a word character), never `""`. Sharp edge, below. |

## Option evaluation (measured, not assumed)

Full-corpus scan, 4 arms, same harness:

| Arm | Latent FP lines removed | Newly flagged (regressions) | Carve-out regions freed | Wall time |
|---|---|---|---|---|
| baseline | — (478 hits) | — | — | 31.9 s |
| **opt1** yaml-neutralize | 8 (3 unique) | **0** | 2 | 74.6 s (naive) |
| **opt2** terraform-anchor | 45 (40 unique) | **0** | 8 | 31.6 s |
| **both** | 49 | **0** | 8 | 33.3 s (optimized) |

8 + 45 = 53 but the union is 49, so the two sets **overlap by 4** — neither is a subset
of the other. Opt1's 3 unique removals are in
`2026-05-25-chore-destroy-guard-sibling-workflows-plan.md:148`,
`2026-06-02-feat-ci-tunnel-apply-generalize-plan.md:102`, and
`2026-07-16-fix-inert-monitor-invariant-registry-heartbeat-plan.md:778`.

Findings that decide the design:

1. **Neither option introduces a single new flag** on the live corpus. The fix is
   purely subtractive against real prose.
2. **Opt2 carries no runtime cost.** Opt1 naively implemented **more than doubles**
   full-scan wall time (32 s → 75 s), because `_has_actor` and `_has_imperative`
   each re-run the substitution per line. Neutralizing **once per line** in
   `scan_text`, behind a cheap fast path that tests **both** `".yml"` and `".yaml"`,
   brings the combined fix to 33.3 s (+4 % vs baseline). This is a required
   implementation detail, not an optimization to defer — and the fast path must test
   both extensions, or the linter is silently broken for every `.yaml` file while all
   the `.yml` fixtures still pass.
3. **Opt1's independent value is the non-`apply` filename family.** Opt2 does
   nothing for a future `destroy-*.yml`, `reboot-*.yml`, `mount-*.yml`, or
   `shutdown-*.yml` workflow — each of which would satisfy `\breboot\b`,
   `\bmount(?:s|ing|ed)?\b`, etc. directly from the filename. A filename is never
   an imperative; opt1 encodes that invariant generally.
4. **Opt2's independent value is prose with no `.yml` in it.** Lines like
   "the `-target=` entry that applies on merge" carry no filename, so opt1 cannot
   help. This is exactly the 45-vs-8 gap.
5. **Option 3 (possessive-actor exclusion) is rejected**, per the issue: a possessive
   actor *would* be a real signal in phrases naming a human's own machine.
6. **Opt2 alone is sufficient for the reported bug.** Verified directly: the #6749 repro
   line run against an opt2-only build exits 0. Opt1 is kept as a deliberate,
   argued-for addition — not because the repro needs it.

**Reviewer dissent, recorded:** the simplicity panel argued opt1 should be cut, since
opt2 alone closes the repro and opt1 adds only 3 unique removals. The counter-argument
kept here: opt1 is ~10 lines behind a fast path, costs +1.4 s, and is the only thing that
stops a future `destroy-*.yml` / `reboot-*.yml` / `mount-*.yml` workflow name from
tripping its own imperative — a family this repo already names that way six times over
with `apply-*.yml`. Reasonable people can land opt2 only; if the implementer prefers the
smaller diff, dropping opt1 (and its four filename fixtures) is a legitimate descope that
still closes #6771.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- lint-infra-ignore start: quotes the linter's own POSITIVE-CONTROL fixture verbatim
     to reason about what the narrowed pattern must keep catching. Test input, not a step. -->
Does opt2 blunt the sentinel? The genuine violation shape — *"the operator runs
`terraform apply -target=…`"* — is matched by the **`terraform\s+appl`** imperative,
not by the `-target` one (note the `-target … apply` pattern requires `appl` to
appear *after* `-target`, which that sentence does not satisfy even today). The
only shape opt2 gives up is un-anchored prose such as "the operator adds a
`-target=` entry then applies", where no tool is named at all. Verified: all four
positive controls below still exit 1.
<!-- lint-infra-ignore end -->

## Prototype validation (already run at plan time)

A fully patched copy of the linter was built and exercised in the scratchpad:

- Existing suite: **`PASS=30 FAIL=0 TOTAL=30`** — no regression in any existing case.
- Full corpus: 478 → 429 hits, **0 newly flagged**, 33.3 s.

The four control fixtures and their measured exit codes:

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- lint-infra-ignore start: the list below IS the linter's test-input corpus. Each
     bullet is a fixture string fed to the linter under repair, with the exit code it
     produced. Quoting a fixture is not prescribing it. -->
- Negative control (repro line, `apply-web-platform-infra.yml` + `operator`) → **exit 0**.
- Positive control `The operator runs terraform apply on the box` → **exit 1**.
- Positive control `` You then run `tofu apply -target=hcloud_server.web` by hand `` → **exit 1**.
- Positive control `The operator SSHs into web-1 and reboots it` → **exit 1**.
<!-- lint-infra-ignore end -->

## Research Insights (deepen pass, 2026-07-20)

### Precedent diff — line-preprocessing in sibling linters

`git grep` over `scripts/lint-*.py` for pre-match text transformation:

| File | Shape | Relation to this plan |
|---|---|---|
| `scripts/lint-rule-bodies.py:97` | `def _normalize(line: str) -> str` — module-level pure function, one-line docstring | **Direct precedent.** `_neutralize_filenames(text: str) -> str` mirrors it exactly: same signature shape, same placement, same docstring convention. Adopt verbatim. |
| `scripts/lint-agents-enforcement-tags.py:132,144` | `PHASE_RE.sub(...)` / `PHASE_PREFIX_RE.sub("", anchor)` on a module-level compiled regex | Precedent for a module-level `*_RE` constant driving a `.sub()`. Note it substitutes the **empty string** — safe there because the result is compared as a whole token, not scanned for adjacent-word patterns. Our case is the opposite and needs `_`. |
| `scripts/lint-infra-no-human-steps.py:133` | `re.sub(r"^[^A-Za-z]+", "", title)` inside `_is_carve_heading` | Precedent inside the file under repair for stripping decoration before matching. |

No precedent uses a fast-path guard before `.sub()`; that is novel here and justified by the
measured 2.3× full-scan cost without it. Flagged for reviewer scrutiny.

### The conceptual line this fix draws

The module docstring makes a deliberate commitment: *"Detection is on the RAW line (inline
backticks are NOT stripped)"* — because a human step hidden behind an inline `` `terraform
apply` `` span still counts. This fix carves one exception out of that principle, and the
exception must be justified on principle, not convenience:

- A **backtick span** can contain a command. Stripping it would hide real imperatives. Keep it raw.
- A **filename** cannot be a command. `apply-web-platform-infra.yml` names automation; it never
  instructs anyone. Neutralizing it removes zero signal by construction.

That asymmetry is the whole argument for opt1, and it is why the substitution is safe to apply
to the actor half as well as the imperative half. Phase 2c must record it in the docstring —
otherwise a future maintainer reads the two statements as contradictory and reverts one.

### Verification sweep (all run at deepen time)

- **Cited rule IDs are active in `AGENTS.md`:** `cq-cite-content-anchor-not-line-number` OK,
  `wg-when-an-audit-identifies-pre-existing` OK. No retired or fabricated IDs.
- **Cited references resolve:** #6771 OPEN (this issue), #6749 MERGED (the PR whose carve-out
  motivated it). Both are issues, not PRs — confirmed via `gh issue view`.
- **All `knowledge-base/` paths cited in the plan and tasks resolve on disk** — zero broken.
- **All 7 sweep-target files exist** at the paths given.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- lint-infra-ignore start: names the SSH positive-control fixture while explaining why the
     network-outage gate does not bind. Quoting the fixture is not prescribing it. -->
- **Network-outage gate (Phase 4.5): does not apply.** The plan matches SSH/handshake keywords
  6× — every match is inside a quoted **test fixture** (the SSH-and-reboot positive control)
  rather than a diagnosis. The plan describes no connectivity symptom and changes no network
  surface, so the L3→L7 checklist has nothing to bind to. Recorded rather than silently
  skipped, because the keyword match is real and a future reader will re-trip it.
<!-- lint-infra-ignore end -->

## Files to Edit

- `scripts/lint-infra-no-human-steps.py` — the two-part fix + module-docstring note.
- `scripts/lint-infra-no-human-steps.test.sh` — regression cases + `MIN_CASES` bump
  (the suite has a minimum-cardinality guard at `MIN_CASES=30`; adding N cases
  requires raising it to `30 + N` or the guard silently stops guarding).
- Carve-out sweep (7 regions, 6 files) — see Phase 3.

## Files to Create

None.

## Implementation Phases

### Phase 1 — RED: regression tests first

Append to `scripts/lint-infra-no-human-steps.test.sh`, then raise `MIN_CASES` to
match the new total.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- lint-infra-ignore start: this section SPECIFIES THE TEST FIXTURES for the linter
     under repair. Every quoted string is an input the suite feeds to the scanner along
     with the exit code it must produce — the sentinel's own test corpus, not a runbook. -->
Mandatory pair (from the issue):

- **Negative control** — a line citing `apply-web-platform-infra.yml` next to the
  word `operator` MUST exit 0. Use the live repro text from #6749 verbatim.
- **Positive control** — a line stating that the operator personally runs
  `terraform apply` during the window MUST exit 1.

Additional cases that guard the specific hazards this fix introduces:

- **Filename-class breadth** — a line citing a hypothetical `reboot-web-hosts.yml`
  next to `operator` MUST exit 0 (proves opt1 generalizes beyond `apply-`).
- **Anchored `-target` still fires** — an actor line containing
  `` `terraform -target=x apply` `` performed by hand MUST exit 1.
- **Adjacency-hazard guard** — `The operator runs terraform pipeline.yml applies cleanly.`
  MUST exit 0. This is the case that fails if the substitution is `""` instead of
  `_`; it is the only mechanical protection against that specific mis-implementation.
- **Actor-side neutralization** — a line citing a hypothetical `operator-digest.yml`
  next to `terraform apply` MUST exit 0.
- **`.yaml` extension** — a line citing `reboot-web-hosts.yaml` (long form) beside
  `operator` MUST exit 0. Load-bearing: an implementation whose fast path tests only
  `".yml" not in lower` passes all six cases above and is still **broken for `.yaml`**.
  This is the only fixture that catches it.
<!-- lint-infra-ignore end -->

Run all seven against the unpatched script before Phase 2. **Exactly three go RED** —
the negative control, the filename-class breadth case, and the actor-side case (the
`.yaml` case shares the breadth case's RED status). The positive control, the
anchored-`-target` case, and the adjacency-hazard guard already **pass** today: they are
regression guards, not new coverage. Do not expect them to be red.

### Phase 2 — GREEN: the fix

Two edits in `scripts/lint-infra-no-human-steps.py`.

**2a. Anchor the `-target` imperative on the tool** (the last entry of
`IMPERATIVE_RES`), matching the shape of every sibling terraform imperative:

```python
# before
r"-target\b.*?\bappl(?:y|ies|ied)\b",                         # -target … apply
# after
r"\b(?:terraform|tofu|opentofu)\b.*?-target\b.*?\bappl(?:y|ies|ied)\b",  # tf … -target … apply
```

**2b. Neutralize `*.yml` / `*.yaml` filenames once per line**, before either half
scans. Add next to the other module-level regexes:

```python
# A filename is never an imperative and never an actor: `apply-web-platform-infra.yml`
# satisfies `\bappl(y|ies|ied)\b` purely because `-` is a word boundary (#6771).
# Substitute `_` (a WORD character), never "": deleting the span can bring two
# fragments into adjacency and CREATE a match ("terraform x.yml applies").
# `*` is in the class so the GLOB form docs actually use (`reboot-*.yml`,
# `destroy-*.yaml`) is covered too — that form is how this repo names workflow
# families, and it is the shape the issue itself writes. A bare `*.yml` is left
# alone: there is no preceding word for it to disguise.
YAML_FILENAME_RE = re.compile(r"\b[\w.*-]+\.ya?ml\b", re.IGNORECASE)


def _neutralize_filenames(text: str) -> str:
    lo = text.lower()
    if ".yml" not in lo and ".yaml" not in lo:   # fast path — most lines
        return text
    return YAML_FILENAME_RE.sub("_", text)
```

and call it **once** at the detection site in `scan_text` (step 5), feeding both
predicates:

```python
scan = _neutralize_filenames(raw)
actor[i] = _has_actor(scan)
imper[i] = _has_imperative(scan)
```

Do **not** call `_neutralize_filenames` inside `_has_actor` / `_has_imperative` —
that doubles the substitution work and is the 32 s → 75 s regression measured above.

**2c. Update the module docstring** — the "Detection is on the RAW line (inline backticks
are NOT stripped)" paragraph must record the one exception and *why it is not a
contradiction*: `*.yml`/`*.yaml` filenames are neutralized first because a backtick span
can contain a command (so stripping it would hide real imperatives) while a filename never
can — it names automation, it does not instruct anyone (#6771). Without that sentence the
two statements read as contradictory and a future maintainer reverts one.

### Phase 3 — Carve-out sweep

Remove the paired `lint-infra-ignore` start/end HTML comments (keeping the body
prose) from the 7 regions the fix un-blinds.

> Note — writing the literal start-marker comment in prose **opens a real region**:
> `IGNORE_START_RE` does not care that it appears inside backticks or inside a
> sentence about markers. This plan therefore names the marker without its `<!--`
> prefix. Out of scope for #6771, but see §Sharp Edges.

| File | start line |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` | 252 |
| `knowledge-base/project/plans/2026-07-07-fix-zot-doppler-registry-isolation-plan.md` | 279, 412 |
| `knowledge-base/project/plans/2026-07-12-feat-inngest-op-arm-no-ssh-doppler-arm-flip-plan.md` | 325 |
| `knowledge-base/project/plans/2026-07-17-fix-workspaces-luks-cutover-env-gate-plan.md` | 94 |
| `knowledge-base/project/plans/2026-07-18-fix-6649-workspaces-luks-escrow-autonomy-plan.md` | 73 |
| `knowledge-base/project/specs/feat-one-shot-6297-anthropic-key-missing-false-page/tasks.md` | 102 |

Line numbers shift as regions are removed — **re-locate each region by its start-marker
content anchor, not by the line number** (`cq-cite-content-anchor-not-line-number`).

**Explicitly retained:** the region at `2026-07-12-feat-inngest-op-arm-no-ssh-doppler-arm-flip-plan.md:155`.
Its body scans clean in isolation but **still flags in context** — unwrapping it makes
the body adjacent to a neighbouring non-blank line, and the adjacency rule pairs them.
This is why the sweep is verified by removing the markers and linting the **whole file**,
never by scanning the region body standalone. Leave it wrapped and note why inline.

The other ~52 carve-out regions in the scan dirs are **out of scope**: they suppress
genuine actor+imperative co-occurrence unrelated to this defect (measured — each still
flags post-fix). No follow-up issue is warranted; they are not blind spots created by
this bug, so the audit gate (`wg-when-an-audit-identifies-pre-existing`) does not fire.

### Phase 4 — Verify

Run the full suite and a full corpus scan; confirm the numbers in §Prototype validation.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash scripts/lint-infra-no-human-steps.test.sh` exits 0 with `FAIL=0` and
   `TOTAL >= 37` (30 existing + 7 new), and `MIN_CASES` in the file equals the new total.
   The existing 30 = 29 `run_case` invocations + the D9 sub-shell pair.
2. <!-- lint-infra-ignore start: ACs 2-3 name the control fixtures by content. -->
   The negative control — the #6749 repro line citing `apply-web-platform-infra.yml`
   beside `operator` — exits **0**.
3. The positive control asserting a human personally runs `terraform apply` exits **1**.
   <!-- lint-infra-ignore end -->
4. The un-anchored pattern is gone and the anchored one is present. Use **fixed-string**
   greps — a BRE pattern over regex source silently under-matches (`..b` demands three
   characters where the text has only `\b`, so the naive form returns 0 on a *correct*
   fix and would block the PR):

   ```bash
   grep -cF 'r"-target'             scripts/lint-infra-no-human-steps.py   # 1 → 0
   grep -cF 'opentofu)\b.*?-target' scripts/lint-infra-no-human-steps.py   # 0 → 1
   ```
5. `_neutralize_filenames` is defined once and called **once**, inside `scan_text` —
   and **zero** times inside `_has_actor` / `_has_imperative`. Verify by reading both
   predicate bodies, not by a raw occurrence count.
6. Full-scan violation count **drops by ~49** and wall time does not regress by more than
   **1.25×**. Measure both arms **on the same machine in the same run** — absolute figures
   are machine-dependent (observed baselines range 32 s–73 s across hosts) and the corpus
   drifts as this PR adds its own artifacts. Do not hard-code 478/429 or a literal second
   count; compute the delta.
7. The post-fix hit set is a strict **subset** of the pre-fix set — zero newly-flagged
   lines. Compare **old script vs new script on the PRE-SWEEP tree** (run this before
   Phase 3): the sweep removes carve-outs, which legitimately *adds* hits under the old
   script and would corrupt the comparison.
8. Exactly **7** `lint-infra-ignore` regions are removed; the
   `2026-07-12-…-arm-flip-plan.md` region at the former line 155 is retained with an
   inline note explaining the adjacency retention.
9. `python3 scripts/lint-infra-no-human-steps.py <file>` exits **0** for every one of
   the 6 swept files (in-context verification, not body-isolation).
10. `bash scripts/test-all.sh` passes (the suite is wired at `test-all.sh:130`).
11. CI's `--changed` arm (`ci.yml:105`) is green on this PR's own diff — this PR edits
    files under the scan dirs, so it must not trip its own gate.

### Post-merge (operator)

None. The change is a CI lint script + docs; no infra, no deploy, no operator action.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is a CI-only
lint gate. The indirect failure mode is the one that matters: if the fix *over*-narrows,
a plan that genuinely prescribes a hands-on-keyboard infra step ships un-flagged, and a
non-technical Soleur user is later handed a terminal command they cannot execute. The
four positive controls exist specifically to bound this.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector.
The script reads repo markdown and writes to stderr; it handles no user data, no secrets,
no network.

**Brand-survival threshold:** none — CI tooling with no user-facing surface and no
regulated-data path. Scope-out: `threshold: none, reason: the change touches only a repo
lint script and its test fixture; no schema, auth flow, API route, or user data is in the
diff.`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI lint tooling change.

## Architecture Decision (ADR/C4)

Not applicable. This is a regex correction inside an existing CI gate; it introduces no
ownership/tenancy boundary, no substrate, no dispatch or trust boundary, and reverses no
ADR. C4 completeness check against all three of `model.c4` / `views.c4` / `spec.c4`: the
change adds no external human actor, no external system or vendor, no container or data
store, and alters no actor↔surface access relationship — the linter is an existing CI
step already inside the system boundary, invoked by no new party. Nothing in the model is
falsified by a narrowed regex. A competent engineer reading the existing ADRs + C4 would
not be misled after this ships.

## Infrastructure (IaC)

Not applicable — no new server, service, secret, cron, DNS record, vendor, or persistent
runtime process. Pure edit to an existing repo script and its test. See the
`iac-routing-ack` note at the head of this plan: the operator-shaped strings in this
document are test fixtures for the linter under repair, not prescribed steps.

## Observability

- **liveness_signal:** the linter runs on every PR (`ci.yml:105`, `--changed` arm) and on
  every commit via `lefthook.yml:104`; cadence = per-PR / per-commit; alert_target = the
  CI job's own red/green; configured_in `.github/workflows/ci.yml` + `lefthook.yml`.
- **error_reporting:** violations print to stderr as `file:line: …` and the process exits
  1; structural errors (unterminated fence / ignore region) are fail-closed. fail_loud: yes
  — there is no silent-pass path.
- **failure_modes:**
  - *over-narrowing (a real hands-on infra step ships un-flagged)* — detection: the four
    positive controls in the suite (AC3 plus the tofu/`-target`/SSH cases); alert_route:
    red test suite in CI.
  - *under-narrowing (the FP persists)* — detection: negative control AC2; alert_route:
    red test suite.
  - *newly-introduced FPs from the substitution adjacency hazard* — detection: AC7's
    strict-subset assertion over the full corpus; alert_route: red AC check at review.
  - *silent perf regression from per-predicate substitution* — detection: AC6's < 45 s
    bound; alert_route: the AC check, and a visibly slower CI lint step.
- **logs:** GitHub Actions job log for the `lint-infra-no-human-steps` step; retention =
  GitHub's default Actions log retention.
- **discoverability_test:**
  - command: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main; echo "exit=$?"`
  - expected_output: `exit=0` on a clean branch; on a branch containing a prescribed
    hands-on infra step, one `file:line: prescribes a human-run infra step …` line per
    violation and `exit=1`.
  - No SSH. Runnable by anyone with the repo checked out, and by CI.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open issue whose body
references `lint-infra-no-human-steps`.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Empty-string substitution creates matches by adjacency | Substitute `_` (word char). Guarded by the `terraform pipeline.yml applies` test case, which is the only mechanical detector of this mis-implementation. |
| Opt1 doubles full-scan wall time | Neutralize once per line in `scan_text`, behind a fast path testing **both** `".yml"` and `".yaml"`. Measured 33.3 s vs 31.9 s baseline. Bounded by AC6's relative 1.25× guard. |
| A `.yml`-only fast path silently breaks `.yaml` | All six `.yml` fixtures pass while `reboot-web-hosts.yaml` still flags. Caught only by the dedicated `.yaml` fixture in Phase 1 — do not drop it as redundant. |
| Opt2 blunts the sentinel on un-anchored `-target` prose | Accepted, and bounded: the genuine hands-on `terraform apply -target=…` shape is caught by the `terraform\s+appl` imperative. Four positive controls assert it. |
| Sweep removes a carve-out that is still needed | In-context verification (lint the whole file post-removal), not body-isolation. This is exactly how the 8th region was caught and retained. |
| Line numbers in the sweep table drift as edits land | Re-locate each region by start-marker content anchor per `cq-cite-content-anchor-not-line-number`. |
| Filename regex `[\w.*-]+\.ya?ml` over-matches | It cannot match across whitespace, so it cannot swallow prose. It intentionally matches dotted/hyphenated/globbed names (`apply-web-platform-infra.yml`, `ci.v2.yaml`, `reboot-*.yml`). Measured A/B: the glob-tolerant and plain forms produce **identical** 429-hit sets on the current corpus — the `*` costs nothing and only broadens the filename class. Bounded by AC7's zero-new-flags assertion. |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Option 1 only (issue's stated preference) | Rejected as sole fix — removes 8 of 49 latent FPs; leaves the `.yml`-free prose class entirely unfixed. |
| Option 2 only | Rejected as sole fix — highest yield (45/49) and free, but leaves `destroy-*.yml` / `reboot-*.yml` / `mount-*.yml` filenames able to trip their own imperatives. |
| Option 3 — exclude possessive actors | Rejected per the issue: a possessive actor *would* be a real signal in phrases naming a human's own machine. Narrows the actor half in a way that loses true positives. |
| Strip filenames from the imperative half only | Rejected — the actor half has the identical failure mode (`operator-*.yml`). Symmetric neutralization costs nothing extra given the once-per-line design. |
| Sweep all 60 carve-out regions | Rejected — measured: only 8 are freed by this fix; the rest suppress unrelated genuine co-occurrence. No follow-up issue needed. |

## Sharp Edges

- The empty-string substitution hazard is **not hypothetical and not caught by any
  existing test**. `terraform foo.yml applies` does not match today; with `""`
  substitution it becomes `terraform  applies`, which matches `\bterraform\s+appl\b`.
  Deleting text from a line can only *add* matches via adjacency — never assume a strip
  is purely subtractive.
- A carve-out region that scans clean **in isolation** can still flag **in context**:
  unwrapping it exposes its body to the adjacency rule against neighbouring non-blank
  lines. 1 of 8 candidate regions in this sweep behaves exactly this way. Always verify
  a carve-out removal by linting the whole file.
- `scripts/lint-infra-no-human-steps.test.sh` ends with a `MIN_CASES=30` cardinality
  guard. Adding cases without raising it leaves the guard permanently satisfied by the
  old floor — a guard that stops guarding.
- The full scan takes ~32 s at baseline (three `.*?` gap segments backtrack over long
  markdown lines). Any new gap-bearing imperative pattern should be timed, not assumed free.
- **Documenting the ignore marker opens a real ignore region.** `IGNORE_START_RE` matches
  the literal `<!--`-prefixed start comment anywhere outside a fence — including inside
  backticks, inside a sentence explaining the marker. Any doc that discusses the carve-out
  syntax silently suppresses everything after it, or (if unpaired) fails the file closed.
  This plan hit it while writing Phase 3. A cheap future fix is to require the marker to be
  the only content on its line; filed as a note here rather than folded into #6771, whose
  scope is the filename false positive. If it recurs, open a follow-up.
- This plan itself lives under a scan dir and quotes actor+imperative prose. It relies on
  the fix landing in the same PR (AC11): the quoted fixtures are either filename-bearing
  (neutralized by 2b) or fenced code blocks (already carved). If a quoted fixture trips
  the gate at CI time, wrap that specific line — do not weaken the sentinel further.
