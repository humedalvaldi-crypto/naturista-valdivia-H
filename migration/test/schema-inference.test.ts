import { describe, expect, it } from 'vitest';
import { inferFieldType, inferSchema, mixedTypeFields, optionalFields } from '../scripts/lib/schema-inference';

const fakeTimestamp = { seconds: 1, nanoseconds: 0, toDate: () => new Date(1000) };
const fakeGeo = { latitude: -39.8, longitude: -73.2, isEqual: () => false };
const fakeRef = { id: 'abc', path: 'notebooks/abc', firestore: {} };

describe('inferFieldType', () => {
  it('reconoce tipos de Firestore', () => {
    expect(inferFieldType(null)).toBe('null');
    expect(inferFieldType('x')).toBe('string');
    expect(inferFieldType(1.5)).toBe('number');
    expect(inferFieldType(true)).toBe('boolean');
    expect(inferFieldType([1])).toBe('array');
    expect(inferFieldType(fakeTimestamp)).toBe('timestamp');
    expect(inferFieldType(new Date())).toBe('timestamp');
    expect(inferFieldType(fakeGeo)).toBe('geopoint');
    expect(inferFieldType(fakeRef)).toBe('reference');
    expect(inferFieldType({ a: 1 })).toBe('map');
  });
});

describe('inferSchema', () => {
  const docs = [
    { userId: 'u1', createdAt: fakeTimestamp, imageUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/y', settings: { lang: 'es' } },
    { userId: 'u2', createdAt: 'hoy', imageUrl: 'data:image/png;base64,AAAA' },
  ];
  const schema = inferSchema(docs);

  it('cuenta presencia y tipos por campo, incluidos mapas anidados', () => {
    expect(schema.sampled).toBe(2);
    expect(schema.fields['userId']).toMatchObject({ present: 2, types: { string: 2 } });
    expect(schema.fields['settings.lang']).toMatchObject({ present: 1 });
  });

  it('detecta URLs de Storage e imágenes Base64 incrustadas', () => {
    expect(schema.fields['imageUrl']).toMatchObject({ storageUrls: 1, dataUrls: 1 });
  });

  it('identifica campos opcionales y de tipo mezclado', () => {
    expect(optionalFields(schema)).toContain('settings');
    expect(mixedTypeFields(schema)).toEqual(['createdAt']);
  });

  it('no copia valores al resultado (privacidad)', () => {
    const json = JSON.stringify(inferSchema([{ rut: '12.345.678-5', telefono: '+56911111111' }]));
    expect(json).not.toContain('12.345.678-5');
    expect(json).not.toContain('+56911111111');
  });
});
