/* ISP CONFIG — panel del servidor (vanilla JS, sin dependencias) */
'use strict';

// Soporta instalar el servidor en subcarpeta: siempre contra la raíz de la API.
const BASE = new URL('../', location.href);
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

const state = { zones: [], nodes: [], aps: [], fw: [], tec: [], dev: [], stats: {} };

// ---------- API ----------

async function api(method, path, data) {
  const url = new URL(String(path).replace(/^\//, ''), BASE);
  const r = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  let j = null;
  try { j = await r.json(); } catch (_) { /* respuesta sin JSON */ }
  if (!r.ok) {
    const err = new Error((j && j.error) || 'HTTP ' + r.status);
    err.status = r.status;
    throw err;
  }
  return j;
}

function toast(msg, tipo) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'show' + (tipo ? ' ' + tipo : '');
  clearTimeout(toast._h);
  toast._h = setTimeout(() => { t.className = ''; }, 3500);
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// ---------- sesión ----------

async function checkSession() {
  const s = await api('GET', 'session');
  if (s.logged) {
    $('#login').hidden = true;
    $('#app').hidden = false;
    await cargarTodo();
  } else {
    $('#login').hidden = false;
    $('#app').hidden = true;
  }
}

$('#login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = new FormData(e.target);
  try {
    await api('POST', 'session', { user: f.get('user'), pass: f.get('pass') });
    await checkSession();
    toast('Bienvenido', 'ok');
  } catch (err) {
    toast(err.message, 'err');
  }
});

$('#logout').addEventListener('click', async () => {
  await api('DELETE', 'session').catch(() => {});
  location.reload();
});

// ---------- pestañas ----------

$$('#tabs button').forEach((b) => b.addEventListener('click', () => {
  $$('#tabs button').forEach((x) => x.classList.toggle('on', x === b));
  $$('main > section').forEach((s) => { s.hidden = s.id !== 'tab-' + b.dataset.tab; });
}));

// ---------- carga ----------

async function cargarTodo() {
  try {
    const [zones, nodes, aps, fw, tec, dev, stats] = await Promise.all([
      api('GET', 'zones'),
      api('GET', 'nodes'),
      api('GET', 'aps'),
      api('GET', 'firmware'),
      api('GET', 'tecnicos'),
      api('GET', 'dispositivos'),
      api('GET', 'stats'),
    ]);
    state.zones = zones; state.nodes = nodes; state.aps = aps;
    state.fw = fw; state.tec = tec; state.dev = dev; state.stats = stats;
    renderAll();
  } catch (err) {
    toast('Error cargando: ' + err.message, 'err');
    if (err.status === 401) { $('#app').hidden = true; $('#login').hidden = false; }
  }
}

function renderAll() {
  renderStats();
  renderZones();
  renderNodes();
  renderAps();
  renderFw();
  renderTec();
  renderDev();
  fillZoneSelects();
}

function renderStats() {
  const s = state.stats;
  $('#stats-box').innerHTML = [
    ['zonas', s.zonas], ['APs', s.aps], ['nodos', s.nodes],
    ['firmware', s.firmware], ['técnicos', s.tecnicos],
    ['IPs activas', s.tecnicos_activos], ['dispositivos APK', s.dispositivos],
  ].map(([k, v]) => `<div class="stat"><b>${Number(v) || 0}</b><span>${k}</span></div>`).join('');
}

function fillZoneSelects() {
  const opts = state.zones.map((z) =>
    `<option value="${esc(z.id)}">${esc(z.zona)} (${esc(z.network)})</option>`).join('');
  $('#nodes-zona').innerHTML = opts;
  $('#aps-zona').innerHTML = opts;
  const actual = $('#aps-filter').value;
  $('#aps-filter').innerHTML = '<option value="">Todas las zonas</option>' + opts;
  $('#aps-filter').value = actual;
}

// ---------- helpers de formulario ----------

function formEdit(id, data) {
  const f = document.getElementById(id);
  f.elements.id.value = data.id ?? '';
  for (const [k, v] of Object.entries(data)) {
    const el = f.elements[k];
    if (!el) continue;
    if (el.type === 'checkbox') el.checked = !!v && v !== '0';
    else el.value = v ?? '';
  }
  f.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function formReset(id) {
  const f = document.getElementById(id);
  f.reset();
  f.elements.id.value = '';
}

$$('[data-reset]').forEach((b) =>
  b.addEventListener('click', () => formReset(b.dataset.reset)));

function onForm(id, endpoint, render) {
  document.getElementById(id).addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = e.target;
    const fd = new FormData(f);
    const data = Object.fromEntries(fd.entries());
    if (data.id) data.id = parseInt(data.id, 10);
    if (fd.get('activo') !== null) data.activo = fd.get('activo') === 'on' ? 1 : 0;
    try {
      await api(data.id ? 'PUT' : 'POST', endpoint, data);
      formReset(id);
      toast('Guardado ✓', 'ok');
      await cargarTodo();
      render();
    } catch (err) {
      toast(err.message, 'err');
    }
  });
}

