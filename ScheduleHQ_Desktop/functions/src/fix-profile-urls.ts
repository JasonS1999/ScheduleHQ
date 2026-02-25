/**
 * One-time fix script: Backfill profileImageURL for employees whose profile
 * picture was uploaded to Firebase Storage before the Firestore write rules
 * were fixed.
 *
 * What it does:
 *   1. Finds all manager UIDs from the users collection (role == "manager")
 *   2. For each manager's employees subcollection, checks if profile.jpg
 *      exists in Storage
 *   3. If the file exists but profileImageURL is missing/empty, generates
 *      a download URL and writes it to the employee document
 *
 * Run from the functions directory:
 *   npm run build
 *   node lib/fix-profile-urls.js
 */

import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const bucket = admin.storage().bucket("schedulehq-cf87f.firebasestorage.app");

async function fixProfileUrls(): Promise<void> {
  console.log("Starting profile image URL backfill...\n");

  // Find manager UIDs from the users collection
  const usersSnap = await db
    .collection("users")
    .where("role", "==", "manager")
    .get();

  const managerUids = usersSnap.docs.map((d) => d.id);
  console.log(`Found ${managerUids.length} manager(s): ${managerUids.join(", ")}\n`);

  if (managerUids.length === 0) {
    // Fallback: list all documents in the managers collection
    console.log("No managers found in users collection, trying managers collection...");
    const managersSnap = await db.collection("managers").get();
    for (const doc of managersSnap.docs) {
      managerUids.push(doc.id);
    }
    console.log(`Found ${managerUids.length} manager(s) via fallback\n`);
  }

  let totalChecked = 0;
  let totalFixed = 0;
  let totalSkipped = 0;
  let totalNoFile = 0;

  for (const managerUid of managerUids) {
    console.log(`\nManager: ${managerUid}`);

    const employeesSnap = await db
      .collection("managers")
      .doc(managerUid)
      .collection("employees")
      .get();

    console.log(`  ${employeesSnap.size} employee(s)`);

    for (const empDoc of employeesSnap.docs) {
      totalChecked++;
      const data = empDoc.data();
      const empName = data.name || `ID:${empDoc.id}`;

      // Skip if profileImageURL is already set
      if (data.profileImageURL) {
        totalSkipped++;
        console.log(`  SKIP: ${empName} (already has URL)`);
        continue;
      }

      // Check if profile.jpg exists in Storage
      const storagePath = `managers/${managerUid}/employees/${empDoc.id}/profile.jpg`;
      const file = bucket.file(storagePath);

      try {
        const [exists] = await file.exists();
        if (!exists) {
          totalNoFile++;
          console.log(`  NONE: ${empName} (no file in Storage)`);
          continue;
        }

        // File exists — generate a Firebase-style download URL using a
        // download token from the file metadata
        const [metadata] = await file.getMetadata();
        let downloadToken = metadata.metadata?.firebaseStorageDownloadTokens;

        if (!downloadToken) {
          // No existing token — create one via UUID and set it on the file
          const { v4: uuidv4 } = await import("crypto");
          downloadToken = uuidv4();
          await file.setMetadata({
            metadata: { firebaseStorageDownloadTokens: downloadToken },
          });
        }

        const encodedPath = encodeURIComponent(storagePath);
        const downloadUrl =
          `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${downloadToken}`;

        // Update Firestore
        await empDoc.ref.update({ profileImageURL: downloadUrl });

        totalFixed++;
        console.log(`  FIXED: ${empName} (${empDoc.id})`);
      } catch (err) {
        console.error(`  ERROR for ${empName} (${empDoc.id}):`, err);
      }
    }
  }

  console.log("\n========== Summary ==========");
  console.log(`Employees checked:  ${totalChecked}`);
  console.log(`Already had URL:    ${totalSkipped}`);
  console.log(`No file in Storage: ${totalNoFile}`);
  console.log(`Fixed (URL added):  ${totalFixed}`);
  console.log("=============================\n");
}

fixProfileUrls()
  .then(() => {
    console.log("Done.");
    process.exit(0);
  })
  .catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
  });
