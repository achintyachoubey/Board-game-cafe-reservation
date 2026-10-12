"""Every query Q01-Q44, T1, X1, L1-L3 and the walkthrough runs, with spot checks on the results.

Runs on the shared test database after the business-rule tests, i.e. on seed data plus
everything the rule tests added - which is also what TC-32 checks.
"""
from __future__ import annotations

import pytest

from build_db import SQL_DIR, Runner
from capture_evidence import Item, parse_items, run_items


@pytest.fixture(scope="module")
def items(db, cfg) -> dict[str, Item]:
    runner = Runner(cfg, db.name)
    runner.admin.select_db(db.name)
    out: dict[str, Item] = {}
    try:
        for fname in ("09_queries.sql", "10_demo_transactions.sql", "11_demo_indexing.sql",
                      "12_demo_lab_extras.sql"):
            text = (SQL_DIR / fname).read_text(encoding="utf-8")
            parsed = parse_items(text, fname, db.name, cfg)
            run_items(runner, parsed)
            out.update({i.key: i for i in parsed})
    finally:
        runner.close()
    return out


def rows(item: Item, n: int = 0):
    return item.outcomes[n].result_sets[0].rows


def test_all_items_present(items):
    expected = {f"Q{n:02d}" for n in range(1, 45)} | {"T1", "X1", "L1", "L2", "L3"}
    assert expected <= set(items), expected - set(items)


@pytest.mark.parametrize("key", [f"Q{n:02d}" for n in range(1, 45)] + ["T1", "X1", "L1", "L2", "L3"])
def test_item_runs(items, key):
    bad = [(o.stmt.line, o.error_text or f"expected {o.stmt.expect_error}")
           for o in items[key].outcomes if not o.met_expectation]
    assert not bad, bad


def test_q08_no_double_bookings(items):
    assert rows(items["Q08"]) == []


def test_q20_fixture_member_played_every_party_game(items, db):
    ids = {r[0] for r in rows(items["Q20"])}
    assert 9 in ids, ids
    assert db.one("SELECT CONCAT(first_name, ' ', last_name) FROM Customers WHERE customer_id = 9") \
        == "Rahul Verma"


def test_q22_members_with_both_kinds(items):
    assert len(rows(items["Q22"])) >= 1


def test_q23_inactive_table_never_booked(items, db):
    inactive = db.one("SELECT table_code FROM Cafe_Tables WHERE NOT is_active")
    assert inactive in {r[0] for r in rows(items["Q23"])}


def test_q43_full_outer_join_keeps_one_window_games(items):
    data = rows(items["Q43"])
    assert any(prev == 0 and last > 0 for _, prev, last, _ in data), "a game played only recently"
    assert any(prev > 0 and last == 0 for _, prev, last, _ in data), "a game played only before"


def test_q16_never_played(items):
    assert ("Chess",) in rows(items["Q16"])


def test_q35_blocked_members(items):
    reasons = {r[0]: r[2] for r in rows(items["Q35"])}
    assert reasons[19] == "Account Suspended"
    assert reasons[21] == "Membership expired"
    assert reasons[13].startswith("Owes Rs")


def test_q41_q42_q44_lab_extras(items):
    zones = [z for (z,) in rows(items["Q41"])]
    assert zones and len(zones) == len(set(zones)), zones          # DISTINCT zones
    assert len(rows(items["Q42"])) <= 5
    for booking, party, code, capacity, empty in rows(items["Q44"]):
        assert capacity >= party and empty == capacity - party


def test_x1_explain_keys(items):
    explains = [o for o in items["X1"].outcomes if o.stmt.sql.upper().startswith("EXPLAIN SELECT")]
    keys = [o.result_sets[0].rows[0][o.result_sets[0].columns.index("key")] for o in explains]
    assert keys == ["idx_customer_name", None, None, "idx_rr_start"]
    types = [o.result_sets[0].rows[0][o.result_sets[0].columns.index("type")] for o in explains]
    assert types == ["ref", "ALL", "ALL", "range"]
    analyze = next(o for o in items["X1"].outcomes if o.stmt.sql.upper().startswith("EXPLAIN ANALYZE"))
    plan = analyze.result_sets[0].rows[0][0]
    assert "idx_rr_table_window" in plan and "actual time" in plan, plan


def test_t1_savepoint_keeps_first_payment(items):
    before = rows(items["T1"], 1)[0]
    after = items["T1"].outcomes[-1].result_sets[0].rows[0]
    assert after[0] == before[0]
    assert after[2] - before[2] == 200
    assert any(o.error_msg and o.error_msg.startswith("PAY-02") for o in items["T1"].outcomes)


def test_l2_view_operations(items, db):
    assert db.rows("SELECT tier_id, status FROM Customers WHERE email = 'lavanya.rao@mail.test'") == \
        [(3, "Active")]
    assert any(o.error_code == 1369 for o in items["L2"].outcomes)


def test_l3_least_privilege(items):
    codes = [o.error_code for o in items["L3"].outcomes if o.error_code]
    assert codes == [1142, 1142]
    grants = [o for o in items["L3"].outcomes if o.stmt.sql.upper().startswith("SHOW GRANTS FOR 'REPORT_BOT")]
    first, after_role_revoke = grants[0], grants[-1]
    assert any("analyst" in r[0] for r in first.result_sets[0].rows), "REVOKE ALL keeps the role"
    assert not any("analyst" in r[0] for r in after_role_revoke.result_sets[0].rows), \
        "REVOKE 'analyst' removes it"


def test_l1_sandbox_objects_are_gone(db):
    assert db.one("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = %s "
                  "AND table_name IN ('Event_Nights', 'Theme_Nights')", (db.name,)) == 0


def test_events_exist_and_enabled(db):
    assert db.rows("SELECT event_name, status FROM information_schema.events WHERE event_schema = %s "
                   "ORDER BY event_name", (db.name,)) == [
        ("ev_flag_suspensions", "ENABLED"), ("ev_mark_no_shows", "ENABLED"), ("ev_mark_overdue", "ENABLED")]


def test_walkthrough_end_to_end(db, cfg):
    runner = Runner(cfg, db.name)
    try:
        outcomes = runner.run_file(SQL_DIR / "13_walkthrough.sql")
    finally:
        runner.close()
    bad = [(o.stmt.line, o.error_text) for o in outcomes if not o.met_expectation]
    assert not bad, bad
    audit = outcomes[-1].result_sets[0]
    statuses = [r[audit.columns.index("new_status")] for r in audit.rows]
    assert statuses == ["Reserved", "Checked_In", "Completed"]
    fees = next(o for o in outcomes if o.stmt.sql.startswith("SELECT base_charge")).result_sets[0].rows[0]
    base, discount, late, damage, total = fees
    assert damage > 0 and late == 0 and total == base - discount + damage
    copy_status = [o.result_sets[0].rows[0][1] for o in outcomes
                   if o.stmt.sql.startswith("SELECT copy_id, status FROM Game_Copies")]
    assert copy_status == ["Missing_Pieces", "Available"]
    paid = next(o for o in outcomes if "member_balance_now" in o.stmt.sql).result_sets[0].rows[0]
    assert paid[0] == total
