---
title: "fix: lint-shell-capture-exit S3/S4 residual blind spots (deferred from PR #8836)"
type: fix
date: 2026-09-25
slug: lint-capture-exit-s34-blind-spots
branch: feat-one-shot-8884-lint-capture-exit-s34
issue: 8884
closes: 8884
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# lint-shell-capture-exit: close the S3/S4 residual blind spots

## Overview

`scripts/lint-shell-capture-exit.py` gained its S3 (dead status read) and S4
(status-leaking `test && action` function tail) classes in PR #8836; its review
deferred a bounded set of residual misses into #8884, all documented in the
gate's HEURISTIC LIMITS docstring. This plan closes the five linter defects —
multi-line compound tails as S3 antecedents, three untracked function shapes for
S4, `set` tokens inside multi-line quoted strings spoofing the errexit model,
literal-prefix status reads (`x=pre$?`), and a quote-blind `;` segmenter — and
evaluates the sixth issue item (PR-head evidence resolution), which is a hook
anchor-drift vector already tracked by #8791/#8790, not a linter defect. Every
claimed miss was reproduced against the live linter during planning; two of them
are wrong-direction findings (a false S3 attribution and an errexit phantom-arm),
not just silence.

Spec lacks valid `lane:` — no spec.md exists for this branch; defaulted to
cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-25 (soleur:deepen-plan, in-process — no Task tool on
this harness; the agent fan-out was replaced by direct reads/greps/bash probes
in this session, recorded under "Deepen-pass findings" below)

**Sections enhanced:** Research Insights, Technical Considerations,
Implementation Phase 1, Observability (added — deepen-plan Phase 4.7 halt
requirement).

### Key Improvements

1. Bash semantics verified empirically at deepen time: `if`/`while`/`case`/`{ }`
   bodies DO honor `set -e` in a non-exempt context (each aborts on an inner
   `false`), a function DEFINITION always returns 0 (so a `}` popping
   func_stack is never a dead-read antecedent), and `until` admits a
   zero-iteration live path (inherited conservative verdict documented).
2. Precedent-diff (Phase 4.4): the sibling
   `scripts/lint-workflow-errexit-capture.py::_heredoc_opener` (:170-201)
   already carries a quote-state scanner — adopt its `\`-escape rule
   (`\` escapes the next char unless single-quoted), which additionally fixes
   unquoted `\'` mis-tracking; and mirror its unterminated-heredoc
   FAIL-CLOSED choice for a quote left open at EOF (re-judge the skipped tail
   as code rather than silently dropping it).
3. deepen halt gates evaluated: 4.6 User-Brand pass (threshold `none`, no
   sensitive-path match — verified by running `SENSITIVE_PATH_RE` against the
   Files-to-Edit list); 4.7 Observability — section ADDED (Files-to-Edit is
   not pure-docs); 4.8 PAT sweep clean; 4.9 UI — no UI-surface files; 4.10
   Encryption — no store/connection; 4.11 Guard Contract — `lint-guard-contract.py`
   green on 3 entries, assemblies are structural (chokepoints named).

## Problem Statement / Motivation

The gate is fail-silent by design — every heuristic limit documented in its
docstring errs toward missing a finding rather than inventing one. That is the
right default for a lint gate, but each documented miss is also a hole the class
can recur through: the whole reason the gate exists (ADR-166) is that this
defect family kept re-appearing in disguises reviewers missed. #8884 is the
burn-down of the residual disguises.

Empirical verification (fixtures run against the linter on this branch, 2026-09-25):

| # | Shape | Today | Direction |
|---|-------|-------|-----------|
| M1 | `if …\n worker\nfi` then `rc=$?` | silent | miss — the `fi` line resolves as antecedent and is protected |
| M2 | `report()` newline `{` … `(( c )) && echo` … `}` | silent | S4 miss — opener regex requires same-line `{` |
| M3 | `report() (` … `)` paren body | silent | S4 miss — paren-bodied functions never tracked |
| M4 | `report() {` … `(( c )) && echo "x"; }` | silent | S4 miss — mid-line `}` never pops the function stack |
| M5 | `bash -c '…\nset -e\n…'` then `x=$(grep …)` | **false S1** | spoof — quoted `set -e` arms the model; wrong-direction finding |
| M6 | `worker` then `x=pre$?` | silent | miss — READ_RE requires the status immediately after `=` |
| M7 | `echo 'a;b'; rc=$?` | **false S3 antecedent `b'`** | mis-segmentation — `;` inside quotes splits, producing a phantom `b'` segment (a true dead read reported under the wrong command text) |
| M8 | `while read l; do … done < f` then `rc=$?` | silent | miss — same as M1 |
| M9 | `if c; then worker; fi; rc=$?` (same line) | silent | miss — `fi` segment is protected even mid-line |
| M10 | `case … esac` then `rc=$?` | silent | miss — same as M1 |
| M11 | `{ worker }` group then `rc=$?` | silent | miss — `}` antecedent exempted wholesale |
| M12 | `set -e` then `bash -c '…\nset +e\n…'` then `worker\nrc=$?` | silent | **fail-silent spoof** — quoted `set +e` clears the model, hiding the real dead read after it |

