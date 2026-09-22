import sqlite3
def get_map(conn): return {r["key"]: r["value"] for r in conn.execute("SELECT * FROM settings").fetchall()}
