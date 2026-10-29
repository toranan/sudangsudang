-- 앱 '문의하기'로 들어온 내용. send-inquiry 엣지 함수(service role)만 쓰고 읽는다.
create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  role text,
  category text not null default '기타',
  message text not null,
  contact text,
  app_version text,
  device text,
  created_at timestamptz not null default now()
);

alter table public.inquiries enable row level security;
-- 정책을 만들지 않아 앱(anon/authenticated)에서는 직접 읽거나 쓸 수 없다.
