"""TC-01 ... TC-34: every business rule, exercised through the real procedures and triggers.

Rules that depend on opening hours use dates several days ahead; anything that has to
happen "now" uses Take_Home bookings (no opening-hours rule). Members whose account
standing matters are created fresh by the test.
"""
from __future__ import annotations

import datetime as dt
from decimal import Decimal
from pathlib import Path

import pytest

D = Decimal


def window(db, days: int, start: str, end: str) -> tuple[dt.datetime, dt.datetime]:
    return db.at(days, start), db.at(days, end)


# --------------------------------------------------------------------------- BR-01 / BR-02 / BR-03 / BR-04
def test_tc01_party_larger_than_table(db):
    s, e = window(db, 5, "14:00", "16:00")
    member = db.new_member("Gold")
    table = db.free_table(s, e, capacity=4)
    code, msg = db.error(lambda: db.reserve(member, "Dine_In", table, None, 6, s, e))
    assert msg.startswith("BR-01"), msg


def test_tc01b_inactive_table(db):
    s, e = window(db, 5, "14:00", "16:00")
    table = db.one("SELECT table_id FROM Cafe_Tables WHERE NOT is_active")
    code, msg = db.error(lambda: db.reserve(db.new_member(), "Dine_In", table, None, 2, s, e))
    assert msg == "BR-01: table is out of service"


def test_tc02_party_equal_to_capacity(db):
    s, e = window(db, 6, "14:00", "16:00")
    table = db.free_table(s, e, capacity=4)
    bid = db.reserve(db.new_member("Gold"), "Dine_In", table, None, 4, s, e)
    assert db.booking(bid)["status"] == "Reserved"


def test_tc03_party_outside_game_range(db):
    s, e = window(db, 5, "16:00", "18:00")
    table = db.free_table(s, e, min_capacity=2)
    crew = db.free_copy(s, e, "The Crew")                      # 3-5 players
    code, msg = db.error(lambda: db.reserve(db.new_member(), "Dine_In", table, crew, 2, s, e))
    assert msg.startswith("BR-02"), msg


def test_tc04_child_books_18_plus_game(db):
    s, e = window(db, 5, "11:00", "13:00")
    teen = db.new_member("Basic", age=14)
    assert db.one("SELECT fn_customer_age(%s, CURRENT_DATE)", (teen,)) == 14
    table = db.free_table(s, e, min_capacity=4)
    cah = db.free_copy(s, e, "Cards Against Humanity")         # min age 18, 4-10 players
    code, msg = db.error(lambda: db.reserve(teen, "Dine_In", table, cah, 4, s, e))
    assert msg.startswith("BR-03"), msg


def test_tc05_sixteen_year_old_take_home(db):
    s, e = window(db, 3, "12:00", "12:00")
    e = e + dt.timedelta(days=1)
    teen = db.new_member("Silver", age=16)
    copy = db.free_copy(s, e, "Ticket to Ride")                 # min age 8
    code, msg = db.error(lambda: db.reserve(teen, "Take_Home", None, copy, None, s, e))
    assert msg == "BR-04: take-home rentals require age 18+"


# --------------------------------------------------------------------------- BR-05 / BR-06 / BR-07 / BR-08
@pytest.fixture(scope="module")
def booked_table(db):
    """One table booked 14:00-16:00, seven days ahead (TC-06/07/08)."""
    s, e = window(db, 7, "14:00", "18:00")
    table = db.free_table(s, e, capacity=4)
    bid = db.reserve(db.new_member(), "Dine_In", table, None, 2, *window(db, 7, "14:00", "16:00"))
    return table, bid


def test_tc06_overlapping_table_booking(db, booked_table):
    table, _ = booked_table
    code, msg = db.error(lambda: db.reserve(db.new_member(), "Dine_In", table, None, 2,
                                            *window(db, 7, "15:30", "17:00")))
    assert msg == "BR-05: table already booked for an overlapping time"


def test_tc07_touching_window_is_fine(db, booked_table):
    table, _ = booked_table
    bid = db.reserve(db.new_member(), "Dine_In", table, None, 2, *window(db, 7, "16:00", "18:00"))
    assert db.booking(bid)["status"] == "Reserved"


