# Review panel findings — PR #7482 (#7450)

10 of 10 agents returned. **~15 P1s. The PR is NOT mergeable as it stands.**
All four lenses that died during `deepen-plan` were re-run here and all four found P1s.

Panel: `security-sentinel`, `test-design-reviewer`, `code-simplicity-reviewer`, `spec-flow-analyzer`
(the four carry-forwards) + structural-enumeration seat, `user-impact-reviewer`,
`architecture-strategist`, `code-quality-analyst`, `pattern-recognition-specialist`,
`git-history-analyzer`. All spawned report-only; no agent edited the tree.

Everything marked **measured** was executed by the reporting agent, on a sandbox copy.

---

## A. The guard is substantially weaker than it claims (all measured)

| # | Defect | Evidence |
| --- | --- | --- |
| A1 | **Per-line, not per-occurrence.** One line can carry a compliant AND a hostile ref: `SENTINEL="${CLAUDE_PLUGIN_ROOT}/…"; [[ -x "$SENTINEL" ]] \|\| SENTINEL="$(git rev-parse --show-toplevel)/…"` | **Guard 1 16/16 green, all Guard 2 PASS.** The removed fallback pattern, reintroduced as a one-liner. |
| A2 | **G5 asserts co-location, not dispatch.** Converting the preflight's `exit 2; }` to `true; }` (fail-open) stays green — satisfied by the *unrelated* `[[ -r ]]` shape check's `exit 2` below it. | measured green |
| A3 | **`reachedThroughAnchor` → `return true`** unconditionally | measured green |
| A4 | **Delete the whole `#7450` describe block** | measured **green, 9 tests** — `P5`'s counter is closure-scoped to describe #1; G6 dies with what it counts |
| A5 | **Append a neutered `it` below G6** | green at 17 tests — anything below G6 is outside the floor |
| A6 | **Test 19c PASSes on a bare relative path**, printing the decoy's own path — `case` compares an *unresolved* relative string against an absolute prefix, so relative always "passes" | measured |
| A7 | **Oracle shadowing** — an earlier ```` ```text ```` doc example carrying the good literal retargets 18a, 19b and 19c | measured; caught only by G1's G2 (cross-guard redundancy) |
| A8 | **No quoting assertion** on the skills axis; the header declares the canonical form "QUOTED" and the command surface enforces it at P1c | measured green unquoted |
| A9 | **Comment launder** — appending `# ${CLAUDE_PLUGIN_ROOT}/…/redact-sentinel.sh` to a hostile line certifies it (G4 passes too, matching the comment's clean path) | measured PASS |
| A10 | **`GATE_REF_FLOOR` fails OPEN on additions.** Safe for removals (loud RED); the first legitimate 5th site converts zero slack into slack and the bare-basename detection silently disappears | measured |
| A11 | Bare-basename CWD-relative invocation (`cd <dir>` then `bash redact-sentinel.sh`) yields **zero refs** — invisible to G2, and G5 self-disarms via `if (gateRefs(...).length === 0) continue` | measured |
| A12 | 18c false-PASSes if its search root does not exist (`grep` rc 2, `\|\| true` swallows) | measured |
| A13 | No committed negative fixture — every Guard 1 assertion quantifies over a 100%-compliant corpus, so `violations` is structurally always `[]` | — |

**Battery post-mortem:** M1–M10 all mutate the SUT. Seven axes were never edited (intra-line
multiplicity, sub-floor reference shape, floor+1 cardinality, quoting, harness/guard mutation,
dispatch direction, oracle shadowing). Six of the seven produced confirmed vacuities.
*"Ten points along five axes, not ten axes."*

Test Quality Score **7.6/10 (B)**. TDD discipline scored **10/10** — the RED captures are
verifiable in the commit graph (`0962a469e`, `a0c040a1f` precede `96e18d424`).

---

## B. The security claim is overstated (measured)

**B1 — the identity preflight gives ZERO discrimination against the named adversary.**

```
CLAUDE_PLUGIN_ROOT=<worktree>/plugins/soleur  →  PREFLIGHT PASSED, rc=0
CLAUDE_PLUGIN_ROOT unset                      →  HALT, rc=2
```

