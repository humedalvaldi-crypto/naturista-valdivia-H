import { z } from 'zod';
import { badRequest } from '../services/http-error';

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((v) => (v.length === 0 ? null : v))
    .nullable()
    .optional();

/** Fecha y hora ISO 8601; no se aceptan observaciones del futuro (con 1 día de margen por zonas horarias). */
const observedAt = z.iso.datetime({ offset: true }).refine((v) => Date.parse(v) <= Date.now() + 24 * 3600 * 1000, {
  message: 'La fecha no puede estar en el futuro.',
});

export const createObservationSchema = z
  .strictObject({
    speciesId: z.string().max(80).nullable().optional(),
    taxonName: optionalText(120),
    count: z.number().int().min(1).max(100_000).nullable().optional(),
    observedAt,
    latitude: z.number().finite().min(-90).max(90),
    longitude: z.number().finite().min(-180).max(180),
    accuracyM: z.number().finite().min(0).max(100_000).nullable().optional(),
    locationSource: z.enum(['gps', 'manual']).default('manual'),
    locationName: optionalText(120),
    geoprivacy: z.enum(['open', 'obscured']).default('open'),
    notes: optionalText(2000),
    photoAssetId: z.uuid().nullable().optional(),
    visibility: z.enum(['public', 'private']).default('public'),
  })
  .refine((v) => v.speciesId || v.taxonName, { message: 'Indica la especie o un nombre.', path: ['taxonName'] });

export const updateObservationSchema = z
  .strictObject({
    speciesId: z.string().max(80).nullable().optional(),
    taxonName: optionalText(120),
    count: z.number().int().min(1).max(100_000).nullable().optional(),
    observedAt: observedAt.optional(),
    latitude: z.number().finite().min(-90).max(90).optional(),
    longitude: z.number().finite().min(-180).max(180).optional(),
    accuracyM: z.number().finite().min(0).max(100_000).nullable().optional(),
    locationSource: z.enum(['gps', 'manual']).optional(),
    locationName: optionalText(120),
    geoprivacy: z.enum(['open', 'obscured']).optional(),
    notes: optionalText(2000),
    photoAssetId: z.uuid().nullable().optional(),
    visibility: z.enum(['public', 'private']).optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: 'Debe incluir al menos un campo.' })
  .refine((v) => (v.latitude === undefined) === (v.longitude === undefined), { message: 'Latitud y longitud van juntas.' });

export type CreateObservationInput = z.infer<typeof createObservationSchema>;

/** bbox=oeste,sur,este,norte (grados). */
export function parseBbox(raw: string | undefined): { w: number; s: number; e: number; n: number } | null {
  if (raw === undefined) return null;
  const parts = raw.split(',').map(Number);
  const invalid = () => badRequest('`bbox` debe ser oeste,sur,este,norte en grados.');
  if (parts.length !== 4 || parts.some((p) => !Number.isFinite(p))) throw invalid();
  const [w, s, e, n] = parts as [number, number, number, number];
  if (s < -90 || n > 90 || s > n || w < -180 || e > 180 || w > e) throw invalid();
  return { w, s, e, n };
}

export const TAXON_GROUPS = ['aves', 'mamiferos', 'anfibios', 'reptiles', 'peces', 'insectos', 'flora', 'funga', 'otros'] as const;