The same-line quoted-`;` defect also has a fail-silent arm: `echo 'x;set +e';
rc=$?` produces a phantom `set +e'` segment that clears the model and silences
the read. So "quote-blind segmentation" and "per-line quote context" are one
root — the model has no cross-line/persistent quote state — and both directions
of it are live today.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #8884 is `OPEN`, no closing PR — premise live.
- PR #8836 (`feat(ci): lint-shell-capture-exit covers the fn; rc=$? dead read
  and fn-tail status leak (#8784)`) merged 2026-09-25T13:43Z; the deferral
  source is real. Review trailer `87c6352b8c` and the fix commits
  `c2649419bb`, `1247858959`, `ffc4cee5be` all resolve.
- `scripts/lint-shell-capture-exit.py` (914 lines), `.test.sh` (874 lines,
  `MIN_ASSERTIONS=74`), and `.baseline.txt` (210 lines) exist on this branch;
  the gate is registered in `scripts/test-all.sh` (`run_suite` rows
  `lint-shell-capture-exit` at :3303 and `-live` at :3304, the latter invoked
  WITH `--baseline`). Tracked `*.sh` census is now 1275 (issue says 1272;
  drift only).
- Every issue claim was re-verified empirically (the M1–M12 table above) —
  none is stale, and two are worse than the issue describes: the quote spoofs
  run in BOTH directions (M5 false-arm → false S1; M12 false-clear → hidden
  real finding), and the `;` split mis-attributes an existing true positive
  (M7).
- Mechanism check vs the ADR corpus: nothing here proposes a new mechanism —
  it extends an existing `scripts/lint-*` gate along the axis its own
  docstring scopes. `WHY NOT shellcheck` (linter :47-52) already rejected the
  only alternative tool. No ADR rejects a state-model/regex-model fix on this
  gate. ADR-166 is the standing charter.
- **PR-head evidence resolution (issue item 6)** evaluated: it describes
  `pre-merge-rebase.sh` reading `origin/main..HEAD` in a session-anchored
  detached checkout — a hook behavior, nothing in this linter. The residual
  cwd-scoped merge-gate class is already tracked by **#8791**
  (`hooks(pre-merge): residual cwd-scoped merge-gate follow-ups after #8778`)
  with sibling **#8790** (`cla-signed-author-gate` same vector).
  **Disposition: out of scope — acknowledge, do not re-file.**

### Property List (Phase 0.6b)

- P1: a `rc=$?`-family read after a closed multi-line compound
  (`fi`/`done`/`esac`/group `}` — line-initial or mid-line segment) is judged
  against the compound's armed interior, not silently absorbed by the
  protected closer token — symmetric with the already-flagged one-line
  `if c; then cmd; fi`.
- P2: S4 judges the tail of every POSIX function definition shape —
  `name() {`, `name()` newline `{`, `function name`, `name() (` — and every
  `}` position — `}`-only line, `cmd; }`, `}; rest`.
- P3: text inside an open quote (same-line or spanning logical lines) is data:
  it produces no `set` verdict, no status-read anchor, and no `;` statement
  boundary for this shell's model — in both directions (no phantom arm, no
  phantom clear).
- P4: `name=<literal>$?` reads (`x=pre$?`) anchor the same as `name=$?`.
- P5: no false positives introduced on the protected idioms the suite already
  pins (`cmd || rc=$?`, function-head caller-status reads, `$( )` interiors,
  the canonical `if cmd; then rc=0; else rc=$?; fi` rewrite — including its
  multi-line form, where the `fi` closer must not be swept into the new
  compound-closer handling).

### Cut List (Phase 0.6b)

- **A second linter / shellcheck for the residual shapes** → covers all of
  P1–P4 nominally → cut: same-file extension is strictly cheaper; the gate
  already owns errexit tracking, heredoc/comment blanking, continuation
  folding, segment state, fingerprinting and baseline. shellcheck stays
  rejected per the gate's own `WHY NOT shellcheck`.
- **Full bash parser (grammar-level correctness)** → covers every residual
  shape including `$'…'` ANSI-C quoting, `name() cmd` bodies, heredoc-quoted
  `set` strings → cut: dependency + runtime cost for a heuristic gate whose
  remaining misses are documented and fail silent; the lexer deltas below
  cover the issue's list without a grammar.
- **PR-head evidence resolution fix** → buys no property this plan lists (it
  is a hook anchor-drift defect, not a linter property) → cut to existing
  tracking: #8791 (pre-merge residual) / #8790 (sibling gate). No new issue
  filed — #8791 already owns the residual bucket.
- **Bare `$?`-in-argument reads** (`echo "rc=$?"`, `exit $?`) → adjacent
  class, still declined exactly as the parent plan declined it — noisier
  calibration, not in the issue's ask.

### Repo research (in-process — no Task tool on this harness)

