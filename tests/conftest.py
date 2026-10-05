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

import atexit
import os
import secrets
import shutil
import signal
import stat as _stat
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

_SCRATCH_MARKER = ".soleur-owned"
_scratch_owned_root: str | None = None


def _pid_namespace() -> str:
    try:
        return os.readlink("/proc/self/ns/pid")
    except OSError:
        return "pid:[unknown]"


def write_scratch_marker(directory: str, pid: int | None = None) -> None:
    """Write ``<directory>/.soleur-owned`` atomically, in the format ``tc_marker_owner_pid`` parses.

    The python sibling of ``soleur_scratch_mark_owned`` (``scripts/lib/scratch-root.sh``) and of
    ``writeScratchMarker`` (``plugins/soleur/test/lib/scratch-session.ts``): ``pid=``, ``schema=1``,
    ``ns=``. Three writers, one parser -- ``tests/scripts/test-scratch-residue.sh`` pins that.
    """
    owner = os.getpid() if pid is None else pid
    tmp = os.path.join(directory, f"{_SCRATCH_MARKER}.{secrets.token_hex(4)}")
    # 0600 and exclusive, like the shell (`mktemp`) and TS (`mode: 0o600, flag: "wx"`) writers: a plain
    # open() would write 0644 under the usual umask and follow a planted symlink at the tmp name.
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(f"pid={owner}\nschema=1\nns={_pid_namespace()}\n")
        os.replace(tmp, os.path.join(directory, _SCRATCH_MARKER))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def is_adoptable_scratch_root(root: str) -> bool:
    """True when a live same-uid, same-pid-namespace process declared ``root`` its own scratch root."""
    try:
        if not root.startswith("/"):
            return False
        st = os.lstat(root)
        if not _stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
            return False
        marker = os.path.join(root, _SCRATCH_MARKER)
        ms = os.lstat(marker)
        if not _stat.S_ISREG(ms.st_mode) or ms.st_uid != os.getuid():
            return False
        with open(marker, encoding="utf-8") as fh:
            body = fh.read()
        ns = next((ln[3:] for ln in body.splitlines() if ln.startswith("ns=pid:[")), None)
        pid = next((ln[4:] for ln in body.splitlines() if ln.startswith("pid=")), None)
        mine = _pid_namespace()
        if not ns or not pid or not pid.isdigit() or mine == "pid:[unknown]" or ns != mine:
            return False
        if int(pid) <= 1:
            return False  # kill(0, 0) signals OUR OWN process group (always "alive"); pid 1 is init
        os.kill(int(pid), 0)  # ESRCH (dead) and EPERM (another uid) both mean: not the owner
        return True
    except (OSError, ValueError):
        return False


def _standard_bases() -> list[str]:
    """The bases Reaper 3 scans at depth 1: ``TMPFS_GUARD_SCRATCH_BASES`` (default ``/tmp /var/tmp``)."""
    raw = os.environ.get("TMPFS_GUARD_SCRATCH_BASES", "/tmp /var/tmp")
    return [b.rstrip("/") for b in raw.split() if b.startswith("/") and b.rstrip("/")]


def normalize_scratch_base(base: str) -> str:
    """``/tmp/<sub>/...`` -> ``/tmp`` (likewise per standard base); anything else is returned as is.

    Mirrors the normalisation in ``soleur_scratch_session_begin``: a root allocated beneath a subdir of
    a scanned base is at depth 2, which Reaper 3's ``-maxdepth 1`` enumeration never reaches.
    """
    b = base.rstrip("/") or base
    bases = _standard_bases()
    while any(b.startswith(s + "/") for s in bases):
        b = b[: b.rindex("/")]
    return b


def ensure_scratch_session() -> str:
    """Bind this process to a per-run ``soleur-run.<pid>.*`` scratch root and point TMPDIR at it (#9117).

    The python sibling of ``plugins/soleur/test/lib/scratch-session.ts``. Call it as a statement
    immediately BEFORE ``ensure_incident_sandbox()``: reversed, ``soleur-inc-*`` lands in the shared
    base and escapes the root (``.claude/hooks/incident-sandbox-coverage.test.sh`` asserts the order).

    A valid ``SOLEUR_SCRATCH_SESSION_ROOT`` (exists, same uid, marker from a live same-uid owner, pid > 1,
    in our pid namespace) is ADOPTED and never deleted; an invalid one is left untouched and a fresh
    root is created. Only a root this call created is removed -- at exit, and on SIGTERM (whose
    default action skips ``atexit``). ``SOLEUR_KEEP_SCRATCH=1`` keeps it for inspection. A TMPDIR
    beneath a standard scratch base is normalised up to that base (``normalize_scratch_base``). The stdlib
    caches ``tempfile.tempdir`` on first use, so it is set explicitly.
    """
    global _scratch_owned_root
    if _scratch_owned_root is not None:
        return _scratch_owned_root

    inherited = os.environ.get("SOLEUR_SCRATCH_SESSION_ROOT", "")
    base = tempfile.gettempdir()
    if inherited:
        if is_adoptable_scratch_root(inherited):
            os.environ["TMPDIR"] = inherited
            tempfile.tempdir = inherited
            return inherited
        if base.rstrip("/") == inherited.rstrip("/"):
            base = os.path.dirname(inherited.rstrip("/"))

    base = normalize_scratch_base(base)
    root = ""
    for _ in range(8):
        # 6 random bytes -> exactly 8 url-safe characters: the ``soleur-run.<pid>.XXXXXXXX`` schema.
        candidate = os.path.join(base, f"soleur-run.{os.getpid()}.{secrets.token_urlsafe(6)}")
        try:
            os.mkdir(candidate, 0o700)
        except FileExistsError:
            continue
        root = candidate
        break
    if not root:
        raise RuntimeError(f"scratch-session: could not allocate a root under {base}")
    try:
        write_scratch_marker(root)
    except OSError:
        shutil.rmtree(root, ignore_errors=True)
        raise

    _scratch_owned_root = root
    os.environ["TMPDIR"] = root
    os.environ["SOLEUR_SCRATCH_SESSION_ROOT"] = root
    os.environ["SOLEUR_SCRATCH_OWNER_PID"] = str(os.getpid())
    tempfile.tempdir = root

    creator = os.getpid()

    def _remove() -> None:
        # A forked child inherits this atexit handler and runs it on `sys.exit`; only the process that
        # CREATED the root may remove it.
        if os.getpid() != creator:
            return
        if os.environ.get("SOLEUR_KEEP_SCRATCH") != "1":
            shutil.rmtree(root, ignore_errors=True)

    atexit.register(_remove)
    try:
        if signal.getsignal(signal.SIGTERM) is signal.SIG_DFL:
            def _on_term(signum: int, _frame: object) -> None:
                raise SystemExit(128 + signum)  # unwinds through atexit; keeps the 128+n status

            signal.signal(signal.SIGTERM, _on_term)
    except ValueError:
        pass  # not the main thread: atexit still covers a normal exit
    return root


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
    ensure_scratch_session()  # BEFORE the sandbox: otherwise soleur-inc-* escapes the root (#9117)
    ensure_incident_sandbox()
