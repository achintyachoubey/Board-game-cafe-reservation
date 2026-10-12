#!/usr/bin/env python3
"""Run every query and demo against a freshly built database and record the real output.

    python scripts/capture_evidence.py            # build boardgame_cafe_evidence, capture, drop it
    python scripts/capture_evidence.py --keep     # keep the evidence database afterwards

Writes
  docs/query_results.md   every item: header, SQL, row count, first 10 rows
  docs/lab_record.md      fills the <!-- BEGIN OUTPUT key --> ... <!-- END OUTPUT key -->
                          blocks with the captured output (the prose around them is hand-written)
  docs/data_dictionary.md generated from information_schema

Single-session items (Q01-Q44, T1, X1, L1-L3, the walkthrough and a few lab
evidence snippets) run on one admin connection; `-- @as user` lines run on a
real connection for that demo user. The two-session demos T2-T4 are parsed
from the /* @two-session ... */ blocks in sql/10_demo_transactions.sql and run
on two connections by run_two_session(), which tests/test_concurrency.py uses too.
"""
from __future__ import annotations

import argparse
import datetime as dt
import decimal
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_db import (  # noqa: E402
    DEFAULT_DB, ROOT, SQL_DIR, Config, Outcome, Runner, Statement, build, connect, execute,
    load_config, render_sql, split_sql,
)

DOCS = ROOT / "docs"
EVIDENCE_DB = "boardgame_cafe_evidence"
MAX_ROWS = 10
STEP_WAIT = 2.0       # seconds before a two-session step is reported as "waiting"

GROUPS = [
    ("A", "Retrieval", 1, 4), ("B", "Joins", 5, 9), ("C", "Aggregation", 10, 14),
    ("D", "Subqueries", 15, 20), ("E", "Set operations", 21, 23),
    ("F", "Window functions", 24, 28), ("G", "CTEs incl. recursive", 29, 30),
    ("H", "Business-rule queries", 31, 36), ("I", "DML", 37, 40), ("J", "Lab extras", 41, 44),
]

