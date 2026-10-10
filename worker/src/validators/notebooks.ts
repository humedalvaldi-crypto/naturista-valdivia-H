import { z } from 'zod';

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((v) => (v.length === 0 ? null : v))
    .nullable()
    .optional();

const hexColor = z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'Color en formato #RRGGBB.');

export const createNotebookSchema = z.strictObject({
  title: z.string().trim().min(1).max(120),
  description: optionalText(500),
  color: hexColor.optional(),
  visibility: z.enum(['private', 'public']).optional(),
});

export const updateNotebookSchema = z
  .strictObject({
    title: z.string().trim().min(1).max(120).optional(),
    description: optionalText(500),
    color: hexColor.optional(),
    visibility: z.enum(['private', 'public']).optional(),
    coverAssetId: z.uuid().nullable().optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: 'Debe incluir al menos un campo.' });

/** Tamaño del lienzo de página en unidades lógicas (proporción A4). */
export const PAGE_WIDTH = 1000;
export const PAGE_HEIGHT = 1414;
export const MAX_ELEMENTS_PER_PAGE = 200;
/** Tope por elemento (un dibujo con muchos trazos puede ser grande). */
export const MAX_ELEMENT_DATA_CHARS = 400_000;
/** Tope del cuerpo de un guardado de página. */
export const MAX_PAGE_BODY_BYTES = 2 * 1024 * 1024;

const coord = z.number().finite().min(-PAGE_WIDTH * 2).max(PAGE_HEIGHT * 3);

export const elementSchema = z.strictObject({
  id: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/),
  type: z.enum(['text', 'photo', 'drawing', 'sticker', 'species', 'coordinates', 'audio']),
  x: coord,
  y: coord,
  width: z.number().finite().positive().max(PAGE_HEIGHT * 3),
  height: z.number().finite().positive().max(PAGE_HEIGHT * 3),
  rotation: z.number().finite().min(-360).max(360).default(0),
  z: z.number().int().min(0).max(10_000).default(0),
  data: z
    .record(z.string(), z.unknown())
    .default({})
    .refine((d) => JSON.stringify(d).length <= MAX_ELEMENT_DATA_CHARS, { message: 'El contenido del elemento es demasiado grande.' }),
  mediaAssetId: z.uuid().nullable().optional(),
});

export type PageElementInput = z.infer<typeof elementSchema>;

export const savePageSchema = z
  .strictObject({
    version: z.number().int().positive(),
    title: optionalText(120),
    pageDate: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/)
      .nullable()
      .optional(),
    locationName: optionalText(120),
    latitude: z.number().min(-90).max(90).nullable().optional(),
    longitude: z.number().min(-180).max(180).nullable().optional(),
    locationSource: z.enum(['gps', 'manual']).nullable().optional(),
    weather: optionalText(80),
    paper: z.enum(['plain', 'lined', 'grid', 'dots']).optional(),
    elements: z.array(elementSchema).max(MAX_ELEMENTS_PER_PAGE),
  })
  .refine((v) => new Set(v.elements.map((e) => e.id)).size === v.elements.length, {
    message: 'Hay elementos con el mismo id.',
    path: ['elements'],
  })
  .refine((v) => (v.latitude == null) === (v.longitude == null), {
    message: 'Latitud y longitud van juntas.',
    path: ['latitude'],
  });

export type SavePageInput = z.infer<typeof savePageSchema>;

export const pageOrderSchema = z.strictObject({ pageIds: z.array(z.string().min(1).max(64)).max(1000) });
