import { describe, expect, it } from 'vitest';
import { addToReport, classifyUid, compositeIdMatches, emptyReferenceReport } from '../scripts/lib/reference-check';

const known = new Set(['uidA', 'uidB']);

describe('classifyUid', () => {
  it('clasifica válidos, marcadores, huérfanos y ausentes', () => {
    expect(classifyUid('uidA', known)).toBe('resolved');
    expect(classifyUid('anon', known)).toBe('placeholder');
    expect(classifyUid('guest', known)).toBe('placeholder');
    expect(classifyUid('borrado', known)).toBe('orphan');
    expect(classifyUid(undefined, known)).toBe('missing');
    expect(classifyUid(42, known)).toBe('missing');
  });

  it('acumula un informe', () => {
    const r = emptyReferenceReport();
    for (const v of ['uidA', 'uidB', 'anon', 'x', null]) addToReport(r, v, known);
    expect(r).toEqual({ checked: 5, resolved: 2, placeholder: 1, orphan: 1, missing: 1 });
  });
});

describe('compositeIdMatches', () => {
  it('valida IDs compuestos como follows/{follower}_{followed}', () => {
    expect(compositeIdMatches('uidA_uidB', ['uidA', 'uidB'])).toBe(true);
    expect(compositeIdMatches('uidB_uidA', ['uidA', 'uidB'])).toBe(false);
    expect(compositeIdMatches('uidA_', ['uidA', ''])).toBe(false);
  });
});
