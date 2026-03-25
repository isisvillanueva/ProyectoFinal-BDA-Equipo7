from flask import Flask, render_template, redirect, url_for, flash, request, session, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor
from functools import wraps

app = Flask(__name__)
app.secret_key = "hospitaliot_equipo7_secret"

DB_CONFIG = dict(
    host="localhost",
    database="hospital",
    user="postgres",
    password="contraseñareal",
    port="5432"
)

def get_db():
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)

# ── decorators ────────────────────────────────────────────────────────────────
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

# ── helpers ───────────────────────────────────────────────────────────────────
def rol_desde_db(id_usuario):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT r.rol_usuario
                    FROM usuario_rol ur
                    JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
                    WHERE ur.id_usuario = %s
                    LIMIT 1
                """, (id_usuario,))
                row = cur.fetchone()
                if row:
                    v = row["rol_usuario"].lower()
                    if "responsable" in v:
                        return "responsable"
                    if "biomedico" in v or "biomédico" in v:
                        return "biomedico"
                    if "enfermero" in v:
                        return "enfermero"
                    if "medico" in v or "médico" in v:
                        return "medico"
                    if "admin" in v:
                        return "admin"
    except Exception:
        pass
    return "sin_rol"

def rol_desde_username(u):
    u = u.lower()
    for prefix, rol in [
        ("admin", "admin"),
        ("biomedico", "biomedico"),
        ("enfermero", "enfermero"),
        ("medico", "medico"),
        ("responsable", "responsable")
    ]:
        if u.startswith(prefix):
            return rol
    return "sin_rol"

# ── auth + módulo público ─────────────────────────────────────────────────────
@app.route("/")
def public_home():
    if "id_usuario" in session:
        return redirect(url_for("dashboard"))

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("SELECT COUNT(*) AS n FROM equipo")
                total_equipos = cur.fetchone()["n"]

                cur.execute("""
                    SELECT ee.estado_equipo, COUNT(*) AS total
                    FROM equipo e
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    GROUP BY ee.estado_equipo
                    ORDER BY total DESC
                """)
                estados_publicos = cur.fetchall()

                cur.execute("""
                    SELECT te.tipo_equipo, COUNT(*) AS total
                    FROM equipo e
                    JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
                    GROUP BY te.tipo_equipo
                    ORDER BY total DESC
                """)
                tipos_publicos = cur.fetchall()

                cur.execute("""
                    SELECT DISTINCT te.tipo_equipo
                    FROM equipo e
                    JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
                    ORDER BY te.tipo_equipo
                """)
                tipos_filtro = [r["tipo_equipo"] for r in cur.fetchall()]

                cur.execute("""
                    SELECT DISTINCT ar.area
                    FROM equipo e
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
                    JOIN area_registro ar ON ar.id_area = ue.id_area
                    ORDER BY ar.area
                """)
                areas_filtro = [r["area"] for r in cur.fetchall()]

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

@app.route("/acceso")
def login_view():
    if "id_usuario" in session:
        return redirect(url_for("dashboard"))
    return render_template("login.html")

@app.route("/login", methods=["POST"])
def login():
    d = request.get_json(silent=True) or {}
    username = (d.get("username") or "").strip()
    password = (d.get("password") or "").strip()

    if not username or not password:
        return jsonify(ok=False, mensaje="Ingresa usuario y contraseña."), 400

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT u.id_usuario, u.username, u.contrasenia, u.activo,
                           u.id_persona, p.nombre_persona, p.apellido_persona
                    FROM usuario u
                    JOIN persona p ON p.id_persona = u.id_persona
                    WHERE u.username = %s
                """, (username,))
                row = cur.fetchone()
    except Exception as e:
        return jsonify(ok=False, mensaje=f"Error BD: {e}"), 500

    if not row:
        return jsonify(ok=False, mensaje="Usuario no encontrado."), 401
    if not row["activo"]:
        return jsonify(ok=False, mensaje="Usuario inactivo."), 401
    if row["contrasenia"] != password:
        return jsonify(ok=False, mensaje="Contraseña incorrecta."), 401

    rol = rol_desde_db(row["id_usuario"]) or rol_desde_username(row["username"])
    session.update(
        id_usuario=row["id_usuario"],
        username=row["username"],
        id_persona=row["id_persona"],
        rol=rol,
        nombre=f"{row['nombre_persona']} {row['apellido_persona']}"
    )
    return jsonify(ok=True, redirect=url_for("dashboard"))

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login_view"))

@app.route("/dashboard")
@login_required
def dashboard():
    destinos = dict(
        admin="admin_v",
        medico="medico_v",
        enfermero="enfermero_v",
        biomedico="biomedico_v",
        responsable="responsable_v"
    )
    dest = destinos.get(session.get("rol"))
    if dest:
        return redirect(url_for(dest))
    flash("Rol sin dashboard.", "error")
    return redirect(url_for("logout"))

