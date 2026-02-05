import * as admin from "firebase-admin";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { logger } from "firebase-functions/v2";
import { parse } from "csv-parse/sync";

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

/**
 * Creates a new manager account with server-side auth code validation.
 * The auth code is stored in Firestore at settings/managerAuthCode.
 * 
 * @param email - Manager's email address
 * @param password - Manager's password
 * @param displayName - Manager's display name
 * @param authCode - Authorization code to validate
 */
export const createManagerAccountWithAuthCode = onCall(
  { invoker: "public" },  // Allow unauthenticated access - we validate via auth code
  async (request) => {
  const { email, password, displayName, authCode } = request.data;

  // Validate required fields
  if (!email || !password || !authCode) {
    throw new HttpsError("invalid-argument", "Email, password, and authorization code are required");
  }

  // Validate email format
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    throw new HttpsError("invalid-argument", "Invalid email format");
  }

  // Validate password length
  if (password.length < 6) {
    throw new HttpsError("invalid-argument", "Password must be at least 6 characters");
  }

  try {
    // Get the stored auth code from Firestore
    const authCodeDoc = await db.collection("settings").doc("managerAuthCode").get();
    
    if (!authCodeDoc.exists) {
      logger.error("Manager auth code not configured in Firestore");
      throw new HttpsError("failed-precondition", "Authorization system not configured. Contact administrator.");
    }

    const storedAuthCode = authCodeDoc.data()?.code;
    if (!storedAuthCode) {
      logger.error("Manager auth code document exists but has no code field");
      throw new HttpsError("failed-precondition", "Authorization system not configured. Contact administrator.");
    }

    // Validate the auth code (case-insensitive comparison)
    if (authCode.trim().toLowerCase() !== storedAuthCode.trim().toLowerCase()) {
      logger.warn(`Invalid auth code attempt for email: ${email}`);
      throw new HttpsError("permission-denied", "Invalid authorization code");
    }

    // Check if user already exists
    try {
      await auth.getUserByEmail(email);
      throw new HttpsError("already-exists", "An account with this email already exists");
    } catch (error: unknown) {
      if ((error as { code?: string }).code !== "auth/user-not-found") {
        throw error;
      }
      // User doesn't exist, which is what we want
    }

    // Create the Firebase Auth user
    const userRecord = await auth.createUser({
      email: email,
      password: password,
      displayName: displayName || undefined,
      emailVerified: false,
    });

    // Create user document with manager role
    await db.collection("users").doc(userRecord.uid).set({
      email: email,
      displayName: displayName || null,
      role: "manager",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.log(`Manager account created via auth code for ${email} (uid: ${userRecord.uid})`);

    return { 
      success: true, 
      uid: userRecord.uid,
      message: "Manager account created successfully" 
    };

  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("Error creating manager account:", error);
    throw new HttpsError("internal", "Failed to create account. Please try again.");
  }
});

/**
 * Updates the manager authorization code. Only callable by existing managers.
 * 
 * @param newCode - The new authorization code
 */
export const updateManagerAuthCode = onCall(
  { invoker: "public" },  // Public access but we verify auth internally
  async (request) => {
  // Verify caller is authenticated
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  // Verify caller is a manager
  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "manager") {
    throw new HttpsError("permission-denied", "Only managers can update the authorization code");
  }

  const { newCode } = request.data;

  if (!newCode || typeof newCode !== "string" || newCode.trim().length === 0) {
    throw new HttpsError("invalid-argument", "New authorization code is required");
  }

  try {
    await db.collection("settings").doc("managerAuthCode").set({
      code: newCode.trim(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth.uid,
    });

    logger.log(`Manager auth code updated by ${request.auth.uid}`);
    return { success: true, message: "Authorization code updated successfully" };

  } catch (error) {
    logger.error("Error updating auth code:", error);
    throw new HttpsError("internal", "Failed to update authorization code");
  }
});

/**
 * Gets the current manager authorization code. Only callable by existing managers.
 */
export const getManagerAuthCode = onCall(
  { invoker: "public" },  // Public access but we verify auth internally
  async (request) => {
  // Verify caller is authenticated
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  // Verify caller is a manager
  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "manager") {
    throw new HttpsError("permission-denied", "Only managers can view the authorization code");
  }

  try {
    const authCodeDoc = await db.collection("settings").doc("managerAuthCode").get();
    
    if (!authCodeDoc.exists) {
      return { code: null, message: "No authorization code configured" };
    }

    return { 
      code: authCodeDoc.data()?.code || null,
      updatedAt: authCodeDoc.data()?.updatedAt || null,
    };

  } catch (error) {
    logger.error("Error getting auth code:", error);
    throw new HttpsError("internal", "Failed to retrieve authorization code");
  }
});

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
  const managerUid = request.auth.uid;

  if (!employeeUid || !title) {
    throw new HttpsError("invalid-argument", "employeeUid and title are required");
  }

  try {
    // Get employee's FCM token from manager's subcollection
    const employeeQuery = await db.collection("managers")
      .doc(managerUid)
      .collection("employees")
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
  const managerUid = request.auth.uid;

  if (!employeeUids || !Array.isArray(employeeUids) || !title) {
    throw new HttpsError("invalid-argument", "employeeUids array and title are required");
  }

  try {
    // Get FCM tokens for all employees from manager's subcollection
    const tokens: string[] = [];
    
    for (const uid of employeeUids) {
      const employeeQuery = await db.collection("managers")
        .doc(managerUid)
        .collection("employees")
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
 * Check if a UID looks like a valid Firebase Auth UID.
 * Firebase UIDs are typically 28 characters of alphanumeric characters.
 */
function isValidFirebaseUid(uid: string | undefined | null): boolean {
  if (!uid || uid.length < 20) return false;
  if (uid.toLowerCase() === "admin") return false;
  return /^[a-zA-Z0-9]+$/.test(uid);
}

/**
 * Fix employees with invalid UIDs (like "Admin").
 * This will clear the invalid UID and create a proper Firebase Auth account.
 * Also updates the users collection appropriately (but won't change existing manager roles).
 */
export const fixInvalidEmployeeUids = onCall(async (request) => {
  // Verify caller is a manager
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "manager") {
    throw new HttpsError("permission-denied", "Only managers can fix employee UIDs");
  }

  const managerUid = request.data?.managerUid || request.auth.uid;
  const specificEmployeeId = request.data?.employeeId; // Optional: fix specific employee only

  const results = {
    total: 0,
    fixed: 0,
    alreadyValid: 0,
    noUid: 0,
    errors: [] as string[],
  };

  try {
    let query: admin.firestore.Query = db
      .collection("managers")
      .doc(managerUid)
      .collection("employees");
    
    if (specificEmployeeId) {
      // Get specific employee only
      const doc = await db
        .collection("managers")
        .doc(managerUid)
        .collection("employees")
        .doc(specificEmployeeId.toString())
        .get();
      
      if (!doc.exists) {
        throw new HttpsError("not-found", `Employee ${specificEmployeeId} not found`);
      }
      
      const employeeData = doc.data()!;
      const existingUid = employeeData.uid;
      const email = employeeData.email;
      
      if (!existingUid) {
        results.noUid++;
      } else if (isValidFirebaseUid(existingUid)) {
        results.alreadyValid++;
      } else {
        // Invalid UID - fix it
        logger.log(`Fixing invalid UID "${existingUid}" for employee ${doc.id}`);
        
        const accountEmail = email || `employee_${managerUid}_${doc.id}@schedulehq.internal`;
        const hasRealEmail = !!email;
        
        let userRecord;
        try {
          userRecord = await auth.getUserByEmail(accountEmail);
          logger.log(`Found existing user for ${accountEmail}: ${userRecord.uid}`);
        } catch (error: unknown) {
          if ((error as { code?: string }).code === "auth/user-not-found") {
            userRecord = await auth.createUser({
              email: accountEmail,
              emailVerified: false,
              disabled: !hasRealEmail,
            });
            logger.log(`Created new user for ${accountEmail}: ${userRecord.uid}`);
          } else {
            throw error;
          }
        }
        
        // Update employee with correct UID
        await doc.ref.update({
          uid: userRecord.uid,
          previousInvalidUid: existingUid,
          uidFixedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        // Only create/update users doc if this UID doesn't already have a role
        const existingUserDoc = await db.collection("users").doc(userRecord.uid).get();
        if (!existingUserDoc.exists) {
          await db.collection("users").doc(userRecord.uid).set({
            email: accountEmail,
            realEmail: hasRealEmail ? email : null,
            employeeId: parseInt(doc.id) || doc.id,
            managerUid: managerUid,
            role: "employee",
            hasAppAccess: hasRealEmail,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        
        results.fixed++;
      }
      
      results.total = 1;
      return results;
    }

    // Process all employees
    const employeesSnapshot = await query.get();
    results.total = employeesSnapshot.size;

    for (const doc of employeesSnapshot.docs) {
      const employeeData = doc.data();
      const existingUid = employeeData.uid;
      const email = employeeData.email;

      if (!existingUid) {
        results.noUid++;
        continue;
      }

      if (isValidFirebaseUid(existingUid)) {
        results.alreadyValid++;
        continue;
      }

      // Invalid UID - fix it
      logger.log(`Fixing invalid UID "${existingUid}" for employee ${doc.id} (${employeeData.name})`);

      const accountEmail = email || `employee_${managerUid}_${doc.id}@schedulehq.internal`;
      const hasRealEmail = !!email;

      try {
        let userRecord;
        try {
          userRecord = await auth.getUserByEmail(accountEmail);
          logger.log(`Found existing user for ${accountEmail}: ${userRecord.uid}`);
        } catch (error: unknown) {
          if ((error as { code?: string }).code === "auth/user-not-found") {
            userRecord = await auth.createUser({
              email: accountEmail,
              emailVerified: false,
              disabled: !hasRealEmail,
            });
            logger.log(`Created new user for ${accountEmail}: ${userRecord.uid}`);
          } else {
            throw error;
          }
        }

        // Update employee with correct UID
        await doc.ref.update({
          uid: userRecord.uid,
          previousInvalidUid: existingUid,
          uidFixedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Only create/update users doc if this UID doesn't already have a role
        // This prevents overwriting manager roles
        const existingUserDoc = await db.collection("users").doc(userRecord.uid).get();
        if (!existingUserDoc.exists) {
          await db.collection("users").doc(userRecord.uid).set({
            email: accountEmail,
            realEmail: hasRealEmail ? email : null,
            employeeId: parseInt(doc.id) || doc.id,
            managerUid: managerUid,
            role: "employee",
            hasAppAccess: hasRealEmail,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        results.fixed++;

      } catch (error) {
        logger.error(`Error fixing employee ${doc.id}:`, error);
        results.errors.push(`${doc.id}: ${error}`);
      }
    }

    logger.log(`Fix complete:`, results);
    return results;

  } catch (error) {
    logger.error("Error fixing employee UIDs:", error);
    throw new HttpsError("internal", `Error fixing UIDs: ${error}`);
  }
});

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

// =============================================================================
// Shift Manager CSV Processing
// =============================================================================

/**
 * Shift Manager Report entry structure
 */
interface ShiftManagerEntry {
  employeeId: number;
  managerName: string;
  timeSlice: string;
  allNetSales: number;
  numberOfShifts: number;
  gc: number;
  dtPulledForwardPct: number;
  kvsHealthyUsage: number;
  oepe: number;
  punchLaborPct: number;
  dtGc: number;
  tpph: number;
  averageCheck: number;
  actVsNeed: number;
  r2p: number;
}

/**
 * Hourly Summary entry structure (aggregated by shift type)
 * Used when processing hourly CSV format with "End Time" column
 */
interface HourlySummaryEntry {
  employeeId: number;      // From shiftRunner lookup, -1 if unassigned
  runnerName: string;      // From shiftRunner or "Unassigned"
  shiftType: string;       // Shift type key (e.g., "open", "lunch", "close")
  shiftLabel: string;      // Shift type label (e.g., "Open", "Lunch", "Close")
  allNetSales: number;     // SUM
  stwGc: number;           // SUM (STW GC column)
  oepe: number;            // AVG
  kvsTimePerItem: number;  // AVG
  kvsHealthyUsage: number; // AVG
  dtPullForwardPct: number;// AVG
  punchLaborPct: number;   // AVG
  tpph: number;            // AVG
  r2p: number;             // SUM
}

/**
 * Shift type definition from managerSettings
 */
interface ShiftType {
  id: number;
  key: string;
  label: string;
  rangeStart: string;  // "HH:mm" format
  rangeEnd: string;    // "HH:mm" format
  sortOrder: number;
}

/**
 * Parse a numeric value from CSV, handling various formats
 */
function parseNumber(value: string | undefined): number {
  if (!value) return 0;
  // Remove $ signs, commas, and % signs
  const cleaned = value.toString().replace(/[$,%]/g, "").trim();
  const num = parseFloat(cleaned);
  return isNaN(num) ? 0 : num;
}

/**
 * Get column value from CSV row with flexible matching
 * Handles BOM, whitespace, and case differences in column names
 */
function getColumn(row: Record<string, string>, columnName: string): string {
  // Try exact match first
  if (row[columnName] !== undefined) {
    return row[columnName]?.toString().trim() || "";
  }
  
  // Try case-insensitive, whitespace-trimmed match
  // Also strips BOM and other invisible characters
  const normalizedTarget = columnName.toLowerCase().trim().replace(/[\ufeff\u200b]/g, "");
  
  for (const key of Object.keys(row)) {
    const normalizedKey = key.toLowerCase().trim().replace(/[\ufeff\u200b]/g, "");
    if (normalizedKey === normalizedTarget) {
      return row[key]?.toString().trim() || "";
    }
  }
  
  return "";
}

/**
 * Normalize manager name from "LastName, FirstName" to "FirstName LastName" format
 * to match employee name field in Firestore
 */
function normalizeManagerName(name: string): string | null {
  if (!name || typeof name !== "string") return null;
  
  const trimmedName = name.trim();
  const parts = trimmedName.split(",").map(p => p.trim());
  
  if (parts.length === 2 && parts[0] && parts[1]) {
    // "LastName, FirstName" → "FirstName LastName"
    return `${parts[1]} ${parts[0]}`;
  }
  
  // Already in "FirstName LastName" format or single name
  return trimmedName || null;
}

/**
 * Extract date from filename like "ShiftManager_17495_2026-02-03.csv"
 */
function extractDateFromFilename(filename: string): string {
  // Try to find date pattern YYYY-MM-DD
  const dateMatch = filename.match(/(\d{4}-\d{2}-\d{2})/);
  if (dateMatch) {
    return dateMatch[1];
  }
  // Default to today's date
  const today = new Date();
  return today.toISOString().split("T")[0];
}

/**
 * CSV Format Types
 */
type CsvFormat = "manager" | "hourly";

/**
 * Detect CSV format based on column headers
 * - "manager" format: has "Time Slice" and "Manager Name" columns (original format)
 * - "hourly" format: has "End Time" column (new hourly summary format)
 */
function detectCsvFormat(row: Record<string, string>): CsvFormat {
  const hasEndTime = getColumn(row, "End Time") !== "";
  const hasTimeSlice = getColumn(row, "Time Slice") !== "";
  const hasManagerName = getColumn(row, "Manager Name") !== "";

  if (hasEndTime && !hasTimeSlice) {
    return "hourly";
  }
  if (hasTimeSlice && hasManagerName) {
    return "manager";
  }
  // Default to hourly if End Time exists
  return hasEndTime ? "hourly" : "manager";
}

/**
 * Parse "End Time" column value (e.g., "5:00", "13:00", "25:00")
 * Returns hour in 0-23 range (values >= 24 are normalized by subtracting 24)
 */
function parseEndTimeHour(value: string): number {
  if (!value) return -1;
  const cleaned = value.trim();
  // Match H:MM or HH:MM format
  const match = cleaned.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return -1;
  
  let hour = parseInt(match[1], 10);
  // Normalize hours past midnight (25:00 → 1, 26:00 → 2, etc.)
  if (hour >= 24) {
    hour = hour - 24;
  }
  return hour;
}

/**
 * Check if a CSV row is a "total" row that should be skipped
 */
function isTotalRow(row: Record<string, string>): boolean {
  const loc = getColumn(row, "Loc").toLowerCase();
  const endTime = getColumn(row, "End Time").toLowerCase();
  return loc === "total" || endTime === "total";
}

/**
 * Check if all metric columns in a row are zero/empty
 * @param row CSV row to check
 * @returns true if all metrics are zero and row should be skipped
 */
function isAllZeroRow(row: Record<string, string>): boolean {
  const metrics = [
    parseNumber(getColumn(row, "All Net Sales")),
    parseNumber(getColumn(row, "STW GC")),
    parseNumber(getColumn(row, "OEPE")),
    parseNumber(getColumn(row, "KVS Time Per Item")),
    parseNumber(getColumn(row, "KVS Healthy Usage")),
    parseNumber(getColumn(row, "DT Pull Forward %")),
    parseNumber(getColumn(row, "Punch Labor")),
    parseNumber(getColumn(row, "TPPH")),
    parseNumber(getColumn(row, "R2P")),
  ];
  return metrics.every(m => m === 0);
}

/**
 * Parse time string "HH:mm" to minutes since midnight
 */
function parseTimeToMinutes(timeStr: string): number {
  const match = timeStr.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return 0;
  return parseInt(match[1], 10) * 60 + parseInt(match[2], 10);
}

/**
 * Determine which shift type an hour belongs to based on shift ranges
 * The "end time" in CSV represents the END of that hour's data
 * e.g., "6:00" means data from 5:00-6:00, so we use hour-1 for matching
 * 
 * @param endTimeHour The hour from "End Time" column (already normalized 0-23)
 * @param shiftTypes Array of shift type definitions with rangeStart/rangeEnd
 * @returns The matching shift type key, or null if no match
 */
function getShiftTypeForHour(endTimeHour: number, shiftTypes: ShiftType[]): ShiftType | null {
  // End Time represents end of the hour bucket, so 6:00 means the 5:00-5:59 period
  // Use endTimeHour - 1 to get the actual hour the data represents
  const dataHour = endTimeHour === 0 ? 23 : endTimeHour - 1;
  const dataMinutes = dataHour * 60;

  for (const st of shiftTypes) {
    const rangeStart = parseTimeToMinutes(st.rangeStart);
    let rangeEnd = parseTimeToMinutes(st.rangeEnd);

    // Handle overnight ranges (e.g., 20:00 to 01:00)
    if (rangeEnd <= rangeStart) {
      // Overnight shift: either dataMinutes >= rangeStart OR dataMinutes < rangeEnd
      if (dataMinutes >= rangeStart || dataMinutes < rangeEnd) {
        return st;
      }
    } else {
      // Normal daytime shift
      if (dataMinutes >= rangeStart && dataMinutes < rangeEnd) {
        return st;
      }
    }
  }
  return null;
}

/**
 * Raw hourly data bucket for aggregation
 */
interface HourlyBucket {
  allNetSales: number;
  stwGc: number;
  oepe: number;
  kvsTimePerItem: number;
  kvsHealthyUsage: number;
  dtPullForwardPct: number;
  punchLaborPct: number;
  tpph: number;
  r2p: number;
}

/**
 * Aggregate hourly CSV rows into shift type buckets
 * 
 * @param records Parsed CSV rows
 * @param shiftTypes Shift type definitions from manager settings
 * @returns Map of shiftType key to aggregated HourlySummaryEntry (without employee info)
 */
function aggregateHourlyData(
  records: Record<string, string>[],
  shiftTypes: ShiftType[]
): Map<string, { shiftType: ShiftType; sumData: HourlyBucket; avgData: HourlyBucket; count: number }> {
  const buckets = new Map<string, { shiftType: ShiftType; sumData: HourlyBucket; avgData: HourlyBucket; count: number }>();

  // Initialize buckets for each shift type
  for (const st of shiftTypes) {
    buckets.set(st.key, {
      shiftType: st,
      sumData: { allNetSales: 0, stwGc: 0, oepe: 0, kvsTimePerItem: 0, kvsHealthyUsage: 0, dtPullForwardPct: 0, punchLaborPct: 0, tpph: 0, r2p: 0 },
      avgData: { allNetSales: 0, stwGc: 0, oepe: 0, kvsTimePerItem: 0, kvsHealthyUsage: 0, dtPullForwardPct: 0, punchLaborPct: 0, tpph: 0, r2p: 0 },
      count: 0,
    });
  }

  // Process each row
  for (const row of records) {
    // Skip total rows and all-zero rows
    if (isTotalRow(row) || isAllZeroRow(row)) {
      continue;
    }

    const endTimeHour = parseEndTimeHour(getColumn(row, "End Time"));
    if (endTimeHour < 0) {
      continue; // Invalid time
    }

    const matchedShift = getShiftTypeForHour(endTimeHour, shiftTypes);
    if (!matchedShift) {
      continue; // Hour doesn't match any shift type
    }

    const bucket = buckets.get(matchedShift.key);
    if (!bucket) continue;

    // Extract values from row
    const allNetSales = parseNumber(getColumn(row, "All Net Sales"));
    const stwGc = parseNumber(getColumn(row, "STW GC"));
    const oepe = parseNumber(getColumn(row, "OEPE"));
    const kvsTimePerItem = parseNumber(getColumn(row, "KVS Time Per Item"));
    const kvsHealthyUsage = parseNumber(getColumn(row, "KVS Healthy Usage"));
    const dtPullForwardPct = parseNumber(getColumn(row, "DT Pull Forward %"));
    const punchLaborPct = parseNumber(getColumn(row, "Punch Labor"));
    const tpph = parseNumber(getColumn(row, "TPPH"));
    const r2p = parseNumber(getColumn(row, "R2P"));

    // SUM fields: allNetSales, stwGc, r2p
    bucket.sumData.allNetSales += allNetSales;
    bucket.sumData.stwGc += stwGc;
    bucket.sumData.r2p += r2p;

    // AVG fields: accumulate for later averaging
    bucket.avgData.oepe += oepe;
    bucket.avgData.kvsTimePerItem += kvsTimePerItem;
    bucket.avgData.kvsHealthyUsage += kvsHealthyUsage;
    bucket.avgData.dtPullForwardPct += dtPullForwardPct;
    bucket.avgData.punchLaborPct += punchLaborPct;
    bucket.avgData.tpph += tpph;

    bucket.count++;
  }

  // Calculate averages
  for (const bucket of buckets.values()) {
    if (bucket.count > 0) {
      bucket.avgData.oepe = bucket.avgData.oepe / bucket.count;
      bucket.avgData.kvsTimePerItem = bucket.avgData.kvsTimePerItem / bucket.count;
      bucket.avgData.kvsHealthyUsage = bucket.avgData.kvsHealthyUsage / bucket.count;
      bucket.avgData.dtPullForwardPct = bucket.avgData.dtPullForwardPct / bucket.count;
      bucket.avgData.punchLaborPct = bucket.avgData.punchLaborPct / bucket.count;
      bucket.avgData.tpph = bucket.avgData.tpph / bucket.count;
    }
  }

  return buckets;
}

/**
 * Triggered when a CSV file is uploaded to shift_manager_imports/
 * Parses the CSV, matches manager names to employees, and saves to Firestore.
 */
export const processShiftManagerCSV = onObjectFinalized(
  {
    bucket: "schedulehq-cf87f.firebasestorage.app",
  },
  async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType;

    // Only process CSV files in the shift_manager_imports folder
    if (!filePath.startsWith("shift_manager_imports/")) {
      logger.log(`Ignoring file outside shift_manager_imports: ${filePath}`);
      return;
    }

    if (!contentType || !contentType.includes("csv")) {
      logger.log(`Ignoring non-CSV file: ${filePath} (${contentType})`);
      return;
    }

    const filename = filePath.split("/").pop() || "";
    logger.log(`Processing Shift Manager CSV: ${filename}`);

    try {
      // Download file from Storage
      const bucket = admin.storage().bucket(event.data.bucket);
      const file = bucket.file(filePath);
      
      const [fileContents] = await file.download();
      const csvContent = fileContents.toString("utf-8");

      // Parse CSV
      const records = parse(csvContent, {
        columns: true,
        skip_empty_lines: true,
        trim: true,
        bom: true, // Handle BOM (byte order mark)
      });

      logger.log(`Parsed ${records.length} rows from CSV`);

      // Debug: Log actual column names from first row
      if (records.length > 0) {
        const columnNames = Object.keys(records[0]);
        logger.log(`CSV columns found: ${JSON.stringify(columnNames)}`);
      }

      // Get location from first CSV row to find the correct manager
      const location = getColumn(records[0] || {}, "Loc");
      
      if (!location) {
        logger.error("No location (Loc) found in CSV. Check column names above.");
        return;
      }

      logger.log(`Looking up manager for store location: ${location}`);

      // Find manager with matching storeNsn in managerSettings (nested in storeHours)
      const settingsSnapshot = await db
        .collection("managerSettings")
        .where("storeHours.storeNsn", "==", location)
        .limit(1)
        .get();

      if (settingsSnapshot.empty) {
        logger.error(`No manager found with storeHours.storeNsn: ${location}`);
        return;
      }

      const managerUid = settingsSnapshot.docs[0].id;
      logger.log(`Found manager ${managerUid} for store ${location}`);

      // Get all employees for this manager
      const employeesSnapshot = await db
        .collection("managers")
        .doc(managerUid)
        .collection("employees")
        .get();

      // Build employee lookup map by name field (case-insensitive)
      const employeeMap = new Map<string, { id: number; name: string }>();
      
      employeesSnapshot.forEach((doc) => {
        const data = doc.data();
        const name = (data.name || "").toLowerCase().trim();
        const localId = data.localId || parseInt(doc.id) || 0;
        
        if (name) {
          // Key format: "firstname lastname" (lowercase)
          employeeMap.set(name, { id: localId, name: data.name });
        }
      });

      logger.log(`Loaded ${employeeMap.size} employees for matching`);

      // Extract date from filename
      const reportDate = extractDateFromFilename(filename);

      // Process each row
      const matchedEntries: ShiftManagerEntry[] = [];
      let unmatchedCount = 0;

      for (const row of records) {
        const managerName = getColumn(row, "Manager Name");
        
        // Normalize "LastName, FirstName" → "FirstName LastName"
        const normalizedName = normalizeManagerName(managerName);

        if (!normalizedName) {
          logger.warn(`Could not parse manager name: "${managerName}"`);
          unmatchedCount++;
          continue;
        }

        // Look up employee by normalized name (case-insensitive)
        const lookupKey = normalizedName.toLowerCase();
        const employee = employeeMap.get(lookupKey);

        if (!employee) {
          logger.warn(`No employee match for: "${managerName}" → "${normalizedName}" (key: ${lookupKey})`);
          unmatchedCount++;
          continue;
        }

        // Create entry using flexible column matching
        const entry: ShiftManagerEntry = {
          employeeId: employee.id,
          managerName: employee.name, // Use the employee's actual name from Firestore
          timeSlice: getColumn(row, "Time Slice"),
          allNetSales: parseNumber(getColumn(row, "All Net Sales")),
          numberOfShifts: parseNumber(getColumn(row, "# of Shifts")),
          gc: parseNumber(getColumn(row, "GC")),
          dtPulledForwardPct: parseNumber(getColumn(row, "DT Pulled Forward %")),
          kvsHealthyUsage: parseNumber(getColumn(row, "KVS Healthy Usage")),
          oepe: parseNumber(getColumn(row, "OEPE")),
          punchLaborPct: parseNumber(getColumn(row, "Punch Labor %")),
          dtGc: parseNumber(getColumn(row, "DT GC")),
          tpph: parseNumber(getColumn(row, "TPPH")),
          averageCheck: parseNumber(getColumn(row, "Average Check")),
          actVsNeed: parseNumber(getColumn(row, "Act vs Need")),
          r2p: parseNumber(getColumn(row, "R2P")),
        };

        matchedEntries.push(entry);
      }

      logger.log(`Matched ${matchedEntries.length} entries, ${unmatchedCount} unmatched`);

      // Save to Firestore
      if (matchedEntries.length > 0) {
        const reportRef = db
          .collection("managers")
          .doc(managerUid)
          .collection("shiftManagerReports")
          .doc(reportDate);

        await reportRef.set({
          importedAt: admin.firestore.FieldValue.serverTimestamp(),
          fileName: filename,
          location: location, // Store location from CSV lookup
          reportDate: reportDate,
          totalEntries: matchedEntries.length,
          unmatchedEntries: unmatchedCount,
          entries: matchedEntries,
        });

        logger.log(`Saved report to Firestore: managers/${managerUid}/shiftManagerReports/${reportDate}`);
      } else {
        logger.warn("No matched entries to save");
      }

      // Delete processed file from Storage
      await file.delete();
      logger.log(`Deleted processed file: ${filePath}`);

    } catch (error) {
      logger.error(`Error processing CSV ${filename}:`, error);
      throw error;
    }
  }
);
