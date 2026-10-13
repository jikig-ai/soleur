"""Bounded retained-byte collection from an already opened synthetic root.

No path-opening CLI, volume discovery, Docker or workload execution exists here.
The future adapter must prove root ownership and writer quiescence before giving
this helper a descriptor. Supplied bindings are compared, never authenticated.
Fixtures exercise only fresh scratch trees; collection emits hashes, never bytes.
"""
import copy
import hashlib
import os
from pathlib import PurePosixPath
import re
import stat
from prepare import Refused, canonical, require, sha


MAX_ENTRIES = 1024
MAX_BYTES = 16 * 1024**2
BINDING_FIELDS = {'attempt', 'source_sha', 'pairing_sha256', 'resource_kind',
                  'resource_id', 'root_device', 'root_inode', 'quiescence_id'}


def path(value):
    require(isinstance(value, str) and 0 < len(value) <= 2048 and
            all(ord(c) >= 32 and ord(c) not in (127, 0x2028, 0x2029) for c in value),
            'Unambiguous fixture path required')
    parsed = PurePosixPath(value)
    require(not parsed.is_absolute() and str(parsed) == value and
            all(part not in ('.', '..') for part in parsed.parts) and
            len(parsed.parts) <= 32, 'Fixture path traversal or depth refused')
    return value


def checked_binding(binding):
    require(isinstance(binding, dict) and set(binding) == BINDING_FIELDS,
            'Complete retained-root binding required')
    require(isinstance(binding['attempt'], str) and
            re.fullmatch(r'[a-zA-Z0-9_-]{1,128}', binding['attempt']), 'Bounded attempt identity required')
    for field, length in [('source_sha', 40), ('pairing_sha256', 64),
                          ('resource_id', 64), ('quiescence_id', 64)]:
        require(isinstance(binding[field], str) and
                re.fullmatch('[0-9a-f]{' + str(length) + '}', binding[field]), 'Missing retained identity')
    require(binding['resource_kind'] in ('workspace', 'storage'), 'Only synthetic retained scopes admitted')
    require(type(binding['root_device']) is int and binding['root_device'] >= 0 and
            type(binding['root_inode']) is int and binding['root_inode'] > 0, 'Root device/inode required')


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_nlink,
            info.st_mtime_ns, info.st_ctime_ns)


def read_regular(parent, name, info, remaining):
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size <= remaining,
            'Only bounded singly linked regular files admitted')
    descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    try:
        require(fingerprint(os.fstat(descriptor)) == fingerprint(info), 'File changed before descriptor read')
        digest, size = hashlib.sha256(), 0
        while True:
            block = os.read(descriptor, min(65536, remaining - size + 1))
            if not block:
                break
            size += len(block)
            require(size <= remaining, 'Retained byte budget exceeded')
            digest.update(block)
        require(size == info.st_size and fingerprint(os.fstat(descriptor)) == fingerprint(info),
                'File changed during descriptor read')
        return size, digest.hexdigest()
    finally:
        os.close(descriptor)


def snapshot(root_fd, binding, expected_paths, *, max_entries=MAX_ENTRIES, max_bytes=MAX_BYTES):
    """Collect complete inventory; binding validity never grants root admission."""
    checked_binding(binding)
    require(type(max_entries) is int and 0 < max_entries <= MAX_ENTRIES and
            type(max_bytes) is int and 0 < max_bytes <= MAX_BYTES, 'Bounded collection budget required')
    require(isinstance(expected_paths, list) and len(expected_paths) <= max_entries,
            'Bounded synthetic fixture census required')
    expected = [path(value) for value in expected_paths]
    require(len(set(expected)) == len(expected), 'Duplicate fixture path refused')
    root = os.fstat(root_fd)
    require(stat.S_ISDIR(root.st_mode) and root.st_dev == binding['root_device'] and
            root.st_ino == binding['root_inode'], 'Retained root descriptor differs from binding')
    entries, total = [], 0

    def visit(descriptor, prefix, depth):
        nonlocal total
        require(depth <= 32, 'Retained directory depth exceeded')
        initial = os.fstat(descriptor)
        names = sorted(os.listdir(descriptor))
        require(len(entries) + len(names) <= max_entries, 'Retained entry budget exceeded')
        for name in names:
            relative = path(prefix + name)
            require(relative in expected, 'Retained inventory differs from synthetic census')
            info = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            require(info.st_dev == root.st_dev, 'Retained mount escape refused')
            row = {'path': relative, 'mode': stat.S_IMODE(info.st_mode)}
            if stat.S_ISDIR(info.st_mode):
                row.update(type='directory', bytes=0, sha256=None)
                entries.append(row)
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
                try:
                    require(fingerprint(os.fstat(child)) == fingerprint(info), 'Directory identity changed')
                    visit(child, relative + '/', depth + 1)
                finally:
                    os.close(child)
            else:
                size, digest = read_regular(descriptor, name, info, max_bytes - total)
                total += size
                row.update(type='file', bytes=size, sha256=digest)
                entries.append(row)
            require(fingerprint(os.stat(name, dir_fd=descriptor, follow_symlinks=False)) == fingerprint(info),
                    'Retained entry replaced during collection')
            require(len(entries) <= max_entries, 'Retained entry budget exceeded')
        require(names == sorted(os.listdir(descriptor)) and
                fingerprint(os.fstat(descriptor)) == fingerprint(initial), 'Retained directory changed during collection')

    try:
        visit(root_fd, '', 0)
    except OSError:
        raise Refused('Retained filesystem could not be measured') from None
    require({row['path'] for row in entries} == set(expected), 'Retained census has missing entries')
    entries.sort(key=lambda row: row['path'])
    return {'binding': copy.deepcopy(binding), 'entries': entries,
            'fixture_census_sha256': sha(canonical(sorted(expected))),
            'manifest_sha256': sha(canonical(entries)), 'total_bytes': total,
            'root_mode': stat.S_IMODE(root.st_mode),
            'ownership_verified': False, 'quiescence_verified': False,
            'issuer_authenticated': False, 'execute_authorized': False}


