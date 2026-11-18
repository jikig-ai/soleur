"""Unwired request shape validator; no identity, authority or persistence proof."""
import hashlib
import json
import re
import sys

COMMON = ['version','purpose','operation','generation','command','nonce','epoch','entry','vault_device','vault_inode','start_ms','deadline_ms','manifest_sha256','controller_sha256','caller_sha256','audience_sha256']
BIND = COMMON + ['reserve_sha256','receipt_device','receipt_inode']
_ABSENT = object()

def digest(raw):
    return hashlib.sha256(raw.encode('utf-8')).hexdigest()

def parse(raw):
    if type(raw) is not str or len(raw.encode('utf-8')) > 4096: raise ValueError()
    obj = json.loads(raw)
    if type(obj) is not dict or json.dumps(obj, separators=(',', ':'), ensure_ascii=True) != raw: raise ValueError()
    purpose = obj.get('purpose')
    if purpose not in ('reserve','bind') or list(obj) != (BIND if purpose == 'bind' else COMMON): raise ValueError()
    if obj['version'] != 'holder-reservation-v1' or obj['entry'] != 'receipt': raise ValueError()
    def valid_hex(value, length):
        return type(value) is str and re.fullmatch('[0-9a-f]{%d}' % length, value) is not None
    def decimal(value):
        return type(value) is str and re.fullmatch(r'(0|[1-9][0-9]{0,19})', value) is not None and int(value) <= 18446744073709551615
    if not all(valid_hex(obj[k],32) for k in ('operation','generation','command','nonce')): raise ValueError()
    if not all(valid_hex(obj[k],64) for k in ('manifest_sha256','controller_sha256','caller_sha256','audience_sha256')): raise ValueError()
    if not all(decimal(obj[k]) for k in ('epoch','vault_device','vault_inode','start_ms','deadline_ms')): raise ValueError()
    if not 0 < int(obj['deadline_ms']) - int(obj['start_ms']) <= 86400000: raise ValueError()
    if purpose == 'bind' and (not valid_hex(obj['reserve_sha256'],64) or not decimal(obj['receipt_device']) or not decimal(obj['receipt_inode'])): raise ValueError()
    return obj

def validate(raw, reserve_raw=_ABSENT):
    try:
        obj = parse(raw)
        if obj['purpose'] == 'bind':
            reserve = parse(reserve_raw)
            if reserve['purpose'] != 'reserve' or obj['reserve_sha256'] != digest(reserve_raw) or any(obj[k] != reserve[k] for k in COMMON if k != 'purpose'): raise ValueError()
        elif reserve_raw is not _ABSENT: raise ValueError()
        return digest(raw)
    except (ValueError, TypeError, KeyError, UnicodeError, OverflowError):
        return 'unknown'

if __name__ == '__main__':
    raw = sys.stdin.read(16385)
    if len(raw) > 16384: print('unknown')
    else:
        try:
            value = json.loads(raw)
            print(validate(*value) if type(value) is list and len(value) == 2 else validate(raw))
        except (ValueError, TypeError): print('unknown')
