"""Shared fixtures: one fresh, seeded, throw-away database per test session.

The database is called boardgame_cafe_test_<random>; its roles and demo users
get the same suffix (front_desk_test_<random>, desk_priya_test_<random>, ...),
so the student's real boardgame_cafe database and accounts are never touched.
Everything is dropped again at the end of the session.
"""
from __future__ import annotations

import datetime as dt
import itertools
import secrets
import sys
from pathlib import Path
from typing import Any, Callable

import pymysql
import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from build_db import SQL_DIR, Config, Runner, build, connect, demo_user, load_config  # noqa: E402


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line("markers", "last: run after every other test (TC-32)")


def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    items.sort(key=lambda i: 1 if i.get_closest_marker("last") else 0)


class Db:
    """Thin helper around an autocommit admin connection to the test database."""

    def __init__(self, cfg: Config, name: str):
        self.cfg = cfg
        self.name = name
        self.conn = connect(cfg, database=name)
        self._seq = itertools.count(1)
        self._tag = secrets.token_hex(2)

    # ---- plain SQL ---------------------------------------------------------------
    def rows(self, sql: str, args: Any = None) -> list[tuple]:
        with self.conn.cursor() as cur:
            cur.execute(sql, args)
            return list(cur.fetchall()) if cur.description else []

    def one(self, sql: str, args: Any = None) -> Any:
        r = self.rows(sql, args)
        return r[0][0] if r else None

    def run(self, sql: str, args: Any = None) -> int:
        with self.conn.cursor() as cur:
            n = cur.execute(sql, args)
            while cur.nextset():
                pass
            return n

    def error(self, fn: Callable[[], Any]) -> tuple[int, str]:
        """Run fn, expect a MySQL error, return (code, message)."""
        with pytest.raises(pymysql.err.MySQLError) as info:
            fn()
        return info.value.args[0], info.value.args[1]

    def expect_error(self, fragment: str, sql: str, args: Any = None) -> str:
        code, msg = self.error(lambda: self.run(sql, args))
        assert fragment in f"{code} {msg}", f"expected {fragment!r}, got {code}: {msg}"
        return msg

    # ---- time (always the server's clock) -------------------------------------------
    def now(self) -> dt.datetime:
        return self.one("SELECT NOW()")

    def at(self, days: int, hhmm: str) -> dt.datetime:
        return self.one("SELECT TIMESTAMP(CURRENT_DATE + INTERVAL %s DAY, %s)", (days, hhmm + ":00"))

    # ---- fresh data -------------------------------------------------------------------
    def new_member(self, tier: str = "Gold", age: int = 30, status: str = "Active",
                   expiry_days: int = 365, join_days_ago: int = 30) -> int:
        n = next(self._seq)
        email = f"test{self._tag}.{n}@mail.test"
        phone = f"7{int(self._tag, 16) % 10000:04d}{n:05d}"
        self.run("""INSERT INTO Customers (first_name, last_name, email, phone, date_of_birth,
                                           tier_id, join_date, membership_expiry, status)
                    SELECT 'Test', CONCAT('Member', %s), %s, %s,
                           CURRENT_DATE - INTERVAL %s YEAR - INTERVAL 150 DAY,
                           tier_id, CURRENT_DATE - INTERVAL %s DAY,
                           CURRENT_DATE + INTERVAL %s DAY, %s
                      FROM Membership_Tiers WHERE tier_name = %s""",
                 (n, email, phone, age, join_days_ago, expiry_days, status, tier))
        return self.one("SELECT customer_id FROM Customers WHERE email = %s", (email,))

    def free_table(self, start: dt.datetime, end: dt.datetime, capacity: int | None = None,
                   rate: int | None = None, min_capacity: int = 2) -> int:
        tid = self.one("""SELECT table_id FROM Cafe_Tables
                           WHERE is_active AND seating_capacity >= %s
                             AND (%s IS NULL OR seating_capacity = %s)
                             AND (%s IS NULL OR hourly_rate = %s)
                             AND fn_table_is_free(table_id, %s, %s, NULL)
                           ORDER BY seating_capacity, table_id LIMIT 1""",
                       (min_capacity, capacity, capacity, rate, rate, start, end))
        assert tid, f"no free table (capacity {capacity}, rate {rate}) for {start}-{end}"
        return tid

    def free_copy(self, start: dt.datetime, end: dt.datetime, title: str | None = None,
                  where: str = "TRUE") -> int:
        cid = self.one(f"""SELECT gc.copy_id FROM Game_Copies gc
                             JOIN Board_Games bg ON bg.game_id = gc.game_id
                            WHERE gc.status = 'Available' AND (%s IS NULL OR bg.title = %s)
                              AND bg.title NOT IN ('Spirit Island', 'Hanabi', 'Chess')
                              AND {where}
                              AND fn_copy_is_free(gc.copy_id, %s, %s, NULL)
                            ORDER BY gc.copy_id LIMIT 1""", (title, title, start, end))
        assert cid, f"no free copy of {title or where} for {start}-{end}"
        return cid

    def reserve(self, customer: int, btype: str, table: int | None, copy: int | None,
                party: int | None, start: dt.datetime, end: dt.datetime) -> int:
        with self.conn.cursor() as cur:
            cur.execute("CALL sp_create_reservation(%s, %s, %s, %s, %s, %s, %s, @bid)",
                        (customer, btype, table, copy, party, start, end))
            cur.execute("SELECT @bid")
            return cur.fetchone()[0]

    def booking(self, booking_id: int) -> dict[str, Any]:
        with self.conn.cursor(pymysql.cursors.DictCursor) as cur:
            cur.execute("SELECT * FROM Rentals_Reservations WHERE booking_id = %s", (booking_id,))
            return cur.fetchone()

    def balance(self, customer: int):
        return self.one("SELECT fn_customer_balance(%s)", (customer,))

    def staff(self) -> int:
        return self.one("SELECT staff_id FROM Staff WHERE role = 'Game_Guru' AND is_active "
                        "ORDER BY staff_id LIMIT 1")

    def take_home_now(self, customer: int, copy: int, check_in: bool = True) -> int:
        """A 1-day Take_Home starting now (no opening-hours rules), optionally checked in."""
        start = self.now().replace(second=0, microsecond=0)
        bid = self.reserve(customer, "Take_Home", None, copy, None, start, start + dt.timedelta(days=1))
        if check_in:
            self.run("CALL sp_check_in(%s)", (bid,))
        return bid

    def user_conn(self, name: str) -> pymysql.connections.Connection:
        return connect(self.cfg, user=demo_user(name, self.name), password=self.cfg.demo_password)


@pytest.fixture(scope="session")
def cfg() -> Config:
    return load_config()


@pytest.fixture(scope="session")
def db(cfg: Config):
    name = f"boardgame_cafe_test_{secrets.token_hex(3)}"
    build(cfg, name, quiet=True)
    helper = Db(cfg, name)
    yield helper
    helper.conn.close()
    dropper = Runner(cfg, name)
    try:
        dropper.run_file(SQL_DIR / "00_drop_all.sql")
    finally:
        dropper.close()
