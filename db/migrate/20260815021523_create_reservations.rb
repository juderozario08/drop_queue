class CreateReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :reservations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :status, default: "held", null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end
    
    add_index :reservations, [:user_id, :product_id, :status], unique: true, where: "status = 'held'"
  end
end