After `gh pr checkout` the reviewed party's tree **is** a soleur checkout with a byte-identical
`plugins/soleur/.claude-plugin/plugin.json` naming `"soleur"`. Manifest+name is a shape check
too. **ADR-179 §R1 already says this** — and §R1 is *"Tracked in #7450"*, i.e. this issue.

Prose to retract: *"The identity preflight is mandatory, not defence-in-depth."*
Fix that actually inverts the vector — assert the resolved root is **outside the working tree**:
`case "$(cd "${CLAUDE_PLUGIN_ROOT}" && pwd -P)/" in "$(git rev-parse --show-toplevel 2>/dev/null)/"*) halt;; esac`

**What the PR DOES legitimately close:** the git-root *default arm*. With the bare form and the
variable unset the path is root-anchored and nonexistent, so the gate halts. The residual is the
*ambient-`CLAUDE_PLUGIN_ROOT`* vector (direnv/`.bashrc`/`postinstall`, named as measured-working
in ADR-179 §(a)).

**B2 — a worse, uncovered site.** `trigger-cron/SKILL.md:40,43,47` sits on
`${CLAUDE_PLUGIN_ROOT:-plugins/soleur}`, and `trigger.sh:133` runs
`doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -c prd --plain`. ADR-093 names it in the same
breath as the redaction gates. **No env-var precondition at all** — strictly cheaper to exploit
than the vector this PR fixes. Test 18c's needle covers only the git-rev-parse variant, so it
prints "zero … remain anywhere under plugins/soleur/" while this sits on the `./`-relative form.
The "five sites" set came from ADR-179 §R5, which enumerates by **syntax**, not **stakes**.

**B3 — 20 unconditional git-root `source` sites**, all `source "$(git rev-parse
--show-toplevel)/.claude/hooks/lib/incidents.sh"`, across `ship`(7), `deepen-plan`(7),
`brainstorm`(2), `compound`, `plan`, `review`, `work`. `source` executes into the **current**
shell with no `${CLAUDE_PLUGIN_ROOT}` arm. Sharpest instance is self-contained:
`review/SKILL.md:63` instructs `gh pr checkout`; `review/SKILL.md:654` sources. Same file, 591
lines apart. **See §E — blocked on an architectural fork.**

**B4 — `.claude/settings.json:9`** auto-approves, with no prompt,
`Bash(bash $(git rev-parse --show-toplevel)/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh *)`.
Operator config, not payload, but a live instance of the same vector.

---

## C. Defects I introduced (PR-introduced, must fix)

