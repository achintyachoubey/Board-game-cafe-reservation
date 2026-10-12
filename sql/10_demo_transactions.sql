-- =====================================================================
-- 10_demo_transactions.sql
-- Purpose : Transactions and concurrency demos.
--             T1  SAVEPOINT - keep a good payment, undo a bad one (runnable here)
--             T2  double-booking race            (two terminals, see below)
--             T3  READ COMMITTED vs REPEATABLE READ (two terminals)
--             T4  deadlock and ERROR 1213          (two terminals)
-- Run order: after 08_seed.sql
-- Lab      : Exp 11 (COMMIT / ROLLBACK / SAVEPOINT); CO4 (ACID, isolation,
--            two-phase locking, deadlock handling)
-- How to run:
--   * T1 contains an INTENTIONAL error (PAY-02). In the mysql shell use
--       mysql --force -u root -p boardgame_cafe < sql/10_demo_transactions.sql
--     In Workbench turn off Query > "Stop Script Execution on Errors".
--   * T2, T3 and T4 are inside /* ... */ comments, so they do NOT run when the
--     file is sourced. Open two terminals (Session A and Session B), connect
--     both to boardgame_cafe, and paste the steps in the order shown:
--     [AB0] in both terminals, then [A1], [B1], [A2], ...
--     The test suite (tests/test_concurrency.py) and scripts/capture_evidence.py
--     run these exact steps on two real connections.
-- =====================================================================
USE boardgame_cafe;

-- =====================================================================
-- T1 · SAVEPOINT: keep a good payment, undo a bad one.
-- Concept: a failed statement rolls back only itself; ROLLBACK TO SAVEPOINT
--          undoes back to a named point; COMMIT keeps the rest.   Lab: Exp 11
-- =====================================================================
-- Pick a Completed booking with at least Rs 200 still unpaid
SELECT rr.booking_id INTO @b
  FROM Rentals_Reservations rr
 WHERE rr.status = 'Completed'
   AND rr.total_amount - (SELECT IFNULL(SUM(p.amount), 0) FROM Payments p
                           WHERE p.booking_id = rr.booking_id) >= 200
 ORDER BY rr.booking_id
 LIMIT 1;
SELECT rr.booking_id, rr.total_amount,
       (SELECT IFNULL(SUM(amount), 0) FROM Payments WHERE booking_id = rr.booking_id) AS paid_before
  FROM Rentals_Reservations rr WHERE rr.booking_id = @b;

START TRANSACTION;
INSERT INTO Payments (booking_id, amount, method) VALUES (@b, 200.00, 'UPI');
SAVEPOINT after_first_payment;
-- @expect-error PAY-02
INSERT INTO Payments (booking_id, amount, method) VALUES (@b, 99999.00, 'Cash');  -- PAY-02 error
ROLLBACK TO SAVEPOINT after_first_payment;
COMMIT;                                       -- only the ₹200 payment is saved

SELECT rr.booking_id, rr.total_amount,
       (SELECT IFNULL(SUM(amount), 0) FROM Payments WHERE booking_id = rr.booking_id) AS paid_after
  FROM Rentals_Reservations rr WHERE rr.booking_id = @b;

/* @two-session T2
=====================================================================
T2 · Double-booking race: two front desks book the same table and slot.
Concept: sp_create_reservation runs at READ COMMITTED and takes FOR UPDATE
         row locks (table -> copy -> customer) BEFORE any plain read. The
         second desk waits on the lock; when the first commits, the second
         desk's overlap check (a fresh READ COMMITTED read in the trigger)
         sees the new booking and refuses with BR-05. Without the lock both
         overlap checks would run before either insert is committed, both
         would see a free table, and the table would be double-booked.
         Session A plays the procedure step by step so the lock is visible.
Lab: Exp 11; CO4 (two-phase locking: locks are held until COMMIT)
=====================================================================
-- [AB0] Both sessions: the same slot, table and two different members
USE boardgame_cafe;
SET @start = TIMESTAMP(CURRENT_DATE + INTERVAL 2 DAY, '19:00:00');
SET @end   = TIMESTAMP(CURRENT_DATE + INTERVAL 2 DAY, '21:00:00');
SELECT table_id INTO @t FROM Cafe_Tables
 WHERE is_active AND seating_capacity >= 2 AND fn_table_is_free(table_id, @start, @end, NULL)
 ORDER BY seating_capacity, hourly_rate, table_code LIMIT 1;
SELECT customer_id INTO @cust_a FROM Customers
 WHERE status = 'Active' AND membership_expiry >= DATE(@end)
   AND fn_customer_balance(customer_id) <= 500
 ORDER BY customer_id LIMIT 1;
SELECT customer_id INTO @cust_b FROM Customers
 WHERE status = 'Active' AND membership_expiry >= DATE(@end)
   AND fn_customer_balance(customer_id) <= 500
 ORDER BY customer_id LIMIT 1 OFFSET 1;
SELECT @t AS table_id, @start AS slot_start, @end AS slot_end, @cust_a AS member_a, @cust_b AS member_b;
-- [A1] Session A: lock the table row, insert, do NOT commit yet
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT table_id FROM Cafe_Tables WHERE table_id = @t FOR UPDATE;
INSERT INTO Rentals_Reservations (customer_id, table_id, booking_type, party_size,
                                  reserved_start, reserved_end)
VALUES (@cust_a, @t, 'Dine_In', 2, @start, @end);
-- expect: 1 row inserted (the trigger validated and priced it); the lock on the table row is held
-- [B1] Session B: the second desk books the same table and slot
CALL sp_create_reservation(@cust_b, 'Dine_In', @t, NULL, 2, @start, @end, @booking_b);
-- expect: WAITS - the procedure's SELECT ... FOR UPDATE on the same Cafe_Tables row blocks
-- [A2] Session A: commit
COMMIT;
-- expect: Session B wakes up and fails: ERROR 1644 (45000): BR-05: table already booked for an overlapping time
-- [B2] Session B: check the result
SELECT @booking_b AS booking_b;
SELECT booking_id, customer_id, status FROM Rentals_Reservations
 WHERE table_id = @t AND reserved_start = @start AND status = 'Reserved';
-- expect: booking_b is NULL; exactly one Reserved row, owned by member_a
*/

