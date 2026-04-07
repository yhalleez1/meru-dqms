// models/queue.model.js
'use strict';

const { pool, parseOfficeId } = require('./base.model');

/**
 * Get current serving ticket number
 */
async function getCurrentServing(officeId = null) {
    if (officeId) {
        const officeIdInt = parseOfficeId(officeId);
        const { rows } = await pool.query(
            `SELECT ticket_number FROM current_serving WHERE office_id = $1`,
            [officeIdInt]
        );
        return rows.length ? rows[0].ticket_number : null;
    }
    const { rows } = await pool.query(
        `SELECT ticket_number FROM current_serving ORDER BY updated_at DESC LIMIT 1`
    );
    return rows.length ? rows[0].ticket_number : null;
}

/**
 * Get waiting tickets for an office
 */
async function getWaitingTickets(officeId = null) {
    let query, params;

    if (officeId) {
        const officeIdInt = parseOfficeId(officeId);
        // Query directly from queue_tickets table (view may not exist)
        query = `
            SELECT
                id,
                ticket_number AS "ticketNumber",
                office_id AS "officeId",
                status,
                issued_at AS "issuedAt",
                created_at AS "createdAt"
            FROM queue_tickets
            WHERE office_id = $1 AND status = 'waiting'
            ORDER BY created_at ASC
        `;
        params = [officeIdInt];
    } else {
        query = `
            SELECT id, ticket_number AS "ticketNumber", office_id AS "officeId",
                   status, issued_at AS "issuedAt", created_at AS "createdAt"
            FROM queue_tickets
            WHERE status = 'waiting'
            ORDER BY created_at
        `;
        params = [];
    }

    const { rows } = await pool.query(query, params);
    return rows;
}

/**
 * Call next ticket
 */
async function callNext(officeId) {
    const officeIdInt = parseOfficeId(officeId);
    
    try {
        // Try stored procedure first if it exists
        const { rows } = await pool.query(
            `CALL sp_call_next($1, NULL, NULL, NULL)`,
            [officeIdInt]
        );
        const row = rows[0];
        if (!row.p_found) return null;
        return { ticketId: row.p_ticket_id, ticketNumber: row.p_ticket_number };
    } catch (spError) {
        // Stored procedure doesn't exist, use direct query
        console.log('Stored procedure not found, using direct query...');
        
        // Get first waiting ticket
        const { rows } = await pool.query(`
            SELECT id, ticket_number AS "ticketNumber"
            FROM queue_tickets
            WHERE office_id = $1 AND status = 'waiting'
            ORDER BY created_at ASC
            LIMIT 1
        `, [officeIdInt]);
        
        if (rows.length === 0) return null;
        
        const ticket = rows[0];
        
        // Update as serving with called_at timestamp
        await pool.query(`
            UPDATE queue_tickets SET status = 'called', called_at = NOW()
            WHERE id = $1
        `, [ticket.id]);
        
        // Update current_serving table for this office
        try {
            await pool.query(`
                INSERT INTO current_serving (office_id, ticket_id, ticket_number, updated_at)
                VALUES ($1, $2, $3, NOW())
                ON CONFLICT (office_id) DO UPDATE
                SET ticket_id = EXCLUDED.ticket_id, 
                    ticket_number = EXCLUDED.ticket_number, 
                    updated_at = NOW()
            `, [officeIdInt, ticket.id, ticket.ticketNumber]);
            console.log(`✓ Updated current_serving for office ${officeIdInt}: ticket #${ticket.ticketNumber}`);
        } catch (updateErr) {
            console.warn(`⚠ Failed to update current_serving: ${updateErr.message}`);
            // Don't fail - just log warning
        }
        
        return { ticketId: ticket.id, ticketNumber: ticket.ticketNumber };
    }
}

/**
 * Skip ticket
 */
async function skipTicket(ticketNumber, officeId) {
    const officeIdInt = parseOfficeId(officeId);
    
    try {
        const { rows } = await pool.query(
            `CALL sp_skip_ticket($1, $2, NULL, NULL)`,
            [ticketNumber, officeIdInt]
        );
        const row = rows[0];
        return {
            skipped: ticketNumber,
            nextServing: row.p_next_ticket_number ?? null,
        };
    } catch (spError) {
        // Stored procedure doesn't exist, use direct query
        console.log('Skip stored procedure not found, using direct query...');
        
        // Mark ticket as skipped
        await pool.query(`
            UPDATE queue_tickets SET status = 'skipped', skipped_at = NOW()
            WHERE ticket_number = $1 AND office_id = $2
        `, [ticketNumber, officeIdInt]);
        
        return {
            skipped: ticketNumber,
            nextServing: null,
        };
    }
}

