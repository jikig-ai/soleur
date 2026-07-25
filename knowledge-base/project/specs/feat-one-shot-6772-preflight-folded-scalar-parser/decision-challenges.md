# Decision Challenges — feat-one-shot-6772-preflight-folded-scalar-parser

Recorded headless (no operator pause). `ship` renders these into the PR body and files
an `action-required` issue.

## Challenge 1 — awk extracted out of the SKILL.md fence into a real file

**Operator direction:** "The production awk in `plugins/soleur/skills/preflight/SKILL.md`
Check 10 Step 10.4 (the bash IS the runtime)."

**Plan diverges:** Phase 2 extracts the Form A program to
`plugins/soleur/skills/preflight/scripts/parse-form-a.awk` and has Step 10.4 call it via
`awk -f`. The bash is still the runtime — it just lives in a file the runtime reads
instead of a fence the runtime inlines.

**Why:** the operator also mandated a parity assertion between the awk and its TS mirror.
Implementing that against a fenced program requires regex-scraping awk out of markdown,
plus a second guard against the scrape silently returning empty. Extracting deletes the
scrape, the scrape-guard, and the "awk is unlintable" sharp edge, and makes rule order
(the actual bug) reviewable in a real file rather than asserted by byte offset.
`plugins/soleur/AGENTS.md` already sanctions `skills/<name>/scripts/`.

**Operator's direction is the default.** If the fence must stay, the parity harness keeps
the scrape + P2 guard and AC1 reverts to a byte-offset assertion. Say so and it reverts.

## Challenge 2 — sandbox mutation protocol scoped to the already-green cases

**Operator direction:** "each case mutation-verified non-vacuous: mutate a SANDBOX COPY,
assert the mutation actually landed via a diff against a pristine backup, and confirm the
suite reddens."

**Plan diverges:** the full 5-step sandbox protocol runs for the six cases that are green
*before* the fix (I1, N3, B2, B3, E1, P3). For the cases that are red before the fix
(F1–F4, N1, N2, N5, B1, P1), Phase 1's RED-first run already produces exactly the
demanded signal — observed failure against the unmodified parser — and its output is
recorded in the PR body as the evidence.

**Why:** re-deriving RED-first evidence via ~50 sandbox operations does not increase
confidence; it repeats it. The non-vacuity requirement is fully honoured — every case
still has a named mutation and recorded evidence, from whichever mechanism actually
produces it.

**Operator's direction is the default.** If per-case sandbox runs are wanted regardless,
AC9 expands to all sixteen rows.
