class Product < ApplicationRecord
  def available_inventory
    total_inventory - reserved_inventory
  end
end