# Extra evidence for the lab record (Exp 1, 3, 12, Additional 1). Runs after the demos.
LAB_EVIDENCE_SQL = """
-- =====================================================================
-- E1 · Schema object counts (Exp 1-3)
-- =====================================================================
SELECT (SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE') AS tables_,
       (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = DATABASE()) AS views_,
       (SELECT COUNT(*) FROM information_schema.routines
         WHERE routine_schema = DATABASE() AND routine_type = 'FUNCTION') AS functions_,
       (SELECT COUNT(*) FROM information_schema.routines
         WHERE routine_schema = DATABASE() AND routine_type = 'PROCEDURE') AS procedures_,
       (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = DATABASE()) AS triggers_,
       (SELECT COUNT(*) FROM information_schema.events WHERE event_schema = DATABASE()) AS events_;
SELECT constraint_type, COUNT(*) AS how_many
  FROM information_schema.table_constraints
 WHERE table_schema = DATABASE()
 GROUP BY constraint_type ORDER BY constraint_type;
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
-- =====================================================================
-- E2 · Constraints at work: CHECK, UNIQUE, FOREIGN KEY, NOT NULL, DEFAULT (Exp 3)
-- =====================================================================
-- @expect-error 3819
INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id, membership_expiry)
VALUES ('Test', 'Member', 'not-an-email', '9000000001', '2000-01-01', 1, CURRENT_DATE + INTERVAL 1 YEAR);
-- @expect-error 1062
INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id, membership_expiry)
SELECT 'Test', 'Member', email, '9000000002', '2000-01-01', 1, CURRENT_DATE + INTERVAL 1 YEAR
  FROM Customers WHERE customer_id = 1;
-- @expect-error 1452
INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id, membership_expiry)
VALUES ('Test', 'Member', 'test.member@mail.test', '9000000003', '2000-01-01', 9, CURRENT_DATE + INTERVAL 1 YEAR);
-- @expect-error 1048
INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth, tier_id, membership_expiry)
VALUES ('Test', NULL, 'test.member@mail.test', '9000000004', '2000-01-01', 1, CURRENT_DATE + INTERVAL 1 YEAR);
-- @expect-error 1451
DELETE FROM Membership_Tiers WHERE tier_id = 1;
SELECT column_name, column_default FROM information_schema.columns
 WHERE table_schema = DATABASE() AND table_name = 'Customers' AND column_default IS NOT NULL;
-- =====================================================================
-- E3 · A business rule refusing a booking (BR-01) and the error the client sees (Exp 12)
-- =====================================================================
SELECT table_id INTO @small FROM Cafe_Tables WHERE seating_capacity = 4 AND is_active
 ORDER BY table_id LIMIT 1;
-- @expect-error BR-01
CALL sp_create_reservation(3, 'Dine_In', @small, NULL, 6,
     TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '18:00:00'),
     TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '20:00:00'), @nope);
-- @expect-error BR-13
CALL sp_create_reservation(19, 'Dine_In', @small, NULL, 2,
     TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '18:00:00'),
     TIMESTAMP(CURRENT_DATE + INTERVAL 3 DAY, '20:00:00'), @nope);
-- @expect-error BR-15
UPDATE Rentals_Reservations SET status = 'Reserved' WHERE status = 'Completed' ORDER BY booking_id LIMIT 1;
-- @expect-error BR-20
DELETE FROM Rentals_Reservations WHERE status = 'Completed' ORDER BY booking_id LIMIT 1;
-- =====================================================================
-- E4 · The six functions called directly (Additional Exp 1)
-- =====================================================================
SELECT fn_customer_age(14, CURRENT_DATE) AS age_member_14,
       fn_customer_balance(13) AS balance_member_13,
       fn_table_is_free(1, TIMESTAMP(CURRENT_DATE + INTERVAL 20 DAY, '18:00:00'),
                           TIMESTAMP(CURRENT_DATE + INTERVAL 20 DAY, '20:00:00'), NULL) AS table1_free_in_20_days,
       fn_copy_is_free(2, NOW(), NOW() + INTERVAL 1 HOUR, NULL) AS copy2_free_now,
       fn_calculate_base_charge('Dine_In', 1, 1, TIMESTAMP(CURRENT_DATE, '18:00:00'),
                                TIMESTAMP(CURRENT_DATE, '20:00:00')) AS two_hours_mh01_catan,
       fn_calculate_base_charge('Take_Home', NULL, 1, TIMESTAMP(CURRENT_DATE, '12:00:00'),
                                TIMESTAMP(CURRENT_DATE + INTERVAL 2 DAY, '12:00:00')) AS two_days_catan;
SELECT booking_id, booking_type, reserved_end,
       fn_calculate_late_fee(booking_id, reserved_end + INTERVAL 10 MINUTE) AS late_10_min,
       fn_calculate_late_fee(booking_id, reserved_end + INTERVAL 40 MINUTE) AS late_40_min,
       fn_calculate_late_fee(booking_id, reserved_end + INTERVAL 75 MINUTE) AS late_75_min
  FROM Rentals_Reservations WHERE status = 'Reserved' ORDER BY booking_type, booking_id LIMIT 3;
-- =====================================================================
-- E5 · The cursor procedure: statuses before and after sp_flag_suspensions (Additional Exp 1)
-- =====================================================================
SELECT customer_id, customer, status, balance FROM vw_customer_balances
 WHERE status <> 'Active' OR balance > 500 ORDER BY customer_id;
CALL sp_flag_suspensions();
SELECT customer_id, customer, status, balance FROM vw_customer_balances
 WHERE status <> 'Active' OR balance > 500 ORDER BY customer_id;
-- =====================================================================
-- E6 · Triggers, events and roles that exist (Exp 10, 12)
-- =====================================================================
SELECT trigger_name, action_timing, event_manipulation, event_object_table
  FROM information_schema.triggers WHERE trigger_schema = DATABASE()
 ORDER BY event_object_table, action_timing, event_manipulation;
SELECT event_name, status, interval_value, interval_field
  FROM information_schema.events WHERE event_schema = DATABASE() ORDER BY event_name;
SHOW GRANTS FOR 'front_desk';
SHOW GRANTS FOR 'analyst';
"""


# --------------------------------------------------------------------------- items
@dataclass
class Item:
    key: str
    title: str
    source: str
    concept: str = ""
    algebra: str = ""
    stmts: list[Statement] = field(default_factory=list)          # original text (for display)
    rendered: list[Statement] = field(default_factory=list)       # what actually runs
    outcomes: list[Outcome] = field(default_factory=list)


