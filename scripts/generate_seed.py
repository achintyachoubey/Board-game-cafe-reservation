#!/usr/bin/env python3
"""Generate sql/08_seed.sql - deterministic seed data for the Board Game Cafe.

    python scripts/generate_seed.py            # writes sql/08_seed.sql

Every date in the output is relative to the day the file is LOADED, e.g.
TIMESTAMP(CURRENT_DATE - INTERVAL 37 DAY, '18:30:00'), so the static file loads
correctly on any day without Python. A fixed random seed makes the file
reproducible byte for byte.

All rows go in through the real triggers and CHECK constraints; nothing is
disabled. The generator therefore produces only bookings that satisfy the
rules: opening hours, :00/:30 slots, tier session limits, party size vs table
and game, minimum ages, take-home 18+, and no overlap on a table or copy.

Load order inside the file (the traps found while testing the spec):
  1. reference data            5. reset copy statuses, then set fixture statuses
  2. history (Completed, ...)  6. payments - BEFORE any future reservation (BR-13)
  3. late fees                 7. live rows: Overdue (inserted Checked_In, then
  4. inspections + missing        updated) and Checked_In take-home rentals
     pieces (after the            8. ~20 future reservations via CALL sp_create_reservation
     bookings are Completed)
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "sql" / "08_seed.sql"
RNG = random.Random(2026)
DAY = 1440

# --------------------------------------------------------------------------- reference data
TIERS = [  # name, fee, rentals, hours, days, discount
    ("Basic", 0, 1, 4, 1, 0), ("Silver", 999, 2, 6, 2, 10), ("Gold", 1999, 3, 8, 3, 20)]

STAFF = [  # name, role, hired_days_ago, active
    ("Rakesh Iyer", "Manager", 1400, True), ("Farhan Ali", "Game_Guru", 1100, True),
    ("Shreya Das", "Game_Guru", 900, True), ("Gaurav Menon", "Game_Guru", 600, True),
    ("Nandini Rao", "Game_Guru", 420, True), ("Kiran Joshi", "Front_Desk", 700, True),
    ("Asha Fernandes", "Front_Desk", 300, True), ("Deepak Yadav", "Front_Desk", 1500, False)]

CATEGORIES = ["Strategy", "Party", "Family", "Co-op", "Card Game", "Deck Building",
              "Abstract", "Word", "Dexterity", "Trivia"]


@dataclass
class Game:
    gid: int
    title: str
    publisher: str
    year: int | None
    pmin: int
    pmax: int
    age: int
    minutes: int
    complexity: float
    hourly: int
    daily: int
    replacement: int
    cats: list[str]
    components: list[tuple[str, int, int]]  # name, qty, unit cost
    copies: int = 2


GAMES = [
    Game(1, "Catan", "Kosmos", 1995, 3, 4, 10, 90, 2.3, 50, 200, 3500, ["Strategy", "Family"],
         [("Resource cards", 95, 8), ("Development cards", 25, 10), ("Settlements", 20, 25),
          ("Cities", 16, 30), ("Roads", 60, 10), ("Number tokens", 18, 15)], 3),
    Game(2, "Ticket to Ride", "Days of Wonder", 2004, 2, 5, 8, 60, 1.8, 50, 180, 3800,
         ["Family", "Strategy"],
         [("Train cars", 240, 6), ("Train cards", 110, 8), ("Destination tickets", 30, 10),
          ("Scoring markers", 5, 20), ("Game board", 1, 900)], 3),
    Game(3, "Codenames", "Czech Games Edition", 2015, 2, 8, 14, 15, 1.3, 30, 100, 1200,
         ["Party", "Word"],
         [("Codename cards", 200, 4), ("Key cards", 40, 6), ("Agent cards", 16, 8),
          ("Assassin card", 1, 15), ("Sand timer", 1, 120)], 3),
    Game(4, "Pandemic", "Z-Man Games", 2008, 2, 4, 8, 45, 2.4, 50, 180, 3200, ["Co-op", "Strategy"],
         [("Disease cubes", 96, 5), ("Player cards", 59, 8), ("Infection cards", 48, 8),
          ("Pawns", 7, 40), ("Research stations", 6, 30), ("Role cards", 7, 15)], 3),
    Game(5, "Dominion", "Rio Grande Games", 2008, 2, 4, 13, 30, 2.4, 40, 150, 3000,
         ["Card Game", "Deck Building"],
         [("Kingdom cards", 250, 5), ("Treasure cards", 130, 5), ("Victory cards", 48, 5),
          ("Trash mat", 1, 40), ("Randomizer cards", 25, 4)]),
    Game(6, "Azul", "Next Move Games", 2017, 2, 4, 8, 40, 1.8, 40, 150, 2800, ["Abstract", "Family"],
         [("Tiles", 100, 12), ("Player boards", 4, 150), ("Factory displays", 9, 40),
          ("Scoring markers", 4, 20), ("Cloth bag", 1, 150)], 3),
    Game(7, "Wingspan", "Stonemaier Games", 2019, 1, 5, 10, 70, 2.4, 60, 250, 4500,
         ["Strategy", "Card Game"],
         [("Bird cards", 170, 10), ("Food tokens", 103, 6), ("Egg miniatures", 75, 8),
          ("Dice", 5, 50), ("Action cubes", 40, 6), ("Bird feeder tower", 1, 350)], 3),
    Game(8, "Dixit", "Libellud", 2008, 3, 8, 8, 30, 1.2, 40, 150, 2500, ["Family", "Card Game"],
         [("Story cards", 84, 15), ("Voting tokens", 48, 5), ("Rabbit pawns", 8, 40),
          ("Score board", 1, 250)]),
    Game(9, "Jenga", "Hasbro", 1983, 1, 8, 6, 20, 1.0, 30, 100, 900, ["Dexterity", "Family"],
         [("Wooden blocks", 54, 10), ("Stacking sleeve", 1, 80), ("Rule leaflet", 1, 10),
          ("Storage box", 1, 120)]),
    Game(10, "Splendor", "Space Cowboys", 2014, 2, 4, 10, 30, 1.8, 40, 150, 2500,
         ["Strategy", "Card Game"],
         [("Development cards", 90, 10), ("Gem tokens", 40, 20), ("Noble tiles", 10, 15),
          ("Gold tokens", 5, 25)], 3),
    Game(11, "7 Wonders", "Repos Production", 2010, 3, 7, 10, 30, 2.3, 50, 200, 3500,
         ["Strategy", "Card Game"],
         [("Age cards", 148, 8), ("Wonder boards", 7, 60), ("Coins", 46, 5),
          ("Conflict tokens", 46, 5), ("Score pad", 1, 60)]),
    Game(12, "Exploding Kittens", "Exploding Kittens", 2015, 2, 5, 7, 15, 1.1, 30, 100, 1200,
         ["Party", "Card Game"],
         [("Exploding Kitten cards", 4, 20), ("Defuse cards", 6, 15), ("Action cards", 46, 8),
          ("Box tray", 1, 50)], 3),
    Game(13, "Scrabble", "Mattel", 1948, 2, 4, 8, 90, 1.9, 30, 100, 1500, ["Word", "Family"],
         [("Letter tiles", 100, 10), ("Tile racks", 4, 60), ("Tile bag", 1, 100),
          ("Game board", 1, 400)]),
    Game(14, "Carcassonne", "Z-Man Games", 2000, 2, 5, 7, 45, 1.9, 40, 150, 2200,
         ["Family", "Strategy"],
         [("Land tiles", 72, 15), ("Meeples", 40, 10), ("Scoreboard", 1, 150),
          ("Abbot figures", 5, 15)], 3),
    Game(15, "Terraforming Mars", "FryxGames", 2016, 1, 5, 12, 120, 3.3, 70, 300, 5500,
         ["Strategy"],
         [("Project cards", 208, 8), ("Player markers", 200, 2), ("Resource cubes", 200, 2),
          ("Player boards", 5, 100), ("Tiles", 60, 10), ("Corporation cards", 12, 10)]),
    Game(16, "The Crew", "Kosmos", 2019, 3, 5, 10, 20, 2.0, 30, 100, 1100, ["Co-op", "Card Game"],
         [("Playing cards", 40, 10), ("Task cards", 36, 8), ("Logbook", 1, 150),
          ("Commander token", 1, 20), ("Reminder cards", 5, 10)]),
    Game(17, "Sushi Go Party!", "Gamewright", 2016, 2, 8, 8, 20, 1.3, 30, 100, 1500,
         ["Party", "Card Game", "Family"],
         [("Dish cards", 216, 4), ("Menu tiles", 26, 10), ("Score track", 1, 120),
          ("Scoring tokens", 8, 15)]),
    Game(18, "Chess", "House of Staunton", None, 2, 2, 6, 60, 3.7, 20, 80, 1500,
         ["Abstract", "Strategy"],
         [("Pawns", 16, 40), ("Major pieces", 16, 60), ("Board", 1, 500), ("Chess clock", 1, 1200)]),
    Game(19, "Trivial Pursuit", "Hasbro", 1981, 2, 6, 12, 90, 1.7, 30, 100, 1800,
         ["Trivia", "Family"],
         [("Question cards", 400, 3), ("Wedges", 36, 10), ("Pies", 6, 30), ("Die", 1, 30),
          ("Card boxes", 2, 60)]),
    Game(20, "Gloomhaven: Jaws of the Lion", "Cephalofair Games", 2020, 1, 4, 14, 120, 3.6, 80, 300,
         4500, ["Co-op", "Strategy"],
         [("Ability cards", 200, 8), ("Monster standees", 40, 25), ("Scenario book", 1, 600),
          ("Character miniatures", 4, 250), ("Condition tokens", 50, 5)]),
    Game(21, "Werewolf", "Bezier Games", 2014, 5, 10, 10, 30, 1.3, 30, 100, 900, ["Party"],
         [("Role cards", 30, 15), ("Moderator guide", 1, 100), ("Night tokens", 20, 10),
          ("Vote tokens", 10, 10)]),
    Game(22, "Uno", "Mattel", 1971, 2, 10, 7, 30, 1.0, 20, 80, 400, ["Card Game", "Family"],
         [("Number cards", 76, 3), ("Action cards", 24, 3), ("Wild cards", 8, 5),
          ("Customisable wild cards", 3, 5)], 3),
    Game(23, "Cards Against Humanity", "Cards Against Humanity LLC", 2011, 4, 10, 18, 30, 1.2, 40,
         150, 2000, ["Party", "Card Game"],
         [("Black cards", 90, 4), ("White cards", 460, 3), ("Blank cards", 50, 2), ("Box insert", 1, 100)]),
    Game(24, "Spirit Island", "Greater Than Games", 2017, 1, 4, 13, 120, 4.0, 70, 300, 5000,
         ["Co-op", "Strategy"],
         [("Power cards", 100, 8), ("Spirit panels", 8, 60), ("Invader cards", 15, 8),
          ("Presence discs", 100, 4), ("Fear tokens", 24, 6), ("Island boards", 4, 200)]),
    Game(25, "Hanabi", "R&R Games", 2010, 2, 5, 8, 25, 1.7, 20, 80, 600, ["Co-op", "Card Game"],
         [("Firework cards", 50, 8), ("Clue tokens", 8, 10), ("Fuse tokens", 3, 10),
          ("Storage box", 1, 80)]),
]
G = {g.gid: g for g in GAMES}
PARTY_GAMES = [g.gid for g in GAMES if "Party" in g.cats]

TABLES = [  # code, zone, capacity, rate, accessible, active
    ("MH-01", "Main_Hall", 4, 150, False, True), ("MH-02", "Main_Hall", 4, 150, True, True),
    ("MH-03", "Main_Hall", 6, 200, False, True), ("MH-04", "Main_Hall", 2, 100, False, True),
    ("MH-05", "Main_Hall", 8, 250, False, True), ("QC-01", "Quiet_Corner", 2, 100, False, True),
    ("QC-02", "Quiet_Corner", 2, 100, False, True), ("QC-03", "Quiet_Corner", 4, 140, False, True),
    ("PR-01", "Party_Room", 10, 350, False, True), ("PR-02", "Party_Room", 8, 300, False, True),
    ("PR-03", "Party_Room", 6, 220, False, True), ("PA-01", "Patio", 4, 120, True, True),
    ("PA-02", "Patio", 6, 180, False, True), ("PA-03", "Patio", 2, 90, False, True),
    ("PA-04", "Patio", 4, 120, False, True), ("PA-05", "Patio", 8, 260, False, False),
]
INACTIVE_TABLE = 16


@dataclass
class Customer:
    cid: int
    first: str
    last: str
    age: int
    tier: int
    phone: str
    join_ago: int            # days before load date
    expiry: int              # days after load date (negative = expired)
    status: str = "Active"
    dob_extra: int = 0       # days beyond the last birthday (100-250 keeps age constant)

    @property
    def max_hours(self) -> int:
        return TIERS[self.tier - 1][3]

    @property
    def max_days(self) -> int:
        return TIERS[self.tier - 1][4]

    @property
    def max_rentals(self) -> int:
        return TIERS[self.tier - 1][2]


_CUST = [  # first, last, age, tier, phone
    ("Aarav", "Mehta", 29, 3, "9810012345"), ("Ananya", "Iyer", 24, 2, "9820023456"),
    ("Rohan", "Gupta", 35, 1, "9830034567"), ("Priya", "Nair", 31, 2, "9840045678"),
    ("Vikram", "Singh", 42, 3, "9820054321"), ("Sneha", "Reddy", 27, 1, "9860067890"),
    ("Arjun", "Sharma", 22, 2, "9870078901"), ("Kavya", "Pillai", 19, 1, "9880089012"),
    ("Rahul", "Verma", 38, 3, "9890090123"), ("Ishita", "Banerjee", 26, 2, "9811101234"),
    ("Aditya", "Joshi", 45, 1, "9822212345"), ("Meera", "Krishnan", 52, 3, "9833323456"),
    ("Karan", "Malhotra", 33, 2, "9844434567"), ("Diya", "Kapoor", 14, 1, "9855545678"),
    ("Nikhil", "Desai", 61, 1, "9866656789"), ("Pooja", "Agarwal", 30, 2, "9877767890"),
    ("Siddharth", "Rao", 36, 3, "9888878901"), ("Tanvi", "Kulkarni", 16, 2, "9899989012"),
    ("Manish", "Chauhan", 47, 1, "9712309876"), ("Neha", "Saxena", 23, 2, "9723410987"),
    ("Varun", "Bhatia", 28, 1, "9734521098"), ("Riya", "Ghosh", 21, 3, "9745632109"),
    ("Harsh", "Patel", 34, 2, "9756743210"), ("Lakshmi", "Venkatesh", 65, 3, "9767854321"),
    ("Kabir", "Khanna", 25, 1, "9778965432"), ("Anjali", "Mishra", 39, 2, "9789076543"),
    ("Yash", "Thakur", 12, 1, "9790187654"), ("Zoya", "Qureshi", 32, 3, "9701298765"),
    ("Arnav", "Bose", 20, 1, "8801309876"), ("Divya", "Menon", 44, 2, "8812410987"),
]
CUSTOMERS: list[Customer] = []
for _i, (_f, _l, _a, _t, _p) in enumerate(_CUST, start=1):
    CUSTOMERS.append(Customer(_i, _f, _l, _a, _t, _p, join_ago=RNG.randint(150, 900),
                              expiry=RNG.randint(60, 330), dob_extra=RNG.randint(100, 250)))
C = {c.cid: c for c in CUSTOMERS}

# ----- guaranteed fixtures (tests depend on them) --------------------------------------
FX_PARTY_ALL = 9          # Rahul Verma: completed a booking of every Party game (Q20), and
                          # has both Dine_In and Take_Home completed bookings (Q22)
FX_OWES = 13              # Karan Malhotra: Active, owes > Rs 500 (BR-13 refuses him)
FX_SUSPENDED = 19         # Manish Chauhan: Suspended, owes ~Rs 1,100 (stays suspended)
FX_EXPIRED = 21           # Varun Bhatia: membership expired 20 days ago
FX_EXPIRING = 23          # Harsh Patel: membership expires in 5 days
FX_AGE14, FX_AGE16 = 14, 18   # Diya Kapoor (14), Tanvi Kulkarni (16)
C[FX_SUSPENDED].status = "Suspended"
C[FX_EXPIRED].expiry, C[FX_EXPIRED].join_ago = -20, 400
C[FX_EXPIRING].expiry = 5
C[2].expiry = 21          # a second member expiring within 30 days (Q02)

# copy ids are assigned in game order; fixture copies are looked up after numbering
COPIES: list[tuple[int, int, int]] = []   # copy_id, game_id, n-th copy of the game
for g in GAMES:
    g.copies = 3 if g.copies == 3 else 2
    for n in range(1, g.copies + 1):
        COPIES.append((len(COPIES) + 1, g.gid, n))
COPY_GAME = {cid: gid for cid, gid, _ in COPIES}


def copy_of(gid: int, n: int) -> int:
    return next(c for c, g, k in COPIES if g == gid and k == n)


FX_COPY_MISSING = copy_of(1, 2)       # Catan #2  -> Missing_Pieces (un-restocked rows)
FX_COPY_REPAIR = copy_of(9, 1)        # Jenga #1  -> Under_Repair (returned Damaged)
FX_COPY_RETIRED = copy_of(9, 2)       # Jenga #2  -> Retired (came back short 3 times)
FX_COPY_OVERDUE = copy_of(2, 3)       # Ticket to Ride #3 -> held by the Overdue rental
FX_COPY_OUT = copy_of(4, 1)           # Pandemic #1 -> held by the Checked_In rental
NEVER_PLAYED = {18}                   # Chess: never booked (Q16)
ONLY_PREVIOUS_WINDOW = {24}           # Spirit Island: played only 31-60 days ago (Q43)
ONLY_RECENT_WINDOW = {25}             # Hanabi: played only in the last 30 days (Q43)
FIXTURE_ONLY_GAMES = {9} | NEVER_PLAYED | ONLY_PREVIOUS_WINDOW | ONLY_RECENT_WINDOW
FIXTURE_COPIES = {FX_COPY_MISSING, FX_COPY_REPAIR, FX_COPY_RETIRED}

COMPONENTS: list[tuple[int, int, str, int, int]] = []   # id, game, name, qty, cost
for g in GAMES:
    for name, qty, cost in g.components:
        COMPONENTS.append((len(COMPONENTS) + 1, g.gid, name, qty, cost))


def components_of(gid: int) -> list[tuple[int, int, str, int, int]]:
    return [c for c in COMPONENTS if c[1] == gid]


# --------------------------------------------------------------------------- time helpers
def ts(t: int) -> str:
    """Minutes relative to CURRENT_DATE 00:00 -> SQL expression relative to the load date."""
    day, mod = divmod(t, DAY)
    hh, mm = divmod(mod, 60)
    if day < 0:
        base = f"CURRENT_DATE - INTERVAL {-day} DAY"
    elif day > 0:
        base = f"CURRENT_DATE + INTERVAL {day} DAY"
    else:
        base = "CURRENT_DATE"
    return f"TIMESTAMP({base}, '{hh:02d}:{mm:02d}:00')"


def at(days_ago: int, hh: int, mm: int = 0) -> int:
    return -days_ago * DAY + hh * 60 + mm


def date_expr(days: int) -> str:
    if days < 0:
        return f"CURRENT_DATE - INTERVAL {-days} DAY"
    if days > 0:
        return f"CURRENT_DATE + INTERVAL {days} DAY"
    return "CURRENT_DATE"


# --------------------------------------------------------------------------- scheduling
@dataclass
class Booking:
    customer: int
    btype: str
    start: int
    end: int
    table: int | None = None
    copy: int | None = None
    party: int | None = None
    status: str = "Completed"
    checked_in: int | None = None
    returned: int | None = None
    cancel_fee: int = 0
    condition: str | None = None
    missing: list[tuple[int, int]] = field(default_factory=list)   # (component_id, qty)
    note: str | None = None
    bid: int = 0


class Calendar:
    """Busy intervals per table and per copy, so generated rows never overlap."""

    def __init__(self) -> None:
        self.table: dict[int, list[tuple[int, int]]] = {}
        self.copy: dict[int, list[tuple[int, int]]] = {}

    @staticmethod
    def _free(slots: list[tuple[int, int]], s: int, e: int) -> bool:
        return all(not (s < b and a < e) for a, b in slots)

    def table_free(self, t: int, s: int, e: int) -> bool:
        return self._free(self.table.get(t, []), s, e)

    def copy_free(self, c: int, s: int, e: int) -> bool:
        return self._free(self.copy.get(c, []), s, e)

    def take(self, b: Booking) -> None:
        hold_end = max(b.end, b.returned or b.end)
        if b.table:
            self.table.setdefault(b.table, []).append((b.start, hold_end))
        if b.copy:
            self.copy.setdefault(b.copy, []).append((b.start - 30, hold_end + 30))


CAL = Calendar()
HISTORY: list[Booking] = []


def tables_for(party: int) -> list[int]:
    return [i for i, t in enumerate(TABLES, start=1) if t[5] and t[2] >= party]


def member_valid(c: Customer, days_ago: int) -> bool:
    return c.join_ago > days_ago and c.expiry >= -days_ago


def add(b: Booking) -> Booking:
    assert b.returned is None or b.returned <= -60, "history must be returned before load day"
    CAL.take(b)
    HISTORY.append(b)
    return b


def fixture_dine_in(cust: int, days_ago: int, hh: int, mm: int, minutes: int, party: int,
                    game: int | None = None, copy: int | None = None, table: int | None = None,
                    **kw) -> Booking:
    s = at(days_ago, hh, mm)
    e = s + minutes
    if game and copy is None:
        copy = next(c for c, g, _ in COPIES if g == game and c not in FIXTURE_COPIES
                    and CAL.copy_free(c, s, e))
    if table is None:
        table = next(t for t in sorted(tables_for(party), key=lambda t: TABLES[t - 1][2])
                     if CAL.table_free(t, s, e))
    kw.setdefault("condition", "Good" if copy else None)
    b = Booking(cust, "Dine_In", s, e, table, copy, party, checked_in=s + 3,
                returned=e - 5, **kw)
    return add(b)


def fixture_take_home(cust: int, days_ago: int, hh: int, days: int, copy: int,
                      returned_delta: int = -120, **kw) -> Booking:
    s = at(days_ago, hh)
    e = s + days * DAY
    kw.setdefault("condition", "Good")
    b = Booking(cust, "Take_Home", s, e, None, copy, None, checked_in=s + 5,
                returned=e + returned_delta, **kw)
    return add(b)


def comp(gid: int, name: str) -> int:
    return next(c[0] for c in COMPONENTS if c[1] == gid and c[2] == name)


# ----- live rows -------------------------------------------------------------------------
OVERDUE = Booking(17, "Take_Home", at(3, 12), at(1, 12), None, FX_COPY_OVERDUE, None,
                  status="Overdue", checked_in=at(3, 12, 10))
CHECKED_IN = Booking(1, "Take_Home", at(1, 17), at(-1, 17), None, FX_COPY_OUT, None,
                     status="Checked_In", checked_in=at(1, 17, 5))
UNAVAILABLE_NOW = FIXTURE_COPIES | {FX_COPY_OVERDUE, FX_COPY_OUT}
CAL.take(OVERDUE)
CAL.take(CHECKED_IN)
LATEST_RETURN = -60   # every historical return happened before 23:00 yesterday

# ----- fixture history -------------------------------------------------------------------
# Q20 / Q22: member 9 completes every Party game, both Dine_In and Take_Home
fixture_dine_in(FX_PARTY_ALL, 60, 18, 0, 120, 4, game=3)
fixture_dine_in(FX_PARTY_ALL, 47, 19, 0, 90, 5, game=12)
fixture_dine_in(FX_PARTY_ALL, 33, 17, 0, 120, 6, game=17)
fixture_dine_in(FX_PARTY_ALL, 20, 20, 0, 120, 8, game=21)
fixture_take_home(FX_PARTY_ALL, 12, 14, 2, copy_of(23, 1))
# BR-13 / T1: member 13 owes Rs 972 for a recent completed session (left unpaid)
FX_OWES_BOOKING = fixture_dine_in(FX_OWES, 4, 18, 0, 180, 4, game=7, table=10)
# Suspended member 19: an unpaid 4-hour session and an unpaid no-show
FX_SUSP_BOOKINGS = [
    fixture_dine_in(FX_SUSPENDED, 25, 12, 0, 240, 6, table=5),
    add(Booking(FX_SUSPENDED, "Dine_In", at(15, 19), at(15, 21), 3, None, 4,
                status="No_Show", cancel_fee=100)),
]
# Q43: Spirit Island only 31-60 days ago, Hanabi only in the last 30 days
fixture_dine_in(5, 45, 15, 0, 180, 3, game=24)
fixture_dine_in(12, 52, 14, 0, 180, 2, game=24)
fixture_dine_in(4, 9, 19, 0, 90, 4, game=25)
fixture_dine_in(22, 17, 18, 30, 60, 3, game=25)
# Jenga #2: came back short three times, worn out -> Retired
for d, qty, cust in ((80, 3, 25), (65, 2, 29), (50, 4, 8)):
    fixture_dine_in(cust, d, 16, 0, 60, 4, game=9, copy=FX_COPY_RETIRED,
                    condition="Worn", missing=[(comp(9, "Wooden blocks"), qty)],
                    note="blocks short on return")
# Jenga #1: returned Damaged -> Under_Repair
fixture_dine_in(30, 30, 13, 0, 60, 5, game=9, copy=FX_COPY_REPAIR)
fixture_dine_in(6, 8, 17, 0, 90, 6, game=9, copy=FX_COPY_REPAIR, condition="Damaged",
                note="tea spilled, several blocks warped")
# Catan #2: last return had pieces missing that are still not restocked -> Missing_Pieces
fixture_dine_in(16, 40, 18, 0, 150, 4, game=1, copy=FX_COPY_MISSING)
FX_MISSING_BOOKING = fixture_take_home(
    28, 6, 12, 3, FX_COPY_MISSING, returned_delta=-240, condition="Fair",
    missing=[(comp(1, "Number tokens"), 2), (comp(1, "Settlements"), 1)],
    note="two number tokens and a settlement missing")

# ----- random history -------------------------------------------------------------------
CONDITION_STEPS = ["New", "Good", "Fair", "Worn"]
copy_condition = {c: RNG.choice(["New", "New", "Good"]) for c, _, _ in COPIES}


def random_dine_in(days_ago: int) -> Booking | None:
    for _ in range(40):
        c = RNG.choice(CUSTOMERS)
        if not member_valid(c, days_ago):
            continue
        party = RNG.choice([2, 2, 3, 4, 4, 4, 5, 6, 6, 8])
        minutes = RNG.choice([60, 90, 120, 120, 150, 180, 180, 240, 300, 360])
        if minutes > c.max_hours * 60:
            continue
        latest = 23 * 60 - minutes
        slot = RNG.randrange(10 * 60, latest + 1, 30)
        s = at(days_ago, 0) + slot
        e = s + minutes
        tables = [t for t in tables_for(party) if CAL.table_free(t, s, e)]
        if not tables:
            continue
        tables.sort(key=lambda t: (TABLES[t - 1][2], RNG.random()))
        table = tables[0] if RNG.random() < 0.7 else RNG.choice(tables)
        copy = None
        if RNG.random() < 0.85:
            games = [g for g in GAMES if g.gid not in FIXTURE_ONLY_GAMES
                     and g.pmin <= party <= g.pmax and g.age <= c.age]
            RNG.shuffle(games)
            for g in games:
                free = [cp for cp, gid, _ in COPIES if gid == g.gid and cp not in FIXTURE_COPIES
                        and CAL.copy_free(cp, s, e + 120)]
                if free:
                    copy = RNG.choice(free)
                    break
        roll = RNG.random()
        b = Booking(c.cid, "Dine_In", s, e, table, copy, party)
        if roll < 0.08:
            b.status, b.cancel_fee = "Cancelled", RNG.choice([0, 0, 100])
        elif roll < 0.15:
            b.status, b.cancel_fee = "No_Show", 100
        else:
            b.checked_in = s + RNG.randint(-10, 10)
            late = RNG.random()
            if late < 0.75:
                b.returned = e + RNG.randint(-20, 10)
            elif late < 0.9:
                b.returned = e + RNG.randint(16, 55)
            else:
                b.returned = e + RNG.randint(61, 100)
            b.returned = max(b.returned, b.checked_in + 30)
            if b.returned > LATEST_RETURN:
                b.returned = e - 10
        return b
    return None


def random_take_home(days_ago: int) -> Booking | None:
    for _ in range(40):
        c = RNG.choice(CUSTOMERS)
        if c.age < 18 or not member_valid(c, days_ago):
            continue
        days = RNG.randint(1, c.max_days)
        if days_ago < days + 2:
            continue
        s = at(days_ago, RNG.randint(11, 20))
        e = s + days * DAY
        games = [g for g in GAMES if g.gid not in FIXTURE_ONLY_GAMES and g.age <= c.age]
        g = RNG.choice(games)
        free = [cp for cp, gid, _ in COPIES if gid == g.gid and cp not in FIXTURE_COPIES
                and CAL.copy_free(cp, s, e + DAY + 600)]
        if not free:
            continue
        b = Booking(c.cid, "Take_Home", s, e, None, RNG.choice(free), None)
        if RNG.random() < 0.06:
            b.status, b.cancel_fee = "Cancelled", 0
            return b
        b.checked_in = s + RNG.randint(0, 20)
        late = RNG.random()
        if late < 0.8:
            b.returned = e - RNG.randint(60, 600)
        elif late < 0.93:
            b.returned = e + RNG.randint(60, 1200)        # 1 started day late
        else:
            b.returned = e + RNG.randint(1500, 2500)      # 2 started days late
        b.returned = max(b.returned, b.checked_in + 60)
        if b.returned > LATEST_RETURN:
            b.returned = e - 120
        return b
    return None


for days_ago in range(90, 0, -1):
    for _ in range(RNG.choice([2, 3, 3, 3])):
        b = random_dine_in(days_ago)
        if b:
            add(b)
    if RNG.random() < 0.6:
        b = random_take_home(days_ago)
        if b:
            add(b)

# inspections: condition drifts slowly; ~13 random returns with missing pieces
completed_with_copy = [b for b in HISTORY if b.status == "Completed" and b.copy]
for b in sorted(completed_with_copy, key=lambda x: x.returned):
    if b.condition is None:
        cur = copy_condition[b.copy]
        idx = CONDITION_STEPS.index(cur)
        if RNG.random() < 0.12 and idx < 3:
            idx += 1
        b.condition = CONDITION_STEPS[max(idx, 1)] if cur == "New" and RNG.random() < 0.5 \
            else CONDITION_STEPS[idx]
    copy_condition[b.copy] = b.condition if b.condition != "Damaged" else "Worn"
candidates = [b for b in completed_with_copy if not b.missing and b.copy not in FIXTURE_COPIES
              and b.customer not in (FX_OWES, FX_SUSPENDED)]
for b in RNG.sample(candidates, 13):
    parts = components_of(COPY_GAME[b.copy])
    for cp in RNG.sample(parts, RNG.choice([1, 1, 2])):
        b.missing.append((cp[0], RNG.randint(1, min(3, cp[3]))))
    b.note = "pieces missing at return check"

# ids in chronological order
HISTORY.sort(key=lambda b: (b.start, b.table or 0, b.copy or 0))
for i, b in enumerate(HISTORY, start=1):
    b.bid = i
INSPECTED = sorted([b for b in HISTORY if b.status == "Completed" and b.copy],
                   key=lambda b: (b.returned, b.bid))
INSPECTION_ID = {b.bid: i for i, b in enumerate(INSPECTED, start=1)}

# ----- payments --------------------------------------------------------------------------
UNPAID_FULL = {FX_OWES_BOOKING.bid} | {b.bid for b in FX_SUSP_BOOKINGS}
partial_pool = [b for b in HISTORY if b.status == "Completed" and b.bid not in UNPAID_FULL
                and b.customer not in (FX_OWES, FX_SUSPENDED)]
PARTIAL: dict[int, int] = {}
seen_customers: set[int] = set()
for b in RNG.sample(partial_pool, len(partial_pool)):
    if b.customer in seen_customers or len(PARTIAL) >= 8:
        continue
    seen_customers.add(b.customer)
    PARTIAL[b.bid] = RNG.choice([50, 80, 100, 120])


# ----- future reservations (CALL sp_create_reservation) -----------------------------------
FUTURE: list[Booking] = []
active_rentals = {17: 1, 1: 1, 6: 1}   # 6 = today's take-home pick-up below
fcal = Calendar()


def plan_future() -> None:
    eligible = [c for c in CUSTOMERS if c.status == "Active" and c.expiry > 0
                and c.cid not in (FX_OWES,)]
    tries = 0
    while len(FUTURE) < 17 and tries < 2000:
        tries += 1
        c = RNG.choice(eligible)
        day = RNG.randint(1, 13)
        if c.expiry < day:
            continue
        party = RNG.choice([2, 3, 4, 4, 5, 6])
        minutes = RNG.choice([60, 90, 120, 120, 180])
        if minutes > c.max_hours * 60:
            continue
        slot = RNG.randrange(11 * 60, 21 * 60 + 1 - minutes + 60, 30)
        s = day * DAY + slot
        e = s + minutes
        if e > day * DAY + 23 * 60:
            continue
        tables = [t for t in tables_for(party) if fcal.table_free(t, s, e)]
        if not tables:
            continue
        table = min(tables, key=lambda t: (TABLES[t - 1][2], t))
        copy = None
        if RNG.random() < 0.7 and active_rentals.get(c.cid, 0) < c.max_rentals:
            games = [g for g in GAMES if g.gid not in NEVER_PLAYED | {9}
                     and g.pmin <= party <= g.pmax and g.age <= c.age]
            RNG.shuffle(games)
            for g in games:
                free = [cp for cp, gid, _ in COPIES if gid == g.gid and cp not in UNAVAILABLE_NOW
                        and fcal.copy_free(cp, s, e)]
                if free:
                    copy = free[0]
                    break
        b = Booking(c.cid, "Dine_In", s, e, table, copy, party, status="Reserved")
        if copy:
            active_rentals[c.cid] = active_rentals.get(c.cid, 0) + 1
        fcal.take(b)
        FUTURE.append(b)
    # three future take-home rentals for adults
    for cid, day, gid in ((3, 2, 6), (20, 5, 11), (26, 9, 14)):
        c = C[cid]
        if active_rentals.get(cid, 0) >= c.max_rentals:
            continue
        s = day * DAY + 12 * 60
        e = s + c.max_days * DAY
        cp = next(cp for cp, g, _ in COPIES if g == gid and cp not in UNAVAILABLE_NOW
                  and fcal.copy_free(cp, s, e))
        b = Booking(cid, "Take_Home", s, e, None, cp, None, status="Reserved")
        active_rentals[cid] = active_rentals.get(cid, 0) + 1
        fcal.take(b)
        FUTURE.append(b)


plan_future()
FUTURE.sort(key=lambda b: b.start)
# A take-home pick-up later today (start = load time + 1 hour), so today's
# floor plan (Q05) is never empty. Member 6 (Basic) has no other active rental.
TODAY_PICKUP_COPY = next(cp for cp, g, _ in COPIES if g == 22 and cp not in UNAVAILABLE_NOW
                         and fcal.copy_free(cp, -DAY, 2 * DAY))


# --------------------------------------------------------------------------- SQL output
def q(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def write() -> None:
    out: list[str] = []
    w = out.append
    n_hist = len(HISTORY)
    n_dine = sum(b.btype == "Dine_In" for b in HISTORY)
    n_take = n_hist - n_dine
    n_missing_returns = sum(1 for b in HISTORY if b.missing)
    w("""-- =====================================================================
