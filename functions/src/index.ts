import {onCall, HttpsError} from "firebase-functions/v2/https";
import {setGlobalOptions} from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import * as jwt from "jsonwebtoken";

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

// ─────────────────────────────────────────────
// Secrets（從 Firebase Secret Manager 注入）
// ─────────────────────────────────────────────

const APPLE_TEAM_ID = defineSecret("APPLE_TEAM_ID");
const APPLE_KEY_ID = defineSecret("APPLE_KEY_ID");
const APPLE_PRIVATE_KEY = defineSecret("APPLE_PRIVATE_KEY");
const APPLE_BUNDLE_ID = defineSecret("APPLE_BUNDLE_ID");

// ─────────────────────────────────────────────
// Helper: Build Apple JWT client secret
// ─────────────────────────────────────────────

/**
 * Builds a short-lived Apple JWT client secret using stored secrets.
 * @return {string} Signed JWT client secret.
 */
function buildAppleClientSecret(): string {
  const privateKey = APPLE_PRIVATE_KEY.value().replace(/\\n/g, "\n");

  return jwt.sign({}, privateKey, {
    algorithm: "ES256",
    expiresIn: "5m",
    issuer: APPLE_TEAM_ID.value(),
    audience: "https://appleid.apple.com",
    subject: APPLE_BUNDLE_ID.value(),
    keyid: APPLE_KEY_ID.value(),
  });
}

// ─────────────────────────────────────────────
// Helper: Delete all Firestore data for a user
// ─────────────────────────────────────────────

/**
 * Deletes all Firestore documents belonging to a user.
 * @param {string} uid - Firebase user UID.
 */
async function deleteAllFirestoreData(uid: string): Promise<void> {
  const db = admin.firestore();
  const collections = [
    "sessions",
    "categories",
    "products",
    "inventoryChanges",
    "transactions",
    "qrCodes",
  ];

  for (const col of collections) {
    const snap = await db
      .collection("users")
      .doc(uid)
      .collection(col)
      .get();
    const chunks = chunkArray(snap.docs, 450);
    for (const chunk of chunks) {
      const batch = db.batch();
      chunk.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
  }

  // 刪除 private 子集合（syncState、appleToken）
  const privateSnap = await db
    .collection("users")
    .doc(uid)
    .collection("private")
    .get();
  if (!privateSnap.empty) {
    const batch = db.batch();
    privateSnap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  // 刪除 users/{uid} document
  await db.collection("users").doc(uid).delete();
}

// ─────────────────────────────────────────────
// Helper: Delete all Storage files for a user
// ─────────────────────────────────────────────

/**
 * Deletes all Firebase Storage files under users/{uid}/.
 * @param {string} uid - Firebase user UID.
 */
async function deleteAllStorageFiles(uid: string): Promise<void> {
  const bucket = admin.storage().bucket();
  const [files] = await bucket.getFiles({prefix: `users/${uid}/`});
  // eslint-disable-next-line @typescript-eslint/no-empty-function
  await Promise.all(files.map((file) => file.delete().catch(() => {})));
}

// ─────────────────────────────────────────────
// Helper: Chunk array
// ─────────────────────────────────────────────

/**
 * Splits an array into chunks of the given size.
 * @param {Array} arr - Source array.
 * @param {number} size - Chunk size.
 * @return {Array} Array of chunks.
 */
function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

// ─────────────────────────────────────────────
// FUNCTION 1: exchangeAppleToken
// Apple Sign In 完成後呼叫
// 將 authorizationCode 換成 refresh_token 存入 Firestore
// ─────────────────────────────────────────────

export const exchangeAppleToken = onCall(
  {
    secrets: [APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, APPLE_BUNDLE_ID],
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    const uid = request.auth.uid;
    const authorizationCode = request.data.authorizationCode as
      | string
      | undefined;

    if (!authorizationCode) {
      throw new HttpsError(
        "invalid-argument",
        "authorizationCode is required"
      );
    }

    const clientSecret = buildAppleClientSecret();
    const bundleId = APPLE_BUNDLE_ID.value();

    const params = new URLSearchParams({
      client_id: bundleId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    });

    const response = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: params.toString(),
    });

    const tokenData = (await response.json()) as {
      refresh_token?: string;
      error?: string;
    };

    if (!tokenData.refresh_token) {
      throw new HttpsError(
        "internal",
        `Apple token exchange failed: ${tokenData.error ?? "unknown"}`
      );
    }

    await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("private")
      .doc("appleToken")
      .set({
        refreshToken: tokenData.refresh_token,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    return {success: true};
  }
);

// ─────────────────────────────────────────────
// FUNCTION 2: deleteAccount
// Google / Apple 共用
// Apple：revoke token → 刪資料 → 刪 Auth 帳號
// Google：直接刪資料 → 刪 Auth 帳號
// ─────────────────────────────────────────────

export const deleteAccount = onCall(
  {
    secrets: [APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, APPLE_BUNDLE_ID],
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    const uid = request.auth.uid;

    // 1. 取得 provider
    const userDoc = await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .get();
    const provider = userDoc.data()?.provider as string | undefined;

    // 2. Apple：revoke token
    if (provider === "apple") {
      const appleTokenDoc = await admin
        .firestore()
        .collection("users")
        .doc(uid)
        .collection("private")
        .doc("appleToken")
        .get();

      const refreshToken = appleTokenDoc.data()?.refreshToken as
        | string
        | undefined;

      if (refreshToken) {
        const clientSecret = buildAppleClientSecret();
        const bundleId = APPLE_BUNDLE_ID.value();

        const params = new URLSearchParams({
          client_id: bundleId,
          client_secret: clientSecret,
          token: refreshToken,
          token_type_hint: "refresh_token",
        });

        // Best effort：失敗不中斷後續刪除流程
        await fetch("https://appleid.apple.com/auth/revoke", {
          method: "POST",
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: params.toString(),
        }).catch((err) => console.error("Apple revoke failed:", err));
      }
    }

    // 3. 刪除 Firestore 所有資料
    await deleteAllFirestoreData(uid);

    // 4. 刪除 Storage 所有圖片
    await deleteAllStorageFiles(uid);

    // 5. 刪除 Firebase Auth 帳號（Admin SDK，不需要近期驗證）
    await admin.auth().deleteUser(uid);

    return {success: true};
  }
);
