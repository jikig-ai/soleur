-- 180_approval_request.down.sql
-- Reverse 180: drop the approval RPCs, the guard trigger function, the table, and restore the narrower
-- inbox_item.source CHECK. The approval-sourced inbox rows are deleted first (they would violate the restored
-- CHECK); they are derived notifications, the approval_request rows (dropped below) are the record.

DROP FUNCTION IF EXISTS public.anonymise_approval_request(uuid);
DROP FUNCTION IF EXISTS public.sweep_approvals();
DROP FUNCTION IF EXISTS public.list_live_approvals(uuid);
DROP FUNCTION IF EXISTS public.get_approval_status(uuid);
DROP FUNCTION IF EXISTS public.consume_approval(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.decide_approval(uuid, text);
DROP FUNCTION IF EXISTS public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer);
DROP FUNCTION IF EXISTS public.approval_request_inbox_settle(uuid, text);

DROP TABLE IF EXISTS public.approval_request;
DROP FUNCTION IF EXISTS public.approval_request_guard();

DELETE FROM public.inbox_item
 WHERE source = 'approval_required';

ALTER TABLE public.inbox_item DROP CONSTRAINT IF EXISTS inbox_item_source_check;
ALTER TABLE public.inbox_item
  ADD CONSTRAINT inbox_item_source_check
  CHECK (source IN ('task_completed', 'system'))
  NOT VALID;
ALTER TABLE public.inbox_item VALIDATE CONSTRAINT inbox_item_source_check;
