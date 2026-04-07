// controllers/queueController.js
'use strict';

const models = require('../models');

// ── Get current serving ticket for office ────────────────────────────────────
exports.getCurrentServing = async (req, res) => {
    try {
        const { officeId } = req.query;
        
        if (!officeId) {
            return res.status(400).json({ error: 'officeId query parameter is required' });
        }

        const current = await models.getCurrentServing(officeId);
        
        res.json({
            success: true,
            currentServing: current || null
        });
    } catch (error) {
        console.error('❌ getCurrentServing error:', error);
        res.status(500).json({ 
            error: 'Failed to get current serving ticket',
            details: error.message 
        });
    }
};

// ── Get waiting tickets for office ───────────────────────────────────────────
exports.getWaiting = async (req, res) => {
    try {
        const { officeId } = req.query;
        
        if (!officeId) {
            return res.status(400).json({ error: 'officeId query parameter is required' });
        }

        const waiting = await models.getWaitingTickets(officeId);
        
        // Return array directly for staff frontend
        res.json(waiting);
    } catch (error) {
        console.error('❌ getWaiting error:', error);
        res.status(500).json({ 
            error: 'Failed to get waiting tickets',
            details: error.message 
        });
    }
};

// ── Call next ticket ─────────────────────────────────────────────────────────
exports.callNext = async (req, res) => {
    try {
        const { officeId } = req.body;
        
        if (!officeId) {
            return res.status(400).json({ error: 'officeId is required' });
        }

        const nextTicket = await models.callNext(officeId);
        
        if (!nextTicket) {
            return res.status(404).json({ error: 'No waiting tickets', success: false });
        }

        // Broadcast to all displays and student UIs in real-time
        try {
            const { broadcastToAll } = require('../app');
            broadcastToAll({
                type: 'ticket_called',
                officeId: parseInt(officeId),
                ticketNumber: nextTicket.ticketNumber
            });
        } catch(e) {}

        res.json({ success: true, ticketNumber: nextTicket.ticketNumber });
    } catch (error) {
        console.error('❌ callNext error:', error);
        res.status(500).json({ 
            error: 'Failed to call next ticket',
            details: error.message 
        });
    }
};

// ── Mark ticket as served ────────────────────────────────────────────────────
exports.markServed = async (req, res) => {
    try {
        const { ticketNumber } = req.params;
        const { officeId } = req.body;
        
        if (!ticketNumber || !officeId) {
            return res.status(400).json({ error: 'ticketNumber and officeId are required' });
        }

        const served = await models.markServed(ticketNumber, officeId);
        
        if (!served) {
            return res.status(404).json({ error: 'Ticket not found', success: false });
        }

        // Broadcast so student UIs update in real-time
        try {
            const { broadcastToAll } = require('../app');
            broadcastToAll({ type: 'ticket_served', officeId, ticketNumber });
        } catch(e) {}

        res.json({ success: true, data: served });
    } catch (error) {
        console.error('❌ markServed error:', error);
        res.status(500).json({ error: 'Failed to mark ticket as served', details: error.message });
    }
};

// ── Skip a ticket ────────────────────────────────────────────────────────────
exports.skipTicket = async (req, res) => {
    try {
        const { ticketNumber } = req.params;
        const { officeId } = req.body;
        
        if (!ticketNumber || !officeId) {
            return res.status(400).json({ error: 'ticketNumber and officeId are required' });
        }

        const skipped = await models.skipTicket(ticketNumber, officeId);
        
        if (!skipped) {
            return res.status(404).json({ 
                error: 'Ticket not found',
                success: false
            });
        }

        res.json({
            success: true,
            data: skipped,
            message: `Ticket #${ticketNumber} skipped`
        });
    } catch (error) {
        console.error('❌ skipTicket error:', error);
        res.status(500).json({ 
            error: 'Failed to skip ticket',
            details: error.message 
        });
    }
};

// ── Save elapsed time for served ticket ──────────────────────────────────────
exports.saveElapsed = async (req, res) => {
    try {
        const { ticketNumber, elapsedSeconds, officeId } = req.body;
        
        if (!ticketNumber || elapsedSeconds === undefined || !officeId) {
            return res.status(400).json({ 
                error: 'ticketNumber, elapsedSeconds, and officeId are required' 
            });
        }

        const result = await models.saveElapsedSeconds(ticketNumber, elapsedSeconds, officeId);
        
        res.json({
            success: true,
            data: result,
            message: `Elapsed time recorded: ${elapsedSeconds}s`
        });
    } catch (error) {
        console.error('❌ saveElapsed error:', error);
        res.status(500).json({ 
            error: 'Failed to save elapsed time',
            details: error.message 
        });
    }
};