/**
 * Mark ticket as served
 */
async function markServed(ticketNumber, officeId) {
    const officeIdInt = parseOfficeId(officeId);
    // Update ticket status to served
    const { rows } = await pool.query(
        `UPDATE queue_tickets
         SET status = 'served', serve_ended_at = NOW()
         WHERE ticket_number = $1 AND office_id = $2
           AND status IN ('called','waiting')
         RETURNING *`,
        [ticketNumber, officeIdInt]
    );
    if (rows.length === 0) return null;
    // Clear current_serving if this was the active ticket
    await pool.query(
        `DELETE FROM current_serving WHERE office_id = $1 AND ticket_number = $2`,
        [officeIdInt, ticketNumber]
    );
    return { success: true, ticketNumber, officeId: officeIdInt };
}

/**
 * Save elapsed seconds
 */
async function saveElapsedSeconds(ticketNumber, elapsedSeconds, officeId) {
    const officeIdInt = parseOfficeId(officeId);
    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        const { rows: ticketRows } = await client.query(
            `SELECT id FROM queue_tickets 
             WHERE ticket_number = $1 AND office_id = $2 
             ORDER BY created_at DESC LIMIT 1`,
            [ticketNumber, officeIdInt]
        );

        if (ticketRows.length === 0) {
            await client.query('ROLLBACK');
            throw new Error(`Ticket #${ticketNumber} not found`);
        }

        const ticketId = ticketRows[0].id;

        await client.query(
            `UPDATE queue_tickets SET status = 'served', serve_ended_at = NOW()
             WHERE id = $1 AND status != 'served'`,
            [ticketId]
        );

        await client.query(
            `INSERT INTO elapsed_log (ticket_id, ticket_number, office_id, elapsed_seconds)
             VALUES ($1, $2, $3, $4)`,
            [ticketId, ticketNumber, officeIdInt, elapsedSeconds]
        );

        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Get total elapsed today
 */
async function getTodayTotalElapsed(officeId) {
    const officeIdInt = parseOfficeId(officeId);
    const { rows } = await pool.query(
        `SELECT COALESCE(SUM(elapsed_seconds), 0)::INT AS total
         FROM elapsed_log WHERE log_date = CURRENT_DATE AND office_id = $1`,
        [officeIdInt]
    );
    return rows[0].total;
}

/**
 * Get weekly analytics
 */
async function getWeeklyAnalytics(weekOffset = 0) {
    // weekOffset: 0 = this week (last 7 days), 1 = last week (7-14 days ago)
    const offsetDays = weekOffset * 7;
    try {
        // Try to use the view if it exists
        const { rows: dayRows } = await pool.query(`
            SELECT stat_date::TEXT AS date, TRIM(day_name) AS "dayName",
                   tickets_served::INT AS "ticketsServed",
                   tickets_fully_served::INT AS "ticketsFullyServed",
                   avg_wait_minutes::FLOAT AS "avgWaitMinutes",
                   avg_serve_minutes::FLOAT AS "avgServeMinutes",
                   total_serve_minutes::FLOAT AS "totalServeMinutes"
            FROM view_weekly_summary
            WHERE stat_date BETWEEN CURRENT_DATE - ($1 * INTERVAL '1 day')::DATE - 6 AND CURRENT_DATE - ($1 * INTERVAL '1 day')::DATE
            ORDER BY stat_date ASC
        `, [offsetDays]);
        
        const peakHours = {};
        try {
            const { rows: hourRows } = await pool.query(`
                SELECT EXTRACT(HOUR FROM issued_at)::INT as hour, COUNT(*)::INT AS count
                FROM queue_tickets
                WHERE issued_at BETWEEN CURRENT_DATE - ($1 * INTERVAL '1 day') - INTERVAL '6 days'
                  AND CURRENT_DATE - ($1 * INTERVAL '1 day') + INTERVAL '1 day'
                GROUP BY EXTRACT(HOUR FROM issued_at)
                ORDER BY count DESC
            `, [offsetDays]);
            hourRows.forEach(r => { peakHours[String(r.hour)] = r.count; });
        } catch (e) {}

        return { days: dayRows, peakHours };
    } catch (viewError) {
        const { rows: dayRows } = await pool.query(`
            SELECT
                d.day::TEXT AS date,
                TRIM(TO_CHAR(d.day, 'Day')) AS "dayName",
                COUNT(CASE WHEN qt.status IN ('served', 'completed') THEN 1 END)::INT AS "ticketsServed",
                COUNT(CASE WHEN qt.status IN ('served', 'completed') THEN 1 END)::INT AS "ticketsFullyServed",
                COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (qt.serve_ended_at - qt.issued_at)) / 60)::NUMERIC, 1), 0)::FLOAT AS "avgWaitMinutes",
                COALESCE(ROUND(AVG(el.elapsed_seconds / 60)::NUMERIC, 1), 0)::FLOAT AS "avgServeMinutes",
                COALESCE(ROUND(SUM(el.elapsed_seconds / 60)::NUMERIC, 1), 0)::FLOAT AS "totalServeMinutes"
            FROM (
                SELECT (CURRENT_DATE - ($1 * INTERVAL '1 day') - (i * INTERVAL '1 day'))::DATE AS day
                FROM generate_series(0, 6) AS i
            ) d
            LEFT JOIN queue_tickets qt ON qt.issued_at::DATE = d.day
            LEFT JOIN elapsed_log el ON el.log_date::DATE = d.day
            GROUP BY d.day
            ORDER BY d.day ASC
        `, [offsetDays]);

        const days = dayRows.length > 0 ? dayRows : [{
            date: new Date().toISOString().split('T')[0],
            dayName: new Date().toLocaleDateString('en-US', { weekday: 'long' }),
            ticketsServed: 0,
            ticketsFullyServed: 0,
            avgWaitMinutes: 0,
            avgServeMinutes: 0,
            totalServeMinutes: 0,
        }];

        // Get peak hours
        const peakHours = {};
        try {
            const { rows: hourRows } = await pool.query(
                `SELECT hour_of_day::TEXT AS hour, ticket_count::INT AS count FROM view_peak_hours`
            );
            hourRows.forEach(r => { peakHours[r.hour] = r.count; });
        } catch (e) {
            // No data yet
        }

        return { days, peakHours };
    }
}

/**
 * Get office analytics
 */
async function getOfficeAnalytics() {
    const { rows } = await pool.query(`
        SELECT office_id AS "officeId", office_name AS "officeName",
               stat_date::TEXT AS date,
               tickets_served::INT AS "ticketsServed",
               tickets_skipped::INT AS "ticketsSkipped",
               avg_wait_minutes::FLOAT AS "avgWaitMinutes",
               avg_serve_minutes::FLOAT AS "avgServeMinutes",
               total_serve_minutes::FLOAT AS "totalServeMinutes",
               currently_waiting::INT AS "currentlyWaiting"
        FROM view_office_leaderboard
    `);
    return rows;
}

// Legacy helpers
async function updateTicketStatus(ticketNumber, status, extra = {}) {
    const fields = ['status = $2'];
    const values = [ticketNumber, status];
    let idx = 3;

    if (extra.calledAt !== undefined) { fields.push(`called_at = $${idx++}`); values.push(extra.calledAt ?? null); }
    if (extra.serveEndedAt !== undefined) { fields.push(`serve_ended_at = $${idx++}`); values.push(extra.serveEndedAt ?? null); }
    if (extra.skippedAt !== undefined) { fields.push(`skipped_at = $${idx++}`); values.push(extra.skippedAt ?? null); }

    await pool.query(`UPDATE queue_tickets SET ${fields.join(', ')} WHERE ticket_number = $1`, values);
}

async function setCurrentServing(number, officeId = null) {
    if (!officeId) return;
    const officeIdInt = parseOfficeId(officeId);
    await pool.query(
        `INSERT INTO current_serving (office_id, ticket_number, updated_at)
         VALUES ($1, $2, NOW())
         ON CONFLICT (office_id) DO UPDATE
         SET ticket_number = EXCLUDED.ticket_number, updated_at = NOW()`,
        [officeIdInt, number]
    );
}

function clearAnalyticsCache() {}

module.exports = {
    getCurrentServing,
    getWaitingTickets,
    callNext,
    skipTicket,
    markServed,
    saveElapsedSeconds,
    getTodayTotalElapsed,
    getWeeklyAnalytics,
    getOfficeAnalytics,
    updateTicketStatus,
    setCurrentServing,
    clearAnalyticsCache
};