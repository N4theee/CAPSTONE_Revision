// Run with: node test/section_enrollment_sql.cjs <path-to-@electric-sql/pglite>
// An isolated PostgreSQL engine with real pgcrypto; no connection to Supabase.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const runtime = process.argv[2] || '@electric-sql/pglite';
const { PGlite } = require(runtime);
const { pgcrypto } = require(path.join(runtime, 'dist/contrib/pgcrypto.cjs'));
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, 'supabase', name), 'utf8');

(async () => {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`
    create schema extensions;
    create extension pgcrypto with schema extensions;
    create role anon; create role authenticated;
    grant usage on schema public,extensions to anon,authenticated;
  `);
  const baseline = read('NEW_PROJECT_SETUP.sql');
  // Use the repository's real legacy tables and device-aware registration.
  await db.exec(baseline.slice(baseline.indexOf('create table if not exists public.admins ('),
    baseline.indexOf('-- Upgrade existing databases that created subject_offerings')));
  await db.exec(baseline.slice(baseline.indexOf('create table if not exists public.student_subject_enrollments ('),
    baseline.indexOf('create table if not exists public.attendance_sessions (')));
  await db.exec(`
    create table public.attendance_sessions(id uuid primary key default gen_random_uuid(),subject_offering_id uuid references public.subject_offerings(id),is_active boolean default false);
    create table public.attendance_records(id uuid primary key default gen_random_uuid(),student_id uuid,attendance_session_id uuid references public.attendance_sessions(id));
    create table public.exam_sessions(id uuid primary key default gen_random_uuid(),subject_offering_id uuid references public.subject_offerings(id),status text default 'scheduled');
    create table public.exam_attempts(id uuid primary key default gen_random_uuid(),exam_session_id uuid references public.exam_sessions(id),student_id uuid);
    grant select,insert,update,delete on all tables in schema public to anon,authenticated;
    insert into public.admins(full_name,email,password_hash) values('Admin','admin',extensions.crypt('test-admin-password',extensions.gen_salt('bf')));
    insert into public.teachers(full_name,email,password_hash) values('Teacher','teacher','unused');
    insert into public.students(full_name,email,password_hash) select 'Student '||n,'student'||n,'unused' from generate_series(1,6) n;
  `);
  const registration = baseline.slice(baseline.indexOf('create or replace function public.register_student('),
    baseline.indexOf('create or replace function public.admin_create_teacher_account('));
  await db.exec(registration);
  const originalRegistration = (await db.query(`select pg_get_functiondef('public.register_student(text,text,text,text,text,text)'::regprocedure) as def`)).rows[0].def;
  const teacher = (await db.query('select id from public.teachers')).rows[0].id;
  const students = (await db.query('select id from public.students order by email')).rows.map(r => r.id);
  // Existing legacy data must survive the migration, failed enrollment, and semester closing.
  await db.exec(`insert into public.subjects(subject_code,subject_title) values('LEGACY','Existing subject');
    insert into public.sections(section_name) values('Existing section');
    insert into public.subject_offerings(subject_id,teacher_id,section_id,beacon_uuid,beacon_name)
      select s.id,t.id,se.id,'12345678-1234-1234-1234-123456789012','Original beacon' from public.subjects s,public.teachers t,public.sections se;
    insert into public.student_subject_enrollments(student_id,subject_offering_id) select '${students[5]}',id from public.subject_offerings;
    insert into public.student_devices(student_id,device_uuid,device_name) values('${students[5]}','original-device','Original device');
    insert into public.attendance_sessions(subject_offering_id,is_active) select id,false from public.subject_offerings;
    insert into public.attendance_records(student_id,attendance_session_id) select '${students[5]}',id from public.attendance_sessions;
    insert into public.exam_sessions(subject_offering_id,status) select id,'completed' from public.subject_offerings;
    insert into public.exam_attempts(exam_session_id,student_id) select id,'${students[5]}' from public.exam_sessions;`);
  const legacyBefore = {};
  for (const table of ['student_devices','attendance_records','exam_attempts','subject_offerings','student_subject_enrollments']) {
    legacyBefore[table] = (await db.query(`select * from public.${table} order by id`)).rows;
  }
  await db.exec(read('section_enrollment.sql'));
  await db.exec(read('section_enrollment.sql')); // migration is repeatable
  await db.exec(read('section_curriculum_drafts.sql'));
  await db.exec(read('section_curriculum_drafts.sql')); // seed never duplicates
  assert.equal((await db.query('select count(*)::int n from public.school_curricula')).rows[0].n,8);
  assert.equal((await db.query('select count(*)::int n from public.school_curricula where approved')).rows[0].n,0);
  assert.equal((await db.query('select count(*)::int n from public.school_curriculum_subjects where semester is not null')).rows[0].n,0);
  const draftCounts = (await db.query(`select c.grade,c.program,count(*)::int n from public.school_curricula c join public.school_curriculum_subjects s on s.curriculum_id=c.id group by c.grade,c.program order by c.grade,c.program`)).rows;
  assert.deepEqual(draftCounts.map(r => [r.grade,r.program,r.n]),[[11,'EIM',9],[11,'GAS',13],[11,'HE',11],[11,'ICT',10],[12,'EIM',11],[12,'GAS',14],[12,'HE',12],[12,'ICT',13]]);
  const command = async (action,data,password='test-admin-password') => {
    const result = await db.query('select public.admin_school_command($1,$2,$3,$4::jsonb) result',['admin',password,action,JSON.stringify(data)]);
    return result.rows[0].result;
  };
  const fails = async (fn, message) => { await assert.rejects(fn,message); };
  await db.exec('set role anon');
  await fails(() => command('create_section',{} ,'wrong'),/Administrator credentials/);
  await fails(() => db.exec(`insert into public.school_curricula(program,grade,version) values('ICT',11,'unauthorized')`),/permission denied/);
  await db.exec('reset role');
  const curriculum = (await db.query(`select id from public.school_curricula where grade=11 and program='ICT'`)).rows[0].id;
  await fails(() => command('approve_curriculum',{id:curriculum}),/Confirm the semester/);
  const subjects = (await db.query('select subject_id from public.school_curriculum_subjects where curriculum_id=$1 order by subject_id',[curriculum])).rows.map(r=>r.subject_id);
  for (const [i,subject] of subjects.entries()) await command('curriculum_subject',{curriculum_id:curriculum,subject_id:subject,semester:i<2?0:2});
  await command('approve_curriculum',{id:curriculum});
  await fails(() => command('curriculum_subject',{curriculum_id:curriculum,subject_id:subjects[0],semester:1}),/frozen/);
  const copy = (await command('create_curriculum',{program:'ICT',grade:11,version:'Copy',copy_id:curriculum})).id;
  assert.equal((await db.query('select count(*)::int n from public.school_curriculum_subjects where curriculum_id=$1',[copy])).rows[0].n,10);
  await command('remove_curriculum_subject',{curriculum_id:copy,subject_id:subjects[0]});
  await command('curriculum_subject',{curriculum_id:copy,subject_id:subjects[0],semester:null,add:true});
  const section = (await command('create_section',{name:'ICT 11-A',school_year:'2026-2027',grade:11,program:'ICT',capacity:2,adviser_id:teacher})).id;
  const otherSection = (await command('create_section',{name:'ICT 11-B',school_year:'2026-2027',grade:11,program:'ICT',capacity:45})).id;
  const term = (await command('create_term',{section_id:section,curriculum_id:curriculum,semester:1})).id;
  await fails(() => command('ready_term',{id:term}),/Assign a teacher/);
  await fails(() => command('enroll',{term_id:term,student_ids:[students[0]]}),/not ready/);
  for (const subject of subjects.slice(0,2)) await command('assign_teacher',{term_id:term,subject_id:subject,teacher_id:teacher});
  await command('ready_term',{id:term});
  await db.exec('set role anon');
  await command('enroll',{term_id:term,student_ids:[students[0],students[1]]});
  await command('enroll',{term_id:term,student_ids:[students[0],students[1]]}); // idempotent
  await db.exec('reset role');
  assert.equal((await db.query('select count(*)::int n from public.school_section_placements')).rows[0].n,2);
  assert.equal((await db.query('select count(*)::int n from public.student_subject_enrollments where student_id=any($1::uuid[])',[students.slice(0,2)])).rows[0].n,4);
  await fails(() => command('enroll',{term_id:term,student_ids:[students[2],students[3]]}),/available seats/);
  assert.equal((await db.query('select count(*)::int n from public.school_section_placements where student_id=any($1::uuid[])',[students.slice(2,4)])).rows[0].n,0);
  const otherTerm = (await command('create_term',{section_id:otherSection,curriculum_id:curriculum,semester:1})).id;
  for (const subject of subjects.slice(0,2)) await command('assign_teacher',{term_id:otherTerm,subject_id:subject,teacher_id:teacher});
  await command('ready_term',{id:otherTerm});
  await fails(() => command('enroll',{term_id:otherTerm,student_ids:[students[0]]}),/already has a section/);
  await fails(() => command('enroll',{term_id:otherTerm,student_ids:[students[5]]}),/conflicts/);
  const offering = (await db.query('select offering_id from public.school_teaching_assignments where term_id=$1',[term])).rows[0].offering_id;
  await db.exec('set role anon');
  await fails(() => db.query('select public.admin_assign_student_to_offering($1,$2)',[students[0],offering]),/section enrollment/);
  await fails(() => db.query('insert into public.student_subject_enrollments(student_id,subject_offering_id) values($1,$2)',[students[2],offering]),/section placement/);
  await fails(() => db.query('update public.subject_offerings set beacon_name=$1 where id=$2',['Changed beacon',offering]),/teaching assignments/);
  await db.exec('reset role');
  // Even the old security-definer individual enrollment RPC cannot bypass placement.
  await fails(() => db.query('insert into public.student_subject_enrollments(student_id,subject_offering_id) values($1,$2)',[students[2],offering]),/approved section placement/);
  await fails(() => command('assign_teacher',{term_id:term,subject_id:subjects[0],teacher_id:teacher}),/frozen/);
  await db.query('insert into public.attendance_sessions(subject_offering_id,is_active) values($1,true)',[offering]);
  await fails(() => command('close_term',{id:term}),/End active attendance/);
  await db.query('update public.attendance_sessions set is_active=false where subject_offering_id=$1',[offering]);
  await db.query("insert into public.exam_sessions(subject_offering_id,status) values($1,'paused')",[offering]);
  await fails(() => command('close_term',{id:term}),/End active attendance/);
  await db.query("update public.exam_sessions set status='completed' where subject_offering_id=$1",[offering]);
  await command('close_term',{id:term});
  await fails(() => db.query('insert into public.attendance_sessions(subject_offering_id,is_active) values($1,true)',[offering]),/not open/);
  await fails(() => command('enroll',{term_id:term,student_ids:[students[0]]}),/not ready/);
  const secondTerm=(await command('create_term',{section_id:section,curriculum_id:curriculum,semester:2})).id;
  for(const subject of subjects) await command('assign_teacher',{term_id:secondTerm,subject_id:subject,teacher_id:teacher});
  const draftOffering=(await db.query('select offering_id from public.school_teaching_assignments where term_id=$1',[secondTerm])).rows[0].offering_id;
  await db.exec('set role anon');
  await fails(() => db.query('update public.subject_offerings set section_id=$1 where id=$2',[legacyBefore.subject_offerings[0].section_id,draftOffering]),/teaching assignments/);
  await db.exec('reset role');
  await command('ready_term',{id:secondTerm});
  await command('enroll',{term_id:secondTerm,student_ids:[students[0],students[1]]});
  assert.equal((await db.query('select count(*)::int n from public.school_section_placements')).rows[0].n,2);
  await db.exec('set role anon');
  const registered=(await db.query(`select public.register_student_with_section_request('new-number','New Student','new-student','student-password','new-device','Phone',12,'HE') as id`)).rows[0].id;
  await fails(() => db.query(`select public.register_student_with_section_request('wrong','Wrong','new-student','wrong','wrong-device','Wrong',11,'ICT')`),/already registered/);
  await fails(() => db.query(`select public.register_student_with_section_request('invalid','Invalid','invalid-student','password',null,null,10,'ICT')`),/requested grade/);
  await db.exec('reset role');
  assert.equal((await db.query('select requested_program from public.school_student_requests where student_id=$1',[registered])).rows[0].requested_program,'HE');
  assert.equal((await db.query("select count(*)::int n from public.students where email='invalid-student'")).rows[0].n,0);
  assert.equal((await db.query('select count(*)::int n from public.school_section_placements where student_id=$1',[registered])).rows[0].n,0);
  await db.exec('set role anon');
  await db.query('select public.admin_assign_student_to_offering($1,$2)',[registered,legacyBefore.subject_offerings[0].id]);
  await db.exec('reset role');
  for (const [table,rows] of Object.entries(legacyBefore)) {
    const ids=rows.map(r=>r.id);
    const after=(await db.query(`select * from public.${table} where id=any($1::uuid[]) order by id`,[ids])).rows;
    assert.deepEqual(after,rows,`Legacy ${table} changed`);
  }
  assert.equal((await db.query(`select pg_get_functiondef('public.register_student(text,text,text,text,text,text)'::regprocedure) as def`)).rows[0].def,originalRegistration);
  const countBeforeDemo=(await db.query('select count(*)::int n from public.student_subject_enrollments')).rows[0].n;
  const demo=read('section_enrollment_demo.sql').replace('v_teacher_id uuid := NULL;',`v_teacher_id uuid := '${teacher}'::uuid;`);
  await db.exec(demo);
  await db.exec(demo);
  assert.equal((await db.query('select count(*)::int n from public.student_subject_enrollments')).rows[0].n,countBeforeDemo);
  assert.equal((await db.query(`select count(*)::int n from public.school_section_terms t join public.school_sections s on s.id=t.school_section_id join public.sections se on se.id=s.section_id where se.section_name='TEST ONLY - ICT 11-A (2026-2027)' and t.ready`)).rows[0].n,1);
  console.log('PASS: repeatable migration and all 8 subject drafts; approval; teacher readiness; atomic bulk enrollment; capacity; duplicate prevention; conflicting placement; legacy conflicts; client access guards; semester closure; next semester; registration; legacy records/device preservation.');
  await db.close();
})().catch(error => { console.error(error); process.exitCode=1; });
