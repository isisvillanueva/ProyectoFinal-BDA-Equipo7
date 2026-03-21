from flask import Flask, render_template, redirect, url_for, flash
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)
app.secret_key = "proyecto_bda_equipo7"

# Configuración de PostgreSQL
app.config["DB_HOST"] = "localhost"
app.config["DB_NAME"] = "hospital"
app.config["DB_USER"] = "postgres"      # cámbialo si usarás otro usuario
app.config["DB_PASSWORD"] = "667725"  # cámbialo por tu contraseña real
app.config["DB_PORT"] = "5432"


def get_db_connection(): # Conexión a la BD
    conn = psycopg2.connect(
        host=app.config["DB_HOST"],
        database=app.config["DB_NAME"],
        user=app.config["DB_USER"],
        password=app.config["DB_PASSWORD"],
        port=app.config["DB_PORT"],
        cursor_factory=RealDictCursor
    )
    return conn


@app.route("/")
def inicio():
    return redirect(url_for("admin_dashboard"))


@app.route("/admin")
def admin_dashboard():
    db_status = False
    db_info = {}

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT current_database() AS database, current_user AS user;")
        db_info = cur.fetchone()
        db_status = True

        cur.close()
        conn.close()

    except Exception as e:
        flash(f"Error al conectar con PostgreSQL: {e}", "error")

    return render_template(
        "admin_dashboard.html",
        db_status=db_status,
        db_info=db_info
    )


@app.route("/clinico")
def clinico_dashboard():
    db_status = False
    db_info = {}

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT current_database() AS database, current_user AS user;")
        db_info = cur.fetchone()
        db_status = True

        cur.close()
        conn.close()

    except Exception as e:
        flash(f"Error al conectar con PostgreSQL: {e}", "error")

    return render_template(
        "clinico_dashboard.html",
        db_status=db_status,
        db_info=db_info
    )


@app.route("/test-db")
def test_db():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT version();")
        version = cur.fetchone()

        cur.close()
        conn.close()

        return {
            "ok": True,
            "mensaje": "Conexión exitosa a PostgreSQL",
            "version": version["version"]
        }

    except Exception as e:
        return {
            "ok": False,
            "mensaje": "Error de conexión",
            "error": str(e)
        }, 500


if __name__ == "__main__":
    app.run(debug=True)