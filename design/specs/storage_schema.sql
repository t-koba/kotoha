-- Logical storage contract. Encrypted persistence is supplied by the storage adapter.
PRAGMA foreign_keys = ON;
BEGIN;
CREATE TABLE storage_capabilities (
 name TEXT PRIMARY KEY,
 contract_json TEXT NOT NULL
);
CREATE TABLE projects (
 project_id TEXT PRIMARY KEY,
 title TEXT NOT NULL,
 retention_policy TEXT NOT NULL CHECK(retention_policy IN ('saved','expires')),
 expires_at TEXT,
 settings_json TEXT NOT NULL,
 created_at TEXT NOT NULL,
 updated_at TEXT NOT NULL,
 CHECK(retention_policy <> 'expires' OR expires_at IS NOT NULL)
);
CREATE TABLE source_assets (
 asset_id TEXT PRIMARY KEY,
 project_id TEXT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
 content_digest TEXT NOT NULL CHECK(length(content_digest)=64),
 media_type TEXT NOT NULL,
 byte_length INTEGER NOT NULL CHECK(byte_length>=0),
 encrypted_blob_ref TEXT,
 permission_ref TEXT,
 metadata_json TEXT NOT NULL,
 UNIQUE(asset_id,project_id)
);
CREATE TABLE model_packages (
 package_id TEXT PRIMARY KEY,
 model_id TEXT NOT NULL,
 manifest_digest TEXT NOT NULL UNIQUE CHECK(length(manifest_digest)=64),
 install_state TEXT NOT NULL,
 descriptor_json TEXT NOT NULL,
 installed_at TEXT
);
CREATE TABLE consent_receipts (
 consent_id TEXT PRIMARY KEY,
 subject_type TEXT NOT NULL,
 subject_ref TEXT NOT NULL,
 terms_digest TEXT NOT NULL CHECK(length(terms_digest)=64),
 purpose TEXT NOT NULL,
 scope_json TEXT NOT NULL,
 accepted_at TEXT NOT NULL,
 withdrawn_at TEXT,
 evidence_json TEXT NOT NULL
);
CREATE TABLE participants (
 participant_id TEXT PRIMARY KEY,
 project_id TEXT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
 display_name TEXT NOT NULL,
 reading_languages_json TEXT NOT NULL,
 display_layout_json TEXT NOT NULL,
 speaker_profile_blob_ref TEXT,
 consent_id TEXT REFERENCES consent_receipts(consent_id),
 UNIQUE(participant_id,project_id),
 CHECK(speaker_profile_blob_ref IS NULL OR consent_id IS NOT NULL)
);
CREATE TABLE segments (
 segment_id TEXT PRIMARY KEY,
 project_id TEXT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
 asset_id TEXT,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0),
 locator_json TEXT NOT NULL,
 participant_id TEXT,
 state TEXT NOT NULL,
 FOREIGN KEY(asset_id,project_id) REFERENCES source_assets(asset_id,project_id),
 FOREIGN KEY(participant_id,project_id) REFERENCES participants(participant_id,project_id),
 UNIQUE(segment_id,project_id)
);
CREATE TABLE segment_snapshots (
 snapshot_id TEXT PRIMARY KEY CHECK(length(snapshot_id)=64),
 segment_id TEXT NOT NULL REFERENCES segments(segment_id) ON DELETE CASCADE,
 parent_snapshot_id TEXT,
 content_digest TEXT NOT NULL CHECK(length(content_digest)=64),
 source_text TEXT NOT NULL,
 source_language TEXT NOT NULL,
 language_annotations_json TEXT NOT NULL,
 origin TEXT NOT NULL,
 recognition_json TEXT NOT NULL,
 created_at TEXT NOT NULL,
 UNIQUE(snapshot_id,segment_id),
 FOREIGN KEY(parent_snapshot_id,segment_id) REFERENCES segment_snapshots(snapshot_id,segment_id)
);
CREATE TABLE segment_heads (
 segment_id TEXT PRIMARY KEY REFERENCES segments(segment_id) ON DELETE CASCADE,
 snapshot_id TEXT NOT NULL,
 FOREIGN KEY(snapshot_id,segment_id) REFERENCES segment_snapshots(snapshot_id,segment_id)
);
CREATE TABLE translations (
 translation_id TEXT PRIMARY KEY,
 snapshot_id TEXT NOT NULL REFERENCES segment_snapshots(snapshot_id) ON DELETE CASCADE,
 target_language TEXT NOT NULL,
 generated_text TEXT NOT NULL,
 edited_text TEXT,
 state TEXT NOT NULL,
 package_id TEXT REFERENCES model_packages(package_id) ON DELETE SET NULL,
 provenance_json TEXT NOT NULL,
 created_at TEXT NOT NULL
);
CREATE TABLE glossaries (
 glossary_id TEXT PRIMARY KEY,
 project_id TEXT REFERENCES projects(project_id) ON DELETE CASCADE,
 title TEXT NOT NULL,
 content_digest TEXT NOT NULL CHECK(length(content_digest)=64)
);
CREATE TABLE glossary_entries (
 entry_id TEXT PRIMARY KEY,
 glossary_id TEXT NOT NULL REFERENCES glossaries(glossary_id) ON DELETE CASCADE,
 source_language TEXT NOT NULL,
 target_language TEXT NOT NULL,
 source_term TEXT NOT NULL,
 target_term TEXT NOT NULL,
 constraints_json TEXT NOT NULL
);
CREATE TABLE translation_memory (
 memory_id TEXT PRIMARY KEY,
 project_id TEXT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
 source_language TEXT NOT NULL,
 target_language TEXT NOT NULL,
 source_text TEXT NOT NULL,
 approved_target_text TEXT NOT NULL,
 approved_at TEXT NOT NULL,
 provenance_json TEXT NOT NULL
);
CREATE TABLE jobs (
 job_id TEXT PRIMARY KEY,
 project_id TEXT REFERENCES projects(project_id) ON DELETE CASCADE,
 parent_job_id TEXT REFERENCES jobs(job_id),
 state TEXT NOT NULL,
 input_fingerprint TEXT NOT NULL,
 plan_json TEXT NOT NULL,
 checkpoint_json TEXT,
 updated_at TEXT NOT NULL
);
CREATE TABLE job_runs (
 job_id TEXT NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
 run_id TEXT NOT NULL,
 state TEXT NOT NULL,
 plan_json TEXT NOT NULL,
 checkpoint_json TEXT,
 PRIMARY KEY(job_id,run_id)
);
CREATE TABLE committed_events (
 job_id TEXT NOT NULL,
 run_id TEXT NOT NULL,
 sequence INTEGER NOT NULL CHECK(sequence>=0),
 event_json TEXT NOT NULL,
 PRIMARY KEY(job_id,run_id,sequence),
 FOREIGN KEY(job_id,run_id) REFERENCES job_runs(job_id,run_id) ON DELETE CASCADE
);
CREATE TABLE evaluation_profiles (
 profile_id TEXT PRIMARY KEY,
 task TEXT NOT NULL,
 capability_conditions_json TEXT NOT NULL,
 language_conditions_json TEXT NOT NULL,
 model_references_json TEXT NOT NULL,
 metrics_json TEXT NOT NULL,
 evidence_json TEXT NOT NULL
);
CREATE INDEX segments_order_idx ON segments(project_id,asset_id,ordinal);
CREATE INDEX translations_target_idx ON translations(snapshot_id,target_language);
CREATE INDEX jobs_state_idx ON jobs(state,updated_at);
COMMIT;
