# Setting up Google and Microsoft for Endless

**Phase 9a (2026-11-05): cloud sync with Google Drive and OneDrive needs this too.** The steps are the same project and the same app registration as for calendar sync below, with a few additions. They're in the next section; Parts 1 and 2 below say how to make the project and the registration.

## Cloud sync: Google Drive and OneDrive

Settings › Sync & backup → **Connect** signs in. Until the build has the client ids, Connect says sign-in isn't set up yet, and everything else keeps working on the tablet.

**Google Drive** (in the Google Cloud project from Part 1):
1. **APIs & Services → Library → Google Drive API → Enable.**
2. **Data access → Add or remove scopes**: tick `https://www.googleapis.com/auth/drive.file` ("See, edit, create and delete only the specific Google Drive files you use with this app"). It's **non-sensitive**: no verification is needed for it, even published. Endless sees only the files and folders it makes, not the rest of your Drive. That's why Change folder lists only folders Endless made (or makes a new one).
3. The Android client and the Web client from Part 1 (steps 7 and 8) are all Android needs. Send me the **Web client ID**.
4. *(Windows)* The Desktop client from step 9: its ID and secret.

**OneDrive** (in the app registration from Part 2):
1. **API permissions → Add a permission → Microsoft Graph → Delegated**: `Files.ReadWrite` (with `offline_access` and `User.Read`, already there for the calendar). Personal accounts approve it when they sign in.
2. **Authentication → Add a platform → Mobile and desktop applications** → *Custom redirect URIs*: `com.endless.endless://auth` → **Configure**. (Endless signs in to Microsoft on Android through the system browser with AppAuth, which comes back to the app at that address. The `msauth://` Android platform from step 2b.4 isn't used for this.)
3. *(Windows)* `http://localhost` under Mobile and desktop applications (step 2b.5).
4. Send me the **Application (client) ID**.

**Building with them.** Client ids aren't secrets; they go in at build time:

```
flutter build apk --release   --dart-define=GOOGLE_WEB_CLIENT_ID=1234-abc.apps.googleusercontent.com   --dart-define=MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000
```

For Windows add `--dart-define=GOOGLE_DESKTOP_CLIENT_ID=…` and `--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=…`. They're read in `lib/sync/cloud_auth.dart` (`CloudIds`).

**Who owns what, and how long it lasts.**
- **The developer side** (the Google Cloud project and the Microsoft app registration) belongs to the account you make them with. It isn't the account people sync with: anyone can sign in to Endless with their own Google or Microsoft account. To hand it over: Google Cloud → IAM → add another Google account as **Owner** (then the first can be removed); Microsoft Entra → the app registration → **Owners** → add one (and, for the tenant itself, make another account a Global Administrator). The client ids don't change, so no new build is needed.
- **Google OAuth clients unused for six months are deleted by Google** (its policy since 2025). Any sign-in or token refresh from Endless counts as use, so a client in regular use stays.
- **Google Desktop client secret** (Windows only): the console shows it once, when it's made. Copy it then.
- **Microsoft**: Endless has no client secret, so nothing expires on that side.
- **Signing in, for people using Endless.** On Android, Google sign-in rides on the Google account already on the tablet: sign in once; it lasts until access is removed in the Google account's settings, or the account leaves the tablet. On Windows, a refresh token: it lasts until unused for 6 months or revoked. Microsoft: a refresh token that lasts 90 days and renews each time it's used, so opening Endless now and then keeps it; a password change or "sign out everywhere" means signing in again. In Endless: Settings › Sync & backup → Change folder → **Use another account** switches accounts.
- **Testing mode (Google)**: while the project's audience is "Testing", Google signs everyone out every 7 days and only listed test users can sign in. With only `drive.file` (non-sensitive), **Publish app** removes both without verification. (Two-way calendar sync later adds sensitive calendar scopes; then the "unverified app" warning and the 100-user cap apply until it's verified.)

**Costs.** The Drive API and Microsoft Graph are free for this use. Notebooks count against your own Drive or OneDrive storage (15 GB free on Google, 5 GB on OneDrive); big videos moved there count too.

# Setting up Google Calendar and Outlook sync

The calendar syncs both ways with Google Calendar and with Outlook / Microsoft 365. Endless talks to them directly from the tablet: there is no Endless server. For that, Google and Microsoft each need to know the app exists. You register it once with each, and they give you an ID that goes into the app.

Everything below is for **Endless on Android** (package `com.endless.endless`). Windows needs one extra client per provider, listed at the end of each part.

The planner and a calendar kept on the tablet work without any of this.

