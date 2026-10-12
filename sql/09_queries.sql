-- =====================================================================
-- 09_queries.sql
-- Purpose : The query bank Q01-Q44 (Appendix C), grouped by concept:
--             A retrieval (Q01-Q04)        F window functions (Q24-Q28)
--             B joins (Q05-Q09)            G CTEs incl. recursive (Q29-Q30)
--             C aggregation (Q10-Q14)      H business-rule queries (Q31-Q36)
--             D subqueries (Q15-Q20)       I DML (Q37-Q40)
--             E set operations (Q21-Q23)   Lab extras (Q41-Q44)
-- Run order: after 08_seed.sql. Q37-Q40 CHANGE data (UPDATE / INSERT /
--            upsert / DELETE); rebuild with scripts/build_db.py to reset.
-- Lab      : Exp 5, 6, 7, 8, 9 (and Exp 4 for Q37-Q40)
-- Notation : π project, σ select, ⋈ join, ⟕ left outer join, γ group/aggregate,
--            ρ rename, ∪ ∩ − set operations, ÷ division
-- =====================================================================
USE boardgame_cafe;

-- =====================================================================
-- Q01 · Which games suit a group of 5, youngest player 10, under an hour?
-- Concept: WHERE with BETWEEN, comparison, ORDER BY   Lab: Exp 5
-- Relational algebra: π title,… (σ min_players≤5≤max_players ∧ min_age≤10 ∧ avg_play_minutes≤60 (Board_Games))
-- =====================================================================
SELECT title, min_players, max_players, min_age, avg_play_minutes, complexity
  FROM Board_Games
 WHERE 5 BETWEEN min_players AND max_players
   AND min_age <= 10
   AND avg_play_minutes <= 60
 ORDER BY complexity, title;

-- =====================================================================
-- Q02 · Whose membership expires in the next 30 days?
-- Concept: date arithmetic, BETWEEN on dates   Lab: Exp 5
-- Relational algebra: π customer_id,… (σ today ≤ membership_expiry ≤ today+30 (Customers))
-- =====================================================================
SELECT customer_id, CONCAT(first_name, ' ', last_name) AS member, email, membership_expiry,
       DATEDIFF(membership_expiry, CURRENT_DATE) AS days_left
  FROM Customers
 WHERE membership_expiry BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL 30 DAY
 ORDER BY membership_expiry;

-- =====================================================================
-- Q03 · Which large tables (6+ seats) are in the Party Room or on the Patio, accessible first?
-- Concept: IN list, boolean column, multi-key ORDER BY   Lab: Exp 5
-- Relational algebra: π table_code,… (σ zone∈{Party_Room,Patio} ∧ seating_capacity≥6 ∧ is_active (Cafe_Tables))
-- =====================================================================
SELECT table_code, zone, seating_capacity, hourly_rate, is_accessible
  FROM Cafe_Tables
 WHERE zone IN ('Party_Room', 'Patio') AND seating_capacity >= 6 AND is_active
 ORDER BY is_accessible DESC, seating_capacity;

-- =====================================================================
-- Q04 · Find a member from a partial name or the last digits of a phone number (LIKE).
-- Concept: LIKE with % wildcards, OR   Lab: Exp 5
-- Relational algebra: π customer_id,… (σ first_name LIKE 'Ar%' ∨ last_name LIKE '%sh%' ∨ phone LIKE '%4321' (Customers))
-- =====================================================================
SELECT customer_id, first_name, last_name, phone
  FROM Customers
 WHERE first_name LIKE 'Ar%' OR last_name LIKE '%sh%' OR phone LIKE '%4321';

-- =====================================================================
-- Q05 · Today's floor plan: every booking with customer, table and game (INNER + LEFT JOIN).
-- Concept: INNER JOIN + LEFT OUTER JOIN chain, sargable date range   Lab: Exp 7
-- Relational algebra: σ start∈today (RR) ⋈ Customers ⟕ Cafe_Tables ⟕ Game_Copies ⟕ Board_Games
-- =====================================================================
SELECT rr.booking_id, TIME(rr.reserved_start) AS starts, TIME(rr.reserved_end) AS ends,
       CONCAT(c.first_name, ' ', c.last_name) AS customer, rr.party_size,
       ct.table_code, ct.zone, IFNULL(bg.title, '(table only)') AS game, rr.status
  FROM Rentals_Reservations rr
  JOIN Customers c         ON c.customer_id = rr.customer_id
  LEFT JOIN Cafe_Tables ct ON ct.table_id   = rr.table_id
  LEFT JOIN Game_Copies gc ON gc.copy_id    = rr.copy_id
  LEFT JOIN Board_Games bg ON bg.game_id    = gc.game_id
 WHERE rr.reserved_start >= CURRENT_DATE
   AND rr.reserved_start <  CURRENT_DATE + INTERVAL 1 DAY
 ORDER BY rr.reserved_start, ct.table_code;