def test_tc08_cancel_then_rebook(db, booked_table):
    table, first = booked_table
    db.run("CALL sp_cancel_booking(%s)", (first,))
    assert db.booking(first)["status"] == "Cancelled"
    bid = db.reserve(db.new_member(), "Dine_In", table, None, 2, *window(db, 7, "14:00", "16:00"))
    assert db.booking(bid)["status"] == "Reserved"


def test_tc09_same_copy_overlapping(db):
    s1, e1 = db.at(8, "10:00"), db.at(9, "10:00")
    s2, e2 = db.at(8, "18:00"), db.at(9, "18:00")
    copy = db.free_copy(s1, e2, "Azul")
    db.reserve(db.new_member("Silver"), "Take_Home", None, copy, None, s1, e1)
    code, msg = db.error(lambda: db.reserve(db.new_member("Silver"), "Take_Home", None, copy, None, s2, e2))
    assert msg == "BR-06: game copy already booked for an overlapping time"


def test_tc10_missing_pieces_copy(db):
    copy = db.one("SELECT copy_id FROM Game_Copies WHERE status = 'Missing_Pieces' ORDER BY copy_id LIMIT 1")
    assert copy, "seed fixture: a copy in Missing_Pieces"
    s, e = db.at(4, "12:00"), db.at(5, "12:00")
    code, msg = db.error(lambda: db.reserve(db.new_member(), "Take_Home", None, copy, None, s, e))
    assert msg == "BR-07: game copy is not available for booking"


def test_tc10b_retired_and_repair_copies(db):
    s, e = db.at(4, "12:00"), db.at(5, "12:00")
    for status in ("Retired", "Under_Repair"):
        copy = db.one("SELECT copy_id FROM Game_Copies WHERE status = %s LIMIT 1", (status,))
        assert copy, f"seed fixture: a copy in {status}"
        code, msg = db.error(lambda: db.reserve(db.new_member(), "Take_Home", None, copy, None, s, e))
        assert msg.startswith("BR-07"), msg


def test_tc11_booking_type_shape(db):
    s, e = window(db, 5, "18:00", "20:00")
    m = db.new_member()
    code, msg = db.error(lambda: db.reserve(m, "Dine_In", None, None, 4, s, e))
    assert msg.startswith("BR-08"), msg
    table = db.free_table(s, e)
    copy = db.free_copy(s, e, "Uno")
    code, msg = db.error(lambda: db.reserve(m, "Take_Home", table, copy, None, s, e))
    assert msg.startswith("BR-08"), msg


# --------------------------------------------------------------------------- BR-09 / BR-10 / BR-11 / BR-12
def test_tc12_dine_in_slot_check_constraint(db):
    m = db.new_member()
    s, e = window(db, 5, "14:15", "16:15")
    table = db.free_table(s, e)
    code, msg = db.error(lambda: db.reserve(m, "Dine_In", table, None, 2, s, e))
    assert code == 3819 and "chk_rr_dinein_slots" in msg, (code, msg)
    s, e = window(db, 5, "14:00", "14:45")
    code, msg = db.error(lambda: db.reserve(m, "Dine_In", table, None, 2, s, e))
    assert code == 3819 and "chk_rr_dinein_slots" in msg, (code, msg)


def test_tc12b_end_before_start(db):
    code, msg = db.error(lambda: db.reserve(db.new_member(), "Take_Home", None, 1, None,
                                            db.at(5, "12:00"), db.at(5, "11:00")))
    assert code == 3819 and "chk_rr_window" in msg, (code, msg)


def test_tc13_outside_opening_hours(db):
    s, e = db.at(5, "21:30"), db.at(5, "21:30") + dt.timedelta(hours=2)
    table = db.free_table(s, e)
    code, msg = db.error(lambda: db.reserve(db.new_member(), "Dine_In", table, None, 2, s, e))
    assert msg == "BR-10: booking outside opening hours (10:00-23:00)"


def test_tc14_basic_member_five_hours(db):
    s, e = window(db, 6, "12:00", "17:00")
    table = db.free_table(s, e)
    code, msg = db.error(lambda: db.reserve(db.new_member("Basic"), "Dine_In", table, None, 2, s, e))
    assert msg == "BR-11: session longer than the membership tier allows"


def test_tc14b_take_home_too_long(db):
    s = db.at(3, "12:00")
    copy = db.free_copy(s, s + dt.timedelta(days=2), "Splendor")
    code, msg = db.error(lambda: db.reserve(db.new_member("Basic"), "Take_Home", None, copy, None,
                                            s, s + dt.timedelta(days=2)))
    assert msg.startswith("BR-11"), msg


