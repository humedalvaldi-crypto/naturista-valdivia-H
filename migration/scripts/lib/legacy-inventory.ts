/**
 * Inventario de colecciones de la app antigua (React + Firebase), obtenido
 * del código fuente `naturista-valdivia-proyecto` (artifacts/naturalista-valdivia/src).
 * La auditoría compara este inventario con lo que realmente existe en Firestore.
 */

export interface LegacyCollection {
  name: string;
  /** Cómo se forma el ID del documento en el código antiguo. */
  docId: 'auto' | 'uid' | 'composite';
  /** Campos que contienen UIDs de Firebase y deben existir en Auth. */
  uidFields: string[];
  /** Campos que apuntan a documentos de otras colecciones. */
  refFields?: Record<string, string>;
  /** Contiene datos personales sensibles. */
  sensitive?: boolean;
  /** Tabla destino prevista en D1 (Fase 8 confirma el mapeo). */
  target: string;
  notes?: string;
}

export const LEGACY_COLLECTIONS: LegacyCollection[] = [
  {
    name: 'profiles',
    docId: 'uid',
    uidFields: [],
    sensitive: true,
    target: 'profiles + profile_private',
    notes: 'Incluye rut, fechaNacimiento, telefono, whatsapp, genero, addressValdivia. Ver docs/security.md.',
  },
  { name: 'settings', docId: 'uid', uidFields: [], target: 'user_settings', notes: 'Secciones: language, accessibility, notebook, map, stickers, privacy, notifications, twoFactor.' },
  { name: 'posts', docId: 'auto', uidFields: ['userId'], target: 'posts', notes: 'Contadores likes/comments/shares desnormalizados.' },
  { name: 'observations', docId: 'auto', uidFields: ['userId'], target: 'observations', notes: "Puede tener userId = 'anon'." },
  { name: 'notebooks', docId: 'auto', uidFields: ['userId'], target: 'notebooks' },
  {
    name: 'notebook_pages',
    docId: 'auto',
    uidFields: ['userId'],
    refFields: { notebookId: 'notebooks' },
    target: 'notebook_pages + notebook_elements',
    notes: 'Campos de ubicación latitude/longitude/locationSource; audioNoteUrl; sticker.',
  },
  { name: 'notebook_likes', docId: 'composite', uidFields: ['userId'], refFields: { notebookId: 'notebooks' }, target: 'reactions' },
  { name: 'follows', docId: 'composite', uidFields: ['followerId', 'followedId'], target: 'follows', notes: 'ID = `${followerId}_${followedId}`.' },
  { name: 'groups', docId: 'auto', uidFields: ['createdBy'], target: 'communities' },
  { name: 'group_members', docId: 'composite', uidFields: ['userId'], refFields: { groupId: 'groups' }, target: 'community_members' },
  { name: 'chat_messages', docId: 'auto', uidFields: ['senderId', 'recipientId'], target: 'conversations + messages', notes: "chatId derivado de ambos UIDs; puede haber senderId = 'guest'." },
  { name: 'notifications', docId: 'auto', uidFields: ['userId'], target: 'notifications' },
  { name: 'places', docId: 'auto', uidFields: ['authorId'], target: 'map points (por definir)', notes: 'lat/lng, wetlandId, imageUrl.' },
  { name: 'wetlands', docId: 'auto', uidFields: [], target: 'map_layers', notes: 'Catálogo de humedales.' },
  { name: 'species_catalog', docId: 'auto', uidFields: [], target: 'species' },
  { name: 'species_album', docId: 'auto', uidFields: [], target: 'species (álbum)' },
  { name: 'user_collections', docId: 'uid', uidFields: [], target: 'user_species_unlocks', notes: 'unlockedIds: string[].' },
  { name: 'user_file_assets', docId: 'auto', uidFields: ['ownerId'], target: 'media_assets', notes: 'storagePath en Firebase Storage → objeto R2.' },
  { name: 'profile_views', docId: 'composite', uidFields: ['profileId', 'viewerId'], target: 'profile_views (por decidir)' },
  { name: 'reports', docId: 'auto', uidFields: ['userId'], sensitive: true, target: 'reports', notes: 'Mensajes de contacto con userEmail.' },
];

/** Subcolecciones conocidas: `users/{uid}/notifications`. */
export const LEGACY_SUBCOLLECTIONS = [{ parent: 'users', name: 'notifications', target: 'notifications' }];

/** Valores de UID ficticios usados por la app antigua cuando no había sesión. */
export const PLACEHOLDER_UIDS = new Set(['anon', 'guest', '']);
