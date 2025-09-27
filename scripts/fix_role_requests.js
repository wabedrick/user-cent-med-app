#!/usr/bin/env node
/*
 * Normalize role_requests collection
 * - Ensures every doc has a 'uid' field
 * - Moves docs so that document ID == uid (merging data) and deletes the old doc
 * - De-duplicates multiple docs for the same uid by keeping the most recent by createdAt
 *
 * Usage:
 *   node scripts/fix_role_requests.js [--dry]
 *
 * Requires firebase-admin credentials (see scripts/role_manager.js for setup)
 */
const path = require('path');
const fs = require('fs');
const admin = require('firebase-admin');

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

function parseArgs() {
    const args = process.argv.slice(2);
    const opts = { dry: false };
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--dry') opts.dry = true;
    }
    return opts;
}

async function main() {
    const { dry } = parseArgs();
    initAdmin();
    const db = admin.firestore();
    const col = db.collection('role_requests');
    const snap = await col.get();
    if (snap.empty) {
        console.log('No role_requests docs found.');
        return;
    }
    console.log(`Scanning ${snap.size} role_requests docs...`);
    const byUid = new Map();
    const tasks = [];
    snap.forEach(doc => {
        const d = doc.data() || {};
        const uid = (d.uid && typeof d.uid === 'string' && d.uid) || doc.id;
        const created = d.createdAt && d.createdAt.toDate ? d.createdAt.toDate().getTime() : 0;
        const list = byUid.get(uid) || [];
        list.push({ id: doc.id, data: { ...d, uid }, created });
        byUid.set(uid, list);
    });

    let moved = 0, updated = 0, deleted = 0;
    for (const [uid, docs] of byUid.entries()) {
        // Keep the most recent doc for this uid
        docs.sort((a, b) => b.created - a.created);
        const primary = docs[0];
        const targetRef = col.doc(uid);
        // Merge primary into target doc (ensures uid field exists and latest fields preserved)
        if (dry) {
            console.log(`[DRY] upsert -> role_requests/${uid} (from ${primary.id})`);
        } else {
            await targetRef.set(primary.data, { merge: true });
        }
        updated++;
        // Delete any duplicates or docs where id !== uid
        for (const extra of docs) {
            if (extra.id !== uid) {
                if (dry) {
                    console.log(`[DRY] delete -> role_requests/${extra.id}`);
                } else {
                    await col.doc(extra.id).delete();
                }
                deleted++;
            }
        }
        // If primary was not at id==uid originally, count as moved
        if (primary.id !== uid) moved++;
    }
    console.log(`Done. Upserted: ${updated}, Moved IDs: ${moved}, Deleted duplicates: ${deleted}.`);
    if (dry) console.log('DRY RUN (no writes performed). Re-run without --dry to apply changes.');
}

main().catch(e => {
    console.error('Error:', e.message || e);
    process.exit(1);
});