@app.route("/api/public/equipos")
def api_public_equipos():
    q = (request.args.get("q") or "").strip()
    tipo = (request.args.get("tipo") or "").strip()
    area = (request.args.get("area") or "").strip()
    estado = (request.args.get("estado") or "").strip()

    sql = """
        SELECT
            e.id_equipo,
            e.codigo_interno,
            e.nombre_equipo,
            e.marca,
            e.modelo,
            te.tipo_equipo,
            ce.categoria_equipo,
            ee.estado_equipo,
            ue.nombre_ubicacion,
            ar.area
        FROM equipo e
        JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
        JOIN categoria_equipos ce ON ce.id_categoria_equipo = e.id_categoria_equipo
        JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
        JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
        JOIN area_registro ar ON ar.id_area = ue.id_area
        WHERE 1=1
    """
    params = []

    if q:
        sql += """
            AND (
                LOWER(e.codigo_interno) LIKE %s OR
                LOWER(e.nombre_equipo) LIKE %s OR
                LOWER(e.marca) LIKE %s OR
                LOWER(e.modelo) LIKE %s
            )
        """
        like = f"%{q.lower()}%"
        params.extend([like, like, like, like])

    if tipo:
        sql += " AND te.tipo_equipo = %s"
        params.append(tipo)

    if area:
        sql += " AND ar.area = %s"
        params.append(area)

    if estado:
        sql += " AND ee.estado_equipo = %s"
        params.append(estado)

    sql += " ORDER BY e.nombre_equipo LIMIT 200"

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(sql, tuple(params))
                rows = cur.fetchall()
        return jsonify(ok=True, data=rows)
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500

