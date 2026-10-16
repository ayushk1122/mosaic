-- Resolve email-or-username to an auth email for password sign-in.
CREATE OR REPLACE FUNCTION public.email_for_login(p_identifier text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
    cleaned text := lower(trim(p_identifier));
    user_id uuid;
BEGIN
    IF cleaned IS NULL OR cleaned = '' THEN
        RETURN NULL;
    END IF;
    IF cleaned LIKE '%@%' THEN
        RETURN cleaned;
    END IF;
    IF cleaned !~ '^[a-z0-9_]{3,20}$' THEN
        RETURN NULL;
    END IF;
    SELECT profiles.id INTO user_id
      FROM public.profiles
     WHERE profiles.username = cleaned;
    IF user_id IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN (SELECT users.email FROM auth.users users WHERE users.id = user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.email_for_login(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_for_login(text) TO anon, authenticated, service_role;