def test_tc15_basic_second_concurrent_rental(db):
    m = db.new_member("Basic")
    s1, e1 = db.at(3, "12:00"), db.at(4, "12:00")
    s2, e2 = db.at(10, "12:00"), db.at(11, "12:00")
    db.reserve(m, "Take_Home", None, db.free_copy(s1, e1, "Carcassonne"), None, s1, e1)
    copy2 = db.free_copy(s2, e2, "7 Wonders")
    code, msg = db.error(lambda: db.reserve(m, "Take_Home", None, copy2, None, s2, e2))
    assert msg == "BR-12: concurrent rental limit for the membership tier reached"


# --------------------------------------------------------------------------- BR-13 / BR-14 / BR-15
def test_tc16_account_standing(db):
    s, e = window(db, 4, "12:00", "14:00")
    table = db.free_table(s, e)
    suspended = db.new_member(status="Suspended")
    code, msg = db.error(lambda: db.reserve(suspended, "Dine_In", table, None, 2, s, e))
    assert msg == "BR-13: customer account is not active"

    expired = db.new_member(expiry_days=-1, join_days_ago=400)
    code, msg = db.error(lambda: db.reserve(expired, "Dine_In", table, None, 2, s, e))
    assert msg == "BR-13: membership expires before the booking ends"

    debtor = db.new_member("Gold")
    big = db.one("SELECT table_id FROM Cafe_Tables WHERE is_active ORDER BY hourly_rate DESC LIMIT 1")
    db.run("""INSERT INTO Rentals_Reservations (customer_id, table_id, booking_type, party_size,
                                                reserved_start, reserved_end, checked_in_at,
                                                returned_at, status)
              VALUES (%s, %s, 'Dine_In', 6, TIMESTAMP(CURRENT_DATE - INTERVAL 5 DAY, '12:00:00'),
                      TIMESTAMP(CURRENT_DATE - INTERVAL 5 DAY, '16:00:00'),
                      TIMESTAMP(CURRENT_DATE - INTERVAL 5 DAY, '12:00:00'),
                      TIMESTAMP(CURRENT_DATE - INTERVAL 5 DAY, '16:00:00'), 'Completed')""",
           (debtor, big))
    assert db.balance(debtor) > 500
    code, msg = db.error(lambda: db.reserve(debtor, "Dine_In", table, None, 2, s, e))
    assert msg == "BR-13: outstanding balance above Rs 500"


def test_tc17_booking_window(db):
    m = db.new_member()
    now = db.now().replace(second=0, microsecond=0)
    copy = db.free_copy(now + dt.timedelta(days=15), now + dt.timedelta(days=16), "Uno")
    code, msg = db.error(lambda: db.reserve(m, "Take_Home", None, copy, None,
                                            now + dt.timedelta(days=15), now + dt.timedelta(days=16)))
    assert msg == "BR-14: bookings open only 14 days ahead"
    code, msg = db.error(lambda: db.reserve(m, "Take_Home", None, copy, None,
                                            now - dt.timedelta(hours=2), now + dt.timedelta(hours=20)))
    assert msg == "BR-14: booking cannot start in the past"


def test_tc18_lifecycle(db):
    s, e = window(db, 9, "12:00", "14:00")
    bid = db.reserve(db.new_member(), "Dine_In", db.free_table(s, e), None, 2, s, e)
    db.expect_error("BR-15: invalid status transition",
                    "UPDATE Rentals_Reservations SET status = 'Completed' WHERE booking_id = %s", (bid,))
    done = db.one("SELECT MIN(booking_id) FROM Rentals_Reservations WHERE status = 'Completed'")
    db.expect_error("BR-15: invalid status transition",
                    "UPDATE Rentals_Reservations SET status = 'Reserved' WHERE booking_id = %s", (done,))


def test_tc18b_closed_rows_are_frozen(db):
    done = db.one("SELECT MIN(booking_id) FROM Rentals_Reservations WHERE status = 'Completed'")
    db.expect_error("BR-15: closed bookings cannot be changed",
                    "UPDATE Rentals_Reservations SET reserved_end = reserved_end + INTERVAL 30 MINUTE "
                    "WHERE booking_id = %s", (done,))