@app.route("/api/public/equipos-mapa")
def api_public_equipos_mapa():
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT
                        e.id_equipo,
                        e.codigo_interno,
                        e.nombre_equipo,
                        e.marca,
                        e.modelo,
                        ee.estado_equipo,
                        ue.nombre_ubicacion,
                        ar.area,
                        eg.latitud,
                        eg.longitud,
                        eg.fecha_evento_gps
                    FROM equipo e
                    JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                    JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
                    JOIN area_registro ar ON ar.id_area = ue.id_area
                    JOIN dispositivo_gps dg ON dg.id_equipo = e.id_equipo
                    JOIN LATERAL (
                        SELECT eg.latitud, eg.longitud, eg.fecha_evento_gps
                        FROM evento_gps eg
                        WHERE eg.id_gps = dg.id_gps
                        ORDER BY eg.fecha_evento_gps DESC
                        LIMIT 1
                    ) eg ON TRUE
                    ORDER BY e.nombre_equipo;
                """)
                rows = cur.fetchall()

        return jsonify(ok=True, data=rows)
    except Exception as e:
        return jsonify(ok=False, mensaje=str(e)), 500

# ═══════════════════════════════════════════════════════
# ADMIN
# ═══════════════════════════════════════════════════════
def _admin_catalogs(cur):
    cur.execute("SELECT id_tipo_equipo,tipo_equipo FROM tipo_equipos ORDER BY tipo_equipo")
    tipos_equipo = cur.fetchall()

    cur.execute("SELECT id_categoria_equipo,categoria_equipo FROM categoria_equipos ORDER BY categoria_equipo")
    categorias = cur.fetchall()

    cur.execute("SELECT id_estado_equipo,estado_equipo FROM estado_equipos ORDER BY estado_equipo")
    estados_cat = cur.fetchall()

    cur.execute("SELECT id_ubicacion,nombre_ubicacion FROM ubicacion_especifica ORDER BY nombre_ubicacion")
    ubicaciones = cur.fetchall()

    cur.execute("SELECT id_persona,nombre_persona||' '||apellido_persona AS nombre FROM persona ORDER BY apellido_persona")
    personas = cur.fetchall()

    return tipos_equipo, categorias, estados_cat, ubicaciones, personas

@app.route("/admin")
@login_required
@role_required("admin")
def admin_v():
    with get_db() as c:
        with c.cursor() as cur:
            # KPIs
            cur.execute("SELECT COUNT(*) AS n FROM equipo")
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
                GROUP BY ee.estado_equipo
            """)
            estados = {r["estado_equipo"]: r["n"] for r in cur.fetchall()}

            # Equipos completo
            cur.execute("""
                SELECT e.id_equipo,e.codigo_interno,e.nombre_equipo,e.marca,e.modelo,
                       e.numero_serie,te.tipo_equipo,ce.categoria_equipo,
                       ee.estado_equipo,ue.nombre_ubicacion,ar.area,
                       e.id_tipo_equipo,e.id_categoria_equipo,e.id_estado_equipo,e.id_ubicacion
                FROM equipo e
                JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
                JOIN categoria_equipos ce ON ce.id_categoria_equipo = e.id_categoria_equipo
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
                JOIN area_registro ar ON ar.id_area = ue.id_area
                ORDER BY e.codigo_interno
            """)
            equipos = cur.fetchall()

            # Movimientos
            cur.execute("""
                SELECT m.id_movimiento,e.nombre_equipo,e.codigo_interno,
                       tm.tipo_movimiento,uo.nombre_ubicacion AS origen,
                       ud.nombre_ubicacion AS destino,
                       p.nombre_persona||' '||p.apellido_persona AS responsable,
                       m.fecha_movimiento,m.observacion_movimiento
                FROM movimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_movimientos tm ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                JOIN ubicacion_especifica uo ON uo.id_ubicacion = m.id_ubicacion_origen
                JOIN ubicacion_especifica ud ON ud.id_ubicacion = m.id_ubicacion_destino
                JOIN persona p ON p.id_persona = m.id_persona_responsable
                ORDER BY m.fecha_movimiento DESC
            """)
            movimientos = cur.fetchall()

            # Usuarios
            cur.execute("""
                SELECT u.id_usuario,u.username,p.nombre_persona,p.apellido_persona,
                       p.correo_persona,r.rol_usuario,u.activo
                FROM usuario u
                JOIN persona p ON p.id_persona = u.id_persona
                JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
                JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
                ORDER BY r.rol_usuario,p.apellido_persona
            """)
            usuarios = cur.fetchall()

            # Asignaciones activas
            cur.execute("""
                SELECT ae.id_asignacion,e.nombre_equipo,e.codigo_interno,
                       p.nombre_persona||' '||p.apellido_persona AS asignado_a,
                       ue.nombre_ubicacion,ae.fecha_asignacion,ae.observacion_asignacion
                FROM asignacion_equipo ae
                JOIN equipo e ON e.id_equipo = ae.id_equipo
                JOIN persona p ON p.id_persona = ae.id_persona
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = ae.id_ubicacion
                WHERE ae.fecha_fin_asignacion IS NULL
                ORDER BY ae.fecha_asignacion DESC
            """)
            asignaciones = cur.fetchall()

            # Mantenimientos
            cur.execute("""
                SELECT m.id_mantenimiento,e.nombre_equipo,e.codigo_interno,
                       tm.tipo_mantenimiento,trm.resultado_mantenimiento,
                       p.nombre_persona||' '||p.apellido_persona AS biomedico,
                       m.descripcion_mantenimiento,m.fecha_mantenimiento
                FROM mantenimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_mantenimientos tm ON tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento
                JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = m.id_resultado_mantenimiento
                JOIN persona p ON p.id_persona = m.id_persona
                ORDER BY m.fecha_mantenimiento DESC
            """)
            mantenimientos = cur.fetchall()

            # ── REPORTES: datos reales desde BD ──
            cur.execute("""
                SELECT * FROM fn_reporte_equipos_mas_movidos(
                    '2025-01-01'::timestamp,'2099-12-31'::timestamp)
                ORDER BY total_movimientos DESC
            """)
            rpt_mas_movidos = cur.fetchall()

            cur.execute("""
                SELECT * FROM fn_reporte_carga_biomedica(
                    '2025-01-01'::timestamp,'2099-12-31'::timestamp)
                ORDER BY total_mantenimientos DESC
            """)
            rpt_carga_bio = cur.fetchall()

            cur.execute("""
                SELECT e.codigo_interno, e.nombre_equipo,
                       COUNT(DISTINCT u.id_uso_clinico) AS total_usos,
                       COUNT(DISTINCT m.id_mantenimiento) AS total_mants
                FROM equipo e
                LEFT JOIN uso_clinico_equipo u ON u.id_equipo = e.id_equipo
                LEFT JOIN mantenimiento m ON m.id_equipo = e.id_equipo
                GROUP BY e.id_equipo, e.codigo_interno, e.nombre_equipo
                ORDER BY total_usos DESC
            """)
            rpt_uso_vs_mant = cur.fetchall()

            cur.execute("""
                SELECT ar.area,
                       COUNT(m.id_movimiento) AS total_movs,
                       COUNT(DISTINCT e.id_equipo) AS equipos_involucrados
                FROM area_registro ar
                LEFT JOIN ubicacion_especifica ue ON ue.id_area = ar.id_area
                LEFT JOIN movimiento m ON m.id_ubicacion_destino = ue.id_ubicacion
                    OR m.id_ubicacion_origen = ue.id_ubicacion
                LEFT JOIN equipo e ON e.id_ubicacion = ue.id_ubicacion
                GROUP BY ar.id_area, ar.area
                ORDER BY total_movs DESC
            """)
            rpt_movs_area = cur.fetchall()

            cur.execute("""
                SELECT tm.tipo_movimiento, COUNT(*) AS total
                FROM movimiento m
                JOIN tipo_movimientos tm ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                GROUP BY tm.tipo_movimiento
                ORDER BY total DESC
            """)
            rpt_freq_mov = cur.fetchall()

            cur.execute("""
                SELECT ee.estado_equipo, COUNT(*) AS total
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                GROUP BY ee.estado_equipo
                ORDER BY total DESC
            """)
            rpt_estados = cur.fetchall()

            tipos_equipo, categorias, estados_cat, ubicaciones, personas = _admin_catalogs(cur)

    return render_template(
        "admin.html",
        total_eq=total_eq, total_mov=total_mov, total_usr=total_usr, total_mant=total_mant,
        estados=estados, equipos=equipos, movimientos=movimientos,
        usuarios=usuarios, asignaciones=asignaciones, mantenimientos=mantenimientos,
        rpt_mas_movidos=rpt_mas_movidos, rpt_carga_bio=rpt_carga_bio,
        rpt_uso_vs_mant=rpt_uso_vs_mant, rpt_movs_area=rpt_movs_area,
        rpt_freq_mov=rpt_freq_mov, rpt_estados=rpt_estados,
        tipos_equipo=tipos_equipo, categorias=categorias, estados_cat=estados_cat,
        ubicaciones=ubicaciones, personas=personas
    )

# CRUD equipos
@app.route("/admin/equipo", methods=["POST"])
@login_required
@role_required("admin")
def admin_nuevo_equipo():
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "CALL sp_registrar_equipo(%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                    (
                        f["codigo_interno"], f["nombre_equipo"], f["marca"], f["modelo"],
                        f.get("numero_serie", ""), int(f["id_tipo_equipo"]), int(f["id_categoria_equipo"]),
                        int(f["id_estado_equipo"]), int(f["id_ubicacion"])
                    )
                )
            c.commit()
        flash("Equipo registrado correctamente.", "success")
    except Exception as e:
        flash(f"Error al registrar equipo: {e}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")