-- =====================================================================
-- Q06 · Full catalogue with categories (M:N join + GROUP_CONCAT).
-- Concept: resolving an M:N relationship through its bridge table   Lab: Exp 7
-- Relational algebra: γ game_id,title; GROUP_CONCAT(category_name) (Board_Games ⋈ Board_Game_Categories ⋈ Game_Categories)
-- =====================================================================
SELECT bg.title,
       GROUP_CONCAT(cat.category_name ORDER BY cat.category_name SEPARATOR ', ') AS categories
  FROM Board_Games bg
  JOIN Board_Game_Categories bgc ON bgc.game_id   = bg.game_id
  JOIN Game_Categories cat       ON cat.category_id = bgc.category_id
 GROUP BY bg.game_id, bg.title
 ORDER BY bg.title;

-- =====================================================================
-- Q07 · Which tables had no bookings in the last 7 days (LEFT JOIN … IS NULL)?
-- Concept: anti-join with LEFT JOIN … IS NULL; filter in ON, not WHERE   Lab: Exp 7
-- Relational algebra: π table_code,zone (Cafe_Tables) − π table_code,zone (Cafe_Tables ⋈ σ start≥today−7 (RR))
-- =====================================================================
SELECT ct.table_code, ct.zone
  FROM Cafe_Tables ct
  LEFT JOIN Rentals_Reservations rr
         ON rr.table_id = ct.table_id
        AND rr.reserved_start >= CURRENT_DATE - INTERVAL 7 DAY
 WHERE rr.booking_id IS NULL;

-- =====================================================================
-- Q08 · Integrity audit: are any two active bookings overlapping on one table (self-join)?
-- Concept: self-join with a non-equi overlap condition; must return 0 rows   Lab: Exp 7
-- Relational algebra: σ a.id<b.id ∧ a.start<b.end ∧ b.start<a.end (ρa(σ active RR) ⋈ a.table_id=b.table_id ρb(σ active RR))
-- =====================================================================
SELECT a.booking_id AS booking_a, b.booking_id AS booking_b, ct.table_code,
       a.reserved_start AS a_start, a.reserved_end AS a_end,
       b.reserved_start AS b_start, b.reserved_end AS b_end
  FROM Rentals_Reservations a
  JOIN Rentals_Reservations b
    ON a.table_id = b.table_id
   AND a.booking_id < b.booking_id
   AND a.reserved_start < b.reserved_end
   AND b.reserved_start < a.reserved_end
  JOIN Cafe_Tables ct ON ct.table_id = a.table_id
 WHERE a.status IN ('Reserved', 'Checked_In', 'Overdue')
   AND b.status IN ('Reserved', 'Checked_In', 'Overdue');

-- =====================================================================
-- Q09 · How many returns has each staff member inspected, including staff with none (RIGHT JOIN)?
-- Concept: RIGHT OUTER JOIN + COUNT(column) ignores NULLs   Lab: Exp 7
-- Relational algebra: γ staff_id; COUNT(inspection_id) (Return_Inspections ⟖ Staff)
-- =====================================================================
SELECT s.full_name, s.role, COUNT(ri.inspection_id) AS inspections
  FROM Return_Inspections ri
 RIGHT JOIN Staff s ON s.staff_id = ri.inspected_by
 GROUP BY s.staff_id, s.full_name, s.role
 ORDER BY inspections DESC;

-- =====================================================================
-- Q10 · Revenue by month and booking type, with subtotals (GROUP BY … WITH ROLLUP).
-- Concept: GROUP BY on an expression alias, WITH ROLLUP super-aggregates   Lab: Exp 6
-- Relational algebra: γ month,booking_type; COUNT(*),SUM(total_amount) (σ closed (RR))
-- =====================================================================
SELECT DATE_FORMAT(reserved_start, '%Y-%m') AS month, booking_type,
       COUNT(*) AS bookings, SUM(total_amount) AS revenue
  FROM Rentals_Reservations
 WHERE status IN ('Completed', 'Cancelled', 'No_Show')
 GROUP BY month, booking_type WITH ROLLUP;

-- =====================================================================
-- Q11 · Which zones average more than 3 guests per booking (HAVING)?
-- Concept: HAVING filters groups after aggregation   Lab: Exp 6
-- Relational algebra: σ avg_party>3 (γ zone; COUNT(*),AVG(party_size) (σ Completed (RR) ⋈ Cafe_Tables))
-- =====================================================================
SELECT ct.zone, COUNT(*) AS bookings, ROUND(AVG(rr.party_size), 2) AS avg_party,
       ROUND(100 * AVG(rr.party_size / ct.seating_capacity), 1) AS avg_seat_fill_pct
  FROM Rentals_Reservations rr
  JOIN Cafe_Tables ct ON ct.table_id = rr.table_id
 WHERE rr.status = 'Completed'
 GROUP BY ct.zone
