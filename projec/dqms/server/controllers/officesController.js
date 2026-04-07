// controllers/officesController.js
'use strict';

const { pool } = require('../config/db');

// ── Get all offices (with live staff count) ───────────────────────────────────
exports.getAllOffices = async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT
        o.id,
        o.name,
        o.status,
        o.created_at AS "createdAt",
        COUNT(s.id)::INT AS "staffCount"
      FROM offices o
      LEFT JOIN staff s ON s.office_id = o.id
      GROUP BY o.id
      ORDER BY o.name
    `);
    res.json(rows);
  } catch (e) {
    console.error('❌ getAllOffices:', e);
    res.status(500).json({ error: 'Failed to get offices' });
  }
};

// ── Create an office ──────────────────────────────────────────────────────────
exports.createOffice = async (req, res) => {
  try {
    const { name, status = 'active' } = req.body;
    if (!name) return res.status(400).json({ error: 'name is required' });

    const validStatuses = ['active', 'inactive', 'closed'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ error: `status must be one of: ${validStatuses.join(', ')}` });
    }

    const { rows } = await pool.query(
      `INSERT INTO offices (name, status) VALUES ($1, $2)
       RETURNING id, name, status, created_at AS "createdAt"`,
      [name, status]
    );

    // Initialise a ticket counter row for the new office (office_id is now INTEGER)
    await pool.query(
      `INSERT INTO ticket_counters (office_id) VALUES ($1) ON CONFLICT DO NOTHING`,
      [rows[0].id]
    );

    res.status(201).json({ ...rows[0], staffCount: 0 });
  } catch (e) {
    console.error('❌ createOffice:', e);
    res.status(500).json({ error: 'Failed to create office' });
  }
};

// ── Update an office ──────────────────────────────────────────────────────────
exports.updateOffice = async (req, res) => {
  try {
    const { id } = req.params;
    const { name, status } = req.body;

    // Convert id to integer (if it's passed as string)
    const officeId = parseInt(id);
    if (isNaN(officeId)) {
      return res.status(400).json({ error: 'Invalid office ID' });
    }

    const { rows } = await pool.query(
      `UPDATE offices SET name = $2, status = $3, updated_at = NOW()
       WHERE id = $1
       RETURNING id, name, status`,
      [officeId, name, status]
    );

    if (rows.length === 0) return res.status(404).json({ error: 'Office not found' });
    res.json(rows[0]);
  } catch (e) {
    console.error('❌ updateOffice:', e);
    res.status(500).json({ error: 'Failed to update office' });
  }
};

// ── Delete an office ──────────────────────────────────────────────────────────
exports.deleteOffice = async (req, res) => {
  const { id } = req.params;
  
  // Convert id to integer
  const officeId = parseInt(id);
  if (isNaN(officeId)) {
    return res.status(400).json({ error: 'Invalid office ID' });
  }
  
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Unassign staff
    await client.query(`UPDATE staff SET office_id = NULL WHERE office_id = $1`, [officeId]);

    // 2. Clear current_serving
    await client.query(`DELETE FROM current_serving WHERE office_id = $1`, [officeId]);

    // 3. Delete elapsed_log for this office
    await client.query(`DELETE FROM elapsed_log WHERE office_id = $1`, [officeId]);

    // 4. Delete audit_log entries for this office's tickets
    await client.query(`
      DELETE FROM audit_log
      WHERE entity = 'queue_tickets'
        AND entity_id IN (
          SELECT id::TEXT FROM queue_tickets WHERE office_id = $1
        )`, [officeId]);

    // 5. Delete all tickets (removes the FK block on offices)
    await client.query(`DELETE FROM queue_tickets WHERE office_id = $1`, [officeId]);

    // 6. Delete ticket counter
    await client.query(`DELETE FROM ticket_counters WHERE office_id = $1`, [officeId]);

    // 7. Delete the office
    const { rowCount } = await client.query(`DELETE FROM offices WHERE id = $1`, [officeId]);

    if (rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Office not found' });
    }

    await client.query('COMMIT');
    res.json({ message: 'Office and all related data deleted successfully' });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('❌ deleteOffice:', e);
    res.status(500).json({ error: 'Failed to delete office' });
  } finally {
    client.release();
  }
};

// ── Reset ticket counter for an office ───────────────────────────────────────
exports.resetTicketCounter = async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query(
      `UPDATE ticket_counters SET next_ticket = 1, reset_date = CURRENT_DATE WHERE office_id = $1`,
      [id]
    );
    // Cancel all active waiting/called tickets for this office
    await pool.query(
      `UPDATE queue_tickets SET status = 'cancelled' WHERE office_id = $1 AND status IN ('waiting','called')`,
      [id]
    );
    res.json({ success: true, message: 'Ticket counter reset to 1' });
  } catch (e) {
    console.error('❌ resetTicketCounter:', e);
    res.status(500).json({ error: 'Failed to reset ticket counter' });
  }
};
