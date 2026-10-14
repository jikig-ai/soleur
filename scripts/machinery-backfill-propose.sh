#!/usr/bin/env bash
# machinery-backfill-propose.sh — propose, never apply.
#
# Emits a reviewable PROPOSAL for which open issues belong on the machinery
# ledger. It NEVER labels and it NEVER closes. Labelling is a separate,
# explicit step driven from the committed proposal artifact, so the
# classification is auditable after the fact rather than inferred from a bulk
# mutation nobody can reconstruct.
#
# THE EVIDENCE RULE, AND WHY IT IS TITLE-SCOPED. An issue is proposed as
# machinery when BOTH hold OF ITS TITLE:
#   (a) the title names a machinery noun -- guard, gate, ledger, probe,
#       assertion, sweep, rehearsal, fixture, mutation, harness, linter; AND
#   (b) the title names NO user-visible surface, drawn from the SAME closed
#       taxonomy the filing gate uses
#       (.claude/hooks/lib/user-surface-taxonomy.txt).
#
# The plan specified "title or body" for both. MEASURED against 200 open issues
# on 2026-09-10, that is unusable and the two failure directions are opposite:
#
#   scope=body   machinery=121  names-a-surface=191  admits=6
#   scope=title  machinery=42   names-a-surface=22   admits=39
#   hybrid (machinery in body, surface in title)     admits=103
#
# Body scope is VACUOUS as a negative: 191 of 200 bodies (96%) mention some
# surface token incidentally -- a long technical body almost always contains
# "command", "report", "document" or "page" somewhere -- so condition (b) is
# effectively always true and the rule admits 3%.
#
# The hybrid over-admits in the direction that actually hurts. Sampled, it
# proposed a dead Supabase management token (HTTP 401 across four Doppler
# configs -- the variable name is deliberately not spelled here, because
# lint-supabase-deprecated-endpoints reads it as evidence that this script
# calls the Management API and demands a host pin, which it should not carry:
# this script talks only to the GitHub issues API), a
# docker login failing on every deploy, and image signature verification that
# had never once succeeded. Those are live operational incidents, and labelling
# them machinery would hide them from the operator digest -- the same class of
# harm as auto-closing a legitimate issue, one step earlier in the pipeline.
#
# The reason no body-scoped rule can work is worth stating plainly: Soleur's
# real infrastructure IS guards, gates and probes, so a genuine outage and a
# finding-about-a-guard share a vocabulary. Only the TITLE reliably states
# which one an issue is about, because a title is a deliberate summary and a
# body is not. This rule is therefore HIGH-PRECISION and LOW-RECALL by
# construction: it will miss machinery findings whose titles are vague, and
# that is the correct direction to be wrong in. Recall is recovered over time
# by the filing gate labelling new findings at source, not by widening this.
#
# Precision is not asserted to be perfect either, which is why this emits a
# PROPOSAL. In the same 200-issue sample it admitted at least two arguable
# calls (a release announcement not gated on deploy success; a tenant-integration
# suite red on main). Those are for a human to strike, which is the entire
# reason the artifact is committed and reviewed rather than applied.
#
# Sharing (b) with guardrails:require-filing-justification is deliberate: the
# gate decides "may this be filed as user-facing?" and this script decides "was
# this user-facing?", and those two must not answer from two drifting lists.
#
# WHY NOT A BULK RELABEL OF domain/engineering. 626 of a 1,000-issue sample
# carry domain/engineering, but that label means "the CTO owns it", not "no user
# receives it". Relabelling on it would sweep real user-facing engineering work
# onto a ledger excluded from the operator digest -- the precise failure the
# standing DO-NOT forbids.
set -euo pipefail

REPO="${REPO:-jikig-ai/soleur}"
LIMIT="${LIMIT:-200}"
OUT="${OUT:-}"

# Read-only by construction: this script carries no issue-mutating verb at all.
# The assertion that proves it greps for those verbs, so this comment must not
# spell them -- a body-grep sees comments too, and a "must not contain X" check
# that trips on the sentence documenting X is a guard that can only false-fail.
MACHINERY_RE='guard|gate|ledger|probe|assert|sweep|rehearsal|fixture|mutation|harness|linter|lint|vacuous|drift-guard|test-all|CI gate'

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TAXO="$HERE/../.claude/hooks/lib/user-surface-taxonomy.txt"
if [[ ! -r "$TAXO" ]]; then
  echo "FATAL: shared user-surface taxonomy unreadable at $TAXO" >&2
  echo "Refusing to classify: without it, EVERY issue reads as naming no user" >&2
  echo "surface, and the proposal would sweep the entire backlog." >&2
  exit 2
fi
SURFACE_RE="$(grep -vE '^[[:space:]]*(#|$)' "$TAXO" | paste -sd'|' - || true)"
if [[ -z "$SURFACE_RE" ]]; then
  echo "FATAL: taxonomy at $TAXO parsed to an EMPTY pattern." >&2
  echo "An empty negative-evidence pattern matches nothing, so condition (b)" >&2
  echo "would hold for every issue. Refusing rather than proposing the backlog." >&2
  exit 2
fi

command -v gh >/dev/null 2>&1 || { echo "FATAL: gh not on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq not on PATH" >&2; exit 2; }

ISSUES="$(gh issue list -R "$REPO" --state open --limit "$LIMIT" \
  --json number,title,body,labels)"

TOTAL="$(jq 'length' <<<"$ISSUES")"
if [[ "$TOTAL" -eq 0 ]]; then
  echo "FATAL: query returned zero open issues. A zero-candidate run against a" >&2
  echo "1,400-issue backlog is a defect, not a clean result." >&2
  exit 2
fi

emit() {
  printf '# Machinery-ledger backfill proposal\n\n'
  printf 'Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'Repo: %s  |  Scanned: %s open issues (limit %s)\n\n' "$REPO" "$TOTAL" "$LIMIT"
  printf 'PROPOSAL ONLY. Nothing here has been labelled and nothing has been closed.\n'
  printf 'Each row records the evidence that produced it so the call can be checked\n'
  printf 'rather than trusted.\n\n'
  printf '| # | title | machinery evidence | surface evidence (blocks) |\n'
  printf '|---|---|---|---|\n'

  jq -r --arg mre "$MACHINERY_RE" --arg sre "$SURFACE_RE" '
    .[]
    | select([.labels[].name] | index("meta/machinery") | not)
    | . as $i
    | ($i.title // "") as $hay
    | ($hay | test($mre; "i")) as $ismach
    | ($hay | test($sre; "i")) as $issurf
    | select($ismach and ($issurf | not))
    | [ ($i.number|tostring),
        ($i.title // "" | gsub("\\|"; "\\\\|") | .[0:90]),
        ($hay | capture("(?<m>" + $mre + ")"; "i").m),
        "none"
      ] | "| " + join(" | ") + " |"
  ' <<<"$ISSUES"
}

if [[ -n "$OUT" ]]; then
  emit > "$OUT"
  n="$(grep -cE '^\| [0-9]+ \|' "$OUT" || true)"
  echo "SOLEUR_MACHINERY_BACKFILL scanned=$TOTAL proposed=$n out=$OUT"
else
  emit
fi
