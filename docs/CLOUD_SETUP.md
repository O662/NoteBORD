# Setting up Google Calendar and Outlook sync

The calendar syncs both ways with Google Calendar and with Outlook / Microsoft 365. Endless talks to them directly from the tablet: there is no Endless server. For that, Google and Microsoft each need to know the app exists. You register it once with each, and they give you an ID that goes into the app.

Everything below is for **Endless on Android** (package `com.endless.endless`). Windows needs one extra client per provider, listed at the end of each part.

The planner and a calendar kept on the tablet work without any of this.

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