| # | Defect |
| --- | --- |
| C1 | **`linear-fetch` pipe → tempfile.** Pre-diff it piped (nothing on disk); post-diff `PERSIST_SAFE="$(bash "$SCRUBBER" <blob-tmpfile)"` materializes the un-redacted, bearer-URL-bearing blob to a file never created, named, or removed, on 4 halt paths. Surrounding prose still says "piping". |
| C2 | **The block returns nothing.** `$PERSIST_SAFE` is never printed and shell state does not persist across Bash calls, so the fence cannot produce the artifact it exists to produce. Needs `printf '%s\n' "$PERSIST_SAFE"`. |
| C3 | **Nothing checks redaction HAPPENED.** A scrubber returning input unchanged is non-empty, rc 0, all four guards green → unredacted blob labelled PERSIST-SAFE. One `grep -qiE 'uploads\.linear\.app'` closes it, and it is the only check not dependent on the anchor being trustworthy. |
| C4 | **The halt fires AFTER `agent_context` is emitted.** Phase C `extract_images` + the `agent_context` bullet precede the guard, so on every halt the signed URLs are already in the parent transcript. Guards 1–2 are blob-independent → move to a pre-fetch preflight. |
| C5 | **`brainstorm` Phase 0.5 step 3 is an unpatched contradiction.** Its conditional's false branch is "continue with raw `$ARGUMENTS`"; a halt makes the antecedent false, so leaders spawn anyway — directly contradicting the new Phase 0.4 item 4, 30 lines up. |
| C6 | **ADR-179 §R5 asserts a control this PR deleted** — *"`compound` correctly received a non-blocking skip guard"* (removed in `7840b2a42`). Also the plan's §User-Brand Impact and `session-state.md` §Decisions carry the same stale claim; `session-state.md` contradicts itself. |
| C7 | **ADR-179 Decision 2 rescoped to "command or skill file"** — `compound/SKILL.md` is a skill file with a producer and no companion, so my own amended normative text is violated by a site I shipped. Scope it to *secret-gate* skill files (matching G5). |
| C8 | **ADR-093 record edit.** I wrote *"The paragraph below is retained as the record of what was believed"* and then reworded that paragraph to satisfy AC11's grep. It de-fangs the falsification (the *worktree* IS the operator's checkout; its **contents** are the PR author's) and **destroyed a content anchor both ADRs quote** — `"git-root = the operator's own checkout"` now exists nowhere in the body. Restore byte-identical; scope AC11's needle to exclude the quotation. |
| C9 | **Halt message is self-contradictory** — *"re-run `/soleur:incident` from a session where the Soleur plugin is installed"*, reached by typing `/soleur:incident`. "fail closed" is unactionable jargon. Print the resolved root; give a state-discriminating remediation. |
| C10 | **No `SOLEUR_*` telemetry marker** on the three new fail-closed halts. `go.md` and `sync.md` both emit one, and `go.md:26-28` documents why. `hr-observability-as-plan-quality-gate`. |
| C11 | **Pattern A count is wrong for the command published beside it.** `git grep -lF ':-$(git rev-parse --show-toplevel)' -- plugins/soleur/` → **5/5**, not 6/6; the `worktree-manager.sh` site uses `--git-common-dir` and cannot match. My "6" came from a shorter needle than the one printed. Pattern B publishes no command at all (43/45 only reproduce under an unstated `(/\.\.){2,}`; the naive predicate gives 78/90). |
| C12 | **AC5d unmet.** *"Asserted by a test, not by inspection"* — no test asserts it; deleting `[ -n "$PERSIST_SAFE" ]` leaves the suite green. |
| C13 | **`sync.md:94` is `exit 1`** against the `exit 2` I wrote into Decision 2 and scoped to command files → I made `sync.md` non-conformant with my own clause. Also the amendment's *"appeared nowhere in `plugins/`"* is falsified by `sync.md:88`'s `[ -d …/scripts ]` (AND-ed, so not a bypass — the honest form is "nowhere as the *sole* predicate"). |
| C14 | **Un-redacted `mktemp` residue** on the new exit-2 paths in `incident` AND `legal-generate` (the plan named only `incident`). This PR adds an *earlier* halt, so it increases how often the draft is abandoned. No `trap`/`rm -f` at either site. |
| C15 | **Test 19's decoy control is `SENTINEL`-only**, so it never covers `linear-fetch` — the site the PR body calls "the highest residual risk". Generalize 19b's extractor to `(SENTINEL\|SCRUBBER)`. |

---

## D. Record / corpus defects

