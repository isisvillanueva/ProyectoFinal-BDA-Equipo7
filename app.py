# -*- coding: utf-8 -*-
from flask import Flask, render_template, redirect, url_for, flash, request, session, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor
from functools import wraps
from pymongo import MongoClient
import datetime
import threading
from itsdangerous import URLSafeSerializer, BadSignature

app = Flask(__name__)
app.secret_key = "hospitaliot_equipo7_secret"

# Token compartido con beacon_scanner.py
BEACON_SCRIPT_TOKEN = "beacon_scanner_token_hospital7"
# Estado en memoria del último heartbeat recibido desde beacon_scanner.py
_beacon_state: dict = {
    "activo": False, "id_beacon": None,
    "zona": None, "rssi": None, "ts": None,
}
_beacon_lock = threading.Lock()

DB_CONFIG = dict(
    host="127.0.0.1",
    database="hospital_db",
    user="hospital_user",
    password="AIR795",
    port=5432
)

MONGO_URI = "mongodb://hospital_mongo_user:AIR795@localhost:27017/hospital_mongo"
MONGO_DB  = "hospital_mongo"

_mongo_client = None

def get_mongo_db():
    global _mongo_client
    if _mongo_client is None:
        _mongo_client = MongoClient(MONGO_URI)
    return _mongo_client[MONGO_DB]

def get_db():
    conn = psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)
    print("CONEXIÓN EXITOSA")
    return conn

# Helper: convierte lista de RealDictRow ? lista de dict planos
# Necesario para jsonify y para |tojson en plantillas Jinja2
def to_dicts(rows):
    return [dict(r) for r in rows]


# ── MongoDB helpers para datos de gráficas ────────────────────────────────────

