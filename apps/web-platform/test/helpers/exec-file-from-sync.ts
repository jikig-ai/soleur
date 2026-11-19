// Test seam (review fix round 1, WP1, D38(1)): the connected-repo runner is async (`execFile` with a callback), while the
// session-sync unit suites script git through a synchronous `execFileSync` stub. This adapts such a stub into an `execFile`
// mock: the stub's return value is the child's stdout; a throw is a failed child whose `code` is the stub error's `status`
// (default 1). The stub keeps receiving `(cmd, args, opts)`, so its call records and option assertions are unchanged.
type SyncStub = (cmd: string, args: string[], opts?: unknown) => unknown;
type Callback = (err: Error | null, stdout: Buffer, stderr: Buffer) => void;

const asBuffer = (v: unknown): Buffer => (Buffer.isBuffer(v) ? v : Buffer.from(v === undefined || v === null ? "" : String(v)));

export function execFileFromSync(stub: SyncStub) {
  return (cmd: string, args: string[], opts: unknown, cb?: Callback) => {
    const callback = (typeof opts === "function" ? opts : cb) as Callback;
    const options = typeof opts === "function" ? undefined : opts;
    setImmediate(() => {
      try {
        callback(null, asBuffer(stub(cmd, args, options)), Buffer.alloc(0));
      } catch (e) {
        const src = (e ?? {}) as { status?: unknown; stdout?: unknown; stderr?: unknown };
        const err = Object.assign(e instanceof Error ? e : new Error(String(e)), { code: typeof src.status === "number" ? src.status : 1 });
        callback(err, asBuffer(src.stdout), asBuffer(src.stderr));
      }
    });
    return { stdin: { on: () => undefined, end: () => undefined } };
  };
}
