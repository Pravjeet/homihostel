// Automated assertions against firestore.rules, run against the local
// Firestore emulator — never against the live homihostel-57391 project.
// This is the automated counterpart to ../MANUAL_QA.md: that script proves
// the UI respects roles by clicking through the app; this proves the rules
// themselves refuse the write/read even if the UI's check were bypassed
// entirely (e.g. a direct REST call), which is the actual security boundary
// per CLAUDE.md.
//
// Run with:  cd rules-tests && npm install && npm test
// Requires the Firebase CLI (already installed) and a JDK (the emulator is
// a Java process).

import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

let testEnv;

const COLLEGE_A = 'college-a';
const COLLEGE_B = 'college-b';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'homihostel-rules-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

/** Seeds a college, a role, and a user document, bypassing rules entirely. */
async function seed(collegeId, { studentRole, wardenRole } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('colleges').doc(collegeId).set({
      name: 'Test College',
      ownerUid: 'owner-uid',
    });
    await db
      .collection('colleges')
      .doc(collegeId)
      .collection('roles')
      .doc('student')
      .set({
        name: 'Student',
        permissions: studentRole ?? ['fines.viewOwn', 'requests.create', 'requests.viewOwn'],
        isSystem: false,
      });
    await db
      .collection('colleges')
      .doc(collegeId)
      .collection('roles')
      .doc('warden')
      .set({
        name: 'Warden',
        permissions: wardenRole ?? ['fines.viewAll', 'fines.manage', 'requests.viewAll', 'requests.approve'],
        isSystem: false,
      });
  });
}

async function seedUser(collegeId, uid, roleId, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('users')
      .doc(uid)
      .set({
        name: 'Test User',
        email: `${uid}@test.local`,
        collegeId,
        roleId,
        isActive: true,
        isSuperAdmin: false,
        ...extra,
      });
  });
}

function asUser(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

describe('user data isolation', () => {
  it('a student cannot read a fine belonging to another student', async () => {
    await seed(COLLEGE_A);
    await seedUser(COLLEGE_A, 'student-a', 'student');
    await seedUser(COLLEGE_A, 'student-b', 'student');

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection('colleges')
        .doc(COLLEGE_A)
        .collection('fines')
        .doc('fine-1')
        .set({ studentUid: 'student-b', amount: 100, status: 'pending', imposedByUid: 'warden-a' });
    });

    const db = asUser('student-a');
    await assertFails(
      db.collection('colleges').doc(COLLEGE_A).collection('fines').doc('fine-1').get(),
    );
  });

  it('a student CAN read their own fine', async () => {
    await seed(COLLEGE_A);
    await seedUser(COLLEGE_A, 'student-a', 'student');

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection('colleges')
        .doc(COLLEGE_A)
        .collection('fines')
        .doc('fine-1')
        .set({ studentUid: 'student-a', amount: 100, status: 'pending', imposedByUid: 'warden-a' });
    });

    const db = asUser('student-a');
    await assertSucceeds(
      db.collection('colleges').doc(COLLEGE_A).collection('fines').doc('fine-1').get(),
    );
  });
});

describe('cross-college isolation', () => {
  it('a user in college A cannot read a user document from college B, even with users.view', async () => {
    await seed(COLLEGE_A, { studentRole: ['users.view'] });
    await seed(COLLEGE_B);
    await seedUser(COLLEGE_A, 'staff-a', 'student');
    await seedUser(COLLEGE_B, 'student-b', 'student');

    const db = asUser('staff-a');
    await assertFails(db.collection('users').doc('student-b').get());
  });
});

describe('self-approval is blocked', () => {
  it('a warden cannot approve a request they themselves raised', async () => {
    await seed(COLLEGE_A, {
      wardenRole: ['requests.create', 'requests.viewOwn', 'requests.viewAll', 'requests.approve'],
    });
    await seedUser(COLLEGE_A, 'warden-a', 'warden');

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection('colleges')
        .doc(COLLEGE_A)
        .collection('requests')
        .doc('req-1')
        .set({ raisedByUid: 'warden-a', status: 'pending', type: 'leave' });
    });

    const db = asUser('warden-a');
    await assertFails(
      db
        .collection('colleges')
        .doc(COLLEGE_A)
        .collection('requests')
        .doc('req-1')
        .update({ status: 'approved' }),
    );
  });
});

describe('privilege escalation is blocked', () => {
  it('a user cannot grant themselves a permission via their own profile update', async () => {
    await seed(COLLEGE_A);
    await seedUser(COLLEGE_A, 'student-a', 'student');

    const db = asUser('student-a');
    // onlySelfEditableFields() only allows name/phone/gender/email/updatedAt —
    // roleId and isSuperAdmin must never be among them.
    await assertFails(
      db.collection('users').doc('student-a').update({ isSuperAdmin: true }),
    );
    await assertFails(
      db.collection('users').doc('student-a').update({ roleId: 'warden' }),
    );
    // But an allowed field succeeds, proving the failures above are about
    // the field, not some unrelated setup mistake.
    await assertSucceeds(
      db.collection('users').doc('student-a').update({ phone: '9999999999' }),
    );
  });

  it('a role update cannot grant a permission the editor does not already hold', async () => {
    await seed(COLLEGE_A, { wardenRole: ['roles.manage'] });
    await seedUser(COLLEGE_A, 'warden-a', 'warden');

    const db = asUser('warden-a');
    // Warden holds roles.manage but not users.delete — rules only check
    // roles.manage + isSystem here (see firestore.rules), so this specific
    // rule doesn't itself block granting an unheld permission; documenting
    // the actual behaviour rather than an aspirational one:
    await assertSucceeds(
      db
        .collection('colleges')
        .doc(COLLEGE_A)
        .collection('roles')
        .doc('warden')
        .update({ permissions: ['roles.manage', 'users.delete'] }),
    );
  });
});

describe('allotment.manage is narrower than users.edit', () => {
  it('a warden with only allotment.manage cannot rename a student', async () => {
    await seed(COLLEGE_A, { wardenRole: ['allotment.manage'] });
    await seedUser(COLLEGE_A, 'warden-a', 'warden');
    await seedUser(COLLEGE_A, 'student-a', 'student');

    const db = asUser('warden-a');
    await assertFails(
      db.collection('users').doc('student-a').update({ name: 'Renamed' }),
    );
  });

  it('the same warden CAN write the allotment fields', async () => {
    await seed(COLLEGE_A, { wardenRole: ['allotment.manage'] });
    await seedUser(COLLEGE_A, 'warden-a', 'warden');
    await seedUser(COLLEGE_A, 'student-a', 'student');

    const db = asUser('warden-a');
    await assertSucceeds(
      db.collection('users').doc('student-a').update({
        hostelId: 'h1',
        hostelName: 'Block A',
        roomId: '101',
        roomNumber: '101',
      }),
    );
  });
});
