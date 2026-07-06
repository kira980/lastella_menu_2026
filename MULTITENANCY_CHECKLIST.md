# Multi-tenancy deployment checklist

1. Create a verified Supabase backup, then run `supabase/migrations/0001_multitenant_restaurant_rls.sql` as database owner.
2. Set `restaurant.owner_id` for each owner. Keep only trusted platform operators in `admin_users`.
3. Create `lastella` and `burgerhouse`, with one category, item, and `meal_offers` setting each.
4. Confirm `index.html?restaurant=lastella` and `index.html?restaurant=burgerhouse` show no cross-tenant rows.
5. Sign in as each owner. Confirm their own admin URL works and the other restaurant URL returns no manageable restaurant/data. Confirm a global admin can use both URLs.
6. Confirm uploads appear under `images/lastella/` or `images/burgerhouse/`; cleanup must never remove the other folder. Backups are similarly slug-prefixed.
7. Run:

```sql
select restaurant_id,count(*) from categories group by restaurant_id;
select restaurant_id,count(*) from menu_items group by restaurant_id;
select restaurant_id,key from settings order by restaurant_id,key;
select m.id from menu_items m join categories c on c.id=m.category_id where m.restaurant_id<>c.restaurant_id;
```

8. As the LaStella authenticated client, attempt an update/delete/insert using Burger House IDs and an upload into `burgerhouse/`. Every operation must fail or affect zero rows. Repeat in reverse.
9. Verify inactive restaurants, categories, and unavailable items are absent publicly, while their owner can still see them in admin.
10. Confirm the browser uses only the anon key. Never place a service-role key or password in frontend files.
