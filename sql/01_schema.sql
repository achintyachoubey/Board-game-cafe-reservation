-- =====================================================================
-- 01_schema.sql
-- Purpose : Create the boardgame_cafe database and its 14 tables
--           (Appendix A of the specification, verbatim, plus COMMENT
--           clauses on every table and column for the data dictionary).
-- Run order: 01 (after 00_drop_all.sql)
-- Lab      : Exp 1 (ER -> relational model, keys), Exp 2 (CREATE),
--            Exp 3 (PRIMARY KEY / FOREIGN KEY / CHECK / NOT NULL / DEFAULT / UNIQUE)
-- Notes    : * TABLES is a reserved word, so the student's "Tables" entity
--              is Cafe_Tables.
--            * "&" is illegal in an unquoted identifier, so the bridge
--              "Rentals_&_Reservations" is Rentals_Reservations.
--            * Condition belongs to the physical box, not the title, so it
--              lives in Game_Copies.copy_condition (CONDITION is reserved too).
-- =====================================================================

CREATE DATABASE IF NOT EXISTS boardgame_cafe
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE boardgame_cafe;

-- 1. Lookup: membership tiers
CREATE TABLE Membership_Tiers (
  tier_id                TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY
                         COMMENT 'Surrogate key of the tier',
  tier_name              VARCHAR(20)  NOT NULL UNIQUE
                         COMMENT 'Basic / Silver / Gold (alternate key)',
  annual_fee             DECIMAL(8,2) NOT NULL DEFAULT 0
                         COMMENT 'Yearly membership fee in rupees',
  max_concurrent_rentals TINYINT UNSIGNED NOT NULL
                         COMMENT 'Active bookings holding a game copy allowed at once (BR-12)',
  max_session_hours      TINYINT UNSIGNED NOT NULL
                         COMMENT 'Longest Dine_In session in hours (BR-11)',
  max_takehome_days      TINYINT UNSIGNED NOT NULL
                         COMMENT 'Longest Take_Home rental in days (BR-11)',
  discount_pct           DECIMAL(5,2) NOT NULL DEFAULT 0
                         COMMENT 'Percent taken off the base charge only, never off fees',
  CONSTRAINT chk_tier_discount CHECK (discount_pct BETWEEN 0 AND 50),
  CONSTRAINT chk_tier_limits   CHECK (max_concurrent_rentals >= 1
                                      AND max_session_hours BETWEEN 1 AND 13
                                      AND max_takehome_days >= 1)
) COMMENT = 'Membership levels and the limits/discount each one grants';

-- 2. Core: customers (members)
CREATE TABLE Customers (
  customer_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY
                    COMMENT 'Surrogate key: the membership card number',
  first_name        VARCHAR(50)  NOT NULL COMMENT 'Given name',
  last_name         VARCHAR(50)  NOT NULL COMMENT 'Family name (indexed with first_name for look-ups)',
  email             VARCHAR(120) NOT NULL UNIQUE
                    COMMENT 'Alternate key; must look like x@y.z (chk_customer_email)',
  phone             VARCHAR(15)  NOT NULL UNIQUE
                    COMMENT 'Alternate key; 10-14 digits, optional leading + (chk_customer_phone)',
  date_of_birth     DATE NOT NULL
                    COMMENT 'Stored instead of age; age is derived by fn_customer_age (BR-03, BR-04)',
  tier_id           TINYINT UNSIGNED NOT NULL COMMENT 'FK to Membership_Tiers',
  join_date         DATE NOT NULL DEFAULT (CURRENT_DATE) COMMENT 'Date the membership started',
  membership_expiry DATE NOT NULL
                    COMMENT 'Last valid day; a booking must end on or before it (BR-13)',
  status            ENUM('Active','Suspended','Inactive') NOT NULL DEFAULT 'Active'
                    COMMENT 'Only Active members may book (BR-13); set by sp_flag_suspensions',
  CONSTRAINT fk_customer_tier FOREIGN KEY (tier_id)
    REFERENCES Membership_Tiers(tier_id) ON DELETE RESTRICT,
  CONSTRAINT chk_customer_email  CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT chk_customer_phone  CHECK (REGEXP_LIKE(phone, '^[+]?[0-9]{10,14}$')),
  CONSTRAINT chk_customer_dob    CHECK (date_of_birth < join_date),
  CONSTRAINT chk_customer_expiry CHECK (membership_expiry >= join_date),
  INDEX idx_customer_name (last_name, first_name)
) COMMENT = 'Cafe members (the library-card holders of the classic design)';

