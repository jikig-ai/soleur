import { createHash } from 'node:crypto';
import { validateReservation } from './holder-reservation-contract.mjs';

// Injected transport only. No authentication, real strong-read guarantee,
// durable authority, epoch, fencing or authorization is established here.
// The separate live Firestore transport continues to reject POST requests.
// The in-memory unknown-write latch does not survive process loss or coordinate
// separate instances. The timeout cannot interrupt synchronous injected code.
const result = state => ({state, capture_authorized:false, cleanup_authorized:false, deletion_verified:false});
const sha = raw => createHash('sha256').update(raw,'utf8').digest('hex');
const keys = (value, fields) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).length === fields.length && fields.every((key, i) => Object.keys(value)[i] === key);
// JSON.parse validates syntax first; this bounded second walk rejects duplicate
// decoded keys without imposing a provider-specific property order or spacing.
export function parseUnique(raw) {
  const value = JSON.parse(raw);
  let i = 0;
  const space = () => { while (i < raw.length && /[\x20\t\r\n]/.test(raw[i])) i++; };
  function string() {
    const start = i++;
    while (i < raw.length) {
      if (raw[i] === '\\') { i += 2; continue; }
      if (raw[i++] === '"') return JSON.parse(raw.slice(start,i));
    }
    throw Error('invalid');
  }
  function walk(depth) {
    if (depth > 32) throw Error('invalid');
    space();
    if (raw[i] === '{') {
      i++; space(); const seen = new Set();
      if (raw[i] === '}') { i++; return; }
      while (true) {
        space(); if (raw[i] !== '"') throw Error('invalid');
        const key = string(); if (seen.has(key)) throw Error('invalid'); seen.add(key);
        space(); if (raw[i++] !== ':') throw Error('invalid');
        walk(depth+1); space();
        if (raw[i] === '}') { i++; return; }
        if (raw[i++] !== ',') throw Error('invalid');
      }
    }
    if (raw[i] === '[') {
      i++; space(); if (raw[i] === ']') { i++; return; }
      while (true) { walk(depth+1); space(); if (raw[i] === ']') { i++; return; } if (raw[i++] !== ',') throw Error('invalid'); }
    }
    if (raw[i] === '"') { string(); return; }
    const start = i;
    while (i < raw.length && !/[\x20\t\r\n,}\]]/.test(raw[i])) i++;
    if (i === start) throw Error('invalid');
  }
  walk(0); space(); if (i !== raw.length) throw Error('invalid');
  return value;
}
export const reservationDocumentTimestamp = value => {
  if (typeof value !== 'string' || value.startsWith('0000-')) return null;
  const match = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{3}|\d{6}|\d{9}))?Z$/.exec(value);
  if (!match || (match[2]?.length === 9 && !match[2].endsWith('000'))) return null;
  const millis = Date.parse(`${match[1]}Z`);
  if (!Number.isFinite(millis) || new Date(millis).toISOString().slice(0,19) !== match[1]) return null;
  return BigInt(millis) * 1000000n + BigInt((match[2] ?? '').padEnd(9,'0'));
};

