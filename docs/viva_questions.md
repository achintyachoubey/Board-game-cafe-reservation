# Viva questions and answers

Short, exam-ready answers, each tied to this project. Grouped by course outcome.

## Project and design (CO1)

1. **What is the project in one sentence?**
   A MySQL database for a board game café in which members book tables and borrow game boxes
   (to play in the café or take home), with every business rule enforced inside the database.

2. **How is it like a Library Management System, and how is it different?**
   Books → board games, book copies → game boxes, library cards → memberships, issue/return →
   take-home rental. New: a booking also reserves a **table** for a **time window**, the party must
   fit both the table and the game's player range, games have age limits, and every return is
   inspected for missing pieces.

3. **Why are there both `Board_Games` and `Game_Copies`?**
   A title (Catan: 3–4 players, 10+) is one thing; each physical box has its own barcode, condition
   and status. Mixing them would repeat the title facts per box and could not express two boxes in
   different condition.

4. **Why is `Game_Components` a weak entity?**
   A component ("Robber pawn") only exists as part of a game and is identified by (game, name). It
   has an identifying relationship to `Board_Games`, total participation and `ON DELETE CASCADE`.

5. **Where are specialization, generalization and aggregation in your design?**
   Specialization: a booking is either Dine_In or Take_Home (disjoint, total), mapped to one table
   with `booking_type` + a CHECK. Generalization: Customer and Staff could generalize to Person
   (not implemented — too few shared attributes). Aggregation: inspections and payments relate to
   the *booking relationship* itself, so BOOKS is aggregated and becomes `Rentals_Reservations`.

6. **Give one derived, one multivalued and one composite attribute.**
   Derived: age (from date_of_birth), `duration_minutes`, `total_amount`, balance. Multivalued: a
   game's categories (→ `Board_Game_Categories`). Composite: name (first_name, last_name).

7. **Why `Cafe_Tables` and `Rentals_Reservations` instead of the proposal's names?**
   `TABLES` is a reserved word; `&` is not allowed in an unquoted identifier.

## SQL (CO2)

8. **INNER vs LEFT vs RIGHT join?**
   INNER keeps matching pairs; LEFT keeps every left row (NULLs where nothing matches); RIGHT the
   same for the right side. Q09 uses RIGHT JOIN so staff with no inspections still appear with 0.

9. **How do you write a FULL OUTER JOIN in MySQL?**
   `LEFT JOIN … UNION … RIGHT JOIN` (Q43). Writing `full join` silently becomes an inner join with
   `full` as a table alias.

10. **What is a non-equi join? Example?**
    A join on a condition other than equality — Q44 joins reservations to tables with
    `seating_capacity >= party_size`.

11. **Correlated subquery example?**
    Q18: for each member, `reserved_start = (SELECT MAX(...) WHERE r2.customer_id = c.customer_id)`.

12. **How does Q20 express "played every Party game"?**
    Relational division with double NOT EXISTS: there is no Party game for which there is no
    completed booking by this member.

13. **RANK vs DENSE_RANK vs ROW_NUMBER?**
    With ties RANK leaves gaps (1, 1, 3), DENSE_RANK does not (1, 1, 2), ROW_NUMBER numbers every
    row uniquely (1, 2, 3). Q24, Q25.

14. **What does a recursive CTE do in Q29?**
    Generates the half-hour slots 10:00–22:30 by repeatedly adding 30 minutes until the stop
    condition; CROSS JOIN with tables gives the availability grid.

15. **WHERE vs HAVING?**
    WHERE filters rows before GROUP BY; HAVING filters groups after aggregation (Q11).

16. **When is a view updatable, and what does WITH CHECK OPTION add?**
    One base table, no aggregates/DISTINCT/GROUP BY/UNION. CHECK OPTION rejects changes that would
    make the row disappear from the view: `UPDATE vw_active_members SET status = 'Suspended'` →
    ERROR 1369.

17. **Procedure vs function?**
    A function returns one value and can be used inside SQL (`fn_customer_balance(id)` in Q35); a
    procedure is CALLed, can return result sets, has OUT parameters and can manage transactions
    (`sp_create_reservation`).

18. **Why do the validation checks live in a trigger and not only in the procedure?**
    A trigger cannot be bypassed: direct INSERTs, procedures and bulk loads all pass through
    `trg_rr_before_insert` → `sp_validate_booking`. Checks that depend on "now" (BR-13, BR-14) are in
    the procedure so that historical rows can be loaded.

19. **How is a business-rule error reported?**
    `SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-05: …'` → the client receives ERROR 1644 with the
    message; tests match on the `BR-xx` prefix.

20. **What are the 10 triggers for?**
    BEFORE INSERT/UPDATE on bookings (validate, price, lifecycle), AFTER INSERT/UPDATE (audit, copy
    → Rented), BEFORE DELETE (keep history), BEFORE/AFTER INSERT on inspections and missing pieces
    (validate, price, copy status, damage fee), BEFORE INSERT on payments (PAY-01/02).

21. **What does the cursor in `sp_flag_suspensions` do?**
    Walks every Active/Suspended member: suspends one owing > ₹2,000, reactivates a suspended one
    owing nothing. DECLARE CURSOR, CONTINUE HANDLER FOR NOT FOUND, OPEN, FETCH, LEAVE, CLOSE.

## Normalization (CO3)

22. **State Armstrong's axioms and derive booking_id → discount_pct.**
    Reflexivity, augmentation, transitivity. booking_id → customer_id → tier_id → discount_pct by
    transitivity (twice).

