import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();
const db = admin.firestore();

const ALLOWED_ROLES = new Set(['engineer', 'nurse', 'medic', 'admin']);

interface RoleChangeRequest {
    targetUid: string;
    newRole: string;
}

export const setUserRole = functions.https.onCall(async (data: RoleChangeRequest, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const callerUid = context.auth.uid;
    const callerRole = (context.auth.token as any).role as string | undefined;
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
export const bootstrapFirstAdmin = functions.https.onCall(async (data, context) => {
    const secret = process.env.BOOTSTRAP_ADMIN_SECRET;
    if (!secret) throw new functions.https.HttpsError('failed-precondition', 'Secret not set');
    if (!data || data.secret !== secret) throw new functions.https.HttpsError('permission-denied', 'Bad secret');
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required');

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
export const selfSyncRoleClaim = functions.https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const uid = context.auth.uid;
    const currentClaimRole = (context.auth.token as any).role as string | undefined;
    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User doc missing');
    }
    const docRole = (userDoc.data() as any).role as string | undefined;
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

// Minimal AI assistant callable. Requires OPENAI_API_KEY set in environment.
// Allowed for roles: engineer, medic, admin. Nurses (legacy) denied by default.
export const aiAssistantChat = functions.https.onCall(async (data: any, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const role = (context.auth.token as any).role as string | undefined;
    if (!(role && (role === 'engineer' || role === 'medic' || role === 'admin'))) {
        throw new functions.https.HttpsError('permission-denied', 'Assistant limited to engineer/medic/admin');
    }
    if (!data || !Array.isArray(data.messages) || data.messages.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'messages array required');
    }
    // Light validation: each message has role and content strings
    const msgs = data.messages as Array<{ role: string; content: string }>;
    if (msgs.some(m => typeof m.role !== 'string' || typeof m.content !== 'string' || m.content.length === 0)) {
        throw new functions.https.HttpsError('invalid-argument', 'invalid message format');
    }

    const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
    const systemPrompt = data.systemPrompt as string | undefined;
    const model = (data.model as string | undefined) ?? 'gpt-4o-mini';
    const temperature = Math.min(1, Math.max(0, Number(data.temperature ?? 0.2)));

    // Audit input
    await db.collection('ai_queries').add({
        uid: context.auth.uid,
        role,
        model,
        ts: admin.firestore.FieldValue.serverTimestamp(),
        inputCount: msgs.length,
    });

    // If key missing, return deterministic safe response
    if (!OPENAI_API_KEY) {
        return {
            status: 'no-key',
            reply: 'AI assistant is not configured. Please contact an administrator.',
        };
    }

    // Call OpenAI responses API (chat completions compatible)
    try {
        const resp = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${OPENAI_API_KEY}`,
            },
            body: JSON.stringify({
                model,
                temperature,
                messages: [
                    ...(systemPrompt ? [{ role: 'system', content: systemPrompt }] : []),
                    ...msgs,
                ],
            }),
        });
        if (!resp.ok) {
            const text = await resp.text();
            throw new Error(`OpenAI error ${resp.status}: ${text}`);
        }
        const json: any = await resp.json();
        const reply = json?.choices?.[0]?.message?.content || '';
        return { status: 'ok', reply };
    } catch (e: any) {
        console.error('aiAssistantChat error', e);
        throw new functions.https.HttpsError('internal', 'Assistant error');
    }
});

// Notify on repair request assignment and completion
export const onRepairRequestChange = functions.firestore
    .document('repair_requests/{reqId}')
    .onWrite(async (change, context) => {
        const before = change.before.exists ? change.before.data()! : undefined;
        const after = change.after.exists ? change.after.data()! : undefined;
        if (!after) {
            return;
        }

        const db = admin.firestore();
        const messages: admin.messaging.Message[] = [];

        // Assigned engineer notification (assignment from null -> some uid)
        if ((!before || !before.assignedEngineerId) && after.assignedEngineerId) {
            const engineerId = String(after.assignedEngineerId);
            try {
                const uDoc = await db.collection('users').doc(engineerId).get();
                const token = (uDoc.exists ? (uDoc.data() as any)?.fcmToken : undefined) as string | undefined;
                if (token) {
                    messages.push({
                        token,
                        notification: { title: 'New Assignment', body: 'A repair request has been assigned to you.' },
                        data: { type: 'repair_assigned', reqId: context.params.reqId },
                    });
                }
            } catch (_) { }
        }

        // Reporter notification on completion (status changed to 'resolved' or 'closed')
        if (
            before &&
            before.status !== after.status &&
            (after.status === 'resolved' || after.status === 'closed')
        ) {
            const reporterId = String(after.reportedByUserId || '');
            if (reporterId) {
                try {
                    const uDoc = await db.collection('users').doc(reporterId).get();
                    const token = (uDoc.exists ? (uDoc.data() as any)?.fcmToken : undefined) as string | undefined;
                    if (token) {
                        messages.push({
                            token,
                            notification: { title: 'Request Completed', body: 'Your repair request has been marked as completed.' },
                            data: { type: 'repair_completed', reqId: context.params.reqId },
                        });
                    }
                } catch (_) { }
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
export const runMaintenanceReminders = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const callerRole = (context.auth.token as any).role as string | undefined;
    if (callerRole !== 'admin' && callerRole !== 'engineer') {
        throw new functions.https.HttpsError('permission-denied', 'Only engineer/admin can trigger reminders');
    }
    const now = admin.firestore.Timestamp.now();
    const snap = await db
        .collection('maintenance_schedules')
        .where('completed', '==', false)
        .where('dueDate', '<=', now)
        .get();
    const messages: admin.messaging.Message[] = [];
    for (const doc of snap.docs) {
        const dataDoc = doc.data() as any;
        const uid = String(dataDoc.assignedTo || '');
        if (!uid) continue;
        try {
            const uDoc = await db.collection('users').doc(uid).get();
            const token = (uDoc.exists ? (uDoc.data() as any)?.fcmToken : undefined) as string | undefined;
            if (token) {
                const dueDate = (dataDoc.dueDate as admin.firestore.Timestamp).toDate();
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
        } catch (_) { }
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
export const maintenanceRemindersDaily = functions.pubsub.schedule('every 24 hours').onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
        .collection('maintenance_schedules')
        .where('completed', '==', false)
        .where('dueDate', '<=', now)
        .get();
    const messages: admin.messaging.Message[] = [];
    for (const doc of snap.docs) {
        const dataDoc = doc.data() as any;
        const uid = String(dataDoc.assignedTo || '');
        if (!uid) continue;
        try {
            const uDoc = await db.collection('users').doc(uid).get();
            const token = (uDoc.exists ? (uDoc.data() as any)?.fcmToken : undefined) as string | undefined;
            if (token) {
                const dueDate = (dataDoc.dueDate as admin.firestore.Timestamp).toDate();
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
        } catch (_) { }
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
