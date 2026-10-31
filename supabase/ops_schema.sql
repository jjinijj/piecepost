-- 조각엽서 외 진의 앱 공통 운영 서버 스키마 (설계 v0.1, 6.2)
-- 앱(anon 키)은 테이블을 직접 읽지 못하고 get_config RPC만 실행함

create table apps (
  id text primary key,                 -- 'piecepost'
  name text not null,
  app_store_id text,
  icon_url text,
  show_in_other_apps boolean not null default false,
  sort_order int not null default 0
);

create table app_configs (
  app_id text primary key references apps(id),
  min_supported_version text not null default '1.0.0',
  recommended_version text,
  flags jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table notices (
  id uuid primary key default gen_random_uuid(),
  app_id text not null references apps(id),
  level text not null default 'info' check (level in ('info', 'warning')),
  title text not null,
  body text not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  min_version text,                    -- 이 버전 이상에만 표시
  max_version text,                    -- 이 버전 이하에만 표시
  is_active boolean not null default true
);

alter table apps enable row level security;
alter table app_configs enable row level security;
alter table notices enable row level security;
-- 정책 없음: anon은 테이블을 직접 읽지 못함

create function semver_arr(v text) returns int[]
language sql immutable
as $$ select string_to_array(v, '.')::int[] $$;

create function get_config(p_app_id text, p_app_version text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'minSupportedVersion', c.min_supported_version,
    'recommendedVersion', c.recommended_version,
    'flags', c.flags,
    'notices', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', n.id, 'level', n.level, 'title', n.title, 'body', n.body)
             order by n.starts_at desc)
      from notices n
      where n.app_id = p_app_id
        and n.is_active
        and n.starts_at <= now()
        and (n.ends_at is null or n.ends_at > now())
        and (n.min_version is null or semver_arr(p_app_version) >= semver_arr(n.min_version))
        and (n.max_version is null or semver_arr(p_app_version) <= semver_arr(n.max_version))
    ), '[]'::jsonb),
    'otherApps', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'name', a.name, 'appStoreId', a.app_store_id, 'iconUrl', a.icon_url)
             order by a.sort_order)
      from apps a
      where a.show_in_other_apps and a.id <> p_app_id
    ), '[]'::jsonb)
  )
  from app_configs c
  where c.app_id = p_app_id;
$$;

revoke all on function get_config(text, text) from public;
grant execute on function get_config(text, text) to anon;
