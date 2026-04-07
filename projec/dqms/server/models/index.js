// models/index.js
'use strict';

const base = require('./base.model');
const queue = require('./queue.model');
const student = require('./student.model');
const dqms = require('./dqms.model');
const office = require('./office.model');

module.exports = {
    // Base
    pool: base.pool,
    parseOfficeId: base.parseOfficeId,
    query: base.query,
    
    // Queue
    getCurrentServing: queue.getCurrentServing,
    getWaitingTickets: queue.getWaitingTickets,
    callNext: queue.callNext,
    skipTicket: queue.skipTicket,
    markServed: queue.markServed,
    saveElapsedSeconds: queue.saveElapsedSeconds,
    getTodayTotalElapsed: queue.getTodayTotalElapsed,
    getWeeklyAnalytics: queue.getWeeklyAnalytics,
    getOfficeAnalytics: queue.getOfficeAnalytics,
    updateTicketStatus: queue.updateTicketStatus,
    setCurrentServing: queue.setCurrentServing,
    clearAnalyticsCache: queue.clearAnalyticsCache,
    
    // Student
    createStudent: student.createStudent,
    getAllStudents: student.getAllStudents,
    getStudentById: student.getStudentById,
    getStudentByDQMSNumber: student.getStudentByDQMSNumber,
    getStudentByPhone: student.getStudentByPhone,
    updateStudent: student.updateStudent,
    deleteStudent: student.deleteStudent,
    
    // DQMS
    registerDQMS: dqms.registerDQMS,
    getDQMSByPhone: dqms.getDQMSByPhone,
    getDQMSByNumber: dqms.getDQMSByNumber,
    getDQMSDetails: dqms.getDQMSDetails,
    markTicketSent: dqms.markTicketSent,
    getPendingTicketNotifications: dqms.getPendingTicketNotifications,
    getDQMSStats: dqms.getDQMSStats,
    getAverageServiceTime: dqms.getAverageServiceTime,
    getWaitingQueueLength: dqms.getWaitingQueueLength,
    calculateExpectedWaitTime: dqms.calculateExpectedWaitTime,
    
    // Office
    getAllOffices: office.getAllOffices,
    getOfficeById: office.getOfficeById,
    createOffice: office.createOffice,
    updateOffice: office.updateOffice,
    deleteOffice: office.deleteOffice
};