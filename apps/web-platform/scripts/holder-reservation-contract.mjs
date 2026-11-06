import { createHash } from 'node:crypto';

// Unwired shape checking only. Inputs, identity, time and persistence are not trusted.
const common = ['version','purpose','operation','generation','command','nonce','epoch','entry','vault_device','vault_inode','start_ms','deadline_ms','manifest_sha256','controller_sha256','caller_sha256','audience_sha256'];
const bindFields = [...common,'reserve_sha256','receipt_device','receipt_inode'];
const hash = s => createHash('sha256').update(s, 'utf8').digest('hex');
const hex = (v,n) => typeof v === 'string' && new RegExp(`^[a-f0-9]{${n}}$`).test(v);
const decimal = v => typeof v === 'string' && /^(0|[1-9][0-9]{0,19})$/.test(v) && BigInt(v) <= 18446744073709551615n;
function parse(raw) {
  if (typeof raw !== 'string' || Buffer.byteLength(raw) > 4096) throw Error();
  const x = JSON.parse(raw);
  if (!x || typeof x !== 'object' || Array.isArray(x) || JSON.stringify(x) !== raw ||
      !['reserve','bind'].includes(x.purpose) || JSON.stringify(Object.keys(x)) !== JSON.stringify(x.purpose === 'bind' ? bindFields : common) ||
      x.version !== 'holder-reservation-v1' || x.entry !== 'receipt' ||
      !['operation','generation','command','nonce'].every(k => hex(x[k],32)) ||
      !['manifest_sha256','controller_sha256','caller_sha256','audience_sha256'].every(k => hex(x[k],64)) ||
      !['epoch','vault_device','vault_inode','start_ms','deadline_ms'].every(k => decimal(x[k])) ||
      BigInt(x.deadline_ms) <= BigInt(x.start_ms) || BigInt(x.deadline_ms) - BigInt(x.start_ms) > 86400000n ||
      (x.purpose === 'bind' && (!hex(x.reserve_sha256,64) || !decimal(x.receipt_device) || !decimal(x.receipt_inode)))) throw Error();
  return x;
}
export function validateReservation(raw, reserveRaw) {
  try {
    const x = parse(raw);
    if (x.purpose === 'bind') {
      const reserve = parse(reserveRaw);
      if (reserve.purpose !== 'reserve' || x.reserve_sha256 !== hash(reserveRaw) || common.some(k => k !== 'purpose' && x[k] !== reserve[k])) throw Error();
    } else if (reserveRaw !== undefined) throw Error();
    return { state:'prepared_unverified', sha256:hash(raw) };
  } catch { return {state:'unknown'}; }
}
