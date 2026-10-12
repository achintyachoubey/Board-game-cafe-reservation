# Board Game Café & Table Reservation System — RDBMS project

A relational database (MySQL 8.0) for a board game café: members book café tables and borrow
physical game boxes, either to play at a table (**Dine_In**) or to take home (**Take_Home**). It is a
deliberate twist on the classic Library Management System — books become board games, library
cards become memberships — with three extra rules that make it interesting: the number of players
must fit **both the game and the table**, every game has an **age limit**, and every returned box is
**inspected for missing pieces**. Every rule is enforced inside the database (constraints, triggers,
stored procedures), not in application code.

There is **no front end**. Every demo runs in the MySQL client (`mysql` shell or MySQL Workbench).
Python is used only to generate the seed data, build the database, capture evidence and run the tests.

Course: CSC2103 Relational Database Management Systems / Lab CSC2131 (RDBMS Lab Manual 2026-27),
B.Tech CSE Semester III, Manipal University Jaipur, July–Nov 2026.

| | |
| --- | --- |
| Tables | 14 (`Customers`, `Board_Games`, `Cafe_Tables`, `Rentals_Reservations` at the centre) |
| Programs | 6 functions · 11 procedures · 10 triggers · 9 views · 3 events · 3 roles |
| Constraints | 14 PK · 14 FK · 21 CHECK · 10 UNIQUE |
| Seed data | 30 members, 25 games, 60 copies, 16 tables, 347 bookings (325 in the last 90 days) |
| Queries | Q01–Q44 + T1–T4 transactions + X1 indexing + L1–L3 lab extras + an end-to-end walkthrough |
| Tests | 129 pytest tests (TC-01 … TC-36 plus schema, query, concurrency and security checks), all passing |

## Repository layout

```text
README.md                   this file
CLAUDE_CODE_PROMPT.md       the build specification
docker-compose.yml          MySQL 8.0 server (event scheduler on, log_bin_trust_function_creators=1)
.env.example                connection settings - copy to .env
requirements.txt            PyMySQL, pytest, python-dotenv (pinned)
sql/00_drop_all.sql         drop database, roles, demo users (idempotent)
sql/01_schema.sql           14 tables with COMMENTs on every table and column
sql/02_functions.sql        6 functions
sql/03_procedures.sql       11 procedures (sp_validate_booking first)
sql/04_triggers.sql         10 triggers
sql/05_views.sql            9 views
sql/06_events.sql           3 events
sql/07_roles.sql            3 roles, 3 demo users, GRANT/REVOKE
sql/08_seed.sql             GENERATED seed data (dates relative to the load date)
sql/09_queries.sql          Q01-Q44, each with a header block
sql/10_demo_transactions.sql  T1 SAVEPOINT (runnable); T2 race, T3 isolation, T4 deadlock (two terminals)
sql/11_demo_indexing.sql    X1 EXPLAIN / EXPLAIN ANALYZE
sql/12_demo_lab_extras.sql  L1 DDL, L2 view operations, L3 DCL
sql/13_walkthrough.sql      book -> check in -> return with missing pieces -> pay -> restock
sql/oracle_plsql/           Additional Experiment 2: the same programs in Oracle PL/SQL (executed)
scripts/build_db.py         runs 00 -> 08 (options --db, --skip-seed, --with-demos)
scripts/generate_seed.py    writes sql/08_seed.sql (fixed random seed)
scripts/capture_evidence.py runs everything on a fresh database, writes docs/query_results.md etc.
tests/                      pytest suite (builds its own throw-away database)
docs/                       report, ER diagram, normalization, business rules, data dictionary,
                            lab record, query results, viva questions
```

## Prerequisites

* **MySQL Community Server 8.0.31 or later** (needed for `INTERSECT` / `EXCEPT`), either installed
  locally or through **Docker Desktop**. Tested on MySQL 8.0.46.
* **Python 3.11+** (tested on 3.13).
* Optional: MySQL Workbench 8.0.

## Setup

### Option A — MySQL in Docker (recommended)

```bash
cp .env.example .env            # edit DB_PASSWORD if you like; keep DEMO_USER_HOST=%
docker compose up -d            # first start takes ~30 s
docker compose ps               # wait for "(healthy)"
```

