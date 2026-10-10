import { cellCenter } from '../../../worker/src/services/geoprivacy';
import { PLACEHOLDER_UIDS } from '../lib/legacy-inventory';
import { cleanUsername, FieldReader, isHexColor, slugify, truncate, type Doc } from './fields';
import { stableId } from './ids';
import type { Plan } from './plan';
import { insert, lit, mediaRef } from './sql';

export interface SnapshotDoc {
  id: string;
  path?: string;
  parent?: string;
  data: Doc;
}

export interface AuthUser {
  uid: string;
  email: string | null;
  emailVerified: boolean;
  displayName: string | null;
  providers: string[];
  disabled: boolean;
  createdAt: string | null;
}

export interface CatalogSpecies {
  id: string;
  scientificName: string;
  commonNameEs: string | null;
  sensitive: boolean;
}

/** Datos personales del sistema antiguo que NO se migran (decisión D2 pendiente; ver docs/security.md). */
export const PERSONAL_FIELDS = new Set([
  'rut', 'fechaNacimiento', 'birthDate', 'birthday', 'telefono', 'phone', 'phoneNumber', 'whatsapp',
  'genero', 'gender', 'addressValdivia', 'address', 'direccion', 'email', 'userEmail',
  'birthdate', 'birthdatePublic', 'age', 'ageVerified', 'rutVerified', 'edad',
]);

