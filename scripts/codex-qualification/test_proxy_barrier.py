"""Requests paused before dispatch cannot survive fatal/deadline transitions."""
import io
import json
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from api_policy import Policy
from api_proxy import Proxy
from fixture_roles import fixture_profiles

class Barrier(unittest.TestCase):
    def fixture(self, transition, at_dispatch=False):
        image = 'sha256:' + 'a' * 64
        p = Proxy.__new__(Proxy)
        p.policy = Policy('fixture', 'fixture-internal', '/tmp/fixture', {image:image},
                          role_profiles=fixture_profiles('fixture', {image:image}))
        p.policy.ids.add('b' * 64)
        p.policy.name_ids['supabase_db_fixture'] = 'b' * 64
        p.lock = threading.RLock()
        p.fatal = None
        p.cleanup_only = False
        p.deadline = time.monotonic() + 30
        p.backend = '/never-contacted'
        p.audit = []
        statuses, requests = [], []
        class Body(io.BytesIO):
            def read(self, size=-1):
                if not at_dispatch:
                    transition(p)
                return super().read(size)
        handler = SimpleNamespace(command='POST', path='/containers/' + 'b'*64 + '/start',
                    headers={'Content-Length':'2'}, rfile=Body(b'{}'), wfile=io.BytesIO(),
                    send_response=statuses.append, send_header=lambda *_: None,
                    end_headers=lambda: None, close_connection=False)
        class Backend:
            def __init__(self, *_):
                if at_dispatch:
                    transition(p)
            def request(self, *args, **kwargs): requests.append(args)
            def getresponse(self): raise AssertionError('Closed admission dispatched upstream')
            def close(self): pass
        with patch('api_proxy.UnixConnection', Backend):
            p.handle(handler)
        self.assertEqual(requests, [])
        self.assertEqual(statuses, [403])
        self.assertTrue(handler.close_connection)

    def test_fatal_during_body_read_cannot_dispatch(self):
        self.fixture(lambda p: setattr(p, 'fatal', 'synthetic prior failure'))

    def test_deadline_during_body_read_cannot_dispatch(self):
        self.fixture(lambda p: setattr(p, 'deadline', time.monotonic() - 1))

    def test_fatal_between_admission_and_dispatch_cannot_dispatch(self):
        self.fixture(lambda p: setattr(p, 'fatal', 'synthetic later failure'), at_dispatch=True)

if __name__ == '__main__':
    unittest.main()
