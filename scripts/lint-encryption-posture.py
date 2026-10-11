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
from pathlib import Path, PurePosixPath

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


def attachment_binds_volume(attach_code: str, attach_skel: str, volume_addr: str) -> bool:
    """Structural check: does this attachment's ONE top-level `volume_id` argument literally reference
    the claimed volume resource? (Not name-similarity - a literal HCL ref; a string or a nested map
    key spelling `volume_id = <volume>.id` is not an argument.)"""
    parsed = parse_address(volume_addr)
    if not parsed:
        return False
    vtype, vname = parsed
    vid = [v for d, v in attr_sites(attach_code, attach_skel, "volume_id") if d == 1]
    return len(vid) == 1 and bool(re.fullmatch(rf"{re.escape(vtype)}\.{re.escape(vname)}\.id", vid[0]))


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

# Shell redirections: `>f` `>>f` `2>f` `2>>f` `<f` `2>&1` (shlex strips the quotes, so
# `2>>"$LOG"` arrives as `2>>$LOG`). An operand never starts with a digit-then-angle or
# a bare angle bracket, so this cannot swallow a real device or mapper name.
_REDIRECT_RE = re.compile(r"^\d*(?:>>?|<<?)&?\d*")


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
    # A SHELL REDIRECTION IS NOT AN OPERAND. `cryptsetup luksOpen ... "$DEV" git-data
    # 2>>"$LOG"` is a legal, and now shipped (#7204), way to capture the command's stderr
    # into a stage detail file — but shlex yields the redirect as a trailing token, so
    # positionals[-1] became `2>>$LOG` and the mapper stopped resolving. The failure mode is
    # a FALSE FAIL (the store looks unbacked by any luksFormat+luksOpen apparatus), which on
    # this linter means a red gate on a correctly-encrypted store. Same class as the
    # line-continuation strip above: a trailing token that is syntax, not an argument.
    tokens = [t for t in tokens if not _REDIRECT_RE.match(t)]
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


def apparatus_mappers(text: str, resolve) -> set[str]:
    """Every mapper a `cryptsetup luksOpen ... <device> <mapper>` site in `text` resolves to, for a
    text that ALSO carries a `cryptsetup luksFormat`. Scans EVERY luksOpen occurrence (re.finditer):
    a file may carry a second, mapper-less luksOpen (a `--test-passphrase` escrow probe) ahead of or
    behind the real one. `resolve(text, operand)` is the operand resolver."""
    mappers: set[str] = set()
    if not re.search(r"cryptsetup\s+luksFormat\b", text):
        return mappers
    for m in re.finditer(r"cryptsetup\s+luksOpen\b([^\n]*)", text):
        positionals = _luksopen_positionals(m.group(1))
        if len(positionals) < 2:
            continue  # no mapper operand at this site (e.g. --test-passphrase)
        mapper = resolve(text, positionals[-1])
        if mapper is not None:
            mappers.add(mapper)
    return mappers


def scan_apparatus(
    infra_files: list[Path], cache: dict
) -> dict[str, list[Path]]:
    """resolved_mapper -> [files] having BOTH a `cryptsetup luksFormat` AND a
    `cryptsetup luksOpen ... <device> <mapper>` site, keyed by the resolved mapper. Reads the
    comment-stripped text, so a commented-out apparatus certifies nothing."""
    result: dict[str, list[Path]] = {}
    for f in infra_files:
        for mapper in apparatus_mappers(_infra_view(f, cache), resolve_mapper_operand):
            result.setdefault(mapper, []).append(f)
    return result


_MAPPER_PATH_RE = re.compile(r"/dev/mapper/([\w-]+)")
_MOUNT_LINE_RE = re.compile(r"[ \t]*MOUNT=")
_MAPPER_LINE_RE = re.compile(r"[ \t]*MAPPER=/dev/mapper/")


def mount_evidence(text: str, fstab_shaped: bool = False) -> list[tuple[str, str]]:
    """[(mapper name, 'fstab'|'gate')]: an fstab-context `/dev/mapper/<name>` line, OR a
    `MAPPER=/dev/mapper/<name>` line paired with a `MOUNT=` line in the same text. `fstab_shaped` adds
    the arm only a PINNED file is read with: an fstab-shaped line held in a variable assignment."""
    found: list[tuple[str, str]] = []
    lines = text.splitlines()
    has_mount_line = any(_MOUNT_LINE_RE.match(ln) for ln in lines)
    for ln in lines:
        fstab_ctx = "fstab" in ln
        for m in _MAPPER_PATH_RE.finditer(ln):
            if fstab_ctx:
                found.append((m.group(1), "fstab"))
            elif has_mount_line and _MAPPER_LINE_RE.match(ln):
                found.append((m.group(1), "gate"))
        # MUTATION-TARGET: MB-L2 start (fstab-shaped mount evidence in a variable assignment)
        if fstab_shaped:
            fm = _FSTAB_SHAPED.match(ln)
            if fm:
                found.append((fm.group(2), "fstab"))
        # MUTATION-TARGET: MB-L2 end
    return found


