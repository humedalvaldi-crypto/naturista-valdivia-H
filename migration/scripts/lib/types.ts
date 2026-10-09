import type { ReferenceReport } from './reference-check';
import type { CollectionSchema } from './schema-inference';

export interface AuditReport {
  projectId: string;
  generatedAt: string;
  sampleSize: number;
  auth: { users: number; byProvider: Record<string, number>; disabled: number };
  collections: Array<{
    name: string;
    expected: boolean;
    count: number;
    schema: CollectionSchema;
    optionalFields: string[];
    mixedTypeFields: string[];
    uidReferences: Record<string, ReferenceReport>;
    compositeIdMismatches?: number;
  }>;
  unexpectedCollections: string[];
  missingCollections: string[];
  subcollections: Array<{ path: string; parentsSampled: number; docs: number }>;
  storage: { bucket: string; files: number; bytes: number; byPurpose: Record<string, number> } | { error: string };
}
