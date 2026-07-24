#!/usr/bin/env python3
"""Layer A encryption-posture detector (ADR-140).

Loads `scripts/encryption-posture-ledger.json` (schema:
`scripts/encryption-posture-ledger.schema.json`) and mechanically resolves every
claim it makes against real code. This is a SECURITY GATE, not a documentation
lint: the headline failure mode it exists to catch is a ledger row asserting
`mechanism: luks` for a volume that is actually plaintext, citing a SIBLING
volume's LUKS apparatus by name-similarity (the `#6588` class — `hcloud_volume.
workspaces` sits beside `hcloud_volume.workspaces_luks`, and any name/mount-path
join lets the plaintext row cite the encrypted sibling's evidence and PASS).
See ADR-140 and `knowledge-base/project/plans/
2026-07-23-feat-encryption-posture-design-time-default-plan.md` (Plan Review
Revisions R1-R11) for the full design rationale.

Modes
-----
--repo-sweep (default)  Load + schema-validate the ledger, run every check below.
                        Exit 0 = PASS, non-zero = FAIL. One `FAIL: <what> -> <fix>`
                        line per violation (stderr) + a summary line (stdout).
--report                Same as --repo-sweep, plus always prints a parity table
                        (*.tf resource-type inventory vs. ledgered rows).
--check-templates       Validates the (not-yet-landed) `## Encryption Posture`
                        blocks in plan-issue-templates.md against this schema's
                        field set. SKIPs gracefully (exit 0) until Phase 5 lands
                        the heading.
--json                  Emits the schema-validated ledger as JSON to stdout (the
                        single-parser contract Layer B shells out to).

Checks implemented (each independently mutation-testable; see
lint-encryption-posture.test.sh's `--mutation`-style battery MB-1..MB-12)
------------------------------------------------------------------------
  a. Three-way *.tf resource-type partition (R7): every `resource "<type>"`
     found under apps/*/infra/**/*.tf (and top-level infra/**/*.tf, if present)
     must be classified in ledger.store_classes or ledger.non_store_types, else
     FAIL fail-closed. A store_classes instance absent from ledger.stores FAILs
     "unledgered store".
  b. Volume-identity binding for mechanism:luks (R1 — the headline check):
     resolved ONLY via the row's device_binding (volume + attachment + mapper
     addresses), never by name similarity. See check_luks_row().
  c. provider-managed:<attestation> requires a named attestation + URL +
     retrieved_on; boilerplate ("the provider handles it" etc.) and staleness
     (>365 days, R9) both FAIL.
  d. plaintext-exception / cert_verification:off require an exception block
     with justification, tracking_issue (^#\\d+$), reevaluate_when, expires_on;
     an expired exception FAILs (R3, offline date arithmetic only).
  e. disclosed_as (R5): a plaintext-exception row whose disclosed_as anchor
     resolves to text asserting encryption FAILs (the exact `#6588` join gap).
  f. does_not_defend is mandatory and rejected when empty/none/n/a (NOT a
     verbatim-restatement regex — R10 deleted that as a vacuous semantic check).
  g. Positive-work floor (R8): expected store count is computed from a *.tf
     scan + the committed non_iac_stores catalog, NEVER from the ledger's own
     row count (so deleting a row cannot silently lower the floor).
  h. Hermeticity: no network calls, no `gh`/`curl`, no reads outside --repo-root.

Exit codes: 0 PASS (or a graceful skip), 1 one or more FAIL, 2 argument/IO error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import sys
from datetime import date
from pathlib import Path

# --- Shared constants --------------------------------------------------------

STORE_KIND_ENUM = {
    "guest-luks-volume",
    "provider-bucket",
    "provider-db",
    "log-sink",
    "secret-store",
}
STORE_CLASS_KIND_ENUM = {"guest-luks-volume", "provider-bucket", "provider-db"}
CERT_VERIFICATION_VALUES = {"on", "off"}

TRACKING_ISSUE_RE = re.compile(r"^#[0-9]+$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
LIVE_VERIFICATION_RE = re.compile(r"^(available|unavailable:.+)$")

# Bare "the provider handles it" boilerplate — never a valid attestation, no
# matter how it's worded. Substring match on the lower-cased attestation name
# + evidence string.
BOILERPLATE_PHRASES = (
    "the provider handles it",
    "provider handles",
    "encrypted by default",
)

# does_not_defend must be a real, concrete sentence — not a placeholder.
DENY_DOES_NOT_DEFEND = {"", "none", "n/a", "na", "not applicable"}

STALE_ATTESTATION_DAYS = 365

RESOURCE_RE = re.compile(r'resource\s+"([A-Za-z0-9_]+)"\s+"([A-Za-z0-9_]+)"\s*\{')


# --- Generic .tf / infra-file parsing helpers --------------------------------


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def find_tf_files(repo_root: Path) -> list[Path]:
    """apps/**/*.tf + (top-level) infra/**/*.tf — the R7 scan scope."""
    files: list[Path] = []
    for base in ("apps", "infra"):
        root = repo_root / base
        if root.is_dir():
            files.extend(sorted(p for p in root.rglob("*.tf") if p.is_file()))
    return files


def find_infra_files(repo_root: Path) -> list[Path]:
    """Every file under apps/*/infra/ — the R1 clause-(a) LUKS apparatus scope
    (cloud-init, bootstrap, OR cutover; any file, not just *.tf)."""
    files: list[Path] = []
    apps_dir = repo_root / "apps"
    if apps_dir.is_dir():
        for app_dir in sorted(p for p in apps_dir.iterdir() if p.is_dir()):
            infra_dir = app_dir / "infra"
            if infra_dir.is_dir():
                files.extend(sorted(p for p in infra_dir.rglob("*") if p.is_file()))
    return files


def extract_resource_blocks(text: str) -> list[tuple[str, str, str]]:
    """Return [(type, name, block_text_including_braces), ...] via a simple
    brace-depth scan (good enough for the flat HCL these infra files use)."""
    blocks: list[tuple[str, str, str]] = []
    for m in RESOURCE_RE.finditer(text):
        type_, name = m.group(1), m.group(2)
        start = m.end() - 1  # index of the opening '{'
        depth = 0
        i = start
        n = len(text)
        while i < n:
            ch = text[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        blocks.append((type_, name, text[start : i + 1]))
    return blocks


def parse_address(addr: str) -> tuple[str, str] | None:
    if not addr or "." not in addr:
        return None
    type_, name = addr.split(".", 1)
    return type_, name


def find_resource_declaration(
    tf_files: list[Path], addr: str, cache: dict[Path, str]
) -> tuple[Path, str] | None:
    parsed = parse_address(addr)
    if not parsed:
        return None
    type_, name = parsed
    for f in tf_files:
        text = cache.get(f)
        if text is None:
            text = read_text(f)
            cache[f] = text
        for t2, n2, block in extract_resource_blocks(text):
            if t2 == type_ and n2 == name:
                return f, block
    return None


def scan_tf_inventory(
    tf_files: list[Path], cache: dict[Path, str]
) -> dict[str, list[str]]:
    """type -> [resource addresses] across the whole R7 scan scope."""
    inventory: dict[str, list[str]] = {}
    for f in tf_files:
        text = cache.get(f)
        if text is None:
            text = read_text(f)
            cache[f] = text
        for t, n, _block in extract_resource_blocks(text):
            inventory.setdefault(t, []).append(f"{t}.{n}")
    return inventory


# --- R1: guest-side LUKS apparatus resolution --------------------------------


def attachment_binds_volume(attach_block: str, volume_addr: str) -> bool:
    """Structural check: does this attachment's volume_id literally reference
    the claimed volume resource? (Not name-similarity — a literal HCL ref.)"""
    parsed = parse_address(volume_addr)
    if not parsed:
        return False
    vtype, vname = parsed
    pattern = re.compile(
        rf"volume_id\s*=\s*{re.escape(vtype)}\.{re.escape(vname)}\.id\b"
    )
    return bool(pattern.search(attach_block))


def file_has_secret_pair(text: str) -> bool:
    return bool(re.search(r'resource\s+"random_password"', text)) and bool(
        re.search(r'resource\s+"doppler_secret"', text)
    )


def resolve_mapper_operand(file_text: str, raw_token: str) -> str | None:
    """A literal token resolves to itself. A `$VAR` / `${VAR}` token resolves
    ONE level via a same-file `VAR="${OTHER:-default}"` or `VAR="literal"`
    assignment, taking the `:-` default literal (R1). Anything requiring a
    second level, or with no assignment found, is unresolved (None)."""
    tok = raw_token.strip()
    # Defensive: shlex.split (the caller's tokenizer) already strips a
    # balanced pair of surrounding double-quotes, but strip again here so this
    # function is correct even if a caller ever hands it a raw, un-tokenized
    # operand like `"$MAPPER_NAME"`.
    if len(tok) >= 2 and tok.startswith('"') and tok.endswith('"'):
        tok = tok[1:-1]
    if not tok.startswith("$"):
        return tok
    varname = tok[1:].strip("{}")
    m = re.search(
        rf'\b{re.escape(varname)}\s*=\s*"\$\{{[A-Za-z_][A-Za-z0-9_]*:-([^}}"]*)\}}"',
        file_text,
    )
    if m:
        return m.group(1)
    m2 = re.search(rf'\b{re.escape(varname)}\s*=\s*"([^"$]+)"', file_text)
    if m2:
        return m2.group(1)
    return None


# cryptsetup luksOpen's ONLY value-taking flag in this repo's apparatus files.
# A trailing bare "-" after it (stdin) is its VALUE, not a positional operand.
_LUKSOPEN_VALUE_FLAGS = {"--key-file"}


def _luksopen_positionals(tail: str) -> list[str]:
    """Tokenize the text after `luksOpen` on one logical line and return its
    positional (non-flag) arguments in order. `cryptsetup luksOpen <device>
    [<name>]` — a real "open and NAME the mapper" call has 2 positionals; a
    `--test-passphrase` probe (device only, no mapper is opened) has 1 and is
    correctly excluded by the caller. A trailing shell line-continuation
    backslash (real cutover scripts wrap the command across lines) is
    stripped before tokenizing, since it is not itself an operand."""
    tail = tail.strip()
    if tail.endswith("\\"):
        tail = tail[:-1].rstrip()
    try:
        tokens = shlex.split(tail)
    except ValueError:
        return []
    positionals: list[str] = []
    i = 0
    n = len(tokens)
    while i < n:
        t = tokens[i]
        if t in _LUKSOPEN_VALUE_FLAGS:
            i += 2  # the flag AND its value (often "-" for stdin) — neither is an operand
            continue
        if t.startswith("-") and t != "-":
            i += 1  # a boolean flag (--test-passphrase, --allow-discards, ...)
            continue
        positionals.append(t)
        i += 1
    return positionals


def scan_apparatus(
    infra_files: list[Path], cache: dict[Path, str]
) -> dict[str, list[Path]]:
    """resolved_mapper -> [files] having BOTH a `cryptsetup luksFormat` AND a
    `cryptsetup luksOpen ... <device> <mapper>` site, keyed by the resolved
    mapper. Scans EVERY luksOpen occurrence in the file (re.finditer, not
    re.search) — a file may carry a second, mapper-less luksOpen (a
    `--test-passphrase` escrow probe, e.g. workspaces-cutover.sh:2064) ahead of
    or behind the real one, and a first-match-only scan can lock onto the
    wrong site or abort the whole file on an unrelated line's syntax."""
    result: dict[str, list[Path]] = {}
    for f in infra_files:
        text = cache.get(f)
        if text is None:
            text = read_text(f)
            cache[f] = text
        has_format = re.search(r"cryptsetup\s+luksFormat\b", text)
        if not has_format:
            continue
        for m in re.finditer(r"cryptsetup\s+luksOpen\b([^\n]*)", text):
            positionals = _luksopen_positionals(m.group(1))
            if len(positionals) < 2:
                continue  # no mapper operand at this site (e.g. --test-passphrase)
            mapper = resolve_mapper_operand(text, positionals[-1])
            if mapper is None:
                continue
            result.setdefault(mapper, []).append(f)
    return result


def scan_mount_evidence(
    infra_files: list[Path], cache: dict[Path, str]
) -> dict[str, list[tuple[Path, str]]]:
    """mapper_name -> [(file, 'fstab'|'gate')] — an fstab-context
    `/dev/mapper/<name>` line, OR a `MAPPER=/dev/mapper/<name>` line paired
    with a `MOUNT=` line in the SAME file."""
    result: dict[str, list[tuple[Path, str]]] = {}
    for f in infra_files:
        text = cache.get(f)
        if text is None:
            text = read_text(f)
            cache[f] = text
        lines = text.splitlines()
        has_mount_line = any(re.match(r"\s*MOUNT=", ln) for ln in lines)
        for ln in lines:
            for m in re.finditer(r"/dev/mapper/([\w-]+)", ln):
                name = m.group(1)
                if "fstab" in ln:
                    result.setdefault(name, []).append((f, "fstab"))
                elif re.match(r"\s*MAPPER=/dev/mapper/", ln) and has_mount_line:
                    result.setdefault(name, []).append((f, "gate"))
    return result


def check_luks_row(
    row: dict,
    tf_files: list[Path],
    infra_files: list[Path],
    cache: dict[Path, str],
    fails: list[str],
) -> None:
    store_addr = row["store"]
    db = row.get("device_binding")
    if not db:
        fails.append(
            f"FAIL: {store_addr} mechanism:luks requires device_binding"
            "{volume,attachment,mapper} -> add device_binding to the stores[] row"
        )
        return
    vol_addr = db["volume"]
    attach_addr = db["attachment"]
    mapper = db["mapper"]

    attach_found = find_resource_declaration(tf_files, attach_addr, cache)
    vol_found = find_resource_declaration(tf_files, vol_addr, cache)
    if not attach_found or not vol_found:
        fails.append(
            f"FAIL: {store_addr} device_binding volume/attachment "
            f"({vol_addr}/{attach_addr}) does not resolve to a real Terraform "
            "resource -> fix device_binding to reference real resources"
        )
        return
    attach_file, attach_block = attach_found

    # MUTATION-TARGET: MB-8 start (R1 volume-identity binding — the false-PASS
    # blocker. Both sub-checks below are what stops a plaintext row from
    # citing a sibling volume's LUKS apparatus.)
    if not attachment_binds_volume(attach_block, vol_addr):
        fails.append(
            f"FAIL: {store_addr} device_binding.attachment {attach_addr} does "
            f"not attach device_binding.volume {vol_addr} -> fix device_binding "
            "to a real, matching volume/attachment pair"
        )
        return
    attach_file_text = cache[attach_file]
    if not file_has_secret_pair(attach_file_text):
        fails.append(
            f"FAIL: {store_addr} device_binding.attachment {attach_addr} has no "
            "co-located random_password+doppler_secret pair -> citation belongs "
            f"to a different volume; fix device_binding or provision the LUKS "
            f"apparatus for {vol_addr}"
        )
        return
    # MUTATION-TARGET: MB-8 end

    # MUTATION-TARGET: MB-2 start (citation resolution: apparatus + mount
    # evidence — accepting the row's word instead of resolving it.)
    apparatus = scan_apparatus(infra_files, cache)
    if mapper not in apparatus:
        fails.append(
            f"FAIL: {store_addr} device_binding.mapper '{mapper}' does not "
            "resolve to any cryptsetup luksFormat+luksOpen apparatus under "
            "apps/*/infra/ -> verify the luksOpen operand (after <=1 level of "
            "${VAR:-default} resolution) equals device_binding.mapper"
        )
        return

    evidence = scan_mount_evidence(infra_files, cache)
    if mapper not in evidence:
        if evidence:
            found_mappers = sorted(evidence.keys())
            fails.append(
                f"FAIL: {store_addr} mapper mismatch: luksOpen resolves to "
                f"'{mapper}' but mount/fstab evidence names {found_mappers} -> "
                "make the mapper in the mount/fstab evidence match "
                "device_binding.mapper"
            )
        else:
            fails.append(
                f"FAIL: {store_addr} device_binding.mapper '{mapper}' has no "
                "/etc/fstab or MAPPER=/MOUNT= gate evidence under "
                "apps/*/infra/ -> add an fstab line or a "
                f"MAPPER=/dev/mapper/{mapper} + MOUNT=<path> gate pair"
            )
        return
    # MUTATION-TARGET: MB-2 end


