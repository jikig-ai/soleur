import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

// Read-only request/projection boundary, not a DynamoDB client. The supplied
// transport, floor and resource pins are assertions. No result proves a strong
// read, non-rollback, authenticated identity, current revocation or authority.
// No AWS credentials, writes, live transport or deployable handler are present.
const result = reason => ({ state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false, reason });
const keys = (o, fields) => o && typeof o === 'object' && !Array.isArray(o) &&
  Object.keys(o).length === fields.length && fields.every(k => Object.hasOwn(o, k));
const id = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const epoch = value => typeof value === 'string' && /^(?:0|[1-9][0-9]{0,15})$/.test(value) &&
  BigInt(value) <= BigInt(Number.MAX_SAFE_INTEGER);
const arn = value => typeof value === 'string' &&
  /^arn:aws:dynamodb:[a-z0-9-]{1,32}:[0-9]{12}:table\/[a-zA-Z0-9_.-]{3,255}(?![\s\S])/.test(value);
const identity = ['table_arn', 'operation_id', 'generation', 'store_id'];

// Drop only whitespace outside quoted strings. JSON.stringify comparison then
// rejects duplicate keys and noncanonical escaped keys or values, fail closed.
function compact(raw) {
  let text = '', quoted = false, escaped = false;
  for (const char of raw) {
    if (quoted) {
      text += char;
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') quoted = false;
    } else if (char === '"') { quoted = true; text += char; }
    else if (char !== ' ' && char !== '\n' && char !== '\r' && char !== '\t') text += char;
  }
  return text;
}

function parse(raw, cap) {
  if (typeof raw !== 'string' || Buffer.byteLength(raw, 'utf8') > cap) throw new Error('invalid');
  const parsed = JSON.parse(raw);
  if (JSON.stringify(parsed) !== compact(raw)) throw new Error('invalid');
  return parsed;
}

export async function readEpochEvidence(read, configJson, floorJson) {
  const invalid = () => result('invalid');
  let controller, timer;
  try {
    const config = parse(configJson, 2048), floor = parse(floorJson, 2048);
    if (typeof read !== 'function' || !keys(config, [...identity, 'timeout_ms']) ||
        !keys(floor, [...identity, 'minimum_epoch', 'revoked']) || !arn(config.table_arn) ||
        !['operation_id', 'generation', 'store_id'].every(k => id(config[k])) ||
        identity.some(k => floor[k] !== config[k]) || !epoch(floor.minimum_epoch) || typeof floor.revoked !== 'boolean' ||
        !Number.isSafeInteger(config.timeout_ms) || config.timeout_ms < 1 || config.timeout_ms > 5000) return invalid();
    controller = new AbortController();
    const stopAt = performance.now() + config.timeout_ms;
    const deadline = new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(null); }, config.timeout_ms); });
    const request = Object.freeze({ TableName: config.table_arn,
      Key: Object.freeze({ operation_id: Object.freeze({ S: config.operation_id }) }), ConsistentRead: true });
    const bytes = await Promise.race([Promise.resolve().then(() => read(request, controller.signal)).catch(() => null), deadline]);
    if (controller.signal.aborted || performance.now() >= stopAt || bytes === null) return invalid();
    const copy = snapshotBytes(bytes, 8192);
    if (!copy.length) return invalid();
    const decoded = new TextDecoder('utf-8', { fatal: true }).decode(copy);
    const data = parse(decoded, 8192);
    if (!keys(data, ['Item']) || !keys(data.Item, ['operation_id', 'generation', 'store_id', 'epoch', 'revoked'])) return invalid();
    const item = data.Item;
    for (const field of ['operation_id', 'generation', 'store_id']) {
      if (!keys(item[field], ['S']) || item[field].S !== config[field]) return invalid();
    }
    if (!keys(item.epoch, ['N']) || !epoch(item.epoch.N) || !keys(item.revoked, ['BOOL']) || typeof item.revoked.BOOL !== 'boolean') return invalid();
    if (controller.signal.aborted || performance.now() >= stopAt) return invalid();
    if (BigInt(item.epoch.N) < BigInt(floor.minimum_epoch)) return result('below_asserted_floor');
    if (item.revoked.BOOL || floor.revoked) return result('revoked_or_asserted_revoked');
    return result('nonrollback_unverified');
  } catch { return invalid(); }
  finally { if (timer !== undefined) clearTimeout(timer); controller?.abort(); }
}