23. **What is the closure of booking_id and what does it show?**
    Every attribute of the 1NF booking relation (customer, tier, table, copy, game, inspection
    facts), so booking_id is a superkey; being a single attribute it is a candidate key.

24. **What is a canonical cover? Give an extraneous attribute.**
    An equivalent FD set with single-attribute right sides, no extraneous attributes and no
    redundant FDs. In {customer_id, email} → first_name, email is extraneous because customer_id →
    first_name already holds.

25. **Which 3NF violation did you remove first?**
    booking_id → customer_id → phone (transitive): member facts moved to `Customers`; likewise
    table, tier, copy and game facts.

26. **3NF vs BCNF; a 3NF-but-not-BCNF example?**
    BCNF requires every determinant to be a superkey. Coaching(zone, category, guru) with
    {zone, category} → guru and guru → category is 3NF (category is prime) but not BCNF; decomposing
    loses {zone, category} → guru (not dependency preserving).

27. **How do you prove a decomposition is lossless?**
    For R1, R2: R1 ∩ R2 must be a superkey of R1 or R2. Bookings ∩ Customers = {customer_id}, the key
    of Customers.

28. **What is an MVD and where would 4NF be violated?**
    game_id ↠ category and game_id ↠ component_name are independent multivalued facts; storing them
    in one relation `GameInfo(game_id, category, component_name)` needs every combination (230 rows
    in the seed). 4NF splits it into the two tables we have (167 rows).

29. **Is storing `total_amount` a normalization violation?**
    It is derived data (a non-key → non-key dependency), but it is a STORED generated column: the
    engine recomputes it on every write, so it can never be inconsistent. The balance, which would
    depend on many rows, is never stored.

30. **Why is `Missing_Pieces.charge` stored if it equals qty × unit cost?**
    It is a snapshot of the price at inspection time; computing it from today's
    `unit_replacement_cost` would change old bills when prices change.

## Transactions and concurrency (CO4)

31. **Explain ACID with examples from the project.**
    Atomicity: `sp_check_out` — inspection, missing pieces, late fee and status commit together or
    not at all (TC-22). Consistency: constraints and triggers. Isolation: READ COMMITTED + row locks
    in `sp_create_reservation`. Durability: InnoDB redo log and doublewrite buffer.

32. **What does SAVEPOINT do in T1?**
    Marks a point inside a transaction; `ROLLBACK TO SAVEPOINT` undoes only what came after it. The
    ₹200 payment survives, the failed ₹99,999 payment does not.

33. **How do you stop two desks double-booking a table?**
    `sp_create_reservation` locks the table's row with `SELECT … FOR UPDATE` before checking for
    overlap. The second desk waits; after the first commits, its READ COMMITTED read sees the new
    booking and fails with BR-05 (T2, TC-31: of 4 simultaneous desks exactly 1 succeeds).

34. **Why READ COMMITTED inside `sp_create_reservation`?**
    The overlap check must see bookings committed while it was waiting for the lock. Under
    REPEATABLE READ a plain read could use an older snapshot.

35. **Non-repeatable read — show it.**
    T3: under READ COMMITTED the same SELECT inside one transaction returned 150.00 then 160.00
    after another session committed an update; under REPEATABLE READ it returned the same value
    twice.

36. **What is two-phase locking? Where is it?**
    A transaction acquires locks in a growing phase and releases them only in a shrinking phase;
    strict 2PL (InnoDB) releases all at COMMIT/ROLLBACK. The booking procedure's locks are held
    until its COMMIT, which makes concurrent bookings serializable for that table.

37. **What is a deadlock and how did you show it?**
    A cycle of transactions each waiting for a lock the other holds. T4: A locks copy 1 then wants
    2, B locks 2 then wants 1. InnoDB detects the cycle and rolls one back with ERROR 1213. Prevention:
    always lock in the same order (table → copy → customer).

38. **Is a schedule serializable if it is conflict-equivalent to a serial one?**
    Yes — conflict serializability (an acyclic precedence graph) implies serializability.

## Storage and indexing (CO5)

39. **How does InnoDB store a table?**
    As a B+ tree clustered on the primary key: leaf pages hold whole rows in key order. Secondary
    indexes are separate B+ trees whose leaves hold the indexed columns plus the primary key.

40. **Why does `DATE(reserved_start) = CURRENT_DATE` not use the index?**
    The function hides the column's sort order (non-sargable) → full scan (`type = ALL`). The range
    `reserved_start >= CURRENT_DATE AND reserved_start < CURRENT_DATE + INTERVAL 1 DAY` uses
    `idx_rr_start` (`type = range`).

41. **What is a covering index? Example?**
    An index containing every column a query needs, so the clustered tree is not visited. The BR-05
    overlap count reads only `table_id, reserved_start, reserved_end` — all in `idx_rr_table_window`.

42. **Why is `idx_customer_name` (last_name, first_name) useless for `WHERE first_name = …`?**
    A composite B+ tree is sorted by the leftmost column first (leftmost-prefix rule).

## Security

43. **How does the front desk create bookings without INSERT on the table?**
    The role has only EXECUTE on the procedures; procedures run with definer rights (SQL SECURITY
    DEFINER), so the procedure's owner performs the INSERT.

44. **Does REVOKE ALL remove a role?**
    No — L3 shows the analyst role still listed after `REVOKE ALL PRIVILEGES, GRANT OPTION`; it is
    removed with `REVOKE 'analyst' FROM 'report_bot'@…`.
