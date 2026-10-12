"""TC-31 (booking race), TC-35 (deadlock) and the two-session demos T2, T3, T4.

T2-T4 are parsed from the /* @two-session ... */ blocks in sql/10_demo_transactions.sql
and run step by step on two real connections (capture_evidence.run_two_session), so the
test exercises exactly the SQL a student pastes into two terminals.
"""
from __future__ import annotations

import threading
from decimal import Decimal

import pymysql

from build_db import connect
from capture_evidence import run_two_session


def _errors(results):
    return [(r.label, r.session, o.error_code, o.error_msg) for r in results for o in r.outcomes
            if o.error_code]


def _row(results, first_column):
    for r in results:
        for o in r.outcomes:
            for rs in o.result_sets:
                if rs.columns and rs.columns[0] == first_column:
                    return rs.rows[0]
    raise AssertionError(f"no result set starting with column {first_column}")


def _value(results, column):
    return _row(results, column)[0]


def test_tc31_four_desks_book_the_same_slot(db, cfg):
    s, e = db.at(10, "19:00"), db.at(10, "21:00")
    table = db.free_table(s, e, min_capacity=2)
    members = [db.new_member() for _ in range(4)]
    barrier = threading.Barrier(4)
    results: dict[int, object] = {}

    def desk(i: int) -> None:
        conn = connect(cfg, database=db.name)
        try:
            with conn.cursor() as cur:
                barrier.wait()
                try:
                    cur.execute("CALL sp_create_reservation(%s, 'Dine_In', %s, NULL, 2, %s, %s, @b)",
                                (members[i], table, s, e))
                    cur.execute("SELECT @b")
                    results[i] = ("ok", cur.fetchone()[0])
                except pymysql.err.MySQLError as exc:
                    results[i] = ("error", exc.args[1])
        finally:
            conn.close()

    threads = [threading.Thread(target=desk, args=(i,)) for i in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(60)
    ok = [v for v in results.values() if v[0] == "ok"]
    errors = [v[1] for v in results.values() if v[0] == "error"]
    assert len(ok) == 1, results
    assert len(errors) == 3 and all(m.startswith("BR-05") for m in errors), results
    assert db.one("""SELECT COUNT(*) FROM Rentals_Reservations WHERE table_id = %s
                      AND reserved_start = %s AND status = 'Reserved'""", (table, s)) == 1


def test_t2_race_demo_two_sessions(db, cfg):
    _, results = run_two_session(cfg, db.name, "T2")
    b1 = next(r for r in results if r.label == "B1")
    assert b1.waited, "Session B should wait on Session A's FOR UPDATE lock"
    assert b1.outcomes[0].error_code == 1644 and b1.outcomes[0].error_msg.startswith("BR-05")
    assert _errors(results) == [("B1", "B", 1644, b1.outcomes[0].error_msg)]
    setup = _row(results, "table_id")               # SELECT @t AS table_id, ..., member_a, member_b
    member_a = setup[3]
    final = next(r for r in results if r.label == "B2").outcomes[-1].result_sets[0].rows
    assert len(final) == 1 and final[0][1] == member_a, "exactly one booking, owned by Session A's member"
    assert _value(results, "booking_b") is None


def test_t3_isolation_levels(db, cfg):
    _, results = run_two_session(cfg, db.name, "T3")
    assert not _errors(results)
    rc1, rc2 = _value(results, "rc_first_read"), _value(results, "rc_second_read")
    rr1, rr2 = _value(results, "rr_first_read"), _value(results, "rr_second_read")
    after = _value(results, "after_commit")
    assert rc2 == rc1 + Decimal(10), "READ COMMITTED shows B's committed change: non-repeatable read"
    assert rr2 == rr1, "REPEATABLE READ keeps the transaction's snapshot"
    assert after == rr1 - Decimal(10) == rc1, "after COMMIT the session sees B's restore"


def test_tc35_deadlock(db, cfg):
    _, results = run_two_session(cfg, db.name, "T4")
    deadlocks = [e for e in _errors(results) if e[2] == 1213]
    assert len(deadlocks) == 1, _errors(results)
    assert len(_errors(results)) == 1, _errors(results)
    victim = deadlocks[0][1]
    survivor = "A" if victim == "B" else "B"
    # the survivor's second lock request succeeded and its COMMIT went through
    second = next(r for r in results if r.label == ("A2" if survivor == "A" else "B2"))
    assert second.outcomes[0].ok and second.outcomes[0].result_sets[0].rows
    commit = next(r for r in results if r.label == ("A3" if survivor == "A" else "B3"))
    assert commit.outcomes[0].ok
    a2 = next(r for r in results if r.label == "A2")
    assert a2.waited, "Session A's request for copy 2 should block before the cycle closes"
