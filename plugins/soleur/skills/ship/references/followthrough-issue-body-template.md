# Follow-Through Issue Body Template

Loaded by `ship` Phase 7 Step 3.5 — the fenced block below IS the issue
body: write it verbatim (with `<...>` substitutions applied) to the temp
file that step mints. The `<!-- soleur:followthrough` directive must start
at column 0 in the rendered ISSUE BODY (the sweeper skips fenced blocks).

````text
   ## Follow-Through Item

   <ITEM_DESCRIPTION>

   <!-- When this item is about a migration, include either of:
   **Migration file:** `NNN_full_stem.sql`
   See "Migration filename anchor" rule above. -->

   **Source PR:** #<PR_NUMBER>
   **Created by:** soleur:ship Phase 7 Step 3.5
   **Created:** <YYYY-MM-DD>

   ## Verification

   <!-- soleur:followthrough
     script=scripts/followthroughs/<feature-name>-<ISSUE_NUM>.sh
     earliest=<ISO-8601-UTC>
     secrets=<comma-separated-secret-names-or-omit>
   -->

   **UNFENCED, COLUMN 0 — this is load-bearing, not formatting.** The sweeper deliberately
   SKIPS fenced blocks (#4200 Gap 3: a fenced directive is an example, not an enrolment) and
   anchors the opener at column 0. This template previously wrapped the directive in a
   ```` ```html ```` fence, and every tracker created from it was enrolled in name only —
   six of 56 open trackers were dead that way, the oldest silent since 2026-06, each with its
   directive plainly visible in the issue body. The indentation above is this document's list
   nesting; the `<!--` must start at column 0 in the ISSUE BODY. Two mechanical backstops now
   agree with the sweeper: `.claude/hooks/follow-through-directive-gate.sh` denies a fenced
   `gh issue create` and names the fence as the cause, and the sweeper comments on any open
   tracker it finds in this state and reds the run.

   Canonical convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
   The directive is parsed daily by `.github/workflows/scheduled-followthrough-sweeper.yml`
   via [scripts/sweep-followthroughs.sh](../../../../scripts/sweep-followthroughs.sh) — exit 0 PASS / exit 1 FAIL / other TRANSIENT.

   ## Status

   Awaiting verification. The follow-through sweeper will check this issue once `earliest` is reached.
   ````````
