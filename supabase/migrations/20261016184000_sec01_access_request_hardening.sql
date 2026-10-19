-- SEC-01: Access requests are RPC-only; Pursuit requests stay bound to the real document owner.
-- Fixes forged approval by retargeting pursuit_id / requester_id via direct UPDATE.

-- Bind pursuit request owner to the document's owner; freeze identity columns after insert.
CREATE OR REPLACE FUNCTION public.bind_pursuit_access_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    real_owner uuid;
BEGIN
    SELECT documents.owner_id
      INTO real_owner
      FROM public.documents
     WHERE documents.id = NEW.pursuit_id
       AND documents.role = 'pursuit';

    IF real_owner IS NULL THEN
        RAISE EXCEPTION 'pursuit not requestable' USING ERRCODE = '42501';
    END IF;

    NEW.owner_id := real_owner;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.pursuit_id IS DISTINCT FROM OLD.pursuit_id
           OR NEW.requester_id IS DISTINCT FROM OLD.requester_id
           OR NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
            RAISE EXCEPTION 'request identity is immutable' USING ERRCODE = '22023';
        END IF;
    END IF;

    IF NEW.owner_id = NEW.requester_id THEN
        RAISE EXCEPTION 'cannot request own pursuit' USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pursuit_access_bind_owner ON public.pursuit_access_requests;
CREATE TRIGGER pursuit_access_bind_owner
    BEFORE INSERT OR UPDATE ON public.pursuit_access_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.bind_pursuit_access_request();

-- Mosaic request identity (owner / requester) cannot be rewritten after insert.
CREATE OR REPLACE FUNCTION public.bind_mosaic_access_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.owner_id IS DISTINCT FROM OLD.owner_id
           OR NEW.requester_id IS DISTINCT FROM OLD.requester_id THEN
            RAISE EXCEPTION 'request identity is immutable' USING ERRCODE = '22023';
        END IF;
    END IF;

    IF NEW.owner_id = NEW.requester_id THEN
        RAISE EXCEPTION 'cannot request own mosaic' USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS mosaic_access_bind_identity ON public.mosaic_access_requests;
CREATE TRIGGER mosaic_access_bind_identity
    BEFORE INSERT OR UPDATE ON public.mosaic_access_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.bind_mosaic_access_request();

-- Accepted Pursuit access must still name the Pursuit's real owner.
CREATE OR REPLACE FUNCTION public.viewer_can_open_pursuit(p_pursuit_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.documents pursuit
        WHERE pursuit.id = p_pursuit_id
          AND pursuit.role = 'pursuit'
          AND auth.uid() IS NOT NULL
          AND (
              pursuit.owner_id = auth.uid()
              OR (
                  public.viewer_passes_mosaic_gate(pursuit.owner_id)
                  AND (
                      pursuit.visibility = 'public'
                      OR (
                          pursuit.visibility = 'private'
                          AND EXISTS (
                              SELECT 1
                              FROM public.pursuit_access_requests request
                              WHERE request.pursuit_id = pursuit.id
                                AND request.owner_id = pursuit.owner_id
                                AND request.requester_id = auth.uid()
                                AND request.status = 'accepted'
                          )
                      )
                  )
              )
          )
    );
$$;

-- Drop direct write policies; SELECT policies remain for inbox UI.
DROP POLICY IF EXISTS pursuit_access_insert_requester ON public.pursuit_access_requests;
DROP POLICY IF EXISTS pursuit_access_update_owner ON public.pursuit_access_requests;
DROP POLICY IF EXISTS pursuit_access_delete_requester ON public.pursuit_access_requests;
DROP POLICY IF EXISTS access_insert_requester ON public.mosaic_access_requests;
DROP POLICY IF EXISTS access_update_owner ON public.mosaic_access_requests;

-- Authenticated clients may only read request rows; mutations go through SECURITY DEFINER RPCs.
REVOKE INSERT, UPDATE, DELETE ON TABLE public.pursuit_access_requests FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.mosaic_access_requests FROM authenticated, anon;
GRANT SELECT ON TABLE public.pursuit_access_requests TO authenticated;
GRANT SELECT ON TABLE public.mosaic_access_requests TO authenticated;

-- Trigger helpers stay off the API surface.
REVOKE ALL ON FUNCTION public.bind_pursuit_access_request() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bind_mosaic_access_request() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_pursuit_access_request() TO service_role;
GRANT EXECUTE ON FUNCTION public.bind_mosaic_access_request() TO service_role;
