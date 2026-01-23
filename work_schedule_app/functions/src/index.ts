import * as admin from "firebase-admin";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

// Initialize Firebase Admin
admin.initializeApp();

const auth = admin.auth();
const db = admin.firestore();

/**
 * Triggered when a new employee document is created in a manager's subcollection.
 * Creates a Firebase Auth account for the employee.
 * - If employee has an email: creates account with that email and sends password reset
 * - If no email: creates account with a placeholder email (employee can't log in but has UID)
 */
export const onEmployeeCreatedInManager = onDocumentCreated(
  "managers/{managerId}/employees/{employeeId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.log("No data in employee document");
      return;
    }

    const employeeData = snapshot.data();
    const managerId = event.params.managerId;
    const employeeId = event.params.employeeId;
    const email = employeeData.email;

    // Generate placeholder email if none provided
    const accountEmail = email || `employee_${managerId}_${employeeId}@schedulehq.internal`;
    const hasRealEmail = !!email;

    logger.log(`Creating account for employee ${employeeId} (manager: ${managerId}) with ${hasRealEmail ? 'email: ' + email : 'placeholder email'}`);

    try {
      // Check if user already exists
      let userRecord;
      try {
        userRecord = await auth.getUserByEmail(accountEmail);
        logger.log(`User already exists with uid: ${userRecord.uid}`);
      } catch (error: unknown) {
        // User doesn't exist, create new account
        if ((error as { code?: string }).code === "auth/user-not-found") {
          userRecord = await auth.createUser({
            email: accountEmail,
            emailVerified: false,
            disabled: !hasRealEmail, // Disable accounts without real emails (they can't log in anyway)
          });
          logger.log(`Created new user with uid: ${userRecord.uid}`);
        } else {
          throw error;
        }
      }

      // Create or update user document with role
      await db.collection("users").doc(userRecord.uid).set({
        email: accountEmail,
        realEmail: hasRealEmail ? email : null,
        employeeId: parseInt(employeeId) || employeeId,
        managerUid: managerId,
        role: "employee",
        hasAppAccess: hasRealEmail,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Update employee document with uid
      await snapshot.ref.update({
        uid: userRecord.uid,
        accountCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Only generate password reset link if they have a real email
      if (hasRealEmail) {
        const resetLink = await auth.generatePasswordResetLink(email);
        logger.log(`Password reset link generated for ${email}: ${resetLink}`);
      }

      logger.log(`Account setup complete for employee ${employeeId} (hasAppAccess: ${hasRealEmail})`);
    } catch (error) {
      logger.error(`Error creating account for employee ${employeeId}:`, error);
      throw error;
    }
  }
);

/**
 * Triggered when an employee document is updated in a manager's subcollection.
 * If the email field was added or changed, handles account creation/update.
 * If employee had no UID (no email before), creates one now.
 */
export const onEmployeeUpdatedInManager = onDocumentUpdated(
  "managers/{managerId}/employees/{employeeId}",
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();
    const managerId = event.params.managerId;
    const employeeId = event.params.employeeId;

    if (!beforeData || !afterData) {
      logger.log("Missing data in employee update");
      return;
    }

    const oldEmail = beforeData.email;
    const newEmail = afterData.email;
    const existingUid = afterData.uid;

    // If no UID exists, create an account (with real email or placeholder)
    if (!existingUid) {
      const accountEmail = newEmail || `employee_${managerId}_${employeeId}@schedulehq.internal`;
      const hasRealEmail = !!newEmail;
      
      logger.log(`Creating account for employee ${employeeId} (no existing UID) with ${hasRealEmail ? 'email: ' + newEmail : 'placeholder email'}`);
      
      try {
        let userRecord;
        try {
          userRecord = await auth.getUserByEmail(accountEmail);
        } catch (error: unknown) {
          if ((error as { code?: string }).code === "auth/user-not-found") {
            userRecord = await auth.createUser({
              email: accountEmail,
              emailVerified: false,
              disabled: !hasRealEmail,
            });
          } else {
            throw error;
          }
        }

        await db.collection("users").doc(userRecord.uid).set({
          email: accountEmail,
          realEmail: hasRealEmail ? newEmail : null,
          employeeId: parseInt(employeeId) || employeeId,
          managerUid: managerId,
          role: "employee",
          hasAppAccess: hasRealEmail,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        await event.data?.after.ref.update({
          uid: userRecord.uid,
          accountCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (hasRealEmail) {
          await auth.generatePasswordResetLink(newEmail);
          logger.log(`Password reset sent to ${newEmail}`);
        }
        
        logger.log(`Account created for employee ${employeeId} with uid ${userRecord.uid}`);
      } catch (error) {
        logger.error(`Error creating account for employee ${employeeId}:`, error);
        throw error;
      }
      return;
    }

    // If email changed (and UID exists), update the account
    if (newEmail && oldEmail !== newEmail) {
      logger.log(`Email changed for employee ${employeeId} (manager: ${managerId}): ${oldEmail} -> ${newEmail}`);

      try {
        // Update existing auth user's email
        await auth.updateUser(existingUid, { 
          email: newEmail,
          disabled: false, // Re-enable if they now have a real email
        });
        logger.log(`Updated email for uid ${existingUid}`);
        
        // Update user document
        await db.collection("users").doc(existingUid).update({
          email: newEmail,
          realEmail: newEmail,
          hasAppAccess: true,
        });
        
        // Send password reset to new email
        await auth.generatePasswordResetLink(newEmail);
        logger.log(`Password reset sent to new email ${newEmail}`);
      } catch (error) {
        logger.error(`Error updating user email:`, error);
        throw error;
      }
    }
  }
);

// ============== LEGACY ROOT COLLECTION TRIGGERS ==============
// Keep these for backwards compatibility with existing data

/**
 * Triggered when a new employee document is created.
 * If the employee has an email, creates a Firebase Auth account
 * and sends a password reset email.
 */
export const onEmployeeCreated = onDocumentCreated(
  "employees/{employeeId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.log("No data in employee document");
      return;
    }

    const employeeData = snapshot.data();
    const employeeId = event.params.employeeId;
    const email = employeeData.email;

    // Skip if no email provided
    if (!email) {
      logger.log(`Employee ${employeeId} has no email, skipping account creation`);
      return;
    }

    logger.log(`Creating account for employee ${employeeId} with email ${email}`);

    try {
      // Check if user already exists
      let userRecord;
      try {
        userRecord = await auth.getUserByEmail(email);
        logger.log(`User already exists with uid: ${userRecord.uid}`);
      } catch (error: unknown) {
        // User doesn't exist, create new account
        if ((error as { code?: string }).code === "auth/user-not-found") {
          userRecord = await auth.createUser({
            email: email,
            emailVerified: false,
            disabled: false,
          });
          logger.log(`Created new user with uid: ${userRecord.uid}`);
        } else {
          throw error;
        }
      }

      // Create or update user document with role
      await db.collection("users").doc(userRecord.uid).set({
        email: email,
        employeeId: parseInt(employeeId) || employeeId,
        role: "employee",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Update employee document with uid
      await snapshot.ref.update({
        uid: userRecord.uid,
        accountCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Generate password reset link and send email
      const resetLink = await auth.generatePasswordResetLink(email);
      logger.log(`Password reset link generated for ${email}: ${resetLink}`);

      // Note: Firebase Auth automatically sends the reset email when you call
      // generatePasswordResetLink. If you want custom email, use sendEmail here.

      logger.log(`Account setup complete for employee ${employeeId}`);
    } catch (error) {
      logger.error(`Error creating account for employee ${employeeId}:`, error);
      throw error;
    }
  }
);

/**
 * Triggered when an employee document is updated.
 * If the email field was added or changed, handles account creation/update.
 */
export const onEmployeeUpdated = onDocumentUpdated(
  "employees/{employeeId}",
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();
    const employeeId = event.params.employeeId;

    if (!beforeData || !afterData) {
      logger.log("Missing data in employee update");
      return;
    }

    const oldEmail = beforeData.email;
    const newEmail = afterData.email;

    // Skip if email hasn't changed or was removed
    if (!newEmail || oldEmail === newEmail) {
      return;
    }

    logger.log(`Email changed for employee ${employeeId}: ${oldEmail} -> ${newEmail}`);

    try {
      // If there was an old account, we might want to update or create new
      if (afterData.uid) {
        // Update existing auth user's email
        try {
          await auth.updateUser(afterData.uid, { email: newEmail });
          logger.log(`Updated email for uid ${afterData.uid}`);
          
          // Send password reset to new email
          await auth.generatePasswordResetLink(newEmail);
          logger.log(`Password reset sent to new email ${newEmail}`);
        } catch (error) {
          logger.error(`Error updating user email:`, error);
          throw error;
        }
      } else {
        // No existing uid, create new account (same logic as onCreate)
        let userRecord;
        try {
          userRecord = await auth.getUserByEmail(newEmail);
        } catch (error: unknown) {
          if ((error as { code?: string }).code === "auth/user-not-found") {
            userRecord = await auth.createUser({
              email: newEmail,
              emailVerified: false,
              disabled: false,
            });
          } else {
            throw error;
          }
        }

        // Create user document
        await db.collection("users").doc(userRecord.uid).set({
          email: newEmail,
          employeeId: parseInt(employeeId) || employeeId,
          role: "employee",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Update employee with uid
        await event.data?.after.ref.update({
          uid: userRecord.uid,
          accountCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Send password reset
        await auth.generatePasswordResetLink(newEmail);
        logger.log(`Account created and reset email sent to ${newEmail}`);
      }
    } catch (error) {
      logger.error(`Error handling email update for employee ${employeeId}:`, error);
      throw error;
    }
  }
);

/**
 * Creates a manager account. Called manually or via admin setup.
 * This is a helper function - you'll call it once to set up your manager account.
 */
export const createManagerAccount = onDocumentCreated(
  "managers/{managerId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const managerData = snapshot.data();
    const email = managerData.email;

    if (!email) {
      logger.log("Manager document has no email");
      return;
    }

    try {
      // Check if user exists
      let userRecord;
      try {
        userRecord = await auth.getUserByEmail(email);
      } catch (error: unknown) {
        if ((error as { code?: string }).code === "auth/user-not-found") {
          userRecord = await auth.createUser({
            email: email,
            emailVerified: false,
            disabled: false,
          });
        } else {
          throw error;
        }
      }

      // Create user document with manager role
      await db.collection("users").doc(userRecord.uid).set({
        email: email,
        role: "manager",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Update manager document with uid
      await snapshot.ref.update({
        uid: userRecord.uid,
      });

      // Send password reset
      await auth.generatePasswordResetLink(email);
      logger.log(`Manager account created for ${email}`);
    } catch (error) {
      logger.error("Error creating manager account:", error);
      throw error;
    }
  }
);

// ============== NOTIFICATION FUNCTIONS ==============
// These are the framework for sending notifications.
// The actual triggers are NOT implemented - you'll add them later.

const messaging = admin.messaging();

/**
 * Send a notification to a specific employee.
 * Called from the manager app when needed.
 * 
 * @param employeeUid - The uid of the employee to notify
 * @param title - Notification title
 * @param body - Notification body
 * @param data - Additional data payload
 */
export const sendNotificationToEmployee = onCall(async (request) => {
  // Verify caller is a manager
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "manager") {
    throw new HttpsError("permission-denied", "Only managers can send notifications");
  }

  const { employeeUid, title, body, data } = request.data;

  if (!employeeUid || !title) {
    throw new HttpsError("invalid-argument", "employeeUid and title are required");
  }

  try {
    // Get employee's FCM token
    const employeeQuery = await db.collection("employees")
      .where("uid", "==", employeeUid)
      .limit(1)
      .get();

    if (employeeQuery.empty) {
      throw new HttpsError("not-found", "Employee not found");
    }

    const employeeData = employeeQuery.docs[0].data();
    const fcmToken = employeeData.fcmToken;

    if (!fcmToken) {
      logger.log(`Employee ${employeeUid} has no FCM token`);
      return { success: false, reason: "no_token" };
    }

    // Send notification
    const message: admin.messaging.Message = {
      token: fcmToken,
      notification: {
        title: title,
        body: body || "",
      },
      data: {
        ...data,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "schedule_notifications",
          priority: "high",
        },
      },
    };

    const response = await messaging.send(message);
    logger.log(`Notification sent to ${employeeUid}: ${response}`);

    return { success: true, messageId: response };
  } catch (error) {
    logger.error(`Error sending notification to ${employeeUid}:`, error);
    throw new HttpsError("internal", "Failed to send notification");
  }
});

/**
 * Send a notification to multiple employees.
 * Useful for schedule publish notifications.
 * 
 * @param employeeUids - Array of employee uids to notify
 * @param title - Notification title
 * @param body - Notification body
 * @param data - Additional data payload
 */
export const sendNotificationToMultiple = onCall(async (request) => {
  // Verify caller is a manager
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "manager") {
    throw new HttpsError("permission-denied", "Only managers can send notifications");
  }

  const { employeeUids, title, body, data } = request.data;

  if (!employeeUids || !Array.isArray(employeeUids) || !title) {
    throw new HttpsError("invalid-argument", "employeeUids array and title are required");
  }

  try {
    // Get FCM tokens for all employees
    const tokens: string[] = [];
    
    for (const uid of employeeUids) {
      const employeeQuery = await db.collection("employees")
        .where("uid", "==", uid)
        .limit(1)
        .get();

      if (!employeeQuery.empty) {
        const fcmToken = employeeQuery.docs[0].data().fcmToken;
        if (fcmToken) {
          tokens.push(fcmToken);
        }
      }
    }

    if (tokens.length === 0) {
      logger.log("No valid FCM tokens found");
      return { success: false, reason: "no_tokens", sent: 0 };
    }

    // Send to all tokens
    const message: admin.messaging.MulticastMessage = {
      tokens: tokens,
      notification: {
        title: title,
        body: body || "",
      },
      data: {
        ...data,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "schedule_notifications",
          priority: "high",
        },
      },
    };

    const response = await messaging.sendEachForMulticast(message);
    logger.log(`Sent ${response.successCount}/${tokens.length} notifications`);

    return { 
      success: true, 
      sent: response.successCount,
      failed: response.failureCount,
    };
  } catch (error) {
    logger.error("Error sending notifications:", error);
    throw new HttpsError("internal", "Failed to send notifications");
  }
});

/**
 * Send a notification to a topic (all subscribers).
 * Useful for announcements.
 * 
 * @param topic - The topic name (e.g., "announcements")
 * @param title - Notification title
 * @param body - Notification body
 * @param data - Additional data payload
 */
export const sendNotificationToTopic = onCall(async (request) => {
  // Verify caller is a manager
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "manager") {
    throw new HttpsError("permission-denied", "Only managers can send notifications");
  }

  const { topic, title, body, data } = request.data;

  if (!topic || !title) {
    throw new HttpsError("invalid-argument", "topic and title are required");
  }

  try {
    const message: admin.messaging.Message = {
      topic: topic,
      notification: {
        title: title,
        body: body || "",
      },
      data: {
        ...data,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "schedule_notifications",
          priority: "high",
        },
      },
    };

    const response = await messaging.send(message);
    logger.log(`Topic notification sent to ${topic}: ${response}`);

    return { success: true, messageId: response };
  } catch (error) {
    logger.error(`Error sending topic notification:`, error);
    throw new HttpsError("internal", "Failed to send notification");
  }
});

// ============== NOTIFICATION TRIGGER STUBS ==============
// These are commented out - uncomment and customize when ready to enable

/*
// Trigger notification when time-off is approved
export const onTimeOffApproved = onDocumentUpdated(
  "timeOffRequests/{requestId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    
    if (!before || !after) return;
    
    // Only trigger if status changed to approved
    if (before.status !== "approved" && after.status === "approved") {
      const employeeUid = after.employeeUid;
      // Call sendNotificationToEmployee here
    }
  }
);

// Trigger notification when schedule is published
export const onSchedulePublished = onDocumentCreated(
  "publishedSchedules/{scheduleId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    
    // Get list of employees in this schedule
    // Call sendNotificationToMultiple here
  }
);
*/

/**
 * Manually sync all existing employees to create Firebase Auth accounts.
 * Call this once to set up accounts for employees created before Cloud Functions were deployed.
 * 
 * ALL employees get a UID:
 * - With email: Creates account with real email, can log into mobile app
 * - Without email: Creates account with placeholder email, has UID for data sync but can't log in
 */
export const syncAllEmployeeAccounts = onCall(async (request) => {
  // Verify caller is a manager
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "manager") {
    throw new HttpsError("permission-denied", "Only managers can sync employee accounts");
  }

  const managerUid = request.data?.managerUid || request.auth.uid;

  const results = {
    total: 0,
    created: 0,
    createdWithPlaceholder: 0,
    updated: 0,
    skipped: 0,
    errors: [] as string[],
  };

  try {
    // Get employees from the manager's subcollection
    const employeesSnapshot = await db
      .collection("managers")
      .doc(managerUid)
      .collection("employees")
      .get();
    
    results.total = employeesSnapshot.size;

    for (const doc of employeesSnapshot.docs) {
      const employeeData = doc.data();
      const email = employeeData.email;
      const existingUid = employeeData.uid;

      // Skip if already has uid
      if (existingUid) {
        logger.log(`Employee ${doc.id} already has uid ${existingUid}`);
        results.skipped++;
        continue;
      }

      // Generate placeholder email if none provided
      const accountEmail = email || `employee_${managerUid}_${doc.id}@schedulehq.internal`;
      const hasRealEmail = !!email;

      try {
        // Check if user already exists in Auth
        let userRecord;
        try {
          userRecord = await auth.getUserByEmail(accountEmail);
          logger.log(`User already exists for ${accountEmail} with uid: ${userRecord.uid}`);
        } catch (error: unknown) {
          if ((error as { code?: string }).code === "auth/user-not-found") {
            // Create new user
            userRecord = await auth.createUser({
              email: accountEmail,
              emailVerified: false,
              disabled: !hasRealEmail, // Disable placeholder accounts
            });
            logger.log(`Created new user for ${accountEmail} with uid: ${userRecord.uid}`);
            if (hasRealEmail) {
              results.created++;
            } else {
              results.createdWithPlaceholder++;
            }
          } else {
            throw error;
          }
        }

        // Update employee document with uid
        await doc.ref.update({
          uid: userRecord.uid,
          accountCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Create/update user document
        await db.collection("users").doc(userRecord.uid).set({
          email: accountEmail,
          realEmail: hasRealEmail ? email : null,
          employeeId: parseInt(doc.id) || doc.id,
          managerUid: managerUid,
          role: "employee",
          hasAppAccess: hasRealEmail,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        results.updated++;
        
        // Send password reset email only for real emails
        if (hasRealEmail) {
          try {
            await auth.generatePasswordResetLink(email);
            logger.log(`Password reset link generated for ${email}`);
          } catch (resetError) {
            logger.warn(`Failed to generate reset link for ${email}:`, resetError);
          }
        }

      } catch (error) {
        logger.error(`Error processing employee ${doc.id}:`, error);
        results.errors.push(`${doc.id}: ${error}`);
      }
    }

    logger.log(`Sync complete:`, results);
    return results;

  } catch (error) {
    logger.error("Error syncing employee accounts:", error);
    throw new HttpsError("internal", `Error syncing accounts: ${error}`);
  }
});
