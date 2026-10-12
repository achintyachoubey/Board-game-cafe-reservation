# Board Game Café & Table Reservation System

### A relational database project — CSC2103 Relational Database Management Systems

| | |
| --- | --- |
| Student name | ______________________ |
| Roll number | ______________________ |
| Section | ______________________ |
| Faculty | ______________________ |
| Date of submission | ______________________ |

B.Tech Computer Science and Engineering, Semester III
Manipal University Jaipur, July – November 2026
Lab: CSC2131 (RDBMS Lab Manual 2026-27, MySQL)

---

## Abstract

This project designs and implements a relational database for a board game café in MySQL 8.0.
Members book café tables and borrow physical game boxes, either to play at a table (Dine_In) or to
take home (Take_Home). The design is a deliberate variation of the classic Library Management
System, extended with three rules that a library does not have: the size of the group must fit
both the table and the game, every game has a minimum age, and every returned box is inspected for
missing pieces, which are charged to the member. The database has 14 tables in BCNF (two
documented, engine-maintained derived columns aside), 21 CHECK constraints, 14 foreign keys,
6 functions, 11 stored procedures, 10 triggers, 9 views, 3 scheduled events and 3 security roles.
All 20 business rules and 2 payment rules are enforced inside the database, so they hold no matter
which client writes the data. A generated, date-relative seed loads 347 bookings through the real
triggers. A 44-query bank covers retrieval, every join type, aggregation, subqueries, set
operations, window functions and recursive CTEs; demos show SAVEPOINTs, a double-booking race,
isolation levels, a deadlock and index use. An automated test suite of 129 tests — including
TC-01 to TC-36 — passes on MySQL 8.0.46.

## 1. Problem statement

A board game café today keeps bookings in a notebook and a spreadsheet. Two staff members can
promise the same table for the same evening; a group of eight is seated at a four-seat table; a
twelve-year-old takes home an 18+ party game; a box comes back without its dice and nobody knows
who had it last; and members' unpaid amounts are tracked by memory. The café needs a database that
records members, games, boxes, tables, bookings, returns and payments, and that **refuses** any
booking or change that breaks the café's rules — even when two desks book at the same instant.

## 2. Objectives

1. Model the café with an ER diagram (including weak entity, specialization, aggregation) and map
   it to a normalized relational schema (CO1, CO3).
2. Enforce every business rule in the database with constraints, triggers and stored procedures,
   reporting each violation with a rule ID (CO2).
3. Provide workflows as stored procedures: book, check in, check out with inspection, cancel,
   mark no-shows, pay, restock, recommend games and find free tables (CO2).
4. Keep bookings correct under concurrency, and demonstrate transactions, isolation and deadlock
   handling (CO4).
5. Show how indexes are used and when they are not (CO5).
6. Restrict access with roles and least privilege.
7. Prove everything with reproducible builds, captured outputs and an automated test suite.

## 3. Scope

**In scope:** members and membership tiers, staff, game titles, categories, physical copies and
their expected components, café tables, Dine_In and Take_Home bookings, check-in/check-out, return
inspections and missing pieces, late/damage/cancellation fees, payments, an audit trail, scheduled
jobs, roles. **Out of scope:** a user interface (all interaction is through the MySQL client), food
and beverage orders, online payments, multiple branches (see Future scope).

## 4. From library to café — the analogy

| Library Management System | Board Game Café |
| --- | --- |
| Book (title, author, ISBN) | Board game title (`Board_Games`: players, minimum age, play time, rates) |
| Book copy (accession number) | Game box (`Game_Copies`: barcode, condition, status) |
| — | Expected contents of a box (`Game_Components`) |
| Library card / member | Membership (`Customers` + `Membership_Tiers`) |
| Issue / return | Take_Home rental / return with inspection |
| Reading room seat | Café table (`Cafe_Tables`) booked for a time window (Dine_In) |
| Fine for late return | Late fee per started hour/day after a 15-minute grace (BR-16) |
| Lost/damaged book charge | Missing-piece charge (qty × unit cost) and copy status (BR-17/18) |
| Borrowing limit per card type | Concurrent-rental limit, session hours and take-home days per tier (BR-11/12) |
| Reservation queue | Reservations with overlap prevention (BR-05/06) |
| — | Party size must fit table and game (BR-01/02); minimum age (BR-03/04) |

## 5. Requirements

**Functional.** Register members with a tier; maintain games, boxes, components and tables; find
free tables and suitable games for a group; book a table and/or a game for a window; check in;
check out with inspection and missing pieces; compute late, damage and cancellation fees; take
payments; mark overdue rentals and no-shows automatically; suspend members with large debts;
report on popularity, utilization, balances and copies needing attention.

**Non-functional.** Correct under concurrent use (no double-booking); rules enforced in the
database, not the client; history never lost; least-privilege access; MySQL 8.0.31+ with the
default strict `sql_mode`; reproducible build from scripts; every claim backed by a test or a
captured output.

