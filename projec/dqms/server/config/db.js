'use strict';

require('dotenv').config();

const { Pool, Client } = require('pg');

if (!process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL is not set in .env');
}

// ── SINGLETON POOL — created once, reused everywhere ─────────────────────────
if (!global._dbPool) {
  global._dbPool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
  });

  global._dbPool.on('error', (err) => {
    console.error('❌ Pool error:', err.message);
  });

  console.log('🗄️  Database pool created (singleton)');
} else {
  console.log('🗄️  Reusing existing database pool');
}

const pool = global._dbPool;

// ── SINGLETON LISTEN CLIENT — created once, never recycled ───────────────────
async function getListenClient() {
  if (global._listenClient) return global._listenClient;

  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });

  client.on('error', (err) => {
    console.error('❌ LISTEN client error — reconnecting in 5s:', err.message);
    global._listenClient = null;
    setTimeout(getListenClient, 5000);
  });

  client.on('end', () => {
    console.warn('⚠️  LISTEN client ended — reconnecting in 5s');
    global._listenClient = null;
    setTimeout(getListenClient, 5000);
  });

  await client.connect();
  await client.query('LISTEN queue_updates');
  await client.query('LISTEN current_serving_updates');
  await client.query('LISTEN office_updates');

  global._listenClient = client;
  console.log('📡 LISTEN client connected (singleton)');
  return global._listenClient;
}

// ── Health check ──────────────────────────────────────────────────────────────
async function testConnection() {
  const client = await pool.connect();
  try {
    const { rows } = await client.query(
      'SELECT current_database() AS db, NOW() AS ts'
    );
    console.log(`✅ PostgreSQL connected → "${rows[0].db}" at ${rows[0].ts}`);
  } finally {
    client.release();
  }
}

module.exports = { pool, getListenClient, testConnection };
