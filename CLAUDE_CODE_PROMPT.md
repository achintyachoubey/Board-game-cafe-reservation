# Claude Code build prompt — Board Game Café & Table Reservation System

**How to use this file.** Make an empty folder, save this file in it as `CLAUDE_CODE_PROMPT.md`, open Claude Code in that folder and type:

> Read CLAUDE_CODE_PROMPT.md in full and build everything it describes. Do not stop until every item in Section 14 (Definition of done) is checked.

Everything below is addressed to Claude Code.

---

## 0. Your role and the one-paragraph brief

You are building a complete, tested, documented **RDBMS final project** for a second-year B.Tech CSE student. The project is a relational database (MySQL 8.0) for a **board game café**: members book café tables and borrow physical game boxes, either to play at a table or to take home. It is deliberately a twist on the classic Library Management System: books become board games, library cards become memberships, and three new rules make it interesting — the number of players must fit both the game and the table, every game has an age limit, and every returned box is inspected for missing pieces. All rules are enforced inside the database (constraints, triggers, stored procedures), not in application code.

**There is no front end.** Do not build a web app, desktop app, Streamlit page, API server or any UI. Every demo runs from the MySQL client (`mysql` shell or MySQL Workbench). Python is used only for the seed generator, the build script, the evidence generator and the test suite.

## 1. Non-negotiable rules for this build

1. **DBMS: MySQL 8.0.31 or later**, InnoDB, `utf8mb4`. The course lab (RDBMS Lab Manual 2026-27, CSC2131) uses MySQL, and features used here need 8.0.31+ (`INTERSECT`/`EXCEPT`). Work with the server's default `sql_mode` (it includes `ONLY_FULL_GROUP_BY` and `STRICT_TRANS_TABLES`); never loosen it.
2. **The appendices are the specification, and they are tested.** Appendix A (schema), Appendix B (functions, procedures, triggers, views, events, roles) and Appendix C (query bank and demos) were executed on MySQL 8.0.46 against seed data, and a 39-check rule suite passed. Use them **verbatim** as the starting point. You may add `COMMENT` clauses, headers, and the extra items this prompt asks for. You may not change a business rule, an error message, a column name, a data type, a constraint or a query's meaning. If you believe something in an appendix is wrong, prove it with a failing test first, then fix it, and record the change, the proof and the reason in `docs/CHANGES_FROM_SPEC.md`.
3. **Nothing is done until it has run.** Every SQL file must load on a fresh server, every query must execute, every test must pass. Report real output, never expected output you did not observe.
4. **No shortcuts that weaken the database to make something else pass.** If seed data or a test hits a business rule, fix the data or the test, not the rule. (Section 7 lists the traps already found.)
5. **No ORM, no stored balances, no FLOAT for money, no `FULL JOIN` keyword** (MySQL has none — see Q43), no `SELECT TOP` (use `LIMIT`).
6. Keep the student's original design visible: the four core entities they proposed — `Customers` (members), `Board_Games` (books: age restriction, player count, condition), `Tables` (zones with maximum seating) and the bridge `Rentals_&_Reservations` (who rented what game, at which table, for how long) — are the centre of the schema. Two names had to change for MySQL, and the docs must say why: `TABLES` is a reserved word, so the entity is `Cafe_Tables`; `&` is illegal in an unquoted identifier, so the bridge is `Rentals_Reservations`. Condition moved from the game title to the physical copy (`Game_Copies.copy_condition`; `condition` is also reserved), and the docs must explain that normalization reason.

## 2. Course context (use it in the docs)

- Course: **CSC2103 Relational Database Management Systems**, B.Tech CSE Semester III, Manipal University Jaipur, July–Nov 2026. Lab: **CSC2131**, RDBMS Lab Manual 2026-27 (MySQL).
- Course outcomes the project must visibly serve: CO1 ER modelling and mapping to relations; CO2 relational algebra and SQL incl. joins, subqueries, views, stored procedures, triggers and cursors; CO3 functional dependencies, normalization, decomposition; CO4 transactions, concurrency control, recovery; CO5 storage and indexing (B+ trees).
- Syllabus topics to show explicitly: generalization, specialization, aggregation; Armstrong's axioms, canonical cover, lossless join, dependency preservation, MVDs and 4NF; ACID, schedules, serializability, two-phase locking, deadlock handling; indexing.
- The 12 lab experiments plus 2 additional experiments, each of which must map to concrete files (Section 11):
  1 ER diagram → relational model, keys · 2 DDL CREATE/DROP/ALTER/RENAME · 3 constraints PK/FK/CHECK/NOT NULL/DEFAULT · 4 DML incl. multi-row INSERT and INSERT…SELECT · 5 SELECT/WHERE/LIKE/DISTINCT/BETWEEN/IN/wildcards · 6 DISTINCT/COUNT/ORDER BY/GROUP BY/TOP/MAX · 7 INNER/LEFT/RIGHT/FULL/non-equi joins · 8 subqueries · 9 views and operations on views · 10 GRANT/REVOKE · 11 COMMIT/ROLLBACK/SAVEPOINT · 12 triggers and stored procedures · Additional 1 cursors and functions · Additional 2 PL/SQL commands for the project.

## 3. Environment setup (do this first, and script it)

1. Detect what exists: `mysql --version`, `mysqld --version`, `docker --version`, `python3 --version`.
2. Database server, in this order of preference:
   - a running local MySQL 8.0.31+ the user already has (ask for credentials only if you cannot connect with the values in `.env`), or
   - Docker: write `docker-compose.yml` using the official `mysql:8.0` image with `--event-scheduler=ON`, `--log-bin-trust-function-creators=1`, a named volume, port 3306 and the root password from `.env`.
   If neither is possible, stop and tell the user exactly what to install (MySQL Community Server 8.0 or Docker Desktop) — do not fake the build.
3. Binary logging is on by default in MySQL 8.0. Every function here declares `READS SQL DATA`, which satisfies the binary-log rule, but a user without the SUPER/SYSTEM_VARIABLES_ADMIN privilege can still get ERROR 1419 when creating functions or triggers. The compose file sets `log_bin_trust_function_creators = 1`; for a local server the README must document `SET GLOBAL log_bin_trust_function_creators = 1;` as the fix for 1418/1419. Also `SET GLOBAL event_scheduler = ON;` (the events do nothing while it is OFF).
4. Python 3.11+ with a virtual environment; dependencies pinned in `requirements.txt`: `pymysql`, `pytest`, `python-dotenv`. Nothing else is needed.
5. `.env.example` with `DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME=boardgame_cafe`. Real `.env` is git-ignored.

## 4. Repository layout (create exactly this)

```text
boardgame-cafe-db/
├── README.md                      setup, build, demo script, tests, troubleshooting
├── CLAUDE_CODE_PROMPT.md          this file
├── docker-compose.yml
├── .env.example
├── .gitignore
├── requirements.txt
├── sql/
│   ├── 00_drop_all.sql            drops database, roles and demo users (idempotent)
│   ├── 01_schema.sql              Appendix A (+ COMMENT clauses)
│   ├── 02_functions.sql           Appendix B.1
│   ├── 03_procedures.sql          Appendix B.2 (sp_validate_booking) + B.4
│   ├── 04_triggers.sql            Appendix B.3
│   ├── 05_views.sql               Appendix B.5
│   ├── 06_events.sql              Appendix B.6
│   ├── 07_roles.sql               Appendix B.7 (users created with passwords from .env or clearly-labelled demo passwords)
│   ├── 08_seed.sql                GENERATED by scripts/generate_seed.py, dates relative to CURRENT_DATE
│   ├── 09_queries.sql             Q01–Q44, each with a header block
│   ├── 10_demo_transactions.sql   T1 runnable script; T2, T3, T4 as two-terminal scripts (see Section 9)
│   ├── 11_demo_indexing.sql       X1
│   ├── 12_demo_lab_extras.sql     L1, L2, L3
│   ├── 13_walkthrough.sql         end-to-end booking → check-in → return with missing pieces → pay → restock
│   └── oracle_plsql/              Additional Experiment 2 (Section 10)
├── scripts/
│   ├── build_db.py                runs 00→08 in order; --db NAME, --skip-seed, --with-demos
│   ├── generate_seed.py           writes sql/08_seed.sql (deterministic: fixed random seed)
│   └── capture_evidence.py        runs every query/demo, writes docs/query_results.md and docs/lab_record.md outputs
├── tests/
│   ├── conftest.py                builds a fresh throw-away database per test session
│   ├── test_schema.py
│   ├── test_business_rules.py     TC-01 … TC-36
│   ├── test_queries.py
│   ├── test_concurrency.py        TC-31 race, TC-35 deadlock
│   └── test_security.py           TC-36 role/privilege checks
└── docs/
    ├── report.md                  the project report (Section 12)
    ├── ER_diagram.md              Mermaid crow's-foot diagram + Chen/ERDplus drawing guide
    ├── data_dictionary.md         generated from information_schema
    ├── normalization.md
    ├── business_rules.md
    ├── lab_record.md              one section per lab experiment, with real outputs
    ├── query_results.md           generated
    ├── viva_questions.md
    └── CHANGES_FROM_SPEC.md       only if you had to change anything (see rule 1.2)
```

Every `.sql` file starts with a comment header (purpose, run order, lab experiment it serves) and, from 02 on, `USE boardgame_cafe;` — the reference blocks do not contain `USE`, and without it they run against whatever database is current. Files that define stored programs use `DELIMITER $$ … DELIMITER ;` exactly as in Appendix B so they run in the `mysql` shell and in Workbench.

The build script must also support building under another database name (for tests): replace the literal `boardgame_cafe` in the SQL text when `--db` differs, and give roles/users a matching suffix so a test build never touches the student's real database or roles.

## 5. Data model (Appendix A is authoritative)

Fourteen tables, created in dependency order:

| Table | Role |
| --- | --- |
| `Membership_Tiers` | Basic / Silver / Gold: concurrent rentals, max Dine_In hours, max Take_Home days, discount |
| `Customers` | Members; email and phone are alternate keys; age is derived from `date_of_birth` |
| `Staff` | Inspect returned games |
| `Game_Categories` | Strategy, Party, Family, Co-op, … |
| `Board_Games` | Titles: player range, minimum age, play time, complexity, hourly and daily rates, replacement cost |
| `Board_Game_Categories` | M:N games ↔ categories |
| `Game_Copies` | Physical boxes: barcode, `copy_condition`, status (Available, Rented, Under_Repair, Missing_Pieces, Retired) |
| `Game_Components` | Expected pieces per title (weak entity; natural key `(game_id, component_name)`) |
| `Cafe_Tables` | Zone, seating capacity, hourly rate, accessible, active |
| `Rentals_Reservations` | The bridge: customer + table + copy + time window + status + fees; `booking_type` Dine_In / Take_Home |
| `Return_Inspections` | One per returned booking (1 : 0..1) |
| `Missing_Pieces` | Components missing in an inspection, with quantity and a charge snapshot |
| `Payments` | Money received against a closed booking |
| `Booking_Audit_Log` | Every status change, written only by triggers |

