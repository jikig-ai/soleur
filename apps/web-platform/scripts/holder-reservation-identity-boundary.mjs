import { createHash } from 'node:crypto';
import { createGoogleIdVerifier } from './holder-google-id-verifier.mjs';
import { validateReservation } from './holder-reservation-contract.mjs';

// Preparation only. Injected JWKS, identity pins and host clock are untrusted.
// There is no transport, guard callback, live authorization or vault action.
// The returned object and unkeyed digest are forgeable; a bearer token does
// not sign the request or attempt. Never use this as an authentication token.
const denied = () => ({state:'unknown',capture_authorized:false,cleanup_authorized:false,deletion_verified:false});
const digest = value => createHash('sha256').update(JSON.stringify(value),'utf8').digest('hex');
const fields = ['audience','vault_subject','operation','generation','manifest_sha256','controller_sha256','epoch','vault_device','vault_inode','start_ms','deadline_ms'];

export function createReservationIdentityBoundary(configJson, jwksJson) {
  const fail = Object.freeze({submit:async()=>denied()});
  if (arguments.length !== 2) return fail;
  try {
    if (typeof configJson !== 'string' || Buffer.byteLength(configJson)>8192 || typeof jwksJson !== 'string') return fail;
    const config=JSON.parse(configJson);
    if (!config || typeof config!=='object' || Array.isArray(config) || JSON.stringify(config)!==configJson ||
        Object.keys(config).length!==fields.length || !fields.every(k=>Object.hasOwn(config,k)) ||
        typeof config.audience!=='string' || config.audience.length>2048 || !/^[\x21-\x7e]+$/.test(config.audience) ||
        typeof config.vault_subject!=='string' || !/^[0-9]{1,32}$/.test(config.vault_subject)) return fail;
    const url=new URL(config.audience);
    if (url.protocol!=='https:' || url.username || url.password || url.search || url.hash || url.href!==config.audience) return fail;
    const verifier=createGoogleIdVerifier(JSON.stringify({audience:config.audience,subjects:[{subject:config.vault_subject,role:'vault'}]}),jwksJson);
    const caller=digest(['holder-reservation-caller-v1','https://accounts.google.com',config.vault_subject]);
    const audience=digest(['holder-reservation-audience-v1',config.audience]);
    return Object.freeze({submit:async (...args) => {
      try {
        if (args.length<3 || args.length>4 || typeof args[1]!=='string' || args[1].length>4096 || Buffer.byteLength(args[1])>4096 ||
            (args.length===4 && (typeof args[3]!=='string' || args[3].length>4096 || Buffer.byteLength(args[3])>4096)) ||
            typeof args[2]!=='string' || !/^[a-f0-9]{32}$/.test(args[2])) return denied();
        const request=JSON.parse(args[1]);
        if (!request || typeof request!=='object' || Array.isArray(request) ||
            (request.purpose==='reserve' ? args.length!==3 || validateReservation(args[1]).state!=='prepared_unverified' :
             request.purpose!=='bind' || args.length!==4 || validateReservation(args[1],args[3]).state!=='prepared_unverified') ||
            !fields.slice(2).every(k=>request[k]===config[k]) || request.caller_sha256!==caller || request.audience_sha256!==audience) return denied();
        const identity=await verifier.verify(args[0]);
        if (identity.state!=='signature_verified_untrusted_keys' || identity.subject!==config.vault_subject || identity.role!=='vault') return denied();
        return {state:'identity_bound_unverified',capture_authorized:false,cleanup_authorized:false,deletion_verified:false,
          identity:'signature_verified_untrusted_keys',request_sha256:createHash('sha256').update(args[1],'utf8').digest('hex'),attempt:args[2]};
      } catch { return denied(); }
    }});
  } catch { return fail; }
}
