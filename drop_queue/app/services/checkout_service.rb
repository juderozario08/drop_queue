class CheckoutService
  def self.call(reservation:)
    product = reservation.product
    user = reservation.user

    Reservation.transaction do
      # Lock the product to ensure atomic finalization
      product.lock!

      if reservation.status == "held" && reservation.expires_at > Time.current
        # Update reservation status
        reservation.update!(status: "purchased")

        # Create the final order
        Order.create!(
          user: user,
          product: product,
          reservation: reservation,
          status: "completed"
        )

        # Deduct from both total and reserved inventory
        product.decrement!(:total_inventory)
        product.decrement!(:reserved_inventory)
        
        return true
      else
        return false # Reservation is either expired or already purchased
      end
    end
  end
end
