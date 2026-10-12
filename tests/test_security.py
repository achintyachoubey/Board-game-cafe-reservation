"""TC-36: least privilege for the demo users (test builds use suffixed users and roles)."""
from __future__ import annotations

import pymysql
import pytest


def _error(conn, sql):
    with pytest.raises(pymysql.err.MySQLError) as info:
        with conn.cursor() as cur:
            cur.execute(sql)
    return info.value.args


def test_tc36_report_bot_cannot_read_customers(db):
    conn = db.user_conn("report_bot")
    try:
        code, msg = _error(conn, f"SELECT COUNT(*) FROM {db.name}.Customers")
        assert code == 1142, msg
        with conn.cursor() as cur:                       # but the analyst views work
            cur.execute(f"SELECT COUNT(*) FROM {db.name}.vw_game_popularity")
            assert cur.fetchone()[0] == 25
    finally:
        conn.close()


def test_tc36_desk_cannot_write_payments_but_can_call_procedures(db):
    conn = db.user_conn("desk_priya")
    try:
        code, msg = _error(conn, f"INSERT INTO {db.name}.Payments (booking_id, amount, method) "
                                 f"VALUES (1, 1, 'UPI')")
        assert code == 1142, msg
        code, msg = _error(conn, f"UPDATE {db.name}.Rentals_Reservations SET late_fee = 0")
        assert code == 1142, msg
        with conn.cursor() as cur:
            cur.execute(f"CALL {db.name}.sp_find_free_tables(4, NOW() + INTERVAL 1 DAY, "
                        f"NOW() + INTERVAL 1 DAY + INTERVAL 2 HOUR, FALSE)")
            assert cur.fetchall()
            cur.execute(f"SELECT COUNT(*) FROM {db.name}.vw_active_bookings")
            assert cur.fetchone()[0] >= 1
    finally:
        conn.close()


def test_front_desk_lost_cancellations_in_the_revoke_demo(db):
    conn = db.user_conn("desk_priya")
    try:
        code, msg = _error(conn, f"CALL {db.name}.sp_cancel_booking(1)")
        assert code == 1370, msg                       # EXECUTE command denied
    finally:
        conn.close()


def test_owner_has_everything(db):
    conn = db.user_conn("owner_ravi")
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) FROM {db.name}.Customers")
            assert cur.fetchone()[0] >= 30
    finally:
        conn.close()
