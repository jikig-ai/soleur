-- Tag-and-Route: make domain_leader nullable, add leader attribution to messages
-- Issue: #1059

-- Make domain_leader nullable (remove NOT NULL + CHECK constraint)
-- Existing conversations keep their domain_leader value; new conversations may omit it
ALTER TABLE public.conversations
  ALTER COLUMN domain_leader DROP NOT NULL;

ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_domain_leader_check;

-- Add leader attribution to messages
-- Each assistant message records which domain leader authored it
ALTER TABLE public.messages
  ADD COLUMN leader_id text;
