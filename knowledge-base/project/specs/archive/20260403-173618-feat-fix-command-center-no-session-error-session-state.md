# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-04-03-fix-command-center-chat-race-condition-plan.md
- Status: complete

### Errors

None

### Decisions

- Root cause is a client-side race condition, not a server bug. Two useEffect hooks fire in the same React render cycle: the first sends start_session and optimistically sets sessionStarted = true, the second sees sessionStarted and immediately sends the chat message before the server has created the conversation.
- Fix on the client, not the server. The server guard (if (!session.conversationId)) is correct defense-in-depth.
- Add sessionConfirmed state to useWebSocket hook that tracks the server's session_started response, and gate the initial message send on that instead of the client-side sessionStarted flag.
- Reset sessionConfirmed in three places: in startSession(), in connect() (reconnection path), and in teardown() (non-transient close codes).
- Keep sessionStarted naming unchanged to minimize diff noise in a bug fix.

### Components Invoked

- soleur:plan
- soleur:plan-review (DHH, Kieran, code-simplicity reviewers)
- soleur:deepen-plan (Context7, institutional learnings, review feedback)
