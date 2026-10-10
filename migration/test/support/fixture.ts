import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

/** PNG de 1×1 válido. */
export const PNG_1x1 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

const ts = (iso: string) => ({ $ts: iso });
const url = (path: string) =>
  `https://firebasestorage.googleapis.com/v0/b/humedalvaldivia-c7d08.firebasestorage.app/o/${encodeURIComponent(path)}?alt=media&token=abc`;

/** Instantánea ficticia con la forma de la exportación real (sin datos reales). */
export function writeFixtureSnapshot(): string {
  const dir = mkdtempSync(join(tmpdir(), 'nv-snapshot-'));
  mkdirSync(join(dir, 'firestore'));
  const jsonl = (file: string, rows: unknown[]) => writeFileSync(join(dir, file), rows.map((r) => JSON.stringify(r)).join('\n') + '\n');

  jsonl('auth-users.jsonl', [
    { uid: 'uidAna', email: 'ana@example.test', emailVerified: true, displayName: 'Ana', providers: ['google.com'], disabled: false, createdAt: '2025-03-01T10:00:00.000Z' },
    { uid: 'uidBeto', email: 'beto@example.test', emailVerified: false, displayName: "Beto O'Higgins", providers: ['password'], disabled: false, createdAt: '2025-04-01T10:00:00.000Z' },
    { uid: 'uidCami', email: null, emailVerified: false, displayName: null, providers: [], disabled: true, createdAt: null },
  ]);
  const fs = (name: string, docs: { id: string; data: unknown; parent?: string }[]) =>
    jsonl(`firestore/${name}.jsonl`, docs.map((d) => ({ path: `${name}/${d.id}`, ...d })));

  fs('profiles', [
    {
      id: 'uidAna',
      data: {
        nombre: 'Ana', apellido: 'Rojas', username: 'Ana.Rojas', bio: 'Observadora de aves', comuna: 'Valdivia',
        rut: '11.111.111-1', telefono: '+56 9 1111 1111', fechaNacimiento: '1990-01-01',
        photoURL: url('user-files/uidAna/avatar/a.jpg'), campoRaro: 1,
      },
    },
    { id: 'uidBeto', data: { nombre: 'Beto', username: 'ana.rojas', isPrivate: true, photoURL: 'https://lh3.googleusercontent.com/a/foto-beto=s96-c' } }, // nombre de usuario repetido
    { id: 'anon', data: { nombre: 'Anónimo' } },
  ]);
  fs('settings', [
    { id: 'uidAna', data: { language: 'en', darkMode: true, twoFactor: { enabled: true }, map: { layer: 'sat' } } },
    { id: 'uidBeto', data: { appearance: { theme: 'light', fontSize: 'large' } } },
  ]);
  fs('species_catalog', [
    { id: 'sc1', data: { scientificName: 'Lontra provocax', nombreComun: 'Huillín', categoria: 'Mamíferos', estadoConservacion: 'En peligro' } },
    { id: 'sc2', data: { scientificName: 'Phalacrocorax brasilianus', nombreComun: 'Yeco', categoria: 'Aves', estadoConservacion: 'LC' } },
  ]);
  fs('groups', [
    { id: 'g1', data: { name: 'Amigos del Angachilla', createdBy: 'uidAna', description: 'Salidas los sábados', imageUrl: url('user-files/uidAna/groups/g.png') } },
    { id: 'g2', data: { name: 'Amigos del Angachilla', createdBy: 'uidBeto' } }, // mismo nombre → slug distinto
  ]);
  fs('group_members', [
    { id: 'g1_uidBeto', data: { groupId: 'g1', userId: 'uidBeto', role: 'admin' } },
    { id: 'g1_guest', data: { groupId: 'g1', userId: 'guest' } },
  ]);
  fs('follows', [
    { id: 'uidAna_uidBeto', data: { followerId: 'uidAna', followedId: 'uidBeto', createdAt: ts('2025-05-01T00:00:00Z') } },
    { id: 'uidBeto_uidFantasma', data: { followerId: 'uidBeto', followedId: 'uidFantasma' } },
  ]);
  fs('posts', [
    { id: 'p1', data: { userId: 'uidAna', content: "Garza en el humedal, ¡qué día! It's 'great'", imageUrl: url('user-files/uidAna/posts/p1.jpg'), createdAt: ts('2025-06-01T12:00:00Z'), likes: 3, groupId: 'g1' } },
    { id: 'p2', data: { userId: 'uidBeto', imageUrl: 'data:image/png;base64,' + PNG_1x1 } }, // sin texto
    { id: 'p3', data: { userId: 'anon', content: 'hola' } },
    { id: 'p4', data: { userId: 'uidAna', content: 'Foto externa', imageUrl: 'https://i.imgur.com/x.jpg' } },
  ]);
  fs('notebooks', [
    { id: 'nb1', data: { userId: 'uidAna', title: 'Salidas 2025', color: '#2f6f7e', isPublic: true, coverImageUrl: url('user-files/uidAna/notebooks/c.jpg') } },
    { id: 'nb2', data: { userId: 'uidFantasma', title: 'Huérfano' } },
  ]);
  fs('notebook_pages', [
    { id: 'pg-b', data: { notebookId: 'nb1', userId: 'uidAna', pageNumber: 2, content: 'Segunda página', drawing: 'data:image/png;base64,' + PNG_1x1 } },
    { id: 'pg-a', data: { notebookId: 'nb1', userId: 'uidAna', pageNumber: 1, content: 'Canto de chucao', latitude: -39.86, longitude: -73.23, locationSource: 'gps', audioNoteUrl: url('user-files/uidAna/audio/n.m4a') } },
    { id: 'pg-x', data: { notebookId: 'nb2', content: 'perdida' } },
    {
      id: 'pg-c',
      data: {
        notebookId: 'nb1', userId: 'uidAna', pageNumber: 3, speciesName: 'Chucao', scientificName: 'Scelorchilus rubecula',
        description: 'Cantaba en el sotobosque', datoPersonalizado: 'Día nublado, 8 °C', weatherCondition: 'Nublado', dateStr: '2025-09-14', category: 'aves',
        elements: [
          { id: 'e1', type: 'text', x: 40, y: 80, width: 400, height: 60, rotation: -5, content: 'Título de campo', style: { align: 'center', color: '#2E5B2A', fontSize: 32, fontWeight: 700, italic: true } },
          { id: 'e2', type: 'image', x: 100, y: 200, width: 600, height: 400, rotation: 0, imageUrl: 'data:image/png;base64,' + PNG_1x1 },
          { id: 'e3', type: 'image', x: 0, y: 0, width: 10, height: 10, rotation: 0, imageUrl: 'blob:https://app/xyz' },
        ],
      },
    },
  ]);
  fs('observations', [
    { id: 'o1', data: { userId: 'uidAna', species: 'Huillín', location: { $geo: [-39.8612, -73.2345] }, date: ts('2025-07-01T09:00:00Z'), imageUrl: url('user-files/uidAna/observations/o1.jpg') } },
    { id: 'o2', data: { userId: 'uidBeto', especie: 'Martín pescador', lat: -39.81, lng: -73.24, cantidad: 2, isPublic: false } },
    { id: 'o3', data: { userId: 'uidAna', species: 'Chucao' } }, // sin coordenadas
    { id: 'o4', data: { userId: 'anon', species: 'Coipo', lat: -39.8, lng: -73.2 } },
  ]);
  fs('chat_messages', [
    { id: 'm1', data: { senderId: 'uidAna', recipientId: 'uidBeto', text: 'Hola Beto', createdAt: ts('2025-08-01T10:00:00Z'), read: true } },
    { id: 'm2', data: { senderId: 'uidBeto', recipientId: 'uidAna', text: 'Hola Ana', createdAt: ts('2025-08-01T10:05:00Z') } },
    { id: 'm3', data: { senderId: 'guest', recipientId: 'uidAna', text: 'spam' } },
  ]);
  fs('wetlands', [{ id: 'w1', data: { name: 'Humedal Angachilla', lat: -39.86, lng: -73.23, geometry: { type: 'Polygon', coordinates: [[[-73.24, -39.87], [-73.22, -39.87], [-73.22, -39.85], [-73.24, -39.87]]] } } }]);
  fs('places', [{ id: 'pl1', data: { name: 'Mirador del río', type: 'mirador', location: { $geo: [-39.82, -73.25] } } }]);
  fs('user_file_assets', [{ id: 'fa1', data: { ownerId: 'uidAna', storagePath: 'user-files/uidAna/observations/extra.jpg', contentType: 'image/jpeg' } }]);
  fs('reports', [{ id: 'r1', data: { userId: 'uidAna', userEmail: 'ana@example.test', message: 'Hola' } }]);
  fs('coleccion_nueva', [{ id: 'x1', data: { a: 1 } }]);
  return dir;
}