HAVING AVG(rr.party_size) > 3;

-- =====================================================================
-- Q12 · Which games lose the most pieces, and how much was charged?
-- Concept: SUM / COUNT(DISTINCT) over a three-table join   Lab: Exp 6
-- Relational algebra: γ game_id,title; SUM(qty_missing),SUM(charge) (Missing_Pieces ⋈ Game_Components ⋈ Board_Games)
-- =====================================================================
SELECT bg.title, SUM(mp.qty_missing) AS pieces_lost, SUM(mp.charge) AS charged,
       COUNT(DISTINCT mp.inspection_id) AS bad_returns
  FROM Missing_Pieces mp
  JOIN Game_Components comp ON comp.component_id = mp.component_id
  JOIN Board_Games bg       ON bg.game_id        = comp.game_id
 GROUP BY bg.game_id, bg.title
 ORDER BY pieces_lost DESC;

-- =====================================================================
-- Q13 · What share of each game's returns came back with missing pieces (derived table + correlated EXISTS)?
-- Concept: derived table in FROM, EXISTS as a 0/1 value, AVG of a flag = rate   Lab: Exp 8
-- Relational algebra: γ game; COUNT(*),SUM(had_loss) (x ⋈ Game_Copies ⋈ Board_Games), x = Return_Inspections ⋈ RR
-- =====================================================================
SELECT bg.title,
       COUNT(*)                        AS returns_inspected,
       SUM(x.had_loss)                 AS returns_with_losses,
       ROUND(100 * AVG(x.had_loss), 1) AS loss_rate_pct
  FROM (SELECT ri.inspection_id, rr.copy_id,
               EXISTS (SELECT 1 FROM Missing_Pieces mp
                        WHERE mp.inspection_id = ri.inspection_id) AS had_loss
          FROM Return_Inspections ri
          JOIN Rentals_Reservations rr ON rr.booking_id = ri.booking_id) AS x
  JOIN Game_Copies gc ON gc.copy_id = x.copy_id
  JOIN Board_Games bg ON bg.game_id = gc.game_id
 GROUP BY bg.game_id, bg.title
 ORDER BY loss_rate_pct DESC;

-- =====================================================================
-- Q14 · Copy condition by game, as a pivot (conditional aggregation).
-- Concept: SUM(boolean) pivot - rows become columns   Lab: Exp 6
-- Relational algebra: γ game; SUM(copy_condition='New'),… (σ status≠Retired (Game_Copies) ⋈ Board_Games)
-- =====================================================================
SELECT bg.title,
       SUM(gc.copy_condition = 'New')     AS new_copies,
       SUM(gc.copy_condition = 'Good')    AS good,
       SUM(gc.copy_condition = 'Fair')    AS fair,
       SUM(gc.copy_condition = 'Worn')    AS worn,
       SUM(gc.copy_condition = 'Damaged') AS damaged,
       COUNT(*)                           AS total
  FROM Game_Copies gc
  JOIN Board_Games bg ON bg.game_id = gc.game_id
 WHERE gc.status <> 'Retired'
 GROUP BY bg.game_id, bg.title
 ORDER BY bg.title;

-- =====================================================================
-- Q15 · Which games are played more than the average game (subquery in HAVING over a derived table)?
-- Concept: scalar subquery in HAVING; AVG over a derived table   Lab: Exp 8
-- Relational algebra: σ plays > avg(plays) (γ game; COUNT(booking_id) (Board_Games ⋈ Game_Copies ⋈ σ Completed (RR)))
-- =====================================================================
SELECT bg.title, COUNT(rr.booking_id) AS plays
  FROM Board_Games bg
  JOIN Game_Copies gc          ON gc.game_id = bg.game_id
  JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id AND rr.status = 'Completed'
 GROUP BY bg.game_id, bg.title
HAVING COUNT(rr.booking_id) > (
         SELECT AVG(per_game.plays)
           FROM (SELECT COUNT(rr2.booking_id) AS plays
                   FROM Board_Games bg2
                   LEFT JOIN Game_Copies gc2          ON gc2.game_id = bg2.game_id
                   LEFT JOIN Rentals_Reservations rr2 ON rr2.copy_id = gc2.copy_id
                                                     AND rr2.status = 'Completed'
                  GROUP BY bg2.game_id) AS per_game)
 ORDER BY plays DESC;

-- =====================================================================
-- Q16 · Which games have never been played (NOT EXISTS anti-join)?
-- Concept: correlated NOT EXISTS   Lab: Exp 8
-- Relational algebra: π title (Board_Games) − π title (Board_Games ⋈ Game_Copies ⋈ RR)
-- =====================================================================
SELECT bg.title
  FROM Board_Games bg
 WHERE NOT EXISTS (SELECT 1
                     FROM Game_Copies gc
                     JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id
                    WHERE gc.game_id = bg.game_id);