HEADER_RE = re.compile(r"^--\s*([QTXLE]\d+|WALK)\s*·\s*(.+)$", re.MULTILINE)


def parse_items(text: str, source: str, db: str, cfg: Config, default_key: str | None = None,
                default_title: str = "") -> list[Item]:
    """Group a file's statements under the header comment (Q01 · ..., T1 · ...) that precedes them."""
    original = split_sql(text)
    rendered = split_sql(render_sql(text, db, cfg))
    assert len(original) == len(rendered), f"{source}: rendering changed the statement count"
    items: list[Item] = []
    current: Item | None = Item(default_key, default_title, source) if default_key else None
    if current:
        items.append(current)
    for o, r in zip(original, rendered):
        m = HEADER_RE.search(o.preamble)
        if m:
            current = Item(m.group(1), m.group(2).strip(), source)
            cm = re.search(r"Concept:\s*(.+)", o.preamble)
            am = re.search(r"Relational algebra:\s*(.+)", o.preamble)
            current.concept = cm.group(1).strip() if cm else ""
            current.algebra = am.group(1).strip() if am else ""
            items.append(current)
        if current is None or o.sql.upper().startswith("USE "):
            continue
        current.stmts.append(o)
        current.rendered.append(r)
    return [i for i in items if i.stmts]


def run_items(runner: Runner, items: list[Item]) -> None:
    for item in items:
        for r in item.rendered:
            item.outcomes.append(execute(runner.conn_for(r), r))


# --------------------------------------------------------------------------- two sessions
@dataclass
class Step:
    label: str          # e.g. A1, B2, AB0
    who: str            # A, B or AB
    title: str
    text: str           # original SQL of the step
    expect: list[str]


@dataclass
class StepResult:
    label: str
    session: str
    title: str
    outcomes: list[Outcome]
    waited: bool        # still running STEP_WAIT seconds after it was sent
    seconds: float
    expect: list[str]


TWO_SESSION_RE = re.compile(r"/\*\s*@two-session\s+(T\d+)(.*?)\*/", re.DOTALL)
STEP_RE = re.compile(r"^-- \[(AB|A|B)(\d+)\]\s*(.*)$", re.MULTILINE)


def parse_two_session(text: str) -> dict[str, tuple[str, list[Step]]]:
    """{'T2': (title, [Step, ...]), ...} from the /* @two-session Tn ... */ blocks."""
    blocks = {}
    for m in TWO_SESSION_RE.finditer(text):
        key, body = m.group(1), m.group(2)
        title_m = re.search(rf"{key}\s*·\s*(.+)", body)
        title = title_m.group(1).strip() if title_m else key
        marks = list(STEP_RE.finditer(body))
        steps = []
        for i, sm in enumerate(marks):
            end = marks[i + 1].start() if i + 1 < len(marks) else len(body)
            chunk = body[sm.end():end]
            expect = [ln.split("expect:", 1)[1].strip() for ln in chunk.splitlines()
                      if ln.strip().startswith("-- expect:")]
            # continuation lines of an expect comment
            steps.append(Step(sm.group(1) + sm.group(2), sm.group(1), sm.group(3).strip(),
                              chunk.strip(), expect))
        blocks[key] = (title, steps)
    return blocks


def _run_step(conn, stmts: list[Statement]) -> tuple[list[Outcome], float]:
    t0 = time.perf_counter()
    outs = [execute(conn, s) for s in stmts]
    return outs, time.perf_counter() - t0