- **S3 antecedent resolution** (`scan()`, :688-772): the back-walk returns the
  whole previous logical line — which is why one-line
  `if c; then cmd; fi` flags (the `;` + closer text makes `is_protected`
  decline it, :431-438) while a closer-ONLY line (`fi`, `done`, `esac`, `}`)
  is protected by `CONTROL_PREFIX_RE` (:175) or `_s3_exempt_command`'s
  `startswith("{","}")` arm (:475). The fix locus is one place: reclassify a
  resolved candidate that IS a closer (`fi`/`done`/`esac` + optional
  redirect/`;`, or `}` closing a GROUP rather than a function definition) as
  the just-closed compound — unprotected, judged armed at the closer's
  position. `}` requires func_stack awareness: a `}` that pops a function
  DEFINITION is not an execution (`f() { … }` then `rc=$?` reads the
  definition's status — boring, not dead; stays silent).
- **Function tracking** (:577-614): `FUNC_OPEN_RE` requires the `{` on the
  opener line; the stack pop fires only on `BRACE_CLOSE_RE` (`^}\s*$`); inner
  `{` groups increment only when a line ENDS in `{`. All three reported shapes
  fall out of those three anchors.
- **Quote context** is per-line only: `_unquoted` (:346-370) is applied to
  single strings; pass 1 (:533-559) never carries quote state across logical
  lines, so a `set` line inside `bash -c '…` open-quote runs `set_verdicts`
  as code (m5/m12 verified).
- **`_segments`** (:373-400) splits on every `;` byte — paren-aware via
  `d`, quote-blind (m7 verified, including the phantom `set +e'` segment).
- **`READ_RE`** (:194-195): `name=` + `"?` + status — nothing between `=` and
  the status token, so `x=pre$?` never anchors (m6 verified).
- **Heredoc handling** already blanks bodies pre-pass (`drop_heredocs`,
  :238-253), so the cross-line quote tracker composes with existing
  preprocessing; comments are blanked first (`strip_comment_lines`, :233-235).
- **Fixture conventions** (`.test.sh`): `write_fix`/`run_lint`/`assert_fires`/
  `assert_silent`, every must-not-fire fixture guarded by positive controls,
  `MIN_ASSERTIONS` floor raised deliberately in the same edit (`CAPTURE_LINT_
  MIN_ASSERTIONS` env override exists for development).
- **Live-gate behavior on widening**: the parent PR's widening surfaced REAL
  bugs (worktree-manager.sh `git branch -D`, ci-deploy.sh `docker exec`,
  guardrails.sh, sdk-bump-sandbox-gate.sh, ~15 test-file captures) — expect
  this pass to again emit true positives on the 1275-script tree; the plan
  carries a triage phase, not a blind baseline regen.
- **Functional/community overlap**: evaluated in-process (no Task tool). No
  uncovered stack (bash/Python in-repo); the community answer is on file in
  the gate's `WHY NOT shellcheck` — nothing new to install.
- **Advisor consult (Phase 4.5)**: skipped — no Task tool in this harness;
  the riskiest decision (compound-closer semantics vs function-definition
  `}`; both quote-spoof directions) was resolved by running the linter on
  reduced fixtures and pinning the POSIX errexit rule (compound bodies DO
  honor errexit when the compound itself is evaluated in a non-exempt
  context — the same semantics the one-line form already flags on).
- **SpecFlow (Phase 3)**: folded in-process — the bash-conditional edge cases
  are enumerated as the M-fixture matrix and the must-not-fire rows in
  Implementation Phases; no agent spawn capability in this harness.

### Deepen-pass findings (Phase 4/4.4/4.45 — in-process)

- **Precedent-diff (Phase 4.4):** the quote-state scanner this plan adds is NOT
  novel — `scripts/lint-workflow-errexit-capture.py::_heredoc_opener`
  (:170-201) already tracks `in_single`/`in_double` over a line to decide
  whether `<<` is a real redirection. Side-by-side differences that matter:
  (a) the sibling's escape rule is `\` skips the next char *unless
  single-quoted* — correct for unquoted `\'` (`echo don\'t` does not open a
  quote) and strictly more accurate than this linter's `_unquoted`, which
  escapes only inside `"…"`; ADOPT the sibling rule for the cross-line
  tracker and note the divergence (or unify `_unquoted` in the same edit —
  measure churn, prefer unifying). (b) The sibling's unterminated-heredoc
  rule is FAIL-CLOSED (blank nothing, keep scanning — :158-165, "fail toward
  'scan it as code'"): mirror it for a quote still open at EOF — re-judge the
  quote-skipped tail as code rather than silently dropping findings, and pin
  the direction with a fixture.
- **Empirical bash-semantics verification** (ran `bash -c` repros at deepen
  time): `set -e` DOES abort on a failing command inside `if`/`while`/`case`/
  `{ }` bodies evaluated in a non-exempt context — so a `rc=$?` after the
  closer is genuinely dead on the armed path; a function DEFINITION
  (`f() { false; }`) returns 0 and cannot abort, so the read after a
  definition-closing `}` is boring-not-dead — the func_stack discriminator in
  Guard 2 is load-bearing, not decorative; `until true; do false; done` runs
  zero iterations and leaves a live `$?` — the conservative flag-anyway
  verdict matches the existing one-line rule (symmetric, honest under both
  context arms per the docstring's S3 note).
- **Verify-the-negative pass (4.45):** the plan's negative claims were checked
  against the code — `x='$?'` is already non-matching today (single-quoted
  value, `READ_RE` requires `"`/bare status — verified by inspection of
  :194-195); the sensitive-path claim was executed (grep of the Files-to-Edit
  list against the canonical `SENSITIVE_PATH_RE` → no match); PAT sweep
  (Phase 4.8 regex) clean. No claim contradicted.
- **Post-edit self-audit (4.45):** plan greps its own citations — every
  `knowledge-base/` path resolves; the only forward reference is this
  feature's own `tasks.md` (created with it). Fixture numbering normalized
  (no gaps in the M-table).
- **Agent fan-out disclosure:** the deepen workflow prescribes parallel
  skill/research/review Task agents (Phases 2/3/4/5). This harness exposes no
  Task/subagent spawn; all passes were executed in-process by direct file
  reads, `git`/`gh`/`grep` probes, and `bash -c` semantics checks — same
  evidence, no panel breadth. Residual risk: a reviewer-seatable taste/class
  finding an in-process pass cannot see; flagged for the PR review phase.

### Related issues / PRs

- #8884 (this), PR #8836 / #8784 (parent classes), #7332/PR #7336 (original
  S1/S2 class), #8791 + #8790 (the anchor-drift item's real home).
- Learnings:
  `knowledge-base/project/learnings/2026-09-25-the-errexit-model-must-be-judged-at-the-commands-position-and-every-text-channel-is-an-fp-vector.md`
  (the quote/text-channel FP vectors — this plan is their continuation),
  `2026-09-19-i-simulated-the-regex-and-segmented-the-pipeline-by-eye.md`
  (quote-blind terminator cuts fall OPEN — the M7 shape, measured before),
  `2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint.md`
  (ADR-166 charter),
  `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  (mutation-matrix rows must include dispatch and second-member),
  `2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md`
  (a baselined linter run WITHOUT `--baseline` re-reports the whole baseline —
  the live triage run must use the registered invocation).

## Open Code-Review Overlap

Query: all open `code-review` issues' bodies searched for each Files-to-Edit
path (`scripts/lint-shell-capture-exit.py`, `.test.sh`, `.baseline.txt`) plus
the bare `lint-shell-capture-exit` token. Only match: **#8884 itself** (this
issue — self-reference). Adjacent-but-distinct classes remain untouched:
#7005 (`grep -q` pipefail fail-open sweep), #7311 (`-z`-guarded assignments),
#8791/#8790 (the anchor-drift item). **Disposition: none to fold in** — the
plan fixes exactly the issue's own list.

## Proposed Solution

Five bounded changes inside `scripts/lint-shell-capture-exit.py`, each pinned
by failing fixtures written FIRST (`cq-write-failing-tests-before`), then a
live-tree triage + baseline regeneration:

1. **Cross-line quote state (P3).** Compute `quote_at[pos]` in pass 1 — the
   open-quote character (`'` or `"`) in force at the START of each logical
   line, carried forward by the same scan `_unquoted` uses per-line. A line
   beginning inside an open quote is data for this shell: no `set_verdicts`
   contribution (kills the m5 phantom-arm and the m12 phantom-clear), and no
   S1/S2/S3 evaluation in pass 2 (a `rc=$?` inside a multi-line
   `bash -c '…'` literal is judged by the inner interpreter — the cross-line
   generalization of the existing same-line quote exemption at :662-674).
   Composes with the existing pre-passes: comments blanked first, heredoc
   bodies blanked before quote tracking.
2. **Quote-aware `;` segmentation (P3, same root).** `_segments` (:373-400)
   gains `'`/`"` tracking identical to `_unquoted`'s (including the `\\`-
   inside-double-quotes escape): a `;` inside quotes accumulates into the
   segment instead of splitting. Paren `depth` counting moves to the
   quote-masked text so `(`/`)` inside literals stop skewing depth (fixes the
   "parens in literals" documented limit along the way). Result: `echo 'a;b';
   rc=$?` resolves antecedent `echo 'a;b'` (correct dead-read attribution) and
   `echo 'x;set +e'` can no longer mint a `set` segment.
3. **Compound-closer antecedent resolution (P1).** A resolved S3 candidate
   that is a closer — `fi`/`done`/`esac` optionally followed by redirect/`;`
   tokens, or `}` closing a `{` GROUP — is reclassified as "the just-closed
   compound": not protected, judged armed at the closer's position (same
   `cmd_state` channel as today). A `}` that pops a function DEFINITION
   (func_stack) is NOT a compound antecedent — it is a definition, its status
   is the definition's, and the read stays silent. Applies at both resolutions
   the issue names: closer-only LINE on back-walk (m1/m8/m10/m11) and closer
   SEGMENT mid-line (m9, `cmd; fi; rc=$?`).
