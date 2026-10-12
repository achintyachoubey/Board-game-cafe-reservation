-- =====================================================================
-- 13_walkthrough.sql
-- Purpose : End-to-end flow, the 2-minute heart of the viva demo:
--             find a free table -> recommend a game -> book -> check in ->
--             return with missing pieces -> pay -> restock.
--           It looks up every ID itself (no hard-coded 3, 12, 31) and works at
--           any time of day: while the cafe is open (slot start 10:00-21:00)
--           it books a 2-hour Dine_In session starting in the current
--           half-hour; otherwise it runs the same flow on a 1-day Take_Home
--           rental starting now.
-- Run order: after 08_seed.sql (can be run repeatedly)
-- Lab      : Exp 12 (procedures + triggers), Exp 11 (each step is a transaction),
--            Additional Exp 2 (the project's stored-program workflow)
-- =====================================================================
USE boardgame_cafe;

-- 0. When, and which kind of booking ------------------------------------------------
SET @slot  = TIMESTAMP(CURRENT_DATE, SEC_TO_TIME(FLOOR(TIME_TO_SEC(CURRENT_TIME) / 1800) * 1800));
SET @type  = IF(TIME(@slot) BETWEEN '10:00:00' AND '21:00:00', 'Dine_In', 'Take_Home');
SET @start = CAST(IF(@type = 'Dine_In', @slot, DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:00')) AS DATETIME);
SET @end   = IF(@type = 'Dine_In', @start + INTERVAL 2 HOUR, @start + INTERVAL 1 DAY);
SET @party = IF(@type = 'Dine_In', 4, NULL);
SELECT @type AS booking_type, @start AS starts, @end AS ends, @party AS party_size;

-- 1. A member in good standing: Active, valid through the end, owes <= Rs 500,
--    18+ (so Take_Home also works) and holding no other game.
SET @member = NULL;
SELECT c.customer_id INTO @member
  FROM Customers c
 WHERE c.status = 'Active'
   AND c.membership_expiry >= DATE(@end)
   AND fn_customer_balance(c.customer_id) <= 500
   AND fn_customer_age(c.customer_id, CURRENT_DATE) >= 18
   AND NOT EXISTS (SELECT 1 FROM Rentals_Reservations r
                    WHERE r.customer_id = c.customer_id AND r.copy_id IS NOT NULL
                      AND r.status IN ('Reserved', 'Checked_In', 'Overdue'))
 ORDER BY c.customer_id
 LIMIT 1;
SELECT customer_id, CONCAT(first_name, ' ', last_name) AS member, tier_id,
       fn_customer_balance(customer_id) AS balance
  FROM Customers WHERE customer_id = @member;

-- 2. Free tables for 4 (Dine_In only). A CALL's result set cannot be captured
--    into a variable in MySQL, so the first row is picked with the same rule
--    sp_find_free_tables uses (smallest table that fits, then rate, then code).
CALL sp_find_free_tables(4, @start, @end, FALSE);
SET @table = NULL;
SELECT table_id INTO @table
  FROM Cafe_Tables
 WHERE @type = 'Dine_In'
   AND is_active
   AND seating_capacity >= 4
   AND fn_table_is_free(table_id, @start, @end, NULL)
 ORDER BY seating_capacity, hourly_rate, table_code
 LIMIT 1;

-- 3. Game recommendations for 4 players, youngest 16, up to 120 minutes. Take the
--    first recommended game whose copy is on the shelf now (a Rented copy that is
--    free later could be reserved but not checked in - BR-07) and whose box has a
--    component with at least 2 pieces (step 6 reports 2 of them missing).
CALL sp_recommend_games(4, 16, 120, @start, @end);
SET @copy = NULL;
SELECT gc.copy_id INTO @copy
  FROM Board_Games bg
  JOIN Game_Copies gc ON gc.game_id = bg.game_id
 WHERE 4 BETWEEN bg.min_players AND bg.max_players
   AND bg.min_age <= 16
   AND bg.avg_play_minutes <= 120
   AND gc.status = 'Available'
   AND fn_copy_is_free(gc.copy_id, @start, @end, NULL)
   AND EXISTS (SELECT 1 FROM Game_Components gco
                WHERE gco.game_id = bg.game_id AND gco.qty_per_copy >= 2)
 ORDER BY bg.complexity, bg.title, gc.copy_id
 LIMIT 1;
SELECT @member AS member_id, @table AS table_id, @copy AS copy_id;

-- 4. Book it (BR-13/BR-14 in the procedure, BR-01..BR-12 in the trigger)
CALL sp_create_reservation(@member, @type, @table, @copy, @party, @start, @end, @booking);
SELECT booking_id, booking_type, status, customer, table_code, game, barcode,
       reserved_start, reserved_end
  FROM vw_active_bookings WHERE booking_id = @booking;

-- 5. Check in (opens 15 minutes before the start; the copy becomes Rented)
CALL sp_check_in(@booking);
SELECT b.booking_id, b.status, b.checked_in_at, gc.status AS copy_status
  FROM Rentals_Reservations b JOIN Game_Copies gc ON gc.copy_id = b.copy_id
 WHERE b.booking_id = @booking;

-- 6. Return: inspection finds 2 pieces of one component missing
SET @component = NULL;
SELECT component_id INTO @component
  FROM Game_Components
 WHERE game_id = (SELECT game_id FROM Game_Copies WHERE copy_id = @copy)
   AND qty_per_copy >= 2
 ORDER BY component_id
 LIMIT 1;
SET @inspector = NULL;
SELECT staff_id INTO @inspector FROM Staff
 WHERE role = 'Game_Guru' AND is_active ORDER BY staff_id LIMIT 1;
SET @missing = JSON_ARRAY(JSON_OBJECT('component_id', @component, 'qty', 2));
SELECT @component AS component_id, @inspector AS inspector, @missing AS missing_json;
CALL sp_check_out(@booking, @inspector, 'Good', @missing, '2 pieces missing');
SELECT base_charge, discount_amount, late_fee, damage_fee, total_amount
  FROM Rentals_Reservations WHERE booking_id = @booking;
SELECT copy_id, status FROM Game_Copies WHERE copy_id = @copy;          -- Missing_Pieces
SELECT * FROM vw_copies_needing_attention WHERE copy_id = @copy;

-- 7. Pay the full amount (PAY-01/PAY-02 checked by trigger)
SELECT total_amount INTO @due FROM Rentals_Reservations WHERE booking_id = @booking;
CALL sp_record_payment(@booking, @due, 'UPI');
SELECT @due AS paid, fn_customer_balance(@member) AS member_balance_now;

-- 8. Staff replace the pieces: copy back on the shelf
CALL sp_restock_copy(@copy);                                -- copy back to Available
SELECT copy_id, status FROM Game_Copies WHERE copy_id = @copy;

-- 9. The audit trail written by the triggers
SELECT * FROM Booking_Audit_Log WHERE booking_id = @booking; -- Reserved → Checked_In → Completed