def mg_rpt_estados(mg):
    pipeline = [
        {"$match": {"activo_equipo": True}},
        {"$lookup": {"from": "estado_equipos", "localField": "id_estado_equipo",
                     "foreignField": "id_estado_equipo", "as": "estado"}},
        {"$unwind": "$estado"},
        {"$group": {"_id": "$estado.estado_equipo", "total": {"$sum": 1}}},
        {"$project": {"estado_equipo": "$_id", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.equipo.aggregate(pipeline))


def mg_rpt_mas_movidos(mg):
    from_date = datetime.datetime(2025, 1, 1)
    pipeline = [
        {"$match": {"fecha_hora_movimiento": {"$gte": from_date}}},
        {"$group": {"_id": "$id_equipo", "total_movimientos": {"$sum": 1}}},
        {"$lookup": {"from": "equipo", "localField": "_id",
                     "foreignField": "id_equipo", "as": "eq"}},
        {"$unwind": "$eq"},
        {"$project": {"nombre_equipo": "$eq.nombre_equipo",
                      "codigo_interno": "$eq.codigo_interno",
                      "total_movimientos": 1, "_id": 0}},
        {"$sort": {"total_movimientos": -1}},
        {"$limit": 20},
    ]
    return list(mg.movimiento.aggregate(pipeline))


def mg_rpt_carga_bio(mg):
    from_date = datetime.datetime(2025, 1, 1)
    pipeline = [
        {"$match": {"fecha_hora_mantenimiento": {"$gte": from_date}}},
        {"$group": {"_id": "$id_biomedico", "total_mantenimientos": {"$sum": 1}}},
        {"$lookup": {"from": "biomedico", "localField": "_id",
                     "foreignField": "id_biomedico", "as": "bio"}},
        {"$unwind": "$bio"},
        {"$lookup": {"from": "persona", "localField": "bio.id_persona",
                     "foreignField": "id_persona", "as": "pers"}},
        {"$unwind": "$pers"},
        {"$project": {
            "biomedico": {"$concat": ["$pers.nombre_persona", " ", "$pers.apellido_persona"]},
            "total_mantenimientos": 1, "_id": 0
        }},
        {"$sort": {"total_mantenimientos": -1}},
    ]
    return list(mg.mantenimiento.aggregate(pipeline))


def mg_rpt_uso_vs_mant(mg):
    equipos = list(mg.equipo.find({"activo_equipo": True},
                                  {"_id": 0, "id_equipo": 1, "codigo_interno": 1, "nombre_equipo": 1}))
    uso_counts  = {}
    mant_counts = {}
    for u in mg.uso_clinico_equipo.find({}, {"_id": 0, "id_equipo": 1, "id_uso_clinico": 1}):
        uso_counts.setdefault(u["id_equipo"], set()).add(u["id_uso_clinico"])
    for m in mg.mantenimiento.find({}, {"_id": 0, "id_equipo": 1, "id_mantenimiento": 1}):
        mant_counts.setdefault(m["id_equipo"], set()).add(m["id_mantenimiento"])
    return sorted(
        [{"codigo_interno": e["codigo_interno"], "nombre_equipo": e["nombre_equipo"],
          "total_usos":  len(uso_counts.get(e["id_equipo"], set())),
          "total_mants": len(mant_counts.get(e["id_equipo"], set()))}
         for e in equipos],
        key=lambda x: x["total_usos"], reverse=True
    )


def mg_rpt_movs_area(mg):
    areas    = list(mg.area_registro.find({}, {"_id": 0}))
    ubics    = list(mg.ubicacion_especifica.find({}, {"_id": 0}))
    ubic_map = {u["id_ubicacion"]: u["id_area"] for u in ubics}
    area_names = {a["id_area"]: a["nombre_area"] for a in areas}

    area_equip = {a["id_area"]: set() for a in areas}
    for e in mg.equipo.find({"activo_equipo": True},
                             {"_id": 0, "id_equipo": 1, "id_ubicacion_administrativa_actual": 1}):
        uid = e.get("id_ubicacion_administrativa_actual")
        if uid and uid in ubic_map:
            area_equip[ubic_map[uid]].add(e["id_equipo"])

    area_movs = {a["id_area"]: 0 for a in areas}
    for m in mg.movimiento.find({}, {"_id": 0, "id_movimiento": 1,
                                     "id_ubicacion_origen": 1, "id_ubicacion_destino": 1}):
        seen = set()
        for uid in [m.get("id_ubicacion_origen"), m.get("id_ubicacion_destino")]:
            if uid and uid in ubic_map:
                aid = ubic_map[uid]
                key = (aid, m.get("id_movimiento"))
                if key not in seen:
                    area_movs[aid] = area_movs.get(aid, 0) + 1
                    seen.add(key)

    return sorted(
        [{"area": area_names[aid], "total_movs": area_movs.get(aid, 0),
          "equipos_involucrados": len(area_equip.get(aid, set()))}
         for aid in area_names],
        key=lambda x: x["total_movs"], reverse=True
    )


def mg_rpt_freq_mov(mg):
    pipeline = [
        {"$group": {"_id": "$id_tipo_movimiento", "total": {"$sum": 1}}},
        {"$lookup": {"from": "tipo_movimientos", "localField": "_id",
                     "foreignField": "id_tipo_movimiento", "as": "tipo"}},
        {"$unwind": "$tipo"},
        {"$project": {"tipo_movimiento": "$tipo.tipo_movimiento", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.movimiento.aggregate(pipeline))


def mg_rpt_por_tipo_mant(mg):
    pipeline = [
        {"$group": {"_id": "$id_tipo_mantenimiento", "total": {"$sum": 1}}},
        {"$lookup": {"from": "tipo_mantenimientos", "localField": "_id",
                     "foreignField": "id_tipo_mantenimiento", "as": "tipo"}},
        {"$unwind": "$tipo"},
        {"$project": {"tipo_mantenimiento": "$tipo.tipo_mantenimiento", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.mantenimiento.aggregate(pipeline))


def mg_rpt_por_resultado(mg):
    pipeline = [
        {"$group": {"_id": "$id_resultado_mantenimiento", "total": {"$sum": 1}}},
        {"$lookup": {"from": "tipo_resultado_mantenimientos", "localField": "_id",
                     "foreignField": "id_resultado_mantenimiento", "as": "res"}},
        {"$unwind": "$res"},
        {"$project": {"resultado_mantenimiento": "$res.resultado_mantenimiento",
                      "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.mantenimiento.aggregate(pipeline))


def mg_rpt_equipos_mas_mant(mg):
    pipeline = [
        {"$group": {"_id": "$id_equipo", "total_mants": {"$sum": 1},
                    "ultimo_mant": {"$max": "$fecha_hora_mantenimiento"}}},
        {"$lookup": {"from": "equipo", "localField": "_id",
                     "foreignField": "id_equipo", "as": "eq"}},
        {"$unwind": "$eq"},
        {"$project": {"nombre_equipo": "$eq.nombre_equipo",
                      "total_mants": 1, "ultimo_mant": 1, "_id": 0}},
        {"$sort": {"total_mants": -1}},
        {"$limit": 10},
    ]
    return list(mg.mantenimiento.aggregate(pipeline))


def mg_rpt_movs_por_mes(mg):
    _meses = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
    pipeline = [
        {"$group": {"_id": {
            "year": {"$year": "$fecha_hora_movimiento"},
            "month": {"$month": "$fecha_hora_movimiento"}
        }, "total": {"$sum": 1}}},
        {"$sort": {"_id.year": 1, "_id.month": 1}},
    ]
    rows = list(mg.movimiento.aggregate(pipeline))
    return [
        {"mes": f"{_meses[r['_id']['month']-1]} {r['_id']['year']}", "total": r["total"]}
        for r in rows
    ]


def mg_rpt_mants_por_mes(mg):
    _meses = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
    pipeline = [
        {"$group": {"_id": {
            "year": {"$year": "$fecha_hora_mantenimiento"},
            "month": {"$month": "$fecha_hora_mantenimiento"}
        }, "total": {"$sum": 1}}},
        {"$sort": {"_id.year": 1, "_id.month": 1}},
    ]
    rows = list(mg.mantenimiento.aggregate(pipeline))
    return [
        {"mes": f"{_meses[r['_id']['month']-1]} {r['_id']['year']}", "total": r["total"]}
        for r in rows
    ]


def mg_rpt_estados_area(mg, id_area):
    ubic_ids = [u["id_ubicacion"] for u in
                mg.ubicacion_especifica.find({"id_area": id_area}, {"id_ubicacion": 1, "_id": 0})]
    pipeline = [
        {"$match": {"activo_equipo": True,
                    "id_ubicacion_administrativa_actual": {"$in": ubic_ids}}},
        {"$lookup": {"from": "estado_equipos", "localField": "id_estado_equipo",
                     "foreignField": "id_estado_equipo", "as": "estado"}},
        {"$unwind": "$estado"},
        {"$group": {"_id": "$estado.estado_equipo", "total": {"$sum": 1}}},
        {"$project": {"estado_equipo": "$_id", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.equipo.aggregate(pipeline))


def mg_rpt_tipos_movs(mg, id_area):
    ubic_ids = [u["id_ubicacion"] for u in
                mg.ubicacion_especifica.find({"id_area": id_area}, {"id_ubicacion": 1, "_id": 0})]
    pipeline = [
        {"$match": {"$or": [{"id_ubicacion_origen": {"$in": ubic_ids}},
                             {"id_ubicacion_destino": {"$in": ubic_ids}}]}},
        {"$group": {"_id": "$id_tipo_movimiento", "total": {"$sum": 1}}},
        {"$lookup": {"from": "tipo_movimientos", "localField": "_id",
                     "foreignField": "id_tipo_movimiento", "as": "tipo"}},
        {"$unwind": "$tipo"},
        {"$project": {"tipo_movimiento": "$tipo.tipo_movimiento", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.movimiento.aggregate(pipeline))


def mg_rpt_actividad_equipos(mg, id_area):
    ubic_ids = [u["id_ubicacion"] for u in
                mg.ubicacion_especifica.find({"id_area": id_area}, {"id_ubicacion": 1, "_id": 0})]
    equipos = list(mg.equipo.find(
        {"activo_equipo": True, "id_ubicacion_administrativa_actual": {"$in": ubic_ids}},
        {"_id": 0, "id_equipo": 1, "nombre_equipo": 1}
    ))
    eq_ids = [e["id_equipo"] for e in equipos]

    asig_cnt = {}
    for a in mg.asignacion_equipo.find({"id_equipo": {"$in": eq_ids}},
                                        {"_id": 0, "id_equipo": 1, "id_asignacion": 1}):
        asig_cnt.setdefault(a["id_equipo"], set()).add(a["id_asignacion"])

    uso_cnt = {}
    for u in mg.uso_clinico_equipo.find({"id_equipo": {"$in": eq_ids}},
                                         {"_id": 0, "id_equipo": 1, "id_uso_clinico": 1}):
        uso_cnt.setdefault(u["id_equipo"], set()).add(u["id_uso_clinico"])

    return sorted(
        [{"nombre_equipo": e["nombre_equipo"],
          "veces_asignado": len(asig_cnt.get(e["id_equipo"], set())),
          "usos_clinicos":  len(uso_cnt.get(e["id_equipo"], set()))}
         for e in equipos],
        key=lambda x: x["veces_asignado"] + x["usos_clinicos"],
        reverse=True
    )


def mg_rpt_mis_equipos_usados(mg, id_persona):
    pipeline = [
        {"$match": {"id_persona_responsable_uso": id_persona}},
        {"$group": {"_id": "$id_equipo", "total_usos": {"$sum": 1}}},
        {"$lookup": {"from": "equipo", "localField": "_id",
                     "foreignField": "id_equipo", "as": "eq"}},
        {"$unwind": "$eq"},
        {"$project": {"nombre_equipo": "$eq.nombre_equipo", "total_usos": 1, "_id": 0}},
        {"$sort": {"total_usos": -1}},
        {"$limit": 8},
    ]
    return list(mg.uso_clinico_equipo.aggregate(pipeline))


def mg_rpt_mis_usos_por_mes(mg, id_persona):
    _meses = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
    pipeline = [
        {"$match": {"id_persona_responsable_uso": id_persona}},
        {"$group": {"_id": {
            "year": {"$year": "$fecha_hora_inicio"},
            "month": {"$month": "$fecha_hora_inicio"}
        }, "total": {"$sum": 1}}},
        {"$sort": {"_id.year": 1, "_id.month": 1}},
    ]
    rows = list(mg.uso_clinico_equipo.aggregate(pipeline))
    return [
        {"mes": f"{_meses[r['_id']['month']-1]} {r['_id']['year']}", "total": r["total"]}
        for r in rows
    ]


def mg_rpt_movs_por_dia(mg, id_area):
    _dias = {1:"Dom",2:"Lun",3:"Mar",4:"Mié",5:"Jue",6:"Vie",7:"Sáb"}
    ubic_ids = [u["id_ubicacion"] for u in
                mg.ubicacion_especifica.find({"id_area": id_area}, {"id_ubicacion": 1, "_id": 0})]
    pipeline = [
        {"$match": {"$or": [{"id_ubicacion_origen": {"$in": ubic_ids}},
                             {"id_ubicacion_destino": {"$in": ubic_ids}}]}},
        {"$group": {"_id": {"$dayOfWeek": "$fecha_hora_movimiento"}, "total": {"$sum": 1}}},
        {"$sort": {"_id": 1}},
    ]
    rows = list(mg.movimiento.aggregate(pipeline))
    day_map = {r["_id"]: r["total"] for r in rows}
    return [{"dia": _dias[d], "total": day_map.get(d, 0)} for d in [2,3,4,5,6,7,1]]


# FASE 1 Infraestructura de Auditor?a
# set_audit_context: inyecta app.id_usuario y app.origen en la
# sesion de PostgreSQL LOCAL (dura solo hasta el fin del bloque
# WITH ? AS c).  El trigger fn_auditoria_generica lee estas
# variables mediante current_setting('app.id_usuario', TRUE).
# Sin esta llamada el trigger usa id_usuario=1 ('Admin/Sistema')
# para TODOS los cambios, perdiendo la trazabilidad real.

def set_audit_context(cur, origen: str = "web") -> None:
    """Inyecta el contexto de auditoría en la sesión PostgreSQL.

    Debe llamarse con el cursor ABIERTO, antes de cualquier
    INSERT / UPDATE / CALL dentro de la misma transacción.

    Args:
        cur:    Cursor psycopg2 ya dentro de un bloque 'with conn'.
        origen: Etiqueta libre que identifica la ruta o módulo
                que origina el cambio (ej. 'web_admin', 'web_bio').
    """
    uid = session.get("id_usuario", 1)
    cur.execute(
        "SELECT set_config('app.id_usuario', %s, TRUE),"
        "       set_config('app.origen',     %s, TRUE)",
        (str(uid), origen),
    )


# FASE 2 Mensajes amigables para errores de triggers de BD
# Centraliza la traduccion de excepciones PostgreSQL en mensajes
# comprensibles para el usuario, evitando pantallas 500.
_TRIGGER_MESSAGES = {
    "turno activo":           "El personal no está en su turno activo en este momento. "
                              "Verifica el turno asignado y la hora actual.",
    "uso clinico activo":     "El equipo ya tiene un uso clínico abierto sin cerrar. "
                              "Cierra el uso activo antes de registrar uno nuevo.",
    "no esta disponible":     "El equipo no está disponible para esta operación. "
                              "Verifica su estado actual.",
    "no está disponible":     "El equipo no está disponible para esta operación. "
                              "Verifica su estado actual.",
    "ubicacion origen":       "La ubicación de origen no coincide con la ubicación "
                              "administrativa actual del equipo. Recarga la página.",
    "ubicación origen":       "La ubicación de origen no coincide con la ubicación "
                              "administrativa actual del equipo. Recarga la página.",
    "conductor no tiene":     "El conductor indicado no tiene un usuario activo con rol Conductor.",
    "ambulancia no esta":     "La ambulancia seleccionada no está activa para traslados.",
    "requiere reemplazo":     "El equipo no cumple las condiciones para ser retirado "
                              "(debe estar en estado Fuera de servicio con resultado "
                              "'Requiere reemplazo').",
    "especialidad requerida": "El enfermero no tiene la especialidad requerida para "
                              "ser responsable de esta área.",
    "ya es el responsable":   "Ese enfermero ya es el responsable activo de esta área.",
    "traslape de periodos":   "Ya existe un periodo de asignación/responsabilidad activo "
                              "que se traslapa con el nuevo. Cierra el anterior primero.",
    "no existe o está dado de baja": "El equipo seleccionado no existe o ya fue dado de baja.",
    "no existe o esta dado de baja": "El equipo seleccionado no existe o ya fue dado de baja.",
    "fecha de inicio debe ser anterior": "La fecha de inicio debe ser anterior a la fecha de fin.",
    "fecha futura":           "La nueva fecha de programación debe ser una fecha futura.",
    "solo se pueden reprogramar": "Solo se pueden reprogramar mantenimientos en estado "
                                  "Pendiente o Vencido.",
    "biomedico con usuario activo": "El biomédico asociado no tiene un usuario activo en el sistema.",
    "correo duplicado":             "Ya existe una persona registrada con ese correo electrónico.",
    "username duplicado":           "Ese nombre de usuario ya está en uso.",
    "persona ya tiene usuario":     "La persona seleccionada ya tiene un usuario asociado.",
    "requiere especialidad y turno": "El rol seleccionado requiere especialidad y turno.",
    "requiere turno":               "El rol Biomédico requiere seleccionar un turno.",
    "no es responsable activo":     "El enfermero no es responsable activo de ningún área.",
    "ya es el responsable":         "El enfermero ya es el responsable activo de esa área.",
    "especialidad requerida":       "La especialidad del enfermero no coincide con la requerida para esa área.",
}


def friendly_db_error(exc: Exception) -> str:
    """Devuelve un mensaje legible a partir de una excepción de BD.

    Recorre _TRIGGER_MESSAGES buscando la primera clave que aparezca
    (case-insensitive) en el mensaje de la excepción.  Si no hay
    coincidencia devuelve el mensaje original para que el admin
    pueda diagnosticar el problema.
    """
    raw = str(exc).lower()
    for key, msg in _TRIGGER_MESSAGES.items():
        if key.lower() in raw:
            return msg
    # Fallback: mostrar el mensaje original acortado
    original = str(exc)
    return original[:300] if len(original) > 300 else original


# Decoradores de autenticación / autorización
def login_required(f):
    @wraps(f)
    def inner(*a, **kw):
        if "id_usuario" not in session:
            flash("Inicia sesión primero.", "error")
            return redirect(url_for("login_view"))
        return f(*a, **kw)
    return inner


def role_required(*roles):
    def dec(f):
        @wraps(f)
        def inner(*a, **kw):
            if "id_usuario" not in session:
                return redirect(url_for("login_view"))
            if session.get("rol") not in roles:
                flash("Sin permisos.", "error")
                return redirect(url_for("dashboard"))
            return f(*a, **kw)
        return inner
    return dec


def _dashboard_enfermero():
    """Redirige al dashboard correcto según si el usuario es responsable o enfermero."""
    if session.get("rol") == "responsable":
        return redirect(url_for("responsable_v"))
    return redirect(url_for("enfermero_v"))


# Helpers de rol
def rol_desde_db(id_usuario, id_persona=None):
    """Consulta el rol del usuario en la BD.
    Si el usuario es Enfermero y tiene área activa en responsable_area → 'responsable'.
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT r.rol_usuario
                    FROM usuario_rol ur
                    JOIN roles_usuario r
                        ON r.id_rol_usuario = ur.id_rol_usuario
                    WHERE ur.id_usuario = %s;
                """, (id_usuario,))
                row = cur.fetchone()
                if row:
                    v = row["rol_usuario"].lower()
                    if "biomédico" in v or "biomedico" in v: return "biomedico"
                    if "enfermero" in v:
                        # Verificar si es responsable de área
                        if id_persona:
                            cur.execute("""
                                SELECT 1 FROM responsable_area ra
                                JOIN enfermero en ON en.id_enfermero = ra.id_enfermero
                                WHERE en.id_persona = %s
                                  AND ra.fecha_fin_responsable_area IS NULL
                                LIMIT 1
                            """, (id_persona,))
                            if cur.fetchone():
                                return "responsable"
                        return "enfermero"
                    if "médico" in v or "medico" in v: return "medico"
                    if "admin" in v or "administrador" in v: return "admin"
    except Exception:
        pass
    return "sin_rol"


def rol_desde_username(u):
    u = u.lower()
    for prefix, rol in [
        ("admin",       "admin"),
        ("biomedico",   "biomedico"),
        ("enfermero",   "enfermero"),
        ("medico",      "medico"),
        ("responsable", "responsable"),
    ]:
        if u.startswith(prefix):
            return rol
    return "sin_rol"


# Catálogos para formularios de Admin
# SCHEMA NOTES:
#   - equipo NO tiene marca/modelo directos  JOIN modelo_equipo + marca_equipo
#   - equipo NO tiene id_categoria_equipo    vive en tipo_equipos
#   - equipo NO tiene id_ubicacion          id_ubicacion_administrativa_actual
#   - se añaden marcas, modelos y criticidades para el formulario de registro
def _admin_catalogs(cur):
    cur.execute("SELECT id_tipo_equipo, tipo_equipo FROM tipo_equipos ORDER BY tipo_equipo")
    tipos_equipo = to_dicts(cur.fetchall())

    cur.execute("SELECT id_categoria_equipo, categoria_equipo FROM categoria_equipos ORDER BY categoria_equipo")
    categorias = to_dicts(cur.fetchall())

    cur.execute("SELECT id_estado_equipo, estado_equipo FROM estado_equipos ORDER BY estado_equipo")
    estados_cat = to_dicts(cur.fetchall())

    cur.execute("SELECT id_ubicacion, nombre_ubicacion FROM ubicacion_especifica ORDER BY nombre_ubicacion")
    ubicaciones = to_dicts(cur.fetchall())

    cur.execute("""
        SELECT id_persona, nombre_persona || ' ' || apellido_persona AS nombre
        FROM persona ORDER BY apellido_persona
    """)
    personas = to_dicts(cur.fetchall())

    # marca y modelo ? equipo los almacena v?a id_modelo ? modelo_equipo ? marca_equipo
    cur.execute("""
        SELECT me.id_modelo,
               me.nombre_modelo,
               ma.nombre_marca
        FROM modelo_equipo me
        JOIN marca_equipo ma ON ma.id_marca = me.id_marca
        ORDER BY ma.nombre_marca, me.nombre_modelo
    """)
    modelos = to_dicts(cur.fetchall())

    cur.execute("SELECT id_marca, nombre_marca FROM marca_equipo ORDER BY nombre_marca")
    marcas = to_dicts(cur.fetchall())

    cur.execute("SELECT id_criticidad_equipo, criticidad_equipo FROM criticidad_equipos ORDER BY criticidad_equipo")
    criticidades = to_dicts(cur.fetchall())

    return tipos_equipo, categorias, estados_cat, ubicaciones, personas, modelos, marcas, criticidades


# MÓDULO PÚBLICO

@app.route("/")
def public_home():
    # No se redirige al dashboard aunque el usuario esté logueado.
    # Esto evita que esta ruta sea parte de un bucle de redirección.
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("SELECT COUNT(*) AS n FROM equipo WHERE activo_equipo = TRUE")
                total_equipos = cur.fetchone()["n"]

                cur.execute("""
                    SELECT ee.estado_equipo, COUNT(*) AS total
                    FROM equipo e
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    WHERE e.activo_equipo = TRUE
                    GROUP BY ee.estado_equipo
                    ORDER BY total DESC
                """)
                estados_publicos = to_dicts(cur.fetchall())

                cur.execute("""
                    SELECT te.tipo_equipo, COUNT(*) AS total
                    FROM equipo e
                    JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
                    WHERE e.activo_equipo = TRUE
                    GROUP BY te.tipo_equipo
                    ORDER BY total DESC
                """)
                tipos_publicos = to_dicts(cur.fetchall())

                cur.execute("""
                    SELECT DISTINCT te.tipo_equipo
                    FROM equipo e
                    JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
                    WHERE e.activo_equipo = TRUE
                    ORDER BY te.tipo_equipo
                """)
                tipos_filtro = [r["tipo_equipo"] for r in cur.fetchall()]

                # SCHEMA FIX #1: area_registro.nombre_area (no 'area')
                # SCHEMA FIX #4: id_ubicacion_administrativa_actual (no 'id_ubicacion')
                cur.execute("""
                    SELECT DISTINCT ar.nombre_area
                    FROM equipo e
                    JOIN ubicacion_especifica ue
                            ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    JOIN area_registro ar ON ar.id_area = ue.id_area
                    WHERE e.activo_equipo = TRUE
                    ORDER BY ar.nombre_area
                """)
                areas_filtro = [r["nombre_area"] for r in cur.fetchall()]

        return render_template(
            "index.html",
            total_equipos=total_equipos,
            estados_publicos=estados_publicos,
            tipos_publicos=tipos_publicos,
            tipos_filtro=tipos_filtro,
            areas_filtro=areas_filtro,
        )
    except Exception as e:
        flash(f"No se pudo cargar el módulo público: {e}", "error")
        return render_template(
            "index.html",
            total_equipos=0,
            estados_publicos=[],
            tipos_publicos=[],
            tipos_filtro=[],
            areas_filtro=[],
        )


# AUTENTICACIÓN
@app.route("/acceso")
def login_view():
    return render_template("login.html")


@app.route("/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    username = data.get("username")
    password = data.get("password")

    try:
        with get_db() as conn:
            with conn.cursor() as cur:

                # Usuario
                cur.execute("""
                    SELECT u.id_usuario, u.id_persona, u.username, u.contrasenia,
                           p.nombre_persona, p.apellido_persona
                    FROM usuario u
                    JOIN persona p ON p.id_persona = u.id_persona
                    WHERE u.username = %s
                """, (username,))
                user = cur.fetchone()

                if not user:
                    return jsonify(ok=False, mensaje="Usuario no encontrado"), 401

                if user["contrasenia"] != password:
                    return jsonify(ok=False, mensaje="Contraseña incorrecta"), 401

                # Roles raw (solo para bloqueo de Conductor)
                cur.execute("""
                    SELECT r.rol_usuario
                    FROM usuario_rol ur
                    JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
                    WHERE ur.id_usuario = %s
                """, (user["id_usuario"],))
                roles_raw = [r["rol_usuario"] for r in cur.fetchall()]

                # BLOQUEO CONDUCTOR
                if len(roles_raw) == 1 and roles_raw[0] == "Conductor":
                    return jsonify(ok=False, mensaje="Vista restringida, consulte al administrador"), 403

                session["id_usuario"]      = user["id_usuario"]
                session["id_persona"]      = user["id_persona"]
                session["nombre"]          = user["nombre_persona"]
                session["nombre_completo"] = user["nombre_persona"] + " " + user["apellido_persona"]

                #    sea idéntico a las llaves del dict en dashboard
                rol = rol_desde_db(user["id_usuario"], user["id_persona"])
                session["rol"] = rol
                session["es_responsable"] = (rol == "responsable")

                # Redirigir directamente al destino del rol
                destinos_login = {
                    "admin":       "admin_v",
                    "medico":      "medico_v",
                    "enfermero":   "enfermero_v",
                    "biomedico":   "biomedico_v",
                    "responsable": "responsable_v",
                }
                dest = destinos_login.get(rol)
                if dest:
                    return jsonify(ok=True, redirect=url_for(dest))

                return jsonify(ok=False, mensaje="Tu cuenta no tiene un rol de acceso válido. "
                               "Contacta al administrador."), 403

    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login_view"))


@app.route("/dashboard")
@login_required
def dashboard():
    # Diccionario exhaustivo ? sincronizado con los valores de rol_desde_db().
    destinos = {
        "admin":       "admin_v",
        "medico":      "medico_v",
        "enfermero":   "enfermero_v",
        "biomedico":   "biomedico_v",
        "responsable": "responsable_v",
    }
    dest = destinos.get(session.get("rol"))
    if dest:
        return redirect(url_for(dest))

    # Rol inválido: NO redirigir a public_home (causar?a bucle).
    # Redirigir a error-permisos, que es una ruta sin @login_required.
    return redirect(url_for("error_permisos"))


@app.route("/error-permisos")
def error_permisos():
    """Ruta de salida segura para sesiones con rol inválido o inconsistente.
    Sin @login_required ni redirección al dashboard → rompe el ciclo.
    """
    return render_template(
        "error_permisos.html",
        rol_actual=session.get("rol", "desconocido"),
        nombre=session.get("nombre", "Usuario"),
    ), 403

# API PÚBLICA (JSON)
@app.route("/api/public/equipos")
def api_public_equipos():
    q      = (request.args.get("q")      or "").strip()
    tipo   = (request.args.get("tipo")   or "").strip()
    area   = (request.args.get("area")   or "").strip()
    estado = (request.args.get("estado") or "").strip()

    # SCHEMA FIXES: #2 marca/modelo via JOIN, #4 id_ubicacion_administrativa_actual,
    #               #1 nombre_area, #5 categoria via tipo_equipos
    sql = """
        SELECT
            e.id_equipo,
            e.codigo_interno,
            e.nombre_equipo,
            ma.nombre_marca  AS marca,
            me.nombre_modelo AS modelo,
            te.tipo_equipo,
            ce.categoria_equipo,
            ee.estado_equipo,
            ue.nombre_ubicacion,
            ar.nombre_area   AS area
        FROM equipo e
        JOIN tipo_equipos te
                ON te.id_tipo_equipo      = e.id_tipo_equipo
        JOIN categoria_equipos ce
                ON ce.id_categoria_equipo = te.id_categoria_equipo
        JOIN estado_equipos ee
                ON ee.id_estado_equipo    = e.id_estado_equipo
        JOIN ubicacion_especifica ue
                ON ue.id_ubicacion        = e.id_ubicacion_administrativa_actual
        JOIN area_registro ar
                ON ar.id_area             = ue.id_area
        JOIN modelo_equipo me ON me.id_modelo = e.id_modelo
        JOIN marca_equipo ma  ON ma.id_marca  = me.id_marca
        WHERE e.activo_equipo = TRUE
    """
    params = []

    if q:
        sql += """
            AND (
                LOWER(e.codigo_interno)  LIKE %s OR
                LOWER(e.nombre_equipo)   LIKE %s OR
                LOWER(ma.nombre_marca)   LIKE %s OR
                LOWER(me.nombre_modelo)  LIKE %s
            )
        """
        like = f"%{q.lower()}%"
        params.extend([like, like, like, like])

    if tipo:
        sql += " AND te.tipo_equipo = %s"
        params.append(tipo)

    if area:
        sql += " AND ar.nombre_area = %s"
        params.append(area)

    if estado:
        sql += " AND ee.estado_equipo = %s"
        params.append(estado)

    sql += " ORDER BY e.nombre_equipo LIMIT 200"

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(sql, tuple(params))
                rows = to_dicts(cur.fetchall())
        return jsonify(ok=True, data=rows)
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


@app.route("/api/public/equipos-mapa")
def api_public_equipos_mapa():
    """
    dispositivo_gps está vinculado a ambulancia (no a equipo).
    Se adjunta la última posición GPS registrada globalmente.
    Columna real: fecha_hora_evento (no fecha_evento_gps).
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT
                        e.id_equipo,
                        e.codigo_interno,
                        e.nombre_equipo,
                        ma.nombre_marca  AS marca,
                        me.nombre_modelo AS modelo,
                        ee.estado_equipo,
                        ue.nombre_ubicacion,
                        ar.nombre_area   AS area,
                        eg.latitud,
                        eg.longitud,
                        eg.fecha_hora_evento
                    FROM equipo e
                    JOIN estado_equipos ee
                            ON ee.id_estado_equipo = e.id_estado_equipo
                    JOIN ubicacion_especifica ue
                            ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    JOIN area_registro ar  ON ar.id_area = ue.id_area
                    JOIN modelo_equipo me  ON me.id_modelo = e.id_modelo
                    JOIN marca_equipo ma   ON ma.id_marca  = me.id_marca
                    JOIN LATERAL (
                        SELECT ev.latitud, ev.longitud, ev.fecha_hora_evento
                        FROM evento_gps ev
                        ORDER BY ev.fecha_hora_evento DESC
                        LIMIT 1
                    ) eg ON TRUE
                    WHERE e.activo_equipo = TRUE
                    ORDER BY e.nombre_equipo
                """)
                rows = to_dicts(cur.fetchall())
        return jsonify(ok=True, data=rows)
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


# ADMINISTRADOR

@app.route("/admin")
@login_required
@role_required("admin")
def admin_v():
    with get_db() as c:
        with c.cursor() as cur:
            # KPIs
            cur.execute("SELECT COUNT(*) AS n FROM equipo WHERE activo_equipo = TRUE")
            total_eq = cur.fetchone()["n"]

            cur.execute("SELECT COUNT(*) AS n FROM movimiento")
            total_mov = cur.fetchone()["n"]

            cur.execute("SELECT COUNT(*) AS n FROM usuario")
            total_usr = cur.fetchone()["n"]

            cur.execute("SELECT COUNT(*) AS n FROM mantenimiento")
            total_mant = cur.fetchone()["n"]

            cur.execute("""
                SELECT ee.estado_equipo, COUNT(*) n
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                WHERE e.activo_equipo = TRUE
                GROUP BY ee.estado_equipo
            """)
            estados = {r["estado_equipo"]: r["n"] for r in cur.fetchall()}

            # Inventario de equipos
            # SCHEMA FIXES: #1 nombre_area, #2/#3 marca/modelo via JOIN,
            #               #4 id_ubicacion_administrativa_actual, #5 categoria via tipo_equipos
            cur.execute("""
                SELECT e.id_equipo,
                       e.codigo_interno,
                       e.nombre_equipo,
                       ma.nombre_marca  AS marca,
                       me.nombre_modelo AS modelo,
                       e.numero_serie,
                       te.tipo_equipo,
                       ce.categoria_equipo,
                       ee.estado_equipo,
                       ue.nombre_ubicacion,
                       ar.nombre_area   AS area,
                       e.activo_equipo,
                       e.id_tipo_equipo,
                       te.id_categoria_equipo,
                       e.id_estado_equipo,
                       e.id_ubicacion_administrativa_actual AS id_ubicacion,
                       e.id_modelo,
                       e.id_criticidad_equipo
                FROM equipo e
                JOIN tipo_equipos te
                        ON te.id_tipo_equipo      = e.id_tipo_equipo
                JOIN categoria_equipos ce
                        ON ce.id_categoria_equipo = te.id_categoria_equipo
                JOIN estado_equipos ee
                        ON ee.id_estado_equipo    = e.id_estado_equipo
                JOIN ubicacion_especifica ue
                        ON ue.id_ubicacion        = e.id_ubicacion_administrativa_actual
                JOIN area_registro ar
                        ON ar.id_area             = ue.id_area
                JOIN modelo_equipo me ON me.id_modelo = e.id_modelo
                JOIN marca_equipo ma  ON ma.id_marca  = me.id_marca
                ORDER BY e.activo_equipo DESC, e.codigo_interno
            """)
            equipos = to_dicts(cur.fetchall())

            # Movimientos
            # SCHEMA FIXES: #8 id_persona_responsable_movimiento, #9 fecha_hora_movimiento
            cur.execute("""
                SELECT m.id_movimiento,
                       e.nombre_equipo,
                       e.codigo_interno,
                       tm.tipo_movimiento,
                       uo.nombre_ubicacion AS origen,
                       ud.nombre_ubicacion AS destino,
                       p.nombre_persona || ' ' || p.apellido_persona AS responsable,
                       m.fecha_hora_movimiento,
                       m.observacion_movimiento
                FROM movimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_movimientos tm
                        ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                JOIN ubicacion_especifica uo
                        ON uo.id_ubicacion = m.id_ubicacion_origen
                JOIN ubicacion_especifica ud
                        ON ud.id_ubicacion = m.id_ubicacion_destino
                JOIN persona p
                        ON p.id_persona = m.id_persona_responsable_movimiento
                ORDER BY m.fecha_hora_movimiento DESC
            """)
            movimientos = to_dicts(cur.fetchall())

            # Usuarios (enriquecido con turno, especialidad, perfil de enfermero/médico/biomédico y responsable de área)
            cur.execute("""
                SELECT u.id_usuario,
                       u.username,
                       p.nombre_persona,
                       p.apellido_persona,
                       p.correo_persona,
                       r.rol_usuario,
                       u.activo_usuario,
                       t.nombre_turno,
                       t.hora_inicio,
                       t.hora_fin,
                       COALESCE(em.especialidad_medico, ee.especialidad_enfermero) AS especialidad,
                       enf.id_enfermero,
                       enf.id_especialidad_enfermero,
                       enf.id_turno AS id_turno_enf,
                       med.id_especialidad_medico,
                       med.id_turno AS id_turno_med,
                       bio.id_turno AS id_turno_bio,
                       ra.id_responsable_area,
                       ar.nombre_area AS area_responsable,
                       ar.id_area AS id_area_responsable,
                       ra.fecha_inicio_responsable_area
                FROM usuario u
                JOIN persona p ON p.id_persona = u.id_persona
                JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
                JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
                LEFT JOIN enfermero enf ON enf.id_persona = u.id_persona
                LEFT JOIN medico med ON med.id_persona = u.id_persona
                LEFT JOIN biomedico bio ON bio.id_persona = u.id_persona
                LEFT JOIN turnos t ON t.id_turno = COALESCE(enf.id_turno, med.id_turno, bio.id_turno)
                LEFT JOIN especialidades_medico em ON em.id_especialidad_medico = med.id_especialidad_medico
                LEFT JOIN especialidades_enfermero ee ON ee.id_especialidad_enfermero = enf.id_especialidad_enfermero
                LEFT JOIN responsable_area ra
                       ON ra.id_enfermero = enf.id_enfermero
                      AND ra.fecha_fin_responsable_area IS NULL
                LEFT JOIN area_registro ar ON ar.id_area = ra.id_area
                ORDER BY r.rol_usuario, p.apellido_persona
            """)
            usuarios = to_dicts(cur.fetchall())

            # Asignaciones activas
            # SCHEMA FIXES: #12 id_persona_responsable, #13 fecha_inicio_asignacion
            cur.execute("""
                SELECT ae.id_asignacion,
                       e.nombre_equipo,
                       e.codigo_interno,
                       p.nombre_persona || ' ' || p.apellido_persona AS asignado_a,
                       ue.nombre_ubicacion,
                       ae.fecha_inicio_asignacion,
                       ae.observacion_asignacion
                FROM asignacion_equipo ae
                JOIN equipo e  ON e.id_equipo  = ae.id_equipo
                JOIN persona p ON p.id_persona = ae.id_persona_responsable
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = ae.id_ubicacion
                WHERE ae.fecha_fin_asignacion IS NULL
                ORDER BY ae.fecha_inicio_asignacion DESC
            """)
            asignaciones = to_dicts(cur.fetchall())

            # Mantenimientos
            # SCHEMA FIXES: #6 id_biomedico ? biomedico ? persona, #7 fecha_hora_mantenimiento
            cur.execute("""
                SELECT m.id_mantenimiento,
                       e.nombre_equipo,
                       e.codigo_interno,
                       tm.tipo_mantenimiento,
                       trm.resultado_mantenimiento,
                       p.nombre_persona || ' ' || p.apellido_persona AS biomedico,
                       m.descripcion_mantenimiento,
                       m.fecha_hora_mantenimiento
                FROM mantenimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_mantenimientos tm
                        ON tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento
                JOIN tipo_resultado_mantenimientos trm
                        ON trm.id_resultado_mantenimiento = m.id_resultado_mantenimiento
                JOIN biomedico b ON b.id_biomedico = m.id_biomedico
                JOIN persona p   ON p.id_persona   = b.id_persona
                ORDER BY m.fecha_hora_mantenimiento DESC
            """)
            mantenimientos = to_dicts(cur.fetchall())

            # Reportes de gráficas — leídos desde MongoDB
            mg = get_mongo_db()
            rpt_mas_movidos  = mg_rpt_mas_movidos(mg)
            rpt_carga_bio    = mg_rpt_carga_bio(mg)
            rpt_uso_vs_mant  = mg_rpt_uso_vs_mant(mg)
            rpt_movs_area    = mg_rpt_movs_area(mg)
            rpt_freq_mov     = mg_rpt_freq_mov(mg)
            rpt_estados      = mg_rpt_estados(mg)
            rpt_movs_por_mes = mg_rpt_movs_por_mes(mg)

            # KPIs analíticos — vistas de BD
            cur.execute("""
                SELECT nombre_area, total_equipos, equipos_disponibles,
                       COALESCE(porcentaje_disponibilidad, 0) AS porcentaje_disponibilidad
                FROM v_disponibilidad_equipos_por_area
                WHERE total_equipos > 0
                ORDER BY porcentaje_disponibilidad ASC
            """)
            disp_por_area = to_dicts(cur.fetchall())

            cur.execute("SELECT COUNT(*) AS total FROM v_equipos_candidatos_reemplazo WHERE alerta_reemplazo = 'Candidato a evaluacion de baja'")
            n_candidatos_reemplazo = (cur.fetchone() or {}).get("total", 0)

            cur.execute("SELECT COUNT(*) AS total FROM v_mantenimientos_vencidos")
            n_mants_vencidos = (cur.fetchone() or {}).get("total", 0)

            cur.execute("SELECT * FROM v_mantenimientos_programados_pendientes WHERE alerta = 'vencido' ORDER BY fecha_proximo_mantenimiento ASC")
            mants_vencidos = to_dicts(cur.fetchall())
            for m in mants_vencidos:
                if m.get("fecha_proximo_mantenimiento"):
                    m["fecha_proximo_mantenimiento"] = m["fecha_proximo_mantenimiento"].strftime("%d/%m/%Y")

            cur.execute("SELECT * FROM v_usos_clinicos_area ORDER BY fecha_hora_inicio DESC LIMIT 50")
            usos_clinicos_recientes = to_dicts(cur.fetchall())
            for u in usos_clinicos_recientes:
                for campo in ("fecha_hora_inicio", "fecha_hora_fin"):
                    if u.get(campo):
                        u[campo] = u[campo].strftime("%d/%m %H:%M")
            areas_uso = sorted({u["nombre_area"] for u in usos_clinicos_recientes if u.get("nombre_area")})

            _total_eq_con_area = sum(a["total_equipos"] for a in disp_por_area)
            _total_disp_con_area = sum(a["equipos_disponibles"] for a in disp_por_area)
            global_disp_pct = int((_total_disp_con_area / _total_eq_con_area * 100) if _total_eq_con_area > 0 else 0)
            n_areas_alerta = sum(1 for a in disp_por_area if a["porcentaje_disponibilidad"] < 70)

            (tipos_equipo, categorias, estados_cat, ubicaciones,
             personas, modelos, marcas, criticidades) = _admin_catalogs(cur)

            
            cur.execute("""
                SELECT a.id_ambulancia, a.codigo_ambulancia, a.placa,
                       a.activo_ambulancia,
                       ea.estado_ambulancia,
                       dg.codigo_gps, dg.activo_gps
                FROM ambulancia a
                JOIN estado_ambulancias ea
                        ON ea.id_estado_ambulancia = a.id_estado_ambulancia
                LEFT JOIN dispositivo_gps dg ON dg.id_ambulancia = a.id_ambulancia
                ORDER BY a.codigo_ambulancia
            """)
            ambulancias = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT p.id_persona, p.nombre_persona, p.apellido_persona,
                       p.correo_persona,
                       u.username, u.activo_usuario,
                       COUNT(t.id_traslado_externo)        AS total_traslados,
                       MAX(t.fecha_salida)                 AS ultimo_traslado
                FROM persona p
                JOIN usuario u ON u.id_persona = p.id_persona
                JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
                JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
                LEFT JOIN traslado_externo_equipo t
                        ON t.id_persona_conductor = p.id_persona
                WHERE r.rol_usuario = 'Conductor'
                GROUP BY p.id_persona, p.nombre_persona, p.apellido_persona,
                         p.correo_persona, u.username, u.activo_usuario
                ORDER BY p.apellido_persona
            """)
            conductores = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT te.id_traslado_externo,
                       e.codigo_interno, e.nombre_equipo,
                       a.codigo_ambulancia,
                       p.nombre_persona || ' ' || p.apellido_persona AS conductor,
                       te.fecha_salida, te.fecha_llegada,
                       tt.tipo_traslado,
                       te.motivo_traslado, te.observacion_traslado
                FROM traslado_externo_equipo te
                JOIN equipo e ON e.id_equipo = te.id_equipo
                JOIN ambulancia a ON a.id_ambulancia = te.id_ambulancia
                JOIN persona p ON p.id_persona = te.id_persona_conductor
                JOIN tipo_traslado_externo tt
                        ON tt.id_tipo_traslado = te.id_tipo_traslado
                ORDER BY te.fecha_salida DESC
            """)
            traslados = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT id_tipo_traslado, tipo_traslado
                FROM tipo_traslado_externo ORDER BY tipo_traslado
            """)
            tipos_traslado = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT e.id_equipo, e.codigo_interno, e.nombre_equipo
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                WHERE ee.estado_equipo = 'Disponible'
                  AND e.activo_equipo = TRUE
                ORDER BY e.codigo_interno
            """)
            equipos_disponibles = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT id_nfc, codigo_uid_nfc, id_equipo
                FROM dispositivo_nfc WHERE activo_nfc = TRUE
                ORDER BY codigo_uid_nfc
            """)
            nfc_equipos = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT a.codigo_ambulancia,
                       ev.fecha_hora_evento,
                       ev.latitud, ev.longitud, ev.precision
                FROM evento_gps ev
                JOIN dispositivo_gps dg ON dg.id_gps = ev.id_gps
                JOIN ambulancia a ON a.id_ambulancia = dg.id_ambulancia
                ORDER BY ev.fecha_hora_evento DESC
                LIMIT 50
            """)
            eventos_gps = to_dicts(cur.fetchall())

            # GPS y traslados activos para la vista Traslados
            cur.execute("SELECT * FROM v_ambulancias_gps ORDER BY codigo_ambulancia")
            ambulancias_gps_adm = to_dicts(cur.fetchall())
            for row in ambulancias_gps_adm:
                if row.get("ultimo_ping"):
                    row["ultimo_ping"] = row["ultimo_ping"].strftime("%d/%m %H:%M:%S")
                if row.get("latitud") is not None:
                    row["latitud"] = float(row["latitud"])
                if row.get("longitud") is not None:
                    row["longitud"] = float(row["longitud"])

            cur.execute("SELECT * FROM v_traslados_activos")
            traslados_activos_adm = to_dicts(cur.fetchall())
            for row in traslados_activos_adm:
                if row.get("fecha_salida"):
                    row["fecha_salida"] = row["fecha_salida"].strftime("%d/%m/%Y %H:%M")

            # Auditoría reciente
            cur.execute("""
                SELECT id_auditoria, tabla_afectada, accion_auditoria,
                       id_registro_afectado, ejecutado_por, origen_cambio,
                       fecha_hora_auditoria, nivel_atencion
                FROM v_admin_auditoria_reciente
                ORDER BY fecha_hora_auditoria DESC
                LIMIT 200
            """)
            auditoria_reciente = to_dicts(cur.fetchall())

            # Actividad por usuario
            cur.execute("""
                SELECT username, rol_usuario, total_operaciones,
                       ultima_actividad, tablas_distintas_afectadas
                FROM v_actividad_sistema_por_usuario
                ORDER BY total_operaciones DESC
            """)
            actividad_usuarios = to_dicts(cur.fetchall())

            # Roles disponibles para crear usuarios
            cur.execute("SELECT id_rol_usuario, rol_usuario FROM roles_usuario ORDER BY rol_usuario")
            roles_usuario = to_dicts(cur.fetchall())

            # Personas sin usuario asociado (para el modal de crear usuario)
            cur.execute("""
                SELECT p.id_persona, p.nombre_persona, p.apellido_persona, p.correo_persona
                FROM persona p
                WHERE NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_persona = p.id_persona)
                ORDER BY p.apellido_persona, p.nombre_persona
            """)
            personas_sin_usuario = to_dicts(cur.fetchall())

            # Turnos, especialidades médico y enfermero (para el modal de crear/editar usuario)
            cur.execute("SELECT id_turno, nombre_turno, hora_inicio, hora_fin FROM turnos ORDER BY id_turno")
            turnos = to_dicts(cur.fetchall())

            # Áreas para asignación de responsable de área
            cur.execute("SELECT id_area, nombre_area FROM area_registro ORDER BY nombre_area")
            areas_registro = to_dicts(cur.fetchall())

            cur.execute("SELECT id_especialidad_medico, especialidad_medico FROM especialidades_medico ORDER BY especialidad_medico")
            especialidades_medico = to_dicts(cur.fetchall())

            cur.execute("SELECT id_especialidad_enfermero, especialidad_enfermero FROM especialidades_enfermero ORDER BY especialidad_enfermero")
            especialidades_enfermero = to_dicts(cur.fetchall())

    # Datos IoT para el panel inline de admin.html (sección v-iot)
    discrepancias = []
    sin_evidencia = []
    eventos_nfc   = []
    eventos_beacon = []
    beacons        = []
    dispositivos_nfc = []
    try:
        with get_db() as _c:
            with _c.cursor() as _cur:
                _cur.execute("""
                    SELECT id_equipo, codigo_interno, nombre_equipo,
                           ubicacion_administrativa, area_administrativa,
                           ubicacion_evidencia_beacon, area_evidencia_beacon,
                           fecha_ultima_evidencia_beacon, resultado
                    FROM v_discrepancia_ubicacion_iot
                    ORDER BY resultado DESC, fecha_ultima_evidencia_beacon DESC NULLS LAST
                """)
                discrepancias = to_dicts(_cur.fetchall())

                _cur.execute("""
                    SELECT id_equipo, codigo_interno, nombre_equipo,
                           criticidad_equipo, ultima_evidencia_nfc,
                           ultima_evidencia_beacon, ultima_evidencia_iot
                    FROM v_equipos_sin_evidencia_iot
                    ORDER BY ultima_evidencia_iot ASC
                """)
                sin_evidencia = to_dicts(_cur.fetchall())

                _cur.execute("""
                    SELECT en.id_evento_nfc, en.fecha_hora_evento,
                           tn.tipo_evento_nfc, dn.codigo_uid_nfc,
                           e.nombre_equipo, e.codigo_interno,
                           ee.estado_equipo, ue.nombre_ubicacion, ar.nombre_area
                    FROM evento_nfc en
                    JOIN tipo_eventos_nfc tn    ON tn.id_tipo_evento_nfc  = en.id_tipo_evento_nfc
                    JOIN dispositivo_nfc  dn    ON dn.id_nfc              = en.id_nfc
                    JOIN equipo           e     ON e.id_equipo            = dn.id_equipo
                    JOIN estado_equipos   ee    ON ee.id_estado_equipo    = e.id_estado_equipo
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    JOIN area_registro        ar ON ar.id_area      = ue.id_area
                    ORDER BY en.fecha_hora_evento DESC LIMIT 50
                """)
                eventos_nfc = to_dicts(_cur.fetchall())

                _cur.execute("""
                    SELECT eb.id_evento_beacon, eb.fecha_hora_evento,
                           teb.tipo_evento_beacon, dbb.uuid_beacon,
                           zb.nombre_zona_beacon, ue.nombre_ubicacion, ar.nombre_area,
                           e.nombre_equipo, e.codigo_interno
                    FROM evento_beacon eb
                    JOIN tipo_eventos_beacon teb ON teb.id_tipo_evento_beacon = eb.id_tipo_evento_beacon
                    JOIN dispositivo_beacon  dbb ON dbb.id_beacon             = eb.id_beacon
                    JOIN zona_beacon         zb  ON zb.id_zona_beacon         = dbb.id_zona_beacon
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion           = zb.id_ubicacion
                    JOIN area_registro        ar ON ar.id_area                = ue.id_area
                    JOIN equipo               e  ON e.id_equipo               = eb.id_equipo
                    ORDER BY eb.fecha_hora_evento DESC LIMIT 50
                """)
                eventos_beacon = to_dicts(_cur.fetchall())

                _cur.execute("""
                    SELECT dbb.id_beacon, dbb.uuid_beacon,
                           dbb.major_beacon, dbb.minor_beacon, dbb.activo_beacon,
                           zb.nombre_zona_beacon, ue.nombre_ubicacion, ar.nombre_area
                    FROM dispositivo_beacon  dbb
                    JOIN zona_beacon         zb ON zb.id_zona_beacon = dbb.id_zona_beacon
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion  = zb.id_ubicacion
                    JOIN area_registro        ar ON ar.id_area       = ue.id_area
                    ORDER BY ar.nombre_area, dbb.uuid_beacon
                """)
                beacons = to_dicts(_cur.fetchall())

                _cur.execute("""
                    SELECT dn.id_nfc, dn.codigo_uid_nfc, dn.activo_nfc,
                           e.nombre_equipo, e.codigo_interno, ee.estado_equipo
                    FROM dispositivo_nfc dn
                    JOIN equipo         e  ON e.id_equipo         = dn.id_equipo
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    ORDER BY e.codigo_interno
                """)
                dispositivos_nfc = to_dicts(_cur.fetchall())
    except Exception:
        pass  # Si las vistas IoT no existen aún, el panel muestra vacío sin romper admin

    total_disc         = sum(1 for d in discrepancias if "alerta" in d.get("resultado", "").lower())
    total_sin_evidencia = len(sin_evidencia)

    return render_template(
        "admin.html",
        total_eq=total_eq, total_mov=total_mov,
        total_usr=total_usr, total_mant=total_mant,
        estados=estados, equipos=equipos,
        movimientos=movimientos, usuarios=usuarios,
        asignaciones=asignaciones, mantenimientos=mantenimientos,
        rpt_mas_movidos=rpt_mas_movidos, rpt_carga_bio=rpt_carga_bio,
        rpt_uso_vs_mant=rpt_uso_vs_mant, rpt_movs_area=rpt_movs_area,
        rpt_freq_mov=rpt_freq_mov, rpt_estados=rpt_estados,
        rpt_movs_por_mes=rpt_movs_por_mes,
        disp_por_area=disp_por_area, global_disp_pct=global_disp_pct,
        total_disp_con_area=_total_disp_con_area, total_eq_con_area=_total_eq_con_area,
        n_candidatos_reemplazo=n_candidatos_reemplazo,
        n_mants_vencidos=n_mants_vencidos, n_areas_alerta=n_areas_alerta,
        tipos_equipo=tipos_equipo, categorias=categorias,
        estados_cat=estados_cat, ubicaciones=ubicaciones,
        personas=personas, modelos=modelos,
        marcas=marcas, criticidades=criticidades,
        ambulancias=ambulancias, conductores=conductores,
        traslados=traslados, tipos_traslado=tipos_traslado,
        equipos_disponibles=equipos_disponibles,
        nfc_equipos=nfc_equipos, eventos_gps=eventos_gps,
        ambulancias_gps=ambulancias_gps_adm,
        traslados_activos=traslados_activos_adm,
        total_disc=total_disc, total_sin_evidencia=total_sin_evidencia,
        discrepancias=discrepancias, sin_evidencia=sin_evidencia,
        eventos_nfc=eventos_nfc, eventos_beacon=eventos_beacon,
        beacons=beacons, dispositivos_nfc=dispositivos_nfc,
        auditoria_reciente=auditoria_reciente,
        actividad_usuarios=actividad_usuarios,
        roles_usuario=roles_usuario,
        personas_sin_usuario=personas_sin_usuario,
        turnos=turnos,
        especialidades_medico=especialidades_medico,
        especialidades_enfermero=especialidades_enfermero,
        areas_registro=areas_registro,
        mants_vencidos=mants_vencidos,
        usos_clinicos_recientes=usos_clinicos_recientes,
        areas_uso=areas_uso,
    )



@app.route("/admin/equipo", methods=["POST"])
@login_required
@role_required("admin")
def admin_nuevo_equipo():
    """
    SP real: sp_registrar_equipo(
        p_id_usuario, p_codigo_interno, p_nombre_equipo, p_id_modelo,
        p_numero_serie, p_id_tipo_equipo, p_id_criticidad,
        p_id_ubicacion, p_codigo_uid_nfc  [OUT p_id_equipo]
    )
    """
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                num_serie = f.get("numero_serie", "").strip() or None
                cod_nfc   = f.get("codigo_uid_nfc", "").strip() or None
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_registrar_equipo(%s,%s,%s,%s,%s,%s,%s,%s,%s,NULL,%s)",
                    (
                        session["id_usuario"],
                        f["codigo_interno"],
                        f["nombre_equipo"],
                        int(f["id_modelo"]),
                        num_serie,
                        int(f["id_tipo_equipo"]),
                        int(f["id_criticidad_equipo"]),
                        int(f["id_ubicacion"]),
                        cod_nfc,
                        "web_admin",
                    )
                )
            c.commit()
        flash("Equipo registrado correctamente.", "success")
    except Exception as e:
        flash(f"Error al registrar equipo: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")


@app.route("/admin/equipo/<int:id_equipo>/editar", methods=["POST"])
@login_required
@role_required("admin")
def admin_editar_equipo(id_equipo):
    """
    SCHEMA FIXES: id_modelo en lugar de marca/modelo sueltos,
                  id_ubicacion_administrativa_actual, id_criticidad_equipo.
    """
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute("""
                    UPDATE equipo
                    SET nombre_equipo                       = %s,
                        id_modelo                          = %s,
                        numero_serie                       = %s,
                        id_tipo_equipo                     = %s,
                        id_criticidad_equipo               = %s,
                        id_estado_equipo                   = %s,
                        id_ubicacion_administrativa_actual = %s
                    WHERE id_equipo = %s
                """, (
                    f["nombre_equipo"],
                    int(f["id_modelo"]),
                    f.get("numero_serie", ""),
                    int(f["id_tipo_equipo"]),
                    int(f["id_criticidad_equipo"]),
                    int(f["id_estado_equipo"]),
                    int(f["id_ubicacion"]),
                    id_equipo
                ))
            c.commit()
        flash("Equipo actualizado.", "success")
    except Exception as e:
        flash(f"Error al actualizar: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")


@app.route("/admin/equipo/<int:id_equipo>/eliminar", methods=["POST"])
@login_required
@role_required("admin")
def admin_eliminar_equipo(id_equipo):
    """Baja lógica: activo_equipo = FALSE."""
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT COUNT(*) AS n FROM asignacion_equipo
                    WHERE id_equipo = %s AND fecha_fin_asignacion IS NULL
                """, (id_equipo,))
                if cur.fetchone()["n"] > 0:
                    flash("No se puede eliminar: el equipo tiene asignaciones activas.", "error")
                    return redirect(url_for("admin_v") + "#v-equipos")
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "UPDATE equipo SET activo_equipo = FALSE WHERE id_equipo = %s",
                    (id_equipo,)
                )
            c.commit()
        flash("Equipo dado de baja.", "success")
    except Exception as e:
        flash(f"Error al eliminar: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")



@app.route("/admin/asignar", methods=["POST"])
@login_required
@role_required("admin")
def admin_asignar():
    """
    SP real: sp_asignar_equipo(
        p_id_usuario, p_id_equipo, p_id_persona_responsable,
        p_id_ubicacion  [OUT p_id_asignacion], p_observacion
    )
    """
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_asignar_equipo(%s,%s,%s,%s,NULL,%s,%s)",
                    (
                        session["id_usuario"],
                        int(f["id_equipo"]),
                        int(f["id_persona"]),
                        int(f["id_ubicacion"]),
                        f.get("observacion", "Asignación"),
                        "web_admin",
                    )
                )
            c.commit()
        flash("Equipo asignado.", "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-asig")


@app.route("/admin/cerrar_asignacion/<int:id_asignacion>", methods=["POST"])
@login_required
@role_required("admin")
def admin_cerrar_asignacion(id_asignacion):
    """
    SP real: sp_cerrar_asignacion_equipo(
        p_id_usuario, p_id_asignacion  [OUT p_mensaje], p_observacion
    )
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_cerrar_asignacion_equipo(%s,%s,NULL,%s,%s)",
                    (
                        session["id_usuario"],
                        id_asignacion,
                        request.form.get("observacion", "Cierre administrativo"),
                        "web_admin",
                    )
                )
            c.commit()
        flash("Asignación cerrada.", "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-asig")



@app.route("/admin/traslado", methods=["POST"])
@login_required
@role_required("admin")
def admin_nuevo_traslado():
    """
    SP: sp_registrar_traslado_externo(
        p_id_usuario, p_id_equipo, p_id_nfc_equipo, p_id_ambulancia,
        p_id_persona_conductor, p_id_tipo_traslado
        [OUT p_id_traslado], p_motivo, p_observacion
    )
    El trigger fn_validar_conductor_autorizado_traslado valida
    que id_persona_conductor tenga usuario activo con rol Conductor.
    """
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_registrar_traslado_externo(%s,%s,%s,%s,%s,%s,NULL,%s,%s,%s)",
                    (
                        session["id_usuario"],
                        int(f["id_equipo"]),
                        int(f["id_nfc_equipo"]),
                        int(f["id_ambulancia"]),
                        int(f["id_persona_conductor"]),
                        int(f["id_tipo_traslado"]),
                        f.get("motivo", ""),
                        f.get("observacion", ""),
                        "web_admin",
                    )
                )
            c.commit()
        flash("Traslado externo registrado correctamente.", "success")
    except Exception as e:
        flash(f"Error al registrar traslado: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-traslados")



@app.route("/admin/movimiento/<int:id_movimiento>/eliminar", methods=["POST"])
@login_required
@role_required("admin")
def admin_eliminar_movimiento(id_movimiento):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "DELETE FROM movimiento WHERE id_movimiento = %s",
                    (id_movimiento,)
                )
            c.commit()
        flash("Movimiento eliminado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("admin_v") + "#v-movs")



@app.route("/admin/usuario/<int:id_usuario_target>/toggle", methods=["POST"])
@login_required
@role_required("admin")
def admin_toggle_usuario(id_usuario_target):
    """
    SP real: sp_cambiar_estado_usuario(p_id_usuario, p_id_usuario_target, p_activo [OUT p_mensaje])
    Lee el estado actual para invertirlo.
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                # SCHEMA FIX #14: activo_usuario
                cur.execute(
                    "SELECT activo_usuario FROM usuario WHERE id_usuario = %s",
                    (id_usuario_target,)
                )
                row = cur.fetchone()
                if not row:
                    flash("Usuario no encontrado.", "error")
                    return redirect(url_for("admin_v") + "#v-usuarios")
                nuevo_estado = not row["activo_usuario"]
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_cambiar_estado_usuario(%s,%s,%s,NULL,%s)",
                    (session["id_usuario"], id_usuario_target, nuevo_estado, "web_admin")
                )
            c.commit()
        flash("Estado de usuario actualizado.", "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-usuarios")


@app.route("/admin/persona/crear", methods=["POST"])
@login_required
@role_required("admin")
def admin_crear_persona():
    f = request.form
    nombre   = f.get("nombre_persona", "").strip()
    apellido = f.get("apellido_persona", "").strip()
    correo   = f.get("correo_persona", "").strip()
    if not all([nombre, apellido, correo]):
        flash("Nombre, apellido y correo son obligatorios.", "error")
        return redirect(url_for("admin_v") + "#v-usuarios")
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_crear_persona(%s,%s,%s,%s,NULL,NULL,%s)",
                    (session["id_usuario"], nombre, apellido, correo, "web_admin")
                )
                row = cur.fetchone()
                msg = row["p_mensaje"] if row else "Persona registrada."
            c.commit()
        flash(msg, "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-usuarios")


@app.route("/admin/usuario/crear", methods=["POST"])
@login_required
@role_required("admin")
def admin_crear_usuario():
    f = request.form
    id_persona  = f.get("id_persona")
    username    = f.get("username", "").strip()
    contrasenia = f.get("contrasenia", "").strip()
    id_rol      = f.get("id_rol")
    id_especialidad_raw = f.get("id_especialidad_medico") or f.get("id_especialidad_enfermero") or None
    id_turno_raw = f.get("id_turno") or None
    id_area_resp = f.get("id_area_responsable") or None  # opcional para enfermero
    if not all([id_persona, username, contrasenia, id_rol]):
        flash("Todos los campos obligatorios están incompletos.", "error")
        return redirect(url_for("admin_v") + "#v-usuarios")
    try:
        id_especialidad = int(id_especialidad_raw) if id_especialidad_raw else None
        id_turno = int(id_turno_raw) if id_turno_raw else None
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_crear_usuario(%s,%s,%s,%s,%s,%s,%s,%s,NULL,NULL)",
                    (session["id_usuario"], int(id_persona), username, contrasenia,
                     int(id_rol), id_especialidad, id_turno, "web_admin")
                )
                row = cur.fetchone()
                msg = row["p_mensaje"] if row else "Usuario creado."
                # Si es enfermero y se indicó área, asignar como responsable
                if id_area_resp:
                    cur.execute(
                        "SELECT id_enfermero FROM enfermero WHERE id_persona = %s",
                        (int(id_persona),)
                    )
                    enf_row = cur.fetchone()
                    if enf_row:
                        cur.execute(
                            "CALL sp_cambiar_responsable_area(%s,%s,%s,NULL,%s)",
                            (session["id_usuario"], int(id_area_resp), enf_row["id_enfermero"], "web_admin")
                        )
                        ra_row = cur.fetchone()
                        if ra_row and ra_row.get("p_mensaje"):
                            msg += " · " + ra_row["p_mensaje"]
            c.commit()
        flash(msg, "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-usuarios")


@app.route("/admin/usuario/<int:id_usuario_target>/editar", methods=["POST"])
@login_required
@role_required("admin")
def admin_editar_usuario(id_usuario_target):
    f = request.form
    username    = f.get("username", "").strip()
    contrasenia = f.get("nueva_contrasenia", "").strip() or None
    id_especialidad_raw = f.get("id_especialidad_medico") or f.get("id_especialidad_enfermero") or None
    id_turno_raw = f.get("id_turno") or None
    if not username:
        flash("El username es obligatorio.", "error")
        return redirect(url_for("admin_v") + "#v-usuarios")
    try:
        id_especialidad = int(id_especialidad_raw) if id_especialidad_raw else None
        id_turno = int(id_turno_raw) if id_turno_raw else None
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_editar_usuario(%s,%s,%s,%s,%s,%s,%s,NULL)",
                    (session["id_usuario"], id_usuario_target, username, contrasenia,
                     id_especialidad, id_turno, "web_admin")
                )
                row = cur.fetchone()
                msg = row["p_mensaje"] if row else "Usuario actualizado."
            c.commit()
        flash(msg, "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-usuarios")


@app.route("/admin/usuario/<int:id_usuario_target>/quitar_responsable", methods=["POST"])
@login_required
@role_required("admin")
def admin_quitar_responsable(id_usuario_target):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "SELECT id_enfermero FROM enfermero e JOIN usuario u ON u.id_persona = e.id_persona WHERE u.id_usuario = %s",
                    (id_usuario_target,)
                )
                row = cur.fetchone()
                if not row:
                    flash("El usuario no tiene perfil de enfermero.", "error")
                    return redirect(url_for("admin_v") + "#v-usuarios")
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_quitar_responsable_area(%s,%s,NULL,%s)",
                    (session["id_usuario"], row["id_enfermero"], "web_admin")
                )
                res = cur.fetchone()
                msg = res["p_mensaje"] if res else "Responsabilidad removida."
            c.commit()
        flash(msg, "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-usuarios")


@app.route("/admin/usuario/<int:id_usuario_target>/asignar_responsable", methods=["POST"])
@login_required
@role_required("admin")
def admin_asignar_responsable(id_usuario_target):
    id_area = request.form.get("id_area")
    if not id_area:
        flash("Selecciona un área.", "error")
        return redirect(url_for("admin_v") + "#v-usuarios")
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "SELECT id_enfermero FROM enfermero e JOIN usuario u ON u.id_persona = e.id_persona WHERE u.id_usuario = %s",
                    (id_usuario_target,)
                )
                row = cur.fetchone()
                if not row:
                    flash("El usuario no tiene perfil de enfermero.", "error")
                    return redirect(url_for("admin_v") + "#v-usuarios")
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_cambiar_responsable_area(%s,%s,%s,NULL,%s)",
                    (session["id_usuario"], int(id_area), row["id_enfermero"], "web_admin")
                )
                res = cur.fetchone()
                msg = res["p_mensaje"] if res else "Responsable asignado."
            c.commit()
        flash(msg, "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-usuarios")


# MÉDICO

@app.route("/medico")
@login_required
@role_required("medico", "admin")
def medico_v():
    ip = session["id_persona"]
    with get_db() as c:
        with c.cursor() as cur:
            # Perfil especialidades_medico (sin 's' final)
            cur.execute("""
                SELECT p.nombre_persona, p.apellido_persona,
                       em.especialidad_medico
                FROM medico m
                JOIN persona p ON p.id_persona = m.id_persona
                JOIN especialidades_medico em
                        ON em.id_especialidad_medico = m.id_especialidad_medico
                WHERE m.id_persona = %s
            """, (ip,))
            perfil = cur.fetchone()

            # Equipos disponibles
            cur.execute("SELECT * FROM v_equipos_disponibles_uso_clinico")
            disponibles = to_dicts(cur.fetchall())

            # Mis asignaciones activas
            cur.execute("""
                SELECT * FROM v_asignaciones_activas
                WHERE id_persona_responsable = %s
                ORDER BY fecha_inicio_asignacion DESC
            """, (ip,))
            mis_asignaciones = to_dicts(cur.fetchall())

            # Mis usos clínicos — vista enriquecida con área, procedimiento y duración
            cur.execute("""
                SELECT * FROM v_historial_uso_clinico_por_persona
                WHERE id_persona_responsable_uso = %s
                ORDER BY fecha_hora_inicio DESC
            """, (ip,))
            mis_usos = to_dicts(cur.fetchall())

            # KPI: equipos críticos no disponibles
            cur.execute("SELECT * FROM v_equipos_criticos_no_disponibles ORDER BY criticidad_equipo DESC, nombre_equipo")
            criticos_no_disponibles = to_dicts(cur.fetchall())

            # KPI: equipos de alta demanda
            cur.execute("SELECT * FROM v_equipos_alta_demanda ORDER BY total_usos_clinicos DESC")
            alta_demanda = to_dicts(cur.fetchall())

            # KPI: disponibilidad por área
            cur.execute("SELECT * FROM v_disponibilidad_equipos_por_area ORDER BY nombre_area")
            disponibilidad_area = to_dicts(cur.fetchall())

            # Reportes de gráficas — leídos desde MongoDB
            _mg = get_mongo_db()
            rpt_mis_equipos_usados = mg_rpt_mis_equipos_usados(_mg, ip)
            rpt_mis_usos_por_mes   = mg_rpt_mis_usos_por_mes(_mg, ip)

            # Reporte: disponibilidad por tipo
            cur.execute("SELECT * FROM v_disponibilidad_por_tipo_equipo ORDER BY total DESC")
            rpt_por_tipo = to_dicts(cur.fetchall())

            cur.execute("SELECT * FROM v_equipos_activos ORDER BY nombre_equipo")
            todos_equipos = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_tipo_procedimiento, tipo_procedimiento
                FROM tipo_procedimiento ORDER BY tipo_procedimiento
            """)
            tipos_proc = to_dicts(cur.fetchall())

    return render_template(
        "medico.html",
        perfil=perfil, disponibles=disponibles,
        mis_asignaciones=mis_asignaciones,
        mis_usos=mis_usos, todos_equipos=todos_equipos,
        tipos_proc=tipos_proc,
        criticos_no_disponibles=criticos_no_disponibles,
        alta_demanda=alta_demanda,
        disponibilidad_area=disponibilidad_area,
        rpt_mis_equipos_usados=rpt_mis_equipos_usados,
        rpt_mis_usos_por_mes=rpt_mis_usos_por_mes,
        rpt_por_tipo=rpt_por_tipo
    )


@app.route("/medico/uso", methods=["POST"])
@login_required
@role_required("medico", "admin")
def medico_uso():
    """
    SP real: sp_registrar_uso_clinico(
        p_id_usuario, p_id_equipo, p_id_persona_responsable,
        p_id_area, p_id_turno, p_id_tipo_procedimiento  [OUT p_id_uso_clinico]
    )
    """
    id_eq = request.form.get("id_equipo", "").strip()
    if not id_eq:
        flash("Selecciona un equipo.", "error")
        return redirect(url_for("medico_v"))
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT ue.id_area
                    FROM equipo e
                    JOIN ubicacion_especifica ue
                            ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    WHERE e.id_equipo = %s
                """, (int(id_eq),))
                area_row = cur.fetchone()
                id_area = area_row["id_area"] if area_row else 1

                cur.execute("SELECT id_turno FROM medico WHERE id_persona = %s", (session["id_persona"],))
                turno_row = cur.fetchone()
                id_turno = turno_row["id_turno"] if turno_row else 1

                id_proc = int(request.form.get("id_tipo_procedimiento", 1))

                set_audit_context(cur, "web_medico")
                cur.execute(
                    "CALL sp_registrar_uso_clinico(%s,%s,%s,%s,%s,%s,NULL,%s,%s)",
                    (
                        session["id_usuario"],
                        int(id_eq),
                        session["id_persona"],
                        id_area,
                        id_turno,
                        id_proc,
                        None,
                        "web_medico",
                    )
                )
            c.commit()
        flash("Uso clínico registrado.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return redirect(url_for("medico_v"))


@app.route("/medico/uso/<int:id_uso>/cerrar", methods=["POST"])
@login_required
@role_required("medico", "admin")
def medico_cerrar_uso(id_uso):
    """SP real: sp_cerrar_uso_clinico(p_id_usuario, p_id_uso_clinico [OUT p_mensaje])"""
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_medico")
                cur.execute(
                    "CALL sp_cerrar_uso_clinico(%s,%s,NULL,%s)",
                    (session["id_usuario"], id_uso, "web_medico")
                )
            c.commit()
        flash("Registro de uso cerrado.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return redirect(url_for("medico_v"))



# BIOMÉDICO

@app.route("/biomedico")
@login_required
@role_required("biomedico", "admin")
def biomedico_v():
    ip = session["id_persona"]
    with get_db() as c:
        with c.cursor() as cur:
            # Resolver id_biomedico del usuario actual
            cur.execute(
                "SELECT id_biomedico FROM biomedico WHERE id_persona = %s",
                (ip,)
            )
            bio_row = cur.fetchone()
            id_biomedico = bio_row["id_biomedico"] if bio_row else -1

            # Mis mantenimientos
            # SCHEMA FIXES: #6 id_biomedico, #7 fecha_hora_mantenimiento
            cur.execute("""
                SELECT m.id_mantenimiento,
                       e.nombre_equipo,
                       e.codigo_interno,
                       tm.tipo_mantenimiento,
                       trm.resultado_mantenimiento,
                       m.descripcion_mantenimiento,
                       m.fecha_hora_mantenimiento,
                       m.id_equipo,
                       m.id_tipo_mantenimiento,
                       m.id_resultado_mantenimiento
                FROM mantenimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_mantenimientos tm
                        ON tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento
                JOIN tipo_resultado_mantenimientos trm
                        ON trm.id_resultado_mantenimiento = m.id_resultado_mantenimiento
                WHERE m.id_biomedico = %s
                ORDER BY m.fecha_hora_mantenimiento DESC
            """, (id_biomedico,))
            mis_mants = to_dicts(cur.fetchall())

            # Equipos críticos con correctivos desfavorables
            cur.execute("""
                SELECT * FROM v_mantenimiento_correctivo_estado_equipo
                WHERE resultado_mantenimiento IN ('Fallido', 'Requiere reemplazo')
                ORDER BY fecha_hora_mantenimiento DESC
            """)
            criticos = to_dicts(cur.fetchall())

            # Reporte: carga biomédica global ? se usa sp_reporte_carga_biomedica
            # con el rango del año en curso para evitar el hardcode anterior.
            # La llamada a través del SP da el desglose exacto (exitosos/desfavorables/costos).
            # Se abre y cierra el cursor de refcursor manualmente porque psycopg2
            # no maneja INOUT refcursor con el helper estándar.
            cur.execute("BEGIN")
            cur.execute(
                "CALL sp_reporte_carga_biomedica(%s, %s::TIMESTAMP, %s::TIMESTAMP, 'cur_carga')",
                (
                    session.get("id_usuario", 1),
                    "2025-01-01 00:00:00",
                    "2099-12-31 23:59:59",
                )
            )
            cur.execute('FETCH ALL FROM "cur_carga"')
            carga = to_dicts(cur.fetchall())
            cur.execute("CLOSE cur_carga")
            cur.execute("COMMIT")

            # Mantenimientos por tipo de equipo — biomédico actual (KPI analítico)
            cur.execute("""
                SELECT te.tipo_equipo, COUNT(*) AS total
                FROM mantenimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
                WHERE m.id_biomedico = %s
                GROUP BY te.tipo_equipo
                ORDER BY total DESC
            """, (id_biomedico,))
            mants_por_tipo_equipo = to_dicts(cur.fetchall())

            # Costo promedio por mantenimiento — biomédico actual
            cur.execute("""
                SELECT
                    ROUND(AVG(costo_mantenimiento)::NUMERIC, 2) AS promedio_costo,
                    COUNT(*) FILTER (WHERE costo_mantenimiento IS NOT NULL) AS con_costo
                FROM mantenimiento
                WHERE id_biomedico = %s
            """, (id_biomedico,))
            _costo = to_dicts(cur.fetchall())
            costo_stats = _costo[0] if _costo else {"promedio_costo": None, "con_costo": 0}

            # Cumplimiento de SLA — mantenimientos con programación asignada
            cur.execute("""
                SELECT
                    COUNT(*) FILTER (
                        WHERE m.id_programacion IS NOT NULL
                          AND m.fecha_hora_mantenimiento <=
                              mp.fecha_proximo_mantenimiento
                              + (mp.sla_horas || ' hours')::INTERVAL
                    ) AS dentro_sla,
                    COUNT(*) FILTER (WHERE m.id_programacion IS NOT NULL) AS programados,
                    COUNT(*) AS total
                FROM mantenimiento m
                LEFT JOIN mantenimiento_programado mp
                       ON mp.id_programacion = m.id_programacion
                WHERE m.id_biomedico = %s
            """, (id_biomedico,))
            _sla = to_dicts(cur.fetchall())
            sla_stats = _sla[0] if _sla else {"dentro_sla": 0, "programados": 0, "total": 0}

            # Reportes de gráficas — leídos desde MongoDB
            _mg = get_mongo_db()
            rpt_por_tipo_mant    = mg_rpt_por_tipo_mant(_mg)
            rpt_por_resultado    = mg_rpt_por_resultado(_mg)
            rpt_equipos_mas_mant = mg_rpt_equipos_mas_mant(_mg)
            rpt_mants_por_mes    = mg_rpt_mants_por_mes(_mg)

            
            # Mantenimientos programados pendientes y vencidos
            cur.execute("SELECT * FROM v_mantenimientos_programados_pendientes ORDER BY fecha_proximo_mantenimiento ASC")
            programados_pendientes = to_dicts(cur.fetchall())

            # Alertas preventivas por equipo
            cur.execute("SELECT * FROM v_alertas_preventivas ORDER BY prox_mant_sugerido NULLS FIRST")
            alertas_preventivas = to_dicts(cur.fetchall())

            cur.execute("SELECT * FROM v_equipos_activos ORDER BY nombre_equipo")
            todos_equipos = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_tipo_mantenimiento, tipo_mantenimiento
                FROM tipo_mantenimientos ORDER BY tipo_mantenimiento
            """)
            tipos_mant = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_resultado_mantenimiento, resultado_mantenimiento
                FROM tipo_resultado_mantenimientos
                ORDER BY resultado_mantenimiento
            """)
            resultados = to_dicts(cur.fetchall())

    return render_template(
        "biomedico.html",
        mis_mants=mis_mants, criticos=criticos, carga=carga,
        todos_equipos=todos_equipos, tipos_mant=tipos_mant,
        resultados=resultados,
        rpt_por_tipo_mant=rpt_por_tipo_mant,
        rpt_por_resultado=rpt_por_resultado,
        rpt_equipos_mas_mant=rpt_equipos_mas_mant,
        rpt_mants_por_mes=rpt_mants_por_mes,
        mants_por_tipo_equipo=mants_por_tipo_equipo,
        costo_stats=costo_stats,
        sla_stats=sla_stats,
        programados_pendientes=programados_pendientes,
        alertas_preventivas=alertas_preventivas,
    )


@app.route("/biomedico/mantenimiento", methods=["POST"])
@login_required
@role_required("biomedico", "admin")
def biomedico_mant():
    """
    SP real: sp_registrar_mantenimiento(
        p_id_usuario, p_id_equipo, p_id_biomedico,
        p_id_tipo_mantenimiento, p_descripcion,
        p_id_resultado_mantenimiento  [OUT p_id_mantenimiento]
    )
    SCHEMA FIX #6: se pasa id_biomedico, no id_persona.
    """
    f = request.form
    if not all([f.get("id_equipo"), f.get("id_tipo"),
                f.get("descripcion"), f.get("id_resultado")]):
        flash("Completa todos los campos.", "error")
        return redirect(url_for("biomedico_v"))

    # Validar que el costo sea positivo si se proporcion?
    costo_raw = f.get("costo", "").strip()
    costo = None
    if costo_raw:
        try:
            costo = float(costo_raw)
            if costo < 0:
                flash("El costo no puede ser negativo.", "error")
                return redirect(url_for("biomedico_v"))
        except ValueError:
            flash("El costo debe ser un número válido.", "error")
            return redirect(url_for("biomedico_v"))

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "SELECT id_biomedico FROM biomedico WHERE id_persona = %s",
                    (session["id_persona"],)
                )
                bio_row = cur.fetchone()
                if not bio_row:
                    flash("No se encontró perfil de biomédico para este usuario.", "error")
                    return redirect(url_for("biomedico_v"))

                # Vincular a programación si viene del formulario
                id_prog = f.get("id_programacion") or None
                if id_prog:
                    id_prog = int(id_prog)

                set_audit_context(cur, "web_biomedico")
                cur.execute(
                    "CALL sp_registrar_mantenimiento(%s,%s,%s,%s,%s,%s,NULL,%s,%s,%s,%s)",
                    (
                        session["id_usuario"],
                        int(f["id_equipo"]),
                        bio_row["id_biomedico"],
                        int(f["id_tipo"]),
                        f["descripcion"],
                        int(f["id_resultado"]),
                        id_prog,
                        costo,
                        None,
                        "web_biomedico",
                    )
                )
            c.commit()
        flash("Mantenimiento registrado.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return redirect(url_for("biomedico_v"))


@app.route("/biomedico/mantenimiento/<int:id_mant>/editar", methods=["POST"])
@login_required
@role_required("biomedico", "admin")
def biomedico_editar_mant(id_mant):
    """SCHEMA FIX #6: filtrar por id_biomedico."""
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "SELECT id_biomedico FROM biomedico WHERE id_persona = %s",
                    (session["id_persona"],)
                )
                bio_row = cur.fetchone()
                if not bio_row:
                    flash("Perfil de biomédico no encontrado.", "error")
                    return redirect(url_for("biomedico_v"))

                set_audit_context(cur, "web_biomedico")
                cur.execute("""
                    UPDATE mantenimiento
                    SET id_tipo_mantenimiento      = %s,
                        descripcion_mantenimiento  = %s,
                        id_resultado_mantenimiento = %s
                    WHERE id_mantenimiento = %s
                      AND id_biomedico     = %s
                """, (
                    int(f["id_tipo"]),
                    f["descripcion"],
                    int(f["id_resultado"]),
                    id_mant,
                    bio_row["id_biomedico"],
                ))
            c.commit()
        flash("Mantenimiento actualizado.", "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("biomedico_v"))


@app.route("/biomedico/mantenimiento/<int:id_mant>/eliminar", methods=["POST"])
@login_required
@role_required("biomedico", "admin")
def biomedico_eliminar_mant(id_mant):
    """SCHEMA FIX #6: filtrar por id_biomedico."""
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "SELECT id_biomedico FROM biomedico WHERE id_persona = %s",
                    (session["id_persona"],)
                )
                bio_row = cur.fetchone()
                if not bio_row:
                    flash("Perfil de biomédico no encontrado.", "error")
                    return redirect(url_for("biomedico_v"))

                set_audit_context(cur, "web_biomedico")
                cur.execute(
                    "DELETE FROM mantenimiento WHERE id_mantenimiento = %s AND id_biomedico = %s",
                    (id_mant, bio_row["id_biomedico"])
                )
            c.commit()
        flash("Mantenimiento eliminado.", "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("biomedico_v"))



# ENFERMERO/A

@app.route("/enfermero")
@login_required
@role_required("enfermero", "responsable", "admin")
def enfermero_v():
    ip = session["id_persona"]
    with get_db() as c:
        with c.cursor() as cur:
            # Área asignada al enfermero via especialidad
            cur.execute("""
                SELECT eae.id_area, ar.nombre_area
                FROM enfermero en
                JOIN especialidad_area_enfermero eae
                        ON eae.id_especialidad_enfermero = en.id_especialidad_enfermero
                JOIN area_registro ar ON ar.id_area = eae.id_area
                WHERE en.id_persona = %s
                LIMIT 1
            """, (ip,))
            row_area = cur.fetchone()
            id_area_enf   = row_area["id_area"]    if row_area else None
            nombre_area_enf = row_area["nombre_area"] if row_area else "Hospital"

            # Equipos del área asignada (dashboard y stats)
            if id_area_enf:
                cur.execute("""
                    SELECT * FROM v_equipos_por_area WHERE id_area = %s ORDER BY nombre_equipo
                """, (id_area_enf,))
            else:
                cur.execute("SELECT * FROM v_equipos_por_area ORDER BY nombre_equipo")
            equipos_area = to_dicts(cur.fetchall())

            # Inventario global (tabla completa y formularios)
            # SCHEMA FIXES: #1 nombre_area, #4 id_ubicacion_administrativa_actual
            cur.execute("""
                SELECT e.nombre_equipo,
                       e.codigo_interno,
                       ee.estado_equipo,
                       ue.nombre_ubicacion,
                       ar.nombre_area AS area
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                JOIN ubicacion_especifica ue
                        ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                JOIN area_registro ar ON ar.id_area = ue.id_area
                WHERE e.activo_equipo = TRUE
                ORDER BY ar.nombre_area, e.nombre_equipo
            """)
            equipos = to_dicts(cur.fetchall())

            # Mis movimientos
            # SCHEMA FIXES: #8 id_persona_responsable_movimiento, #9 fecha_hora_movimiento
            cur.execute("""
                SELECT m.id_movimiento,
                       e.nombre_equipo,
                       tm.tipo_movimiento,
                       uo.nombre_ubicacion AS origen,
                       ud.nombre_ubicacion AS destino,
                       m.fecha_hora_movimiento,
                       m.observacion_movimiento
                FROM movimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_movimientos tm
                        ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                JOIN ubicacion_especifica uo
                        ON uo.id_ubicacion = m.id_ubicacion_origen
                JOIN ubicacion_especifica ud
                        ON ud.id_ubicacion = m.id_ubicacion_destino
                WHERE m.id_persona_responsable_movimiento = %s
                ORDER BY m.fecha_hora_movimiento DESC
            """, (ip,))
            mis_movs = to_dicts(cur.fetchall())

            # Usos clínicos del área del enfermero
            if id_area_enf:
                cur.execute("""
                    SELECT * FROM v_usos_clinicos_area
                    WHERE id_area = %s
                    ORDER BY fecha_hora_inicio DESC
                    LIMIT 20
                """, (id_area_enf,))
            else:
                cur.execute("""
                    SELECT * FROM v_usos_clinicos_area
                    ORDER BY fecha_hora_inicio DESC
                    LIMIT 20
                """)
            historial_usos = to_dicts(cur.fetchall())

            # Mis usos clínicos (filtrado por enfermero en sesión)
            cur.execute("""
                SELECT * FROM v_mis_usos_clinicos
                WHERE id_persona_responsable_uso = %s
                ORDER BY fecha_hora_inicio DESC
                LIMIT 20
            """, (ip,))
            mis_usos = to_dicts(cur.fetchall())

            # Reportes de gráficas — leídos desde MongoDB
            _mg = get_mongo_db()
            rpt_movs_area     = mg_rpt_movs_area(_mg)
            rpt_freq_tipo_mov = mg_rpt_freq_mov(_mg)
            rpt_estados_area  = mg_rpt_estados_area(_mg, id_area_enf) if id_area_enf else mg_rpt_estados(_mg)

            cur.execute("""
                SELECT id_equipo, codigo_interno, nombre_equipo
                FROM equipo WHERE activo_equipo = TRUE
                ORDER BY nombre_equipo
            """)
            todos_equipos = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_tipo_movimiento, tipo_movimiento
                FROM tipo_movimientos ORDER BY tipo_movimiento
            """)
            tipos_mov = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_ubicacion, nombre_ubicacion
                FROM ubicacion_especifica ORDER BY nombre_ubicacion
            """)
            ubicaciones = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_persona,
                       nombre_persona || ' ' || apellido_persona AS nombre
                FROM persona ORDER BY apellido_persona, nombre_persona
            """)
            personas = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_tipo_procedimiento, tipo_procedimiento
                FROM tipo_procedimiento ORDER BY tipo_procedimiento
            """)
            tipos_proc = to_dicts(cur.fetchall())

    return render_template(
        "enfermero.html",
        equipos=equipos, equipos_area=equipos_area,
        mi_area_enf=nombre_area_enf,
        mis_movs=mis_movs,
        mis_usos=mis_usos,
        historial_usos=historial_usos,
        todos_equipos=todos_equipos,
        tipos_mov=tipos_mov, ubicaciones=ubicaciones,
        personas=personas,
        tipos_proc=tipos_proc,
        rpt_movs_area=rpt_movs_area,
        rpt_freq_tipo_mov=rpt_freq_tipo_mov,
        rpt_estados_area=rpt_estados_area
    )


@app.route("/enfermero/movimiento", methods=["POST"])
@login_required
@role_required("enfermero", "responsable", "admin")
def enfermero_mov():
    """
    SP real: sp_registrar_movimiento_equipo(
        p_id_usuario, p_id_equipo, p_id_persona_responsable_movimiento,
        p_id_tipo_movimiento, p_id_ubicacion_origen, p_id_ubicacion_destino
        [OUT p_id_movimiento], p_observacion
    )
    """
    f = request.form
    id_origen  = f.get("id_ubicacion_origen",  "").strip()
    id_destino = f.get("id_ubicacion_destino", "").strip()

    if not all([f.get("id_equipo"), f.get("id_tipo_movimiento"), id_origen, id_destino]):
        flash("Completa todos los campos.", "error")
        return _dashboard_enfermero()

    if id_origen == id_destino:
        flash("Origen y destino deben ser distintos.", "error")
        return _dashboard_enfermero()

    try:
        with get_db() as c:
            with c.cursor() as cur:
                # Pre-validar que el origen coincide con la ubicaci?n actual del equipo
                # (el trigger lo rechazar?a de todas formas, pero as? el mensaje es claro)
                cur.execute(
                    "SELECT id_ubicacion_administrativa_actual FROM equipo WHERE id_equipo = %s",
                    (int(f["id_equipo"]),)
                )
                eq_row = cur.fetchone()
                if eq_row and str(eq_row["id_ubicacion_administrativa_actual"]) != id_origen:
                    flash(
                        "La ubicación de origen no coincide con la ubicación actual "
                        "del equipo en el sistema. Recarga la página para actualizar.",
                        "error",
                    )
                    return _dashboard_enfermero()

                set_audit_context(cur, "web_enfermero")
                cur.execute(
                    "CALL sp_registrar_movimiento_equipo(%s,%s,%s,%s,%s,%s,NULL,%s,%s,%s)",
                    (
                        session["id_usuario"],
                        int(f["id_equipo"]),
                        session["id_persona"],
                        int(f["id_tipo_movimiento"]),
                        int(id_origen),
                        int(id_destino),
                        f.get("observacion", "Movimiento registrado"),
                        None,
                        "web_enfermero",
                    )
                )
            c.commit()
        flash("Movimiento registrado.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return _dashboard_enfermero()


@app.route("/enfermero/movimiento/<int:id_mov>/eliminar", methods=["POST"])
@login_required
@role_required("enfermero", "responsable", "admin")
def enfermero_eliminar_mov(id_mov):
    """SCHEMA FIX #8: id_persona_responsable_movimiento."""
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    DELETE FROM movimiento
                    WHERE id_movimiento                     = %s
                      AND id_persona_responsable_movimiento = %s
                """, (id_mov, session["id_persona"]))
            c.commit()
        flash("Movimiento eliminado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return _dashboard_enfermero()


@app.route("/enfermero/uso", methods=["POST"])
@login_required
@role_required("enfermero", "responsable", "admin")
def enfermero_uso():
    """Mismo flujo que medico_uso."""
    id_eq = request.form.get("id_equipo", "").strip()
    if not id_eq:
        flash("Selecciona un equipo.", "error")
        return _dashboard_enfermero()
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT ue.id_area
                    FROM equipo e
                    JOIN ubicacion_especifica ue
                            ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    WHERE e.id_equipo = %s
                """, (int(id_eq),))
                area_row = cur.fetchone()
                id_area = area_row["id_area"] if area_row else 1

                cur.execute("SELECT id_turno FROM enfermero WHERE id_persona = %s", (session["id_persona"],))
                turno_row = cur.fetchone()
                id_turno = turno_row["id_turno"] if turno_row else 1

                id_proc = int(request.form.get("id_tipo_procedimiento", 1))

                set_audit_context(cur, "web_enfermero")
                cur.execute(
                    "CALL sp_registrar_uso_clinico(%s,%s,%s,%s,%s,%s,NULL,%s,%s)",
                    (
                        session["id_usuario"],
                        int(id_eq),
                        session["id_persona"],
                        id_area,
                        id_turno,
                        id_proc,
                        None,
                        "web_enfermero",
                    )
                )
            c.commit()
        flash("Uso registrado.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return _dashboard_enfermero()


@app.route("/enfermero/uso/<int:id_uso>/cerrar", methods=["POST"])
@login_required
@role_required("enfermero", "responsable", "admin")
def enfermero_cerrar_uso(id_uso):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_enfermero")
                cur.execute(
                    "CALL sp_cerrar_uso_clinico(%s,%s,NULL,%s)",
                    (session["id_usuario"], id_uso, "web_enfermero")
                )
            c.commit()
        flash("Uso clínico cerrado correctamente.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return _dashboard_enfermero()


# RESPONSABLE DE ÁREA

@app.route("/responsable")
@login_required
@role_required("responsable", "admin")
def responsable_v():
    ip = session["id_persona"]

    with get_db() as conn:
        with conn.cursor() as cur:

            
            cur.execute("""
                SELECT ar.id_area,
                       ar.nombre_area AS area,
                       ra.fecha_inicio_responsable_area AS fecha_inicio
                FROM responsable_area ra
                JOIN enfermero en ON en.id_enfermero = ra.id_enfermero
                JOIN area_registro ar ON ar.id_area = ra.id_area
                WHERE en.id_persona = %s
                  AND ra.fecha_fin_responsable_area IS NULL
                LIMIT 1
            """, (ip,))
            mi_area = cur.fetchone()
            id_area = mi_area["id_area"] if mi_area else -1

            
            cur.execute("""
                SELECT e.id_equipo,
                       e.codigo_interno,
                       e.nombre_equipo,
                       ma.nombre_marca  AS marca,
                       ee.estado_equipo,
                       ee.id_estado_equipo,
                       ue.nombre_ubicacion
                FROM equipo e
                JOIN estado_equipos ee
                        ON ee.id_estado_equipo = e.id_estado_equipo
                JOIN ubicacion_especifica ue
                        ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                JOIN area_registro ar ON ar.id_area = ue.id_area
                JOIN modelo_equipo me ON me.id_modelo = e.id_modelo
                JOIN marca_equipo ma  ON ma.id_marca  = me.id_marca
                WHERE ar.id_area = %s AND e.activo_equipo = TRUE
                ORDER BY e.nombre_equipo
            """, (id_area,))
            equipos_area = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT ae.id_asignacion,
                       e.nombre_equipo,
                       e.codigo_interno,
                       p.nombre_persona || ' ' || p.apellido_persona AS asignado_a,
                       ue.nombre_ubicacion,
                       ae.fecha_inicio_asignacion,
                       ae.observacion_asignacion
                FROM asignacion_equipo ae
                JOIN equipo e ON e.id_equipo = ae.id_equipo
                JOIN persona p ON p.id_persona = ae.id_persona_responsable
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = ae.id_ubicacion
                WHERE ue.id_area = %s
                  AND ae.fecha_fin_asignacion IS NULL
                ORDER BY ae.fecha_inicio_asignacion DESC
            """, (id_area,))
            asignaciones = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT m.id_movimiento,
                       e.nombre_equipo,
                       tm.tipo_movimiento,
                       uo.nombre_ubicacion AS origen,
                       ud.nombre_ubicacion AS destino,
                       p.nombre_persona || ' ' || p.apellido_persona AS responsable,
                       m.fecha_hora_movimiento,
                       m.observacion_movimiento
                FROM movimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_movimientos tm
                        ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                JOIN ubicacion_especifica uo ON uo.id_ubicacion = m.id_ubicacion_origen
                JOIN ubicacion_especifica ud ON ud.id_ubicacion = m.id_ubicacion_destino
                JOIN persona p
                        ON p.id_persona = m.id_persona_responsable_movimiento
                WHERE uo.id_area = %s OR ud.id_area = %s
                ORDER BY m.fecha_hora_movimiento DESC
                LIMIT 100
            """, (id_area, id_area))
            movimientos = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT p.nombre_persona,
                       p.apellido_persona,
                       p.correo_persona,
                       ee.especialidad_enfermero
                FROM enfermero en
                JOIN persona p ON p.id_persona = en.id_persona
                JOIN especialidades_enfermero ee
                        ON ee.id_especialidad_enfermero = en.id_especialidad_enfermero
                JOIN usuario u ON u.id_persona = en.id_persona
                WHERE u.activo_usuario = TRUE
                ORDER BY p.apellido_persona
            """)
            personal = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT ar.nombre_area AS area,
                       p.nombre_persona || ' ' || p.apellido_persona AS responsable,
                       ra.fecha_inicio_responsable_area AS fecha_inicio
                FROM responsable_area ra
                JOIN enfermero en ON en.id_enfermero = ra.id_enfermero
                JOIN persona p ON p.id_persona = en.id_persona
                JOIN area_registro ar ON ar.id_area = ra.id_area
                WHERE ra.fecha_fin_responsable_area IS NULL
                ORDER BY ar.nombre_area
            """)
            responsables_activos = to_dicts(cur.fetchall())

            
            cur.execute("""
                SELECT id_estado_equipo, estado_equipo
                FROM estado_equipos ORDER BY estado_equipo
            """)
            estados_cat = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT codigo_interno, nombre_equipo, criticidad_equipo,
                       tipo_mantenimiento, fecha_proximo_mantenimiento,
                       estado_cumplimiento, tiempo_restante, observacion_programacion
                FROM v_mantenimientos_proximos_por_area
                WHERE id_area = %s
                ORDER BY fecha_proximo_mantenimiento
                LIMIT 10
            """, (id_area,))
            mants_proximos = to_dicts(cur.fetchall())

            # Mis movimientos
            cur.execute("""
                SELECT m.id_movimiento, e.nombre_equipo,
                       tm.tipo_movimiento,
                       uo.nombre_ubicacion AS origen,
                       ud.nombre_ubicacion AS destino,
                       m.fecha_hora_movimiento, m.observacion_movimiento
                FROM movimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_movimientos tm ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                JOIN ubicacion_especifica uo ON uo.id_ubicacion = m.id_ubicacion_origen
                JOIN ubicacion_especifica ud ON ud.id_ubicacion = m.id_ubicacion_destino
                WHERE m.id_persona_responsable_movimiento = %s
                ORDER BY m.fecha_hora_movimiento DESC
                LIMIT 20
            """, (ip,))
            mis_movs = to_dicts(cur.fetchall())

            # Mis usos clínicos
            cur.execute("""
                SELECT * FROM v_mis_usos_clinicos
                WHERE id_persona_responsable_uso = %s
                ORDER BY fecha_hora_inicio DESC
                LIMIT 20
            """, (ip,))
            mis_usos = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_equipo, codigo_interno, nombre_equipo
                FROM equipo WHERE activo_equipo = TRUE ORDER BY nombre_equipo
            """)
            todos_equipos = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_tipo_movimiento, tipo_movimiento
                FROM tipo_movimientos ORDER BY tipo_movimiento
            """)
            tipos_mov = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_ubicacion, nombre_ubicacion
                FROM ubicacion_especifica ORDER BY nombre_ubicacion
            """)
            ubicaciones = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_persona, nombre_persona || ' ' || apellido_persona AS nombre
                FROM persona ORDER BY apellido_persona, nombre_persona
            """)
            personas = to_dicts(cur.fetchall())

            cur.execute("""
                SELECT id_tipo_procedimiento, tipo_procedimiento
                FROM tipo_procedimiento ORDER BY tipo_procedimiento
            """)
            tipos_proc = to_dicts(cur.fetchall())

            # Reportes de gráficas — leídos desde MongoDB
            _mg = get_mongo_db()
            rpt_estados_area      = mg_rpt_estados_area(_mg, id_area)
            rpt_tipos_movs        = mg_rpt_tipos_movs(_mg, id_area)
            rpt_actividad_equipos = mg_rpt_actividad_equipos(_mg, id_area)
            rpt_movs_dia          = mg_rpt_movs_por_dia(_mg, id_area)

    return render_template(
        "responsable.html",
        mi_area=mi_area,
        equipos_area=equipos_area,
        asignaciones=asignaciones,
        movimientos=movimientos,
        mis_movs=mis_movs,
        mis_usos=mis_usos,
        todos_equipos=todos_equipos,
        tipos_mov=tipos_mov,
        ubicaciones=ubicaciones,
        personas=personas,
        tipos_proc=tipos_proc,
        personal=personal,
        responsables_activos=responsables_activos,
        estados_cat=estados_cat,
        rpt_estados_area=rpt_estados_area,
        rpt_tipos_movs=rpt_tipos_movs,
        rpt_actividad_equipos=rpt_actividad_equipos,
        rpt_movs_dia=rpt_movs_dia,
        mants_proximos=mants_proximos,
    )


@app.route("/responsable/equipo/<int:id_equipo>/estado", methods=["POST"])
@login_required
@role_required("responsable", "admin")
def responsable_cambiar_estado(id_equipo):
    """SP real: sp_cambiar_estado_equipo(p_id_usuario, p_id_equipo, p_id_nuevo_estado [OUT p_mensaje])"""
    nuevo_estado = request.form.get("id_estado_equipo", "").strip()
    if not nuevo_estado:
        flash("Selecciona un estado.", "error")
        return redirect(url_for("responsable_v"))
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_responsable")
                cur.execute(
                    "CALL sp_cambiar_estado_equipo(%s,%s,%s,NULL,%s)",
                    (session["id_usuario"], id_equipo, int(nuevo_estado), "web_responsable")
                )
            c.commit()
        flash("Estado del equipo actualizado.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return redirect(url_for("responsable_v"))


@app.route("/responsable/asignacion/<int:id_asignacion>/liberar", methods=["POST"])
@login_required
@role_required("responsable", "admin")
def responsable_liberar_asignacion(id_asignacion):
    """SP real: sp_cerrar_asignacion_equipo(p_id_usuario, p_id_asignacion [OUT p_mensaje], p_observacion)"""
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_responsable")
                cur.execute(
                    "CALL sp_cerrar_asignacion_equipo(%s,%s,NULL,%s,%s)",
                    (
                        session["id_usuario"],
                        id_asignacion,
                        "Liberado por responsable de área",
                        "web_responsable",
                    )
                )
            c.commit()
        flash("Asignación liberada.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return redirect(url_for("responsable_v"))



# FASE 4 — Panel IoT y Auditoría Visual (Admin)

@app.route("/admin/iot")
@login_required
@role_required("admin")
def admin_iot():
    """
    Panel de monitoreo IoT. Consume:
    - v_discrepancia_ubicacion_iot  : equipos con ubicacion Beacon != BD.
    - v_equipos_sin_evidencia_iot   : equipos sin senial en >12 horas.
    - evento_nfc                    : ultimas 50 lecturas NFC detalladas.
    - evento_beacon + zona_beacon   : ultimos 50 eventos Beacon.
    - dispositivo_beacon            : inventario de beacons.
    - dispositivo_nfc               : inventario de NFC.
    - v_admin_auditoria_reciente    : ultimas 100 acciones auditadas.
    - v_actividad_sistema_por_usuario: metricas por usuario.
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:

                # Discrepancias Beacon vs Administrativo
                cur.execute("""
                    SELECT id_equipo, codigo_interno, nombre_equipo,
                           ubicacion_administrativa, area_administrativa,
                           ubicacion_evidencia_beacon, area_evidencia_beacon,
                           fecha_ultima_evidencia_beacon, resultado
                    FROM v_discrepancia_ubicacion_iot
                    ORDER BY resultado DESC,
                             fecha_ultima_evidencia_beacon DESC NULLS LAST
                """)
                discrepancias = to_dicts(cur.fetchall())

                # Equipos sin evidencia IoT en las ultimas 12 horas
                cur.execute("""
                    SELECT id_equipo, codigo_interno, nombre_equipo,
                           criticidad_equipo, ultima_evidencia_nfc,
                           ultima_evidencia_beacon, ultima_evidencia_iot
                    FROM v_equipos_sin_evidencia_iot
                    ORDER BY ultima_evidencia_iot ASC
                """)
                sin_evidencia = to_dicts(cur.fetchall())

                # Ultimos 50 eventos NFC con detalle de equipo
                cur.execute("""
                    SELECT en.id_evento_nfc,
                           en.fecha_hora_evento,
                           tn.tipo_evento_nfc,
                           dn.codigo_uid_nfc,
                           e.nombre_equipo,
                           e.codigo_interno,
                           ee.estado_equipo,
                           ue.nombre_ubicacion,
                           ar.nombre_area
                    FROM evento_nfc en
                    JOIN tipo_eventos_nfc    tn  ON tn.id_tipo_evento_nfc  = en.id_tipo_evento_nfc
                    JOIN dispositivo_nfc     dn  ON dn.id_nfc              = en.id_nfc
                    JOIN equipo              e   ON e.id_equipo            = dn.id_equipo
                    JOIN estado_equipos      ee  ON ee.id_estado_equipo    = e.id_estado_equipo
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    JOIN area_registro        ar ON ar.id_area      = ue.id_area
                    ORDER BY en.fecha_hora_evento DESC
                    LIMIT 50
                """)
                eventos_nfc = to_dicts(cur.fetchall())

                # Ultimos 50 eventos Beacon con zona
                cur.execute("""
                    SELECT eb.id_evento_beacon,
                           eb.fecha_hora_evento,
                           teb.tipo_evento_beacon,
                           dbb.uuid_beacon,
                           zb.nombre_zona_beacon,
                           ue.nombre_ubicacion,
                           ar.nombre_area,
                           e.nombre_equipo,
                           e.codigo_interno
                    FROM evento_beacon eb
                    JOIN tipo_eventos_beacon  teb ON teb.id_tipo_evento_beacon = eb.id_tipo_evento_beacon
                    JOIN dispositivo_beacon   dbb ON dbb.id_beacon             = eb.id_beacon
                    JOIN zona_beacon          zb  ON zb.id_zona_beacon         = dbb.id_zona_beacon
                    JOIN ubicacion_especifica ue  ON ue.id_ubicacion           = zb.id_ubicacion
                    JOIN area_registro        ar  ON ar.id_area                = ue.id_area
                    JOIN equipo               e   ON e.id_equipo               = eb.id_equipo
                    ORDER BY eb.fecha_hora_evento DESC
                    LIMIT 50
                """)
                eventos_beacon = to_dicts(cur.fetchall())

                # Inventario de Beacons
                cur.execute("""
                    SELECT dbb.id_beacon, dbb.uuid_beacon,
                           dbb.major_beacon, dbb.minor_beacon,
                           dbb.activo_beacon,
                           zb.nombre_zona_beacon,
                           ue.nombre_ubicacion,
                           ar.nombre_area
                    FROM dispositivo_beacon  dbb
                    JOIN zona_beacon          zb  ON zb.id_zona_beacon = dbb.id_zona_beacon
                    JOIN ubicacion_especifica ue  ON ue.id_ubicacion   = zb.id_ubicacion
                    JOIN area_registro        ar  ON ar.id_area        = ue.id_area
                    ORDER BY ar.nombre_area, dbb.uuid_beacon
                """)
                beacons = to_dicts(cur.fetchall())

                # Inventario de NFC
                cur.execute("""
                    SELECT dn.id_nfc, dn.codigo_uid_nfc, dn.activo_nfc,
                           e.nombre_equipo, e.codigo_interno,
                           ee.estado_equipo
                    FROM dispositivo_nfc  dn
                    JOIN equipo         e  ON e.id_equipo         = dn.id_equipo
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    ORDER BY e.codigo_interno
                """)
                dispositivos_nfc = to_dicts(cur.fetchall())

                # Zonas y equipos para formularios de inventario IoT
                cur.execute("""
                    SELECT id_zona_beacon, nombre_zona_beacon
                    FROM zona_beacon
                    ORDER BY nombre_zona_beacon
                """)
                zonas_beacon = to_dicts(cur.fetchall())

                cur.execute("""
                    SELECT id_equipo, codigo_interno, nombre_equipo
                    FROM equipo
                    WHERE activo_equipo = TRUE
                    ORDER BY nombre_equipo
                """)
                equipos_activos = to_dicts(cur.fetchall())

                # Auditoria reciente (ultimas 100 acciones)
                cur.execute("""
                    SELECT id_auditoria, tabla_afectada, accion_auditoria,
                           id_registro_afectado, ejecutado_por, origen_cambio,
                           fecha_hora_auditoria, nivel_atencion
                    FROM v_admin_auditoria_reciente
                    LIMIT 100
                """)
                auditoria_reciente = to_dicts(cur.fetchall())

                # Actividad del sistema por usuario
                cur.execute("""
                    SELECT username, rol_usuario, total_operaciones,
                           ultima_actividad, tablas_distintas_afectadas
                    FROM v_actividad_sistema_por_usuario
                """)
                actividad_usuarios = to_dicts(cur.fetchall())

                cur.execute("SELECT * FROM v_ambulancias_gps ORDER BY codigo_ambulancia")
                ambulancias_gps = to_dicts(cur.fetchall())
                for row in ambulancias_gps:
                    if row.get("ultimo_ping"):
                        row["ultimo_ping"] = row["ultimo_ping"].strftime("%d/%m %H:%M:%S")
                    if row.get("latitud") is not None:
                        row["latitud"] = float(row["latitud"])
                    if row.get("longitud") is not None:
                        row["longitud"] = float(row["longitud"])

                cur.execute("SELECT * FROM v_traslados_activos")
                traslados_activos = to_dicts(cur.fetchall())
                for row in traslados_activos:
                    if row.get("fecha_salida"):
                        row["fecha_salida"] = row["fecha_salida"].strftime("%d/%m/%Y %H:%M")

                total_disc = sum(
                    1 for d in discrepancias
                    if "alerta" in d.get("resultado", "").lower()
                )

                beacons_activos = sum(1 for b in beacons if b.get("activo_beacon"))
                beacons_inactivos = len(beacons) - beacons_activos
                nfc_activos = sum(1 for n in dispositivos_nfc if n.get("activo_nfc"))
                nfc_inactivos = len(dispositivos_nfc) - nfc_activos

        return render_template(
            "admin_iot.html",
            discrepancias=discrepancias,
            sin_evidencia=sin_evidencia,
            eventos_nfc=eventos_nfc,
            eventos_beacon=eventos_beacon,
            beacons=beacons,
            dispositivos_nfc=dispositivos_nfc,
            auditoria_reciente=auditoria_reciente,
            actividad_usuarios=actividad_usuarios,
            total_disc=total_disc,
            total_sin_evidencia=len(sin_evidencia),
            beacons_activos=beacons_activos,
            beacons_inactivos=beacons_inactivos,
            nfc_activos=nfc_activos,
            nfc_inactivos=nfc_inactivos,
            zonas_beacon=zonas_beacon,
            equipos_activos=equipos_activos,
            ambulancias_gps=ambulancias_gps,
            traslados_activos=traslados_activos,
        )
    except Exception as e:
        flash(f"Error al cargar panel IoT: {friendly_db_error(e)}", "error")
        return redirect(url_for("admin_v"))


