-- =====================================================================
-- Maschinenring – Datenbank für Supabase
-- Einmal komplett im Supabase SQL Editor ausführen (New query → Run).
--
-- VORHER UNTEN BEI "ERSTER ADMIN" DEINE E-MAIL-ADRESSE EINTRAGEN!
-- =====================================================================

create extension if not exists btree_gist;

-- ---------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------

-- Mitglieder (1:1 zu Supabase-Login)
create table public.members (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null check (length(trim(name)) between 1 and 40),
  email       text not null unique,
  role        text not null default 'Mitglied' check (role in ('Admin','Mitglied')),
  since       date not null default current_date,
  rules_accepted_at timestamptz
);

-- Einladungen (gültig 7 Tage ab created_at)
create table public.invites (
  id          bigint generated always as identity primary key,
  email       text not null check (email = lower(trim(email)) and email like '%_@_%._%'),
  name        text,
  invited_by  uuid references public.members(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  status      text not null default 'offen' check (status in ('offen','angenommen')),
  accepted_at timestamptz
);
create unique index invites_one_open_per_email on public.invites (email) where status = 'offen';

-- Geräte
create table public.tools (
  id          bigint generated always as identity primary key,
  name        text not null check (length(trim(name)) between 1 and 80),
  category    text not null check (category in ('bohren','saegen','garten','reinigen','messen','bau','sonstiges')),
  owner       uuid not null references public.members(id) on delete restrict default auth.uid(),
  power       text not null default '230 V',
  accessories text[] not null default '{}',
  note        text not null default '',
  created_at  timestamptz not null default now()
);

-- Ausleihen
create table public.bookings (
  id          bigint generated always as identity primary key,
  tool_id     bigint not null references public.tools(id) on delete cascade,
  borrower    uuid not null references public.members(id) on delete cascade default auth.uid(),
  date_from   date not null,
  date_to     date not null,
  status      text not null default 'angefragt' check (status in ('angefragt','bestätigt','abgelehnt','zurück')),
  purpose     text not null default '',
  created_at  timestamptz not null default now(),
  check (date_to >= date_from),
  -- Zwei bestätigte Ausleihen desselben Geräts dürfen sich nie überschneiden
  constraint keine_doppelbuchung exclude using gist (
    tool_id with =, daterange(date_from, date_to, '[]') with &&
  ) where (status = 'bestätigt')
);

-- Schäden und Wartung
create table public.issues (
  id          bigint generated always as identity primary key,
  tool_id     bigint not null references public.tools(id) on delete cascade,
  kind        text not null check (kind in ('Schaden','Wartung')),
  text        text not null check (length(trim(text)) between 1 and 500),
  reported_by uuid references public.members(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  blocking    boolean not null default false,
  done        boolean not null default false,
  done_at     timestamptz
);

create index on public.bookings (tool_id, date_from);
create index on public.issues (tool_id) where not done;

-- ---------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------
create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where id = auth.uid())
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where id = auth.uid() and role = 'Admin')
$$;

-- ---------------------------------------------------------------------
-- Zugriffsregeln (Row Level Security)
-- Lesen: nur Mitglieder. Schreiben: nur das Eigene, Rest über Funktionen.
-- ---------------------------------------------------------------------
alter table public.members  enable row level security;
alter table public.invites  enable row level security;
alter table public.tools    enable row level security;
alter table public.bookings enable row level security;
alter table public.issues   enable row level security;

revoke all on public.members, public.invites, public.tools, public.bookings, public.issues from anon, authenticated;
grant select on public.members, public.invites, public.tools, public.bookings, public.issues to authenticated;

-- Mitglieder: alle sehen alle; jeder ändert nur seinen eigenen Namen; Admin entfernt
create policy m_read   on public.members for select to authenticated using (is_member() or id = auth.uid());
grant update (name) on public.members to authenticated;
create policy m_update on public.members for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
grant delete on public.members to authenticated;
create policy m_delete on public.members for delete to authenticated using (is_admin() and id <> auth.uid());

