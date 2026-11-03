#!/usr/bin/env bash
# issues (2 of 2): Guard 3 (idempotency and resume) and Guard 4 (epic edits are confined to the marked section).
# Preview, --check-plan, Guard 1 and Guard 2 are in issues-guards.test.sh; both source issues-common.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/issues-common.sh"

# ---------------------------------------------------------------- 7. Guard 3: idempotency and resume
full_case() { newcase; only_first "$R" "$1"; prev; }
full_case 7; calls_reset
with GH_STUB_FAIL_AFTER=3 -- create; FIRST_OUT="$OUT"
check "G3.1: the 4th item create fails -> created=3 and the failed ids are named" bash -c '[ "$(kv "$1" SOLEUR_LAUNCH_CHECK_ISSUES created)" = 3 ] && [ -n "$(kv "$1" SOLEUR_LAUNCH_CHECK_ISSUES failed)" ] && [ "$(kv "$1" SOLEUR_LAUNCH_CHECK_ISSUES failed)" != "-" ]' _ "$FIRST_OUT"
check "G3.1: ... and the run aborts issues-incomplete (rc 2)" abort_is 2 issues-incomplete "$FIRST_OUT"
check "G3.1: the fake tracker holds 3 items and one epic after the failure (state read from the tracker)" bash -c '[ "$1" = 3 ] && [ "$2" = 1 ]' _ "$(items_n)" "$(epics_n)"
check "G3.1: the abort and the summary carry plan=<dir> and phase=, and the exact resume command" bash -c 'grep -q "plan=" "$1" && grep -q "phase=" "$1" && grep -q -- "--create" "$1" && grep -q -- "--plan" "$1"' _ "$FIRST_OUT"
calls_reset; create
check "G3.1: re-running the same plan completes (rc 0)" test "$RC" = 0
check "G3.1: the tracker holds 7 items and exactly one epic, each id once, all linked" bash -c '[ "$1" = 7 ] && [ "$2" = 1 ] && [ "$3" = 1 ] && [ "$4" = 7 ]' _ "$(items_n)" "$(epics_n)" "$(max_dup)" "$(linked_n)"
check "G3.1: the re-run created only the 4 missing issues (issue POSTs == 4)" test "$(n_post POST 'repos/acme/demo/issues$')" = 4
check "G3.1: created.tsv in the plan directory lists what the runs created and the plan directory survives (mode 700)" bash -c '[ -s "$1/created.tsv" ] && [ "$(ls -ld "$1" | cut -c1-10)" = drwx------ ]' _ "$PLAN"
calls_reset; create; calls_reset; create
check "G3 must-PASS: a re-run of an already complete plan records zero writes (no PATCH for a byte-identical section)" bash -c '[ "$1" = 0 ] && [ "$2" = 7 ]' _ "$(n_writes)" "$(items_n)"
full_case 7; calls_reset
with GH_STUB_TRANSPORT_ERROR_AFTER_CREATE=2 -- create
check "G3.2: a transport error right after a create (unknown outcome) ends the run non-zero with the created issues in the tracker" bash -c '[ "$1" != 0 ] && [ "$2" -ge 2 ]' _ "$RC" "$(items_n)"
before_items=$(items_n); calls_reset; create
check "G3.2: the re-run creates no duplicate and links the orphan: 7 items, 7 links, each marker once, at least 2 items existed before" bash -c '[ "$1" = 7 ] && [ "$2" = 7 ] && [ "$3" = 1 ] && [ "$4" -ge 2 ]' _ "$(items_n)" "$(linked_n)" "$(max_dup)" "$before_items"
check "G3.2: no child was linked by more than one POST in the re-run" bash -c '[ "$1" -le 1 ] && [ "$2" = 7 ]' _ "$(cj '[.[]|select(.method=="POST" and (.path|test("sub_issues$")))|.fields[]|select(.k=="sub_issue_id")|.v]|group_by(.)|map(length)|max // 0')" "$(linked_n)"
full_case 7; CLOSED_ID=$(create_ids | sed -n 1p); ORPH_ID=$(create_ids | sed -n 2p)
stub_reset acme/demo private; seed_label lc:launch-check ededed
seed 301 closed stub-user lc:launch-check "<!-- launch-check:gap=$CLOSED_ID -->"; seed 302 open stub-user lc:launch-check "<!-- launch-check:gap=$ORPH_ID -->"
prev
check "G3.3: the preview reports the closed issue by number" grep -q "#301" "$OUT"
calls_reset; create
orph_db=$(tr_q '[.[]|select(.number==302)|.id]|first'); orph_links=$(cj "[.[]|select(.method==\"POST\" and (.path|test(\"sub_issues\$\")))|.fields[]|select(.k==\"sub_issue_id\" and .v==\"$orph_db\")]|length")
check "G3.3: a closed marked issue is not recreated (one carrier of its marker, still closed)" bash -c '[ "$1" = 1 ] && [ "$2" = closed ]' _ "$(marker_n "$CLOSED_ID")" "$(tr_q '[.[]|select(.number==301)|.state]|first')"
check "G3.4: an open marked issue with no parent is not recreated and is linked exactly once" bash -c '[ "$1" = 1 ] && [ "$2" = 1 ] && [ "$3" = 302 ]' _ "$(marker_n "$ORPH_ID")" "$orph_links" "$(tr_q '[.[]|select(.parent != null and .number==302)|.number]|first')"
full_case 7; stub_reset acme/demo private; seed_label lc:severity-high 123456; prev; calls_reset; create
check "G3.6: a pre-existing lc:severity-high label is untouched: no label write names it and its colour is unchanged" bash -c '[ "$(cj "[.[]|select(.method==\"POST\" and (.path|test(\"/labels\$\")) and (.fields[]|select(.k==\"name\" and .v==\"lc:severity-high\")))]|length")" = 0 ] && [ "$(jq -r "[.[]|select(.name==\"lc:severity-high\")|.color]|first" "$1/labels.json")" = 123456 ]' _ "$ST"
check "G3.6 control: absent labels were created (lc:launch-check and lc:epic exist now)" bash -c 'jq -e "map(.name)|index(\"lc:launch-check\") != null and index(\"lc:epic\") != null" "$1/labels.json" >/dev/null' _ "$ST"
full_case 7; D_ID=$(create_ids | sed -n 1p); A_ID=$(create_ids | sed -n 2p); B_ID=$(create_ids | sed -n 3p)
stub_reset acme/demo private; seed 401 open stub-user lc:launch-check "<!-- launch-check:gap=$D_ID -->"; seed 402 open stub-user lc:launch-check "<!-- launch-check:gap=$D_ID -->"
seed 403 open stub-user lc:launch-check "<!-- launch-check:gap=$A_ID --> <!-- launch-check:gap=$B_ID -->"
prev; calls_reset; create
check "G3.7: duplicates of one id resolve to the lowest number (no create for it) and a two-marker body is ignored: 6 item creates + the epic" test "$(n_post POST 'repos/acme/demo/issues$')" = 7
full_case 3; stub_reset acme/demo private; seed 501 closed stub-user lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"
prev
check "G3.8: preview prints a plain warning for a closed epic" bash -c 'grep -qi "closed" "$1" && grep -qi "epic" "$1"' _ "$OUT"
calls_reset; create
check "G3.8: create writes nothing and says how to recover (reopen it or remove the lc:epic label)" bash -c '[ "$1" = 0 ] && grep -qi "reopen" "$2"' _ "$(n_writes)" "$OUT"
check "G3.8: create aborts epic-closed (rc 2)" abort_is 2 epic-closed
full_case 3; stub_reset acme/demo private; seed 511 open stub-user lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"; seed 512 open stub-user lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"
prev; calls_reset; create
check "G3.8: two labelled epic candidates write nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G3.8: ... and abort epic-ambiguous (rc 2)" abort_is 2 epic-ambiguous
full_case 3; stub_reset acme/demo private; seed 521 open someone-else lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"
prev; calls_reset; create
check "G3.12: an epic authored by another login writes nothing and names epic-author" bash -c '[ "$1" = 0 ] && grep -q "epic-author" "$2"' _ "$(n_writes)" "$OUT"
check "G3.12: ... and aborts plan-invalid (rc 2)" abort_is 2 plan-invalid
for st in 404 422; do
  full_case 4; calls_reset; with GH_STUB_SUBISSUE=$st -- create
  check "G3.9 (UNVERIFIED-STUB-ONLY $st): the first failed link latches the run to the task list: one link call, rc 0, fallback=task-list" bash -c '[ "$1" = 1 ] && [ "$2" = 0 ] && [ "$(kv "$3" SOLEUR_LAUNCH_CHECK_ISSUES fallback)" = task-list ]' _ "$(n_post POST 'sub_issues$')" "$RC" "$OUT"
  epic_body_to "$SCRATCH/epic.fb"
  check "G3.9 ($st): the epic section lists every created item as an unchecked task line" bash -c '[ "$(grep -c "^- \[ \] #[0-9]" "$1")" = 4 ]' _ "$SCRATCH/epic.fb"