export function createReservationAdapter(project, database, operation, generation, request) {
  if (typeof project !== 'string' || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(project) ||
      typeof database !== 'string' || !(database === '(default)' || /^[a-z0-9][a-z0-9-]{0,62}$/.test(database)) ||
      ![operation,generation].every(v => typeof v === 'string' && /^[a-f0-9]{32}$/.test(v)) || typeof request !== 'function') throw Error('adapter_configuration');
  const root = `projects/${project}/databases/${database}/documents`;
  const name = `${root}/holder_reservations/${operation}_${generation}`;
  const endpoint = `https://firestore.googleapis.com/v1/${root}`;
  let active = false, unresolved = null;
  function inspect(raw) {
    try {
      if (typeof raw !== 'string' || Buffer.byteLength(raw) > 16384) return null;
      const record = JSON.parse(raw);
      if (!keys(record,['reserve','reserve_sha256','bind','bind_sha256']) || JSON.stringify(record) !== raw ||
          validateReservation(record.reserve).state !== 'prepared_unverified' || record.reserve_sha256 !== sha(record.reserve)) return null;
      const payload = JSON.parse(record.reserve);
      if (payload.purpose !== 'reserve' || payload.operation !== operation || payload.generation !== generation ||
          (record.bind === null ? record.bind_sha256 !== null :
            validateReservation(record.bind,record.reserve).state !== 'prepared_unverified' || record.bind_sha256 !== sha(record.bind))) return null;
      return record;
    } catch { return null; }
  }
  return Object.freeze({
    reserve: raw => submit('reserve',raw),
    bind: (reserve,raw) => submit('bind',raw,reserve),
  });
  async function submit(action, raw, reserve) {
    if (active || (unresolved !== null && (unresolved.action !== action || unresolved.raw !== raw || unresolved.reserve !== reserve))) return result('unknown');
    active = true;
    const controller = new AbortController(), end = performance.now() + 1000;
    let timer;
    const expired = () => controller.signal.aborted || performance.now() >= end;
    const timeout = new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(null); },1000); });
    async function call(method, url, body) {
      try {
        const pending = Promise.resolve().then(() => expired() ? null : request(Object.freeze({method,url,body,maxResponseBytes:32768,signal:controller.signal}))).catch(() => null);
        const response = await Promise.race([pending,timeout]);
        if (expired() || !response) return null;
        const status = response.status, value = response.body;
        return !expired() && Number.isInteger(status) && typeof value === 'string' && Buffer.byteLength(value) <= 32768 ? {status,body:value} : null;
      } catch { return null; }
    }
    async function read() {
      const response = await call('GET',`${endpoint}/holder_reservations/${operation}_${generation}`,undefined);
      if (expired() || !response) return null;
      if (response.status === 404) return {state:'absent'};
      if (response.status !== 200) return null;
      try {
        const doc = parseUnique(response.body);
        if (expired() || !doc || typeof doc !== 'object' || Array.isArray(doc) ||
            !['name','fields','updateTime'].every(k => Object.hasOwn(doc,k)) ||
            !Object.keys(doc).every(k => ['name','fields','updateTime','createTime'].includes(k)) ||
            doc.name !== name || reservationDocumentTimestamp(doc.updateTime) === null ||
            (Object.hasOwn(doc,'createTime') && (reservationDocumentTimestamp(doc.createTime) === null || reservationDocumentTimestamp(doc.createTime) > reservationDocumentTimestamp(doc.updateTime))) ||
            !keys(doc.fields,['payload']) || !keys(doc.fields.payload,['stringValue'])) return null;
        const record = inspect(doc.fields.payload.stringValue);
        return !expired() && record ? {state:'found',record,updateTime:doc.updateTime} : null;
      } catch { return null; }
    }
    const work = async () => {
      try {
        if (typeof raw !== 'string' || (action === 'bind' && typeof reserve !== 'string') ||
            validateReservation(raw,...(action === 'bind' ? [reserve] : [])).state !== 'prepared_unverified') return result('unknown');
        const input = JSON.parse(raw);
        if (input.purpose !== action || input.operation !== operation || input.generation !== generation || expired()) return result('unknown');
        const current = await read();
        if (!current || expired()) return result('unknown');
        if (unresolved !== null) {
          const matches = current.state === 'found' && (action === 'reserve' ? current.record.reserve === raw : current.record.reserve === reserve && current.record.bind === raw);
          if (!matches) return result('unknown');
          unresolved = null;
          return result('historical_unverified');
        }
        let next, condition;
        if (action === 'reserve') {
          if (current.state === 'found') return result(current.record.reserve === raw ? 'historical_unverified' : 'unknown');
          next = {reserve:raw,reserve_sha256:sha(raw),bind:null,bind_sha256:null};
          condition = {exists:false};
        } else {
          if (current.state !== 'found' || current.record.reserve !== reserve) return result('unknown');
          if (current.record.bind !== null) return result(current.record.bind === raw ? 'historical_unverified' : 'unknown');
          next = {...current.record,bind:raw,bind_sha256:sha(raw)};
          condition = {updateTime:current.updateTime};
        }
        const payload = JSON.stringify(next);
        if (!inspect(payload) || expired()) return result('unknown');
        const body = JSON.stringify({writes:[{update:{name,fields:{payload:{stringValue:payload}}},currentDocument:condition}]});
        if (expired() || Buffer.byteLength(body) > 32768) return result('unknown');
        unresolved = {action,raw,reserve};
        await call('POST',`${endpoint}:commit`,body);
        if (expired()) return result('unknown');
        const observed = await read();
        if (expired() || observed?.state !== 'found') return result('unknown');
        const matches = action === 'reserve' ? observed.record.reserve === raw : observed.record.reserve === reserve && observed.record.bind === raw;
        if (matches) unresolved = null;
        return result(matches ? 'persisted_unverified' : 'unknown');
      } catch { return result('unknown'); }
    };
    try {
      const value = await Promise.race([work(),timeout]);
      return expired() || !value ? result('unknown') : value;
    } finally { clearTimeout(timer); controller.abort(); active = false; }
  }
}
