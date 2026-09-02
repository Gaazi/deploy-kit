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
deploy-kit's backup verification. Restore runs with FOREIGN_KEY_CHECKS=0 and
takes a pre-restore safety dump first (double-layer protection).
"""
import sys
import os
import re
import gzip
from datetime import datetime


def fail(msg):
    print("❌ db-dump: " + msg, file=sys.stderr)
    sys.exit(1)


def read_database_url(env_file):
    """Read DATABASE_URL from the app's .env (strip quotes/comments)."""
    if not os.path.isfile(env_file):
        fail("env file not found: " + env_file)
    line = ""
    with open(env_file, "r", encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            if ln.startswith("DATABASE_URL="):
                line = ln.split("=", 1)[1].strip()
                break
    if not line:
        fail("DATABASE_URL not found in " + env_file)
    line = line.strip("'\"")
    if "://" not in line:
        fail("DATABASE_URL has no scheme")
    return line


def connect(url):
    try:
        import pymysql
    except ImportError:
        fail("pymysql not installed in this python — run with the app's venv python")
    # strip scheme (mysql, mysql+pymysql, mysql+aiomysql all OK)
    rest = re.sub(r"^[a-z0-9+]+://", "", url, flags=re.I)
    userinfo = rest.rsplit("@", 1)[0]
    hostport = rest.rsplit("@", 1)[1]
    user = userinfo.split(":", 1)[0] if ":" in userinfo else userinfo
    password = userinfo.split(":", 1)[1] if ":" in userinfo else ""
    host = hostport.split("/", 1)[0].split(":", 1)[0]
    db = hostport.split("/", 1)[1].split("?", 1)[0] if "/" in hostport else ""
    if not db:
        fail("no database name in DATABASE_URL")
    return pymysql.connect(
        host=host, user=user, password=password, database=db,
        charset="utf8mb4", connect_timeout=15,
    )


def esc(v):
    """Escape a value for a MySQL statement (pymysql converter)."""
    try:
        from pymysql.converters import escape_string
        from pymysql.converters import escape_bytes_prefixed
    except ImportError:
        def escape_string(v):
            return v.replace("\\", "\\\\").replace("'", "\\'")
        def escape_bytes_prefixed(v):
            return "_binary'" + v.replace("\\", "\\\\").replace("'", "\\'") + "'"
    if v is None:
        return "NULL"
    if isinstance(v, (bytes, bytearray)):
        return escape_bytes_prefixed(v)
    return "'" + escape_string(str(v)) + "'"


def cmd_dump(env_file, out_file):
    url = read_database_url(env_file)
    conn = connect(url)
    cur = conn.cursor()
    cur.execute("SHOW TABLES")
    tables = [r[0] for r in cur.fetchall()]
    if not tables:
        fail("database has no tables — nothing to dump")
    with open(out_file, "w", encoding="utf-8") as out:
        out.write("-- MySQL dump (deploy-kit python)\n")
        out.write("-- " + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + "\n\n")
        out.write("SET FOREIGN_KEY_CHECKS=0;\n\n")
        for t in tables:
            cur.execute("SHOW CREATE TABLE `" + t.replace("`", "") + "`")
            create = cur.fetchone()[1]
            out.write("DROP TABLE IF EXISTS `" + t + "`;\n")
            out.write(create + ";\n\n")
            cur2 = conn.cursor()
            count = cur2.execute("SELECT * FROM `" + t.replace("`", "") + "`")
            cols = [d[0] for d in cur2.description]
            collist = ",".join("`" + c.replace("`", "") + "`" for c in cols)
            if count:
                rows = cur2.fetchall()
                out.write("INSERT INTO `" + t + "` (" + collist + ") VALUES\n")
                lines = []
                for row in rows:
                    vals = ",".join(esc(v) for v in row)
                    lines.append("(" + vals + ")")
                out.write(",\n".join(lines) + ";\n\n")
            cur2.close()
        out.write("SET FOREIGN_KEY_CHECKS=1;\n")
    cur.close()
    conn.close()
    print("✅ dump written: " + out_file + " (" + str(len(tables)) + " tables)")


def split_statements(text):
    """Split our own dump format into statements.

    Data newlines are escaped (\n two chars), so a statement ends exactly at
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
    safety = os.path.join(os.path.dirname(sql_file), "pre_restore_" + stamp + ".sql")
    cur.execute("SHOW TABLES")
    tables = [r[0] for r in cur.fetchall()]
    with open(safety, "w", encoding="utf-8") as out:
        out.write("-- MySQL dump (deploy-kit python) — PRE-RESTORE SAFETY\n")
        out.write("SET FOREIGN_KEY_CHECKS=0;\n\n")
        for t in tables:
            cur.execute("SHOW CREATE TABLE `" + t.replace("`", "") + "`")
            out.write("DROP TABLE IF EXISTS `" + t + "`;\n")
            out.write(cur.fetchone()[1] + ";\n\n")
            cur2 = conn.cursor()
            cur2.execute("SELECT * FROM `" + t.replace("`", "") + "`")
            cols = [d[0] for d in cur2.description]
            collist = ",".join("`" + c.replace("`", "") + "`" for c in cols)
            rows = cur2.fetchall()
            if rows:
                out.write("INSERT INTO `" + t + "` (" + collist + ") VALUES\n")
                lines = ["(" + ",".join(esc(v) for v in row) + ")" for row in rows]
                out.write(",\n".join(lines) + ";\n\n")
            cur2.close()
    print("🛡️  pre-restore safety dump: " + safety + " (" + str(len(tables)) + " tables)")

    with open(sql_file, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    stmts = split_statements(text)
    if not stmts:
        fail("no statements found in dump")
    cur.execute("SET FOREIGN_KEY_CHECKS=0")
    done = 0
    for s in stmts:
        cur.execute(s)
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
