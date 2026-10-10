import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import { stableId } from '../scripts/transform/ids';
import { storagePathFromUrl } from '../scripts/transform/media';
import { cleanUsername, slugify } from '../scripts/transform/fields';
import { lit } from '../scripts/transform/sql';
import { seedCatalog, transform, type PlanReport } from '../scripts/transform/run';
import { writeFixtureSnapshot } from './support/fixture';
import { applyFiles, count, freshDb, WORKER_MIGRATIONS } from './support/sqlite';

let out: string;
let files: string[];
let report: PlanReport;

beforeAll(() => {
  const snapshot = writeFixtureSnapshot();
  out = mkdtempSync(join(tmpdir(), 'nv-plan-'));
  files = transform(snapshot, out, WORKER_MIGRATIONS).files;
  report = JSON.parse(readFileSync(join(out, 'report.json'), 'utf8')) as PlanReport;
});

describe('utilidades', () => {
  it('IDs deterministas con formato UUID', () => {
    expect(stableId('posts/p1')).toBe(stableId('posts/p1'));
    expect(stableId('posts/p1')).not.toBe(stableId('posts/p2'));
    expect(stableId('posts/p1')).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it('escapa texto para SQL', () => {
    expect(lit("O'Higgins")).toBe("'O''Higgins'");
    expect(lit(null)).toBe('NULL');
    expect(lit(Number.NaN)).toBe('NULL');
    expect(lit('a\u0000b')).toBe("'ab'");
    expect(lit('🐸 ok')).toBe("'🐸 ok'");
    expect(lit('a\uD800b')).toBe("'ab'"); // sustituto suelto
  });

  it('reconoce rutas de Storage en URLs', () => {
    expect(storagePathFromUrl('https://firebasestorage.googleapis.com/v0/b/x.appspot.com/o/user-files%2Fu1%2Fposts%2Fa.jpg?alt=media&token=t')).toBe('user-files/u1/posts/a.jpg');
    expect(storagePathFromUrl('gs://x.appspot.com/user-files/u1/a.jpg')).toBe('user-files/u1/a.jpg');
    expect(storagePathFromUrl('https://storage.googleapis.com/x.appspot.com/user-files/u1/a.jpg')).toBe('user-files/u1/a.jpg');
    expect(storagePathFromUrl('https://i.imgur.com/x.jpg')).toBeNull();
  });

  it('nombres de usuario y slugs válidos para la API', () => {
    expect(cleanUsername('@Ana.Rojas')).toBe('ana.rojas');
    expect(cleanUsername('a')).toBeNull();
    expect(cleanUsername('ana..rojas')).toBeNull();
    expect(slugify('Amigos del Angachilla ¡Ñandú!')).toBe('amigos-del-angachilla-nandu');
  });

  it('lee el catálogo inicial del Worker', () => {
    const catalog = seedCatalog(WORKER_MIGRATIONS);
    expect(catalog.length).toBe(17);
    expect(catalog.find((s) => s.scientificName === 'Lontra provocax')).toMatchObject({ commonNameEs: 'Huillín', sensitive: true });
  });
});

describe('plan sobre una instantánea de prueba', () => {
  it('el SQL se aplica sobre el esquema real con claves foráneas y CHECK activos', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    expect(db.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
    expect(count(db, 'SELECT count(*) n FROM users')).toBe(3);
    expect(count(db, "SELECT count(*) n FROM users WHERE status = 'suspended'")).toBe(1);
  });

  it('es idempotente: aplicarlo dos veces no duplica nada', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    const before = ['users', 'posts', 'observations', 'notebook_pages', 'notebook_elements', 'messages', 'follows', 'community_members'].map((t) =>
      count(db, `SELECT count(*) n FROM ${t}`),
    );
    applyFiles(db, join(out, 'sql'), files);
    const after = ['users', 'posts', 'observations', 'notebook_pages', 'notebook_elements', 'messages', 'follows', 'community_members'].map((t) =>
      count(db, `SELECT count(*) n FROM ${t}`),
    );
    expect(after).toEqual(before);
  });

  it('perfiles: sin datos personales, nombre de usuario repetido queda vacío', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    const ana = db.prepare("SELECT * FROM profiles WHERE user_id = 'uidAna'").get() as Record<string, unknown>;
    expect(ana).toMatchObject({ full_name: 'Ana Rojas', username: 'ana.rojas', bio: 'Observadora de aves', location: 'Valdivia', visibility: 'public' });
    const beto = db.prepare("SELECT * FROM profiles WHERE user_id = 'uidBeto'").get() as Record<string, unknown>;
    expect(beto).toMatchObject({ username: null, visibility: 'private' });
    const all = readFileSync(join(out, 'sql', files.find((f) => f.startsWith('040'))!), 'utf8');
    expect(all).not.toContain('11.111.111-1');
    expect(all).not.toContain('+56 9');
    expect(report.collections['profiles']!.excludedPersonalFields).toMatchObject({ rut: 1, telefono: 1, fechaNacimiento: 1 });
    expect(report.collections['profiles']!.unmappedFields).toMatchObject({ campoRaro: 1 });
    // Sin fotos copiadas todavía, la referencia queda vacía (no rompe la clave foránea).
    expect(ana['photo_asset_id']).toBeNull();
  });

  it('ajustes: idioma y tema; el 2FA simulado no se conserva', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    const s = db.prepare("SELECT * FROM user_settings WHERE user_id = 'uidAna'").get() as Record<string, string>;
    expect(s).toMatchObject({ language: 'en', theme: 'dark' });
    expect(JSON.parse(s['extra_json']!)).toEqual({ map: { layer: 'sat' } });
  });

  it('observaciones: especie del catálogo, ubicación protegida, nombre libre, privadas; sin dueño o sin coordenadas se omiten', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    const rows = db.prepare('SELECT * FROM observations ORDER BY legacy_id').all() as Record<string, unknown>[];
    expect(rows.map((r) => r['legacy_id'])).toEqual(['o1', 'o2']);
    expect(rows[0]).toMatchObject({ species_id: 'sp-lontra-provocax', obscured: 1, latitude: -39.8612 });
    expect(rows[0]!['public_latitude']).not.toBe(-39.8612);
    expect(rows[1]).toMatchObject({ species_id: null, taxon_name: 'Martín pescador', individual_count: 2, visibility: 'private', obscured: 0 });
    expect(report.collections['observations']!.skipped).toMatchObject({ 'sin coordenadas válidas': 1, 'sin dueño verificable (anon) — decisión D3': 1 });
  });

  it('el catálogo antiguo completa el inicial sin duplicar especies', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    expect(count(db, "SELECT count(*) n FROM species WHERE scientific_name = 'Lontra provocax'")).toBe(1);
    expect(db.prepare("SELECT legacy_id FROM species WHERE scientific_name = 'Lontra provocax'").get()).toEqual({ legacy_id: 'sc1' });
    expect(db.prepare("SELECT taxon_group, conservation_status, sensitive FROM species WHERE legacy_id = 'sc2'").get()).toEqual({
      taxon_group: 'aves', conservation_status: 'LC', sensitive: 0,
    });
  });

  it('cuadernos y páginas en orden, con texto y dibujo; huérfanos fuera', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    expect(db.prepare('SELECT title, visibility, color, page_count FROM notebooks').all()).toEqual([
      { title: 'Salidas 2025', visibility: 'public', color: '#2F6F7E', page_count: 2 },
    ]);
    const pages = db.prepare('SELECT legacy_id, position, latitude, location_source FROM notebook_pages ORDER BY position').all();
    expect(pages).toEqual([
      { legacy_id: 'pg-a', position: 0, latitude: -39.86, location_source: 'gps' },
      { legacy_id: 'pg-b', position: 1, latitude: null, location_source: null },
    ]);
    const texts = db.prepare("SELECT data_json FROM notebook_elements WHERE type = 'text'").all() as { data_json: string }[];
    expect(texts.map((t) => JSON.parse(t.data_json).text).sort()).toEqual(['Canto de chucao', 'Segunda página']);
    expect(count(db, "SELECT count(*) n FROM notebook_elements WHERE type = 'photo'")).toBe(1); // dibujo incrustado
    expect(report.collections['notebook_pages']!.skipped).toMatchObject({ 'cuaderno no migrado': 1 });
  });

  it('publicaciones, comunidades, seguidores y mensajes', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    expect(db.prepare("SELECT body FROM posts WHERE legacy_id = 'p1'").get()).toEqual({ body: "Garza en el humedal, ¡qué día! It's 'great'" });
    expect(db.prepare("SELECT body FROM posts WHERE legacy_id = 'p2'").get()).toEqual({ body: '📷' });
    expect(count(db, 'SELECT count(*) n FROM posts')).toBe(3); // p3 (anon) fuera; p4 sin foto externa
    expect(db.prepare('SELECT slug FROM communities ORDER BY slug').all()).toEqual([{ slug: 'amigos-del-angachilla' }, { slug: 'amigos-del-angachilla-2' }]);
    expect(db.prepare("SELECT c.member_count FROM communities c WHERE legacy_id = 'g1'").get()).toEqual({ member_count: 2 });
    expect(db.prepare("SELECT role FROM community_members WHERE user_id = 'uidBeto' AND community_id = (SELECT id FROM communities WHERE legacy_id = 'g1')").get()).toEqual({ role: 'moderator' });
    expect(count(db, 'SELECT count(*) n FROM follows')).toBe(1);
    expect(count(db, 'SELECT count(*) n FROM conversations')).toBe(1);
    expect(db.prepare('SELECT body, read_at IS NOT NULL AS r FROM messages ORDER BY created_at').all()).toEqual([
      { body: 'Hola Beto', r: 1 },
      { body: 'Hola Ana', r: 0 },
    ]);
  });

  it('lugares y humedales con su contorno', () => {
    const db = freshDb();
    applyFiles(db, join(out, 'sql'), files);
    const rows = db.prepare('SELECT kind, name, geojson IS NOT NULL AS g FROM places ORDER BY name').all();
    expect(rows).toEqual([
      { kind: 'wetland', name: 'Humedal Angachilla', g: 1 },
      { kind: 'viewpoint', name: 'Mirador del río', g: 0 },
    ]);
  });

  it('manifiesto de archivos: Storage, incrustados, visibilidad y URLs externas', () => {
    const manifest = readFileSync(join(out, 'media-manifest.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
    const byPath = (p: string) => manifest.find((m) => m.legacyStoragePath === p);
    expect(byPath('user-files/uidAna/avatar/a.jpg')).toMatchObject({ purpose: 'profile-photo', visibility: 'public', ownerId: 'uidAna' });
    expect(byPath('user-files/uidAna/observations/extra.jpg')).toMatchObject({ purpose: 'observation-photo', visibility: 'private', legacyAssetId: 'fa1' });
    expect(byPath('user-files/uidAna/notebooks/c.jpg')).toMatchObject({ visibility: 'public' }); // cuaderno público
    const inline = manifest.filter((m) => m.source.kind === 'inline');
    expect(inline).toHaveLength(2); // foto del post p2 y dibujo de la página
    for (const m of inline) expect(existsSync(join(out, 'inline', m.source.file))).toBe(true);
    expect(report.media.externalHosts).toEqual({ 'i.imgur.com': 1 });
  });

  it('informe: colecciones no migradas y no previstas', () => {
    expect(report.collections['reports']!.skipped).toEqual({ 'mensajes de contacto con correos personales; se revisan a mano, no se migran': 1 });
    expect(Object.keys(report.collections['coleccion_nueva']!.skipped)[0]).toMatch(/no prevista/);
    const md = readFileSync(join(out, 'report.md'), 'utf8');
    expect(md).toContain('Datos personales NO migrados');
    expect(md).not.toContain('ana@example.test');
  });
});
