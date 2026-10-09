import { PLACEHOLDER_UIDS } from './legacy-inventory';

export interface ReferenceReport {
  checked: number;
  /** UID válido que existe en Firebase Auth. */
  resolved: number;
  /** 'anon', 'guest' o vacío: contenido creado sin sesión. */
  placeholder: number;
  /** UID con formato válido que NO existe en Auth (cuenta borrada o dato corrupto). */
  orphan: number;
  /** Ausente o de tipo no cadena. */
  missing: number;
}

export const emptyReferenceReport = (): ReferenceReport => ({
  checked: 0,
  resolved: 0,
  placeholder: 0,
  orphan: 0,
  missing: 0,
});

/**
 * Clasifica el valor de un campo de UID. No conserva los UID huérfanos en el
 * informe: solo los cuenta.
 */
export function classifyUid(value: unknown, knownUids: ReadonlySet<string>): keyof Omit<ReferenceReport, 'checked'> {
  if (typeof value !== 'string') return 'missing';
  if (PLACEHOLDER_UIDS.has(value)) return 'placeholder';
  return knownUids.has(value) ? 'resolved' : 'orphan';
}

export function addToReport(report: ReferenceReport, value: unknown, knownUids: ReadonlySet<string>): ReferenceReport {
  report.checked += 1;
  report[classifyUid(value, knownUids)] += 1;
  return report;
}

/** Comprueba que un ID compuesto `${a}_${b}` coincide con sus campos. */
export function compositeIdMatches(docId: string, parts: unknown[]): boolean {
  if (parts.some((p) => typeof p !== 'string' || p.length === 0)) return false;
  return docId === parts.join('_');
}
