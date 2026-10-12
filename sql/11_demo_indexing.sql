-- =====================================================================
-- 11_demo_indexing.sql
-- Purpose : X1 - see the optimizer use, and not use, an index.
-- Run order: after 08_seed.sql
-- Lab      : CO5 (storage and indexing, B+ trees)
--
-- How InnoDB stores these tables
--   * Every InnoDB table IS a B+ tree on its PRIMARY KEY (the clustered
--     index): the leaf pages hold the whole rows, sorted by the key. A lookup
--     by booking_id walks root -> internal pages -> one leaf (3-4 page reads
--     even for millions of rows).
--   * A secondary index (idx_customer_name, idx_rr_start, ...) is a separate
--     B+ tree whose leaves hold the indexed columns PLUS the primary key.
--     Finding a row through it is two tree walks: secondary tree -> primary
--     key -> clustered tree ("bookmark lookup"). If every column the query
--     needs is in the secondary index, the second walk is skipped: a
--     COVERING index ("Using index" in EXPLAIN).
--   * Composite indexes are sorted left to right, so (last_name, first_name)
--     helps WHERE last_name = ... but not WHERE first_name = ... alone.
--   * Wrapping an indexed column in a function (DATE(reserved_start)) hides
--     the sort order from the optimizer: the predicate is non-sargable and
--     the table is scanned. Rewrite it as a range on the bare column.
-- EXPLAIN columns to read: type (ref/range/ALL), key (index chosen), rows
-- (estimate), Extra. EXPLAIN ANALYZE actually runs the query and shows real
-- row counts and timings per plan step.
-- =====================================================================
USE boardgame_cafe;

-- =====================================================================
-- X1 · See the optimizer use, and not use, an index.
-- Concept: EXPLAIN / EXPLAIN ANALYZE, sargable vs non-sargable predicates   Lab: CO5
-- =====================================================================
-- The B+ tree indexes on the bookings table (PRIMARY = the clustered index)
SHOW INDEX FROM Rentals_Reservations;
-- Uses idx_customer_name (type = ref)
EXPLAIN SELECT customer_id, first_name, phone FROM Customers WHERE last_name = 'Sharma';
-- Same query forced to scan (type = ALL)
EXPLAIN SELECT customer_id, first_name, phone FROM Customers IGNORE INDEX (idx_customer_name)
 WHERE last_name = 'Sharma';
-- Non-sargable: wrapping the column in DATE() hides idx_rr_start
EXPLAIN SELECT * FROM Rentals_Reservations WHERE DATE(reserved_start) = CURRENT_DATE;
-- Sargable range: uses idx_rr_start
EXPLAIN SELECT * FROM Rentals_Reservations
 WHERE reserved_start >= CURRENT_DATE AND reserved_start < CURRENT_DATE + INTERVAL 1 DAY;
-- Real timings for the overlap check behind BR-05
EXPLAIN ANALYZE SELECT COUNT(*) FROM Rentals_Reservations
 WHERE table_id = 3 AND reserved_start < NOW() + INTERVAL 1 DAY AND reserved_end > NOW();
