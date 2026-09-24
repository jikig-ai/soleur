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

Checks implemented (each independently mutation-testable; see the MB-N rows
in lint-encryption-posture.test.sh)
------------------------------------------------------------------------
  a. Three-way *.tf resource-type partition (R7): every resource block in any
     TRACKED `*.tf` / `*.tf.json` (quoted or unquoted labels; comments, strings
     and heredocs cannot fake or truncate a block) must be classified in
     ledger.store_classes or ledger.non_store_types, else FAIL fail-closed. A
     store_classes instance absent from ledger.stores FAILs "unledgered store".
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
  h. Hermeticity: no network calls, no `gh`/`curl`. Files are read from the
     tracked set (`git ls-files`, which reads the repository's git directory),
     never through a symlink.
  i. #8532: an exact positive-work floor (every catalogued id names a row, every
     row is a store-class address or catalogued, no id or address repeats, a
     row conforms to its store class); instance multiplicity for
     for_each/count/module blocks; disclosure anchors resolve exactly once and
     a luks row's claim sentence claims encryption without denying it; record
     anchors in record_surfaces agree with the ledger by equality (ADR-246,
     ADR-247).

Exit codes: 0 PASS (or a graceful skip), 1 one or more FAIL, 2 argument/IO error.
"""

from __future__ import annotations

import argparse
import functools
import json
import os
import re
import shlex
import subprocess
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
    "host-root-disk",
    "provider-image",
}
STORE_CLASS_KIND_ENUM = {
    "guest-luks-volume",
    "provider-bucket",
    "provider-db",
    "host-root-disk",
}
# The validator never reads the schema file; the test suite pins these three
# sets equal to the schema's so the two cannot drift silently.
STORE_KEYS = {"store", "kind", "device_binding", "at_rest", "multiplicity", "records"}
AT_REST_KEYS = {
    "mechanism", "evidence", "attestation_url", "retrieved_on", "defends_against",
    "does_not_defend", "disclosed_as", "live_verification", "exception",
}
DEVICE_BINDING_KEYS = {"volume", "attachment", "mapper"}
CONNECTION_KEYS = {"connection", "enforced_at", "in_transit"}
IN_TRANSIT_KEYS = {"tls", "cert_verification", "does_not_defend", "disclosed_as", "exception"}
EXCEPTION_KEYS = {
    "justification", "tracking_issue", "reevaluate_when", "expires_on",
    # Optional dated record of a review that deliberately left expires_on alone
    # (#7778, hcloud_volume.inngest_redis).
    "reassessed_on", "expires_on_not_extended",
}
STORE_CLASS_KEYS = {"kind", "mechanisms"}


def _unknown_keys(obj: dict, allowed: set[str], where: str) -> list[str]:
    """A misspelled key is rejected, never ignored: an ignored `disclosed_ass`
    silently switches off the check that reads `disclosed_as`."""
    extra = sorted(set(obj) - allowed)
    return [f"{where} has unexpected key(s) {extra}"] if extra else []
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

# A resource block header, quoted or unquoted labels, hyphens allowed (HCL
# identifiers may contain `-`). Run over the comment-blanked view, anchored at a
# line start, so a commented-out `# resource ...` is not counted.
RESOURCE_RE = re.compile(
    r'^[ \t]*resource[ \t]+(?:"([A-Za-z0-9_-]+)"|([A-Za-z_][A-Za-z0-9_-]*))'
    r'[ \t]+(?:"([A-Za-z0-9_-]+)"|([A-Za-z_][A-Za-z0-9_-]*))[ \t]*\{',
    re.MULTILINE,
)
HEREDOC_RE = re.compile(r"<<-?[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*$")
MODULE_RE = re.compile(r'^module\s+"([A-Za-z0-9_-]+)"\s*\{', re.MULTILINE)
MODULE_SOURCE_RE = re.compile(r'^\s*source\s*=\s*"(\.\.?/[^"]+)"', re.MULTILINE)
META_ARG_RE = re.compile(r"^\s*(for_each|count)\s*=\s*(.*?)\s*$")
MAP_KEY_RE = re.compile(r'^\s*"?([A-Za-z0-9_.-]+)"?\s*=')


# --- Generic .tf / infra-file parsing helpers --------------------------------


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _tracked_files(repo_root: Path, pathspecs: list[str]) -> list[Path] | None:
    """Tracked files matching `pathspecs` when repo_root is the top of a git work
    tree, else None. The sweep must give the same verdict on every checkout
    (ADR-140, "Layer A is hermetic"), so it reads the TRACKED file set: an untracked
    `.tf`, a gitignored `*.tfvars`, or a `.terraform/` provider cache on one
    machine must not change it. Every inherited GIT_* variable is dropped first:
    GIT_DIR beats `-C`, so under a git hook it would answer for another repo."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        top = subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True, env=env,
        ).stdout.strip()
        if Path(top).resolve() != repo_root.resolve():
            return None
        out = subprocess.run(
            ["git", "-C", str(repo_root), "ls-files", "-z", "--", *pathspecs],
            capture_output=True, check=True, env=env,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        if (repo_root / ".git").exists():
            # A git checkout whose git could not answer: the fallback walk may
            # read untracked files, so say so rather than degrade silently.
            print(
                "::warning::encryption-posture: git ls-files failed in a git "
                "checkout; scanning the filesystem instead (untracked files "
                "may affect this verdict)",
                file=sys.stderr,
            )
        return None
    paths = [repo_root / p for p in out.decode("utf-8", "replace").split("\0") if p]
    # A tracked symlink could point outside the repository (hermeticity, h).
    return sorted(p for p in paths if p.is_file() and not p.is_symlink())


def _walk(root: Path, pattern: str) -> list[Path]:
    """Filesystem fallback for a tree that is not a git work tree (the test
    fixtures). Never descends into a `.terraform/` provider cache."""
    return sorted(
        p for p in root.rglob(pattern)
        if p.is_file() and ".terraform" not in p.relative_to(root).parts
    )


def find_tf_files(repo_root: Path) -> list[Path]:
    """Every tracked `*.tf` and `*.tf.json` in the repository — the R7 scan
    scope. Not a directory allowlist: a Terraform root added anywhere is in
    scope the moment it is tracked."""
    tracked = _tracked_files(repo_root, [":(glob)**/*.tf", ":(glob)**/*.tf.json"])
    if tracked is not None:
        return tracked
    return sorted(set(_walk(repo_root, "*.tf")) | set(_walk(repo_root, "*.tf.json")))


def find_infra_files(repo_root: Path) -> list[Path]:
    """Every file under apps/*/infra/ — the R1 clause-(a) LUKS apparatus scope
    (cloud-init, bootstrap, OR cutover; any file, not just *.tf)."""
    tracked = _tracked_files(repo_root, [":(glob)apps/*/infra/**"])
    if tracked is not None:
        return tracked
    files: list[Path] = []
    apps_dir = repo_root / "apps"
    if apps_dir.is_dir():
        for app_dir in sorted(p for p in apps_dir.iterdir() if p.is_dir()):
            infra_dir = app_dir / "infra"
            if infra_dir.is_dir():
                files.extend(_walk(infra_dir, "*"))
    return files


def hcl_views(text: str) -> tuple[str, str]:
    """Two same-length, same-line-structure views of HCL source:
    - `nc`: comments (`#`, `//`, `/* */`) blanked, strings and heredocs kept;
    - `co`: additionally blanks string contents and heredoc bodies.
    Every brace count and meta-argument scan reads `co`, so a `}` inside a
    comment, a string or a heredoc cannot truncate a block or hide a
    `for_each`; label and expression TEXT is read from `nc` at the same
    offsets. A small state machine, not a parser: an interpolation that nests
    a second quoted string ends the string early, which errs toward counting
    braces that a string held, i.e. toward a louder failure."""
    nc = list(text)
    co = list(text)
    i, n = 0, len(text)
    heredoc: str | None = None
    line_start = True
    while i < n:
        ch = text[i]
        if heredoc is not None:
            j = text.find("\n", i)
            j = n if j == -1 else j
            if text[i:j].strip() == heredoc:
                heredoc = None
            else:
                for k in range(i, j):
                    co[k] = " "
            i = j + 1
            continue
        if ch == "#" or text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                nc[k] = co[k] = " "
            i = j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                if text[k] != "\n":
                    nc[k] = co[k] = " "
            i = j
            continue
        if ch == '"':
            k = i + 1
            while k < n and text[k] != '"' and text[k] != "\n":
                if text[k] == "\\":
                    co[k] = " "
                    k += 1
                if k < n and text[k] != "\n":
                    co[k] = " "
                k += 1
            i = k + 1
            continue
        if ch == "<" and text.startswith("<<", i):
            j = text.find("\n", i)
            j = n if j == -1 else j
            hm = HEREDOC_RE.match(text[i:j])
            if hm:
                heredoc = hm.group(1)
                i = j + 1
                continue
        i += 1
    return "".join(nc), "".join(co)


def _json_resource_blocks(text: str) -> list[tuple[str, str, str]]:
    """`*.tf.json` resources as (type, name, synthetic block). The synthetic
    block restates any `for_each`/`count` as an HCL line so the multiplicity
    check reads JSON and HCL the same way. Unparseable JSON is reported by the
    caller as a block-less file, never skipped silently."""
    try:
        doc = json.loads(text)
    except ValueError:
        return [("__unparseable_tf_json__", "file", "{}")]
    res = doc.get("resource", {}) if isinstance(doc, dict) else {}
    items = res if isinstance(res, list) else [res]
    out: list[tuple[str, str, str]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        for type_, named in item.items():
            named_list = named if isinstance(named, list) else [named]
            for nm in named_list:
                if not isinstance(nm, dict):
                    continue
                for name, body in nm.items():
                    body0 = body[0] if isinstance(body, list) and body else body
                    lines = ["{"]
                    if isinstance(body0, dict):
                        for meta in ("for_each", "count"):
                            if meta in body0:
                                lines.append(f"  {meta} = {json.dumps(body0[meta])}")
                    lines.append("}")
                    out.append((type_, name, "\n".join(lines)))
    return out


def extract_resource_blocks(text: str, json_source: bool = False) -> list[tuple[str, str, str]]:
    """Return [(type, name, block_text_including_braces), ...]. The block extent
    is found on the code-only view (see hcl_views) and the returned text is the
    comment-blanked view, so string values survive for the callers that read
    them (attachment_binds_volume, block_meta_args)."""
    if json_source:
        return _json_resource_blocks(text)
    nc, co = hcl_views(text)
    blocks: list[tuple[str, str, str]] = []
    for m in RESOURCE_RE.finditer(nc):
        type_ = m.group(1) or m.group(2)
        name = m.group(3) or m.group(4)
        start = m.end() - 1  # index of the opening '{'
        end = _brace_end(co, start)
        blocks.append((type_, name, nc[start : end + 1]))
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
        for t2, n2, block in extract_resource_blocks(text, f.name.endswith(".tf.json")):
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
        for t, n, _block in extract_resource_blocks(text, f.name.endswith(".tf.json")):
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
    apparatus=None,
    evidence=None,
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
    if apparatus is None:
        apparatus = scan_apparatus(infra_files, cache)
    if mapper not in apparatus:
        fails.append(
            f"FAIL: {store_addr} device_binding.mapper '{mapper}' does not "
            "resolve to any cryptsetup luksFormat+luksOpen apparatus under "
            "apps/*/infra/ -> verify the luksOpen operand (after <=1 level of "
            "${VAR:-default} resolution) equals device_binding.mapper"
        )
        return

    if evidence is None:
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
    tf_store_addrs: set[str] = set()
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
            tf_store_addrs.update(addrs)
            # MUTATION-TARGET: MB-1 start (unledgered-store detection)
            for addr in addrs:
                if addr not in ledgered_store_addrs:
                    fails.append(
                        f"FAIL: unledgered store {addr} -> add a stores[] row "
                        f"to the ledger for {addr}"
                    )
            # MUTATION-TARGET: MB-1 end
    return len(tf_store_addrs)


def check_positive_work_floor(
    ledger: dict, tf_store_count: int, fails: list[str]
) -> None:
    """R8: expected is computed from the *.tf scan + the committed
    non_iac_stores catalog — NEVER from the ledger's own stores[] length, so a
    deleted row cannot silently lower the floor it's measured against."""
    # Distinct counts on every operand: repetition is reported by name
    # (MB-21 rows, MB-29 addresses and catalogue), never absorbed as slack here.
    non_iac_count = len(set(ledger["non_iac_stores"]))
    expected = tf_store_count + non_iac_count
    actual = len({s["store"] for s in ledger["stores"]})
    # MUTATION-TARGET: MB-22 start (positive-work floor FAIL branch)
    if actual < expected:
        fails.append(
            f"FAIL: positive-work floor: expected >= {expected} stores "
            f"({tf_store_count} from *.tf + {non_iac_count} non-IaC) but "
            f"ledger has {actual} -> restore the missing stores[] row(s)"
        )
    # MUTATION-TARGET: MB-22 end


def check_non_iac_identity(ledger: dict, fails: list[str]) -> None:
    """#8532 PR-1: every id the floor counts must name a row that exists.

    The floor COUNTS the catalog and never joined it to stores[], so deleting
    the committed supabase.prd row left one unit of slack and the sweep green.
    Exact, case-sensitive match: store ids are addresses, not labels."""
    row_ids = {s["store"] for s in ledger["stores"]}
    # MUTATION-TARGET: MB-17 start (catalogued id must name a row)
    for cid in ledger["non_iac_stores"]:
        if cid not in row_ids:
            fails.append(
                f"FAIL: non_iac_stores entry {cid} names no stores[] row -> "
                f"restore the {cid} row, or remove {cid} from non_iac_stores "
                "if the store is gone"
            )
    # MUTATION-TARGET: MB-17 end


def check_store_id_accounted(
    ledger: dict, tf_inventory: dict[str, list[str]], fails: list[str]
) -> None:
    """#8532 PR-1, the forward direction: every stores[] row resolves to a
    *.tf address of a store-class type or to a non_iac_stores entry, and no
    id repeats. With check_non_iac_identity and MB-1 this makes the floor
    exact by construction: a row outside both operands, or a second copy of
    one, is spare count a deleted row could hide behind."""
    store_classes = ledger["store_classes"]
    tf_store_addrs = {
        addr
        for type_, addrs in tf_inventory.items()
        if type_ in store_classes
        for addr in addrs
    }
    catalog = set(ledger["non_iac_stores"])
    # MUTATION-TARGET: MB-29 start (the floor's operands are disjoint sets)
    declared: dict[str, int] = {}
    for type_, addrs in tf_inventory.items():
        if type_ in store_classes:
            for addr in addrs:
                declared[addr] = declared.get(addr, 0) + 1
    for addr, n in sorted(declared.items()):
        if n > 1:
            fails.append(
                f"FAIL: store address {addr} is declared by {n} *.tf blocks "
                "(separate Terraform roots) and one ledger row cannot tell them "
                "apart -> rename one of the resources"
            )
    for cid in sorted(catalog & set(declared)):
        fails.append(
            f"FAIL: non_iac_stores entry {cid} is also a *.tf store address -> "
            "remove it from non_iac_stores; the *.tf scan already counts it"
        )
    for cid in sorted({c for c in ledger["non_iac_stores"]
                       if ledger["non_iac_stores"].count(c) > 1}):
        fails.append(
            f"FAIL: non_iac_stores entry {cid} is listed more than once -> "
            "list it once"
        )
    # MUTATION-TARGET: MB-29 end
    seen: set[str] = set()
    for row in ledger["stores"]:
        sid = row["store"]
        parsed = parse_address(sid)
        # MUTATION-TARGET: MB-23 start (store-class address must be a real block)
        if parsed and parsed[0] in store_classes and sid not in tf_store_addrs:
            fails.append(
                f"FAIL: stores[] row {sid} names a store_classes type but no "
                "*.tf block declares it -> delete the ghost row (a catalogue "
                "entry cannot stand in for a Terraform block)"
            )
        # MUTATION-TARGET: MB-23 end
        # MUTATION-TARGET: MB-21 start (row accounted + unique)
        if sid in seen:
            fails.append(
                f"FAIL: duplicate stores[] row {sid} -> merge the rows; a "
                "second copy is floor slack a deleted row can hide behind"
            )
        elif sid not in tf_store_addrs and sid not in catalog:
            fails.append(
                f"FAIL: stores[] row {sid} is not accounted for (no *.tf "
                "resource of a store_classes type at that address, and not in "
                f"non_iac_stores) -> fix the address, or catalogue {sid} in "
                "non_iac_stores"
            )
        # MUTATION-TARGET: MB-21 end
        seen.add(sid)


def _brace_end(text: str, open_idx: int) -> int:
    """Index of the '}' closing the '{' at open_idx (or len(text)-1)."""
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(text) - 1


def _strip_hcl_comment(line: str) -> str:
    return re.split(r"\s(?:#|//)", " " + line, maxsplit=1)[0][1:]


def block_meta_args(block: str) -> dict[str, str]:
    """Top-level `for_each` / `count` of a resource block (depth 1 only, so a
    nested `labels = { count = ... }` or a dynamic block is not read). Depth is
    counted on the code-only view, so a brace inside a string or a comment
    cannot move it; the expression text is read from the same lines of the
    comment-blanked view."""
    out: dict[str, str] = {}
    nc, co = hcl_views(block)
    nlines, clines = nc.splitlines(), co.splitlines()
    depth = 0
    i = 0
    while i < len(clines):
        cl, nl = clines[i], nlines[i]
        if depth == 1:
            m = META_ARG_RE.match(cl)
            if m:
                # An expression that opens a bracket continues until it closes
                # (`for_each = {` / `for k, v in var.x : k => v` / `}`), so the
                # whole expression is what the gate check reads.
                mn = META_ARG_RE.match(nl)
                expr = [mn.group(2) if mn else m.group(2)]
                bal = _bracket_balance(m.group(2))
                while bal > 0 and i + 1 < len(clines):
                    i += 1
                    expr.append(nlines[i].strip())
                    bal += _bracket_balance(clines[i])
                    depth += clines[i].count("{") - clines[i].count("}")
                out[m.group(1)] = " ".join(x for x in expr if x)
        depth += cl.count("{") - cl.count("}")
        i += 1
    return out


def _bracket_balance(s: str) -> int:
    return sum(s.count(o) - s.count(c) for o, c in ("{}", "[]", "()"))


def resolve_var_map_keys(
    tf_file: Path, var_name: str, cache: dict[Path, str], tf_files: list[Path]
) -> list[str] | None:
    """Top-level keys of `variable "<var_name>" { default = { ... } }` in the same
    Terraform root (directory) as tf_file, or None when that cannot be settled.
    The committed default is the authority: `*.tfvars` is gitignored here, the
    apply reads its TF_VAR_* inputs from Doppler, and the web-host membership
    check already treats this literal as canonical. Candidates are the SCANNED
    files (tracked, see find_tf_files), never a directory glob. Fails closed
    (None) when the variable is declared more than once in the root (an
    `override.tf` redeclaration), when it has no default, or when the default
    is not a literal object."""
    root = tf_file.parent
    var_re = re.compile(
        r'^[ \t]*variable[ \t]+"' + re.escape(var_name) + r'"[ \t]*\{', re.MULTILINE
    )
    decls: list[tuple[str, str, int]] = []
    for f in sorted(p for p in tf_files if p.parent == root and p.suffix == ".tf"):
        text = _cached_read(f, cache)
        nc, co = hcl_views(text)
        for m in var_re.finditer(nc):
            decls.append((nc, co, m.end() - 1))
    if len(decls) != 1:
        return None
    nc, co, open_idx = decls[0]
    close = _brace_end(co, open_idx)
    d = re.compile(r"^[ \t]*default[ \t]*=[ \t]*\{", re.MULTILINE).search(co, open_idx, close)
    if not d:
        return None
    d_open = d.end() - 1
    d_close = _brace_end(co, d_open)
    # Keep only depth-0 characters of the object body (from nc, so quoted keys
    # survive); every nested value is blanked, so two keys on one line and a
    # key after a multi-line value are both seen.
    depth0 = []
    depth = 0
    for k in range(d_open + 1, d_close):
        c = co[k]
        if c in "{[(":
            depth += 1
        if depth == 0:
            depth0.append(nc[k])
        elif nc[k] == "\n":
            depth0.append("\n")
        if c in "}])":
            depth -= 1
    body = "".join(depth0)
    return [a or b for a, b in re.findall(r'(?:"([^"\n]+)"|([A-Za-z_][A-Za-z0-9_-]*))[ \t]*[=:]', body)]


def _cached_read(f: Path, cache: dict[Path, str]) -> str:
    text = cache.get(f)
    if text is None:
        text = read_text(f)
        cache[f] = text
    return text


def module_calls_by_dir(tf_files: list[Path], cache: dict[Path, str]) -> dict[Path, list[str]]:
    """Resolved module source directory -> the module call names sourcing it."""
    out: dict[Path, list[str]] = {}
    for f in tf_files:
        text = cache.get(f)
        if text is None:
            text = read_text(f)
            cache[f] = text
        for m in MODULE_RE.finditer(text):
            body = text[m.end() - 1 : _brace_end(text, m.end() - 1) + 1]
            src = MODULE_SOURCE_RE.search(body)
            if src:
                d = (f.parent / src.group(1)).resolve()
                out.setdefault(d, []).append(m.group(1))
    return out


GATE_RE = re.compile(r"(?<![\w.])(?:var|local|module)\.[A-Za-z_][A-Za-z0-9_-]*")


def _names_token(token: str, text: str) -> bool:
    return re.search(r"(?<![\w.])" + re.escape(token) + r"(?!\w)", text) is not None


def check_instance_multiplicity(
    ledger: dict, tf_files: list[Path], cache: dict[Path, str], fails: list[str]
) -> None:
    """#8532 PR-2, Guard 2: a row keyed on a for_each/count block states which
    instances it covers, so one row cannot stand for several devices whose
    posture differs. A resolvable `for_each = var.<map>` is compared against the
    variable's default literal; every other multiplicity shape fails CLOSED
    unless the row names its gate, because a resolver that silently does not
    apply is the defect this check exists to close."""
    store_classes = ledger["store_classes"]
    index: dict[str, tuple[Path, str]] = {}
    for f in tf_files:
        text = cache.get(f)
        if text is None:
            text = read_text(f)
            cache[f] = text
        for t, n, block in extract_resource_blocks(text, f.name.endswith(".tf.json")):
            index.setdefault(f"{t}.{n}", (f, block))
    modules = module_calls_by_dir(tf_files, cache)
    for row in ledger["stores"]:
        sid = row["store"]
        hit = index.get(sid)
        parsed = parse_address(sid)
        if hit is None or not parsed or parsed[0] not in store_classes:
            continue
        f, block = hit
        meta = block_meta_args(block)
        mods = modules.get(f.parent.resolve(), [])
        mult = row.get("multiplicity")
        if not meta and not mods:
            # MUTATION-TARGET: MB-25 start (a singleton must not declare instances)
            if mult is not None:
                fails.append(
                    f"FAIL: {sid} declares multiplicity but its block is a "
                    "singleton -> delete the stale multiplicity"
                )
            # MUTATION-TARGET: MB-25 end
            continue
        fe = meta.get("for_each", "")
        keys = None
        if fe and "count" not in meta and not mods:
            # `for_each = var.X`, or any expression whose ONLY gate is var.X (a
            # `{ for k, v in var.X : k => v }` or `toset(keys(var.X))` wrapper),
            # is compared key for key: rewrapping the map must not turn a
            # checked row into an unchecked one.
            fe_gates = set(GATE_RE.findall(fe))
            if len(fe_gates) == 1:
                (g,) = fe_gates
                if g.startswith("var."):
                    keys = resolve_var_map_keys(f, g[4:], cache, tf_files)
        if keys is not None:
            # MUTATION-TARGET: MB-14 start (for_each over a var map: instances compared)
            want = ", ".join(sorted(keys))
            if mult is None:
                fails.append(
                    f"FAIL: {sid} is for_each = {fe} but declares no multiplicity "
                    f"-> add multiplicity.instances [{want}], and split the row "
                    "if their posture differs"
                )
            elif sorted(mult["instances"]) != sorted(keys):
                have = ", ".join(sorted(mult["instances"]))
                fails.append(
                    f"FAIL: {sid} covers instances [{have}] but {fe} declares "
                    f"[{want}] -> ledger every instance (a new key is a new device)"
                )
            # MUTATION-TARGET: MB-14 end
            continue
        if mods:
            desc = "instantiated by " + ", ".join(f"module.{m}" for m in mods)
            haystack = " ".join(f"module.{m}" for m in mods)
        elif "count" in meta:
            desc = f"count = {meta['count']}"
            haystack = meta["count"]
        else:
            desc = f"for_each = {fe}"
            haystack = fe
        gates = sorted(set(GATE_RE.findall(haystack)))
        reeval = (row["at_rest"].get("exception") or {}).get("reevaluate_when") or ""
        # MUTATION-TARGET: MB-24 start (unresolvable multiplicity fails closed)
        if mult is None:
            fails.append(
                f"FAIL: {sid} is {desc}, which this check cannot resolve -> "
                "declare multiplicity with instances: [] and name the gate "
                f"({', '.join(gates) or 'none found'}) in exception.reevaluate_when"
            )
        elif mult["instances"]:
            fails.append(
                f"FAIL: {sid} is {desc}, whose instances this check cannot "
                "verify, yet it declares a list -> declare instances: [] (an "
                "unverified list reads as coverage it does not have)"
            )
        elif not gates:
            fails.append(
                f"FAIL: {sid} is {desc}, which names no var./local./module. gate "
                "-> split the block into singletons, or gate it on a variable"
            )
        elif not any(_names_token(g, reeval) for g in gates):
            fails.append(
                f"FAIL: {sid} exception.reevaluate_when must name one of "
                f"{', '.join(gates)} -> the gate flipping is what reopens this row"
            )
        # MUTATION-TARGET: MB-24 end


# --- #8532 PR-3: record anchors (Guard 3) ----------------------------------

CLAUSE_TOKEN = "(encryption-posture ledger:"
# Any spelling a reader would take for a clause (case, extra whitespace or a
# line wrap, a non-ASCII hyphen) is found by this and must then parse EXACTLY,
# or it is reported malformed. A variant cannot hide from both checks.
CLAUSE_LOOSE_RE = re.compile(
    r"\(\s*encryption[\s\W_]{1,3}posture\s+ledger\s*:", re.IGNORECASE
)
CLAUSE_RE = re.compile(
    r"\(encryption-posture ledger: (?P<id>[A-Za-z0-9_.-]+) — at rest: "
    r"(?P<mech>[A-Za-z0-9_.:-]+)\)"
)
HEADING_RE = re.compile(r"^#{1,2}[ \t]+(.+?)[ \t]*$", re.MULTILINE)
FENCE_RE = re.compile(r"^[ \t]*(```|~~~)", re.MULTILINE)
CLAUSE_TEMPLATE = "(encryption-posture ledger: <store id> — at rest: <mechanism>)"


def _fenced_spans(text: str) -> list[tuple[int, int]]:
    marks = [m.start() for m in FENCE_RE.finditer(text)]
    return [(marks[i], marks[i + 1]) for i in range(0, len(marks) - 1, 2)]


@functools.lru_cache(maxsize=32)
def surface_sections(path_str: str, text: str) -> tuple[tuple[str | None, int, int], ...]:
    """[(heading text or None, start, end)]. A markdown surface is split at its
    H1/H2 headings, because one store is stated under several processing
    activities and each statement must agree on its own. An H3+ heading is a
    sub-part of its section, and a `#` line inside a fenced code block is code,
    not a heading. Any other surface is one section."""
    if not path_str.endswith(".md"):
        return ((None, 0, len(text)),)
    fences: list[tuple[int, int]] = []
    # MUTATION-TARGET: MB-32 start (a `#` line inside fenced code is not a heading)
    fences = _fenced_spans(text)
    # MUTATION-TARGET: MB-32 end
    heads = [
        h for h in HEADING_RE.finditer(text)
        if not any(a <= h.start() < b for a, b in fences)
    ]
    out: list[tuple[str | None, int, int]] = [
        (None, 0, heads[0].start() if heads else len(text))
    ]
    for i, h in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        out.append((h.group(1), h.start(), end))
    return tuple(out)


def _selector_matches(heading: str | None, sel: str) -> bool:
    """`Processing Activity 1` selects `Processing Activity 1 — Accounts`, never
    `Processing Activity 13`: the prefix must end at a non-alphanumeric."""
    if heading is None:
        return False
    return heading == sel or (
        heading.startswith(sel) and not heading[len(sel)].isalnum()
    )


def _section_label(path_str: str, heading: str | None) -> str:
    return f"{path_str}#{heading.split(' — ', 1)[0]}" if heading else path_str


def _clause_tokens(text: str, start: int, end: int) -> list[int]:
    """Offsets of every clause token in [start, end), minus the one documented
    template (CLAUSE_TEMPLATE, verbatim), which the register's maintenance
    section quotes. Anything else clause-shaped must parse."""
    return [
        m.start() for m in CLAUSE_LOOSE_RE.finditer(text, start, end)
        if not text.startswith(CLAUSE_TEMPLATE, m.start())
    ]


def _load_surfaces(
    ledger: dict, repo_root: Path, fails: list[str]
) -> dict[str, str]:
    texts: dict[str, str] = {}
    for sp in ledger.get("record_surfaces", []):
        try:
            path = (repo_root / sp).resolve()
            path.relative_to(repo_root.resolve())
        except (ValueError, OSError):
            path = None
        if path is None or not path.is_file():
            fails.append(
                f"FAIL: record_surfaces entry {sp} is not a file inside the "
                "repository -> fix the path or remove the entry"
            )
            continue
        texts[sp] = read_text(path)
    return texts


def check_records_resolve(
    ledger: dict, texts: dict[str, str], fails: list[str]
) -> None:
    """Forward: each stores[].records entry names one section of a record
    surface, which carries exactly one clause for this store, whose mechanism
    EQUALS the row's. Equality, not a regex over prose: an additive-only
    register holds superseded text beside current text."""
    surfaces = set(ledger.get("record_surfaces", []))
    for row in ledger["stores"]:
        sid = row["store"]
        mech = row["at_rest"]["mechanism"]
        for rec in row.get("records", []):
            path_str, _, sel = rec.partition("#")
            if path_str not in surfaces:
                fails.append(
                    f"FAIL: {sid} record {rec} names a file that is not in "
                    "record_surfaces -> add the file to record_surfaces, so the "
                    "reverse check reads it too"
                )
                continue
            text = texts.get(path_str)
            if text is None:
                continue  # reported by _load_surfaces
            if sel:
                hits = [
                    s for s in surface_sections(path_str, text)
                    if _selector_matches(s[0], sel)
                ]
                if len(hits) != 1:
                    fails.append(
                        f"FAIL: {sid} record {rec}: the section selector matches "
                        f"{len(hits)} headings -> it must select exactly one"
                    )
                    continue
                _h, st, en = hits[0]
            else:
                st, en = 0, len(text)
            clauses = [
                m for m in (CLAUSE_RE.match(text, i) for i in _clause_tokens(text, st, en))
                if m and m.group("id") == sid
            ]
            # MUTATION-TARGET: MB-26 start (one clause per store per section)
            if len(clauses) > 1:
                fails.append(
                    f"FAIL: clause for {sid} occurs {len(clauses)} times in {rec} "
                    "-> keep one; an amended cell supersedes in prose, not by a "
                    "second clause"
                )
                continue
            # MUTATION-TARGET: MB-26 end
            if not clauses:
                fails.append(
                    f"FAIL: no clause for {sid} in {rec} -> add "
                    f"(encryption-posture ledger: {sid} — at rest: {mech}) where "
                    "the section states this store's at-rest posture, or drop "
                    "the record"
                )
                continue
            # MUTATION-TARGET: MB-15 start (the record agrees with the row)
            if clauses[0].group("mech") != mech:
                fails.append(
                    f"FAIL: {sid} record {rec} states at rest: "
                    f"{clauses[0].group('mech')} but the row's mechanism is "
                    f"{mech} -> correct whichever one is wrong, in the same PR"
                )
            # MUTATION-TARGET: MB-15 end


def check_record_anchors_named(
    ledger: dict, texts: dict[str, str], fails: list[str]
) -> None:
    """Reverse: every clause in every record surface parses, names a live row,
    and sits in a section that row's records list. A renamed store cannot leave
    an orphan clause, and a clause cannot exist that no forward check reads."""
    rows = {s["store"]: s for s in ledger["stores"]}
    for sp, text in texts.items():
        for heading, st, en in surface_sections(sp, text):
            label = _section_label(sp, heading)
            for i in _clause_tokens(text, st, en):
                m = CLAUSE_RE.match(text, i)
                if not m:
                    # MUTATION-TARGET: MB-28 start (a clause-shaped token must parse)
                    fails.append(
                        f"FAIL: malformed encryption-posture clause in {label} "
                        "-> write it as (encryption-posture ledger: <store id> "
                        "— at rest: <mechanism>), with an em dash"
                    )
                    # MUTATION-TARGET: MB-28 end
                    continue
                sid = m.group("id")
                if sid not in rows:
                    # MUTATION-TARGET: MB-16 start (a clause must name a live row)
                    fails.append(
                        f"FAIL: {label} carries a clause for {sid}, which names "
                        "no stores[] row -> rename the clause with the store, or "
                        "remove it"
                    )
                    # MUTATION-TARGET: MB-16 end
                    continue
                recs = rows[sid].get("records", [])
                listed = any(
                    r == sp
                    or (r.startswith(sp + "#") and _selector_matches(heading, r[len(sp) + 1 :]))
                    for r in recs
                )
                # MUTATION-TARGET: MB-27 start (the row lists every section it is stated in)
                if not listed:
                    fails.append(
                        f"FAIL: {label} carries a clause for {sid}, which its "
                        f"row's records do not list -> add \"{label}\" to "
                        f"{sid}.records"
                    )
                # MUTATION-TARGET: MB-27 end


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


NOT_FOUND = "does not resolve (path/anchor not found)"

# Days before an exception's expires_on at which the sweep starts warning.
EXPIRY_WARN_DAYS = 14


def resolve_disclosed_as(
    value: str, repo_root: Path
) -> tuple[str | None, int, str | None]:
    """`path:anchor` -> (file text, anchor offset, None) when the anchor occurs
    EXACTLY once, else (None, -1, reason). Zero and many are distinct reasons:
    a moved anchor and an ambiguous one need different fixes. Hermetic:
    refuses to escape repo_root (h)."""
    if ":" not in value:
        return None, -1, NOT_FOUND
    path_str, anchor = value.split(":", 1)
    try:
        path = (repo_root / path_str).resolve()
        path.relative_to(repo_root.resolve())
    except (ValueError, OSError):
        return None, -1, NOT_FOUND
    if not path.is_file():
        return None, -1, NOT_FOUND
    text = read_text(path)
    n = text.count(anchor) if anchor else 0
    # MUTATION-TARGET: MB-19 start (anchor absent -> fail closed)
    if n == 0:
        return None, -1, "does not resolve (anchor not found in the file)"
    # MUTATION-TARGET: MB-19 end
    # MUTATION-TARGET: MB-18 start (anchor ambiguous -> fail closed)
    if n > 1:
        return None, -1, (
            f"is ambiguous (anchor occurs {n} times in {path_str}; it must "
            "occur exactly once)"
        )
    # MUTATION-TARGET: MB-18 end
    return text, text.find(anchor), None


def _anchor_window(text: str, idx: int) -> str:
    return text[max(0, idx - 300) : min(len(text), idx + 300)]


def _claim_sentence(text: str, idx: int, anchor: str) -> str:
    """The first sentence of the anchor's paragraph, anchor text removed.
    A paragraph ends at a blank line or at a line that starts a new list item,
    heading or table row."""
    start = text.rfind("\n", 0, max(idx, 0)) + 1
    lines = [text[start : (text.find("\n", idx) if text.find("\n", idx) != -1 else len(text))]]
    pos = start + len(lines[0]) + 1
    while pos < len(text):
        nxt_end = text.find("\n", pos)
        nxt = text[pos : nxt_end if nxt_end != -1 else len(text)]
        if not nxt.strip() or re.match(r"\s*(?:[-*+]\s|\d+[.)]\s|#|\|)", nxt):
            break
        lines.append(nxt)
        if nxt_end == -1:
            break
        pos = nxt_end + 1
    para = " ".join(line.strip() for line in lines).replace(anchor, " ", 1)
    para = para.replace("**", "")
    m = SENTENCE_END_RE.search(para)
    return para[: m.end()] if m else para


# #8527. A luks row's disclosure is judged on its CLAIM SENTENCE: the anchor's
# paragraph (continuation lines joined, so a hard wrap cannot split "not" from
# "encrypted"), anchor text removed, cut at the first sentence end. A denial
# in that sentence wins over a claim; a qualifier in a LATER sentence is
# allowed, so a disclosure can say what the encryption does not cover
# (#8624). Fails CLOSED on a claim phrased near a negation ("not only
# encrypted"): rephrase the disclosure rather than the predicate.
ENCRYPTION_CLAIM_RE = re.compile(r"\bLUKS\d*\b|\bencrypt(?:ed|ion)\b", re.IGNORECASE)
IN_TRANSIT_RE = re.compile(
    r"\bencrypt\w*\s+in[\s-]+transit\b|\bin[\s-]+transit\s+encrypt\w*"
    r"|\(encryption-posture ledger:[^)]*\)",
    re.IGNORECASE,
)
ENCRYPTION_DENIAL_RE = re.compile(
    r"\b(?:not|never|no|without|cannot|can't|isn't|aren't|wasn't|weren't|"
    r"doesn't|don't|didn't|lacks?|lacking)\b[\s\w,-]{0,40}?(?:encrypt|\bLUKS\d*\b)"
    r"|\bun-?encrypt"
    # "<claim word> [up to three words, never across and/but] is <negative>"
    r"|\b(?:encrypt\w*|LUKS\w*)(?:\s+(?!and\b|but\b|while\b|whereas\b)[\w-]+){0,3}"
    r"\s+(?:is|are|was|were)\s+"
    r"(?:absent|not|disabled|off|missing|unavailable|pending|planned|none)\b"
    r"|\bencryption(?:\s+at\s+rest)?\s*:\s*(?:none|no|n/?a|absent|off)\b"
    r"|\bplaintext\b"
    r"|\b(?:will\s+be|planned|pending|future|not\s+yet|eventually|soon)\b"
    r"[\s\w,-]{0,30}?(?:encrypt|\bLUKS\d*\b)",
    re.IGNORECASE,
)
SENTENCE_END_RE = re.compile(r"[.;!?](?=\s|$|\*)")


def check_disclosed_as_not_encrypted(
    store: str, ar: dict, repo_root: Path, fails: list[str]
) -> None:
    """R5: a plaintext-exception row whose disclosed_as citation resolves to
    text asserting encryption is exactly the `#6588` join gap."""
    disclosed = ar.get("disclosed_as", "")
    # MUTATION-TARGET: MB-11 start
    if not disclosed or disclosed == "not-publicly-claimed":
        return
    text, idx, err = resolve_disclosed_as(disclosed, repo_root)
    if text is None:
        # Fail CLOSED: a plaintext-exception naming a disclosure anchor that does
        # not resolve cannot be verified against reality -- the exact join gap R5
        # exists to close. A moved/bogus/ambiguous anchor must not pass silently.
        fails.append(
            f"FAIL: {store} disclosed_as {disclosed} {err} -> cannot verify "
            "the disclosure claim; fix the anchor or set disclosed_as: "
            "not-publicly-claimed"
        )
    elif re.search(r"LUKS|encrypt", _anchor_window(text, idx), re.IGNORECASE):
        fails.append(
            f"FAIL: {store} disclosed_as {disclosed} asserts encryption while "
            "mechanism is plaintext-exception -> correct the disclosure to "
            "match reality or fix the mechanism"
        )
    # MUTATION-TARGET: MB-11 end


def check_luks_disclosure(
    store: str, ar: dict, repo_root: Path, fails: list[str]
) -> None:
    """#8527: a luks row's disclosure is the public "encrypted at rest" claim,
    so its anchor line must CLAIM encryption and must not DENY it. Checked on
    the anchor line only (see ENCRYPTION_DENIAL_RE)."""
    disclosed = ar.get("disclosed_as", "")
    if not disclosed or disclosed == "not-publicly-claimed":
        return
    text, idx, err = resolve_disclosed_as(disclosed, repo_root)
    if text is None:
        fails.append(
            f"FAIL: {store} disclosed_as {disclosed} {err} -> cannot verify "
            "the encryption claim; fix the anchor or set disclosed_as: "
            "not-publicly-claimed"
        )
        return
    sentence = _claim_sentence(text, idx, disclosed.split(":", 1)[1])
    # MUTATION-TARGET: MB-20 start (luks disclosure must claim, never deny)
    if ENCRYPTION_DENIAL_RE.search(sentence):
        fails.append(
            f"FAIL: {store} disclosed_as {disclosed} denies encryption in its "
            "claim sentence while mechanism is luks -> correct the disclosure "
            "or the row (a qualifier belongs in a later sentence)"
        )
    elif not ENCRYPTION_CLAIM_RE.search(IN_TRANSIT_RE.sub(" ", sentence)):
        fails.append(
            f"FAIL: {store} disclosed_as {disclosed} does not claim encryption "
            "at rest in its claim sentence (the anchor text itself, and "
            "encryption in transit, do not count) -> re-anchor on the sentence "
            "that makes the claim"
        )
    # MUTATION-TARGET: MB-20 end


def check_provider_backups(tf_files: list[Path], cache: dict[Path, str], fails: list[str]) -> None:
    """`backups = true` on an hcloud_server makes Hetzner keep backup images of
    its unencrypted root disk: a derivative store that no ledger row names and
    no erasure path reaches (#8625). Refused until the ledger records it."""
    # MUTATION-TARGET: MB-33 start (provider backups are an unledgered store)
    for f in tf_files:
        text = _cached_read(f, cache)
        for t, n, block in extract_resource_blocks(text, f.name.endswith(".tf.json")):
            if t == "hcloud_server" and re.search(r"(?m)^\s*backups\s*=\s*true\b", block):
                fails.append(
                    f"FAIL: hcloud_server.{n} enables provider backups, a derivative "
                    "store of its unencrypted root disk with no ledger row -> ledger "
                    "the backup images (retention, Art. 17 reach) before enabling them"
                )
    # MUTATION-TARGET: MB-33 end


def check_class_conformance(ledger: dict, fails: list[str]) -> None:
    """A row at a store-class address carries that class's kind and one of its
    mechanisms. Without this, `store_classes.<type>.mechanisms` is decoration:
    a row could claim `luks` on a class that admits only plaintext-exception."""
    classes = ledger["store_classes"]
    for row in ledger["stores"]:
        parsed = parse_address(row["store"])
        if not parsed or parsed[0] not in classes:
            continue
        cls = classes[parsed[0]]
        mech = row["at_rest"]["mechanism"]
        # MUTATION-TARGET: MB-30 start (row conforms to its store class)
        if row["kind"] != cls["kind"]:
            fails.append(
                f"FAIL: {row['store']} kind {row['kind']} differs from its "
                f"store class kind {cls['kind']} -> use {cls['kind']}"
            )
        if not any(mech == m or mech.startswith(m + ":") for m in cls["mechanisms"]):
            fails.append(
                f"FAIL: {row['store']} mechanism {mech} is not one its store "
                f"class admits ({', '.join(cls['mechanisms'])}) -> add it to "
                "store_classes or correct the row"
            )
        # MUTATION-TARGET: MB-30 end


def check_at_rest(row: dict, today: date, repo_root: Path, fails: list[str]) -> None:
    store = row["store"]
    ar = row["at_rest"]
    mech = ar["mechanism"]
    does_not_defend_check(f"{store} at_rest", ar.get("does_not_defend", ""), fails)
    if mech == "luks":
        # The apparatus is resolved separately by check_luks_row().
        check_luks_disclosure(store, ar, repo_root, fails)
        return
    if mech.startswith("provider-managed:"):
        check_provider_managed(store, ar, today, fails)
        check_disclosure_resolves(store, ar.get("disclosed_as", ""), repo_root, fails)
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
        check_disclosure_resolves(store, ar.get("disclosed_as", ""), repo_root, fails)
        return
    fails.append(
        f"FAIL: {store} at_rest.mechanism '{mech}' is not a recognized "
        "mechanism -> use luks | provider-managed:<attestation> | "
        "app-layer-envelope:<scheme> | plaintext-exception"
    )


def check_disclosure_resolves(
    label: str, disclosed: str, repo_root: Path, fails: list[str]
) -> None:
    """Every `disclosed_as` naming a document must resolve exactly once, whatever
    the mechanism: a moved or bogus anchor on a row no content check reads is
    still a claim nobody can find."""
    if not disclosed or disclosed == "not-publicly-claimed":
        return
    text, _idx, err = resolve_disclosed_as(disclosed, repo_root)
    # MUTATION-TARGET: MB-31 start (every disclosure anchor must resolve)
    if text is None:
        fails.append(
            f"FAIL: {label} disclosed_as {disclosed} {err} -> fix the anchor or "
            "set disclosed_as: not-publicly-claimed"
        )
    # MUTATION-TARGET: MB-31 end


def check_connection(conn: dict, today: date, repo_root: Path, fails: list[str]) -> None:
    label = conn["connection"]
    it = conn["in_transit"]
    does_not_defend_check(f"{label} in_transit", it.get("does_not_defend", ""), fails)
    if it.get("cert_verification") != "off":
        check_disclosure_resolves(label, it.get("disclosed_as", ""), repo_root, fails)
    if it.get("cert_verification") == "off":
        check_exception_block(f"{label} in_transit", it, today, fails)
        disclosed = it.get("disclosed_as")
        if disclosed and disclosed != "not-publicly-claimed":
            text, idx, err = resolve_disclosed_as(disclosed, repo_root)
            if text is None:
                fails.append(
                    f"FAIL: {label} disclosed_as {disclosed} {err} -> cannot "
                    "verify the disclosure claim; fix the anchor or set "
                    "disclosed_as: not-publicly-claimed"
                )
            elif re.search(
                r"LUKS|encrypt|TLS|verifi", _anchor_window(text, idx), re.IGNORECASE
            ):
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
OPTIONAL_TOP = ("live_coverage_floor", "record_surfaces")


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
    return _unknown_keys(exc, EXCEPTION_KEYS, f"{prefix}.exception")


def _validate_store(s: dict, i: int) -> list[str]:
    errs = []
    prefix = f"stores[{i}]"
    if not isinstance(s, dict):
        return [f"{prefix} must be an object"]
    for f in ("store", "kind", "at_rest"):
        if f not in s:
            errs.append(f"{prefix} missing '{f}'")
    unexpected = sorted(set(s) - STORE_KEYS)
    if unexpected:
        errs.append(f"{prefix} has unexpected key(s) {unexpected}")
    if "records" in s and (
        not isinstance(s["records"], list)
        or not all(isinstance(x, str) and x for x in s["records"])
    ):
        errs.append(f"{prefix}.records must be a list of non-empty strings")
    if "multiplicity" in s:
        mu = s["multiplicity"]
        if (
            not isinstance(mu, dict)
            or set(mu) - {"instances"}
            or not isinstance(mu.get("instances"), list)
            or not all(isinstance(x, str) for x in mu["instances"])
        ):
            errs.append(f"{prefix}.multiplicity must be {{instances: [string]}}")
    if "kind" in s and s["kind"] not in STORE_KIND_ENUM:
        errs.append(f"{prefix}.kind invalid: {s.get('kind')!r}")
    if "at_rest" in s and isinstance(s["at_rest"], dict):
        ar = s["at_rest"]
        errs.extend(_unknown_keys(ar, AT_REST_KEYS, f"{prefix}.at_rest"))
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
            errs.extend(_unknown_keys(db, DEVICE_BINDING_KEYS, f"{prefix}.device_binding"))
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
    errs.extend(_unknown_keys(c, CONNECTION_KEYS, prefix))
    if "in_transit" in c and isinstance(c["in_transit"], dict):
        it = c["in_transit"]
        errs.extend(_unknown_keys(it, IN_TRANSIT_KEYS, f"{prefix}.in_transit"))
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
            errs.extend(_unknown_keys(v, STORE_CLASS_KEYS, f"store_classes.{t}"))
            if v["kind"] not in STORE_CLASS_KIND_ENUM:
                errs.append(f"store_classes.{t}.kind invalid: {v['kind']!r}")
            if not isinstance(v["mechanisms"], list) or not v["mechanisms"]:
                errs.append(f"store_classes.{t}.mechanisms must be a non-empty list")

    if "record_surfaces" in ledger and (
        not isinstance(ledger["record_surfaces"], list)
        or not all(isinstance(x, str) and x for x in ledger["record_surfaces"])
    ):
        errs.append("record_surfaces must be a list of non-empty strings")

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
    check_non_iac_identity(ledger, fails)
    check_store_id_accounted(ledger, tf_inventory, fails)
    check_instance_multiplicity(ledger, tf_files, cache, fails)
    check_class_conformance(ledger, fails)
    check_provider_backups(tf_files, cache, fails)
    check_live_coverage_floor(ledger, fails)

    luks_rows = [r for r in ledger["stores"] if r["at_rest"]["mechanism"] == "luks"]
    apparatus = scan_apparatus(infra_files, cache) if luks_rows else None
    mount_ev = scan_mount_evidence(infra_files, cache) if luks_rows else None
    for row in ledger["stores"]:
        mech = row["at_rest"]["mechanism"]
        if mech == "luks":
            check_luks_row(row, tf_files, infra_files, cache, fails, apparatus, mount_ev)
        check_at_rest(row, today, repo_root, fails)

    for conn in ledger["connections"]:
        check_connection(conn, today, repo_root, fails)

    texts = _load_surfaces(ledger, repo_root, fails)
    check_records_resolve(ledger, texts, fails)
    check_record_anchors_named(ledger, texts, fails)

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
