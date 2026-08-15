class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :reservation, null: false, foreign_key: true, index: { unique: true }
      t.string :status, default: "completed", null: false

      t.timestamps
    end
  end
end