# --- R7: three-way resource-type partition + unledgered stores --------------


def check_resource_partition(
    ledger: dict, tf_inventory: dict[str, list[str]], fails: list[str]
) -> int:
    store_classes = ledger["store_classes"]
    non_store_types = set(ledger["non_store_types"])
    ledgered_store_addrs = {s["store"] for s in ledger["stores"]}
    tf_store_count = 0
    for type_, addrs in tf_inventory.items():
        # MUTATION-TARGET: MB-5 start (unknown resource type -> FAIL, fail-closed)
        if type_ not in store_classes and type_ not in non_store_types:
            for addr in addrs:
                fails.append(
                    f"FAIL: unknown resource type {type_} (at {addr}) -> add "
                    f"{type_} to store_classes or non_store_types"
                )
            continue
        # MUTATION-TARGET: MB-5 end
        if type_ in store_classes:
            tf_store_count += len(addrs)
            # MUTATION-TARGET: MB-1 start (unledgered-store detection)
            for addr in addrs:
                if addr not in ledgered_store_addrs:
                    fails.append(
                        f"FAIL: unledgered store {addr} -> add a stores[] row "
                        f"to the ledger for {addr}"
                    )
            # MUTATION-TARGET: MB-1 end
    return tf_store_count


def check_positive_work_floor(
    ledger: dict, tf_store_count: int, fails: list[str]
) -> None:
    """R8: expected is computed from the *.tf scan + the committed
    non_iac_stores catalog — NEVER from the ledger's own stores[] length, so a
    deleted row cannot silently lower the floor it's measured against."""
    non_iac_count = len(ledger["non_iac_stores"])
    expected = tf_store_count + non_iac_count
    actual = len(ledger["stores"])
    if actual < expected:
        fails.append(
            f"FAIL: positive-work floor: expected >= {expected} stores "
            f"({tf_store_count} from *.tf + {non_iac_count} non-IaC) but "
            f"ledger has {actual} -> restore the missing stores[] row(s)"
        )


