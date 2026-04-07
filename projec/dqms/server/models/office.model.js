// models/office.model.js
'use strict';

const { pool, parseOfficeId } = require('./base.model');

async function getAllOffices() {
    const { rows } = await pool.query(`
        SELECT o.id, o.name, o.status, o.created_at as "createdAt", o.updated_at as "updatedAt",
               COUNT(DISTINCT s.id) as "staffCount"
        FROM offices o
        LEFT JOIN staff s ON s.office_id = o.id AND s.is_active = true
        GROUP BY o.id
        ORDER BY o.id
    `);
    return rows;
}

async function getOfficeById(officeId) {
    const officeIdInt = parseOfficeId(officeId);
    const { rows } = await pool.query(`
        SELECT o.id, o.name, o.status, o.created_at as "createdAt", o.updated_at as "updatedAt",
               COUNT(DISTINCT s.id) as "staffCount"
        FROM offices o
        LEFT JOIN staff s ON s.office_id = o.id AND s.is_active = true
        WHERE o.id = $1
        GROUP BY o.id
    `, [officeIdInt]);
    return rows[0] || null;
}

async function createOffice(name, status = 'active') {
    const { rows } = await pool.query(
        `INSERT INTO offices (name, status)
         VALUES ($1, $2)
         RETURNING id, name, status, created_at as "createdAt", updated_at as "updatedAt"`,
        [name, status]
    );
    return rows[0];
}

async function updateOffice(officeId, updates) {
    const officeIdInt = parseOfficeId(officeId);
    const fields = [];
    const values = [];
    let idx = 1;
    
    if (updates.name !== undefined) {
        fields.push(`name = $${idx++}`);
        values.push(updates.name);
    }
    if (updates.status !== undefined) {
        fields.push(`status = $${idx++}`);
        values.push(updates.status);
    }
    
    if (fields.length === 0) return null;
    
    values.push(officeIdInt);
    
    const { rows } = await pool.query(
        `UPDATE offices SET ${fields.join(', ')}, updated_at = CURRENT_TIMESTAMP
         WHERE id = $${idx}
         RETURNING id, name, status, created_at as "createdAt", updated_at as "updatedAt"`,
        values
    );
    return rows[0] || null;
}

async function deleteOffice(officeId) {
    const officeIdInt = parseOfficeId(officeId);
    const { rowCount } = await pool.query(`DELETE FROM offices WHERE id = $1`, [officeIdInt]);
    return rowCount > 0;
}

module.exports = {
    getAllOffices,
    getOfficeById,
    createOffice,
    updateOffice,
    deleteOffice
};