# Shake Kit: design

ShakeKit lets someone testing an app file a bug from inside it. They shake
the phone (or pick Report a Bug… on a Mac), and a sheet shows a screenshot
of the moment, the app's recent logs and its version. They sign in to
GitHub once, add a title and a few words, and ShakeKit opens an issue in
the app's repository, with the screenshots embedded inline as GitHub's own
attachments.

The issue composer, the attachment upload and the GitHub client are
general, not shake-specific. They're public libraries here, which the
owner's other apps (an issues browser among them) can use too. ShakeKit is
the thin part on top: the shake, the screenshot and the logs.

This note is for the owner to approve before any code. Open questions are
marked **(?)**.

**Decided so far:**
- Apple's platforms come first; other hosts are later.
- Markup comes later.
- The app gives the repository.
- Attachments are GitHub's own (section 4).

## 1. Libraries

One repository and one Swift package, with four products. Each depends
only on the ones above it.

| Product | What it is | Used by |
| --- | --- | --- |
| `GitHubAuth` | Device flow, tokens, refresh, keychain store | everything below; any app that signs in to GitHub |
| `GitHubIssues` | REST client: create, edit and comment on issues; upload attachments (section 4); labels | ShakeKit; an issues browser |
| `IssueComposer` | SwiftUI: title, Markdown body, attachments with thumbnails (add, remove, reorder), preview, submit, the draft kept on failure | ShakeKit; an issues browser's "New Issue" and "Comment" |
| `ShakeKit` | The shake (or menu command), the screenshot of the moment, logs, device info, and opening `IssueComposer` with them filled in | each app |

`GitHubAuth` and `GitHubIssues` are plain Swift, with no UI, tested with
`swift test` on Linux. `IssueComposer` and `ShakeKit` are SwiftUI, and
their view models are tested on Linux too.

**Shaped so an issues browser can adopt them without a rewrite:**
- **`GitHubIssues`:**
  - The types are `GitHubIssue`, `IssueComment`, `GitHubLabel` and
    `IssueChange` (`title`, `body`, `labels`, `state`, `stateReason`, all
    optional, with `isEmpty`). They match the owner's existing client in
    names, Codable keys and optionality.
  - The calls: create, update, close and reopen (with a reason), comment,
    edit and delete a comment, list labels, and upload an attachment.
- **`IssueComposer`:**
  - **Sending is the host's.** Submit is an `async throws` closure the
    host gives, so a host with an offline outbox can queue the issue
    instead of sending it.
  - **An accessory slot** (`@ViewBuilder`) beside title and body: an
    issues browser's kind, status and priority pickers; ShakeKit's device
    info.
  - **Drafts** are kept through a small protocol, which defaults to
    `UserDefaults`.
  - **Attachments upload at submit, not when picked:**
    1. Each attachment is uploaded.
    2. The body's placeholders are rewritten to the returned URLs.
    3. The host's submit is called.
    4. On failure, the draft and its local files are kept.
- **Kept in each host, not here:** its own issue model, label scheme,
  cache and outbox.

## 2. API

    import ShakeKit

    WindowGroup {
        ContentView()
            .shakeToReport(repository: "owner/app")
    }
    .commands { ShakeKitCommands() }   // macOS: Help › Report a Bug… (⌥⌘B)

- **iOS and iPadOS.** A shake (`motionEnded(.motionShake)`, reaching the
  key window through the responder chain) opens the composer. Shakes
  that come in while it's up are ignored.
- **macOS.** No shake: `ShakeKitCommands()` adds the menu command and its
  shortcut.
- **Other hosts:** later. The API is kept portable, so they can follow
  through Isomer.
- `ShakeReport.present(repository:)` opens it from code, for a "Report a
  Bug" button.
- `ShakeKitConfiguration` (optional): which log subsystems to include,
  the time window, size caps, extra redaction rules, and the issue's
  labels.

Used without ShakeKit, the composer looks like this:

    IssueComposer(repository: "owner/app", session: session)  // GitHubAuth session

## 3. The composer, as ShakeKit fills it

1. **Screenshot of the moment,** taken when the shake arrives, before the
   composer animates in. On iOS it renders the key window
   (`drawHierarchy(afterScreenUpdates: false)`); on a Mac it caches the key
   window's content view. It covers the app's own windows only, so no
   screen-recording permission is needed.