def check_live_coverage_floor(ledger: dict, fails: list[str]) -> None:
    """R8b (#6902 / ADR-141): the ledger must retain at least
    `live_coverage_floor` stores whose at_rest.live_verification == "available"
    (Layer A, PR-time, hermetic — reads only the committed ledger). The floor is
    self-declared and OPTIONAL: absent or 0 => inactive (no-op), so synthesized
    fixtures that omit it are unaffected. It is a COUNT floor keyed on the
    ledger's own declared value, NOT an identity pin on any specific store — an
    honest individual re-ledgering (available -> unavailable, with a tracking
    issue) does not false-fail; only dropping the available count BELOW the
    declared floor does, i.e. zeroing out all live-measurable at-rest coverage.

    Known weakness (recorded in ADR-141): unlike check_positive_work_floor, the
    required count is self-declared, so a commit zeroing coverage can also lower
    the integer in the same diff. Acceptable for this measure-then-scope DEFER
    (the change is visible in review); the derive-from-host-probe hardening is
    the tracking issue's follow-up.
    """
    floor = ledger.get("live_coverage_floor", 0)
    available = sum(
        1
        for s in ledger["stores"]
        if (s.get("at_rest") or {}).get("live_verification") == "available"
    )
    # MUTATION-TARGET: MB-13 start (live-coverage floor — the coverage-zeroing guard)
    if available < floor:
        fails.append(
            f"FAIL: live-coverage floor: expected >= {floor} store(s) with "
            f"at_rest.live_verification 'available' but ledger has {available} "
            "-> the ledger has lost live-measurable at-rest coverage; restore a "
            "store's live_verification to 'available' once a host emitter "
            "re-establishes a runner-reachable signal, or lower "
            "live_coverage_floor with justification (see ADR-141)"
        )
    # MUTATION-TARGET: MB-13 end


