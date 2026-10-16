-- Sprout School: teacher/classroom tools and support tickets
-- Run in Supabase SQL Editor as project owner. Existing question banks and profile data are not changed.
alter table public.profiles add column if not exists is_teacher boolean not null default false;

create table if not exists public.school_classes (
  id bigint generated always as identity primary key,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  join_code text not null unique,
  created_at timestamptz not null default now()
);
create table if not exists public.school_class_members (
  class_id bigint not null references public.school_classes(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(class_id,student_id)
);
create table if not exists public.school_assignments (
  id bigint generated always as identity primary key,
  class_id bigint not null references public.school_classes(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  description text not null default '' check (char_length(description) <= 1000),
  created_at timestamptz not null default now()
);
create table if not exists public.school_assignment_results (
  assignment_id bigint not null references public.school_assignments(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  points integer not null default 0 check(points between 0 and 100000),
  completed_at timestamptz not null default now(),
  primary key(assignment_id,student_id)
);
alter table public.school_classes enable row level security;
alter table public.school_class_members enable row level security;
alter table public.school_assignments enable row level security;
alter table public.school_assignment_results enable row level security;
revoke all on public.school_classes,public.school_class_members,public.school_assignments,public.school_assignment_results from anon,authenticated;
grant select on public.school_classes,public.school_class_members,public.school_assignments,public.school_assignment_results to authenticated;

create or replace function public.teacher_create_class(p_name text)
returns table(id bigint,name text,join_code text,student_count bigint)
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_code text;
begin
 if auth.uid() is null or not coalesce((select p.is_teacher from public.profiles p where p.id=auth.uid()),false) then raise exception 'Lærertilgang kreves'; end if;
 if p_name is null or char_length(trim(p_name)) not between 1 and 80 then raise exception 'Ugyldig klassenavn'; end if;
 v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 insert into public.school_classes(teacher_id,name,join_code) values(auth.uid(),trim(p_name),v_code) returning school_classes.id into v_id;
 return query select c.id,c.name,c.join_code,0::bigint from public.school_classes c where c.id=v_id;
end $$;
create or replace function public.teacher_list_classes()
returns table(id bigint,name text,join_code text,student_count bigint)
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not coalesce((select p.is_teacher from public.profiles p where p.id=auth.uid()),false) then raise exception 'Lærertilgang kreves'; end if;
 return query select c.id,c.name,c.join_code,count(m.student_id) from public.school_classes c left join public.school_class_members m on m.class_id=c.id where c.teacher_id=auth.uid() group by c.id order by c.created_at desc;
end $$;
create or replace function public.teacher_create_assignment(p_class_id bigint,p_title text,p_description text default '')
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
 if auth.uid() is null or not coalesce((select p.is_teacher from public.profiles p where p.id=auth.uid()),false) then raise exception 'Lærertilgang kreves'; end if;
 if p_title is null or char_length(trim(p_title)) not between 1 and 120 then raise exception 'Ugyldig oppgavenavn'; end if;
 if not exists(select 1 from public.school_classes c where c.id=p_class_id and c.teacher_id=auth.uid()) then raise exception 'Klassen finnes ikke eller tilhører ikke deg'; end if;
 insert into public.school_assignments(class_id,teacher_id,title,description) values(p_class_id,auth.uid(),trim(p_title),coalesce(p_description,'')) returning id into v_id;
 return v_id;
end $$;
create or replace function public.teacher_list_progress()
returns table(class_name text,assignment_title text,student_name text,points integer,completed_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not coalesce((select p.is_teacher from public.profiles p where p.id=auth.uid()),false) then raise exception 'Lærertilgang kreves'; end if;
 return query select c.name,a.title,coalesce(p.username,'Elev'),r.points,r.completed_at
 from public.school_assignments a join public.school_classes c on c.id=a.class_id
 left join public.school_assignment_results r on r.assignment_id=a.id
 left join public.profiles p on p.id=r.student_id
 where a.teacher_id=auth.uid() order by a.created_at desc,r.completed_at desc;
end $$;
create or replace function public.student_join_class(p_join_code text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_class bigint;
begin
 if auth.uid() is null then raise exception 'Logg inn først'; end if;
 select c.id into v_class from public.school_classes c where c.join_code=upper(trim(p_join_code));
 if v_class is null then raise exception 'Ugyldig klassekode'; end if;
 insert into public.school_class_members(class_id,student_id) values(v_class,auth.uid()) on conflict do nothing;
end $$;
create or replace function public.student_list_assignments()
returns table(id bigint,title text,description text,class_name text,completed_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Logg inn først'; end if;
 return query select a.id,a.title,a.description,c.name,r.completed_at
 from public.school_class_members m join public.school_classes c on c.id=m.class_id
 join public.school_assignments a on a.class_id=c.id
 left join public.school_assignment_results r on r.assignment_id=a.id and r.student_id=auth.uid()
 where m.student_id=auth.uid() order by a.created_at desc;
end $$;
create or replace function public.student_complete_assignment(p_assignment_id bigint,p_points integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Logg inn først'; end if;
 if p_points is null or p_points not between 0 and 100000 then raise exception 'Ugyldig poengsum'; end if;
 if not exists(select 1 from public.school_assignments a join public.school_class_members m on m.class_id=a.class_id where a.id=p_assignment_id and m.student_id=auth.uid()) then raise exception 'Du er ikke med i klassen for denne oppgaven'; end if;
 insert into public.school_assignment_results(assignment_id,student_id,points) values(p_assignment_id,auth.uid(),p_points)
 on conflict(assignment_id,student_id) do update set points=excluded.points,completed_at=now();
end $$;

create table if not exists public.support_tickets (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 subject text not null check(char_length(trim(subject)) between 1 and 120),
 status text not null default 'open' check(status in ('open','closed')),
 claimed_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 closed_at timestamptz
);
create table if not exists public.support_messages (
 id bigint generated always as identity primary key,
 ticket_id bigint not null references public.support_tickets(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 4000),
 created_at timestamptz not null default now()
);
alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
revoke all on public.support_tickets,public.support_messages from anon,authenticated;
grant select on public.support_tickets,public.support_messages to authenticated;

create or replace function public.create_support_ticket(p_subject text,p_message text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
 if auth.uid() is null then raise exception 'Logg inn først'; end if;
 if p_subject is null or char_length(trim(p_subject)) not between 1 and 120 then raise exception 'Skriv en kort overskrift'; end if;
 if p_message is null or char_length(trim(p_message)) not between 1 and 4000 then raise exception 'Skriv en melding'; end if;
 insert into public.support_tickets(user_id,subject) values(auth.uid(),trim(p_subject)) returning id into v_id;
 insert into public.support_messages(ticket_id,sender_id,body) values(v_id,auth.uid(),trim(p_message));
 return v_id;
end $$;
create or replace function public.send_support_message(p_ticket_id bigint,p_message text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_owner uuid; v_status text; v_verified boolean;
begin
 if auth.uid() is null then raise exception 'Logg inn først'; end if;
 if p_message is null or char_length(trim(p_message)) not between 1 and 4000 then raise exception 'Meldingen må være 1–4000 tegn'; end if;
 select t.user_id,t.status into v_owner,v_status from public.support_tickets t where t.id=p_ticket_id;
 if v_owner is null then raise exception 'Saken finnes ikke'; end if;
 select coalesce(p.is_verified,false) into v_verified from public.profiles p where p.id=auth.uid();
 if auth.uid()<>v_owner and not coalesce(v_verified,false) then raise exception 'Bare eieren eller en verifisert hjelper kan svare'; end if;
 if v_status<>'open' then raise exception 'Saken er lukket'; end if;
 insert into public.support_messages(ticket_id,sender_id,body) values(p_ticket_id,auth.uid(),trim(p_message));
end $$;
create or replace function public.claim_support_ticket(p_ticket_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not coalesce((select p.is_verified from public.profiles p where p.id=auth.uid()),false) then raise exception 'Verifisert hjelper kreves'; end if;
 update public.support_tickets set claimed_by=auth.uid() where id=p_ticket_id and status='open' and (claimed_by is null or claimed_by=auth.uid());
 if not found then raise exception 'Saken er lukket eller tatt av en annen hjelper'; end if;
end $$;
create or replace function public.close_support_ticket(p_ticket_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not coalesce((select p.is_verified from public.profiles p where p.id=auth.uid()),false) then raise exception 'Verifisert hjelper kreves'; end if;
 update public.support_tickets set status='closed',closed_at=now() where id=p_ticket_id and status='open';
 if not found then raise exception 'Saken er allerede lukket eller finnes ikke'; end if;
end $$;
create or replace function public.list_support_tickets()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb;
begin
 if auth.uid() is null then raise exception 'Logg inn først'; end if;
 if coalesce((select p.is_verified from public.profiles p where p.id=auth.uid()),false) then
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'subject',t.subject,'status',t.status,'claimed_by',t.claimed_by,'created_at',t.created_at,'messages',coalesce((select jsonb_agg(jsonb_build_object('sender_name',coalesce(p.username,'Bruker'),'body',m.body,'created_at',m.created_at) order by m.created_at) from public.support_messages m left join public.profiles p on p.id=m.sender_id where m.ticket_id=t.id),'[]'::jsonb)) order by t.created_at desc),'[]'::jsonb) into v_result from public.support_tickets t;
 else
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'subject',t.subject,'status',t.status,'claimed_by',t.claimed_by,'created_at',t.created_at,'messages',coalesce((select jsonb_agg(jsonb_build_object('sender_name',coalesce(p.username,'Bruker'),'body',m.body,'created_at',m.created_at) order by m.created_at) from public.support_messages m left join public.profiles p on p.id=m.sender_id where m.ticket_id=t.id),'[]'::jsonb)) order by t.created_at desc),'[]'::jsonb) into v_result from public.support_tickets t where t.user_id=auth.uid();
 end if;
 return v_result;
end $$;

revoke execute on function public.teacher_create_class(text),public.teacher_list_classes(),public.teacher_create_assignment(bigint,text,text),public.teacher_list_progress(),public.student_join_class(text),public.student_list_assignments(),public.student_complete_assignment(bigint,integer),public.create_support_ticket(text,text),public.send_support_message(bigint,text),public.claim_support_ticket(bigint),public.close_support_ticket(bigint),public.list_support_tickets() from public,anon;
grant execute on function public.teacher_create_class(text),public.teacher_list_classes(),public.teacher_create_assignment(bigint,text,text),public.teacher_list_progress(),public.student_join_class(text),public.student_list_assignments(),public.student_complete_assignment(bigint,integer),public.create_support_ticket(text,text),public.send_support_message(bigint,text),public.claim_support_ticket(bigint),public.close_support_ticket(bigint),public.list_support_tickets() to authenticated;

-- IMPORTANT: an administrator must explicitly grant teacher status after verifying the account:
-- update public.profiles set is_teacher = true where username = 'YOUR_TEACHER_USERNAME';
-- Verified helpers use the existing profiles.is_verified field.