done
full_case 3; one=$(create_ids | sed -n 1p); sed "s/^finding $one open\$/finding $one accepted 2026-11-03 accepted after the preview/" "$R/$REPORT_REL" > "$R/r.new" && mv "$R/r.new" "$R/$REPORT_REL"
calls_reset; create
check "G3.10: accepting a finding after the preview makes create write nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G3.10: ... and abort report-stale (rc 2)" abort_is 2 report-stale
full_case 3; jq '.visibility="public"' "$ST/repo.json" > "$ST/r.new" && mv "$ST/r.new" "$ST/repo.json"; calls_reset; create
check "G3: a plan recorded PRIVATE against a LIVE PUBLIC repo writes nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G3: ... and aborts confirm-public-required (rc 2)" abort_is 2 confirm-public-required
create --confirm-public
check "G3: --confirm-public makes the same run proceed" bash -c '[ "$1" = 0 ] && [ "$2" -gt 0 ]' _ "$RC" "$(n_writes)"
full_case 7; jq '.visibility="public"' "$ST/repo.json" > "$ST/r.new" && mv "$ST/r.new" "$ST/repo.json"; calls_reset; with GH_STUB_FAIL_AFTER=3 -- create --confirm-public
check "resume hint (public): the stopped run prints the resume command WITHOUT --confirm-public, and the separate line that names it" bash -c 'c=$(cmd_line "$1"); [ -n "$c" ] && ! grep -q -- "--confirm-public" <<<"$c" && grep -q "append --confirm-public" "$1"' _ "$OUT"
check "resume hint (public): the stopped run is issues-incomplete (anti-vacuous: the hint was printed by a real failure)" abort_is 2 issues-incomplete
full_case 7; calls_reset; with GH_STUB_FAIL_AFTER=3 -- create
check "resume hint (private): the resume command is printed and no --confirm-public line appears" bash -c 'c=$(cmd_line "$1"); [ -n "$c" ] && ! grep -q -- "--confirm-public" "$1"' _ "$OUT"
full_case 3; jq '.visibility="internal"' "$ST/repo.json" > "$ST/r.new" && mv "$ST/r.new" "$ST/repo.json"; calls_reset; create
check "G3: an internal repository is gated like a public one (confirm-public-required)" abort_is 2 confirm-public-required
full_case 3; calls_reset; create
check "G1 must-PASS: a PRIVATE repository runs without --confirm-public" bash -c '[ "$1" = 0 ]' _ "$RC"
full_case 3; calls_reset; with GH_STUB_LIST=fail -- create
check "G3.11: a failed listing writes nothing and says phase=lookup (never read as none found)" bash -c '[ "$1" = 0 ] && grep -q "phase=lookup" "$2"' _ "$(n_writes)" "$OUT"
check "G3.11: ... and aborts issues-incomplete (rc 2)" abort_is 2 issues-incomplete
calls_reset; with GH_STUB_LIST=malformed -- create
check "G3.11 (UNVERIFIED-STUB-ONLY): malformed listing output writes nothing and says phase=lookup" bash -c '[ "$1" = 0 ] && grep -q "phase=lookup" "$2"' _ "$(n_writes)" "$OUT"
stub_reset acme/demo private; seed 601 open stub-user lc:launch-check NULL; seed 602 open stub-user lc:launch-check ''; seed 603 open stub-user lc:launch-check 'no marker here'
calls_reset; create
check "G3.11 (UNVERIFIED-STUB-ONLY, gojq null handling): null, empty and marker-less bodies are ignored cleanly and the run completes" bash -c '[ "$1" = 0 ] && [ "$2" = 3 ]' _ "$RC" "$(tr_q '[.[]|select(.number>=100 and .number<600)|select(.labels|map(.name)|index("lc:epic")|not)]|length')"
full_case 3; ID3=$(create_ids | sed -n 3p); stub_reset acme/demo private
for i in 1 2 3 4 5; do seed $((700 + i)) closed stub-user lc:launch-check "<!-- launch-check:gap=ZZ-0$i -->"; done; seed 706 closed stub-user lc:launch-check "<!-- launch-check:gap=$ID3 -->"
calls_reset; with GH_STUB_PER_PAGE=2 -- create
maxpages=$(awk -F'\t' '{ if ($2 + 0 > m) m = $2 + 0 } END { print m + 0 }' "$ST/pages.log" 2>/dev/null)
check "G3: a listing forced onto at least 3 pages is read completely (the id on the last page is not recreated)" bash -c '[ "$1" -ge 3 ] && [ "$2" = 1 ]' _ "$maxpages" "$(marker_n "$ID3")"
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; calls_reset; with LC_TEST_NOLIVE=1 -- create
check "G3.5 mutation: with the live lookup removed from the re-run, duplicates appear (so the resume rows are sensitive)" bash -c '[ "$1" -ge 2 ] || [ "$2" -gt 7 ]' _ "$(max_dup)" "$(items_n)"
full_case 7; calls_reset; with GH_STUB_FAIL_AFTER=2 GH_STUB_FAIL_KIND=ratelimit -- create
check "G3: a rate-limit failure names the rate limit and the re-run line" bash -c 'grep -qi "rate" "$1" && grep -q -- "--create" "$1"' _ "$OUT"
check "G3: ... and stops the run issues-incomplete (rc 2)" abort_is 2 issues-incomplete
calls_reset; create
check "G3: the re-run after a rate limit completes with 7 items" bash -c '[ "$1" = 0 ] && [ "$2" = 7 ]' _ "$RC" "$(items_n)"
full_case 7; calls_reset; with GH_STUB_FAIL_AFTER=1 GH_STUB_FAIL_KIND=secret -- create
check "G2.12: a secret-shaped string on the stub's stderr never reaches stdout or stderr of the run, nor the raw HTTP line" bash -c '! grep -qF -- "$1" "$2" && ! grep -qF "token=" "$2" && ! grep -q "HTTP 502" "$2"' _ "$(stub_secret)" "$OUT"
check "G2.12: a failed write still yields the closed-token summary line" grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES " "$OUT"
check "G2: every printed line of a failed create passes lc_scrub (no tab or carriage return)" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES " "$1" && ! grep -q "$(printf "\t")" "$1" && ! grep -q "$(printf "\r")" "$1"' _ "$OUT"
full_case 3; TMPD="$SCRATCH/tmpd"; mkdir -p "$TMPD"; with TMPDIR="$TMPD" -- create
check "no lc-work or lc-gate temp file is left behind after a create (only the plan directory survives)" bash -c '[ "$1" = 0 ] && [ -z "$(ls -A "$2")" ]' _ "$RC" "$TMPD"