-- 08_seed.sql   ***  GENERATED by scripts/generate_seed.py - do not edit  ***
-- Purpose : Demo data. Every date is relative to the day the file is loaded
--           (CURRENT_DATE / NOW()), so it loads correctly on any day.
--           All rows go in through the real triggers and constraints.
-- Run order: 08 (after 07_roles.sql)
-- Lab      : Exp 4 (DML: multi-row INSERT, INSERT ... SELECT, UPDATE with JOIN)
--
-- Volumes : 3 tiers, 8 staff, 10 categories, 25 games, %d copies,
--           %d components, 16 tables, 30 members,
--           %d historical bookings (%d Dine_In, %d Take_Home) over the last 90 days,
--           %d returns with missing pieces, 1 Overdue + 1 Checked_In take-home,
--           %d future reservations created with CALL sp_create_reservation.
--
-- Guaranteed fixtures (tests depend on them):
--   * member %d (%s %s) completed a booking of every Party game          -> Q20
--     and has both Dine_In and Take_Home completed bookings              -> Q22
--   * copy %d (Catan #2) is Missing_Pieces with un-restocked Missing_Pieces rows
--   * copy %d (Jenga #1) is Under_Repair (returned Damaged)
--   * copy %d (Jenga #2) is Retired (came back short three times)
--   * member %d is Suspended, member %d's membership expired 20 days ago,
--     member %d owes more than Rs 500, member %d's membership expires in 5 days
--   * member %d is 14 years old, member %d is 16 years old
--   * table %d (PA-05) is inactive and has never been booked                 -> Q23
--   * Chess has never been booked (Q16); Spirit Island was played only 31-60
--     days ago and Hanabi only in the last 30 days (Q43 full outer join)
-- =====================================================================
USE boardgame_cafe;
""" % (len(COPIES), len(COMPONENTS), n_hist, n_dine, n_take, n_missing_returns, len(FUTURE) + 1,
       FX_PARTY_ALL, C[FX_PARTY_ALL].first, C[FX_PARTY_ALL].last,
       FX_COPY_MISSING, FX_COPY_REPAIR, FX_COPY_RETIRED, FX_SUSPENDED, FX_EXPIRED, FX_OWES,
       FX_EXPIRING, FX_AGE14, FX_AGE16, INACTIVE_TABLE))

    w("-- ---------------------------------------------------------------- 1. reference data")
    w("INSERT INTO Membership_Tiers (tier_id, tier_name, annual_fee, max_concurrent_rentals,\n"
      "                              max_session_hours, max_takehome_days, discount_pct) VALUES")
    w(",\n".join(f"  ({i}, {q(n)}, {f}.00, {r}, {h}, {d}, {p}.00)"
                 for i, (n, f, r, h, d, p) in enumerate(TIERS, start=1)) + ";\n")

    w("INSERT INTO Staff (staff_id, full_name, role, email, hired_on, is_active) VALUES")
    rows = []
    for i, (name, role, ago, active) in enumerate(STAFF, start=1):
        email = name.lower().replace(" ", ".") + "@bgcafe.test"
        rows.append(f"  ({i}, {q(name)}, {q(role)}, {q(email)}, {date_expr(-ago)}, {q(active)})")
    w(",\n".join(rows) + ";\n")

    w("INSERT INTO Game_Categories (category_id, category_name) VALUES")
    w(",\n".join(f"  ({i}, {q(n)})" for i, n in enumerate(CATEGORIES, start=1)) + ";\n")

    w("INSERT INTO Board_Games (game_id, title, publisher, year_published, min_players, max_players,\n"
      "                         min_age, avg_play_minutes, complexity, hourly_rate, daily_rate,\n"
      "                         replacement_cost) VALUES")
    w(",\n".join(f"  ({g.gid}, {q(g.title)}, {q(g.publisher)}, {q(g.year)}, {g.pmin}, {g.pmax}, "
                 f"{g.age}, {g.minutes}, {g.complexity:.1f}, {g.hourly}.00, {g.daily}.00, "
                 f"{g.replacement}.00)" for g in GAMES) + ";\n")

    w("INSERT INTO Board_Game_Categories (game_id, category_id) VALUES")
    w(",\n".join(f"  ({g.gid}, {CATEGORIES.index(cat) + 1})" for g in GAMES for cat in g.cats) + ";\n")

    w("INSERT INTO Game_Copies (copy_id, game_id, barcode, acquired_on, copy_condition, status,\n"
      "                         shelf_location) VALUES")
    rows = []
    for cid, gid, n in COPIES:
        barcode = f"8901{gid:03d}{n:02d}{(gid * 31 + n * 17) % 1000:03d}"
        shelf = f"{'ABCDE'[(gid - 1) // 5]}-{(gid - 1) % 5 + 1:02d}"
        rows.append(f"  ({cid}, {gid}, {q(barcode)}, {date_expr(-RNG.randint(200, 1000))}, "
                    f"'New', 'Available', {q(shelf)})")
    w(",\n".join(rows) + ";\n")

    w("INSERT INTO Game_Components (component_id, game_id, component_name, qty_per_copy,\n"
      "                             unit_replacement_cost) VALUES")
    w(",\n".join(f"  ({i}, {g}, {q(n)}, {qty}, {cost}.00)" for i, g, n, qty, cost in COMPONENTS) + ";\n")

    w("INSERT INTO Cafe_Tables (table_id, table_code, zone, seating_capacity, hourly_rate,\n"
      "                         is_accessible, is_active) VALUES")
    w(",\n".join(f"  ({i}, {q(code)}, {q(zone)}, {cap}, {rate}.00, {q(acc)}, {q(act)})"
                 for i, (code, zone, cap, rate, acc, act) in enumerate(TABLES, start=1)) + ";\n")

    w("-- date_of_birth puts every birthday 100-250 days in the past, so each member's age is the\n"
      "-- same on every date from 90 days ago to 14 days ahead.")
    w("INSERT INTO Customers (customer_id, first_name, last_name, email, phone, date_of_birth,\n"
      "                       tier_id, join_date, membership_expiry, status) VALUES")
    rows = []
    for c in CUSTOMERS:
        email = f"{c.first.lower()}.{c.last.lower()}@mail.test"
        dob = f"CURRENT_DATE - INTERVAL {c.age} YEAR - INTERVAL {c.dob_extra} DAY"
        rows.append(f"  ({c.cid}, {q(c.first)}, {q(c.last)}, {q(email)}, {q(c.phone)}, {dob}, "
                    f"{c.tier}, {date_expr(-c.join_ago)}, {date_expr(c.expiry)}, {q(c.status)})")
    w(",\n".join(rows) + ";\n")

    w("-- ---------------------------------------------------------------- 2. history")
    w("-- Closed bookings are inserted directly with their final status. The BEFORE INSERT\n"
      "-- trigger still validates every row (capacity, players, age, hours, tier limits) and\n"
      "-- prices it; overlap checks apply only to active rows, and none of these overlap anyway.")
    cols = ("booking_id, customer_id, table_id, copy_id, booking_type, party_size, reserved_start, "
            "reserved_end, checked_in_at, returned_at, status, cancellation_fee, created_at")
    for b in HISTORY:
        created = ts(b.start - RNG.randint(1, 5) * DAY - RNG.randint(0, 600))
        w(f"INSERT INTO Rentals_Reservations ({cols}) VALUES\n"
          f"  ({b.bid}, {b.customer}, {q(b.table)}, {q(b.copy)}, {q(b.btype)}, {q(b.party)}, "
          f"{ts(b.start)}, {ts(b.end)}, "
          f"{ts(b.checked_in) if b.checked_in is not None else 'NULL'}, "
          f"{ts(b.returned) if b.returned is not None else 'NULL'}, {q(b.status)}, "
          f"{b.cancel_fee}.00, {created});")
    w("")

    w("-- ---------------------------------------------------------------- 3. late fees (BR-16)")
    w("UPDATE Rentals_Reservations\n"
      "   SET late_fee = fn_calculate_late_fee(booking_id, returned_at)\n"
      " WHERE status = 'Completed' AND returned_at > reserved_end + INTERVAL 15 MINUTE;\n")

    w("-- ---------------------------------------------------------------- 4. inspections (BR-17/18)")
    w("-- Allowed for Completed bookings; trg_insp_after_insert copies the condition to the box.")
    staff_pool = [2, 3, 4, 5, 1]
    for b in INSPECTED:
        inspector = 8 if b.returned < at(70, 0) and RNG.random() < 0.3 else RNG.choice(staff_pool)
        w(f"INSERT INTO Return_Inspections (inspection_id, booking_id, inspected_by, inspected_at, "
          f"condition_on_return, notes) VALUES\n  ({INSPECTION_ID[b.bid]}, {b.bid}, {inspector}, "
          f"{ts(b.returned + 10)}, {q(b.condition)}, {q(b.note)});")
        for comp_id, qty in b.missing:
            w(f"INSERT INTO Missing_Pieces (inspection_id, component_id, qty_missing, charge) "
              f"VALUES ({INSPECTION_ID[b.bid]}, {comp_id}, {qty}, 0);   "
              f"-- charge set by trg_mp_before_insert")
    w("")

    fx_insp = INSPECTION_ID[FX_MISSING_BOOKING.bid]
    w("-- ---------------------------------------------------------------- 5. restock + copy statuses")
    w(f"-- Every lost piece has been replaced except the last return of copy {FX_COPY_MISSING}.")
    w("UPDATE Missing_Pieces mp\n"
      "  JOIN Return_Inspections ri ON ri.inspection_id = mp.inspection_id\n"
      "   SET mp.restocked_at = LEAST(ri.inspected_at + INTERVAL 1 DAY, NOW())\n"
      f" WHERE mp.inspection_id <> {fx_insp};")
    w("-- Inspections moved copies around while history loaded: put every box back on the\n"
      "-- shelf, then set the fixture copies explicitly.")
    w("UPDATE Game_Copies SET status = 'Available';")
    w(f"UPDATE Game_Copies SET status = 'Missing_Pieces' WHERE copy_id = {FX_COPY_MISSING};")
    w(f"UPDATE Game_Copies SET status = 'Under_Repair'   WHERE copy_id = {FX_COPY_REPAIR};")
    w(f"UPDATE Game_Copies SET status = 'Retired'        WHERE copy_id = {FX_COPY_RETIRED};\n")

    w("-- ---------------------------------------------------------------- 6. payments (PAY-01/02)")
    w("-- Payments go in BEFORE the future reservations: otherwise every member with history\n"
      "-- owes more than Rs 500 and sp_create_reservation (correctly) refuses them all (BR-13).")
    unpaid = ", ".join(str(x) for x in sorted(UNPAID_FULL | set(PARTIAL)))
    w("INSERT INTO Payments (booking_id, amount, method, paid_at)\n"
      "SELECT booking_id, total_amount, ELT(1 + booking_id % 3, 'Cash', 'Card', 'UPI'),\n"
      "       COALESCE(returned_at, reserved_start)\n"
      "  FROM Rentals_Reservations\n"
      " WHERE status IN ('Completed', 'Cancelled', 'No_Show') AND total_amount > 0\n"
      f"   AND booking_id NOT IN ({unpaid})\n"
      " ORDER BY booking_id;")
    w("-- A few members still owe a little (at most Rs 120 each) on one visit")
    for bid, left in sorted(PARTIAL.items()):
        w(f"INSERT INTO Payments (booking_id, amount, method, paid_at)\n"
          f"SELECT booking_id, total_amount - {left}, 'UPI', returned_at\n"
          f"  FROM Rentals_Reservations WHERE booking_id = {bid} AND total_amount > {left};")
    w("")

    w("-- ---------------------------------------------------------------- 7. live rows")
    w("-- Overdue take-home: inserted as Checked_In (trg_rr_after_insert marks the copy Rented),\n"
      "-- then moved to Overdue - the same transition ev_mark_overdue makes.")
    for b in (OVERDUE, CHECKED_IN):
        w("INSERT INTO Rentals_Reservations (customer_id, table_id, copy_id, booking_type, party_size,\n"
          "                                  reserved_start, reserved_end, checked_in_at, status)\n"
          f"VALUES ({b.customer}, NULL, {b.copy}, 'Take_Home', NULL, {ts(b.start)}, {ts(b.end)}, "
          f"{ts(b.checked_in)}, 'Checked_In');")
        if b.status == "Overdue":
            w("UPDATE Rentals_Reservations SET status = 'Overdue' WHERE booking_id = LAST_INSERT_ID();")
    w("")

    w("-- ---------------------------------------------------------------- 8. future reservations")
    w("-- Created through the real workflow procedure (BR-13 account checks, BR-14 window,\n"
      "-- FOR UPDATE locks), exactly as the front desk would.")
    for b in FUTURE:
        w(f"CALL sp_create_reservation({b.customer}, {q(b.btype)}, {q(b.table)}, {q(b.copy)}, "
          f"{q(b.party)}, {ts(b.start)}, {ts(b.end)}, @booking_id);")
    w(f"-- Take-home pick-up later today (one hour after the file is loaded)")
    w(f"CALL sp_create_reservation(6, 'Take_Home', NULL, {TODAY_PICKUP_COPY}, NULL,\n"
      f"     DATE_FORMAT(NOW() + INTERVAL 1 HOUR, '%Y-%m-%d %H:%i:00'),\n"
      f"     DATE_FORMAT(NOW() + INTERVAL 1 HOUR + INTERVAL 1 DAY, '%Y-%m-%d %H:%i:00'), @booking_id);\n")

    w("-- ---------------------------------------------------------------- summary")
    w("SELECT (SELECT COUNT(*) FROM Customers) AS customers,\n"
      "       (SELECT COUNT(*) FROM Game_Copies) AS copies,\n"
      "       (SELECT COUNT(*) FROM Rentals_Reservations) AS bookings,\n"
      "       (SELECT COUNT(*) FROM Return_Inspections) AS inspections,\n"
      "       (SELECT COUNT(*) FROM Missing_Pieces) AS missing_piece_rows,\n"
      "       (SELECT COUNT(*) FROM Payments) AS payments,\n"
      "       (SELECT COUNT(*) FROM Booking_Audit_Log) AS audit_rows;")
    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}: {n_hist} historical bookings ({n_dine} Dine_In, "
          f"{n_take} Take_Home), {len(INSPECTED)} inspections, {n_missing_returns} with missing "
          f"pieces, {len(FUTURE) + 1} future reservations")


if __name__ == "__main__":
    write()
