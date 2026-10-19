-- Neither function is called by the app or used in a row-level security policy.
-- viewer_can_open_pursuit is still used inside SECURITY DEFINER functions, which run as the owner.
revoke all on function public.circle_counts() from public, anon, authenticated;
revoke all on function public.viewer_can_open_pursuit(uuid) from public, anon, authenticated;
