"""Schema shape: object and constraint counts (Section 8), names, comments, no FLOAT money."""
from __future__ import annotations

import re

from build_db import ROOT

TABLES = {"Membership_Tiers", "Customers", "Staff", "Game_Categories", "Board_Games",
          "Board_Game_Categories", "Game_Copies", "Game_Components", "Cafe_Tables",
          "Rentals_Reservations", "Return_Inspections", "Missing_Pieces", "Payments",
          "Booking_Audit_Log"}
VIEWS = {"vw_game_catalog", "vw_active_bookings", "vw_available_copies_now", "vw_overdue_rentals",
         "vw_customer_balances", "vw_game_popularity", "vw_table_utilization_30d",
         "vw_copies_needing_attention", "vw_active_members"}
FUNCTIONS = {"fn_customer_age", "fn_table_is_free", "fn_copy_is_free", "fn_calculate_base_charge",
             "fn_calculate_late_fee", "fn_customer_balance"}
PROCEDURES = {"sp_validate_booking", "sp_create_reservation", "sp_check_in", "sp_check_out",
              "sp_cancel_booking", "sp_mark_no_shows", "sp_find_free_tables", "sp_recommend_games",
              "sp_record_payment", "sp_restock_copy", "sp_flag_suspensions"}
TRIGGERS = {"trg_rr_before_insert", "trg_rr_before_update", "trg_rr_after_insert",
            "trg_rr_after_update", "trg_rr_before_delete", "trg_insp_before_insert",
            "trg_insp_after_insert", "trg_mp_before_insert", "trg_mp_after_insert",
            "trg_pay_before_insert"}
EVENTS = {"ev_mark_overdue", "ev_mark_no_shows", "ev_flag_suspensions"}


def names(db, sql):
    return {r[0] for r in db.rows(sql, (db.name,))}


def test_tables(db):
    assert names(db, "SELECT table_name FROM information_schema.tables WHERE table_schema = %s "
                     "AND table_type = 'BASE TABLE'") == TABLES


def test_views(db):
    assert names(db, "SELECT table_name FROM information_schema.views WHERE table_schema = %s") == VIEWS


def test_functions_and_procedures(db):
    assert names(db, "SELECT routine_name FROM information_schema.routines WHERE routine_schema = %s "
                     "AND routine_type = 'FUNCTION'") == FUNCTIONS
    assert names(db, "SELECT routine_name FROM information_schema.routines WHERE routine_schema = %s "
                     "AND routine_type = 'PROCEDURE'") == PROCEDURES


def test_triggers_cover_insert_update_delete(db):
    assert names(db, "SELECT trigger_name FROM information_schema.triggers WHERE trigger_schema = %s") \
        == TRIGGERS
    kinds = set(db.rows("SELECT action_timing, event_manipulation FROM information_schema.triggers "
                        "WHERE trigger_schema = %s", (db.name,)))
    assert kinds == {(t, e) for t in ("BEFORE", "AFTER") for e in ("INSERT", "UPDATE")} | {("BEFORE", "DELETE")}


def test_events(db):
    assert names(db, "SELECT event_name FROM information_schema.events WHERE event_schema = %s") == EVENTS


def test_roles(db):
    from build_db import suffix_for
    sfx = suffix_for(db.name)
    roles = {r[0] for r in db.rows("SELECT user FROM mysql.user WHERE user IN (%s, %s, %s) "
                                   "AND authentication_string = ''",
                                   tuple(f"{n}{sfx}" for n in ("cafe_admin", "front_desk", "analyst")))}
    assert len(roles) == 3


def test_constraint_counts(db):
    counts = dict(db.rows("SELECT constraint_type, COUNT(*) FROM information_schema.table_constraints "
                          "WHERE table_schema = %s GROUP BY constraint_type", (db.name,)))
    assert counts == {"PRIMARY KEY": 14, "FOREIGN KEY": 14, "CHECK": 21, "UNIQUE": 10}


def test_every_table_and_column_has_a_comment(db):
    assert db.rows("SELECT table_name FROM information_schema.tables WHERE table_schema = %s "
                   "AND table_type = 'BASE TABLE' AND table_comment = ''", (db.name,)) == []
    assert db.rows("SELECT table_name, column_name FROM information_schema.columns c "
                   "JOIN information_schema.tables t USING (table_schema, table_name) "
                   "WHERE c.table_schema = %s AND t.table_type = 'BASE TABLE' AND column_comment = ''",
                   (db.name,)) == []


def test_money_is_decimal_and_balance_is_not_stored(db):
    assert db.rows("SELECT table_name, column_name FROM information_schema.columns "
                   "WHERE table_schema = %s AND data_type IN ('float', 'double', 'real')", (db.name,)) == []
    assert db.rows("SELECT table_name, column_name FROM information_schema.columns c "
                   "JOIN information_schema.tables t USING (table_schema, table_name) "
                   "WHERE c.table_schema = %s AND t.table_type = 'BASE TABLE' AND column_name LIKE '%%balance%%'",
                   (db.name,)) == []


def test_generated_columns(db):
    gen = dict(db.rows("SELECT column_name, extra FROM information_schema.columns WHERE table_schema = %s "
                       "AND table_name = 'Rentals_Reservations' AND generation_expression <> ''", (db.name,)))
    assert set(gen) == {"duration_minutes", "total_amount"}


def _code_only(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r"--[^\n]*", "", text)
    return re.sub(r"'(?:[^'\\]|\\.|'')*'", "''", text)


def test_no_forbidden_syntax_in_sql_files():
    for path in sorted((ROOT / "sql").glob("*.sql")):
        code = _code_only(path.read_text(encoding="utf-8")).upper()
        assert not re.search(r"\bFULL\s+(OUTER\s+)?JOIN\b", code), path
        assert not re.search(r"\bSELECT\s+TOP\b", code), path
        assert not re.search(r"\b(FLOAT|DOUBLE|REAL)\b", code), path
