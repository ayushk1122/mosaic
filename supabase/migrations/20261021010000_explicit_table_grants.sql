-- From 2026-10-30, Supabase stops granting Data API access to new tables in "public"
-- automatically; every table needs explicit grants in the migration that creates it.
-- Every existing table already grants what it needs. Two tables still carried access that came
-- only from the old automatic grant, so a database rebuilt from these migrations didn't match
-- the live one. No policy relies on either, and both are written through functions only.

-- profile_private: its migration revoked writes but not anon's read.
REVOKE ALL ON TABLE public.profile_private FROM anon;

-- visits: service-only on the live project; the baseline granted service_role but never revoked
-- the automatic anon/authenticated access in rebuilt databases.
REVOKE ALL ON TABLE public.visits FROM anon, authenticated;
