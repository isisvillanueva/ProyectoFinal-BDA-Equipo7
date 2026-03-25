# ProyectoFinal-BDA-Equipo7

Repositorio del Proyecto Final de la materia Base de Datos Avanzadas donde se desarrollará un prototipo de Sistema de Trazabilidad con RFID para un hospital.

Equipo:
- Isis Villanueva 667725
- Allison Rodriguez 628093
- Roberto Sánchez 668945

# Estructura del proyecto

```
flask-hospital/
├── app.py                  # Aplicación Flask principal
├── requirements.txt        # Dependencias Python
├── static/
│   ├── css/styles.css      # Estilos (palette teal/blanco clínico)
│   └── js/app.js           # JS mínimo: login AJAX, tabs, modal
└── templates/
    ├── base.html           # Layout base (Jinja2)
    ├── macros.html         # Macros reutilizables (badges, flash)
    ├── index.html          # Login
    ├── admin.html          # Dashboard administrador
    ├── medico.html         # Dashboard médico
    ├── biomedico.html      # Dashboard biomédico
    ├── enfermero.html      # Dashboard enfermero/a
    └── responsable.html    # Dashboard responsable de área
```

# Instalación

## En Google Cloud:

### Instalar las siguientes dependencias en su terminal:

pip3 install psycopg2-binary flask_sqlalchemy

### 3. Restaurar la base de datos
psql -U postgres -c "CREATE DATABASE hospital;"
psql -U postgres -d hospital -f hospital.sql

### 4. Configurar acceso a BD en app.py:
DB_CONFIG = dict(
    host="localhost",
    database="hospital",
    user="postgres",
    password="TU_PASSWORD",
    port="5432"
)

### 5. Ejecutar
export FLASK_APP=app.py
flask run --host=0.0.0.0


## Credenciales de prueba

| Usuario      | Contraseña | Rol              |
|--------------|------------|------------------|
| admin01      | admin123   | Administrador    |
| medico01     | pass123    | Médico           |
| biomedico01  | pass123    | Biomédico        |
| enfermero03  | pass123    | Enfermero/a      |
| enfermero01  | pass123    | Responsable Área |

## Funcionalidades por rol

### Administrador
- Dashboard con KPIs en tiempo real
- Inventario completo de equipos
- Registro de nuevos equipos (SP `sp_registrar_equipo`)
- Asignación de equipos a personas (SP `sp_asignar_equipo_persona`)
- Liberar asignaciones (SP `sp_cerrar_asignacion_equipo`)
- Historial de movimientos y mantenimientos
- Directorio de usuarios y roles

### Médico
- Equipos disponibles en tiempo real
- Registro de uso clínico (SP `sp_registrar_uso_clinico`)
- Mis asignaciones activas
- Historial personal de usos

### Biomédico
- Registro de mantenimientos (SP `sp_registrar_mantenimiento`)
- Equipos críticos (resultados problemáticos)
- Reporte de carga de trabajo (`fn_reporte_carga_biomedica`)
- Historial de mantenimientos propios

### Enfermero/a
- Estado de todos los equipos del sistema
- Registro de movimientos (SP `sp_registrar_movimiento_equipo`)
- Registro de uso clínico
- Historial del área

### Responsable de Área
- Dashboard de su área específica
- Equipos, asignaciones y movimientos del área
- Personal a su cargo
- Vista de responsables activos por área

## Procedimientos almacenados utilizados

| SP / Función                        | Usado en                          |
|-------------------------------------|-----------------------------------|
| `sp_registrar_equipo`               | Admin → Nuevo equipo              |
| `sp_asignar_equipo_persona`         | Admin → Asignar equipo            |
| `sp_cerrar_asignacion_equipo`       | Admin → Liberar asignación        |
| `sp_registrar_uso_clinico`          | Médico y Enfermero → Usar equipo  |
| `sp_registrar_mantenimiento`        | Biomédico → Registrar mant.       |
| `sp_registrar_movimiento_equipo`    | Enfermero → Registrar movimiento  |
| `fn_reporte_carga_biomedica`        | Biomédico → Carga de trabajo      |



Notas:
- El error Permission denied en la VM ocurre porque el usuario postgres no tiene acceso al archivo. Moverlo a /tmp y darle permisos de lectura permite que PostgreSQL pueda ejecutarlo correctamente.
