"""Disposable stdin/stdout fixture, not an authenticated service or vault.

Only fixed synthetic operation IDs, a fixed entry and fixed bytes are supported.
No request can supply a receipt body or path. There is no deletion command,
network, authorization, trusted clock, independent epoch or restoration proof.
Use only with a fresh empty disposable directory initialized by the test harness.
"""
import importlib.util
import json
import pathlib
import sys

spec = importlib.util.spec_from_file_location('vault_posix_fixture',
                                               pathlib.Path(__file__).with_name('holder-retention-vault-posix.py'))
vault = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vault)

OPERATION = 'synthetic-operation'
GENERATION = 'synthetic-generation'
MAX_LINE = 512
MAX_REQUESTS = 100
_ACTIONS = {'status', 'write_fixture', 'seal', 'tombstone'}


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate')
        result[key] = value
    return result


def reply(result):
    data = json.dumps({'result': result, 'authorizes_cleanup': False, 'authorizes_capture': False,
                       'deletion_verified': False}, separators=(',', ':'))
    sys.stdout.write(data + '\n')
    sys.stdout.flush()


def serve(path):
    with vault.SyntheticPosixVault(path, OPERATION, GENERATION) as instance:
        for _ in range(MAX_REQUESTS):
            raw = sys.stdin.buffer.readline(MAX_LINE + 1)
            if not raw:
                return
            if len(raw) > MAX_LINE or not raw.endswith(b'\n'):
                reply('refused')
                return
            try:
                request = json.loads(raw, object_pairs_hook=unique_pairs)
                if (not isinstance(request, dict) or set(request) != {'operation_id', 'generation', 'action'} or
                        request['operation_id'] != OPERATION or request['generation'] != GENERATION or
                        not isinstance(request['action'], str) or request['action'] not in _ACTIONS):
                    raise ValueError('invalid')
                action = request['action']
                if action == 'status':
                    result = instance.status()
                else:
                    getattr(instance, action)()
                    result = 'applied'
            except Exception:
                result = 'refused'
            reply(result)


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('invalid')
        serve(sys.argv[1])
    except Exception:
        try:
            reply('refused')
        except Exception:
            pass
