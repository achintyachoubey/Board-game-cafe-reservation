# Additional Experiment 2 — the same programs in Oracle PL/SQL

The project runs on MySQL 8.0. This folder rewrites a representative subset of its stored
programs in Oracle PL/SQL so the two dialects can be compared in the lab record.

| File | What it contains |
| --- | --- |
| `01_schema.sql` | DDL for the five tables the programs touch: `Membership_Tiers`, `Customers`, `Cafe_Tables`, `Rentals_Reservations` (with `total_amount` as a virtual column), `Payments` |
| `02_programs.sql` | `fn_customer_age` (FUNCTION), `fn_customer_balance` (FUNCTION, needed by the next two), `sp_create_reservation` reduced to the BR-13/BR-14 checks plus the insert (PROCEDURE with `RAISE_APPLICATION_ERROR`), `trg_rr_capacity` — the BR-01 check as a `BEFORE INSERT … FOR EACH ROW` trigger, `trg_rr_statement_log` — a statement-level trigger, and `sp_flag_suspensions` with an explicit cursor walked by a cursor `FOR` loop |
| `03_demo.sql` | A little data, then every program called, including each rule being broken on purpose |
| `run_oracle.sh` | Starts `gvenzl/oracle-free` in Docker and runs the three files in SQL*Plus |
| `output/*.out` | The recorded SQL*Plus output of that run |

## Were they executed? Yes.

They ran on **Oracle AI Database 26ai Free, Release 23.26.3.0.0** (Docker image
`gvenzl/oracle-free:23-slim`) on 2026-10-12, through `run_oracle.sh`. The output is in
`output/` and is excerpted below. Nothing was executed on Oracle 19c; the scripts avoid
23ai-only syntax (`BOOLEAN` columns, `DROP TABLE IF EXISTS`) so they should also run there,
but that was not tested.

```bash
bash sql/oracle_plsql/run_oracle.sh        # needs Docker and ~2 GB RAM; first start 1–2 min
docker rm -f cafe_oracle                   # when finished
```

Without Docker: create a user in any Oracle 19c/23ai database (or use Oracle Live SQL), then
in SQL*Plus or SQLcl run `@01_schema.sql`, `@02_programs.sql`, `@03_demo.sql` in that order.

### Recorded output (excerpt from `output/02_programs.out` and `output/03_demo.out`)

```text
OBJECT_NAME              OBJECT_TYPE             STATUS
------------------------ ----------------------- -------
FN_CUSTOMER_AGE          FUNCTION                VALID
FN_CUSTOMER_BALANCE      FUNCTION                VALID
SP_CREATE_RESERVATION    PROCEDURE               VALID
SP_FLAG_SUSPENSIONS      PROCEDURE               VALID
TRG_RR_CAPACITY          TRIGGER                 VALID
TRG_RR_STATEMENT_LOG     TRIGGER                 VALID

=== sp_create_reservation: a valid booking (Aarav, 4 people at MH-01, in 3 days) ===
trg_rr_statement_log: one INSERT statement finished on Rentals_Reservations
created booking 2
=== BR-01 from the row trigger: party of 6 at a 4-seat table ===
refused: ORA-20001: BR-01: party size exceeds table seating capacity
=== BR-01: inactive table ===
refused: ORA-20001: BR-01: table is out of service
=== BR-13: suspended member / member owing more than Rs 500 ===
refused: ORA-20013: BR-13: customer account is not active
refused: ORA-20013: BR-13: outstanding balance above Rs 500
=== BR-14: 15 days ahead / started 2 hours ago ===
refused: ORA-20014: BR-14: bookings open only 14 days ahead
refused: ORA-20014: BR-14: booking cannot start in the past
=== sp_flag_suspensions (cursor FOR loop): Karan owes > 2000 -> Suspended ===
CUSTOMER_ID FIRST_NAME   STATUS        BALANCE          (before)
          1 Aarav        Active              0
          2 Manish       Suspended           0
          3 Karan        Active           2520
CUSTOMER_ID FIRST_NAME   STATUS        BALANCE          (after)
          1 Aarav        Active              0
          2 Manish       Active              0
          3 Karan        Suspended        2520
=== Explicit cursor with OPEN / FETCH / EXIT WHEN %NOTFOUND / CLOSE ===
Aarav     Active
Manish    Active
Karan     Suspended
3 rows fetched
```

