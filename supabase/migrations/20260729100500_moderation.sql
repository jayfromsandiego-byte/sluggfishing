-- ============================================================================
-- OFFINGCUE FOUNDATION 0005 — moderation audit + never-auto-publish machinery
--
-- Policy encoded exactly as decided:
--   * Reports NEVER auto-publish. Approval is a named-operator action.
--   * 60 minutes  → remind primary reviewer
--   * 90 minutes  → route to backup reviewer
--   * 120 minutes → expire from the freshness queue; the draft is retained
--   * Every action lands in an append-only audit table.
--   * Intel (Joseph/Telegram) publication additionally requires a SIGNED
--     contributor agreement — the schema refuses to publish without it.
-- ============================================================================

create table public.moderation_actions (
  id             bigint generated always as identity primary key,
  report_id      uuid references public.reports (id) on delete set null,
  intel_draft_id uuid references public.intel_drafts (id) on delete set null,
  actor_kind     public.actor_kind not null,
  actor_id       uuid references auth.users (id),
  action         public.moderation_action_kind not null,
  before_status  text,
  after_status   text,
  note           text,
  created_at     timestamptz not null default now(),
  constraint moderation_named_operator check (actor_kind <> 'operator' or actor_id is not null),
  constraint moderation_one_subject check (
    (report_id is not null)::int + (intel_draft_id is not null)::int = 1
  )
);

create index moderation_actions_report_idx on public.moderation_actions (report_id, created_at);
create index moderation_actions_intel_idx on public.moderation_actions (intel_draft_id, created_at);

-- Append-only. Nobody edits the audit trail.
create trigger moderation_actions_immutable
  before update or delete on public.moderation_actions
  for each row execute function app.forbid_mutation();

alter table public.moderation_actions enable row level security;
revoke all on table public.moderation_actions from public;
revoke all on table public.moderation_actions from anon, authenticated;
grant select on table public.moderation_actions to authenticated;
grant select on table public.moderation_actions to service_role;
-- No API-role INSERT: audit rows are written by SECURITY DEFINER functions.

create policy moderation_actions_select_operator on public.moderation_actions
  for select to authenticated
  using (app.is_operator());