4. **Full function-shape tracking (P2).** (a) Pending-opener state: a line
   matching the `name()`/`function name` head with no `{` records a pending
   function; the next non-blank logical line leading with `{` opens the body
   (anything else discards the pending record). (b) `name() (` opens a
   paren-bodied function onto the same stack with its own closer shape (`)`-
   initial line; plus the pending form `name()` newline `(`). (c) Mid-line
   brace bookkeeping on quote-masked text: standalone `{`/`}` tokens (a token
   that IS exactly the brace — which excludes `${…}`, `{a,b}` expansion, and
   brace literals inside quotes) manage the inner-group counter and the
   function pop wherever they sit, not only at line end; the S4 tail for a
   mid-line `}` is the last segment before it on that line (`cmd; }` → `cmd`),
   falling back to `last_nonempty` for line-initial `}` (unchanged path).
5. **Literal-prefix reads (P4).** Widen `_STATUS`/`READ_RE` to admit a literal
   prefix in the value: `name=` then optional `"` then a run of chars
   containing no `$`, quote, whitespace, or operator before the status token —
   `x=pre$?`, `rc="pre: $?"` anchor identically to `x=$?`. Single-quoted
   values stay excluded (a literal `'$?'` is not a read — unchanged).

Then the **docstring** gets its accounting: the HEURISTIC LIMITS entries for
the five closed items are removed or rewritten to the surviving residual
(`$'…'` ANSI-C strings, `name() cmd` bodies, `;;` inside case arms, reads
after a function DEFINITION closing `}`), and THE RULE gains the compound /
function-shape / quote-state paragraphs.

