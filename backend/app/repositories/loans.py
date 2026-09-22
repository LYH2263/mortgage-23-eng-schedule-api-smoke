import sqlite3
def list_all(conn): return [dict(r) for r in conn.execute("SELECT * FROM loans ORDER BY id").fetchall()]
def get(conn, lid):
    row = conn.execute("SELECT * FROM loans WHERE id=?", (lid,)).fetchone()
    return dict(row) if row else None