**Not needed yet.** For now Endless shows Google and Outlook calendars from their calendar links, view only (Phase 7d, the owner's choice on 2026-11-04): Calendar → Connect → **Add a calendar link**, and paste the calendar's private iCal (.ics) address. That needs no Google Cloud project, no Microsoft app registration and no card, and costs nothing. This guide is for two-way sync, later.

- **Google Calendar** (on the web; the phone app doesn't show it): Settings → pick the calendar under "Settings for my calendars" → **Integrate calendar** → **Secret address in iCal format** → copy. If the link is ever shared by mistake, **Reset** there makes a new one; add the new one in Endless.
- **Outlook.com / Outlook on the web:** Settings → Calendar → **Shared calendars** → **Publish a calendar** → pick the calendar and **Can view all details** → **Publish** → copy the **ICS** link. A work or school Microsoft 365 account may have publishing turned off by its admin.

## What it costs

| | Cost | What isn't free |
|---|---|---|
| Google Cloud project | Free. No billing account is needed | — |
| Google Calendar API | Free. There are usage limits, which one person's calendar won't reach | — |
| Google sign-in (Testing mode) | Free | Up to 100 test users you list by email. **Sign-ins in Testing expire after 7 days**, so you sign in again weekly |
| Google verification (to publish) | No fee listed by Google | Needs a homepage and a privacy policy on a **domain you own** (about $10–20 a year), plus a short unlisted YouTube video of the sign-in. Takes 3–5 business days. Calendar scopes are "sensitive", not "restricted", so the paid yearly security assessment doesn't apply. The console labels each scope when you add it; check that it says *Sensitive* |
| Microsoft Entra app registration | Free (Entra ID Free tier) | You need an Entra **tenant**. A personal Outlook.com account can't register apps by itself. The free Azure account creates a tenant, and its sign-up asks for a phone number and a **credit or debit card to verify who you are** (a temporary hold, usually $1; no charge unless you upgrade) |
| Microsoft Graph calendar API | Free | — |
| Microsoft publisher verification | Free | Only matters when people at *other* companies sign in with work accounts: their IT may have to approve Endless. Personal Outlook.com accounts aren't affected |

Short version: **you can set up and use both for $0.** Money comes in only when you publish to the public: a domain for Google's verification, and possibly Microsoft publisher verification for companies.

## Your app's details (needed below)

| | Value |
|---|---|
| Android package name | `com.endless.endless` |
| SHA-1 of the signing key (Google) | `25:6A:07:AE:54:CB:E1:26:7A:1F:95:ED:69:78:36:D9:BB:03:5E:CA` |
| Signature hash (Microsoft) | `JWoHrlTL4SZ6H5XtaXg22bsDXso=` |

These come from this PC's debug key (`~/.android/debug.keystore`), which signs both the debug and release builds today. **When the app gets its own release key or goes on Google Play, add that key's SHA-1 and hash too** (Play shows its "App signing key" SHA-1 under Setup → App signing). Builds signed with a key that isn't listed can't sign in.

## Part 1: Google (about 15 minutes)

1. Go to <https://console.cloud.google.com> and sign in with the Google account you'll own the project with.
2. **Create a project.** Use the project picker at the top → **New project** → name it `Endless` → **Create**. Make sure it's selected afterwards.
3. **Turn on the Calendar API.** Go to **APIs & Services → Library**, search for **Google Calendar API**, open it and click **Enable**.
4. **Set up the consent screen.** Go to **Google Auth Platform** (in older consoles: **APIs & Services → OAuth consent screen**) → **Get started**.
   - App information: name `Endless`, and your email as the support email.
   - Audience: **External**.
   - Contact information: your email.
   - Agree to the policy → **Create**.
5. **Add yourself as a test user.** **Audience → Test users → Add users**, then enter every Gmail address you'll sign in with (yours, and anyone helping you test). The limit is 100.
6. **Add the scopes.** **Data access → Add or remove scopes**. Filter for "calendar" and tick these two:
   - `https://www.googleapis.com/auth/calendar.calendarlist.readonly` (to list your calendars: School, Personal…)
   - `https://www.googleapis.com/auth/calendar.events` (to read, add, change and delete events)

   Click **Update**, then **Save**. Both should show as *Sensitive*.
7. **Create the Android client.** **Clients → Create client**:
   - Application type: **Android**
   - Name: `Endless Android`
   - Package name: `com.endless.endless`
   - SHA-1 certificate fingerprint: `25:6A:07:AE:54:CB:E1:26:7A:1F:95:ED:69:78:36:D9:BB:03:5E:CA`
   - **Create**. You don't have to copy anything: Google matches the app by package name and fingerprint.
8. **Create the Web client.** Android's sign-in also needs this one, even though Endless isn't a website. **Clients → Create client**:
   - Application type: **Web application**
   - Name: `Endless (for Android sign-in)`
   - Leave the URIs empty → **Create**.
   - **Copy the Client ID** (it ends in `.apps.googleusercontent.com`). **Send me this one.** You don't need its secret.
9. *(For Windows, now or later.)* **Clients → Create client** → **Desktop app**, named `Endless Windows`. Copy its Client ID **and** its Client secret. For desktop apps Google doesn't treat the secret as secret, but don't paste it anywhere public; I'll read it from a build setting rather than the code.

**About Testing mode.** While the app is in Testing, only your test users can sign in, and Google makes everyone sign in again every 7 days. For your own use there's a shortcut. **Audience → Publish app** moves it to "In production" without verification. After that, sign-in shows a "Google hasn't verified this app" warning (click **Advanced → Go to Endless**), up to 100 people can use it, and the 7-day sign-in expiry stops. Verification (see the table above) removes the warning and the limit, and is only needed before a public release.

## Part 2: Microsoft (about 15 minutes)

### 2a. Get a tenant (once)

App registrations live in a Microsoft Entra **tenant** (a directory). Use whichever case applies to you:

- **You have a work or school Microsoft account that is allowed to register apps:** you can use that tenant. Skip to 2b. If **New registration** is greyed out, your organization doesn't allow it; use the option below instead.
- **You only have a personal account (Outlook.com, Hotmail, Live):** sign up for the free Azure account at <https://azure.microsoft.com/free>. Open a private browser window, sign in with your personal account, and follow the sign-up (phone number plus a card for identity verification). This creates a tenant called **Default Directory**, with you as its Global Administrator. When the free credit period ends, don't upgrade if you don't want to; app registrations are in Entra ID's free tier. (I couldn't find Microsoft stating outright that registrations keep working after the trial subscription lapses. Forum reports say they do. If it ever stops, the registration can be made again in minutes.)

### 2b. Register Endless

1. Go to <https://entra.microsoft.com> and sign in. If you have more than one tenant, use the ⚙️ Settings icon at the top to switch to the right one.
2. **Entra ID → App registrations → New registration.**
   - Name: `Endless`
   - Supported account types: **Any Entra ID Tenant + Personal Microsoft accounts** (so both Outlook.com and work Microsoft 365 calendars can sign in)
   - Leave Redirect URI empty for now → **Register**.
3. On the **Overview** page, **copy the Application (client) ID**. **Send me this one.** You don't need the tenant ID: Endless signs in through Microsoft's shared "common" endpoint.
4. **Add the Android platform.** **Authentication → Add a platform → Android**:
   - Package name: `com.endless.endless`
   - Signature hash: `JWoHrlTL4SZ6H5XtaXg22bsDXso=`
   - **Configure**. It shows a redirect URI starting `msauth://com.endless.endless/…`; nothing to copy.
5. *(For Windows, now or later.)* **Authentication → Add a platform → Mobile and desktop applications**, tick or enter `http://localhost` → **Configure**.
6. Still in **Authentication**, at the bottom: **Allow public client flows → Yes** → **Save**. (Endless is a "public client": it has no server, so it has no secret.)
7. **API permissions → Add a permission → Microsoft Graph → Delegated permissions**, then tick:
   - `Calendars.ReadWrite`
   - `offline_access` (so you stay signed in)
   - `User.Read` is already there; keep it.

   **Add permissions.** You don't need "Grant admin consent" for your own account; each person approves when they sign in. A company tenant may require its admin to approve Endless once.
8. Leave **Certificates & secrets** empty. Endless must not have a secret.

## What to send me

- Google **Web client ID** (step 1.8)
- Microsoft **Application (client) ID** (step 2b.3)
- Optional, for Windows: the Google **Desktop client ID and secret** (step 1.9), and confirm you added `http://localhost` (step 2b.5)

Client IDs aren't secrets. They go into `lib/calendar/cloud_ids.dart`. The desktop secret goes in as a build setting (`--dart-define`), not in the code.

Sources: Google's OAuth docs on Testing-mode refresh tokens ([OAuth 2.0](https://developers.google.com/identity/protocols/oauth2)), unverified apps ([Help](https://support.google.com/cloud/answer/7454865)) and sensitive-scope verification ([guide](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)); Microsoft's [Register an app in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) and [Entra ID Free](https://azure.microsoft.com/free/entra-id). Checked 2026-10-28.
