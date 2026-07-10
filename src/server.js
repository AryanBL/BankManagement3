const app = require('./app');
const env = require('./config/env');
const { closePools } = require('./config/db');

const server = app.listen(env.port, () => {
  console.log(`BankManagement backend listening on http://localhost:${env.port}`);
});

async function shutdown(signal) {
  console.log(`\n${signal} received. Closing server and database pools...`);
  server.close(async () => {
    try {
      await closePools();
      process.exit(0);
    } catch (error) {
      console.error('Error during shutdown:', error);
      process.exit(1);
    }
  });
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
