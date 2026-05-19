# HospitalIoT — Sistema de Gestión de Equipos Biomédicos

Proyecto Final — Bases de Datos Avanzadas  
Equipo 7

**Integrantes**
- Isis Jolette Villanueva Zapata — 667725
- Allison Rodriguez Pereyra — 628093
- Roberto Sánchez Bustani — 668945

Sistema web para la gestión integral de equipos biomédicos hospitalarios con integración IoT (NFC, Beacon Bluetooth, GPS), aplicación móvil Flutter y arquitectura de persistencia dual PostgreSQL + MongoDB.

---

## Tecnologías

| Capa | Tecnología |
|---|---|
| Backend | Python 3.12 · Flask 3.1 |
| Base de datos relacional | PostgreSQL 16 |
| Base de datos NoSQL | MongoDB 8.0 |
| Frontend | HTML5 · CSS3 · JavaScript · Jinja2 |
| Gráficas | Highcharts (CDN) |
| App móvil | Flutter (APK Android) |
| IoT GPS | Traccar Client (protocolo OsmAnd) |
| IoT Bluetooth | bleak (BLE scanner) |
| Túnel externo | ngrok |

---

## Requisitos previos

Antes de comenzar asegúrate de tener instalado:

- Python 3.10 o superior
- PostgreSQL 14 o superior en ejecución
- MongoDB 6.0 o superior en ejecución
- pip

---

## Pasos de replicación

### 1. Descomprimir o clonar el proyecto

```bash
cd ProyectoFinal-BDA-Equipo7
```

### 2. Instalar dependencias Python

```bash
pip install -r requirements.txt
```

Esto instala Flask, psycopg2-binary, pymongo, itsdangerous, aiohttp y bleak.

### 3. Configurar PostgreSQL

**3.1 Crear el usuario y la base de datos** (ejecutar como superusuario de PostgreSQL):

```bash
psql -U postgres -c "CREATE USER hospital_user WITH PASSWORD 'AIR795';"
psql -U postgres -c "CREATE DATABASE hospital_db OWNER hospital_user;"
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE hospital_db TO hospital_user;"
```

**3.2 Restaurar el esquema completo con datos de prueba:**

```bash
PGPASSWORD=AIR795 psql -h 127.0.0.1 -U hospital_user -d hospital_db -f hospital_db.sql
```

Esto crea las 40+ tablas, 37 vistas, 34 triggers, 21 stored procedures e inserta todos los datos de prueba.

### 4. Configurar MongoDB

**4.1 Crear el usuario de MongoDB** (ejecutar dentro de mongosh como admin):

```javascript
use hospital_mongo
db.createUser({
  user: "hospital_mongo_user",
  pwd:  "AIR795",
  roles: [{ role: "readWrite", db: "hospital_mongo" }]
})
```

**4.2 Poblar las colecciones desde PostgreSQL:**

```bash
python3 migrate_to_mongo.py
```

Este script replica las tablas principales de PostgreSQL hacia MongoDB y crea los índices necesarios para los reportes analíticos. Puede ejecutarse nuevamente en cualquier momento para resincronizar los datos.

### 5. Iniciar la aplicación

```bash
./run.sh
```

La aplicación queda disponible en:

```
http://localhost:5000
```

Para acceso desde otros dispositivos en red (APK, dispositivos IoT):

```
http://<IP-del-servidor>:5000
```

### 6. (Opcional) Iniciar el escáner de beacon Bluetooth

Requiere hardware Bluetooth. En una terminal separada:

```bash
python3 beacon_scanner.py
```

El script detecta beacons BLE activos en el entorno y reporta su presencia al backend automáticamente.

### 7. (Opcional) Exponer el servidor con ngrok

Para que la APK Flutter o Traccar Client puedan alcanzar el servidor desde fuera de la red local:

```bash
./ngrok http 5000
```

Usa la URL pública generada en la configuración de la APK y en Traccar Client.

---

## Usuarios de prueba

| Username | Contraseña | Rol |
|---|---|---|
| admin | hashed_admin123 | Administrador |
| ltorres | hashed_torres123 | Médico |
| cgarcia | hashed_garcia123 | Médico |
| sflores | hashed_flores123 | Enfermero |
| rbustani | hashed_rbustani | Enfermero |
| amartinez | hashed_amtz123 | Enfermero |
| rramirez | hashed_ramirez123 | Biomédico |