def checked_manifest(manifest):
    require(isinstance(manifest, dict) and set(manifest) == {'binding', 'entries',
            'fixture_census_sha256', 'manifest_sha256', 'total_bytes', 'root_mode', 'ownership_verified',
            'quiescence_verified', 'issuer_authenticated', 'execute_authorized'}, 'Complete manifest required')
    checked_binding(manifest['binding'])
    require(all(manifest[key] is False for key in ('ownership_verified', 'quiescence_verified',
            'issuer_authenticated', 'execute_authorized')), 'Manifest cannot attest ownership or authorization')
    entries = manifest['entries']
    require(isinstance(entries, list) and len(entries) <= MAX_ENTRIES, 'Bounded complete inventory required')
    require(type(manifest['root_mode']) is int and 0 <= manifest['root_mode'] <= 0o7777,
            'Retained root mode required')
    paths, total = [], 0
    for row in entries:
        require(isinstance(row, dict) and set(row) == {'path', 'mode', 'type', 'bytes', 'sha256'},
                'Exact retained entry fields required')
        paths.append(path(row['path']))
        require(type(row['mode']) is int and 0 <= row['mode'] <= 0o7777 and
                type(row['bytes']) is int and 0 <= row['bytes'] <= MAX_BYTES, 'Malformed retained metadata')
        require((row['type'] == 'directory' and row['bytes'] == 0 and row['sha256'] is None) or
                (row['type'] == 'file' and isinstance(row['sha256'], str) and
                 re.fullmatch('[0-9a-f]{64}', row['sha256'])), 'Ambiguous retained file type or hash')
        total += row['bytes']
    directories = {row['path'] for row in entries if row['type'] == 'directory'}
    require(all(str(parent) in directories for name in paths
                for parent in PurePosixPath(name).parents if str(parent) != '.'),
            'Retained directory census is incomplete')
    require(paths == sorted(set(paths)) and total <= MAX_BYTES and
            type(manifest['total_bytes']) is int and manifest['total_bytes'] == total and
            manifest['fixture_census_sha256'] == sha(canonical(paths)) and
            manifest['manifest_sha256'] == sha(canonical(entries)), 'Retained manifest integrity differs')
    return entries


def compare(before, after, erased_paths=()):
    """Require exact retention, optionally subtracting an exact scoped erasure."""
    prior, current = checked_manifest(before), checked_manifest(after)
    stable = BINDING_FIELDS - {'quiescence_id'}
    require(all(before['binding'][key] == after['binding'][key] for key in stable),
            'Retained resource/source binding changed')
    require(before['root_mode'] == after['root_mode'], 'Retained root mode changed')
    require(isinstance(erased_paths, (list, tuple)), 'Exact erased path list required')
    removed = [path(value) for value in erased_paths]
    require(len(set(removed)) == len(removed) and set(removed) <= {row['path'] for row in prior},
            'Erasure scope is absent or duplicated')
    require([row for row in prior if row['path'] not in removed] == current,
            'Retained entries changed outside exact erasure scope')
    return {'status': 'structurally-matched', 'erased_paths': removed,
            'ownership_verified': False, 'quiescence_verified': False,
            'issuer_authenticated': False, 'execute_authorized': False}
