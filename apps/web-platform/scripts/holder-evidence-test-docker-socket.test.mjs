import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough, Writable } from 'node:stream';
import postgres from '../node_modules/postgres/src/index.js';
import { createFixtureSocket, mountsVerified, validateFixture } from './holder-evidence-test-docker-socket.mjs';

const id = 'a'.repeat(64), image = `sha256:${'b'.repeat(64)}`, marker = 'c'.repeat(32), password = 'd'.repeat(48);
const config = { id, image, marker, password };
function fixture() {
  return { Id: id, Image: image, State: { Running: true },
    Config: { User: '70:70', Env: [`POSTGRES_PASSWORD=${password}`], Labels: { 'soleur.holder-evidence-test': marker } },
    HostConfig: { NetworkMode: 'none', Binds: null, PortBindings: null, Privileged: false, ReadonlyRootfs: true,
      CapDrop: ['ALL'], SecurityOpt: ['no-new-privileges'], Tmpfs: {
        '/var/lib/postgresql/data': 'rw,noexec,nosuid,size=256m,uid=70,gid=70,mode=0700',
        '/run/postgresql': 'rw,noexec,nosuid,size=16m,uid=70,gid=70,mode=0775', '/tmp': 'rw,noexec,nosuid,size=64m,mode=1777' } },
    NetworkSettings: { Ports: {} }, Mounts: [] };
}

test('actual mount observations must show all required noexec nosuid tmpfs entries', () => {
  const good = '1 0 0:1 / /var/lib/postgresql/data rw,nosuid,noexec - tmpfs tmpfs rw\n' +
    '2 0 0:2 / /run/postgresql rw,nosuid,noexec - tmpfs tmpfs rw\n' +
    '3 0 0:3 / /tmp rw,nosuid,noexec - tmpfs tmpfs rw\n';
  assert.equal(mountsVerified(good), true);
  assert.equal(mountsVerified(good.replace(' - tmpfs', ' - ext4')), false);
  assert.equal(mountsVerified(good.replace('rw,nosuid,noexec', 'rw,nosuid')), false);
  assert.equal(mountsVerified(good.split('\n').slice(0, 2).join('\n')), false);
});

test('only the exact isolated synthetic fixture passes inspection', () => {
  assert.equal(validateFixture(fixture(), config), true);
  for (const change of [
    (d) => { d.Id = 'e'.repeat(64); }, (d) => { d.Config.Labels['soleur.holder-evidence-test'] = 'other'; },
    (d) => { d.HostConfig.NetworkMode = 'host'; }, (d) => { d.NetworkSettings.Ports = { '5432/tcp': [{ HostIp: '127.0.0.1' }] }; },
    (d) => { d.Mounts = [{ Type: 'bind' }]; }, (d) => { d.HostConfig.ReadonlyRootfs = false; },
    (d) => { d.State.Running = false; }, (d) => { d.Config.Env = []; },
  ]) {
    const data = fixture(); change(data);
    assert.equal(validateFixture(data, config), false);
  }
});

test('the real postgres driver writes its startup message through the exact container transport', async () => {
  const writes = [], commands = [];
  const mockSpawn = (command, args) => {
    commands.push([command, args]);
    const child = new EventEmitter();
    child.stdout = new PassThrough();
    child.stdin = new Writable({ write(chunk, _encoding, callback) {
      writes.push(Buffer.from(chunk)); callback();
      process.nextTick(() => child.emit('error', new Error('synthetic failure')));
    } });
    child.exitCode = null;
    child.kill = () => { child.exitCode = 1; child.stdout.end(); };
    process.nextTick(() => child.emit('spawn'));
    return child;
  };
  const db = postgres({ host: '127.0.0.1', port: 5432, socket: () => createFixtureSocket(config, { inspect: () => true, spawn: mockSpawn }),
    database: 'synthetic', username: 'postgres', password, max: 1, connect_timeout: 1, fetch_types: false });
  try { await assert.rejects(db.unsafe('SELECT 1')); }
  finally { await db.end({ timeout: 1 }); }
  assert.ok(writes.length > 0);
  assert.ok(writes[0].length >= 8);
  assert.equal(commands.length, 1);
  assert.deepEqual(commands[0], ['/usr/bin/docker', ['--host', 'unix:///var/run/docker.sock', 'exec', '-i', id, 'busybox', 'nc', '127.0.0.1', '5432']]);
});

test('failed fixture inspection never starts a transport or falls back to a host socket', async () => {
  let calls = 0;
  const db = postgres({ host: '127.0.0.1', port: 5432,
    socket: () => createFixtureSocket(config, { inspect: () => false, spawn: () => { calls++; } }),
    database: 'synthetic', username: 'postgres', password, max: 1, connect_timeout: 1, fetch_types: false });
  try { await assert.rejects(db.unsafe('SELECT 1')); }
  finally { await db.end({ timeout: 1 }); }
  assert.equal(calls, 0);
});
