-- Fase 7: catálogo de especies, observaciones y lugares del mapa.
-- Firestore: species_catalog, observations, places, wetlands.

CREATE TABLE species (
  id                  TEXT PRIMARY KEY,
  scientific_name     TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK (length(scientific_name) BETWEEN 3 AND 120),
  common_name_es      TEXT CHECK (common_name_es IS NULL OR length(common_name_es) <= 120),
  common_name_en      TEXT CHECK (common_name_en IS NULL OR length(common_name_en) <= 120),
  taxon_group         TEXT NOT NULL CHECK (taxon_group IN ('aves', 'mamiferos', 'anfibios', 'reptiles', 'peces', 'insectos', 'flora', 'funga', 'otros')),
  -- Estado UICN global (LC, NT, VU, EN, CR, DD, NE). El proyecto debe validarlo con la clasificación nacional (RCE).
  conservation_status TEXT NOT NULL DEFAULT 'NE' CHECK (conservation_status IN ('LC', 'NT', 'VU', 'EN', 'CR', 'DD', 'NE')),
  origin              TEXT NOT NULL DEFAULT 'unknown' CHECK (origin IN ('native', 'introduced', 'unknown')),
  -- Especie sensible: la ubicación de sus observaciones se oculta a terceros.
  sensitive           INTEGER NOT NULL DEFAULT 0 CHECK (sensitive IN (0, 1)),
  illustration        TEXT CHECK (illustration IS NULL OR length(illustration) <= 200),
  created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  legacy_id           TEXT UNIQUE
);
CREATE INDEX idx_species_group ON species (taxon_group, common_name_es);