# --- Shared does_not_defend / provider-managed / exception / disclosed_as ---


def does_not_defend_check(label: str, value: str | None, fails: list[str]) -> None:
    norm = (value or "").strip().lower()
    if norm in DENY_DOES_NOT_DEFEND:
        fails.append(
            f"FAIL: {label} does_not_defend is empty/boilerplate ('{value}') -> "
            "state concretely what this mechanism does NOT defend against"
        )


def check_provider_managed(
    store: str, ar: dict, today: date, fails: list[str]
) -> None:
    mech = ar["mechanism"]
    attestation = mech.split(":", 1)[1].strip() if ":" in mech else ""
    evidence = ar.get("evidence") or ""
    combined = f"{attestation} {evidence}".lower()
    # MUTATION-TARGET: MB-3 start (boilerplate ban-list)
    if not attestation or any(p in combined for p in BOILERPLATE_PHRASES):
        fails.append(
            f"FAIL: {store} at_rest.mechanism/evidence is boilerplate "
            f"('{attestation or evidence}') -> name the real attestation (e.g. "
            "provider-managed:<Provider>-<Standard>) with attestation_url and "
            "retrieved_on"
        )
        return
    # MUTATION-TARGET: MB-3 end
    if not ar.get("attestation_url"):
        fails.append(
            f"FAIL: {store} mechanism provider-managed:{attestation} is missing "
            "attestation_url -> add the attestation URL"
        )
    retrieved_on = ar.get("retrieved_on")
    if not retrieved_on or not DATE_RE.match(retrieved_on):
        fails.append(
            f"FAIL: {store} mechanism provider-managed:{attestation} is missing "
            "a valid retrieved_on date -> add an ISO retrieved_on date"
        )
    else:
        age = (today - date.fromisoformat(retrieved_on)).days
        if age > STALE_ATTESTATION_DAYS:
            fails.append(
                f"FAIL: {store} retrieved_on {retrieved_on} is {age} days old "
                f"(>{STALE_ATTESTATION_DAYS}, as of {today.isoformat()}) -> "
                "re-fetch the attestation and update retrieved_on"
            )