## Technical Considerations

- **Definition-vs-execution `}` is the only new semantic distinction** in the
  whole change: every other closer (`fi`/`done`/`esac`, group `}`) marks an
  executed compound; a `}` that pops func_stack marks a definition. Get the
  ordering right — consult func_stack BEFORE treating a `}` segment/line as a
  compound antecedent, and process the S4 tail check at the same moment.
- **The canonical fix must stay silent in multi-line form.** The gate's own
  remediation `if cmd; then rc=0; else rc=$?; fi` spread over lines puts
  `rc=$?` inside the compound — its antecedent resolves through the `else`
  arm to the `if` CONDITION, which ran exempt. Pin it as a must-not-fire
  fixture BEFORE implementing the compound-closer change so a regression is
  caught red, not diffed out later.
- **POSIX nuance, inherited deliberately:** the one-line rule already flags
  `until c; do cmd; done` / `if c; then cmd; fi` unconditionally even though a
  zero-iteration/`false`-condition path leaves a live `$?`. Multi-line
  handling keeps the same conservative verdict — symmetric, and the flag's
  remediation is correct either way. Stated here so a reviewer does not
  re-derive the objection.
- **`;;` inside case arms** produces `;`-split empty fragments today; the
  quote-aware splitter must keep treating `;;` as separators (they are
  unquoted). Harmless today (empty segments skip); pin with a fixture.
- **NFR/runtime:** still one `git ls-files` pass; the quote tracker adds one
  linear scan per line — unchanged ~2s envelope over 1275 scripts.
- **Security:** none — reads repo text only. The M5 fix REMOVES a wrong-direction
  finding (phantom-armed `set` on data); the M12 fix removes a fail-silent
  suppression. No sensitive-path regex match (verified against preflight
  `SENSITIVE_PATH_RE`: `scripts/lint-*` matches none of its arms).
- **Paper-resolution lint:** every FR above names its implementation locus —
  `scan()` pass-1 loop (:533-559), `_segments` (:373-400), `_unquoted`
  (:346-370), `FUNC_OPEN_RE`/`BRACE_CLOSE_RE` (:205-212), the func-boundary
  block (:577-614), the S3 antecedent resolver (:688-772), `READ_RE`/`_STATUS`
  (:194-195), `is_protected`/`_s3_exempt_command` (:426-479).

## Implementation Phases

### Phase 1: quote model (P3 — foundation; m5/m7/m12)

- Fixtures FIRST (must go red against the unmodified linter):
  - must-fire: `set -e` + `bash -c 'a\nset +e\nb'` + `worker` + `rc=$?`
    (m12 — the quoted clear must NOT disarm the real read);
    `echo 'a;b'` + `rc=$?` fires S3 naming `echo 'a;b'` as antecedent.
  - must-not-fire: `set -uo pipefail` + `bash -c 'a\nset -e\nb'` +
    `x=$(grep p f)` (m5 — the quoted arm must NOT arm; grep capture under
    nounset-only is out of premise); a `rc=$?` text INSIDE a multi-line
    `bash -c '…'` string produces no finding.
- Implement `quote_at[]` in pass 1 and the open-quote line skip in both
  passes; make `_segments` quote-aware; move depth counting onto masked text.
  Escape semantics ADOPT the sibling precedent
  `lint-workflow-errexit-capture.py::_heredoc_opener` (:170-201) — `\` escapes
  the next char unless single-quoted (covers unquoted `\'`, which
  `_unquoted`'s in-double-only rule mis-tracks); unify `_unquoted` to the same
  rule or document the divergence in the docstring. A quote still open at EOF
  re-judges the skipped tail as code — fail-closed, mirroring the sibling's
  unterminated-heredoc rule (:158-165) — pin with a fixture.
- Raise `MIN_ASSERTIONS` in the same edit as the fixtures land.

### Phase 2: S3 compound-closer antecedents (P1 — m1/m8/m9/m10/m11)

- Fixtures FIRST:
  - must-fire: multi-line `if/fi`, `while/done < f`, `for/done`, `case/esac`,
    `{ … }` group, each followed by `rc=$?`; same-line `if c; then w; fi;
    rc=$?` and `cmd; done`-style segment closers.
  - must-not-fire: multi-line `if cmd; then rc=0; else rc=$?; fi` (canonical
    fix); `f() { worker; }` then `rc=$?` (definition close, not execution);
    `until`-arm asymmetry documented or pinned silent per implementation
    choice — whichever is chosen, a fixture pins it.
- Implement the closer reclassification in the antecedent resolver with the
  func_stack-aware `}` exclusion.

### Phase 3: S4 function shapes (P2 — m2/m3/m4)

- Fixtures FIRST:
  - must-fire: `name()\n{` tail; `name() (` … `)` tail; `name() {` …
    `test && act; }` mid-line closer; `}; rest` close with a prior
    `test && act` line; pending `name()\n(`.
  - must-not-fire: `{a,b}` brace expansion and `${x}` inside bodies do not
    perturb the group counter; predicate-named functions still exempt under
    every new opener shape; `cmd || { a; b; }` one-line group inside a
    function does not mis-pop.