const assetKey = (p: string) =>
  (p.split('?')[0]!.split('/').pop() ?? '').replace(/\.[a-z0-9]+$/i, '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

/** Contexto compartido entre colecciones. */
export class Context {
  readonly users = new Set<string>();
  readonly notebookOwner = new Map<string, { id: string; owner: string; isPublic: boolean }>();
  readonly communityByLegacy = new Map<string, { id: string; createdBy: string }>();
  readonly postByLegacy = new Map<string, string>();
  readonly slugs = new Set<string>();
  readonly speciesByName = new Map<string, CatalogSpecies>();
  readonly migratedAt = new Date().toISOString();
  /** Ilustraciones y pegatinas de la app nueva por nombre de archivo (sin extensión), para enlazar rutas antiguas. */
  readonly assetsByName = new Map<string, string>();

  constructor(readonly plan: Plan, catalog: CatalogSpecies[], assets: string[] = []) {
    for (const s of catalog) this.addSpecies(s);
    for (const a of assets) this.assetsByName.set(assetKey(a), a);
  }

  /** Ruta antigua tipo `/illustrations/aves/chucao.jpg` → asset de la app nueva, si existe uno con ese nombre. */
  assetFor(path: string): string | null {
    return this.assetsByName.get(assetKey(path)) ?? null;
  }

  addSpecies(s: CatalogSpecies) {
    this.speciesByName.set(s.scientificName.toLowerCase(), s);
    if (s.commonNameEs) this.speciesByName.set(s.commonNameEs.toLowerCase(), s);
  }

  /** UID válido: existe en Auth y no es un marcador como 'anon' o 'guest'. */
  owner(collection: string, uid: string | null, field = 'usuario'): string | null {
    if (!uid || PLACEHOLDER_UIDS.has(uid)) {
      this.plan.skip(collection, `sin dueño verificable (${uid || 'vacío'}) — decisión D3`);
      return null;
    }
    if (!this.users.has(uid)) {
      this.plan.skip(collection, `${field} inexistente en Auth`);
      return null;
    }
    return uid;
  }
}

/** Referencia a un archivo que puede copiarse antes o después del contenido. */
function ref(ctx: Context, table: string, where: Record<string, string>, column: string, assetId: string | null) {
  if (assetId) ctx.plan.relinks.push({ table, where, column, assetId });
  return mediaRef(assetId);
}

function finish(ctx: Context, collection: string, r: FieldReader) {
  for (const f of r.unused()) {
    if (PERSONAL_FIELDS.has(f)) ctx.plan.excluded(collection, f);
    else ctx.plan.shape(collection, f, r.data[f]);
  }
  ctx.plan.unmapped(collection, r.unused().filter((f) => !PERSONAL_FIELDS.has(f)));
}

// ── Usuarios (Firebase Auth) ───────────────────────────────────────────────
export function mapAuthUser(ctx: Context, u: AuthUser) {
  const c = 'auth';
  ctx.plan.collection(c).read++;
  if (!u.uid || u.uid.length > 128) return ctx.plan.skip(c, 'UID inválido');
  ctx.users.add(u.uid);
  ctx.plan.add(
    '010-users',
    c,
    'users',
    insert(
      'users',
      {
      id: u.uid,
      email: u.email,
      email_verified: u.emailVerified,
      display_name: truncate(u.displayName, 120),
      auth_provider: u.providers[0] ?? null,
      status: u.disabled ? 'suspended' : 'active',
      created_at: u.createdAt ?? ctx.migratedAt,
      legacy_source: 'firestore',
      migrated_at: ctx.migratedAt,
      },
      // Quien ya entró a la app nueva conserva sus datos; solo se marca como migrado.
      `(id) DO UPDATE SET legacy_source = 'firestore', migrated_at = COALESCE(users.migrated_at, excluded.migrated_at)`,
    ),
  );
}

// ── settings/{uid} ─────────────────────────────────────────────────────────
export function mapSettings(ctx: Context, d: SnapshotDoc) {
  const c = 'settings';
  ctx.plan.collection(c).read++;
  const uid = ctx.owner(c, d.id);
  if (!uid) return;
  const r = new FieldReader(d.data);
  const langRaw = r.str('language', 'idioma') ?? (r.obj('language')?.['code'] as string | undefined) ?? null;
  const language = langRaw && /^en/i.test(langRaw) ? 'en' : 'es';
  const dark = r.bool('darkMode');
  const themeRaw =
    r.str('theme') ?? (r.obj('appearance')?.['theme'] as string | undefined) ?? (r.obj('accessibility')?.['theme'] as string | undefined) ?? null;
  const theme = themeRaw === 'dark' || dark === true ? 'dark' : themeRaw === 'light' || dark === false ? 'light' : 'system';
  // `twoFactor` era una simulación sin efecto (docs/security.md): no se conserva.
  r.known('twoFactor');
  const extra: Doc = {};
  for (const k of ['appearance', 'accessibility', 'notebook', 'map', 'stickers', 'privacy', 'notifications']) {
    if (d.data[k] !== undefined) {
      extra[k] = d.data[k];
      r.known(k);
    }
  }
  let extraJson = JSON.stringify(extra);
  if (extraJson.length > 16_000) {
    extraJson = '{}';
    ctx.plan.skip(c, 'secciones extra de ajustes demasiado grandes (se omiten esas secciones)');
  }
  ctx.plan.add('020-user-settings', c, 'user_settings', insert('user_settings', { user_id: uid, language, theme, extra_json: extraJson }));
  finish(ctx, c, r);
}

// ── profiles/{uid} ─────────────────────────────────────────────────────────
export function mapProfile(ctx: Context, d: SnapshotDoc) {
  const c = 'profiles';
  ctx.plan.collection(c).read++;
  const uid = ctx.owner(c, d.id);
  if (!uid) return;
  const r = new FieldReader(d.data);
  const first = r.str('fullName', 'displayName', 'nombre', 'name');
  const last = r.str('apellido', 'apellidos', 'lastName');
  const fullName = truncate([first, last].filter(Boolean).join(' ') || null, 120);
  const rawUsername = r.str('username', 'userName', 'handle', 'nick');
  const username = cleanUsername(rawUsername);
  if (rawUsername && !username) ctx.plan.skip(c, 'nombre de usuario no válido (se deja vacío)');
  const isPrivate = r.bool('isPrivate', 'private');
  const visRaw = r.str('visibility', 'privacy');
  const visibility = visRaw === 'private' || isPrivate === true ? 'private' : visRaw === 'followers' ? 'followers' : 'public';
  const photo = ctx.plan.mediaFrom(r.str('photoURL', 'photoUrl', 'avatarUrl', 'avatar'), {
    ownerId: uid, purpose: 'profile-photo', visibility: 'public', collection: c, docId: d.id, field: 'photoURL',
  });
  const banner = ctx.plan.mediaFrom(r.str('bannerURL', 'bannerUrl', 'coverUrl'), {
    ownerId: uid, purpose: 'profile-banner', visibility: 'public', collection: c, docId: d.id, field: 'bannerURL',
  });
  r.known('createdAt', 'updatedAt', 'uid', 'userId', 'followersCount', 'followingCount', 'postsCount', 'profileCompleted', 'online', 'lastSeen', 'profileViews', 'bannerMimeType', 'photoAssetId', 'bannerAssetId');
  // Si el nombre de usuario ya lo tomó otra persona, se deja vacío (no se inventa otro).
  ctx.plan.add(
    '040-profiles',
    c,
    'profiles',
    insert('profiles', {
      user_id: uid,
      username: username
        ? { raw: `(SELECT ${lit(username)} WHERE NOT EXISTS (SELECT 1 FROM profiles WHERE username = ${lit(username)} AND user_id <> ${lit(uid)}))` }
        : null,
      full_name: fullName,
      bio: truncate(r.str('bio', 'biografia', 'about', 'descripcion', 'description'), 500),
      location: truncate(r.str('location', 'ciudad', 'comuna', 'city'), 120),
      visibility,
      photo_asset_id: ref(ctx, 'profiles', { user_id: uid }, 'photo_asset_id', photo),
      banner_asset_id: ref(ctx, 'profiles', { user_id: uid }, 'banner_asset_id', banner),
      created_at: r.date('createdAt') ?? ctx.migratedAt,
    }),
  );
  finish(ctx, c, r);
}

// ── Catálogo de especies ───────────────────────────────────────────────────
const GROUPS: Record<string, string> = {
  aves: 'aves', ave: 'aves', birds: 'aves', bird: 'aves',
  mamiferos: 'mamiferos', 'mamíferos': 'mamiferos', mamifero: 'mamiferos', mammals: 'mamiferos',
  anfibios: 'anfibios', anfibio: 'anfibios', amphibians: 'anfibios',
  reptiles: 'reptiles', reptil: 'reptiles',
  peces: 'peces', pez: 'peces', fish: 'peces',
  insectos: 'insectos', insecto: 'insectos', insects: 'insectos', invertebrados: 'insectos',
  flora: 'flora', plantas: 'flora', planta: 'flora', plants: 'flora', arboles: 'flora', 'árboles': 'flora',
  funga: 'funga', hongos: 'funga', hongo: 'funga', fungi: 'funga',
};
const STATUSES = new Set(['LC', 'NT', 'VU', 'EN', 'CR', 'DD', 'NE']);
const STATUS_WORDS: Record<string, string> = {
  'preocupacion menor': 'LC', 'casi amenazada': 'NT', vulnerable: 'VU', 'en peligro': 'EN',
  'en peligro critico': 'CR', 'datos insuficientes': 'DD', 'no evaluada': 'NE',
};

export function mapSpecies(ctx: Context, d: SnapshotDoc) {
  const c = 'species_catalog';
  ctx.plan.collection(c).read++;
  const r = new FieldReader(d.data);
  const scientific = r.str('scientificName', 'nombreCientifico', 'scientific_name', 'cientifico');
  if (!scientific || scientific.length < 3) {
    finish(ctx, c, r);
    return ctx.plan.skip(c, 'sin nombre científico');
  }
  const groupRaw = (r.str('group', 'grupo', 'category', 'categoria', 'type', 'tipo', 'kingdom', 'reino') ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const group = GROUPS[groupRaw] ?? 'otros';
  const statusRaw = (r.str('conservationStatus', 'estadoConservacion', 'iucn', 'uicn', 'status', 'estado') ?? '').trim();
  const statusNorm = statusRaw.toUpperCase();
  const statusWord = statusRaw.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const status = STATUSES.has(statusNorm) ? statusNorm : STATUS_WORDS[statusWord] ?? 'NE';
  const sensitive = status === 'VU' || status === 'EN' || status === 'CR';
  const originRaw = (r.str('origin', 'origen') ?? '').toLowerCase();
  const origin = /intro|exot/.test(originRaw) ? 'introduced' : /nativ|endem/.test(originRaw) ? 'native' : 'unknown';
  const common = truncate(r.str('commonName', 'nombreComun', 'nombre', 'name', 'commonNameEs'), 120);
  const id = stableId(`species_catalog/${d.id}`);
  r.known('imageUrl', 'image', 'description', 'descripcion', 'createdAt', 'updatedAt');
  // Si la especie ya está en el catálogo inicial, solo se completan datos que falten.
  ctx.plan.add(
    '030-species',
    c,
    'species',
    insert(
      'species',
      {
        id,
        scientific_name: truncate(scientific, 120),
        common_name_es: common,
        common_name_en: truncate(r.str('commonNameEn', 'englishName', 'nameEn'), 120),
        taxon_group: group,
        conservation_status: status,
        origin,
        sensitive,
        legacy_id: d.id,
      },
      `(scientific_name) DO UPDATE SET legacy_id = COALESCE(species.legacy_id, excluded.legacy_id),
         common_name_es = COALESCE(species.common_name_es, excluded.common_name_es),
         common_name_en = COALESCE(species.common_name_en, excluded.common_name_en)`,
    ),
  );
  const existing = ctx.speciesByName.get(scientific.toLowerCase());
  ctx.addSpecies({ id: existing?.id ?? id, scientificName: scientific, commonNameEs: existing?.commonNameEs ?? common, sensitive: existing?.sensitive ?? sensitive });
  finish(ctx, c, r);
}

// ── Comunidades (groups, group_members) ────────────────────────────────────
export function mapGroup(ctx: Context, d: SnapshotDoc) {
  const c = 'groups';
  ctx.plan.collection(c).read++;
  const r = new FieldReader(d.data);
  const owner = ctx.owner(c, r.str('createdBy', 'ownerId', 'userId', 'authorId'), 'creador');
  const name = truncate(r.str('name', 'nombre', 'title', 'titulo'), 80);
  if (!owner) return finish(ctx, c, r);
  if (!name || name.length < 3) {
    finish(ctx, c, r);
    return ctx.plan.skip(c, 'nombre de menos de 3 caracteres');
  }
  let base = slugify(name);
  if (base.length < 3) base = `comunidad-${d.id.slice(0, 6).toLowerCase()}`;
  let slug = base;
  for (let i = 2; ctx.slugs.has(slug); i++) slug = `${base.slice(0, 36)}-${i}`;
  ctx.slugs.add(slug);
  const id = stableId(`groups/${d.id}`);
  const photo = ctx.plan.mediaFrom(r.str('imageUrl', 'photoUrl', 'photoURL', 'coverUrl'), {
    ownerId: owner, purpose: 'community-photo', visibility: 'public', collection: c, docId: d.id, field: 'imageUrl',
  });
  r.known('memberCount', 'membersCount', 'updatedAt');
  ctx.plan.add(
    '050-communities',
    c,
    'communities',
    insert('communities', {
      id,
      slug,
      name,
      description: truncate(r.str('description', 'descripcion'), 500),
      wetland: truncate(r.str('wetland', 'humedal', 'wetlandName'), 80),
      photo_asset_id: ref(ctx, 'communities', { id }, 'photo_asset_id', photo),
      created_by: owner,
      created_at: r.date('createdAt', 'timestamp') ?? ctx.migratedAt,
      legacy_id: d.id,
    }),
  );
  ctx.communityByLegacy.set(d.id, { id, createdBy: owner });
  // Quien la creó es su dueña.
  ctx.plan.add('060-community-members', c, 'community_members', insert('community_members', { community_id: id, user_id: owner, role: 'owner' }));
  finish(ctx, c, r);
}

export function mapGroupMember(ctx: Context, d: SnapshotDoc) {
  const c = 'group_members';
  ctx.plan.collection(c).read++;
  const r = new FieldReader(d.data);
  const [idGroup, idUser] = d.id.includes('_') ? d.id.split('_', 2) : [null, null];
  const group = ctx.communityByLegacy.get(r.str('groupId', 'communityId') ?? idGroup ?? '');
  if (!group) {
    finish(ctx, c, r);
    return ctx.plan.skip(c, 'comunidad no migrada');
  }
  const uid = ctx.owner(c, r.str('userId', 'uid', 'memberId') ?? idUser);
  if (!uid) return finish(ctx, c, r);
  const roleRaw = (r.str('role', 'rol') ?? '').toLowerCase();
  const role = uid === group.createdBy ? 'owner' : /admin|mod/.test(roleRaw) ? 'moderator' : 'member';
  ctx.plan.add(
    '060-community-members',
    c,
    'community_members',
    insert('community_members', { community_id: group.id, user_id: uid, role, joined_at: r.date('joinedAt', 'createdAt') ?? ctx.migratedAt }),
  );
  finish(ctx, c, r);
}

// ── follows ────────────────────────────────────────────────────────────────
export function mapFollow(ctx: Context, d: SnapshotDoc) {
  const c = 'follows';
  ctx.plan.collection(c).read++;
  const r = new FieldReader(d.data);
  const [a, b] = d.id.includes('_') ? d.id.split('_', 2) : [null, null];
  const follower = ctx.owner(c, r.str('followerId', 'follower') ?? a, 'seguidor');
  const followed = follower ? ctx.owner(c, r.str('followedId', 'followingId', 'followed') ?? b, 'seguido') : null;
  if (!follower || !followed) return finish(ctx, c, r);
  if (follower === followed) {
    finish(ctx, c, r);
    return ctx.plan.skip(c, 'se sigue a sí misma');
  }
  ctx.plan.add('070-follows', c, 'follows', insert('follows', { follower_id: follower, followed_id: followed, created_at: r.date('createdAt') ?? ctx.migratedAt }));
  finish(ctx, c, r);
}

// ── posts ──────────────────────────────────────────────────────────────────
export function mapPost(ctx: Context, d: SnapshotDoc) {
  const c = 'posts';
  ctx.plan.collection(c).read++;
  const r = new FieldReader(d.data);
  const author = ctx.owner(c, r.str('userId', 'authorId', 'uid'), 'autor');
  if (!author) return finish(ctx, c, r);
  const id = stableId(`posts/${d.id}`);
  const image = ctx.plan.mediaFrom(r.str('imageUrl', 'image', 'photoUrl', 'photoURL', 'mediaUrl'), {
    ownerId: author, purpose: 'post-photo', visibility: 'public', collection: c, docId: d.id, field: 'imageUrl',
  });
  let body = r.str('content', 'text', 'body', 'description', 'caption', 'texto');
  if (!body) {
    if (!image) {
      finish(ctx, c, r);
      return ctx.plan.skip(c, 'publicación vacía');
    }
    body = '📷';
    ctx.plan.skip(c, 'sin texto: se publica con 📷 (no se omite, solo se avisa)');
  }
  if ([...body].length > 2000) ctx.plan.skip(c, 'texto recortado a 2000 caracteres (no se omite)');
  const group = r.str('groupId', 'communityId');
  const community = group ? ctx.communityByLegacy.get(group) : undefined;
  if (group && !community) ctx.plan.skip(c, 'comunidad no migrada: queda como publicación general (no se omite)');
  r.known('likes', 'likesCount', 'comments', 'commentsCount', 'shares', 'sharesCount', 'userName', 'userPhoto', 'authorName', 'authorPhoto', 'updatedAt');
  const created = r.date('createdAt', 'timestamp', 'date') ?? ctx.migratedAt;
  ctx.plan.add(
    '080-posts',
    c,
    'posts',
    insert('posts', {
      id,
      author_id: author,
      body: truncate(body, 2000),
      media_asset_id: ref(ctx, 'posts', { id }, 'media_asset_id', image),
      community_id: community?.id ?? null,
      visibility: 'public',
      location_name: truncate(r.str('location', 'locationName', 'place', 'lugar'), 120),
      created_at: created,
      updated_at: created,
      legacy_id: d.id,
    }),
  );
  ctx.postByLegacy.set(d.id, id);
  finish(ctx, c, r);
}

// ── notebooks, notebook_pages ──────────────────────────────────────────────
export function mapNotebook(ctx: Context, d: SnapshotDoc) {
  const c = 'notebooks';
  ctx.plan.collection(c).read++;
  const r = new FieldReader(d.data);
  const owner = ctx.owner(c, r.str('userId', 'ownerId', 'uid'));
  if (!owner) return finish(ctx, c, r);
  const id = stableId(`notebooks/${d.id}`);
  const isPublic = r.bool('isPublic', 'public') === true || r.str('visibility') === 'public';
  const color = r.str('color', 'coverColor');
  const cover = ctx.plan.mediaFrom(r.str('coverImageUrl', 'coverUrl', 'imageUrl'), {
    ownerId: owner, purpose: 'notebook-photo', visibility: isPublic ? 'public' : 'private', collection: c, docId: d.id, field: 'coverImageUrl',
  });
  r.known('pageCount', 'pagesCount', 'likes', 'likesCount', 'category', 'iconName');
  const created = r.date('createdAt', 'timestamp') ?? ctx.migratedAt;
  ctx.plan.add(
    '090-notebooks',
    c,
    'notebooks',
    insert('notebooks', {
      id,
      owner_id: owner,
      title: truncate(r.str('title', 'name', 'titulo', 'nombre') ?? 'Cuaderno de campo', 120),
      description: truncate(r.str('description', 'descripcion'), 500),
      color: isHexColor(color) ? color.toUpperCase() : '#2E5B2A',
      cover_asset_id: ref(ctx, 'notebooks', { id }, 'cover_asset_id', cover),
      visibility: isPublic ? 'public' : 'private',
      created_at: created,
      updated_at: r.date('updatedAt') ?? created,
      legacy_id: d.id,
    }),
  );
  ctx.notebookOwner.set(d.id, { id, owner, isPublic });
  finish(ctx, c, r);
}

/** Las páginas se ordenan por su número, luego por fecha, para asignar posiciones 0..n-1. */
export function mapNotebookPages(ctx: Context, docs: SnapshotDoc[]) {
  const c = 'notebook_pages';
  // Escala de los elementos antiguos (píxeles) al lienzo nuevo de 1000 de ancho:
  // se toma el ancho que realmente ocupan los elementos (mínimo 800 px).
  let legacyWidth = 800;
  for (const d of docs) {
    for (const e of legacyElements(d.data)) legacyWidth = Math.max(legacyWidth, (num(e['x']) ?? 0) + (num(e['width']) ?? 0));
  }
  const scale = 1000 / legacyWidth;
  const byNotebook = new Map<string, { d: SnapshotDoc; order: number; created: string }[]>();
  for (const d of docs) {
    ctx.plan.collection(c).read++;
    const nbLegacy = typeof d.data['notebookId'] === 'string' ? (d.data['notebookId'] as string) : null;
    if (!nbLegacy || !ctx.notebookOwner.has(nbLegacy)) {
      ctx.plan.skip(c, 'cuaderno no migrado');
      continue;
    }
    const r = new FieldReader(d.data);
    const order = r.num('pageNumber', 'order', 'index', 'position', 'numero') ?? Number.MAX_SAFE_INTEGER;
    const created = r.date('createdAt', 'timestamp') ?? '';
    const list = byNotebook.get(nbLegacy) ?? [];
    list.push({ d, order, created });
    byNotebook.set(nbLegacy, list);
  }
  for (const [nbLegacy, list] of byNotebook) {
    const nb = ctx.notebookOwner.get(nbLegacy)!;
    list.sort((a, b) => a.order - b.order || a.created.localeCompare(b.created) || a.d.id.localeCompare(b.d.id));
    list.forEach(({ d }, position) => mapPage(ctx, d, nb, position, scale));
  }
}

const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null);

function legacyElements(data: Doc): Doc[] {
  const v = data['elements'];
  return Array.isArray(v) ? v.filter((e): e is Doc => !!e && typeof e === 'object' && !Array.isArray(e)) : [];
}

function mapPage(ctx: Context, d: SnapshotDoc, nb: { id: string; owner: string; isPublic: boolean }, position: number, scale: number) {
  const c = 'notebook_pages';
  const r = new FieldReader(d.data);
  r.known('notebookId', 'pageNumber', 'order', 'index', 'position', 'numero', 'category', 'elements');
  const author = r.str('userId', 'ownerId', 'uid');
  if (author && author !== nb.owner) ctx.plan.skip(c, 'autor distinto del dueño del cuaderno (se migra con el dueño)');
  const id = stableId(`notebook_pages/${d.id}`);
  const coords = r.coords(['latitude', 'lat'], ['longitude', 'lng', 'lon'], ['location', 'coords', 'geo']);
  const sourceRaw = r.str('locationSource');
  const dateStr = r.str('dateStr');
  const pageDate = (dateStr && /^\d{4}-\d{2}-\d{2}/.test(dateStr) ? `${dateStr.slice(0, 10)}T00:00:00.000Z` : null) ?? r.date('date', 'fecha', 'pageDate', 'createdAt');
  const created = r.date('createdAt', 'timestamp') ?? ctx.migratedAt;
  const species = r.str('speciesName', 'species', 'especie');
  const scientific = r.str('scientificName', 'nombreCientifico');
  ctx.plan.add(
    '100-notebook-pages',
    c,
    'notebook_pages',
    insert('notebook_pages', {
      id,
      notebook_id: nb.id,
      position,
      title: truncate(r.str('title', 'titulo') ?? species, 120),
      page_date: pageDate ? pageDate.slice(0, 10) : null,
      location_name: truncate(r.str('locationName', 'place', 'lugar'), 120),
      latitude: coords?.lat ?? null,
      longitude: coords?.lng ?? null,
      location_source: coords && (sourceRaw === 'gps' || sourceRaw === 'manual') ? sourceRaw : null,
      weather: truncate(r.str('weather', 'clima', 'weatherCondition'), 80),
      created_at: created,
      updated_at: r.date('updatedAt') ?? created,
      legacy_id: d.id,
    }),
  );

  let z = 1;
  const visibility = nb.isPublic ? 'public' : 'private';
  const elements = legacyElements(d.data);

  // 1) Elementos colocados en la página antigua (texto e imágenes), escalados al lienzo nuevo.
  elements.forEach((e, i) => {
    const box = {
      x: Math.round((num(e['x']) ?? 0) * scale),
      y: Math.round((num(e['y']) ?? 0) * scale),
      width: Math.max(20, Math.round((num(e['width']) ?? 300) * scale)),
      height: Math.max(20, Math.round((num(e['height']) ?? 100) * scale)),
      z: z++,
      rotation: num(e['rotation']) ?? 0,
    };
    const localId = `antiguo-${i + 1}`;
    const image = typeof e['imageUrl'] === 'string' ? (e['imageUrl'] as string) : null;
    const content = typeof e['content'] === 'string' ? (e['content'] as string) : null;
    if (image && image.startsWith('/') && ctx.assetFor(image)) {
      element(ctx, id, localId, 'sticker', box, { asset: ctx.assetFor(image) }, null);
    } else if (image) {
      const asset = ctx.plan.mediaFrom(image, { ownerId: nb.owner, purpose: 'notebook-photo', visibility, collection: c, docId: d.id, field: `elements[${i}]` });
      if (asset) element(ctx, id, localId, 'photo', box, {}, asset);
    } else if (content) {
      const st = (e['style'] && typeof e['style'] === 'object' ? e['style'] : {}) as Doc;
      const color = typeof st['color'] === 'string' && /^#[0-9a-fA-F]{6}$/.test(st['color']) ? st['color'] : '#22261F';
      element(ctx, id, localId, 'text', box, {
        text: truncate(content, 20_000),
        size: Math.max(10, Math.round((num(st['fontSize']) ?? 18) * scale)),
        color,
        ...(num(st['fontWeight']) !== null && num(st['fontWeight'])! >= 600 ? { bold: true } : {}),
        ...(st['italic'] === true ? { italic: true } : {}),
        ...(st['align'] === 'center' || st['align'] === 'right' ? { align: st['align'] } : {}),
      }, null);
    } else {
      ctx.plan.skip(c, 'elemento antiguo sin texto ni imagen');
    }
  });

  // 2) Campos de la página (especie, descripción, dibujo, foto) bajo los elementos, si existen.
  if (species || scientific) {
    element(ctx, id, 'especie', 'species', { x: 60, y: elements.length ? 60 : 40, width: 880, height: 90, z: z++, rotation: 0 }, {
      label: [species, scientific ? `(${scientific})` : null].filter(Boolean).join(' '),
      ...(species ? { commonName: species } : {}),
      ...(scientific ? { scientificName: scientific } : {}),
    }, null);
  }
  const drawing = r.str('drawing', 'drawingDataUrl', 'drawingUrl', 'canvasData', 'sketch', 'imageData');
  if (drawing) {
    const asset = ctx.plan.mediaFrom(drawing, { ownerId: nb.owner, purpose: 'notebook-photo', visibility, collection: c, docId: d.id, field: 'drawing' });
    if (asset) element(ctx, id, 'dibujo', 'photo', { x: 0, y: 0, width: 1000, height: 1414, z: 0, rotation: 0 }, { legacy: 'drawing' }, asset);
  }
  const photo = r.str('imageUrl', 'photoUrl', 'photoURL', 'image');
  const photoBox = elements.length ? { x: 100, y: 1060, width: 480, height: 340, z: z++, rotation: 0 } : { x: 100, y: 760, width: 800, height: 560, z: z++, rotation: 0 };
  if (photo && photo.startsWith('/') && ctx.assetFor(photo)) {
    element(ctx, id, 'ilustracion', 'sticker', photoBox, { asset: ctx.assetFor(photo) }, null);
  } else if (photo) {
    const asset = ctx.plan.mediaFrom(photo, { ownerId: nb.owner, purpose: 'notebook-photo', visibility, collection: c, docId: d.id, field: 'imageUrl' });
    if (asset) element(ctx, id, 'foto', 'photo', photoBox, {}, asset);
  }
  const texts = [r.str('content', 'text', 'notes', 'body', 'texto', 'notas'), r.str('description', 'descripcion'), r.str('datoPersonalizado')].filter(
    (t): t is string => !!t,
  );
  if (texts.length) {
    element(ctx, id, 'texto', 'text', elements.length ? { x: 600, y: 1060, width: 360, height: 340, z: z++, rotation: 0 } : { x: 60, y: 140, width: 880, height: 600, z: z++, rotation: 0 }, {
      text: truncate(texts.join('\n\n'), 20_000),
      size: 28,
      color: '#22261F',
    }, null);
  }
  if (r.str('audioNoteUrl', 'audioUrl')) ctx.plan.skip(c, 'nota de audio: el editor nuevo aún no tiene audio (no se migra)');
  const sticker = r.str('sticker', 'stickerId');
  const stickerBox = { x: 760, y: 40, width: 200, height: 200, z: z++, rotation: 0 };
  if (sticker) {
    const local = sticker.startsWith('/') ? ctx.assetFor(sticker) : null;
    if (local) {
      element(ctx, id, 'pegatina', 'sticker', stickerBox, { asset: local }, null);
    } else if (sticker.startsWith('data:image') || /^https:\/\//.test(sticker)) {
      const asset = ctx.plan.mediaFrom(sticker, { ownerId: nb.owner, purpose: 'notebook-photo', visibility, collection: c, docId: d.id, field: 'sticker' });
      if (asset) element(ctx, id, 'pegatina', 'photo', stickerBox, {}, asset);
    } else if ([...sticker].length <= 16) {
      // Emoji o palabra corta: se conserva como texto grande.
      element(ctx, id, 'pegatina', 'text', stickerBox, { text: sticker, size: 96, color: '#22261F', align: 'center' }, null);
    } else {
      ctx.plan.skip(c, 'pegatina antigua en formato desconocido (no se migra)');
    }
  }
  finish(ctx, c, r);
}

function element(
  ctx: Context,
  pageId: string,
  localId: string,
  type: 'text' | 'photo' | 'species' | 'sticker',
  box: { x: number; y: number; width: number; height: number; z: number; rotation?: number },
  data: Doc,
  mediaId: string | null,
) {
  ctx.plan.add(
    '110-notebook-elements',
    'notebook_pages',
    'notebook_elements',
    insert('notebook_elements', {
      id: localId,
      page_id: pageId,
      type,
      x: box.x,
      y: box.y,
      width: box.width,
      height: box.height,
      rotation: Math.max(-360, Math.min(360, box.rotation ?? 0)),
      z: box.z,
      data_json: JSON.stringify(data),
      media_asset_id: ref(ctx, 'notebook_elements', { page_id: pageId, id: localId }, 'media_asset_id', mediaId),
    }),
  );
}

// ── observations ───────────────────────────────────────────────────────────
export function mapObservation(ctx: Context, d: SnapshotDoc) {
  const c = 'observations';
  ctx.plan.collection(c).read++;
  const r = new FieldReader(d.data);
  const owner = ctx.owner(c, r.str('userId', 'uid', 'authorId', 'ownerId'));
  if (!owner) return finish(ctx, c, r);
  const coords = r.coords(['latitude', 'lat'], ['longitude', 'lng', 'lon'], ['location', 'coords', 'position', 'geo', 'coordinates']);
  if (!coords) {
    finish(ctx, c, r);
    return ctx.plan.skip(c, 'sin coordenadas válidas');
  }
  const names = [
    r.str('scientificName', 'nombreCientifico', 'especieCientifico'),
    r.str('species', 'especie', 'speciesName', 'commonName', 'nombreComun', 'name', 'nombre', 'title', 'titulo'),
  ].filter((v): v is string => !!v);
  const match = names.map((n) => ctx.speciesByName.get(n.toLowerCase())).find(Boolean);
  const taxonName = match ? null : truncate(names[0] ?? null, 120);
  if (!match && !taxonName) {
    finish(ctx, c, r);
    return ctx.plan.skip(c, 'sin especie ni nombre');
  }
  const isPublic = r.bool('isPublic', 'public');
  const visibility = isPublic === false || r.str('visibility') === 'private' ? 'private' : 'public';
  const obscured = match?.sensitive === true;
  const observedAt = r.date('observedAt', 'date', 'fecha', 'createdAt', 'timestamp') ?? ctx.migratedAt;
  const count = r.num('count', 'cantidad', 'quantity', 'individuals');
  const accuracy = r.num('accuracy', 'accuracyM', 'precision');
  const source = r.str('locationSource');
  const photo = ctx.plan.mediaFrom(r.str('imageUrl', 'photoUrl', 'photoURL', 'image'), {
    ownerId: owner, purpose: 'observation-photo', visibility, collection: c, docId: d.id, field: 'imageUrl',
  });
  r.known('likes', 'likesCount', 'userName', 'userPhoto', 'updatedAt', 'category', 'categoria', 'group', 'grupo');
  const created = r.date('createdAt', 'timestamp') ?? observedAt;
  const observationId = stableId(`observations/${d.id}`);
  ctx.plan.add(
    '120-observations',
    c,
    'observations',
    insert('observations', {
      id: observationId,
      owner_id: owner,
      species_id: match?.id ?? null,
      taxon_name: taxonName,
      individual_count: count !== null && Number.isInteger(count) && count >= 1 && count <= 100_000 ? count : null,
      observed_at: observedAt,
      latitude: coords.lat,
      longitude: coords.lng,
      accuracy_m: accuracy !== null && accuracy >= 0 && accuracy <= 100_000 ? accuracy : null,
      location_source: source === 'gps' ? 'gps' : 'manual',
      location_name: truncate(r.str('locationName', 'placeName', 'lugar', 'place', 'wetlandName', 'humedal'), 120),
      public_latitude: obscured ? cellCenter(coords.lat) : coords.lat,
      public_longitude: obscured ? cellCenter(coords.lng) : coords.lng,
      obscured,
      geoprivacy: 'open',
      notes: truncate(r.str('notes', 'description', 'descripcion', 'notas', 'comment', 'comentario'), 2000),
      photo_asset_id: ref(ctx, 'observations', { id: observationId }, 'photo_asset_id', photo),
      visibility,
      created_at: created,
      updated_at: r.date('updatedAt') ?? created,
      legacy_id: d.id,
    }),
  );
  finish(ctx, c, r);
}

// ── chat_messages → conversations + messages ───────────────────────────────
export function mapChatMessages(ctx: Context, docs: SnapshotDoc[]) {
  const c = 'chat_messages';
  const lastByConv = new Map<string, string>();
  const convs = new Map<string, { a: string; b: string; legacy: string; created: string }>();
  const rows: { d: SnapshotDoc; r: FieldReader; convId: string; sender: string; body: string; created: string }[] = [];
  for (const d of docs) {
    ctx.plan.collection(c).read++;
    const r = new FieldReader(d.data);
    const sender = ctx.owner(c, r.str('senderId', 'fromId', 'from', 'userId'), 'remitente');
    const recipient = sender ? ctx.owner(c, r.str('recipientId', 'receiverId', 'toId', 'to'), 'destinatario') : null;
    if (!sender || !recipient) {
      finish(ctx, c, r);
      continue;
    }
    if (sender === recipient) {
      finish(ctx, c, r);
      ctx.plan.skip(c, 'mensaje a sí misma');
      continue;
    }
    const body = r.str('text', 'message', 'content', 'body', 'mensaje');
    if (!body) {
      finish(ctx, c, r);
      ctx.plan.skip(c, 'mensaje vacío');
      continue;
    }
    const [a, b] = sender < recipient ? [sender, recipient] : [recipient, sender];
    const convId = stableId(`conversations/${a}/${b}`);
    const created = r.date('createdAt', 'timestamp', 'sentAt') ?? ctx.migratedAt;
    if (!convs.has(convId)) convs.set(convId, { a, b, legacy: r.str('chatId') ?? `${a}_${b}`, created });
    const conv = convs.get(convId)!;
    if (created < conv.created) conv.created = created;
    if (!lastByConv.has(convId) || created > lastByConv.get(convId)!) lastByConv.set(convId, created);
    rows.push({ d, r, convId, sender, body, created });
  }
  for (const [id, cv] of convs) {
    ctx.plan.add(
      '130-conversations',
      c,
      'conversations',
      insert('conversations', { id, user_a: cv.a, user_b: cv.b, created_at: cv.created, last_message_at: lastByConv.get(id) ?? null, legacy_chat_id: cv.legacy }),
    );
  }
  for (const { d, r, convId, sender, body, created } of rows) {
    const read = r.bool('read', 'isRead', 'seen');
    r.known('senderName', 'chatId');
    if (r.str('imageUrl')) ctx.plan.skip(c, 'imagen adjunta en un mensaje: los mensajes nuevos aún no tienen imágenes (se copia solo el texto)');
    ctx.plan.add(
      '140-messages',
      c,
      'messages',
      insert('messages', {
        id: stableId(`chat_messages/${d.id}`),
        conversation_id: convId,
        sender_id: sender,
        body: truncate(body, 2000),
        created_at: created,
        read_at: read ? created : null,
        legacy_id: d.id,
      }),
    );
    finish(ctx, c, r);
  }
}

// ── places, wetlands → places ──────────────────────────────────────────────
export function mapPlace(ctx: Context, d: SnapshotDoc, collection: 'places' | 'wetlands') {
  ctx.plan.collection(collection).read++;
  const r = new FieldReader(d.data);
  const name = truncate(r.str('name', 'nombre', 'title', 'titulo'), 120);
  const coords = r.coords(['lat', 'latitude'], ['lng', 'longitude', 'lon'], ['location', 'coords', 'center', 'geo', 'position']);
  if (!name || !coords) {
    finish(ctx, collection, r);
    return ctx.plan.skip(collection, !name ? 'sin nombre' : 'sin coordenadas válidas');
  }
  const kindRaw = (r.str('type', 'kind', 'category', 'categoria', 'tipo') ?? '').toLowerCase();
  const kind =
    collection === 'wetlands' || /humedal|wetland/.test(kindRaw)
      ? 'wetland'
      : /sender|trail|ruta/.test(kindRaw)
        ? 'trail'
        : /mirador|viewpoint/.test(kindRaw)
          ? 'viewpoint'
          : 'other';
  const geometry = r.obj('geojson', 'geometry', 'polygon', 'boundary');
  const geoType = geometry?.['type'];
  const geojson =
    geometry && typeof geoType === 'string' && ['Polygon', 'MultiPolygon', 'LineString', 'MultiLineString', 'Feature'].includes(geoType)
      ? JSON.stringify(geometry)
      : null;
  if (geometry && !geojson) ctx.plan.skip(collection, 'contorno en formato desconocido (se migra solo el punto)');
  if (r.str('imageUrl', 'photoUrl')) ctx.plan.skip(collection, 'foto del lugar: la tabla places aún no tiene foto (no se migra la foto)');
  r.known('authorId', 'wetlandId', 'createdAt', 'updatedAt');
  ctx.plan.add(
    '150-places',
    collection,
    'places',
    insert('places', {
      id: stableId(`${collection}/${d.id}`),
      kind,
      name,
      description: truncate(r.str('description', 'descripcion'), 2000),
      latitude: coords.lat,
      longitude: coords.lng,
      geojson,
      legacy_id: `${collection}/${d.id}`,
    }),
  );
  finish(ctx, collection, r);
}

// ── user_file_assets: archivos subidos (aunque ningún documento los cite) ──
const PURPOSE_FROM_PATH: Record<string, 'observation-photo' | 'notebook-photo' | 'notebook-audio' | 'profile-photo' | 'profile-banner' | 'community-photo' | 'post-photo' | 'map-place-photo'> = {
  observations: 'observation-photo', observation: 'observation-photo',
  notebooks: 'notebook-photo', notebook: 'notebook-photo', 'notebook-pages': 'notebook-photo', drawings: 'notebook-photo',
  audio: 'notebook-audio', audios: 'notebook-audio',
  avatar: 'profile-photo', avatars: 'profile-photo', profile: 'profile-photo', 'profile-photo': 'profile-photo',
  banner: 'profile-banner', banners: 'profile-banner',
  groups: 'community-photo', communities: 'community-photo',
  posts: 'post-photo', post: 'post-photo',
  places: 'map-place-photo',
};

export function mapFileAsset(ctx: Context, d: SnapshotDoc) {
  const c = 'user_file_assets';
  ctx.plan.collection(c).read++;
  const r = new FieldReader(d.data);
  const path = r.str('storagePath', 'path', 'fullPath');
  const owner = ctx.owner(c, r.str('ownerId', 'userId', 'uid') ?? path?.split('/')[1] ?? null);
  if (!owner) return finish(ctx, c, r);
  if (!path) {
    finish(ctx, c, r);
    return ctx.plan.skip(c, 'sin ruta de Storage');
  }
  const segment = (r.str('purpose', 'kind', 'type') ?? path.split('/')[2] ?? '').toLowerCase();
  const purpose = PURPOSE_FROM_PATH[segment] ?? (/audio/.test(r.str('contentType', 'mimeType') ?? '') ? 'notebook-audio' : 'post-photo');
  r.known('contentType', 'mimeType', 'size', 'sizeBytes', 'createdAt', 'downloadUrl', 'url', 'name', 'fileName');
  ctx.plan.mediaFromStoragePath(path, owner, purpose, 'private', d.id);
  finish(ctx, c, r);
}

/** Recalcula contadores a partir de lo migrado. */
export function recountStatements(): string[] {
  return [
    `UPDATE posts SET reaction_count = (SELECT count(*) FROM reactions x WHERE x.post_id = posts.id),
       comment_count = (SELECT count(*) FROM comments x WHERE x.post_id = posts.id AND x.deleted_at IS NULL)
     WHERE legacy_id IS NOT NULL;`,
    `UPDATE notebooks SET page_count = (SELECT count(*) FROM notebook_pages p WHERE p.notebook_id = notebooks.id) WHERE legacy_id IS NOT NULL;`,
    `UPDATE communities SET member_count = (SELECT count(*) FROM community_members m WHERE m.community_id = communities.id) WHERE legacy_id IS NOT NULL;`,
    `UPDATE conversations SET last_message_at = (SELECT max(created_at) FROM messages m WHERE m.conversation_id = conversations.id) WHERE legacy_chat_id IS NOT NULL;`,
  ];
}
