# Normalization

This document starts from the paper register the café would keep without a database and
normalizes it step by step (UNF → 1NF → 2NF → 3NF → BCNF → 4NF), with the functional-dependency
theory behind each step: Armstrong's axioms, attribute closure, candidate keys, canonical cover,
3NF synthesis, lossless join and dependency preservation. It ends with the design decisions that
look like "denormalization" and why they are not anomalies. (CO3)

## 1. The starting point: an unnormalized register (UNF)

A front-desk register with one line per booking:

| booking | date & time | member | phone | tier | discount | table | zone | seats | table ₹/h | games played (box, title, min age, players) | pieces missing | payments |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 101 | 12 Oct 18:00–20:00 | Rahul Verma | 9890090123 | Gold | 20 % | MH-01 | Main_Hall | 4 | 150 | 8901001…: Catan, 10+, 3–4 | Number tokens ×2 @ ₹15; Settlements ×1 @ ₹25 | ₹200 UPI; ₹155 Cash |
| 102 | 12 Oct 18:00–21:00 | Karan Malhotra | 9844434567 | Silver | 10 % | PR-02 | Party_Room | 8 | 300 | 8901007…: Wingspan, 10+, 1–5 | — | — |

Problems: **repeating groups** (several missing pieces, several payments, and a game has several
categories) and **non-atomic values** ("12 Oct 18:00–20:00", "3–4"). The anomalies that follow:

* **Update anomaly** — Rahul changes his phone number: every line he ever wrote must change; miss
  one and the register contradicts itself. Same for a table's hourly rate or a game's minimum age.
* **Insertion anomaly** — a new table (PA-05) or a new game cannot be recorded until someone books it.
* **Deletion anomaly** — deleting the only booking of *Chess* forgets that the café owns Chess and
  what pieces its box should contain.

## 2. First normal form (1NF): atomic values, no repeating groups

Split compound values (start/end, min/max players, first/last name) and move each repeating
group into its own relation, carrying the key of the register with it:

* `R(booking_id, reserved_start, reserved_end, booking_type, party_size, status, base_charge,
  discount_amount, late_fee, damage_fee, cancellation_fee, customer_id, first_name, last_name,
  email, phone, date_of_birth, tier_id, tier_name, discount_pct, max_session_hours, table_id,
  table_code, zone, seating_capacity, table_rate, copy_id, barcode, copy_condition, game_id, title,
  publisher, min_players, max_players, min_age, game_hourly, game_daily, inspection_id, staff_id,
  condition_on_return)` — key **booking_id**
* `MP(booking_id, component_name, game_id, qty_missing, qty_per_copy, unit_cost, charge)` — key **{booking_id, component_name}**
* `PAY(payment_id, booking_id, amount, method, paid_at)` — key **payment_id**
* `GCAT(game_id, title, category)` — key **{game_id, category}**

Every attribute is now atomic and every row is identified by its key. The anomalies are still
there: R repeats the member's, the table's and the game's facts on every booking.

## 3. The functional dependencies

Write `X → Y` for "the value of X determines the value of Y". From the café's rules:

