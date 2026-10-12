-- =====================================================================
-- 05_views.sql
-- Purpose : The 9 views (Appendix B.5). Front-desk and analyst roles get
--           access to views, never to base tables (07_roles.sql).
-- Run order: 05 (after 04_triggers.sql; views call the 02 functions)
-- Lab      : Exp 9 (views and operations on views)
-- =====================================================================
USE boardgame_cafe;

-- vw_game_catalog: every title with its categories and copy counts (Exp 9)
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

-- vw_active_bookings: Reserved / Checked_In / Overdue bookings, readable
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

-- vw_available_copies_now: boxes on the shelf and not promised for the next minute
CREATE OR REPLACE VIEW vw_available_copies_now AS
SELECT gc.copy_id, gc.barcode, bg.title, gc.copy_condition, gc.shelf_location
  FROM Game_Copies gc
  JOIN Board_Games bg ON bg.game_id = gc.game_id
 WHERE gc.status = 'Available'
   AND fn_copy_is_free(gc.copy_id, NOW(), NOW() + INTERVAL 1 MINUTE, NULL);

-- vw_overdue_rentals: who is late and the late fee so far (BR-16)
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

-- vw_customer_balances: billed - paid per member (balance is computed, never stored)
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

-- vw_game_popularity: completed plays, players, hours and revenue per title
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

-- vw_table_utilization_30d: share of the 13 opening hours x 30 days each table was used
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

-- vw_copies_needing_attention: boxes off the shelf and the pieces still missing
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