def check_exception_block(
    label: str, container: dict, today: date, fails: list[str]
) -> None:
    exc = container.get("exception")
    if not exc:
        fails.append(
            f"FAIL: {label} requires an exception block -> add exception"
            "{justification,tracking_issue,reevaluate_when,expires_on}"
        )
        return
    # MUTATION-TARGET: MB-4 start (tracking_issue requirement — never silence)
    ti = exc.get("tracking_issue", "")
    if not TRACKING_ISSUE_RE.match(ti or ""):
        fails.append(
            f"FAIL: {label} exception.tracking_issue is missing or invalid "
            "(must match ^#[0-9]+$) -> add a tracking_issue like #1234"
        )
    # MUTATION-TARGET: MB-4 end
    justification = exc.get("justification", "")
    if not justification or len(justification) < 8:
        fails.append(
            f"FAIL: {label} exception.justification is missing or too short -> "
            "add a one-sentence justification"
        )
    reevaluate_when = exc.get("reevaluate_when", "")
    if not reevaluate_when or len(reevaluate_when) < 8:
        fails.append(
            f"FAIL: {label} exception.reevaluate_when is missing or too short "
            "-> add the concrete condition that reopens the decision"
        )
    # MUTATION-TARGET: MB-9 start (expires_on requirement + expiry — R3's hard clock)
    expires_on = exc.get("expires_on")
    if not expires_on or not DATE_RE.match(expires_on):
        fails.append(
            f"FAIL: {label} exception.expires_on is missing or invalid -> add "
            "an ISO expires_on date"
        )
    elif date.fromisoformat(expires_on) < today:
        fails.append(
            f"FAIL: {label} exception.expires_on {expires_on} is in the past "
            f"(as of {today.isoformat()}) -> renew the exception with a new "
            "expires_on or remove the exception"
        )
    # MUTATION-TARGET: MB-9 end


def resolve_disclosed_as(
    value: str, repo_root: Path
) -> tuple[str | None, str | None]:
    """`path:anchor` -> (text region around the anchor, path) or (None, None)
    if unresolvable. Hermetic: refuses to escape repo_root (h)."""
    if ":" not in value:
        return None, None
    path_str, anchor = value.split(":", 1)
    try:
        path = (repo_root / path_str).resolve()
        path.relative_to(repo_root.resolve())
    except (ValueError, OSError):
        return None, None
    if not path.is_file():
        return None, None
    text = read_text(path)
    idx = text.find(anchor)
    if idx == -1:
        return None, None
    start = max(0, idx - 300)
    end = min(len(text), idx + 300)
    return text[start:end], path_str


def check_disclosed_as_not_encrypted(
    store: str, ar: dict, repo_root: Path, fails: list[str]
) -> None:
    """R5: a plaintext-exception row whose disclosed_as citation resolves to
    text asserting encryption is exactly the `#6588` join gap."""
    disclosed = ar.get("disclosed_as", "")
    # MUTATION-TARGET: MB-11 start
    if not disclosed or disclosed == "not-publicly-claimed":
        return
    region, _cite = resolve_disclosed_as(disclosed, repo_root)
    if region is None:
        # Fail CLOSED: a plaintext-exception naming a disclosure anchor that does
        # not resolve cannot be verified against reality -- the exact join gap R5
        # exists to close. A moved/bogus anchor must not pass silently.
        fails.append(
            f"FAIL: {store} disclosed_as {disclosed} does not resolve "
            "(path/anchor not found) -> cannot verify the disclosure claim; "
            "fix the anchor or set disclosed_as: not-publicly-claimed"
        )
    elif re.search(r"LUKS|encrypt", region, re.IGNORECASE):
        fails.append(
            f"FAIL: {store} disclosed_as {disclosed} asserts encryption while "
            "mechanism is plaintext-exception -> correct the disclosure to "
            "match reality or fix the mechanism"
        )
    # MUTATION-TARGET: MB-11 end


