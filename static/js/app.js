'use strict';

/* ═══════════════════════════════════════════════════════════════════
   HospitalIoT · app.js — Shared Core
   Retrocompatible con: admin, admin_iot, medico, enfermero, biomedico
   ═══════════════════════════════════════════════════════════════════ */

/* NAMESPACE GLOBAL — toda lógica nueva vive aquí */
window.HospitalIoT = window.HospitalIoT || {};

/* TOAST */
function toast(msg, ok = true) {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = msg;
  el.className = ok ? 'show ok' : 'show err';
  clearTimeout(el._t);
  el._t = setTimeout(() => { el.className = ''; }, 3400);
}

/* NAVEGACIÓN INTERNA (SPA por hash)
   Solo actúa sobre vistas .view dentro de la misma página.
   No interfiere con <a href="..."> que van a rutas Flask reales. */
function goTo(viewId) {
  document.querySelectorAll('.view').forEach(v => {
    v.classList.remove('act');
    v.classList.remove('active'); // compat con admin.html que usa 'active'
  });

  // Highlight sidebar: solo items con data-view (navegación interna)
  document.querySelectorAll('.sbn-item[data-view]').forEach(el => {
    el.classList.toggle('act', el.dataset.view === viewId);
  });

  const target = document.getElementById(viewId);
  if (target) {
    target.classList.add('act');
    target.classList.add('active');
    // Persiste el hash para recargas y back-button del browser
    history.replaceState(null, '', '#' + viewId);
    window.scrollTo(0, 0);
  }
}

/* SIDEBAR — detección de ruta activa para navegación real (Flask)
   Lee el pathname actual y marca el <a class="sbn-item"> cuyo href
   coincide, sin tocar los botones de navegación interna. */
HospitalIoT.sidebar = {
  /** Marca como activo el enlace del sidebar cuya href coincide con
   *  la ruta actual. Soporta coincidencia exacta y por prefijo. */
  highlightActive() {
    const currentPath = window.location.pathname;
    document.querySelectorAll('.sbn-item[href]').forEach(el => {
      const linkPath = new URL(el.href, window.location.origin).pathname;
      const isActive = linkPath === currentPath;
      el.classList.toggle('act', isActive);
      el.classList.toggle('active', isActive);
    });
  }
};

/* MODALES */
function openModal(id) {
  const m = document.getElementById(id);
  if (m) m.classList.add('open');
}

function closeModal(id) {
  const m = document.getElementById(id);
  if (m) m.classList.remove('open');
}

/* Delegación: cierre por clic en fondo o Escape */
document.addEventListener('click', e => {
  if (e.target.classList.contains('modal-bg')) {
    e.target.classList.remove('open');
  }
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    document.querySelectorAll('.modal-bg.open').forEach(m => m.classList.remove('open'));
  }
});

/* DELEGACIÓN DE EVENTOS — sidebar (clicks en navegación interna)
   Escucha sobre el sidebar y despacha goTo solo para botones con
   data-view. Los <a href> reales no se interceptan. */
document.addEventListener('click', e => {
  const btn = e.target.closest('.sbn-item[data-view]');
  if (!btn) return;
  e.preventDefault();
  goTo(btn.dataset.view);
});

/* TOGGLE CONTRASEÑA */
function togglePassword(btn) {
  const wrap = btn.closest('.pass-wrap');
  if (!wrap) return;
  const inp = wrap.querySelector('input');
  if (!inp) return;
  const isPass = inp.type === 'password';
  inp.type = isPass ? 'text' : 'password';
  btn.textContent = isPass ? 'HIDE' : 'SHOW';
}