@app.route("/admin/iot/json")
@login_required
@role_required("admin")
def admin_iot_json():
    """
    Version JSON del panel IoT para polling desde el frontend.
    Devuelve discrepancias y equipos sin evidencia reciente.
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT codigo_interno, nombre_equipo,
                           ubicacion_administrativa, area_administrativa,
                           ubicacion_evidencia_beacon, area_evidencia_beacon,
                           fecha_ultima_evidencia_beacon, resultado
                    FROM v_discrepancia_ubicacion_iot
                    ORDER BY resultado DESC
                """)
                discrepancias = to_dicts(cur.fetchall())

                cur.execute("""
                    SELECT codigo_interno, nombre_equipo, criticidad_equipo,
                           ultima_evidencia_iot
                    FROM v_equipos_sin_evidencia_iot
                    ORDER BY ultima_evidencia_iot ASC
                """)
                sin_evidencia = to_dicts(cur.fetchall())

        return jsonify(
            ok=True,
            discrepancias=discrepancias,
            sin_evidencia=sin_evidencia,
            total_alertas=sum(
                1 for d in discrepancias
                if "alerta" in d.get("resultado", "").lower()
            ),
        )
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500


@app.route("/admin/iot/beacon", methods=["POST"])
@login_required
@role_required("admin")
def admin_iot_add_beacon():
    f = request.form
    uuid_beacon = f.get("uuid_beacon", "").strip()
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "CALL sp_registrar_beacon(%s,%s,%s,%s,%s,NULL,%s)",
                    (
                        session["id_usuario"],
                        uuid_beacon,
                        int(f.get("major_beacon", 0)),
                        int(f.get("minor_beacon", 0)),
                        int(f.get("id_zona_beacon", 0)),
                        "web_admin",
                    )
                )
            c.commit()
        flash("Beacon registrado correctamente.", "success")
    except Exception as e:
        flash(f"Error al registrar beacon: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_iot"))


