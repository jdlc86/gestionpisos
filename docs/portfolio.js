const views = {
  owners: {
    title: 'Propietarios',
    action: 'Añadir propietario',
    emptyTitle: 'No hay propietarios en este estado',
    emptyText: 'Las altas aparecerán aquí y conservarán la relación con sus pisos.',
    singular: 'propietario',
    statuses: ['active', 'blocked', 'archived'],
    fields: [
      { key: 'fullName', label: 'Nombre completo', type: 'text', required: true },
      { key: 'email', label: 'Email', type: 'email' },
      { key: 'phone', label: 'Teléfono', type: 'tel' }
    ]
  },
  properties: {
    title: 'Pisos',
    action: 'Añadir piso',
    emptyTitle: 'No hay pisos en este estado',
    emptyText: 'Cada piso debe permanecer asociado a un propietario.',
    singular: 'piso',
    statuses: ['onboarding', 'active', 'maintenance', 'blocked', 'offboarding', 'archived'],
    fields: [
      { key: 'ownerId', label: 'Propietario', type: 'relation', relation: 'owners', required: true },
      { key: 'name', label: 'Nombre interno', type: 'text', required: true },
      { key: 'address', label: 'Dirección', type: 'text', required: true },
      { key: 'city', label: 'Ciudad', type: 'text' },
      { key: 'postalCode', label: 'Código postal', type: 'text' }
    ]
  },
  rooms: {
    title: 'Habitaciones',
    action: 'Añadir habitación',
    emptyTitle: 'No hay habitaciones en este estado',
    emptyText: 'Cada habitación debe permanecer asociada a un piso.',
    singular: 'habitación',
    statuses: ['active', 'blocked', 'archived'],
    fields: [
      { key: 'propertyId', label: 'Piso', type: 'relation', relation: 'properties', required: true },
      { key: 'label', label: 'Etiqueta', type: 'text', required: true },
      { key: 'description', label: 'Descripción', type: 'textarea' }
    ]
  }
};

const state = {
  owners: [
    {
      id: 'owner-demo-1',
      fullName: 'Lucía Martín · ejemplo',
      email: 'lucia@example.invalid',
      phone: '+34 600 000 001',
      status: 'active',
      history: [{ label: 'Alta de demostración', at: '2026-09-13T18:00:00.000Z' }]
    },
    {
      id: 'owner-demo-2',
      fullName: 'Javier Ortiz · ejemplo',
      email: 'javier@example.invalid',
      phone: '+34 600 000 002',
      status: 'archived',
      archivedAt: '2026-09-13T19:00:00.000Z',
      history: [
        { label: 'Alta de demostración', at: '2026-09-13T17:00:00.000Z' },
        { label: 'Baja lógica', at: '2026-09-13T19:00:00.000Z' }
      ]
    }
  ],
  properties: [
    {
      id: 'property-demo-1',
      ownerId: 'owner-demo-1',
      name: 'Piso Centro · ejemplo',
      address: 'Calle de ejemplo 12',
      city: 'Madrid',
      postalCode: '28000',
      status: 'active',
      history: [{ label: 'Alta de demostración', at: '2026-09-13T18:10:00.000Z' }]
    }
  ],
  rooms: [
    {
      id: 'room-demo-1',
      propertyId: 'property-demo-1',
      label: 'Habitación A · ejemplo',
      description: 'Exterior, uso individual',
      status: 'active',
      history: [{ label: 'Alta de demostración', at: '2026-09-13T18:20:00.000Z' }]
    }
  ]
};

const labels = {
  active: 'Activo',
  blocked: 'Bloqueado',
  archived: 'Archivado',
  onboarding: 'En alta',
  maintenance: 'Mantenimiento',
  offboarding: 'En baja'
};

let current = 'owners';
let editingId = null;

const title = document.getElementById('sectionTitle');
const emptyState = document.getElementById('emptyState');
const emptyTitle = document.getElementById('emptyTitle');
const emptyText = document.getElementById('emptyText');
const records = document.getElementById('records');
const summary = document.getElementById('relationshipSummary');
const action = document.getElementById('newItemBtn');
const statusFilter = document.getElementById('statusFilter');
const editorDialog = document.getElementById('editorDialog');
const editorForm = document.getElementById('editorForm');
const editorTitle = document.getElementById('editorTitle');
const editorFields = document.getElementById('editorFields');
const historyDialog = document.getElementById('historyDialog');
const historyTitle = document.getElementById('historyTitle');
const historyList = document.getElementById('historyList');

