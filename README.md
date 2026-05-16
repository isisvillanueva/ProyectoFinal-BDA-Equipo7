# Equipo 7 - HospitalIoT — Sistema de Gestión de Equipos Médicos
# 
# Isis Jolette Villanueva Zapata - 667725
# Allison Rodriguez Pereyra - 628093
# Roberto Sánchez Bustani - 668945

> Plataforma web para el inventario, trazabilidad y monitoreo en tiempo real de equipos médicos mediante tecnología IoT (NFC y Beacon), desarrollada con Flask y PostgreSQL.

---

## Tabla de contenidos

- [Descripción general](#descripción-general)
- [Tecnologías](#tecnologías)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Requisitos previos](#requisitos-previos)
- [Instalación y configuración](#instalación-y-configuración)
- [Base de datos](#base-de-datos)
- [Roles y permisos](#roles-y-permisos)
- [Módulos de la aplicación](#módulos-de-la-aplicación)
- [API y endpoints](#api-y-endpoints)
- [Procedimientos almacenados](#procedimientos-almacenados)
- [Triggers y validaciones](#triggers-y-validaciones)
- [Vistas SQL](#vistas-sql)
- [Sistema de auditoría](#sistema-de-auditoría)
- [Frontend y estilos](#frontend-y-estilos)
- [Gráficas y reportes](#gráficas-y-reportes)
- [Panel IoT y polling](#panel-iot-y-polling)
- [Consideraciones de seguridad](#consideraciones-de-seguridad)

---

## Descripción general

HospitalIoT centraliza la gestión de equipos médicos en un entorno hospitalario. El sistema permite registrar, asignar, mover y dar mantenimiento a los equipos, integrando lecturas en tiempo real de dispositivos NFC y Beacon para detectar discrepancias entre la ubicación administrativa y la ubicación física real del equipo.

### Funcionalidades principales

- Inventario completo de equipos con estados, ubicaciones y criticidad
- Asignación y liberación de equipos a personal clínico
- Registro de movimientos internos y traslados externos en ambulancia
- Programación y registro de mantenimientos biomédicos
- Monitoreo IoT: eventos NFC, eventos Beacon, discrepancias de ubicación
- Panel de auditoría con trazabilidad de cada operación
- Reportes y gráficas de uso, carga biomédica y estado de inventario
- Control de acceso por rol con cinco perfiles diferenciados

---

## Tecnologías

| Capa | Tecnología |
|---|---|
| Backend | Python 3 · Flask |
| Base de datos | PostgreSQL (psycopg2 con RealDictCursor) |
| Frontend | HTML5 · CSS3 (variables CSS, sistema propio) · JavaScript (ES2020) |
| Gráficas | Chart.js 4.4 |
| Fuentes | Google Fonts — Outfit · Source Serif 4 |
| Servidor de desarrollo | Flask dev server (puerto 5000) |

---

## Estructura del proyecto

```
hospitaliot/
├── app.py                  # Aplicación Flask — rutas, lógica de negocio, conexión BD
├── hospital_db.sql         # Schema completo de PostgreSQL (tablas, SPs, triggers, vistas)
├── styles.css              # Sistema de diseño (variables CSS, componentes, layout)
├── app.js                  # JavaScript compartido (navegación SPA, polling IoT, toast)
├── macros.html             # Macros Jinja2 reutilizables (badges, flash messages)
├── index.html              # Portal público de consulta de equipos
├── login.html              # Pantalla de autenticación
├── admin.html              # Panel Administrador (versión modular + IoT fusionada)
├── admin_iot.html          # Panel IoT independiente (discrepancias, NFC, Beacon)
├── medico.html             # Panel Médico
├── enfermero.html          # Panel Enfermero
├── responsable.html        # Panel Responsable de área
└── biomedico.html          # Panel Biomédico
```

---

## Requisitos previos

- Python 3.9 o superior
- PostgreSQL 14 o superior
- pip

```bash
pip install flask psycopg2-binary
```

---

## Instalación y configuración

### 1. Clonar el repositorio

```bash
git clone https://github.com/tu-org/hospitaliot.git
cd hospitaliot
```

### 2. Configurar la conexión a la base de datos

En `app.py`, editar el diccionario `DB_CONFIG`:

```python
DB_CONFIG = dict(
    host="127.0.0.1",
    database="hospital_db",
    user="hospital_user",
    password="TU_PASSWORD",
    port=5432
)
```

### 3. Crear la base de datos

```bash
psql -U postgres -c "CREATE DATABASE hospital_db;"
psql -U postgres -c "CREATE USER hospital_user WITH PASSWORD 'TU_PASSWORD';"
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE hospital_db TO hospital_user;"
psql -U hospital_user -d hospital_db -f hospital_db.sql
```

### 4. Arrancar la aplicación

```bash
python app.py
```

La aplicación quedará disponible en `http://127.0.0.1:5000`.

### 5. Estructura de archivos estáticos esperada por Flask

Flask busca los estáticos bajo la carpeta `static/`. Colocar los archivos según:

```
static/
├── css/
│   └── styles.css
└── js/
    └── app.js
```

Los templates deben estar en la carpeta `templates/`.

---

## Base de datos

El archivo `hospital_db.sql` contiene el schema completo. La base de datos tiene **47 tablas**, **14 procedimientos almacenados**, **28 vistas** y **18+ triggers**.

### Tablas principales

| Tabla | Descripción |
|---|---|
| `equipo` | Equipos médicos (código, modelo, estado, ubicación, criticidad) |
| `asignacion_equipo` | Asignaciones activas/históricas de equipos a personal |
| `movimiento` | Movimientos internos entre ubicaciones |
| `mantenimiento` | Registros de mantenimiento correctivo y preventivo |
| `traslado_externo_equipo` | Traslados en ambulancia a destinos externos |
| `uso_clinico_equipo` | Usos clínicos abiertos/cerrados por médicos y enfermeros |
| `auditoria` | Log de todas las operaciones (tabla, acción, usuario, timestamp) |
| `dispositivo_nfc` | Dispositivos NFC vinculados a equipos |
| `dispositivo_beacon` | Beacons registrados por zona |
| `evento_nfc` | Lecturas NFC registradas en tiempo real |
| `evento_beacon` | Detecciones Beacon registradas en tiempo real |
| `evento_gps` | Posiciones GPS de ambulancias |
| `usuario` | Cuentas de acceso al sistema |
| `persona` | Datos personales del personal |
| `ambulancia` | Flota de ambulancias con estado y GPS |

### Catálogos

`tipo_equipos`, `categoria_equipos`, `estado_equipos`, `criticidad_equipos`, `marca_equipo`, `modelo_equipo`, `ubicacion_especifica`, `area_registro`, `zona_beacon`, `tipo_movimientos`, `tipo_mantenimientos`, `tipo_resultado_mantenimientos`, `tipo_traslado_externo`, `roles_usuario`, `turnos`

---

## Roles y permisos

El sistema define cinco roles con vistas y operaciones diferenciadas:

| Rol | Endpoint principal | Capacidades |
|---|---|---|
| **Administrador** | `/admin` | CRUD completo de equipos, asignaciones, traslados, usuarios; panel IoT; reportes; auditoría |
| **Médico** | `/medico` | Consulta de equipos disponibles, apertura/cierre de usos clínicos, mis asignaciones |
| **Enfermero** | `/enfermero` | Registro de movimientos, usos clínicos, consulta de equipos por área |
| **Responsable de área** | `/responsable` | Supervisión de área asignada, cambio de estado de equipos, liberación de asignaciones |
| **Biomédico** | `/biomedico` | Registro y edición de mantenimientos, reprogramación, reporte de carga biomédica |

> Los conductores tienen cuenta en el sistema pero no tienen acceso a la interfaz web; su rol solo es válido para ser asignado como conductor en traslados externos.

### Flujo de autenticación

```
POST /login (JSON) → verifica credenciales → asigna rol en sesión → redirige al panel del rol
```

La función `rol_desde_db()` determina el rol real del usuario, incluyendo la detección automática de enfermeros que son **responsables de área activos**.

---

## Módulos de la aplicación

### Módulo público (`/`)

Portal de consulta sin autenticación. Muestra el inventario de equipos activos con filtros por tipo, área y estado. Consume el endpoint `/api/public/equipos`.

### Panel Administrador (`/admin`)

Vista unificada con navegación SPA (Single Page Application) por hash. Contiene diez secciones accesibles desde el sidebar:

- **Dashboard** — KPIs globales, alertas IoT activas, actividad reciente, cards por rol
- **Reportes** — 4 gráficas Chart.js + tablas de distribución
- **Gestión IoT** — Discrepancias, sin señal, eventos NFC/Beacon, inventario IoT con polling automático cada 60 s
- **Equipos** — Tabla con búsqueda en tiempo real, edición y baja lógica
- **Asignaciones** — Asignaciones activas, liberación con modal de confirmación
- **Movimientos** — Historial completo con búsqueda
- **Mantenimientos** — Historial de servicios biomédicos
- **Traslados** — KPIs de estado + tabla con badges de tránsito/completado
- **Usuarios** — Directorio con cards por rol, activación/desactivación
- **Auditoría** — Últimas 100 acciones con badges semánticos

### Panel Biomédico (`/biomedico`)

Registro de mantenimientos correctivos y preventivos. Incluye edición, eliminación y reprogramación de mantenimientos programados. Reporte de carga biomédica mediante cursor de PostgreSQL (`sp_reporte_carga_biomedica`).

### Panel Médico (`/medico`)

Consulta de equipos disponibles, apertura y cierre de usos clínicos. Reportes de equipos más usados y disponibilidad por tipo.

### Panel Enfermero (`/enfermero`)

Registro de movimientos entre ubicaciones y apertura de usos clínicos. Filtrado de equipos disponibles por área.

### Panel Responsable (`/responsable`)

Supervisión del área asignada. Permite cambiar el estado de equipos y liberar asignaciones desde la vista de área.

---

## API y endpoints

### Autenticación

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/acceso` | Formulario de login |
| `POST` | `/login` | Autenticación (JSON) → devuelve `{ok, redirect}` |
| `GET` | `/logout` | Cierra sesión y redirige al login |

### Pública

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/` | Portal público de equipos |
| `GET` | `/api/public/equipos` | JSON — equipos activos con filtros `q`, `tipo`, `area`, `estado` |
| `GET` | `/api/public/equipos-mapa` | JSON — equipos con última posición GPS |

### Administrador — Equipos

| Método | Ruta | Función Flask | Acción |
|---|---|---|---|
| `POST` | `/admin/equipo/crear` | `admin_crear_equipo` | Alta via `sp_registrar_equipo` |
| `POST` | `/admin/equipo/editar/<id>` | `admin_editar_equipo_master` | Edición (resuelve estado/ubicación por texto) |
| `POST` | `/admin/equipo/eliminar/<id>` | `admin_eliminar_equipo_alias` | Baja lógica (`activo_equipo = FALSE`) |
| `GET` | `/equipo/<id>/historial` | `equipo_historial` | JSON — historial unificado via `sp_historial_equipo` |

### Administrador — Asignaciones

| Método | Ruta | Función Flask | Acción |
|---|---|---|---|
| `POST` | `/admin/asignacion/crear` | `admin_crear_asignacion` | Asignar via `sp_asignar_equipo` |
| `POST` | `/admin/asignacion/liberar/<id>` | `admin_liberar_asig` | Liberar via `sp_cerrar_asignacion_equipo` |

### Administrador — Traslados

| Método | Ruta | Función Flask | Acción |
|---|---|---|---|
| `POST` | `/admin/traslado/crear` | `admin_crear_traslado` | Registrar via `sp_registrar_traslado_externo` (resuelve ambulancia y conductor por nombre/código) |

### Administrador — Usuarios

| Método | Ruta | Función Flask | Acción |
|---|---|---|---|
| `POST` | `/admin/usuario/toggle/<id>` | `admin_toggle_usuario_alias` | Activar/desactivar via `sp_cambiar_estado_usuario` |

### Administrador — IoT

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/admin/iot` | Panel IoT completo |
| `GET` | `/admin/iot/json` | JSON para polling (discrepancias + sin evidencia) |
| `POST` | `/admin/iot/beacon` | Registrar beacon |
| `POST` | `/admin/iot/beacon/<id>/toggle` | Activar/desactivar beacon |
| `POST` | `/admin/iot/beacon/<id>/eliminar` | Eliminar beacon |
| `POST` | `/admin/iot/nfc` | Registrar dispositivo NFC |
| `POST` | `/admin/iot/nfc/<id>/toggle` | Activar/desactivar NFC |
| `POST` | `/admin/iot/nfc/<id>/eliminar` | Eliminar NFC |

### Administrador — APIs auxiliares (JSON)

| Ruta | Datos devueltos |
|---|---|
| `/admin/api/conductores` | Conductores activos (id_persona, nombre, username) |
| `/admin/api/ambulancias` | Ambulancias activas (id, código, placa, estado) |
| `/admin/api/catalogos/equipo` | Tipos, modelos, estados, ubicaciones, criticidades |
| `/admin/api/personas` | Usuarios con persona asociada, excluye conductores |

### Administrador — Reportes

| Ruta | Descripción |
|---|---|
| `GET /admin/reporte/carga_biomedica` | JSON — carga biomédica por rango de fechas (`fecha_inicio`, `fecha_fin`) |
| `POST /admin/responsable_area` | Cambiar responsable de área via `sp_cambiar_responsable_area` |

---

## Procedimientos almacenados

Todos los procedimientos siguen el patrón `CALL sp_nombre(params..., NULL)` donde el último parámetro `NULL` es el argumento `OUT` de mensaje de salida.

| Procedimiento | Descripción |
|---|---|
| `sp_registrar_equipo` | Alta de equipo con vinculación NFC opcional |
| `sp_asignar_equipo` | Asignación de equipo a persona en ubicación |
| `sp_cerrar_asignacion_equipo` | Cierre de asignación activa |
| `sp_cambiar_estado_equipo` | Cambio de estado administrativo del equipo |
| `sp_registrar_movimiento_equipo` | Registro de movimiento interno |
| `sp_registrar_uso_clinico` | Apertura de uso clínico |
| `sp_cerrar_uso_clinico` | Cierre de uso clínico |
| `sp_registrar_mantenimiento` | Registro de mantenimiento realizado |
| `sp_reprogramar_mantenimiento` | Reprogramación de mantenimiento (solo Pendiente o Vencido) |
| `sp_registrar_traslado_externo` | Registro de traslado en ambulancia |
| `sp_cambiar_estado_usuario` | Activar/desactivar cuenta de usuario |
| `sp_cambiar_responsable_area` | Reasignar responsable de área de enfermería |
| `sp_reporte_carga_biomedica` | Reporte de carga biomédica por periodo (devuelve cursor) |
| `sp_historial_equipo` | Historial unificado de movimientos, mantenimientos y usos (devuelve cursor) |

---

## Triggers y validaciones

El sistema implementa validaciones a nivel de base de datos mediante triggers que se ejecutan automáticamente antes de cada operación. Esto garantiza integridad de datos independientemente del origen del cambio.

| Trigger | Validación |
|---|---|
| `fn_validar_equipo_disponible_para_uso` | El equipo debe estar en estado Disponible para abrir uso clínico |
| `fn_validar_equipo_sin_uso_clinico_activo_para_traslado` | No se puede trasladar un equipo con uso clínico abierto |
| `fn_validar_conductor_autorizado_traslado` | El conductor debe tener usuario activo con rol Conductor |
| `fn_validar_ambulancia_activa_para_traslado` | La ambulancia debe estar activa |
| `fn_validar_condiciones_retiro_equipo` | Para retirar un equipo debe estar en estado Fuera de servicio con resultado Requiere reemplazo |
| `fn_validar_mantenimiento_biomedico` | El biomédico debe tener usuario activo |
| `fn_validar_especialidad_responsable_area` | El enfermero debe tener la especialidad requerida para el área |
| `fn_validar_beacon_activo` | El beacon referenciado debe estar activo |
| `fn_validar_nfc_activo` | El dispositivo NFC debe estar activo |
| `fn_validar_gps_activo` | El dispositivo GPS debe estar activo |
| `fn_validar_equipo_no_retirado_en_movimiento` | No se registran movimientos de equipos dados de baja |
| `fn_validar_equipo_no_retirado_en_evento_nfc` | No se registran eventos NFC de equipos retirados |
| `fn_validar_equipo_no_retirado_en_evento_beacon` | No se registran eventos Beacon de equipos retirados |
| `fn_actualizar_estado_equipo_por_mantenimiento` | Actualiza el estado del equipo tras un mantenimiento |
| `fn_actualizar_ubicacion_equipo_por_movimiento` | Actualiza la ubicación administrativa tras un movimiento |
| `fn_retirar_equipo_tras_traslado` | Marca el equipo como retirado cuando el traslado lo requiere |
| `fn_auditoria_generica` | Registra en `auditoria` cada INSERT/UPDATE/DELETE de las tablas monitoreadas |

### Mensajes de error amigables

El helper `friendly_db_error()` en `app.py` intercepta las excepciones de PostgreSQL y las traduce a mensajes comprensibles para el usuario final. Los triggers usan `RAISE EXCEPTION` con frases clave que este diccionario mapea a mensajes en español.

---

## Vistas SQL

Las vistas encapsulan las consultas más complejas y son consumidas directamente desde Flask o desde el panel IoT.

| Vista | Uso |
|---|---|
| `v_discrepancia_ubicacion_iot` | Equipos con ubicación Beacon diferente a la administrativa |
| `v_equipos_sin_evidencia_iot` | Equipos sin lectura NFC ni Beacon en las últimas 12 horas |
| `v_admin_auditoria_reciente` | Últimas 100 acciones auditadas |
| `v_actividad_sistema_por_usuario` | Operaciones totales y tablas afectadas por usuario |
| `v_admin_inventario_equipos` | Inventario completo con joins a tipo, marca, modelo, ubicación |
| `v_historial_traslados_externos` | Historial de traslados con conductor, ambulancia y estado |
| `v_historial_tecnico_equipos` | Historial unificado de movimientos y mantenimientos |
| `v_disponibilidad_equipos_por_area` | Disponibilidad de equipos agrupada por área |
| `v_equipos_criticos_no_disponibles` | Equipos de criticidad Alta que no están disponibles |
| `v_mantenimientos_proximos_a_vencer` | Mantenimientos programados a vencer en los próximos 30 días |
| `v_mantenimientos_vencidos` | Mantenimientos cuya fecha programada ya pasó |
| `v_equipos_candidatos_reemplazo` | Equipos con resultado de mantenimiento Requiere reemplazo |
| `v_carga_biomedico` | Carga de trabajo por biomédico |
| `v_resumen_actividad_equipos` | Usos, movimientos y mantenimientos por equipo |
| `v_responsables_activos_por_area` | Responsables de enfermería activos por área |

---

## Gráficas y reportes

El panel de Reportes incluye cuatro gráficas generadas con **Chart.js 4.4** cargado desde CDN:

| ID Canvas | Tipo | Datos |
|---|---|---|
| `chartEstados` | Doughnut | Distribución de estados de equipos (`rpt_estados`) |
| `chartMovidos` | Barras horizontales | Top 8 equipos más movidos (`rpt_mas_movidos`) |
| `chartMovsArea` | Barras verticales | Movimientos por área hospitalaria (`rpt_movs_area`) |
| `chartAlertas` | Pie | Discrepancias IoT vs sin señal vs sin alertas |

Los datos se serializan desde Jinja2 con `| tojson | safe` y se asignan a constantes JavaScript antes del cierre de `</body>`. Las gráficas se inicializan de forma **lazy** mediante un `MutationObserver` que detecta cuándo la vista de Reportes se activa por primera vez, evitando errores de canvas con dimensión cero.

---

## Consideraciones de seguridad

- **Autenticación por sesión Flask**: todas las rutas protegidas usan los decoradores `@login_required` y `@role_required(*roles)`.
- **Contraseñas**: actualmente se comparan en texto plano. Se recomienda migrar a `bcrypt` o `werkzeug.security` antes de producción.
- **Secret key**: el valor actual `"hospitaliot_equipo7_secret"` debe reemplazarse por una clave aleatoria larga en producción. Usar `python -c "import secrets; print(secrets.token_hex(32))"`.
- **Baja lógica**: los equipos nunca se eliminan físicamente de la base de datos; se marcan con `activo_equipo = FALSE`.
- **Auditoría**: cada modificación queda registrada en la tabla `auditoria` con usuario, fecha, tabla afectada y tipo de acción.
- **Validaciones en BD**: los triggers de PostgreSQL validan reglas de negocio críticas independientemente de la capa web, impidiendo estados inconsistentes aunque se acceda directamente a la base de datos.
- **CSRF**: los formularios incluyen un campo `csrf_token` preparado para integrarse con `Flask-WTF`. Activar la protección antes de pasar a producción.