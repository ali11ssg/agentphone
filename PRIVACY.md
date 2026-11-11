# Privacy

AgentPhone is an independent community project. It is not built, maintained,
endorsed by, or affiliated with the official OpenCode team, and it is not
affiliated with Anthropic.

This app is built for one person: you. It talks only to the servers you
configure, and to the official download hosts of the pieces it installs.

## What is sent

**Nothing.** AgentPhone has no analytics, no crash-reporting service and no
performance tracing. There is no vendor SDK in the app and no telemetry
endpoint. No usage counts, no device ranges, no crash reports, no install ID,
no advertising ID.

## What stays on the phone

- Your projects, conversations, settings and saved servers.
- The Linux environment the app installs for you (Ubuntu, Git, Node and the
  agent), inside the app's own storage.
- Saved crash reports: only *what kind* of problem happened and *when* —
  never the error message, never your conversations, never a key.
- A short diagnostics ring buffer: the last 500 log lines, with keys, URLs,
  host names, addresses and paths already blanked.

## What you can send, and only when you choose

**Settings → Help → Send a problem report** shows you the whole report before
anything leaves the phone. Nothing is sent automatically; you read it, and you
press **Send**. The report goes to whoever you send it to, and it contains the
same redacted content shown on screen.

## Keys and passwords

API keys you add (for a model provider, a server password) are kept in the
Android keystore through the system keystore, never in plain files, and never
in the Linux environment the app installs. The agent itself receives a
placeholder token: the real key is added by a local gateway inside the app,
on the device, when the request leaves.

## Network

The app connects only to:

- the server you configure (your own computer, or the one inside the app), on
  `127.0.0.1` or the address you type;
- the official download hosts of the pieces the app installs (the Linux image,
  the agent binary and the package archives inside it);
- the provider endpoints you enter yourself, for the models you choose.

There is no advertising SDK, no crash SDK and no telemetry SDK. The app does
not read the advertising ID, and it does not ask for "all files access".

## Permissions

The app asks for the fewest permissions that still let it work:

| Permission | Why |
| --- | --- |
| `INTERNET` | Talk to the server you configured and to the provider you chose. |
| `POST_NOTIFICATIONS` | Show the status of a running agent, and ask you to approve a command. |
| `FOREGROUND_SERVICE` (with its type permissions) | Keep the agent's server alive while you use other apps. |
| `WAKE_LOCK` | Keep the phone awake only while a task is actually running. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Let the user exempt the app so a long task is not killed. |
| `USE_BIOMETRIC` | Optional app lock: open the app with your fingerprint or face. |

No location, no camera, no microphone, no contacts, no "all files access".

## Your projects are inside the app

The Linux environment and the projects live inside the app's own storage.
**Uninstalling the app deletes them.** Export your projects before you remove
the app, and keep the release signing key somewhere outside the phone: losing
it means the app can never be updated again.
