---
title: Derive guard needles from the call form with a bounded arg, and a conjunct-only predicate cannot deliver a detail-absent fail-loud — it needs the explicit empty disjunct
date: 2026-10-29
category: security-issues
module: inngest-health / Better Stack alert SQL + drift guards
tags: [betterstack, drift-guard, derived-needle, call-form-anchor, fail-loud, phone-home, inngest]
issue: 11526
pr: 11559
---

# Learning: call-form-anchored needles + the empty-disjunct fail-loud

## Problem

Issue #11526: the `inngest_luks_wrong_volume` alert's journald-anchored predicate read zero
rows during a Vector outage — the wrong-volume evidence then arrives only on the
`inngest-boot-phone-home.sh inngest-server-probe-vector-down "<fields>"` fallback channel
(envelope fields `shipper`/`stage`/`detail`, never `marker`). Two construction defects surfaced
in the fix-round review of the remedy:

1. The first needle derivations were **bare-substring greps** — a comment line carrying the
   literal satisfied the extraction, and a rename to a superstring (`-vector-down-v2`) silently
   re-pinned the guard to the NEW literal while the .tf needle still matched, leaving the drift
   property unproven.
2. The prescribed leg-B conjuncts **could not deliver the ruled fail-loud** for detail-absent
   rows: `position(detail,'host_role=dedicated ') > 0` evaluates `position('') = 0` first and
   rejects the row before the negated devid can count it — the schema-drop class went quiet
   (measured E3=0 under the conjunct-only form, 1 with the disjunct).

## Solution

1. **Anchor the extraction on the CALL FORM, bound the arg.** `MUT_STAGE` comes from
   `sed -n 's/^[^#]*inngest-boot-phone-home\.sh[[:space:]]\+\(inngest-server-probe-[A-Za-z0-9_-]*\).*/\1/p'`
   — `^[^#]*` kills commented copies, the helper name + whitespace anchors the invocation, and
   the `inngest-server-probe-[A-Za-z0-9_-]*` class yields the arg BOUNDED, so a `-v2` rename
   extracts the NEW literal and reddens the .tf needle instead of re-pinning a stale one.
   `MUT_SHIPPER` derives the same way from the payload builder (`shipper:"…"` in
   `cloud-init-inngest.yml`). Both empty-extract to a `[FATAL] exit 2` — derivation failure is
   loud, never a vacuous needle.
2. **Pin the RESERVED-token cardinality.** `stage` is a positional `$1` on a shared helper with
   ~16 call sites: `grep -cE '^[^#]*inngest-boot-phone-home\.sh[[:space:]]+inngest-server-probe-vector-down([[:space:]"]|$)'`
   must equal exactly 1 — a second emit site passing the same stage is a leg-B identity
   collision the predicate cannot see.
3. **The fail-loud needs an explicit empty disjunct.** Leg B ships
   `detail = '' OR (host_role-scope AND negated-devid)` — the bare `detail=''` arm counts the
   field-absent row before the scoped conjuncts can reject it. Same philosophy as leg A's
   negated devid: absent evidence pages, never reads healthy. The jq-failure envelope (no
   `shipper` at all) stays uncounted — recorded boundary, CTO T1.
4. Mutation battery grew to 22 rows (shipper-drop, shipper-foreign-flip, stage-drop,
   host_role-scope-drop, whole-arm delete, detail-disjunct neutralize); floors 44/22 with the
   `MUT_SKIP` floor pinned to the presence count.

## Key Insight

A needle derived by bare-substring grep is satisfiable by the file's own prose about the
literal — the anchor must be the mechanism (call form, key-value shape), and the capture must
be bounded so a superstring rename surfaces as a NEW needle rather than a stale match. And a
fail-loud property over "field absent" is unexpressible in pure conjuncts — every conjunct
that reads the field rejects its absence; only an explicit `field = ''` disjunct admits the
absence into the counted set.

## Session Errors

- **`git commit` denied twice by the harness `block-commit-on-main` false positive**
  (worktree-blind `.cwd` resolution; forwarded from session-state.md). Recovery: `git -C
  <worktree-abs-path> commit` — the path-pinned form resolves correctly. Prevention: already
  documented in workflow-patterns
  (`2026-10-25-git-c-with-variable-path-is-denied-like-a-bare-commit.md`); pipeline prompts now
  carry the `git -C` caveat verbatim.
- **No mid-tail errors.** The fix-round ran sequential-fallback (no spawn capability at this
  level); every mapped seat's checklist was applied inline and disclosed as
  `Reviewed-Coverage: sequential-fallback`.

## Prevention

- For any literal a guard derives: name the file, the syntactic ANCHOR (call form / key shape,
  never a bare literal), the BOUNDED capture class, and the loud-empty behaviour — then write a
  mutation row per arm of that contract.
- For any "absent field must page" property: measure the conjunct-only form on a synthetic
  field-absent row BEFORE shipping; if it returns 0, the disjunct is load-bearing, not
  optional.

## Tags
category: security-issues
module: inngest-health / Better Stack alert SQL + drift guards
