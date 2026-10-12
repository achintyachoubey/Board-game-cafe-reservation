-- =====================================================================
-- oracle_plsql/02_programs.sql   (Oracle Database 19c / 23ai)
-- Purpose : PL/SQL versions of a representative subset of the MySQL programs:
--             fn_customer_age        FUNCTION
--             fn_customer_balance    FUNCTION (needed by the two below)
--             sp_create_reservation  PROCEDURE - BR-13/BR-14 checks + the insert,
--                                    errors via RAISE_APPLICATION_ERROR
--             trg_rr_capacity        BEFORE INSERT ... FOR EACH ROW trigger (BR-01)
--             trg_rr_statement_log   statement-level trigger (MySQL has none)
--             sp_flag_suspensions    explicit cursor + cursor FOR loop
-- Each program ends with "/" on a line of its own - SQL*Plus's equivalent of
-- MySQL's DELIMITER $$ ... $$ trick.
-- Lab      : Additional Experiment 2 (PL/SQL)
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_customer_age: age in completed years on p_on (BR-03, BR-04).
-- MySQL: TIMESTAMPDIFF(YEAR, dob, p_on).  Oracle: TRUNC(MONTHS_BETWEEN(...) / 12).
-- MySQL's SELECT ... INTO with no row leaves NULL; Oracle raises NO_DATA_FOUND.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_customer_age(p_customer_id IN NUMBER, p_on IN DATE)
RETURN NUMBER
IS
  v_dob Customers.date_of_birth%TYPE;
BEGIN
  SELECT date_of_birth INTO v_dob FROM Customers WHERE customer_id = p_customer_id;
  RETURN TRUNC(MONTHS_BETWEEN(p_on, v_dob) / 12);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
END fn_customer_age;
/

-- ---------------------------------------------------------------------
-- fn_customer_balance: billed (closed bookings) minus paid; never stored.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_customer_balance(p_customer_id IN NUMBER)
RETURN NUMBER
IS
  v_billed NUMBER(10,2);
  v_paid   NUMBER(10,2);
BEGIN
  SELECT NVL(SUM(total_amount), 0) INTO v_billed
    FROM Rentals_Reservations
   WHERE customer_id = p_customer_id
     AND status IN ('Completed', 'Cancelled', 'No_Show');
  SELECT NVL(SUM(pay.amount), 0) INTO v_paid
    FROM Payments pay
    JOIN Rentals_Reservations rr ON rr.booking_id = pay.booking_id
   WHERE rr.customer_id = p_customer_id;
  RETURN v_billed - v_paid;
END fn_customer_balance;
/

-- ---------------------------------------------------------------------
-- sp_create_reservation (reduced): lock table -> customer FOR UPDATE, then
-- BR-13 (account) and BR-14 (time window), then insert.
-- READ COMMITTED is Oracle's default isolation level, so no SET TRANSACTION
-- is needed (and SET TRANSACTION must be the first statement of a transaction).
-- MySQL: SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '...'
-- Oracle: RAISE_APPLICATION_ERROR(-20000..-20999, '...')
-- MySQL: DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
-- Oracle: EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_create_reservation(
    p_customer_id IN  NUMBER,
    p_type        IN  VARCHAR2,
    p_table_id    IN  NUMBER,
    p_copy_id     IN  NUMBER,
    p_party       IN  NUMBER,
    p_start       IN  DATE,
    p_end         IN  DATE,
    p_booking_id  OUT NUMBER)
IS
  v_lock   NUMBER;
  v_status Customers.status%TYPE;
  v_expiry Customers.membership_expiry%TYPE;
