-- SEC-03 split the owner's FOR ALL media policy into insert / update / delete and dropped SELECT.
-- Storage uploads with x-upsert need SELECT on the object, and a brand-new file is not yet listed
-- in any board's mediaAssets, so viewer_can_read_media denies it and every new upload failed.
-- Owners may read their own folder; visitors still go through viewer_can_read_media.
DROP POLICY IF EXISTS media_storage_owner_select ON storage.objects;
CREATE POLICY media_storage_owner_select ON storage.objects
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        bucket_id = 'media'
        AND (storage.foldername(name))[1] = (auth.uid())::text
    );