@app.route("/admin/iot/beacon/<int:id_beacon>/toggle", methods=["POST"])
@login_required
@role_required("admin")
def admin_iot_toggle_beacon(id_beacon):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "UPDATE dispositivo_beacon SET activo_beacon = NOT activo_beacon WHERE id_beacon = %s",
                    (id_beacon,)
                )
            c.commit()
        flash("Estado del beacon actualizado.", "success")
    except Exception as e:
        flash(f"Error al actualizar beacon: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_iot"))


@app.route("/admin/iot/beacon/<int:id_beacon>/editar", methods=["POST"])
@login_required
@role_required("admin")
def admin_iot_edit_beacon(id_beacon):
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "UPDATE dispositivo_beacon SET uuid_beacon=%s, major_beacon=%s, minor_beacon=%s, id_zona_beacon=%s WHERE id_beacon=%s",
                    (
                        f.get("uuid_beacon", "").strip().upper(),
                        int(f.get("major_beacon", 0)),
                        int(f.get("minor_beacon", 0)),
                        int(f.get("id_zona_beacon", 0)),
                        id_beacon,
                    )
                )
            c.commit()
        flash("Beacon actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al editar beacon: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_iot"))


@app.route("/admin/iot/beacon/<int:id_beacon>/eliminar", methods=["POST"])
@login_required
@role_required("admin")
def admin_iot_delete_beacon(id_beacon):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute("DELETE FROM dispositivo_beacon WHERE id_beacon = %s", (id_beacon,))
            c.commit()
        flash("Beacon eliminado del inventario IoT.", "success")
    except Exception as e:
        flash(f"Error al eliminar beacon: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_iot"))


