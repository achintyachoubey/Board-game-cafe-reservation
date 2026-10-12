# Lab record — CSC2131 RDBMS Lab (RDBMS Lab Manual 2026-27)

Project: **Board Game Café & Table Reservation System** (MySQL 8.0).
Each experiment below gives the aim, the files in this repository that carry it out, the **exact
SQL from the repo with its real output**, and viva questions with answers.

The output blocks (between the `BEGIN OUTPUT` / `END OUTPUT` HTML comments) are written by
`python scripts/capture_evidence.py`, which builds a fresh database, runs every statement and
pastes what MySQL returned (first 10 rows of each result). Do not edit them by hand — re-run the
script. Dates are relative to the day of the run.

<!-- BEGIN OUTPUT META -->
Captured on 2026-10-12 19:05:06 (server time), MySQL 8.0.46, fresh database `boardgame_cafe_evidence` built from `sql/00`-`08`.
<!-- END OUTPUT META -->

| Exp | Topic | Files |
| --- | --- | --- |
| 1 | ER diagram → relational model, keys | `docs/ER_diagram.md`, `sql/01_schema.sql` |
| 2 | DDL: CREATE / DROP / ALTER / RENAME | `sql/00_drop_all.sql`, `sql/01_schema.sql`, L1 in `sql/12_demo_lab_extras.sql` |
| 3 | Constraints: PK / FK / CHECK / NOT NULL / DEFAULT | `sql/01_schema.sql` |
| 4 | DML: INSERT (multi-row, INSERT … SELECT), UPDATE, DELETE | `sql/08_seed.sql`, Q37–Q40, L1 |
| 5 | SELECT, WHERE, LIKE, DISTINCT, BETWEEN, IN, wildcards | Q01–Q04, Q41 |
| 6 | DISTINCT, COUNT, ORDER BY, GROUP BY, TOP, MAX | Q10–Q14, Q42 |
| 7 | INNER / LEFT / RIGHT / FULL / non-equi joins | Q05–Q09, Q29, Q36, Q43, Q44 |
| 8 | Subqueries | Q13, Q15–Q23, Q35 |
| 9 | Views and operations on views | `sql/05_views.sql`, L2, Q28, Q33, Q34 |
| 10 | GRANT / REVOKE | `sql/07_roles.sql`, L3 |
| 11 | COMMIT / ROLLBACK / SAVEPOINT | `sql/10_demo_transactions.sql` (T1–T4) |
| 12 | Triggers and stored procedures | `sql/03_procedures.sql`, `sql/04_triggers.sql`, `sql/13_walkthrough.sql` |
| Add. 1 | Cursors and functions | `sql/02_functions.sql`, `sp_flag_suspensions` |
| Add. 2 | PL/SQL commands for the project | `sql/06_events.sql`, `sql/oracle_plsql/` |

---

## Experiment 1 — ER diagram to relational model; keys

**Aim.** Design an ER model of the café, map it to relations and identify primary, candidate,
alternate and foreign keys.

**Work done.** The conceptual model (strong entities, the weak entity GAME_COMPONENT, the ternary
BOOKS relationship aggregated for inspections, the Dine_In/Take_Home specialization, multivalued
category, derived age/duration/total) is in [`ER_diagram.md`](ER_diagram.md) with a crow's-foot
diagram of the 14 tables and drawing instructions for the Chen version. Keys:

* **Primary keys**: one per table (14), all surrogate except the two bridge tables with composite
  keys: `Board_Game_Categories(game_id, category_id)`, `Missing_Pieces(inspection_id, component_id)`.
* **Candidate / alternate keys** (UNIQUE, 10): `Customers.email`, `Customers.phone`,
  `Membership_Tiers.tier_name`, `Staff.email`, `Game_Categories.category_name`,
  `Board_Games(title, publisher)`, `Game_Copies.barcode`, `Game_Components(game_id, component_name)`,
  `Cafe_Tables.table_code`, `Return_Inspections.booking_id` (makes the relationship 1 : 0..1).
* **Foreign keys** (14), all `ON DELETE RESTRICT` except the dependent rows that live and die with
  their parent (`ON DELETE CASCADE`: categories of a game, components of a game, missing pieces of an
  inspection, audit rows of a booking).

**Output** (object counts, constraint counts and row counts of the built database):

<!-- BEGIN OUTPUT E1 -->
#### E1 · Schema object counts (Exp 1-3)

```sql
SELECT (SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE') AS tables_,
       (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = DATABASE()) AS views_,
       (SELECT COUNT(*) FROM information_schema.routines
         WHERE routine_schema = DATABASE() AND routine_type = 'FUNCTION') AS functions_,
       (SELECT COUNT(*) FROM information_schema.routines
         WHERE routine_schema = DATABASE() AND routine_type = 'PROCEDURE') AS procedures_,
       (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = DATABASE()) AS triggers_,
       (SELECT COUNT(*) FROM information_schema.events WHERE event_schema = DATABASE()) AS events_;
```

**1 row**

| tables_ | views_ | functions_ | procedures_ | triggers_ | events_ |
|---|---|---|---|---|---|
| 14 | 9 | 6 | 11 | 10 | 3 |

```sql
SELECT constraint_type, COUNT(*) AS how_many
  FROM information_schema.table_constraints
 WHERE table_schema = DATABASE()
 GROUP BY constraint_type ORDER BY constraint_type;
```

**4 rows**

| CONSTRAINT_TYPE | how_many |
|---|---|
| CHECK | 21 |
| FOREIGN KEY | 14 |
| PRIMARY KEY | 14 |
| UNIQUE | 10 |

```sql
SELECT table_name, table_rows_exact FROM (
  SELECT 'Membership_Tiers' AS table_name, (SELECT COUNT(*) FROM Membership_Tiers) AS table_rows_exact
  UNION ALL SELECT 'Customers', (SELECT COUNT(*) FROM Customers)
  UNION ALL SELECT 'Staff', (SELECT COUNT(*) FROM Staff)
  UNION ALL SELECT 'Game_Categories', (SELECT COUNT(*) FROM Game_Categories)
  UNION ALL SELECT 'Board_Games', (SELECT COUNT(*) FROM Board_Games)
  UNION ALL SELECT 'Board_Game_Categories', (SELECT COUNT(*) FROM Board_Game_Categories)
  UNION ALL SELECT 'Game_Copies', (SELECT COUNT(*) FROM Game_Copies)
  UNION ALL SELECT 'Game_Components', (SELECT COUNT(*) FROM Game_Components)
  UNION ALL SELECT 'Cafe_Tables', (SELECT COUNT(*) FROM Cafe_Tables)
  UNION ALL SELECT 'Rentals_Reservations', (SELECT COUNT(*) FROM Rentals_Reservations)
  UNION ALL SELECT 'Return_Inspections', (SELECT COUNT(*) FROM Return_Inspections)
  UNION ALL SELECT 'Missing_Pieces', (SELECT COUNT(*) FROM Missing_Pieces)
  UNION ALL SELECT 'Payments', (SELECT COUNT(*) FROM Payments)
  UNION ALL SELECT 'Booking_Audit_Log', (SELECT COUNT(*) FROM Booking_Audit_Log)) AS t;
```

**14 rows** (first 10 shown)

| table_name | table_rows_exact |
|---|---|
| Membership_Tiers | 3 |
| Customers | 31 |
| Staff | 8 |
| Game_Categories | 10 |
| Board_Games | 25 |
| Board_Game_Categories | 49 |
| Game_Copies | 61 |
| Game_Components | 119 |
| Cafe_Tables | 16 |
| Rentals_Reservations | 348 |
<!-- END OUTPUT E1 -->

**Viva.**
* *Why does `Game_Components` have a surrogate key if it is a weak entity?* — Its natural key is
  (game_id, component_name), which is kept as `UNIQUE`; the surrogate `component_id` is just a short
  FK target for `Missing_Pieces`.
* *How is the ternary relationship BOOKS mapped?* — To one table `Rentals_Reservations` with FKs to
  the three participants; `table_id` and `copy_id` are nullable because participation is partial
  (take-home has no table, table-only has no copy).
* *Why were `Tables` and `Rentals_&_Reservations` renamed?* — `TABLES` is a reserved word and `&` is
  illegal in an unquoted identifier; hence `Cafe_Tables` and `Rentals_Reservations`.

---

## Experiment 2 — DDL: CREATE, ALTER, RENAME, TRUNCATE, DROP

**Aim.** Create, alter, rename and drop tables and databases.

**Work done.** `sql/01_schema.sql` creates the database and the 14 tables;
`sql/00_drop_all.sql` drops the database, roles and users idempotently (`IF EXISTS`). L1 practises
every DDL statement on a sandbox table so the real schema is not disturbed.

<!-- BEGIN OUTPUT L1 -->
#### L1 · DDL on a sandbox table: CREATE, ALTER (add, modify, constraint, rename column), RENAME, TRUNCATE, DROP (Exp 2).

```sql
CREATE TABLE Event_Nights (
  night_id   INT AUTO_INCREMENT PRIMARY KEY,
  theme      VARCHAR(60) NOT NULL,
  night_date DATE NOT NULL
);
```

_OK - rows affected: 0_

```sql
ALTER TABLE Event_Nights ADD COLUMN entry_fee DECIMAL(8,2) NOT NULL DEFAULT 0;
```

_OK - rows affected: 0_

```sql
ALTER TABLE Event_Nights MODIFY COLUMN theme VARCHAR(100) NOT NULL;
```

_OK - rows affected: 0_

```sql
ALTER TABLE Event_Nights ADD CONSTRAINT chk_event_fee CHECK (entry_fee >= 0);
```

_OK - rows affected: 0_

```sql
ALTER TABLE Event_Nights RENAME COLUMN night_date TO event_date;
```

_OK - rows affected: 0_

```sql
RENAME TABLE Event_Nights TO Theme_Nights;
```

_OK - rows affected: 0_

```sql
INSERT INTO Theme_Nights (theme, event_date, entry_fee)                    -- multi-row INSERT (Exp 4)
VALUES ('Catan tournament', CURRENT_DATE + INTERVAL 7 DAY, 200.00),
       ('Werewolf Friday',  CURRENT_DATE + INTERVAL 4 DAY,   0.00);
```

_OK - rows affected: 2_

```sql
DESCRIBE Theme_Nights;
```