async function borrar(endpoint, id, que) {
  if (!confirm('¿Borrar ' + que + '?')) return;
  // ids numéricos van como número; el resto (ej. id de dispositivo) como texto.
  const param = /^\d+$/.test(String(id)) ? parseInt(id, 10) : String(id);
  try {
    await api('DELETE', endpoint + '?id=' + encodeURIComponent(param));
    toast('Borrado ✓', 'ok');
    await cargarTodo();
  } catch (err) {
    toast(err.message, 'err');
  }
}

const acciones = (endpoint, id, que) => `
  <button class="mini" data-edit="${endpoint}|${id}">Editar</button>
  <button class="mini" data-del="${endpoint}|${id}|${esc(que)}">Borrar</button>`;

document.addEventListener('click', async (e) => {
  const b = e.target.closest('[data-edit],[data-del]');
  if (!b) return;
  if (b.dataset.edit) {
    const [ep, id] = b.dataset.edit.split('|');
    const list = {
      nodes: state.nodes, aps: state.aps, zones: state.zones,
      firmware: state.fw, tecnicos: state.tec,
    }[ep] || [];
    const row = list.find((x) => String(x.id) === id);
    if (!row) return;
    const forms = {
      nodes: 'f-nodes', aps: 'f-aps', zones: 'f-zones',
      firmware: 'f-fw', tecnicos: 'f-tec',
    };
    formEdit(forms[ep], row);
  } else {
    const [ep, id, que] = b.dataset.del.split('|');
    await borrar(ep, parseInt(id, 10), que);
  }
});

// ---------- nodos ----------

function renderNodes() {
  const q = ($('#nodes-q').value || '').toLowerCase();
  const list = state.nodes.filter((n) =>
    !q || n.nombre.toLowerCase().includes(q) || (n.zona || '').toLowerCase().includes(q));
  $('#nodes-count').textContent = list.length + ' de ' + state.nodes.length;
  $('#t-nodes tbody').innerHTML = list.map((n) => `<tr>
    <td>${esc(n.nombre)}</td>
    <td class="mono">${Number(n.lat).toFixed(5)}</td>
    <td class="mono">${Number(n.lng).toFixed(5)}</td>
    <td>${n.alt != null ? esc(n.alt) : ''}</td>
    <td>${esc(n.zona)}</td>
    <td class="muted">${esc(n.notas)}</td>
    <td>${acciones('nodes', n.id, 'el nodo ' + n.nombre)}</td></tr>`).join('')
    || '<tr><td colspan="7" class="muted">Sin nodos todavía.</td></tr>';
}
$('#nodes-q').addEventListener('input', renderNodes);
onForm('f-nodes', 'nodes', renderNodes);

// ---------- APs ----------

function renderAps() {
  const z = $('#aps-filter').value;
  const list = state.aps.filter((a) => !z || String(a.idzona) === z);
  $('#aps-count').textContent = list.length + ' de ' + state.aps.length;
  const zname = (id) => {
    const zz = state.zones.find((x) => String(x.id) === String(id));
    return zz ? zz.zona + ' (' + zz.network + ')' : '#' + id;
  };
  $('#t-aps tbody').innerHTML = list.map((a) => `<tr>
    <td>${esc(zname(a.idzona))}</td>
    <td>${a.idnodo ?? ''}</td>
    <td>${esc(a.nodo)}</td>
    <td class="mono">${esc(a.ssid)}</td>
    <td>${acciones('aps', a.id, 'la AP ' + a.ssid)}</td></tr>`).join('')
    || '<tr><td colspan="5" class="muted">Sin APs todavía.</td></tr>';
}
$('#aps-filter').addEventListener('change', renderAps);
onForm('f-aps', 'aps', renderAps);

// ---------- zonas ----------

function ipEquipo(network) {
  const n = String(network || '').replace(/\.$/, '');
  return n ? n + '.50' : '';
}

function renderZones() {
  $('#t-zones tbody').innerHTML = state.zones.map((z) => `<tr>
    <td>${z.id}</td>
    <td>${esc(z.zona)}</td>
    <td class="mono">${esc(z.network)}</td>
    <td class="mono">${esc(ipEquipo(z.network))}</td>
    <td>${acciones('zones', z.id, 'la zona ' + z.zona)}</td></tr>`).join('')
    || '<tr><td colspan="5" class="muted">Sin zonas.</td></tr>';
}
onForm('f-zones', 'zones', renderZones);

// ---------- firmware ----------

function renderFw() {
  $('#t-fw tbody').innerHTML = state.fw.map((f) => `<tr>
    <td>${esc(f.modelo)}</td>
    <td class="mono">${esc(f.version)}</td>
    <td class="muted">${esc(f.notas)}</td>
    <td class="muted">${esc(f.creado || '')}</td>
    <td>${acciones('firmware', f.id, 'el firmware de ' + f.modelo)}</td></tr>`).join('')
    || '<tr><td colspan="5" class="muted">Sin registros.</td></tr>';
}
onForm('f-fw', 'firmware', renderFw);