- Implement pending-opener state, the `name() (` opener + `)` closer, and
  per-segment standalone-brace bookkeeping for mid-line `}`/`{`.

### Phase 4: literal-prefix reads (P4 — m6)

- Fixture FIRST: `worker` + `x=pre$?` fires S3; `x=pre$?` under `set +e`
  silent; `x='$?'`-style literal stays silent (must-not-fire control).
- Widen `READ_RE`/`_STATUS` per Proposed Solution item 5.

### Phase 5: docstring, live triage, baseline

- Rewrite the five closed HEURISTIC LIMITS entries; add the surviving
  residuals; extend THE RULE with the new semantics.
- Run the live gate with the REGISTERED invocation
  `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt` over the whole tree — the
  widening WILL surface newly-visible findings; triage each: real defect →
  fix in this PR (parent PR precedent: 4 live bugs + ~15 test-file captures
  fixed, not baselined); benign pre-existing → keep for the baseline regen.
- Only after triage: `--write-baseline` regeneration, committed in the same
  PR; diff must show new keys only in the newly-covered shapes and all prior
  keys persisting.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Full bash grammar/parser dependency | Cost and dependency footprint for a heuristic gate whose remaining misses are documented; the lexer deltas cover the issue's list. |
| Defer the quote-spoof fix (M5 is "only" an FP) | M12 shows the same root runs fail-silent — a quoted `set +e` suppresses real later findings; fixing one direction without the other is impossible anyway (same quote-state mechanism). |
| Scope to line-level closers only (skip `cmd; fi` mid-line segments) | m9 verified silent today; the segment path shares the resolver — half a fix at the same cost. |
| Track function bodies with a brace counter only (no func_stack split) | `}` closing a function DEFINITION vs a group is the one distinction that decides a finding; a bare counter cannot express it. |
| Fix PR-head evidence resolution here | Not a linter defect — already tracked by #8791/#8790; folding it in would mix a hook fix into a lint-gate diff. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong lint verdict on
  `test-all.sh` — either a false `[REJECT]` blocking an unrelated PR, or a
  silently-missed dead read in a script. Developer-facing CI friction only;
  never end-user-facing.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — the gate reads tracked shell files and prints findings; no data
  surfaces, no new network or credential paths.
- **Brand-survival threshold:** `none`

## Observability

The deliverable is a CI lint gate — its observability surface IS the suite
verdict. No new runtime surface is introduced.

```yaml
liveness_signal:
  what: "the `lint-shell-capture-exit` / `lint-shell-capture-exit-live` suite verdict lines in test-all output"
  cadence: "per local `scripts/test-all.sh` run and per CI invocation"
  alert_target: "suite RED blocks the test-all aggregate (fails the commit/CI run)"
  configured_in: "scripts/test-all.sh:3303-3305 (run_suite rows)"

error_reporting:
  destination: "stdout/stderr of the suite runner — the linter prints per-finding `[S1|S2|S3|S4]` blocks"
  fail_loud: "a `[REJECT] lint-shell-capture-exit: N NEW finding(s)` line and non-zero exit"

failure_modes:
  - mode: "a newly-covered blind spot fires on the real tree (true positive on pre-existing code)"
    detection: "`lint-shell-capture-exit-live` suite prints the finding file:line and exits 1"
    alert_route: "the failing suite output itself — no external route"
  - mode: "baseline regenerated from a subset scan (truncated grandfather set)"
    detection: "`--write-baseline` with explicit paths exits 2 (refusal built into the gate)"
    alert_route: "exit 2 + stderr refusal message"
  - mode: "detector goes vacuous (parses nothing, reports 0)"
    detection: "MIN_ASSERTIONS floor in scripts/lint-shell-capture-exit.test.sh fails the suite"
    alert_route: "suite RED on the fixtures run"

logs:
  where: "suite stdout (local) / CI job log (workflows running test-all.sh)"
  retention: "CI retention policy; local run is ephemeral"

discoverability_test:
  command: "python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt"
  expected_output: "0 new findings"
```

## Guard Contract

### Guard 1 — quote model & segmenter integrity

**Property.** Text inside an open `'`/`"` quote — on one line or spanning
logical lines — is data: it yields no `set` verdict, no status-read anchor,
and no `;` statement boundary for this shell's errexit model.

**Assembly.** Every logical line of every tracked `*.sh` through the two
chokepoints: pass-1 state fold (`quote_at`, `set_verdicts`, `depth_at` in
`scan()` :533-559) and pass-2 `_segments` (:373-400) + read evaluation
(:640-772).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `set -e` + multi-line `bash -c '…\nset +e\n…'` + `worker` + `rc=$?` | RED — quoted `set +e` must not clear; S3 fires on the real read |
| 2 | Revert quote state to per-line (`quote_at` always "closed") | RED — the multi-line-quote fixtures all fail (dispatch/vacuity row) |
| 3 | Two consecutive multi-line quoted strings, `set +e` inside the SECOND only | RED — state must carry past the first string, not reset per string (second-member row) |
| 4 | `echo 'x;set +e'; rc=$?` (same-line quoted `;`) | RED — no phantom `set` segment; the read resolves `echo` as antecedent |
| 5 | (Harness) drop the m12 must-fire fixture | RED via `MIN_ASSERTIONS` floor — the floor rises with the fixtures |
| 6 | (Must-PASS, non-canonical) `bash -c '…\nset -e\n…'` under `set -uo pipefail` (no -e) | stays silent — a quoted `set -e` cannot arm the model either |

