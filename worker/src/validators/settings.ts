import { z } from 'zod';

export const SUPPORTED_LANGUAGES = ['es', 'en'] as const;
export const THEMES = ['system', 'light', 'dark'] as const;

/** Actualización parcial de preferencias. Rechaza campos desconocidos. */
export const updateSettingsSchema = z
  .strictObject({
    language: z.enum(SUPPORTED_LANGUAGES).optional(),
    theme: z.enum(THEMES).optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: 'Debe incluir al menos un campo.' });

export type UpdateSettingsInput = z.infer<typeof updateSettingsSchema>;