-- 3. Staff
CREATE TABLE Staff (
  staff_id  SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key',
  full_name VARCHAR(100) NOT NULL COMMENT 'Staff member name',
  role      ENUM('Manager','Game_Guru','Front_Desk') NOT NULL COMMENT 'Job role',
  email     VARCHAR(120) NOT NULL UNIQUE COMMENT 'Work e-mail (alternate key)',
  hired_on  DATE NOT NULL COMMENT 'Date of joining',
  is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'FALSE once the person has left'
) COMMENT = 'Employees; they inspect returned games (Return_Inspections.inspected_by)';

-- 4. Lookup: categories
CREATE TABLE Game_Categories (
  category_id   SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key',
  category_name VARCHAR(40) NOT NULL UNIQUE COMMENT 'Strategy, Party, Family, Co-op, ...'
) COMMENT = 'Game genres; a game can be in several (multivalued attribute -> M:N table)';

-- 5. Core: board game titles
CREATE TABLE Board_Games (
  game_id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key of the title',
  title            VARCHAR(120) NOT NULL COMMENT 'Game title (unique together with publisher)',
  publisher        VARCHAR(80)  NOT NULL COMMENT 'Publisher name',
  year_published   SMALLINT UNSIGNED NULL COMMENT 'Year of first edition; NULL if unknown',
  min_players      TINYINT UNSIGNED NOT NULL COMMENT 'Fewest players the game supports (BR-02)',
  max_players      TINYINT UNSIGNED NOT NULL COMMENT 'Most players the game supports (BR-02)',
  min_age          TINYINT UNSIGNED NOT NULL COMMENT 'Publisher minimum age in years (BR-03)',
  avg_play_minutes SMALLINT UNSIGNED NOT NULL COMMENT 'Typical length of one game in minutes',
  complexity       DECIMAL(2,1) NOT NULL          -- 1.0 (light) to 5.0 (heavy)
                   COMMENT 'Rules weight from 1.0 (light) to 5.0 (heavy)',
  hourly_rate      DECIMAL(8,2) NOT NULL          -- in-cafe play, per hour
                   COMMENT 'Rupees per hour for Dine_In play (pricing, BR-16)',
  daily_rate       DECIMAL(8,2) NOT NULL          -- take-home, per day
                   COMMENT 'Rupees per started day for Take_Home (pricing, BR-16)',
  replacement_cost DECIMAL(10,2) NOT NULL COMMENT 'Rupees to buy a whole new box',
  CONSTRAINT uq_game_title_publisher UNIQUE (title, publisher),
  CONSTRAINT chk_game_players    CHECK (min_players >= 1 AND max_players >= min_players
                                        AND max_players <= 20),
  CONSTRAINT chk_game_age        CHECK (min_age BETWEEN 3 AND 21),
  CONSTRAINT chk_game_complexity CHECK (complexity BETWEEN 1.0 AND 5.0),
  CONSTRAINT chk_game_rates      CHECK (hourly_rate >= 0 AND daily_rate >= hourly_rate
                                        AND replacement_cost > 0),
  CONSTRAINT chk_game_year       CHECK (year_published IS NULL
                                        OR year_published BETWEEN 1800 AND 2100)
) COMMENT = 'Game titles (the "books"); facts that are true for every box of the title';

-- 6. M:N bridge: games <-> categories
CREATE TABLE Board_Game_Categories (
  game_id     INT UNSIGNED NOT NULL COMMENT 'FK to Board_Games',
  category_id SMALLINT UNSIGNED NOT NULL COMMENT 'FK to Game_Categories',
  PRIMARY KEY (game_id, category_id),
  CONSTRAINT fk_bgc_game     FOREIGN KEY (game_id)
    REFERENCES Board_Games(game_id) ON DELETE CASCADE,
  CONSTRAINT fk_bgc_category FOREIGN KEY (category_id)
    REFERENCES Game_Categories(category_id) ON DELETE CASCADE
) COMMENT = 'Which categories each game belongs to (M:N)';

