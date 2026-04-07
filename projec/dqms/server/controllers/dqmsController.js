// controllers/dqmsController.js
'use strict';

const models = require('../models');
const { sendTicketNotification } = require('../services/smsService');

exports.registerDQMS = async (req, res) => {
    try {
        const { dqmsNumber, officeId } = req.body;
        
        if (!dqmsNumber || !officeId) {
            return res.status(400).json({ 
                error: 'dqmsNumber and officeId are required' 
            });
        }
        
        const officeIdInt = parseInt(officeId);
        if (isNaN(officeIdInt)) {
            return res.status(400).json({ error: 'officeId must be a number' });
        }
        
        const student = await models.getStudentByDQMSNumber(dqmsNumber);
        
        if (!student) {
            return res.status(404).json({ 
                error: 'Student not found. Please contact admin to register student first.' 
            });
        }
        
        const office = await models.getOfficeById(officeIdInt);
        
        if (!office) {
            return res.status(404).json({ error: 'Office not found' });
        }
        
        const record = await models.registerDQMS(dqmsNumber, student.id, officeIdInt);
        
        // Calculate expected waiting time
        const expectedWaitMinutes = await models.calculateExpectedWaitTime(officeIdInt);
        
        // Send SMS notification with ticket number and waiting time
        if (record.ticket_number && student.phone_number) {
            const smsResult = await sendTicketNotification(
                student.phone_number,
                record.ticket_number,
                student.student_name || 'Student',
                office.name,
                expectedWaitMinutes
            );
            console.log(`📨 SMS notification result:`, smsResult);
        }
        
        res.status(201).json({
            success: true,
            message: 'DQMS registered successfully',
            data: {
                dqms_number: record.dqms_number,
                office_id: record.office_id,
                office_name: office.name,
                student_name: student.student_name,
                phone_number: student.phone_number,
                student_id: student.registration_number,
                ticket_number: String(record.ticket_number).padStart(3, '0'),
                expected_wait_minutes: Math.round(expectedWaitMinutes),
                ticket_sent: record.ticket_sent
            }
        });
    } catch (error) {
        console.error('❌ registerDQMS error:', error);
        res.status(500).json({ 
            error: 'Failed to register DQMS',
            details: error.message 
        });
    }
};

exports.getStudentQueueInfo = async (req, res) => {
    try {
        const { dqmsNumber } = req.params;
        const { pool } = require('../models/base.model');

        // Get the student's active ticket
        const { rows: ticketRows } = await pool.query(
            `SELECT qt.ticket_number, qt.status, qt.issued_at, qt.office_id, o.name as office_name
             FROM queue_tickets qt
             LEFT JOIN offices o ON qt.office_id = o.id
             WHERE qt.dqms_number = $1 AND qt.status IN ('waiting','called')
             ORDER BY qt.issued_at DESC LIMIT 1`,
            [dqmsNumber]
        );

        if (ticketRows.length === 0) {
            return res.json({ success: true, data: { active_ticket: null } });
        }

        const ticket   = ticketRows[0];
        const officeId = ticket.office_id;

        // Run all queries in parallel
        const [waitingRes, currentRes, avgRes] = await Promise.all([
            // How many tickets are waiting ahead of this student
            pool.query(
                `SELECT COUNT(*) as ahead
                 FROM queue_tickets
                 WHERE office_id = $1 AND status = 'waiting'
                   AND ticket_number < $2`,
                [officeId, ticket.ticket_number]
            ),
            // Now serving
            pool.query(
                `SELECT ticket_number FROM current_serving WHERE office_id = $1 LIMIT 1`,
                [officeId]
            ),
            // Real avg: total time from arrival (issued_at) to service end (serve_ended_at)
            // Only use recent served tickets (last 30 days) to keep it relevant
            pool.query(
                `SELECT AVG(EXTRACT(EPOCH FROM (serve_ended_at - issued_at)) / 60.0) as avg_total_minutes
                 FROM queue_tickets
                 WHERE office_id = $1
                   AND status = 'served'
                   AND serve_ended_at IS NOT NULL
                   AND issued_at IS NOT NULL
                   AND issued_at > NOW() - INTERVAL '30 days'`,
                [officeId]
            )
        ]);

        const aheadCount    = parseInt(waitingRes.rows[0].ahead) || 0;
        const nowServing    = currentRes.rows[0]?.ticket_number ?? null;
        const avgMinPerTicket = parseFloat(avgRes.rows[0]?.avg_total_minutes) || 2;

        // Expected wait = tickets ahead × avg time per ticket
        const expectedWaitMinutes = Math.round(aheadCount * avgMinPerTicket);

        res.json({
            success: true,
            data: {
                active_ticket: {
                    ticket_number: ticket.ticket_number,
                    status: ticket.status,
                    issued_at: ticket.issued_at
                },
                office_id: officeId,
                office_name: ticket.office_name,
                now_serving: nowServing,
                waiting_total: aheadCount + 1, // include self
                tickets_ahead: aheadCount,
                avg_minutes_per_ticket: Math.round(avgMinPerTicket * 10) / 10,
                expected_wait_minutes: expectedWaitMinutes
            }
        });
    } catch (error) {
        console.error('❌ getStudentQueueInfo error:', error);
        res.status(500).json({ success: false, error: error.message });
    }
};

