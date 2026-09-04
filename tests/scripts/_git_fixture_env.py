"""Shared fixture git environment for the python test suites under ``tests/scripts``.

The python sibling of ``plugins/soleur/test/lib/git-fixture-env.ts``. See #7833 and
``knowledge-base/project/specs/feat-one-shot-7833-git-dir-beats-cwd/measurements.md``.

A test that builds a temporary git fixture and passes ``-C <dir>`` to every ``git`` call is still
not scoped to that fixture: when the test process inherits ``GIT_DIR`` / ``GIT_INDEX_FILE`` from a
git hook environment, the subprocess honours the environment over both its working directory and
``-C``. ``git init`` then initialises nothing and the fixture's writes land in the surrounding
repository.

This module exists rather than a per-file copy because the per-file fix is exactly what has already
been shown not to generalise: three independent private copies of the same idea existed in
``plugins/soleur/test/`` and a fourth suite in the same directory still reproduced the defect five
months after the first was fixed.
"""

from __future__ import annotations

import os
from pathlib import Path

#: Variables that redirect WHERE git reads and writes. Removing a subset is the defect, not a
#: partial fix: with ``GIT_DIR`` removed, an absolute ``GIT_INDEX_FILE`` alone still stages into
#: the victim's index while HEAD stays put (measurements.md §M-3).
GIT_LOCATION_VARS = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_NAMESPACE",
)

#: Variables that let an inherited environment inject config or run a command of its choosing.
_INJECTION_PREFIXES = (
    "GIT_SSH_COMMAND",
    "GIT_PROXY_COMMAND",
    "GIT_EXTERNAL_DIFF",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_KEY",
    "GIT_CONFIG_VALUE",
    "GIT_CONFIG_PARAMETERS",
)


def git_fixture_env(fixture_dir: str | os.PathLike[str]) -> dict[str, str]:
    """Build the environment a fixture's ``git`` subprocess should run under.

    ``fixture_dir``'s PARENT becomes ``GIT_CEILING_DIRECTORIES``: the fixture-dir spelling does not
    stop discovery escaping to the enclosing repository when git's cwd equals it (§M-4).

    A deny-list, not an allow-list. A read-only probe allow-list cannot be reused here, because a
    fixture ``git commit`` under one fails ``Author identity unknown`` (§M-7) -- so the ambient
    environment is kept, the dangerous families are removed, and a synthesized identity is pinned
    (``cq-test-fixtures-synthesized-only``).
    """
    env = {
        k: v
        for k, v in os.environ.items()
        if k not in GIT_LOCATION_VARS and not k.startswith(_INJECTION_PREFIXES)
    }

    parent = Path(fixture_dir).resolve().parent
    env["GIT_CEILING_DIRECTORIES"] = str(parent)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_AUTHOR_NAME"] = "Soleur Fixture"
    env["GIT_AUTHOR_EMAIL"] = "fixture@example.com"
    env["GIT_COMMITTER_NAME"] = "Soleur Fixture"
    env["GIT_COMMITTER_EMAIL"] = "fixture@example.com"
    return env
