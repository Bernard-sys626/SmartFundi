const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
const url = process.env.DATABASE_URL || 'postgresql://sf:sf@127.0.0.1:5432/smartfundi';
const pool = new Pool({
  connectionString: url,
  ssl: /neon\.tech|sslmode=require/.test(url) ? { rejectUnauthorized: false } : undefined,
  max: 10,
});
const q = (text, params) => pool.query(text, params).then((r) => r.rows);
const q1 = (text, params) => q(text, params).then((r) => r[0]);
async function migrate() {
  await pool.query(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
}
module.exports = { pool, q, q1, migrate };
