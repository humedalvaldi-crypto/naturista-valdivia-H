-- "Me gusta" en cuadernos (existían en la app antigua: notebook_likes/{userId}_{notebookId}).
CREATE TABLE notebook_likes (
  notebook_id TEXT NOT NULL REFERENCES notebooks (id) ON DELETE CASCADE,
  user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (notebook_id, user_id)
);
CREATE INDEX idx_notebook_likes_user ON notebook_likes (user_id);

-- Avisos copiados de la app antigua: su texto original y, si lo había, el cuaderno.
ALTER TABLE notifications ADD COLUMN body TEXT;
ALTER TABLE notifications ADD COLUMN notebook_id TEXT REFERENCES notebooks (id) ON DELETE CASCADE;
