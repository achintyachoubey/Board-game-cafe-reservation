#!/usr/bin/env python3
"""Build the Board Game Cafe database by running the SQL files in order.

    python scripts/build_db.py                  # 00 -> 08 into boardgame_cafe
    python scripts/build_db.py --skip-seed      # 00 -> 07 (empty tables)
    python scripts/build_db.py --with-demos     # 00 -> 08, then 09 -> 13
    python scripts/build_db.py --db boardgame_cafe_try   # another database name

When --db differs from boardgame_cafe, every literal `boardgame_cafe` in the SQL
text is replaced by the new name and the roles / demo users get a matching
suffix (cafe_admin_try, desk_priya_try, ...), so a test build never touches the
student's real database, roles or users.

This module is also the shared toolkit for capture_evidence.py and the tests:
config loading, connections, a DELIMITER-aware SQL splitter, the name
renderer and a statement runner that understands three comment directives:

    -- @as desk_priya          run the following statements as that demo user
    -- @as admin               switch back to the admin connection from .env
    -- @expect-error 1142      the next statement must fail with this code or
                               message fragment (e.g. PAY-02, 1369, BR-05)

The directives are ordinary SQL comments, so the files still run unchanged in
the mysql shell or MySQL Workbench.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pymysql
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
DEFAULT_DB = "boardgame_cafe"
ROLES = ("cafe_admin", "front_desk", "analyst")
DEMO_USERS = ("desk_priya", "owner_ravi", "report_bot")
SPEC_DEMO_PASSWORD = "ChangeMe#2026"

BUILD_FILES = [
    "00_drop_all.sql", "01_schema.sql", "02_functions.sql", "03_procedures.sql",
    "04_triggers.sql", "05_views.sql", "06_events.sql", "07_roles.sql", "08_seed.sql",
]
DEMO_FILES = [
    "09_queries.sql", "10_demo_transactions.sql", "11_demo_indexing.sql",
    "12_demo_lab_extras.sql", "13_walkthrough.sql",
]


# --------------------------------------------------------------------------- config
@dataclass(frozen=True)
class Config:
    host: str
    port: int
    user: str
    password: str
    db_name: str
    demo_password: str
    demo_host: str
    use_ssl: bool


def load_config() -> Config:
    """Read connection settings from .env (falls back to .env.example values)."""
    load_dotenv(ROOT / ".env")
    if not os.getenv("DB_PASSWORD") and not (ROOT / ".env").exists():
        load_dotenv(ROOT / ".env.example")
    return Config(
        host=os.getenv("DB_HOST", "127.0.0.1"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", ""),
        db_name=os.getenv("DB_NAME", DEFAULT_DB),
        demo_password=os.getenv("DEMO_USER_PASSWORD", SPEC_DEMO_PASSWORD),
        demo_host=os.getenv("DEMO_USER_HOST", "localhost"),
        use_ssl=os.getenv("DB_SSL", "1").lower() not in ("0", "false", "no"),
    )


def connect(cfg: Config, user: str | None = None, password: str | None = None,
            database: str | None = None, autocommit: bool = True) -> pymysql.connections.Connection:
    """Open a connection; exits with a readable message if the server is unreachable.

    TLS is used by default (without certificate verification - this is a local
    lab server): MySQL 8's caching_sha2_password then works without the extra
    'cryptography' package. Set DB_SSL=0 in .env if your server has TLS disabled.
    """
    kwargs: dict[str, Any] = dict(
        host=cfg.host, port=cfg.port, user=user or cfg.user,
        password=cfg.password if password is None else password,
        database=database, autocommit=autocommit, charset="utf8mb4",
        connect_timeout=10,
    )
    if cfg.use_ssl:
        kwargs["ssl"] = {"check_hostname": False}
    try:
        return pymysql.connect(**kwargs)
    except pymysql.err.OperationalError as exc:
        code = exc.args[0] if exc.args else None
        if code in (2003, 2005, 2006, 2013):
            raise SystemExit(
                f"Cannot reach MySQL at {cfg.host}:{cfg.port} ({exc}).\n"
                "  * Docker: run `docker compose up -d` and wait until "
                "`docker compose ps` shows (healthy).\n"
                "  * Local server: start the MySQL80 service and check DB_HOST/DB_PORT in .env."
            ) from exc
        raise


# --------------------------------------------------------------------------- naming
def suffix_for(db_name: str) -> str:
    """'boardgame_cafe' -> '';  'boardgame_cafe_test_ab12' -> '_test_ab12';  'x' -> '_x'."""
    if db_name == DEFAULT_DB:
        return ""
    if db_name.startswith(DEFAULT_DB + "_"):
        return db_name[len(DEFAULT_DB):]
    return "_" + db_name


def demo_user(name: str, db_name: str) -> str:
    return name + suffix_for(db_name)


def render_sql(text: str, db_name: str, cfg: Config) -> str:
    """Point the SQL text at db_name and give roles/users the matching suffix."""
    sfx = suffix_for(db_name)
    if db_name != DEFAULT_DB:
        text = re.sub(r"\bboardgame_cafe\b", db_name, text)
        text = re.sub(r"\bcafe_sandbox\b", "cafe_sandbox" + sfx, text)
        for name in ROLES + DEMO_USERS:
            text = text.replace(f"'{name}'", f"'{name}{sfx}'")
    if cfg.demo_host != "localhost":
        text = text.replace("@'localhost'", f"@'{cfg.demo_host}'")
    if cfg.demo_password != SPEC_DEMO_PASSWORD:
        escaped = cfg.demo_password.replace("\\", "\\\\").replace("'", "''")
        text = text.replace(f"'{SPEC_DEMO_PASSWORD}'", f"'{escaped}'")
    return text


# --------------------------------------------------------------------------- splitter
@dataclass
class Statement:
    sql: str                         # text sent to the server (no delimiter)
    line: int                        # 1-based line where the statement starts
    preamble: str = ""               # comments between the previous statement and this one
    trailing: str = ""               # a "-- comment" on the same line after the delimiter
    as_user: str | None = None       # from "-- @as NAME" (sticky until the next @as)
    expect_error: str | None = None  # from "-- @expect-error X"


_DELIM_RE = re.compile(r"^[ \t]*DELIMITER[ \t]+(\S+)[ \t]*$", re.IGNORECASE)


def split_sql(text: str) -> list[Statement]:
    """Split a script the way the mysql client does (quotes, comments, DELIMITER)."""
    stmts: list[Statement] = []
    delim = ";"
    buf: list[str] = []          # characters of the current statement
    comments: list[str] = []     # comment text seen while buf is still empty
    stmt_line = 1
    i, n, line = 0, len(text), 1
    current_user: str | None = None

    def buf_empty() -> bool:
        return not "".join(buf).strip()

    def flush(end_index: int) -> int:
        nonlocal buf, comments, current_user
        sql = "".join(buf).strip()
        # A "-- comment" right after the delimiter on the same line belongs to this statement.
        j = end_index
        while j < n and text[j] in " \t":
            j += 1
        trailing = ""
        if text.startswith("--", j) and (j + 2 >= n or text[j + 2] in " \t\r\n"):
            k = text.find("\n", j)
            k = n if k == -1 else k
            trailing = text[j:k].strip()
            end_index = k
        preamble = "\n".join(comments)
        expect = None
        for m in re.finditer(r"@as[ \t]+(\w+)", preamble):
            current_user = None if m.group(1).lower() == "admin" else m.group(1)
        m = re.search(r"@expect-error[ \t]+(\S+)", preamble)
        if m:
            expect = m.group(1)
        if sql:
            stmts.append(Statement(sql, stmt_line, preamble, trailing, current_user, expect))
        buf, comments = [], []
        return end_index

    while i < n:
        ch = text[i]
        at_line_start = i == 0 or text[i - 1] == "\n"
        if at_line_start and buf_empty():
            eol = text.find("\n", i)
            eol = n if eol == -1 else eol
            m = _DELIM_RE.match(text[i:eol])
            if m:
                delim = m.group(1)
                i = eol
                continue
        if buf_empty() and ch not in " \t\r\n" and not text.startswith(("--", "/*", "#"), i):
            stmt_line = line
        # comments
        if text.startswith("--", i) and (i + 2 >= n or text[i + 2] in " \t\r\n"):
            eol = text.find("\n", i)
            eol = n if eol == -1 else eol
            if buf_empty():
                comments.append(text[i:eol])
            else:
                buf.append(text[i:eol])
            i = eol
            continue
        if ch == "#":
            eol = text.find("\n", i)
            eol = n if eol == -1 else eol
            if buf_empty():
                comments.append(text[i:eol])
            i = eol
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end == -1 else end + 2
            chunk = text[i:end]
            if buf_empty():
                comments.append(chunk)
            else:
                buf.append(chunk)
            line += chunk.count("\n")
            i = end
            continue
        # quoted strings / identifiers
        if ch in ("'", '"', "`"):
            j = i + 1
            while j < n:
                if text[j] == "\\" and ch != "`":
                    j += 2
                    continue
                if text[j] == ch:
                    if j + 1 < n and text[j + 1] == ch:  # doubled quote
                        j += 2
                        continue
                    break
                j += 1
            chunk = text[i:j + 1]
            buf.append(chunk)
            line += chunk.count("\n")
            i = j + 1
            continue
        # delimiter
        if text.startswith(delim, i):
            i = flush(i + len(delim))
            continue
        if ch == "\n":
            line += 1
        buf.append(ch)
        i += 1
    flush(n)
    return stmts


# --------------------------------------------------------------------------- runner
@dataclass
class ResultSet:
    columns: list[str]
    rows: list[tuple]


@dataclass
class Outcome:
    stmt: Statement
    result_sets: list[ResultSet] = field(default_factory=list)
    rowcount: int | None = None
    error_code: int | None = None
    error_msg: str | None = None
    warnings: list[tuple] = field(default_factory=list)
    seconds: float = 0.0

    @property
    def ok(self) -> bool:
        return self.error_code is None

    @property
    def error_text(self) -> str:
        return f"ERROR {self.error_code}: {self.error_msg}" if self.error_code else ""

    @property
    def met_expectation(self) -> bool:
        """True when an @expect-error statement failed as expected, or a normal one succeeded."""
        if self.stmt.expect_error is None:
            return self.ok
        return (not self.ok) and self.stmt.expect_error.lower() in self.error_text.lower()


def execute(conn: pymysql.connections.Connection, stmt: Statement) -> Outcome:
    """Run one statement and collect every result set (CALL can return several)."""
    out = Outcome(stmt)
    started = time.perf_counter()
    try:
        with conn.cursor() as cur:
            cur.execute(stmt.sql)
            out.rowcount = cur.rowcount
            while True:
                if cur.description:
                    out.result_sets.append(
                        ResultSet([d[0] for d in cur.description], list(cur.fetchall())))
                if not cur.nextset():
                    break
        out.warnings = list(conn.show_warnings() or [])
    except pymysql.err.MySQLError as exc:
        out.error_code = exc.args[0] if exc.args else -1
        out.error_msg = exc.args[1] if len(exc.args) > 1 else str(exc)
        # A failed statement can leave an open transaction (e.g. SAVEPOINT demo);
        # that is intended, so nothing is rolled back here.
    out.seconds = time.perf_counter() - started
    return out


class Runner:
    """Executes statements, switching connections for `-- @as user` directives."""

    def __init__(self, cfg: Config, db_name: str):
        self.cfg = cfg
        self.db_name = db_name
        self.admin = connect(cfg, database=None)
        self._users: dict[str, pymysql.connections.Connection] = {}

    def conn_for(self, stmt: Statement) -> pymysql.connections.Connection:
        if not stmt.as_user:
            return self.admin
        name = demo_user(stmt.as_user, self.db_name)
        if name not in self._users:
            self._users[name] = connect(self.cfg, user=name, password=self.cfg.demo_password)
        return self._users[name]

    def run_text(self, text: str) -> list[Outcome]:
        return [execute(self.conn_for(s), s) for s in split_sql(render_sql(text, self.db_name, self.cfg))]

    def run_file(self, path: Path) -> list[Outcome]:
        return self.run_text(path.read_text(encoding="utf-8"))

    def close(self) -> None:
        for c in [self.admin, *self._users.values()]:
            try:
                c.close()
            except Exception:
                pass


# Notes the build is known to produce on a clean server; anything else is reported.
EXPLAINED_NOTES = {
    1008: "DROP DATABASE IF EXISTS on a database that does not exist yet",
    3162: "DROP USER/ROLE IF EXISTS (or CREATE ... IF NOT EXISTS) on an account that does not exist / already exists",
    3163: "CREATE ROLE/USER IF NOT EXISTS on an account that already exists",
    1305: "DROP ... IF EXISTS on an object that does not exist",
    1537: "CREATE EVENT IF NOT EXISTS on an event that already exists",
}


def build(cfg: Config, db_name: str, skip_seed: bool = False, with_demos: bool = False,
          quiet: bool = False) -> dict[str, Any]:
    """Run 00 -> 08 (and optionally 09 -> 13). Raises RuntimeError on the first unexpected error."""
    files = [f for f in BUILD_FILES if not (skip_seed and f == "08_seed.sql")]
    if with_demos:
        files += DEMO_FILES
    runner = Runner(cfg, db_name)
    summary: dict[str, Any] = {"files": {}, "warnings": [], "statements": 0}
    try:
        for fname in files:
            path = SQL_DIR / fname
            if not path.exists():
                raise RuntimeError(f"{path} is missing (generate 08 with scripts/generate_seed.py)")
            t0 = time.perf_counter()
            outcomes = runner.run_file(path)
            demo = fname in DEMO_FILES
            for o in outcomes:
                if not o.met_expectation:
                    what = o.error_text or f"succeeded but {o.stmt.expect_error} was expected"
                    raise RuntimeError(f"{fname} line {o.stmt.line}: {what}\n{o.stmt.sql[:400]}")
                for w in o.warnings:
                    summary["warnings"].append((fname, o.stmt.line, *w))
            summary["statements"] += len(outcomes)
            summary["files"][fname] = (len(outcomes), time.perf_counter() - t0)
            if not quiet:
                kind = "demo " if demo else ""
                print(f"  ok  {fname:<28} {len(outcomes):>5} {kind}statements "
                      f"({time.perf_counter() - t0:.1f}s)")
    finally:
        runner.close()
    return summary


def report_warnings(summary: dict[str, Any]) -> int:
    """Print warnings; return how many are not on the explained list."""
    unexplained = 0
    for fname, line, level, code, msg in summary["warnings"]:
        tag = EXPLAINED_NOTES.get(code)
        if tag and level == "Note":
            continue
        unexplained += 1
        print(f"  {level} {code} in {fname} line {line}: {msg}")
    explained = len(summary["warnings"]) - unexplained
    print(f"Warnings: {unexplained} unexplained, {explained} expected notes "
          f"(IF [NOT] EXISTS on objects that did not exist / already existed).")
    return unexplained


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", help="database name (default: DB_NAME from .env, i.e. boardgame_cafe)")
    ap.add_argument("--skip-seed", action="store_true", help="do not load sql/08_seed.sql")
    ap.add_argument("--with-demos", action="store_true", help="also run sql/09 .. sql/13")
    args = ap.parse_args(argv)
    cfg = load_config()
    db = args.db or cfg.db_name
    if not re.fullmatch(r"[A-Za-z0-9_]{1,40}", db):
        raise SystemExit("--db must be letters, digits and underscores (max 40 characters)")
    print(f"Building `{db}` on {cfg.host}:{cfg.port} as {cfg.user} "
          f"(demo users @'{cfg.demo_host}', suffix '{suffix_for(db)}')")
    t0 = time.perf_counter()
    try:
        summary = build(cfg, db, args.skip_seed, args.with_demos)
    except RuntimeError as exc:
        print(f"BUILD FAILED: {exc}", file=sys.stderr)
        return 1
    bad = report_warnings(summary)
    print(f"Build finished: {summary['statements']} statements, 0 errors, "
          f"{bad} unexplained warnings, {time.perf_counter() - t0:.1f}s.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
