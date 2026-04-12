-- Add archived_at column to conversations table
-- NULL = not archived, timestamptz = when it was archived
-- Orthogonal to status: a "completed" conversation can be archived
-- while preserving its functional status for analytics.
ALTER TABLE public.conversations
ADD COLUMN archived_at timestamptz DEFAULT NULL;

-- Composite index for filtered queries:
-- "show my non-archived conversations" and "show my archived conversations"
CREATE INDEX idx_conversations_user_archived
ON public.conversations (user_id, archived_at);
