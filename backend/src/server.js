const express = require('express');
const cors = require('cors');
const { migrate } = require('./db');
const { seed } = require('./seed');
const { initFcm } = require('./util');

const app = express();
app.set('trust proxy', 1);
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.get('/health', (req, res) => res.json({ ok: true }));
app.use('/api/auth', require('./routes/auth').router);
app.use('/api', require('./routes/common'));
app.use('/api/jobs', require('./routes/jobs').router);
app.use('/api/payments', require('./routes/payments'));
app.use('/api/fundi', require('./routes/fundi').router);
app.use('/api/admin', require('./routes/admin'));
app.use((err, req, res, next) => {
  if (err && err.type === 'entity.parse.failed') return res.status(400).json({ error: 'bad_request' });
  console.error(err);
  res.status(500).json({ error: 'server' });
});

const port = process.env.PORT || 8080;
(async () => {
  await migrate();
  await seed();
  initFcm();
  app.listen(port, () => console.log('SmartFundi API on :' + port));
})().catch((e) => { console.error('Startup failed', e); process.exit(1); });
