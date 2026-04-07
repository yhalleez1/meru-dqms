// services/smsService.js
'use strict';

require('dotenv').config();
const https = require('https');

const SMS_API_URL = process.env.SMS_API_URL;
const SMS_API_KEY = process.env.SMS_API_KEY;
const SMS_SENDER_NAME = process.env.SMS_SENDER_NAME;

/**
 * Send SMS notification
 * @param {string} phoneNumber - Phone number in format +254XXXXXXXXX
 * @param {string} message - Message to send
 * @returns {Promise<Object>} Response from SMS API
 */
async function sendSMS(phoneNumber, message) {
    if (!SMS_API_KEY || !SMS_API_URL) {
        console.warn('⚠️ SMS API credentials not configured in .env');
        return { success: false, error: 'SMS API not configured' };
    }

    return new Promise((resolve) => {
        try {
            const payload = {
                mobile: phoneNumber,
                response_type: 'json',
                sender_name: SMS_SENDER_NAME || 'DQMS',
                service_id: 0,
                message: message
            };

            const payloadString = JSON.stringify(payload);

            const urlObj = new URL(SMS_API_URL);
            const options = {
                hostname: urlObj.hostname,
                path: urlObj.pathname,
                method: 'POST',
                headers: {
                    'h_api_key': SMS_API_KEY,
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(payloadString)
                }
            };

            console.log(`📱 Sending SMS to ${phoneNumber}...`);

            const req = https.request(options, (res) => {
                let data = '';

                res.on('data', (chunk) => {
                    data += chunk;
                });

                res.on('end', () => {
                    if (res.statusCode === 200) {
                        console.log(`✅ SMS sent successfully to ${phoneNumber}`);
                        resolve({
                            success: true,
                            phoneNumber: phoneNumber,
                            statusCode: res.statusCode,
                            response: data
                        });
                    } else {
                        console.warn(`⚠️ SMS API returned status ${res.statusCode}`);
                        resolve({
                            success: false,
                            error: `SMS API returned status ${res.statusCode}`,
                            response: data
                        });
                    }
                });
            });

            req.on('error', (error) => {
                console.error(`❌ Failed to send SMS to ${phoneNumber}:`, error.message);
                resolve({
                    success: false,
                    phoneNumber: phoneNumber,
                    error: error.message
                });
            });

            req.write(payloadString);
            req.end();
        } catch (error) {
            console.error(`❌ SMS service error:`, error.message);
            resolve({
                success: false,
                error: error.message
            });
        }
    });
}

/**
 * Send ticket notification SMS
 * @param {string} phoneNumber - Phone number
 * @param {number} ticketNumber - Ticket number (will be zero-padded to 3 digits)
 * @param {string} studentName - Student name
 * @param {string} officeName - Office name
 * @param {number} expectedWaitingMinutes - Expected waiting time in minutes (optional)
 * @returns {Promise<Object>} Response from SMS service
 */
async function sendTicketNotification(phoneNumber, ticketNumber, studentName, officeName, expectedWaitingMinutes = null) {
    // Format ticket number with leading zeros (e.g., 001, 002, 003)
    const formattedTicket = String(ticketNumber).padStart(3, '0');
    
    let message = `Hi ${studentName}, your ticket #${formattedTicket} is ready at ${officeName}.`;
    
    // Always add expected waiting time (even if 0)
    if (expectedWaitingMinutes !== null) {
        const waitMinutes = Math.round(expectedWaitingMinutes);
        message += ` Expected wait: ~${waitMinutes} min.`;
    }
    
    return sendSMS(phoneNumber, message);
}

module.exports = {
    sendSMS,
    sendTicketNotification
};
