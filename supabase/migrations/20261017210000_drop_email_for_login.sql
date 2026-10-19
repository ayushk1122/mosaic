-- email_for_login returned any account's email to anonymous callers. Username sign-in now
-- runs through the username-login Edge Function, which resolves the email server-side.
DROP FUNCTION IF EXISTS public.email_for_login(text);
