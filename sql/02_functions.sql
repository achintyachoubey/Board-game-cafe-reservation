-- =====================================================================
-- 02_functions.sql
-- Purpose : The six stored functions (Appendix B.1). All are READS SQL DATA,
--           which satisfies the binary-log rule for functions (see README if
--           you get ERROR 1418/1419: SET GLOBAL log_bin_trust_function_creators = 1).
-- Run order: 02 (after 01_schema.sql)
-- Lab      : Additional Exp 1 (functions), Exp 12 (stored programs)
-- =====================================================================
USE boardgame_cafe;

DELIMITER $$

-- ---------------------------------------------------------------------
-- fn_customer_age
-- Purpose   : Age in completed years of a member on a given date (age is a
--             derived attribute; date_of_birth is what is stored).
-- Parameters: p_customer_id - member; p_on - the date to measure on
-- Rules     : BR-03 (minimum game age), BR-04 (take-home 18+)
-- Errors    : none (NULL for an unknown member)
-- Lab       : Additional Exp 1
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_customer_age(p_customer_id INT UNSIGNED, p_on DATE)
RETURNS INT READS SQL DATA
BEGIN
  DECLARE v_dob DATE;
  SELECT date_of_birth INTO v_dob FROM Customers WHERE customer_id = p_customer_id;
  RETURN TIMESTAMPDIFF(YEAR, v_dob, p_on);
END$$

-- ---------------------------------------------------------------------
-- fn_table_is_free
-- Purpose   : TRUE when no active booking (Reserved, Checked_In, Overdue)
--             overlaps [p_start, p_end) on the table. Overlap test:
--             new_start < old_end AND old_start < new_end. An Overdue
--             booking blocks the table until it is returned.
-- Parameters: p_table_id, p_start, p_end; p_ignore = booking to skip (the
--             row being updated) or NULL
-- Rules     : BR-05
-- Errors    : none
-- Lab       : Additional Exp 1
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_table_is_free(p_table_id SMALLINT UNSIGNED, p_start DATETIME,
                                 p_end DATETIME, p_ignore INT UNSIGNED)
RETURNS BOOLEAN READS SQL DATA
BEGIN
  RETURN NOT EXISTS (
    SELECT 1 FROM Rentals_Reservations
     WHERE table_id = p_table_id
       AND booking_id <> IFNULL(p_ignore, 0)
       AND status IN ('Reserved','Checked_In','Overdue')
       AND reserved_start < p_end
       AND (p_start < reserved_end OR status = 'Overdue'));  -- overdue blocks until returned
END$$

-- ---------------------------------------------------------------------
-- fn_copy_is_free
-- Purpose   : Same overlap test as fn_table_is_free, for one game copy.
-- Parameters: p_copy_id, p_start, p_end, p_ignore (booking to skip or NULL)
-- Rules     : BR-06
-- Errors    : none
-- Lab       : Additional Exp 1
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_copy_is_free(p_copy_id INT UNSIGNED, p_start DATETIME,
                                p_end DATETIME, p_ignore INT UNSIGNED)
RETURNS BOOLEAN READS SQL DATA
BEGIN
  RETURN NOT EXISTS (
    SELECT 1 FROM Rentals_Reservations
     WHERE copy_id = p_copy_id
       AND booking_id <> IFNULL(p_ignore, 0)
       AND status IN ('Reserved','Checked_In','Overdue')
       AND reserved_start < p_end
       AND (p_start < reserved_end OR status = 'Overdue'));
END$$

-- ---------------------------------------------------------------------
-- fn_calculate_base_charge
-- Purpose   : Price of the booked time before discount.
--             Dine_In  : (table hourly + game hourly) x hours (pro rata)
--             Take_Home: game daily x started days
-- Parameters: p_type ('Dine_In'/'Take_Home'), p_table_id, p_copy_id, p_start, p_end
-- Rules     : pricing (Section 6)
-- Errors    : none
-- Lab       : Additional Exp 1
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_calculate_base_charge(p_type VARCHAR(10), p_table_id SMALLINT UNSIGNED,
                                         p_copy_id INT UNSIGNED, p_start DATETIME, p_end DATETIME)
