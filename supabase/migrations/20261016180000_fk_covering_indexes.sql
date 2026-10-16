-- Covering indexes for foreign keys flagged by Supabase advisors / beta-readiness review.
-- Safe to re-run; baseline already includes these for fresh local resets.

CREATE INDEX IF NOT EXISTS circle_seen_document_id_idx
  ON public.circle_seen USING btree (document_id);

CREATE INDEX IF NOT EXISTS follows_target_owner_id_idx
  ON public.follows USING btree (target_owner_id);

CREATE INDEX IF NOT EXISTS mosaic_access_requests_requester_id_idx
  ON public.mosaic_access_requests USING btree (requester_id);
