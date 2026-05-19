# Equivalencias SQL ↔ MongoDB — HospitalIoT

Los ejemplos usan las colecciones reales del proyecto (`equipo`, `movimiento`,
`mantenimiento`, `event_logs`) para ilustrar cómo cada operador SQL se traduce
a la API de MongoDB / pipeline de agregación.

---

## 1. Selección de registros

| SQL | MongoDB |
|-----|---------|
| `SELECT *` | `find({})` |
| `SELECT col1, col2` | `find({}, {"col1": 1, "col2": 1, "_id": 0})` |
| `WHERE` | primer argumento de `find()` o etapa `$match` |
| `LIMIT n` | `.limit(n)` / etapa `$limit` |
| `ORDER BY col ASC/DESC` | `.sort("col", 1 / -1)` / etapa `$sort` |
| `DISTINCT col` | `.distinct("col")` / `$group` por ese campo |

**Ejemplo — equipos disponibles en el área de Urgencias:**

SQL:
```sql
SELECT nombre_equipo, num_serie
FROM equipo
WHERE estado = 'Disponible' AND area = 'Urgencias';
```

MongoDB:
```python
mg.equipo.find(
    {"estado": "Disponible", "area": "Urgencias"},
    {"nombre_equipo": 1, "num_serie": 1, "_id": 0}
)
```

---

## 2. Filtros con operadores de comparación

| SQL | MongoDB |
|-----|---------|
| `= valor` | `{"campo": valor}` |
| `!= valor` | `{"campo": {"$ne": valor}}` |
| `> valor` | `{"campo": {"$gt": valor}}` |
| `>= valor` | `{"campo": {"$gte": valor}}` |
| `< valor` | `{"campo": {"$lt": valor}}` |
| `<= valor` | `{"campo": {"$lte": valor}}` |
| `IN (a, b, c)` | `{"campo": {"$in": [a, b, c]}}` |
| `NOT IN (a, b)` | `{"campo": {"$nin": [a, b]}}` |
| `BETWEEN a AND b` | `{"campo": {"$gte": a, "$lte": b}}` |
| `IS NULL` | `{"campo": None}` |
| `IS NOT NULL` | `{"campo": {"$ne": None}}` |
| `LIKE '%texto%'` | `{"campo": {"$regex": "texto", "$options": "i"}}` |

**Ejemplo — mantenimientos con costo mayor a 500:**

SQL:
```sql
SELECT * FROM mantenimiento WHERE costo > 500;
```

MongoDB:
```python
mg.mantenimiento.find({"costo": {"$gt": 500}})
```

---

## 3. Operadores lógicos

| SQL | MongoDB |
|-----|---------|
| `AND` | `{"$and": [{...}, {...}]}` o condiciones en el mismo objeto |
| `OR` | `{"$or": [{...}, {...}]}` |
| `NOT` | `{"$not": {operador}}` |

**Ejemplo — eventos IoT de tipo NFC o GPS de las últimas 24 horas:**

SQL:
```sql
SELECT * FROM event_logs
WHERE tipo IN ('nfc', 'gps')
  AND timestamp >= NOW() - INTERVAL '24 hours';
```

MongoDB:
```python
import datetime
hace_24h = datetime.datetime.utcnow() - datetime.timedelta(hours=24)

mg.event_logs.find({
    "$or": [{"tipo": "nfc"}, {"tipo": "gps"}],
    "timestamp": {"$gte": hace_24h}
})
```

---

## 4. Agregaciones (GROUP BY + funciones de agregado)

| SQL | MongoDB (`$group`) |
|-----|--------------------|
| `GROUP BY campo` | `{"$group": {"_id": "$campo"}}` |
| `COUNT(*)` | `{"$sum": 1}` |
| `SUM(col)` | `{"$sum": "$col"}` |
| `AVG(col)` | `{"$avg": "$col"}` |
| `MAX(col)` | `{"$max": "$col"}` |
| `MIN(col)` | `{"$min": "$col"}` |
| `HAVING` | etapa `$match` después del `$group` |

**Ejemplo — cantidad de movimientos por tipo (usado en mg_rpt_tipos_movs):**

SQL:
```sql
SELECT tipo_movimiento, COUNT(*) AS total
FROM movimiento
GROUP BY tipo_movimiento
ORDER BY total DESC;
```

MongoDB:
```python
mg.movimiento.aggregate([
    {"$group": {"_id": "$tipo_movimiento", "total": {"$sum": 1}}},
    {"$sort": {"total": -1}}
])
```

**Ejemplo — costo promedio de mantenimiento por equipo (KPI biomédico):**