| # | FD | Meaning |
| --- | --- | --- |
| f1 | booking_id → customer_id, table_id, copy_id, booking_type, party_size, reserved_start, reserved_end, status, base_charge, discount_amount, late_fee, damage_fee, cancellation_fee | a booking is one member, at most one table and one copy, one window |
| f2 | reserved_start, reserved_end → duration_minutes | derived |
| f3 | base_charge, discount_amount, late_fee, damage_fee, cancellation_fee → total_amount | derived |
| f4 | customer_id → first_name, last_name, email, phone, date_of_birth, tier_id, join_date, membership_expiry, customer_status | |
| f5 | email → customer_id; phone → customer_id | alternate keys |
| f6 | tier_id → tier_name, annual_fee, max_concurrent_rentals, max_session_hours, max_takehome_days, discount_pct; tier_name → tier_id | |
| f7 | table_id → table_code, zone, seating_capacity, table_rate, is_accessible, is_active; table_code → table_id | |
| f8 | copy_id → game_id, barcode, acquired_on, copy_condition, copy_status, shelf_location; barcode → copy_id | condition is a property of the box |
| f9 | game_id → title, publisher, year_published, min_players, max_players, min_age, avg_play_minutes, complexity, game_hourly, game_daily, replacement_cost; title, publisher → game_id | |
| f10 | game_id, component_name → qty_per_copy, unit_cost | the expected contents of a box |
| f11 | booking_id → inspection_id; inspection_id → booking_id, staff_id, inspected_at, condition_on_return | one inspection per booking |
| f12 | booking_id, component_name → qty_missing, charge | what was missing in that return |
| f13 | payment_id → booking_id, amount, method, paid_at | |

Not an FD: "an active booking's (table_id, time window) does not overlap another's". Overlap is a
condition over *pairs of rows and ranges of values*, not equality, so no FD (and no UNIQUE
constraint) can express it — which is exactly why BR-05 lives in a trigger.

## 4. Armstrong's axioms at work

Axioms: **reflexivity** (Y ⊆ X ⇒ X → Y), **augmentation** (X → Y ⇒ XZ → YZ), **transitivity**
(X → Y, Y → Z ⇒ X → Z). Derived rules: **union**, **decomposition**, **pseudo-transitivity**.

1. booking_id → tier_id:
   booking_id → customer_id (f1, decomposition); customer_id → tier_id (f4, decomposition);
   transitivity ⇒ booking_id → tier_id.
2. booking_id → discount_pct: from (1) and tier_id → discount_pct (f6) by transitivity — the
   discount on a booking is decided by the member's tier.
3. booking_id → total_amount: booking_id → {base_charge, …, cancellation_fee} (f1, decomposition
   then union); that set → total_amount (f3); transitivity.
4. email → tier_id: email → customer_id (f5), customer_id → tier_id (f4); transitivity.
5. Pseudo-transitivity: copy_id → game_id (f8) and {game_id, component_name} → unit_cost (f10)
   ⇒ {copy_id, component_name} → unit_cost. (This is what `trg_mp_before_insert` uses to price a
   missing piece from the returned copy.)
6. Augmentation: customer_id → tier_id ⇒ {customer_id, booking_id} → {tier_id, booking_id}.
7. Reflexivity: {booking_id, customer_id} → customer_id (trivial FD).

## 5. Attribute closure of booking_id and candidate keys

Compute {booking_id}⁺ over R:

| Step | FD used | Closure so far |
| --- | --- | --- |
| 0 | start | booking_id |
| 1 | f1 | + customer_id, table_id, copy_id, booking_type, party_size, reserved_start, reserved_end, status, base_charge, discount_amount, late_fee, damage_fee, cancellation_fee |
| 2 | f2, f3 | + duration_minutes, total_amount |
| 3 | f4 | + first_name, last_name, email, phone, date_of_birth, tier_id, join_date, membership_expiry, customer_status |
| 4 | f6 | + tier_name, annual_fee, max_concurrent_rentals, max_session_hours, max_takehome_days, discount_pct |
| 5 | f7 | + table_code, zone, seating_capacity, table_rate, is_accessible, is_active |
| 6 | f8 | + game_id, barcode, acquired_on, copy_condition, copy_status, shelf_location |
| 7 | f9 | + title, publisher, …, replacement_cost |
| 8 | f11 | + inspection_id, staff_id, inspected_at, condition_on_return |
| 9 | — | no FD adds anything new: stop |

