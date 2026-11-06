import { validateReservation } from './holder-reservation-contract.mjs';
import { createHash } from 'node:crypto';

// In-memory experiment only: no identity, durability, fencing or authorization.
export function createReservationFixture(operation, generation) {
  if (![operation, generation].every(v => typeof v === 'string' && /^[a-f0-9]{32}$/.test(v))) throw Error('fixture_identity');
  let raw = null, version = 0, delayed = false, pending = null;
  const unknown = () => ({state:'unknown'});
  const validInput = v => typeof v === 'string' && Buffer.byteLength(v) <= 4096;
  const sha = v => createHash('sha256').update(v).digest('hex');
  function inspect(value) {
    try {
      if (typeof value !== 'string' || Buffer.byteLength(value) > 16384) return null;
      const doc = JSON.parse(value);
      if (!doc || Array.isArray(doc) || JSON.stringify(doc) !== value ||
          JSON.stringify(Object.keys(doc)) !== JSON.stringify(['reserve','reserve_sha256','bind','bind_sha256']) ||
          validateReservation(doc.reserve).state !== 'prepared_unverified' || doc.reserve_sha256 !== sha(doc.reserve)) return null;
      const request = JSON.parse(doc.reserve);
      if (request.purpose !== 'reserve' || request.operation !== operation || request.generation !== generation ||
          (doc.bind === null ? doc.bind_sha256 !== null :
            validateReservation(doc.bind, doc.reserve).state !== 'prepared_unverified' || doc.bind_sha256 !== sha(doc.bind))) return null;
      return doc;
    } catch { return null; }
  }
  function write(next) {
    if (delayed) { delayed = false; pending = {next, expected:version}; return unknown(); }
    raw = next; version++; return {state:'committed_unverified'};
  }
  return Object.freeze({
    async read() {
      if (pending !== null || delayed) return unknown();
      if (raw === null) return {state:'absent_unverified'};
      const doc = inspect(raw);
      return doc ? {state:'found_unverified',version:`v${version}`,...doc} : unknown();
    },
    async reserve(request) {
      if (pending !== null) return unknown();
      if (!validInput(request)) return unknown();
      const candidate = JSON.stringify({reserve:request,reserve_sha256:sha(request),bind:null,bind_sha256:null});
      if (!inspect(candidate)) return unknown();
      if (raw !== null) {
        const prior = inspect(raw);
        return prior && prior.reserve === request ? {state:'historical_unverified'} : unknown();
      }
      return write(candidate);
    },
    async bind(expectedVersion, request) {
      if (pending !== null || raw === null) return unknown();
      const prior = inspect(raw);
      if (!prior || expectedVersion !== `v${version}`) return unknown();
      if (prior.bind !== null) return prior.bind === request ? {state:'historical_unverified'} : unknown();
      if (!validInput(request)) return unknown();
      const candidate = JSON.stringify({...prior,bind:request,bind_sha256:sha(request)});
      if (!inspect(candidate)) return unknown();
      return write(candidate);
    },
    delayNext() { if (delayed || pending !== null) throw Error('fixture_pending'); delayed = true; },
    async observeRemote() {
      if (raw === null) return {state:'absent_unverified'};
      const doc = inspect(raw);
      return doc ? {state:'found_unverified',version:`v${version}`,...doc} : unknown();
    },
    externalCreate(request) {
      if (!validInput(request) || raw !== null) return unknown();
      const candidate = JSON.stringify({reserve:request,reserve_sha256:sha(request),bind:null,bind_sha256:null});
      if (!inspect(candidate)) return unknown();
      raw = candidate; version++; return {state:'committed_unverified'};
    },
    externalBind(expectedVersion, request) {
      if (!validInput(request) || expectedVersion !== `v${version}`) return unknown();
      const prior = inspect(raw);
      if (!prior || prior.bind !== null) return unknown();
      const candidate = JSON.stringify({...prior,bind:request,bind_sha256:sha(request)});
      if (!inspect(candidate)) return unknown();
      raw = candidate; version++; return {state:'committed_unverified'};
    },
    releaseDelayed() {
      if (pending === null) throw Error('fixture_pending');
      const item = pending; pending = null;
      if (version !== item.expected) return {state:'conflict_unverified'};
      raw = item.next; version++; return {state:'committed_unverified'};
    },
    loadRawFixture(value) { if (typeof value !== 'string' || Buffer.byteLength(value) > 16384 || pending !== null || delayed) throw Error('fixture_invalid'); raw = value; version++; },
  });
}
