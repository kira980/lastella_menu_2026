-- ============================================
-- LaStella Restaurant — Supabase SQL Setup
-- Paste this entire file into Supabase SQL Editor and click Run
-- ============================================

-- 1. Tables
CREATE TABLE IF NOT EXISTS categories (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar    TEXT        NOT NULL,
  name_en    TEXT        NOT NULL DEFAULT '',
  name_he    TEXT        NOT NULL DEFAULT '',
  note_ar    TEXT        NOT NULL DEFAULT '',
  note_en    TEXT        NOT NULL DEFAULT '',
  note_he    TEXT        NOT NULL DEFAULT '',
  tag        TEXT        NOT NULL DEFAULT '',
  sort_order INTEGER     NOT NULL DEFAULT 0,
  is_active  BOOLEAN     NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS menu_items (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id    UUID        NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  name_ar        TEXT        NOT NULL,
  name_en        TEXT        NOT NULL DEFAULT '',
  name_he        TEXT        NOT NULL DEFAULT '',
  description_ar TEXT        NOT NULL DEFAULT '',
  description_en TEXT        NOT NULL DEFAULT '',
  description_he TEXT        NOT NULL DEFAULT '',
  price          NUMERIC(10,2),
  price_label    TEXT        NOT NULL DEFAULT '',
  image_url      TEXT        NOT NULL DEFAULT '',
  is_available   BOOLEAN     NOT NULL DEFAULT true,
  sort_order     INTEGER     NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS settings (
  key        TEXT        PRIMARY KEY,
  value      JSONB       NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS admin_users (
  user_id    UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

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

-- 2. Row Level Security
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Categories
DROP POLICY IF EXISTS "categories_select" ON categories;
DROP POLICY IF EXISTS "categories_insert" ON categories;
DROP POLICY IF EXISTS "categories_update" ON categories;
DROP POLICY IF EXISTS "categories_delete" ON categories;
CREATE POLICY "categories_select" ON categories FOR SELECT
  USING (is_active = true OR public.is_admin());
CREATE POLICY "categories_insert" ON categories FOR INSERT
  WITH CHECK (public.is_admin());
CREATE POLICY "categories_update" ON categories FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY "categories_delete" ON categories FOR DELETE
  USING (public.is_admin());

-- Menu items
DROP POLICY IF EXISTS "items_select" ON menu_items;
DROP POLICY IF EXISTS "items_insert" ON menu_items;
DROP POLICY IF EXISTS "items_update" ON menu_items;
DROP POLICY IF EXISTS "items_delete" ON menu_items;
CREATE POLICY "items_select" ON menu_items FOR SELECT
  USING (
    public.is_admin()
    OR (is_available = true AND EXISTS (
      SELECT 1 FROM categories c
      WHERE c.id = menu_items.category_id AND c.is_active = true
    ))
  );
CREATE POLICY "items_insert" ON menu_items FOR INSERT
  WITH CHECK (public.is_admin());
CREATE POLICY "items_update" ON menu_items FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY "items_delete" ON menu_items FOR DELETE
  USING (public.is_admin());

-- Settings
DROP POLICY IF EXISTS "settings_select" ON settings;
DROP POLICY IF EXISTS "settings_insert" ON settings;
DROP POLICY IF EXISTS "settings_update" ON settings;
DROP POLICY IF EXISTS "settings_delete" ON settings;
CREATE POLICY "settings_select" ON settings FOR SELECT
  USING (key = 'meal_offers' OR public.is_admin());
CREATE POLICY "settings_insert" ON settings FOR INSERT
  WITH CHECK (public.is_admin());
CREATE POLICY "settings_update" ON settings FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY "settings_delete" ON settings FOR DELETE
  USING (public.is_admin());

-- Admin allow-list
DROP POLICY IF EXISTS "admin_users_select" ON admin_users;
CREATE POLICY "admin_users_select" ON admin_users FOR SELECT
  USING (user_id = auth.uid() OR public.is_admin());

-- Storage bucket for uploaded menu images
INSERT INTO storage.buckets (id, name, public)
VALUES ('images', 'images', true)
ON CONFLICT (id) DO NOTHING;
UPDATE storage.buckets
SET
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'images';

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

-- Storage bucket for generated standalone HTML menu backups
INSERT INTO storage.buckets (id, name, public)
VALUES ('backups', 'backups', false)
ON CONFLICT (id) DO NOTHING;
UPDATE storage.buckets
SET
  public = false,
  file_size_limit = 1048576,
  allowed_mime_types = ARRAY['text/html']
WHERE id = 'backups';

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

/*
-- Optional first-time seed data.
-- This block is disabled so rerunning schema.sql cannot duplicate your menu.
-- Keep it commented after your real menu exists in Supabase.

-- 3. Seed categories
INSERT INTO categories (name_ar, name_en, name_he, tag, note_ar, sort_order) VALUES
  ('ستيك ولحوم',         'Steaks & Meat',    'סטייקים ובשרים',   'Steaks',     'ستيكات، مشاوي وأطباق لحم مميّزة.',     1),
  ('وجبات مميزة',        'Signature Meals',  'מנות מיוחדות',     'Signature',  'وجبات مميزة من لاستيلا بتقديم خاص.',  2),
  ('وجبات للطلب المسبق', 'Pre-order Meals',  'מנות בהזמנה מראש', 'Pre-order',  'أطباق كبيرة تحتاج طلباً مسبقاً.',    3),
  ('دجاج',               'Chicken',          'עוף',               'Chicken',    'أطباق دجاج مشوي، مقلي وكريسبي.',       4),
  ('اسماك',              'Fish',             'דגים',              'Fish',       'أسماك طازجة مشوية أو مقلية.',           5),
  ('فواكه بحر',          'Seafood',          'פירות ים',          'Seafood',    'فواكه بحر متنوعة وطازجة.',             6),
  ('مقبلات',             'Appetizers',       'מנות פתיחה',        'Appetizers', 'مقبلات ساخنة وباردة.',                 7),
  ('سلطات',              'Salads',           'סלטים',             'Salads',     'سلطات طازجة تناسب كل الأذواق.',         8),
  ('مطبخ ايطالي',        'Italian Kitchen',  'מטבח איטלקי',       'Italian',    'أطباق ايطالية بلمسة لاستيلا.',          9),
  ('حلويات',             'Desserts',         'קינוחים',           'Desserts',   'حلويات طازجة بعد الوجبة.',             10),
  ('مشروبات',            'Drinks',           'שתייה',             'Drinks',     'مشروبات باردة وساخنة.',                11);

-- 4. Seed items
DO $$
DECLARE
  steaks_id   UUID;
  specials_id UUID;
  preorder_id UUID;
  chicken_id  UUID;
  fish_id     UUID;
  seafood_id  UUID;
  starters_id UUID;
  salads_id   UUID;
  italian_id  UUID;
  desserts_id UUID;
  drinks_id   UUID;
BEGIN
  SELECT id INTO steaks_id   FROM categories WHERE name_ar = 'ستيك ولحوم'         LIMIT 1;
  SELECT id INTO specials_id FROM categories WHERE name_ar = 'وجبات مميزة'        LIMIT 1;
  SELECT id INTO preorder_id FROM categories WHERE name_ar = 'وجبات للطلب المسبق' LIMIT 1;
  SELECT id INTO chicken_id  FROM categories WHERE name_ar = 'دجاج'               LIMIT 1;
  SELECT id INTO fish_id     FROM categories WHERE name_ar = 'اسماك'              LIMIT 1;
  SELECT id INTO seafood_id  FROM categories WHERE name_ar = 'فواكه بحر'          LIMIT 1;
  SELECT id INTO starters_id FROM categories WHERE name_ar = 'مقبلات'             LIMIT 1;
  SELECT id INTO salads_id   FROM categories WHERE name_ar = 'سلطات'              LIMIT 1;
  SELECT id INTO italian_id  FROM categories WHERE name_ar = 'مطبخ ايطالي'        LIMIT 1;
  SELECT id INTO desserts_id FROM categories WHERE name_ar = 'حلويات'             LIMIT 1;
  SELECT id INTO drinks_id   FROM categories WHERE name_ar = 'مشروبات'            LIMIT 1;

  -- Steaks & Meat
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (steaks_id, 'اضلاع خروف',      'Lamb Ribs',            'צלעות טלה',         100, 1),
    (steaks_id, 'ستيك بورتر هاوس', 'Porterhouse Steak',    'סטייק פורטרהאוס',   140, 2),
    (steaks_id, 'ستيك سنتا',       'Sirloin Steak',        'סטייק סינטה',        110, 3),
    (steaks_id, 'ستيك فيليه',      'Beef Fillet Steak',    'סטייק פילה בקר',    110, 4),
    (steaks_id, 'مشاوي برجيت',     'Brisket Grill',        'גריל בריסקט',         65, 5),
    (steaks_id, 'مشاوي كباب',      'Kebab Grill',          'גריל קבב',            65, 6),
    (steaks_id, 'مشكل مشاوي',      'Mixed Grill Platter',  'מגש גריל מעורב',      90, 7),
    (steaks_id, 'كبدة وز',         'Goose Liver',          'כבד אווז',           200, 8),
    (steaks_id, 'ستيك صدر جاج',    'Chicken Breast Steak', 'סטייק חזה עוף',       65, 9);

  -- Signature Meals
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (specials_id, 'ستيك لاستيلا', 'La Stella Steak', 'סטייק לה סטלה', 140, 1),
    (specials_id, 'تريو لاستيلا', 'La Stella Trio',  'טריו לה סטלה',  120, 2);

  -- Pre-order Meals
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, price_label, sort_order) VALUES
    (preorder_id, 'أباط خروف محشي (ل 4 اشخاص)', 'Stuffed Lamb Shoulder (for 4)',    'כתף טלה ממולאת (ל־4)',    500, '', 1),
    (preorder_id, 'رقبة خروف محشية لشخصين',      'Stuffed Lamb Neck (for 2)',        'צוואר טלה ממולא (ל־2)',   300, '', 2),
    (preorder_id, 'موزة خروف محشية (لشخص)',       'Stuffed Lamb Shank (per person)', 'שוק טלה ממולאת (לסועד)', 150, '', 3);

  -- Chicken
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (chicken_id, 'شنيتسل لاستيلا', 'La Stella Schnitzel', 'שניצל לה סטלה', 55, 1),
    (chicken_id, 'كرسبي دجاج',     'Crispy Chicken',       'קריספי עוף',    55, 2);

  -- Fish
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (fish_id, 'سلمون مشوي',        'Grilled Salmon',              'סלמון על הגריל',    75,  1),
    (fish_id, 'سلمون مطبوخ',       'Cooked Salmon',               'סלמון מבושל',       75,  2),
    (fish_id, 'سمك دينيس (عجاج)',  'Denis Fish (whole)',           'דג דניס שלם',       75,  3),
    (fish_id, 'سمك سلطان ابراهيم', 'Sultan Ibrahim Fish',         'דג סולטאן אברהים',  100, 4),
    (fish_id, 'سمك لبراك',         'Lavrak Fish (fried/grilled)', 'דג לברק',            75,  5);

  -- Seafood
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (seafood_id, 'روس كلماري',       'Calamari Heads',              'ראשים של קלמרי',       75, 1),
    (seafood_id, 'قريدس مطبوخ',      'Cooked Shrimp',               'שרימפס מבושל',         80, 2),
    (seafood_id, 'قريدس مقلي',       'Fried Shrimp',                'שרימפס מטוגן',         80, 3),
    (seafood_id, 'كلماري مقلي',      'Fried Calamari',              'קלמרי מטוגן',          75, 4),
    (seafood_id, 'مشكل فواكة البحر', 'Cooked Seafood Mix',          'מיקס פירות ים מבושל',  80, 5);

  -- Appetizers
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (starters_id, 'جبنه مقليه',  'Fried Cheese',      'גבינה מטוגנת',     15, 1),
    (starters_id, 'شيبس بطاطا',  'French Fries',      'צ׳יפס תפוח אדמה',  15, 2),
    (starters_id, 'كبة بالحبة',  'Kibbeh Balls',      'קובה חמה',          5,  3),
    (starters_id, 'معجنات',      'Assorted Pastries', 'מבחר מאפים',        30, 4);

  -- Salads
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (salads_id, 'تبولة صغير',      'Small Tabbouleh',     'טבולה קטנה',    15, 1),
    (salads_id, 'جرجير صغير',      'Small Arugula Salad', 'סלט רוקט קטן',  15, 2),
    (salads_id, 'سلطة عربية صغير', 'Small Arabic Salad',  'סלט ערבי קטן',  15, 3),
    (salads_id, 'فتوش صغير',       'Small Fattoush',      'סלט פטוש קטן',  15, 4),
    (salads_id, 'حمص',             'Hummus',              'חומוס',          15, 5);

  -- Italian Kitchen
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (italian_id, 'رفيولي بالجبنة', 'Cheese Ravioli with Truffle Cream', 'רביולי גבינה ברוטב שמנת וכמהין',  50, 1),
    (italian_id, 'رفيولي بطاطا',   'Potato Ravioli with Truffle Cream', 'רביולי תפוח אדמה ברוטב שמנת',     50, 2),
    (italian_id, 'موكرام',          'Mokram Gratin',                     'מוקראם בגרטין',                    50, 3);

  -- Desserts
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (desserts_id, 'سوفليه', 'Chocolate Soufflé', 'סופלה שוקולד', 30, 1),
    (desserts_id, 'كنافة',  'Knafeh',            'כנאפה',         15, 2),
    (desserts_id, 'كعك',    'Cookies',           'עוגיות',        30, 3);

  -- Drinks
  INSERT INTO menu_items (category_id, name_ar, name_en, name_he, price, sort_order) VALUES
    (drinks_id, 'ابريق ليمونادا', 'Lemonade Jug',     'קנקן לימונדה', 20, 1),
    (drinks_id, 'مشروب كبير',     'Large Soft Drink', 'שתייה גדולה',  20, 2),
    (drinks_id, 'مشروب صغير',     'Small Soft Drink', 'שתייה קטנה',   10, 3);

END $$;
*/