-- =====================================================================
-- Q17 · Model members: have completed bookings and never paid a late or damage fee (IN / NOT IN).
-- Concept: IN / NOT IN subqueries (safe here: customer_id is NOT NULL)   Lab: Exp 8
-- Relational algebra: π customer_id (σ Completed (RR)) − π customer_id (σ late_fee>0 ∨ damage_fee>0 (RR))
-- =====================================================================
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member
  FROM Customers c
 WHERE c.customer_id IN (SELECT customer_id FROM Rentals_Reservations
                          WHERE status = 'Completed')
   AND c.customer_id NOT IN (SELECT customer_id FROM Rentals_Reservations
                              WHERE late_fee > 0 OR damage_fee > 0);

-- =====================================================================
-- Q18 · Each member's most recent completed visit and what they played (correlated subquery).
-- Concept: correlated scalar subquery (MAX per outer row)   Lab: Exp 8
-- Relational algebra: Customers ⋈ σ start = max_start(customer) (σ Completed (RR)) ⟕ Game_Copies ⟕ Board_Games
-- =====================================================================
SELECT c.first_name, c.last_name, rr.reserved_start AS last_visit,
       IFNULL(bg.title, '(table only)') AS played
  FROM Customers c
  JOIN Rentals_Reservations rr ON rr.customer_id = c.customer_id AND rr.status = 'Completed'
  LEFT JOIN Game_Copies gc     ON gc.copy_id = rr.copy_id
  LEFT JOIN Board_Games bg     ON bg.game_id = gc.game_id
 WHERE rr.reserved_start = (SELECT MAX(r2.reserved_start)
                              FROM Rentals_Reservations r2
                             WHERE r2.customer_id = c.customer_id
                               AND r2.status = 'Completed');

-- =====================================================================
-- Q19 · Tables bigger than every table in the Quiet Corner (> ALL).
-- Concept: quantified comparison > ALL   Lab: Exp 8
-- Relational algebra: σ seating_capacity > max(π seating_capacity σ zone=Quiet_Corner (Cafe_Tables)) (Cafe_Tables)
-- =====================================================================
SELECT table_code, zone, seating_capacity
  FROM Cafe_Tables
 WHERE seating_capacity > ALL (SELECT seating_capacity FROM Cafe_Tables
                                WHERE zone = 'Quiet_Corner');

-- =====================================================================
-- Q20 · Who has played every Party game?
-- Concept: relational division (double NOT EXISTS)   Lab: Exp 8
-- Relational algebra: π customer_id,game_id (RR ⋈ Copies) ÷ π game_id (Party games)
-- =====================================================================
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member
  FROM Customers c
 WHERE NOT EXISTS (
         SELECT 1
           FROM Board_Game_Categories bgc
           JOIN Game_Categories cat ON cat.category_id = bgc.category_id
          WHERE cat.category_name = 'Party'
            AND NOT EXISTS (
                  SELECT 1
                    FROM Rentals_Reservations rr
                    JOIN Game_Copies gc ON gc.copy_id = rr.copy_id
                   WHERE rr.customer_id = c.customer_id
                     AND rr.status = 'Completed'
                     AND gc.game_id = bgc.game_id));

-- =====================================================================
-- Q21 · One reminder list: memberships expiring within 7 days plus anyone holding an overdue game (UNION).
-- Concept: UNION (duplicates removed), ORDER BY applies to the whole union   Lab: Exp 8
-- Relational algebra: π email,reason (σ expiring (Customers)) ∪ π email,reason (Customers ⋈ σ Overdue (RR))
-- =====================================================================
SELECT c.email, 'Membership expiring' AS reason
  FROM Customers c
 WHERE c.membership_expiry BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL 7 DAY
UNION
SELECT c.email, 'Overdue rental'
  FROM Customers c
  JOIN Rentals_Reservations rr ON rr.customer_id = c.customer_id
 WHERE rr.status = 'Overdue'
 ORDER BY email;

-- =====================================================================
-- Q22 · Members who have both played in the café and taken a game home (INTERSECT).
-- Concept: INTERSECT (MySQL 8.0.31+)   Lab: Exp 8
-- Relational algebra: π customer_id (σ Dine_In ∧ Completed (RR)) ∩ π customer_id (σ Take_Home ∧ Completed (RR))
-- =====================================================================
SELECT customer_id FROM Rentals_Reservations
 WHERE booking_type = 'Dine_In' AND status = 'Completed'
INTERSECT
SELECT customer_id FROM Rentals_Reservations
 WHERE booking_type = 'Take_Home' AND status = 'Completed';

