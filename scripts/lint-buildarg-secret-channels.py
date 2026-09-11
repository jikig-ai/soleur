#!/usr/bin/env python3
"""Fail when a non-public credential can reach a PUBLISHED build artifact (#7389).

WHY THIS EXISTS. `SENTRY_IAC_AUTH_TOKEN` was passed to `docker/build-push-action` as a
build-arg. BuildKit records build-args verbatim in the SLSA provenance attestation that
is published next to the image, so the token sat in cleartext in the attestation of
every `ghcr.io/jikig-ai/soleur-web-platform` release, and `crane copy` mirrored that
layer into the zot registry as well.

WHY THE OBVIOUS MITIGATIONS DO NOT COVER IT. Two were believed to and do not:

  * `mode=min` on `cache-to` is about the gha LAYER CACHE. It says nothing about the
    provenance attestation, which is a different channel entirely.
  * Stage-scoping ("the ARG is only consumed in the builder stage, never the runner")
    is a real property and also irrelevant here: BuildKit records the frontend request
    attributes regardless of which stage consumes them.

Measured on 2026-08-10 against BuildKit v0.31.2 AND v0.32.2, exporting OCI locally:
provenance `mode=min` records ZERO build-args; `mode=max` records all of them. The
published attestation had them, so the release was emitting max. The reason is that
`docker/build-push-action` chooses the default by REPOSITORY VISIBILITY
(`src/context.ts`, `getAttestArgs`): a private repo gets `mode=min,inline-only=true`, a
public repo gets `mode=max`. `jikig-ai/soleur` is public, and the workflow never pinned
`provenance:`, so it inherited max.

That is exactly why this gate keys on the CHANNEL and not on the mode. A mode setting is
configuration that drifts -- flipping the repo to private and back, or a future action
default, silently changes it. Keeping credentials out of build-args is a property of the
build definition, which is what a gate can hold.

THE RULE IS A CONJUNCTION. A build-arg key is admitted only if:
    (allowlisted by `prefix:` AND not credential-shaped)  OR  (allowlisted by `exact:`)
Anything else is a finding. A prefix-only allowlist is not sufficient: measured,
`BUILD_DEPLOY_TOKEN` and `NEXT_PUBLIC_SECRET_KEY` are both admitted by a prefix-only
rule, and both are exactly the shape this gate exists to stop.

WHY THE GATE FLAGS THE KEY, NOT THE VALUE. In the source sweep there is no value to
inspect -- `FOO_TOKEN=${{ secrets.BAR }}` is a template. Keying on the secret NAME would
miss it, because the arg key and the secret name need not match. So the source sweep
flags the KEY regardless of the value expression, and the `--provenance` mode adds a
value-layer scan for the built artifact.

MODES
  (default)      Source sweep over the repo: workflow build-args, Dockerfile
                 ARG/ENV/LABEL, and `--build-arg` in shell scripts. Also asserts that
                 every `push: true` build-push-action workflow invokes this gate.
  --provenance F Scan a `docker buildx imagetools inspect --format '{{json .}}'`
                 capture: the request-attribute map plus the image config.
  --shape-check K  Exit 0 if K is not credential-shaped, 1 if it is. Unit surface for
                 the anchoring tests.

EXIT CODES
  0  clean
  1  violation(s), or could-not-inspect (fail closed)
  2  argument / environment error

NEVER PRINTS A VALUE. Findings carry key names and value LENGTHS only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Iterable

try:
    import yaml
except ImportError:  # pragma: no cover - environment error
    print("ERROR: pyyaml is required", file=sys.stderr)
    sys.exit(2)

DEFAULT_ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 "buildarg-key-allowlist.txt")

# Anchored on token boundaries so the segments match as WORDS, not substrings.
# Anchoring is the whole design: `PATH` must not match `PAT`, `AUTHOR` must not match
# `AUTH`, `NEXTAUTH_URL` must not match `AUTH`. Each of those is a real key that would
# otherwise be flagged, turning the gate into noise nobody keeps.
CREDENTIAL_SHAPE = re.compile(
    r"(^|_)(TOKEN|SECRET|KEY|PASSWORD|PASSWD|CREDENTIALS?|AUTH|PAT)($|_)|_DSN$"
)

# The positive control. Its presence proves the sweep parsed a real build-args block
# rather than matching an empty set -- a scanner that silently scans nothing reports
# clean forever, which is the failure mode this whole gate exists to prevent.
POSITIVE_CONTROL = "BUILD_SHA"

GATE_SCRIPT_NAME = "lint-buildarg-secret-channels.py"


def is_credential_shaped(key: str) -> bool:
    return CREDENTIAL_SHAPE.search(key.upper()) is not None


def load_allowlist(path: str) -> tuple[set[str], list[str]]:
    exact: set[str] = set()
    prefixes: list[str] = []
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("exact:"):
                    exact.add(line[len("exact:"):].strip())
                elif line.startswith("prefix:"):
                    prefixes.append(line[len("prefix:"):].strip())
                else:
                    print(f"ERROR: unparseable allowlist line: {line!r}", file=sys.stderr)
                    sys.exit(2)
    except OSError as exc:
        print(f"ERROR: cannot read allowlist {path}: {exc}", file=sys.stderr)
        sys.exit(2)
    if not exact and not prefixes:
        print(f"ERROR: allowlist {path} is empty", file=sys.stderr)
        sys.exit(2)
    return exact, prefixes


def key_admitted(key: str, exact: set[str], prefixes: Iterable[str]) -> bool:
    """The conjunction. See the module docstring."""
    if key in exact:
        return True
    for pre in prefixes:
        if key.startswith(pre):
            return not is_credential_shaped(key)
    return False


# --------------------------------------------------------------------------
# Source sweep
# --------------------------------------------------------------------------

def _walk(root: str, subdir: str, suffixes: tuple[str, ...],
          names: tuple[str, ...] = ()) -> list[str]:
    out: list[str] = []
    base = os.path.join(root, subdir) if subdir else root
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames
                       if d not in {".git", "node_modules", ".next", ".worktrees"}]
        for fn in filenames:
            if fn.endswith(suffixes) or fn in names or any(
                fn.startswith(n) for n in names if n.endswith("*")
            ):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)


def sweep(root: str, exact: set[str], prefixes: list[str]) -> tuple[list[str], dict]:
    findings: list[str] = []
    counts = {"workflows": 0, "dockerfiles": 0, "shell": 0}

    workflows = _walk(root, os.path.join(".github", "workflows"), (".yml", ".yaml"))
    counts["workflows"] = len(workflows)

    # Dockerfile / Dockerfile.* / Containerfile* / *.Dockerfile
    dockerfiles = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if d not in {".git", "node_modules", ".next", ".worktrees"}]
        for fn in filenames:
            if fn == "Dockerfile" or fn.startswith("Dockerfile.") \
               or fn.startswith("Containerfile") or fn.endswith(".Dockerfile"):
                dockerfiles.append(os.path.join(dirpath, fn))
    dockerfiles.sort()
    counts["dockerfiles"] = len(dockerfiles)

    shell = _walk(root, "", (".sh",))
    counts["shell"] = len(shell)

    saw_positive_control = False
    saw_any_buildargs_block = False

    for wf in workflows:
        try:
            with open(wf, encoding="utf-8") as fh:
                text = fh.read()
            doc = yaml.safe_load(text)
        except Exception as exc:
            findings.append(f"{wf}: unparseable workflow ({exc}) -- failing closed")
            continue
        if not isinstance(doc, dict):
            continue
        rel = os.path.relpath(wf, root)

        # Anchor on the SYNTACTIC invocation -- a step whose `run:` body actually calls
        # the script -- never on a bare substring of the file. A whole-file `in text`
        # check is satisfied by a COMMENT that merely names the script, and this very
        # workflow carries such a comment explaining the secret-mount rule. Measured:
        # with the substring check, deleting the real gate step left the sweep GREEN
        # because the comment kept certifying it. The guard would then have been
        # enforced by prose about itself.
        invokes_gate = any(
            GATE_SCRIPT_NAME in str(_s.get("run") or "")
            for _j in (doc.get("jobs") or {}).values() if isinstance(_j, dict)
            for _s in (_j.get("steps") or []) if isinstance(_s, dict)
        )

        for job in (doc.get("jobs") or {}).values():
            if not isinstance(job, dict):
                continue
            for step in (job.get("steps") or []):
                if not isinstance(step, dict):
                    continue
                uses = str(step.get("uses") or "")
                with_ = step.get("with") or {}
                if not isinstance(with_, dict):
                    continue

                if "build-push-action" in uses:
                    push = with_.get("push")
                    pushes = str(push).lower() in {"true", "1"} or (
                        isinstance(push, str) and "${{" in push
                    )
                    # `provenance:` is read with an explicit sentinel, NOT `or ""`.
                    # YAML `provenance: false` is the boolean False, which is falsy --
                    # `or ""` would silently turn "attestation disabled" into "unset"
                    # and flag the one configuration that is strictly safer than
                    # mode=min. Disabling the attestation closes the channel outright.
                    raw_prov = with_.get("provenance", None)
                    prov = "" if raw_prov is None else str(raw_prov).strip()
                    prov_disabled = prov.lower() in {"false", "0"}
                    prov_pinned_min = prov == "mode=min"

                    if pushes and not prov_disabled and not invokes_gate:
                        findings.append(
                            f"{rel}: a `push: true` build-push-action step publishes a "
                            f"provenance attestation but this workflow never invokes "
                            f"{GATE_SCRIPT_NAME}; the attestation would be ungated"
                        )
                    if pushes and not prov_disabled and not prov_pinned_min:
                        findings.append(
                            f"{rel}: build-push-action pushes without `provenance` pinned "
                            f"by value (found {prov!r}; want `mode=min` or `false`). The "
                            f"action defaults to mode=max on a PUBLIC repo, which records "
                            f"every build-arg."
                        )

                ba = with_.get("build-args")
                if ba is None:
                    continue
                saw_any_buildargs_block = True
                lines = ba.splitlines() if isinstance(ba, str) else list(ba)
                for line in lines:
                    line = str(line).strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    key = line.split("=", 1)[0].strip()
                    if key == POSITIVE_CONTROL:
                        saw_positive_control = True
                    if not key_admitted(key, exact, prefixes):
                        why = ("credential-shaped" if is_credential_shaped(key)
                               else "not on the allowlist")
                        findings.append(
                            f"{rel}: build-arg `{key}` is {why}. Build-args are recorded "
                            f"in the published provenance attestation -- use a BuildKit "
                            f"secret mount (`secrets:` + `--mount=type=secret`) instead."
                        )

    for df in dockerfiles:
        rel = os.path.relpath(df, root)
        try:
            with open(df, encoding="utf-8") as fh:
                body = fh.read()
        except OSError as exc:
            findings.append(f"{rel}: unreadable ({exc}) -- failing closed")
            continue
        for m in re.finditer(r"^[ \t]*ARG[ \t]+([A-Za-z_][A-Za-z0-9_]*)", body, re.M):
            k = m.group(1)
            # Full conjunction, not shape alone: an `exact:` allowlist entry is the
            # reviewed escape hatch for a key that is credential-SHAPED but public by
            # design (NEXT_PUBLIC_SUPABASE_ANON_KEY, NEXT_PUBLIC_SENTRY_DSN, ...).
            if not key_admitted(k, exact, prefixes) and is_credential_shaped(k):
                findings.append(
                    f"{rel}: `ARG {k}` is credential-shaped. An ARG is recorded in the "
                    f"provenance attestation when passed as a build-arg -- mount it as a "
                    f"BuildKit secret instead."
                )
        for m in re.finditer(r"^[ \t]*ENV[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t=]", body, re.M):
            k = m.group(1)
            if not key_admitted(k, exact, prefixes) and is_credential_shaped(k):
                findings.append(
                    f"{rel}: `ENV {k}` is credential-shaped and is baked into the "
                    f"published image config."
                )
        for m in re.finditer(r"^[ \t]*LABEL[ \t]+([^\s=]+)=", body, re.M):
            k = m.group(1).strip('"').replace(".", "_").replace("-", "_")
            if is_credential_shaped(k):
                findings.append(
                    f"{rel}: `LABEL {m.group(1)}` is credential-shaped and is published "
                    f"in the image manifest."
                )

    for sh in shell:
        rel = os.path.relpath(sh, root)
        try:
            with open(sh, encoding="utf-8") as fh:
                body = fh.read()
        except OSError:
            continue
        for m in re.finditer(r"--build-arg[ \t=]+[\"']?([A-Za-z_][A-Za-z0-9_]*)=", body):
            k = m.group(1)
            if not key_admitted(k, exact, prefixes):
                why = ("credential-shaped" if is_credential_shaped(k)
                       else "not on the allowlist")
                findings.append(
                    f"{rel}: `--build-arg {k}=` is {why}; build-args are recorded in the "
                    f"published provenance attestation."
                )

    # Empty scan sets and a missing positive control both mean the sweep is not looking
    # where it thinks it is. Silence must never read as clean.
    for name, n in counts.items():
        if n == 0:
            findings.append(
                f"scan set `{name}` matched ZERO files -- the sweep is misconfigured; "
                f"refusing to report clean."
            )
    if saw_any_buildargs_block and not saw_positive_control:
        findings.append(
            f"positive control `{POSITIVE_CONTROL}` absent from every scanned build-args "
            f"block -- cannot confirm the sweep parsed them."
        )

    return findings, counts


# --------------------------------------------------------------------------
# Provenance / built-artifact scan
# --------------------------------------------------------------------------

def scan_provenance(path: str, exact: set[str], prefixes: list[str]) -> tuple[str, list[str]]:
    """Returns (verdict, findings). verdict in {clean, could-not-inspect, violation}."""
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except Exception as exc:
        return "could-not-inspect", [f"{path}: unparseable ({exc}) -- failing closed"]

    if not isinstance(doc, dict):
        return "could-not-inspect", [f"{path}: top level is not an object -- failing closed"]

    # TWO positive controls. A degraded 200 that serialized `null`, or a capture that
    # fetched only one of the two, must fail closed -- `null` has length 0 and would
    # otherwise read as "no args, clean", which is precisely backwards.
    slsa = doc.get("SLSA")
    image = doc.get("Image")
    if not isinstance(slsa, dict):
        return "could-not-inspect", [
            f"{path}: `.SLSA` positive control absent or null -- cannot prove the "
            f"attestation was read; failing closed."
        ]
    if not isinstance(image, dict):
        return "could-not-inspect", [
            f"{path}: `.Image` positive control absent or null -- the image-config "
            f"channel (Env/Labels/history) is mode-independent and was not inspected; "
            f"failing closed."
        ]

    findings: list[str] = []

    args = (slsa.get("buildDefinition", {})
                .get("externalParameters", {})
                .get("request", {})
                .get("args"))
    if args is None:
        args = {}
    if not isinstance(args, dict):
        return "could-not-inspect", [f"{path}: request.args is not a map -- failing closed"]

    # Deny-by-default over the WHOLE request-attribute map, not just `build-arg:`.
    for attr, val in sorted(args.items()):
        key = attr.split(":", 1)[1] if ":" in attr else attr
        vlen = len(val) if isinstance(val, str) else -1
        if not key_admitted(key, exact, prefixes):
            why = ("credential-shaped" if is_credential_shaped(key)
                   else "not on the allowlist")
            findings.append(
                f"provenance request attribute `{attr}` is {why} (value_len={vlen})"
            )

    cfg = image.get("config") or {}
    for entry in (cfg.get("Env") or []):
        k = str(entry).split("=", 1)[0]
        if is_credential_shaped(k):
            vlen = len(str(entry).split("=", 1)[1]) if "=" in str(entry) else -1
            findings.append(f"image config Env `{k}` is credential-shaped (value_len={vlen})")
    for k in (cfg.get("Labels") or {}):
        norm = str(k).replace(".", "_").replace("-", "_")
        if is_credential_shaped(norm):
            findings.append(f"image config Label `{k}` is credential-shaped")
    for h in (image.get("history") or []):
        cc = str((h or {}).get("created_by") or "")
        for m in re.finditer(r"([A-Za-z_][A-Za-z0-9_]*)=", cc):
            if is_credential_shaped(m.group(1)):
                findings.append(
                    f"image history layer sets credential-shaped `{m.group(1)}`"
                )
                break

    return ("violation" if findings else "clean"), findings


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".")
    ap.add_argument("--allowlist", default=DEFAULT_ALLOWLIST)
    ap.add_argument("--provenance")
    ap.add_argument("--shape-check")
    ap.add_argument("--break-glass-reason", default="",
                    help="Record a reason to downgrade a violation to a warning. "
                         "Never silent: the reason is echoed and the run is annotated.")
    args = ap.parse_args(argv)

    if args.shape_check is not None:
        shaped = is_credential_shaped(args.shape_check)
        print(f"{args.shape_check}: credential_shaped={shaped}")
        return 1 if shaped else 0

    exact, prefixes = load_allowlist(args.allowlist)

    if args.provenance:
        verdict, findings = scan_provenance(args.provenance, exact, prefixes)
        print(f"verdict={verdict}")
        for f in findings:
            print(f"  {f}")
        if verdict == "clean":
            return 0
        if args.break_glass_reason:
            print(f"::warning::BREAK-GLASS accepted, reason: {args.break_glass_reason}")
            return 0
        return 1

    findings, counts = sweep(args.root, exact, prefixes)
    print("scanned: " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    verdict = "violation" if findings else "clean"
    print(f"verdict={verdict}")
    for f in findings:
        print(f"  {f}")
    if not findings:
        return 0
    if args.break_glass_reason:
        print(f"::warning::BREAK-GLASS accepted, reason: {args.break_glass_reason}")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