/* @two-session T3
=====================================================================
T3 · Isolation levels: a non-repeatable read under READ COMMITTED that
     REPEATABLE READ (InnoDB's default) prevents with its snapshot.
Lab: Exp 11; CO4 (isolation levels, read phenomena, MVCC snapshots)
=====================================================================
-- [AB0] Both sessions
USE boardgame_cafe;
SELECT MIN(table_id) INTO @t FROM Cafe_Tables WHERE is_active;
-- [A1] Session A: READ COMMITTED, first read
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT hourly_rate AS rc_first_read FROM Cafe_Tables WHERE table_id = @t;
-- expect: the current rate, e.g. 150.00
-- [B1] Session B: change the rate (autocommit)
UPDATE Cafe_Tables SET hourly_rate = hourly_rate + 10 WHERE table_id = @t;
-- [A2] Session A: read again inside the SAME transaction
SELECT hourly_rate AS rc_second_read FROM Cafe_Tables WHERE table_id = @t;
COMMIT;
-- expect: 10 more than the first read - a NON-REPEATABLE READ
-- [A3] Session A: REPEATABLE READ, first read
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT hourly_rate AS rr_first_read FROM Cafe_Tables WHERE table_id = @t;
-- [B2] Session B: put the rate back (autocommit)
UPDATE Cafe_Tables SET hourly_rate = hourly_rate - 10 WHERE table_id = @t;
-- [A4] Session A: read again, commit, read once more
SELECT hourly_rate AS rr_second_read FROM Cafe_Tables WHERE table_id = @t;
COMMIT;
SELECT hourly_rate AS after_commit FROM Cafe_Tables WHERE table_id = @t;
-- expect: rr_second_read = rr_first_read (snapshot); after_commit shows B's change
*/

/* @two-session T4
=====================================================================
T4 · Deadlock: A locks copy 1 then wants copy 2; B locks copy 2 then wants
     copy 1. InnoDB's wait-for graph finds the cycle, rolls one transaction
     back with ERROR 1213, and the other continues and commits.
     (sp_create_reservation avoids this by always locking in the same order.)
Lab: Exp 11; CO4 (deadlock detection and recovery)
=====================================================================
-- [AB0] Both sessions
USE boardgame_cafe;
-- [A1] Session A: lock copy 1
START TRANSACTION;
SELECT copy_id, status FROM Game_Copies WHERE copy_id = 1 FOR UPDATE;
-- [B1] Session B: lock copy 2
START TRANSACTION;
SELECT copy_id, status FROM Game_Copies WHERE copy_id = 2 FOR UPDATE;
-- [A2] Session A: now ask for copy 2
SELECT copy_id, status FROM Game_Copies WHERE copy_id = 2 FOR UPDATE;
-- expect: WAITS for Session B
-- [B2] Session B: now ask for copy 1 - the cycle closes
SELECT copy_id, status FROM Game_Copies WHERE copy_id = 1 FOR UPDATE;
-- expect: one session gets ERROR 1213 (40001): Deadlock found when trying to get lock;
--         its transaction is rolled back and the other session's wait ends
-- [A3] Session A
COMMIT;
-- [B3] Session B
COMMIT;
-- expect: the surviving transaction commits; the victim's COMMIT has nothing left to commit
*/