def check_at_rest(row: dict, today: date, repo_root: Path, fails: list[str]) -> None:
    store = row["store"]
    ar = row["at_rest"]
    mech = ar["mechanism"]
    does_not_defend_check(f"{store} at_rest", ar.get("does_not_defend", ""), fails)
    if mech == "luks":
        return  # resolved separately by check_luks_row()
    if mech.startswith("provider-managed:"):
        check_provider_managed(store, ar, today, fails)
        return
    if mech == "plaintext-exception":
        check_exception_block(store, ar, today, fails)
        check_disclosed_as_not_encrypted(store, ar, repo_root, fails)
        return
    if mech.startswith("app-layer-envelope:"):
        if not ar.get("evidence"):
            fails.append(
                f"FAIL: {store} mechanism app-layer-envelope requires an "
                "evidence file:anchor citation -> add evidence"
            )
        return
    fails.append(
        f"FAIL: {store} at_rest.mechanism '{mech}' is not a recognized "
        "mechanism -> use luks | provider-managed:<attestation> | "
        "app-layer-envelope:<scheme> | plaintext-exception"
    )


def check_connection(conn: dict, today: date, repo_root: Path, fails: list[str]) -> None:
    label = conn["connection"]
    it = conn["in_transit"]
    does_not_defend_check(f"{label} in_transit", it.get("does_not_defend", ""), fails)
    if it.get("cert_verification") == "off":
        check_exception_block(f"{label} in_transit", it, today, fails)
        disclosed = it.get("disclosed_as")
        if disclosed and disclosed != "not-publicly-claimed":
            region, _cite = resolve_disclosed_as(disclosed, repo_root)
            if region is None:
                fails.append(
                    f"FAIL: {label} disclosed_as {disclosed} does not resolve "
                    "(path/anchor not found) -> cannot verify the disclosure "
                    "claim; fix the anchor or set disclosed_as: not-publicly-claimed"
                )
            elif re.search(r"LUKS|encrypt|TLS|verifi", region, re.IGNORECASE):
                fails.append(
                    f"FAIL: {label} disclosed_as {disclosed} asserts secure "
                    "transport while cert_verification is off -> correct the "
                    "disclosure to match reality or fix cert_verification"
                )


# --- Hand-rolled schema validation (no jsonschema dependency) ---------------

REQUIRED_TOP = (
    "schema_version",
    "store_classes",
    "non_store_types",
    "non_iac_stores",
    "stores",
    "connections",
)

# Optional top-level keys (additive; do NOT bump schema_version). #6902/ADR-141:
# live_coverage_floor is a self-declared integer arming the live-coverage floor
# (see check_live_coverage_floor). Absent => 0 => floor inactive.
OPTIONAL_TOP = ("live_coverage_floor",)


def _validate_exception(exc: dict, prefix: str) -> list[str]:
    # Deliberately shallow: only the STRUCTURAL "is this an object" shape is a
    # schema concern here. The exception's substantive required-ness
    # (justification/tracking_issue/reevaluate_when/expires_on, the
    # tracking_issue pattern, and the expires_on-in-the-past business rule) is
    # enforced ONE time, at sweep time, by check_exception_block() below —
    # which ALSO covers the conditional "exception required at all" rule a
    # static schema cannot express (present only when mechanism is
    # plaintext-exception / cert_verification is off). Splitting the same
    # requirement across schema validation AND the sweep would make the
    # tracking_issue-requirement branch structurally unreachable in isolation
    # (schema would always catch it first), which is exactly the kind of
    # doubled-but-untestable enforcement the mutation battery (MB-4) exists to
    # catch.
    if not isinstance(exc, dict):
        return [f"{prefix}.exception must be an object"]
    return []


def _validate_store(s: dict, i: int) -> list[str]:
    errs = []
    prefix = f"stores[{i}]"
    if not isinstance(s, dict):
        return [f"{prefix} must be an object"]
    for f in ("store", "kind", "at_rest"):
        if f not in s:
            errs.append(f"{prefix} missing '{f}'")
    if "kind" in s and s["kind"] not in STORE_KIND_ENUM:
        errs.append(f"{prefix}.kind invalid: {s.get('kind')!r}")
    if "at_rest" in s and isinstance(s["at_rest"], dict):
        ar = s["at_rest"]
        for f in ("mechanism", "defends_against", "does_not_defend", "disclosed_as", "live_verification"):
            if f not in ar:
                errs.append(f"{prefix}.at_rest missing '{f}'")
        if "live_verification" in ar and not LIVE_VERIFICATION_RE.match(
            ar.get("live_verification") or ""
        ):
            errs.append(
                f"{prefix}.at_rest.live_verification must match "
                "^(available|unavailable:.+)$"
            )
        if ar.get("retrieved_on") is not None and not DATE_RE.match(
            ar.get("retrieved_on") or ""
        ):
            errs.append(f"{prefix}.at_rest.retrieved_on must be YYYY-MM-DD")
        if "exception" in ar:
            errs.extend(_validate_exception(ar["exception"], f"{prefix}.at_rest"))
    elif "at_rest" in s:
        errs.append(f"{prefix}.at_rest must be an object")
    if "device_binding" in s:
        db = s["device_binding"]
        if not isinstance(db, dict):
            errs.append(f"{prefix}.device_binding must be an object")
        else:
            for f in ("volume", "attachment", "mapper"):
                if f not in db:
                    errs.append(f"{prefix}.device_binding missing '{f}'")
    return errs


