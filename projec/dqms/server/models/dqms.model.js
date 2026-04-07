// models/dqms.model.js
'use strict';

const { pool, parseOfficeId } = require('./base.model');

async function registerDQMS(dqmsNumber, studentId, officeId) {
    const officeIdInt = parseOfficeId(officeId);
    const client = await pool.connect();
    
    try {
        await client.query('BEGIN');
        
        // Create a queue ticket first
        let ticketNumber;
        let nextTicketResult = await client.query(
            `SELECT next_ticket FROM ticket_counters WHERE office_id = $1 FOR UPDATE`,
            [officeIdInt]
        );
        
        if (nextTicketResult.rows.length === 0) {
            await client.query(
                `INSERT INTO ticket_counters (office_id, next_ticket) VALUES ($1, 1)
                 ON CONFLICT DO NOTHING`,
                [officeIdInt]
            );
            nextTicketResult = await client.query(
                `SELECT next_ticket FROM ticket_counters WHERE office_id = $1 FOR UPDATE`,
                [officeIdInt]
            );
        }
        
        ticketNumber = nextTicketResult.rows[0].next_ticket;
        
        // Increment counter
        await client.query(
            `UPDATE ticket_counters SET next_ticket = next_ticket + 1 WHERE office_id = $1`,
            [officeIdInt]
        );
        
        // Expire any previous active tickets for this dqms_number
        await client.query(
            `UPDATE queue_tickets SET status = 'cancelled'
             WHERE dqms_number = $1 AND status IN ('waiting','called')`,
            [dqmsNumber]
        );

        // Create queue ticket
        await client.query(
            `INSERT INTO queue_tickets (ticket_number, office_id, dqms_number, status, issued_at, created_at)
             VALUES ($1, $2, $3, 'waiting', NOW(), NOW())`,
            [ticketNumber, officeIdInt, dqmsNumber]
        );
        
        // Create/update DQMS record with ticket number
        const { rows } = await client.query(
            `INSERT INTO dqms_records (dqms_number, student_id, office_id, ticket_number)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (dqms_number) DO UPDATE
             SET student_id = EXCLUDED.student_id,
                 office_id = EXCLUDED.office_id,
                 ticket_number = EXCLUDED.ticket_number,
                 updated_at = CURRENT_TIMESTAMP
             RETURNING id, dqms_number, student_id, office_id, ticket_number, ticket_sent, created_at`,
            [dqmsNumber, studentId, officeIdInt, ticketNumber]
        );
        
        await client.query('COMMIT');
        console.log(`📱 DQMS Registered: ${dqmsNumber} -> Office: ${officeIdInt} -> Ticket: ${ticketNumber}`);
        return rows[0];
    } catch (error) {
        await client.query('ROLLBACK');
        throw error;
    } finally {
        client.release();
    }
}

async function getDQMSByPhone(phoneNumber, officeId = null) {
    let query = `
        SELECT dr.id, dr.dqms_number, dr.student_id, dr.office_id, dr.ticket_number,
               dr.ticket_sent, dr.ticket_sent_at, dr.created_at,
               s.phone_number, s.student_name, s.registration_number as student_number_id
        FROM dqms_records dr
        JOIN students s ON dr.student_id = s.id
        WHERE s.phone_number = $1
    `;
    let params = [phoneNumber];
    
    if (officeId) {
        const officeIdInt = parseOfficeId(officeId);
        query += ` AND dr.office_id = $2`;
        params.push(officeIdInt);
    }
    
    query += ` ORDER BY dr.created_at DESC LIMIT 1`;
    
    const { rows } = await pool.query(query, params);
    return rows[0] || null;
}

async function getDQMSByNumber(dqmsNumber) {
    const { rows } = await pool.query(`
        SELECT dr.id, dr.dqms_number, dr.student_id, dr.office_id, o.name as office_name,
               dr.ticket_number, dr.ticket_sent, dr.ticket_sent_at, dr.created_at, dr.updated_at,
               s.phone_number, s.student_name, s.registration_number as student_number_id
        FROM dqms_records dr
        LEFT JOIN students s ON dr.student_id = s.id
        LEFT JOIN offices o ON dr.office_id = o.id
        WHERE dr.dqms_number = $1
    `, [dqmsNumber]);
    return rows[0] || null;
}

async function getDQMSDetails(dqmsNumber) {
    const { rows } = await pool.query(`
        SELECT dr.id, dr.dqms_number, dr.office_id, o.name as office_name,
               dr.ticket_number, dr.ticket_sent, dr.ticket_sent_at, dr.created_at,
               s.id as student_id, s.phone_number, s.student_name,
               s.registration_number as student_number_id, s.is_active as student_active
        FROM dqms_records dr
        LEFT JOIN students s ON dr.student_id = s.id
        LEFT JOIN offices o ON dr.office_id = o.id
        WHERE dr.dqms_number = $1
    `, [dqmsNumber]);
    return rows[0] || null;
}

