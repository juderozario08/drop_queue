class ReserveInventoryService
  class InventoryDepletedError < StandardError; end

  def self.call(user:, product:)
    Reservation.transaction do
      # Lock the specific product row in the DB until this transaction completes
      product.lock! 
      
      if product.available_inventory > 0
        reservation = Reservation.create!(
          user: user,
          product: product,
          status: "held",
          expires_at: 5.minutes.from_now
        )
        
        # Increment the reserved count safely inside the lock
        product.increment!(:reserved_inventory)
        
        # Enqueue the TTL Job to expire this reservation if not bought (Will be implemented in Step 5)
        # ReleaseReservationJob.set(wait: 5.minutes).perform_later(reservation.id)
        
        # Broadcast the new inventory count via Turbo Streams (Will be implemented in Step 6)
        # broadcast_inventory_update(product)
        
        return reservation
      else
        raise InventoryDepletedError, "Sold Out"
      end
    end
  end
end