@app.route("/admin/iot/nfc", methods=["POST"])
@login_required
@role_required("admin")
def admin_iot_add_nfc():
    f = request.form
    uid = f.get("codigo_uid_nfc", "").strip()
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "INSERT INTO dispositivo_nfc (codigo_uid_nfc, activo_nfc, id_equipo) VALUES (%s,%s,%s)",
                    (
                        uid,
                        f.get("activo_nfc") == "on",
                        int(f.get("id_equipo", 0)),
                    )
                )
            c.commit()
        flash("Dispositivo NFC registrado.", "success")
    except Exception as e:
        flash(f"Error al registrar dispositivo NFC: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_iot"))


@app.route("/admin/iot/nfc/<int:id_nfc>/toggle", methods=["POST"])
@login_required
@role_required("admin")
def admin_iot_toggle_nfc(id_nfc):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "UPDATE dispositivo_nfc SET activo_nfc = NOT activo_nfc WHERE id_nfc = %s",
                    (id_nfc,)
                )
            c.commit()
        flash("Estado del dispositivo NFC actualizado.", "success")
    except Exception as e:
        flash(f"Error al actualizar NFC: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_iot"))


@app.route("/admin/iot/nfc/<int:id_nfc>/eliminar", methods=["POST"])
@login_required
@role_required("admin")
def admin_iot_delete_nfc(id_nfc):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "UPDATE dispositivo_nfc SET activo_nfc = FALSE WHERE id_nfc = %s",
                    (id_nfc,)
                )
            c.commit()
        flash("Dispositivo NFC desactivado.", "success")
    except Exception as e:
        flash(f"Error al desactivar NFC: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_iot"))