**Business rules.** BR-01 … BR-20 and PAY-01/02 — listed with the enforcing object and an example
of each in [`business_rules.md`](business_rules.md).

## 6. ER design

The full diagram (Mermaid crow's-foot for the 14 tables, plus a step-by-step guide for the Chen
version) is in [`ER_diagram.md`](ER_diagram.md). Its main features:

* **Strong entities**: Membership tier, Customer, Staff, Board game, Game category, Game copy,
  Café table, Payment.
* **Weak entity**: Game component — identified by (game, component name), double rectangle with
  the identifying relationship CONTAINS, total participation, cascade delete.
* **Ternary relationship** BOOKS among Customer, Café table and Game copy (partial participation of
  table and copy), with the time window, party size, status and fees as relationship attributes.
* **Aggregation**: BOOKS is treated as an entity so that INSPECTS (with Staff), FINDS_MISSING (with
  Game component) and PAID_BY (with Payment) can refer to a booking.
* **Specialization** of a booking into DINE_IN and TAKE_HOME — disjoint and total — mapped to one
  table with the discriminator `booking_type` and the CHECK `chk_booking_type_shape`.
* **Generalization** of Customer and Staff into PERSON at the conceptual level (overlapping,
  partial), not mapped to a table.
* **Attribute types**: derived (age, duration, total, balance — dashed ovals), multivalued
  (a game's categories — double oval → M:N table), composite (name → first/last).

The student's four proposed entities remain the centre of the schema: `Customers`, `Board_Games`,
`Cafe_Tables` (renamed: `TABLES` is a reserved word) and the bridge `Rentals_Reservations`
(renamed: `&` is illegal in an identifier). Condition moved from the title to the box because it
depends on the box, not on the game (normalization).

## 7. Relational schema

```text
Membership_Tiers(tier_id PK, tier_name UK, annual_fee, max_concurrent_rentals, max_session_hours,
                 max_takehome_days, discount_pct)
Customers(customer_id PK, first_name, last_name, email UK, phone UK, date_of_birth, tier_id FK,
          join_date, membership_expiry, status)
Staff(staff_id PK, full_name, role, email UK, hired_on, is_active)
Game_Categories(category_id PK, category_name UK)
Board_Games(game_id PK, title, publisher, year_published, min_players, max_players, min_age,
            avg_play_minutes, complexity, hourly_rate, daily_rate, replacement_cost;
            UK(title, publisher))
Board_Game_Categories(game_id PK FK, category_id PK FK)
Game_Copies(copy_id PK, game_id FK, barcode UK, acquired_on, copy_condition, status, shelf_location)
Game_Components(component_id PK, game_id FK, component_name, qty_per_copy, unit_replacement_cost;
                UK(game_id, component_name))
Cafe_Tables(table_id PK, table_code UK, zone, seating_capacity, hourly_rate, is_accessible, is_active)
Rentals_Reservations(booking_id PK, customer_id FK, table_id FK NULL, copy_id FK NULL, booking_type,
                     party_size NULL, reserved_start, reserved_end, duration_minutes (generated),
                     checked_in_at, returned_at, status, base_charge, discount_amount, late_fee,
                     damage_fee, cancellation_fee, total_amount (generated), created_at)
Return_Inspections(inspection_id PK, booking_id FK UK, inspected_by FK, inspected_at,
                   condition_on_return, notes)
Missing_Pieces(inspection_id PK FK, component_id PK FK, qty_missing, charge, restocked_at)
Payments(payment_id PK, booking_id FK, amount, method, paid_at)
Booking_Audit_Log(log_id PK, booking_id FK, old_status, new_status, changed_at, changed_by)
```

Every column, its type, nullability, default and meaning: [`data_dictionary.md`](data_dictionary.md)
(generated from `information_schema`). Built objects, verified by `tests/test_schema.py`:
**14 tables, 9 views, 6 functions, 11 procedures, 10 triggers, 3 events, 3 roles; 14 primary
keys, 14 foreign keys, 21 CHECK constraints, 10 UNIQUE constraints.**

## 8. Normalization

Full derivation in [`normalization.md`](normalization.md): the paper register (UNF) and its update,
insertion and deletion anomalies; 1NF; the FD set f1–f13; Armstrong derivations; the closure
{booking_id}⁺ proving booking_id is a candidate key; 2NF (partial dependencies in the missing-pieces
and categories relations); 3NF (transitive chains through customer, tier, table, copy and game);
canonical cover with an extraneous attribute and a redundant FD; 3NF synthesis; BCNF check of every
table and a 3NF-but-not-BCNF counter-example; lossless-join proof and a lossy counter-example;
dependency preservation; MVDs and 4NF (230 rows → 167 rows on the seed data); and the design
decisions (condition on copies, one bridge table, generated columns, charge snapshot, computed
balance).

## 9. Implementation

| Layer | Objects | File |
| --- | --- | --- |
| Tables | 14, with COMMENTs on every table and column | `sql/01_schema.sql` |
| Functions | `fn_customer_age`, `fn_table_is_free`, `fn_copy_is_free`, `fn_calculate_base_charge`, `fn_calculate_late_fee`, `fn_customer_balance` | `sql/02_functions.sql` |
| Validation | `sp_validate_booking` — BR-01 … BR-12, shared by the two booking triggers | `sql/03_procedures.sql` |
| Workflows | `sp_create_reservation`, `sp_check_in`, `sp_check_out`, `sp_cancel_booking`, `sp_mark_no_shows`, `sp_find_free_tables`, `sp_recommend_games`, `sp_record_payment`, `sp_restock_copy`, `sp_flag_suspensions` (cursor) | `sql/03_procedures.sql` |
| Triggers | BEFORE/AFTER INSERT and UPDATE on bookings, BEFORE DELETE on bookings, BEFORE/AFTER INSERT on inspections and on missing pieces, BEFORE INSERT on payments | `sql/04_triggers.sql` |
| Views | catalog, active bookings, copies available now, overdue rentals, balances, popularity, 30-day utilization, copies needing attention, updatable active-members view WITH CHECK OPTION | `sql/05_views.sql` |
| Events | overdue marking and no-shows every 15 min, suspension check daily | `sql/06_events.sql` |
| Security | roles `cafe_admin`, `front_desk`, `analyst`; users `owner_ravi`, `desk_priya`, `report_bot` | `sql/07_roles.sql` |
| Data | generated, date-relative seed: 30 members, 25 games, 60 copies, 118 components, 16 tables, 347 bookings, 258 inspections, 304 payments | `sql/08_seed.sql`, `scripts/generate_seed.py` |

Design rule followed throughout: checks that must hold for **every row** live in triggers; checks
that depend on **"now"** (start not in the past, at most 14 days ahead, account standing) live in
`sp_create_reservation`. Overlap and availability checks run only for **active** rows, so history
loads cleanly. The pricing is computed by the BEFORE INSERT trigger; `total_amount` is a generated
column; a member's balance is computed, never stored.

The seed is produced by a Python generator with a fixed random seed and written as plain SQL whose
dates are relative to the load date, so it loads on any day without Python. Every row goes through
the real triggers. It contains guaranteed fixtures used by the tests (a member who has played every
Party game, a Suspended member, an expired member, a member owing more than ₹500, copies in
Missing_Pieces / Under_Repair / Retired, an inactive table that was never booked, members aged 14
and 16, one overdue and one checked-out rental, 20 future reservations).

## 10. Transactions and concurrency

* **Atomic workflows.** `sp_check_out` inserts the inspection, parses the missing pieces from a
  JSON array with `JSON_TABLE`, computes the late fee and completes the booking in one transaction;
  an EXIT HANDLER rolls everything back and re-signals the original error. TC-22/23 confirm that a
  bad component leaves no inspection row and the booking still Checked_In.
* **Preventing double-booking.** `sp_create_reservation` switches to READ COMMITTED and locks the
  contested rows with `SELECT … FOR UPDATE` in a fixed order (table → copy → customer) **before**
  any plain read. A second desk booking the same table waits on the row lock; when the first
  commits, the second's overlap check — a fresh READ COMMITTED read inside the trigger — sees the
  committed booking and fails with BR-05. This is strict two-phase locking: locks are held until
  COMMIT. TC-31 runs four desks at the same instant: exactly one succeeds.
* **SAVEPOINT (T1)**, **race (T2)**, **isolation levels (T3)** and **deadlock (T4)** were executed
  on real connections; the observed outcomes are recorded below and in
  [`query_results.md`](query_results.md).

<!-- BEGIN OUTPUT T2 -->
#### T2 · Double-booking race: two front desks book the same table and slot.

Run on two real connections (Session A, Session B). Each step was sent in the order shown; a step still running 2 s later is reported as **waited**.

**[AB0] Session A** - Both sessions: the same slot, table and two different members

```sql
USE boardgame_cafe_evidence;
```
_OK - rows affected: 0_

```sql
SET @start = TIMESTAMP(CURRENT_DATE + INTERVAL 2 DAY, '19:00:00');
```
_(value stored in a session variable)_

```sql
SET @end   = TIMESTAMP(CURRENT_DATE + INTERVAL 2 DAY, '21:00:00');
```
_(value stored in a session variable)_

```sql
SELECT table_id INTO @t FROM Cafe_Tables
 WHERE is_active AND seating_capacity >= 2 AND fn_table_is_free(table_id, @start, @end, NULL)
 ORDER BY seating_capacity, hourly_rate, table_code LIMIT 1;
```
_(value stored in a session variable)_

```sql
SELECT customer_id INTO @cust_a FROM Customers
 WHERE status = 'Active' AND membership_expiry >= DATE(@end)
   AND fn_customer_balance(customer_id) <= 500
 ORDER BY customer_id LIMIT 1;
```
_(value stored in a session variable)_

```sql
SELECT customer_id INTO @cust_b FROM Customers
 WHERE status = 'Active' AND membership_expiry >= DATE(@end)
   AND fn_customer_balance(customer_id) <= 500
 ORDER BY customer_id LIMIT 1 OFFSET 1;
```
_(value stored in a session variable)_

```sql
SELECT @t AS table_id, @start AS slot_start, @end AS slot_end, @cust_a AS member_a, @cust_b AS member_b;
```
**1 row**

| table_id | slot_start | slot_end | member_a | member_b |
|---|---|---|---|---|
| 14 | 2026-10-14 19:00:00 | 2026-10-14 21:00:00 | 1 | 2 |

**[AB0] Session B** - Both sessions: the same slot, table and two different members

```sql
USE boardgame_cafe_evidence;
```
_OK - rows affected: 0_

```sql
SET @start = TIMESTAMP(CURRENT_DATE + INTERVAL 2 DAY, '19:00:00');
```
_(value stored in a session variable)_

```sql
SET @end   = TIMESTAMP(CURRENT_DATE + INTERVAL 2 DAY, '21:00:00');
```
_(value stored in a session variable)_

```sql
SELECT table_id INTO @t FROM Cafe_Tables
 WHERE is_active AND seating_capacity >= 2 AND fn_table_is_free(table_id, @start, @end, NULL)
 ORDER BY seating_capacity, hourly_rate, table_code LIMIT 1;
```
_(value stored in a session variable)_

```sql
SELECT customer_id INTO @cust_a FROM Customers
 WHERE status = 'Active' AND membership_expiry >= DATE(@end)
   AND fn_customer_balance(customer_id) <= 500
 ORDER BY customer_id LIMIT 1;
```
_(value stored in a session variable)_

```sql
SELECT customer_id INTO @cust_b FROM Customers
 WHERE status = 'Active' AND membership_expiry >= DATE(@end)
   AND fn_customer_balance(customer_id) <= 500
 ORDER BY customer_id LIMIT 1 OFFSET 1;
```
_(value stored in a session variable)_

```sql
SELECT @t AS table_id, @start AS slot_start, @end AS slot_end, @cust_a AS member_a, @cust_b AS member_b;
```
**1 row**

| table_id | slot_start | slot_end | member_a | member_b |
|---|---|---|---|---|
| 14 | 2026-10-14 19:00:00 | 2026-10-14 21:00:00 | 1 | 2 |

**[A1] Session A** - Session A: lock the table row, insert, do NOT commit yet

```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
```
_(value stored in a session variable)_

```sql
START TRANSACTION;
```
_OK - rows affected: 0_

```sql
SELECT table_id FROM Cafe_Tables WHERE table_id = @t FOR UPDATE;
```
**1 row**

| table_id |
|---|
| 14 |

```sql
INSERT INTO Rentals_Reservations (customer_id, table_id, booking_type, party_size,
                                  reserved_start, reserved_end)
VALUES (@cust_a, @t, 'Dine_In', 2, @start, @end);
```
_OK - rows affected: 1_

*Expected:* 1 row inserted (the trigger validated and priced it); the lock on the table row is held

**[B1] Session B** - Session B: the second desk books the same table and slot - **waited 2.3 s** (blocked by a lock)

```sql
CALL sp_create_reservation(@cust_b, 'Dine_In', @t, NULL, 2, @start, @end, @booking_b);
```
**UNEXPECTED ERROR:** `ERROR 1644: BR-05: table already booked for an overlapping time`

*Expected:* WAITS - the procedure's SELECT ... FOR UPDATE on the same Cafe_Tables row blocks

**[A2] Session A** - Session A: commit

```sql
COMMIT;
```
_OK - rows affected: 0_

*Expected:* Session B wakes up and fails: ERROR 1644 (45000): BR-05: table already booked for an overlapping time

**[B2] Session B** - Session B: check the result

```sql
SELECT @booking_b AS booking_b;
```
**1 row**

| booking_b |
|---|
| NULL |

```sql
SELECT booking_id, customer_id, status FROM Rentals_Reservations
 WHERE table_id = @t AND reserved_start = @start AND status = 'Reserved';
```
**1 row**

| booking_id | customer_id | status |
|---|---|---|
| 349 | 1 | Reserved |

*Expected:* booking_b is NULL; exactly one Reserved row, owned by member_a

> Observed: [B1] B waited 2.3 s; Session B then failed with ERROR 1644: BR-05: table already booked for an overlapping time.
<!-- END OUTPUT T2 -->

## 11. Indexing

InnoDB stores each table as a B+ tree clustered on the primary key; secondary indexes are B+ trees
holding the key columns plus the primary key. Secondary indexes created: `idx_customer_name
(last_name, first_name)`, `idx_copy_game_status`, `idx_rr_table_window (table_id, reserved_start,
reserved_end)`, `idx_rr_copy_window`, `idx_rr_customer_status`, `idx_rr_status_end`, `idx_rr_start`,
`idx_pay_paid_at` (plus the indexes behind every UNIQUE and FK). X1 shows the optimizer using
`idx_customer_name` (`ref`), a forced full scan with `IGNORE INDEX`, a non-sargable `DATE()`
predicate scanning the table, the sargable rewrite using `idx_rr_start` (`range`), and
`EXPLAIN ANALYZE` of the BR-05 overlap check as a covering range scan on `idx_rr_table_window`:

<!-- BEGIN OUTPUT X1 -->
#### X1 · See the optimizer use, and not use, an index.

*Concept:* EXPLAIN / EXPLAIN ANALYZE, sargable vs non-sargable predicates   Lab: CO5

```sql
-- The B+ tree indexes on the bookings table (PRIMARY = the clustered index)
SHOW INDEX FROM Rentals_Reservations;
```

**12 rows** (first 10 shown)

| Table | Non_unique | Key_name | Seq_in_index | Column_name | Collation | Cardinality | Sub_part | Packed | Null | Index_type | Comment | Index_comment | Visible | Expression |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Rentals_Reservations | 0 | PRIMARY | 1 | booking_id | A | 325 | NULL | NULL |  | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_table_window | 1 | table_id | A | 16 | NULL | NULL | YES | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_table_window | 2 | reserved_start | A | 325 | NULL | NULL |  | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_table_window | 3 | reserved_end | A | 325 | NULL | NULL |  | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_copy_window | 1 | copy_id | A | 57 | NULL | NULL | YES | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_copy_window | 2 | reserved_start | A | 325 | NULL | NULL |  | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_copy_window | 3 | reserved_end | A | 325 | NULL | NULL |  | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_customer_status | 1 | customer_id | A | 30 | NULL | NULL |  | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_customer_status | 2 | status | A | 61 | NULL | NULL |  | BTREE |  |  | YES | NULL |
| Rentals_Reservations | 1 | idx_rr_status_end | 1 | status | A | 3 | NULL | NULL |  | BTREE |  |  | YES | NULL |

```sql
-- Uses idx_customer_name (type = ref)
EXPLAIN SELECT customer_id, first_name, phone FROM Customers WHERE last_name = 'Sharma';
```

**1 row**

| id | select_type | table | partitions | type | possible_keys | key | key_len | ref | rows | filtered | Extra |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | SIMPLE | Customers | NULL | ref | idx_customer_name | idx_customer_name | 202 | const | 1 | 100.0 | NULL |

```sql
-- Same query forced to scan (type = ALL)
EXPLAIN SELECT customer_id, first_name, phone FROM Customers IGNORE INDEX (idx_customer_name)
 WHERE last_name = 'Sharma';
```

**1 row**

| id | select_type | table | partitions | type | possible_keys | key | key_len | ref | rows | filtered | Extra |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | SIMPLE | Customers | NULL | ALL | NULL | NULL | NULL | NULL | 30 | 3.33 | Using where |

```sql
-- Non-sargable: wrapping the column in DATE() hides idx_rr_start
EXPLAIN SELECT * FROM Rentals_Reservations WHERE DATE(reserved_start) = CURRENT_DATE;
```

**1 row**

| id | select_type | table | partitions | type | possible_keys | key | key_len | ref | rows | filtered | Extra |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | SIMPLE | Rentals_Reservations | NULL | ALL | NULL | NULL | NULL | NULL | 347 | 100.0 | Using where |

```sql
-- Sargable range: uses idx_rr_start
EXPLAIN SELECT * FROM Rentals_Reservations
 WHERE reserved_start >= CURRENT_DATE AND reserved_start < CURRENT_DATE + INTERVAL 1 DAY;
```

**1 row**

| id | select_type | table | partitions | type | possible_keys | key | key_len | ref | rows | filtered | Extra |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | SIMPLE | Rentals_Reservations | NULL | range | idx_rr_start | idx_rr_start | 5 | NULL | 1 | 100.0 | Using index condition |

```sql
-- Real timings for the overlap check behind BR-05
EXPLAIN ANALYZE SELECT COUNT(*) FROM Rentals_Reservations
 WHERE table_id = 3 AND reserved_start < NOW() + INTERVAL 1 DAY AND reserved_end > NOW();
```

**1 row**

```text
-> Aggregate: count(0)  (cost=5.44 rows=1) (actual time=0.0272..0.0273 rows=1 loops=1)
    -> Filter: ((Rentals_Reservations.table_id = 3) and (Rentals_Reservations.reserved_start < <cache>((now() + interval 1 day))) and (Rentals_Reservations.reserved_end > <cache>(now())))  (cost=4.41 rows=10.3) (actual time=0.0257..0.0257 rows=0 loops=1)
        -> Covering index range scan on Rentals_Reservations using idx_rr_table_window over (table_id = 3 AND reserved_start < '2026-10-13 19:05:05')  (cost=4.41 rows=31) (actual time=0.0163..0.0201 rows=31 loops=1)

```
<!-- END OUTPUT X1 -->

## 12. Security

* `front_desk` can SELECT four operational views, SELECT/INSERT/UPDATE the active-members view and
  EXECUTE the workflow procedures — but cannot write any table directly. Because procedures run
  with **definer rights**, `desk_priya` can book (`CALL sp_create_reservation`) without INSERT on
  `Rentals_Reservations`, and every booking still passes through the rules.
* `analyst` sees only three reporting views. `cafe_admin` has everything.
* The REVOKE demo removes `sp_cancel_booking` from the front desk.
* TC-36: `report_bot` reading `Customers` and `desk_priya` inserting into `Payments` both get
  ERROR 1142, while `desk_priya` can CALL `sp_find_free_tables`. L3 shows that `REVOKE ALL` does not
  remove a granted role but `REVOKE 'analyst' FROM …` does.

## 13. Testing

`pytest` builds a fresh database with a random name (roles and users get the same suffix), runs the
suite and drops everything. **Final run: 129 passed, 0 failed, 0 skipped** (MySQL 8.0.46, Python 3.13).

| File | Tests | Covers |
| --- | --- | --- |
| `tests/test_business_rules.py` | 45 | TC-01 … TC-30, TC-32, TC-33, TC-34 and 12 extra cases |
| `tests/test_concurrency.py` | 4 | TC-31 (4-desk race), T2, T3, TC-35 (T4 deadlock) |
| `tests/test_queries.py` | 65 | Q01–Q44, T1, X1, L1–L3 each run (49 parametrized) + 16 result checks incl. the walkthrough |
| `tests/test_schema.py` | 11 | object and constraint counts, comments, no FLOAT, no stored balance, no FULL JOIN / TOP |
| `tests/test_security.py` | 4 | TC-36 and the role/REVOKE demo |
| **Total** | **129** | |

| TC | Scenario | Result |
| --- | --- | --- |
| TC-01 | Party of 6 at a 4-seat table | BR-01 ✔ |
| TC-02 | Party of 4 at a 4-seat table | accepted ✔ |
| TC-03 | Party of 2 with a 3–5 player game | BR-02 ✔ |
| TC-04 | 14-year-old books an 18+ game | BR-03 ✔ |
| TC-05 | 16-year-old Take_Home | BR-04 ✔ |
| TC-06 | Overlapping table booking 15:30–17:00 over 14:00–16:00 | BR-05 ✔ |
| TC-07 | Touching window 16:00–18:00 | accepted ✔ |
| TC-08 | Cancel 14:00–16:00, rebook it | accepted ✔ |
| TC-09 | Same copy, overlapping windows | BR-06 ✔ |
| TC-10 | Book a Missing_Pieces copy | BR-07 ✔ |
| TC-11 | Dine_In without table; Take_Home with table | BR-08 (both) ✔ |
| TC-12 | Dine_In at :15; lasting 45 minutes | CHECK `chk_rr_dinein_slots` ✔ |
| TC-13 | Dine_In 21:30–23:30 | BR-10 ✔ |
| TC-14 | Basic member books 5 hours | BR-11 ✔ |
| TC-15 | Basic member, second concurrent rental | BR-12 ✔ |
| TC-16 | Suspended / expired / owes > ₹500 | BR-13 ×3 ✔ |
| TC-17 | 15 days ahead; started 2 h ago | BR-14 ×2 ✔ |
| TC-18 | Reserved → Completed; Completed → Reserved | BR-15 ×2 ✔ |
| TC-19 | Dine_In 40 / 75 min late (₹150/h table + ₹50/h game) | ₹300 / ₹600 ✔ |
| TC-20 | 10 minutes late | ₹0 ✔ |
| TC-21 | Take_Home returned with 2 × ₹15 pieces missing | damage ₹30, copy Missing_Pieces, balance + total ✔ |
| TC-22 | Component of another game | BR-17, whole check-out rolled back ✔ |
| TC-23 | More pieces than the box has | BR-17, rolled back ✔ |
| TC-24 | Returned Damaged | copy Under_Repair ✔ |
| TC-25 | Cancel > 2 h before / < 2 h before | ₹0 / ₹100 ✔ |
| TC-26 | Reserved, start + 31 min, `sp_mark_no_shows` | No_Show, ₹100 ✔ |
| TC-27 | Delete a customer with bookings | FK error 1451 ✔ |
| TC-28 | Overpay a booking | PAY-02 ✔ |
| TC-29 | Gold member, 2 h at ₹150/h | base ₹300, discount ₹60, total ₹240 ✔ |
| TC-30 | Create then complete a booking | exactly 2 audit rows ✔ |
| TC-31 | 4 sessions book one table/slot at once | 1 succeeds, 3 × BR-05 ✔ |
| TC-32 | Q08 after seed and all tests | 0 rows ✔ |
| TC-33 | Delete a Completed booking / a free cancellation | BR-20 / deleted, audit rows cascade ✔ |
| TC-34 | Suspend a member through `vw_active_members` | ERROR 1369 ✔ |
| TC-35 | Deadlock with two connections | one ERROR 1213, the other commits ✔ |
| TC-36 | `report_bot` reads Customers; `desk_priya` inserts Payments | ERROR 1142 ×2; CALL allowed ✔ |

Build: `python scripts/build_db.py` runs 745 statements from `00` to `08` with 0 errors and 0
warnings (on a server where the objects do not exist yet, `DROP … IF EXISTS` produces expected
*notes* 1008 and 3162, which the script reports separately). Every file also runs unchanged in the
`mysql` command-line client.

## 14. Results

Every query and demo was executed on a freshly built database; the complete outputs are in
[`query_results.md`](query_results.md) and, per experiment, in [`lab_record.md`](lab_record.md).
A few highlights:

<!-- BEGIN OUTPUT Q35 -->
#### Q35 · Which members would be refused a booking right now, and why (CASE over a derived table)?

*Concept:* searched CASE returning NULL = "no problem", filter on the derived column   Lab: Exp 8  
*Relational algebra:* σ blocked_because IS NOT NULL (π customer_id,member,CASE… (Customers))

```sql
SELECT *
  FROM (SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member,
               CASE WHEN c.status <> 'Active'                    THEN CONCAT('Account ', c.status)
                    WHEN c.membership_expiry < CURRENT_DATE       THEN 'Membership expired'
                    WHEN fn_customer_balance(c.customer_id) > 500
                         THEN CONCAT('Owes Rs ', fn_customer_balance(c.customer_id))
               END AS blocked_because
          FROM Customers c) AS t
 WHERE blocked_because IS NOT NULL;
```

**3 rows**

| customer_id | member | blocked_because |
|---|---|---|
| 13 | Karan Malhotra | Owes Rs 972.00 |
| 19 | Manish Chauhan | Account Suspended |
| 21 | Varun Bhatia | Membership expired |
<!-- END OUTPUT Q35 -->

<!-- BEGIN OUTPUT Q33 -->
#### Q33 · Who is holding a game past its end time, and what do they owe so far?

*Concept:* querying a view that calls a stored function   Lab: Exp 9  
*Relational algebra:* vw_overdue_rentals

```sql
SELECT * FROM vw_overdue_rentals ORDER BY minutes_late DESC;
```

**1 row**

| booking_id | customer | phone | booking_type | game | barcode | reserved_end | minutes_late | late_fee_so_far |
|---|---|---|---|---|---|---|---|---|
| 326 | Siddharth Rao | 9888878901 | Take_Home | Ticket to Ride | 890100203113 | 2026-10-11 12:00:00 | 1865 | 540.00 |
<!-- END OUTPUT Q33 -->

<!-- BEGIN OUTPUT Q34 -->
#### Q34 · Which copies are off the shelf for repair or missing pieces, and what is missing?

*Concept:* querying an aggregating view   Lab: Exp 9  
*Relational algebra:* vw_copies_needing_attention

```sql
SELECT * FROM vw_copies_needing_attention ORDER BY title;
```

**2 rows**

| copy_id | barcode | title | status | copy_condition | missing | charged_to_customers |
|---|---|---|---|---|---|---|
| 2 | 890100102065 | Catan | Missing_Pieces | Fair | 2 x Number tokens; 1 x Settlements | 55.00 |
| 23 | 890100901296 | Jenga | Under_Repair | Damaged | NULL | 0.00 |
<!-- END OUTPUT Q34 -->

<!-- BEGIN OUTPUT Q20 -->
#### Q20 · Who has played every Party game?

*Concept:* relational division (double NOT EXISTS)   Lab: Exp 8  
*Relational algebra:* π customer_id,game_id (RR ⋈ Copies) ÷ π game_id (Party games)

```sql
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member
  FROM Customers c
 WHERE NOT EXISTS (
         SELECT 1
           FROM Board_Game_Categories bgc
           JOIN Game_Categories cat ON cat.category_id = bgc.category_id
          WHERE cat.category_name = 'Party'
            AND NOT EXISTS (
                  SELECT 1
                    FROM Rentals_Reservations rr
                    JOIN Game_Copies gc ON gc.copy_id = rr.copy_id
                   WHERE rr.customer_id = c.customer_id
                     AND rr.status = 'Completed'
                     AND gc.game_id = bgc.game_id));
```

**1 row**

| customer_id | member |
|---|---|
| 9 | Rahul Verma |
<!-- END OUTPUT Q20 -->

<!-- BEGIN OUTPUT Q43 -->
#### Q43 · Plays per game, last 30 days vs the 30 before, including games played in only one window.

*Concept:* FULL OUTER JOIN emulated as LEFT JOIN ∪ RIGHT JOIN (MySQL has no FULL JOIN)   Lab: Exp 7  
*Relational algebra:* recent ⟗ previous = (recent ⟕ previous) ∪ (recent ⟖ previous)

```sql
WITH recent AS (
  SELECT gc.game_id, COUNT(*) AS plays
    FROM Rentals_Reservations rr JOIN Game_Copies gc ON gc.copy_id = rr.copy_id
   WHERE rr.status = 'Completed' AND rr.reserved_start >= CURRENT_DATE - INTERVAL 30 DAY
   GROUP BY gc.game_id
), previous AS (
  SELECT gc.game_id, COUNT(*) AS plays
    FROM Rentals_Reservations rr JOIN Game_Copies gc ON gc.copy_id = rr.copy_id
   WHERE rr.status = 'Completed'
     AND rr.reserved_start >= CURRENT_DATE - INTERVAL 60 DAY
     AND rr.reserved_start <  CURRENT_DATE - INTERVAL 30 DAY
   GROUP BY gc.game_id
), full_outer AS (
  SELECT COALESCE(r.game_id, p.game_id) AS game_id,
         IFNULL(p.plays, 0) AS previous_30d, IFNULL(r.plays, 0) AS last_30d
    FROM recent r LEFT JOIN previous p ON p.game_id = r.game_id
  UNION
  SELECT COALESCE(r.game_id, p.game_id), IFNULL(p.plays, 0), IFNULL(r.plays, 0)
    FROM recent r RIGHT JOIN previous p ON p.game_id = r.game_id
)
SELECT bg.title, f.previous_30d, f.last_30d, f.last_30d - f.previous_30d AS change_
  FROM full_outer f JOIN Board_Games bg ON bg.game_id = f.game_id
 ORDER BY change_ DESC;
```

**24 rows** (first 10 shown)

| title | previous_30d | last_30d | change_ |
|---|---|---|---|
| Werewolf | 2 | 7 | 5 |
| Carcassonne | 4 | 7 | 3 |
| Dixit | 1 | 4 | 3 |
| Terraforming Mars | 0 | 2 | 2 |
| Pandemic | 2 | 4 | 2 |
| Dominion | 1 | 3 | 2 |
| Gloomhaven: Jaws of the Lion | 1 | 3 | 2 |
| Hanabi | 0 | 2 | 2 |
| Wingspan | 2 | 3 | 1 |
| Splendor | 2 | 3 | 1 |
<!-- END OUTPUT Q43 -->

The Oracle PL/SQL versions (Additional Experiment 2) were executed on Oracle Database 23ai Free;
see [`sql/oracle_plsql/README.md`](../sql/oracle_plsql/README.md).

## 15. Conclusion

The café's rules — fitting the group to table and game, age limits, no double-booking, inspection
of every returned box, fees and payments — are enforced entirely by the database: by 21 CHECK
constraints, 14 foreign keys, 10 triggers and 11 procedures. Because the rules live in the database,
a direct INSERT, a procedure call from the front desk and a bulk load are all held to the same
standard, and the concurrency demos show they hold even when several desks book at once. The schema
is normalized to BCNF with two deliberate, engine-maintained derived columns, history is never
deleted, balances are computed rather than stored, and staff get only the access their role needs.
The build is reproducible from scripts, and 129 automated tests pass.

## 16. Future scope

* **Game swaps mid-session** — let a Dine_In group exchange one box for another without closing the
  booking (a booking-to-copies child table with its own time windows).
* **Food and beverage orders** linked to a Dine_In booking, with a menu and order lines.
* **Waitlist** for fully booked slots, promoted automatically when a booking is cancelled
  (an event or an AFTER UPDATE trigger).
* **Multiple branches** — a `Branches` table, tables and copies per branch, transfers of boxes.
* **Reminders** — e-mail/SMS before a reservation and before a take-home is due (events writing to
  an outbox table).
* **Wear prediction** — use inspection history (conditions and missing pieces per play) to predict
  when a box needs replacing.

## 17. References

1. A. Silberschatz, H. F. Korth, S. Sudarshan. *Database System Concepts*, 7th ed., McGraw-Hill, 2019.
2. R. Elmasri, S. B. Navathe. *Fundamentals of Database Systems*, 7th ed., Pearson, 2016.
3. Oracle Corporation. *MySQL 8.0 Reference Manual*. <https://dev.mysql.com/doc/refman/8.0/en/>
4. Manipal University Jaipur. *RDBMS Lab Manual 2026-27 (CSC2131)*.
5. Oracle Corporation. *Oracle Database PL/SQL Language Reference* (for Additional Experiment 2).