-- 7. Physical copies (the "book copies")
CREATE TABLE Game_Copies (
  copy_id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key of the physical box',
  game_id        INT UNSIGNED NOT NULL COMMENT 'FK to Board_Games: which title this box is',
  barcode        CHAR(12) NOT NULL UNIQUE COMMENT 'Sticker on the box (alternate key)',
  acquired_on    DATE NOT NULL COMMENT 'Purchase date',
  copy_condition ENUM('New','Good','Fair','Worn','Damaged') NOT NULL DEFAULT 'New'
                 COMMENT 'Wear of this box; updated by every return inspection (BR-18)',
  status         ENUM('Available','Rented','Under_Repair','Missing_Pieces','Retired')
                 NOT NULL DEFAULT 'Available'
                 COMMENT 'Shelf state; only Available/Rented copies can be booked (BR-07, BR-18)',
  shelf_location VARCHAR(10) NOT NULL COMMENT 'Shelf code where the box is kept',
  CONSTRAINT fk_copy_game FOREIGN KEY (game_id)
    REFERENCES Board_Games(game_id) ON DELETE RESTRICT,
  INDEX idx_copy_game_status (game_id, status)
) COMMENT = 'Physical boxes of a title (the "book copies"); condition lives here, not on the title';

-- 8. Expected pieces per title
CREATE TABLE Game_Components (
  component_id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key',
  game_id               INT UNSIGNED NOT NULL COMMENT 'Owner title (weak entity: identified with component_name)',
  component_name        VARCHAR(80) NOT NULL COMMENT 'Piece name, e.g. Robber pawn (partial key)',
  qty_per_copy          SMALLINT UNSIGNED NOT NULL COMMENT 'How many of this piece a complete box holds (BR-17)',
  unit_replacement_cost DECIMAL(8,2) NOT NULL COMMENT 'Rupees charged per missing piece (BR-17)',
  CONSTRAINT uq_component UNIQUE (game_id, component_name),
  CONSTRAINT fk_component_game FOREIGN KEY (game_id)
    REFERENCES Board_Games(game_id) ON DELETE CASCADE,
  CONSTRAINT chk_component CHECK (qty_per_copy >= 1 AND unit_replacement_cost >= 0)
) COMMENT = 'Expected contents of a box of each title (weak entity of Board_Games)';

-- 9. Core: cafe tables
CREATE TABLE Cafe_Tables (
  table_id         SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key',
  table_code       VARCHAR(8) NOT NULL UNIQUE        -- e.g. MH-01
                   COMMENT 'Floor label such as MH-01 (alternate key)',
  zone             ENUM('Main_Hall','Quiet_Corner','Party_Room','Patio') NOT NULL
                   COMMENT 'Area of the cafe',
  seating_capacity TINYINT UNSIGNED NOT NULL COMMENT 'Seats at the table; party size may not exceed it (BR-01)',
  hourly_rate      DECIMAL(8,2) NOT NULL COMMENT 'Rupees per hour for the table (pricing, BR-16)',
  is_accessible    BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Wheelchair accessible',
  is_active        BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'FALSE = out of service, cannot be booked (BR-01)',
  CONSTRAINT chk_table_capacity CHECK (seating_capacity BETWEEN 2 AND 12),
  CONSTRAINT chk_table_rate     CHECK (hourly_rate >= 0)
) COMMENT = 'Physical cafe tables ("Tables" in the proposal; TABLES is a reserved word)';

