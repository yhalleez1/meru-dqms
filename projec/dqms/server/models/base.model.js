// models/base.model.js
'use strict';

const { pool } = require('../config/db');

// Helper function to parse office ID to integer (serial ID)
function parseOfficeId(officeId) {
    if (!officeId) return null;
    if (typeof officeId === 'number') return officeId;
    const parsed = parseInt(officeId, 10);
    if (!isNaN(parsed) && parsed > 0) return parsed;
    return null;
}

// Helper for database queries
async function query(text, params) {
    try {
        const result = await pool.query(text, params);
        return result;
    } catch (error) {
        console.error('Database query error:', error);
        throw error;
    }
}

module.exports = {
    pool,
    parseOfficeId,
    query
};