def test_tc18c_check_in_too_early(db):
    s, e = window(db, 9, "15:00", "17:00")
    bid = db.reserve(db.new_member(), "Dine_In", db.free_table(s, e), None, 2, s, e)
    db.expect_error("BR-15: check-in opens 15 minutes before start", "CALL sp_check_in(%s)", (bid,))


# --------------------------------------------------------------------------- BR-16 late fees
@pytest.fixture(scope="module")
def priced_dine_in(db):
    """Dine_In at a Rs 150/h table with a Rs 50/h game, 9 days ahead."""
    s, e = window(db, 9, "18:00", "20:00")
    table = db.free_table(s, e, rate=150)
    copy = db.free_copy(s, e, where="bg.hourly_rate = 50 AND bg.min_players <= 2 AND bg.max_players >= 2")
    return db.reserve(db.new_member("Gold"), "Dine_In", table, copy, 2, s, e)


def test_tc19_late_fee_dine_in(db, priced_dine_in):
    fee = lambda minutes: db.one(  # noqa: E731
        "SELECT fn_calculate_late_fee(booking_id, reserved_end + INTERVAL %s MINUTE) "
        "FROM Rentals_Reservations WHERE booking_id = %s", (minutes, priced_dine_in))
    assert fee(40) == D("300.00")      # 1 started hour x (150 + 50) x 1.5
    assert fee(75) == D("600.00")      # 2 started hours


def test_tc20_within_grace(db, priced_dine_in):
    assert db.one("SELECT fn_calculate_late_fee(booking_id, reserved_end + INTERVAL 10 MINUTE) "
                  "FROM Rentals_Reservations WHERE booking_id = %s", (priced_dine_in,)) == D("0.00")
    assert db.one("SELECT fn_calculate_late_fee(booking_id, reserved_end + INTERVAL 15 MINUTE) "
                  "FROM Rentals_Reservations WHERE booking_id = %s", (priced_dine_in,)) == D("0.00")


def test_tc20b_late_fee_take_home(db):
    s, e = db.at(3, "12:00"), db.at(4, "12:00")
    copy = db.free_copy(s, e, where="bg.daily_rate = 150")
    bid = db.reserve(db.new_member("Gold"), "Take_Home", None, copy, None, s, e)
    fee = db.one("SELECT fn_calculate_late_fee(%s, reserved_end + INTERVAL 25 HOUR) "
                 "FROM Rentals_Reservations WHERE booking_id = %s", (bid, bid))
    assert fee == D("450.00")          # 2 started days x 150 x 1.5


# --------------------------------------------------------------------------- BR-17 / BR-18 returns
def component(db, copy: int, unit_cost: int | None = None) -> tuple[int, int]:
    return db.rows("""SELECT gco.component_id, gco.qty_per_copy FROM Game_Components gco
                        JOIN Game_Copies gc ON gc.game_id = gco.game_id
                       WHERE gc.copy_id = %s AND gco.qty_per_copy >= 2
                         AND (%s IS NULL OR gco.unit_replacement_cost = %s)
                       ORDER BY gco.component_id LIMIT 1""", (copy, unit_cost, unit_cost))[0]


def test_tc21_take_home_missing_pieces(db):
    now = db.now()
    copy = db.free_copy(now - dt.timedelta(hours=1), now + dt.timedelta(days=2),
                        where="EXISTS (SELECT 1 FROM Game_Components x WHERE x.game_id = bg.game_id "
                              "AND x.unit_replacement_cost = 15 AND x.qty_per_copy >= 2)")
    member = db.new_member("Silver")
    before = db.balance(member)
    bid = db.take_home_now(member, copy)
    assert db.one("SELECT status FROM Game_Copies WHERE copy_id = %s", (copy,)) == "Rented"
    comp, _ = component(db, copy, unit_cost=15)
    db.run("CALL sp_check_out(%s, %s, 'Good', %s, 'two pieces short')",
           (bid, db.staff(), f'[{{"component_id": {comp}, "qty": 2}}]'))
    b = db.booking(bid)
    assert b["status"] == "Completed"
    assert b["damage_fee"] == D("30.00")
    assert db.one("SELECT charge FROM Missing_Pieces mp JOIN Return_Inspections ri "
                  "ON ri.inspection_id = mp.inspection_id WHERE ri.booking_id = %s", (bid,)) == D("30.00")
    assert db.one("SELECT status FROM Game_Copies WHERE copy_id = %s", (copy,)) == "Missing_Pieces"
    assert db.balance(member) == before + b["total_amount"]
    # restock puts it back on the shelf
    db.run("CALL sp_restock_copy(%s)", (copy,))
    assert db.one("SELECT status FROM Game_Copies WHERE copy_id = %s", (copy,)) == "Available"


