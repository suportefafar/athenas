class CreateAthenas < ActiveRecord::Migration[8.1]
  def up
    enable_extension "vector"
    enable_extension "unaccent"
    execute "CREATE TEXT SEARCH CONFIGURATION public.athenas_portuguese (COPY = pg_catalog.portuguese)"
    execute "ALTER TEXT SEARCH CONFIGURATION public.athenas_portuguese ALTER MAPPING FOR hword, hword_part, word WITH public.unaccent, portuguese_stem"
    create_table :users do |t|
      t.string :name, null: false
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "user"
      t.string :invitation_digest
      t.datetime :invitation_sent_at
      t.timestamps
    end
    add_index :users, :email_address, unique: true
    add_index :users, :role, unique: true, where: "role = 'admin'", name: "one_admin_only"
    add_check_constraint :users, "role IN ('admin', 'user')", name: "valid_role"
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :expires_at, null: false
      t.timestamps
    end
    create_table :lots do |t|
      t.references :uploader, null: false, foreign_key: { to_table: :users }
      t.string :source_type, null: false, default: "upload"
      t.string :source_identifier
      t.string :name, null: false
      t.string :content_type
      t.bigint :byte_size, null: false
      t.string :checksum
      t.jsonb :metadata, null: false, default: {}
      t.text :metadata_search_text
      t.text :extracted_text
      t.integer :page_count
      t.string :status, null: false, default: "pending"
      t.jsonb :processing_warnings, null: false, default: []
      t.text :processing_error
      t.tsvector :search_vector
      t.datetime :indexed_at
      t.datetime :notified_at
      t.timestamps
    end
    add_index :lots, :search_vector, using: :gin
    add_index :lots, [ :status, :created_at ]
    add_check_constraint :lots, "status IN ('pending','processing','ready','partial','failed','rejected')", name: "valid_status"
    create_table :lot_chunks do |t|
      t.references :lot, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :text, null: false
      t.timestamps
    end
    execute "ALTER TABLE lot_chunks ADD COLUMN embedding vector(1024)"
    add_index :lot_chunks, [ :lot_id, :position ], unique: true
    create_table :lot_accesses do |t|
      t.references :lot, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: true
      t.datetime :accessed_at, null: false
    end
    add_index :lot_accesses, [ :accessed_at, :lot_id ]
    create_table :audit_events do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.jsonb :subject_snapshot, null: false, default: {}
      t.datetime :created_at, null: false
    end
    execute <<~SQL
      CREATE FUNCTION athenas_search_vector() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        NEW.search_vector := setweight(to_tsvector('public.athenas_portuguese', coalesce(NEW.extracted_text,'')), 'A') ||
          setweight(to_tsvector('public.athenas_portuguese', coalesce(NEW.name,'')), 'B') ||
          setweight(to_tsvector('public.athenas_portuguese', coalesce(NEW.metadata_search_text,'')), 'C');
        RETURN NEW;
      END $$;
      CREATE TRIGGER lots_search_vector BEFORE INSERT OR UPDATE OF extracted_text, name, metadata_search_text
      ON lots FOR EACH ROW EXECUTE FUNCTION athenas_search_vector();
    SQL
  end

  def down
    drop_table :audit_events
    drop_table :lot_accesses
    drop_table :lot_chunks
    drop_table :lots
    drop_table :sessions
    drop_table :users
    execute "DROP FUNCTION athenas_search_vector()"
    execute "DROP TEXT SEARCH CONFIGURATION public.athenas_portuguese"
  end
end