Add `COMMENT` clauses to every table and every column (plain-English meaning, unit, which rule uses it). These feed `docs/data_dictionary.md`. Comments are the only change you may make to Appendix A.

## 6. Business rules (all enforced in the database)

Every rule error is `SIGNAL SQLSTATE '45000'` with a message that starts with its ID (e.g. `BR-05: …`), so tests and the client can match on it.

| ID | Rule | Enforced by |
| --- | --- | --- |
| BR-01 | Party size ≤ table seating capacity; table must be active | `sp_validate_booking` via booking triggers |
| BR-02 | Dine_In with a game: party size within the game's min–max players | same |
| BR-03 | Booking customer's age on the booking date ≥ game's minimum age | same + `fn_customer_age` |
| BR-04 | Take_Home requires age 18+ | same |
| BR-05 | No two active bookings (Reserved, Checked_In, Overdue) overlap on a table: `new_start < old_end AND old_start < new_end`; an Overdue booking blocks until returned | same + `fn_table_is_free`; `FOR UPDATE` lock in `sp_create_reservation` |
| BR-06 | Same for a game copy | same + `fn_copy_is_free` |
| BR-07 | Retired, Under_Repair, Missing_Pieces copies cannot be booked; a copy out now can be reserved for a later window, but check-in needs it back on the shelf | validation + `sp_check_in` |
| BR-08 | Dine_In needs table + party size; Take_Home needs a copy, no table, no party size | CHECK `chk_booking_type_shape` + validation |
| BR-09 | End after start; Dine_In ≥ 60 min, on :00/:30 boundaries | CHECK constraints |
| BR-10 | Dine_In within 10:00–23:00 on one day | validation |
| BR-11 | Dine_In ≤ tier `max_session_hours`; Take_Home ≤ tier `max_takehome_days` | validation |
| BR-12 | Active bookings holding a copy ≤ tier `max_concurrent_rentals` | validation |
| BR-13 | To book: customer Active, membership valid through the booking end, balance ≤ ₹500 | `sp_create_reservation` |
| BR-14 | New bookings start no earlier than 30 minutes ago and at most 14 days ahead | `sp_create_reservation` |
| BR-15 | Lifecycle: Reserved → Checked_In / Cancelled / No_Show; Checked_In → Overdue / Completed; Overdue → Completed; closed rows are frozen | `trg_rr_before_update` |
| BR-16 | Late fee = 1.5 × rate per started hour (Dine_In: table + game hourly) or per started day (Take_Home: game daily) after a 15-minute grace | `fn_calculate_late_fee` |
| BR-17 | A returned copy must be inspected; each missing piece is validated against that game and priced (qty × unit cost) and added as damage fee | `sp_check_out`, inspection and Missing_Pieces triggers |
| BR-18 | After inspection: missing pieces → Missing_Pieces; Damaged → Under_Repair; otherwise Available | triggers |
| BR-19 | Cancel free until 2 h before start, then ₹100; no check-in 30 min after start → No_Show, ₹100 | `sp_cancel_booking`, `sp_mark_no_shows`, event |
| BR-20 | History is never deleted: FK `ON DELETE RESTRICT`; only a free cancellation may be deleted | FKs + `trg_rr_before_delete` |
| PAY-01/02 | Payments only on closed bookings; never more than the amount due | `trg_pay_before_insert` |

Pricing: base = table hourly × hours + game hourly × hours (Dine_In) or game daily × days (Take_Home); tier discount applies to base only; `total_amount` is a generated column. Tiers: Basic (₹0, 1 rental, 4 h, 1 day, 0%), Silver (₹999, 2, 6 h, 2 days, 10%), Gold (₹1,999, 3, 8 h, 3 days, 20%). Balance is computed by `fn_customer_balance` (final bookings billed − payments), never stored.

Design rule worth preserving: checks that must hold for every row (capacity, players, age, overlap, durations) live in triggers; checks that depend on "now" (future start, 14-day window, account standing) live in `sp_create_reservation`. Overlap and concurrency checks only run when the row being written is active, so historical rows load cleanly.

## 7. Seed data — `scripts/generate_seed.py` → `sql/08_seed.sql`

The generator writes a **static SQL file whose every date is relative to the load date** (e.g. `TIMESTAMP(CURRENT_DATE - INTERVAL 37 DAY, '18:30:00')`), so the file loads correctly on any day without Python. Use a fixed random seed so the file is reproducible. All rows go in through the real triggers — never disable triggers or checks to load data.

Volumes and coverage:
- 3 tiers; 8 staff; 10 categories; 25 real board games (e.g. Catan, Ticket to Ride, Codenames, Pandemic, Dominion, Azul, Wingspan, Dixit, Jenga, Splendor, 7 Wonders, Exploding Kittens, Scrabble, Carcassonne, Terraforming Mars, The Crew, Sushi Go Party!, Chess, Trivial Pursuit, Gloomhaven: Jaws of the Lion, Werewolf, Uno, Cards Against Humanity (18+), Spirit Island, Hanabi) with realistic player ranges 1–10, minimum ages 6–18, at least 3 Party games; 2–3 copies each (~60); 4–6 components per game with Indian-rupee replacement costs.
- 16 café tables across the four zones (capacities 2, 4, 6, 8, 10; table codes like `MH-01`, `QC-02`, `PR-01`, `PA-03`), 2 accessible, 1 inactive.
- 30 customers with Indian names, ages 12–65 across all tiers.
- ~300 historical bookings over the last 90 days (mostly Completed, some Cancelled and No_Show, ~50 Take_Home), with inspections for every completed booking that had a copy, ~15–20 returns with missing pieces, and payments covering most closed bookings.
- Live and future rows: one Overdue Take_Home, one Checked_In Take_Home (started yesterday, due tomorrow — Take_Home avoids opening-hour rules so the seed works at any time of day), and ~20 future Reserved bookings over the next 14 days created by `CALL sp_create_reservation(...)`.

Guaranteed fixtures (tests depend on them; name them in a comment):
- one member who has completed a booking of **every** Party game (Q20 returns ≥ 1 row);
- one member with both Dine_In and Take_Home completed bookings (Q22);
- one copy each in Missing_Pieces (with un-restocked `Missing_Pieces` rows), Under_Repair and Retired;
- one Suspended member, one expired member, one owing more than ₹500, one whose membership expires within 7 days;
- members aged 14 and 16; one inactive table that has never been booked (Q23).