def run_two_session(cfg: Config, db: str, key: str) -> tuple[str, list[StepResult]]:
    """Run one two-session demo from sql/10_demo_transactions.sql on two real connections."""
    text = (SQL_DIR / "10_demo_transactions.sql").read_text(encoding="utf-8")
    title, steps = parse_two_session(text)[key]
    conns = {s: connect(cfg, database=db) for s in "AB"}
    pools = {s: ThreadPoolExecutor(max_workers=1, thread_name_prefix=f"session{s}") for s in "AB"}
    results: list[StepResult] = []
    pending: list[tuple[StepResult, object]] = []
    try:
        for step in steps:
            stmts = split_sql(render_sql(step.text, db, cfg))
            for sess in (["A", "B"] if step.who == "AB" else [step.who]):
                res = StepResult(step.label, sess, step.title, [], False, 0.0, step.expect)
                fut = pools[sess].submit(_run_step, conns[sess], stmts)
                results.append(res)
                try:
                    res.outcomes, res.seconds = fut.result(timeout=STEP_WAIT)
                except FutureTimeout:
                    res.waited = True
                    pending.append((res, fut))
                # a step that was waiting may have finished because of this one
                time.sleep(0.3)
                for p_res, p_fut in list(pending):
                    if p_fut.done():
                        p_res.outcomes, p_res.seconds = p_fut.result()
                        pending.remove((p_res, p_fut))
        for p_res, p_fut in pending:
            p_res.outcomes, p_res.seconds = p_fut.result(timeout=120)
    finally:
        for p in pools.values():
            p.shutdown(wait=True)
        for c in conns.values():
            c.close()
    return title, results


# --------------------------------------------------------------------------- markdown
def fmt(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, (bytes, bytearray)):
        v = v.decode("utf-8", "replace")
    if isinstance(v, dt.datetime):
        return v.strftime("%Y-%m-%d %H:%M:%S") + (f".{v.microsecond // 1000:03d}" if v.microsecond else "")
    if isinstance(v, (dt.date, dt.timedelta)):
        return str(v)
    if isinstance(v, decimal.Decimal):
        return str(v)
    return str(v)


def md_table(columns: list[str], rows: list[tuple]) -> str:
    if len(columns) == 1 and any("\n" in fmt(r[0]) for r in rows):   # EXPLAIN ANALYZE / SHOW CREATE
        return "\n".join("```text\n" + fmt(r[0]) + "\n```" for r in rows)
    esc = lambda s: fmt(s).replace("|", "\\|").replace("\n", " ")  # noqa: E731
    head = "| " + " | ".join(esc(c) for c in columns) + " |"
    sep = "|" + "|".join("---" for _ in columns) + "|"
    body = ["| " + " | ".join(esc(v) for v in r) + " |" for r in rows]
    return "\n".join([head, sep, *body])


def display_sql(stmt: Statement) -> str:
    """The statement as written in the repo, minus the item's ===== header block and directives."""
    keep, in_header = [], False
    for ln in stmt.preamble.splitlines():
        s = ln.strip()
        if s.startswith("-- ====="):
            in_header = not in_header
            continue
        if in_header or "@as " in s or "@expect-error" in s:
            continue
        keep.append(ln)
    sql = stmt.sql + ";"
    if stmt.trailing:
        sql += "  " + stmt.trailing
    return "\n".join(keep + [sql]).strip()


def outcome_md(o: Outcome, max_rows: int = MAX_ROWS) -> str:
    parts = []
    if o.error_code:
        tag = "expected error" if o.met_expectation else "UNEXPECTED ERROR"
        parts.append(f"**{tag}:** `ERROR {o.error_code}: {o.error_msg}`")
    elif not o.result_sets:
        if re.match(r"(?is)^\s*(select\b.*\binto\s+@|set\b)", o.stmt.sql):
            parts.append("_(value stored in a session variable)_")
        else:
            parts.append(f"_OK - rows affected: {o.rowcount if o.rowcount is not None else 0}_")
    for rs in o.result_sets:
        n = len(rs.rows)
        shown = f" (first {max_rows} shown)" if n > max_rows else ""
        parts.append(f"**{n} row{'s' if n != 1 else ''}**{shown}\n\n" + md_table(rs.columns, rs.rows[:max_rows]))
    return "\n\n".join(parts)


def item_md(item: Item, level: str = "###") -> str:
    out = [f"{level} {item.key} · {item.title}"]
    meta = []
    if item.concept:
        meta.append(f"*Concept:* {item.concept}")
    if item.algebra:
        meta.append(f"*Relational algebra:* {item.algebra}")
    if meta:
        out.append("  \n".join(meta))
    if len(item.stmts) == 1:
        out.append("```sql\n" + display_sql(item.stmts[0]) + "\n```")
        out.append(outcome_md(item.outcomes[0]))
    else:
        for s, o in zip(item.stmts, item.outcomes):
            out.append("```sql\n" + display_sql(s) + "\n```")
            out.append(outcome_md(o))
    return "\n\n".join(out)