{booking_id}⁺ contains every attribute of R, so booking_id is a **superkey** of R; it is a single
attribute, so it is also minimal — a **candidate key**. No other candidate key exists: booking_id
appears on no right-hand side except f11's (inspection_id → booking_id), and inspection_id is NULL
for bookings never inspected, so it cannot be a key. For the other relations: MP's key is
{booking_id, component_name} ({booking_id}⁺ lacks qty_missing; {component_name}⁺ is just itself);
Customers has three candidate keys (customer_id, email, phone); Board_Games two
(game_id, {title, publisher}).

## 6. Second normal form (2NF): no partial dependencies

2NF: no non-prime attribute depends on **part** of a candidate key. R has a single-attribute key,
so it is automatically in 2NF. The composite-key relations are not:

* **MP** (key {booking_id, component_name}): booking_id → game_id is a partial dependency
  (game_id depends on half the key). Split: game_id goes back with the booking (it is already in R
  through copy_id); the expected-contents facts become
  `Game_Components(game_id, component_name, qty_per_copy, unit_cost)` and the per-return facts
  `Missing_Pieces(booking_id, component_name, qty_missing, charge)`.
  *Anomaly removed:* changing a box's expected piece count meant editing every past return.
* **GCAT** (key {game_id, category}): game_id → title is partial. Split into
  `Board_Games(game_id, title, …)` and `Board_Game_Categories(game_id, category)`.
  *Anomaly removed:* a game with no category yet could not be stored.

## 7. Third normal form (3NF): no transitive dependencies

3NF: for every non-trivial X → A, X is a superkey or A is prime. R violates it through chains
that go **through a non-key attribute**:

| Transitive chain in R | New relation | Anomaly removed |
| --- | --- | --- |
| booking_id → customer_id → first_name, phone, date_of_birth, … | `Customers` | phone change touches one row |
| booking_id → customer_id → tier_id → discount_pct, limits | `Membership_Tiers` | raising Gold's discount touches one row; a tier can exist with no members |
| booking_id → table_id → seating_capacity, zone, rate | `Cafe_Tables` | a never-booked table (PA-05) can be stored |
| booking_id → copy_id → game_id → min_age, players, rates | `Game_Copies`, `Board_Games` | a game owned but never played (Chess) can be stored |
| booking_id → inspection_id → staff_id, condition | `Return_Inspections` | inspection facts are not NULL padding on bookings that never had a copy |

What is left of R is the bridge `Rentals_Reservations(booking_id, customer_id, table_id, copy_id,
booking_type, party_size, reserved_start, reserved_end, …fees…)` — exactly the student's
"Rentals_&_Reservations" entity.

## 8. Canonical cover (minimal cover)

Suppose the analyst first wrote this set G for the member/booking part:

```text
g1  booking_id            → customer_id, tier_id
g2  customer_id           → tier_id
g3  customer_id, email    → first_name
g4  customer_id           → email, first_name
g5  table_code            → table_id
g6  table_id              → table_code, seating_capacity
```

1. **Singleton right-hand sides** (decomposition):
   booking_id → customer_id, booking_id → tier_id, customer_id → tier_id,
   {customer_id, email} → first_name, customer_id → email, customer_id → first_name,
   table_code → table_id, table_id → table_code, table_id → seating_capacity.
2. **Extraneous left-hand attributes**: in {customer_id, email} → first_name, is *email* extraneous?
   Compute {customer_id}⁺ = {customer_id, tier_id, email, first_name} ∋ first_name ⇒ yes.
   The FD becomes customer_id → first_name, a duplicate of one we already have.
3. **Redundant FDs**: is booking_id → tier_id redundant? Remove it and compute {booking_id}⁺
   with the rest: {booking_id, customer_id, tier_id, email, first_name} ∋ tier_id ⇒ redundant
   (it follows by transitivity). Drop it.
4. **Union** equal left sides:

```text
Fc:  booking_id  → customer_id
     customer_id → tier_id, email, first_name
     table_code  → table_id
     table_id    → table_code, seating_capacity
```

Fc is equivalent to G (each implies the other) and has no extraneous attribute and no redundant FD.

## 9. 3NF synthesis

