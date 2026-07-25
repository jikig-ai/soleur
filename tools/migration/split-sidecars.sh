#!/usr/bin/env bash
# split-sidecars.sh — one-shot migration script.
# Reads AGENTS.md + tools/migration/rule-classification.tsv,
# writes AGENTS.core.md, AGENTS.docs.md, AGENTS.rest.md, AGENTS.md (rewritten as pointer index).
#
# Idempotent: re-running produces identical output (no random state).
# Phase 2 of plan 2026-05-09-feat-agents-md-change-class-loader-plan.md.
set -euo pipefail

TSV="tools/migration/rule-classification.tsv"
SOURCE_BLOB=".AGENTS.md.source"   # Idempotent input: never read the rewritten AGENTS.md.
# Source ref defaults to HEAD; pass `origin/main` (or any committish) as $1 to
# rebuild sidecars against a different branch's full registry — useful when
# rebasing this PR onto upstream rule additions.
SOURCE_REF="${1:-HEAD}"
[[ -f "$TSV" ]] || { echo "missing $TSV — run classify-rules.sh first" >&2; exit 2; }

# Source-of-truth: the version of AGENTS.md at $SOURCE_REF with compliance-tier tags applied.
# Idempotency: even if AGENTS.md has been rewritten to pointer-index form, this script
# reads from $SOURCE_REF via `git show` and re-applies tags.
if ! git show "${SOURCE_REF}:AGENTS.md" > "$SOURCE_BLOB" 2>/dev/null; then
  echo "FATAL: cannot read AGENTS.md from ${SOURCE_REF} via git show" >&2
  exit 2
fi

# Idempotency guard: refuse to operate on an already-migrated source. If the
# source AGENTS.md has been rewritten to pointer-index form (slug-only lines
# without prose rule bodies), the classifier can't build the sidecars from
# it. Detect by checking for the absence of any rule body containing a `**Why:**`
# marker plus an excess of pointer lines (`→ core`/`→ docs-only`/`→ rest`).
if ! grep -q '\*\*Why:\*\*' "$SOURCE_BLOB" && grep -qE ' → (core|docs-only|rest)$' "$SOURCE_BLOB"; then
  echo "FATAL: ${SOURCE_REF}:AGENTS.md is already in pointer-index form (no rule bodies)." >&2
  echo "       Pass an earlier source ref (e.g., \`bash $0 origin/main\`) to rebuild" >&2
  echo "       sidecars from the full registry." >&2
  rm -f "$SOURCE_BLOB"
  exit 2
fi

# Apply the 5 compliance-tier tags (Phase 1.3 of the plan) to the source blob.
python3 - <<'PYTAG'
from pathlib import Path
src = Path(".AGENTS.md.source")
content = src.read_text()
for rid in [
    "hr-never-paste-secrets-via-bang-prefix",
    "hr-menu-option-ack-not-prod-write-auth",
    "hr-never-git-add-a-in-user-repo-agents",
    "cq-pg-security-definer-search-path-pin-pg-temp",
    "hr-exhaust-all-automated-options-before",
]:
    needle = f"[id: {rid}]"
    if needle not in content:
        raise SystemExit(f"FATAL: rule {rid} not found in HEAD's AGENTS.md")
    if f"{needle} [compliance-tier]" in content:
        continue   # already tagged (idempotent)
    content = content.replace(needle, f"{needle} [compliance-tier]", 1)
src.write_text(content)
PYTAG

# Build associative maps: id → class, id → section.
declare -A RULE_CLASS RULE_SECTION
while IFS=$'\t' read -r rid section klass _; do
  [[ "$rid" == "rule_id" ]] && continue   # header row
  RULE_CLASS["$rid"]="$klass"
  RULE_SECTION["$rid"]="$section"
done < "$TSV"

# Override: the lone CQ rule with [compliance-tier] tag moves to "Compliance Tier" section in core.
RULE_SECTION["cq-pg-security-definer-search-path-pin-pg-temp"]="Compliance Tier"

# Generate sidecars + index by streaming AGENTS.md once.
# State machine: track current section, route each rule line to the right sidecar buffer.

python3 - <<'PYEOF'
import re
import os
from pathlib import Path

REG = Path(".AGENTS.md.source")
TSV = Path("tools/migration/rule-classification.tsv")

ID_RE = re.compile(r"\[id: ([a-z0-9-]+)\]")

