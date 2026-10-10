-- Fase 5: red social. Todas las tablas guardan `legacy_id` cuando el dato
-- proviene de Firestore, para migrar sin perder referencias (Fase 8).

-- Seguidores. Firestore: follows/{follower}_{followed}.
CREATE TABLE follows (
  follower_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  followed_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (follower_id, followed_id),
  CHECK (follower_id <> followed_id)
);
CREATE INDEX idx_follows_followed ON follows (followed_id, created_at DESC);

-- Bloqueos: quien bloquea deja de ver y ser visto, y no puede recibir mensajes ni comentarios.
CREATE TABLE blocks (
  blocker_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
CREATE INDEX idx_blocks_blocked ON blocks (blocked_id);

-- Comunidades. Firestore: groups, group_members.
CREATE TABLE communities (
  id             TEXT PRIMARY KEY,
  slug           TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK (length(slug) BETWEEN 3 AND 40),
  name           TEXT NOT NULL CHECK (length(name) BETWEEN 3 AND 80),
  description    TEXT CHECK (description IS NULL OR length(description) <= 500),
  wetland        TEXT CHECK (wetland IS NULL OR length(wetland) <= 80),
  photo_asset_id TEXT REFERENCES media_assets (id) ON DELETE SET NULL,
  created_by     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  member_count   INTEGER NOT NULL DEFAULT 0 CHECK (member_count >= 0),
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  legacy_id      TEXT UNIQUE
);

CREATE TABLE community_members (
  community_id TEXT NOT NULL REFERENCES communities (id) ON DELETE CASCADE,
  user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  role         TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'moderator', 'member')),
  joined_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (community_id, user_id)
);
CREATE INDEX idx_members_user ON community_members (user_id);

-- Publicaciones. Firestore: posts.
CREATE TABLE posts (
  id             TEXT PRIMARY KEY,
  author_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  body           TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 2000),
  media_asset_id TEXT REFERENCES media_assets (id) ON DELETE SET NULL,
  community_id   TEXT REFERENCES communities (id) ON DELETE CASCADE,
  visibility     TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'followers')),
  location_name  TEXT CHECK (location_name IS NULL OR length(location_name) <= 120),
  comment_count  INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
  reaction_count INTEGER NOT NULL DEFAULT 0 CHECK (reaction_count >= 0),
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at     TEXT,
  legacy_id      TEXT UNIQUE
);
CREATE INDEX idx_posts_created ON posts (created_at DESC, id DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_author ON posts (author_id, created_at DESC, id DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_community ON posts (community_id, created_at DESC, id DESC) WHERE deleted_at IS NULL;

CREATE TABLE comments (
  id         TEXT PRIMARY KEY,
  post_id    TEXT NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
  author_id  TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  body       TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 1000),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  legacy_id  TEXT UNIQUE
);
CREATE INDEX idx_comments_post ON comments (post_id, created_at, id) WHERE deleted_at IS NULL;

-- "Me gusta": una reacción por persona y publicación.
CREATE TABLE reactions (
  post_id    TEXT NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  kind       TEXT NOT NULL DEFAULT 'like' CHECK (kind IN ('like')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (post_id, user_id)
);

-- Guardados (favoritos).
CREATE TABLE bookmarks (
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  post_id    TEXT NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (user_id, post_id)
);

-- Mensajería privada 1 a 1. user_a < user_b para que el par sea único.
CREATE TABLE conversations (
  id              TEXT PRIMARY KEY,
  user_a          TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  user_b          TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  last_message_at TEXT,
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  legacy_chat_id  TEXT UNIQUE,
  UNIQUE (user_a, user_b),
  CHECK (user_a < user_b)
);
CREATE INDEX idx_conv_a ON conversations (user_a, last_message_at DESC);
CREATE INDEX idx_conv_b ON conversations (user_b, last_message_at DESC);

CREATE TABLE messages (
  id              TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
  sender_id       TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  body            TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 2000),
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  read_at         TEXT,
  legacy_id       TEXT UNIQUE
);
CREATE INDEX idx_messages_conv ON messages (conversation_id, created_at DESC, id DESC);

-- Notificaciones guardadas en el servidor.
CREATE TABLE notifications (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  actor_id   TEXT REFERENCES users (id) ON DELETE CASCADE,
  type       TEXT NOT NULL CHECK (type IN ('follow', 'comment', 'reaction', 'message', 'community_join', 'system')),
  post_id    TEXT REFERENCES posts (id) ON DELETE CASCADE,
  conversation_id TEXT REFERENCES conversations (id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  read_at    TEXT,
  legacy_id  TEXT UNIQUE
);
CREATE INDEX idx_notifications_user ON notifications (user_id, created_at DESC, id DESC);

-- Denuncias para moderación.
CREATE TABLE reports (
  id          TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  target_type TEXT NOT NULL CHECK (target_type IN ('post', 'comment', 'user', 'community', 'message')),
  target_id   TEXT NOT NULL,
  reason      TEXT NOT NULL CHECK (reason IN ('spam', 'abuse', 'inappropriate', 'sensitive_location', 'misinformation', 'other')),
  details     TEXT CHECK (details IS NULL OR length(details) <= 1000),
  status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE (reporter_id, target_type, target_id)
);
CREATE INDEX idx_reports_status ON reports (status, created_at);
