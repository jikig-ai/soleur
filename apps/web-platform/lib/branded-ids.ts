// Branded string identifiers for the Command Center WS protocol (#2885 Stage 3).
//
// At runtime, a branded ID is just a string — there is no boxing, no allocation
// overhead. At compile time, the unique-symbol brand prevents cross-confusion
// (a `PromptId` cannot be passed to a slot expecting a `SpawnId`) and rejects
// raw-string assignment without the corresponding mint helper.
//
// When a branded value flows through a Zod schema, prefer the schema's own
// `.brand<"PromptId">()` chain (see `lib/ws-zod-schemas.ts`). The mint helpers
// here are for code-side construction (server emit sites, test fixtures).

declare const SpawnIdBrand: unique symbol;
declare const PromptIdBrand: unique symbol;
declare const ConversationIdBrand: unique symbol;

export type SpawnId = string & { readonly [SpawnIdBrand]: true };
export type PromptId = string & { readonly [PromptIdBrand]: true };
export type ConversationId = string & { readonly [ConversationIdBrand]: true };

export const mintSpawnId = (s: string): SpawnId => s as SpawnId;
export const mintPromptId = (s: string): PromptId => s as PromptId;
export const mintConversationId = (s: string): ConversationId => s as ConversationId;