def _infra_view(f: Path, cache: dict) -> str:
    """The comment-stripped (shell/YAML) text of one infra file, read once."""
    key = (f, "view")
    if key not in cache:
        text = cache.get(f)
        if text is None:
            text = read_text(f)
            cache[f] = text
        cache[key] = line_comment_view(text)
    return cache[key]


def scan_mount_evidence(
    infra_files: list[Path], cache: dict
) -> dict[str, list[tuple[Path, str]]]:
    """mapper_name -> [(file, 'fstab'|'gate')] over the comment-stripped infra files."""
    key = ("mount-evidence", tuple(infra_files))
    if key not in cache:
        result: dict[str, list[tuple[Path, str]]] = {}
        for f in infra_files:
            for name, kind in mount_evidence(_infra_view(f, cache)):
                result.setdefault(name, []).append((f, kind))
        cache[key] = result
    return cache[key]


def check_singleton_binding(
    store_addr: str,
    db: dict,
    attach_code: str,
    attach_skel: str,
    attach_file_text: str,
    fails: list[str],
) -> bool:
    vol_addr = db["volume"]
    attach_addr = db["attachment"]
    # MUTATION-TARGET: MB-8 start (R1 volume-identity binding — the false-PASS
    # blocker. Both sub-checks below are what stops a plaintext row from
    # citing a sibling volume's LUKS apparatus.)
    if not attachment_binds_volume(attach_code, attach_skel, vol_addr):
        fails.append(
            f"FAIL: {store_addr} device_binding.attachment {attach_addr} does "
            f"not attach device_binding.volume {vol_addr} -> fix device_binding "
            "to a real, matching volume/attachment pair"
        )
        return False
    if not file_has_secret_pair(attach_file_text):
        fails.append(
            f"FAIL: {store_addr} device_binding.attachment {attach_addr} has no "
            "co-located random_password+doppler_secret pair -> citation belongs "
            f"to a different volume; fix device_binding or provision the LUKS "
            f"apparatus for {vol_addr}"
        )
        return False
    # MUTATION-TARGET: MB-8 end
    return True


def check_global_apparatus(
    store_addr: str,
    mapper: str,
    infra_files: list[Path],
    cache: dict[Path, str],
    fails: list[str],
) -> bool:
    """The generic citation resolution: any file under apps/*/infra/ that opens the mapper, and any
    file that mounts it. Used for rows that pin no apparatus (every singleton row today)."""
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
        return False

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
        return False
    # MUTATION-TARGET: MB-2 end
    return True