def _validate_connection(c: dict, i: int) -> list[str]:
    errs = []
    prefix = f"connections[{i}]"
    if not isinstance(c, dict):
        return [f"{prefix} must be an object"]
    for f in ("connection", "enforced_at", "in_transit"):
        if f not in c:
            errs.append(f"{prefix} missing '{f}'")
    if "in_transit" in c and isinstance(c["in_transit"], dict):
        it = c["in_transit"]
        for f in ("tls", "cert_verification", "does_not_defend"):
            if f not in it:
                errs.append(f"{prefix}.in_transit missing '{f}'")
        if "cert_verification" in it and it["cert_verification"] not in CERT_VERIFICATION_VALUES:
            errs.append(f"{prefix}.in_transit.cert_verification must be on|off")
        if "exception" in it:
            errs.extend(_validate_exception(it["exception"], f"{prefix}.in_transit"))
    elif "in_transit" in c:
        errs.append(f"{prefix}.in_transit must be an object")
    return errs


def validate_ledger(ledger) -> list[str]:
    if not isinstance(ledger, dict):
        return ["ledger root must be an object"]
    extra = set(ledger.keys()) - set(REQUIRED_TOP) - set(OPTIONAL_TOP)
    errs: list[str] = []
    if extra:
        errs.append(f"unexpected top-level keys: {sorted(extra)}")
    for k in REQUIRED_TOP:
        if k not in ledger:
            errs.append(f"missing required top-level key '{k}'")
    if errs:
        return errs  # can't safely walk further

    if ledger.get("schema_version") != 1:
        errs.append("schema_version must be 1")

    if "live_coverage_floor" in ledger:
        lcf = ledger["live_coverage_floor"]
        # bool is an int subclass; reject it explicitly so `true` is not read as 1.
        if not isinstance(lcf, int) or isinstance(lcf, bool) or lcf < 0:
            errs.append("live_coverage_floor must be a non-negative integer")

    if not isinstance(ledger["store_classes"], dict):
        errs.append("store_classes must be an object")
    else:
        for t, v in ledger["store_classes"].items():
            if not isinstance(v, dict) or "kind" not in v or "mechanisms" not in v:
                errs.append(f"store_classes.{t} missing kind/mechanisms")
                continue
            if v["kind"] not in STORE_CLASS_KIND_ENUM:
                errs.append(f"store_classes.{t}.kind invalid: {v['kind']!r}")
            if not isinstance(v["mechanisms"], list) or not v["mechanisms"]:
                errs.append(f"store_classes.{t}.mechanisms must be a non-empty list")

    if not isinstance(ledger["non_store_types"], list):
        errs.append("non_store_types must be a list")
    if not isinstance(ledger["non_iac_stores"], list):
        errs.append("non_iac_stores must be a list")

    if not isinstance(ledger["stores"], list):
        errs.append("stores must be a list")
    else:
        for i, s in enumerate(ledger["stores"]):
            errs.extend(_validate_store(s, i))

    if not isinstance(ledger["connections"], list):
        errs.append("connections must be a list")
    else:
        for i, c in enumerate(ledger["connections"]):
            errs.extend(_validate_connection(c, i))

    return errs


# --- Parity table (--report) --------------------------------------------------


def print_parity_table(
    ledger: dict, tf_inventory: dict[str, list[str]]
) -> None:
    print("\n-- encryption-posture parity --")
    ledgered_by_type: dict[str, int] = {}
    for s in ledger["stores"]:
        t = s["store"].split(".", 1)[0] if "." in s["store"] else "(non-iac)"
        ledgered_by_type[t] = ledgered_by_type.get(t, 0) + 1
    print(f"{'type':32} {'in *.tf':>8} {'ledgered':>9}")
    for t in sorted(set(tf_inventory) | set(ledgered_by_type)):
        tf_n = len(tf_inventory.get(t, []))
        led_n = ledgered_by_type.get(t, 0)
        print(f"{t:32} {tf_n:>8} {led_n:>9}")
    print(f"non_iac_stores catalog: {len(ledger['non_iac_stores'])}")


# --- Sweep orchestration ------------------------------------------------------


def run_sweep(
    ledger: dict, repo_root: Path, today: date, report: bool
) -> tuple[list[str], str]:
    fails: list[str] = []
    schema_errs = validate_ledger(ledger)
    if schema_errs:
        for e in schema_errs:
            fails.append(
                f"FAIL: ledger schema: {e} -> fix scripts/encryption-posture-"
                "ledger.json against scripts/encryption-posture-ledger.schema.json"
            )
        summary = (
            f"encryption-posture: schema invalid ({len(schema_errs)} error(s)) "
            "-> FAIL"
        )
        return fails, summary

    cache: dict[Path, str] = {}
    tf_files = find_tf_files(repo_root)
    infra_files = find_infra_files(repo_root)
    tf_inventory = scan_tf_inventory(tf_files, cache)
    tf_store_count = check_resource_partition(ledger, tf_inventory, fails)
    check_positive_work_floor(ledger, tf_store_count, fails)
    check_live_coverage_floor(ledger, fails)

    for row in ledger["stores"]:
        mech = row["at_rest"]["mechanism"]
        if mech == "luks":
            check_luks_row(row, tf_files, infra_files, cache, fails)
        check_at_rest(row, today, repo_root, fails)

    for conn in ledger["connections"]:
        check_connection(conn, today, repo_root, fails)

    n_stores = len(ledger["stores"])
    n_connections = len(ledger["connections"])
    n_unledgered = sum(1 for f in fails if f.startswith("FAIL: unledgered store"))
    status = "PASS" if not fails else "FAIL"
    summary = (
        f"encryption-posture: {n_stores} stores, {n_connections} connections, "
        f"{n_unledgered} unledgered, {len(fails)} failing checks -> {status}"
    )

    if report:
        print_parity_table(ledger, tf_inventory)

    return fails, summary


