"""Synthetic, network-free Config boundary tests. No acquired Config material."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import traceback
import unittest
from contextlib import redirect_stderr, redirect_stdout

import config_schema as schema
from prepare import Refused


def image():
    return {'architecture': 'amd64', 'os': 'linux',
            'rootfs': {'type': 'layers', 'diff_ids': ['sha256:' + 'a' * 64]}}


def raw(value):
    return json.dumps(value, ensure_ascii=True, separators=(',', ':')).encode('ascii')


# Enumerated independently of implementation definitions so omission is observable.
OPTIONAL = {
    (): {'created': '2026-10-20T12:13:14.123456789Z', 'author': 'Synthetic',
         'os.version': 'synthetic', 'os.features': ['synthetic'], 'variant': 'v1',
         'config': {}, 'history': []},
    ('config',): {'User': '1000', 'ExposedPorts': {'8080/tcp': {}},
                    'Env': ['SYNTHETIC=value'], 'Entrypoint': ['/synthetic'],
                    'Cmd': ['--synthetic'], 'Volumes': {'/synthetic': {}},
                    'WorkingDir': '/synthetic', 'Labels': {'example.synthetic': 'value'},
                    'StopSignal': 'SIGTERM', 'ArgsEscaped': False,
                    'Memory': 1, 'MemorySwap': -1, 'CpuShares': 0, 'Healthcheck': {}},
    ('history', 0): {'created': '2026-10-20T12:13:14Z', 'author': 'Synthetic',
                       'created_by': 'synthetic command', 'comment': 'Synthetic',
                       'empty_layer': False},
}


def with_field(path, name, value, *, omit=False):
    result = image()
    if path == ('config',):
        result['config'] = {}
    elif path == ('history', 0):
        result['history'] = [{}]
    obj = result
    for part in path:
        obj = obj[part]
    if not omit:
        obj[name] = value
    return result


class ConfigSchemaTests(unittest.TestCase):
    def accepted(self, value, *, layer_count=1, module=schema):
        self.assertIsNone(module.validate_config(raw(value), layer_count=layer_count))

    def refused(self, data, *, layer_count=1, module=schema):
        if not isinstance(data, bytes):
            data = raw(data)
        with self.assertRaises(Refused) as raised:
            module.validate_config(data, layer_count=layer_count)
        self.assertEqual(str(raised.exception), 'Config schema refused')
        self.assertIsNone(raised.exception.__cause__)
        self.assertIsNone(raised.exception.__context__)

    def test_minimum_and_no_output(self):
        self.accepted(image())
        value = image()
        value['rootfs']['diff_ids'] = []
        self.accepted(value, layer_count=0)

    def test_every_known_optional_missing_null_valid_and_invalid(self):
        for path, fields in OPTIONAL.items():
            for name, value in fields.items():
                with self.subTest(path=path, field=name):
                    self.accepted(with_field(path, name, None, omit=True))
                    self.accepted(with_field(path, name, None))
                    self.accepted(with_field(path, name, value))
                    # A number is invalid for every optional except reserved ints.
                    invalid = True if name in ('Memory', 'MemorySwap', 'CpuShares') else 19
                    self.refused(with_field(path, name, invalid))

    def test_required_fields_and_exact_platform(self):
        for field in ('os', 'architecture', 'rootfs'):
            for value in (None, 1, False, [], 'other'):
                doc = image()
                doc[field] = value
                self.refused(doc)
            doc = image()
            del doc[field]
            self.refused(doc)
        for field in ('type', 'diff_ids'):
            doc = image()
            del doc['rootfs'][field]
            self.refused(doc)
            for value in (None, False, 1, {}):
                doc = image()
                doc['rootfs'][field] = value
                self.refused(doc)
        doc = image()
        doc['rootfs']['type'] = 'other'
        self.refused(doc)

    def test_layer_count_and_digest_syntax(self):
        for count in (-1, True, 1.0, '1', None, 0, 2):
            self.refused(image(), layer_count=count)
        for value in (True, None, 'sha256:', 'sha256:xyz', 'sha256:' + 'a' * 63,
                      'SHA256:' + 'a' * 64, 'sha256:' + 'A' * 64, 'bad digest',
                      'sha256:' + 'a' * 64 + '\n'):
            doc = image()
            doc['rootfs']['diff_ids'] = [value]
            self.refused(doc)
        for digest in ('sha512:' + 'b' * 128, 'example-v1:abc123'):
            doc = image()
            doc['rootfs']['diff_ids'] = [digest]
            self.accepted(doc)

    def test_nested_known_collection_types_and_reserved_fields(self):
        for field in ('Env', 'Cmd', 'Entrypoint'):
            for value in ([None], [False], [{}], [1]):
                self.refused(with_field(('config',), field, value))
        self.refused(with_field((), 'os.features', [None]))
        for field in ('Volumes', 'ExposedPorts'):
            for value in ({'synthetic': None}, {'synthetic': []}, {'synthetic': {'x': 1}}):
                self.refused(with_field(('config',), field, value))
        for value in ({'x': None}, {'x': []}, {'': 3}):
            self.refused(with_field(('config',), 'Labels', value))
        for field in ('ArgsEscaped',):
            for value in (0, 1, 'true'):
                self.refused(with_field(('config',), field, value))
        for field in ('Memory', 'MemorySwap', 'CpuShares'):
            self.refused(with_field(('config',), field, 1.0))
            self.refused(with_field(('config',), field, False))
        self.refused(with_field(('history', 0), 'empty_layer', 1))
        self.refused(with_field((), 'history', [None]))
        self.refused(with_field((), 'history', [1]))

    def test_rfc3339_created_both_locations(self):
        for path in ((), ('history', 0)):
            for value in ('2024-02-29T23:59:59.123456789+23:59',
                          '2026-10-20t12:13:14z', '2016-12-31T23:59:60Z'):
                self.accepted(with_field(path, 'created', value))
            for value in ('', '2026-02-29T12:13:14Z', '2026-10-20',
                          '2026-10-20T24:00:00Z', '2026-10-20T12:13:61Z',
                          '2026-10-20T12:13:14+24:00', '2026-10-20T12:13:14Z\n'):
                self.refused(with_field(path, 'created', value))

    def test_strict_json_and_duplicate_keys_at_every_depth(self):
        good = raw(image())
        cases = [b'\xef\xbb\xbf' + good, b'\xff', good + b' {}', b'[]', b'null',
                 good.replace(b'"linux"', b'NaN'), good.replace(b'"linux"', b'Infinity'),
                 good[:-1] + b',"x":1e999}',
                 b'{"os":"linux","os":"linux"}',
                 good[:-1] + b',"x":{"key":1,"key":2}}',
                 good[:-1] + b',"x":[{"key":1,"ke\\u0079":2}]}',
                 good[:-1] + b',"x":"\\ud800"}',
                 good[:-1] + b',"\\udfff":1}', good + b'canary-secret']
        for value in cases:
            with self.subTest(data=value[:40]):
                self.refused(value)
        # JSON permits whitespace after one document.
        schema.validate_config(good + b' \t\n', layer_count=1)

    def test_unknown_extensions_and_unicode_are_inert_but_bounded(self):
        doc = image()
        doc['unknown'] = {'\u2603': ['\\\"[]{}', '\u00e9', None, True, 1.25]}
        doc['config'] = {'Healthcheck': {'Test': ['never executed']},
                         'unknown': {'anything': None}}
        doc['rootfs']['unknown'] = ['inert']
        doc['history'] = [{'unknown': {'nested': 'inert'}}]
        self.accepted(doc)
        doc = image()
        extension = 'leaf'
        for _ in range(31):
            extension = [extension]
        doc['unknown'] = extension
        self.accepted(doc)
        doc['unknown'] = [extension]
        self.refused(doc)
        self.refused(raw(image()) + b' ' * 2646)
        self.refused('not bytes')

    def test_nonbytes_and_error_canaries_have_no_decoder_context_or_output(self):
        canary = 'SYNTHETIC-SCHEMA-ERROR-CANARY'
        good = raw(image())
        samples = [bytearray(good), memoryview(good), good.decode(), None, {},
                   good[:-1] + b',"' + canary.encode() + b'":',
                   good[:-1] + b',"x":{"' + canary.encode() + b'":1,"' + canary.encode() + b'":2}}',
                   raw(with_field(('config',), 'Env', [canary, False]))]
        for sample in samples:
            with self.subTest(sample_type=type(sample).__name__):
                output = io.StringIO()
                with redirect_stdout(output), redirect_stderr(output):
                    try:
                        schema.validate_config(sample, layer_count=1)
                    except Refused as error:
                        formatted = ''.join(traceback.format_exception(error))
                        self.assertEqual(str(error), 'Config schema refused')
                        self.assertIsNone(error.__context__)
                        self.assertNotIn(canary, formatted)
                    else:
                        self.fail('invalid input unexpectedly accepted')
                self.assertEqual(output.getvalue(), '')

    def test_reference_closure_is_local_complete_and_deterministic(self):
        self.assertEqual(schema.CONTRACT, 'oci-config-v1.1.1-normative-null-v1')
        closure = schema.REFERENCE_CLOSURE
        self.assertEqual(set(closure['config']), set(OPTIONAL[('config',)]))
        self.assertEqual(set(closure['history']), set(OPTIONAL[('history', 0)]))
        self.assertEqual(set(closure['optional']), set(OPTIONAL[()]))
        expected = hashlib.sha256(json.dumps(closure, sort_keys=True, separators=(',', ':'),
                                            ensure_ascii=True).encode('ascii')).hexdigest()
        self.assertEqual(schema.REFERENCE_CLOSURE_SHA256, expected)
        self.assertEqual(schema.reference_closure_sha256(), expected)

    def test_mutations_remove_real_guards_and_are_killed_by_behavior(self):
        source_path = Path(schema.__file__)
        source = source_path.read_text()
        mutations = [
            ('bom', 'if raw.startswith(b"\\xef\\xbb\\xbf"):', 'if False:',
             b'\xef\xbb\xbf' + raw(image())),
            ('duplicate', 'if key in result:', 'if False:',
             raw(image())[:-1] + b',"x":{"a":1,"a":2}}'),
            ('depth', 'if depth > MAX_DEPTH:', 'if False:',
             raw(image())[:-1] + b',"x":' + b'[' * 33 + b'0' + b']' * 33 + b'}'),
            ('platform', 'if doc.get("os") != "linux" or doc.get("architecture") != "amd64":',
             'if False:', raw({**image(), 'os': 'other'})),
            ('count', 'if len(diff_ids) != layer_count:', 'if False:',
             raw({**image(), 'rootfs': {'type': 'layers', 'diff_ids': []}})),
            ('known-type', 'if not _matches(value, kind):', 'if False:',
             raw(with_field(('config',), 'Memory', True))),
            ('digest', 'if not _digest(value):', 'if False:',
             raw({**image(), 'rootfs': {'type': 'layers', 'diff_ids': ['bad']}})),
            ('bytes', 'len(raw) > MAX_BYTES', 'False', raw(image()) + b' ' * 2646),
            ('unicode', '_primitives(doc)', 'pass',
             raw(image())[:-1] + b',"x":"\\ud800"}'),
            ('finite-float', '_primitives(doc)', 'pass',
             raw(image())[:-1] + b',"x":1e999}'),
            ('nonfinite-literal', 'parse_constant=lambda _: _reject()',
             'parse_constant=lambda _: 0', raw(image())[:-1] + b',"x":NaN}'),
            ('utf8', "raw.decode('utf-8')", "raw.decode('utf-8', errors='replace')",
             raw(image())[:-1] + b',"x":"\xff"}'),
            ('trailing', 'doc = json.loads(text, object_pairs_hook=_object, parse_constant=lambda _: _reject())',
             'doc = json.JSONDecoder(object_pairs_hook=_object, parse_constant=lambda _: _reject()).raw_decode(text)[0]',
             raw(image()) + b' {}'),
            ('required-rootfs-type', "or rootfs.get('type') != 'layers'", 'or False',
             raw({**image(), 'rootfs': {'type': 'other', 'diff_ids': ['sha256:' + 'a' * 64]}})),
        ]
        with tempfile.TemporaryDirectory(prefix='synthetic-config-schema-') as directory:
            for index, (name, old, new, sample) in enumerate(mutations):
                with self.subTest(guard=name):
                    self.assertEqual(source.count(old), 1)
                    path = Path(directory) / f'mutant_{index}.py'
                    mutant = source.replace(old, new)
                    if name == 'bom':
                        # The decoder is an independent second BOM guard. Remove
                        # both in this coupled mutant; deleting only the explicit
                        # check is harmless because json.loads also refuses BOM.
                        mutant = mutant.replace("raw.decode('utf-8')", "raw.decode('utf-8-sig')")
                    path.write_text(mutant)
                    spec = importlib.util.spec_from_file_location(f'config_schema_mutant_{index}', path)
                    module = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(module)
                    # Original refuses; guard-removal mutant accepts this sample.
                    self.refused(sample)
                    self.assertIsNone(module.validate_config(sample, layer_count=1))

    def test_layer_count_type_guard_mutation(self):
        source = Path(schema.__file__).read_text()
        old = 'if type(layer_count) is not int or layer_count < 0:'
        self.assertEqual(source.count(old), 1)
        with tempfile.TemporaryDirectory(prefix='synthetic-config-schema-count-') as directory:
            path = Path(directory) / 'count_mutant.py'
            path.write_text(source.replace(old, 'if False:'))
            spec = importlib.util.spec_from_file_location('config_schema_count_mutant', path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            self.refused(image(), layer_count=True)
            self.assertIsNone(module.validate_config(raw(image()), layer_count=True))


if __name__ == '__main__':
    unittest.main()
