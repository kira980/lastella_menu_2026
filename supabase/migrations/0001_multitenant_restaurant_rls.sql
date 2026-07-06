-- BACKUP FIRST using Supabase Dashboard > Database > Backups or `supabase db dump`.
-- Production prerequisite: every category, menu item, and setting already has its correct restaurant_id.
-- This migration never guesses or rewrites tenant ownership.
begin;
create table if not exists public.restaurant(id uuid primary key default gen_random_uuid(),name text not null,slug text,menu_url text,is_active boolean not null default true,created_at timestamptz not null default now(),owner_id uuid references auth.users(id) on delete set null);
alter table public.restaurant add column if not exists owner_id uuid references auth.users(id) on delete set null;
do $$ begin if not exists(select 1 from pg_constraint where conrelid='public.restaurant'::regclass and contype='f' and pg_get_constraintdef(oid) like 'FOREIGN KEY (owner_id)%') then alter table public.restaurant add constraint restaurant_owner_id_fkey foreign key(owner_id) references auth.users(id) on delete set null; end if; end $$;
alter table public.categories add column if not exists restaurant_id uuid references public.restaurant(id) on delete cascade;
alter table public.menu_items add column if not exists restaurant_id uuid references public.restaurant(id) on delete cascade;
alter table public.settings add column if not exists restaurant_id uuid references public.restaurant(id) on delete cascade;
do $$
begin
 if exists(select 1 from public.restaurant where slug is null or btrim(slug)='') then
   raise exception 'Migration stopped: every restaurant must already have a non-empty slug';
 end if;
 if exists(select 1 from public.categories where restaurant_id is null) then
   raise exception 'Migration stopped: categories contains rows without restaurant_id';
 end if;
 if exists(select 1 from public.menu_items where restaurant_id is null) then
   raise exception 'Migration stopped: menu_items contains rows without restaurant_id';
 end if;
 if exists(select 1 from public.settings where restaurant_id is null) then
   raise exception 'Migration stopped: settings contains rows without restaurant_id';
 end if;
 if exists(select 1 from public.menu_items m join public.categories c on c.id=m.category_id where m.restaurant_id<>c.restaurant_id) then
   raise exception 'Migration stopped: a menu item and its category have different restaurant_id values';
 end if;
