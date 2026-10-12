-- =====================================================================
-- 07_roles.sql
-- Purpose : Roles, privileges and demo login accounts (Appendix B.7).
--             cafe_admin  - everything on the database
--             front_desk  - SELECT on four views, SELECT/INSERT/UPDATE on
--                           vw_active_members, EXECUTE on the workflow
--                           procedures; NO direct table writes. Procedures
--                           run with DEFINER rights, so the desk can book
--                           without being able to touch the tables.
--             analyst     - SELECT on three reporting views only
-- Users    : desk_priya (front_desk), owner_ravi (cafe_admin),
--            report_bot (analyst).
--            >>> 'ChangeMe#2026' is a DEMO PASSWORD for the classroom. <<<
--            scripts/build_db.py replaces it with DEMO_USER_PASSWORD from
--            .env when that is set, and replaces the host part 'localhost'
--            with DEMO_USER_HOST (use % when the server runs in Docker).
-- Run order: 07 (after 06_events.sql)
-- Lab      : Exp 10 (GRANT / REVOKE)
-- =====================================================================
USE boardgame_cafe;

CREATE ROLE IF NOT EXISTS 'cafe_admin', 'front_desk', 'analyst';

GRANT ALL PRIVILEGES ON boardgame_cafe.* TO 'cafe_admin';

GRANT SELECT ON boardgame_cafe.vw_game_catalog         TO 'front_desk';
GRANT SELECT ON boardgame_cafe.vw_active_bookings      TO 'front_desk';
GRANT SELECT ON boardgame_cafe.vw_available_copies_now TO 'front_desk';
GRANT SELECT ON boardgame_cafe.vw_overdue_rentals      TO 'front_desk';
GRANT SELECT, INSERT, UPDATE ON boardgame_cafe.vw_active_members TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_create_reservation TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_check_in           TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_check_out          TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_cancel_booking     TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_find_free_tables   TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_recommend_games    TO 'front_desk';
GRANT EXECUTE ON PROCEDURE boardgame_cafe.sp_record_payment     TO 'front_desk';

GRANT SELECT ON boardgame_cafe.vw_game_popularity       TO 'analyst';
GRANT SELECT ON boardgame_cafe.vw_table_utilization_30d TO 'analyst';
GRANT SELECT ON boardgame_cafe.vw_customer_balances     TO 'analyst';

CREATE USER IF NOT EXISTS 'desk_priya'@'localhost' IDENTIFIED BY 'ChangeMe#2026';
CREATE USER IF NOT EXISTS 'owner_ravi'@'localhost' IDENTIFIED BY 'ChangeMe#2026';
CREATE USER IF NOT EXISTS 'report_bot'@'localhost' IDENTIFIED BY 'ChangeMe#2026';
GRANT 'front_desk' TO 'desk_priya'@'localhost';
GRANT 'cafe_admin' TO 'owner_ravi'@'localhost';
GRANT 'analyst'    TO 'report_bot'@'localhost';
SET DEFAULT ROLE ALL TO 'desk_priya'@'localhost', 'owner_ravi'@'localhost', 'report_bot'@'localhost';

-- Demo: take away cancellations from the front desk, then check
REVOKE EXECUTE ON PROCEDURE boardgame_cafe.sp_cancel_booking FROM 'front_desk';
SHOW GRANTS FOR 'desk_priya'@'localhost' USING 'front_desk';