def _checked_in_take_home(db, where="TRUE"):
    now = db.now()
    copy = db.free_copy(now - dt.timedelta(hours=1), now + dt.timedelta(days=2), where=where)
    return db.take_home_now(db.new_member("Silver"), copy), copy


def test_tc22_component_of_another_game_rolls_back(db):
    bid, copy = _checked_in_take_home(db)
    other = db.one("""SELECT component_id FROM Game_Components
                       WHERE game_id <> (SELECT game_id FROM Game_Copies WHERE copy_id = %s)
                       ORDER BY component_id LIMIT 1""", (copy,))
    code, msg = db.error(lambda: db.run(
        "CALL sp_check_out(%s, %s, 'Good', %s, NULL)",
        (bid, db.staff(), f'[{{"component_id": {other}, "qty": 1}}]')))
    assert msg == "BR-17: component does not belong to the returned game"
    assert db.one("SELECT COUNT(*) FROM Return_Inspections WHERE booking_id = %s", (bid,)) == 0
    assert db.booking(bid)["status"] == "Checked_In"
    assert db.one("SELECT status FROM Game_Copies WHERE copy_id = %s", (copy,)) == "Rented"


def test_tc23_more_pieces_than_the_box_rolls_back(db):
    bid, copy = _checked_in_take_home(db)
    comp, qty = component(db, copy)
    code, msg = db.error(lambda: db.run(
        "CALL sp_check_out(%s, %s, 'Good', %s, NULL)",
        (bid, db.staff(), f'[{{"component_id": {comp}, "qty": {qty + 1}}}]')))
    assert msg == "BR-17: more pieces missing than the box contains"
    assert db.one("SELECT COUNT(*) FROM Return_Inspections WHERE booking_id = %s", (bid,)) == 0
    assert db.booking(bid)["status"] == "Checked_In"


def test_tc24_damaged_return_goes_to_repair(db):
    bid, copy = _checked_in_take_home(db)
    db.run("CALL sp_check_out(%s, %s, 'Damaged', NULL, 'box crushed')", (bid, db.staff()))
    assert db.booking(bid)["status"] == "Completed"
    assert db.rows("SELECT status, copy_condition FROM Game_Copies WHERE copy_id = %s", (copy,)) == \
        [("Under_Repair", "Damaged")]


def test_tc24b_completion_needs_inspection(db):
    bid, _ = _checked_in_take_home(db)
    db.expect_error("BR-17: inspect the returned game before completing",
                    "UPDATE Rentals_Reservations SET status = 'Completed' WHERE booking_id = %s", (bid,))


def test_tc24c_check_in_needs_copy_back_on_shelf(db):
    """BR-07: a copy that is still out can be reserved for a later window, but check-in
    is refused until the copy is back on the shelf."""
    now = db.now().replace(second=0, microsecond=0)
    copy = db.free_copy(now - dt.timedelta(days=1), now + dt.timedelta(days=2))
    # previous renter: due 5 minutes ago (inside the 15-minute grace, so not Overdue yet)
    db.run("""INSERT INTO Rentals_Reservations (customer_id, copy_id, booking_type, reserved_start,
                                                reserved_end, checked_in_at, status)
              VALUES (%s, %s, 'Take_Home', %s, %s, %s, 'Checked_In')""",
           (db.new_member("Basic"), copy, now - dt.timedelta(days=1) + dt.timedelta(minutes=5),
            now - dt.timedelta(minutes=5), now - dt.timedelta(days=1) + dt.timedelta(minutes=5)))
    previous = db.one("SELECT LAST_INSERT_ID()")
    assert db.one("SELECT status FROM Game_Copies WHERE copy_id = %s", (copy,)) == "Rented"
    nxt = db.reserve(db.new_member(), "Take_Home", None, copy, None, now, now + dt.timedelta(days=1))
    db.expect_error("BR-07: game copy is not back on the shelf yet", "CALL sp_check_in(%s)", (nxt,))
    db.run("CALL sp_check_out(%s, %s, 'Good', NULL, NULL)", (previous, db.staff()))
    db.run("CALL sp_check_in(%s)", (nxt,))
    assert db.booking(nxt)["status"] == "Checked_In"


