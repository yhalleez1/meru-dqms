// models/student.model.js
'use strict';

const { pool } = require('./base.model');

async function createStudent(dqmsNumber, phoneNumber, studentName = null, studentId = null) {
    const { rows } = await pool.query(
        `INSERT INTO students (dqms_number, phone_number, student_name, registration_number)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (dqms_number) DO UPDATE
         SET phone_number = EXCLUDED.phone_number,
             student_name = COALESCE(EXCLUDED.student_name, students.student_name),
             registration_number = COALESCE(EXCLUDED.registration_number, students.registration_number),
             updated_at = CURRENT_TIMESTAMP
         RETURNING *`,
        [dqmsNumber, phoneNumber, studentName, studentId]
    );
    console.log(`👨‍🎓 Student ${dqmsNumber} (${phoneNumber}) created/updated`);
    return rows[0];
}

async function getAllStudents() {
    const { rows } = await pool.query(`SELECT * FROM students ORDER BY dqms_number`);
    return rows;
}

async function getStudentById(studentId) {
    const { rows } = await pool.query(`SELECT * FROM students WHERE id = $1`, [studentId]);
    return rows[0] || null;
}

async function getStudentByDQMSNumber(dqmsNumber) {
    const { rows } = await pool.query(`SELECT * FROM students WHERE dqms_number = $1`, [dqmsNumber]);
    return rows[0] || null;
}

async function getStudentByPhone(phoneNumber) {
    const { rows } = await pool.query(`SELECT * FROM students WHERE phone_number = $1`, [phoneNumber]);
    return rows[0] || null;
}

async function updateStudent(studentId, updates) {
    const fields = [];
    const values = [];
    let idx = 1;
    
    if (updates.phone_number !== undefined) {
        fields.push(`phone_number = $${idx++}`);
        values.push(updates.phone_number);
    }
    if (updates.student_name !== undefined) {
        fields.push(`student_name = $${idx++}`);
        values.push(updates.student_name);
    }
    if (updates.student_id !== undefined) {
        fields.push(`registration_number = $${idx++}`);
        values.push(updates.student_id);
    }
    if (updates.is_active !== undefined) {
        fields.push(`is_active = $${idx++}`);
        values.push(updates.is_active);
    }
    
    if (fields.length === 0) return null;
    
    values.push(studentId);
    
    const { rows } = await pool.query(
        `UPDATE students SET ${fields.join(', ')}, updated_at = CURRENT_TIMESTAMP
         WHERE id = $${idx} RETURNING *`,
        values
    );
    return rows[0] || null;
}

async function deleteStudent(studentId) {
    const { rowCount } = await pool.query(`DELETE FROM students WHERE id = $1`, [studentId]);
    return rowCount > 0;
}

module.exports = {
    createStudent,
    getAllStudents,
    getStudentById,
    getStudentByDQMSNumber,
    getStudentByPhone,
    updateStudent,
    deleteStudent
};