# Load classifications
rule_class = {}
rule_section_override = {
    "cq-pg-security-definer-search-path-pin-pg-temp": "Compliance Tier"
}
# Force-core overrides for rules the [compliance-tier] tag applies to, regardless of
# what the upstream TSV says. The TSV is generated from the untagged source registry
# (origin/main, pre-Phase-1.3), so cq-pg-security-definer would fall into the default
# Code Quality → rest bucket without this override. Mirrors the 5-rule list inlined in
# the PYTAG block above.
COMPLIANCE_TIER_FORCE_CORE = {
    "hr-never-paste-secrets-via-bang-prefix",
    "hr-menu-option-ack-not-prod-write-auth",
    "hr-never-git-add-a-in-user-repo-agents",
    "cq-pg-security-definer-search-path-pin-pg-temp",
    "hr-exhaust-all-automated-options-before",
}
# Demote-to-rest overrides per plan Phase 1.7.4 ("if core > 18k, default first cut").
# CPO sign-off condition #3 allows ONLY wg-* demotion — never hr-*.
# These two rules are code/test session-specific; no value in injecting them into
# docs-only sessions.
DEMOTE_TO_REST = {
    "wg-when-a-test-runner-crashes-segfault-oom",
    "wg-when-tests-fail-and-are-confirmed-pre",
}
with TSV.open() as f:
    next(f)  # header
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4:
            continue
        rid, section, klass = parts[0], parts[1], parts[2]
        if rid in COMPLIANCE_TIER_FORCE_CORE:
            klass = "core"
        elif rid in DEMOTE_TO_REST:
            klass = "rest"
        rule_class[rid] = klass

# Bucketize rules: { sidecar_path : { section_name : [rule_line, ...] } }
buckets = {
    "AGENTS.core.md": {},
    "AGENTS.docs.md": {},
    "AGENTS.rest.md": {},
}
# Maintain insertion order of sections within each sidecar
core_section_order = ["Hard Rules", "Workflow Gates", "Compliance Tier",
                      "Passive Domain Routing", "Communication"]
docs_section_order = ["Code Quality"]
# Workflow Gates included so demoted wg-* test/runner rules land in rest
# (per plan Phase 1.7.4 default cut; preserves the section heading).
rest_section_order = ["Workflow Gates", "Code Quality", "Review & Feedback"]

content = REG.read_text()
lines = content.splitlines()

# Pre-pass: capture the top preamble (everything before first `## ` heading).
preamble_end = 0
for i, line in enumerate(lines):
    if line.startswith("## "):
        preamble_end = i
        break
preamble = "\n".join(lines[:preamble_end])

# Walk lines, route bullets.
current_section = None
for line in lines[preamble_end:]:
    m = re.match(r"^## (.+?)\s*$", line)
    if m:
        current_section = m.group(1).strip()
        continue
    if not line.startswith("- "):
        continue
    id_match = ID_RE.search(line)
    if not id_match:
        continue
    rid = id_match.group(1)
    klass = rule_class.get(rid)
    if klass is None:
        raise SystemExit(f"unclassified rule: {rid}")
    target_section = rule_section_override.get(rid, current_section)
    sidecar = f"AGENTS.{klass.replace('docs-only', 'docs').replace('rest', 'rest')}.md" if klass != "core" else "AGENTS.core.md"
    buckets[sidecar].setdefault(target_section, []).append(line)

# Write sidecars.
def write_sidecar(path, section_order, header_text):
    out = [header_text, ""]
    sections_in_file = buckets[path]
    for sec in section_order:
        if sec not in sections_in_file:
            continue
        out.append(f"## {sec}")
        out.append("")
        out.extend(sections_in_file[sec])
        out.append("")
    Path(path).write_text("\n".join(out).rstrip() + "\n")

CORE_HEADER = """# AGENTS Core — always-loaded sidecar (every session, via .claude/hooks/session-rules-loader.sh)"""

DOCS_HEADER = """# AGENTS Docs-class — loaded for docs-only sessions (markdown / Eleventy / AGENTS-md meta)"""

REST_HEADER = """# AGENTS Rest-class — loaded for code or infra sessions (TS/React/Postgres runtime + Review & Feedback)"""

write_sidecar("AGENTS.core.md", core_section_order, CORE_HEADER)
write_sidecar("AGENTS.docs.md", docs_section_order, DOCS_HEADER)
write_sidecar("AGENTS.rest.md", rest_section_order, REST_HEADER)