-- =====================================================================
-- Q23 · Tables that have never been booked at all (EXCEPT).
-- Concept: EXCEPT (MySQL 8.0.31+) inside an IN subquery   Lab: Exp 8
-- Relational algebra: π table_id (Cafe_Tables) − π table_id (σ table_id IS NOT NULL (RR))
-- =====================================================================
SELECT ct.table_code, ct.zone
  FROM Cafe_Tables ct
 WHERE ct.table_id IN (SELECT table_id FROM Cafe_Tables
                       EXCEPT
                       SELECT table_id FROM Rentals_Reservations WHERE table_id IS NOT NULL);

-- =====================================================================
-- Q24 · Rank games by plays inside each category (RANK vs DENSE_RANK).
-- Concept: window functions with PARTITION BY; gaps vs no gaps after ties   Lab: Exp 6 (extension)
-- Relational algebra: (window functions go beyond classical RA) over γ category,game; COUNT(booking_id)
-- =====================================================================
SELECT category_name, title, plays,
       RANK()       OVER (PARTITION BY category_name ORDER BY plays DESC) AS rank_in_category,
       DENSE_RANK() OVER (PARTITION BY category_name ORDER BY plays DESC) AS dense_rank_in_category
  FROM (SELECT cat.category_name, bg.title, COUNT(rr.booking_id) AS plays
          FROM Game_Categories cat
          JOIN Board_Game_Categories bgc    ON bgc.category_id = cat.category_id
          JOIN Board_Games bg               ON bg.game_id      = bgc.game_id
          LEFT JOIN Game_Copies gc          ON gc.game_id      = bg.game_id
          LEFT JOIN Rentals_Reservations rr ON rr.copy_id      = gc.copy_id
                                           AND rr.status = 'Completed'
         GROUP BY cat.category_id, cat.category_name, bg.game_id, bg.title) AS t
 ORDER BY category_name, rank_in_category;

-- =====================================================================
-- Q25 · Top 3 spenders in each membership tier (CTE + ROW_NUMBER).
-- Concept: chained CTEs, ROW_NUMBER for top-N per group   Lab: Exp 6 (extension)
-- Relational algebra: σ position≤3 (window over γ customer; SUM(total_amount) (Customers ⋈ Tiers ⋈ σ Completed (RR)))
-- =====================================================================
WITH spend AS (
  SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member,
         t.tier_name, SUM(rr.total_amount) AS total_spent
    FROM Customers c
    JOIN Membership_Tiers t      ON t.tier_id      = c.tier_id
    JOIN Rentals_Reservations rr ON rr.customer_id = c.customer_id AND rr.status = 'Completed'
   GROUP BY c.customer_id, c.first_name, c.last_name, t.tier_id, t.tier_name
), ranked AS (
  SELECT spend.*,
         ROW_NUMBER() OVER (PARTITION BY tier_name ORDER BY total_spent DESC) AS position
    FROM spend
)
SELECT tier_name, position, member, total_spent
  FROM ranked
 WHERE position <= 3
 ORDER BY tier_name, position;

-- =====================================================================
-- Q26 · Daily revenue with a running total and 7-day moving average (SUM/AVG OVER with a frame).
-- Concept: window frame ROWS BETWEEN 6 PRECEDING AND CURRENT ROW   Lab: Exp 6 (extension)
-- Relational algebra: (window functions) over γ DATE(returned_at); SUM(total_amount) (σ Completed (RR))
-- =====================================================================
WITH daily AS (
  SELECT DATE(returned_at) AS day, SUM(total_amount) AS revenue
    FROM Rentals_Reservations
   WHERE status = 'Completed'
   GROUP BY DATE(returned_at)
)
SELECT day, revenue,
       SUM(revenue) OVER (ORDER BY day) AS running_total,
       ROUND(AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2)
         AS moving_avg_7d
  FROM daily
 ORDER BY day;

-- =====================================================================
-- Q27 · Days between each member's visits (LAG with a named window).
-- Concept: LAG(), WINDOW clause   Lab: Exp 6 (extension)
-- Relational algebra: (window functions) over σ Completed (RR) ⋈ Customers
-- =====================================================================
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member,
       rr.reserved_start AS visit,
       LAG(rr.reserved_start) OVER w AS previous_visit,
       DATEDIFF(rr.reserved_start, LAG(rr.reserved_start) OVER w) AS days_since_previous
  FROM Rentals_Reservations rr
  JOIN Customers c ON c.customer_id = rr.customer_id
 WHERE rr.status = 'Completed'
WINDOW w AS (PARTITION BY rr.customer_id ORDER BY rr.reserved_start)
 ORDER BY c.customer_id, rr.reserved_start;

