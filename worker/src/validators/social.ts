import { z } from 'zod';

const text = (min: number, max: number) => z.string().trim().min(min).max(max);
const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((v) => (v.length === 0 ? null : v))
    .nullable()
    .optional();

export const createPostSchema = z.strictObject({
  body: text(1, 2000),
  mediaAssetId: z.uuid().nullable().optional(),
  communitySlug: z.string().trim().min(3).max(40).nullable().optional(),
  visibility: z.enum(['public', 'followers']).default('public'),
  locationName: optionalText(120),
});

export const updatePostSchema = z
  .strictObject({
    body: text(1, 2000).optional(),
    visibility: z.enum(['public', 'followers']).optional(),
    locationName: optionalText(120),
  })
  .refine((v) => Object.keys(v).length > 0, { message: 'Debe incluir al menos un campo.' });

export const createCommentSchema = z.strictObject({ body: text(1, 1000) });

export const createCommunitySchema = z.strictObject({
  name: text(3, 80),
  slug: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9](?:[a-z0-9-]{1,38})[a-z0-9]$/, 'Usa 3 a 40 letras minúsculas, números o guiones.'),
  description: optionalText(500),
  wetland: optionalText(80),
  photoAssetId: z.uuid().nullable().optional(),
});

export const sendMessageSchema = z.strictObject({ body: text(1, 2000) });

export const openConversationSchema = z.strictObject({ userId: z.string().min(1).max(128) });

export const reportSchema = z.strictObject({
  targetType: z.enum(['post', 'comment', 'user', 'community', 'message']),
  targetId: z.string().min(1).max(128),
  reason: z.enum(['spam', 'abuse', 'inappropriate', 'sensitive_location', 'misinformation', 'other']),
  details: optionalText(1000),
});

export const markReadSchema = z.strictObject({ ids: z.array(z.uuid()).max(100).optional() });
