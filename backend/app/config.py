import os
from pathlib import Path
DATA_DIR = Path(os.environ.get("DATA_DIR", Path(__file__).resolve().parent.parent / "data"))
DB_FILENAME = "app.db"