RETURNS DECIMAL(10,2) READS SQL DATA
BEGIN
  DECLARE v_minutes     INT DEFAULT TIMESTAMPDIFF(MINUTE, p_start, p_end);
  DECLARE v_table_rate  DECIMAL(8,2) DEFAULT 0;
  DECLARE v_game_hourly DECIMAL(8,2) DEFAULT 0;
  DECLARE v_game_daily  DECIMAL(8,2) DEFAULT 0;
  IF p_table_id IS NOT NULL THEN
    SELECT hourly_rate INTO v_table_rate FROM Cafe_Tables WHERE table_id = p_table_id;
  END IF;
  IF p_copy_id IS NOT NULL THEN
    SELECT bg.hourly_rate, bg.daily_rate INTO v_game_hourly, v_game_daily
      FROM Game_Copies gc JOIN Board_Games bg ON bg.game_id = gc.game_id
     WHERE gc.copy_id = p_copy_id;
  END IF;
  IF p_type = 'Dine_In' THEN
    RETURN ROUND(v_minutes / 60 * (v_table_rate + v_game_hourly), 2);
  END IF;
  RETURN ROUND(CEIL(v_minutes / 1440) * v_game_daily, 2);
END$$

-- ---------------------------------------------------------------------
-- fn_calculate_late_fee
-- Purpose   : Late fee for a booking returned at p_returned_at.
--             15-minute grace; then 1.5 x rate per started hour (Dine_In:
--             table + game hourly) or per started day (Take_Home: game daily).
-- Parameters: p_booking_id, p_returned_at
-- Rules     : BR-16
-- Errors    : none (0.00 when not late or unknown booking)
-- Lab       : Additional Exp 1
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_calculate_late_fee(p_booking_id INT UNSIGNED, p_returned_at DATETIME)
RETURNS DECIMAL(10,2) READS SQL DATA
BEGIN
  DECLARE v_type VARCHAR(10);
  DECLARE v_end DATETIME;
  DECLARE v_table_hourly, v_game_hourly, v_game_daily DECIMAL(8,2) DEFAULT 0;
  DECLARE v_late INT;
  SELECT rr.booking_type, rr.reserved_end, IFNULL(ct.hourly_rate, 0),
         IFNULL(bg.hourly_rate, 0), IFNULL(bg.daily_rate, 0)
    INTO v_type, v_end, v_table_hourly, v_game_hourly, v_game_daily
    FROM Rentals_Reservations rr
    LEFT JOIN Cafe_Tables ct ON ct.table_id = rr.table_id
    LEFT JOIN Game_Copies gc ON gc.copy_id  = rr.copy_id
    LEFT JOIN Board_Games bg ON bg.game_id  = gc.game_id
   WHERE rr.booking_id = p_booking_id;
  SET v_late = TIMESTAMPDIFF(MINUTE, v_end, p_returned_at);
  IF v_late IS NULL OR v_late <= 15 THEN RETURN 0.00; END IF;          -- grace period
  IF v_type = 'Dine_In' THEN
    RETURN ROUND(CEIL(v_late / 60) * (v_table_hourly + v_game_hourly) * 1.5, 2);
  END IF;
  RETURN ROUND(CEIL(v_late / 1440) * v_game_daily * 1.5, 2);
END$$

-- ---------------------------------------------------------------------
-- fn_customer_balance
-- Purpose   : What a member owes now = total of closed bookings
--             (Completed, Cancelled, No_Show) - payments. Never stored.
-- Parameters: p_customer_id
-- Rules     : BR-13 (Rs 500 limit), sp_flag_suspensions (Rs 2000)
-- Errors    : none
-- Lab       : Additional Exp 1
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_customer_balance(p_customer_id INT UNSIGNED)
RETURNS DECIMAL(10,2) READS SQL DATA
BEGIN
  RETURN (SELECT IFNULL(SUM(total_amount), 0) FROM Rentals_Reservations
           WHERE customer_id = p_customer_id
             AND status IN ('Completed','Cancelled','No_Show'))
       - (SELECT IFNULL(SUM(pay.amount), 0) FROM Payments pay
            JOIN Rentals_Reservations rr ON rr.booking_id = pay.booking_id
           WHERE rr.customer_id = p_customer_id);
END$$

DELIMITER ;
