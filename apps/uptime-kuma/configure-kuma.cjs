// Idempotent Uptime Kuma setup over its Socket.IO API, ported from
// mikrus-devops-portfolio. Creates the admin user, missing monitors and the
// public status page; prints {"changed": bool} for the job log.
const { io } = require('/app/node_modules/socket.io-client');
const fs = require('fs');
const password = process.env.KUMA_ADMIN_PASSWORD;
const desiredMonitors = JSON.parse(fs.readFileSync('/config/monitors.json', 'utf8'));
const socket = io(process.env.KUMA_URL, { transports: ['websocket'], reconnection: false });
const timeout = setTimeout(() => { console.error('Kuma configuration timed out'); process.exit(1); }, 120000);
let monitors = {};
socket.on('monitorList', value => { monitors = value; });
function call(event, ...args) {
    return new Promise((resolve, reject) => socket.timeout(15000).emit(event, ...args, (error, result) => {
        if (error) reject(error); else resolve(result);
    }));
}
function checked(result) {
    if (!result.ok) throw new Error(result.msg || 'Kuma API request failed');
    return result;
}
// Wait for the server's asynchronous handshake before sending API events.
socket.once('info', async () => {
    try {
        let changed = false;
        const setup = await call('setup', 'admin', password);
        if (setup.ok) changed = true;
        // The server pushes the monitor list right after a successful login.
        const listed = new Promise(resolve => socket.once('monitorList', resolve));
        checked(await call('login', { username: 'admin', password }));
        await Promise.race([listed, new Promise(resolve => setTimeout(resolve, 10000))]);
        const ids = [];
        for (const desired of desiredMonitors) {
            const existing = Object.values(monitors).find(m => m.name === desired.name);
            if (existing) { ids.push(existing.id); continue; }
            const result = checked(await call('add', {
                type: 'http', name: desired.name, url: desired.url,
                method: 'GET', interval: 60, retryInterval: 60, maxretries: 2,
                timeout: 15, active: 1, accepted_statuscodes: ['200-299'],
                notificationIDList: {}, ignoreTls: false, upsideDown: false,
                maxredirects: 5, conditions: [], expiryNotification: false,
            }));
            ids.push(result.monitorID);
            changed = true;
        }
        let status = await call('getStatusPage', 'portfolio');
        if (!status.ok) {
            checked(await call('addStatusPage', 'Kubernetes GitOps / Service status', 'portfolio'));
            status = checked(await call('getStatusPage', 'portfolio'));
            checked(await call('saveStatusPage', 'portfolio', {
                ...status.config, slug: 'portfolio', title: 'Kubernetes GitOps / Service status',
                description: 'Monitors created by an Argo CD sync hook. Checks run every 60 seconds.',
                theme: 'dark', published: true, showTags: false,
                showPoweredBy: true, analyticsType: null, domainNameList: [],
                footerText: 'Provisioned with Argo CD', customCSS: '',
            }, '', [{name: 'Platform services', weight: 1, monitorList: ids.map(id => ({id}))}]));
            changed = true;
        }
        console.log(JSON.stringify({changed, monitors: ids.length}));
        clearTimeout(timeout); socket.disconnect();
    } catch (error) { console.error(error.message); process.exit(1); }
});
socket.on('connect_error', error => { console.error(error.message); process.exit(1); });