def check_luks_row(
    row: dict,
    tf_files: list[Path],
    infra_files: list[Path],
    cache: dict[Path, str],
    fails: list[str],
    repo_root: Path,
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

    # The row's volume IS the store it ledgers: a row for one volume cannot cite a sibling volume's
    # binding (the #6588 shape, one level up). No mutation row: with the sibling's own luks row in the
    # ledger the password-claim guard (MB-L5) fires on the same input, so deleting this check is an
    # equivalent mutant on every fixture that can reach it; WC-25 pins the message.
    if vol_addr != store_addr:
        fails.append(
            f"FAIL: {store_addr} device_binding.volume {vol_addr} must equal the store "
            f"{store_addr} -> a luks row binds its own volume, never a sibling's"
        )
        return

    # Both addresses must resolve to ONE declaration on the comment-free code view: routing between the
    # indexed and singleton arms reads that declaration, so a decoy (a singleton-shaped copy in an
    # earlier-sorted root, a ghost block) must not be able to choose the arm.
    vol_decls = find_declarations(tf_files, vol_addr, cache)
    att_decls = find_declarations(tf_files, attach_addr, cache)
    if not vol_decls or not att_decls:
        fails.append(
            f"FAIL: {store_addr} device_binding volume/attachment "
            f"({vol_addr}/{attach_addr}) does not resolve to a real Terraform "
            "resource -> fix device_binding to reference real resources"
        )
        return
    # MUTATION-TARGET: MB-L11 start (routing reads ONE declaration; a decoy cannot choose the arm)
    if len(vol_decls) != 1 or len(att_decls) != 1:
        fails.append(
            f"FAIL: {store_addr} device_binding volume {vol_addr} ({len(vol_decls)} declaration(s)) "
            f"or attachment {attach_addr} ({len(att_decls)}) is declared more than once across the "
            "scan scope -> an address must resolve exactly once, or the binding is ambiguous"
        )
        return
    # MUTATION-TARGET: MB-L11 end
    attach_file, attach_code, attach_skel = att_decls[0]

    vparsed = parse_address(vol_addr) or ("", "")
    indexed = any(
        d == 1 and re.match(rf"{re.escape(vparsed[0])}\.{re.escape(vparsed[1])}\s*\[", v)
        for d, v in attr_sites(attach_code, attach_skel, "volume_id")
    )
    ctx: dict | None = None
    if indexed:
        ctx = check_indexed_binding(store_addr, db, tf_files, cache, fails)
        if ctx is None:
            return
        missing = False
        # MUTATION-TARGET: MB-L8a start (an indexed row names the apparatus it relies on)
        if not db.get("apparatus"):
            fails.append(
                f"FAIL: {store_addr} indexed binding (the attachment's volume_id is "
                f"{vol_addr}[...]) requires apparatus -> pin the file that holds this volume's "
                "cryptsetup luksFormat and luksOpen"
            )
            missing = True
        # MUTATION-TARGET: MB-L8a end
        # MUTATION-TARGET: MB-L8b start (an indexed row names its passphrase custody)
        if not db.get("key_chain"):
            fails.append(
                f"FAIL: {store_addr} indexed binding (the attachment's volume_id is "
                f"{vol_addr}[...]) requires key_chain -> name the consumer, token, secret and "
                "password the host reads the key through"
            )
            missing = True
        # MUTATION-TARGET: MB-L8b end
        if missing:
            return
    else:
        if db.get("apparatus") or db.get("key_chain"):
            fails.append(
                f"FAIL: {store_addr} device_binding.apparatus and key_chain apply to an indexed "
                f"binding only, and the attachment's volume_id is not {vol_addr}[...] (read from "
                f"the one declaration of {attach_addr}) -> remove them from a singleton row, or "
                "fix the attachment"
            )
            return
        # The binding is read from the CODE view: a commented-out `volume_id = <volume>.id` must not
        # satisfy it while the live line is something else (an indexed or wrapped form).
        if not check_singleton_binding(
            store_addr, db, attach_code, attach_skel, hcl_views(cache[attach_file])[0], fails
        ):
            return

    # An indexed row cannot reach here without both keys (MB-L8a/b refuse it above); the `.get`s keep
    # this block total, so removing a mandatory-key check degrades to the name join instead of crashing.
    kc_ctx: dict | None = None
    if ctx is not None and db.get("key_chain"):
        kc_ctx = check_key_chain(store_addr, db, ctx, tf_files, cache, fails)
        if kc_ctx is None:
            return
    if db.get("apparatus"):
        if not check_pinned_apparatus(
            store_addr, db, kc_ctx, infra_files, repo_root, cache, fails
        ):
            return
    elif not check_global_apparatus(store_addr, mapper, infra_files, cache, fails):
        return


# --- #9372 / #9572: web-class (indexed) luks rows ----------------------------
#
# A row whose volume is a `for_each` set (the web hosts' /workspaces) cannot be proven by the
# singleton checks above: its attachment is indexed by [each.key], its passphrase reaches the host
# through a fresh-boot token rather than a same-file pair, and its apparatus is a file the generic
# scan would otherwise resolve through a SIBLING volume's cutover script (the #6588 class). The checks
# below run for a row only when its attachment is indexed, or when the row carries the optional keys
# `device_binding.key_chain` / `device_binding.apparatus`. Every structural check reads a code view
# (comments, and for the skeleton the string contents, removed), including the singleton arm, whose
# scanners read comment-stripped text since #9941 (a commented-out apparatus no longer certifies a row).


def _skip_hcl_string(text: str, i: int) -> int:
    """text[i] is a double quote; return the index just past its closing quote.
    Interpolations `${...}` / directives `%{...}` may nest quotes and braces."""
    n = len(text)
    j = i + 1
    depth = 0
    while j < n:
        c = text[j]
        if depth == 0:
            if c == "\\":
                j += 2
                continue
            if c == '"':
                return j + 1
            if text.startswith("$${", j) or text.startswith("%%{", j):
                j += 3
                continue
            if text.startswith("${", j) or text.startswith("%{", j):
                depth = 1
                j += 2
                continue
            j += 1
        else:
            if c == '"':
                j = _skip_hcl_string(text, j)
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            j += 1
    return n


def hcl_views(text: str) -> tuple[str, str]:
    """(code, skeleton), both exactly as long as `text`. `code` has `#` `//` and `/* */` comments
    and heredoc bodies blanked and keeps strings; `skeleton` additionally blanks string contents
    (interpolations included), so brace matching and attribute counting never read a string."""
    n = len(text)
    code = list(text)
    skel = list(text)

    def blank(lo: int, hi: int, arrs: tuple) -> None:
        for a in arrs:
            for k in range(lo, hi):
                if text[k] != "\n":
                    a[k] = " "

    heredoc = re.compile(r"<<-?[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\n")
    i = 0
    while i < n:
        c = text[i]
        if c == "#" or text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j, (code, skel))
            i = j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            blank(i, j, (code, skel))
            i = j
            continue
        if c == "<":
            m = heredoc.match(text, i)
            if m:
                tag = m.group(1)
                pos = m.end()
                body_end = n
                resume = n
                for lm in re.finditer(r"^[ \t]*" + re.escape(tag) + r"[ \t]*$", text[pos:], re.M):
                    body_end = pos + lm.start()
                    resume = pos + lm.end()
                    break
                blank(pos, body_end, (code, skel))
                i = resume
                continue
        if c == '"':
            j = _skip_hcl_string(text, i)
            blank(i + 1, max(i + 1, j - 1), (skel,))
            i = j
            continue
        i += 1
    return "".join(code), "".join(skel)