# --------------------------------------------------------------------------- BR-19 cancellations / no-shows
def test_tc25_cancellation_fees(db):
    s, e = db.at(4, "12:00"), db.at(5, "12:00")
    early = db.reserve(db.new_member(), "Take_Home", None, db.free_copy(s, e, "Pandemic"), None, s, e)
    db.run("CALL sp_cancel_booking(%s)", (early,))
    b = db.booking(early)
    assert (b["status"], b["cancellation_fee"], b["total_amount"]) == ("Cancelled", D("0.00"), D("0.00"))

    now = db.now().replace(second=0, microsecond=0)
    s, e = now + dt.timedelta(hours=1), now + dt.timedelta(hours=1, days=1)
    late = db.reserve(db.new_member(), "Take_Home", None, db.free_copy(s, e), None, s, e)
    db.run("CALL sp_cancel_booking(%s)", (late,))
    b = db.booking(late)
    assert (b["status"], b["cancellation_fee"], b["total_amount"]) == ("Cancelled", D("100.00"), D("100.00"))
    db.expect_error("BR-19", "CALL sp_cancel_booking(%s)", (late,))


def test_tc26_no_show(db):
    now = db.now().replace(second=0, microsecond=0)
    s, e = now - dt.timedelta(minutes=31), now + dt.timedelta(hours=20)
    copy = db.free_copy(s, e)
    member = db.new_member()
    db.run("""INSERT INTO Rentals_Reservations (customer_id, copy_id, booking_type, reserved_start,
                                                reserved_end, status)
              VALUES (%s, %s, 'Take_Home', %s, %s, 'Reserved')""", (member, copy, s, e))
    bid = db.one("SELECT LAST_INSERT_ID()")
    db.run("CALL sp_mark_no_shows()")
    b = db.booking(bid)
    assert (b["status"], b["cancellation_fee"], b["base_charge"], b["total_amount"]) == \
        ("No_Show", D("100.00"), D("0.00"), D("100.00"))


# --------------------------------------------------------------------------- BR-20, PAY, pricing, audit
def test_tc27_delete_customer_with_history(db):
    code, msg = db.error(lambda: db.run("DELETE FROM Customers WHERE customer_id = 1"))
    assert code == 1451, (code, msg)


def test_tc28_overpayment(db):
    bid = db.one("""SELECT rr.booking_id FROM Rentals_Reservations rr
                     WHERE rr.status = 'Completed' AND rr.total_amount > 0
                       AND rr.total_amount = (SELECT IFNULL(SUM(amount), 0) FROM Payments p
                                               WHERE p.booking_id = rr.booking_id)
                     ORDER BY rr.booking_id LIMIT 1""")
    db.expect_error("PAY-02: payment exceeds the amount due", "CALL sp_record_payment(%s, 1, 'UPI')", (bid,))


def test_tc28b_payment_before_check_out(db):
    bid = db.one("SELECT MIN(booking_id) FROM Rentals_Reservations WHERE status = 'Reserved'")
    db.expect_error("PAY-01", "CALL sp_record_payment(%s, 10, 'Cash')", (bid,))


def test_tc29_gold_discount(db):
    s, e = window(db, 10, "12:00", "14:00")
    bid = db.reserve(db.new_member("Gold"), "Dine_In", db.free_table(s, e, rate=150), None, 2, s, e)
    b = db.booking(bid)
    assert (b["base_charge"], b["discount_amount"], b["total_amount"]) == (D("300.00"), D("60.00"), D("240.00"))


def test_tc30_audit_trail(db):
    """A walk-in take-home (inserted as Checked_In) that is then checked out: exactly 2 audit rows."""
    now = db.now().replace(second=0, microsecond=0)
    copy = db.free_copy(now - dt.timedelta(hours=1), now + dt.timedelta(days=1))
    db.run("""INSERT INTO Rentals_Reservations (customer_id, copy_id, booking_type, reserved_start,
                                                reserved_end, checked_in_at, status)
              VALUES (%s, %s, 'Take_Home', %s, %s, %s, 'Checked_In')""",
           (db.new_member(), copy, now - dt.timedelta(hours=1), now + dt.timedelta(hours=23),
            now - dt.timedelta(hours=1)))
    bid = db.one("SELECT LAST_INSERT_ID()")
    db.run("CALL sp_check_out(%s, %s, 'Good', NULL, NULL)", (bid, db.staff()))
    assert db.rows("SELECT old_status, new_status FROM Booking_Audit_Log WHERE booking_id = %s "
                   "ORDER BY log_id", (bid,)) == [(None, "Checked_In"), ("Checked_In", "Completed")]