### Guard 2 — S3 compound-closer antecedents

**Property.** A status read whose antecedent is a just-closed compound
(`fi`/`done`/`esac`, group `}`; line or segment) resolves to that compound —
unprotected, judged armed at the closer — while a `}` that closes a function
DEFINITION is never an antecedent.

**Assembly.** The antecedent resolver's two resolution paths — same-line
segments and the back-walk (`scan()` :695-739) — plus the protection
predicate pair `is_protected`/`_s3_exempt_command` (:426-479) where closer
tokens are currently exempted wholesale. Func-stack membership at the `}` is
the definition-vs-execution discriminator.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Multi-line `if …\nworker\nfi` + `rc=$?` fixture | RED — S3 fires |
| 2 | `while read l; do w; done < f` + `rc=$?` AND `case … esac` + `rc=$?` in one file | RED — both named (closer-class second-member row) |
| 3 | Same-line `if c; then w; fi; rc=$?` | RED — segment-level closer, not just line-level |
| 4 | Neuter closer recognition so `fi`/`done`/`esac`/`}` stay protected | RED — every compound fixture fails (dispatch row) |
| 5 | (Order/lifetime) multi-line canonical fix `if cmd; then rc=0; else rc=$?; fi` | stays silent — the read inside the compound resolves to the exempt condition; a guard that flags it rejects its own remediation |
| 6 | (Must-PASS, non-canonical) `f() { worker; }` then `rc=$?` | stays silent — definition close is not an execution |

### Guard 3 — S4 function-shape coverage

**Property.** The function stack tracks every POSIX function definition
shape — `name() {`, `name()` newline `{`, `function name`, `name() (` — and a
`}`/`{` group token manages the stack wherever it appears, so a leaking
`test && action` tail cannot hide behind opener or closer syntax.

**Assembly.** The open/close machinery: `FUNC_OPEN_RE` (:205-208) plus the
new pending-opener and `name() (` forms, `BRACE_CLOSE_RE` (:212) plus the new
per-segment standalone-brace bookkeeping in the func-boundary block
(:577-614). The quantified set is the tail statement of every function
definition in tracked `*.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `report()` newline `{` … `(( c )) && echo` … `}` | RED — S4 fires on the deferred-brace opener |
| 2 | `report() (` … `(( c )) && echo` … `)` | RED — paren body tracked |
| 3 | `f() { (( c )) && echo x; }` mid-line `}` AND a second `g() { (( d )) && echo y; }` | RED — both named (second-member row) |
| 4 | Drop mid-line `}` handling (pop only on `^}\s*$`) | RED — the mid-line fixtures pass green only under a vacuous tracker (dispatch row) |
| 5 | (Harness) stub the linter to exit 0 | RED — must-fire fixtures fail |
| 6 | (Must-PASS, non-canonical) `check_x() {` … `{a,b}` expansion + `${v}` refs … `}` | stays silent — brace-expansion/`${}` tokens never perturb the counter |

## Files to Edit

- `scripts/lint-shell-capture-exit.py` — quote state + quote-aware
  `_segments`, closer reclassification, function-shape tracking, `READ_RE`
  widening, docstring.
- `scripts/lint-shell-capture-exit.test.sh` — new fixtures (must-fire +
  must-not-fire per phase), `MIN_ASSERTIONS` floor raised in the same edit.
- `scripts/lint-shell-capture-exit.baseline.txt` — regeneration only after
  live triage (Phase 5).
- `knowledge-base/project/specs/feat-one-shot-8884-lint-capture-exit-s34/tasks.md`
  — this feature's task list.
- Conditional: any `*.sh` whose newly-visible live finding triages as a real
  defect (same disposition rule as the parent PR — fix real bugs, baseline
  benign pre-existing).

## Files to Create

- none

## Acceptance Criteria

- [ ] All five issue-listed misses reproduce as RED fixtures, then go green:
  multi-line `fi`/`done`/`esac`/group-`}` reads (S3); `f()\n{`, `name() (`,
  and mid-line `}`/`};` function shapes (S4); `set` inside multi-line quoted
  strings neutralized in BOTH directions (no phantom arm, no phantom clear);
  `x=pre$?` flags; `;` inside quotes no longer splits segments.
- [ ] Verified-negative pins hold: multi-line canonical
  `if cmd; then rc=0; else rc=$?; fi` silent; function-DEFINITION `}` before a
  read silent; `;;` case-arm separators and `{a,b}`/`${x}` brace text do not
  perturb tracking; every pre-existing silent fixture stays silent.
- [ ] `echo 'a;b'; rc=$?` reports `echo 'a;b'` as the antecedent command text
  (m7 — the mis-attribution is corrected, not merely still-firing).
- [ ] `bash scripts/lint-shell-capture-exit.test.sh` → `ALL TESTS PASSED` with
  the raised `MIN_ASSERTIONS` floor (floor value equals the new assertion
  count).
- [ ] `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt` → `[OK]` over the full tree;
  every newly-visible finding was triaged — fixed or baselined, none left
  unaddressed; regenerated baseline committed with all prior keys persisting.
- [ ] Docstring: the five closed HEURISTIC LIMITS entries removed/rewritten;
  surviving residuals ($'…' strings, `name() cmd` bodies, `;;` fragments)
  documented.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal lint tooling change confined
to `scripts/`; no user-facing, infra-provisioning, vendor, regulated-data, or
content surface. Mechanical UI-surface override checked: no Files-to-Edit
path matches the ui-surface glob set.

## Test Scenarios

- Given `set -e`, a multi-line `if c; then … worker … fi`, and `rc=$?` after
  it, when the linter runs, then `:N: [S3]` fires at the read naming the
  compound.
- Given `set -e` and `bash -c '…\nset +e\n…'` followed by `worker` + `rc=$?`,
  when the linter runs, then S3 still fires — the quoted `set +e` is data.
- Given `set -uo pipefail` (no `-e`) and `bash -c '…\nset -e\n…'` followed by
  `x=$(grep p f)`, when the linter runs, then nothing fires — a quoted
  `set -e` cannot arm the model.
- Given `set -e` and `report()\n{\n (( c > 0 )) && echo x\n}`, when the
  linter runs, then `:N: [S4]` fires at the tail.
- Given `set -e` and `report() {` … `(( c > 0 )) && echo x; }`, when the
  linter runs, then S4 fires at the mid-line closer's tail segment.
- Given `set -e` and `worker` then `x=pre$?`, when the linter runs, then S3
  fires.
- Given `set -e` and `echo 'a;b'; rc=$?`, when the linter runs, then the S3
  finding names `echo 'a;b'` — not a `b'` fragment.
