class HandleLargeSearchVectors < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION athenas_search_vector() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        BEGIN
          NEW.search_vector := setweight(to_tsvector('public.athenas_portuguese', coalesce(NEW.extracted_text,'')), 'A') ||
            setweight(to_tsvector('public.athenas_portuguese', coalesce(NEW.name,'')), 'B') ||
            setweight(to_tsvector('public.athenas_portuguese', coalesce(NEW.metadata_search_text,'')), 'C');
        EXCEPTION WHEN program_limit_exceeded THEN
          NEW.search_vector := setweight(to_tsvector('public.athenas_portuguese', coalesce(NEW.name,'')), 'B') ||
            setweight(to_tsvector('public.athenas_portuguese', coalesce(NEW.metadata_search_text,'')), 'C');
          NEW.processing_warnings := coalesce(NEW.processing_warnings, '[]'::jsonb) || jsonb_build_array(
            'Conteúdo excede a capacidade do índice lexical do PostgreSQL. Apenas nome/metadados na busca lexical; embeddings disponíveis quando gerados.');
          IF NEW.status IN ('ready','partial') THEN NEW.status := 'partial'; END IF;
        END;
        RETURN NEW;
      END $$;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
