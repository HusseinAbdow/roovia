const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const DAY_MS = 24 * 60 * 60 * 1000;
const UPCOMING_GAP_MS = 20 * 60 * 60 * 1000;
const OVERDUE_GAP_MS = 24 * 60 * 60 * 1000;
const MAX_OVERDUE_REMINDERS = 6;

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function utcDayStart(date) {
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

function daysUntilDue(dueDate, now = new Date()) {
  return Math.floor((utcDayStart(dueDate) - utcDayStart(now)) / DAY_MS);
}

function reminderBody(kind, expenseTitle, amountOwed) {
  const amountText = amountOwed > 0 ? ` You still owe ₺${amountOwed.toFixed(2)}.` : '';
  switch (kind) {
    case 'bill_due_soon':
      return `${expenseTitle} bill is due in 3 days.`;
    case 'bill_due_tomorrow':
      return `${expenseTitle} bill is due tomorrow.`;
    case 'bill_overdue_reminder':
      return `${expenseTitle} bill is now overdue.${amountText}`.trim();
    default:
      return `${expenseTitle} bill needs your attention.`;
  }
}

function reminderTitle(kind) {
  switch (kind) {
    case 'bill_due_soon':
      return 'Bill due soon';
    case 'bill_due_tomorrow':
      return 'Bill due tomorrow';
    case 'bill_overdue_reminder':
      return 'Bill overdue';
    default:
      return 'Bill reminder';
  }
}

function reminderWindowOpen(lastReminderAt, minimumGapMs) {
  if (!lastReminderAt) return true;
  return Date.now() - lastReminderAt.getTime() >= minimumGapMs;
}

async function sendNotificationBatch({
  expenseId,
  houseId,
  createdBy,
  title,
  body,
  type,
  targets,
  reminderPatch,
}) {
  if (!targets.length) return false;

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const target of targets) {
    const notificationRef = db
      .collection('user_notifications')
      .doc(target.userId)
      .collection('notifications')
      .doc();

    batch.set(notificationRef, {
      title,
      body,
      type,
      read: false,
      createdAt: now,
      houseId,
      expenseId,
      fromUserId: createdBy,
      userName: target.userName || 'Member',
      amountOwed: target.amountOwed,
    });
  }

  batch.update(db.collection('house_expenses').doc(expenseId), reminderPatch);
  await batch.commit();
  return true;
}

async function getUserName(userId) {
  try {
    const snapshot = await db.collection('users').doc(userId).get();
    const data = snapshot.data() || {};
    return data.displayName || data.username || 'Member';
  } catch (error) {
    return 'Member';
  }
}

async function getPendingTargets(expenseRef, creatorId) {
  const participantsSnapshot = await expenseRef.collection('participants').get();
  const pending = participantsSnapshot.docs.filter((doc) => {
    const data = doc.data() || {};
    const status = (data.status || 'pending').toString();
    return doc.id !== creatorId && status === 'pending';
  });

  const targets = [];
  for (const doc of pending) {
    const data = doc.data() || {};
    targets.push({
      userId: doc.id,
      userName: await getUserName(doc.id),
      amountOwed: Number(data.amountOwed || 0),
    });
  }

  return targets;
}

