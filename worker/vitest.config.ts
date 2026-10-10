import path from 'node:path';
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-plugin';
import { defineConfig } from 'vitest/config';

export default defineConfig(async () => {
  const migrations = await readD1Migrations(path.join(import.meta.dirname, 'migrations'));
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: './wrangler.toml' },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            APP_ENV: 'test',
            FIREBASE_PROJECT_ID: 'test-project',
            ALLOWED_ORIGINS: 'https://app.example.test,http://localhost:8080',
            MEDIA_SIGNING_KEY: 'clave-de-prueba-solo-para-tests',
          },
        },
      }),
    ],
    test: { setupFiles: ['./test/apply-migrations.ts'] },
  };
});
