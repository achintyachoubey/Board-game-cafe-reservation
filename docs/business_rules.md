# Business rules

Every rule is enforced **inside the database**. A rule violation is raised with
`SIGNAL SQLSTATE '45000'` (client error **1644**) and a message that starts with the rule ID, so a
client — or a test — can match on it. A few rules are plain constraints and raise the constraint's
own error (CHECK → **3819**, foreign key → **1451/1452**, view CHECK OPTION → **1369**).

Each example below is exercised by the test named in brackets (`tests/test_business_rules.py`
unless stated otherwise); the error text is exactly what MySQL 8.0.46 returned.

## Where each kind of rule lives

| Kind of check | Where | Why there |
| --- | --- | --- |
| Must hold for **every** row: shape, durations, capacity, players, age, opening hours, tier limits | `sp_validate_booking`, called by `trg_rr_before_insert` and `trg_rr_before_update` | A trigger cannot be bypassed — a direct `INSERT`, a procedure and a bulk load all pass through it |
| Must hold only while a booking is **active** (Reserved, Checked_In, Overdue): no overlap, copy available, concurrent-rental limit | Same procedure, guarded by `v_active` | Historical rows (Completed, Cancelled, No_Show) can then be loaded without tripping over each other |
| Depends on **"now"**: start not in the past, at most 14 days ahead, account standing today | `sp_create_reservation` | A row's validity must not change with the clock; only the act of booking does |
| Static shape of a row | CHECK constraints (`chk_booking_type_shape`, `chk_rr_dinein_slots`, `chk_rr_window`, …) | Declarative, checked by the engine on every write |
| History | `ON DELETE RESTRICT` foreign keys + `trg_rr_before_delete` | Nothing billable is ever deleted |

## The rules

| ID | Rule | Enforced by |
| --- | --- | --- |
| BR-01 | Party size ≤ table seating capacity; table must be active | `sp_validate_booking` via booking triggers |
| BR-02 | Dine_In with a game: party size within the game's min–max players | same |
| BR-03 | Booking customer's age on the booking date ≥ game's minimum age | same + `fn_customer_age` |
| BR-04 | Take_Home requires age 18+ | same |
| BR-05 | No two active bookings overlap on a table (`new_start < old_end AND old_start < new_end`); an Overdue booking blocks until returned | same + `fn_table_is_free`; `FOR UPDATE` lock in `sp_create_reservation` |
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

Pricing: base = table hourly × hours + game hourly × hours (Dine_In) or game daily × started days
(Take_Home); the tier discount applies to the base only; `total_amount` is a generated column.
Tiers: Basic (₹0, 1 rental, 4 h, 1 day, 0 %), Silver (₹999, 2, 6 h, 2 days, 10 %),
Gold (₹1,999, 3, 8 h, 3 days, 20 %). A member's balance is computed by `fn_customer_balance`
(final bookings billed − payments) and never stored.

## Examples, one per rule

Dates are written relative to today; `D+5` means `TIMESTAMP(CURRENT_DATE + INTERVAL 5 DAY, …)`.
All calls go through `CALL sp_create_reservation(customer, type, table, copy, party, start, end, @id)`
unless stated otherwise.

### BR-01 — party must fit the table, table must be in service
* Party of 6 at a 4-seat table, D+5 14:00–16:00 → `ERROR 1644 (45000): BR-01: party size exceeds table seating capacity` [TC-01]
* Party of 4 at the same 4-seat table → accepted, status `Reserved` [TC-02]
* Any booking at the inactive table PA-05 → `BR-01: table is out of service` [TC-01b]

### BR-02 — party must fit the game
* Party of 2 with *The Crew* (3–5 players) → `BR-02: party size outside the game player range` [TC-03]

### BR-03 — minimum age
* A 14-year-old books *Cards Against Humanity* (18+) for a party of 4 → `BR-03: customer is below the game minimum age` [TC-04]

### BR-04 — take-home is 18+
* A 16-year-old takes *Ticket to Ride* (8+) home → `BR-04: take-home rentals require age 18+` [TC-05]

### BR-05 — no double-booked table
* Table booked D+7 14:00–16:00; new booking 15:30–17:00 → `BR-05: table already booked for an overlapping time` [TC-06]
* 16:00–18:00 touches but does not overlap (`16:00 < 16:00` is false) → accepted [TC-07]
* Cancel the 14:00–16:00 booking, book 14:00–16:00 again → accepted (cancelled rows are not active) [TC-08]
* Four desks book the same table and slot at the same instant → exactly one succeeds, three get `BR-05` [TC-31, `test_concurrency.py`]

### BR-06 — no double-booked copy
* One *Azul* copy taken home D+8 10:00 → D+9 10:00, then D+8 18:00 → D+9 18:00 for another member → `BR-06: game copy already booked for an overlapping time` [TC-09]

