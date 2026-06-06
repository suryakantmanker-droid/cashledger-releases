const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

/**
 * Triggered when a new notification document is created in Firestore.
 * Reads the target user's FCM token from user_tokens/{userId}
 * and sends a push notification via FCM.
 */
exports.sendPushOnNotification = onDocumentCreated(
  'notifications/{notificationId}',
  async (event) => {
    const notification = event.data.data();
    if (!notification) return;

    const { userId, title, body, type, data } = notification;
    if (!userId || !title || !body) return;

    try {
      // Get FCM token from user_tokens collection
      const tokenDoc = await getFirestore()
        .collection('user_tokens')
        .doc(userId)
        .get();

      if (!tokenDoc.exists) {
        console.log(`No FCM token for user ${userId}`);
        return;
      }

      const fcmToken = tokenDoc.data().fcmToken;
      if (!fcmToken) {
        console.log(`Empty FCM token for user ${userId}`);
        return;
      }

      // Bug fix #2: count actual unread notifications for the badge
      const unreadSnap = await getFirestore()
        .collection('notifications')
        .where('userId', '==', userId)
        .where('isRead', '==', false)
        .get();
      const badgeCount = unreadSnap.size; // includes this new notification

      // Build the FCM message
      const message = {
        token: fcmToken,
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: type || '',
          ...Object.fromEntries(
            Object.entries(data || {}).map(([k, v]) => [k, String(v)])
          ),
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          notification: {
            channelId: 'expense_tracker_channel',
            priority: 'high',
            sound: 'default',
          },
          priority: 'high',
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: badgeCount,
            },
          },
        },
      };

      const response = await getMessaging().send(message);
      console.log(`Push sent to ${userId}: ${response}`);
    } catch (error) {
      // Token may be invalid/expired — log but don't throw
      console.error(`Push send failed for ${userId}:`, error.message);
    }
  }
);