def line_comment_view(text: str) -> str:
    """Shell / YAML code view for POSITIVE-evidence scans: a `#` at the start of a word (after
    whitespace, `;`, `&`, `|`, `(` or `)`) comments the rest of the line. Over-stripping (a `#` after
    whitespace inside a quoted string) can only HIDE evidence, which fails the row closed; the
    command separators are included so `true;#cryptsetup luksOpen ...` is not shown as code."""
    return re.sub(r"(?m)(^|[\s;&|()])#.*$", r"\1", text)


def decl_blocks(f: Path, cache: dict) -> list[tuple[str, str, str, str]]:
    """[(type, name, code_block, skeleton_block)] for one .tf file; headers are matched on the
    comment-free code view and braces on the string-free skeleton."""
    key = (f, "decl")
    if key in cache:
        return cache[key]
    text = cache.get(f)
    if text is None:
        text = read_text(f)
        cache[f] = text
    code, skel = hcl_views(text)
    blocks: list[tuple[str, str, str, str]] = []
    for m in RESOURCE_RE.finditer(code):
        start = m.end() - 1
        depth = 0
        i = start
        n = len(skel)
        while i < n:
            if skel[i] == "{":
                depth += 1
            elif skel[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        blocks.append((m.group(1), m.group(2), code[start : i + 1], skel[start : i + 1]))
    cache[key] = blocks
    return blocks


def find_declarations(
    tf_files: list[Path], addr: str, cache: dict
) -> list[tuple[Path, str, str]]:
    """EVERY declaration of an address across the scan scope, on the comment-free code view (a
    first-match lookup would let a decoy in an earlier directory, or a commented-out block, win)."""
    parsed = parse_address(addr)
    if not parsed:
        return []
    type_, name = parsed
    found: list[tuple[Path, str, str]] = []
    for f in tf_files:
        for t2, n2, code, skel in decl_blocks(f, cache):
            if t2 == type_ and n2 == name:
                found.append((f, code, skel))
    return found


def attr_sites(code: str, skel: str, attr: str, collapse: bool = True) -> list[tuple[int, str]]:
    """[(brace depth, value text)] for every `attr =` assignment of a block. Depth 1 is a top-level
    argument; anything deeper sits in a nested block. The value runs to the end of its line, and on
    past it while a `(`, `[` or `{` opened in the value is still unclosed (counted on the skeleton, so
    a bracket in a string never counts), whitespace collapsed unless `collapse` is False - a multi-line `for_each = {` is read
    whole, so two different comprehensions never compare equal on their first line."""
    sites: list[tuple[int, str]] = []
    for m in re.finditer(rf"(?<![\w.]){attr}\s*=(?!=)", skel):
        depth = skel.count("{", 0, m.start()) - skel.count("}", 0, m.start())
        end = m.end()
        open_ = 0
        while end < len(skel):
            ch = skel[end]
            if ch in "([{":
                open_ += 1
            elif ch in ")]}":
                if open_ == 0:
                    break  # the enclosing block's own closing brace
                open_ -= 1
            elif ch == "\n" and open_ == 0:
                break
            end += 1
        value = code[m.end() : end]
        sites.append((depth, " ".join(value.split()) if collapse else value.strip("\n")))
    return sites


def _unique_decl(
    store: str, what: str, addr: str, tf_files: list[Path], cache: dict, fails: list[str]
) -> tuple[Path, str, str] | None:
    found = find_declarations(tf_files, addr, cache)
    if len(found) != 1:
        fails.append(
            f"FAIL: {store} {what} {addr} is declared more than once or not at all across the "
            f"scan scope ({len(found)} declaration(s)) -> an address must resolve exactly once"
        )
        return None
    return found[0]


def check_indexed_binding(
    store: str, db: dict, tf_files: list[Path], cache: dict, fails: list[str]
) -> dict | None:
    """The indexed arm of the volume binding: `volume_id = <vtype>.<vname>[each.key].id`, accepted
    only when the volume and the attachment each carry exactly one `for_each` and the two
    expressions are identical. Returns what later checks need, or None after appending a FAIL."""
    vol_addr, att_addr = db["volume"], db["attachment"]
    vtype, vname = parse_address(vol_addr) or ("", "")
    vol = _unique_decl(store, "indexed binding: volume", vol_addr, tf_files, cache, fails)
    att = _unique_decl(store, "indexed binding: attachment", att_addr, tf_files, cache, fails)
    if not vol or not att:
        return None
    (_vf, vcode, vskel), (_af, acode, askel) = vol, att
    exprs: dict[str, str] = {}
    for label, code, skel in (("volume", vcode, vskel), ("attachment", acode, askel)):
        sites = attr_sites(code, skel, "for_each")
        nested = any(d > 1 for d, _ in sites)
        if label == "attachment":
            nested = nested or any(d > 1 for d, _ in attr_sites(code, skel, "volume_id"))
        if nested:
            fails.append(
                f"FAIL: {store} indexed binding: for_each or volume_id inside a nested block of "
                f"the {label} -> the extractor cannot read it, so the row fails closed"
            )
            return None
        if len(sites) != 1:
            fails.append(
                f"FAIL: {store} indexed binding requires one identical for_each on the volume and "
                f"the attachment; the {label} carries {len(sites)} -> declare exactly one"
            )
            return None
        exprs[label] = sites[0][1]
    # MUTATION-TARGET: MB-L1 start (the two for_each expressions must be the same set)
    if exprs["volume"] != exprs["attachment"]:
        fails.append(
            f"FAIL: {store} indexed binding requires one identical for_each on the volume and the "
            f"attachment: {exprs['volume']!r} vs {exprs['attachment']!r} -> make them the same "
            "expression"
        )
        return None
    # MUTATION-TARGET: MB-L1 end
    vid = attr_sites(acode, askel, "volume_id")
    if len(vid) != 1 or not re.fullmatch(
        rf"{re.escape(vtype)}\.{re.escape(vname)}\[each\.key\]\.id", vid[0][1]
    ):
        fails.append(
            f"FAIL: {store} device_binding.attachment {att_addr} does not attach "
            f"device_binding.volume {vol_addr} -> the only indexed form accepted is "
            f"volume_id = {vol_addr}[each.key].id"
        )
        return None
    return {"attach_code": acode, "attach_skel": askel}


def _top_attr(code: str, skel: str, attr: str, collapse: bool = True) -> str | None:
    sites = [v for d, v in attr_sites(code, skel, attr, collapse) if d == 1]
    return sites[0] if len(sites) == 1 else None


def check_key_chain(
    store: str, db: dict, ctx: dict, tf_files: list[Path], cache: dict, fails: list[str]
) -> dict | None:
    """Passphrase custody for an indexed row whose host reads the key through a fresh-boot token: the
    attachment binds the consumer host, the consumer's user_data carries the volume id and the token,
    the token and the secret sit on one Doppler config, and the secret's value is the named password.
    Each hop is a literal reference matched on the code view. Returns the consumer's declaration for
    the install hop."""
    kc = db["key_chain"]
    consumer = _unique_decl(store, "key_chain consumer", kc["consumer"], tf_files, cache, fails)
    token = _unique_decl(store, "key_chain token", kc["token"], tf_files, cache, fails)
    secret = _unique_decl(store, "key_chain secret", kc["secret"], tf_files, cache, fails)
    if not consumer or not token or not secret:
        return None
    vtype, vname = parse_address(db["volume"]) or ("", "")
    # MUTATION-TARGET: MB-L10 start (the attachment binds the host whose user_data carries the key)
    sid = attr_sites(ctx["attach_code"], ctx["attach_skel"], "server_id")
    if len(sid) != 1 or not re.fullmatch(rf"{re.escape(kc['consumer'])}\[each\.key\]\.id", sid[0][1]):
        fails.append(
            f"FAIL: {store} key_chain consumer {kc['consumer']} is not the host the attachment binds "
            f"(server_id must be {kc['consumer']}[each.key].id) -> the host that reads the key must be "
            "the host the volume is attached to"
        )
        return None
    # MUTATION-TARGET: MB-L10 end
    # The volume id and the token reach the host through the consumer's `user_data` argument only; a
    # line elsewhere in the block (another attribute, a string) is not the host's input. The volume line
    # is matched on the skeleton, so a string literal cannot stand in for the reference, and the
    # reference must be the value or the true branch of a ternary (`cond ? <ref> : "retired"`).
    # Line structure is kept (collapse=False) so each attribute is matched on its own line; the
    # skeleton view means a string literal can stand in for neither reference.
    ud_code = _top_attr(consumer[1], consumer[2], "user_data")
    ud_skel = _top_attr(consumer[2], consumer[2], "user_data", collapse=False)
    vol_line = re.compile(
        rf"(?m)^[ \t]*workspaces_volume_id[ \t]*=[ \t]*(?:[^\n]*?\?[ \t]*)?"
        rf"{re.escape(vtype)}\.{re.escape(vname)}\[each\.key\]\.id[ \t]*(?::[^\n]*)?$"
    )
    tok_line = re.compile(
        rf"(?m)^[ \t]*workspaces_luks_fresh_boot_token[ \t]*=[ \t]*{re.escape(kc['token'])}\.key[ \t]*$"
    )
    if (
        ud_code is None
        or ud_skel is None
        or not vol_line.search(ud_skel)
        or not tok_line.search(ud_skel)
    ):
        fails.append(
            f"FAIL: {store} key_chain consumer {kc['consumer']} user_data does not carry the volume id "
            f"line (workspaces_volume_id referencing {db['volume']}[each.key].id) and the token line "
            f"(workspaces_luks_fresh_boot_token = {kc['token']}.key) the row names -> the host that "
            "reads the key does not get this volume's id and token (both must sit inside the "
            "consumer's user_data argument)"
        )
        return None
    # MUTATION-TARGET: MB-L3 start (the token reads the config the secret is written to)
    tok_cfg = _top_attr(token[1], token[2], "config")
    sec_cfg = _top_attr(secret[1], secret[2], "config")
    if not tok_cfg or tok_cfg != sec_cfg:
        fails.append(
            f"FAIL: {store} key_chain token config {tok_cfg!r} differs from the secret config "
            f"{sec_cfg!r} -> the token must read the Doppler config the passphrase is written to"
        )
        return None
    # MUTATION-TARGET: MB-L3 end
    # MUTATION-TARGET: MB-L4 start (the secret's value is the named password)
    if _top_attr(secret[1], secret[2], "value") != f"{kc['password']}.result":
        fails.append(
            f"FAIL: {store} key_chain secret value is not {kc['password']}.result -> the secret "
            "must be written from the password the row claims"
        )
        return None
    # MUTATION-TARGET: MB-L4 end
    return {"consumer_file": consumer[0], "user_data": ud_code}


def check_password_claims(
    ledger: dict, tf_files: list[Path], cache: dict, fails: list[str]
) -> None:
    """No random_password may be claimed by two luks rows. A row's claim is its key_chain.password,
    or - for a row with no key_chain - every random_password declared in its attachment's own file.
    Keyed by (Terraform root, address): two roots may reuse a name."""
    claims: dict[tuple[Path, str], list[str]] = {}
    for row in ledger["stores"]:
        if row["at_rest"]["mechanism"] != "luks" or not row.get("device_binding"):
            continue
        db = row["device_binding"]
        att = find_declarations(tf_files, db["attachment"], cache)
        if not att:
            continue
        root = att[0][0].parent
        if db.get("key_chain"):
            addrs = [db["key_chain"]["password"]]
        else:
            addrs = [
                f"random_password.{n}"
                for t, n, _c, _s in decl_blocks(att[0][0], cache)
                if t == "random_password"
            ]
        for a in addrs:
            claims.setdefault((root, a), []).append(row["store"])
    conflicts = {k: v for k, v in claims.items() if len(set(v)) > 1}
    # MUTATION-TARGET: MB-L5 start (one passphrase, one luks row)
    for (_root, addr), rows in conflicts.items():
        fails.append(
            f"FAIL: {addr} is claimed by more than one luks row ({', '.join(sorted(set(rows)))}) "
            "-> each luks row needs its own passphrase"
        )
    # MUTATION-TARGET: MB-L5 end


def check_apparatus_pins(ledger: dict, fails: list[str]) -> None:
    pins: dict[str, list[str]] = {}
    for row in ledger["stores"]:
        db = row.get("device_binding") or {}
        if row["at_rest"]["mechanism"] == "luks" and db.get("apparatus"):
            pins.setdefault(db["apparatus"], []).append(row["store"])
    for path, rows in sorted(pins.items()):
        if len(rows) > 1:
            fails.append(
                f"FAIL: apparatus {path} is pinned by more than one row ({', '.join(rows)}) -> a "
                "file with one luksOpen cannot serve two volumes"
            )


_UNQUOTED_ASSIGN = r"^[ \t]*(?:export[ \t]+)?{var}=([A-Za-z0-9_.-]+)[ \t]*$"
_FSTAB_SHAPED = re.compile(
    r"^\s*[A-Za-z_][A-Za-z0-9_]*=(['\"])/dev/mapper/([\w-]+)\s+/\S+\s+\S+\s+\S+(?:\s+\d+\s+\d+)?\1\s*$"
)


def _pinned_mapper(view: str, raw_token: str) -> str | None:
    """resolve_mapper_operand, then - for a PINNED file only - one unquoted `VAR=literal`
    assignment (exactly one of that name, no `:=`)."""
    got = resolve_mapper_operand(view, raw_token)
    tok = raw_token.strip().strip('"')
    if got is not None or not tok.startswith("$"):
        return got
    var = tok[1:].strip("{}")
    # MUTATION-TARGET: MB-L6 start (the provisioner's own unquoted MAPPER_NAME=literal)
    hits = re.findall(_UNQUOTED_ASSIGN.format(var=re.escape(var)), view, re.M)
    if len(hits) == 1:
        return hits[0]
    # MUTATION-TARGET: MB-L6 end
    return None


def scan_pinned_apparatus(view: str) -> set[str]:
    return apparatus_mappers(view, _pinned_mapper)


def scan_pinned_mount_evidence(view: str) -> set[str]:
    return {name for name, _kind in mount_evidence(view, fstab_shaped=True)}


def check_pinned_apparatus(
    store: str,
    db: dict,
    kc_ctx: dict | None,
    infra_files: list[Path],
    repo_root: Path,
    cache: dict,
    fails: list[str],
) -> bool:
    path = db["apparatus"]
    mapper = db["mapper"]
    pp = PurePosixPath(path)
    target = repo_root / path
    # The path must be spelled canonically (so two spellings of one file cannot dodge the one-row-per-
    # file rule), stay relative with no '..', be a regular file under apps/*/infra/ (the infra_files
    # set), and not resolve through a symlink at any depth.
    if (
        pp.as_posix() != path
        or pp.is_absolute()
        or ".." in pp.parts
        or target not in set(infra_files)
        or target.resolve() != target
    ):
        fails.append(
            f"FAIL: {store} device_binding.apparatus '{path}' must be a canonical relative path to a "
            "regular file under apps/*/infra/ (no '..', '.', '//' or symlink) -> fix the pin"
        )
        return False
    base = pp.name
    # The install hop needs the consumer that only key_chain names; an indexed row always has it.
    if kc_ctx is not None:
        consumer_file: Path = kc_ctx["consumer_file"]
        # The pin must be the module-root script the host installs: the host-script list and the
        # cloud-init line name a BASENAME resolved against the consumer's own directory, so the same
        # basename in another directory is a different file the host never reads.
        same_dir = target.parent == consumer_file.parent
        ci = re.search(r'templatefile\(\s*"\$\{path\.module\}/([^"]+)"', kc_ctx["user_data"])
        list_ok = bool(
            re.search(
                rf'^[ \t]*"{re.escape(base)}",?[ \t]*$',
                hcl_views(cache.get(consumer_file) or read_text(consumer_file))[0],
                re.M,
            )
        )
        init_ok = False
        ci_path = consumer_file.parent / ci.group(1) if ci else None
        if ci_path is not None and ci_path.is_file():
            init_text = line_comment_view(read_text(ci_path))
            run_at = re.search(r"(?m)^runcmd:[ \t]*$", init_text)
            # The runcmd section ends at the next top-level key (write_files:, power_state:, ...).
            section = init_text[run_at.end() :] if run_at else ""
            section = re.split(r"(?m)^[A-Za-z_][\w-]*:", section, maxsplit=1)[0]
            init_ok = bool(
                re.search(rf"(?m)^[ \t]*-[ \t]*/usr/local/bin/{re.escape(base)}[ \t]*$", section)
            )
        if not (same_dir and list_ok and init_ok):
            fails.append(
                f"FAIL: {store} apparatus {path} is not installed by the consumer "
                f"{db['key_chain']['consumer']} -> a file no host installs proves nothing about the "
                f"volume. Checked: pinned file in the consumer's directory "
                f"({consumer_file.parent.relative_to(repo_root).as_posix()}/): {same_dir}; "
                f'host-script list entry `"{base}",` in {consumer_file.name}: {list_ok}; '
                f"`- /usr/local/bin/{base}` under runcmd: in "
                f"{ci_path.name if ci_path else '(no templatefile in user_data)'}: {init_ok}"
            )
            return False
    view = _infra_view(target, cache)
    opened = scan_pinned_apparatus(view)
    if mapper not in opened:
        fails.append(
            f"FAIL: {store} pinned apparatus {path} does not resolve a cryptsetup "
            f"luksFormat+luksOpen site for mapper '{mapper}' (mappers found: {sorted(opened) or 'none'}) "
            "-> the file the row pins must hold a `cryptsetup luksFormat` and a `cryptsetup luksOpen "
            "[flags] <device> <mapper>` whose mapper is a literal, a `$VAR` assigned once as `VAR=literal` "
            'or `VAR="${X:-literal}"`; comments and text after a command separator `#` do not count'
        )
        return False
    if mapper not in scan_pinned_mount_evidence(view):
        fails.append(
            f"FAIL: {store} has no mount evidence in the pinned apparatus {path} for mapper "
            f"'{mapper}' -> the pinned file must carry its own fstab line or MAPPER=/MOUNT= pair"
        )
        return False
    return True


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
    # validate_ledger (run first in run_sweep, early-returns on any schema error)
    # guarantees every store carries an at_rest.live_verification, so subscript
    # directly — matching the sibling floor + the run_sweep loop below.
    available = sum(
        1
        for s in ledger["stores"]
        if s["at_rest"]["live_verification"] == "available"
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
    else:
        # Advance notice, not a failure (#6907). The sweep blocks merge through
        # `test`, so an expiry is a repo-wide merge freeze on the day it lands;
        # this line is the only warning an operator gets before that day.
        days_left = (date.fromisoformat(expires_on) - today).days
        if days_left <= EXPIRY_WARN_DAYS:
            print(
                f"::warning::encryption-posture: {label} exception expires in "
                f"{days_left} day(s) ({expires_on}); tracking {exc.get('tracking_issue', '?')} "
                "-> renew or remove it before then, or every PR goes red on that date"
            )
    # MUTATION-TARGET: MB-9 end


# Days before an exception's expires_on at which the sweep starts warning.
EXPIRY_WARN_DAYS = 14


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


KEY_CHAIN_FIELDS = ("consumer", "token", "secret", "password")


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
                elif not (isinstance(db[f], str) and db[f]):
                    errs.append(f"{prefix}.device_binding.{f} must be a non-empty string")
            for f in sorted(set(db) - {"volume", "attachment", "mapper", "apparatus", "key_chain"}):
                errs.append(f"{prefix}.device_binding has unexpected key '{f}'")
            mech = (s.get("at_rest") or {}).get("mechanism") if isinstance(s.get("at_rest"), dict) else None
            if mech != "luks" and ("apparatus" in db or "key_chain" in db):
                errs.append(
                    f"{prefix}.device_binding.apparatus and key_chain apply to a mechanism:luks row only"
                )
            if "apparatus" in db and not (
                isinstance(db["apparatus"], str) and db["apparatus"].strip()
            ):
                errs.append(f"{prefix}.device_binding.apparatus must be a non-empty string")
            if "key_chain" in db:
                kc = db["key_chain"]
                if not isinstance(kc, dict):
                    errs.append(f"{prefix}.device_binding.key_chain must be an object")
                else:
                    for f in KEY_CHAIN_FIELDS:
                        if not (isinstance(kc.get(f), str) and kc.get(f)):
                            errs.append(
                                f"{prefix}.device_binding.key_chain.{f} must be a non-empty string"
                            )
                    if isinstance(kc.get("password"), str) and not kc["password"].startswith(
                        "random_password."
                    ):
                        errs.append(
                            f"{prefix}.device_binding.key_chain.password must name a random_password"
                        )
                    for f in sorted(set(kc) - set(KEY_CHAIN_FIELDS)):
                        errs.append(f"{prefix}.device_binding.key_chain has unexpected key '{f}'")
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
    check_password_claims(ledger, tf_files, cache, fails)
    check_apparatus_pins(ledger, fails)

    for row in ledger["stores"]:
        mech = row["at_rest"]["mechanism"]
        if mech == "luks":
            check_luks_row(row, tf_files, infra_files, cache, fails, repo_root)
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
        # FAIL, not a graceful skip (#6907). The skip existed while the seed
        # ledger was a separate deliverable; since the sweep blocks merge
        # through `test`, reading a missing ledger as a pass would make
        # deleting it a one-line bypass of the gate.
        print(
            "FAIL: encryption-posture ledger missing "
            "(scripts/encryption-posture-ledger.json absent) -> restore it; "
            "the sweep is merge-blocking and cannot pass without a ledger",
            file=sys.stderr,
        )
        return 1

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