The compose file starts `mysql:8.0` with `--event-scheduler=ON` and
`--log-bin-trust-function-creators=1`, a named volume `mysql_data`, port 3306 and the root password
from `DB_PASSWORD`.

### Option B — a MySQL server installed on your machine

1. Copy `.env.example` to `.env` and set `DB_USER` / `DB_PASSWORD` to an account that can create
   databases, users and roles (root is simplest), and set `DEMO_USER_HOST=localhost`.
2. Once, as root, in the `mysql` shell or Workbench:

   ```sql
   SET GLOBAL log_bin_trust_function_creators = 1;   -- avoids ERROR 1418/1419 when creating functions/triggers
   SET GLOBAL event_scheduler = ON;                  -- events do nothing while it is OFF
   ```

   (`SET GLOBAL` lasts until the server restarts; add `log_bin_trust_function_creators=1` and
   `event_scheduler=ON` under `[mysqld]` in `my.ini` / `my.cnf` to make it permanent.)

### Python

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## Build

```bash
python scripts/build_db.py                   # 00 -> 08: the boardgame_cafe database with seed data
python scripts/build_db.py --with-demos      # ... then also runs 09 -> 13
python scripts/build_db.py --skip-seed       # empty tables
python scripts/build_db.py --db boardgame_cafe_try   # build a second copy under another name
```

Expected output ends with `Build finished: 745 statements, 0 errors, 0 unexplained warnings`.
The build is idempotent: `00_drop_all.sql` removes the database, roles and demo users first, so
running it again always produces the same database. The seed file uses dates relative to the day
it is loaded (`CURRENT_DATE - INTERVAL 37 DAY` …), so **rebuild on the morning of your viva** — the
data is then "fresh" (future reservations are in the next 14 days, one rental is overdue, one game
is out on loan).

To regenerate the seed file (it is already committed): `python scripts/generate_seed.py`.

### Building in MySQL Workbench or the mysql shell instead

Open and run the files **in order** `00` → `08` (File → Open SQL Script, then the lightning-bolt
"Execute" button). They contain `DELIMITER $$ … DELIMITER ;` exactly as Workbench and the `mysql`
shell expect. From a terminal:

```bash
mysql -u root -p < sql/00_drop_all.sql
mysql -u root -p < sql/01_schema.sql
# ... 02 to 08 the same way
```

Files 10 and 12 contain **intentional** errors (a payment that is too large, a CHECK OPTION
violation, privilege denials). Run them with `mysql --force …`, or in Workbench switch off
Query → *Stop Script Execution on Errors*.

When you run `07_roles.sql` by hand the demo users are created as `'desk_priya'@'localhost'` etc.
with the demo password `ChangeMe#2026`. The build script instead uses `DEMO_USER_HOST` and
`DEMO_USER_PASSWORD` from `.env` (through Docker the server sees your connection as coming from
`172.x.x.x`, not `localhost`, so the Docker setup uses `%`).

## Demo script for the viva (about 10 minutes)

1. **Build** (1 min): `python scripts/build_db.py` — 745 statements, 0 errors. Show the counts:
   `SELECT COUNT(*) FROM Rentals_Reservations;` (347).
2. **A rule refusing bad data** (1 min) — party of 6 at a 4-seat table:

   ```sql
   USE boardgame_cafe;
   CALL sp_create_reservation(3, 'Dine_In', 1, NULL, 6,
        TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '18:00:00'),
        TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '20:00:00'), @b);
   -- ERROR 1644 (45000): BR-01: party size exceeds table seating capacity
   ```

   Also try the Suspended member 19 (→ `BR-13`) and a 14-year-old (member 14) with
   Cards Against Humanity (→ `BR-03`). See `docs/business_rules.md` for one example per rule.
3. **Walkthrough** (2 min): `SOURCE sql/13_walkthrough.sql;` (or open it in Workbench) — it finds a
   free table and a game, books, checks in, returns the box with 2 pieces missing, takes payment and
   restocks. Point out the damage fee, the copy going `Missing_Pieces` → `Available`, and the
   three audit rows. Outside 10:00–21:00 it automatically uses a Take_Home rental.
4. **Overdue and missing pieces** (1 min): `SELECT * FROM vw_overdue_rentals;` and
   `SELECT * FROM vw_copies_needing_attention;`