SQL:
```sql
SELECT id_equipo, AVG(costo) AS promedio_costo
FROM mantenimiento
GROUP BY id_equipo
HAVING COUNT(*) > 1;
```

MongoDB:
```python
mg.mantenimiento.aggregate([
    {"$group": {
        "_id": "$id_equipo",
        "promedio_costo": {"$avg": "$costo"},
        "total": {"$sum": 1}
    }},
    {"$match": {"total": {"$gt": 1}}}
])
```

---

## 5. Proyección de campos (`SELECT col AS alias`)

| SQL | MongoDB (etapa `$project`) |
|-----|---------------------------|
| `SELECT col` | `{"$project": {"col": 1}}` |
| `SELECT col AS alias` | `{"$project": {"alias": "$col"}}` |
| `EXCLUDE col` | `{"$project": {"col": 0}}` |
| Expresión calculada | `{"$project": {"resultado": {"$multiply": ["$a", "$b"]}}}` |

**Ejemplo — nombre del equipo y su estado, excluyendo `_id`:**

```python
mg.equipo.aggregate([
    {"$project": {"_id": 0, "nombre_equipo": 1, "estado": 1}}
])
```

---

## 6. JOIN entre colecciones (`$lookup`)

| SQL | MongoDB |
|-----|---------|
| `INNER JOIN tabla2 ON t1.col = t2.col` | `$lookup` + `$unwind` |

**Ejemplo — movimientos con el nombre del equipo (equivale a JOIN equipo):**

SQL:
```sql
SELECT m.id_movimiento, m.tipo_movimiento, e.nombre_equipo
FROM movimiento m
JOIN equipo e ON m.id_equipo = e.id_equipo;
```

MongoDB:
```python
mg.movimiento.aggregate([
    {"$lookup": {
        "from": "equipo",
        "localField": "id_equipo",
        "foreignField": "id_equipo",
        "as": "equipo_info"
    }},
    {"$unwind": "$equipo_info"},
    {"$project": {
        "id_movimiento": 1,
        "tipo_movimiento": 1,
        "nombre_equipo": "$equipo_info.nombre_equipo"
    }}
])
```

---

## 7. Inserción de registros

| SQL | MongoDB |
|-----|---------|
| `INSERT INTO tabla (cols) VALUES (vals)` | `insert_one({documento})` |
| Inserción múltiple | `insert_many([{doc1}, {doc2}])` |

**Ejemplo — insertar evento GPS en event_logs (dual-write desde Flask):**

SQL:
```sql
INSERT INTO event_logs (tipo, id_dispositivo, latitud, longitud, timestamp)
VALUES ('gps', 'GPS-AMB-001', 25.78, -100.23, NOW());
```

MongoDB:
```python
mg.event_logs.insert_one({
    "tipo":          "gps",
    "id_dispositivo": "GPS-AMB-001",
    "latitud":       25.78,
    "longitud":      -100.23,
    "timestamp":     datetime.datetime.utcnow()
})
```

---

## 8. Actualización de registros

| SQL | MongoDB |
|-----|---------|
| `UPDATE tabla SET col = val WHERE ...` | `update_one({filtro}, {"$set": {campo: val}})` |
| Actualización masiva | `update_many(...)` |
| Incrementar valor | `{"$inc": {"campo": n}}` |
| Añadir a un array | `{"$push": {"array": valor}}` |

**Ejemplo — cambiar estado de un equipo a "En mantenimiento":**

SQL:
```sql
UPDATE equipo SET estado = 'En mantenimiento' WHERE id_equipo = 12;
```

MongoDB:
```python
mg.equipo.update_one(
    {"id_equipo": 12},
    {"$set": {"estado": "En mantenimiento"}}
)
```

---

## 9. Eliminación de registros

| SQL | MongoDB |
|-----|---------|
| `DELETE FROM tabla WHERE ...` | `delete_one({filtro})` / `delete_many({filtro})` |

> El sistema HospitalIoT no realiza eliminaciones físicas en ninguna colección.
> La baja lógica se implementa con `update_one(..., {"$set": {"activo": False}})`,
> equivalente al patrón de `soft delete` usado en PostgreSQL.

---

## 10. Índices

| SQL | MongoDB |
|-----|---------|
| `CREATE INDEX idx ON tabla(col)` | `create_index("col")` |
| `CREATE UNIQUE INDEX` | `create_index("col", unique=True)` |
| Índice compuesto | `create_index([("col1", 1), ("col2", -1)])` |

Los índices del proyecto se crean en `migrate_to_mongo.py` sobre los campos
más consultados: `id_equipo`, `estado`, `area`, `tipo`, `timestamp`.
