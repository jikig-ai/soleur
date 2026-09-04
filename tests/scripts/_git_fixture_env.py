"""Fixture git environment for the python test suites under ``tests/scripts``.

The python sibling of ``plugins/soleur/test/lib/git-fixture-env.ts``. See #7833 and
``knowledge-base/project/specs/feat-one-shot-7833-git-dir-beats-cwd/measurements.md``.

A test that builds a temporary git fixture and passes ``-C <dir>`` to every ``git`` call is still
not scoped to that fixture: when the test process inherits ``GIT_DIR`` / ``GIT_INDEX_FILE`` from a
git hook environment, the subprocess honours the environment over both its working directory and
``-C``. ``git init`` then initialises nothing and the fixture's writes land in the surrounding
repository.

EXCLUSION BY PREFIX, NEVER BY NAME LIST — the rule stated by
``plugins/soleur/test/lib/git-clean-env.ts`` and honoured here. An earlier revision of this file
carried a name list, and review found four omissions in one pass: ``GIT_TEMPLATE_DIR`` and
``GIT_EXEC_PATH`` (both proven to execute arbitrary code — ``git init`` copies template hooks in
before any config is consulted, so the config hardening below is no defence), ``GIT_SSH`` (which a
``GIT_SSH_COMMAND`` prefix rule structurally cannot match, the prefix being longer than the name),
and the ``GIT_TRACE`` family (which appends to an absolute path — a write outside the fixture, i.e.
the very property this module exists to establish). A list has to be complete against a vocabulary
git is free to grow; sweeping the namespace is complete by construction.
"""

from __future__ import annotations

import os
from pathlib import Path

#: The variables that redirect WHERE git reads and writes, or that make ``git init`` copy
#: executable content into the fixture.
#:
#: This is NOT used to build the environment — the namespace sweep does that, and a list could only
#: make it narrower. It exists because the TRIPWIRE and the entry-point scrub need a concrete set to
#: name: a tripwire cannot refuse every ``GIT_`` variable (``GIT_AUTHOR_NAME`` is harmless and a
#: hook exports it on every commit), and an ``unset`` needs words.
#:
#: Kept in lockstep with ``GIT_LOCATION_VARS`` in ``plugins/soleur/test/lib/git-fixture-env.ts``,
#: the shell list in ``plugins/soleur/test/test-helpers.sh``, and ``REQUIRED_SCRUB_VARS`` in
#: ``plugins/soleur/test/hook-git-env-coverage.test.sh``. That lockstep is ENFORCED by
#: ``plugins/soleur/test/git-env-list-parity.test.sh``, not asserted in a drift comment.
GIT_LOCATION_VARS = (
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

#: Execution vectors git consults whose names carry no ``GIT_`` prefix, so the sweep cannot reach
#: them by shape. ``SSH_ASKPASS`` is git's documented fallback when ``GIT_ASKPASS`` and
#: ``core.askPass`` are unset — an inherited value names a program git will run.
_NON_GIT_SCRUBBED_VARS = ("SSH_ASKPASS",)


def fixture_ceiling(fixture_dir: str | os.PathLike[str]) -> str:
    """Return the enforceable ``GIT_CEILING_DIRECTORIES`` value for ``fixture_dir``.

    The fixture's PARENT, resolved through symlinks. The fixture-dir spelling does not stop
    discovery escaping when git's cwd equals it (measurements.md §M-4).

    :raises ValueError: when no enforceable ceiling exists, rather than emitting one git ignores.
        ``GIT_CEILING_DIRECTORIES`` is ``:``-separated and git discards every non-absolute entry, so
        a colon anywhere in the path silently voids it; ``"/"`` is discarded for the same reason. A
        ceiling that looks set and does nothing is worse than none, because it reads as protection.
    """
    physical = Path(fixture_dir).resolve()
    ceiling = str(physical.parent)
    if not ceiling.startswith("/") or ceiling == "/" or ":" in ceiling:
        raise ValueError(
            f"no enforceable GIT_CEILING_DIRECTORIES for {fixture_dir!r} (computed {ceiling!r}). "
            'git ignores a ceiling that is "/" or non-absolute, and ":" splits it into fragments '
            "that are all ignored."
        )
    return ceiling


def git_fixture_env(fixture_dir: str | os.PathLike[str]) -> dict[str, str]:
    """Build the environment a fixture's ``git`` subprocess should run under.

    ``fixture_dir`` is required and there is deliberately no default. A default of
    ``tempfile.gettempdir()`` yields a ceiling of ``"/"``, which git ignores — so every caller that
    omitted the argument would silently lose the ceiling while the code read as if it had one.
    """
    ceiling = fixture_ceiling(fixture_dir)
    physical = Path(fixture_dir).resolve()

    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith("GIT_") and k not in _NON_GIT_SCRUBBED_VARS
    }

    env["GIT_CEILING_DIRECTORIES"] = ceiling
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    # GIT_CONFIG_GLOBAL replaces ~/.gitconfig and ~/.config/git/config but NOT the sibling XDG git
    # files: ~/.config/git/attributes and ~/.config/git/ignore are located independently of config
    # content, so a developer's `* text=auto` still rewrites fixture bytes.
    env["GIT_ATTR_NOSYSTEM"] = "1"
    env["XDG_CONFIG_HOME"] = str(physical / ".soleur-fixture-xdg")
    env["GIT_TERMINAL_PROMPT"] = "0"
    # Synthesized identity (`cq-test-fixtures-synthesized-only`). Required: the sweep removes
    # GIT_AUTHOR_*/GIT_COMMITTER_* and GIT_CONFIG_GLOBAL=os.devnull removes the developer's, so
    # without these the fixture's first commit fails `Author identity unknown`.
    env["GIT_AUTHOR_NAME"] = "Soleur Fixture"
    env["GIT_AUTHOR_EMAIL"] = "fixture@example.com"
    env["GIT_COMMITTER_NAME"] = "Soleur Fixture"
    env["GIT_COMMITTER_EMAIL"] = "fixture@example.com"
    return env
