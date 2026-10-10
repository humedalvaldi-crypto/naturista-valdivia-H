import { z } from 'zod';

export const SUPPORTED_LANGUAGES = ['es', 'en'] as const;
export const THEMES = ['system', 'light', 'dark'] as const;

/** Actualización parcial de preferencias. Rechaza campos desconocidos. */
export const NOTIFICATION_KINDS = ['follow', 'comment', 'reaction', 'message'] as const;
export const MESSAGE_POLICIES = ['everyone', 'following', 'nobody'] as const;

export const updateSettingsSchema = z
  .strictObject({
    language: z.enum(SUPPORTED_LANGUAGES).optional(),
    theme: z.enum(THEMES).optional(),
    /** Qué avisos crear para esta persona (por defecto, todos). */
    notifications: z
      .strictObject(Object.fromEntries(NOTIFICATION_KINDS.map((k) => [k, z.boolean().optional()])) as Record<(typeof NOTIFICATION_KINDS)[number], z.ZodOptional<z.ZodBoolean>>)
      .optional(),
    /** Quién puede escribirle mensajes. */
    privacy: z.strictObject({ messages: z.enum(MESSAGE_POLICIES).optional() }).optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: 'Debe incluir al menos un campo.' });

export type UpdateSettingsInput = z.infer<typeof updateSettingsSchema>;

export const feedbackSchema = z.strictObject({
  kind: z.enum(['bug', 'idea', 'question', 'other']),
  message: z.string().trim().min(1).max(2000),
  appVersion: z.string().trim().max(40).optional(),
  platform: z.string().trim().max(40).optional(),
});