**4 rows**

| Field | Type | Null | Key | Default | Extra |
|---|---|---|---|---|---|
| night_id | int | NO | PRI | NULL | auto_increment |
| theme | varchar(100) | NO |  | NULL |  |
| event_date | date | NO |  | NULL |  |
| entry_fee | decimal(8,2) | NO |  | 0.00 |  |

```sql
SELECT * FROM Theme_Nights;
```

**2 rows**

| night_id | theme | event_date | entry_fee |
|---|---|---|---|
| 1 | Catan tournament | 2026-10-19 | 200.00 |
| 2 | Werewolf Friday | 2026-10-16 | 0.00 |

```sql
TRUNCATE TABLE Theme_Nights;  -- DDL: removes all rows, resets AUTO_INCREMENT, cannot be rolled back
```

_OK - rows affected: 0_

```sql
DROP TABLE Theme_Nights;
```

_OK - rows affected: 0_

```sql
CREATE DATABASE IF NOT EXISTS cafe_sandbox;
```

_OK - rows affected: 1_

```sql
DROP DATABASE cafe_sandbox;
```

_OK - rows affected: 0_
<!-- END OUTPUT L1 -->

**Viva.**
* *DELETE vs TRUNCATE vs DROP?* — `DELETE` is DML: removes chosen rows, fires triggers, can be rolled
  back. `TRUNCATE` is DDL: removes all rows, resets AUTO_INCREMENT, implicit commit, no triggers.
  `DROP` removes the table definition as well.
* *Can DDL be rolled back in MySQL?* — No: DDL statements cause an implicit commit.
* *`ALTER TABLE … RENAME COLUMN` vs `CHANGE COLUMN`?* — RENAME COLUMN only renames; CHANGE renames
  and redefines the type in one go; MODIFY changes the type only.

---

## Experiment 3 — Constraints: PRIMARY KEY, FOREIGN KEY, CHECK, NOT NULL, DEFAULT

**Aim.** Enforce integrity declaratively and observe each constraint rejecting bad data.

**Work done.** 21 named CHECK constraints (e.g. `chk_customer_phone` uses `REGEXP_LIKE`,
`chk_booking_type_shape` encodes the Dine_In/Take_Home shape, `chk_rr_dinein_slots` the :00/:30
rule), 14 FKs, NOT NULL on every mandatory column, DEFAULTs including the expression default
`join_date DEFAULT (CURRENT_DATE)`. The statements below try to break each kind of constraint:

<!-- BEGIN OUTPUT E2 -->
#### E2 · Constraints at work: CHECK, UNIQUE, FOREIGN KEY, NOT NULL, DEFAULT (Exp 3)

```sql
INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id, membership_expiry)
VALUES ('Test', 'Member', 'not-an-email', '9000000001', '2000-01-01', 1, CURRENT_DATE + INTERVAL 1 YEAR);
```

**expected error:** `ERROR 3819: Check constraint 'chk_customer_email' is violated.`

```sql
INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id, membership_expiry)
SELECT 'Test', 'Member', email, '9000000002', '2000-01-01', 1, CURRENT_DATE + INTERVAL 1 YEAR
  FROM Customers WHERE customer_id = 1;
```

**expected error:** `ERROR 1062: Duplicate entry 'aarav.mehta@mail.test' for key 'Customers.email'`

```sql
INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id, membership_expiry)
VALUES ('Test', 'Member', 'test.member@mail.test', '9000000003', '2000-01-01', 9, CURRENT_DATE + INTERVAL 1 YEAR);
```

**expected error:** `ERROR 1452: Cannot add or update a child row: a foreign key constraint fails (`boardgame_cafe_evidence`.`Customers`, CONSTRAINT `fk_customer_tier` FOREIGN KEY (`tier_id`) REFERENCES `Membership_Tiers` (`tier_id`) ON DELETE RESTRICT)`

```sql
INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id, membership_expiry)
VALUES ('Test', NULL, 'test.member@mail.test', '9000000004', '2000-01-01', 1, CURRENT_DATE + INTERVAL 1 YEAR);
```

**expected error:** `ERROR 1048: Column 'last_name' cannot be null`

```sql
DELETE FROM Membership_Tiers WHERE tier_id = 1;
```

**expected error:** `ERROR 1451: Cannot delete or update a parent row: a foreign key constraint fails (`boardgame_cafe_evidence`.`Customers`, CONSTRAINT `fk_customer_tier` FOREIGN KEY (`tier_id`) REFERENCES `Membership_Tiers` (`tier_id`) ON DELETE RESTRICT)`

```sql
SELECT column_name, column_default FROM information_schema.columns
 WHERE table_schema = DATABASE() AND table_name = 'Customers' AND column_default IS NOT NULL;
```

**2 rows**

| COLUMN_NAME | COLUMN_DEFAULT |
|---|---|
| join_date | curdate() |
| status | Active |
<!-- END OUTPUT E2 -->

**Viva.**
* *Are CHECK constraints enforced in MySQL?* — Yes, since 8.0.16 (earlier versions parsed and
  ignored them). Violation = ERROR 3819.
* *Why can't a CHECK enforce "no overlapping bookings"?* — A CHECK sees only the row being written;
  overlap compares rows with each other, so it needs a trigger (BR-05).
* *What does `ON DELETE RESTRICT` do?* — Refuses to delete a parent row that still has children
  (ERROR 1451); it is how BR-20 keeps history.

---

## Experiment 4 — DML: multi-row INSERT, INSERT … SELECT, UPDATE, DELETE

**Aim.** Insert, modify and delete data, including set-based forms.

**Work done.** `sql/08_seed.sql` (generated) loads the data with **multi-row INSERTs** (tiers,
staff, categories, games, copies, components, tables, members), per-row INSERTs for bookings (so
each passes the triggers), a multi-table **UPDATE** (restocking), and an **INSERT … SELECT** that
records payments for every closed booking:

```sql
INSERT INTO Payments (booking_id, amount, method, paid_at)
SELECT booking_id, total_amount, ELT(1 + booking_id % 3, 'Cash', 'Card', 'UPI'),
       COALESCE(returned_at, reserved_start)
  FROM Rentals_Reservations
 WHERE status IN ('Completed', 'Cancelled', 'No_Show') AND total_amount > 0
   AND booking_id NOT IN (...)
 ORDER BY booking_id;
```

The query bank's DML (Q37–Q40) on the seeded database:

<!-- BEGIN OUTPUT Q37 -->
#### Q37 · Retire worn copies that have come back short 3 or more times (UPDATE with JOIN to a derived table).

*Concept:* multi-table UPDATE with a derived table   Lab: Exp 4  
*Relational algebra:* (DML) target = σ condition∈{Worn,Damaged} ∧ bad_returns≥3 (Game_Copies ⋈ γ copy; COUNT(DISTINCT inspection) (…))

```sql
UPDATE Game_Copies gc
  JOIN (SELECT rr.copy_id, COUNT(DISTINCT mp.inspection_id) AS bad_returns
          FROM Missing_Pieces mp
          JOIN Return_Inspections ri   ON ri.inspection_id = mp.inspection_id
          JOIN Rentals_Reservations rr ON rr.booking_id    = ri.booking_id
         GROUP BY rr.copy_id) AS losses ON losses.copy_id = gc.copy_id
   SET gc.status = 'Retired'
 WHERE gc.copy_condition IN ('Worn', 'Damaged')
   AND losses.bad_returns >= 3
   AND gc.status <> 'Rented';
```

_OK - rows affected: 0_
<!-- END OUTPUT Q37 -->

<!-- BEGIN OUTPUT Q38 -->
#### Q38 · Buy a new copy of every game that has no copy in service (INSERT … SELECT).

*Concept:* INSERT … SELECT with NOT EXISTS   Lab: Exp 4  
*Relational algebra:* (DML) Game_Copies ← Game_Copies ∪ π …(Board_Games − π game (σ Available∨Rented (Game_Copies)))

```sql
INSERT INTO Game_Copies (game_id, barcode, acquired_on, copy_condition, status, shelf_location)
SELECT bg.game_id,
       CONCAT('BG', LPAD(bg.game_id, 4, '0'), DATE_FORMAT(CURRENT_DATE, '%y%m%d')),
       CURRENT_DATE, 'New', 'Available', 'NEW-ARR'
  FROM Board_Games bg
 WHERE NOT EXISTS (SELECT 1 FROM Game_Copies gc
                    WHERE gc.game_id = bg.game_id
                      AND gc.status IN ('Available', 'Rented'));
```

_OK - rows affected: 1_
<!-- END OUTPUT Q38 -->

<!-- BEGIN OUTPUT Q39 -->
#### Q39 · Add a component or update its price if it already exists (upsert).

*Concept:* INSERT … ON DUPLICATE KEY UPDATE with a row alias (8.0.19+)   Lab: Exp 4  
*Relational algebra:* (DML) upsert on the alternate key (game_id, component_name)

```sql
INSERT INTO Game_Components (game_id, component_name, qty_per_copy, unit_replacement_cost)
VALUES (1, 'Robber pawn', 1, 40.00) AS new_row
ON DUPLICATE KEY UPDATE unit_replacement_cost = new_row.unit_replacement_cost;
```

_OK - rows affected: 1_
<!-- END OUTPUT Q39 -->

<!-- BEGIN OUTPUT Q40 -->
#### Q40 · Purge audit entries older than 2 years for closed bookings (DELETE with subquery).

*Concept:* DELETE with an IN subquery on another table   Lab: Exp 4  
*Relational algebra:* (DML) Booking_Audit_Log ← Booking_Audit_Log − σ old ∧ booking∈closed (Booking_Audit_Log)

```sql
DELETE FROM Booking_Audit_Log
 WHERE changed_at < NOW() - INTERVAL 2 YEAR
   AND booking_id IN (SELECT booking_id FROM Rentals_Reservations
                       WHERE status IN ('Completed', 'Cancelled', 'No_Show'));
```

_OK - rows affected: 0_
<!-- END OUTPUT Q40 -->

(Q38 inserts one copy: in the seed both Jenga boxes are out of service — one Retired, one
Under_Repair. Q39 reports 1 row affected because 'Robber pawn' is new; MySQL reports 2 when an
existing row is updated and 0 when the update changes nothing. Q37 and Q40 have nothing to do on
fresh data: 0 rows.)