# --- --check-templates --------------------------------------------------------

EXPECTED_TEMPLATE_SECTIONS = {"at_rest", "in_transit", "exception"}


def check_templates(repo_root: Path, templates_rel: str) -> int:
    path = repo_root / templates_rel
    if not path.is_file():
        print(
            f"note: {templates_rel} not found -> --check-templates SKIP "
            "(templates not yet present)"
        )
        return 0
    text = read_text(path)
    if "## Encryption Posture" not in text:
        print(
            "note: '## Encryption Posture' heading not yet present in "
            f"{templates_rel} -> --check-templates SKIP (templates not yet present)"
        )
        return 0

    fails: list[str] = []
    blocks = re.findall(r"## Encryption Posture.*?```yaml(.*?)```", text, re.DOTALL)
    if not blocks:
        fails.append(
            "FAIL: --check-templates: '## Encryption Posture' heading present "
            "but no fenced yaml block found -> add a ```yaml block matching "
            "encryption-posture-ledger.schema.json"
        )
    for idx, block in enumerate(blocks):
        top_keys = set(re.findall(r"^([a-z_]+):", block, re.MULTILINE))
        missing = EXPECTED_TEMPLATE_SECTIONS - top_keys
        if missing:
            fails.append(
                f"FAIL: --check-templates: block {idx + 1} missing top-level "
                f"section(s) {sorted(missing)} -> sync {templates_rel} with "
                "encryption-posture-ledger.schema.json"
            )
    for f in fails:
        print(f, file=sys.stderr)
    if fails:
        print(f"encryption-posture --check-templates: {len(fails)} failing -> FAIL")
        return 1
    print(f"encryption-posture --check-templates: {len(blocks)} block(s) OK -> PASS")
    return 0


# --- CLI -----------------------------------------------------------------------


def load_json(path: Path):
    return json.loads(read_text(path))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Layer A encryption-posture detector (mechanically resolves "
        "the encryption-posture ledger against real code)."
    )
    parser.add_argument("--repo-sweep", action="store_true", help="Default mode.")
    parser.add_argument(
        "--report", action="store_true", help="repo-sweep + always print the parity table."
    )
    parser.add_argument(
        "--check-templates", action="store_true", help="Validate plan-issue-templates.md blocks."
    )
    parser.add_argument(
        "--json", action="store_true", help="Emit the schema-validated ledger as JSON."
    )
    parser.add_argument("--repo-root", default=".", help="Repo root to scan (default: cwd).")
    parser.add_argument(
        "--ledger", default=None, help="Ledger path (default: <repo-root>/scripts/encryption-posture-ledger.json)."
    )
    parser.add_argument(
        "--templates-file",
        default="plugins/soleur/skills/plan/references/plan-issue-templates.md",
        help="Path (relative to --repo-root) of the templates file for --check-templates.",
    )
    parser.add_argument(
        "--today",
        default=None,
        help="YYYY-MM-DD to treat as 'today' for offline date arithmetic (R3/R9). "
        "Defaults to $EP_TODAY, else the real date.",
    )
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()

    today_str = args.today or os.environ.get("EP_TODAY") or date.today().isoformat()
    try:
        today = date.fromisoformat(today_str)
    except ValueError:
        print(
            f"ERROR: --today value '{today_str}' is not a valid YYYY-MM-DD date",
            file=sys.stderr,
        )
        return 2

    if args.check_templates:
        return check_templates(repo_root, args.templates_file)

    default_ledger = not args.ledger
    ledger_path = (
        Path(args.ledger) if args.ledger else repo_root / "scripts" / "encryption-posture-ledger.json"
    )
    if not ledger_path.is_file():
        if not default_ledger:
            print(f"ERROR: --ledger {ledger_path} not found", file=sys.stderr)
            return 2
        # Graceful degrade (R0/R11): the real seed ledger is a SEPARATE
        # deliverable (the audit). Until it lands, --repo-sweep must not break CI.
        print(
            "encryption-posture: ledger not yet seeded "
            "(scripts/encryption-posture-ledger.json absent) -> PASS (skipped)"
        )
        return 0

    try:
        ledger = load_json(ledger_path)
    except (json.JSONDecodeError, OSError) as exc:
        print(
            f"FAIL: ledger {ledger_path} could not be parsed: {exc} -> fix the JSON",
            file=sys.stderr,
        )
        return 1

    if args.json:
        schema_errs = validate_ledger(ledger)
        if schema_errs:
            for e in schema_errs:
                print(f"FAIL: ledger schema: {e}", file=sys.stderr)
            return 1
        print(json.dumps(ledger, indent=2, sort_keys=True))
        return 0

    fails, summary = run_sweep(ledger, repo_root, today, report=args.report)
    for f in fails:
        print(f, file=sys.stderr)
    print(summary)
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
