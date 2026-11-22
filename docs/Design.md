# Shake Kit: design

ShakeKit lets someone testing an app file a bug from inside it. They shake
the phone (or pick Report a Bug… on a Mac), and a sheet shows a screenshot
of the moment, the app's recent logs and its version. They sign in to
GitHub once, add a title and a few words, and ShakeKit opens an issue in
the app's repository with the screenshots and logs attached.

This note is for the owner to approve before any code. Open questions are
marked **(?)**.

## 1. API

    import ShakeKit

    ContentView()
        .shakeToReport()                      // repository from Info.plist
        .shakeToReport(repository: "owner/app") // or given here

- **iOS and iPadOS.** A shake (`motionEnded(.motionShake)`, which reaches
  the key window through the responder chain) opens the sheet. Shakes
  that come in while the sheet is up are ignored.
- **macOS.** There's no shake. A scene modifier adds **Help › Report a
  Bug…** (⌥⌘B) that opens the same sheet:

      WindowGroup { ContentView().shakeToReport(repository: "owner/app") }
          .commands { ShakeKitCommands() }

- **Isomer hosts (Android, web, Linux, Windows).** Following update_kit,
  the same API compiles everywhere, and where a platform has no way in
  yet it does nothing. What each needs from Isomer is asked of Isomer, not
  `#if`'d here:
  - Android: a shake from the accelerometer, which needs a sensor API
    in Isomer **(?)**.
  - Web: a keyboard shortcut. `devicemotion` needs a permission prompt
    on iOS Safari, so it isn't worth it.
  - Linux and Windows desktop: a menu command or shortcut, wherever
    Isomer has commands.
  - Headless test hosts: nothing, but the sheet's view model is tested
    there.
- `ShakeReport.present()` opens the sheet from code too, for a button in an
  app's own settings.
- `ShakeKitConfiguration` (optional): which log subsystems to include,
  the time window, size caps, labels for the issue, and whether to ask for
  extra screenshots.

## 2. The sheet

1. **Screenshot of the moment,** taken when the shake arrives, before the
   sheet animates in. On iOS it renders the key window
   (`drawHierarchy(afterScreenUpdates: false)`); on a Mac it caches the key
   window's content view. It covers the app's own windows only, so no
   screen-recording permission is needed.
2. **More screenshots** (optional): the person can dismiss the sheet, go
   to another screen and shake again, and the draft keeps what's there.
   Markup through PencilKit is left for after 0.1.0, unless it turns out
   cheap **(?)**.
3. **Logs:** `OSLogStore(scope: .currentProcessIdentifier)`, holding the
   last 15 minutes by default, only the app's own subsystems unless
   configured otherwise, and capped at 256 KB (newest kept). On other
   hosts, whatever the app's logger keeps through a small `ShakeLogSource`
   protocol the app can provide.
4. **About the app and device:**
   - the app's name, bundle id, version and build;
   - the OS and its version, and the device model;
   - the locale, the time zone, and the time of the shake.
5. **Title** (required) and **description.**
6. **Preview** (section 5), then **Create Issue.** The result shows the
   issue's link. If it fails, the draft is kept to retry.

## 3. Sign-in

The owner's GitHub App, called **the Shake App** here (setup below).
Device flow, with a user-to-server token, so the issue is opened as the
person who signs in ("via the Shake App"), not as a bot.

- **First report:** the sheet shows the code and "Open github.com/login/device".
  It polls until the person has entered the code, then carries on with
  the report.
- **Tokens:** the access token (8 h) and the refresh token (6 months) go in
  the app's own keychain on Apple systems, in the host app's own access
  group (never one shared with another app's GitHub sign-in, or a report's
  sign-in would replace it). They're keyed by the App's client id.
  Elsewhere they use Isomer's secure store **(?)**. They're refreshed
  before expiry, and if the refresh token has expired, the person signs
  in again.
- **Sign Out** in the sheet deletes both tokens from the keychain.
- A user-to-server token can only reach repositories where the Shake App
  is installed **and** the person has access themselves. So a tester of a
  private app has to be a collaborator on that app's repository.

**What the owner creates** (Settings › Developer settings › GitHub Apps ›
New GitHub App):

- Name: the Shake App's name (the owner's choice; it's shown on every
  issue as "via …").
- Homepage URL: this repository.
- Webhook: off.
- Callback URL: none. **Enable Device Flow**: on. **Expire user
  authorization tokens**: on.
- Repository permissions:
  - Issues: read and write;
  - Contents: read and write, only for the attachments repository below;
  - Metadata: read (always required).
  No account or organization permissions.
- Where it can be installed: only on this account.
- Installed on: each app's repository (section 7) and the attachments
  repository, and nowhere else. "Contents: write" is App-wide, but only
  takes effect where the App is installed. That's why the attachments
  repository is the one installed repository that holds no code.
- The App's **client id** (not a secret) goes in each app's Info.plist as
  `ShakeKitClientID`, and the repository as `ShakeKitRepository`. Both are
  stamped in by the app's CI at build time, as update_kit's settings are.
  With no client id, ShakeKit does nothing. No client secret or private
  key is needed anywhere.

## 4. Attachments

GitHub's REST API can't attach files to issues: the web UI's upload
endpoint isn't public. The options:

| Option | Privilege | Who can see the files | Verdict |
| --- | --- | --- | --- |
| **A private attachments repository** (e.g. `shake_reports`), with files put through the Contents API and linked from the issue | Contents write on that one repository | Its collaborators | **Proposed** |
| A `shake/` path on an assets branch in each app's repository | Contents write on every app's repository | Anyone who can read that repository, so the public on public repos | Simplest, and reporters need no extra access, but it gives every reporter's token write access to every app's code **(?)** |
| Release assets on each repository | Contents write on every app's repository | The public, on public repos | No: same privilege, and abuses releases |
| Base64 in the issue body | Issues only | Everyone, but GitHub doesn't render data URIs | No |
| A server holding an installation token, which uploads for the person | None for the person | As chosen | Later, if testers shouldn't have to be collaborators **(?)** |

**Proposed:** one private repository, `<owner>/shake_reports`. Each report
puts `reports/<repository>/<yyyy-mm-dd>/<id>/screenshot-1.png …` and
`logs.txt`, in one commit, and the issue links to them. The issue body
shows each screenshot as a link, not inline, because a private repository's
image won't render for readers without access.

The trade-offs, stated plainly:
- A public app's issue links to files only the owner (and the
  attachments repository's collaborators) can open. That's intended:
  screenshots and logs can hold private data, and the issue text itself
  is public.
- Each reporter needs write access to `shake_reports`, because of the
  token's intersection rule. That suits the owner and a few invited
  testers. Testers can read each other's reports, though. If testers
  outside that circle are wanted, the server row above is the way.

## 5. Privacy

- **Logs:**
  - Only the app's own subsystems, from the last 15 minutes.
  - Messages that the app logs as `.private` arrive redacted already
    (`<private>`), as OSLogStore gives them.
  - Before upload, ShakeKit also redacts anything that looks like a
    token, an email address, or a URL's query string.
  - An app can add its own rules (`ShakeKitConfiguration.redact`).
- **Preview:**
  - The person sees every screenshot and the full log text before
    sending, and can remove a screenshot or the logs entirely.
  - The issue text that will be public on a public repository is shown
    as such: "This issue is public; the screenshots and logs are not."
- Nothing leaves the device until Create Issue: no network at all until
  the sheet opens, no analytics, and no crash hooks. Screenshots and logs
  stay in memory (or the app's container, for a kept draft) and are
  dropped once the issue is created.
- **Release builds:** ShakeKit isn't meant for App Store releases, but
  it's harmless there. With no `ShakeKitClientID` in the Info.plist, the
  sheet never opens.

## 6. Packaging and conventions (as update_kit)

- A Swift package (`ShakeKit`) and a Bazel module in the same repository.
- Apps take it in either of two ways:
  - an `exact:` version through SwiftPM or rules_swift_package_manager;
  - a pin in the owner's bazel_registry.
- **Portable core:** the report model, its redaction, its issue body,
  GitHub's REST calls, device flow and token refresh are all plain Swift
  with no UI. They're tested with `swift test` on Linux, with GitHub's
  answers faked.
- The SwiftUI sheet and the platform hooks (shake, screenshot, OSLogStore,
  keychain) are thin and sit behind `canImport`.
- **Its own small GitHub client,** using the names and behaviour of the
  owner's existing (private) GitHub client, so the two can later merge:
  - `GitHubDeviceFlow`: the code, then polling, honouring `interval` and
    `slow_down`, and refresh with `grant_type=refresh_token`;
  - `GitHubToken`: the access and refresh tokens, `expires` and
    `refreshExpires`;
  - `TokenStore`, keyed by client id, with `KeychainTokenStore` and
    `MemoryTokenStore`. Off Apple's systems, the host gives its own store
    through the protocol;
  - `GitHubCredentials`: renews before expiry, and forgets the token on a
    401;
  - two REST calls: create an issue, and put a file's contents.
  - **Follow-up, for the owner's OK:** a public `github_auth_kit` takes these
    files whole, and both clients depend on it.
- **CI on GitHub's hosted runners and cache** (the repository is public):
  - Linux tests on every pull request;
  - an iOS and macOS build only when a release is verified.
  - Release secrets, if any, live in an environment limited to `v*` tags.
- Every release carries a proof (format 2): the tests' results and
  screenshots of the sheet on iOS (portrait and landscape) and macOS. The
  screenshots come from fixtures, with a fixed date, locale and
  appearance.
- Tools in Swift, not shell. Workflow files are committed for agents by
  the repository's maintainer. Versions are tags the owner makes.
- **Changes:**
  - each pull request adds a `changes/<branch>.md` fragment, never
    CHANGELOG.md;
  - one release per minor line;
  - a scoped CODEOWNERS;
  - platform specifics behind one small protocol.

## 7. Rollout

After ShakeKit 0.1.0, each app's owner integrates it, in a pull request of
their own: the modifier on the root view, `ShakeKitCommands()` on a Mac,
the client id in Info.plist, and the Shake App installed on its repository.

Each app files to its own repository. The list of apps and their
repositories is kept with the owner, not here, since some are private.
The public ones to start: Visor (`visor`), Playground (`playground`) and
Isomer's Storybook (`isomer`).

The issues get a `shake-report` label, made on first use if missing.