# ---------------------------------------------------------------- 8. Guard 4: epic edits are confined to the marked section
custom_epic() { # customer text before and after the markers, using the words begin and end without the marker syntax
  tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= ("CUSTOMER-TOP begin and end are just words here\n" + . + "\nCUSTOMER-BOTTOM\n")'
}
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; custom_epic; epic_body_to "$SCRATCH/e.before"; calls_reset; create; epic_body_to "$SCRATCH/e.after"
check "G4.1: customer text before and after the markers is byte-identical after a re-run that rewrote the section" bash -c 'outside "$1" > "$3"; outside "$2" > "$4"; cmp -s "$3" "$4" && grep -q CUSTOMER-TOP "$4" && grep -q CUSTOMER-BOTTOM "$4"' _ "$SCRATCH/e.before" "$SCRATCH/e.after" "$SCRATCH/o1" "$SCRATCH/o2"
check "G4.1 harness row: the re-run really rewrote the section (a PATCH was recorded and the body changed)" bash -c '[ "$1" -ge 1 ] && ! cmp -s "$2" "$3"' _ "$(n_post PATCH 'issues/[0-9]+$')" "$SCRATCH/e.before" "$SCRATCH/e.after"
check "G4 must-PASS: customer text containing the words begin and end (without marker syntax) survives" grep -q "CUSTOMER-TOP begin and end are just words here" "$SCRATCH/e.after"
order=$(cj '[.[]|select(.path|test("issues/[0-9]+$"))|.method]|join(",")')
check "G4: the call order on the epic is GET then PATCH (the body is read just before the splice)" bash -c 'case "$1" in *GET*PATCH*) exit 0 ;; esac; exit 1' _ "$order"
for mode in get write; do
  full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; custom_epic; calls_reset; with GH_STUB_EDIT_EPIC_BETWEEN=$mode -- create; epic_body_to "$SCRATCH/e.mid"
  check "G4.2: a customer edit made mid-run ($mode) survives the splice (the epic body is re-read just before it)" bash -c 'grep -q CUSTOMER-EDIT-MIDRUN "$1" && [ -s "$2/events.log" ]' _ "$SCRATCH/e.mid" "$ST"
