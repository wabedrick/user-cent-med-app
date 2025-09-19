#!/usr/bin/env node
/*
 * Local Role Management Helper (No Blaze Plan Required)
 * ----------------------------------------------------
 * Provides administrative operations for user roles using firebase-admin directly.
 * Commands:
 *   node scripts/role_manager.js bootstrap --email <email> --role admin
 *   node scripts/role_manager.js set-role --uid <uid> --role <role>
 *   node scripts/role_manager.js set-role-email --email <email> --role <role>
 *   node scripts/role_manager.js list-users [--role <role>] [--limit N]
 *   node scripts/role_manager.js audit-logs [--limit N]
 *
 * Prerequisites:
 *   1. Create a service account key in Firebase Console (Project Settings > Service Accounts > Generate Key)
 *   2. Save it as serviceAccountKey.json at project root OR set GOOGLE_APPLICATION_CREDENTIALS env var to its path.
 *   3. npm install
 *
 * Security: Keep the key private. Do NOT commit serviceAccountKey.json.
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

// Attempt to load service account key from local file if GOOGLE_APPLICATION_CREDENTIALS not set.
function initAdmin() {
    if (!admin.apps.length) {
        let options = {};
        if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
            const keyPath = path.resolve(process.cwd(), 'serviceAccountKey.json');
            if (!fs.existsSync(keyPath)) {
                console.error('Missing credentials. Provide serviceAccountKey.json or set GOOGLE_APPLICATION_CREDENTIALS.');
                process.exit(1);
            }
            options.credential = admin.credential.cert(require(keyPath));
        } else {
            options.credential = admin.credential.applicationDefault();
        }
        admin.initializeApp(options);
    }
    return admin;
}

const firestore = () => admin.firestore();

function parseArgs() {
    const args = process.argv.slice(2);
    const cmd = args.shift();
    const opts = {};
    const positionals = [];
    for (let i = 0; i < args.length; i++) {
        if (args[i].startsWith('--')) {
            const key = args[i].substring(2);
            const val = args[i + 1] && !args[i + 1].startsWith('--') ? args[++i] : true;
            opts[key] = val;
        } else {
            positionals.push(args[i]);
        }
    }
    opts._ = positionals; // store leftover positional args
    return { cmd, opts };
}

async function ensureUserDoc(uid, email) {
    const ref = firestore().collection('users').doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
        await ref.set({ email: email || null, role: 'nurse', createdAt: admin.firestore.FieldValue.serverTimestamp() });
    }
}

async function writeAudit(entry) {
    await firestore().collection('audit_logs').add({
        ...entry,
        at: admin.firestore.FieldValue.serverTimestamp(),
        source: 'local-script'
    });
}

async function bootstrap({ email, role }) {
    if (!email) {
        // fallback: first positional after command
        if (Array.isArray(arguments[0]._unused)) {
            // no-op; legacy placeholder
        }
        // Support positional via opts._ (populated by parseArgs)
        if (!email && Array.isArray(arguments[0]._)) {
            email = arguments[0]._[0];
        }
    }
    if (!email) throw new Error('bootstrap requires --email (or positional email)');
    role = role || 'admin';
    if (role !== 'admin') throw new Error('bootstrap role must be admin');
    const user = await admin.auth().getUserByEmail(email).catch(() => null);
    if (!user) throw new Error('No user with that email. User must sign up first.');
    // Set custom claims
    await admin.auth().setCustomUserClaims(user.uid, { role: 'admin' });
    await ensureUserDoc(user.uid, email);
    await firestore().collection('users').doc(user.uid).set({ role: 'admin' }, { merge: true });
    await writeAudit({ type: 'bootstrap_admin', uid: user.uid, email });
    console.log(`Bootstrapped first admin: ${email}`);
}

async function setRole({ uid, role }) {
    if (!uid) throw new Error('set-role requires --uid');
    if (!role) throw new Error('set-role requires --role');
    role = role.toLowerCase();
    if (!['admin', 'engineer', 'nurse'].includes(role)) throw new Error('Invalid role');
    const user = await admin.auth().getUser(uid).catch(() => null);
    if (!user) throw new Error('User not found');
    await admin.auth().setCustomUserClaims(uid, { role });
    await ensureUserDoc(uid, user.email);
    await firestore().collection('users').doc(uid).set({ role }, { merge: true });
    await writeAudit({ type: 'role_change', uid, newRole: role });
    console.log(`Updated role for ${uid} -> ${role}`);
}

async function setRoleByEmail({ email, role }) {
    if (!email) {
        if (Array.isArray(arguments[0]._)) {
            email = arguments[0]._[0];
        }
    }
    if (!email) throw new Error('set-role-email requires --email (or positional email)');
    if (!role) throw new Error('set-role-email requires --role');
    role = role.toLowerCase();
    if (!['admin', 'engineer', 'nurse'].includes(role)) throw new Error('Invalid role');
    const user = await admin.auth().getUserByEmail(email).catch(() => null);
    if (!user) throw new Error('User not found');
    await admin.auth().setCustomUserClaims(user.uid, { role });
    await ensureUserDoc(user.uid, email);
    await firestore().collection('users').doc(user.uid).set({ role }, { merge: true });
    await writeAudit({ type: 'role_change', uid: user.uid, email, newRole: role });
    console.log(`Updated role for ${email} -> ${role}`);
}

async function listUsers({ role, limit }) {
    const max = parseInt(limit || '100', 10);
    let nextPageToken = undefined;
    const rows = [];
    while (rows.length < max) {
        const resp = await admin.auth().listUsers(1000, nextPageToken);
        for (const user of resp.users) {
            const r = user.customClaims && user.customClaims.role;
            if (!role || r === role) {
                rows.push({ uid: user.uid, email: user.email, role: r || '—' });
                if (rows.length >= max) break;
            }
        }
        if (!resp.pageToken || rows.length >= max) break;
        nextPageToken = resp.pageToken;
    }
    console.table(rows);
    console.log(`Total: ${rows.length}`);
}

async function auditLogs({ limit }) {
    const max = parseInt(limit || '25', 10);
    const snap = await firestore().collection('audit_logs').orderBy('at', 'desc').limit(max).get();
    const rows = [];
    snap.forEach(doc => {
        const d = doc.data();
        rows.push({ id: doc.id, type: d.type, uid: d.uid, email: d.email || '', role: d.newRole || d.role || '', at: d.at ? d.at.toDate().toISOString() : '' });
    });
    console.table(rows);
}

async function main() {
    let { cmd, opts } = parseArgs();
    // Gracefully handle common typo 'boostrap'
    if (cmd === 'boostrap') {
        console.warn("'boostrap' detected; assuming you meant 'bootstrap'.");
        cmd = 'bootstrap';
    }
    if (!cmd) {
        console.log('Commands: bootstrap | set-role | set-role-email | list-users | audit-logs');
        process.exit(0);
    }
    initAdmin();
    try {
        switch (cmd) {
            case 'bootstrap':
                await bootstrap(opts); break;
            case 'set-role':
                await setRole(opts); break;
            case 'set-role-email':
                await setRoleByEmail(opts); break;
            case 'list-users':
                await listUsers(opts); break;
            case 'audit-logs':
                await auditLogs(opts); break;
            default:
                console.error('Unknown command');
                process.exit(1);
        }
    } catch (e) {
        console.error('Error:', e.message);
        process.exit(1);
    }
}

main();