// ---------- técnicos / IPs ----------

function renderTec() {
  $('#tec-count').textContent = state.tec.length + ' registrados';
  $('#t-tec tbody').innerHTML = state.tec.map((t) => `<tr>
    <td class="ip">${esc(t.ip)}</td>
    <td>${esc(t.nombre)}</td>
    <td><span class="badge ${t.activo ? 'on' : 'off'}">${t.activo ? 'activo' : 'inactivo'}</span></td>
    <td class="muted">${esc(t.notas)}</td>
    <td>${acciones('tecnicos', t.id, 'a ' + t.nombre)}</td></tr>`).join('')
    || '<tr><td colspan="5" class="muted">Ningún técnico con IP asignada.</td></tr>';
}
onForm('f-tec', 'tecnicos', renderTec);

// Buscador: si escribes una IP, dice de inmediato quién la tiene (o si está libre).
let tecQ = null;
$('#tec-q').addEventListener('input', async (e) => {
  clearTimeout(tecQ);
  const q = e.target.value.trim();
  tecQ = setTimeout(async () => {
    if (!q) { renderTec(); return; }
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(q)) {
      try {
        const r = await api('GET', 'tecnicos?ip=' + encodeURIComponent(q));
        if (r.length === 0) {
          $('#tec-count').innerHTML = `<span class="badge libre">${esc(q)} está LIBRE</span>`;
          $('#t-tec tbody').innerHTML =
            '<tr><td colspan="5" class="muted">Esa IP no está asignada a nadie.</td></tr>';
          return;
        }
        $('#tec-count').innerHTML =
          `<span class="badge on">${esc(q)} → ${esc(r[0].nombre)}</span>`;
        state.tec = r;
        renderTec();
        return;
      } catch (_) { /* cae al filtro local */ }
    }
    const ql = q.toLowerCase();
    const list = state.tec.filter((t) =>
      t.nombre.toLowerCase().includes(ql) || t.ip.includes(ql) ||
      (t.notas || '').toLowerCase().includes(ql));
    $('#tec-count').textContent = list.length + ' coincidencias';
    const bak = state.tec;
    state.tec = list;
    renderTec();
    state.tec = bak;
  }, 250);
});

// ---------- dispositivos con la APK ----------

function renderDev() {
  const q = ($('#dev-q').value || '').toLowerCase();
  const list = state.dev.filter((d) =>
    !q || (d.modelo || '').toLowerCase().includes(q) ||
    (d.ip || '').includes(q) || (d.id || '').toLowerCase().includes(q) ||
    (d.tecnico || '').toLowerCase().includes(q));
  $('#dev-count').textContent = list.length + ' de ' + state.dev.length;
  const tecOpts = (actual) =>
    '<option value="">— sin asignar —</option>' +
    state.tec.map((t) =>
      `<option value="${esc(t.nombre)}"${t.nombre === actual ? ' selected' : ''}>` +
      `${esc(t.nombre)} (${esc(t.ip)})</option>`).join('');
  $('#t-dev tbody').innerHTML = list.map((d) => `<tr>
    <td><b>${esc(d.modelo || 'sin modelo')}</b>
        <span class="muted">${esc(d.so)}</span><br>
        <span class="muted mono">${esc(String(d.id).slice(0, 12))}</span></td>
    <td class="mono">${esc(d.version_apk || '—')}</td>
    <td class="mono">${esc(d.ip || '—')}</td>
    <td class="muted">${esc(d.ultimo_visto || '')}</td>
    <td><select data-dev="${esc(d.id)}">${tecOpts(d.tecnico)}</select></td>
    <td><button class="mini" data-del="dispositivos|${esc(d.id)}|este dispositivo">Borrar</button></td>
  </tr>`).join('')
    || '<tr><td colspan="6" class="muted">Ningún dispositivo ha sincronizado todavía.</td></tr>';
}
$('#dev-q').addEventListener('input', renderDev);

// Asignar el técnico (y su IP) a cada dispositivo con la APK.
document.addEventListener('change', async (e) => {
  const sel = e.target.closest('select[data-dev]');
  if (!sel) return;
  try {
    await api('PUT', 'dispositivos', { id: sel.dataset.dev, tecnico: sel.value });
    const d = state.dev.find((x) => x.id === sel.dataset.dev);
    if (d) d.tecnico = sel.value;
    toast(sel.value ? 'Asignado a ' + sel.value : 'Técnico quitado', 'ok');
  } catch (err) {
    toast(err.message, 'err');
    renderDev();
  }
});

// ---------- contraseña ----------

$('#f-pass').addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  try {
    await api('POST', 'password', { actual: fd.get('actual'), nueva: fd.get('nueva') });
    e.target.reset();
    toast('Contraseña cambiada ✓', 'ok');
  } catch (err) {
    toast(err.message, 'err');
  }
});

// ---------- arranque ----------

checkSession().catch((e) => toast('No pude conectar con la API: ' + e.message, 'err'));