CREATE TABLE observations (
  id              TEXT PRIMARY KEY,
  owner_id        TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  species_id      TEXT REFERENCES species (id) ON DELETE SET NULL,
  -- Nombre libre cuando la especie no está en el catálogo (o no se sabe).
  taxon_name      TEXT CHECK (taxon_name IS NULL OR length(taxon_name) <= 120),
  individual_count INTEGER CHECK (individual_count IS NULL OR individual_count BETWEEN 1 AND 100000),
  observed_at     TEXT NOT NULL,
  -- Ubicación exacta: solo la ve quien observó.
  latitude        REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude       REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  accuracy_m      REAL CHECK (accuracy_m IS NULL OR accuracy_m BETWEEN 0 AND 100000),
  location_source TEXT NOT NULL DEFAULT 'manual' CHECK (location_source IN ('gps', 'manual')),
  location_name   TEXT CHECK (location_name IS NULL OR length(location_name) <= 120),
  -- Ubicación pública: igual a la exacta, o el centro de una celda de 0,1° si está oculta.
  public_latitude  REAL NOT NULL,
  public_longitude REAL NOT NULL,
  obscured        INTEGER NOT NULL DEFAULT 0 CHECK (obscured IN (0, 1)),
  geoprivacy      TEXT NOT NULL DEFAULT 'open' CHECK (geoprivacy IN ('open', 'obscured')),
  notes           TEXT CHECK (notes IS NULL OR length(notes) <= 2000),
  photo_asset_id  TEXT REFERENCES media_assets (id) ON DELETE SET NULL,
  visibility      TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'private')),
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at      TEXT,
  legacy_id       TEXT UNIQUE,
  CHECK (species_id IS NOT NULL OR taxon_name IS NOT NULL)
);
CREATE INDEX idx_obs_public_geo ON observations (public_latitude, public_longitude) WHERE deleted_at IS NULL;
CREATE INDEX idx_obs_owner ON observations (owner_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_obs_species ON observations (species_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_obs_created ON observations (created_at DESC, id DESC) WHERE deleted_at IS NULL;

-- Lugares del mapa (humedales, senderos, miradores). Se cargan desde
-- Firestore (places, wetlands) en la migración; sin datos inventados.
CREATE TABLE places (
  id          TEXT PRIMARY KEY,
  kind        TEXT NOT NULL CHECK (kind IN ('wetland', 'trail', 'viewpoint', 'other')),
  name        TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  description TEXT CHECK (description IS NULL OR length(description) <= 2000),
  latitude    REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude   REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  -- Contorno opcional en GeoJSON (Polygon/MultiPolygon/LineString).
  geojson     TEXT CHECK (geojson IS NULL OR json_valid(geojson)),
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  legacy_id   TEXT UNIQUE
);
CREATE INDEX idx_places_geo ON places (latitude, longitude);

-- Catálogo inicial: especies ilustradas en el proyecto y otras frecuentes en
-- los humedales de Valdivia. Estado = UICN global; revisar con el equipo.
INSERT INTO species (id, scientific_name, common_name_es, common_name_en, taxon_group, conservation_status, origin, sensitive, illustration) VALUES
  ('sp-scelorchilus-rubecula', 'Scelorchilus rubecula', 'Chucao', 'Chucao tapaculo', 'aves', 'LC', 'native', 0, 'assets/illustrations/aves/chucao.jpg'),
  ('sp-glaucidium-nana', 'Glaucidium nana', 'Chuncho', 'Austral pygmy owl', 'aves', 'LC', 'native', 0, 'assets/illustrations/aves/chuncho.jpg'),
  ('sp-cygnus-melancoryphus', 'Cygnus melancoryphus', 'Cisne de cuello negro', 'Black-necked swan', 'aves', 'LC', 'native', 0, 'assets/illustrations/aves/cisnes.jpg'),
  ('sp-xolmis-pyrope', 'Xolmis pyrope', 'Diucón', 'Fire-eyed diucon', 'aves', 'LC', 'native', 0, 'assets/illustrations/aves/diucon.jpg'),
  ('sp-ardea-alba', 'Ardea alba', 'Garza grande', 'Great egret', 'aves', 'LC', 'native', 0, 'assets/illustrations/aves/garzagrande.jpg'),
  ('sp-mareca-sibilatrix', 'Mareca sibilatrix', 'Pato real', 'Chiloe wigeon', 'aves', 'LC', 'native', 0, 'assets/illustrations/aves/pato_real.jpg'),
  ('sp-hymenops-perspicillatus', 'Hymenops perspicillatus', 'Run-run', 'Spectacled tyrant', 'aves', 'LC', 'native', 0, 'assets/illustrations/aves/runrun.jpg'),
  ('sp-tachuris-rubrigastra', 'Tachuris rubrigastra', 'Siete colores', 'Many-colored rush tyrant', 'aves', 'LC', 'native', 0, 'assets/illustrations/aves/sietecolores_1.jpg'),
  ('sp-theristicus-melanopis', 'Theristicus melanopis', 'Bandurria', 'Black-faced ibis', 'aves', 'LC', 'native', 0, NULL),
  ('sp-fulica-armillata', 'Fulica armillata', 'Tagua', 'Red-gartered coot', 'aves', 'LC', 'native', 0, NULL),
  ('sp-lontra-provocax', 'Lontra provocax', 'Huillín', 'Southern river otter', 'mamiferos', 'EN', 'native', 1, 'assets/illustrations/mamiferos/huillin.jpg'),
  ('sp-myocastor-coypus', 'Myocastor coypus', 'Coipo', 'Coypu', 'mamiferos', 'LC', 'native', 0, NULL),
  ('sp-calyptocephalella-gayi', 'Calyptocephalella gayi', 'Rana chilena', 'Helmeted water toad', 'anfibios', 'VU', 'native', 1, NULL),
  ('sp-pleurodema-thaul', 'Pleurodema thaul', 'Sapito de cuatro ojos', 'Four-eyed frog', 'anfibios', 'LC', 'native', 0, NULL),
  ('sp-bombus-dahlbomii', 'Bombus dahlbomii', 'Abejorro colorado', 'Giant Patagonian bumblebee', 'insectos', 'EN', 'native', 1, 'assets/illustrations/insectos/bombus.webp'),
  ('sp-lapageria-rosea', 'Lapageria rosea', 'Copihue', 'Chilean bellflower', 'flora', 'NE', 'native', 0, 'assets/illustrations/flora/copihue.jpg'),
  ('sp-amanita-muscaria', 'Amanita muscaria', 'Matamoscas', 'Fly agaric', 'funga', 'NE', 'introduced', 0, 'assets/illustrations/funga/amanita.jpg');
