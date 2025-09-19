"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function (o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
        desc = { enumerable: true, get: function () { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function (o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function (o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function (o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function (o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.maintenanceRemindersDaily = exports.runMaintenanceReminders = exports.onRepairRequestChange = exports.selfSyncRoleClaim = exports.bootstrapFirstAdmin = exports.setUserRole = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
const db = admin.firestore();
// Added 'medic' role (replaces previous 'nurse' UI terminology). Keep 'nurse' temporarily for backward compatibility.
const ALLOWED_ROLES = new Set(['engineer', 'nurse', 'medic', 'admin']);
exports.setUserRole = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const callerUid = context.auth.uid;
    const callerRole = context.auth.token.role;
    if (callerRole !== 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Only admin can change roles');
    }
    if (!data || typeof data.targetUid !== 'string' || typeof data.newRole !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'targetUid and newRole required');
    }
    const newRole = data.newRole.toLowerCase().trim();
    if (!ALLOWED_ROLES.has(newRole)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid role');
    }
    const userDocRef = db.collection('users').doc(data.targetUid);
    const userSnap = await userDocRef.get();
    if (!userSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'User doc missing');
    }
    // Update Firestore role field
    await userDocRef.update({ role: newRole, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    // Set custom claim
    await admin.auth().setCustomUserClaims(data.targetUid, { role: newRole });
    // Write audit log
    await db.collection('audit_logs').add({
        type: 'role_change',
        targetUid: data.targetUid,
        newRole,
        changedBy: callerUid,
        ts: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { status: 'ok', newRole };
});
// One-time secure bootstrap callable: Call with a secret to elevate first admin.
exports.bootstrapFirstAdmin = functions.https.onCall(async (data, context) => {
    const secret = process.env.BOOTSTRAP_ADMIN_SECRET;
    if (!secret)
        throw new functions.https.HttpsError('failed-precondition', 'Secret not set');
    if (!data || data.secret !== secret)
        throw new functions.https.HttpsError('permission-denied', 'Bad secret');
    if (!context.auth)
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    const callerUid = context.auth.uid;
    const claims = (await admin.auth().getUser(callerUid)).customClaims || {};
    if (claims.role === 'admin') {
        return { status: 'already-admin' };
    }
    await admin.auth().setCustomUserClaims(callerUid, { role: 'admin' });
    await db.collection('users').doc(callerUid).set({
        role: 'admin',
        elevatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await db.collection('audit_logs').add({
        type: 'bootstrap_admin',
        targetUid: callerUid,
        ts: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { status: 'ok', role: 'admin' };
});
// Allow a signed-in user to sync their missing custom claim from Firestore user doc.
// Only sets claim if claim is currently absent OR different from Firestore value.
exports.selfSyncRoleClaim = functions.https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const uid = context.auth.uid;
    const currentClaimRole = context.auth.token.role;
    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User doc missing');
    }
    const docRole = userDoc.data().role;
    if (!docRole || !ALLOWED_ROLES.has(docRole)) {
        throw new functions.https.HttpsError('failed-precondition', 'Invalid role in user doc');
    }
    if (currentClaimRole === docRole) {
        return { status: 'noop', role: docRole };
    }
    await admin.auth().setCustomUserClaims(uid, { role: docRole });
    await db.collection('audit_logs').add({
        type: 'self_sync_role_claim',
        targetUid: uid,
        newRole: docRole,
        previousClaim: currentClaimRole || null,
        ts: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { status: 'updated', role: docRole };
});
// Notify on repair request assignment and completion
exports.onRepairRequestChange = functions.firestore
    .document('repair_requests/{reqId}')
    .onWrite(async (change, context) => {
        const before = change.before.exists ? change.before.data() : undefined;
        const after = change.after.exists ? change.after.data() : undefined;
        if (!after) {
            return;
        }
        const db = admin.firestore();
        const messages = [];
        // Assigned engineer notification (assignment from null -> some uid)
        if ((!before || !before.assignedEngineerId) && after.assignedEngineerId) {
            const engineerId = String(after.assignedEngineerId);
            try {
                const uDoc = await db.collection('users').doc(engineerId).get();
                const token = (uDoc.exists ? uDoc.data()?.fcmToken : undefined);
                if (token) {
                    messages.push({
                        token,
                        notification: { title: 'New Assignment', body: 'A repair request has been assigned to you.' },
                        data: { type: 'repair_assigned', reqId: context.params.reqId },
                    });
                }
            }
            catch (_) { }
        }
        // Reporter notification on completion (status changed to 'resolved' or 'closed')
        if (before &&
            before.status !== after.status &&
            (after.status === 'resolved' || after.status === 'closed')) {
            const reporterId = String(after.reportedByUserId || '');
            if (reporterId) {
                try {
                    const uDoc = await db.collection('users').doc(reporterId).get();
                    const token = (uDoc.exists ? uDoc.data()?.fcmToken : undefined);
                    if (token) {
                        messages.push({
                            token,
                            notification: { title: 'Request Completed', body: 'Your repair request has been marked as completed.' },
                            data: { type: 'repair_completed', reqId: context.params.reqId },
                        });
                    }
                }
                catch (_) { }
            }
        }
        if (messages.length > 0) {
            const batchSize = 100;
            for (let i = 0; i < messages.length; i += batchSize) {
                const chunk = messages.slice(i, i + batchSize);
                await admin.messaging().sendEach(chunk);
            }
        }
    });
// On-demand maintenance reminders (Spark-friendly replacement for scheduled Pub/Sub)
exports.runMaintenanceReminders = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const callerRole = context.auth.token.role;
    if (callerRole !== 'admin' && callerRole !== 'engineer') {
        throw new functions.https.HttpsError('permission-denied', 'Only engineer/admin can trigger reminders');
    }
    const now = admin.firestore.Timestamp.now();
    const snap = await db
        .collection('maintenance_schedules')
        .where('completed', '==', false)
        .where('dueDate', '<=', now)
        .get();
    const messages = [];
    for (const doc of snap.docs) {
        const dataDoc = doc.data();
        const uid = String(dataDoc.assignedTo || '');
        if (!uid)
            continue;
        try {
            const uDoc = await db.collection('users').doc(uid).get();
            const token = (uDoc.exists ? uDoc.data()?.fcmToken : undefined);
            if (token) {
                const dueDate = dataDoc.dueDate.toDate();
                const overdueDays = Math.max(0, Math.ceil((Date.now() - dueDate.getTime()) / (1000 * 60 * 60 * 24)));
                messages.push({
                    token,
                    notification: {
                        title: overdueDays > 0 ? 'Maintenance Overdue' : 'Maintenance Due',
                        body: overdueDays > 0
                            ? `A scheduled maintenance is ${overdueDays} day(s) overdue.`
                            : 'A scheduled maintenance is due today.'
                    },
                    data: { type: 'maintenance_due', scheduleId: doc.id },
                });
            }
        }
        catch (_) { }
    }
    if (messages.length > 0) {
        const batchSize = 100;
        for (let i = 0; i < messages.length; i += batchSize) {
            const chunk = messages.slice(i, i + batchSize);
            await admin.messaging().sendEach(chunk);
        }
    }
    return { sent: messages.length };
});
// Scheduled (daily) maintenance reminders - requires Blaze (Pub/Sub scheduler)
exports.maintenanceRemindersDaily = functions.pubsub.schedule('every 24 hours').onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
        .collection('maintenance_schedules')
        .where('completed', '==', false)
        .where('dueDate', '<=', now)
        .get();
    const messages = [];
    for (const doc of snap.docs) {
        const dataDoc = doc.data();
        const uid = String(dataDoc.assignedTo || '');
        if (!uid)
            continue;
        try {
            const uDoc = await db.collection('users').doc(uid).get();
            const token = (uDoc.exists ? uDoc.data()?.fcmToken : undefined);
            if (token) {
                const dueDate = dataDoc.dueDate.toDate();
                const overdueDays = Math.max(0, Math.ceil((Date.now() - dueDate.getTime()) / (1000 * 60 * 60 * 24)));
                messages.push({
                    token,
                    notification: {
                        title: overdueDays > 0 ? 'Maintenance Overdue' : 'Maintenance Due',
                        body: overdueDays > 0
                            ? `A scheduled maintenance is ${overdueDays} day(s) overdue.`
                            : 'A scheduled maintenance is due today.'
                    },
                    data: { type: 'maintenance_due', scheduleId: doc.id },
                });
            }
        }
        catch (_) { }
    }
    if (messages.length > 0) {
        const batchSize = 100;
        for (let i = 0; i < messages.length; i += batchSize) {
            const chunk = messages.slice(i, i + batchSize);
            await admin.messaging().sendEach(chunk);
        }
    }
    return null;
});