-- =====================================================================
-- Q28 · Split members into spend quartiles (NTILE).
-- Concept: NTILE over a view   Lab: Exp 9 (querying a view)
-- Relational algebra: (window function) over vw_customer_balances
-- =====================================================================
SELECT customer, tier_name, total_billed,
       NTILE(4) OVER (ORDER BY total_billed DESC) AS spend_quartile
  FROM vw_customer_balances
 ORDER BY spend_quartile, total_billed DESC;

-- =====================================================================
-- Q29 · Tomorrow's availability grid: every table × every half-hour slot (recursive CTE + CROSS JOIN).
-- Concept: WITH RECURSIVE generator, CROSS JOIN (Cartesian product), stored function in SELECT   Lab: Exp 7
-- Relational algebra: slots × σ is_active (Cafe_Tables)
-- =====================================================================
WITH RECURSIVE slots AS (
  SELECT TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '10:00:00') AS slot_start
  UNION ALL
  SELECT slot_start + INTERVAL 30 MINUTE
    FROM slots
   WHERE slot_start + INTERVAL 30 MINUTE < TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '23:00:00')
)
SELECT TIME_FORMAT(s.slot_start, '%H:%i') AS slot, ct.table_code,
       CASE WHEN fn_table_is_free(ct.table_id, s.slot_start, s.slot_start + INTERVAL 30 MINUTE, NULL)
            THEN 'free' ELSE 'booked' END AS state
  FROM slots s
 CROSS JOIN Cafe_Tables ct
 WHERE ct.is_active
 ORDER BY s.slot_start, ct.table_code;

-- =====================================================================
-- Q30 · Peak hours by weekday, banded with CASE.
-- Concept: CTE + GROUP BY + searched CASE on an aggregate   Lab: Exp 6
-- Relational algebra: γ dow,weekday,hour; COUNT(*),SUM(party_size) (σ Dine_In ∧ Completed (RR))
-- =====================================================================
WITH visits AS (
  SELECT DAYNAME(reserved_start) AS weekday, DAYOFWEEK(reserved_start) AS dow,
         HOUR(reserved_start) AS hour_of_day, party_size
    FROM Rentals_Reservations
   WHERE booking_type = 'Dine_In' AND status = 'Completed'
)
SELECT weekday, hour_of_day, COUNT(*) AS bookings, SUM(party_size) AS guests,
       CASE WHEN COUNT(*) >= 5 THEN 'Peak'
            WHEN COUNT(*) >= 2 THEN 'Normal'
            ELSE 'Quiet' END AS load_band
  FROM visits
 GROUP BY dow, weekday, hour_of_day
 ORDER BY dow, hour_of_day;

-- =====================================================================
-- Q31 · Smallest free table for 5 people tomorrow 18:00–21:00.
-- Concept: calling a stored procedure that returns a result set   Lab: Exp 12
-- Relational algebra: σ is_active ∧ capacity≥5 ∧ fn_table_is_free(…) (Cafe_Tables)
-- =====================================================================
CALL sp_find_free_tables(5, TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '18:00:00'),
                            TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '21:00:00'), FALSE);

-- =====================================================================
-- Q32 · Games for 4 players, youngest 12, at most 90 minutes, with a copy free in that window.
-- Concept: stored procedure with GROUP BY and a function in WHERE   Lab: Exp 12
-- Relational algebra: γ game; COUNT(copy_id) (σ fits ∧ fn_copy_is_free(…) (Board_Games ⋈ Game_Copies))
-- =====================================================================
CALL sp_recommend_games(4, 12, 90, TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '18:00:00'),
                                   TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '21:00:00'));

-- =====================================================================
-- Q33 · Who is holding a game past its end time, and what do they owe so far?
-- Concept: querying a view that calls a stored function   Lab: Exp 9
-- Relational algebra: vw_overdue_rentals
-- =====================================================================
SELECT * FROM vw_overdue_rentals ORDER BY minutes_late DESC;

-- =====================================================================
-- Q34 · Which copies are off the shelf for repair or missing pieces, and what is missing?
-- Concept: querying an aggregating view   Lab: Exp 9
-- Relational algebra: vw_copies_needing_attention
-- =====================================================================
SELECT * FROM vw_copies_needing_attention ORDER BY title;

-- =====================================================================
-- Q35 · Which members would be refused a booking right now, and why (CASE over a derived table)?
-- Concept: searched CASE returning NULL = "no problem", filter on the derived column   Lab: Exp 8
-- Relational algebra: σ blocked_because IS NOT NULL (π customer_id,member,CASE… (Customers))
-- =====================================================================
SELECT *
  FROM (SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS member,
               CASE WHEN c.status <> 'Active'                    THEN CONCAT('Account ', c.status)
                    WHEN c.membership_expiry < CURRENT_DATE       THEN 'Membership expired'
                    WHEN fn_customer_balance(c.customer_id) > 500
                         THEN CONCAT('Owes Rs ', fn_customer_balance(c.customer_id))
               END AS blocked_because
          FROM Customers c) AS t
 WHERE blocked_because IS NOT NULL;