**Viva.**
* *Why are the historical bookings inserted one row per statement?* — So the reader can see each;
  a multi-row INSERT would also fire the row triggers once per row.
* *What does `ON DUPLICATE KEY UPDATE` need?* — A PRIMARY KEY or UNIQUE index that the new row
  collides with — here `uq_component (game_id, component_name)`.
* *Why does the seed insert payments before the future reservations?* — Otherwise every member with
  history owes more than ₹500 and `sp_create_reservation` correctly refuses them (BR-13).

---

## Experiment 5 — SELECT with WHERE, LIKE, DISTINCT, BETWEEN, IN and wildcards

**Aim.** Retrieve rows with simple and compound conditions.

<!-- BEGIN OUTPUT Q01 -->
#### Q01 · Which games suit a group of 5, youngest player 10, under an hour?

*Concept:* WHERE with BETWEEN, comparison, ORDER BY   Lab: Exp 5  
*Relational algebra:* π title,… (σ min_players≤5≤max_players ∧ min_age≤10 ∧ avg_play_minutes≤60 (Board_Games))

```sql
SELECT title, min_players, max_players, min_age, avg_play_minutes, complexity
  FROM Board_Games
 WHERE 5 BETWEEN min_players AND max_players
   AND min_age <= 10
   AND avg_play_minutes <= 60
 ORDER BY complexity, title;
```

**11 rows** (first 10 shown)

| title | min_players | max_players | min_age | avg_play_minutes | complexity |
|---|---|---|---|---|---|
| Jenga | 1 | 8 | 6 | 20 | 1.0 |
| Uno | 2 | 10 | 7 | 30 | 1.0 |
| Exploding Kittens | 2 | 5 | 7 | 15 | 1.1 |
| Dixit | 3 | 8 | 8 | 30 | 1.2 |
| Sushi Go Party! | 2 | 8 | 8 | 20 | 1.3 |
| Werewolf | 5 | 10 | 10 | 30 | 1.3 |
| Hanabi | 2 | 5 | 8 | 25 | 1.7 |
| Ticket to Ride | 2 | 5 | 8 | 60 | 1.8 |
| Carcassonne | 2 | 5 | 7 | 45 | 1.9 |
| The Crew | 3 | 5 | 10 | 20 | 2.0 |
<!-- END OUTPUT Q01 -->

<!-- BEGIN OUTPUT Q04 -->
#### Q04 · Find a member from a partial name or the last digits of a phone number (LIKE).

*Concept:* LIKE with % wildcards, OR   Lab: Exp 5  
*Relational algebra:* π customer_id,… (σ first_name LIKE 'Ar%' ∨ last_name LIKE '%sh%' ∨ phone LIKE '%4321' (Customers))

```sql
SELECT customer_id, first_name, last_name, phone
  FROM Customers
 WHERE first_name LIKE 'Ar%' OR last_name LIKE '%sh%' OR phone LIKE '%4321';
```

**9 rows**

| customer_id | first_name | last_name | phone |
|---|---|---|---|
| 5 | Vikram | Singh | 9820054321 |
| 7 | Arjun | Sharma | 9870078901 |
| 11 | Aditya | Joshi | 9822212345 |
| 12 | Meera | Krishnan | 9833323456 |
| 22 | Riya | Ghosh | 9745632109 |
| 24 | Lakshmi | Venkatesh | 9767854321 |
| 26 | Anjali | Mishra | 9789076543 |
| 28 | Zoya | Qureshi | 9701298765 |
| 29 | Arnav | Bose | 8801309876 |
<!-- END OUTPUT Q04 -->

<!-- BEGIN OUTPUT Q41 -->
#### Q41 · Which zones hosted a booking in the last 30 days? (DISTINCT, BETWEEN, IN, NOT IN, the `_` wildcard)

*Concept:* DISTINCT, BETWEEN, IN, NOT IN, LIKE with _   Lab: Exp 5  
*Relational algebra:* π zone (σ start∈[today−30,today] ∧ status∈{…} ∧ capacity∉{2} ∧ code LIKE '__-0_' (RR ⋈ Cafe_Tables))

```sql
SELECT DISTINCT ct.zone
  FROM Rentals_Reservations rr
  JOIN Cafe_Tables ct ON ct.table_id = rr.table_id
 WHERE rr.reserved_start BETWEEN CURRENT_DATE - INTERVAL 30 DAY AND CURRENT_DATE
   AND rr.status IN ('Completed', 'Checked_In')
   AND ct.seating_capacity NOT IN (2)
   AND ct.table_code LIKE '__-0_';  -- each _ matches exactly one character
```

**4 rows**

| zone |
|---|
| Main_Hall |
| Quiet_Corner |
| Party_Room |
| Patio |
<!-- END OUTPUT Q41 -->

Q02 (expiring memberships, `BETWEEN` on dates) and Q03 (`IN` list) are in
[`query_results.md`](query_results.md).

**Viva.**
* *`%` vs `_`?* — `%` matches any number of characters (including none), `_` exactly one.
  `'__-0_'` matches `MH-01` but not `MH-10`.
* *Is BETWEEN inclusive?* — Yes, on both ends. For DATETIME ranges prefer `>= start AND < end`.
* *Why is `NOT IN` dangerous with subqueries?* — If the subquery returns a NULL, `x NOT IN (…)` is
  never true. Q17 is safe because `customer_id` is NOT NULL.

---

## Experiment 6 — DISTINCT, COUNT, ORDER BY, GROUP BY, TOP, MAX

**Aim.** Summarise data with aggregate functions and groups.

<!-- BEGIN OUTPUT Q10 -->
#### Q10 · Revenue by month and booking type, with subtotals (GROUP BY … WITH ROLLUP).

*Concept:* GROUP BY on an expression alias, WITH ROLLUP super-aggregates   Lab: Exp 6  
*Relational algebra:* γ month,booking_type; COUNT(*),SUM(total_amount) (σ closed (RR))

```sql
SELECT DATE_FORMAT(reserved_start, '%Y-%m') AS month, booking_type,
       COUNT(*) AS bookings, SUM(total_amount) AS revenue
  FROM Rentals_Reservations
 WHERE status IN ('Completed', 'Cancelled', 'No_Show')
 GROUP BY month, booking_type WITH ROLLUP;
```

**13 rows** (first 10 shown)

| month | booking_type | bookings | revenue |
|---|---|---|---|
| 2026-07 | Dine_In | 52 | 27792.00 |
| 2026-07 | Take_Home | 11 | 2502.00 |
| 2026-07 | NULL | 63 | 30294.00 |
| 2026-08 | Dine_In | 92 | 41179.00 |
| 2026-08 | Take_Home | 19 | 4258.00 |
| 2026-08 | NULL | 111 | 45437.00 |
| 2026-09 | Dine_In | 88 | 56789.00 |
| 2026-09 | Take_Home | 22 | 5896.00 |
| 2026-09 | NULL | 110 | 62685.00 |
| 2026-10 | Dine_In | 34 | 16444.00 |
<!-- END OUTPUT Q10 -->

<!-- BEGIN OUTPUT Q11 -->
#### Q11 · Which zones average more than 3 guests per booking (HAVING)?

*Concept:* HAVING filters groups after aggregation   Lab: Exp 6  
*Relational algebra:* σ avg_party>3 (γ zone; COUNT(*),AVG(party_size) (σ Completed (RR) ⋈ Cafe_Tables))

```sql
SELECT ct.zone, COUNT(*) AS bookings, ROUND(AVG(rr.party_size), 2) AS avg_party,
       ROUND(100 * AVG(rr.party_size / ct.seating_capacity), 1) AS avg_seat_fill_pct
  FROM Rentals_Reservations rr
  JOIN Cafe_Tables ct ON ct.table_id = rr.table_id
 WHERE rr.status = 'Completed'
 GROUP BY ct.zone
HAVING AVG(rr.party_size) > 3;
```

**3 rows**

| zone | bookings | avg_party | avg_seat_fill_pct |
|---|---|---|---|
| Main_Hall | 72 | 4.83 | 93.9 |
| Patio | 70 | 3.87 | 91.1 |
| Party_Room | 58 | 5.48 | 78.7 |
<!-- END OUTPUT Q11 -->

<!-- BEGIN OUTPUT Q42 -->
#### Q42 · Top 5 games by plays, with group-size and session-length extremes.

