-- Comunidad de cuadernos: la categoría que tenía la app antigua (p. ej. «Biodiversidad»)
-- y un índice para explorar los cuadernos públicos por fecha de actualización.
ALTER TABLE notebooks ADD COLUMN category TEXT CHECK (category IS NULL OR length(category) <= 40);
CREATE INDEX idx_notebooks_public_updated ON notebooks (updated_at DESC, id DESC) WHERE visibility = 'public' AND deleted_at IS NULL;
