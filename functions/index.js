const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const DAY_MS = 24 * 60 * 60 * 1000;
const UPCOMING_GAP_MS = 20 * 60 * 60 * 1000;
const OVERDUE_GAP_MS = 24 * 60 * 60 * 1000;
const MAX_OVERDUE_REMINDERS = 6;

function logNotification(message, details = {}) {
  console.log(`[notifications] ${message}`, details);
}

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
      return `${expenseTitle} bill is due in 3 days.${amountText}`.trim();
    case 'bill_due_tomorrow':
      return `${expenseTitle} bill is due tomorrow.${amountText}`.trim();
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
  notificationIdSuffix,
  billTitle,
  billAmount,
  dueDate,
}) {
  if (!targets.length) return false;

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const target of targets) {
    const notificationRef = db
      .collection('user_notifications')
      .doc(target.userId)
      .collection('notifications')
      .doc(`${expenseId}_${target.userId}_${notificationIdSuffix || type}`);

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
      billTitle: billTitle || '',
      billAmount: billAmount || 0,
      dueDate: dueDate || null,
    });
  }

  batch.update(db.collection('house_expenses').doc(expenseId), reminderPatch);
  await batch.commit();
  logNotification('reminder sent', {
    expenseId,
    houseId,
    createdBy,
    type,
    targetCount: targets.length,
  });
  return true;
}

