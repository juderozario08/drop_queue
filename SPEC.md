# Technical Specification: DropQueue (Flash Sale Reservation Engine)

**Target Reader:** AI Coding Assistants (Antigravity, Void, Cursor, Windsurf) and Human Engineers.
**Objective:** Scaffold, build, and test a production-grade Flash Sale inventory reservation system using Ruby on Rails. The system must prevent overselling during high-concurrency traffic spikes using database-level locking, manage temporary inventory holds via background jobs, and stream live queue updates to the frontend using WebSockets.

---

## 1. Stack & Architecture Definitions

**Environment & Core Frameworks:**

* **Ruby:** `3.3.0+`
* **Rails:** `8.0+` (Utilizing the new "Solid" defaults).
* **Database:** PostgreSQL (Neon.tech for production, local Postgres/SQLite for dev).
* **Background Jobs:** `Solid Queue` (Database-backed queue, native to Rails 8, replacing Sidekiq/Redis).
* **Real-time WebSockets:** `Solid Cable` (Database-backed ActionCable, replacing Redis).
* **Frontend:** Hotwire (Turbo Streams + Turbo Frames + Stimulus.js) with Tailwind CSS. No React/Vue.

**Infrastructure Constraints:**

* **$0.00 Budget:** The app must not rely on external paid APIs (no Redis, no paid queues). Everything must run through the PostgreSQL database.

---

## 2. Database Schema & Migrations

The AI Assistant should generate migrations for the following models exactly as specified.

### A. `Product`

The item being sold during the flash sale.

* `title` (string, null: false)
* `total_inventory` (integer, default: 0, null: false)
* `reserved_inventory` (integer, default: 0, null: false)
* `price_cents` (integer, default: 0, null: false)
* `drop_time` (datetime, null: false)

*Helper Method to calculate available:*

```ruby
def available_inventory
  total_inventory - reserved_inventory
end

```

### B. `User`

The customer attempting to buy. (Use standard `has_secure_password` for basic auth).

* `email` (string, unique index, null: false)
* `password_digest` (string, null: false)

### C. `Reservation`

The temporary 5-minute hold on a product.

* `user_id` (foreign_key, index: true)
* `product_id` (foreign_key, index: true)
* `status` (string, default: "held") - Enum: `held`, `purchased`, `expired`
* `expires_at` (datetime, null: false)
* *Index:* `add_index :reservations, [:user_id, :product_id, :status], unique: true, conditions: "status = 'held'"` (Prevents a user from holding the same item twice).

### D. `Order`

The final finalized purchase.

* `user_id` (foreign_key)
* `product_id` (foreign_key)
* `reservation_id` (foreign_key, unique index)
* `status` (string, default: "completed")

---

## 3. Core Business Logic (The AI Implementation Guide)

The AI assistant must implement the following specific patterns to handle concurrency safely.

### 3.1. The Concurrency Lock (PostgreSQL Row-Level Locking)

When a user clicks "Reserve", the app must use `with_lock` (which translates to PostgreSQL's `SELECT FOR UPDATE`). This prevents race conditions when 100 users hit the exact same product row simultaneously.

**File:** `app/services/reserve_inventory_service.rb`

```ruby
class ReserveInventoryService
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
        
        # Enqueue the TTL Job to expire this reservation if not bought
        ReleaseReservationJob.set(wait: 5.minutes).perform_later(reservation.id)
        
        # Broadcast the new inventory count via Turbo Streams
        broadcast_inventory_update(product)
        
        return reservation
      else
        raise InventoryDepletedError, "Sold Out"
      end
    end
  end
end

```

### 3.2. The Time-to-Live (TTL) Background Job

If the user does not complete checkout in 5 minutes, the reservation expires and inventory is returned to the pool.

**File:** `app/jobs/release_reservation_job.rb`

```ruby
class ReleaseReservationJob < ApplicationJob
  queue_as :default

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return unless reservation&.status == "held"

    Reservation.transaction do
      reservation.product.lock! # Lock again to prevent race conditions during release
      
      # Double check it wasn't purchased in the last millisecond
      if reservation.reload.status == "held"
        reservation.update!(status: "expired")
        reservation.product.decrement!(:reserved_inventory)
        
        # Broadcast the updated (increased) inventory count
        ProductChannel.broadcast_update_to(reservation.product, ...)
      end
    end
  end
end

```

### 3.3. Finalizing the Checkout

When the user "pays", convert the reservation to an order.

**File:** `app/services/checkout_service.rb`

* Find the `Reservation` where status is `held`.
* Inside a `.transaction` and `product.lock!`:
* Change reservation status to `purchased`.
* Create the `Order`.
* Decrement *both* `total_inventory` and `reserved_inventory` by 1.



---

## 4. Real-Time WebSockets (Hotwire)

The frontend must dynamically update the inventory count and the user's queue/cart status without JavaScript SPAs. The IDE should configure:

1. **Model Broadcasts:** In `app/models/product.rb`, add:
```ruby
broadcasts_to ->(product) { "product_#{product.id}_inventory" }, inserts_by: :replace

```


2. **View Listeners:** In `app/views/products/show.html.erb`:
```erb
<%= turbo_stream_from "product_#{@product.id}_inventory" %>
<div id="product_<%= @product.id %>">
  Available: <%= @product.available_inventory %>
</div>

```



---

## 5. Automated Testing Plan (Minitest)

The AI assistant MUST generate a concurrency test to prove the locking mechanism works. This is the most critical part of the portfolio piece.

**File:** `test/services/reserve_inventory_service_test.rb`
The test must spawn multiple Ruby threads to simulate concurrent web requests.

```ruby
require "test_helper"

class ReserveInventoryServiceTest < ActiveSupport::TestCase
  test "prevents overselling when multiple threads attempt to reserve simultaneously" do
    product = products(:limited_sneaker) # Assume total_inventory is 2, reserved is 0
    users = create_list_of_users(5)
    
    # Spawn 5 parallel threads hitting the database at the exact same millisecond
    threads = users.map do |user|
      Thread.new do
        begin
          ReserveInventoryService.call(user: user, product: product)
        rescue InventoryDepletedError
          # Expected for 3 out of 5 threads
        end
      end
    end
    
    threads.each(&:join)
    
    product.reload
    assert_equal 2, product.reserved_inventory
    assert_equal 0, product.available_inventory
    assert_equal 2, Reservation.where(status: "held").count
  end
end

```

---

## 6. IDE Execution Steps

**For the AI Assistant reading this document:**
Execute the following steps sequentially, verifying tests pass at each milestone.

1. **Initialization:** `rails new drop_queue --css tailwind --database postgresql`
2. **Ensure Solid Queue & Cable:** Verify `config/queue.yml` and `config/cable.yml` are using the DB adapter (Rails 8 default).
3. **Generate Models:** Run Rails generators for `User`, `Product`, `Reservation`, and `Order` utilizing the schema in Section 2. Run `rails db:migrate`.
4. **Implement Services:** Create `app/services/` directory. Implement `ReserveInventoryService` and `CheckoutService` with `product.lock!` transactions.
5. **Implement Background Jobs:** Generate `ReleaseReservationJob` and implement the expiration logic.
6. **Hotwire UI:** Scaffold the `ProductsController#show` view. Add `turbo_stream_from` tags and the reserve button.
7. **Concurrency Testing:** Write the threaded `Minitest` suite in Section 5. Run `bin/rails test`. If it fails (oversells), the PostgreSQL lock is implemented incorrectly. Stop and fix the lock.

---

**End of Specification**