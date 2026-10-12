-- =====================================================================
-- 03_procedures.sql
-- Purpose : The 11 stored procedures. sp_validate_booking (Appendix B.2)
--           comes first because the triggers in 04 call it; the workflow
--           procedures (Appendix B.4) follow.
-- Run order: 03 (after 02_functions.sql, before 04_triggers.sql)
-- Lab      : Exp 12 (stored procedures), Exp 11 (transactions inside
--            procedures), Additional Exp 1 (cursor: sp_flag_suspensions),
--            Additional Exp 2 (PL/SQL-style programs for the project)
-- =====================================================================
USE boardgame_cafe;

-- ---------------------------------------------------------------------
-- sp_validate_booking  (Appendix B.2)
-- Purpose   : Row-level rules shared by trg_rr_before_insert and
--             trg_rr_before_update. Checks that must hold for every row
--             (shape, durations, capacity, players, age, hours) always run;
--             overlap / availability / concurrency checks run only when the
--             row is active (Reserved, Checked_In, Overdue), so historical
--             rows load cleanly.
-- Parameters: p_booking_id (NULL on insert; the row itself on update),
--             p_customer_id, p_table_id, p_copy_id, p_type, p_party,
--             p_start, p_end, p_status
-- Rules     : BR-01, BR-02, BR-03, BR-04, BR-05, BR-06, BR-07, BR-08,
--             BR-10, BR-11, BR-12
-- Errors    : SQLSTATE 45000 'BR-xx: ...'
-- Lab       : Exp 12
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_validate_booking(
    IN p_booking_id INT UNSIGNED, IN p_customer_id INT UNSIGNED,
    IN p_table_id SMALLINT UNSIGNED, IN p_copy_id INT UNSIGNED,
    IN p_type VARCHAR(10), IN p_party TINYINT UNSIGNED,
    IN p_start DATETIME, IN p_end DATETIME, IN p_status VARCHAR(12))