async function sendHouseMessageNotificationBatch({
  houseId,
  messageId,
  senderId,
  senderName,
  text,
  targets,
}) {
  if (!targets.length) return false;

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const preview = text.length > 120 ? `${text.slice(0, 117)}...` : text;
  const title = 'New chat message';
  const body = `${senderName}: ${preview}`;

  for (const target of targets) {
    const notificationRef = db
      .collection('user_notifications')
      .doc(target.userId)
      .collection('notifications')
      .doc(`${houseId}_${messageId}_${target.userId}`);

    batch.set(notificationRef, {
      title,
      body,
      type: 'chat_message',
      read: false,
      createdAt: now,
      houseId,
      messageId,
      senderId,
      senderName,
      messageText: text,
    });
  }

  await batch.commit();
  logNotification('chat message notification sent', {
    houseId,
    messageId,
    senderId,
    targetCount: targets.length,
  });
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
    const shouldInclude = doc.id !== creatorId && status === 'pending';
    if (shouldInclude) {
      logNotification('participant filtered', { expenseId: expenseRef.id, userId: doc.id, status });
    }
    return shouldInclude;
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
    logNotification('reminder skipped', {
      expenseId,
      reason: !reminderEnabled ? 'disabled' : status === 'confirmed' ? 'confirmed' : 'missing_due_date',
    });
    return false;
  }

  const targets = await getPendingTargets(expenseRef, createdBy);
  if (!targets.length) {
    logNotification('reminder skipped', { expenseId, reason: 'no_pending_targets' });
    return false;
  }

  const gapOkForUpcoming = reminderWindowOpen(lastReminderAt, UPCOMING_GAP_MS);
  const gapOkForOverdue = reminderWindowOpen(lastReminderAt, OVERDUE_GAP_MS);
  const daysLeft = daysUntilDue(dueDate);

  if (daysLeft < 0) {
    logNotification('overdue detection', {
      expenseId,
      houseId,
      title,
      daysLeft,
      overdueReminderCount,
    });
  }

  if (daysLeft === 3 && reminderCount < 1 && gapOkForUpcoming) {
    return sendNotificationBatch({
      expenseId,
      houseId,
      createdBy,
      title: reminderTitle('bill_due_soon'),
      body: reminderBody('bill_due_soon', title, 0),
      type: 'bill_due_soon',
      targets,
      notificationIdSuffix: 'bill_due_soon',
      reminderPatch: {
        reminderCount: admin.firestore.FieldValue.increment(1),
        lastReminderAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      billTitle: title,
      billAmount: 0,
      dueDate: admin.firestore.Timestamp.fromDate(dueDate),
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
      notificationIdSuffix: 'bill_due_tomorrow',
      reminderPatch: {
        reminderCount: admin.firestore.FieldValue.increment(1),
        lastReminderAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      billTitle: title,
      billAmount: 0,
      dueDate: admin.firestore.Timestamp.fromDate(dueDate),
    });
  }

  if (daysLeft < 0 && overdueReminderCount < MAX_OVERDUE_REMINDERS && gapOkForOverdue) {
    const nextOverdueCount = overdueReminderCount + 1;
    return sendNotificationBatch({
      expenseId,
      houseId,
      createdBy,
      title: reminderTitle('bill_overdue_reminder'),
      body: reminderBody('bill_overdue_reminder', title, Number(data.perPersonAmount || 0)),
      type: 'bill_overdue_reminder',
      targets,
      notificationIdSuffix: `bill_overdue_reminder_${nextOverdueCount}`,
      reminderPatch: {
        overdueReminderCount: admin.firestore.FieldValue.increment(1),
        lastReminderAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      billTitle: title,
      billAmount: Number(data.perPersonAmount || 0),
      dueDate: admin.firestore.Timestamp.fromDate(dueDate),
    });
  }

  logNotification('reminder skipped', {
    expenseId,
    reason: 'window_not_open_or_not_due',
    daysLeft,
    reminderCount,
    overdueReminderCount,
  });

  return false;
}

async function getHouseMembers(houseId, senderId) {
  const houseSnapshot = await db.collection('houses').doc(houseId).get();
  if (!houseSnapshot.exists) {
    return [];
  }

  const houseData = houseSnapshot.data() || {};
  const members = Array.isArray(houseData.members) ? houseData.members : [];
  return members
    .map((memberId) => (memberId || '').toString().trim())
    .filter((memberId) => memberId && memberId !== senderId)
    .map((userId) => ({ userId }));
}

exports.sendPushOnHouseChatMessage = functions.firestore
  .document('house_chats/{houseId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const { houseId, messageId } = context.params;
    const data = snap.data() || {};
    const senderId = (data.senderId || '').toString().trim();
    const senderName = (data.senderName || 'Member').toString().trim() || 'Member';
    const text = (data.text || '').toString().trim();

    if (!houseId || !messageId || !senderId || !text) {
      logNotification('chat push skipped', {
        houseId,
        messageId,
        senderId,
        reason: 'missing_required_fields',
      });
      return null;
    }

    const targets = await getHouseMembers(houseId, senderId);
    if (!targets.length) {
      logNotification('chat push skipped', { houseId, messageId, reason: 'no_targets' });
      return null;
    }

    return sendHouseMessageNotificationBatch({
      houseId,
      messageId,
      senderId,
      senderName,
      text,
      targets,
    });
  });

/**
 * Relay in-app notification documents to FCM using the stored user token.
 * This keeps the existing Firestore notification collection intact.
 */
exports.sendPushOnUserNotification = functions.firestore
  .document('user_notifications/{userId}/notifications/{notifId}')
  .onCreate(async (snap, context) => {
    const { userId } = context.params;
    const notif = snap.data() || {};
    const notificationId = context.params.notifId;

    if (notif.pushSentAt) {
      logNotification('push skipped', { userId, notificationId, reason: 'already_sent' });
      return null;
    }

    const title = notif.title || 'Roovia';
    const body = notif.body || '';
    const data = {
      type: notif.type || '',
      expenseId: notif.expenseId || '',
      houseId: notif.houseId || '',
      notificationId,
    };

    try {
      const userDoc = await db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        logNotification('push skipped', { userId, notificationId, reason: 'missing_user_doc' });
        return null;
      }

      const userData = userDoc.data() || {};
      const token = typeof userData.fcmToken === 'string' ? userData.fcmToken.trim() : '';
      if (!token) {
        logNotification('push skipped', { userId, notificationId, reason: 'missing_token' });
        return null;
      }

      const response = await admin.messaging().send({
        token,
        notification: {
          title,
          body,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'roovia_channel',
            sound: 'default',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
        data,
      });

      await snap.ref.set(
        {
          pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
          pushMessageId: response,
        },
        { merge: true },
      );

      logNotification('push sent', { userId, notificationId, response });
      return response;
    } catch (error) {
      const code = error && error.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        logNotification('token invalid', { userId, notificationId, code });
        await db.collection('users').doc(userId).set(
          { fcmToken: admin.firestore.FieldValue.delete() },
          { merge: true },
        );
      } else {
        console.error('Error sending FCM', error);
      }

      await snap.ref.set(
        {
          pushFailedAt: admin.firestore.FieldValue.serverTimestamp(),
          pushErrorCode: code || 'unknown',
        },
        { merge: true },
      );
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
