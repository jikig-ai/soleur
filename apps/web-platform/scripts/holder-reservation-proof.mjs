import { createHash, createPublicKey, verify } from 'node:crypto';
import { validateReservation } from './holder-reservation-contract.mjs';

// Unwired proof-of-possession primitive only. A supplied key is not a trusted
// identity, a challenge is not consumed here, and no operation is authorized.
const hash = value => createHash('sha256').update(value).digest('hex');
const denied = () => ({state:'unknown',capture_authorized:false,cleanup_authorized:false,deletion_verified:false});
const hex = (value, length) => typeof value === 'string' && new RegExp(`^[a-f0-9]{${length}}$`).test(value);

export function proofMessage(request, reserve, attempt, challenge, tokenHash, publicPem) {
  try {
    if (arguments.length !== 6 || typeof request !== 'string' || Buffer.byteLength(request)>4096 ||
        (reserve !== undefined && (typeof reserve !== 'string' || Buffer.byteLength(reserve)>4096)) ||
        !hex(attempt,32) || !hex(challenge,64) || !hex(tokenHash,64) ||
        typeof publicPem !== 'string' || publicPem.length>1024) throw Error();
    const validated = validateReservation(request,reserve);
    if (validated.state !== 'prepared_unverified') throw Error();
    const key = createPublicKey(publicPem);
    if (key.type !== 'public' || key.asymmetricKeyType !== 'ed25519' ||
        key.export({type:'spki',format:'pem'}).toString() !== publicPem) throw Error();
    const fingerprint = hash(key.export({type:'spki',format:'der'}));
    const purpose = JSON.parse(request).purpose;
    return Buffer.from(JSON.stringify(['holder-reservation-request-proof-v1',purpose,validated.sha256,attempt,challenge,tokenHash,fingerprint]));
  } catch { throw new Error('proof_unknown'); }
}

export function verifyReservationProof(request, reserve, attempt, challenge, tokenHash, publicPem, signature) {
  try {
    if (arguments.length !== 7 || typeof signature !== 'string' || signature.length !== 88) return denied();
    const bytes = Buffer.from(signature,'base64');
    if (bytes.length !== 64 || bytes.toString('base64') !== signature) return denied();
    const message = proofMessage(request,reserve,attempt,challenge,tokenHash,publicPem);
    if (!verify(null,message,createPublicKey(publicPem),bytes)) return denied();
    return {state:'signature_valid_only',capture_authorized:false,cleanup_authorized:false,deletion_verified:false};
  } catch { return denied(); }
}
