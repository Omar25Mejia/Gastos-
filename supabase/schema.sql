-- Control Financiero: esquema multiusuario para Supabase
-- Ejecutar en Supabase SQL Editor. RLS está activado en todas las tablas de datos.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'user' check (role in ('user','admin')),
  plan text not null default 'free' check (plan in ('free','basic','pro','premium')),
  created_at timestamptz not null default now()
);

create table if not exists public.debts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  balance numeric(12,2),
  rate numeric(7,3) not null default 0,
  payment numeric(12,2) not null default 0,
  due_day smallint check (due_day between 1 and 31),
  debt_type text not null default 'Otro',
  priority text not null default 'Media' check (priority in ('Alta','Media','Mantener')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  debt_id uuid references public.debts(id) on delete set null,
  payment_date date not null default current_date,
  amount numeric(12,2) not null check (amount >= 0),
  capital numeric(12,2) not null default 0 check (capital >= 0),
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.incomes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  income_date date not null default current_date,
  amount numeric(12,2) not null check (amount >= 0),
  income_type text not null default 'Extra',
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  amount numeric(12,2) not null check (amount >= 0),
  due_day smallint check (due_day between 1 and 31),
  created_at timestamptz not null default now()
);

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  salary numeric(12,2) not null default 0,
  extra_average numeric(12,2) not null default 0,
  cash_reserve numeric(12,2) not null default 0,
  goal_date date,
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  plan text not null default 'free' check (plan in ('free','basic','pro','premium')),
  status text not null default 'active',
  current_period_end timestamptz,
  provider text,
  provider_customer_id text,
  provider_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','')) on conflict(id) do nothing;
  insert into public.user_settings(user_id) values(new.id) on conflict(user_id) do nothing;
  insert into public.subscriptions(user_id) values(new.id) on conflict(user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.debts enable row level security;
alter table public.payments enable row level security;
alter table public.incomes enable row level security;
alter table public.expenses enable row level security;
alter table public.user_settings enable row level security;
alter table public.subscriptions enable row level security;

-- Profiles: cada usuario ve su perfil; admin puede consultar perfiles para soporte/gestión.
create policy "profile own read" on public.profiles for select using (id=auth.uid() or public.is_admin());
create policy "profile own update" on public.profiles for update using (id=auth.uid()) with check (id=auth.uid());

-- Datos financieros: aislamiento por user_id.
create policy "debts own all" on public.debts for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "payments own all" on public.payments for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "incomes own all" on public.incomes for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "expenses own all" on public.expenses for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "settings own all" on public.user_settings for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "subscription own read" on public.subscriptions for select using (user_id=auth.uid() or public.is_admin());

-- Solo administradores pueden modificar suscripciones desde funciones/servidor; el cliente no recibe service_role.

create index if not exists debts_user_id_idx on public.debts(user_id);
create index if not exists payments_user_id_idx on public.payments(user_id);
create index if not exists payments_debt_id_idx on public.payments(debt_id);
create index if not exists incomes_user_id_idx on public.incomes(user_id);
create index if not exists expenses_user_id_idx on public.expenses(user_id);

-- IMPORTANTE: para producción, la asignación del primer admin se hace manualmente en SQL:
-- update public.profiles set role='admin' where id='UUID_DEL_USUARIO';