function createElement(tag, className, content) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (content !== undefined) element.textContent = content;
  return element;
}

function itemName(type, item) {
  if (!item) return 'Sin relación';
  if (type === 'owners') return item.fullName;
  if (type === 'properties') return item.name;
  return item.label;
}

function findItem(type, id) {
  return state[type].find(item => item.id === id);
}

function makeSummaryCell(value, label) {
  const cell = createElement('div', 'summary-cell');
  cell.append(createElement('strong', '', String(value)), createElement('span', '', label));
  return cell;
}

function renderSummary() {
  const activeOwners = state.owners.filter(item => item.status !== 'archived').length;
  const activeProperties = state.properties.filter(item => item.status !== 'archived').length;
  const activeRooms = state.rooms.filter(item => item.status !== 'archived').length;
  summary.replaceChildren(
    makeSummaryCell(activeOwners, 'propietarios en cartera'),
    makeSummaryCell(activeProperties, 'pisos en cartera'),
    makeSummaryCell(activeRooms, 'habitaciones en cartera')
  );
}

function visibleItems() {
  const filter = statusFilter.value;
  return state[current].filter(item => {
    if (filter === 'all') return true;
    if (filter === 'archived') return item.status === 'archived';
    return item.status !== 'archived';
  });
}

function relationChips(item) {
  const chips = createElement('div', 'relation-chips');
  if (current === 'owners') {
    const properties = state.properties.filter(property => property.ownerId === item.id);
    chips.append(createElement('span', 'relation-chip', `${properties.length} piso${properties.length === 1 ? '' : 's'}`));
    properties.slice(0, 2).forEach(property => {
      chips.append(createElement('span', 'relation-chip', property.name));
    });
  }
  if (current === 'properties') {
    const owner = findItem('owners', item.ownerId);
    const rooms = state.rooms.filter(room => room.propertyId === item.id);
    chips.append(
      createElement('span', 'relation-chip', `Propietario: ${itemName('owners', owner)}`),
      createElement('span', 'relation-chip', `${rooms.length} habitación${rooms.length === 1 ? '' : 'es'}`)
    );
  }
  if (current === 'rooms') {
    const property = findItem('properties', item.propertyId);
    const owner = property ? findItem('owners', property.ownerId) : null;
    chips.append(
      createElement('span', 'relation-chip', `Piso: ${itemName('properties', property)}`),
      createElement('span', 'relation-chip', `Propietario: ${itemName('owners', owner)}`)
    );
  }
  return chips;
}

function descriptionFor(item) {
  if (current === 'owners') return [item.email, item.phone].filter(Boolean).join(' · ') || 'Sin datos de contacto';
  if (current === 'properties') return [item.address, item.city, item.postalCode].filter(Boolean).join(' · ');
  return item.description || 'Sin descripción';
}

function renderCard(item) {
  const card = createElement('article', 'record-card');
  const content = createElement('div');
  const heading = createElement('h4', '', itemName(current, item));
  const description = createElement('p', '', descriptionFor(item));
  const meta = createElement('div', 'record-meta');
  meta.append(createElement('span', `status-pill is-${item.status}`, labels[item.status] || item.status));
  if (item.archivedAt) {
    meta.append(createElement('span', 'relation-chip', `Baja: ${formatDate(item.archivedAt)}`));
  }
  content.append(heading, description, meta, relationChips(item));

  const buttons = createElement('div', 'record-actions');
  const edit = createElement('button', 'secondary', 'Editar');
  edit.type = 'button';
  edit.dataset.action = 'edit';
  edit.dataset.id = item.id;
  const history = createElement('button', 'secondary', 'Histórico');
  history.type = 'button';
  history.dataset.action = 'history';
  history.dataset.id = item.id;
  buttons.append(edit, history);
  if (item.status !== 'archived') {
    const archive = createElement('button', 'danger-soft', 'Archivar');
    archive.type = 'button';
    archive.dataset.action = 'archive';
    archive.dataset.id = item.id;
    buttons.append(archive);
  }
  card.append(content, buttons);
  return card;
}

function render() {
  const view = views[current];
  const items = visibleItems();
  title.textContent = view.title;
  action.textContent = view.action;
  emptyTitle.textContent = view.emptyTitle;
  emptyText.textContent = view.emptyText;
  document.querySelectorAll('.segment').forEach(button => {
    button.classList.toggle('is-active', button.dataset.view === current);
  });
  records.replaceChildren(...items.map(renderCard));
  emptyState.hidden = items.length !== 0;
  renderSummary();
}

