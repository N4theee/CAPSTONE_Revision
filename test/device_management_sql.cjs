// node test/device_management_sql.cjs <absolute path to @electric-sql/pglite>
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const runtime = path.resolve(process.argv[2]);
const { PGlite } = require(runtime);
const { pgcrypto } = require(path.join(runtime, 'dist/contrib/pgcrypto.cjs'));
const sql = name => fs.readFileSync(path.join(__dirname, '../supabase', name), 'utf8');

(async () => {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`create publication supabase_realtime; create schema extensions; create role anon; create role authenticated;
    grant usage on schema public,extensions to anon,authenticated;`);
  await db.exec(sql('NEW_PROJECT_SETUP.sql'));
  await db.exec(`grant select,insert,update,delete on all tables in schema public to anon,authenticated;
    insert into public.admins(full_name,email,password_hash)
      values('Reset Administrator','reset-admin',extensions.crypt('test-reset-password',extensions.gen_salt('bf')));`);
  const register = async (name, device) => (await db.query(
    'select public.register_student($1,$2,$3,$4,$5,$6) id',
    [name, name, name, 'test-student-password', device, 'Test phone'],
  )).rows[0].id;
  const a = await register('Student-A', 'phone-a');
  const b = await register('Student-B', 'phone-b');
  const login = async (name, phone) => db.query(
    'select * from public.app_student_login_with_device($1,$2,$3,$4,$5)',
    [name,'test-student-password',phone,'Test phone',`${phone}-fingerprint`],
  );
  await login('Student-A','phone-a');
  await login('Student-B','phone-b');
  await db.exec(sql('device_management.sql'));
  await db.exec(sql('device_management.sql')); // idempotent; does not reset any device
  const command = async (action, student, phone, reason, details = '', password = 'test-reset-password', page = 0) =>
    (await db.query('select public.admin_device_management($1,$2,$3,$4,$5,$6,$7,$8) result',
      ['reset-admin',password,action,student,phone,reason,details,page])).rows[0].result;
  const valid = async (student, phone) => (await db.query(
    'select public.student_device_session_valid($1,$2) valid', [student,phone],
  )).rows[0].valid;
  assert.equal(await valid(a,'phone-a'), true);
  await db.exec('set role anon');
  await assert.rejects(() => command('reset_student_device',a,null,'Lost phone','','wrong'), /Administrator credentials/);
  await assert.rejects(() => command('reset_student_device',a,null,null), /Choose a reset reason/);
  await assert.rejects(() => command('reset_student_device',a,null,'Other',''), /Explain the other reason/);
  await assert.rejects(() => command('release_device',a,'phone-b','Device reassignment'), /binding changed/);
  await assert.rejects(() => db.exec(`update public.student_devices set is_revoked=false`), /permission denied/);
  await assert.rejects(() => db.exec(`update public.student_login_sessions set is_active=true`), /permission denied/);
  await assert.rejects(() => db.exec(`select * from public.device_reset_history`), /permission denied/);
  await assert.rejects(() => db.exec(`delete from public.device_reset_history`), /permission denied/);
  await assert.rejects(() => db.exec(`insert into public.device_reset_history default values`), /permission denied/);
  await assert.rejects(() => command('history',null,null,null,'','wrong'), /Administrator credentials/);
  assert.equal(await valid(a,'phone-a'), true); // failures changed nothing
  await db.exec('reset role');
  // Existing school records and even an active exam are intentionally preserved.
  await db.exec(`insert into public.teachers(full_name,email,password_hash) values('Teacher','reset-teacher','unused');
    insert into public.subjects(subject_code,subject_title) values('RESET-TEST','Device reset test');
    insert into public.sections(section_name) values('Reset test section');
    insert into public.subject_offerings(teacher_id,subject_id,section_id,beacon_uuid,beacon_name)
      select t.id,s.id,c.id,'test-beacon','TEST' from public.teachers t,public.subjects s,public.sections c
      where t.email='reset-teacher' and s.subject_code='RESET-TEST' and c.section_name='Reset test section';
    insert into public.student_subject_enrollments(student_id,subject_offering_id) select '${a}',id from public.subject_offerings;
    insert into public.attendance_sessions(subject_offering_id,beacon_uuid,is_active) select id,'test-beacon',true from public.subject_offerings;
    insert into public.attendance_records(student_id,attendance_session_id) select '${a}',id from public.attendance_sessions;
    insert into public.exam_sessions(subject_offering_id,teacher_id,exam_title,exam_code,status,ble_uuid)
      select id,teacher_id,'Active exam','RESET-EXAM','active','test-beacon' from public.subject_offerings;
    insert into public.exam_attempts(exam_session_id,student_id) select id,'${a}' from public.exam_sessions;`);
  const preserved = ['students','student_subject_enrollments','attendance_sessions','attendance_records','exam_sessions','exam_attempts'];
  const before = {};
  for (const t of preserved) before[t] = (await db.query(`select * from public.${t} order by id`)).rows;
  // A failed audit write must roll back device and session revocation too.
  await db.exec(`create function public.test_reject_device_audit() returns trigger language plpgsql as $$
    begin raise exception 'Simulated audit failure'; end $$;
    create trigger test_device_audit before insert on public.device_reset_history
    for each row execute function public.test_reject_device_audit();`);
  await assert.rejects(() => command('reset_student_device',a,null,'Lost phone'), /Simulated audit failure/);
  assert.equal(await valid(a,'phone-a'),true);
  await db.exec('drop trigger test_device_audit on public.device_reset_history; drop function public.test_reject_device_audit();');
  await db.exec('set role anon');
  const reset = await command('reset_student_device',a,null,'Broken phone','Teacher approval letter 42');
  assert.equal(reset.entry.admin_name, 'Reset Administrator');
  assert.equal(reset.entry.student_id, a);
  assert.equal(reset.entry.devices[0].device_uuid, 'phone-a');
  assert.equal(reset.entry.details, 'Teacher approval letter 42');
  assert.ok(reset.entry.created_at);
  assert.equal(await valid(a,'phone-a'), false);
  assert.equal(await valid(b,'phone-b'), true);
  await assert.rejects(() => db.query('select public.validate_student_attendance_device($1,$2,$3)', [a,'phone-a','phone-a-fingerprint']), /Attendance blocked/);
  await login('Student-A','replacement-phone');
  assert.equal(await valid(a,'replacement-phone'), true);
  await assert.rejects(() => login('Student-A','phone-a'), /another device|registered device/);
  // Reassignment releases the physical phone for another existing account.
  await command('release_device',a,'replacement-phone','Device reassignment');
  await command('reset_student_device',b,null,'Replacement phone');
  await login('Student-B','replacement-phone');
  assert.equal(await valid(b,'replacement-phone'), true);
  assert.equal(await valid(a,'replacement-phone'), false);
  // Same phone can be rebound by its student after an administrator reset.
  await command('reset_student_device',b,null,'Other','Approved account correction');
  await login('Student-B','replacement-phone');
  assert.equal(await valid(b,'replacement-phone'), true);
  const history = await command('history',null,null,null);
  assert.equal(history.rows.length,4);
  assert.equal(history.rows[0].reason,'Other');
  assert.equal((await command('history',null,null,null,'','test-reset-password',1)).rows.length,0);
  assert.equal(JSON.stringify(history).includes('test-reset-password'),false);
  await assert.rejects(() => command('reset_student_device',a,null,'Lost phone'), /no device binding/);
  await db.exec('reset role');
  for (const t of preserved) assert.deepEqual((await db.query(`select * from public.${t} order by id`)).rows,before[t],`${t} preserved`);
  await db.close();
  console.log('Device SQL checks passed: password/reason validation, protected writes/history, replacement, reassignment, same-phone rebinding, revocation and academic-record preservation.');
})().catch(e => { console.error(e.message); process.exitCode = 1; });
