# =============================================================================
#  HospitalIoT — Consultas e inserciones MongoDB
#  Equipo 7 — Bases de Datos Avanzadas
#
#  Este archivo documenta todas las operaciones que el sistema realiza
#  sobre la base de datos hospital_mongo:
#    1. Conexión desde Flask
#    2. Inserciones en tiempo real (eventos IoT)
#    3. Pipelines de agregación para reportes y dashboards
# =============================================================================

from pymongo import MongoClient
import datetime

# =============================================================================
# 1. CONEXIÓN DESDE FLASK
# =============================================================================
# Se utiliza un cliente singleton para reutilizar la conexión entre peticiones.
# La URI incluye usuario, contraseña, host y base de datos.

MONGO_URI = "mongodb://hospital_mongo_user:AIR795@localhost:27017/hospital_mongo"
MONGO_DB  = "hospital_mongo"

_mongo_client = None

def get_mongo_db():
    global _mongo_client
    if _mongo_client is None:
        _mongo_client = MongoClient(MONGO_URI)
    return _mongo_client[MONGO_DB]

# Uso en Flask:
#   mg = get_mongo_db()
#   resultados = mg.equipo.find({...})


# =============================================================================
# 2. INSERCIONES EN TIEMPO REAL — event_logs
# =============================================================================
# Cada vez que un dispositivo IoT envía un evento, Flask lo persiste
# simultáneamente en PostgreSQL (trazabilidad transaccional) y en MongoDB
# (disponibilidad analítica en tiempo real).
# Si MongoDB falla, el bloque try/except evita interrumpir el flujo principal.

# --- 2a. Evento NFC ---
# Se dispara cuando la APK Flutter escanea una etiqueta NFC de un equipo.
def insertar_evento_nfc(mg, id_nfc, uid_nfc, id_equipo):
    try:
        mg.event_logs.insert_one({
            "tipo":      "nfc",
            "id_nfc":    id_nfc,
            "uid_nfc":   uid_nfc,
            "id_equipo": id_equipo,
            "timestamp": datetime.datetime.now(),
        })
    except Exception:
        pass

# --- 2b. Evento GPS ---
# Se dispara cuando Traccar Client (ambulancia AMB-001) transmite su posición.
def insertar_evento_gps(mg, codigo, id_gps, lat, lon, precision):
    try:
        mg.event_logs.insert_one({
            "tipo":      "gps",
            "codigo":    codigo,
            "id_gps":    id_gps,
            "latitud":   float(lat),
            "longitud":  float(lon),
            "precision": float(precision) if precision is not None else None,
            "timestamp": datetime.datetime.now(),
        })
    except Exception:
        pass

# --- 2c. Evento Beacon ---
# Se dispara cuando beacon_scanner.py detecta un beacon BLE activo.
def insertar_evento_beacon(mg, id_beacon, zona, rssi):
    try:
        mg.event_logs.insert_one({
            "tipo":      "beacon",
            "id_beacon": id_beacon,
            "zona":      zona,
            "rssi":      rssi,
            "timestamp": datetime.datetime.now(),
        })
    except Exception:
        pass


# =============================================================================
# 3. PIPELINES DE AGREGACIÓN — Reportes y dashboards
# =============================================================================

