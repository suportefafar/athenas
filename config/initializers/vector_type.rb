# pgvector SQL is explicit; Rails stores/reads the validated vector literal as text.
# Registering the type also avoids unknown-OID diagnostics on chunk reads.
ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::OID::TypeMapInitializer.prepend(Module.new do
    def run(records)
      records.each do |row|
        @store.register_type(row["oid"].to_i, ActiveRecord::Type::String.new) if row["typname"] == "vector"
      end
      super
    end
  end)
end