## MySQL stored programs vs Oracle PL/SQL

| Topic | MySQL 8.0 (this project) | Oracle PL/SQL |
| --- | --- | --- |
| Ending a program in the client | `DELIMITER $$` … `END$$` … `DELIMITER ;` — a client-side trick so the `;` inside the body does not end the statement | A `/` on a line of its own after `END;` |
| Raising a business error | `SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-13: …'` (client sees ERROR 1644) | `RAISE_APPLICATION_ERROR(-20013, 'BR-13: …')` — user codes −20000 … −20999 (client sees ORA-20013) |
| Handling errors | `DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;` declared at the top of the block | `EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;` section at the bottom of the block; named exceptions such as `NO_DATA_FOUND` |
| `SELECT … INTO` finds no row | Variables keep their old value / NULL, warning 1329 | Raises `NO_DATA_FOUND` (handled in `sp_create_reservation` and `fn_customer_age`) |
| Cursor loop | `DECLARE cur CURSOR FOR …`, `DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE`, `OPEN`, `FETCH` in a `LOOP`, `LEAVE`, `CLOSE` | Cursor `FOR` loop opens, fetches and closes implicitly; or `OPEN` / `FETCH` / `EXIT WHEN cur%NOTFOUND` / `CLOSE`; attributes `%ROWCOUNT`, `%FOUND`; `UPDATE … WHERE CURRENT OF cur` |
| Trigger granularity | `FOR EACH ROW` only | `FOR EACH ROW` **or** statement level (omit `FOR EACH ROW`); also `INSTEAD OF` triggers on views and compound triggers |
| Row values in triggers | `NEW.col`, `OLD.col` | `:NEW.col`, `:OLD.col`; optional `WHEN (NEW.col …)` filter; `INSERTING` / `UPDATING` / `DELETING` predicates |
| Mutating tables | A trigger may read its own table but not modify it (ERROR 1442) | A row trigger may not even read its own table (ORA-04091) — `trg_rr_capacity` reads only `Cafe_Tables` |
| Getting the new key | `LAST_INSERT_ID()` | `INSERT … RETURNING booking_id INTO v_id` |
| Top-N rows | `LIMIT n` (SQL Server: `SELECT TOP n`) | `FETCH FIRST n ROWS ONLY` (12c+) |
| Isolation default | REPEATABLE READ (the procedure switches to READ COMMITTED) | READ COMMITTED (`SET TRANSACTION` must be the first statement of a transaction) |
| Auto-numbering | `AUTO_INCREMENT` | `GENERATED BY DEFAULT AS IDENTITY` (12c+) or a sequence |
| Enumerations / booleans | `ENUM(...)`, `BOOLEAN` (= `TINYINT(1)`) | `VARCHAR2` + `CHECK (col IN (...))`; `NUMBER(1)` + `CHECK` (SQL `BOOLEAN` columns only from 23ai) |
| Derived column | `… AS (expr) STORED` | `… GENERATED ALWAYS AS (expr) VIRTUAL` |
| Anchored types | — | `Customers.status%TYPE`, `%ROWTYPE` |
| Scheduled jobs | `CREATE EVENT … ON SCHEDULE EVERY 15 MINUTE` | `DBMS_SCHEDULER.CREATE_JOB` |
| Printing from a program | `SELECT` a result set | `DBMS_OUTPUT.PUT_LINE` (+ `SET SERVEROUTPUT ON`) |
