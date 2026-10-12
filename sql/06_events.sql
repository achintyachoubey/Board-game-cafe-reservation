-- =====================================================================
-- 06_events.sql
-- Purpose : The 3 scheduled events (Appendix B.6). They only run while the
--           event scheduler is ON (docker-compose starts mysqld with
--           --event-scheduler=ON; on a local server this file turns it on,
--           which needs the SYSTEM_VARIABLES_ADMIN privilege).
--             ev_mark_overdue      every 15 min: Checked_In past end + 15 min -> Overdue
--             ev_mark_no_shows     every 15 min: CALL sp_mark_no_shows()      (BR-19)
--             ev_flag_suspensions  daily 02:00 : CALL sp_flag_suspensions()   (cursor)
-- Run order: 06 (after 05_views.sql)
-- Lab      : Additional Exp 2 (PL/SQL-style scheduled jobs for the project)
-- =====================================================================
USE boardgame_cafe;

SET GLOBAL event_scheduler = ON;

CREATE EVENT IF NOT EXISTS ev_mark_overdue
  ON SCHEDULE EVERY 15 MINUTE
  DO UPDATE Rentals_Reservations SET status = 'Overdue'
      WHERE status = 'Checked_In' AND reserved_end < NOW() - INTERVAL 15 MINUTE;

CREATE EVENT IF NOT EXISTS ev_mark_no_shows
  ON SCHEDULE EVERY 15 MINUTE
  DO CALL sp_mark_no_shows();

CREATE EVENT IF NOT EXISTS ev_flag_suspensions
  ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR)
  DO CALL sp_flag_suspensions();
