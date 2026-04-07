// routes/queueRoutes.js
'use strict';

const express = require('express');
const router  = express.Router();

const queueController   = require('../controllers/queueController');
const officesController = require('../controllers/officesController');
const staffController   = require('../controllers/staffController');
const dqmsController    = require('../controllers/dqmsController');
const studentsController = require('../controllers/studentsController');

// ── CONSOLIDATED: Queue & DQMS Registration ────────────────────────────────
// Single endpoint for registering a ticket via DQMS number and office ID
// Requires: { dqmsNumber, officeId }
router.post('/register',              dqmsController.registerDQMS);

// ── Queue Status & Management ──────────────────────────────────────────────
router.get( '/current',               queueController.getCurrentServing);
router.get( '/display/:officeId',     queueController.getDisplayData);
router.post('/next',                  queueController.callNext);
router.post('/served/:ticketNumber',  queueController.markServed);
router.get( '/waiting',               queueController.getWaiting);
router.post('/skip/:ticketNumber',    queueController.skipTicket);
router.post('/elapsed',               queueController.saveElapsed);
router.get( '/elapsed/total',         queueController.getTotalElapsed);
router.get( '/analytics/weekly',      queueController.getWeeklyAnalytics);
router.get( '/analytics/by-office',   queueController.getOfficeAnalytics);
router.get( '/analytics/offices-avg', queueController.getAllOfficesAvgWait);

// ── DQMS Status & Notifications ────────────────────────────────────────────
router.get('/status/:dqmsNumber',      dqmsController.getDQMSStatus);
router.get('/queue-info/:dqmsNumber',  dqmsController.getStudentQueueInfo);
router.get('/current-ticket',          dqmsController.getCurrentTicketByPhone);
router.post('/ticket-sent/:dqmsNumber', dqmsController.markTicketSent);
router.get('/pending-notifications',   dqmsController.getPendingNotifications);
router.get('/expected-wait/:officeId',  dqmsController.getExpectedWaitTime);
router.get('/stats',                   dqmsController.getDQMSStats);

// ── Student Routes (Admin) ─────────────────────────────────────────────────────
router.get(   '/students',                  studentsController.getAllStudents);
router.get(   '/students/:id',              studentsController.getStudentById);
router.get(   '/students/by-dqms/:dqmsNumber', studentsController.getStudentByDQMS);
router.get(   '/students/by-phone/:phone',  studentsController.getStudentByPhone);
router.post(  '/students',                  studentsController.createStudent);
router.post(  '/student/lookup',            studentsController.lookupStudent);
router.get(   '/student/next-dqms',         studentsController.getNextDQMSNumber);
router.put(   '/students/:id',              studentsController.updateStudent);
router.delete('/students/:id',              studentsController.deleteStudent);

// ── Offices ───────────────────────────────────────────────────────────────────
router.get(   '/offices',        officesController.getAllOffices);
router.post(  '/offices',        officesController.createOffice);
router.put(   '/offices/:id',    officesController.updateOffice);
router.delete('/offices/:id',    officesController.deleteOffice);
router.post(  '/offices/:id/reset-tickets', officesController.resetTicketCounter);

// ── Staff ─────────────────────────────────────────────────────────────────────
router.get(   '/staff',          staffController.getAllStaff);
router.post(  '/staff',          staffController.createStaff);
router.put(   '/staff/:id',      staffController.updateStaff);
router.delete('/staff/:id',      staffController.deleteStaff);
router.post(  '/staff/login',    staffController.loginStaff);

module.exports = router;