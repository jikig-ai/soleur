# Learning: a shell guard's vacuity predicate is a FIRST-ELEMENT property, and a fix commit re-opens the exact class it was written to close

## Problem

PR #12064 (epic #10390 batch) shipped `scripts/lint-gh-dedupe-shape.py`, a
ratchet classifying `IDENT=$(gh issue|pr list|search)` captures as
handled/marked/unclassified. The first fix-round's `_VACUOUS_ARM` regex
end-anchored the vacuous arm to end-of-logical-line:

```python
r"\s*(?:true|:|[A-Za-z_][A-Za-z0-9_]*=(?:\"\"|''))\s*[;|&]?\s*(?:#.*)?$"
```

Every review seat empirically re-opened the silent-collapse class through
one token: `|| true; echo x`, `|| true >/dev/null`, `|| : "note"`,
`|| X="" y=1`, `||` at end-of-line (empty arm → handled). Three other
fixes-in-the-fix the same round found:

- The `||`-adjacency repair (tail must *begin* with `||`) was too strict
  in the other direction: `V=$(gh…) 2>&1 || {…}` (redirect word between
  `)` and `||`), `( V=$(gh…) ) || rc=$?` (wrapping `)` close), and
  `\"` inside a quoted tail all became unclassified — over-strict is the
  *loud* direction, but it misreads genuinely-bound real shapes.
- `CONDITION_RE` requiring keyword-then-`IDENT=` fired on POSIX-exempt
  condition lists: `if a; V=$(gh…); then` and `if a && V=$(…)` — `;`/`&&`
  do not end a condition; only `then`/`do` does. Fixing it then left a
  new silent hole: `if X=$(gh…) || true; then` (always-then) — a vacuous
  `||` inside a condition still collapses silently, so the condition limb
  must not rescue a vacuous arm (tri-state: bound/vacuous/none).
- A secrets-free `release-publish` environment comment claimed "cannot
  weaken" then "narrows the reachable set to anyone who can land bytes on
  main" — the second clause silently re-imported the overclaim the
  paragraph itself disproved (a secrets-free env has no credential lever
  forcing the `environment:` binding, so the honest unsigned-surface
  residual is "bytes on ANY dispatchable ref", and stale pre-merge refs
  need no byte-landing at all).

## Mechanism

1. **Vacuity is a first-element property.** Judge the `||` arm's FIRST
   command word only (`true`/`:`/`IDENT=`/`""`/`''` with any trailer),
   never end-of-line — the arm ends at `;`/`|`/`&`/`&&`/newline and a
   trailing second command cannot rescue a vacuous first element.
   `|| rc=$?` stays a disposition because it *stores* the rc; `|| VAR=""`
   discards it. Empty arm = unmodelable = unclassified (loud).
2. **Adjacency ≠ first-token-only.** A `||` binds the capture's rc when
   it is the first *command operator* after `)` — same-command redirect
   words (`2>&1`, `>file`) and wrapping `)` closes sit *inside* that span
   legitimately. Skip them; reject on `;`, `&&`, `&`, lone `|`.
3. **Fix commits are the least-audited surface — every round proved it.**
   Two consecutive fix rounds each introduced a new silent-pass while
   closing the last one; both were caught only because the seats
   re-probed the *fixed* predicate with fixtures, not because the suite
   red-flagged it. Mutation-fixture pairs (G11–G22) are what make a new
   predicate's discriminating lines provable.
4. **Honest-bound wording: policy vs binding.** A `deployment_branch_policy`
   is evaluated server-side; the `environment:` *binding* it checks lives
   in the dispatched ref's own bytes. A secrets-free environment is a
   mistake-gate (unmodified dispatches) not an adversary-gate — claim
   exactly that and name the covering control (cosign identity regexp
   for signed artifacts; the unsigned tag/release/GHCR surface is the
   residual). "Narrows to anyone who can land bytes on main" is only
   true when a secret forces the binding (`infra-privileged`).
5. **Two-dot review ranges render main-side work as reversals.** On a
   branch ~7h stale, `origin/main..SHA` showed ~86 of 137 files as
   main's own commits read backwards — a security seat nearly owned a
   `redact-gate.sh` regression that belonged to main. Review diffs are
   `merge-base..SHA`.
6. **Scripted union merges leave commit-subject fragments.** The rebase
   resolver's union matched `>>>>>>> <sha>` mid-line and appended the
   commit subject to 10 `Last Updated:` lines — caught by the
   mirror-drift gate, not by eyeballing. After any scripted merge,
   grep the resolved file for the marker fragments before continuing.

## Action taken

- `_or_status` tri-state + `_vacuous_first` + redirect/`)`-skip +
  quote-escape handling landed in fix-round-3 (`774412182c`) with
  fixtures G17–G22 pinning each closed hole.
- `MARKER_RE` tightened to typed vocabulary + reason required +
  `finditer` real-comment check; `collect()` advisory `--quiet`-gated.
- `REVIEWER_LESS_RATCHET` pins *absence of any `reviewers` block* (not
  just empty `users`); secrets-free pin matches `release[-_]publish`
  both spellings; H6 advisory ceiling is fail-closed on parse miss.
- The tf/ADR/workflow comments now state the binding-voluntary residual
  verbatim (ADR-241 residual 3).

## References

- PR #12064; plan `knowledge-base/project/plans/2026-11-04-chore-ci-infra-hygiene-batch-plan.md`
- Findings: pattern-recognition P1 (adjacency/vacuity), code-quality P2
  (`;` boundary), security-sentinel P2 (honest bound), architecture P2
  (negative parity pins), all in the #10390 batch review round.