-- Einladungen: jedes Mitglied lädt ein; erneut senden/zurückziehen: Einladender oder Admin
create policy i_read   on public.invites for select to authenticated using (is_member());
grant insert (email, name) on public.invites to authenticated;
create policy i_insert on public.invites for insert to authenticated with check (is_member() and invited_by = auth.uid() and status = 'offen');
grant update (created_at) on public.invites to authenticated;
create policy i_update on public.invites for update to authenticated
  using (status = 'offen' and (invited_by = auth.uid() or is_admin()))
  with check (created_at <= now() + interval '1 minute');
grant delete on public.invites to authenticated;
create policy i_delete on public.invites for delete to authenticated using (status = 'offen' and (invited_by = auth.uid() or is_admin()));

-- Geräte: alle sehen alle; Besitzer pflegt seine Geräte; Admin darf alles
create policy t_read   on public.tools for select to authenticated using (is_member());
grant insert (name, category, power, accessories, note) on public.tools to authenticated;
create policy t_insert on public.tools for insert to authenticated with check (is_member() and owner = auth.uid());
grant update (name, category, power, accessories, note) on public.tools to authenticated;
create policy t_update on public.tools for update to authenticated using (owner = auth.uid() or is_admin());
grant delete on public.tools to authenticated;
create policy t_delete on public.tools for delete to authenticated using (owner = auth.uid() or is_admin());

-- Ausleihen: lesen alle Mitglieder; Änderungen nur über die Funktionen unten;
-- eigene offene/abgelehnte Anfrage darf man löschen
create policy b_read   on public.bookings for select to authenticated using (is_member());
grant delete on public.bookings to authenticated;
create policy b_delete on public.bookings for delete to authenticated using (borrower = auth.uid() and status in ('angefragt','abgelehnt'));

-- Meldungen: jedes Mitglied meldet; erledigen über Funktion
create policy s_read   on public.issues for select to authenticated using (is_member());
grant insert (tool_id, kind, text, blocking) on public.issues to authenticated;
create policy s_insert on public.issues for insert to authenticated with check (is_member() and reported_by = auth.uid() and not done);

-- ---------------------------------------------------------------------
-- Funktionen (prüfen die Regeln serverseitig)
-- ---------------------------------------------------------------------

-- Nach dem ersten Login: Einladung einlösen und Mitglied werden
create or replace function public.join_group(p_name text) returns public.members
language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(auth.jwt() ->> 'email');
  v_inv   invites;
  v_m     members;
begin
  if auth.uid() is null then raise exception 'Nicht angemeldet.'; end if;
  select * into v_m from members where id = auth.uid();
  if found then return v_m; end if;

  select * into v_inv from invites
   where email = v_email and status = 'offen' and created_at > now() - interval '7 days'
   order by created_at desc limit 1;
  if not found then
    raise exception 'Für % gibt es keine gültige Einladung. Bitte ein Mitglied, dich (erneut) einzuladen.', v_email;
  end if;

  insert into members (id, name, email, role, rules_accepted_at)
  values (auth.uid(),
          coalesce(nullif(trim(p_name), ''), nullif(trim(v_inv.name), ''), split_part(v_email, '@', 1)),
          v_email,
          case when exists (select 1 from members) then 'Mitglied' else 'Admin' end,
          now())
  returning * into v_m;

  update invites set status = 'angenommen', accepted_at = now() where id = v_inv.id;
  return v_m;
end $$;

-- Ausleihe anfragen
create or replace function public.request_booking(p_tool bigint, p_from date, p_to date, p_purpose text default '')
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_c bookings; v_owner uuid;
begin
  if not is_member() then raise exception 'Nur für Mitglieder.'; end if;
  select owner into v_owner from tools where id = p_tool;
  if not found then raise exception 'Gerät nicht gefunden.'; end if;
  if v_owner = auth.uid() then raise exception 'Das ist dein eigenes Gerät.'; end if;
  if p_from < current_date then raise exception 'Der Start liegt in der Vergangenheit.'; end if;
  if p_to < p_from then raise exception 'Bis muss am oder nach dem Startdatum liegen.'; end if;
  if exists (select 1 from issues where tool_id = p_tool and blocking and not done) then
    raise exception 'Das Gerät ist wegen eines Schadens gesperrt.';
  end if;
  select * into v_c from bookings
   where tool_id = p_tool and status = 'bestätigt'
     and daterange(date_from, date_to, '[]') && daterange(p_from, p_to, '[]') limit 1;
  if found then
    raise exception 'Belegt vom % bis %, bitte anderen Zeitraum wählen.', to_char(v_c.date_from,'DD.MM.'), to_char(v_c.date_to,'DD.MM.');
  end if;
  insert into bookings (tool_id, borrower, date_from, date_to, purpose)
  values (p_tool, auth.uid(), p_from, p_to, coalesce(p_purpose, ''))
  returning * into v_b;
  return v_b;
