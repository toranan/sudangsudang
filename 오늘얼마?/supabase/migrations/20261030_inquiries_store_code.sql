-- 1) 앱 '문의하기'. 앱에서 바로 넣고, 운영자는 Supabase 대시보드 Table Editor에서 본다.
create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  role text,
  category text not null default '기타',
  message text not null check (char_length(message) between 1 and 4000),
  contact text,
  app_version text,
  device text,
  created_at timestamptz not null default now()
);

alter table public.inquiries enable row level security;

-- 본인 이름으로 넣기만 가능. 읽기는 대시보드(관리자)에서만.
drop policy if exists "Users can submit own inquiries" on public.inquiries;
create policy "Users can submit own inquiries"
on public.inquiries for insert
to authenticated
with check (user_id = auth.uid());

-- 2) 매장 코드 다시 만들기. invites에 사장님 UPDATE 정책이 없어 앱에서 이전 코드를
--    만료시키지 못했다. 소유자 확인 후 서버에서 이전 코드 만료 + 새 6자리 숫자 코드 발급을 한 번에 한다.
create extension if not exists pgcrypto;

create or replace function public.reissue_store_code(p_store_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  if not exists (
    select 1 from public.stores where id = p_store_id and owner_id = auth.uid()
  ) then
    raise exception '내 매장만 코드를 바꿀 수 있어요.' using errcode = '42501';
  end if;

  update public.invites
  set expires_at = now()
  where store_id = p_store_id
    and expires_at > now();

  for attempt in 1..10 loop
    v_token := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
    begin
      insert into public.invites (store_id, token, expires_at)
      values (p_store_id, v_token, '2099-12-31T00:00:00Z');
      return v_token;
    exception when unique_violation then
      -- 같은 코드가 이미 있으면 다시 뽑는다.
    end;
  end loop;

  raise exception '코드를 만들지 못했어요. 다시 시도해주세요.';
end;
$$;

revoke all on function public.reissue_store_code(uuid) from public;
grant execute on function public.reissue_store_code(uuid) to authenticated;
