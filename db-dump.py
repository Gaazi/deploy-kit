#!/usr/bin/env python3
"""
DEPLOY KIT — db-dump.py (generic MySQL backup/restore without mysqldump)

Shared-hosting servers often lack mysqldump. This tool uses pymysql (already
installed in the app's venv) to dump/restore the database from DATABASE_URL
in the app's .env — works on ANY project that uses a MySQL DATABASE_URL.

Usage:
  db-dump.py dump    <env-file> <out-file>   # write plain SQL dump
  db-dump.py restore <env-file> <sql-file>   # execute sql-file (safety dump first)

Dump format: plain SQL, header "-- MySQL dump (deploy-kit python)" — matches
deploy-kit's backup verification. Rows are written in chunks (CHUNK_ROWS per
INSERT) so a big table neither exhausts memory nor exceeds MySQL's
max_allowed_packet on restore. The dump is written to <out-file>.part and only
renamed on success: a dump that dies half-way must never be left behind
looking like a valid backup. Restore runs with FOREIGN_KEY_CHECKS=0 and takes
a pre-restore safety dump first (double-layer protection).
"""
import os
import re
import sys
from datetime import datetime
from urllib.parse import parse_qs, unquote, urlsplit

CHUNK_ROWS = 500        # rows per INSERT statement (memory + packet safety)

# MySQL string escaping (self-contained: pymysql.converters.escape_bytes_prefixed
# is a "DO NOT IMPORT THIS!!!" string in PyMySQL >= 1.x and made BLOB dumps crash).
_ESC = {i: chr(i) for i in range(256)}
_ESC.update({0: "\\0", 8: "\\b", 9: "\\t", 10: "\\n", 11: "\\v", 12: "\\f",
             13: "\\r", 26: "\\Z", 34: '\\"', 39: "\\'", 92: "\\\\"})


def fail(msg):
    print("❌ db-dump: " + msg, file=sys.stderr)
    sys.exit(1)


