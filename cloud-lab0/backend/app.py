import os

import psycopg2
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FRONTEND_DIR = os.path.join(BASE_DIR, "..", "frontend")

app = Flask(__name__)
# CORS — на случай, если фронт будет открыт с другого адреса/порта.
CORS(app)

# Параметры подключения берутся из переменных окружения —
# так их будет легко менять при контейнеризации.
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "notes_db"),
    "user": os.getenv("DB_USER", "notes_user"),
    "password": os.getenv("DB_PASSWORD", "notes_pass"),
}


def get_conn():
    return psycopg2.connect(**DB_CONFIG)


def init_db():
    """Создаёт таблицу, если её ещё нет."""
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


@app.get("/")
def index():
    # Отдаём фронтенд с того же адреса, что и API — проблем с CORS не будет.
    return send_from_directory(FRONTEND_DIR, "index.html")


@app.get("/api/health")
def health():
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify(status="ok", db="up")
    except Exception as e:
        return jsonify(status="error", db="down", detail=str(e)), 500


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
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
