// server.js
'use strict';

require('dotenv').config();   // we load .env before anything else

const { server } = require('./app');
const { testConnection } = require('./config/db');

const PORT = process.env.PORT || 3000;

(async () => {
  try {
    // Verify PostgreSQL is reachable before accepting requests
    await testConnection();
    console.log('✅ PostgreSQL connected successfully');

    server.listen(PORT, () => {
      console.log(`\n🚀 Server running  →  http://localhost:${PORT}`);
      console.log(`📡 WebSocket ready →  ws://localhost:${PORT}/ws`);
      console.log(`\n� Main Endpoints:`);
      console.log(`   POST   /api/register                - Register new ticket (DQMS + Office)`);
      console.log(`   GET    /api/current                 - Get current serving ticket`);
      console.log(`   POST   /api/next                    - Call next ticket`);
      console.log(`   GET    /api/waiting                 - Get waiting tickets`);
      console.log(`\n📱 DQMS Status:`);
      console.log(`   GET    /api/status/:dqmsNumber      - Get DQMS status`);
      console.log(`   GET    /api/current-ticket          - Get ticket by phone`);
      console.log(`   GET    /api/pending-notifications   - Get pending SMS notifications`);
      console.log(`\n👨‍🎓 Student Management:`);
      console.log(`   GET    /api/students                - Get all students`);
      console.log(`   POST   /api/students                - Add new student`);
      console.log(`   GET    /api/students/by-dqms/:dqms  - Get student by DQMS`);
      console.log(`\n📊 Analytics:`);
      console.log(`   GET    /api/analytics/weekly        - Weekly statistics`);
      console.log(`   GET    /api/analytics/by-office     - Office statistics`);
      console.log(`\n`);
    });
  } catch (err) {
    console.error('❌ Failed to connect to PostgreSQL. Server not started.');
    console.error(err.message);
    process.exit(1);
  }
})();