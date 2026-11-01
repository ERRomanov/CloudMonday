import os
import time

import psycopg2
from flask import Flask, jsonify, request

app = Flask(__name__)

# Идентификатор экземпляра, по нему видно, какая копия бэкенда ответила.
INSTANCE_ID = os.getenv("INSTANCE_ID", "backend-1")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "notes_db"),
    "user": os.getenv("DB_USER", "notes_user"),
    "password": os.getenv("DB_PASSWORD", "notes_pass"),
}


def get_conn():
    return psycopg2.connect(**DB_CONFIG)


def init_db(retries=10):
    """Создаёт таблицу. Повторяет попытки: база может ещё не быть готова,
    а два экземпляра могут одновременно выполнять CREATE TABLE."""
    for attempt in range(1, retries + 1):
        try:
            with get_conn() as conn, conn.cursor() as cur:
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS notes (
                        id SERIAL PRIMARY KEY,
                        text TEXT NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                    )
                    """
                )
            return
        except psycopg2.Error as e:
            if attempt == retries:
                raise
            print(f"init_db: попытка {attempt} не удалась: {e}", flush=True)
            time.sleep(1)


@app.after_request
def add_instance_header(resp):
    resp.headers["X-Instance-Id"] = INSTANCE_ID
    return resp


@app.get("/api/health")
def health():
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify(status="ok", db="up", instance=INSTANCE_ID)
    except Exception as e:
        return jsonify(status="error", db="down", instance=INSTANCE_ID, detail=str(e)), 500


@app.get("/api/notes")
def list_notes():
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, text, created_at FROM notes ORDER BY id DESC")
        rows = cur.fetchall()
    return jsonify(
        [{"id": r[0], "text": r[1], "created_at": r[2].isoformat()} for r in rows]
    )


@app.post("/api/notes")
def add_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text:
        return jsonify(error="Поле text обязательно"), 400
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO notes (text) VALUES (%s) RETURNING id, text, created_at",
            (text,),
        )
        r = cur.fetchone()
    return jsonify({"id": r[0], "text": r[1], "created_at": r[2].isoformat()}), 201


if __name__ == "__main__":
    init_db()
    # Статику и HTTPS отдаёт nginx, поэтому бэкенд слушает только localhost.
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5001")))
