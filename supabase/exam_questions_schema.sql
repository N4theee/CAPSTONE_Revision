-- =============================================================================
-- Attendximity — Exam questions, choices, answers (multiple-choice phase 1)
-- =============================================================================
-- Run in Supabase SQL Editor AFTER supabase/exam_sessions_schema.sql
-- =============================================================================

-- Optional exam duration (minutes) for UI / time guidance
alter table public.exam_sessions
  add column if not exists duration_minutes integer default 60;

-- ---------------------------------------------------------------------------
-- exam_questions
-- ---------------------------------------------------------------------------
create table if not exists public.exam_questions (
  id uuid primary key default gen_random_uuid(),
  exam_session_id uuid not null references public.exam_sessions(id) on delete cascade,
  question_text text not null,
  points integer not null default 1,
  question_order integer not null default 1,
  created_at timestamptz not null default now()
);

create index if not exists idx_exam_questions_session
  on public.exam_questions(exam_session_id);

-- ---------------------------------------------------------------------------
-- exam_choices
-- ---------------------------------------------------------------------------
create table if not exists public.exam_choices (
  id uuid primary key default gen_random_uuid(),
  exam_question_id uuid not null references public.exam_questions(id) on delete cascade,
  choice_text text not null,
  is_correct boolean not null default false,
  choice_order integer not null default 1,
  created_at timestamptz not null default now()
);

create index if not exists idx_exam_choices_question
  on public.exam_choices(exam_question_id);

-- ---------------------------------------------------------------------------
-- exam_answers
-- ---------------------------------------------------------------------------
create table if not exists public.exam_answers (
  id uuid primary key default gen_random_uuid(),
  exam_attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  exam_question_id uuid not null references public.exam_questions(id) on delete cascade,
  selected_choice_id uuid references public.exam_choices(id) on delete set null,
  is_correct boolean not null default false,
  points_awarded integer not null default 0,
  answered_at timestamptz not null default now(),
  unique (exam_attempt_id, exam_question_id)
);

create index if not exists idx_exam_answers_attempt
  on public.exam_answers(exam_attempt_id);

-- ---------------------------------------------------------------------------
-- exam_attempts scoring columns
-- ---------------------------------------------------------------------------
alter table public.exam_attempts
  add column if not exists raw_score integer default 0,
  add column if not exists total_points integer default 0,
  add column if not exists percentage_score numeric default 0,
  add column if not exists submitted_at timestamptz;

-- completion_seconds may already exist; ensure default
alter table public.exam_attempts
  alter column completion_seconds set default 0;

-- Keep legacy exam_score in sync with percentage for older code paths
comment on column public.exam_attempts.percentage_score is 'Primary MCQ score 0-100';
comment on column public.exam_attempts.exam_score is 'Legacy; mirror percentage_score on submit';

-- ---------------------------------------------------------------------------
-- RLS (open anon pattern — matches exam_sessions_schema.sql)
-- ---------------------------------------------------------------------------
alter table public.exam_questions enable row level security;
alter table public.exam_choices enable row level security;
alter table public.exam_answers enable row level security;

drop policy if exists "open exam_questions rw" on public.exam_questions;
create policy "open exam_questions rw"
  on public.exam_questions for all to anon using (true) with check (true);

drop policy if exists "open exam_choices rw" on public.exam_choices;
create policy "open exam_choices rw"
  on public.exam_choices for all to anon using (true) with check (true);

drop policy if exists "open exam_answers rw" on public.exam_answers;
create policy "open exam_answers rw"
  on public.exam_answers for all to anon using (true) with check (true);

notify pgrst, 'reload schema';