end $$;
alter table public.restaurant alter column slug set not null;
alter table public.categories alter column restaurant_id set not null;
alter table public.menu_items alter column restaurant_id set not null;
alter table public.settings alter column restaurant_id set not null;
alter table public.settings alter column value set default '{}'::jsonb;
alter table public.settings alter column value set not null;
alter table public.settings alter column updated_at set default now();
create unique index if not exists restaurant_slug_uidx on public.restaurant(slug);
create index if not exists categories_restaurant_sort_idx on public.categories(restaurant_id,sort_order);
create index if not exists menu_items_restaurant_category_sort_idx on public.menu_items(restaurant_id,category_id,sort_order);
create index if not exists settings_restaurant_key_idx on public.settings(restaurant_id,key);
do $$ declare p name; begin select conname into p from pg_constraint where conrelid='public.settings'::regclass and contype='p'; if p is not null and pg_get_constraintdef((select oid from pg_constraint where conname=p and conrelid='public.settings'::regclass))<>'PRIMARY KEY (restaurant_id, key)' then execute format('alter table public.settings drop constraint %I',p); end if; if not exists(select 1 from pg_constraint where conrelid='public.settings'::regclass and contype='p') then alter table public.settings add primary key(restaurant_id,key); end if; end $$;
create or replace function public.validate_menu_item_restaurant() returns trigger language plpgsql set search_path=public as $$ begin if not exists(select 1 from categories c where c.id=new.category_id and c.restaurant_id=new.restaurant_id) then raise exception 'category and menu item must belong to the same restaurant'; end if; return new; end $$;
drop trigger if exists menu_item_restaurant_guard on public.menu_items;
create trigger menu_item_restaurant_guard before insert or update of category_id,restaurant_id on public.menu_items for each row execute function public.validate_menu_item_restaurant();
create or replace function public.touch_settings_updated_at() returns trigger language plpgsql set search_path=public as $$ begin new.updated_at=now(); return new; end $$;
drop trigger if exists settings_touch_updated_at on public.settings;
create trigger settings_touch_updated_at before update on public.settings for each row execute function public.touch_settings_updated_at();
create or replace function public.is_global_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from admin_users where user_id=auth.uid()) $$;
create or replace function public.can_manage_restaurant(p_id uuid) returns boolean language sql stable security definer set search_path=public as $$ select public.is_global_admin() or exists(select 1 from restaurant where id=p_id and owner_id=auth.uid()) $$;
revoke all on function public.is_global_admin() from public; revoke all on function public.can_manage_restaurant(uuid) from public;
grant execute on function public.is_global_admin(),public.can_manage_restaurant(uuid) to anon,authenticated;
alter table public.restaurant enable row level security; alter table public.categories enable row level security; alter table public.menu_items enable row level security; alter table public.settings enable row level security; alter table public.admin_users enable row level security;
do $$ declare x record; begin for x in select tablename,policyname from pg_policies where schemaname='public' and tablename in('restaurant','categories','menu_items','settings','admin_users') loop execute format('drop policy if exists %I on public.%I',x.policyname,x.tablename); end loop; end $$;
create policy restaurant_read on public.restaurant for select using(is_active or public.can_manage_restaurant(id));
create policy restaurant_insert on public.restaurant for insert with check(public.is_global_admin() or owner_id=auth.uid());
create policy restaurant_update on public.restaurant for update using(public.can_manage_restaurant(id)) with check(public.can_manage_restaurant(id));
create policy restaurant_delete on public.restaurant for delete using(public.can_manage_restaurant(id));
create policy categories_read on public.categories for select using(public.can_manage_restaurant(restaurant_id) or (is_active and exists(select 1 from restaurant r where r.id=restaurant_id and r.is_active)));
create policy categories_insert on public.categories for insert with check(public.can_manage_restaurant(restaurant_id));
create policy categories_update on public.categories for update using(public.can_manage_restaurant(restaurant_id)) with check(public.can_manage_restaurant(restaurant_id));
create policy categories_delete on public.categories for delete using(public.can_manage_restaurant(restaurant_id));
create policy items_read on public.menu_items for select using(public.can_manage_restaurant(restaurant_id) or (is_available and exists(select 1 from restaurant r where r.id=restaurant_id and r.is_active)));
create policy items_insert on public.menu_items for insert with check(public.can_manage_restaurant(restaurant_id));
create policy items_update on public.menu_items for update using(public.can_manage_restaurant(restaurant_id)) with check(public.can_manage_restaurant(restaurant_id));
create policy items_delete on public.menu_items for delete using(public.can_manage_restaurant(restaurant_id));
create policy settings_read on public.settings for select using(public.can_manage_restaurant(restaurant_id) or (key='meal_offers' and exists(select 1 from restaurant r where r.id=restaurant_id and r.is_active)));
create policy settings_insert on public.settings for insert with check(public.can_manage_restaurant(restaurant_id));
create policy settings_update on public.settings for update using(public.can_manage_restaurant(restaurant_id)) with check(public.can_manage_restaurant(restaurant_id));
create policy settings_delete on public.settings for delete using(public.can_manage_restaurant(restaurant_id));
create policy admins_read on public.admin_users for select using(user_id=auth.uid() or public.is_global_admin());
create policy admins_insert on public.admin_users for insert with check(public.is_global_admin());
create policy admins_update on public.admin_users for update using(public.is_global_admin()) with check(public.is_global_admin());
create policy admins_delete on public.admin_users for delete using(public.is_global_admin());

-- Storage is tenant-scoped by the first path component (the restaurant slug).
drop policy if exists images_insert on storage.objects; drop policy if exists images_update on storage.objects; drop policy if exists images_delete on storage.objects;
create policy images_insert on storage.objects for insert with check(bucket_id='images' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id)));
create policy images_update on storage.objects for update using(bucket_id='images' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id))) with check(bucket_id='images' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id)));
create policy images_delete on storage.objects for delete using(bucket_id='images' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id)));
drop policy if exists backups_select on storage.objects; drop policy if exists backups_insert on storage.objects; drop policy if exists backups_update on storage.objects; drop policy if exists backups_delete on storage.objects;
create policy backups_select on storage.objects for select using(bucket_id='backups' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id)));
create policy backups_insert on storage.objects for insert with check(bucket_id='backups' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id)));
create policy backups_update on storage.objects for update using(bucket_id='backups' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id))) with check(bucket_id='backups' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id)));
create policy backups_delete on storage.objects for delete using(bucket_id='backups' and exists(select 1 from restaurant r where r.slug=(storage.foldername(name))[1] and public.can_manage_restaurant(r.id)));
commit;