READS SQL DATA
BEGIN
  DECLARE v_active BOOLEAN DEFAULT p_status IN ('Reserved','Checked_In','Overdue');
  DECLARE v_age INT;
  DECLARE v_capacity, v_min_players, v_max_players, v_min_age TINYINT UNSIGNED;
  DECLARE v_table_in_service BOOLEAN;
  DECLARE v_copy_status VARCHAR(20);
  DECLARE v_max_hours, v_max_days, v_max_rentals TINYINT UNSIGNED;
  DECLARE v_open_rentals INT;

  IF (p_type = 'Dine_In'   AND (p_table_id IS NULL OR p_party IS NULL))
  OR (p_type = 'Take_Home' AND (p_copy_id IS NULL OR p_table_id IS NOT NULL OR p_party IS NOT NULL)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: booking type does not match table/copy/party fields';
  END IF;

  SELECT t.max_session_hours, t.max_takehome_days, t.max_concurrent_rentals
    INTO v_max_hours, v_max_days, v_max_rentals
    FROM Customers c JOIN Membership_Tiers t ON t.tier_id = c.tier_id
   WHERE c.customer_id = p_customer_id;
  SET v_age = fn_customer_age(p_customer_id, DATE(p_start));

  IF p_type = 'Dine_In' AND TIMESTAMPDIFF(MINUTE, p_start, p_end) > v_max_hours * 60 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-11: session longer than the membership tier allows';
  END IF;
  IF p_type = 'Take_Home' AND TIMESTAMPDIFF(MINUTE, p_start, p_end) > v_max_days * 1440 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-11: take-home rental longer than the membership tier allows';
  END IF;

  IF p_table_id IS NOT NULL THEN
    SELECT seating_capacity, is_active INTO v_capacity, v_table_in_service
      FROM Cafe_Tables WHERE table_id = p_table_id;
    IF NOT v_table_in_service THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-01: table is out of service';
    END IF;
    IF p_party > v_capacity THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-01: party size exceeds table seating capacity';
    END IF;
    IF DATE(p_start) <> DATE(p_end) OR TIME(p_start) < '10:00:00' OR TIME(p_end) > '23:00:00' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-10: booking outside opening hours (10:00-23:00)';
    END IF;
    IF v_active AND NOT fn_table_is_free(p_table_id, p_start, p_end, p_booking_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-05: table already booked for an overlapping time';
    END IF;
  END IF;

  IF p_copy_id IS NOT NULL THEN
    SELECT gc.status, bg.min_players, bg.max_players, bg.min_age
      INTO v_copy_status, v_min_players, v_max_players, v_min_age
      FROM Game_Copies gc JOIN Board_Games bg ON bg.game_id = gc.game_id
     WHERE gc.copy_id = p_copy_id;
    IF v_active AND v_copy_status IN ('Retired','Under_Repair','Missing_Pieces') THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-07: game copy is not available for booking';
    END IF;
    IF p_type = 'Dine_In' AND (p_party < v_min_players OR p_party > v_max_players) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-02: party size outside the game player range';
    END IF;
    IF v_age < v_min_age THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-03: customer is below the game minimum age';
    END IF;
    IF p_type = 'Take_Home' AND v_age < 18 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-04: take-home rentals require age 18+';
    END IF;
    IF v_active THEN
      IF NOT fn_copy_is_free(p_copy_id, p_start, p_end, p_booking_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-06: game copy already booked for an overlapping time';
      END IF;
      SELECT COUNT(*) INTO v_open_rentals FROM Rentals_Reservations
       WHERE customer_id = p_customer_id AND copy_id IS NOT NULL
         AND status IN ('Reserved','Checked_In','Overdue')
         AND booking_id <> IFNULL(p_booking_id, 0);
      IF v_open_rentals >= v_max_rentals THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-12: concurrent rental limit for the membership tier reached';
      END IF;
    END IF;
  END IF;
END$$
DELIMITER ;

DELIMITER $$

-- ---------------------------------------------------------------------
-- sp_create_reservation  (Appendix B.4)
-- Purpose   : The only way the front desk creates a booking.
--             Concurrency: runs at READ COMMITTED and locks the contested
--             rows FOR UPDATE in a fixed order (table -> copy -> customer)
--             BEFORE any plain read. A second session booking the same
--             table waits on the row lock; when the first commits, the
--             second's overlap check (a fresh READ COMMITTED read inside the
--             trigger) sees the committed booking and fails with BR-05.
--             The fixed lock order prevents deadlocks between bookings.
-- Parameters: p_customer_id, p_type, p_table_id, p_copy_id, p_party,
--             p_start, p_end; OUT p_booking_id
-- Rules     : BR-13, BR-14 here; BR-01..BR-12 via trg_rr_before_insert
-- Errors    : 45000 'BR-13: ...', 'BR-14: ...', plus any trigger error
--             (re-signalled after ROLLBACK)
-- Lab       : Exp 11 (transaction), Exp 12
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_create_reservation(
    IN p_customer_id INT UNSIGNED, IN p_type VARCHAR(10), IN p_table_id SMALLINT UNSIGNED,
    IN p_copy_id INT UNSIGNED, IN p_party TINYINT UNSIGNED,
    IN p_start DATETIME, IN p_end DATETIME, OUT p_booking_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE v_lock INT;
  DECLARE v_status VARCHAR(12);
  DECLARE v_expiry DATE;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  -- 1. Lock the contested resources first (fixed order: table, copy, customer)
  IF p_table_id IS NOT NULL THEN
    SELECT table_id INTO v_lock FROM Cafe_Tables WHERE table_id = p_table_id FOR UPDATE;
  END IF;
  IF p_copy_id IS NOT NULL THEN
    SELECT copy_id INTO v_lock FROM Game_Copies WHERE copy_id = p_copy_id FOR UPDATE;
  END IF;
  SELECT status, membership_expiry INTO v_status, v_expiry
    FROM Customers WHERE customer_id = p_customer_id FOR UPDATE;
  -- 2. Account rules (BR-13) and time rules (BR-14)
  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-13: customer not found';
  END IF;
  IF v_status <> 'Active' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-13: customer account is not active';
  END IF;
  IF v_expiry < DATE(p_end) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-13: membership expires before the booking ends';
  END IF;
  IF fn_customer_balance(p_customer_id) > 500 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-13: outstanding balance above Rs 500';
  END IF;
  IF p_start < NOW() - INTERVAL 30 MINUTE THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-14: booking cannot start in the past';
  END IF;
  IF p_start > NOW() + INTERVAL 14 DAY THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-14: bookings open only 14 days ahead';
  END IF;
  -- 3. Insert; the BEFORE INSERT trigger enforces BR-01..BR-12 and prices the row
  INSERT INTO Rentals_Reservations (customer_id, table_id, copy_id, booking_type,
                                    party_size, reserved_start, reserved_end)
  VALUES (p_customer_id, p_table_id, p_copy_id, p_type, p_party, p_start, p_end);
  SET p_booking_id = LAST_INSERT_ID();
  COMMIT;
END$$

-- ---------------------------------------------------------------------
-- sp_check_in
-- Purpose   : Reserved -> Checked_In. Opens 15 minutes before the start.
--             A reserved copy must be back on the shelf (Available).
-- Parameters: p_booking_id
-- Rules     : BR-15, BR-07
-- Errors    : 45000 'BR-15: ...', 'BR-07: game copy is not back on the shelf yet'
-- Lab       : Exp 11, Exp 12
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_check_in(IN p_booking_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE v_status VARCHAR(12);
  DECLARE v_start DATETIME;
  DECLARE v_copy INT UNSIGNED;
  DECLARE v_copy_status VARCHAR(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT status, reserved_start, copy_id INTO v_status, v_start, v_copy
    FROM Rentals_Reservations WHERE booking_id = p_booking_id FOR UPDATE;
  IF v_status IS NULL OR v_status <> 'Reserved' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-15: only Reserved bookings can be checked in';
  END IF;
  IF NOW() < v_start - INTERVAL 15 MINUTE THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-15: check-in opens 15 minutes before start';
  END IF;
  IF v_copy IS NOT NULL THEN
    SELECT status INTO v_copy_status FROM Game_Copies WHERE copy_id = v_copy FOR UPDATE;
    IF v_copy_status <> 'Available' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-07: game copy is not back on the shelf yet';
    END IF;
  END IF;
  UPDATE Rentals_Reservations SET status = 'Checked_In', checked_in_at = NOW()
   WHERE booking_id = p_booking_id;
  COMMIT;
END$$

-- ---------------------------------------------------------------------
-- sp_check_out
-- Purpose   : Close a Checked_In/Overdue booking in ONE transaction:
--             inspection row, missing pieces (JSON array parsed with
--             JSON_TABLE), late fee, status Completed. Any error rolls the
--             whole thing back (EXIT HANDLER: ROLLBACK; RESIGNAL).
-- Parameters: p_booking_id, p_staff_id (inspector), p_condition,
--             p_missing JSON e.g. '[{"component_id": 12, "qty": 2}]' or NULL,
--             p_notes
-- Rules     : BR-15, BR-16, BR-17, BR-18 (via inspection/missing-piece triggers)
-- Errors    : 45000 'BR-15: ...', 'BR-17: ...'
-- Lab       : Exp 11 (atomicity), Exp 12
-- ---------------------------------------------------------------------
-- p_missing example: '[{"component_id": 12, "qty": 2}, {"component_id": 14, "qty": 1}]'
CREATE PROCEDURE sp_check_out(
    IN p_booking_id INT UNSIGNED, IN p_staff_id SMALLINT UNSIGNED,
    IN p_condition VARCHAR(10), IN p_missing JSON, IN p_notes VARCHAR(255))
MODIFIES SQL DATA
BEGIN
  DECLARE v_status VARCHAR(12);
  DECLARE v_copy, v_inspection INT UNSIGNED;
  DECLARE v_now DATETIME DEFAULT NOW();
  DECLARE v_late DECIMAL(10,2);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
  SELECT status, copy_id INTO v_status, v_copy
    FROM Rentals_Reservations WHERE booking_id = p_booking_id FOR UPDATE;
  IF v_status IS NULL OR v_status NOT IN ('Checked_In','Overdue') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-15: only Checked_In or Overdue bookings can be checked out';
  END IF;
  IF v_copy IS NOT NULL THEN
    IF p_staff_id IS NULL OR p_condition IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-17: returned game needs an inspector and a condition';
    END IF;
    INSERT INTO Return_Inspections (booking_id, inspected_by, inspected_at, condition_on_return, notes)
    VALUES (p_booking_id, p_staff_id, v_now, p_condition, p_notes);
    SET v_inspection = LAST_INSERT_ID();
    IF p_missing IS NOT NULL AND JSON_LENGTH(p_missing) > 0 THEN
      INSERT INTO Missing_Pieces (inspection_id, component_id, qty_missing, charge)
      SELECT v_inspection, jt.component_id, jt.qty, 0
        FROM JSON_TABLE(p_missing, '$[*]' COLUMNS (
               component_id INT UNSIGNED      PATH '$.component_id' ERROR ON EMPTY,
               qty          SMALLINT UNSIGNED PATH '$.qty'          ERROR ON EMPTY)) AS jt;
    END IF;
  END IF;
  SET v_late = fn_calculate_late_fee(p_booking_id, v_now);
  UPDATE Rentals_Reservations
     SET status = 'Completed', returned_at = v_now, late_fee = v_late
   WHERE booking_id = p_booking_id;
  COMMIT;
END$$

-- ---------------------------------------------------------------------
-- sp_cancel_booking
-- Purpose   : Reserved -> Cancelled. Free until 2 hours before the start,
--             Rs 100 after that. Base charge and discount are cleared.
-- Parameters: p_booking_id
-- Rules     : BR-19, BR-15
-- Errors    : 45000 'BR-19: only Reserved bookings can be cancelled'
-- Lab       : Exp 12
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_cancel_booking(IN p_booking_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE v_status VARCHAR(12);
  DECLARE v_start DATETIME;
  SELECT status, reserved_start INTO v_status, v_start
    FROM Rentals_Reservations WHERE booking_id = p_booking_id;
  IF v_status IS NULL OR v_status <> 'Reserved' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-19: only Reserved bookings can be cancelled';
  END IF;
  UPDATE Rentals_Reservations
     SET status = 'Cancelled', discount_amount = 0, base_charge = 0,
         cancellation_fee = IF(NOW() > v_start - INTERVAL 2 HOUR, 100.00, 0.00)
   WHERE booking_id = p_booking_id;
END$$

-- ---------------------------------------------------------------------
-- sp_mark_no_shows
-- Purpose   : Every Reserved booking not checked in 30 minutes after its
--             start becomes No_Show with a Rs 100 fee. Called by the
--             ev_mark_no_shows event every 15 minutes.
-- Parameters: none
-- Rules     : BR-19
-- Errors    : none
-- Lab       : Exp 12
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_mark_no_shows()
MODIFIES SQL DATA
BEGIN
  UPDATE Rentals_Reservations
     SET status = 'No_Show', discount_amount = 0, base_charge = 0, cancellation_fee = 100.00
   WHERE status = 'Reserved' AND reserved_start < NOW() - INTERVAL 30 MINUTE;
END$$

-- ---------------------------------------------------------------------
-- sp_find_free_tables
-- Purpose   : Active tables that seat the party and are free for the whole
--             window, smallest suitable table first.
-- Parameters: p_party, p_start, p_end, p_accessible_only
-- Rules     : BR-01, BR-05 (read-only helper)
-- Errors    : none
-- Lab       : Exp 12
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_find_free_tables(IN p_party TINYINT UNSIGNED, IN p_start DATETIME,
                                     IN p_end DATETIME, IN p_accessible_only BOOLEAN)
READS SQL DATA
BEGIN
  SELECT table_id, table_code, zone, seating_capacity, hourly_rate, is_accessible
    FROM Cafe_Tables
   WHERE is_active
     AND seating_capacity >= p_party
     AND (NOT p_accessible_only OR is_accessible)
     AND fn_table_is_free(table_id, p_start, p_end, NULL)
   ORDER BY seating_capacity, hourly_rate, table_code;   -- smallest table that fits first
END$$

-- ---------------------------------------------------------------------
-- sp_recommend_games
-- Purpose   : Games that fit the group (player range, youngest player's age,
--             time available) and have a copy free in the window.
-- Parameters: p_party, p_youngest_age, p_max_minutes, p_start, p_end
-- Rules     : BR-02, BR-03, BR-06, BR-07 (read-only helper)
-- Errors    : none
-- Lab       : Exp 12
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_recommend_games(IN p_party TINYINT UNSIGNED, IN p_youngest_age TINYINT UNSIGNED,
                                    IN p_max_minutes SMALLINT UNSIGNED,
                                    IN p_start DATETIME, IN p_end DATETIME)
READS SQL DATA
BEGIN
  SELECT bg.game_id, bg.title, bg.min_players, bg.max_players, bg.min_age,
         bg.avg_play_minutes, bg.complexity,
         COUNT(gc.copy_id) AS free_copies, MIN(gc.copy_id) AS suggested_copy_id
    FROM Board_Games bg
    JOIN Game_Copies gc ON gc.game_id = bg.game_id
   WHERE p_party BETWEEN bg.min_players AND bg.max_players
     AND bg.min_age <= p_youngest_age
     AND bg.avg_play_minutes <= p_max_minutes
     AND gc.status IN ('Available','Rented')
     AND fn_copy_is_free(gc.copy_id, p_start, p_end, NULL)
   GROUP BY bg.game_id
   ORDER BY bg.complexity, bg.title;
END$$

-- ---------------------------------------------------------------------
-- sp_record_payment
-- Purpose   : Record money received for a closed booking.
-- Parameters: p_booking_id, p_amount, p_method ('Cash','Card','UPI')
-- Rules     : PAY-01, PAY-02 (via trg_pay_before_insert)
-- Errors    : 45000 'PAY-01: ...', 'PAY-02: ...'
-- Lab       : Exp 12
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_record_payment(IN p_booking_id INT UNSIGNED, IN p_amount DECIMAL(10,2),
                                   IN p_method VARCHAR(5))
MODIFIES SQL DATA
BEGIN
  INSERT INTO Payments (booking_id, amount, method) VALUES (p_booking_id, p_amount, p_method);
END$$

-- ---------------------------------------------------------------------
-- sp_restock_copy
-- Purpose   : Staff replaced the missing pieces: stamp restocked_at on the
--             copy's open Missing_Pieces rows and put it back on the shelf.
-- Parameters: p_copy_id
-- Rules     : BR-18
-- Errors    : re-signals any error after ROLLBACK
-- Lab       : Exp 11, Exp 12
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_restock_copy(IN p_copy_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  UPDATE Missing_Pieces mp
    JOIN Return_Inspections ri   ON ri.inspection_id = mp.inspection_id
    JOIN Rentals_Reservations rr ON rr.booking_id    = ri.booking_id
     SET mp.restocked_at = NOW()
   WHERE rr.copy_id = p_copy_id AND mp.restocked_at IS NULL;
  UPDATE Game_Copies SET status = 'Available'
   WHERE copy_id = p_copy_id AND status = 'Missing_Pieces';
  COMMIT;
END$$

-- ---------------------------------------------------------------------
-- sp_flag_suspensions  (the cursor demo)
-- Purpose   : Walk every Active/Suspended member with an explicit cursor:
--             suspend an Active member owing more than Rs 2000; reactivate a
--             Suspended member who owes nothing. Called daily by
--             ev_flag_suspensions.
-- Parameters: none
-- Rules     : account standing feeding BR-13
-- Errors    : none
-- Lab       : Additional Exp 1 (cursors: DECLARE, OPEN, FETCH, NOT FOUND
--             handler, CLOSE)
-- ---------------------------------------------------------------------
-- Cursor demo: walk every Active/Suspended member and set status from the balance
CREATE PROCEDURE sp_flag_suspensions()
MODIFIES SQL DATA
BEGIN
  DECLARE v_done BOOLEAN DEFAULT FALSE;
  DECLARE v_customer INT UNSIGNED;
  DECLARE v_status VARCHAR(10);
  DECLARE v_balance DECIMAL(10,2);
  DECLARE cur_members CURSOR FOR
    SELECT customer_id, status FROM Customers WHERE status IN ('Active','Suspended');
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
  OPEN cur_members;
  member_loop: LOOP
    FETCH cur_members INTO v_customer, v_status;
    IF v_done THEN LEAVE member_loop; END IF;
    SET v_balance = fn_customer_balance(v_customer);
    IF v_balance > 2000 AND v_status = 'Active' THEN
      UPDATE Customers SET status = 'Suspended' WHERE customer_id = v_customer;
    ELSEIF v_balance <= 0 AND v_status = 'Suspended' THEN
      UPDATE Customers SET status = 'Active' WHERE customer_id = v_customer;
    END IF;
  END LOOP;
  CLOSE cur_members;
END$$

DELIMITER ;