> Los enfermeros asignados como responsables de área acceden con su misma cuenta. El sistema detecta automáticamente si el enfermero tiene un área activa bajo su responsabilidad y les muestra la vista de responsable.

---

## Estructura del proyecto

```
ProyectoFinal-BDA-Equipo7/
├── app.py                  # Aplicación Flask principal
├── migrate_to_mongo.py     # Migración PostgreSQL → MongoDB
├── beacon_scanner.py       # Escáner BLE para beacons Bluetooth
├── hospital_db.sql         # Esquema completo PostgreSQL con datos de prueba
├── requirements.txt        # Dependencias Python
├── run.sh                  # Script de arranque
├── templates/
│   ├── admin.html          # Panel Administrador
│   ├── medico.html         # Panel Médico
│   ├── enfermero.html      # Panel Enfermero
│   ├── biomedico.html      # Panel Biomédico
│   ├── responsable.html    # Panel Responsable de área
│   ├── admin_iot.html      # Panel IoT
│   ├── index.html          # Portal público
│   ├── login.html          # Pantalla de acceso
│   ├── nfc_login.html      # Login por NFC
│   ├── nfc_scan.html       # Escaneo NFC
│   ├── error_permisos.html # Página de error de acceso
│   └── macros.html         # Componentes Jinja2 reutilizables
└── static/
    ├── css/
    └── js/
```

---

## Roles del sistema

| Rol | Ruta principal | Descripción |
|---|---|---|
| Administrador | `/admin` | Gestión completa de inventario, usuarios, IoT, reportes y auditoría |
| Médico | `/medico` | Registro y cierre de usos clínicos, consulta de equipos disponibles |
| Enfermero | `/enfermero` | Registro de movimientos y usos clínicos en su área |
| Biomédico | `/biomedico` | Registro de mantenimientos, carga de trabajo y KPIs de costo |
| Responsable de área | `/responsable` | Supervisión del inventario y actividad del área asignada |

---

## Base de datos

### PostgreSQL — hospital_db

- **40+ tablas** organizadas en grupos: personas y usuarios, equipos e inventario, operaciones clínicas, mantenimientos, IoT y auditoría
- **37 vistas analíticas** — 23 activamente consumidas por la aplicación
- **21 stored procedures** — todos invocados desde la aplicación
- **34 triggers** — activos en PostgreSQL, cubren validaciones de negocio, actualización automática de estado/ubicación y auditoría

### MongoDB — hospital_mongo

15 colecciones replicadas desde PostgreSQL más la colección `event_logs` para eventos IoT en tiempo real. Los datos se sincronizan con `migrate_to_mongo.py` y se complementan con escrituras en tiempo real desde los endpoints IoT de Flask.

---

## Aplicación móvil (APK Flutter)

La APK permite al personal clínico registrar usos clínicos directamente desde el punto de atención. El flujo es:

1. Login → recibe token firmado
2. Escaneo NFC del equipo + detección de beacon de la zona → identifica el equipo y confirma ubicación física
3. Selección del tipo de procedimiento → registra el uso clínico vía `sp_registrar_uso_clinico`
4. Cierre del uso clínico cuando termina el procedimiento → vía `sp_cerrar_uso_clinico`

Endpoints utilizados por la APK:
- `POST /api/mobile/login`
- `POST /api/iot/escaneo`
- `POST /api/iot/uso/registrar`
- `POST /api/iot/uso/cerrar`

---

## Auditoría

El trigger `fn_auditoria_generica` registra automáticamente las operaciones sobre 7 tablas críticas: `equipo`, `usuario`, `persona`, `asignacion_equipo`, `movimiento`, `mantenimiento` y `responsable_area`.

Tipos de acción registrados: `INSERT`, `UPDATE`, `DELETE_LOGICO`, `ACTIVACION`, `DESACTIVACION`.

El sistema no realiza eliminaciones físicas. Cada registro de auditoría incluye el usuario responsable, la fecha y hora, los valores antes y después del cambio, y el origen de la operación (`web_admin`, `flutter_movil`, `directo_bd`, etc.).

---

## Notas

- Las contraseñas se almacenan en texto plano en esta versión. Su reemplazo por hashing con bcrypt está identificado como mejora pendiente.
- El seguimiento GPS usa Traccar Client apuntando a `POST /api/gps/osmand`. La ambulancia activa es `GPS-AMB-001`.
- Los eventos IoT (NFC, GPS, beacon) se escriben simultáneamente en PostgreSQL y en la colección `event_logs` de MongoDB.
