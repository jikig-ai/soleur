#!/usr/bin/env python3
"""Raw-inotify OPEN recorder for scripts/audit-suite-reads.sh (#9307).

Why not `inotifywait`: measured on the operator host (max_queued_events 16384), `inotifywait -m -r`
delivered exactly 16384 events for 17500 distinct opens and printed NO overflow record when the reader lags
(the reader was stopped while the opens happened; a free-running reader received every event), so a
recording could never be proven complete. This reader sees the kernel's IN_Q_OVERFLOW and reports it.

Usage: inotify-open-recorder.py ROOT [--exclude NAME]...
  --exclude NAME is a BARE name matched at ANY depth (a directory or file called NAME anywhere under ROOT is
  skipped), not a path. The audit passes `.git` and `node_modules`.

stdout, one record per line, flushed after every kernel read (paths are relative to ROOT, "." = ROOT):
  O<TAB>path   a file was opened
  D<TAB>path   a directory was opened (its listing was read)
  C<TAB>path   a directory was created (it is NOT watched: the verdict treats it as disqualifying)
  Q            IN_Q_OVERFLOW: events were dropped, the recording is incomplete
  X            an event whose path holds a TAB or NEWLINE (cannot be encoded)
  X<TAB>path   a watched directory was moved, deleted or its watch dropped: later opens under that name would
               be attributed to a stale path, so the window is unreliable (renames are NOT tracked)
Undecodable (non-UTF-8) names are written back byte-exact (surrogateescape), never dropped.
stderr: `Failed to watch <dir>` per directory that could not be watched, then `ready` once the initial
recursive watch walk is done (never printed, exit status 2, when not a single watch could be added).
SIGTERM / SIGINT end the process with status 0, and so does the death of the parent process (polled about
once a second), so an aborted audit never leaves a reader behind.
"""
import ctypes
import os
import select
import signal
import struct
import sys

IN_OPEN, IN_MOVED_FROM, IN_MOVED_TO, IN_CREATE = 0x20, 0x40, 0x80, 0x100
IN_DELETE_SELF, IN_MOVE_SELF, IN_Q_OVERFLOW, IN_IGNORED, IN_ISDIR = 0x400, 0x800, 0x4000, 0x8000, 0x40000000
IN_DONT_FOLLOW = 0x02000000
WATCH_MASK = IN_OPEN | IN_CREATE | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE_SELF | IN_MOVE_SELF | IN_DONT_FOLLOW


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: inotify-open-recorder.py ROOT [--exclude NAME]...\n")
        return 2
    root, skip = os.path.abspath(argv[1]), set()
    rest = argv[2:]
    while rest:
        if rest[0] != "--exclude" or len(rest) < 2:
            sys.stderr.write("usage: inotify-open-recorder.py ROOT [--exclude NAME]...\n")
            return 2
        skip.add(rest[1])
        rest = rest[2:]
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        fd = libc.inotify_init1(os.O_CLOEXEC)
    except (OSError, AttributeError) as exc:
        sys.stderr.write("inotify unavailable: %s\n" % exc)
        return 2
    if fd < 0:
        sys.stderr.write("inotify_init1 failed: errno %d\n" % ctypes.get_errno())
        return 2
    sys.stdout.reconfigure(errors="surrogateescape")
    wds = {}

    def watch(path):
        wd = libc.inotify_add_watch(fd, os.fsencode(path), WATCH_MASK)
        if wd < 0:
            sys.stderr.write("Failed to watch %s\n" % path)
        else:
            wds[wd] = os.path.relpath(path, root)

    def walk_error(exc):
        sys.stderr.write("Failed to watch %s\n" % exc.filename)

    for cur, dirs, _files in os.walk(root, onerror=walk_error):
        dirs[:] = [d for d in dirs if d not in skip]
        watch(cur)
    if not wds:
        sys.stderr.write("no directory could be watched under %s\n" % root)
        sys.stderr.flush()
        return 2
    sys.stderr.write("ready\n")
    sys.stderr.flush()

    def stop(*_):
        sys.stdout.flush()
        os._exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    parent = os.getppid()
    while True:
        if os.getppid() != parent:
            stop()
        if not select.select([fd], [], [], 1.0)[0]:
            continue
        buf = os.read(fd, 1 << 16)
        out, pos = [], 0
        while pos < len(buf):
            wd, mask, _cookie, ln = struct.unpack_from("iIII", buf, pos)
            name = os.fsdecode(buf[pos + 16:pos + 16 + ln].split(b"\0", 1)[0])
            pos += 16 + ln
            if mask & IN_Q_OVERFLOW:
                out.append("Q")
                continue
            base = wds.get(wd)
            if base is None:
                continue
            if mask & (IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED):
                # the watched directory itself vanished or moved: its name in `wds` is stale from now on
                out.append("X\t" + base)
                if mask & (IN_DELETE_SELF | IN_IGNORED):
                    del wds[wd]
                continue
            if name in skip:
                continue
            rel = os.path.normpath(os.path.join(base, name)) if name else base
            if "\t" in rel or "\n" in rel:
                out.append("X")
            elif mask & (IN_MOVED_FROM | IN_MOVED_TO):
                if mask & IN_ISDIR:
                    out.append("X\t" + rel)
            elif mask & IN_CREATE and mask & IN_ISDIR:
                out.append("C\t" + rel)
            elif mask & IN_OPEN:
                out.append(("D\t" if mask & IN_ISDIR else "O\t") + rel)
        if out:
            sys.stdout.write("\n".join(out) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
