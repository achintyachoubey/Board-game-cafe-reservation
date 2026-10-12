-- =====================================================================
-- 00_drop_all.sql
-- Purpose : Remove everything this project creates so a rebuild starts clean:
--           the database, the three roles and the three demo users.
--           Idempotent: safe to run when nothing exists yet.
-- Run order: 00 (first). Then 01 -> 08.
-- Lab      : Exp 2 (DDL: DROP DATABASE / DROP ROLE / DROP USER)
-- =====================================================================

DROP DATABASE IF EXISTS boardgame_cafe;

DROP USER IF EXISTS 'desk_priya'@'localhost', 'owner_ravi'@'localhost', 'report_bot'@'localhost';
DROP ROLE IF EXISTS 'cafe_admin', 'front_desk', 'analyst';
