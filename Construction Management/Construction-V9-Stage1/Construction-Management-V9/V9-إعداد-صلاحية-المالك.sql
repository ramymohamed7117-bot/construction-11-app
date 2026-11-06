-- V9: تسجيل حساب المالك بأمان دون تعديل أو حذف بيانات app_records الحالية.
-- نفّذ هذا الملف مرة واحدة من Supabase SQL Editor بعد التأكد من وجود حساب المالك في Authentication > Users.

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.app_admins enable row level security;

drop policy if exists "app_admins_select_self" on public.app_admins;
create policy "app_admins_select_self" on public.app_admins
  for select to authenticated using (auth.uid() = user_id);

-- لا توجد سياسات INSERT أو UPDATE أو DELETE للمستخدمين من المتصفح.
-- إضافة المالك تتم إداريًا من SQL فقط باستخدام UID المطابق للبريد المؤكد.
insert into public.app_admins (user_id)
select id from auth.users
where lower(email) = lower('ramymohamed7117@gmail.com')
on conflict (user_id) do nothing;

-- تحقق: يجب أن يعرض الاستعلام صفًا واحدًا فقط.
select a.user_id, u.email, a.created_at
from public.app_admins a
join auth.users u on u.id = a.user_id
where lower(u.email) = lower('ramymohamed7117@gmail.com');