BEGIN
  -- 1. Lock the contested rows first (fixed order: table, then customer)
  IF p_table_id IS NOT NULL THEN
    SELECT table_id INTO v_lock FROM Cafe_Tables WHERE table_id = p_table_id FOR UPDATE;
  END IF;
  BEGIN
    SELECT status, membership_expiry INTO v_status, v_expiry
      FROM Customers WHERE customer_id = p_customer_id FOR UPDATE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20013, 'BR-13: customer not found');
  END;
  -- 2. Account rules (BR-13) and time rules (BR-14)
  IF v_status <> 'Active' THEN
    RAISE_APPLICATION_ERROR(-20013, 'BR-13: customer account is not active');
  END IF;
  IF v_expiry < TRUNC(p_end) THEN
    RAISE_APPLICATION_ERROR(-20013, 'BR-13: membership expires before the booking ends');
  END IF;
  IF fn_customer_balance(p_customer_id) > 500 THEN
    RAISE_APPLICATION_ERROR(-20013, 'BR-13: outstanding balance above Rs 500');
  END IF;
  IF p_start < SYSDATE - INTERVAL '30' MINUTE THEN
    RAISE_APPLICATION_ERROR(-20014, 'BR-14: booking cannot start in the past');
  END IF;
  IF p_start > SYSDATE + INTERVAL '14' DAY THEN
    RAISE_APPLICATION_ERROR(-20014, 'BR-14: bookings open only 14 days ahead');
  END IF;
  -- 3. Insert; the row trigger enforces BR-01. RETURNING replaces LAST_INSERT_ID().
  INSERT INTO Rentals_Reservations (customer_id, table_id, copy_id, booking_type,
                                    party_size, reserved_start, reserved_end)
  VALUES (p_customer_id, p_table_id, p_copy_id, p_type, p_party, p_start, p_end)
  RETURNING booking_id INTO p_booking_id;
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END sp_create_reservation;
/

-- ---------------------------------------------------------------------
-- trg_rr_capacity: BR-01 as a row-level trigger. :NEW instead of NEW; the
-- WHEN clause filters rows before the body runs (MySQL has no WHEN clause).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_rr_capacity
BEFORE INSERT ON Rentals_Reservations
FOR EACH ROW
WHEN (NEW.table_id IS NOT NULL)
DECLARE
  v_capacity Cafe_Tables.seating_capacity%TYPE;
  v_active   Cafe_Tables.is_active%TYPE;
BEGIN
  SELECT seating_capacity, is_active INTO v_capacity, v_active
    FROM Cafe_Tables WHERE table_id = :NEW.table_id;
  IF v_active = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'BR-01: table is out of service');
  END IF;
  IF :NEW.party_size > v_capacity THEN
    RAISE_APPLICATION_ERROR(-20001, 'BR-01: party size exceeds table seating capacity');
  END IF;
END trg_rr_capacity;
/

-- ---------------------------------------------------------------------
-- trg_rr_statement_log: a STATEMENT-level trigger (no FOR EACH ROW): fires once
-- per INSERT/UPDATE/DELETE statement however many rows it touches. MySQL
-- supports only FOR EACH ROW triggers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_rr_statement_log
AFTER INSERT OR UPDATE OR DELETE ON Rentals_Reservations
BEGIN
  DBMS_OUTPUT.PUT_LINE('trg_rr_statement_log: one '
    || CASE WHEN INSERTING THEN 'INSERT' WHEN UPDATING THEN 'UPDATE' ELSE 'DELETE' END
    || ' statement finished on Rentals_Reservations');
END trg_rr_statement_log;
/

-- ---------------------------------------------------------------------
-- sp_flag_suspensions: explicit cursor walked with a cursor FOR loop
-- (implicit OPEN / FETCH / CLOSE and loop exit), updating WHERE CURRENT OF.
-- MySQL needs DECLARE CURSOR + DECLARE CONTINUE HANDLER FOR NOT FOUND +
-- OPEN / FETCH / LEAVE / CLOSE for the same loop.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_flag_suspensions
IS
  CURSOR cur_members IS
    SELECT customer_id, status FROM Customers
     WHERE status IN ('Active', 'Suspended')
       FOR UPDATE OF status;
  v_balance NUMBER(10,2);
BEGIN
  FOR m IN cur_members LOOP
    v_balance := fn_customer_balance(m.customer_id);
    IF v_balance > 2000 AND m.status = 'Active' THEN
      UPDATE Customers SET status = 'Suspended' WHERE CURRENT OF cur_members;
    ELSIF v_balance <= 0 AND m.status = 'Suspended' THEN
      UPDATE Customers SET status = 'Active' WHERE CURRENT OF cur_members;
    END IF;
  END LOOP;
  COMMIT;
END sp_flag_suspensions;
/

SHOW ERRORS
SET LINESIZE 120
COLUMN object_name FORMAT A24
SELECT object_name, object_type, status FROM user_objects
 WHERE object_type IN ('FUNCTION', 'PROCEDURE', 'TRIGGER') ORDER BY object_type, object_name;
