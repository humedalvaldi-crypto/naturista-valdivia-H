import { z } from 'zod';

const trimmedOrNull = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((v) => (v.length === 0 ? null : v))
    .nullable();

/** Nombre de usuario: 3–30 caracteres, minúsculas, números, punto y guion bajo. */
export const usernameSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(/^[a-z0-9](?:[a-z0-9._]{1,28})[a-z0-9]$/, 'Usa 3 a 30 letras minúsculas, números, punto o guion bajo.')
  .refine((v) => !/[._]{2}/.test(v), 'No uses dos signos seguidos.');

export const updateProfileSchema = z
  .strictObject({
    username: usernameSchema.nullable().optional(),
    fullName: trimmedOrNull(120).optional(),
    bio: trimmedOrNull(500).optional(),
    location: trimmedOrNull(120).optional(),
    visibility: z.enum(['public', 'followers', 'private']).optional(),
    photoAssetId: z.uuid().nullable().optional(),
    bannerAssetId: z.uuid().nullable().optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: 'Debe incluir al menos un campo.' });

export type UpdateProfileInput = z.infer<typeof updateProfileSchema>;
