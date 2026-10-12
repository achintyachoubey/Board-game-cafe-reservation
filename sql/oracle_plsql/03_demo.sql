-- =====================================================================
-- oracle_plsql/03_demo.sql   (Oracle Database 19c / 23ai)
-- Purpose : Load a little data and exercise every program in 02_programs.sql,
--           printing results with DBMS_OUTPUT. Errors are caught in each
--           anonymous block (EXCEPTION WHEN OTHERS) so the script continues.
-- Lab      : Additional Experiment 2
-- =====================================================================
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET LINESIZE 160
SET PAGESIZE 100
COLUMN first_name   FORMAT A12
COLUMN status       FORMAT A10
COLUMN booking_type FORMAT A10
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI';

INSERT INTO Membership_Tiers (tier_name, annual_fee, max_concurrent_rentals, max_session_hours,
                              max_takehome_days, discount_pct)
SELECT 'Basic', 0, 1, 4, 1, 0 FROM dual UNION ALL
SELECT 'Silver', 999, 2, 6, 2, 10 FROM dual UNION ALL
SELECT 'Gold', 1999, 3, 8, 3, 20 FROM dual;

INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id,
                       join_date, membership_expiry, status)
SELECT 'Aarav', 'Mehta', 'aarav.mehta@mail.test', '9810012345', ADD_MONTHS(TRUNC(SYSDATE), -12 * 29) - 150,
       3, TRUNC(SYSDATE) - 200, TRUNC(SYSDATE) + 200, 'Active' FROM dual UNION ALL
SELECT 'Manish', 'Chauhan', 'manish.chauhan@mail.test', '9712309876', ADD_MONTHS(TRUNC(SYSDATE), -12 * 47) - 120,
       1, TRUNC(SYSDATE) - 300, TRUNC(SYSDATE) + 100, 'Suspended' FROM dual UNION ALL
SELECT 'Karan', 'Malhotra', 'karan.malhotra@mail.test', '9844434567', ADD_MONTHS(TRUNC(SYSDATE), -12 * 33) - 110,
       2, TRUNC(SYSDATE) - 250, TRUNC(SYSDATE) + 90, 'Active' FROM dual;

INSERT INTO Cafe_Tables (table_code, zone, seating_capacity, hourly_rate, is_accessible, is_active)
SELECT 'MH-01', 'Main_Hall', 4, 150, 0, 1 FROM dual UNION ALL
SELECT 'PR-01', 'Party_Room', 10, 350, 0, 1 FROM dual UNION ALL
SELECT 'PA-05', 'Patio', 8, 260, 0, 0 FROM dual;

-- Karan owes Rs 2,520 for an old 6-hour party-room session with games (base 2,800 - 10%), unpaid
INSERT INTO Rentals_Reservations (customer_id, table_id, booking_type, party_size, reserved_start,
                                  reserved_end, status, base_charge, discount_amount)
VALUES (3, 2, 'Dine_In', 6, TRUNC(SYSDATE) - 5 + 12/24, TRUNC(SYSDATE) - 5 + 18/24, 'Completed', 2800, 280);
COMMIT;

PROMPT
PROMPT === fn_customer_age ===
SELECT customer_id, first_name, fn_customer_age(customer_id, SYSDATE) AS age FROM Customers ORDER BY customer_id;

PROMPT === fn_customer_balance ===
SELECT customer_id, first_name, fn_customer_balance(customer_id) AS balance FROM Customers ORDER BY customer_id;

PROMPT === sp_create_reservation: a valid booking (Aarav, 4 people at MH-01, in 3 days) ===
DECLARE
  v_id NUMBER;
BEGIN
  sp_create_reservation(1, 'Dine_In', 1, NULL, 4, TRUNC(SYSDATE) + 3 + 18/24, TRUNC(SYSDATE) + 3 + 20/24, v_id);
  DBMS_OUTPUT.PUT_LINE('created booking ' || v_id);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('refused: ' || SQLERRM);
END;
/

PROMPT === BR-01 from the row trigger: party of 6 at a 4-seat table ===
DECLARE
  v_id NUMBER;
BEGIN
  sp_create_reservation(1, 'Dine_In', 1, NULL, 6, TRUNC(SYSDATE) + 4 + 18/24, TRUNC(SYSDATE) + 4 + 20/24, v_id);
  DBMS_OUTPUT.PUT_LINE('created booking ' || v_id);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('refused: ' || SQLERRM);
END;
/

PROMPT === BR-01: inactive table ===
DECLARE
  v_id NUMBER;
BEGIN
  sp_create_reservation(1, 'Dine_In', 3, NULL, 2, TRUNC(SYSDATE) + 4 + 18/24, TRUNC(SYSDATE) + 4 + 20/24, v_id);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('refused: ' || SQLERRM);
END;
/

PROMPT === BR-13: suspended member / member owing more than Rs 500 ===
DECLARE
  v_id NUMBER;
BEGIN
  BEGIN
    sp_create_reservation(2, 'Dine_In', 1, NULL, 2, TRUNC(SYSDATE) + 5 + 12/24, TRUNC(SYSDATE) + 5 + 14/24, v_id);
  EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('refused: ' || SQLERRM);
  END;
  BEGIN
    sp_create_reservation(3, 'Dine_In', 1, NULL, 2, TRUNC(SYSDATE) + 5 + 15/24, TRUNC(SYSDATE) + 5 + 17/24, v_id);
  EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('refused: ' || SQLERRM);
  END;
END;
/

PROMPT === BR-14: 15 days ahead / started 2 hours ago ===
DECLARE
  v_id NUMBER;
BEGIN
  BEGIN
    sp_create_reservation(1, 'Take_Home', NULL, 7, NULL, SYSDATE + 15, SYSDATE + 16, v_id);
  EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('refused: ' || SQLERRM);
  END;
  BEGIN
    sp_create_reservation(1, 'Take_Home', NULL, 7, NULL, SYSDATE - 2/24, SYSDATE + 1, v_id);
  EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('refused: ' || SQLERRM);
  END;
END;
/

PROMPT === Bookings now (FETCH FIRST n ROWS ONLY is Oracle's LIMIT n) ===
SELECT booking_id, customer_id, table_id, booking_type, party_size, status, total_amount
  FROM Rentals_Reservations ORDER BY booking_id FETCH FIRST 5 ROWS ONLY;

PROMPT === sp_flag_suspensions (cursor FOR loop): Karan owes > 2000 -> Suspended ===
SELECT customer_id, first_name, status, fn_customer_balance(customer_id) AS balance FROM Customers ORDER BY customer_id;
EXEC sp_flag_suspensions
SELECT customer_id, first_name, status, fn_customer_balance(customer_id) AS balance FROM Customers ORDER BY customer_id;

PROMPT === Explicit cursor with OPEN / FETCH / EXIT WHEN %NOTFOUND / CLOSE ===
DECLARE
  CURSOR cur_members IS SELECT first_name, status FROM Customers ORDER BY customer_id;
  v_name   Customers.first_name%TYPE;
  v_status Customers.status%TYPE;
BEGIN
  OPEN cur_members;
  LOOP
    FETCH cur_members INTO v_name, v_status;
    EXIT WHEN cur_members%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(RPAD(v_name, 10) || v_status);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(cur_members%ROWCOUNT || ' rows fetched');
  CLOSE cur_members;
END;
/
