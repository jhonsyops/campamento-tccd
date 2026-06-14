-- ============================================================
--  CAMPAMENTO TCCD — Schema v3 (Transferencias + Efectivo)
--  Sin pasarelas de pago: el campista transfiere desde su banco,
--  reporta el comprobante, y un admin lo verifica y aprueba.
-- ============================================================

-- 1) INSCRIPCIONES
create table if not exists public.registrations (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,
  name        text not null,
  age         int  not null check (age >= 0 and age < 120),
  role        text not null check (role in ('camper','leader')),
  church      text not null,
  allergies   text default 'Ninguna',
  phone       text not null,
  email       text,
  size        text not null,
  tier        text not null,
  total       int  not null,
  checkin     boolean default false,
  note        text,
  cabin       text,
  created_at  timestamptz default now()
);

-- 2) PAGOS CONFIRMADOS (transferencias aprobadas + efectivo)
create table if not exists public.payments (
  id           uuid primary key default gen_random_uuid(),
  registration uuid not null references public.registrations(id) on delete cascade,
  amount       int  not null check (amount > 0),
  method       text not null,                 -- 'Transferencia — Banreservas' | 'Efectivo' | ...
  kind         text not null default 'cash' check (kind in ('transfer','cash')),
  ref          text,
  created_at   timestamptz default now()
);

-- 3) REPORTES DE TRANSFERENCIA (cola de verificación)
create table if not exists public.transfer_reports (
  id            uuid primary key default gen_random_uuid(),
  registration  uuid not null references public.registrations(id) on delete cascade,
  bank          text not null,
  amount        int  not null check (amount > 0),
  ref           text,                          -- referencia del banco (puede faltar si hay captura)
  date          date,                          -- fecha de la transferencia
  shot          text,                          -- path del comprobante en Storage (puede faltar si hay ref)
  status        text not null default 'pending' check (status in ('pending','approved','rejected')),
  reject_reason text,
  created_at    timestamptz default now()
);

-- 4) ADMINS
create table if not exists public.admins (
  email text primary key,
  name  text
);
insert into public.admins(email,name) values
  ('jhonfrer@tccd.do','Jhonfrer'),
  ('genesis@tccd.do','Genesis'),
  ('tesoreria@tccd.do','Tesoreria')
on conflict(email) do nothing;

create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = pg_catalog, public as $$
  select exists(select 1 from public.admins where email = (auth.jwt() ->> 'email'));
$$;

-- ============================================================
--  ROW LEVEL SECURITY
-- ============================================================
alter table public.registrations    enable row level security;
alter table public.payments         enable row level security;
alter table public.transfer_reports enable row level security;
alter table public.admins           enable row level security;

-- Inscripciones: público inserta; solo admins ven/editan/borran
drop policy if exists "publico se inscribe" on public.registrations;
create policy "publico se inscribe" on public.registrations for insert to anon, authenticated with check (true);
drop policy if exists "admins ven inscripciones" on public.registrations;
create policy "admins ven inscripciones" on public.registrations for select to authenticated using (public.is_admin());
drop policy if exists "admins editan inscripciones" on public.registrations;
create policy "admins editan inscripciones" on public.registrations for update to authenticated using (public.is_admin());
drop policy if exists "admins borran inscripciones" on public.registrations;
create policy "admins borran inscripciones" on public.registrations for delete to authenticated using (public.is_admin());

-- Pagos: SOLO admins (ver e insertar). El campista nunca crea pagos directos:
-- reporta una transferencia y el admin la aprueba.
drop policy if exists "admins ven pagos" on public.payments;
create policy "admins ven pagos" on public.payments for select to authenticated using (public.is_admin());
drop policy if exists "admins registran pagos" on public.payments;
create policy "admins registran pagos" on public.payments for insert to authenticated with check (public.is_admin());

-- Reportes: público inserta (reportar su transferencia); solo admins ven/actualizan
drop policy if exists "publico reporta transferencia" on public.transfer_reports;
create policy "publico reporta transferencia" on public.transfer_reports for insert to anon, authenticated with check (true);
drop policy if exists "admins ven reportes" on public.transfer_reports;
create policy "admins ven reportes" on public.transfer_reports for select to authenticated using (public.is_admin());
drop policy if exists "admins actualizan reportes" on public.transfer_reports;
create policy "admins actualizan reportes" on public.transfer_reports for update to authenticated using (public.is_admin());

drop policy if exists "admins ven admins" on public.admins;
create policy "admins ven admins" on public.admins for select to authenticated using (public.is_admin());

-- ============================================================
--  RPC: Portal del campista (sin login)
--  Devuelve datos + pagos confirmados + reportes (con estado) +
--  monto en verificación. Se puede entrar por CÓDIGO o por WHATSAPP.
-- ============================================================

-- Helper interno: construye el JSON completo de una inscripción
create or replace function public._registration_json(p_id uuid)
returns json language sql security definer stable set search_path = pg_catalog, public as $$
  select row_to_json(r) from (
    select reg.id, reg.code, reg.name, reg.role, reg.tier, reg.total, reg.age, reg.size, reg.cabin,
      coalesce((
        select json_agg(json_build_object('id',p.id,'amount',p.amount,'method',p.method,
          'kind',p.kind,'ref',p.ref,'created_at',p.created_at) order by p.created_at)
        from public.payments p where p.registration = reg.id
      ),'[]') as payments,
      coalesce((
        select json_agg(json_build_object('id',t.id,'bank',t.bank,'amount',t.amount,'ref',t.ref,
          'date',t.date,'status',t.status,'reject_reason',t.reject_reason,'created_at',t.created_at)
          order by t.created_at)
        from public.transfer_reports t where t.registration = reg.id
      ),'[]') as reports,
      coalesce((
        select sum(t.amount)::int from public.transfer_reports t
        where t.registration = reg.id and t.status = 'pending'
      ),0) as pending_verification
    from public.registrations reg where reg.id = p_id
  ) r;
