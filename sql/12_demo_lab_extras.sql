-- =====================================================================
-- 12_demo_lab_extras.sql
-- Purpose : L1 DDL on a sandbox table, L2 operations on a view, L3 more DCL.
-- Run order: after 08_seed.sql (run once per fresh build: L2 inserts a member
--            with a fixed e-mail address)
-- Lab      : Exp 2 (L1), Exp 4 (multi-row INSERT in L1), Exp 9 (L2), Exp 10 (L3)
-- How to run: L2 and L3 contain INTENTIONAL errors (1369, 1142); use
--   mysql --force ... or turn off "Stop Script Execution on Errors" in Workbench.
--   The L3 lines marked "Logged in as report_bot / desk_priya" are meant for a
--   second terminal logged in as that user (mysql -u report_bot -p); as root
--   they would simply succeed. scripts/capture_evidence.py and the tests run
--   them on real connections for those users.
-- =====================================================================
USE boardgame_cafe;

-- =====================================================================
-- L1 · DDL on a sandbox table: CREATE, ALTER (add, modify, constraint, rename column), RENAME, TRUNCATE, DROP (Exp 2).
-- =====================================================================
CREATE TABLE Event_Nights (
  night_id   INT AUTO_INCREMENT PRIMARY KEY,
  theme      VARCHAR(60) NOT NULL,
  night_date DATE NOT NULL
);
ALTER TABLE Event_Nights ADD COLUMN entry_fee DECIMAL(8,2) NOT NULL DEFAULT 0;
ALTER TABLE Event_Nights MODIFY COLUMN theme VARCHAR(100) NOT NULL;
ALTER TABLE Event_Nights ADD CONSTRAINT chk_event_fee CHECK (entry_fee >= 0);
ALTER TABLE Event_Nights RENAME COLUMN night_date TO event_date;
RENAME TABLE Event_Nights TO Theme_Nights;
INSERT INTO Theme_Nights (theme, event_date, entry_fee)                    -- multi-row INSERT (Exp 4)
VALUES ('Catan tournament', CURRENT_DATE + INTERVAL 7 DAY, 200.00),
       ('Werewolf Friday',  CURRENT_DATE + INTERVAL 4 DAY,   0.00);
DESCRIBE Theme_Nights;
SELECT * FROM Theme_Nights;
TRUNCATE TABLE Theme_Nights;   -- DDL: removes all rows, resets AUTO_INCREMENT, cannot be rolled back
DROP TABLE Theme_Nights;
CREATE DATABASE IF NOT EXISTS cafe_sandbox;
DROP DATABASE cafe_sandbox;

-- =====================================================================
-- L2 · Operations on a view: SELECT, INSERT and UPDATE through vw_active_members,
--      and the CHECK OPTION refusing a change that would hide the row (Exp 9).
-- =====================================================================
SELECT customer_id, first_name, tier_id, status FROM vw_active_members LIMIT 5;
INSERT INTO vw_active_members (first_name, last_name, email, phone, date_of_birth,
                               tier_id, membership_expiry, status)
VALUES ('Lavanya', 'Rao', 'lavanya.rao@mail.test', '9876501234', '2001-04-09',
        2, CURRENT_DATE + INTERVAL 1 YEAR, 'Active');                      -- lands in Customers
UPDATE vw_active_members SET tier_id = 3 WHERE email = 'lavanya.rao@mail.test';
-- @expect-error 1369
UPDATE vw_active_members SET status = 'Suspended'
 WHERE email = 'lavanya.rao@mail.test';          -- ERROR 1369: CHECK OPTION failed
SELECT customer_id, first_name, last_name, tier_id, status, join_date
  FROM Customers WHERE email = 'lavanya.rao@mail.test';    -- the base table row: Gold, still Active

-- =====================================================================
-- L3 · More DCL: WITH GRANT OPTION, REVOKE ALL, and proving least privilege (Exp 10).
-- =====================================================================
GRANT SELECT ON boardgame_cafe.vw_game_catalog TO 'owner_ravi'@'localhost' WITH GRANT OPTION;
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'report_bot'@'localhost';
SHOW GRANTS FOR 'report_bot'@'localhost';     -- the analyst role is still listed
-- Logged in as report_bot:
-- @as report_bot
SELECT COUNT(*) FROM boardgame_cafe.vw_game_popularity;   -- allowed through the role
-- @expect-error 1142
SELECT COUNT(*) FROM boardgame_cafe.Customers;            -- ERROR 1142: SELECT command denied
-- Logged in as desk_priya:
-- @as desk_priya
CALL boardgame_cafe.sp_find_free_tables(4, NOW() + INTERVAL 1 DAY, NOW() + INTERVAL 1 DAY + INTERVAL 2 HOUR, FALSE);  -- allowed
-- @expect-error 1142
INSERT INTO boardgame_cafe.Payments (booking_id, amount, method) VALUES (1, 1, 'UPI');   -- ERROR 1142: INSERT denied
-- Back as the administrator: REVOKE ALL did not remove the role; revoking the ROLE does.
-- @as admin
SHOW GRANTS FOR 'owner_ravi'@'localhost';
REVOKE 'analyst' FROM 'report_bot'@'localhost';
SHOW GRANTS FOR 'report_bot'@'localhost';     -- only USAGE left: no access at all
GRANT 'analyst' TO 'report_bot'@'localhost';  -- restore the demo account
SET DEFAULT ROLE ALL TO 'report_bot'@'localhost';
