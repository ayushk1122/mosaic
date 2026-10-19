-- The onboarding backfill marked every existing profile as onboarded, including accounts
-- that never chose a username and still carry the handle_new_user placeholder.
UPDATE public.profiles
   SET onboarded_at = NULL,
       updated_at = now()
 WHERE onboarded_at IS NOT NULL
   AND username = 'user_' || substr(replace(id::text, '-', ''), 1, 12);
