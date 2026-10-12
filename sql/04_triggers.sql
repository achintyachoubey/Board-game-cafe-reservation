-- =====================================================================
-- 04_triggers.sql
-- Purpose : The 10 triggers (Appendix B.3): BEFORE/AFTER on INSERT, UPDATE
--           and DELETE. MySQL triggers are always FOR EACH ROW (there is no
--           FOR EACH STATEMENT as in Oracle/PostgreSQL).
-- Run order: 04 (after 03_procedures.sql: the booking triggers CALL
--            sp_validate_booking)
-- Lab      : Exp 12 (triggers)
-- =====================================================================
USE boardgame_cafe;

DELIMITER $$

-- ---------------------------------------------------------------------
-- trg_rr_before_insert  (BEFORE INSERT ON Rentals_Reservations)
-- Purpose : Validate every new booking and price it (base charge and tier
--           discount) unless it is Cancelled/No_Show or already priced.
-- Rules   : BR-01..BR-12 via sp_validate_booking; pricing
-- Errors  : any 'BR-xx' raised by sp_validate_booking
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_rr_before_insert BEFORE INSERT ON Rentals_Reservations
FOR EACH ROW
BEGIN
  DECLARE v_discount_pct DECIMAL(5,2);
  CALL sp_validate_booking(NULL, NEW.customer_id, NEW.table_id, NEW.copy_id, NEW.booking_type,
                           NEW.party_size, NEW.reserved_start, NEW.reserved_end, NEW.status);
  IF NEW.base_charge = 0 AND NEW.status NOT IN ('Cancelled','No_Show') THEN
    SET NEW.base_charge = fn_calculate_base_charge(NEW.booking_type, NEW.table_id, NEW.copy_id,
                                                   NEW.reserved_start, NEW.reserved_end);
    SELECT t.discount_pct INTO v_discount_pct
      FROM Customers c JOIN Membership_Tiers t ON t.tier_id = c.tier_id
     WHERE c.customer_id = NEW.customer_id;
    SET NEW.discount_amount = ROUND(NEW.base_charge * v_discount_pct / 100, 2);
  END IF;
END$$

