document.addEventListener('DOMContentLoaded', () => {
    const bodyView = document.body.dataset.view;

    // ======================
    // VISTA ADMIN
    // ======================
    if (bodyView === 'admin') {
        const search = document.getElementById('adminSearch');
        const statusFilter = document.getElementById('adminStatusFilter');
        const rows = document.querySelectorAll('#adminInventoryTable tbody tr');

        const filterAdminTable = () => {
            const query = search.value.toLowerCase().trim();
            const status = statusFilter.value;

            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                const rowStatus = row.dataset.status;

                const matchesSearch = text.includes(query);
                const matchesStatus = status === 'todos' || rowStatus === status;

                if (matchesSearch && matchesStatus) {
                    row.classList.remove('hidden-row');
                } else {
                    row.classList.add('hidden-row');
                }
            });
        };

        if (search && statusFilter) {
            search.addEventListener('input', filterAdminTable);
            statusFilter.addEventListener('change', filterAdminTable);
        }
    }

    // ======================
    // VISTA CLÍNICO
    // ======================
    if (bodyView === 'clinico') {
        const search = document.getElementById('clinicoSearch');
        const typeFilter = document.getElementById('clinicoTypeFilter');
        const rows = document.querySelectorAll('#clinicoTable tbody tr');

        const filterClinicoTable = () => {
            const query = search.value.toLowerCase().trim();
            const type = typeFilter.value;

            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                const rowType = row.dataset.type;

                const matchesSearch = text.includes(query);
                const matchesType = type === 'todos' || rowType === type;

                if (matchesSearch && matchesType) {
                    row.classList.remove('hidden-row');
                } else {
                    row.classList.add('hidden-row');
                }
            });
        };

        if (search && typeFilter) {
            search.addEventListener('input', filterClinicoTable);
            typeFilter.addEventListener('change', filterClinicoTable);
        }
    }
});