done
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= sub("<!-- launch-check:end -->"; "")'
calls_reset; create
check "G4.3: a deleted end marker -> no PATCH is recorded and the summary says epic-section=markers-damaged" bash -c '[ "$1" = 0 ] && [ "$(kv "$2" SOLEUR_LAUNCH_CHECK_ISSUES created)" != "" ] && [ "$(kv "$2" SOLEUR_LAUNCH_CHECK_ISSUES epic-section)" = markers-damaged ]' _ "$(n_post PATCH 'issues/[0-9]+$')" "$OUT"
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= (. + "\n<!-- launch-check:begin -->\n")'
calls_reset; create
check "G4.4: a duplicated begin marker -> no PATCH is recorded (the run itself created the items)" bash -c '[ "$1" = 0 ] && [ "$2" = 7 ]' _ "$(n_post PATCH 'issues/[0-9]+$')" "$(items_n)"
full_case 7; calls_reset; with GH_STUB_FAIL_AFTER=3 GH_STUB_CRLF=1 -- create; custom_epic
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= gsub("\r?\n"; "\r\n")'
epic_body_to "$SCRATCH/c.before"; create; epic_body_to "$SCRATCH/c.after"
check "G4.5: an epic stored with CRLF: the section is rewritten and the CRLF bytes outside it are preserved" bash -c 'outside "$1" > "$3"; outside "$2" > "$4"; cmp -s "$3" "$4" && grep -q "$(printf "\r")" "$4" && ! cmp -s "$1" "$2"' _ "$SCRATCH/c.before" "$SCRATCH/c.after" "$SCRATCH/o3" "$SCRATCH/o4"
full_case 4; with GH_STUB_SUBISSUE=404 -- create
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= sub("- \\[ \\] #"; "- [x] #")'
calls_reset; with GH_STUB_SUBISSUE=404 -- create; epic_body_to "$SCRATCH/t.after"
check "G4.9: a task line the customer ticked stays ticked after a re-run" bash -c '[ "$(grep -c "^- \[x\] #" "$1")" -ge 1 ]' _ "$SCRATCH/t.after"
check "G4: the marked section carries the last run's counts (the record that outlives the terminal)" bash -c 'grep -qiE "created|skipped|failed" < <(awk "/<!-- launch-check:begin -->/{f=1;next} /<!-- launch-check:end -->/{f=0} f" "$1")' _ "$SCRATCH/t.after"
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; custom_epic
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= (. + "\ncustomer pasted '"$(gl_only_secret)"'\n")'
calls_reset; : > "$GL_ON"; with LAUNCH_CHECK_GITLEAKS="$SCRATCH/gl-toggle.sh" -- create; rm -f "$GL_ON"
check "G4 carve-out: customer-owned bytes outside the markers are carried unchanged and not re-judged (rc 0, the text is still in the epic)" bash -c '[ "$1" = 0 ] && grep -qF "customer pasted" < <(jq -r "[.[]|select(.labels|map(.name)|index(\"lc:epic\"))][0].body" "$2")' _ "$RC" "$ST/issues.json"
cat > "$SCRATCH/splice-mut.sh" <<'EOF'
lc_epic_splice() { cat "$2"; }
EOF
SB1=$(mk_sbx splice); inject "$SB1" "$SCRATCH/seams.sh"; inject "$SB1" "$SCRATCH/splice-mut.sh"
check "G4.6 mutation landed (the sandbox differs from the pristine copy and still parses)" bash -c 'bash -n "$1" && ! cmp -s "$1" "$2"' _ "$SB1" "$SB0"
splice_scn() { # splice_scn <lc script>: customer text outside the markers survives a rewrite (return 0 = the property holds)
  LCS="$1"; full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; custom_epic; create; epic_body_to "$SCRATCH/s.after"; grep -q CUSTOMER-BOTTOM "$SCRATCH/s.after"
}
splice_scn "$SB0"; rc=$?
check "G4.6 control: the pristine copy keeps the customer text" test "$rc" = 0
splice_scn "$SB1"; rc=$?
check "G4.6 mutation: a splice that replaces the whole body loses the customer text (caught)" test "$rc" != 0
LCS="$SB0"

# ---------------------------------------------------------------- 9. the exit-code table: every fail_loud reason this half owns was exercised by a row above
check "every fail_loud abort reason owned by this half (resume and epic) was exercised by a marker-and-exit-code row" bash -c 'miss=""; for r in confirm-public-required epic-closed epic-ambiguous issues-incomplete; do case " $1 " in *" $r "*) ;; *) miss="$miss $r" ;; esac; done; [ -z "$miss" ]' _ "$SEEN_REASONS"
finish 65