function relationOptions(type, selectedId) {
  return state[type].filter(item => item.status !== 'archived' || item.id === selectedId);
}

function makeField(field, item) {
  const wrapper = createElement('label', '', field.label);
  let input;
  if (field.type === 'relation') {
    input = document.createElement('select');
    const blank = document.createElement('option');
    blank.value = '';
    blank.textContent = 'Selecciona una opción';
    input.append(blank);
    relationOptions(field.relation, item?.[field.key]).forEach(related => {
      const option = document.createElement('option');
      option.value = related.id;
      option.textContent = itemName(field.relation, related);
      input.append(option);
    });
  } else if (field.type === 'textarea') {
    input = document.createElement('textarea');
  } else {
    input = document.createElement('input');
    input.type = field.type;
    input.autocomplete = 'off';
  }
  input.name = field.key;
  input.required = Boolean(field.required);
  input.value = item?.[field.key] || '';
  wrapper.append(input);
  return wrapper;
}

function statusField(item) {
  const wrapper = createElement('label', '', 'Estado');
  const select = document.createElement('select');
  select.name = 'status';
  views[current].statuses.forEach(status => {
    const option = document.createElement('option');
    option.value = status;
    option.textContent = labels[status] || status;
    select.append(option);
  });
  select.value = item?.status || views[current].statuses[0];
  wrapper.append(select);
  return wrapper;
}

function openEditor(id = null) {
  editingId = id;
  const view = views[current];
  const item = id ? findItem(current, id) : null;
  editorTitle.textContent = item ? `Editar ${view.singular}` : `Nuevo ${view.singular}`;
  editorFields.replaceChildren(
    ...view.fields.map(field => makeField(field, item)),
    statusField(item)
  );
  editorDialog.showModal();
}

function formatDate(value) {
  return new Intl.DateTimeFormat('es-ES', {
    dateStyle: 'medium',
    timeStyle: 'short'
  }).format(new Date(value));
}

function saveItem(event) {
  event.preventDefault();
  if (!editorForm.reportValidity()) return;
  const data = Object.fromEntries(new FormData(editorForm).entries());
  const now = new Date().toISOString();
  const existing = editingId ? findItem(current, editingId) : null;
  const nextStatus = data.status;
  const archivedAt = nextStatus === 'archived' ? existing?.archivedAt || now : null;
  if (existing) {
    const statusChanged = existing.status !== nextStatus;
    Object.assign(existing, data, { archivedAt });
    existing.history.push({
      label: statusChanged ? `Estado: ${labels[nextStatus]}` : 'Datos editados',
      at: now
    });
  } else {
    state[current].push({
      ...data,
      id: `${current}-${Date.now()}`,
      archivedAt,
      history: [{ label: 'Alta de demostración', at: now }]
    });
  }
  editorDialog.close();
  render();
}

function archiveItem(id) {
  const item = findItem(current, id);
  if (!item || item.status === 'archived') return;
  const now = new Date().toISOString();
  item.status = 'archived';
  item.archivedAt = now;
  item.history.push({ label: 'Baja lógica', at: now });
  render();
}

function showHistory(id) {
  const item = findItem(current, id);
  if (!item) return;
  historyTitle.textContent = itemName(current, item);
  const entries = [...item.history].reverse().map(entry => {
    const row = document.createElement('li');
    row.append(
      createElement('strong', '', entry.label),
      createElement('time', '', formatDate(entry.at))
    );
    return row;
  });
  historyList.replaceChildren(...entries);
  historyDialog.showModal();
}

document.querySelectorAll('.segment').forEach(button => {
  button.addEventListener('click', () => {
    current = button.dataset.view;
    render();
  });
});

records.addEventListener('click', event => {
  const button = event.target.closest('button[data-action]');
  if (!button) return;
  if (button.dataset.action === 'edit') openEditor(button.dataset.id);
  if (button.dataset.action === 'archive') archiveItem(button.dataset.id);
  if (button.dataset.action === 'history') showHistory(button.dataset.id);
});

action.addEventListener('click', () => openEditor());
statusFilter.addEventListener('change', render);
editorForm.addEventListener('submit', saveItem);
document.getElementById('closeEditorBtn').addEventListener('click', () => editorDialog.close());
document.getElementById('cancelEditorBtn').addEventListener('click', () => editorDialog.close());
document.getElementById('closeHistoryBtn').addEventListener('click', () => historyDialog.close());

render();
