const request = require('supertest');
const { app }  = require('../app');
const { pool } = require('../models/base.model');

// Mock SMS so register tests don't timeout waiting for real SMS API
jest.mock('../services/smsService', () => ({
  sendTicketNotification: jest.fn().mockResolvedValue({ success: true })
}));

// ── Seed constants ────────────────────────────────────────────────────────────
const OFFICE_ID   = 10;
const DQMS_NUMBER = 'C100';
const PHONE       = '+254797074165';
const REG_NUMBER  = 'CT202/113637/23';
const STUDENT_ID  = '9c0eff7b-643d-4f3d-a07e-52ec9a4f5573';
const STAFF_ID    = '87335b05-25ac-4e8c-827f-325ec9d30db8';
const STAFF_USER  = 'sam';

let createdStudentId = null;
let calledTicket     = null;
let createdOfficeId  = null;

afterAll(async () => { await pool.end(); });

// ─────────────────────────────────────────────────────────────────────────────
describe('Health', () => {
  test('GET /health → 200', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('status');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('Offices', () => {
  test('GET /api/offices → 200 array', async () => {
    const res = await request(app).get('/api/offices');
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  test('POST /api/offices → 201 with id', async () => {
    const res = await request(app).post('/api/offices')
      .send({ name: 'Jest Test Office', status: 'active' });
    expect(res.statusCode).toBe(201);
    expect(res.body).toHaveProperty('id');
    createdOfficeId = res.body.id;
  });

  test('PUT /api/offices/:id → 200', async () => {
    const res = await request(app).put(`/api/offices/${createdOfficeId}`)
      .send({ name: 'Jest Updated Office', status: 'inactive' });
    expect(res.statusCode).toBe(200);
  });

  test('POST /api/offices/:id/reset-tickets → 200', async () => {
    const res = await request(app).post(`/api/offices/${createdOfficeId}/reset-tickets`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('DELETE /api/offices/:id → 200', async () => {
    const res = await request(app).delete(`/api/offices/${createdOfficeId}`);
    expect(res.statusCode).toBe(200);
  });

  test('POST /api/offices missing name → 400', async () => {
    const res = await request(app).post('/api/offices').send({});
    expect(res.statusCode).toBe(400);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('Staff', () => {
  test('GET /api/staff → 200 array', async () => {
    const res = await request(app).get('/api/staff');
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  test('POST /api/staff/login wrong password → 401', async () => {
    const res = await request(app).post('/api/staff/login')
      .send({ username: STAFF_USER, password: 'wrongpass' });
    expect(res.statusCode).toBe(401);
  });

  test('POST /api/staff/login missing fields → 400', async () => {
    const res = await request(app).post('/api/staff/login').send({});
    expect(res.statusCode).toBe(400);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('Students', () => {
  test('GET /api/students → 200', async () => {
    const res = await request(app).get('/api/students');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('success', true);
  });

  test('GET /api/students/:id → 200', async () => {
    const res = await request(app).get(`/api/students/${STUDENT_ID}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('GET /api/students/:id not found → 404', async () => {
    const res = await request(app).get('/api/students/00000000-0000-0000-0000-000000000000');
    expect(res.statusCode).toBe(404);
  });

  test('GET /api/students/by-dqms/:dqmsNumber → 200', async () => {
    const res = await request(app).get(`/api/students/by-dqms/${DQMS_NUMBER}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('GET /api/students/by-phone/:phone → 200', async () => {
    const res = await request(app).get(`/api/students/by-phone/${encodeURIComponent(PHONE)}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('GET /api/student/next-dqms?prefix=T → 200 with next', async () => {
    const res = await request(app).get('/api/student/next-dqms?prefix=T');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('next');
    expect(res.body.next).toMatch(/^T\d{3,}/);
  });

  test('POST /api/students → 201', async () => {
    const res = await request(app).post('/api/students')
      .send({ dqmsNumber: 'JEST001', phoneNumber: '0700000099', studentName: 'Jest User', studentId: 'JEST001' });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    createdStudentId = res.body.data?.id;
  });

  test('POST /api/student/lookup → 200', async () => {
    const res = await request(app).post('/api/student/lookup')
      .send({ registrationNumber: REG_NUMBER, phoneNumber: PHONE });
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveProperty('dqmsNumber');
  });

  test('POST /api/student/lookup wrong reg → 404', async () => {
    const res = await request(app).post('/api/student/lookup')
      .send({ registrationNumber: 'WRONG', phoneNumber: PHONE });
    expect(res.statusCode).toBe(404);
  });

  test('PUT /api/students/:id → 200', async () => {
    const res = await request(app).put(`/api/students/${createdStudentId}`)
      .send({ studentName: 'Jest Updated', phoneNumber: '0700000099', registrationNumber: 'JEST001', isActive: true });
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('DELETE /api/students/:id → 200', async () => {
    const res = await request(app).delete(`/api/students/${createdStudentId}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('DQMS', () => {
  test('POST /api/register → 201', async () => {
    const res = await request(app).post('/api/register')
      .send({ dqmsNumber: DQMS_NUMBER, officeId: OFFICE_ID });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveProperty('ticket_number');
  });

  test('POST /api/register missing fields → 400', async () => {
    const res = await request(app).post('/api/register').send({});
    expect(res.statusCode).toBe(400);
  });

  test('GET /api/status/:dqmsNumber → 200', async () => {
    const res = await request(app).get(`/api/status/${DQMS_NUMBER}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('GET /api/queue-info/:dqmsNumber → 200', async () => {
    const res = await request(app).get(`/api/queue-info/${DQMS_NUMBER}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('GET /api/current-ticket?phone= → 200', async () => {
    const res = await request(app).get(`/api/current-ticket?phone=${encodeURIComponent(PHONE)}`);
    expect(res.statusCode).toBe(200);
  });

  test('GET /api/pending-notifications → 200', async () => {
    const res = await request(app).get('/api/pending-notifications');
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('GET /api/stats → 200', async () => {
    const res = await request(app).get('/api/stats');
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('GET /api/expected-wait/:officeId → 200', async () => {
    const res = await request(app).get(`/api/expected-wait/${OFFICE_ID}`);
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('Queue', () => {
  test('GET /api/current?officeId= → 200', async () => {
    const res = await request(app).get(`/api/current?officeId=${OFFICE_ID}`);
    expect(res.statusCode).toBe(200);
  });

  test('GET /api/display/:officeId → 200', async () => {
    const res = await request(app).get(`/api/display/${OFFICE_ID}`);
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('now_serving');
    expect(res.body).toHaveProperty('waiting_count');
  });

  test('GET /api/waiting?officeId= → 200', async () => {
    const res = await request(app).get(`/api/waiting?officeId=${OFFICE_ID}`);
    expect(res.statusCode).toBe(200);
  });

  test('POST /api/next → 200 with ticketNumber', async () => {
    const res = await request(app).post('/api/next').send({ officeId: OFFICE_ID });
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('ticketNumber');
    calledTicket = res.body.ticketNumber;
  });

  test('POST /api/next missing officeId → 400', async () => {
    const res = await request(app).post('/api/next').send({});
    expect(res.statusCode).toBe(400);
  });

  test('POST /api/served/:ticketNumber → 200', async () => {
    const res = await request(app).post(`/api/served/${calledTicket}`)
      .send({ officeId: OFFICE_ID });
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('GET /api/elapsed/total → 200', async () => {
    const res = await request(app).get(`/api/elapsed/total?officeId=${OFFICE_ID}`);
    expect(res.statusCode).toBe(200);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('Analytics', () => {
  test('GET /api/analytics/weekly?week=current → 200 with days', async () => {
    const res = await request(app).get('/api/analytics/weekly?week=current');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('days');
    expect(Array.isArray(res.body.days)).toBe(true);
  });

  test('GET /api/analytics/weekly?week=last → 200 with days', async () => {
    const res = await request(app).get('/api/analytics/weekly?week=last');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('days');
  });

  test('GET /api/analytics/offices-avg → 200', async () => {
    const res = await request(app).get('/api/analytics/offices-avg');
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });
});
