const express = require('express');
const os = require('os');
const { Pool } = require('pg');

// ===== Change this line for the "small modification" test =====
const APP_TITLE = 'Learning Management Platform - v1';
// ===============================================================

const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || 'local';

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME || 'lms_db',
  user: process.env.DB_USER || 'lms_user',
  password: process.env.DB_PASSWORD || '',
  connectionTimeoutMillis: 3000,
});

async function initDb() {
  await pool.query(`CREATE TABLE IF NOT EXISTS courses (
      id SERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      instructor TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW())`);
  const { rows } = await pool.query('SELECT COUNT(*)::int AS n FROM courses');
  if (rows[0].n === 0) {
    await pool.query(`INSERT INTO courses (title, instructor) VALUES
      ('Intro to DevOps', 'A. Sharma'),
      ('Terraform on AWS', 'R. Mehta'),
      ('Ansible Automation', 'S. Iyer'),
      ('CI/CD with Jenkins', 'P. Nair')`);
  }
}

async function dbStatus() {
  try {
    const r = await pool.query('SELECT version() AS v, NOW() AS t');
    return { connected: true, version: r.rows[0].v, time: r.rows[0].t };
  } catch (e) {
    return { connected: false, error: e.message };
  }
}

const app = express();
app.use(express.urlencoded({ extended: false }));

app.get('/health', async (_req, res) => {
  const db = await dbStatus();
  res.status(db.connected ? 200 : 500).json({
    status: db.connected ? 'UP' : 'DEGRADED',
    db: db.connected ? 'connected' : 'disconnected',
    host: os.hostname(),
    version: APP_VERSION,
    dbHost: process.env.DB_HOST,
    error: db.error,
  });
});

app.get('/api/courses', async (_req, res) => {
  try {
    const { rows } = await pool.query('SELECT * FROM courses ORDER BY id');
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/courses', async (req, res) => {
  const { title, instructor } = req.body;
  if (title && instructor) {
    await pool.query('INSERT INTO courses (title, instructor) VALUES ($1,$2)', [title, instructor]);
  }
  res.redirect('/');
});

app.get('/', async (_req, res) => {
  const db = await dbStatus();
  let courses = [];
  if (db.connected) {
    try { courses = (await pool.query('SELECT * FROM courses ORDER BY id')).rows; } catch (_) {}
  }
  const rowsHtml = courses
    .map((c) => `<tr><td>${c.id}</td><td>${escapeHtml(c.title)}</td><td>${escapeHtml(c.instructor)}</td></tr>`)
    .join('');
  res.send(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>${APP_TITLE}</title>
<style>
 body{font-family:Arial,sans-serif;background:#f4f6fb;margin:0}
 header{background:#1e3a8a;color:#fff;padding:20px 32px}
 main{padding:24px 32px;max-width:900px}
 .card{background:#fff;border-radius:8px;padding:16px 20px;margin-bottom:16px;box-shadow:0 1px 3px rgba(0,0,0,.1)}
 .ok{color:#15803d;font-weight:bold}.bad{color:#b91c1c;font-weight:bold}
 table{width:100%;border-collapse:collapse}td,th{padding:8px;border-bottom:1px solid #e5e7eb;text-align:left}
 input{padding:6px;margin-right:6px}button{padding:6px 14px}
</style></head><body>
<header><h1>${APP_TITLE}</h1></header>
<main>
 <div class="card">
  <p><b>Served by host (container):</b> ${os.hostname()}</p>
  <p><b>App version / build:</b> ${APP_VERSION}</p>
  <p><b>Database (${process.env.DB_HOST}):</b>
   ${db.connected ? '<span class="ok">CONNECTED</span>' : '<span class="bad">NOT CONNECTED</span> - ' + escapeHtml(db.error || '')}</p>
   ${db.connected ? `<p style="font-size:12px;color:#555">${escapeHtml(db.version)}</p>` : ''}
 </div>
 <div class="card"><h2>Courses</h2>
  <table><tr><th>ID</th><th>Title</th><th>Instructor</th></tr>${rowsHtml}</table>
 </div>
 <div class="card"><h3>Add a course</h3>
  <form method="post" action="/courses">
   <input name="title" placeholder="Course title" required>
   <input name="instructor" placeholder="Instructor" required>
   <button type="submit">Add</button>
  </form>
 </div>
</main></body></html>`);
});

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
}

app.listen(PORT, '0.0.0.0', async () => {
  console.log(`${APP_TITLE} listening on ${PORT}`);
  try { await initDb(); console.log('Database initialised'); }
  catch (e) { console.error('DB init failed:', e.message); }
});