def two_session_md(key: str, title: str, results: list[StepResult]) -> str:
    out = [f"### {key} · {title}", "Run on two real connections (Session A, Session B). "
           "Each step was sent in the order shown; a step still running "
           f"{STEP_WAIT:.0f} s later is reported as **waited**."]
    for r in results:
        lines = [f"**[{r.label}] Session {r.session}** - {r.title}"
                 + (f" - **waited {r.seconds:.1f} s** (blocked by a lock)" if r.waited else "")]
        for o in r.outcomes:
            sql = o.stmt.sql if len(o.stmt.sql) < 400 else o.stmt.sql[:400] + " ..."
            res = outcome_md(o, max_rows=5)
            lines.append("```sql\n" + sql + ";\n```\n" + res)
        if r.expect:
            lines.append("*Expected:* " + " ".join(r.expect))
        out.append("\n\n".join(lines))
    return "\n\n".join(out)


def two_session_summary(key: str, results: list[StepResult]) -> str:
    errs = [(r.label, r.session, o.error_code, o.error_msg) for r in results for o in r.outcomes
            if o.error_code]
    waited = [f"[{r.label}] {r.session} waited {r.seconds:.1f} s" for r in results if r.waited]
    if key == "T2":
        e = next((x for x in errs if "BR-05" in (x[3] or "")), None)
        return (f"Observed: {'; '.join(waited) or 'no step waited'}; "
                f"{'Session ' + e[1] + ' then failed with ERROR ' + str(e[2]) + ': ' + e[3] if e else 'no BR-05 error'}.")
    if key == "T3":
        reads = {}
        for r in results:
            for o in r.outcomes:
                for rs in o.result_sets:
                    if rs.rows and rs.columns[0].endswith(("_read", "after_commit")):
                        reads[rs.columns[0]] = fmt(rs.rows[0][0])
        return ("Observed: READ COMMITTED read " + reads.get("rc_first_read", "?") + " then "
                + reads.get("rc_second_read", "?") + " in the same transaction (non-repeatable read); "
                "REPEATABLE READ read " + reads.get("rr_first_read", "?") + " then "
                + reads.get("rr_second_read", "?") + " (snapshot), and "
                + reads.get("after_commit", "?") + " after COMMIT.")
    if key == "T4":
        dl = [x for x in errs if x[2] == 1213]
        return (f"Observed: {'; '.join(waited) or 'no step waited'}; "
                + (f"Session {dl[0][1]} got ERROR 1213 at step [{dl[0][0]}] and was rolled back; "
                   f"the other session committed." if len(dl) == 1 else f"{len(dl)} deadlock errors."))
    return ""