def test_tc33_history_is_kept(db):
    done = db.one("SELECT MIN(booking_id) FROM Rentals_Reservations WHERE status = 'Completed'")
    db.expect_error("BR-20", "DELETE FROM Rentals_Reservations WHERE booking_id = %s", (done,))
    s, e = window(db, 11, "12:00", "14:00")
    bid = db.reserve(db.new_member(), "Dine_In", db.free_table(s, e), None, 2, s, e)
    db.run("CALL sp_cancel_booking(%s)", (bid,))
    assert db.one("SELECT COUNT(*) FROM Booking_Audit_Log WHERE booking_id = %s", (bid,)) == 2
    assert db.run("DELETE FROM Rentals_Reservations WHERE booking_id = %s", (bid,)) == 1
    assert db.one("SELECT COUNT(*) FROM Booking_Audit_Log WHERE booking_id = %s", (bid,)) == 0


def test_tc34_view_check_option(db):
    m = db.new_member()
    code, msg = db.error(lambda: db.run(
        "UPDATE vw_active_members SET status = 'Suspended' WHERE customer_id = %s", (m,)))
    assert code == 1369, (code, msg)
    assert db.one("SELECT status FROM Customers WHERE customer_id = %s", (m,)) == "Active"


def test_view_insert_lands_in_base_table(db):
    db.run("""INSERT INTO vw_active_members (first_name, last_name, email, phone, date_of_birth,
                                             tier_id, membership_expiry, status)
              VALUES ('View', 'Insert', 'view.insert@mail.test', '7000012345', '1999-05-05', 1,
                      CURRENT_DATE + INTERVAL 1 YEAR, 'Active')""")
    assert db.one("SELECT join_date = CURRENT_DATE FROM Customers WHERE email = 'view.insert@mail.test'") == 1


def test_cursor_procedure_flags_suspensions(db):
    """sp_flag_suspensions: Active owing > 2000 -> Suspended; Suspended owing nothing -> Active."""
    heavy = db.new_member("Basic")
    big = db.one("SELECT table_id FROM Cafe_Tables WHERE is_active ORDER BY hourly_rate DESC LIMIT 1")
    for day in (6, 7):
        db.run("""INSERT INTO Rentals_Reservations (customer_id, table_id, booking_type, party_size,
                                                    reserved_start, reserved_end, status)
                  VALUES (%s, %s, 'Dine_In', 4, TIMESTAMP(CURRENT_DATE - INTERVAL %s DAY, '12:00:00'),
                          TIMESTAMP(CURRENT_DATE - INTERVAL %s DAY, '16:00:00'), 'Completed')""",
               (heavy, big, day, day))
    assert db.balance(heavy) > 2000
    clean = db.new_member(status="Suspended")
    db.run("CALL sp_flag_suspensions()")
    assert db.one("SELECT status FROM Customers WHERE customer_id = %s", (heavy,)) == "Suspended"
    assert db.one("SELECT status FROM Customers WHERE customer_id = %s", (clean,)) == "Active"


@pytest.mark.last
def test_tc32_no_overlapping_active_bookings_after_everything(db):
    text = (Path(__file__).resolve().parent.parent / "sql" / "09_queries.sql").read_text(encoding="utf-8")
    start = text.index("SELECT a.booking_id AS booking_a")
    sql = text[start:text.index(";", start)]
    assert db.rows(sql) == []
    # and the same audit for game copies
    assert db.rows("""SELECT a.booking_id, b.booking_id FROM Rentals_Reservations a
                        JOIN Rentals_Reservations b ON a.copy_id = b.copy_id
                         AND a.booking_id < b.booking_id
                         AND a.reserved_start < b.reserved_end AND b.reserved_start < a.reserved_end
                       WHERE a.status IN ('Reserved', 'Checked_In', 'Overdue')
                         AND b.status IN ('Reserved', 'Checked_In', 'Overdue')""") == []
