"""Pure recipes and exact-name DNS for the existing owned Docker controller.

No Docker invocation, namespace creation, service launch or trust installation
occurs on import. Registered/revalidated receipts establish preparation inputs;
they do not prove actual namespace DNS, route isolation or application login.
"""
import ipaddress
import socket
import struct
from local_tls import Refused, checked_hostname, material_recipe, private_ipv4, require


def namespace_recipe(policy, network_receipt, kong_receipt, hostname):
    checked_hostname(hostname)
    require(isinstance(network_receipt, dict) and isinstance(kong_receipt, dict), 'Observed owned receipts required')
    policy.verify_network(network_receipt)
    kong_name = 'supabase_kong_' + policy.project
    kong_id = policy.own(kong_name)
    require(kong_receipt.get('Id') == kong_id and kong_receipt.get('Name') == '/' + kong_name,
            'Kong receipt is outside registered inventory')
    labels = kong_receipt.get('Config', {}).get('Labels', {})
    require(labels.get('soleur.recovery.attempt') == policy.project and
            labels.get('com.supabase.cli.project') == policy.project, 'Kong ownership labels differ')
    networks = kong_receipt.get('NetworkSettings', {}).get('Networks', {})
    require(set(networks) == {policy.network}, 'Kong has a foreign/missing network')
    endpoint = networks[policy.network]
    require(endpoint.get('NetworkID') == policy.network_id, 'Kong network ID differs')
    upstream = private_ipv4(endpoint.get('IPAddress'))
    observed = network_receipt.get('Containers', {}).get(kong_id, {}).get('IPv4Address')
    require(isinstance(observed, str) and observed.split('/')[0] == upstream, 'Network/Kong endpoint receipts differ')
    subnets = network_receipt.get('IPAM', {}).get('Config', [])
    require(len(subnets) == 1 and set(subnets[0]) <= {'Subnet', 'Gateway'} and 'Subnet' in subnets[0],
            'Single observed internal subnet required')
    try:
        subnet = ipaddress.IPv4Network(subnets[0]['Subnet'])
    except (ValueError, TypeError):
        raise Refused('Malformed internal subnet') from None
    require(any(subnet.subnet_of(ipaddress.ip_network(block)) for block in
                ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')),
            'Owned subnet must be wholly within RFC1918 range')
    require(ipaddress.IPv4Address(upstream) in subnet and ipaddress.IPv4Address(upstream) not in
            (subnet.network_address, subnet.broadcast_address), 'Kong IP lies outside usable internal subnet')
    roles = {}
    for role in ('renderer', 'browser', 'tls', 'resolver'):
        name = ('codex9051-renderer-' + policy.project + '-first' if role == 'renderer'
                else 'codex9051-' + role + '-' + policy.project)
        roles[role] = {'name': name, 'network_id': policy.network_id,
                       'user': 'soleur', 'external_route': 'must-be-observed-absent',
                       'ports_published': [], 'host_aliases': [], 'privileged': False,
                       'cap_add': [], 'pid_namespace': 'private', 'trust_global': False,
                       'image_id': None, 'command_reviewed': False}
    roles['renderer']['ca_environment'] = {'NODE_EXTRA_CA_CERTS': '/qualification/tls/ca.crt'}
    roles['browser']['ca_trust'] = material_recipe(hostname)['browser_trust']
    for role in ('renderer', 'browser'):
        roles[role]['dns'] = {'server': 'successfully-created-resolver-IP-pending',
                              'search': ['.'], 'options': ['ndots:0'],
                              'external_forwarding': False}
    roles['tls'].update({'listen_port': 443, 'sni': hostname, 'host': hostname,
                         'upstream': {'ip': upstream, 'port': 8000}, 'general_proxy': False,
                         'namespace_sysctls': {'net.ipv4.ip_unprivileged_port_start': '0'},
                         'low_port_bind': 'exact-namespace-sysctl-observation-required'})
    roles['resolver'].update({'listen_port': 53, 'records': {hostname: 'owned-TLS-IP-pending'},
                              'forwarders': [], 'unknown_name': 'NXDOMAIN',
                              'namespace_sysctls': {'net.ipv4.ip_unprivileged_port_start': '0'},
                              'low_port_bind': 'exact-namespace-sysctl-observation-required'})
    return {'status': 'prepared-operational-evidence-pending', 'execute_authorized': False,
            'network_id': policy.network_id, 'subnet': str(subnet), 'hostname': hostname,
            'upstream': {'container_id': kong_id, 'ip': upstream, 'port': 8000}, 'roles': roles,
            'required_evidence': ['actual-dns-and-route-observations-in-each-role',
                                  'role-image-command-user-environment-and-mounted-files-revalidation',
                                  'resolver-TLS-and-client-container-ID-and-IP-registration',
                                  'task-CA-exact-SAN-and-process-profile-trust-observations',
                                  'owned-local-synthetic-auth', 'fresh-exact-command-approval'],
            'operations': {'docker': 0, 'sql': 0, 'auth': 0}}


def exact_dns_reply(packet, hostname, address):
    """Answer only A for one exact name; no lookup, forwarding or compression."""
    checked_hostname(hostname)
    address = private_ipv4(address)
    require(isinstance(packet, bytes) and 12 <= len(packet) <= 512, 'Bounded DNS packet required')
    identifier, flags, questions, answers, authorities, additional = struct.unpack('!6H', packet[:12])
    require(flags & ~0x0100 == 0 and questions == 1 and answers == authorities == 0 and additional in (0, 1),
            'Only one ordinary DNS question admitted')
    index, labels = 12, []
    while True:
        require(index < len(packet), 'Truncated DNS name')
        length = packet[index]
        index += 1
        if not length:
            break
        require(length <= 63 and index + length <= len(packet), 'Compressed/malformed DNS label refused')
        try:
            labels.append(packet[index:index + length].decode('ascii'))
        except UnicodeDecodeError:
            raise Refused('Non-ASCII DNS name refused') from None
        index += length
        require(index - 12 <= 254, 'DNS name too long')
    question_end = index + 4
    require(question_end <= len(packet), 'Truncated DNS question refused')
    kind, domain = struct.unpack('!2H', packet[index:question_end])
    require(domain == 1, 'Only internet DNS class admitted')
    if additional:
        opt = packet[question_end:]
        require(len(opt) == 11 and opt[0] == 0, 'Only empty bounded EDNS record admitted')
        record, udp_size, flags_version, size = struct.unpack('!HHIH', opt[1:])
        require(record == 41 and 512 <= udp_size <= 4096 and flags_version in (0, 0x8000) and size == 0,
                'EDNS options, extra names and version overrides refused')
    else:
        require(question_end == len(packet), 'Ambiguous/truncated DNS question refused')
    same_name = '.'.join(labels).lower() == hostname
    answering = same_name and kind == 1
    header = struct.pack('!6H', identifier, 0x8400 | (flags & 0x0100) | (0 if same_name else 3),
                         1, int(answering), 0, 0)
    question = packet[12:question_end]
    answer = (b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 0, 4) + socket.inet_aton(address)) if answering else b''
    return header + question + answer


class ExactResolver:
    """Explicitly constructed UDP and TCP handlers; no operational entrypoint."""
    def __init__(self, hostname, address):
        self.hostname = checked_hostname(hostname)
        self.address = private_ipv4(address)

    def reply(self, packet):
        return exact_dns_reply(packet, self.hostname, self.address)

    def udp_once(self, listener):
        listener.settimeout(3)
        packet, peer = listener.recvfrom(513)
        try:
            reply = self.reply(packet)
        except Refused:
            return False
        listener.sendto(reply, peer)
        return True

    def tcp_once(self, connection):
        connection.settimeout(3)
        def read(size):
            data = b''
            while len(data) < size:
                part = connection.recv(size - len(data))
                require(part, 'Early DNS stream EOF')
                data += part
            return data
        size = struct.unpack('!H', read(2))[0]
        require(12 <= size <= 512, 'Bounded DNS frame required')
        reply = self.reply(read(size))
        connection.sendall(struct.pack('!H', len(reply)) + reply)