async function processExpenseReminder(expenseDoc) {
  const data = expenseDoc.data() || {};
  const expenseId = expenseDoc.id;
  const expenseRef = expenseDoc.ref;

  const reminderEnabled = data.reminderEnabled !== false;
  const status = (data.status || 'pending').toString();
  const createdBy = (data.createdBy || '').toString();
  const houseId = (data.houseId || '').toString();
  const title = (data.title || 'a bill').toString();
  const dueDate = toDate(data.dueDate);
  const lastReminderAt = toDate(data.lastReminderAt || data.lastReminderSentAt);
  const reminderCount = Number(data.reminderCount || 0);
  const overdueReminderCount = Number(data.overdueReminderCount || 0);

  if (!reminderEnabled || status === 'confirmed' || !dueDate) {
    return false;
  }

  const targets = await getPendingTargets(expenseRef, createdBy);
  if (!targets.length) {
    return false;
  }

  const gapOkForUpcoming = reminderWindowOpen(lastReminderAt, UPCOMING_GAP_MS);
  const gapOkForOverdue = reminderWindowOpen(lastReminderAt, OVERDUE_GAP_MS);
  const daysLeft = daysUntilDue(dueDate);

  if (daysLeft === 3 && reminderCount < 1 && gapOkForUpcoming) {
    return sendNotificationBatch({
      expenseId,
      houseId,
      createdBy,
      title: reminderTitle('bill_due_soon'),
      body: reminderBody('bill_due_soon', title, 0),
      type: 'bill_due_soon',
      targets,
      reminderPatch: {
        reminderCount: admin.firestore.FieldValue.increment(1),
        lastReminderAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  }

  if (daysLeft === 1 && reminderCount < 2 && gapOkForUpcoming) {
    return sendNotificationBatch({
      expenseId,
      houseId,
      createdBy,
      title: reminderTitle('bill_due_tomorrow'),
      body: reminderBody('bill_due_tomorrow', title, 0),
      type: 'bill_due_tomorrow',
      targets,
      reminderPatch: {
        reminderCount: admin.firestore.FieldValue.increment(1),
        lastReminderAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  }

  if (daysLeft < 0 && overdueReminderCount < MAX_OVERDUE_REMINDERS && gapOkForOverdue) {
    return sendNotificationBatch({
      expenseId,
      houseId,
      createdBy,
      title: reminderTitle('bill_overdue_reminder'),
      body: reminderBody('bill_overdue_reminder', title, Number(data.perPersonAmount || 0)),
      type: 'bill_overdue_reminder',
      targets,
      reminderPatch: {
        overdueReminderCount: admin.firestore.FieldValue.increment(1),
        lastReminderAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  }

  return false;
}

/**
 * Relay in-app notification documents to FCM using the stored user token.
 * This keeps the existing Firestore notification collection intact.
 */
exports.sendPushOnUserNotification = functions.firestore
  .document('user_notifications/{userId}/notifications/{notifId}')
  .onCreate(async (snap, context) => {
    const { userId } = context.params;
    const notif = snap.data() || {};

    const title = notif.title || 'Roovia';
    const body = notif.body || '';
    const data = {
      type: notif.type || '',
      expenseId: notif.expenseId || '',
      houseId: notif.houseId || '',
    };

    try {
      const userDoc = await db.collection('users').doc(userId).get();
      const userData = userDoc.data() || {};
      const token = userData.fcmToken || null;
      if (!token) {
        console.log('No token for user', userId);
        return null;
      }

      const response = await admin.messaging().send({
        token,
        notification: {
          title,
          body,
        },
        data,
      });

      console.log('Sent FCM message:', response);
      return response;
    } catch (error) {
      const code = error && error.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        await db.collection('users').doc(userId).set(
          { fcmToken: admin.firestore.FieldValue.delete() },
          { merge: true },
        );
      }

      console.error('Error sending FCM', error);
      return null;
    }
  });

/**
 * Scheduled reminder processor for bill automation.
 * Runs frequently enough to catch the 3-day, 1-day, and overdue windows.
 */
exports.processBillReminders = functions.pubsub
  .schedule('every 1 hours')
  .timeZone('UTC')
  .onRun(async () => {
    const now = new Date();
    const windowEnd = new Date(now.getTime() + 3 * DAY_MS);

    const expensesSnapshot = await db
      .collection('house_expenses')
      .where('dueDate', '<=', admin.firestore.Timestamp.fromDate(windowEnd))
      .get();

    let processed = 0;
    for (const expenseDoc of expensesSnapshot.docs) {
      try {
        const sent = await processExpenseReminder(expenseDoc);
        if (sent) processed += 1;
      } catch (error) {
        console.error('Reminder processing failed for', expenseDoc.id, error);
      }
    }

    console.log(`Reminder run complete. Notifications sent for ${processed} expenses.`);
    return null;
  });