# --------------------------------------------------------------------------- data dictionary
def data_dictionary(cfg: Config, db: str) -> str:
    conn = connect(cfg, database=db)
    out = ["# Data dictionary",
           "",
           f"Generated by `scripts/capture_evidence.py` from `information_schema` of a fresh build "
           f"(MySQL {server_version(conn)}). Comments come from the `COMMENT` clauses in "
           "`sql/01_schema.sql`. Do not edit by hand.",
           ""]
    with conn.cursor() as cur:
        cur.execute("""SELECT table_name, table_comment FROM information_schema.tables
                        WHERE table_schema = %s AND table_type = 'BASE TABLE'
                        ORDER BY create_time, table_name""", (db,))
        tables = cur.fetchall()
        order = [
            "Membership_Tiers", "Customers", "Staff", "Game_Categories", "Board_Games",
            "Board_Game_Categories", "Game_Copies", "Game_Components", "Cafe_Tables",
            "Rentals_Reservations", "Return_Inspections", "Missing_Pieces", "Payments",
            "Booking_Audit_Log"]
        tables = sorted(tables, key=lambda t: order.index(t[0]) if t[0] in order else 99)
        out.append("| # | Table | Purpose |")
        out.append("|---|---|---|")
        for i, (t, c) in enumerate(tables, start=1):
            out.append(f"| {i} | [`{t}`](#{t.lower()}) | {c} |")
        out.append("")
        for t, comment in tables:
            out += [f"## {t}", "", comment, "",
                    "| Column | Type | Null | Key | Default | Extra | Comment |",
                    "|---|---|---|---|---|---|---|"]
            cur.execute("""SELECT column_name, column_type, is_nullable, column_key, column_default,
                                  extra, column_comment, generation_expression
                             FROM information_schema.columns
                            WHERE table_schema = %s AND table_name = %s
                            ORDER BY ordinal_position""", (db, t))
            for name, ctype, null, key, default, extra, ccomment, gen in cur.fetchall():
                ex = extra or ""
                if gen:
                    ex = f"{ex} AS ({gen})".strip()
                cells = [f"`{name}`", ctype, null, key, fmt(default) if default is not None else "",
                         ex, ccomment]
                out.append("| " + " | ".join(str(c).replace("|", "\\|") for c in cells) + " |")
            cur.execute("""SELECT tc.constraint_name, tc.constraint_type,
                                  GROUP_CONCAT(k.column_name ORDER BY k.ordinal_position),
                                  MAX(k.referenced_table_name),
                                  GROUP_CONCAT(k.referenced_column_name ORDER BY k.ordinal_position),
                                  MAX(rc.delete_rule), MAX(cc.check_clause)
                             FROM information_schema.table_constraints tc
                             LEFT JOIN information_schema.key_column_usage k
                                    ON k.constraint_schema = tc.constraint_schema
                                   AND k.constraint_name = tc.constraint_name
                                   AND k.table_name = tc.table_name
                             LEFT JOIN information_schema.referential_constraints rc
                                    ON rc.constraint_schema = tc.constraint_schema
                                   AND rc.constraint_name = tc.constraint_name
                             LEFT JOIN information_schema.check_constraints cc
                                    ON cc.constraint_schema = tc.constraint_schema
                                   AND cc.constraint_name = tc.constraint_name
                            WHERE tc.table_schema = %s AND tc.table_name = %s
                            GROUP BY tc.constraint_name, tc.constraint_type
                            ORDER BY FIELD(tc.constraint_type, 'PRIMARY KEY', 'UNIQUE',
                                           'FOREIGN KEY', 'CHECK'), tc.constraint_name""", (db, t))
            rows = cur.fetchall()
            out += ["", "**Constraints**", "", "| Name | Type | Definition |", "|---|---|---|"]
            for name, ctype, cols, rtab, rcols, rule, check in rows:
                if ctype == "FOREIGN KEY":
                    d = f"({cols}) → {rtab}({rcols}) ON DELETE {rule}"
                elif ctype == "CHECK":
                    d = (check or "").replace("|", "\\|")
                else:
                    d = f"({cols})"
                out.append(f"| `{name}` | {ctype} | {d} |")
            cur.execute("""SELECT index_name, non_unique, GROUP_CONCAT(column_name ORDER BY seq_in_index),
                                  MAX(index_type)
                             FROM information_schema.statistics
                            WHERE table_schema = %s AND table_name = %s
                            GROUP BY index_name, non_unique
                            ORDER BY index_name = 'PRIMARY' DESC, index_name""", (db, t))
            out += ["", "**Indexes** (all B+ trees; PRIMARY is the clustered index)", "",
                    "| Index | Unique | Columns |", "|---|---|---|"]
            for name, non_unique, cols, itype in cur.fetchall():
                out.append(f"| `{name}` | {'no' if non_unique else 'yes'} | {cols} |")
            out.append("")
        # views / routines / triggers / events
        cur.execute("""SELECT table_name, is_updatable, check_option FROM information_schema.views
                        WHERE table_schema = %s ORDER BY table_name""", (db,))
        out += ["## Views", "", "| View | Updatable | Check option |", "|---|---|---|"]
        out += [f"| `{v}` | {u} | {c} |" for v, u, c in cur.fetchall()]
        cur.execute("""SELECT routine_type, routine_name, data_type, sql_data_access, security_type
                         FROM information_schema.routines WHERE routine_schema = %s
                        ORDER BY routine_type, routine_name""", (db,))
        out += ["", "## Stored functions and procedures", "",
                "| Type | Name | Returns | Data access | Security |", "|---|---|---|---|---|"]
        out += [f"| {a} | `{b}` | {c or ''} | {d} | {e} |" for a, b, c, d, e in cur.fetchall()]
        cur.execute("""SELECT trigger_name, action_timing, event_manipulation, event_object_table
                         FROM information_schema.triggers WHERE trigger_schema = %s
                        ORDER BY event_object_table, action_timing, event_manipulation""", (db,))
        out += ["", "## Triggers", "", "| Trigger | Timing | Event | Table |", "|---|---|---|---|"]
        out += [f"| `{a}` | {b} | {c} | `{d}` |" for a, b, c, d in cur.fetchall()]
        cur.execute("""SELECT event_name, CONCAT('EVERY ', interval_value, ' ', interval_field), status
                         FROM information_schema.events WHERE event_schema = %s ORDER BY event_name""", (db,))
        out += ["", "## Events", "", "| Event | Schedule | Status |", "|---|---|---|"]
        out += [f"| `{a}` | {b} | {c} |" for a, b, c in cur.fetchall()]
    conn.close()
    return "\n".join(out) + "\n"


