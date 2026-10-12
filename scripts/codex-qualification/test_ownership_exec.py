"""Ownership and privileged-exec regression fixtures. No Docker or database calls."""
import copy
import json
from api_policy import Policy, Refused, MissingOwnedContainer

IMAGE = 'sha256:' + 'a' * 64
ID = 'b' * 64
NAME = 'supabase_db_fixture'
CONFIG = {'Image': IMAGE, 'Labels': {'com.supabase.cli.project': 'fixture'}}
OPS = [('POST', 'start'), ('POST', 'stop'), ('POST', 'kill'), ('POST', 'exec'),
       ('DELETE', '')]
checks = 0

def fresh():
    policy = Policy('fixture','fixture-internal','/tmp/fixture',{IMAGE:IMAGE})
    policy.admit('POST', '/networks/create', json.dumps({'Name': policy.network,
                 'Labels': {'com.supabase.cli.project': policy.project}}).encode())
    policy.created_network(policy.network, {'Id': 'd' * 64})
    return policy

def refused(call):
    global checks
    try:
        call()
        raise AssertionError('Unowned or privileged operation was admitted')
    except Refused:
        checks += 1

def no_name_mutations(policy):
    for method, operation in OPS:
        suffix = '/' + operation if operation else ''
        refused(lambda: policy.admit(method,'/containers/'+NAME+suffix))

p = fresh()
no_name_mutations(p)  # Reserved name is not ownership, before any create.
try:
    p.admit('GET','/containers/'+NAME+'/json')
    raise AssertionError('Reserved inspection was forwarded')
except MissingOwnedContainer:
    checks += 1
p.admit('POST','/containers/create?name='+NAME,json.dumps(CONFIG).encode())
no_name_mutations(p)  # Pending request has not produced a registered ID.
p.failed_container_creation(NAME)
assert NAME not in p.name_ids and not p.ids and NAME not in p.pending
checks += 1
no_name_mutations(p)  # Backend conflict/failed create never grants ownership.
refused(lambda:p.admit('POST','/containers/create?name='+NAME,json.dumps(CONFIG).encode()))

p = fresh()
p.admit('POST','/containers/create?name='+NAME,json.dumps(CONFIG).encode())
p.created_container(NAME,ID)
for method, operation in OPS:
    suffix = '/' + operation if operation else ''
    payload = json.dumps({'Cmd':['node','--version']}).encode() if operation=='exec' else b''
    path,_ = p.admit(method,'/v1.47/containers/'+NAME+suffix,payload)
    assert path == '/v1.47/containers/'+ID+suffix
    checks += 1
path,_ = p.admit('GET','/containers/'+NAME+'/json')
assert path == '/containers/'+ID+'/json'
checks += 1

base = {'Cmd':['node','--version']}
bad = [{'Privileged':True}, {'Privileged':'false'}, {'User':'0'},
       {'User':'root'}, {'Tty':True},
       {'Env':['OPENAI_API_KEY=synthetic-do-not-use']},
       {'Env':['SUPABASE_ACCESS_TOKEN=synthetic-do-not-use']},
       {'Env':['DATABASE_URL_POOLER=postgres://synthetic.invalid/example']},
       {'Env':['DOCKER_HOST=unix:///var/run/docker.sock']},
       {'Env':['HOME=/root']}, {'Env':['PATH=/usr/bin:/bin','PATH=/usr/bin:/bin']},
       {'Cmd':['node',1]}, {'AttachStdin':'true'}, {'UnreviewedField':True},
       {'Env':False}, {'DetachKeys':'unreviewed'}, {'ConsoleSize':[999999999,1]}]
for extra in bad:
    payload = {**base,**extra}
    refused(lambda:p.admit('POST','/containers/'+NAME+'/exec',json.dumps(payload).encode()))
good = {**base,'Privileged':False,'Env':['HOME=/tmp','PATH=/usr/bin:/bin'],'AttachStdout':True}
path,_ = p.admit('POST','/containers/'+NAME+'/exec',json.dumps(good).encode())
assert path == '/containers/'+ID+'/exec'
checks += 1
p.created_exec('c'*64,ID)
refused(lambda:p.admit('POST','/exec/'+'c'*64+'/start',json.dumps({'Privileged':True}).encode()))
p.removed_container(ID)
assert NAME not in p.name_ids and ID not in p.ids
checks += 1
no_name_mutations(p)  # Deleted ID or later foreign takeover of same name never revives ownership.
refused(lambda:p.admit('GET','/containers/'+ID+'/json'))
refused(lambda:p.admit('POST','/exec/'+'c'*64+'/start'))
print(json.dumps({'ownership_exec_checks':checks,'docker_calls':0,
 'reserved_before_pending_failed_created_deleted':'pass','exec_privilege_credentials':'pass'}))
