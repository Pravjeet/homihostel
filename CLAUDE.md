# Homi Hostel — working notes for Claude

Flutter + Firebase hostel management dashboard for SLIET. Read
`ARCHITECTURE.md` for the reasoning behind the design; this file is the
short operational brief.

## Commands

```bash
flutter analyze              # ALWAYS run before saying code is done
flutter run -d edge          # web (primary target during development)
flutter run -d windows       # desktop
firebase deploy --only firestore:rules
```

`flutter analyze` is the single most useful thing you can run here. Much of
this codebase was written without a compiler available, so treat a clean
analyze as the minimum bar, not a bonus.

## The one architectural rule

**One dashboard, permission-filtered.** There is no per-role dashboard and
there must never be. `lib/core/nav_registry.dart` is the master list of every
screen; each entry declares a `requires:` list of permission strings, and
`navigationFor(session)` filters it. A Student and a Super Admin run the
identical widget tree.

Adding a feature = one entry in `_allSections` + one page file + a rules block.

**Never branch on role names** (`if (role == 'Warden')`). Roles are user-created
data, so any such check breaks the moment someone invents "Hostel Manager".
Branch on `session.can(Perm.x)`.

## Layout

```
lib/core/          permissions, session, nav registry, theme, identity
lib/models/        AppUser, AppRole, Hostel/Room, HostelRequest, Mess
lib/services/      one service per module; widgets never touch Firestore
lib/screens/pages/ one file per page, plus *_view.dart for drill-downs
firestore.rules    security — the real enforcement, not the UI
```

Pages hold drill-down state internally (`_openHostelId`, `_openUser`) rather
than pushing routes, so the sidebar stays visible.

## Data model

```
colleges/{collegeId}
  ├── roles/{roleId}          name, permissions[], isSystem
  ├── hostels/{hostelId}      + denormalised roomCount/bedCount/occupiedBeds
  │     └── rooms/{roomNumber}   room number IS the doc id
  └── requests/{requestId}    leave / complaint / roomChange / other

users/{uid}                   root collection, NOT under the college
```

`users` is root because at login you only have a uid — you don't know the
college yet. Room allotment is denormalised onto both the room
(`occupantUids`) and the user (`roomId`, `roomNumber`), written in one
transaction so they cannot disagree.

## Things that will bite you

**Allotment must be a transaction, never a batch.** Two wardens clicking the
last free bed simultaneously would both read "1 free" and both write. See
`AllotmentService.allot`.

**Students log in with a registration number**, mapped to a synthetic address
(`2110910@homihostel.local`) by `lib/core/identity.dart`. Never show a raw
synthetic address in the UI — use `Identity.display()`. Synthetic addresses
have no inbox, so password reset cannot work for students.

**Creating users client-side is a workaround.** `AuthService.createSubUser`
uses a secondary FirebaseApp because `createUserWithEmailAndPassword` would
otherwise sign the admin out. Firebase throttles it, so bulk import past ~40
accounts will fail rows. The real fix is a Node script using the Admin SDK.
`deleteUserProfile` only removes the Firestore doc — the Auth account lingers.

**A widget that returns `Expanded` or `Spacer` needs a bounded parent.** A
card inside a `Wrap` has unbounded height; a vertical flex child there fails
to lay out and silently blanks the whole list. This has already happened once.

**`ConstrainedBox` is not const-constructible** (its constructor asserts via a
method call). Neither are `Container`, `AlertDialog`, `Tooltip`.

## Security rules

The UI hiding a button is not security — anyone can hit the Firestore REST API
with their ID token. Every permission check in the app is repeated in
`firestore.rules`, and those are what enforce it.

`hasPerm()` short-circuits on `isSuperAdmin()`, so **testing as Super Admin
will not exercise the permission branches.** Create a Warden and a Student to
test properly. If you see "You don't have permission to do that" while signed
in as Super Admin, the rules are out of date — redeploy.

### Deploying rules — non-negotiable

**Any change to `firestore.rules` is not real until it is deployed.** The file
on disk has no effect; only the published version does.

```bash
./deploy-rules.bat     # publishes, and records the deployed hash
./check-rules.bat      # says whether live rules match the file
```

**If you are Claude Code, run `deploy-rules.bat` yourself** immediately after
editing `firestore.rules` — you have the user's shell and their `firebase
login`, so there is no reason to make them do it by hand.

**If you cannot run it** (sandboxed shell, no credentials), then you MUST end
your reply with a clearly marked block saying the rules changed and must be
deployed, naming what changed and who it affects. Silently editing the file
and moving on has already caused confusing permission errors in this project
more than once.

## Reference data

College details and structure: https://sliet.ac.in/

## Not built yet

Finance, notices, settings, audit logs. `ComingSoonPage` placeholders are wired
into the nav with their permissions already defined — swap the builder in
`nav_registry.dart` when you build one.