$$;

-- Entrar con el código
create or replace function public.get_registration_by_code(p_code text)
returns json language sql security definer stable set search_path = pg_catalog, public as $$
  select public._registration_json(reg.id) from public.registrations reg
  where lower(reg.code) = lower(p_code) limit 1;
$$;
grant execute on function public.get_registration_by_code(text) to anon, authenticated;

-- Recuperar/entrar con el WhatsApp (compara los últimos 10 dígitos)
create or replace function public.get_registration_by_phone(p_phone text)
returns json language sql security definer stable set search_path = pg_catalog, public as $$
  select public._registration_json(reg.id) from public.registrations reg
  where right(regexp_replace(reg.phone,'[^0-9]','','g'),10)
      = right(regexp_replace(p_phone,'[^0-9]','','g'),10) limit 1;
$$;
grant execute on function public.get_registration_by_phone(text) to anon, authenticated;

-- ============================================================
--  STORAGE: bucket para los comprobantes (capturas)
--  Ejecuta esto, y si da error de permisos hazlo desde la UI:
--  Storage → New bucket → "vouchers" (private)
-- ============================================================
insert into storage.buckets (id, name, public) values ('vouchers','vouchers', false)
on conflict (id) do nothing;

-- El público puede SUBIR su comprobante; solo admins pueden VERLO
drop policy if exists "publico sube voucher" on storage.objects;
create policy "publico sube voucher" on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'vouchers');
drop policy if exists "admins ven vouchers" on storage.objects;
create policy "admins ven vouchers" on storage.objects
  for select to authenticated using (bucket_id = 'vouchers' and public.is_admin());

-- NOTA para el front (producción): al mostrar un comprobante en la cola
-- de verificación, genera un signed URL:
--   const { data } = await sb.storage.from('vouchers').createSignedUrl(rep.shot, 3600);
--   rep.shotUrl = data.signedUrl;

-- ============================================================
--  ENDURECIMIENTO DE SEGURIDAD (validación del lado del servidor)
--  Motivo: la "anon key" es pública; cualquiera puede llamar la API
--  saltándose el formulario. NUNCA confíes en lo que envía el cliente.
--  Aquí el servidor calcula precio/tier/código y valida los datos.
-- ============================================================

-- 1) Trigger autoritativo en inscripciones:
--    el cliente NO decide el precio, el tier ni el código.
create or replace function public.reg_guard()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public as $$
begin
  new.name := btrim(coalesce(new.name,''));
  if char_length(new.name) < 2 then
    raise exception 'Nombre invalido';
  end if;
  if new.age is null or new.age < 0 or new.age >= 120 then
    raise exception 'Edad invalida';
  end if;
  -- Precio y tier AUTORITATIVOS segun la edad (ignora lo que mande el cliente).
  -- ⚠️ Manten estos montos sincronizados con CONFIG.TIERS del front.
  if new.age < 11 then new.tier := 'kids';   new.total := 2500;
  else                 new.tier := 'normal'; new.total := 4500; end if;
  -- El codigo lo genera el servidor (se descarta el que mande el cliente).
  new.code := 'TCCD-' || upper(substr(md5(gen_random_uuid()::text), 1, 4));
  -- Defaults seguros: nadie se autoasigna check-in / notas en el insert.
  new.checkin := false;
  new.note := null;
  return new;
end$$;

drop trigger if exists trg_reg_guard on public.registrations;
create trigger trg_reg_guard before insert on public.registrations
  for each row execute function public.reg_guard();

-- 2) Restricciones de formato/longitud (idempotentes).
do $$ begin
  alter table public.registrations add constraint reg_name_len   check (char_length(name) between 2 and 80);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.registrations add constraint reg_phone_fmt  check (phone ~ '^[0-9 +().-]{10,20}$');
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.registrations add constraint reg_email_len  check (email is null or char_length(email) <= 120);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.registrations add constraint reg_aller_len  check (allergies is null or char_length(allergies) <= 300);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.registrations add constraint reg_note_len   check (note is null or char_length(note) <= 600);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.registrations add constraint reg_church_len check (char_length(church) <= 80);
exception when duplicate_object then null; end $$;

-- 3) Validacion de los reportes de transferencia (limites razonables).
do $$ begin
  alter table public.transfer_reports add constraint rep_amt_max  check (amount > 0 and amount <= 1000000);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.transfer_reports add constraint rep_bank_len check (char_length(bank) <= 60);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.transfer_reports add constraint rep_ref_len  check (ref is null or char_length(ref) <= 60);
exception when duplicate_object then null; end $$;

-- 4) Almacenamiento de comprobantes:
--    el bucket ya es PRIVADO (solo admins leen). Ademas, en el panel de
--    Supabase -> Storage -> bucket "vouchers" configura:
--      - File size limit: 5 MB
--      - Allowed MIME types: image/png, image/jpeg, image/webp
--    Eso evita que suban ejecutables o archivos enormes.

-- 5) (Opcional, recomendado) Rate limiting / anti-spam:
--    El insert publico de inscripciones y de reportes esta abierto a 'anon'
--    por diseno (no hay login para el campista). Para mitigar abuso:
--      - Activa "Bot/Abuse protection" y CAPTCHA en Supabase Auth/Edge.
--      - O coloca un Edge Function/proxy con rate limit por IP delante.
--    El control compensatorio clave ya existe: NINGUN pago se acredita solo;
--    un admin verifica cada transferencia contra el banco antes de aprobar.