The synthesis algorithm turns a canonical cover into a dependency-preserving, lossless 3NF schema:

1. One relation per FD group in Fc: (booking_id, customer_id), (customer_id, tier_id, email,
   first_name), (table_code, table_id), (table_id, table_code, seating_capacity).
2. Drop relations contained in another: (table_code, table_id) ⊆ (table_id, table_code,
   seating_capacity).
3. If no relation contains a candidate key of the whole schema, add one. In this fragment
   {booking_id}⁺ = {booking_id, customer_id, tier_id, email, first_name} misses the table
   attributes, and nothing determines table_id except table_code (and vice versa), so the
   candidate keys of the fragment are {booking_id, table_id} and {booking_id, table_code}. No
   relation from step 1 contains either, so the algorithm adds **(booking_id, table_id)** — which
   is precisely the missing "which table did this booking use" fact. In the full FD set this
   step adds nothing: f1 contains booking_id → table_id, so the booking relation produced in
   step 1 already holds the key booking_id.

Applied to the full set f1–f13 this produces exactly the 14 tables of `sql/01_schema.sql`
(plus `Booking_Audit_Log`, which records history and has its own key).

## 10. BCNF

BCNF: for every non-trivial X → A, X is a superkey. Checking the final tables:

* `Customers`: determinants customer_id, email, phone — all candidate keys ✓
* `Board_Games`: game_id and {title, publisher} — candidate keys ✓
* `Game_Components`: component_id and {game_id, component_name} — candidate keys ✓
* `Cafe_Tables`, `Game_Copies`, `Membership_Tiers`: determinants are the PK or a UNIQUE column ✓
* `Missing_Pieces`, `Board_Game_Categories`, `Payments`, `Return_Inspections` ✓
* `Rentals_Reservations`: two deliberate exceptions, f2 and f3 — {reserved_start, reserved_end} →
  duration_minutes and {fees} → total_amount have non-key determinants. They are **generated
  columns**: the DBMS computes them on every write, so they can never disagree with their inputs
  and cause no update anomaly. They exist for convenience and indexing (§13).

**3NF but not BCNF — an example from the café.** Suppose each Game Guru specialises in one
category, and in each zone each category is covered by one guru:
`Coaching(zone, category, guru)` with FDs {zone, category} → guru and guru → category.
Candidate keys: {zone, category} and {zone, guru}. All attributes are prime, so it is in 3NF; but
guru → category has a non-superkey determinant, so it is not in BCNF (anomaly: a guru's category
is repeated for every zone). BCNF decomposition: `(guru, category)` and `(zone, guru)` — lossless
(common attribute guru is a key of the first), but the FD {zone, category} → guru is no longer
inside one relation: it is **not preserved** and could only be checked by a join or a trigger.
This is the classic BCNF-vs-dependency-preservation trade-off; 3NF always allows both.

## 11. Lossless join

A binary decomposition of R into R1, R2 is lossless iff R1 ∩ R2 → R1 or R1 ∩ R2 → R2
(the common attributes are a superkey of one side).

