// aksab_admin/tool/backfill_rep_type.mjs
//
// One-time backfill: explicitly classify every ALREADY-APPROVED sales rep
// as Permanent. SAFE by construction:
//   - touches ONLY docs in `salesRep` that have NO `repType` field at all;
//   - writes ONLY the single field `repType: 'permanent'` (merge write,
//     every other field untouched);
//   - DRY-RUN by default; pass --apply to write for real;
//   - prints every doc it would touch / touched.
//
// Auth: set GOOGLE_APPLICATION_CREDENTIALS to a service-account key with
// Firestore read/write on the aksab-erp project, then:
//     node tool/backfill_rep_type.mjs            (dry run, no writes)
//     node tool/backfill_rep_type.mjs --apply    (real run)
//
// DO NOT run against production without review. Requires `firebase-admin`
// (`npm i firebase-admin` in a scratch dir, or run with an existing setup).

import admin from 'firebase-admin';

const APPLY = process.argv.includes('--apply');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'aksab-erp',
});

const db = admin.firestore();

const snap = await db.collection('salesRep').get();
let missing = 0;
let skipped = 0;
const batchQueue = [];

for (const doc of snap.docs) {
  const data = doc.data();
  if (data.repType === undefined) {
    missing += 1;
    batchQueue.push(doc.ref);
    console.log(`${APPLY ? 'WRITE' : 'WOULD-WRITE'} salesRep/${doc.id} repCode=${data.repCode ?? '?'} -> repType='permanent'`);
  } else {
    skipped += 1;
  }
}

console.log(`scanned=${snap.size} missing=${missing} already-classified=${skipped}`);

if (!APPLY) {
  console.log('dry-run: no writes performed. Re-run with --apply to write.');
  process.exit(0);
}

const BATCH = 400;
for (let i = 0; i < batchQueue.length; i += BATCH) {
  const batch = db.batch();
  for (const ref of batchQueue.slice(i, i + BATCH)) {
    batch.set(ref, { repType: 'permanent' }, { merge: true });
  }
  await batch.commit();
  console.log(`committed batch ${i / BATCH + 1}`);
}
console.log('done.');
process.exit(0);