def server_version(conn) -> str:
    with conn.cursor() as cur:
        cur.execute("SELECT VERSION()")
        return cur.fetchone()[0]


# --------------------------------------------------------------------------- lab record fill
def fill_markers(path: Path, blocks: dict[str, str]) -> list[str]:
    """Replace <!-- BEGIN OUTPUT key --> ... <!-- END OUTPUT key --> with captured output."""
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    missing = []

    def repl(m: re.Match) -> str:
        key = m.group(1)
        if key not in blocks:
            missing.append(key)
            return m.group(0)
        return f"<!-- BEGIN OUTPUT {key} -->\n{blocks[key].strip()}\n<!-- END OUTPUT {key} -->"

    text = re.sub(r"<!-- BEGIN OUTPUT (\S+) -->.*?<!-- END OUTPUT \1 -->", repl, text, flags=re.DOTALL)
    path.write_text(text, encoding="utf-8")
    return missing


# --------------------------------------------------------------------------- main
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default=EVIDENCE_DB, help=f"throw-away database name (default {EVIDENCE_DB})")
    ap.add_argument("--keep", action="store_true", help="keep the evidence database afterwards")
    args = ap.parse_args(argv)
    cfg = load_config()
    db = args.db
    if db == DEFAULT_DB:
        raise SystemExit("Refusing to capture into the real boardgame_cafe database; use another --db.")
    print(f"Building {db} ...")
    summary = build(cfg, db, quiet=True)
    print(f"  {summary['statements']} statements, 0 errors")

    runner = Runner(cfg, db)
    runner.admin.select_db(db)      # the files' own USE lines are not part of any item
    all_items: list[Item] = []
    try:
        for fname, dkey, dtitle in [
            ("09_queries.sql", None, ""), ("10_demo_transactions.sql", None, ""),
            ("11_demo_indexing.sql", None, ""), ("12_demo_lab_extras.sql", None, ""),
            ("13_walkthrough.sql", "WALK", "End-to-end walkthrough: book, check in, return "
                                           "with missing pieces, pay, restock")]:
            text = (SQL_DIR / fname).read_text(encoding="utf-8")
            if fname == "13_walkthrough.sql":
                text = re.sub(r"\A(--.*\n)+", "", text)   # file header is not part of the item
            items = parse_items(text, fname, db, cfg, dkey, dtitle)
            run_items(runner, items)
            all_items += items
            bad = [(i.key, o.stmt.line, o.error_text) for i in items for o in i.outcomes
                   if not o.met_expectation]
            print(f"  ran {fname}: {sum(len(i.outcomes) for i in items)} statements, "
                  f"{len(bad)} unexpected results")
            for b in bad:
                print("    UNEXPECTED", b)
        evidence = parse_items(LAB_EVIDENCE_SQL, "scripts/capture_evidence.py", db, cfg)
        run_items(runner, evidence)
        bad = [(i.key, o.error_text) for i in evidence for o in i.outcomes if not o.met_expectation]
        print(f"  ran lab evidence: {sum(len(i.outcomes) for i in evidence)} statements, "
              f"{len(bad)} unexpected results")
        for b in bad:
            print("    UNEXPECTED", b)
        version = server_version(runner.admin)
        with runner.admin.cursor() as cur:
            cur.execute("SELECT NOW()")
            captured_at = fmt(cur.fetchone()[0])
    finally:
        runner.close()

    two = {}
    for key in ("T2", "T3", "T4"):
        title, results = run_two_session(cfg, db, key)
        two[key] = (title, results)
        print(f"  ran {key} on two connections: {two_session_summary(key, results)}")

    by_key = {i.key: i for i in all_items + evidence}
    unexpected = sum(1 for i in all_items + evidence for o in i.outcomes if not o.met_expectation)

    # ---- query_results.md
    md = ["# Query results",
          "",
          f"Generated by `scripts/capture_evidence.py` on **{captured_at}** (server time) against a "
          f"freshly built and seeded database `{db}` on MySQL **{version}**. Every statement below "
          "was executed; the tables are the real output (first "
          f"{MAX_ROWS} rows). Seed dates are relative to the load date, so dates differ from run "
          "to run while the shape of the results stays the same.",
          "",
          f"Statements executed: **{sum(len(i.outcomes) for i in all_items)}** in the query bank "
          f"and demos; unexpected errors: **{unexpected}**. Intentional errors (rule violations, "
          "privilege checks) are marked *expected error*.",
          "",
          "Items run in this order on one connection: Q01-Q44 (09), T1 (10), X1 (11), L1-L3 (12), "
          "walkthrough (13). Q37-Q40 change data, so later items see their effects.",
          "",
          "## Contents", ""]
    for g, name, lo, hi in GROUPS:
        md.append(f"- {g} · {name}: " + ", ".join(f"[Q{n:02d}](#q{n:02d})" for n in range(lo, hi + 1)))
    md.append("- Transactions: [T1](#t1), [T2](#t2), [T3](#t3), [T4](#t4) · Indexing: [X1](#x1) · "
              "Lab extras: [L1](#l1), [L2](#l2), [L3](#l3) · [Walkthrough](#walk)")
    md.append("")
    for g, name, lo, hi in GROUPS:
        md += [f"## {g} · {name}", ""]
        for n in range(lo, hi + 1):
            md += [f'<a id="q{n:02d}"></a>', "", item_md(by_key[f"Q{n:02d}"]), ""]
    md += ["## Transactions (Exp 11)", "", f'<a id="t1"></a>', "", item_md(by_key["T1"]), ""]
    for key in ("T2", "T3", "T4"):
        title, results = two[key]
        md += [f'<a id="{key.lower()}"></a>', "", two_session_md(key, title, results), "",
               f"> {two_session_summary(key, results)}", ""]
    md += ["## Indexing (CO5)", "", '<a id="x1"></a>', "", item_md(by_key["X1"]), ""]
    md += ["## Lab extras", ""]
    for key in ("L1", "L2", "L3"):
        md += [f'<a id="{key.lower()}"></a>', "", item_md(by_key[key]), ""]
    md += ["## End-to-end walkthrough", "", '<a id="walk"></a>', "", item_md(by_key["WALK"]), ""]
    (DOCS / "query_results.md").write_text("\n".join(md), encoding="utf-8")
    print("  wrote docs/query_results.md")

    # ---- lab record blocks
    blocks = {k: item_md(v, "####") for k, v in by_key.items()}
    for key, (title, results) in two.items():
        blocks[key] = two_session_md(key, title, results).replace("### ", "#### ", 1) + \
            f"\n\n> {two_session_summary(key, results)}"
    blocks["META"] = (f"Captured on {captured_at} (server time), MySQL {version}, fresh database "
                      f"`{db}` built from `sql/00`-`08`.")
    missing = fill_markers(DOCS / "lab_record.md", blocks)
    missing += fill_markers(DOCS / "report.md", blocks)
    print(f"  filled output blocks in docs/lab_record.md and docs/report.md"
          + (f" (unknown keys: {missing})" if missing else ""))

    # ---- data dictionary
    (DOCS / "data_dictionary.md").write_text(data_dictionary(cfg, db), encoding="utf-8")
    print("  wrote docs/data_dictionary.md")

    if not args.keep:
        drop = Runner(cfg, db)
        try:
            drop.run_file(SQL_DIR / "00_drop_all.sql")
        finally:
            drop.close()
        print(f"  dropped {db} and its roles/users")
    return 1 if unexpected else 0


if __name__ == "__main__":
    sys.exit(main())
