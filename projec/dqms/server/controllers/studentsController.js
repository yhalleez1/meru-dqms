// controllers/studentsController.js
'use strict';

const models = require('../models');

exports.getAllStudents = async (req, res) => {
    try {
        const students = await models.getAllStudents();
        res.json({
            success: true,
            count: students.length,
            data: students
        });
    } catch (error) {
        console.error('❌ getAllStudents error:', error);
        res.status(500).json({ 
            error: 'Failed to get students',
            details: error.message 
        });
    }
};

exports.getStudentById = async (req, res) => {
    try {
        const { id } = req.params;
        const student = await models.getStudentById(id);
        
        if (!student) {
            return res.status(404).json({ error: 'Student not found' });
        }
        
        res.json({
            success: true,
            data: student
        });
    } catch (error) {
        console.error('❌ getStudentById error:', error);
        res.status(500).json({ 
            error: 'Failed to get student',
            details: error.message 
        });
    }
};

exports.getStudentByDQMS = async (req, res) => {
    try {
        const { dqmsNumber } = req.params;
        const student = await models.getStudentByDQMSNumber(dqmsNumber);
        
        if (!student) {
            return res.status(404).json({ error: 'Student not found' });
        }
        
        res.json({
            success: true,
            data: student
        });
    } catch (error) {
        console.error('❌ getStudentByDQMS error:', error);
        res.status(500).json({ 
            error: 'Failed to get student',
            details: error.message 
        });
    }
};

exports.getStudentByPhone = async (req, res) => {
    try {
        const { phone } = req.params;
        const student = await models.getStudentByPhone(phone);
        
        if (!student) {
            return res.status(404).json({ error: 'Student not found' });
        }
        
        res.json({
            success: true,
            data: student
        });
    } catch (error) {
        console.error('❌ getStudentByPhone error:', error);
        res.status(500).json({ 
            error: 'Failed to get student',
            details: error.message 
        });
    }
};

exports.createStudent = async (req, res) => {
    try {
        const { dqmsNumber, phoneNumber, studentName, studentId } = req.body;
        
        if (!dqmsNumber || !phoneNumber) {
            return res.status(400).json({ 
                error: 'dqmsNumber and phoneNumber are required' 
            });
        }
        
        const student = await models.createStudent(
            dqmsNumber,
            phoneNumber,
            studentName || null,
            studentId || null
        );
        
        res.status(201).json({
            success: true,
            message: 'Student created successfully',
            data: student
        });
    } catch (error) {
        console.error('❌ createStudent error:', error);
        res.status(500).json({ 
            error: 'Failed to create student',
            details: error.message 
        });
    }
};

exports.updateStudent = async (req, res) => {
    try {
        const { id } = req.params;
        const { phoneNumber, studentName, registrationNumber, isActive } = req.body;
        
        const student = await models.updateStudent(id, {
            phone_number: phoneNumber,
            student_name: studentName,
            student_id: registrationNumber,
            is_active: isActive
        });
        
        if (!student) {
            return res.status(404).json({ error: 'Student not found' });
        }
        
        res.json({
            success: true,
            message: 'Student updated successfully',
            data: student
        });
    } catch (error) {
        console.error('❌ updateStudent error:', error);
        res.status(500).json({ 
            error: 'Failed to update student',
            details: error.message 
        });
    }
};

exports.deleteStudent = async (req, res) => {
    try {
        const { id } = req.params;
        const deleted = await models.deleteStudent(id);
        
        if (!deleted) {
            return res.status(404).json({ error: 'Student not found' });
        }
        
        res.json({
            success: true,
            message: 'Student deleted successfully'
        });
    } catch (error) {
        console.error('❌ deleteStudent error:', error);
        res.status(500).json({ 
            error: 'Failed to delete student',
            details: error.message 
        });
    }
};

exports.getNextDQMSNumber = async (req, res) => {
    try {
        const { prefix } = req.query;
        if (!prefix) return res.status(400).json({ success: false, message: 'prefix is required' });

        const { pool } = require('../models/base.model');
        // Find the highest numeric part among dqms_numbers starting with this prefix
        const { rows } = await pool.query(
            `SELECT dqms_number FROM students WHERE dqms_number ILIKE $1 ORDER BY dqms_number DESC`,
            [`${prefix}%`]
        );

        let nextNum = 1;
        if (rows.length > 0) {
            const nums = rows
                .map(r => parseInt(r.dqms_number.replace(new RegExp(`^${prefix}`, 'i'), ''), 10))
                .filter(n => !isNaN(n));
            if (nums.length > 0) nextNum = Math.max(...nums) + 1;
        }

        res.json({ success: true, next: `${prefix.toUpperCase()}${String(nextNum).padStart(3, '0')}` });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.lookupStudent = async (req, res) => {
    try {
        const { registrationNumber, phoneNumber } = req.body;

        if (!registrationNumber || !phoneNumber) {
            return res.status(400).json({ success: false, message: 'registrationNumber and phoneNumber are required' });
        }

        const student = await models.getStudentByPhone(phoneNumber.trim());

        if (!student || student.registration_number !== registrationNumber.trim()) {
            return res.status(404).json({ success: false, message: 'No matching student found. Please check your registration number and phone number.' });
        }

        res.json({
            success: true,
            data: {
                name: student.student_name,
                registrationNumber: student.registration_number,
                phoneNumber: student.phone_number,
                dqmsNumber: student.dqms_number
            }
        });
    } catch (error) {
        console.error('❌ lookupStudent error:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};
