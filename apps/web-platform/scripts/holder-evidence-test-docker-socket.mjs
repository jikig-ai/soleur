// Synthetic local-test transport only. It connects through an exact Docker
// container ID and never falls back to a host TCP port or grants clearance.
import { spawn, spawnSync } from 'node:child_process';
import { Duplex } from 'node:stream';

const host = 'unix:///var/run/docker.sock';
const label = 'soleur.holder-evidence-test';
const tmpfs = { '/var/lib/postgresql/data': 'rw,noexec,nosuid,size=256m,uid=70,gid=70,mode=0700',
  '/run/postgresql': 'rw,noexec,nosuid,size=16m,uid=70,gid=70,mode=0775', '/tmp': 'rw,noexec,nosuid,size=64m,mode=1777' };

export function mountsVerified(text) {
  if (typeof text !== 'string' || text.length > 65536) return false;
  const seen = new Set();
  for (const line of text.split('\n').filter(Boolean)) {
    const parts = line.split(' - ');
    if (parts.length !== 2) return false;
    const before = parts[0].trim().split(/\s+/), after = parts[1].trim().split(/\s+/);
    if (before.length < 6 || after.length < 1) return false;
    const path = before[4];
    if (Object.hasOwn(tmpfs, path)) {
      const flags = new Set(before[5].split(','));
      if (seen.has(path) || after[0] !== 'tmpfs' || !['rw', 'nosuid', 'noexec'].every((flag) => flags.has(flag))) return false;
      seen.add(path);
    }
  }
  return seen.size === Object.keys(tmpfs).length;
}

export function validateFixture(data, config) {
  try {
    if (!/^[a-f0-9]{64}$/.test(config.id) || !/^sha256:[a-f0-9]{64}$/.test(config.image) ||
        !/^[a-f0-9]{32}$/.test(config.marker) || !/^[a-f0-9]{48}$/.test(config.password)) return false;
    const h = data.HostConfig, c = data.Config, ports = data.NetworkSettings?.Ports;
    return Boolean(data.Id === config.id && data.Image === config.image && data.State?.Running === true &&
      c?.Labels?.[label] === config.marker && c.User === '70:70' && Array.isArray(c.Env) &&
      c.Env.includes(`POSTGRES_PASSWORD=${config.password}`) && h?.NetworkMode === 'none' &&
      (h.Binds == null || (Array.isArray(h.Binds) && h.Binds.length === 0)) &&
      (h.PortBindings == null || Object.keys(h.PortBindings).length === 0) && !h.PublishAllPorts && !h.Privileged &&
      h.ReadonlyRootfs === true && Array.isArray(h.CapDrop) && h.CapDrop.includes('ALL') &&
      Array.isArray(h.SecurityOpt) && h.SecurityOpt.includes('no-new-privileges') &&
      Object.keys(h.Tmpfs ?? {}).length === Object.keys(tmpfs).length && Object.entries(tmpfs).every(([path, options]) => h.Tmpfs[path] === options) &&
      Array.isArray(data.Mounts) && data.Mounts.every((mount) => mount.Type === 'tmpfs' && Object.hasOwn(tmpfs, mount.Destination)) &&
      ports && typeof ports === 'object' && !Array.isArray(ports) && Object.values(ports).every((value) => value == null || (Array.isArray(value) && value.length === 0)));
  } catch { return false; }
}

function inspect(config) {
  const result = spawnSync('/usr/bin/docker', ['--host', host, 'inspect', '--format', '{{json .}}', config.id],
    { encoding: 'utf8', timeout: 3000, maxBuffer: 65536, env: { PATH: '/usr/bin:/bin', HOME: '/nonexistent' } });
  if (result.status !== 0) return false;
  try {
    if (!validateFixture(JSON.parse(result.stdout), config)) return false;
    const mounts = spawnSync('/usr/bin/docker', ['--host', host, 'exec', config.id, 'busybox', 'cat', '/proc/self/mountinfo'],
      { encoding: 'utf8', timeout: 3000, maxBuffer: 65536, env: { PATH: '/usr/bin:/bin', HOME: '/nonexistent' } });
    return mounts.status === 0 && mountsVerified(mounts.stdout);
  } catch { return false; }
}

export function createFixtureSocket(config, testDependencies = {}) {
  let child;
  const stream = new Duplex({
    read() { child?.stdout.resume(); },
    write(chunk, _encoding, callback) { if (!child?.stdin.writable) callback(new Error('synthetic transport unavailable')); else child.stdin.write(chunk, callback); },
    final(callback) { if (child?.stdin.writable) child.stdin.end(callback); else callback(); },
    destroy(error, callback) { stream.readyState = 'closed'; child?.stdin.destroy(); if (child && child.exitCode === null) child.kill(); callback(error); },
  });
  stream.readyState = 'closed';
  try {
    if (!(testDependencies.inspect ?? inspect)(config)) throw new Error('identity');
    child = (testDependencies.spawn ?? spawn)('/usr/bin/docker', ['--host', host, 'exec', '-i', config.id, 'busybox', 'nc', '127.0.0.1', '5432'],
      { stdio: ['pipe', 'pipe', 'ignore'], env: { PATH: '/usr/bin:/bin', HOME: '/nonexistent' } });
    stream.readyState = 'open';
    child.once('error', () => stream.destroy(new Error('synthetic transport failed')));
    child.once('exit', (code) => { if (code !== 0 && !stream.destroyed) stream.destroy(new Error('synthetic transport stopped')); });
    child.stdout.on('data', (chunk) => { if (!stream.push(chunk)) child.stdout.pause(); });
    child.stdout.once('end', () => stream.push(null));
  } catch { throw new Error('synthetic fixture identity unknown'); }
  return stream;
}
