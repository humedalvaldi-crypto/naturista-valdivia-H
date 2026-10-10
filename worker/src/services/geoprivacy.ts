/**
 * Ubicación pública de una observación. Si está oculta (especie sensible o
 * decisión de quien observa), se publica solo el centro de una celda de
 * 0,1° × 0,1° (≈ 11 × 8,5 km en Valdivia). La ubicación exacta queda solo
 * para quien observó, y las búsquedas de terceros usan siempre la pública,
 * así que acotar el área de búsqueda no revela el punto real.
 */
export const OBSCURE_CELL_DEG = 0.1;

export function cellCenter(value: number, cell = OBSCURE_CELL_DEG): number {
  const center = Math.floor(value / cell) * cell + cell / 2;
  return Math.round(center * 1e6) / 1e6;
}

export function publicLocation(lat: number, lng: number, obscured: boolean): { lat: number; lng: number } {
  if (!obscured) return { lat, lng };
  return { lat: cellCenter(lat), lng: cellCenter(lng) };
}