-- =====================================================================
-- Q36 · Reservations in the next 24 hours whose game copy is still out with someone else.
-- Concept: self-join of the bookings table on copy_id   Lab: Exp 7
-- Relational algebra: σ Reserved ∧ start∈[now,now+24h] (ρnxt RR) ⋈ copy_id ρcur(σ Checked_In∨Overdue (RR))
-- =====================================================================
SELECT nxt.booking_id, nxt.reserved_start, bg.title, gc.barcode,
       cur.booking_id AS held_by_booking, cur.status AS held_status, cur.reserved_end AS due_back
  FROM Rentals_Reservations nxt
  JOIN Game_Copies gc          ON gc.copy_id = nxt.copy_id
  JOIN Board_Games bg          ON bg.game_id = gc.game_id
  JOIN Rentals_Reservations cur ON cur.copy_id = nxt.copy_id
                               AND cur.booking_id <> nxt.booking_id
                               AND cur.status IN ('Checked_In', 'Overdue')
 WHERE nxt.status = 'Reserved'
   AND nxt.reserved_start BETWEEN NOW() AND NOW() + INTERVAL 24 HOUR;

-- =====================================================================
-- Q37 · Retire worn copies that have come back short 3 or more times (UPDATE with JOIN to a derived table).
-- Concept: multi-table UPDATE with a derived table   Lab: Exp 4
-- Relational algebra: (DML) target = σ condition∈{Worn,Damaged} ∧ bad_returns≥3 (Game_Copies ⋈ γ copy; COUNT(DISTINCT inspection) (…))
-- =====================================================================
UPDATE Game_Copies gc
  JOIN (SELECT rr.copy_id, COUNT(DISTINCT mp.inspection_id) AS bad_returns
          FROM Missing_Pieces mp
          JOIN Return_Inspections ri   ON ri.inspection_id = mp.inspection_id
          JOIN Rentals_Reservations rr ON rr.booking_id    = ri.booking_id
         GROUP BY rr.copy_id) AS losses ON losses.copy_id = gc.copy_id
   SET gc.status = 'Retired'
 WHERE gc.copy_condition IN ('Worn', 'Damaged')
   AND losses.bad_returns >= 3
   AND gc.status <> 'Rented';

-- =====================================================================
-- Q38 · Buy a new copy of every game that has no copy in service (INSERT … SELECT).
-- Concept: INSERT … SELECT with NOT EXISTS   Lab: Exp 4
-- Relational algebra: (DML) Game_Copies ← Game_Copies ∪ π …(Board_Games − π game (σ Available∨Rented (Game_Copies)))
-- =====================================================================
INSERT INTO Game_Copies (game_id, barcode, acquired_on, copy_condition, status, shelf_location)
SELECT bg.game_id,
       CONCAT('BG', LPAD(bg.game_id, 4, '0'), DATE_FORMAT(CURRENT_DATE, '%y%m%d')),
       CURRENT_DATE, 'New', 'Available', 'NEW-ARR'
  FROM Board_Games bg
 WHERE NOT EXISTS (SELECT 1 FROM Game_Copies gc
                    WHERE gc.game_id = bg.game_id
                      AND gc.status IN ('Available', 'Rented'));

-- =====================================================================
-- Q39 · Add a component or update its price if it already exists (upsert).
-- Concept: INSERT … ON DUPLICATE KEY UPDATE with a row alias (8.0.19+)   Lab: Exp 4
-- Relational algebra: (DML) upsert on the alternate key (game_id, component_name)
-- =====================================================================
INSERT INTO Game_Components (game_id, component_name, qty_per_copy, unit_replacement_cost)
VALUES (1, 'Robber pawn', 1, 40.00) AS new_row
ON DUPLICATE KEY UPDATE unit_replacement_cost = new_row.unit_replacement_cost;

-- =====================================================================
-- Q40 · Purge audit entries older than 2 years for closed bookings (DELETE with subquery).
-- Concept: DELETE with an IN subquery on another table   Lab: Exp 4
-- Relational algebra: (DML) Booking_Audit_Log ← Booking_Audit_Log − σ old ∧ booking∈closed (Booking_Audit_Log)
-- =====================================================================
DELETE FROM Booking_Audit_Log
 WHERE changed_at < NOW() - INTERVAL 2 YEAR
   AND booking_id IN (SELECT booking_id FROM Rentals_Reservations
                       WHERE status IN ('Completed', 'Cancelled', 'No_Show'));

