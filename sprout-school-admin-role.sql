-- Sprout School: administrator role badge
-- Run this in the Supabase SQL Editor as the project owner.
-- This adds a role flag; it does not grant admin status to everyone.
alter table public.profiles
  add column if not exists is_admin boolean not null default false;

-- After running this migration, manually grant the role to your own account:
-- Replace YOUR_USERNAME with the exact username shown in Sprout School, then run:
-- update public.profiles set is_admin = true where username = 'YOUR_USERNAME';

-- To revoke the role later:
-- update public.profiles set is_admin = false where username = 'YOUR_USERNAME';

-- Only trusted project owners should change is_admin. Do not add this field
-- to the normal profile-edit form or allow users to update it themselves.