@app.route("/admin/iot/nfc/<int:id_nfc>/uid", methods=["POST"])
@login_required
@role_required("admin")
def admin_iot_update_uid_nfc(id_nfc):
    uid = request.form.get("codigo_uid_nfc", "").strip().upper()
    if not uid:
        flash("El UID no puede estar vacío.", "error")
        return redirect(url_for("admin_iot"))
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "UPDATE dispositivo_nfc SET codigo_uid_nfc = %s WHERE id_nfc = %s",
                    (uid, id_nfc)
                )
            c.commit()
        flash(f"UID actualizado a {uid}.", "success")
    except Exception as e:
        flash(f"Error al actualizar UID: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_iot"))


def _mobile_token(id_usuario):
    return URLSafeSerializer(app.secret_key, salt="mobile").dumps(id_usuario)

def _verify_mobile_token(token):
    try:
        return URLSafeSerializer(app.secret_key, salt="mobile").loads(token)
    except BadSignature:
        return None


@app.route("/api/mobile/login", methods=["POST"])
def api_mobile_login():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = (data.get("password") or "").strip()
    if not username or not password:
        return jsonify(ok=False, mensaje="Usuario y contraseña requeridos"), 400
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT u.id_usuario, u.contrasenia, p.nombre_persona, p.apellido_persona
                    FROM usuario u
                    JOIN persona p ON p.id_persona = u.id_persona
                    WHERE u.username = %s AND u.activo_usuario = TRUE
                """, (username,))
                user = cur.fetchone()
        if not user or user["contrasenia"] != password:
            return jsonify(ok=False, mensaje="Credenciales incorrectas"), 401
        token = _mobile_token(user["id_usuario"])
        return jsonify(ok=True, token=token,
                       nombre=f"{user['nombre_persona']} {user['apellido_persona']}")
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


@app.route("/api/iot/escaneo", methods=["POST"])
def api_iot_escaneo():
    data = request.get_json(silent=True) or {}
    token       = data.get("token", "")
    uid_nfc     = (data.get("uid_nfc") or "").strip().upper()
    uuid_beacon = (data.get("uuid_beacon") or "").strip().upper()
    major       = data.get("major", 0)
    minor       = data.get("minor", 0)

    id_usuario = _verify_mobile_token(token)
    if not id_usuario:
        return jsonify(ok=False, mensaje="Token inválido"), 401
    if not uid_nfc:
        return jsonify(ok=False, mensaje="UID NFC requerido"), 400

    try:
        with get_db() as c:
            with c.cursor() as cur:
                # Buscar equipo por NFC
                cur.execute("""
                    SELECT dn.id_nfc, dn.id_equipo,
                           e.nombre_equipo, e.codigo_interno,
                           ee.estado_equipo,
                           ue.nombre_ubicacion, ar.nombre_area
                    FROM dispositivo_nfc dn
                    JOIN equipo e ON e.id_equipo = dn.id_equipo
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    JOIN area_registro ar ON ar.id_area = ue.id_area
                    WHERE dn.codigo_uid_nfc = %s AND dn.activo_nfc = TRUE
                """, (uid_nfc,))
                tag = cur.fetchone()
                if not tag:
                    return jsonify(ok=False, mensaje="Tag NFC no reconocido o inactivo"), 404

                # Registrar evento NFC (tipo 1 = Lectura)
                cur.execute("""
                    INSERT INTO evento_nfc (id_nfc, id_tipo_evento_nfc, fecha_hora_evento)
                    VALUES (%s, 1, NOW()) RETURNING id_evento_nfc
                """, (tag["id_nfc"],))
                id_evento_nfc = cur.fetchone()["id_evento_nfc"]

                # Buscar beacon y registrar evento beacon si se proporcionó
                id_evento_beacon = None
                area_beacon = None
                if uuid_beacon:
                    cur.execute("""
                        SELECT db.id_beacon, zb.nombre_zona_beacon
                        FROM dispositivo_beacon db
                        JOIN zona_beacon zb ON zb.id_zona_beacon = db.id_zona_beacon
                        WHERE db.uuid_beacon = %s
                          AND db.major_beacon = %s
                          AND db.minor_beacon = %s
                          AND db.activo_beacon = TRUE
                    """, (uuid_beacon, int(major), int(minor)))
                    beacon = cur.fetchone()
                    if beacon:
                        cur.execute("""
                            INSERT INTO evento_beacon (id_beacon, id_equipo, fecha_hora_evento, id_tipo_evento_beacon)
                            VALUES (%s, %s, NOW(), 1) RETURNING id_evento_beacon
                        """, (beacon["id_beacon"], tag["id_equipo"]))
                        id_evento_beacon = cur.fetchone()["id_evento_beacon"]
                        area_beacon = beacon["nombre_zona_beacon"]

                cur.execute("SELECT id_persona FROM usuario WHERE id_usuario = %s", (id_usuario,))
                user_row = cur.fetchone()
                id_persona = user_row["id_persona"] if user_row else None

                uso_activo_row = None
                tipos_proc     = []
                if id_persona:
                    cur.execute("""
                        SELECT uce.id_uso_clinico, tp.tipo_procedimiento,
                               uce.fecha_hora_inicio
                        FROM uso_clinico_equipo uce
                        JOIN tipo_procedimiento tp
                                ON tp.id_tipo_procedimiento = uce.id_tipo_procedimiento
                        WHERE uce.id_equipo = %s
                          AND uce.id_persona_responsable_uso = %s
                          AND uce.fecha_hora_fin IS NULL
                        ORDER BY uce.fecha_hora_inicio DESC
                        LIMIT 1
                    """, (tag["id_equipo"], id_persona))
                    uso_activo_row = cur.fetchone()

                    cur.execute("""
                        SELECT id_tipo_procedimiento, tipo_procedimiento
                        FROM tipo_procedimiento ORDER BY tipo_procedimiento
                    """)
                    tipos_proc = to_dicts(cur.fetchall())

            c.commit()

        uso_activo = None
        if uso_activo_row:
            uso_activo = dict(uso_activo_row)
            if uso_activo.get("fecha_hora_inicio"):
                uso_activo["fecha_hora_inicio"] = uso_activo["fecha_hora_inicio"].strftime("%d/%m %H:%M")

        return jsonify(
            ok=True,
            id_evento_nfc=id_evento_nfc,
            id_evento_beacon=id_evento_beacon,
            equipo=dict(tag),
            area_detectada=area_beacon,
            uso_activo=uso_activo,
            tipos_proc=tipos_proc,
        )
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


@app.route("/api/iot/uso/registrar", methods=["POST"])
def api_iot_uso_registrar():
    data    = request.get_json(silent=True) or {}
    token   = data.get("token", "")
    id_eq   = data.get("id_equipo")
    id_proc = data.get("id_tipo_procedimiento")

    id_usuario = _verify_mobile_token(token)
    if not id_usuario:
        return jsonify(ok=False, mensaje="Token inválido"), 401
    if not id_eq or not id_proc:
        return jsonify(ok=False, mensaje="Faltan datos"), 400
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("SELECT id_persona FROM usuario WHERE id_usuario = %s", (id_usuario,))
                u = cur.fetchone()
                id_persona = u["id_persona"] if u else None

                cur.execute("""
                    SELECT ue.id_area FROM equipo e
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    WHERE e.id_equipo = %s
                """, (int(id_eq),))
                a = cur.fetchone()
                id_area = a["id_area"] if a else 1

                cur.execute("""
                    SELECT id_turno FROM enfermero WHERE id_persona = %s
                    UNION
                    SELECT id_turno FROM medico WHERE id_persona = %s
                    LIMIT 1
                """, (id_persona, id_persona))
                t = cur.fetchone()
                id_turno = t["id_turno"] if t else 1

                set_audit_context(cur, "flutter_movil")
                cur.execute(
                    "CALL sp_registrar_uso_clinico(%s,%s,%s,%s,%s,%s,NULL,%s,%s)",
                    (id_usuario, int(id_eq), id_persona, id_area, id_turno,
                     int(id_proc), None, "flutter_movil")
                )
            c.commit()
        return jsonify(ok=True, mensaje="Uso clínico registrado")
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500


@app.route("/api/iot/uso/cerrar", methods=["POST"])
def api_iot_uso_cerrar():
    data   = request.get_json(silent=True) or {}
    token  = data.get("token", "")
    id_uso = data.get("id_uso_clinico")

    id_usuario = _verify_mobile_token(token)
    if not id_usuario:
        return jsonify(ok=False, mensaje="Token inválido"), 401
    if not id_uso:
        return jsonify(ok=False, mensaje="ID de uso requerido"), 400
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "flutter_movil")
                cur.execute("CALL sp_cerrar_uso_clinico(%s,%s,NULL,%s)",
                    (id_usuario, int(id_uso), "flutter_movil"))
            c.commit()
        return jsonify(ok=True, mensaje="Uso clínico cerrado")
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500


@app.route("/api/nfc/evento", methods=["POST"])
@login_required
def api_nfc_evento():
    """Recibe un escaneo NFC desde la app móvil y registra el evento."""
    data = request.get_json(silent=True) or {}
    uid  = (data.get("uid_nfc") or "").strip().upper()
    tipo = data.get("id_tipo_evento_nfc", 1)

    if not uid:
        return jsonify(ok=False, mensaje="UID requerido"), 400

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT dn.id_nfc, dn.id_equipo,
                           e.nombre_equipo, e.codigo_interno,
                           ee.estado_equipo
                    FROM dispositivo_nfc dn
                    JOIN equipo e ON e.id_equipo = dn.id_equipo
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    WHERE dn.codigo_uid_nfc = %s AND dn.activo_nfc = TRUE
                """, (uid,))
                tag = cur.fetchone()

                if not tag:
                    return jsonify(ok=False, mensaje="Tag NFC no reconocido o inactivo"), 404

                cur.execute("""
                    INSERT INTO evento_nfc (id_nfc, id_tipo_evento_nfc, fecha_hora_evento)
                    VALUES (%s, %s, NOW())
                    RETURNING id_evento_nfc
                """, (tag["id_nfc"], int(tipo)))
                id_evento = cur.fetchone()["id_evento_nfc"]
            c.commit()

        return jsonify(ok=True, id_evento_nfc=id_evento, equipo=dict(tag))
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500