2. **More screenshots:** the person can dismiss the sheet, go to another
   screen and shake again, and the draft keeps what's there. They can also
   add images from Photos or Files.
3. **Logs:**
   - from `OSLogStore(scope: .currentProcessIdentifier)`, the last 15
     minutes, the app's own subsystems only, capped at 256 KB (newest
     kept);
   - uploaded as a `.txt` attachment if the endpoint takes text files
     **(?)**, otherwise put in the body, folded in a `<details>` block.
4. **About the app and device,** as a small table in the body:
   - the app's name, bundle id, version and build;
   - the OS and its version, and the device model;
   - the locale, the time zone, and the time of the shake.
5. **Title** (required) and **description.**
6. **Preview** (section 6), then **Create Issue,** which shows the issue's
   link. If it fails, the draft is kept to retry.

## 4. Attachments: GitHub's own

The owner asked for the attachments the web UI makes, the
`github.com/user-attachments/assets/…` URLs, since they're what GitHub
renders inline. Findings (November 2026):

- **There's now a supported client for that endpoint.** Since GitHub CLI
  2.99.0 (changelog, 2026-09-01), `gh issue create --attach` is generally
  available. GitHub's docs cover it in "Attaching files with GitHub CLI".
- **The request (from `gh`'s source, `internal/attachments`):**

      POST https://uploads.github.com/user-attachments/assets
           ?name=<file>&content_type=<mime>&repository_id=<numeric id>
      Authorization: Bearer <token>
      Content-Type: application/octet-stream

  It returns `{"url": "https://github.com/user-attachments/assets/…"}`,
  which goes in the body as `![alt](url)`, as `gh` does. It's a plain token
  request, not the web UI's cookie and CSRF flow.
- **It isn't in the REST reference.** GitHub documents it only through
  `gh`, so it could change. `gh` is its main user, though, so it's unlikely
  to break quietly. If it changes, `GitHubIssues` is the one place to
  follow it.
- **Limits:**
  - types: PNG, JPEG, GIF, WebP, SVG, MP4, MOV and WebM;
  - sizes: 10 MB for an image; 10 MB for a video (100 MB on paid plans);
  - no GitHub Enterprise Server.
- **The token's access:** write access to the repository, so READ and
  TRIAGE get a 404.
  - GitHub's changelog names OAuth tokens and classic PATs.
  - `gh`'s source says the endpoint "accepts tokens from only some GitHub
    Apps".
  - Tested 2026-11-22: a GitHub App *installation* token (`ghs_`) with
    write access gets a 404.
  - Whether a GitHub App *user* token (`ghu_`, what device flow gives)
    is taken is **untested (?)**. It's the first thing to try once the
    Shake App exists, before any other code.
- **If `ghu_` isn't taken,** there are two fallbacks:
  1. **An OAuth App instead (preferred).**
     - It also does device flow, and its tokens (`gho_`) are what `gh`
       uses, so attachments stay GitHub's own and render inline.
     - The cost: OAuth scopes are coarse (`public_repo`, or `repo` for
       private apps), and its tokens don't expire.
     - A GitHub App's user token is narrower: Issues only, on the
       repositories it's installed on.
  2. **Images committed through the Contents API** to a
     `shake-attachments` branch of the app's repository, and linked by
     raw URL.
     - It needs Contents write on the App.
     - It renders inline on public repositories only: a private
       repository's raw images don't render in its issues.
     - It's the last resort.

  `GitHubIssues` treats the upload as best-effort. If it fails, the issue
  is still created, with the attachments left out and a note saying so.
- **Rendering and privacy:**
  - On a **private** repository, attachments uploaded against it need
    GitHub sign-in and access to that repository. They're served through
    short-lived signed URLs, so they render inline for the app's
    collaborators and for no one else.
  - On a **public** repository, attachments are public, like the issue.
    The composer says so before sending.
- **Rejected:** files kept in a separate repository and linked from the
  issue. Images from a private repository don't render inline in issues,
  even for viewers with access, which is what the owner saw.

So: **user-attachments, through the reporter's token, against the
app's own repository.**
- No other repository is involved, and the App needs no Contents
  permission.
- Every reporter needs write access to the app's repository. That's the
  owner and the app's collaborators, which fits who reports bugs.

## 5. Sign-in (`GitHubAuth`)

Device flow, so the issue is opened as the person who signs in.

- **The sign-in screen:** it shows the code and "Open
  github.com/login/device", and polls until the person has entered the
  code.
- **Tokens:**
  - The access and refresh tokens go in the app's keychain, in the host
    app's own access group. It must never be a group shared with another
    app's GitHub sign-in, or one sign-in would replace the other.
  - They're keyed by the App's client id.
  - They're refreshed before they expire, and the person signs in again
    when the refresh token runs out.
- **Sign Out** deletes both tokens.
- **Names and behaviour** follow the owner's existing GitHub client, so the
  two can merge:
  - `GitHubDeviceFlow`: honours `interval` and `slow_down`, and refreshes
    with `grant_type=refresh_token`;
  - `GitHubToken`;
  - `TokenStore`, with `KeychainTokenStore` and `MemoryTokenStore`;
  - `GitHubCredentials`: renews before expiry, and forgets the token on a
    401.

  The owner's issues browser can move onto `GitHubAuth` and
  `GitHubIssues` once they're released.

**What the owner creates** (if `ghu_` is taken; see section 4):

- **App:** a GitHub App, named as the owner chooses (it's shown as "via …").
  Its homepage is this repository.
- **Settings:**
  - webhook off;
  - no callback URL;
  - **Enable Device Flow** on;
  - **Expire user authorization tokens** on.
- **Permissions:**
  - repository: Issues, read and write; Metadata, read;
  - nothing else: no Contents, and no account permissions.
- **Installed on:** each app's repository, and installable on this account
  only.
- **Settings in each app:** the App's client id (not a secret) goes in
  the app's Info.plist as `ShakeKitClientID`, stamped by its CI. No client
  secret or private key is needed.

## 6. Privacy

- **Logs:**
  - Only the app's own subsystems, from the last 15 minutes.
  - `.private` values arrive redacted already, as OSLogStore gives them.
  - Before upload, the composer also redacts tokens, email addresses and
    URL query strings.
  - An app can add its own rules.
- **Preview:**
  - The person sees every attachment and the full log text, and can
    remove any of them.
  - On a public repository the composer says "This issue and its
    attachments will be public." On a private one, it says who can see
    them.
- **No network until the composer opens:** no analytics and no crash
  hooks. Screenshots and logs stay in memory (or the app's container, for
  a kept draft), and are dropped once the issue is created.
- **Release builds:** with no `ShakeKitClientID`, ShakeKit does nothing.

## 7. Packaging and conventions (as update_kit)

- **One package, two ways in:**
  - a Swift package and a Bazel module in the same repository;
  - apps pin it `exact:` through SwiftPM or rules_swift_package_manager, or
    through the owner's bazel_registry.
- **Linux:** `swift test` runs on Linux, with GitHub's answers faked.
  Apple's frameworks sit behind one small platform protocol.
- **CI:**
  - on GitHub's hosted runners and cache (the repository is public);
  - Linux tests on every pull request;
  - an iOS and macOS build only when a release is verified;
  - release secrets, if any, in an environment limited to `v*` tags.
- **Proof:** every release carries one (format 2), with the tests' results
  and the composer on iOS (portrait and landscape) and macOS. The shots
  come from fixtures, with a fixed date, locale and appearance.
- **Tools and workflow files:** tools are in Swift. Workflow files are
  committed for agents by the repository's maintainer.
- **Versions** are tags the owner makes.
- **Process:**
  - a `changes/<branch>.md` fragment in each pull request;
  - one release per minor line;
  - a scoped CODEOWNERS.

## 8. Rollout

1. **The Shake App:** the owner creates it.
2. **The first spike:** check that its `ghu_` token can upload. If not,
   switch it to an OAuth App (section 4).
3. **0.1.0:** with `GitHubAuth`, `GitHubIssues`, `IssueComposer` and
   `ShakeKit`, on iOS and macOS.
4. **Each app:** its owner integrates it in a pull request of their own,
   with:
   - the modifier, and the commands on a Mac;
   - the client id in Info.plist;
   - the Shake App installed on its repository.

   The list of apps is kept with the owner, since some are private. The
   public ones: Visor, Playground and Isomer's Storybook.
5. **The issues browser** moves onto `GitHubAuth`, `GitHubIssues` and
   `IssueComposer` after 0.1.0 is tagged, in step with its owner, pinning
   it through rules_swift_package_manager.

The issues get a `shake-report` label, made on first use if missing.