-- =====================================================================
-- Q41 · Which zones hosted a booking in the last 30 days? (DISTINCT, BETWEEN, IN, NOT IN, the `_` wildcard)
-- Concept: DISTINCT, BETWEEN, IN, NOT IN, LIKE with _   Lab: Exp 5
-- Relational algebra: π zone (σ start∈[today−30,today] ∧ status∈{…} ∧ capacity∉{2} ∧ code LIKE '__-0_' (RR ⋈ Cafe_Tables))
-- =====================================================================
SELECT DISTINCT ct.zone
  FROM Rentals_Reservations rr
  JOIN Cafe_Tables ct ON ct.table_id = rr.table_id
 WHERE rr.reserved_start BETWEEN CURRENT_DATE - INTERVAL 30 DAY AND CURRENT_DATE
   AND rr.status IN ('Completed', 'Checked_In')
   AND ct.seating_capacity NOT IN (2)
   AND ct.table_code LIKE '__-0_';          -- each _ matches exactly one character

-- =====================================================================
-- Q42 · Top 5 games by plays, with group-size and session-length extremes.
-- Concept: COUNT, MIN, MAX, AVG, ORDER BY, LIMIT (MySQL's answer to SELECT TOP)   Lab: Exp 6
-- Relational algebra: γ game; COUNT,MIN,MAX,AVG (σ Completed ∧ Dine_In (RR) ⋈ Game_Copies ⋈ Board_Games), first 5
-- =====================================================================
SELECT bg.title, COUNT(rr.booking_id) AS plays,
       MIN(rr.party_size) AS smallest_group, MAX(rr.party_size) AS largest_group,
       ROUND(AVG(rr.duration_minutes)) AS avg_minutes
  FROM Board_Games bg
  JOIN Game_Copies gc          ON gc.game_id = bg.game_id
  JOIN Rentals_Reservations rr ON rr.copy_id = gc.copy_id
 WHERE rr.status = 'Completed' AND rr.booking_type = 'Dine_In'
 GROUP BY bg.game_id, bg.title
 ORDER BY plays DESC
 LIMIT 5;

-- =====================================================================
-- Q43 · Plays per game, last 30 days vs the 30 before, including games played in only one window.
-- Concept: FULL OUTER JOIN emulated as LEFT JOIN ∪ RIGHT JOIN (MySQL has no FULL JOIN)   Lab: Exp 7
-- Relational algebra: recent ⟗ previous = (recent ⟕ previous) ∪ (recent ⟖ previous)
-- =====================================================================
WITH recent AS (
  SELECT gc.game_id, COUNT(*) AS plays
    FROM Rentals_Reservations rr JOIN Game_Copies gc ON gc.copy_id = rr.copy_id
   WHERE rr.status = 'Completed' AND rr.reserved_start >= CURRENT_DATE - INTERVAL 30 DAY
   GROUP BY gc.game_id
), previous AS (
  SELECT gc.game_id, COUNT(*) AS plays
    FROM Rentals_Reservations rr JOIN Game_Copies gc ON gc.copy_id = rr.copy_id
   WHERE rr.status = 'Completed'
     AND rr.reserved_start >= CURRENT_DATE - INTERVAL 60 DAY
     AND rr.reserved_start <  CURRENT_DATE - INTERVAL 30 DAY
   GROUP BY gc.game_id
), full_outer AS (
  SELECT COALESCE(r.game_id, p.game_id) AS game_id,
         IFNULL(p.plays, 0) AS previous_30d, IFNULL(r.plays, 0) AS last_30d
    FROM recent r LEFT JOIN previous p ON p.game_id = r.game_id
  UNION
  SELECT COALESCE(r.game_id, p.game_id), IFNULL(p.plays, 0), IFNULL(r.plays, 0)
    FROM recent r RIGHT JOIN previous p ON p.game_id = r.game_id
)
SELECT bg.title, f.previous_30d, f.last_30d, f.last_30d - f.previous_30d AS change_
  FROM full_outer f JOIN Board_Games bg ON bg.game_id = f.game_id
 ORDER BY change_ DESC;

-- =====================================================================
-- Q44 · For each pending reservation, every table that could seat the group and how many seats would sit empty.
-- Concept: non-equi join (join condition is >=, not =)   Lab: Exp 7
-- Relational algebra: σ Reserved ∧ Dine_In (RR) ⋈ capacity≥party_size ∧ is_active Cafe_Tables (theta join)
-- =====================================================================
SELECT rr.booking_id, rr.party_size, ct.table_code, ct.seating_capacity,
       ct.seating_capacity - rr.party_size AS empty_seats
  FROM Rentals_Reservations rr
  JOIN Cafe_Tables ct
    ON ct.seating_capacity >= rr.party_size      -- join condition is >=, not =
   AND ct.is_active
 WHERE rr.status = 'Reserved' AND rr.booking_type = 'Dine_In'
 ORDER BY rr.booking_id, empty_seats;