**Proof for Bookings / Customers.** R1 = `Rentals_Reservations(booking_id, customer_id, …)`,
R2 = `Customers(customer_id, first_name, …)`. R1 ∩ R2 = {customer_id}, and customer_id → R2
(it is R2's key, f4). Hence R1 ⋈ R2 = the original relation: every booking row matches exactly
one customer row and no spurious tuples appear. The same argument (the shared attribute is the
key of the "lookup" side) holds for every FK in the schema, so the whole decomposition is lossless.

**A lossy decomposition.** Split `BookingTable(booking_id, table_code, zone)` on *zone* into
`A(booking_id, zone)` and `B(table_code, zone)`:

| A: booking_id | zone | | B: table_code | zone |
| --- | --- | --- | --- | --- |
| 1 | Main_Hall | | MH-01 | Main_Hall |
| 2 | Main_Hall | | MH-03 | Main_Hall |

A ⋈ B returns 4 rows — including (1, MH-03) and (2, MH-01), which never happened. zone is not a
key of either side, so information about *which* table each booking used is lost.

## 12. Dependency preservation

A decomposition preserves F if (F₁ ∪ F₂ ∪ …)⁺ = F⁺, where Fᵢ are the FDs that hold within Rᵢ.
Every FD f1–f13 has all its attributes inside one final table (f1, f2, f3 in
`Rentals_Reservations`; f4, f5 in `Customers`; f6 in `Membership_Tiers`; … f12 in `Missing_Pieces`
with component_name replaced by its surrogate component_id), so each can be enforced by that
table's key or UNIQUE constraint without a join: the decomposition is **dependency preserving**
(the 3NF synthesis guarantees it). Counter-example: the BCNF split of `Coaching` in §10.

## 13. Multivalued dependencies and 4NF

Consider `GameInfo(game_id, category, component_name)` — "what kind of game is it, and what is in
the box". Category and component are **independent** facts about a game, so:

* game_id ↠ category and game_id ↠ component_name (multivalued dependencies), and
* every category must be paired with every component.

Catan (2 categories × 6 components) needs 12 rows:

| game_id | category | component_name |
| --- | --- | --- |
| 1 | Family | Cities |
| 1 | Family | Development cards |
| … | … | … |
| 1 | Strategy | Settlements |

Across the seed data `GameInfo` would hold **230** rows. Anomaly: adding a third category to Catan
needs 6 new rows; forgetting one breaks the "every pair" rule. GameInfo is in BCNF (its only key
is all three attributes and there are no non-trivial FDs) but **not in 4NF**, because game_id ↠
category is a non-trivial MVD whose left side is not a superkey.

4NF decomposition: `Board_Game_Categories(game_id, category_id)` and
`Game_Components(game_id, component_name, …)` — **167** rows in the seed (49 + 118), and each fact
is stored once. The decomposition is lossless because game_id ↠ category holds
(the MVD form of the lossless-join test).

## 14. Design decisions

| Decision | Normalization reasoning |
| --- | --- |
| **Condition on the copy, not the title** (`Game_Copies.copy_condition`) | Condition depends on the physical box (copy_id), not on game_id. On `Board_Games` it would be a non-key fact about something other than the key — a 2NF/3NF error — and could not express "box 1 is New, box 2 is Worn". |
| **One bridge table for both booking types** | Dine_In and Take_Home share almost every attribute (window, status, fees) and every rule about overlap and payment; single-table mapping of a disjoint, total specialization with the discriminator `booking_type`. The shape rule is a CHECK (`chk_booking_type_shape`), so the nullable `table_id` / `copy_id` / `party_size` never hold impossible combinations. |
| **Generated columns** `duration_minutes`, `total_amount` | Strictly, derived data. They are maintained by the engine (`STORED` generated columns), so they cannot drift — controlled redundancy that makes queries and indexes simpler. |
| **Charge snapshot** `Missing_Pieces.charge` (and `base_charge`, `discount_amount` on the booking) | Not redundancy: the fact recorded is "what we charged at that time". It depends on (inspection, component) *at inspection time*; deriving it from today's `unit_replacement_cost` would silently rewrite past bills when prices change. |
| **Balance is computed, never stored** | A stored balance would depend on Payments and Rentals_Reservations rows — a transitive, multi-row dependency that every payment would have to update (update anomaly, lost-update risk under concurrency). `fn_customer_balance` and `vw_customer_balances` compute it from the facts. |
| **Age is computed** from `date_of_birth` | Age changes every year without any update; storing it would make it wrong by design. |
| **Surrogate keys** (`component_id`, `booking_id`, …) with natural keys kept UNIQUE | Short, stable FK targets; the natural key (e.g. {game_id, component_name}) is still enforced, so no FD is lost. |