Traps already found when this spec was tested — handle them:
1. **Insert payments before creating future reservations.** Otherwise every member with history owes more than ₹500 and `sp_create_reservation` correctly refuses them all (BR-13).
2. Historical Completed rows are inserted directly with `status = 'Completed'`; their inspections are inserted afterwards (allowed for Completed bookings); late fees can be set with `fn_calculate_late_fee(booking_id, returned_at)`.
3. Inspections update copy statuses, so after loading history, reset every copy to `Available` and then set the fixture copies' statuses explicitly.
4. An Overdue row is inserted as `Checked_In` and then updated to `Overdue` (a direct `Checked_In` insert also marks the copy Rented via `trg_rr_after_insert`).
5. Historical Dine_In rows must respect the CHECK constraints (:00/:30, ≥ 60 min, within 10:00–23:00, within the member's tier hours) and the party/age rules — generate them so they do.

## 8. Database programs (Appendix B is authoritative)

Exactly these objects, and the schema test must assert the counts: **14 tables, 9 views, 6 functions, 11 procedures, 10 triggers (BEFORE/AFTER on INSERT, UPDATE and DELETE), 3 events, 3 roles; 14 primary keys, 14 foreign keys, 21 CHECK constraints, 10 UNIQUE constraints.**

- Functions: `fn_customer_age`, `fn_table_is_free`, `fn_copy_is_free`, `fn_calculate_base_charge`, `fn_calculate_late_fee`, `fn_customer_balance`.
- Procedures: `sp_validate_booking` (shared by triggers), `sp_create_reservation` (locks table → copy → customer with `FOR UPDATE` **before** any plain read, at READ COMMITTED, so concurrent bookings serialize — explain this in the docs), `sp_check_in`, `sp_check_out` (inspection + missing pieces from a JSON array via `JSON_TABLE` + late fee, all in one transaction with an EXIT HANDLER that rolls back and RESIGNALs), `sp_cancel_booking`, `sp_mark_no_shows`, `sp_find_free_tables`, `sp_recommend_games`, `sp_record_payment`, `sp_restock_copy`, `sp_flag_suspensions` (cursor loop — the cursor demo).
- Triggers: `trg_rr_before_insert`, `trg_rr_before_update`, `trg_rr_after_insert`, `trg_rr_after_update`, `trg_rr_before_delete`, `trg_insp_before_insert`, `trg_insp_after_insert`, `trg_mp_before_insert`, `trg_mp_after_insert`, `trg_pay_before_insert`.
- Views: `vw_game_catalog`, `vw_active_bookings`, `vw_available_copies_now`, `vw_overdue_rentals`, `vw_customer_balances`, `vw_game_popularity`, `vw_table_utilization_30d`, `vw_copies_needing_attention`, `vw_active_members` (updatable, `WITH CASCADED CHECK OPTION`, includes every NOT NULL column without a default so INSERT works through it).
- Events: `ev_mark_overdue`, `ev_mark_no_shows`, `ev_flag_suspensions`.
- Roles: `cafe_admin`, `front_desk` (views + EXECUTE on workflow procedures only — no direct table writes; procedures run with definer rights), `analyst` (reporting views only); demo users `desk_priya`, `owner_ravi`, `report_bot`.

## 9. Query bank and demos (Appendix C is authoritative)

Put Q01–Q44 in `sql/09_queries.sql`, each preceded by a header:

```sql
-- =====================================================================
-- Q20 · Who has played every Party game?
-- Concept: relational division (double NOT EXISTS)   Lab: Exp 8
-- Relational algebra: π customer_id,game_id (RR ⋈ Copies) ÷ π game_id (Party games)
-- =====================================================================
```

Concept groups: A retrieval (Q01–Q04), B joins (Q05–Q09), C aggregation (Q10–Q14), D subqueries (Q15–Q20), E set operations (Q21–Q23), F window functions (Q24–Q28), G CTEs incl. recursive (Q29–Q30), H business-rule queries (Q31–Q36), I DML (Q37–Q40), lab extras (Q41 DISTINCT/BETWEEN/IN/wildcards, Q42 aggregates + LIMIT, Q43 FULL OUTER JOIN emulated with LEFT JOIN UNION RIGHT JOIN, Q44 non-equi join).

Demos:
- `10_demo_transactions.sql`: **T1** SAVEPOINT (runnable: pick a Completed unpaid booking into `@b` first). **T2** double-booking race, **T3** isolation levels (READ COMMITTED vs REPEATABLE READ non-repeatable read), **T4** deadlock (two sessions lock copies 1→2 and 2→1; one gets ERROR 1213) — write T2–T4 as clearly labelled "Session A" / "Session B" step scripts for two terminals, with the expected result of each step.
- `11_demo_indexing.sql`: X1 — `EXPLAIN` showing `ref` on `idx_customer_name`, a forced scan with `IGNORE INDEX`, a non-sargable `DATE(reserved_start)` scan vs a sargable range on `idx_rr_start`, and `EXPLAIN ANALYZE` of the BR-05 overlap check (a covering range scan on `idx_rr_table_window`). Explain the InnoDB clustered B+ tree on the primary key versus secondary indexes in comments.
- `12_demo_lab_extras.sql`: L1 DDL (CREATE, ALTER add/modify/constraint/rename column, RENAME TABLE, multi-row INSERT, TRUNCATE, DROP, CREATE/DROP DATABASE), L2 view operations, L3 DCL (WITH GRANT OPTION, REVOKE ALL — note it does **not** remove a granted role; `REVOKE 'analyst' FROM …` does — and least-privilege proof).
- `13_walkthrough.sql`: the end-to-end flow. It must pick real IDs itself (free table from `sp_find_free_tables`, copy from `sp_recommend_games`, a component of that copy's game) rather than hard-coding 3, 12 and 31, and it must work at any time of day: if the café is closed now, run the flow on a Take_Home booking instead of Dine_In.

`scripts/capture_evidence.py` runs every query and demo that can run in one session against a freshly seeded database and writes `docs/query_results.md`: for each item, the header, the SQL, the row count and the first 10 rows as a Markdown table. Two-session demos (T2–T4) are executed by the test suite with two connections, and their observed outcomes are written into the same file.

## 10. Additional Experiment 2 — Oracle PL/SQL appendix

In `sql/oracle_plsql/`, write Oracle 19c/23ai PL/SQL equivalents of a representative subset, for comparison in the lab record: the DDL for the tables those programs touch; `fn_customer_age` (FUNCTION); `sp_create_reservation` reduced to the BR-13/BR-14 checks plus the insert (PROCEDURE with `RAISE_APPLICATION_ERROR`); the BR-01 capacity check as a `BEFORE INSERT … FOR EACH ROW` trigger; and `sp_flag_suspensions` with an explicit cursor and a `FOR` loop. Add a README comparing MySQL stored programs and PL/SQL (DELIMITER vs `/`, SIGNAL vs RAISE_APPLICATION_ERROR, handlers vs EXCEPTION blocks, `FOR EACH STATEMENT` support, `FETCH FIRST n ROWS ONLY` vs `LIMIT`). If Docker is available, run them in `gvenzl/oracle-free` and record the output; if not, say plainly in that README that they were written but not executed. Never claim they were run when they were not.

## 11. Tests (pytest) — all must pass

`conftest.py` builds a fresh database (unique name, e.g. `boardgame_cafe_test_<random>`) from the SQL files, loads the seed, and drops it at the end. Tests create their **own fresh members** where account standing matters — a member's balance changes as tests charge fees, and BR-13 will (correctly) refuse a member who owes more than ₹500. Avoid wall-clock fragility: anything that depends on opening hours must either use Take_Home bookings, compute dates far enough ahead, or insert the active row directly; late-fee math is verified with `fn_calculate_late_fee(booking_id, reserved_end + INTERVAL n MINUTE)`.

| Test | Scenario | Expected |
| --- | --- | --- |
| TC-01 | Party of 6 at a 4-seat table | `BR-01` |
| TC-02 | Party of 4 at a 4-seat table | accepted |
| TC-03 | Party of 2 with a 3–5 player game | `BR-02` |
| TC-04 | 14-year-old books an 18+ game | `BR-03` |
| TC-05 | 16-year-old Take_Home | `BR-04` |
| TC-06 | Table booked 14:00–16:00; new 15:30–17:00 | `BR-05` |
| TC-07 | Touching window 16:00–18:00 | accepted |
| TC-08 | Cancel 14:00–16:00, rebook it | accepted |
| TC-09 | Same copy, overlapping windows | `BR-06` |
| TC-10 | Book a Missing_Pieces copy | `BR-07` |
| TC-11 | Dine_In without table; Take_Home with table | `BR-08` (both) |
| TC-12 | Dine_In starting at :15; lasting 45 minutes | CHECK `chk_rr_dinein_slots` |
| TC-13 | Dine_In 21:30–23:30 | `BR-10` |
| TC-14 | Basic member books 5 hours | `BR-11` |
| TC-15 | Basic member, second concurrent rental | `BR-12` |
| TC-16 | Suspended / expired / owes > ₹500 | `BR-13` (three cases) |
| TC-17 | 15 days ahead; started 2 h ago | `BR-14` |
| TC-18 | Reserved → Completed; Completed → Reserved | `BR-15` |
| TC-19 | Dine_In returned 40 min late (table ₹150/h + game ₹50/h) | late fee ₹300; 75 min late → ₹600 |
| TC-20 | 10 minutes late | ₹0 |
| TC-21 | Take_Home returned with 2 pieces at ₹15 missing | damage fee ₹30; copy Missing_Pieces; balance rises by the booking total |
| TC-22 | Report a component of another game | `BR-17`; whole check-out rolled back (no inspection row, booking still Checked_In) |
| TC-23 | Report more pieces than the box has | `BR-17`; rolled back |
| TC-24 | Return Damaged, nothing missing | copy Under_Repair |
| TC-25 | Cancel > 2 h before / < 2 h before | ₹0 / ₹100 |
| TC-26 | Reserved, start + 31 min, run `sp_mark_no_shows` | No_Show, ₹100 |
| TC-27 | Delete a customer with bookings | FK error 1451 |
| TC-28 | Overpay a booking | `PAY-02` |
| TC-29 | Gold member, 2 h at a ₹150/h table | base ₹300, discount ₹60, total ₹240 |
| TC-30 | Create then complete a booking | exactly 2 audit rows |
| TC-31 | 4 sessions book one table/slot at once | exactly 1 succeeds, others `BR-05` |
| TC-32 | Q08 after seed and all tests | 0 rows |
| TC-33 | Delete a Completed booking / a free cancellation | `BR-20` / accepted, audit rows cascade |
| TC-34 | Set a member Suspended through `vw_active_members` | ERROR 1369 CHECK OPTION failed |
| TC-35 | Deadlock T4 with two connections | one ERROR 1213, the other commits |
| TC-36 | `report_bot` reads `Customers`; `desk_priya` inserts into `Payments` | both ERROR 1142; `desk_priya` can CALL `sp_find_free_tables` |

Also: `test_schema.py` asserts the object and constraint counts in Section 8; `test_queries.py` runs every Q01–Q44, X1 and L1–L3 and asserts specifics (Q08 empty, Q20 contains the fixture member, Q22 non-empty, Q23 contains the inactive table, Q43 includes games played in only one of the two windows, X1 `EXPLAIN` keys are `idx_customer_name`, NULL, NULL, `idx_rr_start`), and that `ev_*` events exist and are ENABLED. Add a test that runs `13_walkthrough.sql` end to end.

## 12. Documentation (Markdown, written for the student to submit and defend)

- `README.md`: what the project is, prerequisites, setup with and without Docker, build order (`python scripts/build_db.py`), how to run the files in MySQL Workbench instead, the demo script for the viva (10 minutes: build → a rule violation → walkthrough → overdue/missing-pieces views → T2 race in two terminals → EXPLAIN), how to run tests, troubleshooting (log_bin_trust_function_creators, event scheduler, ONLY_FULL_GROUP_BY, DELIMITER in Workbench, port conflicts).
- `docs/report.md`: title page placeholders (student name, roll number, section, faculty, date), abstract, problem statement, objectives, scope, the library-system analogy table, requirements, ER design (incl. extended ER: specialization Dine_In/Take_Home, generalization, aggregation of the booking relationship for inspections, weak entity Game_Components, attribute types), relational schema, normalization, implementation (programs), transactions and concurrency, indexing, security, testing summary with the real pass counts, results (with real query outputs), conclusion, future scope (game swaps mid-session, F&B orders, waitlist, multi-branch, reminders, wear prediction), references (Korth/Silberschatz/Sudarshan 7e; Elmasri/Navathe 7e; MySQL 8.0 Reference Manual).
- `docs/ER_diagram.md`: the Mermaid `erDiagram` (crow's foot) for all 14 tables, plus precise instructions for drawing the Chen-notation version in ERDplus/Dia (double rectangle and double diamond for the weak entity, ternary diamond, aggregation box, ISA triangle with "d" and total participation, dashed ovals for derived attributes, double oval for the multivalued category).
- `docs/normalization.md`: UNF register → 1NF → 2NF → 3NF → BCNF with the anomalies each step removes; the FD set; Armstrong derivations; attribute closure of `booking_id`; candidate key reasoning; canonical cover (with the redundant FD and extraneous attribute example); 3NF synthesis; lossless-join proof and a lossy counter-example; dependency preservation; MVDs and 4NF (`GameInfo(game_id, category, component_name)` → split); the design decisions (condition on copies, one bridge table, generated columns, charge snapshot, computed balance).
- `docs/business_rules.md`: Section 6 expanded with an example and its error for each rule.
- `docs/data_dictionary.md`: generated from `information_schema` (table, column, type, null, key, default, comment) plus constraints and indexes.
- `docs/lab_record.md`: one section per lab experiment (1–12, Additional 1–2): aim, the exact SQL from the repo, the **real captured output**, and the viva questions for that experiment with answers. Include the three lab-manual corrections: the manual's `select * from state full join info on ID=info.OID;` silently runs as an inner join in MySQL (`full` becomes an alias) — use the UNION form; MySQL triggers are `FOR EACH ROW` only; `TOP` is SQL Server syntax (MySQL `LIMIT`, Oracle `FETCH FIRST`).
- `docs/viva_questions.md`: at least 30 questions with short, correct answers covering every section above.

## 13. Coding standards

- SQL keywords upper case, identifiers as in the appendices, 2-space indents, aligned `ON` clauses as in the appendices.
- Every stored program has a header comment: purpose, parameters, rules enforced, errors raised, lab experiment.
- Python: type hints, `pathlib`, no hard-coded credentials, parameterised queries only (`%s`), clear error messages when the server is unreachable.
- Idempotent builds: `00_drop_all.sql` then 01→08 always yields the same database.

## 14. Definition of done (verify each, then report)

- [ ] Fresh build from `00` to `08` succeeds with zero errors and zero warnings you have not explained.
- [ ] Schema counts match Section 8 exactly.
- [ ] Every query Q01–Q44, X1, L1–L3, T1 and the walkthrough runs; outputs captured in `docs/query_results.md`.
- [ ] `pytest` passes: all of TC-01 to TC-36 plus schema and query tests. Paste the final summary line in your report to the user.
- [ ] T2, T3, T4 executed with two connections and their observed outcomes recorded.
- [ ] Oracle appendix either executed (output recorded) or clearly marked as not executed.
- [ ] All docs in Section 12 written, with real numbers from the build (row counts, test counts), no placeholders except the title-page fields.
- [ ] `docs/CHANGES_FROM_SPEC.md` exists only if you changed something, and every change has a failing test that proves it was needed.
- [ ] No front end, no ORM, no FLOAT money, no stored balance, no `FULL JOIN` keyword anywhere.

When finished, reply with: what was built, the build and test results (exact counts), anything that could not be run and why, and the one command to rebuild everything.

---

# Appendix A — Schema (tested on MySQL 8.0.46)

Goes into `sql/01_schema.sql` (add `COMMENT` clauses only).

```sql
CREATE DATABASE IF NOT EXISTS boardgame_cafe
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE boardgame_cafe;

-- 1. Lookup: membership tiers
CREATE TABLE Membership_Tiers (
  tier_id                TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tier_name              VARCHAR(20)  NOT NULL UNIQUE,
  annual_fee             DECIMAL(8,2) NOT NULL DEFAULT 0,
  max_concurrent_rentals TINYINT UNSIGNED NOT NULL,
  max_session_hours      TINYINT UNSIGNED NOT NULL,
  max_takehome_days      TINYINT UNSIGNED NOT NULL,
  discount_pct           DECIMAL(5,2) NOT NULL DEFAULT 0,
  CONSTRAINT chk_tier_discount CHECK (discount_pct BETWEEN 0 AND 50),
  CONSTRAINT chk_tier_limits   CHECK (max_concurrent_rentals >= 1
                                      AND max_session_hours BETWEEN 1 AND 13
                                      AND max_takehome_days >= 1)
);

-- 2. Core: customers (members)
CREATE TABLE Customers (
  customer_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  first_name        VARCHAR(50)  NOT NULL,
  last_name         VARCHAR(50)  NOT NULL,
  email             VARCHAR(120) NOT NULL UNIQUE,
  phone             VARCHAR(15)  NOT NULL UNIQUE,
  date_of_birth     DATE NOT NULL,
  tier_id           TINYINT UNSIGNED NOT NULL,
  join_date         DATE NOT NULL DEFAULT (CURRENT_DATE),
  membership_expiry DATE NOT NULL,
  status            ENUM('Active','Suspended','Inactive') NOT NULL DEFAULT 'Active',
  CONSTRAINT fk_customer_tier FOREIGN KEY (tier_id)
    REFERENCES Membership_Tiers(tier_id) ON DELETE RESTRICT,
  CONSTRAINT chk_customer_email  CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT chk_customer_phone  CHECK (REGEXP_LIKE(phone, '^[+]?[0-9]{10,14}$')),
  CONSTRAINT chk_customer_dob    CHECK (date_of_birth < join_date),
  CONSTRAINT chk_customer_expiry CHECK (membership_expiry >= join_date),
  INDEX idx_customer_name (last_name, first_name)
);

-- 3. Staff
CREATE TABLE Staff (
  staff_id  SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  role      ENUM('Manager','Game_Guru','Front_Desk') NOT NULL,
  email     VARCHAR(120) NOT NULL UNIQUE,
  hired_on  DATE NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- 4. Lookup: categories
CREATE TABLE Game_Categories (
  category_id   SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  category_name VARCHAR(40) NOT NULL UNIQUE
);

-- 5. Core: board game titles
CREATE TABLE Board_Games (
  game_id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title            VARCHAR(120) NOT NULL,
  publisher        VARCHAR(80)  NOT NULL,
  year_published   SMALLINT UNSIGNED NULL,
  min_players      TINYINT UNSIGNED NOT NULL,
  max_players      TINYINT UNSIGNED NOT NULL,
  min_age          TINYINT UNSIGNED NOT NULL,
  avg_play_minutes SMALLINT UNSIGNED NOT NULL,
  complexity       DECIMAL(2,1) NOT NULL,          -- 1.0 (light) to 5.0 (heavy)
  hourly_rate      DECIMAL(8,2) NOT NULL,          -- in-cafe play, per hour
  daily_rate       DECIMAL(8,2) NOT NULL,          -- take-home, per day
  replacement_cost DECIMAL(10,2) NOT NULL,
  CONSTRAINT uq_game_title_publisher UNIQUE (title, publisher),
  CONSTRAINT chk_game_players    CHECK (min_players >= 1 AND max_players >= min_players
                                        AND max_players <= 20),
  CONSTRAINT chk_game_age        CHECK (min_age BETWEEN 3 AND 21),
  CONSTRAINT chk_game_complexity CHECK (complexity BETWEEN 1.0 AND 5.0),
  CONSTRAINT chk_game_rates      CHECK (hourly_rate >= 0 AND daily_rate >= hourly_rate
                                        AND replacement_cost > 0),
  CONSTRAINT chk_game_year       CHECK (year_published IS NULL
                                        OR year_published BETWEEN 1800 AND 2100)
);

-- 6. M:N bridge: games <-> categories
CREATE TABLE Board_Game_Categories (
  game_id     INT UNSIGNED NOT NULL,
  category_id SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (game_id, category_id),
  CONSTRAINT fk_bgc_game     FOREIGN KEY (game_id)
    REFERENCES Board_Games(game_id) ON DELETE CASCADE,
  CONSTRAINT fk_bgc_category FOREIGN KEY (category_id)
    REFERENCES Game_Categories(category_id) ON DELETE CASCADE
);

-- 7. Physical copies (the "book copies")
CREATE TABLE Game_Copies (
  copy_id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  game_id        INT UNSIGNED NOT NULL,
  barcode        CHAR(12) NOT NULL UNIQUE,
  acquired_on    DATE NOT NULL,
  copy_condition ENUM('New','Good','Fair','Worn','Damaged') NOT NULL DEFAULT 'New',
  status         ENUM('Available','Rented','Under_Repair','Missing_Pieces','Retired')
                 NOT NULL DEFAULT 'Available',
  shelf_location VARCHAR(10) NOT NULL,
  CONSTRAINT fk_copy_game FOREIGN KEY (game_id)
    REFERENCES Board_Games(game_id) ON DELETE RESTRICT,
  INDEX idx_copy_game_status (game_id, status)
);

-- 8. Expected pieces per title
CREATE TABLE Game_Components (
  component_id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  game_id               INT UNSIGNED NOT NULL,
  component_name        VARCHAR(80) NOT NULL,
  qty_per_copy          SMALLINT UNSIGNED NOT NULL,
  unit_replacement_cost DECIMAL(8,2) NOT NULL,
  CONSTRAINT uq_component UNIQUE (game_id, component_name),
  CONSTRAINT fk_component_game FOREIGN KEY (game_id)
    REFERENCES Board_Games(game_id) ON DELETE CASCADE,
  CONSTRAINT chk_component CHECK (qty_per_copy >= 1 AND unit_replacement_cost >= 0)
);

-- 9. Core: cafe tables
CREATE TABLE Cafe_Tables (
  table_id         SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  table_code       VARCHAR(8) NOT NULL UNIQUE,        -- e.g. MH-01
  zone             ENUM('Main_Hall','Quiet_Corner','Party_Room','Patio') NOT NULL,
  seating_capacity TINYINT UNSIGNED NOT NULL,
  hourly_rate      DECIMAL(8,2) NOT NULL,
  is_accessible    BOOLEAN NOT NULL DEFAULT FALSE,
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT chk_table_capacity CHECK (seating_capacity BETWEEN 2 AND 12),
  CONSTRAINT chk_table_rate     CHECK (hourly_rate >= 0)
);

-- 10. Core bridge: rentals and reservations
CREATE TABLE Rentals_Reservations (
  booking_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id      INT UNSIGNED NOT NULL,
  table_id         SMALLINT UNSIGNED NULL,
  copy_id          INT UNSIGNED NULL,
  booking_type     ENUM('Dine_In','Take_Home') NOT NULL,
  party_size       TINYINT UNSIGNED NULL,
  reserved_start   DATETIME NOT NULL,
  reserved_end     DATETIME NOT NULL,
  duration_minutes INT AS (TIMESTAMPDIFF(MINUTE, reserved_start, reserved_end)) STORED,
  checked_in_at    DATETIME NULL,
  returned_at      DATETIME NULL,
  status           ENUM('Reserved','Checked_In','Overdue','Completed','Cancelled','No_Show')
                   NOT NULL DEFAULT 'Reserved',
  base_charge      DECIMAL(10,2) NOT NULL DEFAULT 0,
  discount_amount  DECIMAL(10,2) NOT NULL DEFAULT 0,
  late_fee         DECIMAL(10,2) NOT NULL DEFAULT 0,
  damage_fee       DECIMAL(10,2) NOT NULL DEFAULT 0,
  cancellation_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
  total_amount     DECIMAL(10,2) AS (base_charge - discount_amount + late_fee
                                     + damage_fee + cancellation_fee) STORED,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_rr_customer FOREIGN KEY (customer_id)
    REFERENCES Customers(customer_id) ON DELETE RESTRICT,
  CONSTRAINT fk_rr_table FOREIGN KEY (table_id)
    REFERENCES Cafe_Tables(table_id) ON DELETE RESTRICT,
  CONSTRAINT fk_rr_copy FOREIGN KEY (copy_id)
    REFERENCES Game_Copies(copy_id) ON DELETE RESTRICT,
  CONSTRAINT chk_rr_window CHECK (reserved_end > reserved_start),
  CONSTRAINT chk_booking_type_shape CHECK (
       (booking_type = 'Dine_In'   AND table_id IS NOT NULL
                                   AND party_size IS NOT NULL AND party_size >= 1)
    OR (booking_type = 'Take_Home' AND table_id IS NULL
                                   AND copy_id IS NOT NULL AND party_size IS NULL)),
  CONSTRAINT chk_rr_dinein_slots CHECK (booking_type <> 'Dine_In' OR (
         MINUTE(reserved_start) IN (0,30) AND MINUTE(reserved_end) IN (0,30)
     AND SECOND(reserved_start) = 0     AND SECOND(reserved_end) = 0
     AND TIMESTAMPDIFF(MINUTE, reserved_start, reserved_end) >= 60)),
  CONSTRAINT chk_rr_actuals CHECK (checked_in_at IS NULL OR returned_at IS NULL
                                   OR returned_at >= checked_in_at),
  CONSTRAINT chk_rr_money CHECK (base_charge >= 0 AND discount_amount BETWEEN 0 AND base_charge
                                 AND late_fee >= 0 AND damage_fee >= 0
                                 AND cancellation_fee >= 0),
  INDEX idx_rr_table_window   (table_id, reserved_start, reserved_end),
  INDEX idx_rr_copy_window    (copy_id, reserved_start, reserved_end),
  INDEX idx_rr_customer_status(customer_id, status),
  INDEX idx_rr_status_end     (status, reserved_end),
  INDEX idx_rr_start          (reserved_start)
);

-- 11. One inspection per returned booking
CREATE TABLE Return_Inspections (
  inspection_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id          INT UNSIGNED NOT NULL UNIQUE,
  inspected_by        SMALLINT UNSIGNED NOT NULL,
  inspected_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  condition_on_return ENUM('New','Good','Fair','Worn','Damaged') NOT NULL,
  notes               VARCHAR(255) NULL,
  CONSTRAINT fk_insp_booking FOREIGN KEY (booking_id)
    REFERENCES Rentals_Reservations(booking_id) ON DELETE RESTRICT,
  CONSTRAINT fk_insp_staff FOREIGN KEY (inspected_by)
    REFERENCES Staff(staff_id) ON DELETE RESTRICT
);

-- 12. Missing pieces found in an inspection (M:N with attributes)
CREATE TABLE Missing_Pieces (
  inspection_id INT UNSIGNED NOT NULL,
  component_id  INT UNSIGNED NOT NULL,
  qty_missing   SMALLINT UNSIGNED NOT NULL,
  charge        DECIMAL(10,2) NOT NULL,     -- snapshot: qty x unit cost at the time
  restocked_at  DATETIME NULL,              -- set when staff replace the pieces
  PRIMARY KEY (inspection_id, component_id),
  CONSTRAINT fk_mp_inspection FOREIGN KEY (inspection_id)
    REFERENCES Return_Inspections(inspection_id) ON DELETE CASCADE,
  CONSTRAINT fk_mp_component FOREIGN KEY (component_id)
    REFERENCES Game_Components(component_id) ON DELETE RESTRICT,
  CONSTRAINT chk_mp CHECK (qty_missing >= 1 AND charge >= 0)
);

-- 13. Payments against a booking
CREATE TABLE Payments (
  payment_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id INT UNSIGNED NOT NULL,
  amount     DECIMAL(10,2) NOT NULL,
  method     ENUM('Cash','Card','UPI') NOT NULL,
  paid_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pay_booking FOREIGN KEY (booking_id)
    REFERENCES Rentals_Reservations(booking_id) ON DELETE RESTRICT,
  CONSTRAINT chk_pay_amount CHECK (amount > 0),
  INDEX idx_pay_paid_at (paid_at)
);

-- 14. Audit trail, written only by trigger
CREATE TABLE Booking_Audit_Log (
  log_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id INT UNSIGNED NOT NULL,
  old_status VARCHAR(12) NULL,
  new_status VARCHAR(12) NOT NULL,
  changed_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  changed_by VARCHAR(100) NOT NULL,
  CONSTRAINT fk_audit_booking FOREIGN KEY (booking_id)
    REFERENCES Rentals_Reservations(booking_id) ON DELETE CASCADE
);
```

# Appendix B — Database programs (tested on MySQL 8.0.46)

Run order: functions, validation procedure, workflow procedures, triggers, views, events, roles. Each file needs `USE boardgame_cafe;` at the top.

## B.1 Functions → sql/02_functions.sql

```sql
DELIMITER $$

CREATE FUNCTION fn_customer_age(p_customer_id INT UNSIGNED, p_on DATE)
RETURNS INT READS SQL DATA
BEGIN
  DECLARE v_dob DATE;
  SELECT date_of_birth INTO v_dob FROM Customers WHERE customer_id = p_customer_id;
  RETURN TIMESTAMPDIFF(YEAR, v_dob, p_on);
END$$

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
```

## B.2 Row-level validation procedure → sql/03_procedures.sql (first)

```sql
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
```

## B.3 Triggers → sql/04_triggers.sql

```sql
DELIMITER $$

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

CREATE TRIGGER trg_rr_after_insert AFTER INSERT ON Rentals_Reservations
FOR EACH ROW
BEGIN
  INSERT INTO Booking_Audit_Log (booking_id, old_status, new_status, changed_by)
  VALUES (NEW.booking_id, NULL, NEW.status, CURRENT_USER());
  IF NEW.copy_id IS NOT NULL AND NEW.status = 'Checked_In' THEN
    UPDATE Game_Copies SET status = 'Rented' WHERE copy_id = NEW.copy_id;
  END IF;
END$$

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

-- DELETE trigger (lab Exp 12): history is kept; only a free cancellation can be removed
CREATE TRIGGER trg_rr_before_delete BEFORE DELETE ON Rentals_Reservations
FOR EACH ROW
BEGIN
  IF NOT (OLD.status = 'Cancelled' AND OLD.cancellation_fee = 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-20: only free cancellations can be deleted; history is kept';
  END IF;
END$$

DELIMITER ;
```

## B.4 Workflow procedures → sql/03_procedures.sql

```sql
DELIMITER $$

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

CREATE PROCEDURE sp_mark_no_shows()
MODIFIES SQL DATA
BEGIN
  UPDATE Rentals_Reservations
     SET status = 'No_Show', discount_amount = 0, base_charge = 0, cancellation_fee = 100.00
   WHERE status = 'Reserved' AND reserved_start < NOW() - INTERVAL 30 MINUTE;
END$$

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

CREATE PROCEDURE sp_record_payment(IN p_booking_id INT UNSIGNED, IN p_amount DECIMAL(10,2),
                                   IN p_method VARCHAR(5))
MODIFIES SQL DATA
BEGIN
  INSERT INTO Payments (booking_id, amount, method) VALUES (p_booking_id, p_amount, p_method);
END$$

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
```

## B.5 Views → sql/05_views.sql

```sql
CREATE OR REPLACE VIEW vw_game_catalog AS
SELECT bg.game_id, bg.title, bg.publisher, bg.min_players, bg.max_players, bg.min_age,
       bg.avg_play_minutes, bg.complexity, bg.hourly_rate, bg.daily_rate,
       (SELECT GROUP_CONCAT(cat.category_name ORDER BY cat.category_name SEPARATOR ', ')
          FROM Board_Game_Categories bgc
          JOIN Game_Categories cat ON cat.category_id = bgc.category_id
         WHERE bgc.game_id = bg.game_id) AS categories,
       (SELECT COUNT(*) FROM Game_Copies c
         WHERE c.game_id = bg.game_id AND c.status <> 'Retired')   AS copies_owned,
       (SELECT COUNT(*) FROM Game_Copies c
         WHERE c.game_id = bg.game_id AND c.status = 'Available')  AS copies_on_shelf
  FROM Board_Games bg;

CREATE OR REPLACE VIEW vw_active_bookings AS
SELECT rr.booking_id, rr.booking_type, rr.status,
       CONCAT(c.first_name, ' ', c.last_name) AS customer, c.phone,
       ct.table_code, ct.zone, rr.party_size, bg.title AS game, gc.barcode,
       rr.reserved_start, rr.reserved_end, rr.checked_in_at
  FROM Rentals_Reservations rr
  JOIN Customers c         ON c.customer_id = rr.customer_id
  LEFT JOIN Cafe_Tables ct ON ct.table_id   = rr.table_id
  LEFT JOIN Game_Copies gc ON gc.copy_id    = rr.copy_id
  LEFT JOIN Board_Games bg ON bg.game_id    = gc.game_id
 WHERE rr.status IN ('Reserved','Checked_In','Overdue');

CREATE OR REPLACE VIEW vw_available_copies_now AS
SELECT gc.copy_id, gc.barcode, bg.title, gc.copy_condition, gc.shelf_location
  FROM Game_Copies gc
  JOIN Board_Games bg ON bg.game_id = gc.game_id
 WHERE gc.status = 'Available'
   AND fn_copy_is_free(gc.copy_id, NOW(), NOW() + INTERVAL 1 MINUTE, NULL);

CREATE OR REPLACE VIEW vw_overdue_rentals AS
SELECT rr.booking_id, CONCAT(c.first_name, ' ', c.last_name) AS customer, c.phone,
       rr.booking_type, bg.title AS game, gc.barcode, rr.reserved_end,
       TIMESTAMPDIFF(MINUTE, rr.reserved_end, NOW()) AS minutes_late,
       fn_calculate_late_fee(rr.booking_id, NOW())   AS late_fee_so_far
  FROM Rentals_Reservations rr
  JOIN Customers c         ON c.customer_id = rr.customer_id
  LEFT JOIN Game_Copies gc ON gc.copy_id    = rr.copy_id
  LEFT JOIN Board_Games bg ON bg.game_id    = gc.game_id
 WHERE rr.status = 'Overdue';

CREATE OR REPLACE VIEW vw_customer_balances AS
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS customer,
       t.tier_name, c.status,
       IFNULL(b.billed, 0) AS total_billed, IFNULL(p.paid, 0) AS total_paid,
       IFNULL(b.billed, 0) - IFNULL(p.paid, 0) AS balance
  FROM Customers c
  JOIN Membership_Tiers t ON t.tier_id = c.tier_id
  LEFT JOIN (SELECT customer_id, SUM(total_amount) AS billed
               FROM Rentals_Reservations
              WHERE status IN ('Completed','Cancelled','No_Show')
              GROUP BY customer_id) b ON b.customer_id = c.customer_id
  LEFT JOIN (SELECT rr.customer_id, SUM(pay.amount) AS paid
               FROM Payments pay
               JOIN Rentals_Reservations rr ON rr.booking_id = pay.booking_id
              GROUP BY rr.customer_id) p ON p.customer_id = c.customer_id;

CREATE OR REPLACE VIEW vw_game_popularity AS
SELECT bg.game_id, bg.title,
       COUNT(rr.booking_id)                               AS times_played,
       COUNT(DISTINCT rr.customer_id)                     AS distinct_customers,
       ROUND(IFNULL(SUM(rr.duration_minutes), 0) / 60, 1) AS hours_played,
       IFNULL(SUM(rr.total_amount), 0)                    AS booking_revenue
  FROM Board_Games bg
  LEFT JOIN Game_Copies gc          ON gc.game_id = bg.game_id
  LEFT JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id AND rr.status = 'Completed'
 GROUP BY bg.game_id, bg.title;

CREATE OR REPLACE VIEW vw_table_utilization_30d AS
SELECT ct.table_id, ct.table_code, ct.zone, ct.seating_capacity,
       COUNT(rr.booking_id) AS bookings,
       IFNULL(SUM(rr.duration_minutes), 0) AS booked_minutes,
       ROUND(100 * IFNULL(SUM(rr.duration_minutes), 0) / (30 * 13 * 60), 1) AS utilization_pct,
       ROUND(100 * AVG(rr.party_size / ct.seating_capacity), 1)           AS avg_seat_fill_pct
  FROM Cafe_Tables ct
  LEFT JOIN Rentals_Reservations rr
         ON rr.table_id = ct.table_id
        AND rr.status IN ('Checked_In','Overdue','Completed')
        AND rr.reserved_start >= NOW() - INTERVAL 30 DAY
 GROUP BY ct.table_id, ct.table_code, ct.zone, ct.seating_capacity;

CREATE OR REPLACE VIEW vw_copies_needing_attention AS
SELECT gc.copy_id, gc.barcode, bg.title, gc.status, gc.copy_condition,
       GROUP_CONCAT(CONCAT(mp.qty_missing, ' x ', comp.component_name) SEPARATOR '; ') AS missing,
       IFNULL(SUM(mp.charge), 0) AS charged_to_customers
  FROM Game_Copies gc
  JOIN Board_Games bg ON bg.game_id = gc.game_id
  LEFT JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id
  LEFT JOIN Return_Inspections ri   ON ri.booking_id = rr.booking_id
  LEFT JOIN Missing_Pieces mp       ON mp.inspection_id = ri.inspection_id
                                   AND mp.restocked_at IS NULL
  LEFT JOIN Game_Components comp    ON comp.component_id = mp.component_id
 WHERE gc.status IN ('Missing_Pieces','Under_Repair')
 GROUP BY gc.copy_id, gc.barcode, bg.title, gc.status, gc.copy_condition;

-- Updatable view with CHECK OPTION: the front desk edits only active members
CREATE OR REPLACE VIEW vw_active_members AS
SELECT customer_id, first_name, last_name, email, phone, date_of_birth,
       tier_id, membership_expiry, status
  FROM Customers
 WHERE status = 'Active'
WITH CASCADED CHECK OPTION;
-- It carries every NOT NULL column without a default (incl. date_of_birth), so INSERT through it works.
-- UPDATE vw_active_members SET status = 'Suspended' WHERE customer_id = 3;  -- rejected: CHECK OPTION failed
```

## B.6 Events → sql/06_events.sql

```sql
SET GLOBAL event_scheduler = ON;

CREATE EVENT IF NOT EXISTS ev_mark_overdue
  ON SCHEDULE EVERY 15 MINUTE
  DO UPDATE Rentals_Reservations SET status = 'Overdue'
      WHERE status = 'Checked_In' AND reserved_end < NOW() - INTERVAL 15 MINUTE;

CREATE EVENT IF NOT EXISTS ev_mark_no_shows
  ON SCHEDULE EVERY 15 MINUTE
  DO CALL sp_mark_no_shows();

CREATE EVENT IF NOT EXISTS ev_flag_suspensions
  ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR)
  DO CALL sp_flag_suspensions();
```

## B.7 Roles and privileges → sql/07_roles.sql

```sql
CREATE ROLE IF NOT EXISTS 'cafe_admin', 'front_desk', 'analyst';

GRANT ALL PRIVILEGES ON boardgame_cafe.* TO 'cafe_admin';

GRANT SELECT ON boardgame_cafe.vw_game_catalog         TO 'front_desk';
GRANT SELECT ON boardgame_cafe.vw_active_bookings      TO 'front_desk';
GRANT SELECT ON boardgame_cafe.vw_available_copies_now TO 'front_desk';
GRANT SELECT ON boardgame_cafe.vw_overdue_rentals      TO 'front_desk';
GRANT SELECT, INSERT, UPDATE ON boardgame_cafe.vw_active_members TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_create_reservation TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_check_in           TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_check_out          TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_cancel_booking     TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_find_free_tables   TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_recommend_games    TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_record_payment     TO 'front_desk';

GRANT SELECT ON boardgame_cafe.vw_game_popularity       TO 'analyst';
GRANT SELECT ON boardgame_cafe.vw_table_utilization_30d TO 'analyst';
GRANT SELECT ON boardgame_cafe.vw_customer_balances     TO 'analyst';

CREATE USER IF NOT EXISTS 'desk_priya'@'localhost' IDENTIFIED BY 'ChangeMe#2026';
CREATE USER IF NOT EXISTS 'owner_ravi'@'localhost' IDENTIFIED BY 'ChangeMe#2026';
CREATE USER IF NOT EXISTS 'report_bot'@'localhost' IDENTIFIED BY 'ChangeMe#2026';
GRANT 'front_desk' TO 'desk_priya'@'localhost';
GRANT 'cafe_admin' TO 'owner_ravi'@'localhost';
GRANT 'analyst'    TO 'report_bot'@'localhost';
SET DEFAULT ROLE ALL TO 'desk_priya'@'localhost', 'owner_ravi'@'localhost', 'report_bot'@'localhost';

-- Demo: take away cancellations from the front desk, then check
REVOKE EXECUTE ON PROCEDURE boardgame_cafe.sp_cancel_booking FROM 'front_desk';
SHOW GRANTS FOR 'desk_priya'@'localhost' USING 'front_desk';
```

# Appendix C — Query bank and demos (tested on MySQL 8.0.46)

Every item below ran without error against the seed data. T2, T3 and T4 are two-session demos described in Section 9; T1 needs `@b` set to a Completed booking with at least ₹200 unpaid; the walkthrough's IDs 5, 3, 12, 2 and 31 are placeholders that `sql/13_walkthrough.sql` must replace with IDs it looks up itself.

### Q01 — Which games suit a group of 5, youngest player 10, under an hour?

```sql
SELECT title, min_players, max_players, min_age, avg_play_minutes, complexity
  FROM Board_Games
 WHERE 5 BETWEEN min_players AND max_players
   AND min_age <= 10
   AND avg_play_minutes <= 60
 ORDER BY complexity, title;
```

### Q02 — Whose membership expires in the next 30 days?

```sql
SELECT customer_id, CONCAT(first_name, ' ', last_name) AS member, email, membership_expiry,
       DATEDIFF(membership_expiry, CURRENT_DATE) AS days_left
  FROM Customers
 WHERE membership_expiry BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL 30 DAY
 ORDER BY membership_expiry;
```

### Q03 — Which large tables (6+ seats) are in the Party Room or on the Patio, accessible first?

```sql
SELECT table_code, zone, seating_capacity, hourly_rate, is_accessible
  FROM Cafe_Tables
 WHERE zone IN ('Party_Room', 'Patio') AND seating_capacity >= 6 AND is_active
 ORDER BY is_accessible DESC, seating_capacity;
```

### Q04 — Find a member from a partial name or the last digits of a phone number (LIKE).

```sql
SELECT customer_id, first_name, last_name, phone
  FROM Customers
 WHERE first_name LIKE 'Ar%' OR last_name LIKE '%sh%' OR phone LIKE '%4321';
```

### Q05 — Today's floor plan: every booking with customer, table and game (INNER + LEFT JOIN).

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

### Q06 — Full catalogue with categories (M:N join + GROUP_CONCAT).

```sql
SELECT bg.title,
       GROUP_CONCAT(cat.category_name ORDER BY cat.category_name SEPARATOR ', ') AS categories
  FROM Board_Games bg
  JOIN Board_Game_Categories bgc ON bgc.game_id   = bg.game_id
  JOIN Game_Categories cat       ON cat.category_id = bgc.category_id
 GROUP BY bg.game_id, bg.title
 ORDER BY bg.title;
```

### Q07 — Which tables had no bookings in the last 7 days (LEFT JOIN … IS NULL)?

```sql
SELECT ct.table_code, ct.zone
  FROM Cafe_Tables ct
  LEFT JOIN Rentals_Reservations rr
         ON rr.table_id = ct.table_id
        AND rr.reserved_start >= CURRENT_DATE - INTERVAL 7 DAY
 WHERE rr.booking_id IS NULL;
```

### Q08 — Integrity audit: are any two active bookings overlapping on one table (self-join)?

```sql
SELECT a.booking_id AS booking_a, b.booking_id AS booking_b, ct.table_code,
       a.reserved_start AS a_start, a.reserved_end AS a_end,
       b.reserved_start AS b_start, b.reserved_end AS b_end
  FROM Rentals_Reservations a
  JOIN Rentals_Reservations b
    ON a.table_id = b.table_id
   AND a.booking_id < b.booking_id
   AND a.reserved_start < b.reserved_end
   AND b.reserved_start < a.reserved_end
  JOIN Cafe_Tables ct ON ct.table_id = a.table_id
 WHERE a.status IN ('Reserved', 'Checked_In', 'Overdue')
   AND b.status IN ('Reserved', 'Checked_In', 'Overdue');
```

### Q09 — How many returns has each staff member inspected, including staff with none (RIGHT JOIN)?

```sql
SELECT s.full_name, s.role, COUNT(ri.inspection_id) AS inspections
  FROM Return_Inspections ri
 RIGHT JOIN Staff s ON s.staff_id = ri.inspected_by
 GROUP BY s.staff_id, s.full_name, s.role
 ORDER BY inspections DESC;
```

### Q10 — Revenue by month and booking type, with subtotals (GROUP BY … WITH ROLLUP).

```sql
SELECT DATE_FORMAT(reserved_start, '%Y-%m') AS month, booking_type,
       COUNT(*) AS bookings, SUM(total_amount) AS revenue
  FROM Rentals_Reservations
 WHERE status IN ('Completed', 'Cancelled', 'No_Show')
 GROUP BY month, booking_type WITH ROLLUP;
```

### Q11 — Which zones average more than 3 guests per booking (HAVING)?

```sql
SELECT ct.zone, COUNT(*) AS bookings, ROUND(AVG(rr.party_size), 2) AS avg_party,
       ROUND(100 * AVG(rr.party_size / ct.seating_capacity), 1) AS avg_seat_fill_pct
  FROM Rentals_Reservations rr
  JOIN Cafe_Tables ct ON ct.table_id = rr.table_id
 WHERE rr.status = 'Completed'
 GROUP BY ct.zone
HAVING AVG(rr.party_size) > 3;
```

### Q12 — Which games lose the most pieces, and how much was charged?

```sql
SELECT bg.title, SUM(mp.qty_missing) AS pieces_lost, SUM(mp.charge) AS charged,
       COUNT(DISTINCT mp.inspection_id) AS bad_returns
  FROM Missing_Pieces mp
  JOIN Game_Components comp ON comp.component_id = mp.component_id
  JOIN Board_Games bg       ON bg.game_id        = comp.game_id
 GROUP BY bg.game_id, bg.title
 ORDER BY pieces_lost DESC;
```

### Q13 — What share of each game's returns came back with missing pieces (derived table + correlated EXISTS)?

```sql
SELECT bg.title,
       COUNT(*)                        AS returns_inspected,
       SUM(x.had_loss)                 AS returns_with_losses,
       ROUND(100 * AVG(x.had_loss), 1) AS loss_rate_pct
  FROM (SELECT ri.inspection_id, rr.copy_id,
               EXISTS (SELECT 1 FROM Missing_Pieces mp
                        WHERE mp.inspection_id = ri.inspection_id) AS had_loss
          FROM Return_Inspections ri
          JOIN Rentals_Reservations rr ON rr.booking_id = ri.booking_id) AS x
  JOIN Game_Copies gc ON gc.copy_id = x.copy_id
  JOIN Board_Games bg ON bg.game_id = gc.game_id
 GROUP BY bg.game_id, bg.title
 ORDER BY loss_rate_pct DESC;
```

### Q14 — Copy condition by game, as a pivot (conditional aggregation).

```sql
SELECT bg.title,
       SUM(gc.copy_condition = 'New')     AS new_copies,
       SUM(gc.copy_condition = 'Good')    AS good,
       SUM(gc.copy_condition = 'Fair')    AS fair,
       SUM(gc.copy_condition = 'Worn')    AS worn,
       SUM(gc.copy_condition = 'Damaged') AS damaged,
       COUNT(*)                           AS total
  FROM Game_Copies gc
  JOIN Board_Games bg ON bg.game_id = gc.game_id
 WHERE gc.status <> 'Retired'
 GROUP BY bg.game_id, bg.title
 ORDER BY bg.title;
```

### Q15 — Which games are played more than the average game (subquery in HAVING over a derived table)?

```sql
SELECT bg.title, COUNT(rr.booking_id) AS plays
  FROM Board_Games bg
  JOIN Game_Copies gc          ON gc.game_id = bg.game_id
  JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id AND rr.status = 'Completed'
 GROUP BY bg.game_id, bg.title
HAVING COUNT(rr.booking_id) > (
         SELECT AVG(per_game.plays)
           FROM (SELECT COUNT(rr2.booking_id) AS plays
                   FROM Board_Games bg2
                   LEFT JOIN Game_Copies gc2          ON gc2.game_id = bg2.game_id
                   LEFT JOIN Rentals_Reservations rr2 ON rr2.copy_id = gc2.copy_id
                                                     AND rr2.status = 'Completed'
                  GROUP BY bg2.game_id) AS per_game)
 ORDER BY plays DESC;
```

### Q16 — Which games have never been played (NOT EXISTS anti-join)?

```sql
SELECT bg.title
  FROM Board_Games bg
 WHERE NOT EXISTS (SELECT 1
                     FROM Game_Copies gc
                     JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id
                    WHERE gc.game_id = bg.game_id);
```

### Q17 — Model members: have completed bookings and never paid a late or damage fee (IN / NOT IN).

```sql
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member
  FROM Customers c
 WHERE c.customer_id IN (SELECT customer_id FROM Rentals_Reservations
                          WHERE status = 'Completed')
   AND c.customer_id NOT IN (SELECT customer_id FROM Rentals_Reservations
                              WHERE late_fee > 0 OR damage_fee > 0);
```

### Q18 — Each member's most recent completed visit and what they played (correlated subquery).

```sql
SELECT c.first_name, c.last_name, rr.reserved_start AS last_visit,
       IFNULL(bg.title, '(table only)') AS played
  FROM Customers c
  JOIN Rentals_Reservations rr ON rr.customer_id = c.customer_id AND rr.status = 'Completed'
  LEFT JOIN Game_Copies gc     ON gc.copy_id = rr.copy_id
  LEFT JOIN Board_Games bg     ON bg.game_id = gc.game_id
 WHERE rr.reserved_start = (SELECT MAX(r2.reserved_start)
                              FROM Rentals_Reservations r2
                             WHERE r2.customer_id = c.customer_id
                               AND r2.status = 'Completed');
```

### Q19 — Tables bigger than every table in the Quiet Corner (> ALL).

```sql
SELECT table_code, zone, seating_capacity
  FROM Cafe_Tables
 WHERE seating_capacity > ALL (SELECT seating_capacity FROM Cafe_Tables
                                WHERE zone = 'Quiet_Corner');
```

### Q20 — Who has played every Party game? (relational division, double NOT EXISTS)

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

### Q21 — One reminder list: memberships expiring within 7 days plus anyone holding an overdue game (UNION).

```sql
SELECT c.email, 'Membership expiring' AS reason
  FROM Customers c
 WHERE c.membership_expiry BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL 7 DAY
UNION
SELECT c.email, 'Overdue rental'
  FROM Customers c
  JOIN Rentals_Reservations rr ON rr.customer_id = c.customer_id
 WHERE rr.status = 'Overdue'
 ORDER BY email;
```

### Q22 — Members who have both played in the café and taken a game home (INTERSECT).

```sql
SELECT customer_id FROM Rentals_Reservations
 WHERE booking_type = 'Dine_In' AND status = 'Completed'
INTERSECT
SELECT customer_id FROM Rentals_Reservations
 WHERE booking_type = 'Take_Home' AND status = 'Completed';
```

### Q23 — Tables that have never been booked at all (EXCEPT).

```sql
SELECT ct.table_code, ct.zone
  FROM Cafe_Tables ct
 WHERE ct.table_id IN (SELECT table_id FROM Cafe_Tables
                       EXCEPT
                       SELECT table_id FROM Rentals_Reservations WHERE table_id IS NOT NULL);
```

### Q24 — Rank games by plays inside each category (RANK vs DENSE_RANK).

```sql
SELECT category_name, title, plays,
       RANK()       OVER (PARTITION BY category_name ORDER BY plays DESC) AS rank_in_category,
       DENSE_RANK() OVER (PARTITION BY category_name ORDER BY plays DESC) AS dense_rank_in_category
  FROM (SELECT cat.category_name, bg.title, COUNT(rr.booking_id) AS plays
          FROM Game_Categories cat
          JOIN Board_Game_Categories bgc    ON bgc.category_id = cat.category_id
          JOIN Board_Games bg               ON bg.game_id      = bgc.game_id
          LEFT JOIN Game_Copies gc          ON gc.game_id      = bg.game_id
          LEFT JOIN Rentals_Reservations rr ON rr.copy_id      = gc.copy_id
                                           AND rr.status = 'Completed'
         GROUP BY cat.category_id, cat.category_name, bg.game_id, bg.title) AS t
 ORDER BY category_name, rank_in_category;
```

### Q25 — Top 3 spenders in each membership tier (CTE + ROW_NUMBER).

```sql
WITH spend AS (
  SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member,
         t.tier_name, SUM(rr.total_amount) AS total_spent
    FROM Customers c
    JOIN Membership_Tiers t      ON t.tier_id      = c.tier_id
    JOIN Rentals_Reservations rr ON rr.customer_id = c.customer_id AND rr.status = 'Completed'
   GROUP BY c.customer_id, c.first_name, c.last_name, t.tier_id, t.tier_name
), ranked AS (
  SELECT spend.*,
         ROW_NUMBER() OVER (PARTITION BY tier_name ORDER BY total_spent DESC) AS position
    FROM spend
)
SELECT tier_name, position, member, total_spent
  FROM ranked
 WHERE position <= 3
 ORDER BY tier_name, position;
```

### Q26 — Daily revenue with a running total and 7-day moving average (SUM/AVG OVER with a frame).

```sql
WITH daily AS (
  SELECT DATE(returned_at) AS day, SUM(total_amount) AS revenue
    FROM Rentals_Reservations
   WHERE status = 'Completed'
   GROUP BY DATE(returned_at)
)
SELECT day, revenue,
       SUM(revenue) OVER (ORDER BY day) AS running_total,
       ROUND(AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2)
         AS moving_avg_7d
  FROM daily
 ORDER BY day;
```

### Q27 — Days between each member's visits (LAG with a named window).

```sql
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member,
       rr.reserved_start AS visit,
       LAG(rr.reserved_start) OVER w AS previous_visit,
       DATEDIFF(rr.reserved_start, LAG(rr.reserved_start) OVER w) AS days_since_previous
  FROM Rentals_Reservations rr
  JOIN Customers c ON c.customer_id = rr.customer_id
 WHERE rr.status = 'Completed'
WINDOW w AS (PARTITION BY rr.customer_id ORDER BY rr.reserved_start)
 ORDER BY c.customer_id, rr.reserved_start;
```

### Q28 — Split members into spend quartiles (NTILE).

```sql
SELECT customer, tier_name, total_billed,
       NTILE(4) OVER (ORDER BY total_billed DESC) AS spend_quartile
  FROM vw_customer_balances
 ORDER BY spend_quartile, total_billed DESC;
```

### Q29 — Tomorrow's availability grid: every table × every half-hour slot (recursive CTE + CROSS JOIN).

```sql
WITH RECURSIVE slots AS (
  SELECT TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '10:00:00') AS slot_start
  UNION ALL
  SELECT slot_start + INTERVAL 30 MINUTE
    FROM slots
   WHERE slot_start + INTERVAL 30 MINUTE < TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '23:00:00')
)
SELECT TIME_FORMAT(s.slot_start, '%H:%i') AS slot, ct.table_code,
       CASE WHEN fn_table_is_free(ct.table_id, s.slot_start, s.slot_start + INTERVAL 30 MINUTE, NULL)
            THEN 'free' ELSE 'booked' END AS state
  FROM slots s
 CROSS JOIN Cafe_Tables ct
 WHERE ct.is_active
 ORDER BY s.slot_start, ct.table_code;
```

### Q30 — Peak hours by weekday, banded with CASE.

```sql
WITH visits AS (
  SELECT DAYNAME(reserved_start) AS weekday, DAYOFWEEK(reserved_start) AS dow,
         HOUR(reserved_start) AS hour_of_day, party_size
    FROM Rentals_Reservations
   WHERE booking_type = 'Dine_In' AND status = 'Completed'
)
SELECT weekday, hour_of_day, COUNT(*) AS bookings, SUM(party_size) AS guests,
       CASE WHEN COUNT(*) >= 5 THEN 'Peak'
            WHEN COUNT(*) >= 2 THEN 'Normal'
            ELSE 'Quiet' END AS load_band
  FROM visits
 GROUP BY dow, weekday, hour_of_day
 ORDER BY dow, hour_of_day;
```

### Q31 — Smallest free table for 5 people tomorrow 18:00–21:00.

```sql
CALL sp_find_free_tables(5, TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '18:00:00'),
                            TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '21:00:00'), FALSE);
```

### Q32 — Games for 4 players, youngest 12, at most 90 minutes, with a copy free in that window.

```sql
CALL sp_recommend_games(4, 12, 90, TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '18:00:00'),
                                   TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '21:00:00'));
```

### Q33 — Who is holding a game past its end time, and what do they owe so far?

```sql
SELECT * FROM vw_overdue_rentals ORDER BY minutes_late DESC;
```

### Q34 — Which copies are off the shelf for repair or missing pieces, and what is missing?

```sql
SELECT * FROM vw_copies_needing_attention ORDER BY title;
```

### Q35 — Which members would be refused a booking right now, and why (CASE over a derived table)?

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

### Q36 — Reservations in the next 24 hours whose game copy is still out with someone else.

```sql
SELECT nxt.booking_id, nxt.reserved_start, bg.title, gc.barcode,
       cur.booking_id AS held_by_booking, cur.status AS held_status, cur.reserved_end AS due_back
  FROM Rentals_Reservations nxt
  JOIN Game_Copies gc          ON gc.copy_id = nxt.copy_id
  JOIN Board_Games bg          ON bg.game_id = gc.game_id
  JOIN Rentals_Reservations cur ON cur.copy_id = nxt.copy_id
                               AND cur.booking_id <> nxt.booking_id
                               AND cur.status IN ('Checked_In', 'Overdue')
 WHERE nxt.status = 'Reserved'
   AND nxt.reserved_start BETWEEN NOW() AND NOW() + INTERVAL 24 HOUR;
```

### End-to-end walkthrough — book, check in, return with missing pieces, pay, restock.

```sql
SET @start = TIMESTAMP(CURRENT_DATE, SEC_TO_TIME(FLOOR(TIME_TO_SEC(CURRENT_TIME) / 1800) * 1800));
SET @end   = @start + INTERVAL 2 HOUR;
CALL sp_find_free_tables(4, @start, @end, FALSE);          -- pick a table_id, e.g. 3
CALL sp_recommend_games(4, 16, 120, @start, @end);          -- pick suggested_copy_id, e.g. 12
CALL sp_create_reservation(5, 'Dine_In', 3, 12, 4, @start, @end, @booking);
CALL sp_check_in(@booking);
CALL sp_check_out(@booking, 2, 'Good', '[{"component_id": 31, "qty": 2}]', '2 cards missing');
SELECT base_charge, discount_amount, late_fee, damage_fee, total_amount
  FROM Rentals_Reservations WHERE booking_id = @booking;
SELECT status FROM Game_Copies WHERE copy_id = 12;          -- Missing_Pieces
SELECT total_amount INTO @due FROM Rentals_Reservations WHERE booking_id = @booking;
CALL sp_record_payment(@booking, @due, 'UPI');
CALL sp_restock_copy(12);                                   -- copy back to Available
SELECT * FROM Booking_Audit_Log WHERE booking_id = @booking; -- Reserved → Checked_In → Completed
```

### Q37 — Retire worn copies that have come back short 3 or more times (UPDATE with JOIN to a derived table).

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

### Q38 — Buy a new copy of every game that has no copy in service (INSERT … SELECT).

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

### Q39 — Add a component or update its price if it already exists (upsert).

```sql
INSERT INTO Game_Components (game_id, component_name, qty_per_copy, unit_replacement_cost)
VALUES (1, 'Robber pawn', 1, 40.00) AS new_row
ON DUPLICATE KEY UPDATE unit_replacement_cost = new_row.unit_replacement_cost;
```

### Q40 — Purge audit entries older than 2 years for closed bookings (DELETE with subquery).

```sql
DELETE FROM Booking_Audit_Log
 WHERE changed_at < NOW() - INTERVAL 2 YEAR
   AND booking_id IN (SELECT booking_id FROM Rentals_Reservations
                       WHERE status IN ('Completed', 'Cancelled', 'No_Show'));
```

### T1 — SAVEPOINT: keep a good payment, undo a bad one.

```sql
START TRANSACTION;
INSERT INTO Payments (booking_id, amount, method) VALUES (@b, 200.00, 'UPI');
SAVEPOINT after_first_payment;
INSERT INTO Payments (booking_id, amount, method) VALUES (@b, 99999.00, 'Cash');  -- PAY-02 error
ROLLBACK TO SAVEPOINT after_first_payment;
COMMIT;                                       -- only the ₹200 payment is saved
```

### X1 — See the optimizer use, and not use, an index.

```sql
-- Uses idx_customer_name (type = ref)
EXPLAIN SELECT customer_id, first_name, phone FROM Customers WHERE last_name = 'Sharma';
-- Same query forced to scan (type = ALL)
EXPLAIN SELECT customer_id, first_name, phone FROM Customers IGNORE INDEX (idx_customer_name)
 WHERE last_name = 'Sharma';
-- Non-sargable: wrapping the column in DATE() hides idx_rr_start
EXPLAIN SELECT * FROM Rentals_Reservations WHERE DATE(reserved_start) = CURRENT_DATE;
-- Sargable range: uses idx_rr_start
EXPLAIN SELECT * FROM Rentals_Reservations
 WHERE reserved_start >= CURRENT_DATE AND reserved_start < CURRENT_DATE + INTERVAL 1 DAY;
-- Real timings for the overlap check behind BR-05
EXPLAIN ANALYZE SELECT COUNT(*) FROM Rentals_Reservations
 WHERE table_id = 3 AND reserved_start < NOW() + INTERVAL 1 DAY AND reserved_end > NOW();
```

### L1 — DDL on a sandbox table: CREATE, ALTER (add, modify, constraint, rename column), RENAME, TRUNCATE, DROP (Exp 2).

```sql
CREATE TABLE Event_Nights (
  night_id   INT AUTO_INCREMENT PRIMARY KEY,
  theme      VARCHAR(60) NOT NULL,
  night_date DATE NOT NULL
);
ALTER TABLE Event_Nights ADD COLUMN entry_fee DECIMAL(8,2) NOT NULL DEFAULT 0;
ALTER TABLE Event_Nights MODIFY COLUMN theme VARCHAR(100) NOT NULL;
ALTER TABLE Event_Nights ADD CONSTRAINT chk_event_fee CHECK (entry_fee >= 0);
ALTER TABLE Event_Nights RENAME COLUMN night_date TO event_date;
RENAME TABLE Event_Nights TO Theme_Nights;
INSERT INTO Theme_Nights (theme, event_date, entry_fee)                    -- multi-row INSERT (Exp 4)
VALUES ('Catan tournament', CURRENT_DATE + INTERVAL 7 DAY, 200.00),
       ('Werewolf Friday',  CURRENT_DATE + INTERVAL 4 DAY,   0.00);
DESCRIBE Theme_Nights;
TRUNCATE TABLE Theme_Nights;   -- DDL: removes all rows, resets AUTO_INCREMENT, cannot be rolled back
DROP TABLE Theme_Nights;
CREATE DATABASE IF NOT EXISTS cafe_sandbox;
DROP DATABASE cafe_sandbox;
```

### Q41 — Which zones hosted a booking in the last 30 days? (DISTINCT, BETWEEN, IN, NOT IN, the `_` wildcard — Exp 5)

```sql
SELECT DISTINCT ct.zone
  FROM Rentals_Reservations rr
  JOIN Cafe_Tables ct ON ct.table_id = rr.table_id
 WHERE rr.reserved_start BETWEEN CURRENT_DATE - INTERVAL 30 DAY AND CURRENT_DATE
   AND rr.status IN ('Completed', 'Checked_In')
   AND ct.seating_capacity NOT IN (2)
   AND ct.table_code LIKE '__-0_';          -- each _ matches exactly one character
```

### Q42 — Top 5 games by plays, with group-size and session-length extremes (COUNT, MIN, MAX, AVG, ORDER BY, LIMIT — Exp 6).

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

### Q43 — Plays per game, last 30 days vs the 30 before, including games played in only one window (FULL OUTER JOIN — Exp 7).

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

### Q44 — For each pending reservation, every table that could seat the group and how many seats would sit empty (non-equi join — Exp 7).

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

### L2 — Operations on a view: SELECT, INSERT and UPDATE through `vw_active_members`, and the CHECK OPTION refusing a change that would hide the row (Exp 9).

```sql
SELECT customer_id, first_name, tier_id, status FROM vw_active_members LIMIT 5;
INSERT INTO vw_active_members (first_name, last_name, email, phone, date_of_birth,
                               tier_id, membership_expiry, status)
VALUES ('Lavanya', 'Rao', 'lavanya.rao@mail.test', '9876501234', '2001-04-09',
        2, CURRENT_DATE + INTERVAL 1 YEAR, 'Active');                      -- lands in Customers
UPDATE vw_active_members SET tier_id = 3 WHERE email = 'lavanya.rao@mail.test';
UPDATE vw_active_members SET status = 'Suspended'
 WHERE email = 'lavanya.rao@mail.test';          -- ERROR 1369: CHECK OPTION failed
```

### L3 — More DCL: WITH GRANT OPTION, REVOKE ALL, and proving least privilege (Exp 10).

```sql
GRANT SELECT ON boardgame_cafe.vw_game_catalog TO 'owner_ravi'@'localhost' WITH GRANT OPTION;
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'report_bot'@'localhost';
SHOW GRANTS FOR 'report_bot'@'localhost';     -- the analyst role is still listed
-- Logged in as report_bot:
SELECT COUNT(*) FROM boardgame_cafe.vw_game_popularity;   -- allowed through the role
SELECT COUNT(*) FROM boardgame_cafe.Customers;            -- ERROR 1142: SELECT command denied
-- Logged in as desk_priya:
CALL boardgame_cafe.sp_find_free_tables(4, NOW() + INTERVAL 1 DAY, NOW() + INTERVAL 1 DAY + INTERVAL 2 HOUR, FALSE);  -- allowed
INSERT INTO boardgame_cafe.Payments (booking_id, amount, method) VALUES (1, 1, 'UPI');   -- ERROR 1142: INSERT denied
```