-- 10. Core bridge: rentals and reservations
CREATE TABLE Rentals_Reservations (
  booking_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key of the booking',
  customer_id      INT UNSIGNED NOT NULL COMMENT 'FK: the member who booked',
  table_id         SMALLINT UNSIGNED NULL COMMENT 'FK: table for Dine_In; NULL for Take_Home (BR-08)',
  copy_id          INT UNSIGNED NULL COMMENT 'FK: game box; required for Take_Home, optional for Dine_In (BR-08)',
  booking_type     ENUM('Dine_In','Take_Home') NOT NULL
                   COMMENT 'Specialization: play at a table or take the box home (BR-08)',
  party_size       TINYINT UNSIGNED NULL COMMENT 'Guests at the table; Dine_In only (BR-01, BR-02)',
  reserved_start   DATETIME NOT NULL COMMENT 'Booked start (BR-09, BR-10, BR-14)',
  reserved_end     DATETIME NOT NULL COMMENT 'Booked end; late fees run from here (BR-09, BR-16)',
  duration_minutes INT AS (TIMESTAMPDIFF(MINUTE, reserved_start, reserved_end)) STORED
                   COMMENT 'Derived: booked length in minutes (generated column)',
  checked_in_at    DATETIME NULL COMMENT 'Actual arrival / pick-up time',
  returned_at      DATETIME NULL COMMENT 'Actual end / return time (BR-16)',
  status           ENUM('Reserved','Checked_In','Overdue','Completed','Cancelled','No_Show')
                   NOT NULL DEFAULT 'Reserved' COMMENT 'Lifecycle state (BR-15); audited by trigger',
  base_charge      DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Rupees for the booked time, set by trigger',
  discount_amount  DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Tier discount on base_charge only',
  late_fee         DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Rupees from fn_calculate_late_fee (BR-16)',
  damage_fee       DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Sum of Missing_Pieces charges (BR-17)',
  cancellation_fee DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Rs 100 late cancel / no-show (BR-19)',
  total_amount     DECIMAL(10,2) AS (base_charge - discount_amount + late_fee
                                     + damage_fee + cancellation_fee) STORED
                   COMMENT 'Derived: amount due for the booking (generated column)',
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When the row was written',
  CONSTRAINT fk_rr_customer FOREIGN KEY (customer_id)
    REFERENCES Customers(customer_id) ON DELETE RESTRICT,
  CONSTRAINT fk_rr_table FOREIGN KEY (table_id)
    REFERENCES Cafe_Tables(table_id) ON DELETE RESTRICT,
  CONSTRAINT fk_rr_copy FOREIGN KEY (copy_id)
    REFERENCES Game_Copies(copy_id) ON DELETE RESTRICT,
  CONSTRAINT chk_rr_window CHECK (reserved_end > reserved_start),
  CONSTRAINT chk_booking_type_shape CHECK (
       (booking_type = 'Dine_In'   AND table_id IS NOT NULL
                                   AND party_size IS NOT NULL AND party_size >= 1)
    OR (booking_type = 'Take_Home' AND table_id IS NULL
                                   AND copy_id IS NOT NULL AND party_size IS NULL)),
  CONSTRAINT chk_rr_dinein_slots CHECK (booking_type <> 'Dine_In' OR (
         MINUTE(reserved_start) IN (0,30) AND MINUTE(reserved_end) IN (0,30)
     AND SECOND(reserved_start) = 0     AND SECOND(reserved_end) = 0
     AND TIMESTAMPDIFF(MINUTE, reserved_start, reserved_end) >= 60)),
  CONSTRAINT chk_rr_actuals CHECK (checked_in_at IS NULL OR returned_at IS NULL
                                   OR returned_at >= checked_in_at),
  CONSTRAINT chk_rr_money CHECK (base_charge >= 0 AND discount_amount BETWEEN 0 AND base_charge
                                 AND late_fee >= 0 AND damage_fee >= 0
                                 AND cancellation_fee >= 0),
  INDEX idx_rr_table_window   (table_id, reserved_start, reserved_end),
  INDEX idx_rr_copy_window    (copy_id, reserved_start, reserved_end),
  INDEX idx_rr_customer_status(customer_id, status),
  INDEX idx_rr_status_end     (status, reserved_end),
  INDEX idx_rr_start          (reserved_start)
) COMMENT = 'The bridge "Rentals_&_Reservations": who booked which table and/or game box, when';

