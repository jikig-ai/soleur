import { createHash } from 'node:crypto';
import { validateReservation } from './holder-reservation-contract.mjs';

// Constructs candidate REST commit bytes only. It does not execute them or
// establish identity, durable guards, provider semantics, fencing or authority.
// Live Firestore transport continues to reject POST requests.
// A supplied payload and revision can describe different real documents. The
// precondition pins only the revision; it does NOT authenticate the payload.
// Never execute these bytes without an authority-owned authenticated read that
// binds each exact name, payload and revision, plus the remaining live gates.
const sha = raw => createHash('sha256').update(raw,'utf8').digest('hex');
const unknown = () => ({state:'unknown'});
const hex32 = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
function validTime(value) {
  if (typeof value !== 'string' || value.startsWith('0000-')) return false;
  const match = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{3}|\d{6}|\d{9}))?Z$/.exec(value);
  if (!match || (match[2]?.length === 9 && !match[2].endsWith('000'))) return false;
  const millis = Date.parse(`${match[1]}Z`);
  return Number.isFinite(millis) && new Date(millis).toISOString().slice(0,19) === match[1];
}

export function createGuardCommitBuilder(project, database, operation, generation, purpose) {
  if (typeof project !== 'string' || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(project) ||
      typeof database !== 'string' || !(database === '(default)' || /^[a-z0-9][a-z0-9-]{0,62}$/.test(database)) ||
      !hex32(operation) || !hex32(generation) || !['reserve','bind'].includes(purpose)) throw Error('builder_configuration');
  const root = `projects/${project}/databases/${database}/documents`;
  const guardName = `${root}/holder_reservation_guards/${operation}_${generation}_${purpose}`;
  const reservationName = `${root}/holder_reservations/${operation}_${generation}`;
  const readyObject = {version:'holder-guard-v1',operation,generation,purpose,state:'ready',attempt:null,request:null,prior:null,revision:null,barrier:null};
  const ready = JSON.stringify(readyObject);
  const write = (name, payload, condition) => ({update:{name,fields:{payload:{stringValue:payload}}},currentDocument:condition});
  const prepared = (guard, writes) => {
    const body = JSON.stringify({writes});
    return Buffer.byteLength(body) <= 65536 ? {state:'prepared_unverified',guard,body} : unknown();
  };
  const recordFor = (request, prior, revision) => {
    if (typeof request !== 'string' || Buffer.byteLength(request) > 4096) return null;
    try {
      const input = JSON.parse(request);
      if (input.purpose !== purpose || input.operation !== operation || input.generation !== generation) return null;
      if (purpose === 'reserve') {
        if (prior !== null || revision !== null || validateReservation(request).state !== 'prepared_unverified') return null;
        return {payload:JSON.stringify({reserve:request,reserve_sha256:sha(request),bind:null,bind_sha256:null}),condition:{exists:false}};
      }
      if (typeof prior !== 'string' || Buffer.byteLength(prior) > 16384 || !validTime(revision)) return null;
      const previous = JSON.parse(prior);
      if (!previous || typeof previous !== 'object' || Array.isArray(previous) || JSON.stringify(previous) !== prior ||
          JSON.stringify(Object.keys(previous)) !== JSON.stringify(['reserve','reserve_sha256','bind','bind_sha256']) ||
          previous.bind !== null || previous.bind_sha256 !== null || previous.reserve_sha256 !== sha(previous.reserve) ||
          validateReservation(previous.reserve).state !== 'prepared_unverified' ||
          validateReservation(request,previous.reserve).state !== 'prepared_unverified') return null;
      const initial = JSON.parse(previous.reserve);
      if (initial.operation !== operation || initial.generation !== generation || initial.purpose !== 'reserve') return null;
      return {payload:JSON.stringify({...previous,bind:request,bind_sha256:sha(request)}),condition:{updateTime:revision}};
    } catch { return null; }
  };
  const build = Object.freeze({
    initialize() { return prepared(ready,[write(guardName,ready,{exists:false})]); },
    claim(raw, version, attempt, request, prior, revision) {
      try {
        if (raw !== ready || !validTime(version) || !hex32(attempt) ||
            (purpose === 'reserve' && (prior !== undefined || revision !== undefined))) return unknown();
        const p = purpose === 'reserve' ? null : prior, r = purpose === 'reserve' ? null : revision;
        if (!recordFor(request,p,r)) return unknown();
        const guard = JSON.stringify({...readyObject,state:'pending',attempt,request,prior:p,revision:r});
        return prepared(guard,[write(guardName,guard,{updateTime:version})]);
      } catch { return unknown(); }
    },
    effect(raw, version) {
      try {
        if (typeof raw !== 'string' || Buffer.byteLength(raw) > 32768 || !validTime(version)) return unknown();
        const pending = JSON.parse(raw);
        if (!pending || pending.state !== 'pending') return unknown();
        const claim = purpose === 'reserve' ? build.claim(ready,version,pending.attempt,pending.request) :
          build.claim(ready,version,pending.attempt,pending.request,pending.prior,pending.revision);
        if (claim.state !== 'prepared_unverified' || claim.guard !== raw) return unknown();
        const target = recordFor(pending.request,pending.prior,pending.revision);
        if (!target) return unknown();
        const guard = JSON.stringify({...pending,state:'committed'});
        return prepared(guard,[write(guardName,guard,{updateTime:version}),write(reservationName,target.payload,target.condition)]);
      } catch { return unknown(); }
    },
    fence(raw, version, barrier) {
      try {
        if (typeof raw !== 'string' || Buffer.byteLength(raw) > 32768 || !validTime(version) || !hex32(barrier)) return unknown();
        let prior;
        if (raw === ready) prior = readyObject;
        else {
          prior = JSON.parse(raw);
          if (!prior || prior.state !== 'pending') return unknown();
          const claim = purpose === 'reserve' ? build.claim(ready,version,prior.attempt,prior.request) :
            build.claim(ready,version,prior.attempt,prior.request,prior.prior,prior.revision);
          if (claim.state !== 'prepared_unverified' || claim.guard !== raw) return unknown();
        }
        const guard = JSON.stringify({...prior,state:'fenced',barrier});
        return prepared(guard,[write(guardName,guard,{updateTime:version})]);
      } catch { return unknown(); }
    },
  });
  return build;
}