-- ---------------------------------------------------------------------
-- trg_rr_before_update  (BEFORE UPDATE ON Rentals_Reservations)
-- Purpose : Enforce the status lifecycle, require an inspection before a
--           booking holding a copy completes, freeze closed rows, and
--           re-validate / re-price an active row whose details change.
-- Rules   : BR-15, BR-17, BR-01..BR-12
-- Errors  : 'BR-15: invalid status transition', 'BR-15: closed bookings
--           cannot be changed', 'BR-17: inspect the returned game before
--           completing', plus sp_validate_booking errors
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_rr_before_update BEFORE UPDATE ON Rentals_Reservations
FOR EACH ROW
BEGIN
  DECLARE v_discount_pct DECIMAL(5,2);
  -- BR-15 lifecycle
  IF NEW.status <> OLD.status AND NOT (
       (OLD.status = 'Reserved'   AND NEW.status IN ('Checked_In','Cancelled','No_Show'))
    OR (OLD.status = 'Checked_In' AND NEW.status IN ('Overdue','Completed'))
    OR (OLD.status = 'Overdue'    AND NEW.status = 'Completed')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-15: invalid status transition';
  END IF;
  -- A copy must be inspected before its booking completes
  IF NEW.status = 'Completed' AND OLD.status <> 'Completed' AND NEW.copy_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM Return_Inspections WHERE booking_id = NEW.booking_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-17: inspect the returned game before completing';
  END IF;
  -- Booking details changed: closed rows are frozen, active rows are re-validated and re-priced
  IF NEW.customer_id <> OLD.customer_id OR NOT (NEW.table_id <=> OLD.table_id)
     OR NOT (NEW.copy_id <=> OLD.copy_id) OR NOT (NEW.party_size <=> OLD.party_size)
     OR NEW.booking_type <> OLD.booking_type
     OR NEW.reserved_start <> OLD.reserved_start OR NEW.reserved_end <> OLD.reserved_end THEN
    IF OLD.status IN ('Completed','Cancelled','No_Show') THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-15: closed bookings cannot be changed';
    END IF;
    CALL sp_validate_booking(NEW.booking_id, NEW.customer_id, NEW.table_id, NEW.copy_id,
         NEW.booking_type, NEW.party_size, NEW.reserved_start, NEW.reserved_end, NEW.status);
    SET NEW.base_charge = fn_calculate_base_charge(NEW.booking_type, NEW.table_id, NEW.copy_id,
                                                   NEW.reserved_start, NEW.reserved_end);
    SELECT t.discount_pct INTO v_discount_pct
      FROM Customers c JOIN Membership_Tiers t ON t.tier_id = c.tier_id
     WHERE c.customer_id = NEW.customer_id;
    SET NEW.discount_amount = ROUND(NEW.base_charge * v_discount_pct / 100, 2);
  END IF;
  IF NEW.status = 'Checked_In' AND OLD.status = 'Reserved' AND NEW.checked_in_at IS NULL THEN
    SET NEW.checked_in_at = NOW();
  END IF;
  IF NEW.status = 'Completed' AND NEW.returned_at IS NULL THEN
    SET NEW.returned_at = NOW();
  END IF;
END$$

-- ---------------------------------------------------------------------
-- trg_rr_after_insert  (AFTER INSERT ON Rentals_Reservations)
-- Purpose : Write the first audit row; a booking inserted directly as
--           Checked_In marks its copy Rented.
-- Rules   : audit trail; BR-18 (copy status)
-- Errors  : none
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_rr_after_insert AFTER INSERT ON Rentals_Reservations
FOR EACH ROW
BEGIN
  INSERT INTO Booking_Audit_Log (booking_id, old_status, new_status, changed_by)
  VALUES (NEW.booking_id, NULL, NEW.status, CURRENT_USER());
  IF NEW.copy_id IS NOT NULL AND NEW.status = 'Checked_In' THEN
    UPDATE Game_Copies SET status = 'Rented' WHERE copy_id = NEW.copy_id;
  END IF;
END$$

-- ---------------------------------------------------------------------
-- trg_rr_after_update  (AFTER UPDATE ON Rentals_Reservations)
-- Purpose : Audit every status change; checking in marks the copy Rented.
-- Rules   : audit trail; BR-18
-- Errors  : none
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_rr_after_update AFTER UPDATE ON Rentals_Reservations
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO Booking_Audit_Log (booking_id, old_status, new_status, changed_by)
    VALUES (NEW.booking_id, OLD.status, NEW.status, CURRENT_USER());
    IF NEW.copy_id IS NOT NULL AND NEW.status = 'Checked_In' THEN
      UPDATE Game_Copies SET status = 'Rented' WHERE copy_id = NEW.copy_id;
    END IF;
  END IF;
END$$

-- ---------------------------------------------------------------------
-- trg_insp_before_insert  (BEFORE INSERT ON Return_Inspections)
-- Purpose : Only a booking that holds a copy and actually went out
--           (Checked_In, Overdue, Completed) can be inspected.
-- Rules   : BR-17
-- Errors  : 'BR-17: booking has no game copy to inspect',
--           'BR-17: only games that went out can be inspected'
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_insp_before_insert BEFORE INSERT ON Return_Inspections
FOR EACH ROW
BEGIN
  DECLARE v_copy INT UNSIGNED;
  DECLARE v_status VARCHAR(12);
  SELECT copy_id, status INTO v_copy, v_status
    FROM Rentals_Reservations WHERE booking_id = NEW.booking_id;
  IF v_copy IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-17: booking has no game copy to inspect';
  END IF;
  IF v_status NOT IN ('Checked_In','Overdue','Completed') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-17: only games that went out can be inspected';
  END IF;
END$$

-- ---------------------------------------------------------------------
-- trg_insp_after_insert  (AFTER INSERT ON Return_Inspections)
-- Purpose : Copy the inspected condition onto the box; Damaged -> Under_Repair,
--           otherwise back to Available (Retired stays Retired).
-- Rules   : BR-18
-- Errors  : none
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_insp_after_insert AFTER INSERT ON Return_Inspections
FOR EACH ROW
BEGIN
  UPDATE Game_Copies gc
    JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id
     SET gc.copy_condition = NEW.condition_on_return,
         gc.status = CASE WHEN gc.status = 'Retired' THEN 'Retired'
                          WHEN NEW.condition_on_return = 'Damaged' THEN 'Under_Repair'
                          ELSE 'Available' END
   WHERE rr.booking_id = NEW.booking_id;
END$$

-- ---------------------------------------------------------------------
-- trg_mp_before_insert  (BEFORE INSERT ON Missing_Pieces)
-- Purpose : The component must belong to the returned game and the
--           quantity cannot exceed what the box holds; price the row
--           (qty x unit cost) as a snapshot.
-- Rules   : BR-17
-- Errors  : 'BR-17: component does not belong to the returned game',
--           'BR-17: more pieces missing than the box contains'
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_mp_before_insert BEFORE INSERT ON Missing_Pieces
FOR EACH ROW
BEGIN
  DECLARE v_copy_game, v_comp_game INT UNSIGNED;
  DECLARE v_qty_per_copy SMALLINT UNSIGNED;
  DECLARE v_unit DECIMAL(8,2);
  SELECT gc.game_id INTO v_copy_game
    FROM Return_Inspections ri
    JOIN Rentals_Reservations rr ON rr.booking_id = ri.booking_id
    JOIN Game_Copies gc          ON gc.copy_id    = rr.copy_id
   WHERE ri.inspection_id = NEW.inspection_id;
  SELECT game_id, qty_per_copy, unit_replacement_cost
    INTO v_comp_game, v_qty_per_copy, v_unit
    FROM Game_Components WHERE component_id = NEW.component_id;
  IF v_comp_game IS NULL OR v_comp_game <> v_copy_game THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-17: component does not belong to the returned game';
  END IF;
  IF NEW.qty_missing > v_qty_per_copy THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-17: more pieces missing than the box contains';
  END IF;
  SET NEW.charge = ROUND(NEW.qty_missing * v_unit, 2);
END$$

-- ---------------------------------------------------------------------
-- trg_mp_after_insert  (AFTER INSERT ON Missing_Pieces)
-- Purpose : Add the charge to the booking's damage fee and flag the copy
--           Missing_Pieces (unless Retired).
-- Rules   : BR-17, BR-18
-- Errors  : none
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_mp_after_insert AFTER INSERT ON Missing_Pieces
FOR EACH ROW
BEGIN
  UPDATE Rentals_Reservations rr
    JOIN Return_Inspections ri ON ri.booking_id = rr.booking_id
     SET rr.damage_fee = rr.damage_fee + NEW.charge
   WHERE ri.inspection_id = NEW.inspection_id;
  UPDATE Game_Copies gc
    JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id
    JOIN Return_Inspections ri   ON ri.booking_id = rr.booking_id
     SET gc.status = 'Missing_Pieces'
   WHERE ri.inspection_id = NEW.inspection_id AND gc.status <> 'Retired';
END$$

-- ---------------------------------------------------------------------
-- trg_pay_before_insert  (BEFORE INSERT ON Payments)
-- Purpose : Money is taken only for closed bookings and never beyond the
--           amount due.
-- Rules   : PAY-01, PAY-02
-- Errors  : 'PAY-01: payments are taken after check-out, cancellation or
--           no-show', 'PAY-02: payment exceeds the amount due'
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_pay_before_insert BEFORE INSERT ON Payments
FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(12);
  DECLARE v_total, v_paid DECIMAL(10,2);
  SELECT status, total_amount INTO v_status, v_total
    FROM Rentals_Reservations WHERE booking_id = NEW.booking_id;
  IF v_status NOT IN ('Completed','Cancelled','No_Show') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PAY-01: payments are taken after check-out, cancellation or no-show';
  END IF;
  SELECT IFNULL(SUM(amount), 0) INTO v_paid FROM Payments WHERE booking_id = NEW.booking_id;
  IF v_paid + NEW.amount > v_total THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PAY-02: payment exceeds the amount due';
  END IF;
END$$

-- ---------------------------------------------------------------------
-- trg_rr_before_delete  (BEFORE DELETE ON Rentals_Reservations)
-- Purpose : History is never deleted; only a free cancellation may go
--           (its audit rows cascade via fk_audit_booking).
-- Rules   : BR-20
-- Errors  : 'BR-20: only free cancellations can be deleted; history is kept'
-- Lab     : Exp 12
-- ---------------------------------------------------------------------
-- DELETE trigger (lab Exp 12): history is kept; only a free cancellation can be removed
CREATE TRIGGER trg_rr_before_delete BEFORE DELETE ON Rentals_Reservations
FOR EACH ROW
BEGIN
  IF NOT (OLD.status = 'Cancelled' AND OLD.cancellation_fee = 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-20: only free cancellations can be deleted; history is kept';
  END IF;
END$$

DELIMITER ;
