"""Foreign reserved-name collision tests against a fake backend, never Docker."""
import http.server
import json
from pathlib import Path
import tempfile
import threading
from api_policy import Policy
from api_proxy import Proxy, UnixHTTPServer, UnixConnection

IMAGE='sha256:'+'a'*64
ID='b'*64
NAME='supabase_db_fixture'
received=[]
conflict=True
foreign_at_reserved_name=True
checks=0

class Fake(http.server.BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*_): pass
    def reply(self,status,value):
        body=json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        received.append(('GET',self.path))
        value={'Id':'f'*64,'foreign':'synthetic-sentinel'} if NAME in self.path and foreign_at_reserved_name else {'Id':ID}
        self.reply(200,value)
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length','0')))
        received.append(('POST',self.path))
        if self.path.startswith('/containers/create'):
            self.reply(409,{'message':'reserved name already belongs to foreign fixture'}) if conflict else self.reply(201,{'Id':ID})
        else:
            self.reply(200,{})
    def do_DELETE(self):
        received.append(('DELETE',self.path))
        self.reply(200,{})

def request(proxy,method,path,body=None):
    c=UnixConnection(proxy.path)
    c.request(method,path,json.dumps(body).encode() if body is not None else None)
    r=c.getresponse()
    result=(r.status,r.read())
    c.close()
    return result

with tempfile.TemporaryDirectory(prefix='codex9051-name-collision-') as directory:
    root=Path(directory)
    backend=UnixHTTPServer(str(root/'fake.sock'),Fake)
    thread=threading.Thread(target=backend.serve_forever,daemon=True)
    thread.start()
    config={'Image':IMAGE,'Labels':{'com.supabase.cli.project':'fixture'}}
    def create_proxy(suffix):
        p=Policy('fixture','fixture-internal',root,{IMAGE:IMAGE})
        proxy=Proxy(root/(suffix+'.sock'),root/'fake.sock',p,lifetime=10)
        proxy.start()
        return p,proxy
    try:
        p,proxy=create_proxy('before-create')
        try:
            before=len(received)
            status,body=request(proxy,'GET','/containers/'+NAME+'/json')
            assert status==404 and b'synthetic-sentinel' not in body and len(received)==before and not proxy.fatal
            checks+=1
            status,_=request(proxy,'POST','/containers/'+NAME+'/start')
            assert status==403 and len(received)==before
            checks+=1
        finally: proxy.stop()

        p,proxy=create_proxy('failed-create')
        try:
            before=len(received)
            status,_=request(proxy,'POST','/containers/create?name='+NAME,config)
            assert status==409 and len(received)==before+1
            assert not p.ids and NAME not in p.name_ids and NAME not in p.pending and NAME in p.failed_names
            assert proxy.fatal
            checks+=1
            count=len(received)
            for method,suffix in [('POST','start'),('POST','stop'),('POST','kill'),('POST','exec'),('DELETE','')]:
                path='/containers/'+NAME+('/'+suffix if suffix else '')
                status,_=request(proxy,method,path)
                assert status==403 and len(received)==count
                checks+=1
        finally: proxy.stop()

        conflict=False
        foreign_at_reserved_name=False
        p,proxy=create_proxy('registered-id')
        try:
            status,_=request(proxy,'POST','/containers/create?name='+NAME,config)
            assert status==201 and p.name_ids[NAME]==ID
            checks+=1
            # A later foreign takeover of the name cannot redirect the registered alias.
            foreign_at_reserved_name=True
            status,body=request(proxy,'GET','/containers/'+NAME+'/json')
            assert status==200 and json.loads(body)['Id']==ID and received[-1]==('GET','/containers/'+ID+'/json')
            checks+=1
            status,_=request(proxy,'POST','/containers/'+NAME+'/start')
            assert status==200 and received[-1]==('POST','/containers/'+ID+'/start')
            checks+=1
            count=len(received)
            status,_=request(proxy,'POST','/containers/'+NAME+'/exec',{'Cmd':['node','--version'],'Privileged':True})
            assert status==403 and len(received)==count
            checks+=1
        finally: proxy.stop()
        print(json.dumps({'collision_transport_checks':checks,'docker_calls':0,
                          'foreign_reserved_before_failed_registered':'pass',
                          'privileged_exec_never_forwarded':'pass'}))
    finally:
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=5)
        assert not backend.errors, 'Fake backend thread failed'