5. **T2 race in two terminals** (3 min): open two `mysql` sessions on `boardgame_cafe`, then paste
   the steps of T2 from `sql/10_demo_transactions.sql` in the order `[AB0]` (both), `[A1]`, `[B1]`
   (Session B **hangs**), `[A2]` (A commits → B immediately fails with `BR-05`), `[B2]`.
   Explain the `FOR UPDATE` lock at READ COMMITTED.
6. **EXPLAIN** (2 min): run `sql/11_demo_indexing.sql` — `ref` on `idx_customer_name`, `ALL` when the
   index is ignored or hidden by `DATE()`, `range` on `idx_rr_start`, and the `EXPLAIN ANALYZE` of
   the overlap check using `idx_rr_table_window`.

## Tests

```bash
pytest -q
```

The suite builds a fresh database called `boardgame_cafe_test_<random>` (roles and users get the
same suffix, so your real `boardgame_cafe`, `desk_priya`, … are never touched), runs 129 tests and
drops everything afterwards. Last run: **129 passed** in about 16 s.

| File | What it covers |
| --- | --- |
| `tests/test_business_rules.py` | TC-01 … TC-30, TC-32 (runs last), TC-33, TC-34, plus extra cases (inactive table, retired/repair copies, frozen rows, check-in rules, take-home late fee, PAY-01, view INSERT, cursor procedure) |
| `tests/test_concurrency.py` | TC-31 four desks racing for one slot, T2 race, T3 isolation levels, TC-35/T4 deadlock — each on real parallel connections |
| `tests/test_queries.py` | Every Q01–Q44, T1, X1, L1–L3 and the walkthrough runs; spot checks (Q08 empty, Q20 fixture member, Q22, Q23, Q43, X1 index keys, events enabled) |
| `tests/test_schema.py` | Object and constraint counts, names, comments on every column, no FLOAT, no stored balance, no `FULL JOIN` / `TOP` |
| `tests/test_security.py` | TC-36: `report_bot` and `desk_priya` denied (ERROR 1142), `desk_priya` can CALL procedures |

### Evidence for the report

```bash
python scripts/capture_evidence.py
```

builds `boardgame_cafe_evidence`, runs every query and demo (T2–T4 on two real connections), writes
`docs/query_results.md` and `docs/data_dictionary.md`, refreshes the output blocks in
`docs/lab_record.md` and `docs/report.md`, then drops the evidence database.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `ERROR 1418` / `ERROR 1419` (… *you might want to use the less safe log_bin_trust_function_creators variable*) when creating functions or triggers | Binary logging is on by default in MySQL 8.0. As root: `SET GLOBAL log_bin_trust_function_creators = 1;` (the Docker setup already does this). |
| Overdue / no-show statuses never change | The event scheduler is off: `SHOW VARIABLES LIKE 'event_scheduler';` → `SET GLOBAL event_scheduler = ON;` |
| `ERROR 1055 … incompatible with sql_mode=only_full_group_by` in your own queries | Every non-aggregated column in the SELECT list must be in `GROUP BY` (or functionally dependent on its key). Do **not** turn the mode off — all project queries comply with the default `sql_mode`. |
| Workbench reports a syntax error near `END` / `$$` | Run the whole file (lightning bolt), not a single statement, so the `DELIMITER $$` lines are processed; or paste the block including the `DELIMITER` lines. |
| `docker compose up` fails: *port 3306 is already allocated* | A local MySQL already uses 3306. Stop it, or set `DB_PORT=3307` in `.env` (the compose file maps `${DB_PORT}:3306`). |
| `Cannot reach MySQL at 127.0.0.1:3306` from the Python scripts | Start the server (`docker compose up -d` and wait for healthy) and check `DB_HOST`/`DB_PORT`. |
| `Access denied for user 'desk_priya'@'172.…'` | Through Docker the demo users must be created with `DEMO_USER_HOST=%` in `.env`; rebuild. |
| SSL errors from PyMySQL | The scripts use TLS by default (it lets MySQL 8's `caching_sha2_password` work without extra packages). If your server has TLS disabled, set `DB_SSL=0` in `.env` and `pip install cryptography`. |
| `BR-13: outstanding balance above Rs 500` when demoing with a seeded member | Members 13 (owes ₹972) and 19 (Suspended) are refused on purpose; use another member, or rebuild. |
