import { createGuardCommitBuilder } from './holder-reservation-guard-commit.mjs';
import { parseUnique, reservationDocumentTimestamp } from './holder-reservation-firestore.mjs';

// Injected transport orchestration only: transport and provider identities,
// strong reads, durable isolation and anti-rollback are unverified. This is
// neither a listening authority service nor authorization for any vault action.
// A synchronous injected dependency may block past the deadline. Live POST is
// still rejected by the separate Firestore HTTPS transport.
const output = state => ({state,capture_authorized:false,cleanup_authorized:false,deletion_verified:false});
export function createGuardAuthority(project,database,operation,generation,purpose,request) {
  const builder = createGuardCommitBuilder(project,database,operation,generation,purpose);
  if (typeof request !== 'function') throw Error('authority_configuration');
  const root = `projects/${project}/databases/${database}/documents`;
  const endpoint = `https://firestore.googleapis.com/v1/${root}`;
  const guardName = `${root}/holder_reservation_guards/${operation}_${generation}_${purpose}`;
  const reservationName = `${root}/holder_reservations/${operation}_${generation}`;
  let active = false, local = 'closed', pending = null;

  async function perform(fn) {
    if (active) return output('unknown');
    active = true;
    const controller = new AbortController(), end = performance.now()+1000;
    let timer;
    const expired = () => controller.signal.aborted || performance.now() >= end;
    const timeout = new Promise(resolve => { timer=setTimeout(() => {controller.abort();resolve(null);},1000); });
    async function call(method,url,body) {
      try {
        const task=Promise.resolve().then(() => expired()?null:request(Object.freeze({method,url,body,maxResponseBytes:65536,signal:controller.signal}))).catch(() => null);
        const response=await Promise.race([task,timeout]);
        if (expired() || !response) return null;
        const status=response.status, data=response.body;
        return !expired() && Number.isInteger(status) && typeof data==='string' && Buffer.byteLength(data)<=65536 ? {status,body:data} : null;
      } catch { return null; }
    }
    async function read(name) {
      const response=await call('GET',`https://firestore.googleapis.com/v1/${name}`,undefined);
      if (!response || expired() || response.status!==200) return null;
      try {
        const doc=parseUnique(response.body), update=reservationDocumentTimestamp(doc?.updateTime);
        if (!doc || typeof doc!=='object' || Array.isArray(doc) ||
            !['name','fields','updateTime'].every(k=>Object.hasOwn(doc,k)) ||
            !Object.keys(doc).every(k=>['name','fields','updateTime','createTime'].includes(k)) ||
            doc.name!==name || update===null ||
            (Object.hasOwn(doc,'createTime') && (reservationDocumentTimestamp(doc.createTime)===null || reservationDocumentTimestamp(doc.createTime)>update)) ||
            !doc.fields || Object.keys(doc.fields).length!==1 || !Object.hasOwn(doc.fields,'payload') ||
            !doc.fields.payload || Object.keys(doc.fields.payload).length!==1 || !Object.hasOwn(doc.fields.payload,'stringValue') ||
            typeof doc.fields.payload.stringValue!=='string' || Buffer.byteLength(doc.fields.payload.stringValue)>32768 || expired()) return null;
        return {payload:doc.fields.payload.stringValue,time:doc.updateTime};
      } catch { return null; }
    }
    try {
      const value=await Promise.race([Promise.resolve().then(()=>fn({call,read,expired})).catch(()=>output('unknown')),timeout]);
      return expired() || !value ? output('unknown') : value;
    } finally { clearTimeout(timer); controller.abort(); active=false; }
  }
  return Object.freeze({
    bootstrap(...args) { return perform(async ({call,read,expired}) => {
      if (args.length || local!=='closed') return output('unknown');
      const init=builder.initialize();
      const response=await call('POST',`${endpoint}:commit`,init.body);
      if (expired() || response?.status!==200) return output('unknown');
      const observed=await read(guardName);
      if (!observed || observed.payload!==init.guard || expired()) return output('unknown');
      local='ready'; return output('ready_unverified');
    }); },
    claim(...args) { return perform(async ({call,read,expired}) => {
      if (args.length!==2 || local!=='ready') return output('unknown');
      local='closed';
      const current=await read(guardName);
      if (!current || current.payload!==builder.initialize().guard || expired()) return output('unknown');
      const prior=purpose==='bind' ? await read(reservationName) : null;
      if (purpose==='bind' && !prior) return output('unknown');
      const claim=purpose==='bind' ? builder.claim(current.payload,current.time,args[1],args[0],prior.payload,prior.time) : builder.claim(current.payload,current.time,args[1],args[0]);
      if (claim.state!=='prepared_unverified' || expired()) return output('unknown');
      await call('POST',`${endpoint}:commit`,claim.body);
      if (expired()) return output('unknown');
      const observed=await read(guardName);
      if (!observed || observed.payload!==claim.guard || expired()) return output('unknown');
      pending=claim.guard; local='pending'; return output('pending_unverified');
    }); },
    commit(...args) { return perform(async ({call,read,expired}) => {
      if (args.length || local!=='pending' || pending===null) return output('unknown');
      const expected=pending; pending=null; local='closed';
      const current=await read(guardName);
      if (!current || current.payload!==expected || expired()) return output('unknown');
      const effect=builder.effect(current.payload,current.time);
      if (effect.state!=='prepared_unverified' || expired()) return output('unknown');
      await call('POST',`${endpoint}:commit`,effect.body);
      if (expired()) return output('unknown');
      const guard=await read(guardName), reservation=await read(reservationName);
      // This conservative equality condition is a local admission rule, not a
      // verified claim about Firestore's actual cross-document timestamps.
      if (!guard || !reservation || expired() || guard.payload!==effect.guard ||
          reservationDocumentTimestamp(guard.time)!==reservationDocumentTimestamp(reservation.time)) return output('unknown');
      const expectedReservation=JSON.parse(effect.body).writes[1].update.fields.payload.stringValue;
      return output(reservation.payload===expectedReservation ? 'committed_unverified' : 'unknown');
    }); },
    reconcile(...args) { return perform(async ({read,expired}) => {
      // Separate injected reads and equal timestamps do not prove one atomic
      // commit, an authenticated provider, exclusive writers or anti-rollback.
      if (args.length!==2 || typeof args[0]!=='string' || typeof args[1]!=='string') return output('unknown');
      const guard=await read(guardName);
      if (!guard || expired()) return output('unknown');
      let stored;
      try { stored=JSON.parse(guard.payload); } catch { return output('unknown'); }
      if (!stored || stored.state!=='committed' || stored.request!==args[0] || stored.attempt!==args[1]) return output('unknown');
      const pendingGuard=JSON.stringify({...stored,state:'pending'});
      const effect=builder.effect(pendingGuard,guard.time);
      if (effect.state!=='prepared_unverified' || effect.guard!==guard.payload || expired()) return output('unknown');
      const reservation=await read(reservationName);
      if (!reservation || expired() || reservationDocumentTimestamp(guard.time)!==reservationDocumentTimestamp(reservation.time)) return output('unknown');
      const expected=JSON.parse(effect.body).writes[1].update.fields.payload.stringValue;
      return output(reservation.payload===expected ? 'reconciled_unverified' : 'unknown');
    }); },
    recover(...args) { return perform(async ({call,read,expired}) => {
      if (args.length!==1) return output('unknown');
      local='closed'; pending=null;
      const current=await read(guardName);
      if (!current || expired()) return output('unknown');
      const fence=builder.fence(current.payload,current.time,args[0]);
      if (fence.state!=='prepared_unverified' || expired()) return output('unknown');
      await call('POST',`${endpoint}:commit`,fence.body);
      if (expired()) return output('unknown');
      const observed=await read(guardName);
      return output(observed && observed.payload===fence.guard && reservationDocumentTimestamp(observed.time)>reservationDocumentTimestamp(current.time) && !expired() ? 'fenced_unverified' : 'unknown');
    }); },
  });
}
