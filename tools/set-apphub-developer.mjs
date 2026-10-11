// Run only on a trusted administrator machine with Firebase Admin credentials.
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const [projectId, uid, action] = process.argv.slice(2);
if (!projectId || !uid || !['grant', 'revoke'].includes(action)) {
  console.error('Usage: node tools/set-apphub-developer.mjs <firebase-project-id> <user-uid> <grant|revoke>');
  process.exit(1);
}
initializeApp({ credential: applicationDefault(), projectId });
const auth = getAuth();
const user = await auth.getUser(uid);
const claims = { ...user.customClaims };
if (action === 'grant') claims.developer = true;
else delete claims.developer;
await auth.setCustomUserClaims(uid, claims);
console.log(`Developer access ${action === 'grant' ? 'granted' : 'revoked'}. Refresh Account Access in AppHub to apply.`);
