'use strict';

function toast(msg, ok = true) {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = msg;
  el.className = ok ? 'show ok' : 'show err';
  clearTimeout(el._t);
  el._t = setTimeout(() => { el.className = ''; }, 3400);
}

function goTo(viewId) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('act'));
  document.querySelectorAll('.sbn-item[data-view]').forEach(el => {
    el.classList.toggle('act', el.dataset.view === viewId);
  });

  const target = document.getElementById(viewId);
  if (target) {
    target.classList.add('act');
    window.scrollTo(0, 0);
  }
}

function openModal(id) {
  const m = document.getElementById(id);
  if (m) m.classList.add('open');
}

function closeModal(id) {
  const m = document.getElementById(id);
  if (m) m.classList.remove('open');
}

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

function togglePassword(btn) {
  const wrap = btn.closest('.pass-wrap');
  if (!wrap) return;

  const inp = wrap.querySelector('input');
  if (!inp) return;

  const isPass = inp.type === 'password';
  inp.type = isPass ? 'text' : 'password';
  btn.textContent = isPass ? 'HIDE' : 'SHOW';
}

async function doLogin() {
  const username = document.getElementById('inp-user')?.value.trim() || '';
  const password = document.getElementById('inp-pass')?.value.trim() || '';
  const msgEl = document.getElementById('login-msg');

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
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Verificando…';
  }

  try {
    const res = await fetch('/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });

    const data = await res.json();

    if (data.ok) {
      showMsg('Acceso correcto. Redirigiendo…', 'success');
      setTimeout(() => {
        window.location.href = data.redirect;
      }, 600);
    } else {
      showMsg(data.mensaje || 'Error al iniciar sesión.');
      if (btn) {
        btn.disabled = false;
        btn.textContent = 'Ingresar →';
      }
    }
  } catch (err) {
    showMsg('Error de conexión. Intenta de nuevo.');
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Ingresar →';
    }
  }
}

function confirmarLiberar(formId) {
  if (confirm('¿Confirmas liberar esta asignación?')) {
    document.getElementById(formId)?.submit();
  }
}

function filtrarTabla(inputId, tbodySelector) {
  const inp = document.getElementById(inputId);
  const tbody = document.querySelector(tbodySelector);
  if (!inp || !tbody) return;

  inp.addEventListener('input', () => {
    const q = inp.value.toLowerCase();
    tbody.querySelectorAll('tr').forEach(tr => {
      tr.style.display = tr.textContent.toLowerCase().includes(q) ? '' : 'none';
    });
  });
}

async function loadPublicTable() {
  const tbody = document.getElementById('pub-table-body');
  const count = document.getElementById('pub-count');

  if (!tbody) return;

  const q = document.getElementById('pub-q')?.value.trim() || '';
  const tipo = document.getElementById('pub-tipo')?.value || '';
  const area = document.getElementById('pub-area')?.value || '';
  const estado = document.getElementById('pub-estado')?.value || '';

  const params = new URLSearchParams({ q, tipo, area, estado });

  tbody.innerHTML = `
    <tr>
      <td colspan="7" class="empty">Consultando equipos…</td>
    </tr>
  `;

  try {
    const res = await fetch(`/api/public/equipos?${params.toString()}`);
    const data = await res.json();

    if (!data.ok) {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" class="empty">No se pudo cargar la tabla.</td>
        </tr>
      `;
      return;
    }

    const rows = data.data || [];
    if (count) {
      count.textContent = `${rows.length} resultados`;
    }

    if (!rows.length) {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" class="empty">No hay equipos con esos filtros.</td>
        </tr>
      `;
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
  } catch (e) {
    tbody.innerHTML = `
      <tr>
        <td colspan="7" class="empty">Error de conexión.</td>
      </tr>
    `;
  }
}

function resetPublicFilters() {
  ['pub-q', 'pub-tipo', 'pub-area', 'pub-estado'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  loadPublicTable();
}

function badgeClass(estado) {
  const map = {
    'Disponible': 'badge b-green',
    'En uso': 'badge b-teal',
    'En mantenimiento': 'badge b-amber',
    'Fuera de servicio': 'badge b-red',
    'Reservado': 'badge b-blue',
    'En traslado': 'badge b-blue',
    'Dañado': 'badge b-red',
    'Calibración': 'badge b-amber',
    'Limpieza': 'badge b-amber',
    'Inactivo': 'badge b-gray'
  };
  return map[estado] || 'badge b-gray';
}

function escapeHtml(v) {
  return String(v)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

document.addEventListener('DOMContentLoaded', () => {
  ['inp-user', 'inp-pass'].forEach(id => {
    const el = document.getElementById(id);
    if (el) {
      el.addEventListener('keydown', e => {
        if (e.key === 'Enter') doLogin();
      });
    }
  });

  const firstView = document.querySelector('.view');
  if (firstView && !document.querySelector('.view.act')) {
    firstView.classList.add('act');
    const firstNav = document.querySelector('.sbn-item[data-view]');
    if (firstNav) firstNav.classList.add('act');
  }

  setTimeout(() => {
    document.querySelectorAll('.flash-msg').forEach(el => {
      el.style.transition = 'opacity .4s';
      el.style.opacity = '0';
      setTimeout(() => el.remove(), 400);
    });
  }, 5000);

  ['pub-q', 'pub-tipo', 'pub-area', 'pub-estado'].forEach(id => {
    const el = document.getElementById(id);
    if (el) {
      const evt = id === 'pub-q' ? 'input' : 'change';
      el.addEventListener(evt, () => loadPublicTable());
    }
  });
});