### BR-07 — copy must be bookable
* Book the copy in `Missing_Pieces` (seed fixture: Catan #2) → `BR-07: game copy is not available for booking` [TC-10]; the same for the `Retired` and `Under_Repair` Jenga copies [TC-10b]
* A copy still out with the previous renter (due 5 minutes ago) can be reserved from now, but `CALL sp_check_in(…)` → `BR-07: game copy is not back on the shelf yet`; after the previous rental is checked out, check-in succeeds [TC-24c]

### BR-08 — booking shape
* Dine_In without a table → `BR-08: booking type does not match table/copy/party fields`
* Take_Home with a table → same error [TC-11]
* (The CHECK constraint `chk_booking_type_shape` is the second line of defence: the trigger fires first, so the client sees the BR-08 message.)

### BR-09 — time window shape (CHECK constraints)
* Dine_In 14:15–16:15 → `ERROR 3819 (HY000): Check constraint 'chk_rr_dinein_slots' is violated.`
* Dine_In 14:00–14:45 (45 minutes) → same [TC-12]
* End before start → `Check constraint 'chk_rr_window' is violated.` [TC-12b]

### BR-10 — opening hours
* Dine_In 21:30–23:30 → `BR-10: booking outside opening hours (10:00-23:00)` [TC-13]

### BR-11 — tier length limits
* Basic member, Dine_In 12:00–17:00 (5 h > 4 h) → `BR-11: session longer than the membership tier allows` [TC-14]
* Basic member, 2-day take-home (> 1 day) → `BR-11: take-home rental longer than the membership tier allows` [TC-14b]

### BR-12 — concurrent rentals
* Basic member already holding a take-home reservation books a second game → `BR-12: concurrent rental limit for the membership tier reached` [TC-15]

### BR-13 — account standing (in `sp_create_reservation`)
* Suspended member → `BR-13: customer account is not active`
* Membership expired yesterday → `BR-13: membership expires before the booking ends`
* Member owing ₹1,120 → `BR-13: outstanding balance above Rs 500` [TC-16]
* Seed fixtures that show it: member 19 (Suspended), 21 (expired), 13 (owes ₹972) — query Q35 lists them with the reason.

### BR-14 — booking window
* Take-home starting 15 days from now → `BR-14: bookings open only 14 days ahead`
* Starting 2 hours ago → `BR-14: booking cannot start in the past` [TC-17]

### BR-15 — lifecycle
* `UPDATE … SET status = 'Completed'` on a Reserved booking → `BR-15: invalid status transition`
* `UPDATE … SET status = 'Reserved'` on a Completed booking → same [TC-18]
* Moving the end time of a Completed booking → `BR-15: closed bookings cannot be changed` [TC-18b]
* `CALL sp_check_in(…)` for a booking 9 days ahead → `BR-15: check-in opens 15 minutes before start` [TC-18c]

### BR-16 — late fees
* Dine_In at a ₹150/h table with a ₹50/h game, returned 40 min late → ₹300 (1 started hour × ₹200 × 1.5); 75 min late → ₹600 (2 hours) [TC-19]
* 10 or 15 minutes late → ₹0 (grace period) [TC-20]
* Take-home of a ₹150/day game returned 25 h late → ₹450 (2 started days × ₹150 × 1.5) [TC-20b]
* Computed with `fn_calculate_late_fee(booking_id, reserved_end + INTERVAL n MINUTE)`; `sp_check_out` stores it.

### BR-17 — inspection of returned boxes
* Take-home returned with 2 pieces at ₹15 missing → `damage_fee` ₹30, `Missing_Pieces.charge` ₹30, member's balance rises by the booking total [TC-21]
* Report a component of another game → `BR-17: component does not belong to the returned game`, and the **whole** check-out is rolled back: no inspection row, booking still `Checked_In`, copy still `Rented` [TC-22]
* Report more pieces than the box holds → `BR-17: more pieces missing than the box contains`, rolled back [TC-23]
* Set a booking holding a copy to Completed without an inspection → `BR-17: inspect the returned game before completing` [TC-24b]

### BR-18 — copy status after inspection
* Missing pieces → copy `Missing_Pieces`; `sp_restock_copy` → back to `Available` [TC-21]
* Returned `Damaged`, nothing missing → copy `Under_Repair`, condition `Damaged` [TC-24]

### BR-19 — cancellations and no-shows
* Cancel 4 days ahead → fee ₹0, total ₹0; cancel a pick-up due in 1 hour → fee ₹100; cancel it again → `BR-19: only Reserved bookings can be cancelled` [TC-25]
* Reserved booking whose start was 31 minutes ago, `CALL sp_mark_no_shows()` → `No_Show`, fee ₹100, base ₹0 [TC-26] (the event `ev_mark_no_shows` does the same every 15 minutes)

### BR-20 — history is kept
* `DELETE FROM Customers WHERE customer_id = 1` → `ERROR 1451 (23000): Cannot delete or update a parent row: a foreign key constraint fails` [TC-27]
* Delete a Completed booking → `BR-20: only free cancellations can be deleted; history is kept`
* Delete a free cancellation → 1 row deleted, its 2 audit rows go with it (`ON DELETE CASCADE`) [TC-33]

### PAY-01 / PAY-02 — payments
* Pay ₹1 more on a booking that is fully paid → `PAY-02: payment exceeds the amount due` [TC-28]
* Pay for a booking that is still Reserved → `PAY-01: payments are taken after check-out, cancellation or no-show` [TC-28b]
* In T1 (`sql/10_demo_transactions.sql`) the PAY-02 error inside a transaction rolls back only that statement; `ROLLBACK TO SAVEPOINT` and `COMMIT` keep the earlier ₹200 payment.

### Pricing and audit
* Gold member, 2 h at a ₹150/h table → base ₹300, discount ₹60, total ₹240 [TC-29]
* A walk-in take-home inserted as Checked_In and then checked out → exactly 2 audit rows: `(NULL → Checked_In)`, `(Checked_In → Completed)` [TC-30]
* `UPDATE vw_active_members SET status = 'Suspended' …` → `ERROR 1369 (HY000): CHECK OPTION failed` [TC-34]
* `sp_flag_suspensions` (cursor) suspends an Active member owing > ₹2,000 and reactivates a Suspended member owing nothing [`test_cursor_procedure_flags_suspensions`]