@app.route("/admin/equipo/<int:id_equipo>/editar", methods=["POST"])
@login_required
@role_required("admin")
def admin_editar_equipo(id_equipo):
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    UPDATE equipo
                    SET nombre_equipo=%s, marca=%s, modelo=%s,
                        numero_serie=%s, id_tipo_equipo=%s, id_categoria_equipo=%s,
                        id_estado_equipo=%s, id_ubicacion=%s
                    WHERE id_equipo=%s
                """, (
                    f["nombre_equipo"], f["marca"], f["modelo"], f.get("numero_serie", ""),
                    int(f["id_tipo_equipo"]), int(f["id_categoria_equipo"]),
                    int(f["id_estado_equipo"]), int(f["id_ubicacion"]), id_equipo
                ))
            c.commit()
        flash("Equipo actualizado.", "success")
    except Exception as e:
        flash(f"Error al actualizar: {e}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")

@app.route("/admin/equipo/<int:id_equipo>/eliminar", methods=["POST"])
@login_required
@role_required("admin")
def admin_eliminar_equipo(id_equipo):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT COUNT(*) AS n
                    FROM asignacion_equipo
                    WHERE id_equipo=%s AND fecha_fin_asignacion IS NULL
                """, (id_equipo,))
                if cur.fetchone()["n"] > 0:
                    flash("No se puede eliminar: el equipo tiene asignaciones activas.", "error")
                    return redirect(url_for("admin_v") + "#v-equipos")

                cur.execute("DELETE FROM equipo WHERE id_equipo=%s", (id_equipo,))
            c.commit()
        flash("Equipo eliminado.", "success")
    except Exception as e:
        flash(f"Error al eliminar: {e}", "error")
    return redirect(url_for("admin_v") + "#v-equipos")

