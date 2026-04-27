-- Run this in Supabase SQL Editor to restrict write access to one admin user.
-- Replace the email below before running.

CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id    UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.admin_users (user_id)
SELECT id
FROM auth.users
WHERE email = 'ahmed.hosh007@gmail.com'
ON CONFLICT (user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users au
    WHERE au.user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "categories_select" ON public.categories;
DROP POLICY IF EXISTS "categories_insert" ON public.categories;
DROP POLICY IF EXISTS "categories_update" ON public.categories;
DROP POLICY IF EXISTS "categories_delete" ON public.categories;

CREATE POLICY "categories_select" ON public.categories FOR SELECT
  USING (is_active = true OR public.is_admin());
CREATE POLICY "categories_insert" ON public.categories FOR INSERT
  WITH CHECK (public.is_admin());
CREATE POLICY "categories_update" ON public.categories FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY "categories_delete" ON public.categories FOR DELETE
  USING (public.is_admin());

DROP POLICY IF EXISTS "items_select" ON public.menu_items;
DROP POLICY IF EXISTS "items_insert" ON public.menu_items;
DROP POLICY IF EXISTS "items_update" ON public.menu_items;
DROP POLICY IF EXISTS "items_delete" ON public.menu_items;

CREATE POLICY "items_select" ON public.menu_items FOR SELECT
  USING (
    public.is_admin()
    OR (is_available = true AND EXISTS (
      SELECT 1 FROM public.categories c
      WHERE c.id = menu_items.category_id AND c.is_active = true
    ))
  );
CREATE POLICY "items_insert" ON public.menu_items FOR INSERT
  WITH CHECK (public.is_admin());
CREATE POLICY "items_update" ON public.menu_items FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY "items_delete" ON public.menu_items FOR DELETE
  USING (public.is_admin());

DROP POLICY IF EXISTS "settings_select" ON public.settings;
DROP POLICY IF EXISTS "settings_insert" ON public.settings;
DROP POLICY IF EXISTS "settings_update" ON public.settings;
DROP POLICY IF EXISTS "settings_delete" ON public.settings;

CREATE POLICY "settings_select" ON public.settings FOR SELECT
  USING (key = 'meal_offers' OR public.is_admin());
CREATE POLICY "settings_insert" ON public.settings FOR INSERT
  WITH CHECK (public.is_admin());
CREATE POLICY "settings_update" ON public.settings FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY "settings_delete" ON public.settings FOR DELETE
  USING (public.is_admin());

DROP POLICY IF EXISTS "admin_users_select" ON public.admin_users;
CREATE POLICY "admin_users_select" ON public.admin_users FOR SELECT
  USING (user_id = auth.uid() OR public.is_admin());

INSERT INTO storage.buckets (id, name, public)
VALUES ('images', 'images', true)
ON CONFLICT (id) DO NOTHING;

UPDATE storage.buckets
SET
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'images';

INSERT INTO storage.buckets (id, name, public)
VALUES ('backups', 'backups', false)
ON CONFLICT (id) DO NOTHING;

UPDATE storage.buckets
SET
  public = false,
  file_size_limit = 1048576,
  allowed_mime_types = ARRAY['text/html']
WHERE id = 'backups';

DROP POLICY IF EXISTS "images_select" ON storage.objects;
DROP POLICY IF EXISTS "images_insert" ON storage.objects;
DROP POLICY IF EXISTS "images_update" ON storage.objects;
DROP POLICY IF EXISTS "images_delete" ON storage.objects;

CREATE POLICY "images_select" ON storage.objects FOR SELECT
  USING (bucket_id = 'images');
CREATE POLICY "images_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'images' AND public.is_admin());
CREATE POLICY "images_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'images' AND public.is_admin())
  WITH CHECK (bucket_id = 'images' AND public.is_admin());
CREATE POLICY "images_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'images' AND public.is_admin());

DROP POLICY IF EXISTS "backups_select" ON storage.objects;
DROP POLICY IF EXISTS "backups_insert" ON storage.objects;
DROP POLICY IF EXISTS "backups_update" ON storage.objects;
DROP POLICY IF EXISTS "backups_delete" ON storage.objects;

CREATE POLICY "backups_select" ON storage.objects FOR SELECT
  USING (bucket_id = 'backups' AND public.is_admin());
CREATE POLICY "backups_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'backups' AND public.is_admin());
CREATE POLICY "backups_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'backups' AND public.is_admin())
  WITH CHECK (bucket_id = 'backups' AND public.is_admin());
CREATE POLICY "backups_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'backups' AND public.is_admin());

NOTIFY pgrst, 'reload schema';