- Given a multi-line `if cmd; then rc=0; else rc=$?; fi`, when the linter
  runs, then nothing fires (the gate does not flag its own remediation).
- Integration: `bash scripts/lint-shell-capture-exit.test.sh` prints
  `ALL TESTS PASSED`; `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt` prints `[OK]` and exits 0.

## Success Metrics

- The five issue-listed defect shapes are covered by firing fixtures; zero
  new false-positive fixtures introduced on the protected-idiom set.
- Live gate over ~1275 tracked scripts reports `[OK]` post-regeneration with
  every new key triaged (fixed or baselined with justification in the PR).
- `MIN_ASSERTIONS` floor equals the new assertion total — no silent fixture
  skipping.

## Dependencies & Risks

- **Risk — false positives from the widened coverage on the real tree:**
  mitigated by Phase 5's explicit triage and by the parent PR's measured
  precedent (its widening surfaced true bugs, all dispositioned).
- **Risk — `}` overload ambiguity (function vs group vs `${}`/`{a,b}`):**
  mitigated by the standalone-token rule and the brace-expansion/`${}`
  must-not-fire fixtures; misses residual fail silent, never loud.
- **Risk — quote state interacting with heredocs/continuations:** ordering is
  pinned — comments → heredocs → continuation fold → quote/depth tracking;
  an interleaved fixture (`bash -c '…'` containing a `<<` inside quotes)
  belongs in the must-not-fire set.
- **Risk — baseline growth optics:** the baseline header says it may only
  shrink; a widening legitimately adds newly-detected pre-existing keys.
  Precedent: the parent PR regenerated +50/−39 as a reviewable one-time
  event; this plan requires the same diff-visible justification.
- **Dependency:** none beyond python3 + git, unchanged.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty/placeholder/omits the
  threshold fails `deepen-plan` Phase 4.6 — filled above; no sensitive-path
  match, so no scope-out bullet is required.
- `--write-baseline` must run ONLY after fixtures are green AND the live
  triage dispositions every new finding — regenerating early bakes real bugs
  into the grandfathered set.
- The live run must use the registered `--baseline` invocation (the bare form
  re-reports the entire baseline as new — the #8386 trap recorded in
  `2026-09-20-the-ops-only-green-verdict-…`).
- `lint-guard-contract.py` quantifies over EVERY `### Guard` entry — all
  three above carry Property/Assembly/≥3 matrix rows with a dispatch row and
  a second-member row each.
- `MIN_ASSERTIONS` rises in the SAME edit as the fixtures it counts — a floor
  raised in a later tidy-up is exactly the #8386 slack defect.
- `x=pre$?` widening must not anchor `x='$?'` (literal) — pin the negative.
- The plan-file path for `soleur:work`:
  `knowledge-base/project/plans/2026-09-25-fix-lint-capture-exit-s34-blind-spots-plan.md`.

## References & Research

- Issue: #8884; parent classes: PR #8836 / #8784 / #7332; design anchor:
  `scripts/lint-shell-capture-exit.py` docstring (WHY THIS EXISTS, THE RULE,
  HEURISTIC LIMITS) and `scripts/lint-workflow-errexit-capture.py`
  `scan_body()` (the ported two-pass model).
- Anchor-drift item home: #8791 (`pre-merge` residual), #8790
  (`cla-signed-author-gate` same vector) — explicitly out of scope here.
- Learnings cited in Research Insights; fixture-harness conventions from
  `.test.sh` header + `run_lint` comment; ADR-166 via the gate docstring;
  ADR-127 for why the review-trailer anchor question is not this linter's
  problem.
- Empirical basis: the M1–M12 fixture table in Problem Statement was run
  against the live linter on this branch at plan time.
