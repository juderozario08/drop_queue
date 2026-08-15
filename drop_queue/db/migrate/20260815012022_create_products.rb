class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :title, null: false
      t.integer :total_inventory, default: 0, null: false
      t.integer :reserved_inventory, default: 0, null: false
      t.integer :price_cents, default: 0, null: false
      t.datetime :drop_time, null: false

      t.timestamps
    end
  end
end
