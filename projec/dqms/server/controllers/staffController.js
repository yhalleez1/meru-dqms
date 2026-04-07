// controllers/staffController.js
'use strict';

const { pool } = require('../config/db');
const { parseOfficeId } = require('../models/base.model');
const bcrypt   = require('bcrypt');

const SALT_ROUNDS = 10;

// ── Get all staff (no password hashes) ───────────────────────────────────────
exports.getAllStaff = async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT
        s.id,
        s.name,
        s.username,
        s.office_id   AS "officeId",
        s.is_active   AS "isActive",
        s.last_login_at AS "lastLoginAt",
        s.created_at  AS "createdAt",
        o.name        AS "officeName"
      FROM staff s
      LEFT JOIN offices o ON o.id = s.office_id
      ORDER BY s.name
    `);
    res.json(rows);
  } catch (e) {
    console.error('❌ getAllStaff:', e);
    res.status(500).json({ error: 'Failed to get staff' });
  }
};

// ── Create a staff member ─────────────────────────────────────────────────────
exports.createStaff = async (req, res) => {
  try {
    const { name, username, password, officeId } = req.body;
    if (!name || !username || !password) {
      return res.status(400).json({ error: 'name, username, and password are required' });
    }

    // Check username uniqueness
    const { rows: existing } = await pool.query(
      `SELECT id FROM staff WHERE username = $1`,
      [username]
    );
    if (existing.length > 0) return res.status(400).json({ error: 'Username already taken' });

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    // Validate and use officeId if provided
    let officeIdInt = null;
    if (officeId) {
      officeIdInt = parseOfficeId(officeId);
      if (!officeIdInt) {
        return res.status(400).json({ error: 'Invalid office ID' });
      }
    }

    const { rows } = await pool.query(
      `INSERT INTO staff (name, username, password_hash, office_id)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, username, office_id AS "officeId", created_at AS "createdAt"`,
      [name, username, passwordHash, officeIdInt]
    );

    res.status(201).json(rows[0]);
  } catch (e) {
    console.error('❌ createStaff:', e);
    res.status(500).json({ error: 'Failed to create staff' });
  }
};

// ── Update a staff member ─────────────────────────────────────────────────────
exports.updateStaff = async (req, res) => {
  try {
    const { id } = req.params;
    const { name, username, password, officeId } = req.body;

    // Parse staff ID as integer
    const staffId = parseInt(id, 10);
    if (isNaN(staffId) || staffId <= 0) {
      return res.status(400).json({ error: 'Invalid staff ID' });
    }

    // Check username uniqueness (excluding self)
    if (username) {
      const { rows: existing } = await pool.query(
        `SELECT id FROM staff WHERE username = $1 AND id != $2`,
        [username, staffId]
      );
      if (existing.length > 0) return res.status(400).json({ error: 'Username already taken' });
    }

    // Validate and use officeId if provided
    let officeIdInt = null;
    if (officeId) {
      officeIdInt = parseOfficeId(officeId);
      if (!officeIdInt) {
        return res.status(400).json({ error: 'Invalid office ID' });
      }
    }

    let query, params;

    if (password) {
      const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
      query = `
        UPDATE staff
        SET name = $2, username = $3, password_hash = $4, office_id = $5, updated_at = NOW()
        WHERE id = $1
        RETURNING id, name, username, office_id AS "officeId"
      `;
      params = [staffId, name, username, passwordHash, officeIdInt];
    } else {
      query = `
        UPDATE staff
        SET name = $2, username = $3, office_id = $4, updated_at = NOW()
        WHERE id = $1
        RETURNING id, name, username, office_id AS "officeId"
      `;
      params = [staffId, name, username, officeIdInt];
    }

    const { rows } = await pool.query(query, params);
    if (rows.length === 0) return res.status(404).json({ error: 'Staff member not found' });
    res.json(rows[0]);
  } catch (e) {
    console.error('❌ updateStaff:', e);
    res.status(500).json({ error: 'Failed to update staff' });
  }
};

// ── Delete a staff member ─────────────────────────────────────────────────────
exports.deleteStaff = async (req, res) => {
  try {
    const { id } = req.params;
    
    // Parse staff ID as integer
    const staffId = parseInt(id, 10);
    if (isNaN(staffId) || staffId <= 0) {
      return res.status(400).json({ error: 'Invalid staff ID' });
    }
    
    const { rowCount } = await pool.query(
      `DELETE FROM staff WHERE id = $1`,
      [staffId]
    );
    if (rowCount === 0) return res.status(404).json({ error: 'Staff member not found' });
    res.json({ message: 'Staff deleted' });
  } catch (e) {
    console.error('❌ deleteStaff:', e);
    res.status(500).json({ error: 'Failed to delete staff' });
  }
};

// ── Staff login ───────────────────────────────────────────────────────────────
exports.loginStaff = async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'username and password required' });
    }

    const { rows } = await pool.query(
      `SELECT
         s.id, s.name, s.username, s.password_hash AS "passwordHash",
         s.office_id AS "officeId", s.is_active AS "isActive",
         o.name AS "officeName"
       FROM staff s
       LEFT JOIN offices o ON o.id = s.office_id
       WHERE s.username = $1
       LIMIT 1`,
      [username]
    );

    if (rows.length === 0) return res.status(401).json({ error: 'Invalid credentials' });

    const staff = rows[0];
    if (!staff.isActive) return res.status(403).json({ error: 'Account is deactivated' });

    const match = await bcrypt.compare(password, staff.passwordHash);
    if (!match) return res.status(401).json({ error: 'Invalid credentials' });

    // Update last login timestamp
    await pool.query(
      `UPDATE staff SET last_login_at = NOW() WHERE id = $1`,
      [staff.id]
    );

    res.json({
      id:         staff.id,
      name:       staff.name,
      username:   staff.username,
      officeId:   staff.officeId,
      officeName: staff.officeName,
    });
  } catch (e) {
    console.error('❌ loginStaff:', e);
    res.status(500).json({ error: 'Login failed' });
  }
};