-- Álbum de especies: desbloqueos heredados de la app antigua (Firestore:
-- user_collections.unlockedIds). Los desbloqueos por observaciones se
-- calculan al vuelo desde la tabla observations.
CREATE TABLE species_unlocks (
  user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  species_id  TEXT NOT NULL REFERENCES species (id) ON DELETE CASCADE,
  source      TEXT NOT NULL DEFAULT 'legacy' CHECK (source IN ('legacy')),
  unlocked_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (user_id, species_id)
);
