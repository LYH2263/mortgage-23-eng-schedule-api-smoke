import sqlite3
from app.config import DATA_DIR, DB_FILENAME
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / DB_FILENAME
def connect() -> sqlite3.Connection:
    c = sqlite3.connect(DB_PATH); c.row_factory = sqlite3.Row; return c