-- Transparency: authors can see the audit trail of their own reports.
create policy moderation_actions_select_author on public.moderation_actions
  for select to authenticated
  using (report_id in (select id from public.reports where author_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- moderate_report — the ONLY path to 'approved'.
-- ---------------------------------------------------------------------------
create or replace function public.moderate_report(
  p_report uuid,
  p_action text,          -- approve | reject | request_changes | clarify
  p_note   text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_report public.reports%rowtype;
  v_new    public.report_status;
begin
  if v_uid is null or not app.is_operator() then
    raise exception 'Named operator required: moderation is never anonymous and never automatic';
  end if;

  select * into v_report from public.reports where id = p_report for update;
  if not found then
    raise exception 'Report not found';
  end if;
  if v_report.status <> 'submitted' then
    raise exception 'Only submitted reports can be moderated (current status: %)', v_report.status;
  end if;

  v_new := case p_action
    when 'approve'         then 'approved'::public.report_status
    when 'reject'          then 'rejected'::public.report_status
    when 'request_changes' then 'needs_changes'::public.report_status
    when 'clarify'         then 'submitted'::public.report_status
    else null
  end;
  if v_new is null then
    raise exception 'Unknown moderation action %', p_action;
  end if;

  perform set_config('app.write_ctx', 'moderation', true);
  update public.reports
     set status       = v_new,
         approved_at  = case when v_new = 'approved' then now() else approved_at end,
         moderated_by = v_uid
   where id = p_report;
  perform set_config('app.write_ctx', '', true);

  insert into public.moderation_actions
    (report_id, actor_kind, actor_id, action, before_status, after_status, note)
  values
    (p_report, 'operator', v_uid, p_action::public.moderation_action_kind,
     v_report.status::text, v_new::text, p_note);
end;
$$;
revoke execute on function public.moderate_report(uuid, text, text) from public;
grant execute on function public.moderate_report(uuid, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Escalations: 60 remind / 90 backup / 120 expire (draft retained).
-- p_now is injectable for tests. Schedule via pg_cron in production.
-- Escalation never publishes anything — it only moves reviewer routing
-- state, and at 120 minutes it takes the report OUT of the queue.
-- ---------------------------------------------------------------------------
create or replace function public.run_moderation_escalations(p_now timestamptz default now())
returns table (reminded integer, routed integer, expired integer)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  n_remind   integer := 0;
  n_route    integer := 0;
  n_expire   integer := 0;
  r          record;
begin
  -- Callable by operators, service, or the database itself (cron).
  if v_uid is not null and not app.is_operator() then
    raise exception 'Operator role required';
  end if;

  perform set_config('app.write_ctx', 'moderation', true);

  for r in
    select id, status from public.reports
    where status = 'submitted'
      and submitted_at <= p_now - interval '60 minutes'
      and sla_reminded_at is null
    for update
  loop
    update public.reports set sla_reminded_at = p_now where id = r.id;
    insert into public.moderation_actions
      (report_id, actor_kind, action, before_status, after_status, note)
    values (r.id, 'system', 'remind_primary', 'submitted', 'submitted',
            'SLA 60 min: primary reviewer reminded');
    n_remind := n_remind + 1;
  end loop;

  for r in
    select id from public.reports
    where status = 'submitted'
      and submitted_at <= p_now - interval '90 minutes'
      and sla_backup_routed_at is null
    for update
  loop
    update public.reports set sla_backup_routed_at = p_now where id = r.id;
    insert into public.moderation_actions
      (report_id, actor_kind, action, before_status, after_status, note)
    values (r.id, 'system', 'route_backup', 'submitted', 'submitted',
            'SLA 90 min: routed to backup reviewer');
    n_route := n_route + 1;
  end loop;

  for r in
    select id from public.reports
    where status = 'submitted'
      and submitted_at <= p_now - interval '120 minutes'
    for update
  loop
    update public.reports
       set status = 'expired_queue', sla_expired_at = p_now
     where id = r.id;
    insert into public.moderation_actions
      (report_id, actor_kind, action, before_status, after_status, note)
    values (r.id, 'system', 'expire_freshness', 'submitted', 'expired_queue',
            'SLA 120 min: expired from freshness queue; draft retained');
    n_expire := n_expire + 1;
  end loop;

  perform set_config('app.write_ctx', '', true);
  return query select n_remind, n_route, n_expire;
end;
$$;
revoke execute on function public.run_moderation_escalations(timestamptz) from public;
grant execute on function public.run_moderation_escalations(timestamptz) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Operator queue view
-- ---------------------------------------------------------------------------
create view public.moderation_queue
with (security_invoker = on) as
select
  r.id,
  r.author_id,
  p.handle as author_handle,
  r.origin,
  r.contributor_label,
  r.zone_id,
  z.name as zone_name,
  r.species_id,
  r.privacy_level,
  r.submitted_at,
  floor(extract(epoch from (now() - r.submitted_at)) / 60)::int as minutes_waiting,
  case
    when r.sla_backup_routed_at is not null then 'backup'
    when r.sla_reminded_at is not null then 'reminded'
    else 'primary'
  end as escalation_stage
from public.reports r
join public.zones z on z.id = r.zone_id
left join public.profiles p on p.id = r.author_id
where r.status = 'submitted' and app.is_operator();

revoke all on public.moderation_queue from public;
revoke all on public.moderation_queue from anon;
grant select on public.moderation_queue to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Intel approval — human-only, agreement-gated.
-- Publishing an intel draft creates a real report through the same guarded
-- path as everything else, then approves it via the moderation context, so
-- the never-auto-publish trigger discipline applies here too.
-- ---------------------------------------------------------------------------
create or replace function public.approve_intel(p_intel uuid, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_draft   public.intel_drafts%rowtype;
  v_payload app_private.intel_payloads%rowtype;
  v_id      uuid;
begin
  if v_uid is null or not app.is_operator() then
    raise exception 'Named operator required';
  end if;

  select * into v_draft from public.intel_drafts where id = p_intel for update;
  if not found then
    raise exception 'Intel draft not found';
  end if;
  if v_draft.status <> 'pending' then
    raise exception 'Intel draft is not pending (status: %)', v_draft.status;
  end if;
  if v_draft.agreement_status <> 'signed' then
    raise exception 'Contributor agreement gate: no publication without a signed agreement (status: %)', v_draft.agreement_status;
  end if;
  if v_draft.zone_id is null then
    raise exception 'Intel draft needs a zone before publication';
  end if;
  if not coalesce(v_draft.region_check_passed, false)
     or not coalesce(v_draft.duplicate_check_passed, false)
     or not coalesce(v_draft.safety_check_passed, false) then
    raise exception 'Region, duplicate, and safety checks must all pass before publication';
  end if;

  select * into v_payload from app_private.intel_payloads where intel_id = p_intel;
  if not found or v_payload.exact_geom is null then
    raise exception 'Intel draft has no retained coordinates; request clarification instead';
  end if;

  -- Create the report (guarded insert path).
  perform set_config('app.write_ctx', 'intel_publish', true);
  insert into public.reports
    (author_id, origin, contributor_label, zone_id, species_id, body,
     caught_at, privacy_level)
  values
    (v_uid, 'intel', v_draft.contributor_label, v_draft.zone_id,
     v_draft.species_id, v_draft.draft_text, v_draft.received_at,
     v_draft.privacy_level)
  returning id into v_id;

  insert into app_private.report_locations
    (report_id, exact_geom, jitter_azimuth_rad, jitter_distance_m)
  values
    (v_id, v_payload.exact_geom, random() * 2 * pi(), 300 + random() * 700);

  update public.reports set privacy_level = v_draft.privacy_level where id = v_id;
  update public.reports set status = 'submitted' where id = v_id;
  perform set_config('app.write_ctx', '', true);

  -- Named-operator approval through the one true gate.
  perform public.moderate_report(v_id, 'approve',
    coalesce(p_note, 'Published from intel draft ' || p_intel));

  update public.intel_drafts
     set status = 'approved',
         reviewed_by = v_uid,
         reviewed_at = now(),
         published_report_id = v_id
   where id = p_intel;

  insert into public.moderation_actions
    (intel_draft_id, actor_kind, actor_id, action, before_status, after_status, note)
  values
    (p_intel, 'operator', v_uid, 'approve', 'pending', 'approved', p_note);

  return v_id;
end;
$$;
revoke execute on function public.approve_intel(uuid, text) from public;
grant execute on function public.approve_intel(uuid, text) to authenticated, service_role;

create or replace function public.review_intel(p_intel uuid, p_action text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_draft public.intel_drafts%rowtype;
  v_new   public.intel_status;
begin
  if v_uid is null or not app.is_operator() then
    raise exception 'Named operator required';
  end if;
  select * into v_draft from public.intel_drafts where id = p_intel for update;
  if not found then
    raise exception 'Intel draft not found';
  end if;
  v_new := case p_action
    when 'reject'  then 'rejected'::public.intel_status
    when 'clarify' then 'needs_clarification'::public.intel_status
    when 'expire'  then 'expired'::public.intel_status
    else null
  end;
  if v_new is null then
    raise exception 'Unknown intel action % (use approve_intel for publication)', p_action;
  end if;

  update public.intel_drafts
     set status = v_new, reviewed_by = v_uid, reviewed_at = now()
   where id = p_intel;

  insert into public.moderation_actions
    (intel_draft_id, actor_kind, actor_id, action, before_status, after_status, note)
  values
    (p_intel, 'operator', v_uid,
     case p_action when 'reject' then 'reject' else 'clarify' end::public.moderation_action_kind,
     v_draft.status::text, v_new::text, p_note);
end;
$$;
revoke execute on function public.review_intel(uuid, text, text) from public;
grant execute on function public.review_intel(uuid, text, text) to authenticated, service_role;
