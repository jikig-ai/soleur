"""Synthetic namespace receipts refuse aliases and isolation declarations as proof."""
import unittest
from api_policy import Policy
from namespace import Refused, namespace_recipe, exact_dns_reply, tls_proxy_from_receipts
from prepare import browser_contract
import struct


class Namespace(unittest.TestCase):
    def setUp(self):
        self.policy = Policy('fixture', 'fixture-internal', '/tmp/fixture', {})
        self.policy.network_id = 'd' * 64
        self.policy.ids.add('b' * 64)
        self.policy.name_ids['supabase_kong_fixture'] = 'b' * 64
        self.network = {'Id': 'd' * 64, 'Name': 'fixture-internal', 'Driver': 'bridge',
                        'Internal': True, 'EnableIPv6': False,
                        'Labels': {'soleur.recovery.attempt': 'fixture'},
                        'IPAM': {'Config': [{'Subnet': '172.28.5.0/24'}]},
                        'Containers': {'b' * 64: {'IPv4Address': '172.28.5.3/24'}}}
        self.kong = {'Id': 'b' * 64, 'Name': '/supabase_kong_fixture',
                     'Config': {'Labels': {'soleur.recovery.attempt': 'fixture',
                                          'com.supabase.cli.project': 'fixture'}},
                     'NetworkSettings': {'Networks': {'fixture-internal': {
                         'NetworkID': 'd' * 64, 'IPAddress': '172.28.5.3'}}}}
        self.hostname = browser_contract()['url'].removeprefix('https://')

    def test_recipe_stays_pending_and_requires_live_registered_receipts(self):
        recipe = namespace_recipe(self.policy, self.network, self.kong, self.hostname)
        self.assertEqual(recipe['status'], 'prepared-operational-evidence-pending')
        self.assertFalse(recipe['execute_authorized'])
        self.assertEqual(recipe['upstream'], {'container_id': 'b' * 64, 'ip': '172.28.5.3', 'port': 8000})
        self.assertEqual(set(recipe['roles']), {'renderer', 'browser', 'tls', 'resolver'})
        for role in ('tls', 'resolver'):
            self.assertEqual(recipe['roles'][role]['namespace_sysctls'],
                             {'net.ipv4.ip_unprivileged_port_start': '0'})
            self.assertEqual(recipe['roles'][role]['user'], 'soleur')
            self.assertEqual(recipe['roles'][role]['cap_add'], [])
        self.assertIn('actual-dns-and-route-observations-in-each-role', recipe['required_evidence'])
        for changed in [None, {}, {**self.network, 'Internal': False},
                        {**self.network, 'Id': 'e' * 64}, {**self.network, 'Containers': {}}]:
            with self.assertRaises((Refused, RuntimeError)):
                namespace_recipe(self.policy, changed, self.kong, self.hostname)
        for changed in [{**self.kong, 'Id': 'e' * 64},
                        {**self.kong, 'NetworkSettings': {'Networks': {}}},
                        {**self.kong, 'NetworkSettings': {'Networks': {
                            **self.kong['NetworkSettings']['Networks'], 'foreign': {}}}}]:
            with self.assertRaises(Refused):
                namespace_recipe(self.policy, self.network, changed, self.hostname)

    def test_tls_proxy_uses_only_the_registered_kong_receipt_endpoint(self):
        network = {**self.network,
                   'Containers': {'b' * 64: {'IPv4Address': '172.28.5.4/24'}}}
        kong = {**self.kong,
                'NetworkSettings': {'Networks': {'fixture-internal': {
                    'NetworkID': 'd' * 64, 'IPAddress': '172.28.5.4'}}}}
        proxy = tls_proxy_from_receipts(self.policy, network, kong, self.hostname)

        self.assertEqual((proxy.upstream_ip, proxy.upstream_port), ('172.28.5.4', 8000))
        for target in ('/fixture?next=https://foreign.invalid/',
                       '/https://foreign.invalid:443/path',
                       '/%2F%2Fforeign.invalid:443/path'):
            admitted = proxy.admit('GET', target, [('Host', self.hostname)])
            self.assertEqual(admitted, target)
            self.assertEqual((proxy.upstream_ip, proxy.upstream_port), ('172.28.5.4', 8000))

        with self.assertRaises(Refused):
            tls_proxy_from_receipts(self.policy, network,
                                    {**self.kong, 'NetworkSettings': {'Networks': {}}},
                                    self.hostname)

    def packet(self, hostname, kind=1):
        labels = b''.join(bytes([len(part)]) + part.encode() for part in hostname.split('.')) + b'\0'
        return struct.pack('!6H', 7, 0x0100, 1, 0, 0, 0) + labels + struct.pack('!2H', kind, 1)

    def test_exact_resolver_never_forwards_or_resolves_other_names(self):
        request = self.packet(self.hostname)
        reply = exact_dns_reply(request, self.hostname, '172.28.5.4')
        self.assertEqual(struct.unpack('!6H', reply[:12]), (7, 0x8500, 1, 1, 0, 0))
        self.assertEqual(reply[-4:], bytes([172, 28, 5, 4]))
        for foreign in ['foreign.invalid', 'api.openai.com', 'db.fixture.internal']:
            reply = exact_dns_reply(self.packet(foreign), self.hostname, '172.28.5.4')
            self.assertEqual(struct.unpack('!H', reply[2:4])[0] & 15, 3)
        self.assertEqual(struct.unpack('!H', exact_dns_reply(self.packet(self.hostname, 28),
                         self.hostname, '172.28.5.4')[6:8])[0], 0)
        for packet in [b'', request + b'junk', request[:12] + b'\xc0\x0c' + request[-4:],
                       request[:4] + struct.pack('!H', 2) + request[6:]]:
            with self.assertRaises(Refused):
                exact_dns_reply(packet, self.hostname, '172.28.5.4')

    def test_browser_edns_is_bounded_and_never_adds_a_forwarder(self):
        request = self.packet(self.hostname)
        opt = b'\0' + struct.pack('!HHIH', 41, 1232, 0, 0)
        request = request[:10] + struct.pack('!H', 1) + request[12:] + opt
        reply = exact_dns_reply(request, self.hostname, '172.28.5.4')
        self.assertEqual(struct.unpack('!6H', reply[:12]), (7, 0x8500, 1, 1, 0, 0))
        self.assertEqual(reply[-4:], bytes([172, 28, 5, 4]))
        with self.assertRaises(Refused):
            exact_dns_reply(request[:-2] + b'\0\x01x', self.hostname, '172.28.5.4')


if __name__ == '__main__':
    unittest.main()
