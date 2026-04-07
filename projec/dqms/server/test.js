// test.js — MERU DQMS API Endpoint Tester
// Run: node test.js
// Tests all endpoints, prints PASS/FAIL with details

const BASE = 'http://localhost:3000/api';

// ── Seed values from DB ───────────────────────────────────────────────────────
const OFFICE_ID      = 10;
const STUDENT_ID     = '9c0eff7b-643d-4f3d-a07e-52ec9a4f5573';
const STAFF_ID       = '87335b05-25ac-4e8c-827f-325ec9d30db8';
const DQMS_NUMBER    = 'C100';
const PHONE_NUMBER   = '+254797074165';
const REG_NUMBER     = 'CT202/113637/23';

let createdStudentId = null;
let calledTicket     = null;
let passed = 0, failed = 0;

async function req(method, path, body) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${BASE}${path}`, opts);
  let data;
  try { data = await res.json(); } catch { data = {}; }
  return { status: res.status, data };
}

function check(name, status, data, expectStatus, expectKey) {
  const statusOk = status === expectStatus;
  const keyOk    = expectKey ? (data[expectKey] !== undefined || data.data?.[expectKey] !== undefined || data.success !== undefined) : true;
  const pass     = statusOk && keyOk;
  if (pass) {
    console.log(`  ✅ PASS  ${name}`);
    passed++;
  } else {
    console.log(`  ❌ FAIL  ${name}`);
    console.log(`         Expected status ${expectStatus}, got ${status}`);
    if (expectKey && !keyOk) console.log(`         Missing key: "${expectKey}" in response`);
    console.log(`         Response:`, JSON.stringify(data).substring(0, 200));
    failed++;
  }
  return data;
}

async function run() {
  console.log('\n══════════════════════════════════════════');
  console.log('  MERU DQMS — API Endpoint Test Suite');
  console.log('══════════════════════════════════════════\n');

  let r;

  // ── Health ────────────────────────────────────────────────────────────────
  console.log('── Health ──────────────────────────────────');
  r = await req('GET', '/../health');
  // health is at /health not /api/health
  try {
    const res = await fetch('http://localhost:3000/health');
    const d   = await res.json();
    check('GET /health', res.status, d, 200, 'status');
  } catch(e) { console.log('  ❌ FAIL  GET /health —', e.message); failed++; }

  // ── Offices ───────────────────────────────────────────────────────────────
  console.log('\n── Offices ─────────────────────────────────');
  r = await req('GET', '/offices');
  check('GET /offices', r.status, r.data, 200);

  r = await req('POST', '/offices', { name: 'Test Office', status: 'active' });
  const newOfficeId = r.data.id || r.data.data?.id;
  check('POST /offices', r.status, r.data, 201, 'id');

  if (newOfficeId) {
    r = await req('PUT', `/offices/${newOfficeId}`, { name: 'Test Office Updated', status: 'inactive' });
    check('PUT /offices/:id', r.status, r.data, 200);

    r = await req('POST', `/offices/${newOfficeId}/reset-tickets`);
    check('POST /offices/:id/reset-tickets', r.status, r.data, 200, 'success');

    r = await req('DELETE', `/offices/${newOfficeId}`);
    check('DELETE /offices/:id', r.status, r.data, 200);
  }

  // ── Staff ─────────────────────────────────────────────────────────────────
  console.log('\n── Staff ───────────────────────────────────');
  r = await req('GET', '/staff');
  check('GET /staff', r.status, r.data, 200);

  r = await req('POST', '/staff/login', { username: 'admin', password: 'admin123' });
  check('POST /staff/login', r.status, r.data, 200, 'id');

  // ── Students ──────────────────────────────────────────────────────────────
  console.log('\n── Students ────────────────────────────────');
  r = await req('GET', '/students');
  check('GET /students', r.status, r.data, 200);

  r = await req('GET', `/students/${STUDENT_ID}`);
  check('GET /students/:id', r.status, r.data, 200, 'success');

  r = await req('GET', `/students/by-dqms/${DQMS_NUMBER}`);
  check('GET /students/by-dqms/:dqmsNumber', r.status, r.data, 200, 'success');

  r = await req('GET', `/students/by-phone/${encodeURIComponent(PHONE_NUMBER)}`);
  check('GET /students/by-phone/:phone', r.status, r.data, 200, 'success');

  r = await req('GET', `/student/next-dqms?prefix=T`);
  check('GET /student/next-dqms?prefix=T', r.status, r.data, 200, 'next');

  r = await req('POST', '/students', { dqmsNumber: 'TEST001', phoneNumber: '0700000001', studentName: 'Test User', studentId: 'TST001' });
  createdStudentId = r.data.data?.id;
  check('POST /students', r.status, r.data, 201, 'success');

  r = await req('POST', '/student/lookup', { registrationNumber: REG_NUMBER, phoneNumber: PHONE_NUMBER });
  check('POST /student/lookup', r.status, r.data, 200, 'success');

  if (createdStudentId) {
    r = await req('PUT', `/students/${createdStudentId}`, { studentName: 'Test Updated', phoneNumber: '0700000001', registrationNumber: 'TST001', isActive: true });
    check('PUT /students/:id', r.status, r.data, 200, 'success');

    r = await req('DELETE', `/students/${createdStudentId}`);
    check('DELETE /students/:id', r.status, r.data, 200, 'success');
  }

  // ── DQMS ──────────────────────────────────────────────────────────────────
  console.log('\n── DQMS ────────────────────────────────────');
  r = await req('POST', '/register', { dqmsNumber: DQMS_NUMBER, officeId: OFFICE_ID });
  check('POST /register', r.status, r.data, 201, 'success');

  r = await req('GET', `/status/${DQMS_NUMBER}`);
  check('GET /status/:dqmsNumber', r.status, r.data, 200, 'success');

  r = await req('GET', `/queue-info/${DQMS_NUMBER}`);
  check('GET /queue-info/:dqmsNumber', r.status, r.data, 200, 'success');

  r = await req('GET', `/current-ticket?phone=${encodeURIComponent(PHONE_NUMBER)}`);
  check('GET /current-ticket?phone=', r.status, r.data, 200);

  r = await req('GET', '/pending-notifications');
  check('GET /pending-notifications', r.status, r.data, 200, 'success');

  r = await req('GET', '/stats');
  check('GET /stats', r.status, r.data, 200, 'success');

  r = await req('GET', `/expected-wait/${OFFICE_ID}`);
  check('GET /expected-wait/:officeId', r.status, r.data, 200, 'success');

  // ── Queue ─────────────────────────────────────────────────────────────────
  console.log('\n── Queue ───────────────────────────────────');
  r = await req('GET', `/current?officeId=${OFFICE_ID}`);
  check('GET /current?officeId=', r.status, r.data, 200);

  r = await req('GET', `/display/${OFFICE_ID}`);
  check('GET /display/:officeId', r.status, r.data, 200, 'now_serving');

  r = await req('GET', `/waiting?officeId=${OFFICE_ID}`);
  check('GET /waiting?officeId=', r.status, r.data, 200);

  r = await req('POST', '/next', { officeId: OFFICE_ID });
  calledTicket = r.data.ticketNumber;
  check('POST /next', r.status, r.data, 200, 'ticketNumber');

  if (calledTicket) {
    r = await req('POST', `/served/${calledTicket}`, { officeId: OFFICE_ID });
    check('POST /served/:ticketNumber', r.status, r.data, 200, 'success');
  }

  // Register another ticket to test skip
  r = await req('POST', '/register', { dqmsNumber: DQMS_NUMBER, officeId: OFFICE_ID });
  r = await req('POST', '/next', { officeId: OFFICE_ID });
  const skipTicket = r.data.ticketNumber;
  if (skipTicket) {
    r = await req('POST', `/skip/${skipTicket}`, { officeId: OFFICE_ID });
    check('POST /skip/:ticketNumber', r.status, r.data, 200);
  }

  r = await req('POST', '/elapsed', { ticketNumber: calledTicket || 1, seconds: 120, officeId: OFFICE_ID });
  check('POST /elapsed', r.status, r.data, 200);

  r = await req('GET', `/elapsed/total?officeId=${OFFICE_ID}`);
  check('GET /elapsed/total', r.status, r.data, 200);

  // ── Analytics ─────────────────────────────────────────────────────────────
  console.log('\n── Analytics ───────────────────────────────');
  r = await req('GET', '/analytics/weekly?week=current');
  check('GET /analytics/weekly?week=current', r.status, r.data, 200, 'days');

  r = await req('GET', '/analytics/weekly?week=last');
  check('GET /analytics/weekly?week=last', r.status, r.data, 200, 'days');

  r = await req('GET', `/analytics/by-office?officeId=${OFFICE_ID}`);
  check('GET /analytics/by-office?officeId=', r.status, r.data, 200);

  r = await req('GET', '/analytics/offices-avg');
  check('GET /analytics/offices-avg', r.status, r.data, 200, 'success');

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log('\n══════════════════════════════════════════');
  console.log(`  Results: ${passed} passed, ${failed} failed out of ${passed + failed} tests`);
  if (failed === 0) console.log('  🎉 All tests passed!');
  else console.log(`  ⚠️  ${failed} test(s) need attention`);
  console.log('══════════════════════════════════════════\n');
}

run().catch(e => { console.error('Fatal error:', e.message); process.exit(1); });
