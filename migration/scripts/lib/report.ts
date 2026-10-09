import type { AuditReport } from './types';

const fmtBytes = (n: number) =>
  n > 1e9 ? `${(n / 1e9).toFixed(2)} GB` : n > 1e6 ? `${(n / 1e6).toFixed(1)} MB` : `${Math.round(n / 1e3)} KB`;

/** Resumen legible del informe de auditoría (sin valores de documentos). */
export function renderMarkdown(r: AuditReport): string {
  const lines: string[] = [];
  lines.push(`# Auditoría Firestore — ${r.projectId}`, '', `Generado: ${r.generatedAt} · muestra por colección: ${r.sampleSize}`, '');

  lines.push('## Firebase Auth', '', `Usuarios: **${r.auth.users}** (deshabilitados: ${r.auth.disabled})`, '');
  lines.push('| Proveedor | Usuarios |', '|---|---|');
  for (const [p, n] of Object.entries(r.auth.byProvider).sort()) lines.push(`| ${p} | ${n} |`);
  lines.push('');

  lines.push('## Colecciones', '', '| Colección | Docs | Prevista | Campos opcionales | Tipos mezclados | URLs Storage | data: URLs |', '|---|---|---|---|---|---|---|');
  for (const c of r.collections) {
    const storage = Object.values(c.schema.fields).reduce((a, f) => a + f.storageUrls, 0);
    const dataUrls = Object.values(c.schema.fields).reduce((a, f) => a + f.dataUrls, 0);
    lines.push(`| ${c.name} | ${c.count} | ${c.expected ? 'sí' : '**no**'} | ${c.optionalFields.length} | ${c.mixedTypeFields.join(', ') || '—'} | ${storage} | ${dataUrls} |`);
  }
  lines.push('');
  if (r.missingCollections.length) lines.push(`Colecciones del código que no existen en Firestore: ${r.missingCollections.join(', ')}`, '');
  if (r.unexpectedCollections.length) lines.push(`Colecciones no previstas: **${r.unexpectedCollections.join(', ')}**`, '');

  lines.push('## Referencias a usuarios (muestra)', '', '| Colección.campo | Revisados | Válidos | anon/guest | Huérfanos | Ausentes |', '|---|---|---|---|---|---|');
  for (const c of r.collections) {
    for (const [field, ref] of Object.entries(c.uidReferences)) {
      lines.push(`| ${c.name}.${field} | ${ref.checked} | ${ref.resolved} | ${ref.placeholder} | ${ref.orphan} | ${ref.missing} |`);
    }
  }
  lines.push('');

  lines.push('## Subcolecciones', '');
  for (const s of r.subcollections) lines.push(`- ${s.path}: ${s.docs} documentos en ${s.parentsSampled} padres revisados`);
  lines.push('');

  lines.push('## Firebase Storage', '');
  if ('error' in r.storage) {
    lines.push(`No se pudo listar: ${r.storage.error}`);
  } else {
    lines.push(`Bucket \`${r.storage.bucket}\`: ${r.storage.files} archivos, ${fmtBytes(r.storage.bytes)}`, '');
    for (const [p, n] of Object.entries(r.storage.byPurpose).sort()) lines.push(`- ${p}: ${n}`);
  }
  lines.push('');
  return lines.join('\n');
}
