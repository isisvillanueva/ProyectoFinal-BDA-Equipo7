# -*- coding: utf-8 -*-
"""
Migración PostgreSQL → MongoDB
Clona las tablas relevantes de hospital_db a MongoDB (hospital_mongo).
Uso: python3 migrate_to_mongo.py
"""

import psycopg2
from psycopg2.extras import RealDictCursor
from pymongo import MongoClient, ASCENDING
import datetime

PG_CONFIG = dict(
    host="127.0.0.1",
    database="hospital_db",
    user="hospital_user",
    password="AIR795",
    port=5432,
)

MONGO_URI = "mongodb://hospital_mongo_user:AIR795@localhost:27017/hospital_mongo"
MONGO_DB  = "hospital_mongo"

TABLES = [
    "equipo",
    "estado_equipos",
    "movimiento",
    "area_registro",
    "ubicacion_especifica",
    "tipo_movimientos",
    "mantenimiento",
    "tipo_mantenimientos",
    "tipo_resultado_mantenimientos",
    "biomedico",
    "persona",
    "asignacion_equipo",
    "uso_clinico_equipo",
    "responsable_area",
    "enfermero",
]


def serialize_row(row: dict) -> dict:
    """Convierte tipos no-JSON (Decimal, date) a tipos Python estándar."""
    out = {}
    for k, v in row.items():
        if isinstance(v, datetime.datetime):
            out[k] = v
        elif isinstance(v, datetime.date):
            out[k] = datetime.datetime(v.year, v.month, v.day)
        else:
            try:
                import decimal
                if isinstance(v, decimal.Decimal):
                    out[k] = float(v)
                else:
                    out[k] = v
            except Exception:
                out[k] = v
    return out


def migrate_table(pg_cur, mg_db, table: str) -> int:
    pg_cur.execute(f"SELECT * FROM {table}")
    rows = pg_cur.fetchall()
    if not rows:
        print(f"  {table}: vacía, sin cambios")
        return 0

    docs = [serialize_row(dict(r)) for r in rows]
    col = mg_db[table]
    col.drop()
    col.insert_many(docs)
    return len(docs)


def create_indexes(mg_db):
    mg_db.equipo.create_index([("id_equipo", ASCENDING)])
    mg_db.equipo.create_index([("activo_equipo", ASCENDING)])
    mg_db.equipo.create_index([("id_estado_equipo", ASCENDING)])
    mg_db.equipo.create_index([("id_ubicacion_administrativa_actual", ASCENDING)])

    mg_db.estado_equipos.create_index([("id_estado_equipo", ASCENDING)])

    mg_db.movimiento.create_index([("id_equipo", ASCENDING)])
    mg_db.movimiento.create_index([("id_tipo_movimiento", ASCENDING)])
    mg_db.movimiento.create_index([("id_ubicacion_origen", ASCENDING)])
    mg_db.movimiento.create_index([("id_ubicacion_destino", ASCENDING)])
    mg_db.movimiento.create_index([("fecha_hora_movimiento", ASCENDING)])

    mg_db.mantenimiento.create_index([("id_equipo", ASCENDING)])
    mg_db.mantenimiento.create_index([("id_biomedico", ASCENDING)])
    mg_db.mantenimiento.create_index([("id_tipo_mantenimiento", ASCENDING)])
    mg_db.mantenimiento.create_index([("id_resultado_mantenimiento", ASCENDING)])
    mg_db.mantenimiento.create_index([("fecha_hora_mantenimiento", ASCENDING)])

    mg_db.ubicacion_especifica.create_index([("id_ubicacion", ASCENDING)])
    mg_db.ubicacion_especifica.create_index([("id_area", ASCENDING)])

    mg_db.area_registro.create_index([("id_area", ASCENDING)])

    mg_db.tipo_movimientos.create_index([("id_tipo_movimiento", ASCENDING)])
    mg_db.tipo_mantenimientos.create_index([("id_tipo_mantenimiento", ASCENDING)])
    mg_db.tipo_resultado_mantenimientos.create_index([("id_resultado_mantenimiento", ASCENDING)])

    mg_db.biomedico.create_index([("id_biomedico", ASCENDING)])
    mg_db.biomedico.create_index([("id_persona", ASCENDING)])

    mg_db.persona.create_index([("id_persona", ASCENDING)])

    mg_db.asignacion_equipo.create_index([("id_equipo", ASCENDING)])
    mg_db.uso_clinico_equipo.create_index([("id_equipo", ASCENDING)])

    mg_db.responsable_area.create_index([("id_area", ASCENDING)])
    mg_db.responsable_area.create_index([("id_enfermero", ASCENDING)])

    mg_db.enfermero.create_index([("id_enfermero", ASCENDING)])
    mg_db.enfermero.create_index([("id_persona", ASCENDING)])


def main():
    print("=== Migración PostgreSQL → MongoDB ===")
    print(f"Origen : hospital_db (PostgreSQL)")
    print(f"Destino: {MONGO_DB} (MongoDB)")
    print()

    pg_conn  = psycopg2.connect(**PG_CONFIG, cursor_factory=RealDictCursor)
    mg_client = MongoClient(MONGO_URI)
    mg_db    = mg_client[MONGO_DB]

    with pg_conn.cursor() as cur:
        for table in TABLES:
            try:
                n = migrate_table(cur, mg_db, table)
                print(f"  ✓ {table}: {n} documentos migrados")
            except Exception as e:
                print(f"  ✗ {table}: ERROR — {e}")

    print()
    print("Creando índices...")
    create_indexes(mg_db)
    print("  ✓ Índices creados")

    pg_conn.close()
    mg_client.close()
    print()
    print("Migración completada.")


if __name__ == "__main__":
    main()