# CRUD asignaciones
@app.route("/admin/asignar", methods=["POST"])
@login_required
@role_required("admin")
def admin_asignar():
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "CALL sp_asignar_equipo_persona(%s,%s,%s,%s)",
                    (
                        int(f["id_equipo"]),
                        int(f["id_persona"]),
                        int(f["id_ubicacion"]),
                        f.get("observacion", "Asignación")
                    )
                )
            c.commit()
        flash("Equipo asignado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("admin_v") + "#v-asig")

@app.route("/admin/cerrar_asignacion/<int:id_asignacion>", methods=["POST"])
@login_required
@role_required("admin")
def admin_cerrar_asignacion(id_asignacion):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "CALL sp_cerrar_asignacion_equipo(%s,%s)",
                    (id_asignacion, request.form.get("observacion", "Cierre administrativo"))
                )
            c.commit()
        flash("Asignación cerrada.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("admin_v") + "#v-asig")

# CRUD movimientos
@app.route("/admin/movimiento/<int:id_movimiento>/eliminar", methods=["POST"])
@login_required
@role_required("admin")
def admin_eliminar_movimiento(id_movimiento):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("DELETE FROM movimiento WHERE id_movimiento=%s", (id_movimiento,))
            c.commit()
        flash("Movimiento eliminado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("admin_v") + "#v-movs")

# CRUD usuarios
@app.route("/admin/usuario/<int:id_usuario>/toggle", methods=["POST"])
@login_required
@role_required("admin")
def admin_toggle_usuario(id_usuario):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("UPDATE usuario SET activo = NOT activo WHERE id_usuario=%s", (id_usuario,))
            c.commit()
        flash("Estado de usuario actualizado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("admin_v") + "#v-usuarios")

# ═══════════════════════════════════════════════════════
# MÉDICO
# ═══════════════════════════════════════════════════════
@app.route("/medico")
@login_required
@role_required("medico", "admin")
def medico_v():
    ip = session["id_persona"]
    with get_db() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT p.nombre_persona,p.apellido_persona,em.especialidad_medico
                FROM medico m
                JOIN persona p ON p.id_persona = m.id_persona
                JOIN especialidades_medicos em ON em.id_especialidad_medico = m.id_especialidad_medico
                WHERE m.id_persona=%s
            """, (ip,))
            perfil = cur.fetchone()

            cur.execute("""
                SELECT e.id_equipo,e.codigo_interno,e.nombre_equipo,e.marca,
                       te.tipo_equipo,ue.nombre_ubicacion,ar.area
                FROM equipo e
                JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
                JOIN area_registro ar ON ar.id_area = ue.id_area
                WHERE ee.estado_equipo='Disponible'
                ORDER BY e.nombre_equipo
            """)
            disponibles = cur.fetchall()

            cur.execute("""
                SELECT ae.id_asignacion,e.nombre_equipo,e.codigo_interno,
                       ue.nombre_ubicacion,ae.fecha_asignacion,ae.observacion_asignacion
                FROM asignacion_equipo ae
                JOIN equipo e ON e.id_equipo = ae.id_equipo
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = ae.id_ubicacion
                WHERE ae.id_persona=%s AND ae.fecha_fin_asignacion IS NULL
                ORDER BY ae.fecha_asignacion DESC
            """, (ip,))
            mis_asignaciones = cur.fetchall()

            cur.execute("""
                SELECT u.id_uso_clinico,e.nombre_equipo,e.codigo_interno,u.fecha_uso
                FROM uso_clinico_equipo u
                JOIN equipo e ON e.id_equipo = u.id_equipo
                WHERE u.id_persona=%s
                ORDER BY u.fecha_uso DESC
            """, (ip,))
            mis_usos = cur.fetchall()

            # Reportes médico
            cur.execute("""
                SELECT e.nombre_equipo, COUNT(*) AS total_usos
                FROM uso_clinico_equipo u
                JOIN equipo e ON e.id_equipo = u.id_equipo
                WHERE u.id_persona=%s
                GROUP BY e.nombre_equipo
                ORDER BY total_usos DESC
            """, (ip,))
            rpt_mis_equipos_usados = cur.fetchall()

            cur.execute("""
                SELECT ee.estado_equipo, COUNT(*) AS total
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                GROUP BY ee.estado_equipo
                ORDER BY total DESC
            """)
            rpt_estados_globales = cur.fetchall()

            cur.execute("""
                SELECT te.tipo_equipo, COUNT(*) AS total,
                       COUNT(CASE WHEN ee.estado_equipo='Disponible' THEN 1 END) AS disponibles
                FROM equipo e
                JOIN tipo_equipos te ON te.id_tipo_equipo = e.id_tipo_equipo
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                GROUP BY te.tipo_equipo
                ORDER BY total DESC
            """)
            rpt_por_tipo = cur.fetchall()

            cur.execute("SELECT id_equipo,codigo_interno,nombre_equipo FROM equipo ORDER BY nombre_equipo")
            todos_equipos = cur.fetchall()

    return render_template(
        "medico.html",
        perfil=perfil, disponibles=disponibles, mis_asignaciones=mis_asignaciones,
        mis_usos=mis_usos, todos_equipos=todos_equipos,
        rpt_mis_equipos_usados=rpt_mis_equipos_usados,
        rpt_estados_globales=rpt_estados_globales, rpt_por_tipo=rpt_por_tipo
    )

@app.route("/medico/uso", methods=["POST"])
@login_required
@role_required("medico", "admin")
def medico_uso():
    id_eq = request.form.get("id_equipo", "").strip()
    if not id_eq:
        flash("Selecciona un equipo.", "error")
        return redirect(url_for("medico_v"))
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("CALL sp_registrar_uso_clinico(%s,%s)", (int(id_eq), session["id_persona"]))
            c.commit()
        flash("Uso clínico registrado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("medico_v"))

@app.route("/medico/uso/<int:id_uso>/eliminar", methods=["POST"])
@login_required
@role_required("medico", "admin")
def medico_eliminar_uso(id_uso):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "DELETE FROM uso_clinico_equipo WHERE id_uso_clinico=%s AND id_persona=%s",
                    (id_uso, session["id_persona"])
                )
            c.commit()
        flash("Registro de uso eliminado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("medico_v"))

# ═══════════════════════════════════════════════════════
# BIOMÉDICO
# ═══════════════════════════════════════════════════════
@app.route("/biomedico")
@login_required
@role_required("biomedico", "admin")
def biomedico_v():
    ip = session["id_persona"]
    with get_db() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT m.id_mantenimiento,e.nombre_equipo,e.codigo_interno,
                       tm.tipo_mantenimiento,trm.resultado_mantenimiento,
                       m.descripcion_mantenimiento,m.fecha_mantenimiento,
                       m.id_equipo,m.id_tipo_mantenimiento,m.id_resultado_mantenimiento
                FROM mantenimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_mantenimientos tm ON tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento
                JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = m.id_resultado_mantenimiento
                WHERE m.id_persona=%s
                ORDER BY m.fecha_mantenimiento DESC
            """, (ip,))
            mis_mants = cur.fetchall()

            cur.execute("""
                SELECT DISTINCT ON (e.id_equipo) e.id_equipo,e.nombre_equipo,e.codigo_interno,
                       ee.estado_equipo,trm.resultado_mantenimiento,m.fecha_mantenimiento
                FROM mantenimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = m.id_resultado_mantenimiento
                WHERE trm.resultado_mantenimiento IN('Fallido','Parcial','Requiere refacción','Reemplazo necesario')
                ORDER BY e.id_equipo, m.fecha_mantenimiento DESC
            """)
            criticos = cur.fetchall()

            cur.execute("""
                SELECT * FROM fn_reporte_carga_biomedica(
                    '2025-01-01'::timestamp,'2099-12-31'::timestamp)
                ORDER BY total_mantenimientos DESC
            """)
            carga = cur.fetchall()

            # Reportes biomédico
            cur.execute("""
                SELECT tm.tipo_mantenimiento, COUNT(*) AS total
                FROM mantenimiento m
                JOIN tipo_mantenimientos tm ON tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento
                GROUP BY tm.tipo_mantenimiento
                ORDER BY total DESC
            """)
            rpt_por_tipo_mant = cur.fetchall()

            cur.execute("""
                SELECT trm.resultado_mantenimiento, COUNT(*) AS total
                FROM mantenimiento m
                JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = m.id_resultado_mantenimiento
                GROUP BY trm.resultado_mantenimiento
                ORDER BY total DESC
            """)
            rpt_por_resultado = cur.fetchall()

            cur.execute("""
                SELECT e.nombre_equipo, COUNT(*) AS total_mants,
                       MAX(m.fecha_mantenimiento) AS ultimo_mant
                FROM mantenimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                GROUP BY e.id_equipo,e.nombre_equipo
                ORDER BY total_mants DESC
                LIMIT 10
            """)
            rpt_equipos_mas_mant = cur.fetchall()

            cur.execute("SELECT id_equipo,codigo_interno,nombre_equipo FROM equipo ORDER BY nombre_equipo")
            todos_equipos = cur.fetchall()

            cur.execute("SELECT id_tipo_mantenimiento,tipo_mantenimiento FROM tipo_mantenimientos ORDER BY tipo_mantenimiento")
            tipos_mant = cur.fetchall()

            cur.execute("""
                SELECT id_resultado_mantenimiento,resultado_mantenimiento
                FROM tipo_resultado_mantenimientos
                ORDER BY resultado_mantenimiento
            """)
            resultados = cur.fetchall()

    return render_template(
        "biomedico.html",
        mis_mants=mis_mants, criticos=criticos, carga=carga,
        todos_equipos=todos_equipos, tipos_mant=tipos_mant, resultados=resultados,
        rpt_por_tipo_mant=rpt_por_tipo_mant, rpt_por_resultado=rpt_por_resultado,
        rpt_equipos_mas_mant=rpt_equipos_mas_mant
    )

@app.route("/biomedico/mantenimiento", methods=["POST"])
@login_required
@role_required("biomedico", "admin")
def biomedico_mant():
    f = request.form
    if not all([f.get("id_equipo"), f.get("id_tipo"), f.get("descripcion"), f.get("id_resultado")]):
        flash("Completa todos los campos.", "error")
        return redirect(url_for("biomedico_v"))
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "CALL sp_registrar_mantenimiento(%s,%s,%s,%s,%s)",
                    (
                        int(f["id_equipo"]),
                        int(f["id_tipo"]),
                        f["descripcion"],
                        session["id_persona"],
                        int(f["id_resultado"])
                    )
                )
            c.commit()
        flash("Mantenimiento registrado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("biomedico_v"))

@app.route("/biomedico/mantenimiento/<int:id_mant>/editar", methods=["POST"])
@login_required
@role_required("biomedico", "admin")
def biomedico_editar_mant(id_mant):
    f = request.form
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("""
                    UPDATE mantenimiento
                    SET id_tipo_mantenimiento=%s,
                        descripcion_mantenimiento=%s,
                        id_resultado_mantenimiento=%s
                    WHERE id_mantenimiento=%s AND id_persona=%s
                """, (
                    int(f["id_tipo"]),
                    f["descripcion"],
                    int(f["id_resultado"]),
                    id_mant,
                    session["id_persona"]
                ))
            c.commit()
        flash("Mantenimiento actualizado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("biomedico_v"))

@app.route("/biomedico/mantenimiento/<int:id_mant>/eliminar", methods=["POST"])
@login_required
@role_required("biomedico", "admin")
def biomedico_eliminar_mant(id_mant):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "DELETE FROM mantenimiento WHERE id_mantenimiento=%s AND id_persona=%s",
                    (id_mant, session["id_persona"])
                )
            c.commit()
        flash("Mantenimiento eliminado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("biomedico_v"))

# ═══════════════════════════════════════════════════════
# ENFERMERO
# ═══════════════════════════════════════════════════════
@app.route("/enfermero")
@login_required
@role_required("enfermero", "admin")
def enfermero_v():
    ip = session["id_persona"]
    with get_db() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT e.nombre_equipo,e.codigo_interno,ee.estado_equipo,
                       ue.nombre_ubicacion,ar.area
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
                JOIN area_registro ar ON ar.id_area = ue.id_area
                ORDER BY ar.area,e.nombre_equipo
            """)
            equipos = cur.fetchall()

            cur.execute("""
                SELECT m.id_movimiento,e.nombre_equipo,tm.tipo_movimiento,
                       uo.nombre_ubicacion AS origen,ud.nombre_ubicacion AS destino,
                       m.fecha_movimiento,m.observacion_movimiento
                FROM movimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_movimientos tm ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                JOIN ubicacion_especifica uo ON uo.id_ubicacion = m.id_ubicacion_origen
                JOIN ubicacion_especifica ud ON ud.id_ubicacion = m.id_ubicacion_destino
                WHERE m.id_persona_responsable=%s
                ORDER BY m.fecha_movimiento DESC
            """, (ip,))
            mis_movs = cur.fetchall()

            cur.execute("""
                SELECT u.id_uso_clinico,e.nombre_equipo,e.codigo_interno,
                       p.nombre_persona||' '||p.apellido_persona AS persona,u.fecha_uso
                FROM uso_clinico_equipo u
                JOIN equipo e ON e.id_equipo = u.id_equipo
                JOIN persona p ON p.id_persona = u.id_persona
                ORDER BY u.fecha_uso DESC
                LIMIT 20
            """)
            historial_usos = cur.fetchall()

            # Reportes enfermero
            cur.execute("""
                SELECT ar.area, COUNT(m.id_movimiento) AS total_movs,
                       COUNT(DISTINCT e.id_equipo) AS equipos_activos
                FROM area_registro ar
                LEFT JOIN ubicacion_especifica ue ON ue.id_area = ar.id_area
                LEFT JOIN movimiento m ON m.id_ubicacion_destino = ue.id_ubicacion
                    OR m.id_ubicacion_origen = ue.id_ubicacion
                LEFT JOIN equipo e ON e.id_ubicacion = ue.id_ubicacion
                GROUP BY ar.id_area,ar.area
                ORDER BY total_movs DESC
            """)
            rpt_movs_area = cur.fetchall()

            cur.execute("""
                SELECT tm.tipo_movimiento, COUNT(*) AS total
                FROM movimiento m
                JOIN tipo_movimientos tm ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                GROUP BY tm.tipo_movimiento
                ORDER BY total DESC
            """)
            rpt_freq_tipo_mov = cur.fetchall()

            cur.execute("""
                SELECT ee.estado_equipo, COUNT(*) AS total
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                GROUP BY ee.estado_equipo
                ORDER BY total DESC
            """)
            rpt_estados = cur.fetchall()

            cur.execute("SELECT id_equipo,codigo_interno,nombre_equipo FROM equipo ORDER BY nombre_equipo")
            todos_equipos = cur.fetchall()

            cur.execute("SELECT id_tipo_movimiento,tipo_movimiento FROM tipo_movimientos ORDER BY tipo_movimiento")
            tipos_mov = cur.fetchall()

            cur.execute("SELECT id_ubicacion,nombre_ubicacion FROM ubicacion_especifica ORDER BY nombre_ubicacion")
            ubicaciones = cur.fetchall()

    return render_template(
        "enfermero.html",
        equipos=equipos, mis_movs=mis_movs, historial_usos=historial_usos,
        todos_equipos=todos_equipos, tipos_mov=tipos_mov, ubicaciones=ubicaciones,
        rpt_movs_area=rpt_movs_area, rpt_freq_tipo_mov=rpt_freq_tipo_mov, rpt_estados=rpt_estados
    )

@app.route("/enfermero/movimiento", methods=["POST"])
@login_required
@role_required("enfermero", "admin")
def enfermero_mov():
    f = request.form
    id_origen = f.get("id_ubicacion_origen", "").strip()
    id_destino = f.get("id_ubicacion_destino", "").strip()

    if not all([f.get("id_equipo"), f.get("id_tipo"), id_origen, id_destino]):
        flash("Completa todos los campos.", "error")
        return redirect(url_for("enfermero_v"))

    if id_origen == id_destino:
        flash("Origen y destino deben ser distintos.", "error")
        return redirect(url_for("enfermero_v"))

    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "CALL sp_registrar_movimiento_equipo(%s,%s,%s,%s,%s,%s)",
                    (
                        int(f["id_equipo"]),
                        int(f["id_tipo"]),
                        int(id_origen),
                        int(id_destino),
                        session["id_persona"],
                        f.get("observacion", "Movimiento registrado")
                    )
                )
            c.commit()
        flash("Movimiento registrado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("enfermero_v"))

@app.route("/enfermero/movimiento/<int:id_mov>/eliminar", methods=["POST"])
@login_required
@role_required("enfermero", "admin")
def enfermero_eliminar_mov(id_mov):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "DELETE FROM movimiento WHERE id_movimiento=%s AND id_persona_responsable=%s",
                    (id_mov, session["id_persona"])
                )
            c.commit()
        flash("Movimiento eliminado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("enfermero_v"))

@app.route("/enfermero/uso", methods=["POST"])
@login_required
@role_required("enfermero", "admin")
def enfermero_uso():
    id_eq = request.form.get("id_equipo", "").strip()
    if not id_eq:
        flash("Selecciona un equipo.", "error")
        return redirect(url_for("enfermero_v"))
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute("CALL sp_registrar_uso_clinico(%s,%s)", (int(id_eq), session["id_persona"]))
            c.commit()
        flash("Uso registrado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("enfermero_v"))

# ═══════════════════════════════════════════════════════
# RESPONSABLE
# ═══════════════════════════════════════════════════════
@app.route("/responsable")
@login_required
@role_required("responsable", "admin")
def responsable_v():
    ip = session["id_persona"]
    with get_db() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT ar.id_area,ar.area,ra.fecha_inicio
                FROM responsable_area ra
                JOIN enfermero en ON en.id_enfermero = ra.id_enfermero
                JOIN area_registro ar ON ar.id_area = ra.id_area
                WHERE en.id_persona=%s AND ra.fecha_fin IS NULL
                LIMIT 1
            """, (ip,))
            mi_area = cur.fetchone()
            id_area = mi_area["id_area"] if mi_area else -1

            cur.execute("""
                SELECT e.id_equipo,e.nombre_equipo,e.codigo_interno,e.marca,
                       ee.estado_equipo,ue.nombre_ubicacion,e.id_estado_equipo
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
                WHERE ue.id_area=%s
                ORDER BY e.nombre_equipo
            """, (id_area,))
            equipos_area = cur.fetchall()

            cur.execute("""
                SELECT ae.id_asignacion,e.nombre_equipo,e.codigo_interno,
                       p.nombre_persona||' '||p.apellido_persona AS asignado_a,
                       ue.nombre_ubicacion,ae.fecha_asignacion,ae.observacion_asignacion
                FROM asignacion_equipo ae
                JOIN equipo e ON e.id_equipo = ae.id_equipo
                JOIN persona p ON p.id_persona = ae.id_persona
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = ae.id_ubicacion
                WHERE ue.id_area=%s AND ae.fecha_fin_asignacion IS NULL
                ORDER BY ae.fecha_asignacion DESC
            """, (id_area,))
            asignaciones = cur.fetchall()

            cur.execute("""
                SELECT m.id_movimiento,e.nombre_equipo,tm.tipo_movimiento,
                       uo.nombre_ubicacion AS origen,ud.nombre_ubicacion AS destino,
                       p.nombre_persona||' '||p.apellido_persona AS responsable,
                       m.fecha_movimiento,m.observacion_movimiento
                FROM movimiento m
                JOIN equipo e ON e.id_equipo = m.id_equipo
                JOIN tipo_movimientos tm ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                JOIN ubicacion_especifica uo ON uo.id_ubicacion = m.id_ubicacion_origen
                JOIN ubicacion_especifica ud ON ud.id_ubicacion = m.id_ubicacion_destino
                JOIN persona p ON p.id_persona = m.id_persona_responsable
                WHERE uo.id_area=%s OR ud.id_area=%s
                ORDER BY m.fecha_movimiento DESC
            """, (id_area, id_area))
            movimientos = cur.fetchall()

            cur.execute("""
                SELECT ar.area,p.nombre_persona||' '||p.apellido_persona AS responsable,
                       ee.especialidad_enfermero,ra.fecha_inicio
                FROM responsable_area ra
                JOIN enfermero en ON en.id_enfermero = ra.id_enfermero
                JOIN persona p ON p.id_persona = en.id_persona
                JOIN especialidades_enfermeros ee ON ee.id_especialidad_enfermero = en.id_especialidad_enfermero
                JOIN area_registro ar ON ar.id_area = ra.id_area
                WHERE ra.fecha_fin IS NULL
                ORDER BY ar.area
            """)
            responsables_activos = cur.fetchall()

            cur.execute("""
                SELECT p.nombre_persona,p.apellido_persona,p.correo_persona,
                       ee.especialidad_enfermero
                FROM enfermero e
                JOIN persona p ON p.id_persona = e.id_persona
                JOIN especialidades_enfermeros ee ON ee.id_especialidad_enfermero = e.id_especialidad_enfermero
                ORDER BY p.apellido_persona
            """)
            personal = cur.fetchall()

            # Reportes responsable
            cur.execute("""
                SELECT ee.estado_equipo, COUNT(*) AS total
                FROM equipo e
                JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
                WHERE ue.id_area=%s
                GROUP BY ee.estado_equipo
                ORDER BY total DESC
            """, (id_area,))
            rpt_estados_area = cur.fetchall()

            cur.execute("""
                SELECT tm.tipo_movimiento, COUNT(*) AS total
                FROM movimiento m
                JOIN tipo_movimientos tm ON tm.id_tipo_movimiento = m.id_tipo_movimiento
                JOIN ubicacion_especifica uo ON uo.id_ubicacion = m.id_ubicacion_origen
                JOIN ubicacion_especifica ud ON ud.id_ubicacion = m.id_ubicacion_destino
                WHERE uo.id_area=%s OR ud.id_area=%s
                GROUP BY tm.tipo_movimiento
                ORDER BY total DESC
            """, (id_area, id_area))
            rpt_tipos_movs = cur.fetchall()

            cur.execute("""
                SELECT e.nombre_equipo,
                       COUNT(DISTINCT ae.id_asignacion) AS veces_asignado,
                       COUNT(DISTINCT u.id_uso_clinico) AS usos_clinicos
                FROM equipo e
                JOIN ubicacion_especifica ue ON ue.id_ubicacion = e.id_ubicacion
                LEFT JOIN asignacion_equipo ae ON ae.id_equipo = e.id_equipo
                LEFT JOIN uso_clinico_equipo u ON u.id_equipo = e.id_equipo
                WHERE ue.id_area=%s
                GROUP BY e.id_equipo,e.nombre_equipo
                ORDER BY usos_clinicos DESC
            """, (id_area,))
            rpt_actividad_equipos = cur.fetchall()

            cur.execute("SELECT id_estado_equipo,estado_equipo FROM estado_equipos ORDER BY estado_equipo")
            estados_cat = cur.fetchall()

    return render_template(
        "responsable.html",
        mi_area=mi_area, equipos_area=equipos_area,
        asignaciones=asignaciones, movimientos=movimientos,
        responsables_activos=responsables_activos, personal=personal,
        rpt_estados_area=rpt_estados_area, rpt_tipos_movs=rpt_tipos_movs,
        rpt_actividad_equipos=rpt_actividad_equipos, estados_cat=estados_cat
    )

@app.route("/responsable/equipo/<int:id_equipo>/estado", methods=["POST"])
@login_required
@role_required("responsable", "admin")
def responsable_cambiar_estado(id_equipo):
    nuevo_estado = request.form.get("id_estado_equipo", "").strip()
    if not nuevo_estado:
        flash("Selecciona un estado.", "error")
        return redirect(url_for("responsable_v"))
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "CALL sp_actualizar_estado_ubicacion_equipo(%s,%s,%s)",
                    (id_equipo, int(nuevo_estado), None)
                )
            c.commit()
        flash("Estado del equipo actualizado.", "success")
    except Exception:
        try:
            with get_db() as c:
                with c.cursor() as cur:
                    cur.execute(
                        "UPDATE equipo SET id_estado_equipo=%s WHERE id_equipo=%s",
                        (int(nuevo_estado), id_equipo)
                    )
                c.commit()
            flash("Estado actualizado.", "success")
        except Exception as e2:
            flash(f"Error: {e2}", "error")
    return redirect(url_for("responsable_v"))

@app.route("/responsable/asignacion/<int:id_asignacion>/liberar", methods=["POST"])
@login_required
@role_required("responsable", "admin")
def responsable_liberar_asignacion(id_asignacion):
    try:
        with get_db() as c:
            with c.cursor() as cur:
                cur.execute(
                    "CALL sp_cerrar_asignacion_equipo(%s,%s)",
                    (id_asignacion, "Liberado por responsable de área")
                )
            c.commit()
        flash("Asignación liberada.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("responsable_v"))

if __name__ == "__main__":
    app.run(debug=True, port=5000)