async function markTicketSent(dqmsNumber) {
    const { rows } = await pool.query(
        `UPDATE dqms_records
         SET ticket_sent = TRUE, ticket_sent_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE dqms_number = $1
         RETURNING *`,
        [dqmsNumber]
    );
    if (rows[0]) {
        console.log(`📨 Ticket #${rows[0].ticket_number} marked as sent for DQMS ${dqmsNumber}`);
    }
    return rows[0];
}

async function getPendingTicketNotifications(officeId = null) {
    let query = `
        SELECT dr.id, dr.dqms_number, dr.ticket_number, dr.created_at,
               s.phone_number, s.student_name
        FROM dqms_records dr
        JOIN students s ON dr.student_id = s.id
        WHERE dr.ticket_number IS NOT NULL AND dr.ticket_sent = FALSE
    `;
    let params = [];
    
    if (officeId) {
        const officeIdInt = parseOfficeId(officeId);
        query += ` AND dr.office_id = $1`;
        params.push(officeIdInt);
    }
    
    query += ` ORDER BY dr.created_at ASC`;
    
    const { rows } = await pool.query(query, params);
    return rows;
}

async function getDQMSStats() {
    const { rows } = await pool.query(`
        SELECT COUNT(*) as total_devices,
               COUNT(CASE WHEN ticket_number IS NOT NULL THEN 1 END) as with_tickets,
               COUNT(CASE WHEN ticket_sent = true THEN 1 END) as tickets_sent,
               COUNT(CASE WHEN ticket_sent = false AND ticket_number IS NOT NULL THEN 1 END) as pending_notifications
        FROM dqms_records
    `);
    return rows[0];
}

/**
 * Get average service time in minutes for an office
 * @param {number} officeId - Office ID
 * @returns {Promise<number>} Average service time in minutes
 */
async function getAverageServiceTime(officeId) {
    const officeIdInt = parseOfficeId(officeId);
    
    try {
        const { rows } = await pool.query(`
            SELECT 
                COALESCE(AVG(EXTRACT(EPOCH FROM (serve_ended_at - called_at)) / 60.0), 0) as avg_service_minutes
            FROM queue_tickets
            WHERE office_id = $1 
              AND status = 'served'
              AND serve_ended_at IS NOT NULL
              AND called_at IS NOT NULL
              AND EXTRACT(EPOCH FROM (serve_ended_at - called_at)) > 0
              AND issued_at > NOW() - INTERVAL '7 days'
        `, [officeIdInt]);
        
        const avgTime = rows[0]?.avg_service_minutes || 0;
        
        // Use default 2 minutes if no historical data
        return avgTime > 0 ? avgTime : 2;
    } catch (error) {
        console.warn(`⚠️ Error calculating average service time for office ${officeIdInt}:`, error.message);
        return 2; // Default 2 minutes
    }
}

/**
 * Get number of waiting tickets (queue position)
 * @param {number} officeId - Office ID
 * @returns {Promise<number>} Number of waiting tickets in queue
 */
async function getWaitingQueueLength(officeId) {
    const officeIdInt = parseOfficeId(officeId);
    
    try {
        const { rows } = await pool.query(`
            SELECT COUNT(*) as waiting_count
            FROM queue_tickets
            WHERE office_id = $1 AND status = 'waiting'
        `, [officeIdInt]);
        
        return rows[0]?.waiting_count || 0;
    } catch (error) {
        console.warn(`⚠️ Error getting queue length for office ${officeIdInt}:`, error.message);
        return 0;
    }
}

/**
 * Calculate expected waiting time in minutes
 * @param {number} officeId - Office ID
 * @returns {Promise<number>} Expected waiting time in minutes
 */
async function calculateExpectedWaitTime(officeId) {
    const queueLength = await getWaitingQueueLength(officeId);
    const avgServiceTime = await getAverageServiceTime(officeId);
    
    // New ticket goes to end of queue, so multiply queue length by average service time
    const expectedWaitMinutes = queueLength * avgServiceTime;
    
    return expectedWaitMinutes;
}

module.exports = {
    registerDQMS,
    getDQMSByPhone,
    getDQMSByNumber,
    getDQMSDetails,
    markTicketSent,
    getPendingTicketNotifications,
    getDQMSStats,
    getAverageServiceTime,
    getWaitingQueueLength,
    calculateExpectedWaitTime
};