import { applyD1Migrations, env } from 'cloudflare:test';

// Cada archivo de prueba parte de una base D1 aislada con el esquema real.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