# Rewrite AGENTS.md as a thin pointer index.
# Per plan: `- <one-sentence summary> [id: <slug>] [<enforcement-tags>] → AGENTS.<class>.md`
# Pointer ≤ 200 bytes. Extract first sentence of each rule body, preserve enforcement tags.

def extract_pointer(line, klass):
    """Convert a full rule line to a minimal pointer line.

    Format: `- [id: <slug>] [<enforcement-tag>...] → <class-token>`
    The slug itself acts as the human-readable summary (e.g.,
    `hr-never-git-stash-in-worktrees` is self-describing). The full
    rule body lives in the corresponding sidecar.
    """
    body = line[2:].lstrip()
    id_match = ID_RE.search(body)
    if not id_match:
        return None
    id_token = id_match.group(0)

    # Slug-only pointer — enforcement tags + prose live in the sidecar body.
    # Canonical class tokens (single source of truth): core | docs-only | rest.
    # Must match `POINTER_LINE_RE` alternation in scripts/lint-rule-ids.py AND
    # `CLASSES=` vocabulary in .claude/hooks/session-rules-loader.sh.
    return f"- {id_token} → {klass}"

# Re-walk AGENTS.md to produce pointer index in the same section order as the original
section_pointers = {}     # section_name → [pointer_line, ...]
section_order_seen = []    # preserve order of section appearance
current_section = None
for line in lines[preamble_end:]:
    m = re.match(r"^## (.+?)\s*$", line)
    if m:
        current_section = m.group(1).strip()
        if current_section not in section_pointers:
            section_pointers[current_section] = []
            section_order_seen.append(current_section)
        continue
    if not line.startswith("- "):
        continue
    id_match = ID_RE.search(line)
    if not id_match:
        continue
    rid = id_match.group(1)
    klass = rule_class.get(rid)
    if klass is None:
        continue
    # The pointer for cq-pg-security-definer (a "Compliance Tier" rule in core)
    # appears under the index's Code Quality section, so the reader-friendly
    # index keeps the prefix-section convention intact.
    section_pointers[current_section].append(extract_pointer(line, klass))

INDEX_HEADER = """# Agent Instructions — Index

Pointer index. Bodies live in `AGENTS.{core,docs,rest}.md`; SessionStart hook injects the matching sidecar. Multi-class/empty diff → all sidecars (fail-closed). Spec: `knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md`."""

index_out = [INDEX_HEADER, ""]
for sec in section_order_seen:
    pointers = section_pointers.get(sec, [])
    if not pointers:
        continue
    index_out.append(f"## {sec}")
    index_out.append("")
    index_out.extend(pointers)
    index_out.append("")

Path("AGENTS.md").write_text("\n".join(index_out).rstrip() + "\n")

# Sanity output.
# HISTORICAL: the "target" below is the #3493 migration's point-in-time goal,
# not a current threshold. This one-shot tool has already run and gates nothing.
# The live authority is scripts/lint-agents-rule-budget.py, enforced across
# consumers by scripts/lint-agents-compound-sync.sh -- do NOT "sync" this number
# to it, and do not read it as drift (#6461).
core_bytes = Path("AGENTS.core.md").stat().st_size
docs_bytes = Path("AGENTS.docs.md").stat().st_size
rest_bytes = Path("AGENTS.rest.md").stat().st_size
index_bytes = Path("AGENTS.md").stat().st_size
print(f"AGENTS.md (index):  {index_bytes:>6} bytes")
print(f"AGENTS.core.md:     {core_bytes:>6} bytes  (target ≤ 18000)")
print(f"AGENTS.docs.md:     {docs_bytes:>6} bytes")
print(f"AGENTS.rest.md:     {rest_bytes:>6} bytes")
print(f"always-loaded:      {index_bytes + core_bytes:>6} bytes")
print(f"original 24618 →    {index_bytes + core_bytes + docs_bytes + rest_bytes:>6} total")

# Pointer ≤ 200 bytes assertion
oversized = []
for line in Path("AGENTS.md").read_text().splitlines():
    if line.startswith("- ") and len(line.encode("utf-8")) > 200:
        oversized.append((len(line.encode("utf-8")), line[:80]))
if oversized:
    print(f"\nFAIL: {len(oversized)} pointer(s) > 200 bytes:")
    for size, preview in oversized:
        print(f"  {size}B: {preview}...")
    raise SystemExit(1)
print("\nAll pointers ≤ 200 bytes ✓")
PYEOF