// ── Get total elapsed time for today ─────────────────────────────────────────
exports.getTotalElapsed = async (req, res) => {
    try {
        const { officeId } = req.query;
        
        if (!officeId) {
            return res.status(400).json({ error: 'officeId query parameter is required' });
        }

        const total = await models.getTodayTotalElapsed(officeId);
        
        res.json({
            success: true,
            totalSeconds: total || 0
        });
    } catch (error) {
        console.error('❌ getTotalElapsed error:', error);
        res.status(500).json({ 
            error: 'Failed to get total elapsed time',
            details: error.message 
        });
    }
};

// ── Get weekly analytics ─────────────────────────────────────────────────────
exports.getDisplayData = async (req, res) => {
    try {
        const { officeId } = req.params;
        const { pool } = require('../models/base.model');

        const { rows } = await pool.query(`
            SELECT
                cs.ticket_number   AS now_serving,
                o.name             AS office_name,
                o.id               AS office_id,
                COUNT(wt.id)::INT  AS waiting_count
            FROM offices o
            LEFT JOIN current_serving cs ON cs.office_id = o.id
            LEFT JOIN queue_tickets wt   ON wt.office_id = o.id AND wt.status = 'waiting'
            WHERE o.id = $1
            GROUP BY cs.ticket_number, o.name, o.id
        `, [officeId]);

        if (!rows.length) return res.status(404).json({ error: 'Office not found' });

        const d = rows[0];
        res.json({
            office_id:     d.office_id,
            office_name:   d.office_name,
            now_serving:   d.now_serving ? String(d.now_serving).padStart(3, '0') : '---',
            waiting_count: d.waiting_count
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};

exports.getWeeklyAnalytics = async (req, res) => {
    try {
        const weekOffset = req.query.week === 'last' ? 1 : 0;
        const analytics = await models.getWeeklyAnalytics(weekOffset);
        
        // Calculate aggregates for UI
        const days = analytics.days || [];
        const todayData = days.length > 0 ? days[days.length - 1] : null;
        const todayAvgMinutes = todayData?.avgWaitMinutes || null;
        
        // Week average
        const avgWaits = days.filter(d => d.avgWaitMinutes != null).map(d => d.avgWaitMinutes);
        const weekAvgMinutes = avgWaits.length > 0 
            ? (avgWaits.reduce((a, b) => a + b, 0) / avgWaits.length)
            : null;
        
        // Today tickets
        const todayTickets = todayData?.ticketsServed || 0;
        
        res.json({
            success: true,
            days,
            peakHours: analytics.peakHours,
            todayAvgMinutes,
            weekAvgMinutes,
            todayTickets
        });
    } catch (error) {
        console.error('❌ getWeeklyAnalytics error:', error);
        res.status(500).json({ 
            error: 'Failed to get weekly analytics',
            details: error.message 
        });
    }
};

// ── Get office analytics ─────────────────────────────────────────────────────
exports.getOfficeAnalytics = async (req, res) => {
    try {
        const { officeId } = req.query;
        
        if (!officeId) {
            return res.status(400).json({ error: 'officeId query parameter is required' });
        }

        const analytics = await models.getOfficeAnalytics(officeId);
        
        res.json({
            success: true,
            data: analytics
        });
    } catch (error) {
        console.error('❌ getOfficeAnalytics error:', error);
        res.status(500).json({ 
            error: 'Failed to get office analytics',
            details: error.message 
        });
    }
};

exports.getAllOfficesAvgWait = async (req, res) => {
    try {
        const { pool } = require('../models/base.model');
        const { rows } = await pool.query(`
            SELECT
                office_id,
                ROUND(AVG(EXTRACT(EPOCH FROM (serve_ended_at - issued_at)) / 60.0)::numeric, 1) as avg_wait_minutes,
                COUNT(*) as total_served
            FROM queue_tickets
            WHERE status = 'served'
              AND serve_ended_at IS NOT NULL
              AND issued_at IS NOT NULL
            GROUP BY office_id
        `);
        // key by office_id for easy lookup
        const result = {};
        rows.forEach(r => { result[r.office_id] = { avg_wait_minutes: parseFloat(r.avg_wait_minutes) || 0, total_served: parseInt(r.total_served) }; });
        res.json({ success: true, data: result });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};