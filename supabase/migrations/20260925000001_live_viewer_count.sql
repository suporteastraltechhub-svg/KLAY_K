create or replace function public.sync_live_viewer_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live_id uuid;
begin
  if tg_op = 'DELETE' then
    v_live_id := old.live_id;
  else
    v_live_id := new.live_id;
  end if;

  update public.lives
     set viewer_count = (
       select count(*)::int
         from public.live_participants
        where live_id = v_live_id
          and left_at is null
          and is_streamer = false
     )
   where id = v_live_id
     and status = 'live';

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists live_participants_viewer_count_sync
  on public.live_participants;

create trigger live_participants_viewer_count_sync
after insert or delete or update
on public.live_participants
for each row
execute function public.sync_live_viewer_count();

update public.lives l
   set viewer_count = (
     select count(*)::int
       from public.live_participants p
      where p.live_id = l.id
        and p.left_at is null
        and p.is_streamer = false
   )
 where l.status = 'live';

revoke all on function public.sync_live_viewer_count() from public, anon, authenticated;

notify pgrst, 'reload schema';
