import { createPool } from './db.js';
import { createAPI } from './api.js';

const pool = createPool();
const server = await createAPI(pool);
server.on('databaseDisconnected', () => {
  console.error('Database event connection lost; restarting API');
  process.exit(1);
});
server.listen(Number(process.env.PORT || 3100), process.env.HOST || '127.0.0.1', () => console.log('Torly API ready'));
for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => {
  server.closeAllConnections();
  server.close(async () => { await pool.end(); process.exit(0); });
  setTimeout(() => process.exit(1), 10000).unref();
});