# FASE 3B ? sp_cambiar_responsable_area (Admin)

@app.route("/admin/responsable_area", methods=["POST"])
@login_required
@role_required("admin")
def admin_cambiar_responsable_area():
    """
    SP real: sp_cambiar_responsable_area(
        p_id_usuario, p_id_area, p_id_enfermero_nuevo  [OUT p_mensaje]
    )
    Cierra el responsable activo del area (si existe) y registra el nuevo.
    El trigger fn_validar_especialidad_responsable_area verifica que el
    enfermero tenga la especialidad requerida para el area.
    """
    f = request.form
    id_area      = f.get("id_area", "").strip()
    id_enfermero = f.get("id_enfermero", "").strip()
    if not id_area or not id_enfermero:
        flash("Area y enfermero son obligatorios.", "error")
        return redirect(url_for("admin_v") + "#v-usuarios")
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_cambiar_responsable_area(%s,%s,%s,NULL,%s)",
                    (session["id_usuario"], int(id_area), int(id_enfermero), "web_admin")
                )
            c.commit()
        flash("Responsable de area actualizado correctamente.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return redirect(url_for("admin_v") + "#v-usuarios")



# FASE 3B ? sp_reprogramar_mantenimiento (Biomedico)

@app.route("/biomedico/reprogramar", methods=["POST"])
@login_required
@role_required("biomedico", "admin")
def biomedico_reprogramar():
    """
    SP real: sp_reprogramar_mantenimiento(
        p_id_usuario, p_id_programacion, p_nueva_fecha  [OUT p_mensaje],
        p_observacion
    )
    Solo se pueden reprogramar mantenimientos en estado Pendiente (1) o Vencido (3).
    La nueva fecha debe ser futura.
    """
    f = request.form
    id_prog     = f.get("id_programacion", "").strip()
    nueva_fecha = f.get("nueva_fecha", "").strip()
    observacion = f.get("observacion", "").strip() or None

    if not id_prog or not nueva_fecha:
        flash("Programacion y nueva fecha son obligatorios.", "error")
        return redirect(url_for("biomedico_v"))

    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_biomedico")
                cur.execute(
                    "CALL sp_reprogramar_mantenimiento(%s,%s,%s::TIMESTAMP,NULL,%s,%s)",
                    (session["id_usuario"], int(id_prog), nueva_fecha, observacion, "web_biomedico")
                )
            c.commit()
        flash("Mantenimiento reprogramado correctamente.", "success")
    except Exception as e:
        flash(friendly_db_error(e), "error")
    return redirect(url_for("biomedico_v"))



# FASE 3B ? sp_reporte_carga_biomedica con fechas dinamicas (Admin)

@app.route("/admin/reporte/carga_biomedica")
@login_required
@role_required("admin")
def admin_reporte_carga_biomedica():
    """
    Endpoint JSON que consume sp_reporte_carga_biomedica con rango
    de fechas dinamico pasado via query string:
    ?fecha_inicio=YYYY-MM-DD&fecha_fin=YYYY-MM-DD

    Campos del SP: biomedico, total_mantenimientos, exitosos,
    desfavorables, costo_total_gestionado, costo_promedio,
    primer_mantenimiento_periodo, ultimo_mantenimiento_periodo.
    """
    import re as _re
    fecha_inicio = request.args.get("fecha_inicio", "2025-01-01")
    fecha_fin    = request.args.get("fecha_fin",    "2099-12-31")

    patron = _re.compile(r"^\d{4}-\d{2}-\d{2}$")
    if not patron.match(fecha_inicio) or not patron.match(fecha_fin):
        return jsonify(ok=False, mensaje="Formato de fecha invalido. Use YYYY-MM-DD."), 400

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("BEGIN")
                cur.execute(
                    "CALL sp_reporte_carga_biomedica(%s,%s::TIMESTAMP,%s::TIMESTAMP,'cur_carga_adm')",
                    (
                        session["id_usuario"],
                        fecha_inicio + " 00:00:00",
                        fecha_fin    + " 23:59:59",
                    )
                )
                cur.execute('FETCH ALL FROM "cur_carga_adm"')
                datos = to_dicts(cur.fetchall())
                cur.execute("CLOSE cur_carga_adm")
                cur.execute("COMMIT")
        return jsonify(ok=True, data=datos,
                       periodo={"desde": fecha_inicio, "hasta": fecha_fin})
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500



# FASE 3C ? sp_historial_equipo: historial unificado por equipo

@app.route("/equipo/<int:id_equipo>/historial")
@login_required
@role_required("admin", "biomedico", "medico", "responsable", "enfermero")
def equipo_historial(id_equipo):
    """
    Consume sp_historial_equipo(p_id_usuario, p_id_equipo, p_resultado).
    Devuelve un UNION ALL de Movimientos + Mantenimientos + Usos Clinicos
    ordenados cronologicamente DESC.
    Responde en JSON para cargarse en un modal de detalle sin recargar.
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("BEGIN")
                cur.execute(
                    "CALL sp_historial_equipo(%s,%s,'cur_hist')",
                    (session["id_usuario"], id_equipo)
                )
                cur.execute('FETCH ALL FROM "cur_hist"')
                historial = to_dicts(cur.fetchall())
                cur.execute("CLOSE cur_hist")
                cur.execute("COMMIT")

                cur.execute("""
                    SELECT e.codigo_interno, e.nombre_equipo,
                           ee.estado_equipo,
                           ma.nombre_marca  AS marca,
                           me.nombre_modelo AS modelo
                    FROM equipo e
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    JOIN modelo_equipo  me ON me.id_modelo        = e.id_modelo
                    JOIN marca_equipo   ma ON ma.id_marca         = me.id_marca
                    WHERE e.id_equipo = %s
                """, (id_equipo,))
                equipo_info = cur.fetchone()

        return jsonify(
            ok=True,
            equipo=dict(equipo_info) if equipo_info else {},
            historial=historial,
            total=len(historial),
        )
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500



# CRUD ADMIN — Rutas del panel maestro (admin_master.html)
# Estas rutas unifican los alias que usa el template consolidado.
# Las operaciones reales ya existen; aquí se exponen con las URLs
# que url_for() necesita para generar los href de los formularios.


# ── Equipo: crear ──────────────────────────────────────────────────
@app.route("/admin/equipo/crear", methods=["POST"])
@login_required
@role_required("admin")
def admin_crear_equipo():
    """
    Alias de admin_nuevo_equipo.
    Llama a sp_registrar_equipo(
        p_id_usuario, p_codigo_interno, p_nombre_equipo, p_id_modelo,
        p_numero_serie, p_id_tipo_equipo, p_id_criticidad,
        p_id_ubicacion, p_codigo_uid_nfc  [OUT p_id_equipo]
    ).
    El formulario del modal envía los campos con nombres simplificados;
    se resuelven aquí con defaults seguros para campos opcionales.
    """
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                num_serie = f.get("numero_serie", "").strip() or None
                cod_nfc   = f.get("codigo_uid_nfc", "").strip().upper() or None
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_registrar_equipo(%s,%s,%s,%s,%s,%s,%s,%s,%s,NULL,%s)",
                    (
                        session["id_usuario"],
                        f.get("codigo_interno", "").strip(),
                        f.get("nombre_equipo", "").strip(),
                        int(f["id_modelo"]),
                        num_serie,
                        int(f["id_tipo_equipo"]),
                        int(f["id_criticidad_equipo"]),
                        int(f["id_ubicacion"]),
                        cod_nfc,
                        "web_admin",
                    )
                )
            c.commit()
        flash("Equipo registrado correctamente.", "success")
    except Exception as e:
        flash(f"Error al registrar equipo: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")


# ── Equipo: editar ─────────────────────────────────────────────────
@app.route("/admin/equipo/editar/<int:id>", methods=["POST"])
@login_required
@role_required("admin")
def admin_editar_equipo_master(id):
    """
    Alias de admin_editar_equipo para el template admin_master.html.
    Actualiza nombre, estado y modelo de un equipo existente.
    Resuelve id_estado_equipo desde el texto si no se envía el ID.
    """
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                # Resolver id_estado desde texto del select si no viene el ID
                id_estado = f.get("id_estado_equipo", "").strip()
                if not id_estado:
                    nombre_est = f.get("estado_equipo", "Disponible")
                    cur.execute(
                        "SELECT id_estado_equipo FROM estado_equipos "
                        "WHERE estado_equipo = %s LIMIT 1",
                        (nombre_est,)
                    )
                    row = cur.fetchone()
                    id_estado = row["id_estado_equipo"] if row else 1

                # Recuperar valores actuales del equipo para no romper FKs
                cur.execute("""
                    SELECT id_modelo, numero_serie, id_tipo_equipo,
                           id_criticidad_equipo,
                           id_ubicacion_administrativa_actual
                    FROM equipo WHERE id_equipo = %s
                """, (id,))
                eq = cur.fetchone()
                if not eq:
                    flash("Equipo no encontrado.", "error")
                    return redirect(url_for("admin_v") + "#v-equipos")

                set_audit_context(cur, "web_admin")
                cur.execute("""
                    UPDATE equipo
                    SET nombre_equipo                       = %s,
                        id_modelo                          = %s,
                        numero_serie                       = %s,
                        id_tipo_equipo                     = %s,
                        id_criticidad_equipo               = %s,
                        id_estado_equipo                   = %s,
                        id_ubicacion_administrativa_actual = %s
                    WHERE id_equipo = %s
                """, (
                    f.get("nombre_equipo", eq["nombre_equipo"] if "nombre_equipo" in eq else ""),
                    int(f.get("id_modelo", eq["id_modelo"])),
                    f.get("numero_serie", eq["numero_serie"] or ""),
                    int(f.get("id_tipo_equipo", eq["id_tipo_equipo"])),
                    int(f.get("id_criticidad_equipo", eq["id_criticidad_equipo"])),
                    int(id_estado),
                    int(f.get("id_ubicacion", eq["id_ubicacion_administrativa_actual"])),
                    id,
                ))
            c.commit()
        flash("Equipo actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al actualizar equipo: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")


# ── Asignación: crear ──────────────────────────────────────────────
@app.route("/admin/asignacion/crear", methods=["POST"])
@login_required
@role_required("admin")
def admin_crear_asignacion():
    """
    Llama a sp_asignar_equipo(
        p_id_usuario, p_id_equipo, p_id_persona_responsable,
        p_id_ubicacion  [OUT p_id_asignacion], p_observacion
    ).
    El modal envía id_usuario (del select de usuarios); se resuelve
    su id_persona para cumplir la firma del SP.
    Si no se envía id_ubicacion se usa la ubicación actual del equipo.
    """
    f = request.form
    try:
        id_equipo  = int(f["id_equipo"])
        id_usuario = int(f["id_usuario"])

        with get_db() as c:
            with c.cursor() as cur:
                # Resolver id_persona desde id_usuario
                cur.execute(
                    "SELECT id_persona FROM usuario WHERE id_usuario = %s",
                    (id_usuario,)
                )
                row = cur.fetchone()
                if not row:
                    flash("Usuario no encontrado.", "error")
                    return redirect(url_for("admin_v") + "#v-asig")
                id_persona = row["id_persona"]

                # Resolver id_ubicacion: usar el enviado o la ubicación actual del equipo
                id_ubic = f.get("id_ubicacion", "").strip()
                if not id_ubic:
                    cur.execute(
                        "SELECT id_ubicacion_administrativa_actual FROM equipo "
                        "WHERE id_equipo = %s",
                        (id_equipo,)
                    )
                    eq = cur.fetchone()
                    id_ubic = eq["id_ubicacion_administrativa_actual"] if eq else 1

                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_asignar_equipo(%s,%s,%s,%s,NULL,%s,%s)",
                    (
                        session["id_usuario"],
                        id_equipo,
                        int(id_persona),
                        int(id_ubic),
                        f.get("observacion", "Asignación desde panel admin"),
                        "web_admin",
                    )
                )
            c.commit()
        flash("Equipo asignado correctamente.", "success")
    except Exception as e:
        flash(f"Error al asignar equipo: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-asig")


# ── Asignación: liberar ────────────────────────────────────────────
@app.route("/admin/asignacion/liberar/<int:id>", methods=["POST"])
@login_required
@role_required("admin")
def admin_liberar_asig(id):
    """
    Alias de admin_cerrar_asignacion para el template admin_master.html.
    Llama a sp_cerrar_asignacion_equipo(
        p_id_usuario, p_id_asignacion  [OUT p_mensaje], p_observacion
    ).
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_cerrar_asignacion_equipo(%s,%s,NULL,%s,%s)",
                    (
                        session["id_usuario"],
                        id,
                        request.form.get("observacion", "Liberación desde panel admin"),
                        "web_admin",
                    )
                )
            c.commit()
        flash("Asignación liberada correctamente.", "success")
    except Exception as e:
        flash(f"Error al liberar asignación: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-asig")


# ── Traslado: crear ────────────────────────────────────────────────
@app.route("/admin/traslado/crear", methods=["POST"])
@login_required
@role_required("admin")
def admin_crear_traslado():
    """
    Llama a sp_registrar_traslado_externo(
        p_id_usuario, p_id_equipo, p_id_nfc_equipo, p_id_ambulancia,
        p_id_persona_conductor, p_id_tipo_traslado
        [OUT p_id_traslado], p_motivo, p_observacion
    ).
    El modal simplificado envía: id_equipo, codigo_ambulancia, conductor
    (nombre), tipo_traslado (texto) y motivo_traslado.
    Este handler resuelve los IDs reales mediante consultas a catálogos.
    """
    f = request.form
    try:
        id_equipo = int(f["id_equipo"])

        with get_db() as c:
            with c.cursor() as cur:

                # ── Resolver id_nfc_equipo: el primero activo del equipo ─────
                cur.execute(
                    "SELECT id_nfc FROM dispositivo_nfc "
                    "WHERE id_equipo = %s AND activo_nfc = TRUE LIMIT 1",
                    (id_equipo,)
                )
                nfc_row = cur.fetchone()
                id_nfc = nfc_row["id_nfc"] if nfc_row else None

                # Resolver id_ambulancia desde codigo_ambulancia
                codigo_amb = f.get("codigo_ambulancia", "").strip()
                cur.execute(
                    "SELECT id_ambulancia FROM ambulancia "
                    "WHERE codigo_ambulancia = %s AND activo_ambulancia = TRUE LIMIT 1",
                    (codigo_amb,)
                )
                amb_row = cur.fetchone()
                if not amb_row:
                    flash(f"Ambulancia '{codigo_amb}' no encontrada o inactiva.", "error")
                    return redirect(url_for("admin_v") + "#v-traslados")
                id_ambulancia = amb_row["id_ambulancia"]

                # Resolver id_persona_conductor desde nombre
                nombre_conductor = f.get("conductor", "").strip()
                cur.execute("""
                    SELECT p.id_persona
                    FROM persona p
                    JOIN usuario u ON u.id_persona = p.id_persona
                    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
                    JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
                    WHERE r.rol_usuario = 'Conductor'
                      AND u.activo_usuario = TRUE
                      AND (
                          p.nombre_persona || ' ' || p.apellido_persona ILIKE %s
                          OR p.nombre_persona ILIKE %s
                      )
                    LIMIT 1
                """, (f"%{nombre_conductor}%", f"%{nombre_conductor}%"))
                cond_row = cur.fetchone()
                if not cond_row:
                    flash(f"Conductor '{nombre_conductor}' no encontrado o sin rol activo.", "error")
                    return redirect(url_for("admin_v") + "#v-traslados")
                id_conductor = cond_row["id_persona"]

                # Resolver id_tipo_traslado desde texto
                tipo_txt = f.get("tipo_traslado", "Préstamo temporal").strip()
                cur.execute(
                    "SELECT id_tipo_traslado FROM tipo_traslado_externo "
                    "WHERE tipo_traslado = %s LIMIT 1",
                    (tipo_txt,)
                )
                tipo_row = cur.fetchone()
                if not tipo_row:
                    cur.execute(
                        "SELECT id_tipo_traslado FROM tipo_traslado_externo "
                        "WHERE tipo_traslado = 'Préstamo temporal' LIMIT 1"
                    )
                    tipo_row = cur.fetchone()
                if not tipo_row:
                    flash("No se encontró el tipo de traslado 'Préstamo temporal' en la base de datos.", "error")
                    return redirect(url_for("admin_v") + "#v-traslados")
                id_tipo = tipo_row["id_tipo_traslado"]

                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_registrar_traslado_externo(%s,%s,%s,%s,%s,%s,NULL,%s,%s,%s)",
                    (
                        session["id_usuario"],
                        id_equipo,
                        id_nfc,        # puede ser None; el SP acepta NULL
                        id_ambulancia,
                        id_conductor,
                        id_tipo,
                        f.get("motivo_traslado", "").strip(),
                        f.get("observacion", "").strip(),
                        "web_admin",
                    )
                )
            c.commit()
        flash("Traslado externo registrado correctamente.", "success")
    except Exception as e:
        flash(f"Error al registrar traslado: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-traslados")


