-- Onboarding: profile completion gate and private birthday storage.

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS onboarded_at timestamptz;

UPDATE public.profiles
   SET onboarded_at = created_at
 WHERE onboarded_at IS NULL;

CREATE TABLE public.profile_private (
    user_id uuid NOT NULL PRIMARY KEY REFERENCES public.profiles (id) ON DELETE CASCADE,
    birthday date NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profile_private ENABLE ROW LEVEL SECURITY;

CREATE POLICY profile_private_owner_select ON public.profile_private
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));

REVOKE INSERT, UPDATE, DELETE ON TABLE public.profile_private FROM authenticated, anon;
GRANT SELECT ON TABLE public.profile_private TO authenticated;
GRANT ALL ON TABLE public.profile_private TO service_role;

CREATE OR REPLACE FUNCTION public.validate_birthday(p_birthday date)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_birthday IS NULL THEN
        RAISE EXCEPTION 'birthday required' USING ERRCODE = '22023';
    END IF;
    IF p_birthday >= current_date THEN
        RAISE EXCEPTION 'birthday must be in the past' USING ERRCODE = '22023';
    END IF;
    IF p_birthday < (current_date - interval '120 years')::date THEN
        RAISE EXCEPTION 'birthday out of range' USING ERRCODE = '22023';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_birthday(date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_birthday(date) TO service_role;

CREATE OR REPLACE FUNCTION public.onboarding_status()
RETURNS TABLE (
    onboarded_at timestamptz,
    username text,
    display_name text,
    birthday date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT
        profile.onboarded_at,
        profile.username,
        profile.display_name,
        private.birthday
    FROM public.profiles profile
    LEFT JOIN public.profile_private private ON private.user_id = profile.id
    WHERE profile.id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.complete_onboarding(
    p_username text,
    p_display_name text,
    p_birthday date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    cleaned_username text;
    cleaned_display text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'sign in required' USING ERRCODE = '28000';
    END IF;

    cleaned_username := lower(trim(p_username));
    cleaned_display := left(trim(coalesce(p_display_name, '')), 40);

    IF cleaned_username !~ '^[a-z0-9_]{3,20}$' THEN
        RAISE EXCEPTION 'invalid username' USING ERRCODE = '22023';
    END IF;

    PERFORM public.validate_birthday(p_birthday);

    IF EXISTS (
        SELECT 1 FROM public.profiles
        WHERE onboarded_at IS NOT NULL AND id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'already onboarded' USING ERRCODE = '22023';
    END IF;

    UPDATE public.profiles
       SET username = cleaned_username,
           display_name = NULLIF(cleaned_display, ''),
           onboarded_at = now(),
           updated_at = now()
     WHERE id = auth.uid()
       AND onboarded_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'already onboarded' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.profile_private (user_id, birthday, updated_at)
    VALUES (auth.uid(), p_birthday, now())
    ON CONFLICT (user_id) DO UPDATE
        SET birthday = EXCLUDED.birthday,
            updated_at = now();
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'username taken' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.update_private_birthday(p_birthday date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'sign in required' USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND onboarded_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = '42501';
    END IF;

    PERFORM public.validate_birthday(p_birthday);

    INSERT INTO public.profile_private (user_id, birthday, updated_at)
    VALUES (auth.uid(), p_birthday, now())
    ON CONFLICT (user_id) DO UPDATE
        SET birthday = EXCLUDED.birthday,
            updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.onboarding_status() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_onboarding(text, text, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_private_birthday(date) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.onboarding_status() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_onboarding(text, text, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_private_birthday(date) TO authenticated, service_role;
