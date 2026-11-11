#!/usr/bin/env bash
# Read-only intake of a specs/<prefix>-<short-name>/ directory. Writes nothing.
exec python3 - "$@" <<'PY'
import errno
import hashlib
import os
import re
import stat
import sys

CAP = 1048576
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
CLOSED_NEVER = ("research.md", "data-model.md", "contracts", "quickstart.md")
MARKERS = ("--- side-evidence ---", "--- projected ---")
READ_NAMES = ("spec.md", "plan.md", "tasks.md")
LEAF_TS = re.compile(r"[0-9]{8}-[0-9]{6}-[A-Za-z0-9][A-Za-z0-9_-]*\Z")
LEAF_NUM = re.compile(r"[0-9]{3}-[A-Za-z0-9][A-Za-z0-9_-]*\Z")
ATX = re.compile(r"^#{1,6}[ \t]+(.+?)[ \t]*\Z")
USER_STORY = re.compile(r"user\s+story", re.IGNORECASE)
PRIORITY = re.compile(r"\bP[123]\b")


def refuse(reason):
    sys.stdout.write("intake: %s\n" % reason)
    raise SystemExit(1)


def valid_leaf(name):
    return LEAF_TS.fullmatch(name) is not None or LEAF_NUM.fullmatch(name) is not None


def resolve(cwd, dire):
    if dire.startswith("/"):
        return dire
    if not cwd:
        refuse("not-a-directory")
    if cwd.endswith("/"):
        return cwd + dire
    return cwd + "/" + dire


def parts_of(path):
    if not path.startswith("/"):
        refuse("not-a-directory")
    parts = [p for p in path.split("/") if p]
    if any(p in (".", "..") for p in parts):
        refuse("not-a-directory")
    if len(parts) < 2 or parts[-2] != "specs" or not valid_leaf(parts[-1]):
        refuse("not-a-directory")
    return parts


def open_dir_component(parent, name):
    """O_DIRECTORY plus O_NOFOLLOW reports a symlink as ENOTDIR.

    A second open without O_DIRECTORY still sets O_NOFOLLOW, so a symlink
    returns ELOOP and is not followed. A non-directory is not-a-directory.
    """
    try:
        return os.open(name, DIR_FLAGS, dir_fd=parent)
    except OSError as err:
        if err.errno == errno.ELOOP:
            refuse("symlink-escape")
        if err.errno != errno.ENOTDIR:
            refuse("not-a-directory")
    try:
        probed = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    except OSError as err:
        if err.errno == errno.ELOOP:
            refuse("symlink-escape")
        refuse("not-a-directory")
    os.close(probed)
    refuse("not-a-directory")


def walk(parts):
    try:
        fd = os.open("/", DIR_FLAGS)
    except OSError:
        refuse("not-a-directory")
    try:
        for name in parts:
            nxt = open_dir_component(fd, name)
            os.close(fd)
            fd = nxt
        owned = fd
        fd = -1
        return owned
    finally:
        if fd >= 0:
            os.close(fd)


def hostile(name):
    if name in MARKERS:
        return True
    if "\n" in name or "\r" in name or "\x7f" in name:
        return True
    if "\u2028" in name or "\u2029" in name:
        return True
    return False


def load_file(dir_fd, name):
    try:
        fd = os.open(name, FILE_FLAGS, dir_fd=dir_fd)
    except OSError as err:
        if err.errno == errno.ENOENT:
            return "absent", None
        if err.errno == errno.ELOOP:
            return "symlink-escape", None
        return "unreadable", None
    try:
        st = os.fstat(fd)
        if stat.S_ISLNK(st.st_mode):
            return "symlink-escape", None
        if not stat.S_ISREG(st.st_mode):
            return "not-a-regular-file", None
        if st.st_size > CAP:
            return "over-cap", None
        size = st.st_size
        data = b""
        while len(data) < size:
            chunk = os.read(fd, size - len(data))
            if not chunk:
                break
            data += chunk
        st2 = os.fstat(fd)
        if st2.st_size != size or len(data) != size:
            return "over-cap", None
        return "ok", data
    finally:
        os.close(fd)


def strip_controls(data):
    out = bytearray()
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if b == 0xE2 and i + 2 < n and data[i + 1] == 0x80 and data[i + 2] in (0xA8, 0xA9):
            i += 3
            continue
        if b < 32 and b not in (9, 10):
            i += 1
            continue
        if b == 127:
            i += 1
            continue
        out.append(b)
        i += 1
    return out.decode("utf-8", "replace")


def parse_sections(text):
    lines = text.split("\n")
    i = 0
    if i < len(lines) and lines[i] == "---":
        i += 1
        while i < len(lines) and lines[i] != "---":
            i += 1
        if i < len(lines) and lines[i] == "---":
            i += 1
    sections = []
    title = None
    body = []
    fence = False
    for line in lines[i:]:
        opener = line.startswith("```") or line.startswith("~~~")
        if fence:
            if opener:
                fence = False
            if title is not None:
                body.append(line)
            continue
        if opener:
            fence = True
            if title is not None:
                body.append(line)
            continue
        match = ATX.match(line)
        if match:
            if title is not None:
                sections.append((title, "\n".join(body)))
            title = match.group(1)
            body = []
            continue
        if title is not None:
            body.append(line)
    if title is not None:
        sections.append((title, "\n".join(body)))
    return sections