# Usuario: toggle activo/inactivo (alias para template)
# admin_toggle_usuario ya existe con la URL /admin/usuario/<id>/toggle
# El template usa url_for("admin_toggle_usuario", id=u.id_usuario)
# que coincide exactamente con la función existente — sin cambios.


# API JSON: autocompletar conductores para el modal de traslado
@app.route("/admin/api/conductores")
@login_required
@role_required("admin")
def admin_api_conductores():
    """
    Devuelve lista de conductores activos para autocompletar en el modal.
    Response: [{id_persona, nombre_completo, username}, ...]
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT p.id_persona,
                           p.nombre_persona || ' ' || p.apellido_persona AS nombre_completo,
                           u.username
                    FROM persona p
                    JOIN usuario u ON u.id_persona = p.id_persona
                    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
                    JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
                    WHERE r.rol_usuario = 'Conductor'
                      AND u.activo_usuario = TRUE
                    ORDER BY p.apellido_persona
                """)
                rows = to_dicts(cur.fetchall())
        return jsonify(ok=True, data=rows)
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


# API JSON: ambulancias activas para el modal de traslado
@app.route("/admin/api/ambulancias")
@login_required
@role_required("admin")
def admin_api_ambulancias():
    """
    Devuelve ambulancias activas para el modal de nuevo traslado.
    Response: [{id_ambulancia, codigo_ambulancia, placa, estado_ambulancia}, ...]
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT a.id_ambulancia, a.codigo_ambulancia, a.placa,
                           ea.estado_ambulancia
                    FROM ambulancia a
                    JOIN estado_ambulancias ea
                            ON ea.id_estado_ambulancia = a.id_estado_ambulancia
                    WHERE a.activo_ambulancia = TRUE
                    ORDER BY a.codigo_ambulancia
                """)
                rows = to_dicts(cur.fetchall())
        return jsonify(ok=True, data=rows)
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


# API JSON: catálogos para el modal de nuevo equipo
@app.route("/admin/api/catalogos/equipo")
@login_required
@role_required("admin")
def admin_api_catalogos_equipo():
    """
    Devuelve los catálogos necesarios para el formulario de nuevo equipo
    (tipos, modelos, estados, ubicaciones, criticidades) en un solo request.
    Evita recargar la página completa para abrir el modal.
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("SELECT id_tipo_equipo, tipo_equipo FROM tipo_equipos ORDER BY tipo_equipo")
                tipos = to_dicts(cur.fetchall())

                cur.execute("""
                    SELECT me.id_modelo,
                           me.nombre_modelo,
                           ma.nombre_marca
                    FROM modelo_equipo me
                    JOIN marca_equipo ma ON ma.id_marca = me.id_marca
                    ORDER BY ma.nombre_marca, me.nombre_modelo
                """)
                modelos = to_dicts(cur.fetchall())

                cur.execute("SELECT id_estado_equipo, estado_equipo FROM estado_equipos ORDER BY estado_equipo")
                estados = to_dicts(cur.fetchall())

                cur.execute("SELECT id_ubicacion, nombre_ubicacion FROM ubicacion_especifica ORDER BY nombre_ubicacion")
                ubicaciones = to_dicts(cur.fetchall())

                cur.execute("SELECT id_criticidad_equipo, criticidad_equipo FROM criticidad_equipos ORDER BY criticidad_equipo")
                criticidades = to_dicts(cur.fetchall())

        return jsonify(ok=True, tipos=tipos, modelos=modelos,
                       estados=estados, ubicaciones=ubicaciones,
                       criticidades=criticidades)
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


# API JSON: personas para el modal de asignación
@app.route("/admin/api/personas")
@login_required
@role_required("admin")
def admin_api_personas():
    """
    Devuelve usuarios con persona asociada para el select de responsable
    en el modal de nueva asignación.
    Excluye conductores (sin uso clínico de equipos).
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT u.id_usuario,
                           p.id_persona,
                           p.nombre_persona || ' ' || p.apellido_persona AS nombre_completo,
                           u.username,
                           r.rol_usuario
                    FROM usuario u
                    JOIN persona p ON p.id_persona = u.id_persona
                    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
                    JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
                    WHERE u.activo_usuario = TRUE
                      AND r.rol_usuario != 'Conductor'
                    ORDER BY r.rol_usuario, p.apellido_persona
                """)
                rows = to_dicts(cur.fetchall())
        return jsonify(ok=True, data=rows)
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500


# CRUD ADMIN — Alias de rutas con parámetro 'id' para admin.html
# Las funciones de negocio ya existen; estas rutas adicionales
# registran endpoints con el nombre/parámetro que usa url_for() en
# el template consolidado.

# Equipo: eliminar con parámetro 'id'
@app.route("/admin/equipo/eliminar/<int:id>", methods=["POST"])
@login_required
@role_required("admin")
def admin_eliminar_equipo_alias(id):
    """
    Alias de admin_eliminar_equipo para admin_master.html.
    Parámetro 'id' en lugar de 'id_equipo'.
    Baja lógica: activo_equipo = FALSE.
    Bloquea si hay asignaciones activas abiertas.
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT COUNT(*) AS n FROM asignacion_equipo
                    WHERE id_equipo = %s AND fecha_fin_asignacion IS NULL
                """, (id,))
                if cur.fetchone()["n"] > 0:
                    flash("No se puede eliminar: el equipo tiene asignaciones activas.", "error")
                    return redirect(url_for("admin_v") + "#v-equipos")
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "UPDATE equipo SET activo_equipo = FALSE WHERE id_equipo = %s",
                    (id,)
                )
            c.commit()
        flash("Equipo dado de baja correctamente.", "success")
    except Exception as e:
        flash(f"Error al eliminar equipo: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")


@app.route("/admin/equipo/reactivar/<int:id>", methods=["POST"])
@login_required
@role_required("admin")
def admin_reactivar_equipo(id):
    """Reactiva un equipo dado de baja (activo_equipo = TRUE)."""
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "UPDATE equipo SET activo_equipo = TRUE, id_estado_equipo = "
                    "(SELECT id_estado_equipo FROM estado_equipos WHERE estado_equipo = 'Disponible' LIMIT 1) "
                    "WHERE id_equipo = %s",
                    (id,)
                )
            c.commit()
        flash("Equipo reactivado correctamente.", "success")
    except Exception as e:
        flash(f"Error al reactivar equipo: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")


# Usuario: toggle activo con parámetro 'id'
@app.route("/admin/usuario/toggle/<int:id>", methods=["POST"])
@login_required
@role_required("admin")
def admin_toggle_usuario_alias(id):
    """
    Alias de admin_toggle_usuario para admin_master.html.
    Parámetro 'id' en lugar de 'id_usuario_target'.
    Llama a sp_cambiar_estado_usuario e invierte el estado actual.
    """
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "SELECT activo_usuario FROM usuario WHERE id_usuario = %s",
                    (id,)
                )
                row = cur.fetchone()
                if not row:
                    flash("Usuario no encontrado.", "error")
                    return redirect(url_for("admin_v") + "#v-usuarios")
                nuevo_estado = not row["activo_usuario"]
                set_audit_context(cur, "web_admin")
                cur.execute(
                    "CALL sp_cambiar_estado_usuario(%s,%s,%s,NULL,%s)",
                    (session["id_usuario"], id, nuevo_estado, "web_admin")
                )
            c.commit()
        accion = "activado" if nuevo_estado else "desactivado"
        flash(f"Usuario {accion} correctamente.", "success")
    except Exception as e:
        flash(f"Error: {friendly_db_error(e)}", "error")
    return redirect(url_for("admin_v") + "#v-usuarios")


# ── Beacon heartbeat (llamado por beacon_scanner.py cada ~10 s) ────────────
@app.route("/api/beacon/heartbeat", methods=["POST"])
def api_beacon_heartbeat():
    data = request.get_json(silent=True) or {}
    if data.get("token") != BEACON_SCRIPT_TOKEN:
        return jsonify(ok=False, mensaje="Token inválido"), 401

    uuid_beacon = (data.get("uuid_beacon") or "").strip().upper()
    major       = data.get("major", 0)
    minor       = data.get("minor", 0)
    activo      = bool(data.get("activo", False))
    rssi        = data.get("rssi")

    id_beacon = None
    zona      = None

    if activo and uuid_beacon:
        try:
            with get_db() as c:
                with c.cursor() as cur:
                    cur.execute("""
                        SELECT db.id_beacon, zb.nombre_zona_beacon
                        FROM dispositivo_beacon db
                        JOIN zona_beacon zb ON zb.id_zona_beacon = db.id_zona_beacon
                        WHERE db.uuid_beacon = %s
                          AND db.major_beacon = %s
                          AND db.minor_beacon = %s
                          AND db.activo_beacon = TRUE
                    """, (uuid_beacon, int(major), int(minor)))
                    row = cur.fetchone()
                    if row:
                        id_beacon = row["id_beacon"]
                        zona      = row["nombre_zona_beacon"]
        except Exception:
            pass

    with _beacon_lock:
        _beacon_state["activo"]    = activo and (id_beacon is not None)
        _beacon_state["id_beacon"] = id_beacon
        _beacon_state["zona"]      = zona
        _beacon_state["rssi"]      = rssi
        _beacon_state["ts"]        = datetime.datetime.now()

    return jsonify(ok=True)


# ── Estado del beacon (consultado por la página /nfc-scan) ──────────────────
@app.route("/api/beacon/estado")
@login_required
def api_beacon_estado():
    with _beacon_lock:
        state = dict(_beacon_state)

    segundos_ago = None
    activo = state["activo"]
    if state["ts"]:
        segundos_ago = int((datetime.datetime.now() - state["ts"]).total_seconds())
        if segundos_ago > 30:
            activo = False

    return jsonify(
        activo       = activo,
        zona         = state["zona"],
        rssi         = state["rssi"],
        segundos_ago = segundos_ago,
    )


# ── Receptor GPS OsmAnd (Traccar Client) ────────────────────────────────────
@app.route("/api/gps/osmand", methods=["GET", "POST"])
def api_gps_osmand():
    """
    Traccar Client (protocolo OsmAnd) envía:
      GET /api/gps/osmand?id=GPS-AMB-001&lat=25.6&lon=-100.3&accuracy=8&timestamp=1234567890
    """
    # Intenta leer de query string (OsmAnd clásico o JSON con ?id=)
    codigo = (request.args.get("id") or request.form.get("id") or "").strip()
    lat = request.args.get("lat")
    lon = request.args.get("lon")
    acc = request.args.get("accuracy")

    # Si no vienen en query string, intenta JSON body (Traccar iOS)
    if not lat or not lon:
        try:
            body = request.get_json(force=True, silent=True) or {}
            coords = body.get("location", {}).get("coords", {})
            lat = coords.get("latitude")
            lon = coords.get("longitude")
            acc = coords.get("accuracy")
        except Exception:
            pass

    if not codigo or lat is None or lon is None:
        return ("", 400)

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "SELECT id_gps FROM dispositivo_gps "
                    "WHERE codigo_gps = %s AND activo_gps = TRUE",
                    (codigo,)
                )
                row = cur.fetchone()
                if not row:
                    return ("", 404)

                cur.execute(
                    """
                    INSERT INTO evento_gps
                        (id_gps, fecha_hora_evento, latitud, longitud, precision)
                    VALUES (%s, NOW(), %s, %s, %s)
                    """,
                    (row["id_gps"], float(lat), float(lon),
                     float(acc) if acc is not None else None)
                )
            c.commit()
        return ("", 200)
    except Exception as e:
        print("GPS ERROR:", e)
        return ("", 500)


@app.route("/api/traslado/cerrar/<int:id_traslado>", methods=["POST"])
@login_required
@role_required("administrador")
def api_cerrar_traslado(id_traslado):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("CALL sp_cerrar_traslado(%s)", (id_traslado,))
            c.commit()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


# ── Login dedicado para flujo NFC ───────────────────────────────────────────
@app.route("/nfc-login", methods=["GET", "POST"])
def nfc_login_page():
    if request.method == "GET":
        if "id_usuario" in session:
            return redirect(url_for("nfc_scan_page"))
        return render_template("nfc_login.html", error=None)

    username = (request.form.get("username") or "").strip()
    password = (request.form.get("password") or "").strip()
    if not username or not password:
        return render_template("nfc_login.html", error="Ingresa usuario y contraseña.")

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT u.id_usuario, u.id_persona, u.contrasenia,
                           p.nombre_persona, p.apellido_persona
                    FROM usuario u
                    JOIN persona p ON p.id_persona = u.id_persona
                    WHERE u.username = %s AND u.activo_usuario = TRUE
                """, (username,))
                user = cur.fetchone()
        if not user or user["contrasenia"] != password:
            return render_template("nfc_login.html", error="Credenciales incorrectas.")
        session["id_usuario"]      = user["id_usuario"]
        session["id_persona"]      = user["id_persona"]
        session["nombre"]          = user["nombre_persona"]
        session["nombre_completo"] = user["nombre_persona"] + " " + user["apellido_persona"]
        return redirect(url_for("nfc_scan_page"))
    except Exception as e:
        return render_template("nfc_login.html", error=str(e))


# ── Página NFC para celular ──────────────────────────────────────────────────
@app.route("/nfc-scan")
@login_required
def nfc_scan_page():
    return render_template("nfc_scan.html")


# ── Escaneo NFC desde web: crea evento_nfc + evento_beacon ──────────────────
@app.route("/api/nfc/movil", methods=["POST"])
@login_required
def api_nfc_movil():
    data    = request.get_json(silent=True) or {}
    uid_nfc = (data.get("uid_nfc") or "").strip().upper()

    if not uid_nfc:
        return jsonify(ok=False, mensaje="UID NFC requerido"), 400

    with _beacon_lock:
        beacon_activo = _beacon_state["activo"]
        id_beacon     = _beacon_state["id_beacon"]
        zona          = _beacon_state["zona"]
        beacon_ts     = _beacon_state["ts"]

    if beacon_ts and (datetime.datetime.now() - beacon_ts).total_seconds() > 30:
        beacon_activo = False

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT dn.id_nfc, dn.id_equipo,
                           e.nombre_equipo, e.codigo_interno,
                           ee.estado_equipo
                    FROM dispositivo_nfc dn
                    JOIN equipo e ON e.id_equipo = dn.id_equipo
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    WHERE dn.codigo_uid_nfc = %s AND dn.activo_nfc = TRUE
                """, (uid_nfc,))
                tag = cur.fetchone()
                if not tag:
                    return jsonify(ok=False, mensaje="Tag NFC no reconocido o inactivo"), 404

                cur.execute("""
                    INSERT INTO evento_nfc (id_nfc, id_tipo_evento_nfc, fecha_hora_evento)
                    VALUES (%s, 1, NOW()) RETURNING id_evento_nfc
                """, (tag["id_nfc"],))
                id_evento_nfc = cur.fetchone()["id_evento_nfc"]

                id_evento_beacon = None
                if beacon_activo and id_beacon:
                    cur.execute("""
                        INSERT INTO evento_beacon
                            (id_beacon, id_equipo, fecha_hora_evento, id_tipo_evento_beacon)
                        VALUES (%s, %s, NOW(), 1)
                        RETURNING id_evento_beacon
                    """, (id_beacon, tag["id_equipo"]))
                    id_evento_beacon = cur.fetchone()["id_evento_beacon"]

                cur.execute("""
                    SELECT uce.id_uso_clinico, tp.tipo_procedimiento,
                           uce.fecha_hora_inicio
                    FROM uso_clinico_equipo uce
                    JOIN tipo_procedimiento tp
                            ON tp.id_tipo_procedimiento = uce.id_tipo_procedimiento
                    WHERE uce.id_equipo = %s
                      AND uce.id_persona_responsable_uso = %s
                      AND uce.fecha_hora_fin IS NULL
                    ORDER BY uce.fecha_hora_inicio DESC
                    LIMIT 1
                """, (tag["id_equipo"], session["id_persona"]))
                uso_activo = cur.fetchone()

                cur.execute("""
                    SELECT id_tipo_procedimiento, tipo_procedimiento
                    FROM tipo_procedimiento ORDER BY tipo_procedimiento
                """)
                tipos_proc = to_dicts(cur.fetchall())

            c.commit()

        uso_activo_dict = None
        if uso_activo:
            uso_activo_dict = dict(uso_activo)
            if uso_activo_dict.get("fecha_hora_inicio"):
                uso_activo_dict["fecha_hora_inicio"] = uso_activo_dict["fecha_hora_inicio"].strftime("%d/%m %H:%M")

        return jsonify(
            ok=True,
            equipo=dict(tag),
            zona=zona,
            beacon_activo=beacon_activo,
            id_evento_nfc=id_evento_nfc,
            id_evento_beacon=id_evento_beacon,
            uso_activo=uso_activo_dict,
            tipos_proc=tipos_proc,
        )
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500


@app.route("/api/movil/uso/registrar", methods=["POST"])
@login_required
def api_movil_uso_registrar():
    data    = request.get_json(silent=True) or {}
    id_eq   = data.get("id_equipo")
    id_proc = data.get("id_tipo_procedimiento")
    if not id_eq or not id_proc:
        return jsonify(ok=False, mensaje="Faltan datos"), 400
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT ue.id_area FROM equipo e
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion_administrativa_actual
                    WHERE e.id_equipo = %s
                """, (int(id_eq),))
                a = cur.fetchone()
                id_area = a["id_area"] if a else 1

                cur.execute("""
                    SELECT id_turno FROM enfermero WHERE id_persona = %s
                    UNION
                    SELECT id_turno FROM medico WHERE id_persona = %s
                    LIMIT 1
                """, (session["id_persona"], session["id_persona"]))
                t = cur.fetchone()
                id_turno = t["id_turno"] if t else 1

                set_audit_context(cur, "web_movil")
                cur.execute(
                    "CALL sp_registrar_uso_clinico(%s,%s,%s,%s,%s,%s,NULL,%s,%s)",
                    (session["id_usuario"], int(id_eq), session["id_persona"],
                     id_area, id_turno, int(id_proc), None, "web_movil")
                )
            c.commit()
        return jsonify(ok=True, mensaje="Uso clínico registrado correctamente")
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500


@app.route("/api/movil/uso/cerrar", methods=["POST"])
@login_required
def api_movil_uso_cerrar():
    data   = request.get_json(silent=True) or {}
    id_uso = data.get("id_uso_clinico")
    if not id_uso:
        return jsonify(ok=False, mensaje="ID de uso requerido"), 400
    try:
        with get_db() as c:
            with c.cursor() as cur:
                set_audit_context(cur, "web_movil")
                cur.execute("CALL sp_cerrar_uso_clinico(%s,%s,NULL,%s)",
                    (session["id_usuario"], int(id_uso), "web_movil"))
            c.commit()
        return jsonify(ok=True, mensaje="Uso clínico cerrado correctamente")
    except Exception as e:
        return jsonify(ok=False, mensaje=friendly_db_error(e)), 500


if __name__ == "__main__":
    app.run(debug=True, port=5000)