end $$;

-- Anfrage zusagen oder ablehnen (nur Besitzer des Geräts)
create or replace function public.respond_booking(p_id bigint, p_accept boolean)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare v_b bookings;
begin
  select b.* into v_b from bookings b join tools t on t.id = b.tool_id
   where b.id = p_id and t.owner = auth.uid() and b.status = 'angefragt';
  if not found then raise exception 'Anfrage nicht gefunden oder schon beantwortet.'; end if;
  begin
    update bookings set status = case when p_accept then 'bestätigt' else 'abgelehnt' end
     where id = p_id returning * into v_b;
  exception when exclusion_violation then
    raise exception 'Überschneidet sich mit einer bestätigten Ausleihe.';
  end;
  return v_b;
end $$;

-- Rückgabe erfassen (Ausleiher oder Besitzer), optional mit Meldungen
create or replace function public.return_booking(
  p_id bigint, p_missing text[] default '{}', p_damage text default null, p_block boolean default false)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare v_b bookings;
begin
  select b.* into v_b from bookings b join tools t on t.id = b.tool_id
   where b.id = p_id and b.status = 'bestätigt' and (b.borrower = auth.uid() or t.owner = auth.uid());
  if not found then raise exception 'Ausleihe nicht gefunden.'; end if;
  update bookings set status = 'zurück', date_to = least(date_to, greatest(date_from, current_date))
   where id = p_id returning * into v_b;
  if coalesce(array_length(p_missing, 1), 0) > 0 then
    insert into issues (tool_id, kind, text, reported_by)
    values (v_b.tool_id, 'Wartung', 'Zubehör fehlt bei Rückgabe: ' || array_to_string(p_missing, ', '), auth.uid());
  end if;
  if nullif(trim(p_damage), '') is not null then
    insert into issues (tool_id, kind, text, reported_by, blocking)
    values (v_b.tool_id, 'Schaden', trim(p_damage), auth.uid(), p_block);
  end if;
  return v_b;
end $$;

-- Meldung erledigen (Besitzer, Melder oder Admin)
create or replace function public.close_issue(p_id bigint) returns public.issues
language plpgsql security definer set search_path = public as $$
declare v_i issues;
begin
  update issues i set done = true, done_at = now()
    from tools t
   where i.id = p_id and t.id = i.tool_id and not i.done
     and (t.owner = auth.uid() or i.reported_by = auth.uid() or is_admin())
  returning i.* into v_i;
  if not found then raise exception 'Meldung nicht gefunden oder keine Berechtigung.'; end if;
  return v_i;
end $$;

revoke execute on function public.join_group(text), public.request_booking(bigint,date,date,text),
  public.respond_booking(bigint,boolean), public.return_booking(bigint,text[],text,boolean),
  public.close_issue(bigint), public.is_member(), public.is_admin() from public, anon;
grant execute on function public.join_group(text), public.request_booking(bigint,date,date,text),
  public.respond_booking(bigint,boolean), public.return_booking(bigint,text[],text,boolean),
  public.close_issue(bigint), public.is_member(), public.is_admin() to authenticated;

-- =====================================================================
-- ERSTER ADMIN: hier deine E-Mail-Adresse eintragen (klein geschrieben)
-- Wer sich als Erster mit einer gültigen Einladung anmeldet, wird Admin.
-- =====================================================================
insert into public.invites (email, name, invited_by)
values ('maschinenring41@gmail.com', 'Raphael', null);