def classify(title, body):
    if "NEEDS CLARIFICATION" in body:
        return "unmapped", title
    folded = title.casefold().strip()
    pri = set(PRIORITY.findall(title))
    if USER_STORY.search(title):
        if "P1" in pri and "P2" not in pri and "P3" not in pri:
            return "fr", body.strip()
        return "unmapped", title
    if folded == "success criteria":
        return "goals", body.strip()
    if folded in ("out of scope", "non-goals", "exclusions"):
        return "nongoals", body.strip()
    if "P2" in pri or "P3" in pri:
        return "unmapped", title
    return "unmapped", title


def project(text):
    goals = []
    nongoals = []
    frs = []
    unmapped = []
    for title, body in parse_sections(text):
        kind, payload = classify(title, body)
        if kind == "goals" and payload:
            goals.append(payload)
        elif kind == "nongoals" and payload:
            nongoals.append(payload)
        elif kind == "fr" and payload:
            frs.append(payload)
        elif kind == "unmapped":
            unmapped.append(payload)
    moved = []
    if goals:
        moved.append("Goals")
    if nongoals:
        moved.append("Non-Goals")
    if frs:
        moved.append("Functional Requirements")
    body = "\n".join(
        [
            "---",
            "lane: cross-domain",
            "brand_survival_threshold: single-user incident",
            "---",
            "",
            "## Goals",
            "",
            "\n\n".join(goals),
            "",
            "## Non-Goals",
            "",
            "\n\n".join(nongoals),
            "",
            "## Functional Requirements",
            "",
            "\n\n".join(frs),
            "",
            "## Unmapped appendix",
            "",
            "\n".join("- %s" % name for name in unmapped),
            "",
            "Not a requirement. Not built from.",
            "",
        ]
    )
    return moved, unmapped, body


def digest_line(name, data):
    return "%s %s %s" % (name, len(data), hashlib.sha256(data).hexdigest())


def indent(text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    return "\n".join("    " + line for line in lines)


def side_block(name, data):
    if data is None:
        return "%s absent" % name
    return digest_line(name, data) + " not-requirements\n" + indent(strip_controls(data))


def emit(dir_fd, names, spec, plan, tasks):
    spec_text = strip_controls(spec)
    moved, unmapped, projected = project(spec_text)
    never = list(CLOSED_NEVER)
    for name in sorted(names):
        if name in READ_NAMES or name in CLOSED_NEVER:
            continue
        never.append(name)
    lines = [
        "moved: %s" % (", ".join(moved) if moved else "none"),
        "unmapped: %s" % ", ".join(unmapped),
        "never-read: %s" % ", ".join(never),
        digest_line("spec.md", spec),
        side_block("plan.md", plan).split("\n")[0] if plan is not None else "plan.md absent",
        side_block("tasks.md", tasks).split("\n")[0] if tasks is not None else "tasks.md absent",
        "--- side-evidence ---",
        side_block("plan.md", plan),
        side_block("tasks.md", tasks),
        "--- projected ---",
        projected,
    ]
    sys.stdout.write("\n".join(lines))
    if not projected.endswith("\n"):
        sys.stdout.write("\n")


def take(dir_fd, name, required):
    status, data = load_file(dir_fd, name)
    if status == "ok":
        return data
    if status == "absent" and not required:
        return None
    if status == "absent" and required:
        refuse("missing-spec")
    refuse(status)


def run(argv):
    if "--probe" in argv:
        sys.stdout.write("spec-kit-intake: ok\n")
        return
    cwd = None
    dire = None
    i = 0
    while i < len(argv):
        if argv[i] == "--cwd" and i + 1 < len(argv):
            cwd = argv[i + 1]
            i += 2
            continue
        if argv[i] == "--dir" and i + 1 < len(argv):
            dire = argv[i + 1]
            i += 2
            continue
        refuse("not-a-directory")
    if dire is None:
        refuse("not-a-directory")
    path = resolve(cwd, dire)
    parts = parts_of(path)
    dir_fd = walk(parts)
    try:
        names = []
        with os.scandir(dir_fd) as scan:
            for entry in scan:
                names.append(entry.name)
        for name in names:
            if hostile(name):
                refuse("unreadable")
        spec = take(dir_fd, "spec.md", True)
        plan = take(dir_fd, "plan.md", False)
        tasks = take(dir_fd, "tasks.md", False)
        emit(dir_fd, names, spec, plan, tasks)
    finally:
        os.close(dir_fd)


def main():
    try:
        run(sys.argv[1:])
    except SystemExit:
        raise
    except Exception:
        sys.stdout.write("intake: unreadable\n")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
PY