def read_database_url(env_file):
    """Read DATABASE_URL from the app's .env (quotes/CRLF/`export` all handled)."""
    if not os.path.isfile(env_file):
        fail("env file not found: " + env_file)
    line = ""
    with open(env_file, "r", encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            match = re.match(r"^\s*(?:export\s+)?DATABASE_URL\s*=(.*)$", ln)
            if match:
                line = match.group(1).strip()
                break
    if not line:
        fail("DATABASE_URL not found in " + env_file)
    line = line.strip("'\"")
    if "://" not in line:
        fail("DATABASE_URL has no scheme")
    return line


def connect(url):
    """Connect to the exact endpoint in DATABASE_URL (port + unix_socket too)."""
    try:
        import pymysql
    except ImportError:
        fail("pymysql not installed in this python — run with the app's venv python")
    parts = urlsplit(url)
    # .username/.password are NOT percent-decoded by urlsplit (verified) —
    # SQLAlchemy/Django URLs encode @ : / in passwords, so decode them here.
    user = unquote(parts.username) if parts.username else ""
    password = unquote(parts.password) if parts.password else ""
    database = unquote(parts.path.lstrip("/"))
    if not database:
        fail("no database name in DATABASE_URL")
    kwargs = {
        "user": user, "password": password, "database": database,
        "charset": "utf8mb4", "connect_timeout": 15,
    }
    socket_path = parse_qs(parts.query).get("unix_socket", [""])[0]
    if socket_path:
        kwargs["unix_socket"] = socket_path          # socket-only MySQL
    else:
        kwargs["host"] = parts.hostname or "localhost"
        if parts.port:
            kwargs["port"] = parts.port              # custom port was ignored before
    return pymysql.connect(**kwargs)


def esc(v):
    """Escape a value for a MySQL statement (no external dependency)."""
    if v is None:
        return "NULL"
    if isinstance(v, (bytes, bytearray)):
        return "_binary X'" + bytes(v).hex() + "'"
    return "'" + str(v).translate(_ESC) + "'"


def write_dump(conn, out):
    """Write a plain-SQL dump of every table. Returns the table count.

    One cursor's result set is always fully consumed before the next query is
    sent on the connection (pymysql is unbuffered — mixing them would
    desynchronise the protocol).
    """
    cur = conn.cursor()
    cur.execute("SHOW TABLES")
    tables = [r[0] for r in cur.fetchall()]
    out.write("SET FOREIGN_KEY_CHECKS=0;\n\n")
    for table in tables:
        name = table.replace("`", "")
        cur.execute("SHOW CREATE TABLE `" + name + "`")
        out.write("DROP TABLE IF EXISTS `" + name + "`;\n")
        out.write(cur.fetchone()[1] + ";\n\n")
        cols_cur = conn.cursor()
        cols_cur.execute("SELECT * FROM `" + name + "`")
        collist = ",".join("`" + d[0].replace("`", "") + "`" for d in cols_cur.description)
        rows = cols_cur.fetchmany(CHUNK_ROWS)
        while rows:
            out.write("INSERT INTO `" + name + "` (" + collist + ") VALUES\n")
            out.write(",\n".join("(" + ",".join(esc(v) for v in row) + ")" for row in rows))
            out.write(";\n\n")
            rows = cols_cur.fetchmany(CHUNK_ROWS)
        cols_cur.close()
    out.write("SET FOREIGN_KEY_CHECKS=1;\n")
    cur.close()
    return len(tables)


def cmd_dump(env_file, out_file):
    url = read_database_url(env_file)
    conn = connect(url)
    tmp = out_file + ".part"
    try:
        with open(tmp, "w", encoding="utf-8") as out:
            out.write("-- MySQL dump (deploy-kit python)\n")
            out.write("-- " + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + "\n\n")
            tables = write_dump(conn, out)
    except Exception as exc:                      # noqa: BLE001 - reported, then exit
        if os.path.exists(tmp):
            os.remove(tmp)
        fail("dump failed: " + str(exc))
    finally:
        conn.close()
    os.replace(tmp, out_file)                     # only a complete dump is kept
    if tables:
        print("✅ dump written: " + out_file + " (" + str(tables) + " tables)")
    else:
        # An empty database is valid (fresh install) — the deploy must not abort.
        print("✅ dump written: " + out_file + " (0 tables — empty database)")


def split_statements(text):
    """Split our own dump format into statements.

    Data newlines are escaped (\\n two chars), so a statement ends exactly at
    a line whose trailing char is ';'. Comment-only groups are separated but
    their non-comment lines (SET etc.) are kept.
    """
    stmts = []
    buf = []
    for ln in text.split("\n"):
        buf.append(ln)
        if ln.rstrip().endswith(";"):
            stmt = "\n".join(buf).strip()
            buf = []
            # drop pure-comment lines inside the group, keep real commands
            body = "\n".join(
                l for l in stmt.split("\n") if not l.strip().startswith("--")
            ).strip()
            if body:
                stmts.append(body)
    return [s for s in stmts if s]


def cmd_restore(env_file, sql_file):
    url = read_database_url(env_file)
    if not os.path.isfile(sql_file):
        fail("dump file not found: " + sql_file)
    if os.path.getsize(sql_file) == 0:
        fail("dump file is EMPTY — refusing to restore")
    if sql_file.endswith(".gz"):
        fail("restore expects a plain .sql dump (uncompress first: gunzip)")
    conn = connect(url)
    cur = conn.cursor()

    # double-layer safety: dump CURRENT state first (tagged pre_restore)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safety = os.path.join(os.path.dirname(sql_file) or ".", "pre_restore_" + stamp + ".sql")
    with open(safety, "w", encoding="utf-8") as out:
        out.write("-- MySQL dump (deploy-kit python) — PRE-RESTORE SAFETY\n")
        out.write("-- " + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + "\n\n")
        tables = write_dump(conn, out)
    print("🛡️  pre-restore safety dump: " + safety + " (" + str(tables) + " tables)")

    with open(sql_file, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    stmts = split_statements(text)
    if not stmts:
        fail("no statements found in dump")
    cur.execute("SET FOREIGN_KEY_CHECKS=0")
    done = 0
    for stmt in stmts:
        try:
            cur.execute(stmt)
        except Exception as exc:                  # noqa: BLE001 - reported, then exit
            fail("restore stopped after " + str(done) + " statements: " + str(exc)
                 + " — the safety dump is at " + safety)
        done += 1
    conn.commit()
    cur.execute("SET FOREIGN_KEY_CHECKS=1")
    conn.commit()
    cur.close()
    conn.close()
    print("✅ restored: " + sql_file + " (" + str(done) + " statements)")


def main():
    if len(sys.argv) < 4:
        print("usage: db-dump.py dump|restore <env-file> <file>", file=sys.stderr)
        sys.exit(2)
    mode, env_file, path = sys.argv[1], sys.argv[2], sys.argv[3]
    if mode == "dump":
        cmd_dump(env_file, path)
    elif mode == "restore":
        cmd_restore(env_file, path)
    else:
        fail("unknown mode: " + mode)


if __name__ == "__main__":
    main()