-- 11. One inspection per returned booking
CREATE TABLE Return_Inspections (
  inspection_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key',
  booking_id          INT UNSIGNED NOT NULL UNIQUE
                      COMMENT 'FK + UNIQUE: at most one inspection per booking (1 : 0..1)',
  inspected_by        SMALLINT UNSIGNED NOT NULL COMMENT 'FK: staff member who checked the box',
  inspected_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When the box was checked',
  condition_on_return ENUM('New','Good','Fair','Worn','Damaged') NOT NULL
                      COMMENT 'Condition found; copied to Game_Copies.copy_condition (BR-18)',
  notes               VARCHAR(255) NULL COMMENT 'Free-text remarks',
  CONSTRAINT fk_insp_booking FOREIGN KEY (booking_id)
    REFERENCES Rentals_Reservations(booking_id) ON DELETE RESTRICT,
  CONSTRAINT fk_insp_staff FOREIGN KEY (inspected_by)
    REFERENCES Staff(staff_id) ON DELETE RESTRICT
) COMMENT = 'Check of a returned game box (relationship set Booking treated as an entity: aggregation)';

-- 12. Missing pieces found in an inspection (M:N with attributes)
CREATE TABLE Missing_Pieces (
  inspection_id INT UNSIGNED NOT NULL COMMENT 'FK to Return_Inspections',
  component_id  INT UNSIGNED NOT NULL COMMENT 'FK to Game_Components; must belong to the returned game (BR-17)',
  qty_missing   SMALLINT UNSIGNED NOT NULL COMMENT 'Pieces missing; at most qty_per_copy (BR-17)',
  charge        DECIMAL(10,2) NOT NULL     -- snapshot: qty x unit cost at the time
                COMMENT 'Rupees charged = qty_missing x unit cost, frozen at inspection time (BR-17)',
  restocked_at  DATETIME NULL              -- set when staff replace the pieces
                COMMENT 'When staff replaced the pieces (sp_restock_copy); NULL = still missing',
  PRIMARY KEY (inspection_id, component_id),
  CONSTRAINT fk_mp_inspection FOREIGN KEY (inspection_id)
    REFERENCES Return_Inspections(inspection_id) ON DELETE CASCADE,
  CONSTRAINT fk_mp_component FOREIGN KEY (component_id)
    REFERENCES Game_Components(component_id) ON DELETE RESTRICT,
  CONSTRAINT chk_mp CHECK (qty_missing >= 1 AND charge >= 0)
) COMMENT = 'Pieces found missing in an inspection, with the charge at that time (M:N with attributes)';

-- 13. Payments against a booking
CREATE TABLE Payments (
  payment_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key',
  booking_id INT UNSIGNED NOT NULL COMMENT 'FK: the closed booking being paid (PAY-01)',
  amount     DECIMAL(10,2) NOT NULL COMMENT 'Rupees received; total per booking <= total_amount (PAY-02)',
  method     ENUM('Cash','Card','UPI') NOT NULL COMMENT 'Payment method',
  paid_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When the money was received',
  CONSTRAINT fk_pay_booking FOREIGN KEY (booking_id)
    REFERENCES Rentals_Reservations(booking_id) ON DELETE RESTRICT,
  CONSTRAINT chk_pay_amount CHECK (amount > 0),
  INDEX idx_pay_paid_at (paid_at)
) COMMENT = 'Money received; balances are computed from this table, never stored';

-- 14. Audit trail, written only by trigger
CREATE TABLE Booking_Audit_Log (
  log_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'Surrogate key',
  booking_id INT UNSIGNED NOT NULL COMMENT 'FK: booking whose status changed',
  old_status VARCHAR(12) NULL COMMENT 'Status before the change; NULL for a new booking',
  new_status VARCHAR(12) NOT NULL COMMENT 'Status after the change',
  changed_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT 'When (millisecond precision)',
  changed_by VARCHAR(100) NOT NULL COMMENT 'CURRENT_USER() of the session that made the change',
  CONSTRAINT fk_audit_booking FOREIGN KEY (booking_id)
    REFERENCES Rentals_Reservations(booking_id) ON DELETE CASCADE
) COMMENT = 'Every booking status change, written only by trg_rr_after_insert / trg_rr_after_update';
