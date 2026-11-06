import importlib.util
import hashlib
import json
import pathlib
import unittest

path = pathlib.Path(__file__).with_name('holder-reservation-builder.py')
spec = importlib.util.spec_from_file_location('builder', path)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ReservationBuilderTest(unittest.TestCase):
    def test_identity_digest_vectors(self):
        def digest(value):
            return hashlib.sha256(json.dumps(value, separators=(',', ':'), ensure_ascii=True).encode('ascii')).hexdigest()
        self.assertEqual(digest(['holder-reservation-caller-v1', 'https://accounts.google.com', '123456789012345678901']), 'ba1e0c0da0c66440c777a211da590ae00cc60b4a8ec271dfec1d55ac207e4b67')
        self.assertEqual(digest(['holder-reservation-audience-v1', 'https://synthetic.invalid/authority']), '81f0d9c57f9980a78a86813208641ed6868515052f9e43a13542eb51e8810dd8')

    def setUp(self):
        self.fields = dict(operation='a'*32, generation='b'*32, command='c'*32,
                           nonce='d'*32, epoch=2**64-1, vault_device=2**53+1,
                           vault_inode=2**64-1, start_ms=100, deadline_ms=200,
                           manifest_sha256='e'*64, controller_sha256='f'*64,
                           caller_sha256='1'*64, audience_sha256='2'*64)

    def test_frozen_cross_runtime_vectors(self):
        reserve = builder.reserve(self.fields)
        bind = builder.bind(reserve, 2**53+1, 2**64-1)
        expected = ('{"version":"holder-reservation-v1","purpose":"reserve","operation":"' + 'a'*32 +
                    '","generation":"' + 'b'*32 + '","command":"' + 'c'*32 + '","nonce":"' + 'd'*32 +
                    '","epoch":"18446744073709551615","entry":"receipt","vault_device":"9007199254740993",'
                    '"vault_inode":"18446744073709551615","start_ms":"100","deadline_ms":"200",'
                    '"manifest_sha256":"' + 'e'*64 + '","controller_sha256":"' + 'f'*64 +
                    '","caller_sha256":"' + '1'*64 + '","audience_sha256":"' + '2'*64 + '"}')
        self.assertEqual(reserve, expected)
        self.assertEqual(bind, expected.replace('"purpose":"reserve"', '"purpose":"bind"')[:-1] +
                         ',"reserve_sha256":"9345cbeb4843da0bf7cb8933e334fe51ad1c7e232842eb4924c5438acca188dd",'
                         '"receipt_device":"9007199254740993","receipt_inode":"18446744073709551615"}')
        self.assertEqual(builder.contract.validate(reserve), '9345cbeb4843da0bf7cb8933e334fe51ad1c7e232842eb4924c5438acca188dd')
        self.assertEqual(builder.contract.validate(bind, reserve), 'e81b5af819189fcf80414fb934be1ac871cd3e299d8ba1a038923872f3b5ac4a')

    def test_rejects_noninteger_or_out_of_range_identifiers_and_extra_fields(self):
        for value in (True, -1, 2**64, '1', 1.0):
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.reserve({**self.fields, 'vault_device': value})
            with self.subTest(bind=value), self.assertRaises(ValueError):
                builder.bind(builder.reserve(self.fields), value, 2)
        with self.assertRaises(ValueError): builder.reserve({**self.fields, 'extra': 'x'})

    def test_rejects_invalid_or_changed_reserve(self):
        for raw in ('{}', builder.reserve(self.fields) + ' '):
            with self.assertRaises(ValueError): builder.bind(raw, 1, 2)
        with self.assertRaises(ValueError): builder.reserve({**self.fields, 'deadline_ms': 100})

    def test_rejects_untrusted_shapes_before_serialization(self):
        cyclic = []
        cyclic.append(cyclic)
        for field in ('operation', 'generation', 'command', 'nonce', 'manifest_sha256',
                      'controller_sha256', 'caller_sha256', 'audience_sha256'):
            for value in (object(), cyclic, 'a' * 100000, 'x' * len(self.fields[field])):
                with self.subTest(field=field, value=type(value)), self.assertRaises(ValueError):
                    builder.reserve({**self.fields, field: value})
        missing = dict(self.fields)
        del missing['operation']
        with self.assertRaises(ValueError): builder.reserve(missing)


if __name__ == '__main__': unittest.main()
