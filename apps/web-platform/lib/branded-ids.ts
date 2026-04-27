// Branded string identifiers for the Command Center WS protocol (#2885 Stage 3).
//
// At runtime, a branded ID is just a string — there is no boxing, no allocation
// overhead. At compile time, the unique-symbol brand prevents cross-confusion
// (a `PromptId` cannot be passed to a slot expecting a `SpawnId`) and rejects
// raw-string assignment without the corresponding mint helper.
//
// **Stage 3 (this PR) ships the brand types + mint helpers but does NOT yet
// thread them through internal API boundaries** (`PendingPromptRegistry`,
// `cc-dispatcher`, `soleur-go-runner` producer sites). That threading is
// architectural-pivot scope and is tracked as a follow-up issue. Until
// Stage 4 wires the consumers, this module's value is documenting the
// design heuristic from
// `knowledge-base/project/learnings/best-practices/2026-04-27-branded-ids-belong-at-internal-boundaries-not-wire-types.md`
// and exercising the type-system contract via `test/branded-ids.test.ts`.
//
// `WSMessage` deliberately uses plain `string` for IDs because the wire
// format has no brand concept (JSON.stringify drops brands). Brands belong
// at function-signature boundaries, not at the wire-protocol union.

declare const SpawnIdBrand: unique symbol;
declare const PromptIdBrand: unique symbol;
declare const ConversationIdBrand: unique symbol;

export type SpawnId = string & { readonly [SpawnIdBrand]: true };
export type PromptId = string & { readonly [PromptIdBrand]: true };
export type ConversationId = string & { readonly [ConversationIdBrand]: true };

export const mintSpawnId = (s: string): SpawnId => s as SpawnId;
export const mintPromptId = (s: string): PromptId => s as PromptId;
export const mintConversationId = (s: string): ConversationId => s as ConversationId;