- **D1 — the superseded learning file was never touched.** `knowledge-base/project/learnings/best-practices/2026-07-08-plugin-root-migration-ac-grep-scope-and-anchor-preservation.md` still instructs *"Preserve the EXACT original fallback anchor per site — never homogenize"* and names the git-root form **for exactly these three redaction gates**, with `synced_to: [work, plan]` so it is agent-retrievable. The plan flagged it as superseded and predicted this exact failure. **Highest-value one-line fix in the set.**
- **D2 — closing #7450 orphans §R1.** ADR-179 §R1 is *"Tracked in #7450"* and is unaddressed; §R5 in the same list now reads "CLOSED by #7450". Re-route R1 before merge.
- **D3** — ADR-093 still asserts the pre-fix state as current (*"the three redaction gates use the git-root fallback"*); classifies `compound` as a secret gate (which ADR-179 §R5's correction exists to deny); and says the ~105 remaining sites *"still follow the guidance below"* (they are unmigrated, not endorsed).
- **D4** — ADR-179 §Relationship-to-prior-decisions still says command-surface-only; §Consequences still says the skills surface is "not migrated here … blocked on this ADR"; frontmatter unchanged.
- **D5 — `tasks.md`: 0 of 48 checkboxes checked**, task 4.4 still mandates the descoped compound guard, task 1.5 says "Phase 5" where the plan says "Phase 4".
- **D6 — `phase-1-measurement.md` Arm 3's inference is logically void.** Non-substitution of a *non-matching* literal cannot distinguish "the pass ran and declined" from "the pass never ran on this surface" — both predict identical bytes. That was the load-bearing bridge to the SKILL surface. **And the un-executed arm IS executable**: a headless `claude -p` from Bash builds its own registry. Run it, or drop the leg and rest the claim on the two independent precedents alone.
- **D7** — the negative branch's blast radius is understated: a negative means 4 skills halt on *every* invocation for *every* CLI operator, permanently, with no durable telemetry (layer-7 residual).

---

## E. BLOCKER — B3/B2/B4 depend on an unsettled architectural fork

All 20 `source` sites target **one** non-payload file (`.claude/hooks/lib/incidents.sh`, 364
lines). `${CLAUDE_PLUGIN_ROOT}` cannot anchor it. ADR-179 leaves exactly two instruments:

1. **Relocate into the payload** (decision 3). Nearly passes the relocatability test —
   `INCIDENTS_REPO_ROOT` already supplies a caller-side data root — but `_incidents_repo_root()`
   defaults to *"three dirs up from its own location"*, which ADR-179 itself calls *"relocatable,
   with a fail-open default … the same construct this ADR rejects one level up in markdown."*
   Requires moving the library, fixing that default, and repointing the 20 skill sites **and** the
   repo-side hooks that source it.
2. **Gate behind the monorepo sentinel** (decisions 4-6). But the sentinel is CWD-relative, and
   **ADR-179 §R1 records it is satisfied by a `gh pr checkout` of a contributor PR and is "not a
   defense on the review path."**

So both sanctioned instruments are blocked on §R1 — which is tracked in #7450 itself.
**This is an engineering/architecture fork with material trade-offs: route the binding decision to
the `soleur:engineering:cto` agent** (`hr`/CTO routing rule), not to the operator. That ruling
governs B2, B3 and B4 together, since all three fail for the same reason.

---

## F. Confirmed NON-findings (stated, not padded)

- `exit 2` **is** reachable at all three gates; `A && B || C` groups correctly; no vacuous arm (measured).
- Fence separation is fail-closed at both gates — rc 127 in a fresh shell (measured).
- The 18c needle concatenation is sound in both directions; the file cannot self-match (measured).
- Test 19c genuinely reddens on a revert of the anchor (measured).
- The `<draft-tmpfile>` placeholder taken literally is fail-closed (rc 2, measured).
- **The hosted Concierge surface is NOT broken** by removing the `:-` arm: `agent-env.ts:230-233`
  injects `CLAUDE_PLUGIN_ROOT` via `assertTrustedPluginPath` and hard-throws when empty.
- `escapeRe` is correct; G4 legitimately catches the doubled-payload-segment error (ADR-179's
  most frequent migration error) which G2 alone would certify.
- `code-to-prd` is not an uncovered sixth gate — its real invocation is `BASH_SOURCE`-relative
  (layout-invariant per ADR-178) — but it IS outside the guard's population, so nothing asserts
  it stays that way.
- No hardcoded secrets, no injection sink, no new network egress in the diff.
- `tsc --noEmit` rc=0; `shellcheck` findings all pre-existing or intentional.
- `main` moved one commit (`fa04b2ae3`, legal corpus) — introduces no new members to any set the
  guards quantify over.
- Historical claims verified: the `98ad03aa8` circularity (all four sites), AC#3-satisfied-by-#7426
  (the five-level walk did exist; the issue's `:48` citation was accurate at that commit), and the
  ADR-177→179 renumber (visible in the commit message).

---

## G. Gotchas for whoever picks this up

- **Do NOT re-run M1–M10.** They pass. The vacuities are on the seven axes they never edit.
- **Mutate a SANDBOX COPY** (`cp -r` to a temp dir), never the tracked tree.
- **Run the un-mutated control first** and require it GREEN — a red baseline voids every row.
- **Assert each mutation LANDED** against a pristine backup (`diff -q`), never against `HEAD`
  (the tree is legitimately dirty during a review pass).
- Guard 1 runs under `want_webplat`, Guard 2 under `want_scripts` — they do **not** always run
  together, which is why 18b should be *strengthened* rather than cut.
- `persist-safe-integration.test.sh` lives under `skills/linear-fetch/scripts/`, which
  `test-all.sh`'s `skills/*/test/*.test.sh` glob never reaches — **the linear rail's only E2E has
  no runner.** Relocate it to `test/` when adding the halt arm.