exports.getDQMSStatus = async (req, res) => {
    try {
        const { dqmsNumber } = req.params;

        if (!dqmsNumber) {
            return res.status(400).json({ error: 'dqmsNumber is required' });
        }

        const record = await models.getDQMSByNumber(dqmsNumber);

        if (!record) {
            return res.status(404).json({ error: 'DQMS number not found' });
        }

        // Enrich with live ticket status from queue_tickets
        const { pool } = require('../models/base.model');
        const { rows } = await pool.query(
            `SELECT ticket_number, status, issued_at, called_at
             FROM queue_tickets
             WHERE dqms_number = $1 AND status IN ('waiting','called')
             ORDER BY issued_at DESC LIMIT 1`,
            [dqmsNumber]
        );

        const activeTicket = rows[0] || null;

        res.json({
            success: true,
            data: {
                ...record,
                active_ticket: activeTicket ? {
                    ticket_number: activeTicket.ticket_number,
                    status: activeTicket.status,
                    issued_at: activeTicket.issued_at,
                    called_at: activeTicket.called_at
                } : null
            }
        });
    } catch (error) {
        console.error('❌ getDQMSStatus error:', error);
        res.status(500).json({
            error: 'Failed to get DQMS status',
            details: error.message
        });
    }
};

exports.getCurrentTicketByPhone = async (req, res) => {
    try {
        const { phone, office } = req.query;

        if (!phone) return res.status(400).send('0');

        // Find the dqms record for this phone
        const record = await models.getDQMSByPhone(phone, office || null);
        if (!record || !record.dqms_number) return res.send('0');

        // Check queue_tickets for an active ticket linked to this dqms_number
        const { pool } = require('../models/base.model');
        const { rows } = await pool.query(
            `SELECT ticket_number, status FROM queue_tickets
             WHERE dqms_number = $1 AND status IN ('waiting','called')
             ORDER BY issued_at DESC LIMIT 1`,
            [record.dqms_number]
        );

        if (rows.length === 0) return res.send('0');
        return res.send(String(rows[0].ticket_number));
    } catch (error) {
        console.error('❌ getCurrentTicketByPhone error:', error);
        res.status(500).send('0');
    }
};

exports.markTicketSent = async (req, res) => {
    try {
        const { dqmsNumber } = req.params;
        
        if (!dqmsNumber) {
            return res.status(400).json({ error: 'dqmsNumber is required' });
        }
        
        const record = await models.markTicketSent(dqmsNumber);
        
        if (!record) {
            return res.status(404).json({ error: 'DQMS record not found' });
        }
        
        res.json({
            success: true,
            message: 'Ticket marked as sent',
            data: record
        });
    } catch (error) {
        console.error('❌ markTicketSent error:', error);
        res.status(500).json({ 
            error: 'Failed to mark ticket as sent',
            details: error.message 
        });
    }
};

exports.getPendingNotifications = async (req, res) => {
    try {
        const { office } = req.query;
        const pending = await models.getPendingTicketNotifications(office || null);
        
        res.json({
            success: true,
            count: pending.length,
            data: pending
        });
    } catch (error) {
        console.error('❌ getPendingNotifications error:', error);
        res.status(500).json({ 
            error: 'Failed to get pending notifications',
            details: error.message 
        });
    }
};

exports.getDQMSStats = async (req, res) => {
    try {
        const stats = await models.getDQMSStats();
        res.json({
            success: true,
            data: stats
        });
    } catch (error) {
        console.error('❌ getDQMSStats error:', error);
        res.status(500).json({ 
            error: 'Failed to get DQMS stats',
            details: error.message 
        });
    }
};
exports.getExpectedWaitTime = async (req, res) => {
    try {
        const { officeId } = req.params;
        
        if (!officeId) {
            return res.status(400).json({ error: 'officeId is required' });
        }
        
        const waitingCount = await models.getWaitingQueueLength(officeId);
        const avgServiceTime = await models.getAverageServiceTime(officeId);
        const expectedWaitMinutes = await models.calculateExpectedWaitTime(officeId);
        
        res.json({
            success: true,
            data: {
                office_id: officeId,
                waiting_tickets: waitingCount,
                average_service_time_minutes: Math.round(avgServiceTime * 10) / 10,
                expected_wait_minutes: Math.round(expectedWaitMinutes),
                expected_wait_formatted: `${Math.round(expectedWaitMinutes)} min`
            }
        });
    } catch (error) {
        console.error('❌ getExpectedWaitTime error:', error);
        res.status(500).json({ 
            error: 'Failed to calculate expected wait time',
            details: error.message 
        });
    }
};