# --- 3a. Estados del inventario global ---
# Colección: equipo + lookup a estado_equipos
# Uso: Dashboard Administrador — gráfica de dona (indicador dinámico)
# Resultado: [{ "estado_equipo": "Disponible", "total": 12 }, ...]
def mg_rpt_estados(mg):
    pipeline = [
        {"$match": {"activo_equipo": True}},
        {"$lookup": {
            "from": "estado_equipos",
            "localField": "id_estado_equipo",
            "foreignField": "id_estado_equipo",
            "as": "estado"
        }},
        {"$unwind": "$estado"},
        {"$group": {"_id": "$estado.estado_equipo", "total": {"$sum": 1}}},
        {"$project": {"estado_equipo": "$_id", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.equipo.aggregate(pipeline))


# --- 3b. Top equipos más movidos ---
# Colección: movimiento + lookup a equipo
# Uso: Dashboard Administrador — gráfica de barras verticales
# Resultado: [{ "nombre_equipo": "...", "codigo_interno": "...", "total_movimientos": 8 }, ...]
def mg_rpt_mas_movidos(mg):
    from_date = datetime.datetime(2025, 1, 1)
    pipeline = [
        {"$match": {"fecha_hora_movimiento": {"$gte": from_date}}},
        {"$group": {"_id": "$id_equipo", "total_movimientos": {"$sum": 1}}},
        {"$lookup": {
            "from": "equipo",
            "localField": "_id",
            "foreignField": "id_equipo",
            "as": "eq"
        }},
        {"$unwind": "$eq"},
        {"$project": {
            "nombre_equipo": "$eq.nombre_equipo",
            "codigo_interno": "$eq.codigo_interno",
            "total_movimientos": 1,
            "_id": 0
        }},
        {"$sort": {"total_movimientos": -1}},
        {"$limit": 20},
    ]
    return list(mg.movimiento.aggregate(pipeline))


# --- 3c. Carga de trabajo por biomédico ---
# Colección: mantenimiento + lookup a biomedico + lookup a persona
# Uso: Dashboard Administrador — tabla de carga biomédica
# Resultado: [{ "biomedico": "Roberto Ramírez", "total_mantenimientos": 5 }, ...]
def mg_rpt_carga_bio(mg):
    from_date = datetime.datetime(2025, 1, 1)
    pipeline = [
        {"$match": {"fecha_hora_mantenimiento": {"$gte": from_date}}},
        {"$group": {"_id": "$id_biomedico", "total_mantenimientos": {"$sum": 1}}},
        {"$lookup": {
            "from": "biomedico",
            "localField": "_id",
            "foreignField": "id_biomedico",
            "as": "bio"
        }},
        {"$unwind": "$bio"},
        {"$lookup": {
            "from": "persona",
            "localField": "bio.id_persona",
            "foreignField": "id_persona",
            "as": "pers"
        }},
        {"$unwind": "$pers"},
        {"$project": {
            "biomedico": {"$concat": ["$pers.nombre_persona", " ", "$pers.apellido_persona"]},
            "total_mantenimientos": 1,
            "_id": 0
        }},
        {"$sort": {"total_mantenimientos": -1}},
    ]
    return list(mg.mantenimiento.aggregate(pipeline))


# --- 3d. Comparativa uso clínico vs mantenimientos por equipo ---
# Colecciones: equipo, uso_clinico_equipo, mantenimiento (find simple, sin aggregate)
# Uso: Dashboard Administrador — tabla comparativa
# Resultado: [{ "codigo_interno": "EQ-001", "nombre_equipo": "...", "total_usos": 3, "total_mants": 2 }, ...]
def mg_rpt_uso_vs_mant(mg):
    equipos = list(mg.equipo.find(
        {"activo_equipo": True},
        {"_id": 0, "id_equipo": 1, "codigo_interno": 1, "nombre_equipo": 1}
    ))
    uso_counts  = {}
    mant_counts = {}
    for u in mg.uso_clinico_equipo.find({}, {"_id": 0, "id_equipo": 1, "id_uso_clinico": 1}):
        uso_counts.setdefault(u["id_equipo"], set()).add(u["id_uso_clinico"])
    for m in mg.mantenimiento.find({}, {"_id": 0, "id_equipo": 1, "id_mantenimiento": 1}):
        mant_counts.setdefault(m["id_equipo"], set()).add(m["id_mantenimiento"])
    return sorted(
        [{"codigo_interno": e["codigo_interno"],
          "nombre_equipo":  e["nombre_equipo"],
          "total_usos":     len(uso_counts.get(e["id_equipo"], set())),
          "total_mants":    len(mant_counts.get(e["id_equipo"], set()))}
         for e in equipos],
        key=lambda x: x["total_usos"], reverse=True
    )


# --- 3e. Movimientos por área ---
# Colecciones: area_registro, ubicacion_especifica, equipo, movimiento (find simple)
# Uso: Dashboard Administrador — tabla de actividad por área
# Resultado: [{ "area": "Quirófano", "total_movs": 15, "equipos_involucrados": 4 }, ...]
def mg_rpt_movs_area(mg):
    areas      = list(mg.area_registro.find({}, {"_id": 0}))
    ubics      = list(mg.ubicacion_especifica.find({}, {"_id": 0}))
    ubic_map   = {u["id_ubicacion"]: u["id_area"] for u in ubics}
    area_names = {a["id_area"]: a["nombre_area"] for a in areas}
    area_equip = {a["id_area"]: set() for a in areas}
    for e in mg.equipo.find({"activo_equipo": True},
                             {"_id": 0, "id_equipo": 1,
                              "id_ubicacion_administrativa_actual": 1}):
        uid = e.get("id_ubicacion_administrativa_actual")
        if uid and uid in ubic_map:
            area_equip[ubic_map[uid]].add(e["id_equipo"])
    area_movs = {a["id_area"]: 0 for a in areas}
    for m in mg.movimiento.find({}, {"_id": 0, "id_movimiento": 1,
                                     "id_ubicacion_origen": 1,
                                     "id_ubicacion_destino": 1}):
        seen = set()
        for uid in [m.get("id_ubicacion_origen"), m.get("id_ubicacion_destino")]:
            if uid and uid in ubic_map:
                aid = ubic_map[uid]
                key = (aid, m.get("id_movimiento"))
                if key not in seen:
                    area_movs[aid] = area_movs.get(aid, 0) + 1
                    seen.add(key)
    return sorted(
        [{"area": area_names[aid],
          "total_movs": area_movs.get(aid, 0),
          "equipos_involucrados": len(area_equip.get(aid, set()))}
         for aid in area_names],
        key=lambda x: x["total_movs"], reverse=True
    )


# --- 3f. Frecuencia por tipo de movimiento ---
# Colección: movimiento + lookup a tipo_movimientos
# Uso: Dashboard Administrador y Enfermero — gráfica de dona
# Resultado: [{ "tipo_movimiento": "Traslado interno", "total": 20 }, ...]
def mg_rpt_freq_mov(mg):
    pipeline = [
        {"$group": {"_id": "$id_tipo_movimiento", "total": {"$sum": 1}}},
        {"$lookup": {
            "from": "tipo_movimientos",
            "localField": "_id",
            "foreignField": "id_tipo_movimiento",
            "as": "tipo"
        }},
        {"$unwind": "$tipo"},
        {"$project": {"tipo_movimiento": "$tipo.tipo_movimiento", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.movimiento.aggregate(pipeline))


# --- 3g. Mantenimientos por tipo ---
# Colección: mantenimiento + lookup a tipo_mantenimientos
# Uso: Dashboard Biomédico — gráfica de barras verticales
# Resultado: [{ "tipo_mantenimiento": "Preventivo", "total": 10 }, ...]
def mg_rpt_por_tipo_mant(mg):
    pipeline = [
        {"$group": {"_id": "$id_tipo_mantenimiento", "total": {"$sum": 1}}},
        {"$lookup": {
            "from": "tipo_mantenimientos",
            "localField": "_id",
            "foreignField": "id_tipo_mantenimiento",
            "as": "tipo"
        }},
        {"$unwind": "$tipo"},
        {"$project": {"tipo_mantenimiento": "$tipo.tipo_mantenimiento", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.mantenimiento.aggregate(pipeline))


# --- 3h. Resultados de mantenimientos ---
# Colección: mantenimiento + lookup a tipo_resultado_mantenimientos
# Uso: Dashboard Biomédico — gráfica de dona (indicador dinámico)
# Resultado: [{ "resultado_mantenimiento": "Exitoso", "total": 8 }, ...]
def mg_rpt_por_resultado(mg):
    pipeline = [
        {"$group": {"_id": "$id_resultado_mantenimiento", "total": {"$sum": 1}}},
        {"$lookup": {
            "from": "tipo_resultado_mantenimientos",
            "localField": "_id",
            "foreignField": "id_resultado_mantenimiento",
            "as": "res"
        }},
        {"$unwind": "$res"},
        {"$project": {
            "resultado_mantenimiento": "$res.resultado_mantenimiento",
            "total": 1,
            "_id": 0
        }},
        {"$sort": {"total": -1}},
    ]
    return list(mg.mantenimiento.aggregate(pipeline))


# --- 3i. Equipos con más mantenimientos ---
# Colección: mantenimiento + lookup a equipo
# Uso: Dashboard Biomédico — tabla de equipos críticos
# Resultado: [{ "nombre_equipo": "...", "total_mants": 4, "ultimo_mant": datetime }, ...]
def mg_rpt_equipos_mas_mant(mg):
    pipeline = [
        {"$group": {
            "_id": "$id_equipo",
            "total_mants": {"$sum": 1},
            "ultimo_mant": {"$max": "$fecha_hora_mantenimiento"}
        }},
        {"$lookup": {
            "from": "equipo",
            "localField": "_id",
            "foreignField": "id_equipo",
            "as": "eq"
        }},
        {"$unwind": "$eq"},
        {"$project": {
            "nombre_equipo": "$eq.nombre_equipo",
            "total_mants": 1,
            "ultimo_mant": 1,
            "_id": 0
        }},
        {"$sort": {"total_mants": -1}},
        {"$limit": 10},
    ]
    return list(mg.mantenimiento.aggregate(pipeline))


# --- 3j. Movimientos por mes (serie de tiempo) ---
# Colección: movimiento — agrupación por año y mes con $year y $month
# Uso: Dashboard Administrador — gráfica de área (serie de tiempo)
# Resultado: [{ "mes": "Ene 2025", "total": 12 }, ...]
def mg_rpt_movs_por_mes(mg):
    _meses = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
    pipeline = [
        {"$group": {"_id": {
            "year":  {"$year":  "$fecha_hora_movimiento"},
            "month": {"$month": "$fecha_hora_movimiento"}
        }, "total": {"$sum": 1}}},
        {"$sort": {"_id.year": 1, "_id.month": 1}},
    ]
    rows = list(mg.movimiento.aggregate(pipeline))
    return [
        {"mes": f"{_meses[r['_id']['month']-1]} {r['_id']['year']}", "total": r["total"]}
        for r in rows
    ]


# --- 3k. Mantenimientos por mes (serie de tiempo) ---
# Colección: mantenimiento — agrupación por año y mes
# Uso: Dashboard Biomédico — gráfica de área (serie de tiempo)
# Resultado: [{ "mes": "Mar 2025", "total": 5 }, ...]
def mg_rpt_mants_por_mes(mg):
    _meses = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
    pipeline = [
        {"$group": {"_id": {
            "year":  {"$year":  "$fecha_hora_mantenimiento"},
            "month": {"$month": "$fecha_hora_mantenimiento"}
        }, "total": {"$sum": 1}}},
        {"$sort": {"_id.year": 1, "_id.month": 1}},
    ]
    rows = list(mg.mantenimiento.aggregate(pipeline))
    return [
        {"mes": f"{_meses[r['_id']['month']-1]} {r['_id']['year']}", "total": r["total"]}
        for r in rows
    ]


# --- 3l. Estados de equipos por área específica ---
# Colección: ubicacion_especifica (find) + equipo + estado_equipos
# Uso: Dashboard Responsable y Enfermero — gráfica de dona filtrada por área
# Resultado: [{ "estado_equipo": "En uso", "total": 3 }, ...]
def mg_rpt_estados_area(mg, id_area):
    ubic_ids = [u["id_ubicacion"] for u in
                mg.ubicacion_especifica.find(
                    {"id_area": id_area}, {"id_ubicacion": 1, "_id": 0}
                )]
    pipeline = [
        {"$match": {
            "activo_equipo": True,
            "id_ubicacion_administrativa_actual": {"$in": ubic_ids}
        }},
        {"$lookup": {
            "from": "estado_equipos",
            "localField": "id_estado_equipo",
            "foreignField": "id_estado_equipo",
            "as": "estado"
        }},
        {"$unwind": "$estado"},
        {"$group": {"_id": "$estado.estado_equipo", "total": {"$sum": 1}}},
        {"$project": {"estado_equipo": "$_id", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.equipo.aggregate(pipeline))


# --- 3m. Tipos de movimientos en un área ---
# Colección: ubicacion_especifica (find) + movimiento + tipo_movimientos
# Uso: Dashboard Responsable — gráfica de barras por tipo de movimiento del área
# Resultado: [{ "tipo_movimiento": "Préstamo", "total": 6 }, ...]
def mg_rpt_tipos_movs(mg, id_area):
    ubic_ids = [u["id_ubicacion"] for u in
                mg.ubicacion_especifica.find(
                    {"id_area": id_area}, {"id_ubicacion": 1, "_id": 0}
                )]
    pipeline = [
        {"$match": {"$or": [
            {"id_ubicacion_origen":  {"$in": ubic_ids}},
            {"id_ubicacion_destino": {"$in": ubic_ids}}
        ]}},
        {"$group": {"_id": "$id_tipo_movimiento", "total": {"$sum": 1}}},
        {"$lookup": {
            "from": "tipo_movimientos",
            "localField": "_id",
            "foreignField": "id_tipo_movimiento",
            "as": "tipo"
        }},
        {"$unwind": "$tipo"},
        {"$project": {"tipo_movimiento": "$tipo.tipo_movimiento", "total": 1, "_id": 0}},
        {"$sort": {"total": -1}},
    ]
    return list(mg.movimiento.aggregate(pipeline))


# --- 3n. Actividad de equipos en un área (asignaciones + usos clínicos) ---
# Colecciones: equipo, asignacion_equipo, uso_clinico_equipo (find simple)
# Uso: Dashboard Responsable — tabla de actividad de equipos del área
# Resultado: [{ "nombre_equipo": "...", "veces_asignado": 3, "usos_clinicos": 5 }, ...]
def mg_rpt_actividad_equipos(mg, id_area):
    ubic_ids = [u["id_ubicacion"] for u in
                mg.ubicacion_especifica.find(
                    {"id_area": id_area}, {"id_ubicacion": 1, "_id": 0}
                )]
    equipos = list(mg.equipo.find(
        {"activo_equipo": True,
         "id_ubicacion_administrativa_actual": {"$in": ubic_ids}},
        {"_id": 0, "id_equipo": 1, "nombre_equipo": 1}
    ))
    eq_ids    = [e["id_equipo"] for e in equipos]
    asig_cnt  = {}
    for a in mg.asignacion_equipo.find({"id_equipo": {"$in": eq_ids}},
                                        {"_id": 0, "id_equipo": 1, "id_asignacion": 1}):
        asig_cnt.setdefault(a["id_equipo"], set()).add(a["id_asignacion"])
    uso_cnt = {}
    for u in mg.uso_clinico_equipo.find({"id_equipo": {"$in": eq_ids}},
                                         {"_id": 0, "id_equipo": 1, "id_uso_clinico": 1}):
        uso_cnt.setdefault(u["id_equipo"], set()).add(u["id_uso_clinico"])
    return sorted(
        [{"nombre_equipo":   e["nombre_equipo"],
          "veces_asignado":  len(asig_cnt.get(e["id_equipo"], set())),
          "usos_clinicos":   len(uso_cnt.get(e["id_equipo"], set()))}
         for e in equipos],
        key=lambda x: x["veces_asignado"] + x["usos_clinicos"],
        reverse=True
    )


# --- 3o. Equipos más usados por un médico o enfermero específico ---
# Colección: uso_clinico_equipo + lookup a equipo — filtrado por id_persona
# Uso: Dashboard Médico — gráfica de barras personalizada
# Resultado: [{ "nombre_equipo": "...", "total_usos": 4 }, ...]
def mg_rpt_mis_equipos_usados(mg, id_persona):
    pipeline = [
        {"$match": {"id_persona_responsable_uso": id_persona}},
        {"$group": {"_id": "$id_equipo", "total_usos": {"$sum": 1}}},
        {"$lookup": {
            "from": "equipo",
            "localField": "_id",
            "foreignField": "id_equipo",
            "as": "eq"
        }},
        {"$unwind": "$eq"},
        {"$project": {"nombre_equipo": "$eq.nombre_equipo", "total_usos": 1, "_id": 0}},
        {"$sort": {"total_usos": -1}},
        {"$limit": 8},
    ]
    return list(mg.uso_clinico_equipo.aggregate(pipeline))


# --- 3p. Usos clínicos por mes de un usuario específico ---
# Colección: uso_clinico_equipo — agrupación por año y mes, filtrado por persona
# Uso: Dashboard Médico — gráfica de área (serie de tiempo personal)
# Resultado: [{ "mes": "Abr 2025", "total": 3 }, ...]
def mg_rpt_mis_usos_por_mes(mg, id_persona):
    _meses = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
    pipeline = [
        {"$match": {"id_persona_responsable_uso": id_persona}},
        {"$group": {"_id": {
            "year":  {"$year":  "$fecha_hora_inicio"},
            "month": {"$month": "$fecha_hora_inicio"}
        }, "total": {"$sum": 1}}},
        {"$sort": {"_id.year": 1, "_id.month": 1}},
    ]
    rows = list(mg.uso_clinico_equipo.aggregate(pipeline))
    return [
        {"mes": f"{_meses[r['_id']['month']-1]} {r['_id']['year']}", "total": r["total"]}
        for r in rows
    ]


# --- 3q. Movimientos por día de la semana en un área ---
# Colección: movimiento — agrupación por $dayOfWeek, filtrado por ubicaciones del área
# Uso: Dashboard Responsable — gráfica de barras por día de la semana
# Resultado: [{ "dia": "Lun", "total": 8 }, { "dia": "Mar", "total": 5 }, ...]
def mg_rpt_movs_por_dia(mg, id_area):
    _dias    = {1:"Dom", 2:"Lun", 3:"Mar", 4:"Mié", 5:"Jue", 6:"Vie", 7:"Sáb"}
    ubic_ids = [u["id_ubicacion"] for u in
                mg.ubicacion_especifica.find(
                    {"id_area": id_area}, {"id_ubicacion": 1, "_id": 0}
                )]
    pipeline = [
        {"$match": {"$or": [
            {"id_ubicacion_origen":  {"$in": ubic_ids}},
            {"id_ubicacion_destino": {"$in": ubic_ids}}
        ]}},
        {"$group": {
            "_id": {"$dayOfWeek": "$fecha_hora_movimiento"},
            "total": {"$sum": 1}
        }},
        {"$sort": {"_id": 1}},
    ]
    rows    = list(mg.movimiento.aggregate(pipeline))
    day_map = {r["_id"]: r["total"] for r in rows}
    return [{"dia": _dias[d], "total": day_map.get(d, 0)} for d in [2,3,4,5,6,7,1]]


# =============================================================================
# EJEMPLO DE EJECUCIÓN
# =============================================================================
if __name__ == "__main__":
    mg = get_mongo_db()

    print("=== Estados del inventario ===")
    for r in mg_rpt_estados(mg):
        print(f"  {r['estado_equipo']}: {r['total']} equipos")

    print("\n=== Top equipos más movidos ===")
    for r in mg_rpt_mas_movidos(mg)[:5]:
        print(f"  {r['nombre_equipo']} ({r['codigo_interno']}): {r['total_movimientos']} movimientos")

    print("\n=== Mantenimientos por tipo ===")
    for r in mg_rpt_por_tipo_mant(mg):
        print(f"  {r['tipo_mantenimiento']}: {r['total']}")

    print("\n=== Resultados de mantenimientos ===")
    for r in mg_rpt_por_resultado(mg):
        print(f"  {r['resultado_mantenimiento']}: {r['total']}")

    print("\n=== Movimientos por mes ===")
    for r in mg_rpt_movs_por_mes(mg):
        print(f"  {r['mes']}: {r['total']}")

    print("\n=== Últimos 3 eventos IoT en event_logs ===")
    for r in mg.event_logs.find({}, {"_id": 0}).sort("timestamp", -1).limit(3):
        print(f"  [{r['tipo'].upper()}] {r.get('timestamp','')}")