/* LOGIN */
async function doLogin() {
  const username = document.getElementById('inp-user')?.value.trim() || '';
  const password = document.getElementById('inp-pass')?.value.trim() || '';
  const msgEl    = document.getElementById('login-msg');

  function showMsg(text, type = 'error') {
    if (!msgEl) return;
    msgEl.textContent = text;
    msgEl.className = `login-msg show ${type}`;
  }

  if (!username || !password) {
    showMsg('Ingresa tu usuario y contraseña.');
    return;
  }

  const btn = document.querySelector('.btn-login');
  if (btn) { btn.disabled = true; btn.textContent = 'Verificando…'; }

  try {
    const res  = await fetch('/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    const data = await res.json();

    if (data.ok) {
      showMsg('Acceso correcto. Redirigiendo…', 'success');
      setTimeout(() => { window.location.href = data.redirect; }, 600);
    } else {
      showMsg(data.mensaje || 'Error al iniciar sesión.');
      if (btn) { btn.disabled = false; btn.textContent = 'Ingresar →'; }
    }
  } catch {
    showMsg('Error de conexión. Intenta de nuevo.');
    if (btn) { btn.disabled = false; btn.textContent = 'Ingresar →'; }
  }
}

/* TABLA — filtro en tiempo real
   Firma retrocompatible: acepta (inputId, tbodySelector) original
   Y la forma inline: filtrarTabla(inputElement, tableId) de admin.html */
function filtrarTabla(inputOrId, selectorOrId) {
  // Forma inline: primer arg es un HTMLInputElement (admin.html)
  if (inputOrId instanceof HTMLElement) {
    const q     = inputOrId.value.toLowerCase();
    const tbody = document.querySelector('#' + selectorOrId + ' tbody') ||
                  document.getElementById(selectorOrId);
    if (!tbody) return;
    tbody.querySelectorAll('tr').forEach(tr => {
      tr.style.display = tr.textContent.toLowerCase().includes(q) ? '' : 'none';
    });
    return;
  }

  // Forma original: ambos son strings (ids)
  const inp   = document.getElementById(inputOrId);
  const tbody = document.querySelector(selectorOrId);
  if (!inp || !tbody) return;

  inp.addEventListener('input', () => {
    const q = inp.value.toLowerCase();
    tbody.querySelectorAll('tr').forEach(tr => {
      tr.style.display = tr.textContent.toLowerCase().includes(q) ? '' : 'none';
    });
  });
}

/* CONFIRMAR LIBERAR ASIGNACIÓN (clínico) */
function confirmarLiberar(formId) {
  if (confirm('¿Confirmas liberar esta asignación?')) {
    document.getElementById(formId)?.submit();
  }
}

/* TABLA PÚBLICA DE EQUIPOS */
async function loadPublicTable() {
  const tbody = document.getElementById('pub-table-body');
  const count = document.getElementById('pub-count');
  if (!tbody) return;

  const q      = document.getElementById('pub-q')?.value.trim() || '';
  const tipo   = document.getElementById('pub-tipo')?.value || '';
  const area   = document.getElementById('pub-area')?.value || '';
  const estado = document.getElementById('pub-estado')?.value || '';
  const params = new URLSearchParams({ q, tipo, area, estado });

  tbody.innerHTML = `<tr><td colspan="7" class="empty">Consultando equipos…</td></tr>`;

  try {
    const res  = await fetch(`/api/public/equipos?${params.toString()}`);
    const data = await res.json();

    if (!data.ok) {
      tbody.innerHTML = `<tr><td colspan="7" class="empty">No se pudo cargar la tabla.</td></tr>`;
      return;
    }

    const rows = data.data || [];
    if (count) count.textContent = `${rows.length} resultados`;

    if (!rows.length) {
      tbody.innerHTML = `<tr><td colspan="7" class="empty">No hay equipos con esos filtros.</td></tr>`;
      return;
    }

    tbody.innerHTML = rows.map(r => `
      <tr>
        <td><span class="cod">${escapeHtml(r.codigo_interno || '')}</span></td>
        <td><strong>${escapeHtml(r.nombre_equipo || '')}</strong></td>
        <td>${escapeHtml((r.marca || '-') + ' / ' + (r.modelo || '-'))}</td>
        <td>${escapeHtml(r.tipo_equipo || '-')}</td>
        <td>${escapeHtml(r.area || '-')}</td>
        <td>${escapeHtml(r.nombre_ubicacion || '-')}</td>
        <td><span class="${badgeClass(r.estado_equipo)}">${escapeHtml(r.estado_equipo || '-')}</span></td>
      </tr>
    `).join('');
  } catch {
    tbody.innerHTML = `<tr><td colspan="7" class="empty">Error de conexión.</td></tr>`;
  }
}

function resetPublicFilters() {
  ['pub-q', 'pub-tipo', 'pub-area', 'pub-estado'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  loadPublicTable();
}

/* UTILIDADES COMPARTIDAS */
function badgeClass(estado) {
  const map = {
    'Disponible':       'badge b-green',
    'En uso':           'badge b-teal',
    'En mantenimiento': 'badge b-amber',
    'Fuera de servicio':'badge b-red',
    'Retirado':         'badge b-gray',
    'En préstamo':      'badge b-purple',
    'Calibración':      'badge b-amber',
    'Limpieza':         'badge b-amber',
    'Inactivo':         'badge b-gray',
  };
  return map[estado] || 'badge b-gray';
}

function escapeHtml(v) {
  return String(v)
    .replaceAll('&',  '&amp;')
    .replaceAll('<',  '&lt;')
    .replaceAll('>',  '&gt;')
    .replaceAll('"',  '&quot;')
    .replaceAll("'",  '&#039;');
}

/* IoT — Polling (solo se activa si el contenedor existe en el DOM)
   Toda la lógica queda bajo HospitalIoT.admin para evitar colisiones. */
HospitalIoT.admin = {
  _pollInterval: null,

  /** Refresca los KPI de la página IoT sin hacer nada si no existe */
  async refresh() {
    const container = document.getElementById('iot-panel-root');
    if (!container) return; // No estamos en admin_iot → salir silenciosamente

    const urlEl = document.getElementById('iot-refresh-url');
    const url   = urlEl?.dataset?.url;
    if (!url) return;

    try {
      const res  = await fetch(url);
      const data = await res.json();
      if (!data.ok) return;

      const kpiDisc = container.querySelector('.iot-kpi:first-child .kpi-val');
      if (kpiDisc) {
        kpiDisc.textContent = data.total_alertas;
        kpiDisc.className   = 'kpi-val ' + (data.total_alertas > 0 ? 'kpi-red' : 'kpi-green');
      }

      const kpiSin = container.querySelector('.iot-kpi:nth-child(2) .kpi-val');
      if (kpiSin) {
        kpiSin.textContent = data.sin_evidencia?.length ?? 0;
        kpiSin.className   = 'kpi-val ' + ((data.sin_evidencia?.length ?? 0) > 0 ? 'kpi-amber' : 'kpi-green');
      }

      const ts = document.getElementById('last-refresh');
      if (ts) ts.textContent = 'Actualizado ' + new Date().toLocaleTimeString('es-MX');
    } catch (e) {
      console.error('[HospitalIoT.admin.refresh]', e);
    }
  },

  /** Inicia el polling cada 60 s; solo si el panel IoT existe */
  startPolling(intervalMs = 60_000) {
    if (!document.getElementById('iot-panel-root')) return;
    this._pollInterval = setInterval(() => this.refresh(), intervalMs);
  },

  stopPolling() {
    clearInterval(this._pollInterval);
  }
};

/* Alias global para el botón "↻ Actualizar" existente en admin_iot.html */
function refreshIoT() {
  HospitalIoT.admin.refresh();
}

/* DOMContentLoaded — inicialización */
document.addEventListener('DOMContentLoaded', () => {

  /* 1. Highlight de ruta activa en sidebar (para páginas Flask reales) */
  HospitalIoT.sidebar.highlightActive();

  /* 2. Navegación interna por hash (admin.html SPA) */
  const hash = location.hash.replace('#', '');
  if (hash && document.getElementById(hash)) {
    goTo(hash);
  } else {
    const firstView = document.querySelector('.view');
    if (firstView && !document.querySelector('.view.act, .view.active')) {
      const id = firstView.id;
      if (id) goTo(id);
      else {
        firstView.classList.add('act', 'active');
        const firstNav = document.querySelector('.sbn-item[data-view]');
        if (firstNav) firstNav.classList.add('act');
      }
    }
  }

  /* 3. Enter en login */
  ['inp-user', 'inp-pass'].forEach(id => {
    document.getElementById(id)
      ?.addEventListener('keydown', e => { if (e.key === 'Enter') doLogin(); });
  });

  /* 4. Auto-dismiss flash messages */
  setTimeout(() => {
    document.querySelectorAll('.flash-msg').forEach(el => {
      el.style.transition = 'opacity .4s';
      el.style.opacity    = '0';
      setTimeout(() => el.remove(), 400);
    });
  }, 5000);

  /* 5. Filtros de tabla pública */
  ['pub-q', 'pub-tipo', 'pub-area', 'pub-estado'].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.addEventListener(id === 'pub-q' ? 'input' : 'change', loadPublicTable);
  });

  /* 6. IoT polling — solo arranca si el panel existe en el DOM */
  HospitalIoT.admin.startPolling();
});

function toggleInactivos(mostrar) {
  document.querySelectorAll('#tb-equipos tr[data-inactivo="1"]').forEach(row => {
    row.style.display = mostrar ? '' : 'none';
  });
}