*Concept:* COUNT, MIN, MAX, AVG, ORDER BY, LIMIT (MySQL's answer to SELECT TOP)   Lab: Exp 6  
*Relational algebra:* γ game; COUNT,MIN,MAX,AVG (σ Completed ∧ Dine_In (RR) ⋈ Game_Copies ⋈ Board_Games), first 5

```sql
SELECT bg.title, COUNT(rr.booking_id) AS plays,
       MIN(rr.party_size) AS smallest_group, MAX(rr.party_size) AS largest_group,
       ROUND(AVG(rr.duration_minutes)) AS avg_minutes
  FROM Board_Games bg
  JOIN Game_Copies gc          ON gc.game_id = bg.game_id
  JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id
 WHERE rr.status = 'Completed' AND rr.booking_type = 'Dine_In'
 GROUP BY bg.game_id, bg.title
 ORDER BY plays DESC
 LIMIT 5;
```

**5 rows**

| title | plays | smallest_group | largest_group | avg_minutes |
|---|---|---|---|---|
| Cards Against Humanity | 22 | 4 | 8 | 180 |
| Uno | 22 | 2 | 8 | 146 |
| Exploding Kittens | 18 | 2 | 5 | 130 |
| Sushi Go Party! | 13 | 2 | 8 | 164 |
| Trivial Pursuit | 13 | 2 | 6 | 111 |
<!-- END OUTPUT Q42 -->

**Lab-manual correction — `TOP`.** `SELECT TOP n …` is SQL Server syntax. MySQL uses `LIMIT n`
(Q42) and Oracle `FETCH FIRST n ROWS ONLY` (see `sql/oracle_plsql/03_demo.sql`). Observed on
MySQL 8.0.46:

```text
mysql> SELECT TOP 2 * FROM state;
ERROR 1064 (42000): You have an error in your SQL syntax; ... near '2 * FROM state' at line 1
```

**Viva.**
* *WHERE vs HAVING?* — WHERE filters rows before grouping, HAVING filters groups after aggregation
  (Q11 keeps zones whose average party > 3).
* *What does `ONLY_FULL_GROUP_BY` require?* — Every selected non-aggregated column must be in GROUP
  BY or functionally dependent on it; every query here passes under the default `sql_mode`.
* *What does `WITH ROLLUP` add?* — Super-aggregate rows (subtotal per month, grand total) with NULL
  in the rolled-up column (Q10).

---

## Experiment 7 — INNER, LEFT, RIGHT, FULL and non-equi joins

**Aim.** Combine tables with every kind of join.

<!-- BEGIN OUTPUT Q05 -->
#### Q05 · Today's floor plan: every booking with customer, table and game (INNER + LEFT JOIN).

*Concept:* INNER JOIN + LEFT OUTER JOIN chain, sargable date range   Lab: Exp 7  
*Relational algebra:* σ start∈today (RR) ⋈ Customers ⟕ Cafe_Tables ⟕ Game_Copies ⟕ Board_Games

```sql
SELECT rr.booking_id, TIME(rr.reserved_start) AS starts, TIME(rr.reserved_end) AS ends,
       CONCAT(c.first_name, ' ', c.last_name) AS customer, rr.party_size,
       ct.table_code, ct.zone, IFNULL(bg.title, '(table only)') AS game, rr.status
  FROM Rentals_Reservations rr
  JOIN Customers c         ON c.customer_id = rr.customer_id
  LEFT JOIN Cafe_Tables ct ON ct.table_id   = rr.table_id
  LEFT JOIN Game_Copies gc ON gc.copy_id    = rr.copy_id
  LEFT JOIN Board_Games bg ON bg.game_id    = gc.game_id
 WHERE rr.reserved_start >= CURRENT_DATE
   AND rr.reserved_start <  CURRENT_DATE + INTERVAL 1 DAY
 ORDER BY rr.reserved_start, ct.table_code;
```

**1 row**

| booking_id | starts | ends | customer | party_size | table_code | zone | game | status |
|---|---|---|---|---|---|---|---|---|
| 347 | 20:05:00 | 20:05:00 | Sneha Reddy | NULL | NULL | NULL | Uno | Reserved |
<!-- END OUTPUT Q05 -->

<!-- BEGIN OUTPUT Q09 -->
#### Q09 · How many returns has each staff member inspected, including staff with none (RIGHT JOIN)?

*Concept:* RIGHT OUTER JOIN + COUNT(column) ignores NULLs   Lab: Exp 7  
*Relational algebra:* γ staff_id; COUNT(inspection_id) (Return_Inspections ⟖ Staff)

```sql
SELECT s.full_name, s.role, COUNT(ri.inspection_id) AS inspections
  FROM Return_Inspections ri
 RIGHT JOIN Staff s ON s.staff_id = ri.inspected_by
 GROUP BY s.staff_id, s.full_name, s.role
 ORDER BY inspections DESC;
```

**8 rows**

| full_name | role | inspections |
|---|---|---|
| Nandini Rao | Game_Guru | 59 |
| Rakesh Iyer | Manager | 56 |
| Shreya Das | Game_Guru | 47 |
| Farhan Ali | Game_Guru | 43 |
| Gaurav Menon | Game_Guru | 40 |
| Deepak Yadav | Front_Desk | 13 |
| Kiran Joshi | Front_Desk | 0 |
| Asha Fernandes | Front_Desk | 0 |
<!-- END OUTPUT Q09 -->

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

<!-- BEGIN OUTPUT Q44 -->
#### Q44 · For each pending reservation, every table that could seat the group and how many seats would sit empty.

*Concept:* non-equi join (join condition is >=, not =)   Lab: Exp 7  
*Relational algebra:* σ Reserved ∧ Dine_In (RR) ⋈ capacity≥party_size ∧ is_active Cafe_Tables (theta join)

```sql
SELECT rr.booking_id, rr.party_size, ct.table_code, ct.seating_capacity,
       ct.seating_capacity - rr.party_size AS empty_seats
  FROM Rentals_Reservations rr
  JOIN Cafe_Tables ct
    ON ct.seating_capacity >= rr.party_size      -- join condition is >=, not =
   AND ct.is_active
 WHERE rr.status = 'Reserved' AND rr.booking_type = 'Dine_In'
 ORDER BY rr.booking_id, empty_seats;
```

**170 rows** (first 10 shown)

| booking_id | party_size | table_code | seating_capacity | empty_seats |
|---|---|---|---|---|
| 328 | 3 | MH-01 | 4 | 1 |
| 328 | 3 | MH-02 | 4 | 1 |
| 328 | 3 | QC-03 | 4 | 1 |
| 328 | 3 | PA-01 | 4 | 1 |
| 328 | 3 | PA-04 | 4 | 1 |
| 328 | 3 | MH-03 | 6 | 3 |
| 328 | 3 | PR-03 | 6 | 3 |
| 328 | 3 | PA-02 | 6 | 3 |
| 328 | 3 | MH-05 | 8 | 5 |
| 328 | 3 | PR-02 | 8 | 5 |
<!-- END OUTPUT Q44 -->

Self-join (Q08, must be empty), anti-join (Q07), CROSS JOIN (Q29) and the copy self-join (Q36) are in
[`query_results.md`](query_results.md).

**Lab-manual correction — FULL JOIN.** MySQL has no FULL OUTER JOIN. The manual's
`select * from state full join info on ID=info.OID;` does **not** fail: MySQL reads `full` as an
**alias for `state`** and `join` as an inner join, so it silently returns only the matching rows.
Observed on MySQL 8.0.46 with `state` = {1 Rajasthan, 2 Kerala, 3 Goa} and
`info` = {1 Jaipur, 2 Thiruvananthapuram, 4 Shimla}:

```text
mysql> select * from state full join info on ID=info.OID;
+------+-----------+------+--------------------+
| ID   | sname     | OID  | capital            |
+------+-----------+------+--------------------+
|    1 | Rajasthan |    1 | Jaipur             |
|    2 | Kerala    |    2 | Thiruvananthapuram |
+------+-----------+------+--------------------+          <- Goa and Shimla are missing

mysql> SELECT full.sname FROM state full JOIN info ON ID = info.OID;   -- proof: "full" is an alias
+-----------+
| sname     |
+-----------+
| Rajasthan |
| Kerala    |
+-----------+

mysql> SELECT s.ID, s.sname, i.OID, i.capital FROM state s LEFT JOIN info i ON s.ID = i.OID
    -> UNION
    -> SELECT s.ID, s.sname, i.OID, i.capital FROM state s RIGHT JOIN info i ON s.ID = i.OID;
+------+-----------+------+--------------------+
| ID   | sname     | OID  | capital            |
+------+-----------+------+--------------------+
|    1 | Rajasthan |    1 | Jaipur             |
|    2 | Kerala    |    2 | Thiruvananthapuram |
|    3 | Goa       | NULL | NULL               |
| NULL | NULL      |    4 | Shimla             |
+------+-----------+------+--------------------+
```

Use the `LEFT JOIN … UNION … RIGHT JOIN` form, as Q43 does.

**Viva.**
* *Why UNION and not UNION ALL in the FULL JOIN emulation?* — Matching rows appear in both halves;
  UNION removes those duplicates. (UNION ALL works if the second half keeps only `WHERE r.game_id IS NULL`.)
* *Why is the 7-day filter of Q07 in the ON clause?* — In WHERE it would discard the NULL rows the
  LEFT JOIN produced, turning it into an inner join.
* *What is a non-equi join?* — A join whose condition is not equality: Q44 uses
  `seating_capacity >= party_size`.

---

## Experiment 8 — Subqueries

**Aim.** Nested, correlated and set-valued subqueries; relational division; set operators.

<!-- BEGIN OUTPUT Q16 -->
#### Q16 · Which games have never been played (NOT EXISTS anti-join)?

*Concept:* correlated NOT EXISTS   Lab: Exp 8  
*Relational algebra:* π title (Board_Games) − π title (Board_Games ⋈ Game_Copies ⋈ RR)

```sql
SELECT bg.title
  FROM Board_Games bg
 WHERE NOT EXISTS (SELECT 1
                     FROM Game_Copies gc
                     JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id
                    WHERE gc.game_id = bg.game_id);
```

**1 row**

| title |
|---|
| Chess |
<!-- END OUTPUT Q16 -->

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

<!-- BEGIN OUTPUT Q23 -->
#### Q23 · Tables that have never been booked at all (EXCEPT).

*Concept:* EXCEPT (MySQL 8.0.31+) inside an IN subquery   Lab: Exp 8  
*Relational algebra:* π table_id (Cafe_Tables) − π table_id (σ table_id IS NOT NULL (RR))

```sql
SELECT ct.table_code, ct.zone
  FROM Cafe_Tables ct
 WHERE ct.table_id IN (SELECT table_id FROM Cafe_Tables
                       EXCEPT
                       SELECT table_id FROM Rentals_Reservations WHERE table_id IS NOT NULL);
```

**1 row**

| table_code | zone |
|---|---|
| PA-05 | Patio |
<!-- END OUTPUT Q23 -->

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

Q13 (derived table + EXISTS), Q15 (subquery in HAVING), Q17 (IN / NOT IN), Q18 (correlated MAX),
Q19 (`> ALL`), Q21 (UNION) and Q22 (INTERSECT) are in [`query_results.md`](query_results.md).

**Viva.**
* *How does the double NOT EXISTS implement division?* — "There is no Party game that this member
  has not completed" ⇔ the member completed every Party game (Q20).
* *Correlated vs non-correlated subquery?* — A correlated subquery refers to the outer row and is
  (logically) evaluated once per outer row (Q18); a non-correlated one is evaluated once.
* *INTERSECT / EXCEPT in MySQL?* — Available from 8.0.31 (Q22, Q23); before that, use IN / NOT EXISTS.

---

## Experiment 9 — Views and operations on views

**Aim.** Create views, query them, and insert/update through an updatable view with CHECK OPTION.

**Work done.** Nine views in `sql/05_views.sql`. `vw_active_members` is updatable and declared
`WITH CASCADED CHECK OPTION`; it includes every NOT NULL column without a default, so INSERT works.

<!-- BEGIN OUTPUT L2 -->
#### L2 · Operations on a view: SELECT, INSERT and UPDATE through vw_active_members,

```sql
SELECT customer_id, first_name, tier_id, status FROM vw_active_members LIMIT 5;
```

**5 rows**

| customer_id | first_name | tier_id | status |
|---|---|---|---|
| 1 | Aarav | 3 | Active |
| 2 | Ananya | 2 | Active |
| 3 | Rohan | 1 | Active |
| 4 | Priya | 2 | Active |
| 5 | Vikram | 3 | Active |

```sql
INSERT INTO vw_active_members (first_name, last_name, email, phone, date_of_birth,
                               tier_id, membership_expiry, status)
VALUES ('Lavanya', 'Rao', 'lavanya.rao@mail.test', '9876501234', '2001-04-09',
        2, CURRENT_DATE + INTERVAL 1 YEAR, 'Active');  -- lands in Customers
```

_OK - rows affected: 1_

```sql
UPDATE vw_active_members SET tier_id = 3 WHERE email = 'lavanya.rao@mail.test';
```

_OK - rows affected: 1_

```sql
UPDATE vw_active_members SET status = 'Suspended'
 WHERE email = 'lavanya.rao@mail.test';  -- ERROR 1369: CHECK OPTION failed
```

**expected error:** `ERROR 1369: CHECK OPTION failed 'boardgame_cafe_evidence.vw_active_members'`

```sql
SELECT customer_id, first_name, last_name, tier_id, status, join_date
  FROM Customers WHERE email = 'lavanya.rao@mail.test';  -- the base table row: Gold, still Active
```

**1 row**

| customer_id | first_name | last_name | tier_id | status | join_date |
|---|---|---|---|---|---|
| 31 | Lavanya | Rao | 3 | Active | 2026-10-12 |
<!-- END OUTPUT L2 -->

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

**Viva.**
* *When is a view updatable?* — One base table (or a key-preserving join), no aggregates, DISTINCT,
  GROUP BY, UNION or subquery in the select list. `vw_customer_balances` is not updatable.
* *What does WITH CHECK OPTION do?* — Rejects an INSERT/UPDATE through the view that would produce a
  row the view cannot see (ERROR 1369). CASCADED also applies the checks of underlying views.
* *Why do the roles get views and not tables?* — Least privilege: a view exposes only chosen columns
  and rows (e.g. analysts see balances, not phone numbers of every member).

---

## Experiment 10 — GRANT and REVOKE

**Aim.** Control access with users, roles and privileges.

**Work done.** `sql/07_roles.sql` creates roles `cafe_admin` (everything), `front_desk` (four views,
updatable member view, EXECUTE on the workflow procedures — no direct table writes) and `analyst`
(three reporting views), users `desk_priya`, `owner_ravi`, `report_bot`, and demonstrates REVOKE.
Procedures run with **definer rights**, so the front desk can create a booking without INSERT on
the table. L3 adds WITH GRANT OPTION, REVOKE ALL and proves least privilege by logging in as the
users:

<!-- BEGIN OUTPUT L3 -->
#### L3 · More DCL: WITH GRANT OPTION, REVOKE ALL, and proving least privilege (Exp 10).

```sql
GRANT SELECT ON boardgame_cafe.vw_game_catalog TO 'owner_ravi'@'localhost' WITH GRANT OPTION;
```

_OK - rows affected: 0_

```sql
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'report_bot'@'localhost';
```

_OK - rows affected: 0_

```sql
SHOW GRANTS FOR 'report_bot'@'localhost';  -- the analyst role is still listed
```

**2 rows**

| Grants for report_bot_evidence@% |
|---|
| GRANT USAGE ON *.* TO `report_bot_evidence`@`%` |
| GRANT `analyst_evidence`@`%` TO `report_bot_evidence`@`%` |

```sql
-- Logged in as report_bot:
SELECT COUNT(*) FROM boardgame_cafe.vw_game_popularity;  -- allowed through the role
```

**1 row**

| COUNT(*) |
|---|
| 25 |

```sql
SELECT COUNT(*) FROM boardgame_cafe.Customers;  -- ERROR 1142: SELECT command denied
```

**expected error:** `ERROR 1142: SELECT command denied to user 'report_bot_evidence'@'172.18.0.1' for table 'Customers'`

```sql
-- Logged in as desk_priya:
CALL boardgame_cafe.sp_find_free_tables(4, NOW() + INTERVAL 1 DAY, NOW() + INTERVAL 1 DAY + INTERVAL 2 HOUR, FALSE);  -- allowed
```

**9 rows**

| table_id | table_code | zone | seating_capacity | hourly_rate | is_accessible |
|---|---|---|---|---|---|
| 12 | PA-01 | Patio | 4 | 120.00 | 1 |
| 15 | PA-04 | Patio | 4 | 120.00 | 0 |
| 8 | QC-03 | Quiet_Corner | 4 | 140.00 | 0 |
| 13 | PA-02 | Patio | 6 | 180.00 | 0 |
| 3 | MH-03 | Main_Hall | 6 | 200.00 | 0 |
| 11 | PR-03 | Party_Room | 6 | 220.00 | 0 |
| 5 | MH-05 | Main_Hall | 8 | 250.00 | 0 |
| 10 | PR-02 | Party_Room | 8 | 300.00 | 0 |
| 9 | PR-01 | Party_Room | 10 | 350.00 | 0 |

```sql
INSERT INTO boardgame_cafe.Payments (booking_id, amount, method) VALUES (1, 1, 'UPI');  -- ERROR 1142: INSERT denied
```

**expected error:** `ERROR 1142: INSERT command denied to user 'desk_priya_evidence'@'172.18.0.1' for table 'Payments'`

```sql
-- Back as the administrator: REVOKE ALL did not remove the role; revoking the ROLE does.
SHOW GRANTS FOR 'owner_ravi'@'localhost';
```

**3 rows**

| Grants for owner_ravi_evidence@% |
|---|
| GRANT USAGE ON *.* TO `owner_ravi_evidence`@`%` |
| GRANT SELECT ON `boardgame_cafe_evidence`.`vw_game_catalog` TO `owner_ravi_evidence`@`%` WITH GRANT OPTION |
| GRANT `cafe_admin_evidence`@`%` TO `owner_ravi_evidence`@`%` |

```sql
REVOKE 'analyst' FROM 'report_bot'@'localhost';
```

_OK - rows affected: 0_

```sql
SHOW GRANTS FOR 'report_bot'@'localhost';  -- only USAGE left: no access at all
```

**1 row**

| Grants for report_bot_evidence@% |
|---|
| GRANT USAGE ON *.* TO `report_bot_evidence`@`%` |

```sql
GRANT 'analyst' TO 'report_bot'@'localhost';  -- restore the demo account
```

_OK - rows affected: 0_

```sql
SET DEFAULT ROLE ALL TO 'report_bot'@'localhost';
```

_(value stored in a session variable)_
<!-- END OUTPUT L3 -->

(In the evidence run the users carry the suffix `_evidence` and the host `%`; in your own build they
are `desk_priya`, `owner_ravi`, `report_bot`.)

**Viva.**
* *Does `REVOKE ALL PRIVILEGES` remove a granted role?* — No. Roles are revoked separately with
  `REVOKE 'analyst' FROM user` — shown at the end of L3.
* *Why `SET DEFAULT ROLE ALL`?* — Granted roles are inactive in a new session unless they are
  default roles (or activated with `SET ROLE`).
* *What is WITH GRANT OPTION?* — The grantee may pass the privilege on to others.

---

## Experiment 11 — COMMIT, ROLLBACK, SAVEPOINT; concurrency

**Aim.** Control transactions and observe isolation, locking and deadlocks.

**T1 — SAVEPOINT** (one session):

<!-- BEGIN OUTPUT T1 -->
#### T1 · SAVEPOINT: keep a good payment, undo a bad one.

*Concept:* a failed statement rolls back only itself; ROLLBACK TO SAVEPOINT

```sql
-- Pick a Completed booking with at least Rs 200 still unpaid
SELECT rr.booking_id INTO @b
  FROM Rentals_Reservations rr
 WHERE rr.status = 'Completed'
   AND rr.total_amount - (SELECT IFNULL(SUM(p.amount), 0) FROM Payments p
                           WHERE p.booking_id = rr.booking_id) >= 200
 ORDER BY rr.booking_id
 LIMIT 1;
```

_(value stored in a session variable)_

```sql
SELECT rr.booking_id, rr.total_amount,
       (SELECT IFNULL(SUM(amount), 0) FROM Payments WHERE booking_id = rr.booking_id) AS paid_before
  FROM Rentals_Reservations rr WHERE rr.booking_id = @b;
```

**1 row**

| booking_id | total_amount | paid_before |
|---|---|---|
| 234 | 1000.00 | 0.00 |

```sql
START TRANSACTION;
```

_OK - rows affected: 0_

```sql
INSERT INTO Payments (booking_id, amount, method) VALUES (@b, 200.00, 'UPI');
```

_OK - rows affected: 1_

```sql
SAVEPOINT after_first_payment;
```

_OK - rows affected: 0_

```sql
INSERT INTO Payments (booking_id, amount, method) VALUES (@b, 99999.00, 'Cash');  -- PAY-02 error
```

**expected error:** `ERROR 1644: PAY-02: payment exceeds the amount due`

```sql
ROLLBACK TO SAVEPOINT after_first_payment;
```

_OK - rows affected: 0_

```sql
COMMIT;  -- only the ₹200 payment is saved
```

_OK - rows affected: 0_

```sql
SELECT rr.booking_id, rr.total_amount,
       (SELECT IFNULL(SUM(amount), 0) FROM Payments WHERE booking_id = rr.booking_id) AS paid_after
  FROM Rentals_Reservations rr WHERE rr.booking_id = @b;
```

**1 row**

| booking_id | total_amount | paid_after |
|---|---|---|
| 234 | 1000.00 | 200.00 |
<!-- END OUTPUT T1 -->

**T2 — double-booking race** (two sessions; executed on two real connections):

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

**T3 — READ COMMITTED vs REPEATABLE READ** (two sessions):

<!-- BEGIN OUTPUT T3 -->
#### T3 · Isolation levels: a non-repeatable read under READ COMMITTED that

Run on two real connections (Session A, Session B). Each step was sent in the order shown; a step still running 2 s later is reported as **waited**.

**[AB0] Session A** - Both sessions

```sql
USE boardgame_cafe_evidence;
```
_OK - rows affected: 0_

```sql
SELECT MIN(table_id) INTO @t FROM Cafe_Tables WHERE is_active;
```
_(value stored in a session variable)_

**[AB0] Session B** - Both sessions

```sql
USE boardgame_cafe_evidence;
```
_OK - rows affected: 0_

```sql
SELECT MIN(table_id) INTO @t FROM Cafe_Tables WHERE is_active;
```
_(value stored in a session variable)_

**[A1] Session A** - Session A: READ COMMITTED, first read

```sql
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```
_(value stored in a session variable)_

```sql
START TRANSACTION;
```
_OK - rows affected: 0_

```sql
SELECT hourly_rate AS rc_first_read FROM Cafe_Tables WHERE table_id = @t;
```
**1 row**

| rc_first_read |
|---|
| 150.00 |

*Expected:* the current rate, e.g. 150.00

**[B1] Session B** - Session B: change the rate (autocommit)

```sql
UPDATE Cafe_Tables SET hourly_rate = hourly_rate + 10 WHERE table_id = @t;
```
_OK - rows affected: 1_

**[A2] Session A** - Session A: read again inside the SAME transaction

```sql
SELECT hourly_rate AS rc_second_read FROM Cafe_Tables WHERE table_id = @t;
```
**1 row**

| rc_second_read |
|---|
| 160.00 |

```sql
COMMIT;
```
_OK - rows affected: 0_

*Expected:* 10 more than the first read - a NON-REPEATABLE READ

**[A3] Session A** - Session A: REPEATABLE READ, first read

```sql
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```
_(value stored in a session variable)_

```sql
START TRANSACTION;
```
_OK - rows affected: 0_

```sql
SELECT hourly_rate AS rr_first_read FROM Cafe_Tables WHERE table_id = @t;
```
**1 row**

| rr_first_read |
|---|
| 160.00 |

**[B2] Session B** - Session B: put the rate back (autocommit)

```sql
UPDATE Cafe_Tables SET hourly_rate = hourly_rate - 10 WHERE table_id = @t;
```
_OK - rows affected: 1_

**[A4] Session A** - Session A: read again, commit, read once more

```sql
SELECT hourly_rate AS rr_second_read FROM Cafe_Tables WHERE table_id = @t;
```
**1 row**

| rr_second_read |
|---|
| 160.00 |

```sql
COMMIT;
```
_OK - rows affected: 0_

```sql
SELECT hourly_rate AS after_commit FROM Cafe_Tables WHERE table_id = @t;
```
**1 row**

| after_commit |
|---|
| 150.00 |

*Expected:* rr_second_read = rr_first_read (snapshot); after_commit shows B's change

> Observed: READ COMMITTED read 150.00 then 160.00 in the same transaction (non-repeatable read); REPEATABLE READ read 160.00 then 160.00 (snapshot), and 150.00 after COMMIT.
<!-- END OUTPUT T3 -->

**T4 — deadlock** (two sessions):

<!-- BEGIN OUTPUT T4 -->
#### T4 · Deadlock: A locks copy 1 then wants copy 2; B locks copy 2 then wants

Run on two real connections (Session A, Session B). Each step was sent in the order shown; a step still running 2 s later is reported as **waited**.

**[AB0] Session A** - Both sessions

```sql
USE boardgame_cafe_evidence;
```
_OK - rows affected: 0_

**[AB0] Session B** - Both sessions

```sql
USE boardgame_cafe_evidence;
```
_OK - rows affected: 0_

**[A1] Session A** - Session A: lock copy 1

```sql
START TRANSACTION;
```
_OK - rows affected: 0_

```sql
SELECT copy_id, status FROM Game_Copies WHERE copy_id = 1 FOR UPDATE;
```
**1 row**

| copy_id | status |
|---|---|
| 1 | Available |

**[B1] Session B** - Session B: lock copy 2

```sql
START TRANSACTION;
```
_OK - rows affected: 0_

```sql
SELECT copy_id, status FROM Game_Copies WHERE copy_id = 2 FOR UPDATE;
```
**1 row**

| copy_id | status |
|---|---|
| 2 | Missing_Pieces |

**[A2] Session A** - Session A: now ask for copy 2 - **waited 2.3 s** (blocked by a lock)

```sql
SELECT copy_id, status FROM Game_Copies WHERE copy_id = 2 FOR UPDATE;
```
**1 row**

| copy_id | status |
|---|---|
| 2 | Missing_Pieces |

*Expected:* WAITS for Session B

**[B2] Session B** - Session B: now ask for copy 1 - the cycle closes

```sql
SELECT copy_id, status FROM Game_Copies WHERE copy_id = 1 FOR UPDATE;
```
**UNEXPECTED ERROR:** `ERROR 1213: Deadlock found when trying to get lock; try restarting transaction`

*Expected:* one session gets ERROR 1213 (40001): Deadlock found when trying to get lock;

**[A3] Session A** - Session A

```sql
COMMIT;
```
_OK - rows affected: 0_

**[B3] Session B** - Session B

```sql
COMMIT;
```
_OK - rows affected: 0_

*Expected:* the surviving transaction commits; the victim's COMMIT has nothing left to commit

> Observed: [A2] A waited 2.3 s; Session B got ERROR 1213 at step [B2] and was rolled back; the other session committed.
<!-- END OUTPUT T4 -->

**Viva.**
* *ACID in this project?* — Atomicity: `sp_check_out` writes the inspection, missing pieces, late fee
  and status in one transaction and rolls all back on any error (TC-22). Consistency: constraints and
  triggers. Isolation: READ COMMITTED + `FOR UPDATE` in `sp_create_reservation`. Durability: InnoDB
  redo log.
* *Why lock with `FOR UPDATE` before the overlap check?* — Without it two sessions could both read
  "table free" before either inserts (a write-skew / phantom problem). Locking the table's row
  serializes bookings for that table; this is two-phase locking — locks are held until COMMIT.
* *How does InnoDB handle the deadlock?* — It detects the cycle in the wait-for graph immediately,
  rolls back one transaction (ERROR 1213) and lets the other continue. A fixed lock order
  (table → copy → customer) prevents it in the real procedure.

---

## Experiment 12 — Triggers and stored procedures

**Aim.** Encode business rules in triggers and workflows in stored procedures.

**Work done.** 11 procedures (`sql/03_procedures.sql`) and 10 triggers (`sql/04_triggers.sql`):
BEFORE INSERT/UPDATE validation and pricing, AFTER INSERT/UPDATE auditing, BEFORE DELETE protecting
history, triggers on inspections, missing pieces and payments. Rules refusing bad bookings:

<!-- BEGIN OUTPUT E3 -->
#### E3 · A business rule refusing a booking (BR-01) and the error the client sees (Exp 12)

```sql
SELECT table_id INTO @small FROM Cafe_Tables WHERE seating_capacity = 4 AND is_active
 ORDER BY table_id LIMIT 1;
```

_(value stored in a session variable)_

```sql
CALL sp_create_reservation(3, 'Dine_In', @small, NULL, 6,
     TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '18:00:00'),
     TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '20:00:00'), @nope);
```

**expected error:** `ERROR 1644: BR-01: party size exceeds table seating capacity`

```sql
CALL sp_create_reservation(19, 'Dine_In', @small, NULL, 2,
     TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '18:00:00'),
     TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '20:00:00'), @nope);
```

**expected error:** `ERROR 1644: BR-13: customer account is not active`

```sql
UPDATE Rentals_Reservations SET status = 'Reserved' WHERE status = 'Completed' ORDER BY booking_id LIMIT 1;
```

**expected error:** `ERROR 1644: BR-15: invalid status transition`

```sql
DELETE FROM Rentals_Reservations WHERE status = 'Completed' ORDER BY booking_id LIMIT 1;
```

**expected error:** `ERROR 1644: BR-20: only free cancellations can be deleted; history is kept`
<!-- END OUTPUT E3 -->

The complete workflow, `sql/13_walkthrough.sql`:

<!-- BEGIN OUTPUT WALK -->
#### WALK · End-to-end walkthrough: book, check in, return with missing pieces, pay, restock

```sql
-- 0. When, and which kind of booking ------------------------------------------------
SET @slot  = TIMESTAMP(CURRENT_DATE, SEC_TO_TIME(FLOOR(TIME_TO_SEC(CURRENT_TIME) / 1800) * 1800));
```

_(value stored in a session variable)_

```sql
SET @type  = IF(TIME(@slot) BETWEEN '10:00:00' AND '21:00:00', 'Dine_In', 'Take_Home');
```

_(value stored in a session variable)_

```sql
SET @start = CAST(IF(@type = 'Dine_In', @slot, DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:00')) AS DATETIME);
```

_(value stored in a session variable)_

```sql
SET @end   = IF(@type = 'Dine_In', @start + INTERVAL 2 HOUR, @start + INTERVAL 1 DAY);
```

_(value stored in a session variable)_

```sql
SET @party = IF(@type = 'Dine_In', 4, NULL);
```

_(value stored in a session variable)_

```sql
SELECT @type AS booking_type, @start AS starts, @end AS ends, @party AS party_size;
```

**1 row**

| booking_type | starts | ends | party_size |
|---|---|---|---|
| Dine_In | 2026-10-12 19:00:00 | 2026-10-12 21:00:00 | 4 |

```sql
-- 1. A member in good standing: Active, valid through the end, owes <= Rs 500,
--    18+ (so Take_Home also works) and holding no other game.
SET @member = NULL;
```

_(value stored in a session variable)_

```sql
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
```

_(value stored in a session variable)_

```sql
SELECT customer_id, CONCAT(first_name, ' ', last_name) AS member, tier_id,
       fn_customer_balance(customer_id) AS balance
  FROM Customers WHERE customer_id = @member;
```

**1 row**

| customer_id | member | tier_id | balance |
|---|---|---|---|
| 5 | Vikram Singh | 3 | 50.00 |

```sql
-- 2. Free tables for 4 (Dine_In only). A CALL's result set cannot be captured
--    into a variable in MySQL, so the first row is picked with the same rule
--    sp_find_free_tables uses (smallest table that fits, then rate, then code).
CALL sp_find_free_tables(4, @start, @end, FALSE);
```

**11 rows** (first 10 shown)

| table_id | table_code | zone | seating_capacity | hourly_rate | is_accessible |
|---|---|---|---|---|---|
| 12 | PA-01 | Patio | 4 | 120.00 | 1 |
| 15 | PA-04 | Patio | 4 | 120.00 | 0 |
| 8 | QC-03 | Quiet_Corner | 4 | 140.00 | 0 |
| 1 | MH-01 | Main_Hall | 4 | 150.00 | 0 |
| 2 | MH-02 | Main_Hall | 4 | 150.00 | 1 |
| 13 | PA-02 | Patio | 6 | 180.00 | 0 |
| 3 | MH-03 | Main_Hall | 6 | 200.00 | 0 |
| 11 | PR-03 | Party_Room | 6 | 220.00 | 0 |
| 5 | MH-05 | Main_Hall | 8 | 250.00 | 0 |
| 10 | PR-02 | Party_Room | 8 | 300.00 | 0 |

```sql
SET @table = NULL;
```

_(value stored in a session variable)_

```sql
SELECT table_id INTO @table
  FROM Cafe_Tables
 WHERE @type = 'Dine_In'
   AND is_active
   AND seating_capacity >= 4
   AND fn_table_is_free(table_id, @start, @end, NULL)
 ORDER BY seating_capacity, hourly_rate, table_code
 LIMIT 1;
```

_(value stored in a session variable)_

```sql
-- 3. Game recommendations for 4 players, youngest 16, up to 120 minutes. Take the
--    first recommended game whose copy is on the shelf now (a Rented copy that is
--    free later could be reserved but not checked in - BR-07) and whose box has a
--    component with at least 2 pieces (step 6 reports 2 of them missing).
CALL sp_recommend_games(4, 16, 120, @start, @end);
```

**22 rows** (first 10 shown)

| game_id | title | min_players | max_players | min_age | avg_play_minutes | complexity | free_copies | suggested_copy_id |
|---|---|---|---|---|---|---|---|---|
| 9 | Jenga | 1 | 8 | 6 | 20 | 1.0 | 1 | 61 |
| 22 | Uno | 2 | 10 | 7 | 30 | 1.0 | 2 | 52 |
| 12 | Exploding Kittens | 2 | 5 | 7 | 15 | 1.1 | 3 | 30 |
| 8 | Dixit | 3 | 8 | 8 | 30 | 1.2 | 2 | 21 |
| 3 | Codenames | 2 | 8 | 14 | 15 | 1.3 | 3 | 7 |
| 17 | Sushi Go Party! | 2 | 8 | 8 | 20 | 1.3 | 2 | 42 |
| 25 | Hanabi | 2 | 5 | 8 | 25 | 1.7 | 2 | 59 |
| 19 | Trivial Pursuit | 2 | 6 | 12 | 90 | 1.7 | 2 | 46 |
| 6 | Azul | 2 | 4 | 8 | 40 | 1.8 | 3 | 15 |
| 10 | Splendor | 2 | 4 | 10 | 30 | 1.8 | 3 | 25 |

```sql
SET @copy = NULL;
```

_(value stored in a session variable)_

```sql
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
```

_(value stored in a session variable)_

```sql
SELECT @member AS member_id, @table AS table_id, @copy AS copy_id;
```

**1 row**

| member_id | table_id | copy_id |
|---|---|---|
| 5 | 12 | 61 |

```sql
-- 4. Book it (BR-13/BR-14 in the procedure, BR-01..BR-12 in the trigger)
CALL sp_create_reservation(@member, @type, @table, @copy, @party, @start, @end, @booking);
```

_OK - rows affected: 0_

```sql
SELECT booking_id, booking_type, status, customer, table_code, game, barcode,
       reserved_start, reserved_end
  FROM vw_active_bookings WHERE booking_id = @booking;
```

**1 row**

| booking_id | booking_type | status | customer | table_code | game | barcode | reserved_start | reserved_end |
|---|---|---|---|---|---|---|---|---|
| 348 | Dine_In | Reserved | Vikram Singh | PA-01 | Jenga | BG0009261012 | 2026-10-12 19:00:00 | 2026-10-12 21:00:00 |

```sql
-- 5. Check in (opens 15 minutes before the start; the copy becomes Rented)
CALL sp_check_in(@booking);
```

_OK - rows affected: 0_

```sql
SELECT b.booking_id, b.status, b.checked_in_at, gc.status AS copy_status
  FROM Rentals_Reservations b JOIN Game_Copies gc ON gc.copy_id = b.copy_id
 WHERE b.booking_id = @booking;
```

**1 row**

| booking_id | status | checked_in_at | copy_status |
|---|---|---|---|
| 348 | Checked_In | 2026-10-12 19:05:06 | Rented |

```sql
-- 6. Return: inspection finds 2 pieces of one component missing
SET @component = NULL;
```

_(value stored in a session variable)_

```sql
SELECT component_id INTO @component
  FROM Game_Components
 WHERE game_id = (SELECT game_id FROM Game_Copies WHERE copy_id = @copy)
   AND qty_per_copy >= 2
 ORDER BY component_id
 LIMIT 1;
```

_(value stored in a session variable)_

```sql
SET @inspector = NULL;
```

_(value stored in a session variable)_

```sql
SELECT staff_id INTO @inspector FROM Staff
 WHERE role = 'Game_Guru' AND is_active ORDER BY staff_id LIMIT 1;
```

_(value stored in a session variable)_

```sql
SET @missing = JSON_ARRAY(JSON_OBJECT('component_id', @component, 'qty', 2));
```

_(value stored in a session variable)_

```sql
SELECT @component AS component_id, @inspector AS inspector, @missing AS missing_json;
```

**1 row**

| component_id | inspector | missing_json |
|---|---|---|
| 43 | 2 | [{"qty": 2, "component_id": 43}] |

```sql
CALL sp_check_out(@booking, @inspector, 'Good', @missing, '2 pieces missing');
```

_OK - rows affected: 0_

```sql
SELECT base_charge, discount_amount, late_fee, damage_fee, total_amount
  FROM Rentals_Reservations WHERE booking_id = @booking;
```

**1 row**

| base_charge | discount_amount | late_fee | damage_fee | total_amount |
|---|---|---|---|---|
| 300.00 | 60.00 | 0.00 | 20.00 | 260.00 |

```sql
SELECT copy_id, status FROM Game_Copies WHERE copy_id = @copy;  -- Missing_Pieces
```

**1 row**

| copy_id | status |
|---|---|
| 61 | Missing_Pieces |

```sql
SELECT * FROM vw_copies_needing_attention WHERE copy_id = @copy;
```

**1 row**

| copy_id | barcode | title | status | copy_condition | missing | charged_to_customers |
|---|---|---|---|---|---|---|
| 61 | BG0009261012 | Jenga | Missing_Pieces | Good | 2 x Wooden blocks | 20.00 |

```sql
-- 7. Pay the full amount (PAY-01/PAY-02 checked by trigger)
SELECT total_amount INTO @due FROM Rentals_Reservations WHERE booking_id = @booking;
```

_(value stored in a session variable)_

```sql
CALL sp_record_payment(@booking, @due, 'UPI');
```

_OK - rows affected: 1_

```sql
SELECT @due AS paid, fn_customer_balance(@member) AS member_balance_now;
```

**1 row**

| paid | member_balance_now |
|---|---|
| 260.00 | 50.00 |

```sql
-- 8. Staff replace the pieces: copy back on the shelf
CALL sp_restock_copy(@copy);  -- copy back to Available
```

_OK - rows affected: 0_

```sql
SELECT copy_id, status FROM Game_Copies WHERE copy_id = @copy;
```

**1 row**

| copy_id | status |
|---|---|
| 61 | Available |

```sql
-- 9. The audit trail written by the triggers
SELECT * FROM Booking_Audit_Log WHERE booking_id = @booking;  -- Reserved → Checked_In → Completed
```

**3 rows**

| log_id | booking_id | old_status | new_status | changed_at | changed_by |
|---|---|---|---|---|---|
| 349 | 348 | NULL | Reserved | 2026-10-12 19:05:06.218 | root@% |
| 350 | 348 | Reserved | Checked_In | 2026-10-12 19:05:06.226 | root@% |
| 351 | 348 | Checked_In | Completed | 2026-10-12 19:05:06.241 | root@% |
<!-- END OUTPUT WALK -->

**Lab-manual correction — trigger granularity.** MySQL triggers are always `FOR EACH ROW`;
there is no statement-level trigger (Oracle and PostgreSQL have `FOR EACH STATEMENT`). Observed:

```text
mysql> CREATE TRIGGER t_stmt AFTER INSERT ON state FOR EACH STATEMENT SET @x = 1;
ERROR 1064 (42000): You have an error in your SQL syntax; ... near 'STATEMENT SET @x = 1' at line 1
```

<!-- BEGIN OUTPUT E6 -->
#### E6 · Triggers, events and roles that exist (Exp 10, 12)

```sql
SELECT trigger_name, action_timing, event_manipulation, event_object_table
  FROM information_schema.triggers WHERE trigger_schema = DATABASE()
 ORDER BY event_object_table, action_timing, event_manipulation;
```

**10 rows**

| TRIGGER_NAME | ACTION_TIMING | EVENT_MANIPULATION | EVENT_OBJECT_TABLE |
|---|---|---|---|
| trg_mp_before_insert | BEFORE | INSERT | Missing_Pieces |
| trg_mp_after_insert | AFTER | INSERT | Missing_Pieces |
| trg_pay_before_insert | BEFORE | INSERT | Payments |
| trg_rr_before_insert | BEFORE | INSERT | Rentals_Reservations |
| trg_rr_before_update | BEFORE | UPDATE | Rentals_Reservations |
| trg_rr_before_delete | BEFORE | DELETE | Rentals_Reservations |
| trg_rr_after_insert | AFTER | INSERT | Rentals_Reservations |
| trg_rr_after_update | AFTER | UPDATE | Rentals_Reservations |
| trg_insp_before_insert | BEFORE | INSERT | Return_Inspections |
| trg_insp_after_insert | AFTER | INSERT | Return_Inspections |

```sql
SELECT event_name, status, interval_value, interval_field
  FROM information_schema.events WHERE event_schema = DATABASE() ORDER BY event_name;
```

**3 rows**

| EVENT_NAME | STATUS | INTERVAL_VALUE | INTERVAL_FIELD |
|---|---|---|---|
| ev_flag_suspensions | ENABLED | 1 | DAY |
| ev_mark_no_shows | ENABLED | 15 | MINUTE |
| ev_mark_overdue | ENABLED | 15 | MINUTE |

```sql
SHOW GRANTS FOR 'front_desk';
```

**12 rows** (first 10 shown)

| Grants for front_desk_evidence@% |
|---|
| GRANT USAGE ON *.* TO `front_desk_evidence`@`%` |
| GRANT SELECT ON `boardgame_cafe_evidence`.`vw_active_bookings` TO `front_desk_evidence`@`%` |
| GRANT SELECT, INSERT, UPDATE ON `boardgame_cafe_evidence`.`vw_active_members` TO `front_desk_evidence`@`%` |
| GRANT SELECT ON `boardgame_cafe_evidence`.`vw_available_copies_now` TO `front_desk_evidence`@`%` |
| GRANT SELECT ON `boardgame_cafe_evidence`.`vw_game_catalog` TO `front_desk_evidence`@`%` |
| GRANT SELECT ON `boardgame_cafe_evidence`.`vw_overdue_rentals` TO `front_desk_evidence`@`%` |
| GRANT EXECUTE ON PROCEDURE `boardgame_cafe_evidence`.`sp_check_in` TO `front_desk_evidence`@`%` |
| GRANT EXECUTE ON PROCEDURE `boardgame_cafe_evidence`.`sp_check_out` TO `front_desk_evidence`@`%` |
| GRANT EXECUTE ON PROCEDURE `boardgame_cafe_evidence`.`sp_create_reservation` TO `front_desk_evidence`@`%` |
| GRANT EXECUTE ON PROCEDURE `boardgame_cafe_evidence`.`sp_find_free_tables` TO `front_desk_evidence`@`%` |

```sql
SHOW GRANTS FOR 'analyst';
```

**4 rows**

| Grants for analyst_evidence@% |
|---|
| GRANT USAGE ON *.* TO `analyst_evidence`@`%` |
| GRANT SELECT ON `boardgame_cafe_evidence`.`vw_customer_balances` TO `analyst_evidence`@`%` |
| GRANT SELECT ON `boardgame_cafe_evidence`.`vw_game_popularity` TO `analyst_evidence`@`%` |
| GRANT SELECT ON `boardgame_cafe_evidence`.`vw_table_utilization_30d` TO `analyst_evidence`@`%` |
<!-- END OUTPUT E6 -->

**Viva.**
* *BEFORE vs AFTER triggers?* — BEFORE can change `NEW` (pricing) and reject the row (validation);
  AFTER sees the final row and is used for side effects (audit, copy status).
* *Why do the triggers call a procedure?* — Insert and update need the same checks;
  `sp_validate_booking` keeps them in one place.
* *How does an error inside `sp_check_out` undo earlier inserts?* — `DECLARE EXIT HANDLER FOR
  SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;` rolls back the transaction and re-raises the original
  error to the caller.

---

## Additional Experiment 1 — Cursors and functions

**Aim.** Write stored functions and walk a result set with a cursor.

**Work done.** Six functions (`sql/02_functions.sql`), all `READS SQL DATA`; the cursor procedure
`sp_flag_suspensions` (DECLARE CURSOR, CONTINUE HANDLER FOR NOT FOUND, OPEN, FETCH in a LOOP, LEAVE,
CLOSE).

<!-- BEGIN OUTPUT E4 -->
#### E4 · The six functions called directly (Additional Exp 1)

```sql
SELECT fn_customer_age(14, CURRENT_DATE) AS age_member_14,
       fn_customer_balance(13) AS balance_member_13,
       fn_table_is_free(1, TIMESTAMP(CURRENT_DATE + INTERVAL 20 DAY, '18:00:00'),
                           TIMESTAMP(CURRENT_DATE + INTERVAL 20 DAY, '20:00:00'), NULL) AS table1_free_in_20_days,
       fn_copy_is_free(2, NOW(), NOW() + INTERVAL 1 HOUR, NULL) AS copy2_free_now,
       fn_calculate_base_charge('Dine_In', 1, 1, TIMESTAMP(CURRENT_DATE, '18:00:00'),
                                TIMESTAMP(CURRENT_DATE, '20:00:00')) AS two_hours_mh01_catan,
       fn_calculate_base_charge('Take_Home', NULL, 1, TIMESTAMP(CURRENT_DATE, '12:00:00'),
                                TIMESTAMP(CURRENT_DATE + INTERVAL 2 DAY, '12:00:00')) AS two_days_catan;
```

**1 row**

| age_member_14 | balance_member_13 | table1_free_in_20_days | copy2_free_now | two_hours_mh01_catan | two_days_catan |
|---|---|---|---|---|---|
| 14 | 972.00 | 1 | 1 | 400.00 | 400.00 |

```sql
SELECT booking_id, booking_type, reserved_end,
       fn_calculate_late_fee(booking_id, reserved_end + INTERVAL 10 MINUTE) AS late_10_min,
       fn_calculate_late_fee(booking_id, reserved_end + INTERVAL 40 MINUTE) AS late_40_min,
       fn_calculate_late_fee(booking_id, reserved_end + INTERVAL 75 MINUTE) AS late_75_min
  FROM Rentals_Reservations WHERE status = 'Reserved' ORDER BY booking_type, booking_id LIMIT 3;
```

**3 rows**

| booking_id | booking_type | reserved_end | late_10_min | late_40_min | late_75_min |
|---|---|---|---|---|---|
| 328 | Dine_In | 2026-10-13 21:00:00 | 0.00 | 255.00 | 510.00 |
| 329 | Dine_In | 2026-10-13 21:30:00 | 0.00 | 270.00 | 540.00 |
| 330 | Dine_In | 2026-10-14 21:00:00 | 0.00 | 285.00 | 570.00 |
<!-- END OUTPUT E4 -->

<!-- BEGIN OUTPUT E5 -->
#### E5 · The cursor procedure: statuses before and after sp_flag_suspensions (Additional Exp 1)

```sql
SELECT customer_id, customer, status, balance FROM vw_customer_balances
 WHERE status <> 'Active' OR balance > 500 ORDER BY customer_id;
```

**2 rows**

| customer_id | customer | status | balance |
|---|---|---|---|
| 13 | Karan Malhotra | Active | 972.00 |
| 19 | Manish Chauhan | Suspended | 900.00 |

```sql
CALL sp_flag_suspensions();
```

_OK - rows affected: 0_

```sql
SELECT customer_id, customer, status, balance FROM vw_customer_balances
 WHERE status <> 'Active' OR balance > 500 ORDER BY customer_id;
```

**2 rows**

| customer_id | customer | status | balance |
|---|---|---|---|
| 13 | Karan Malhotra | Active | 972.00 |
| 19 | Manish Chauhan | Suspended | 900.00 |
<!-- END OUTPUT E5 -->

(In E5 nothing changes: member 19 is Suspended but still owes money, and nobody owes more than
₹2,000. The test `test_cursor_procedure_flags_suspensions` shows both transitions.)

**Viva.**
* *Why must a function that reads tables declare `READS SQL DATA`?* — With binary logging on, MySQL
  requires a function to declare whether it is DETERMINISTIC / reads / modifies data (ERROR 1418);
  `log_bin_trust_function_creators = 1` relaxes this for non-SUPER users.
* *How does the cursor loop know when to stop?* — FETCH past the last row raises NOT FOUND; the
  CONTINUE HANDLER sets `v_done = TRUE` and the loop LEAVEs.
* *Could `sp_flag_suspensions` be one UPDATE?* — Yes (`UPDATE … WHERE fn_customer_balance(…) > 2000`);
  the cursor is the lab demonstration of row-by-row processing.

---

## Additional Experiment 2 — PL/SQL commands for the project

**Aim.** Write the project's programs in PL/SQL style and compare with Oracle.

**Work done.**

* MySQL scheduled jobs (`sql/06_events.sql`): `ev_mark_overdue` and `ev_mark_no_shows` every
  15 minutes, `ev_flag_suspensions` daily at 02:00 (output E6 above lists them as ENABLED).
* Oracle PL/SQL equivalents in `sql/oracle_plsql/`: `fn_customer_age`, `sp_create_reservation`
  (BR-13/BR-14 + insert, `RAISE_APPLICATION_ERROR`), the BR-01 check as a
  `BEFORE INSERT … FOR EACH ROW` trigger, a statement-level trigger, and `sp_flag_suspensions` with
  an explicit cursor and a cursor `FOR` loop. **They were executed** on Oracle Database 23ai Free
  (Release 23.26.3) in Docker; the recorded output is in `sql/oracle_plsql/output/`. Excerpt:

```text
=== BR-01 from the row trigger: party of 6 at a 4-seat table ===
refused: ORA-20001: BR-01: party size exceeds table seating capacity
=== BR-13: suspended member / member owing more than Rs 500 ===
refused: ORA-20013: BR-13: customer account is not active
refused: ORA-20013: BR-13: outstanding balance above Rs 500
=== BR-14: 15 days ahead / started 2 hours ago ===
refused: ORA-20014: BR-14: bookings open only 14 days ahead
refused: ORA-20014: BR-14: booking cannot start in the past
=== sp_flag_suspensions (cursor FOR loop): Karan owes > 2000 -> Suspended ===
  (before)  2 Manish  Suspended  0     3 Karan  Active     2520
  (after)   2 Manish  Active     0     3 Karan  Suspended  2520
```

The comparison table (DELIMITER vs `/`, SIGNAL vs RAISE_APPLICATION_ERROR, handlers vs EXCEPTION,
FOR EACH STATEMENT, FETCH FIRST vs LIMIT) is in
[`sql/oracle_plsql/README.md`](../sql/oracle_plsql/README.md).

**Viva.**
* *What replaces `DELIMITER $$` in SQL*Plus?* — A `/` on its own line ends a PL/SQL block.
* *Why error numbers −20000 … −20999?* — That range is reserved for application errors raised with
  `RAISE_APPLICATION_ERROR`.
* *Can an Oracle row trigger read its own table?* — No (ORA-04091, mutating table); MySQL allows
  reading, which `sp_validate_booking` relies on for the overlap check.
