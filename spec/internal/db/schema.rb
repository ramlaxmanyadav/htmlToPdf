# Only what this gem's own specs exercise: ActiveStorage's own core tables
# (so storage/active_storage_adapter_spec.rb can attach a real blob) plus one
# minimal owning model, `documents`.
ActiveRecord::Schema[8.1].define do
  create_table :documents, force: true

  create_table :active_storage_blobs, force: true do |t|
    t.string   :key,          null: false
    t.string   :filename,     null: false
    t.string   :content_type
    t.text     :metadata
    t.string   :service_name, null: false
    t.bigint   :byte_size,    null: false
    t.string   :checksum
    t.datetime :created_at,   null: false, precision: 6

    t.index [:key], unique: true
  end

  create_table :active_storage_attachments, force: true do |t|
    t.string     :name,     null: false
    t.references :record,   null: false, polymorphic: true, index: false
    t.references :blob,     null: false

    t.datetime :created_at, null: false, precision: 6

    t.index [:record_type, :record_id, :name, :blob_id],
            name: "index_active_storage_attachments_uniqueness", unique: true
    t.foreign_key :active_storage_blobs, column: :blob_id
  end

  create_table :active_storage_variant_records, force: true do |t|
    t.belongs_to :blob, null: false, index: false
    t.string :variation_digest, null: false

    t.index [:blob_id, :variation_digest],
            name: "index_active_storage_variant_records_uniqueness", unique: true
    t.foreign_key :active_storage_blobs, column: :blob_id
  end
end
