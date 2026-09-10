"""Git-location tripwire for the python test arm (#7833).

Guard 3 registers a prelude per runner RUNTIME: a `bunfig.toml` preload for bun, a `globalSetup`
for vitest, and a sourced prelude in `plugins/soleur/test/test-helpers.sh` for shell. The python
arm had none, which falsified the deferral's central claim — that with the entry-point scrub and
the tripwire in force, no fixture suite can observe a hostile environment in any reachable
invocation. A direct `python3 -m unittest tests.scripts.<suite>` from a shell holding GIT_DIR had
no layer at all.

pytest imports this automatically. `scripts/test-all.sh` drives these suites through
`python3 -m unittest`, which does NOT, so `tests/scripts/_git_fixture_env.py` imports it too — that
module is imported by every python suite that spawns git, which is exactly the population at risk.
"""

from __future__ import annotations

import os
import sys
import tempfile

#: Kept in lockstep with the other four copies; enforced by
#: ``plugins/soleur/test/git-env-list-parity.test.sh``.
_GIT_LOCATION_VARS = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_NAMESPACE",
    "GIT_TEMPLATE_DIR",
    "GIT_EXEC_PATH",
)

GIT_TRIPWIRE_EXIT_CODE = 97


def assert_no_inherited_git_location(runner: str = "python") -> None:
    """Abort the process if any git-location variable was inherited at start.

    Fails rather than scrubbing, for the same reason as the other three arms: scrubbing in-process
    would hide a broken entry point, and the next suite that does not import this module would
    still be exposed while nobody learned which invocation lacked the scrub.
    """
    found = [k for k in _GIT_LOCATION_VARS if os.environ.get(k)]
    if not found:
        return
    if os.environ.get("SOLEUR_GIT_TRIPWIRE_ALLOW") == "1":
        sys.stderr.write(
            f"[git-tripwire] DISARMED by SOLEUR_GIT_TRIPWIRE_ALLOW=1 in {runner}; "
            f"inherited: {' '.join(found)}\n"
        )
        return
    detail = "\n".join(f"  {k}={os.environ[k]}" for k in found)
    sys.stderr.write(
        f"\nFATAL: {runner} started with an inherited git-location environment.\n\n"
        "These override BOTH a subprocess's working directory and `git -C`, so a fixture that\n"
        "builds a temp repository would write into the repository they point at instead:\n\n"
        f"{detail}\n\n"
        "Fix the ENTRY POINT that started this runner, by prefixing it with:\n\n"
        f"  unset {' '.join(found)} && <runner>\n\n"
    )
    raise SystemExit(GIT_TRIPWIRE_EXIT_CODE)


def ensure_incident_sandbox() -> str:
    """Point incident telemetry at a scratch root, unless the caller already chose one (#7853).

    The python sibling of ``plugins/soleur/test/lib/incident-sandbox.ts`` and of
    ``.claude/hooks/lib/test-incident-sandbox.sh``. Registered at the same chokepoint as the
    tripwire above, and for the same reason: a python suite that spawns a hook or a gate script
    otherwise appends fabricated rows to the operator real
    ``.claude/.rule-incidents.jsonl``.

    Idempotent and non-destructive -- a root already chosen by an outer runner or by the suite
    itself wins.

    Raises:
        RuntimeError: if no sandbox can be created. Refusal is the only safe direction. Leaving the
            variable unset does not degrade to a lesser sandbox, it restores the operator real
            ledger; and an EMPTY value is indistinguishable from unset to ``_incidents_repo_root()``
            while still reading as "set" to a static check for the variable name.
    """
    existing = os.environ.get("INCIDENTS_REPO_ROOT", "")
    if existing.startswith("/"):
        return existing

    root = tempfile.mkdtemp(prefix="soleur-inc-")
    if not root.startswith("/"):
        raise RuntimeError(f"incident-sandbox: refusing a non-absolute sandbox path {root!r}")
    # Create the `.claude/` parent rather than relying on the emitter, matching the bash and TS
    # siblings so all three spellings leave the same shape on disk.
    os.makedirs(os.path.join(root, ".claude"), exist_ok=True)

    os.environ["INCIDENTS_REPO_ROOT"] = root
    # A second name a suite may read to find the rows its own emitter wrote, without knowing this
    # module internals.
    os.environ["SOLEUR_TEST_INCIDENT_ROOT"] = root
    return root


def pytest_configure() -> None:
    """pytest's own entry point.

    A module-level call here would fire on ANY import of this module — including the import from
    ``tests/scripts/_git_fixture_env.py``, which reaches it under ``python3 -m unittest`` — and
    would then label every abort "pytest" regardless of the runner that actually started. The
    unittest arm calls the function directly with its own label.
    """
    assert_no_inherited_git_location("pytest")
    ensure_incident_sandbox()
