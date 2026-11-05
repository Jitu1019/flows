# Zoop API flows (DevTools)

API flows for Zoop, built with [DevTools](https://dev.tools) and kept in git as YAML. Edit them on Studio's visual canvas, and run them from the CLI.

| Flow | File | What it does |
|---|---|---|
| `auth-journey` | `devtools/auth.yamlflow.yaml` | Logs in with the test account, then fetches the profile, rotates and verifies the token, and signs out. Also checks the 401 cases |
| `chat-session` | `devtools/chat-load.yamlflow.yaml` | Acts as one buyer chatting in a live stream over notification-service's Socket.IO connection. Its `load:` scenarios run many buyers at once |

## Quickstart

Requirements:
- DevTools CLI 1.6.1 (`~/.local/bin/devtools`; install with `curl -fsSL https://sh.dev.tools/install.sh | bash`)
- DevTools Studio 1.1.3, for the canvas
- Node 22.3+, which the CLI uses for JS steps
- macOS, for the chat flow's stream ID dialog

```bash
cp .env.example .env                                # fill in the test account, OTP and chat numbers
npm run devtools                                    # auth-journey against UAT; JUnit in reports/devtools-junit.xml
npm run devtools:chat                               # one chat session, per-step table
SCENARIO=chat-smoke npm run devtools:chat-load      # 2 buyers, 4 sessions
npm run devtools:chat-load                          # chat-ramp: up to 25 buyers, ~5 min
npm run devtools:chat-load -- --vus-scale 4         # chat-ramp with 4× the buyers
ZOOP_STREAM_ID=12345 npm run devtools:chat-load     # skip the stream ID dialog
npm run studio                                      # (re)start Studio with the values from .env
```

## Layout

```
devtools/auth.yamlflow.yaml        auth-journey flow
devtools/chat-load.yamlflow.yaml   chat-session flow + load scenarios (chat-smoke, chat-ramp)
scripts/chat-load.sh               loads .env, then runs the chat flow / a load scenario
scripts/studio.sh                  quits and relaunches Studio with the values from .env
.env.example                       test account, OTP and chat numbers; copy to .env (git-ignored)
reports/                           JUnit output (git-ignored)
```

**Secrets only come from the environment.** Flows read them with `{{ #env:NAME }}`, and JS steps read them from `process.env`. Test numbers log in with the bypass OTP in every environment, production included. So `.env` stays out of git, and both flows refuse the production host.

## Studio

- **Opening a flow:** start Studio with `npm run studio`, then *Import* → drop the file → open the flow → *Run*.
  - `npm run studio` quits a running Studio first. Studio only reads `{{ #env:… }}` values from the environment it was launched with. Opened from the Dock, it has no test account, so `Login` fails.
  - **chat-session** asks for the stream ID in a dialog on every *Run*, prefilled with the last one.
- **Studio 1.1.3's importer is incomplete:**
  - It skips `environments:` and request `assertions:`.
  - It rejects a `load:` block with anything but `constant-vus`.
  - It creates `ws_connection`, `ws_send` and `wait` nodes with no settings: no URL, message or duration.

  In the current Studio workspace, `chat-session` was imported without its `load:` block. Its missing settings, its `Login` assertions and the `uat`/`qa`/`local` environments were added through Studio's local API, so check them if you re-import. `auth-journey`'s assertions were lost the same way and haven't been restored.
- **Edits made in Studio stay in Studio's database.** To keep them, export the workspace as YAML and copy the changed flow back into its file. For `chat-load.yamlflow.yaml`, keep the file's `load:` block and environments; Studio's export has neither.

## Chat load test (notification-service socket)

One run of `chat-session` is one buyer, about 60 s in all:
1. Picks a test number and logs in.
2. Connects to notification-service.
3. Joins the stream's chat.
4. Posts 12 messages, 5 s apart.
5. Leaves.

- **Stream ID:** a macOS dialog asks for it. The stream must be live or scheduled; a completed stream is rejected at sign-in.
  - **Studio** asks on every *Run*, prefilled with the last answer.
  - **A CLI run** asks once, and every session in a load run reuses that answer. The load profile's clock keeps running while the dialog is open, so answer quickly or set `ZOOP_STREAM_ID`.
  - **Setting `ZOOP_STREAM_ID`** skips the dialog. Without a GUI, as on CI, it's required.
  - **Why a background dialog:** DevTools cuts a JS step off after 5 s and has no stdin, so `AskStreamId` opens the dialog in the background and the `WaitStreamId` loop polls for up to 2 minutes. Cancel, a timeout or a non-numeric answer stops the run at `CheckStreamId`.
- **Login:** each session picks one of `ZOOP_CHAT_MOBILES` at random and logs in through `POST /api/v1/auth/v2/otp/verify`. Its token authenticates that session's socket. Every login adds a session row in user-service that sign-out never expires, so a `chat-ramp` run adds roughly 100–150.
- **Target:** `active_environment` in the file picks the target: `uat` (default) or `qa`. Login and socket use the same host. Production is refused.
- **What it writes:** real chat messages in that stream. They go to Firebase `streamMessages/<stream>`, the Redis comment list, Pub/Sub and Mixpanel, through the same pipeline as the app. Each message ends in `· lt-<session>` and each session shows up as **Load &lt;session&gt;**, so they are easy to spot. Point it at a test stream.
- **Users:** with four numbers and up to 25 concurrent buyers, each user has several sockets open at once, each with its own display name. On UAT, four of the five chat test numbers log in. The one ending in 03 fails with a bare 400 "Something went wrong", which means user-service refused the account, so it's left out of `.env`. The server rejects the same text from one user within 30 s, so every message is a unique `faker` sentence.
- **What the report shows:** DevTools times HTTP steps only, so a load run's table covers `Login`, alongside `Iterations` and `Iteration errors`. WebSocket steps run but aren't timed. Read socket latency and server health from Cloud Run, CubeAPM or Grafana for notification-service. Watch the stream in the app to see chat arrive.
- **A session fails** (and counts as an iteration error) when:
  - a login fails: an assertion failure on `Login`
  - the socket rejects the token: `Socket connect rejected`
  - sign-in is refused: `signin rejected: Stream is completed`, blocked, …
  - a message is refused: `sendMessage rejected: duplicate_message`, `abusive_message`, …

  If every buyer's first session fails, the CLI reports "the target was not reachable". To see the real reason, run `npm run devtools:chat`.
- **Secrets in output:** `--show-output` and `--report json` print the login body (test number, OTP) and the handshake frame (access token). Don't share that output.

How it speaks Socket.IO: DevTools only has raw WebSocket steps, so the flow writes Socket.IO v4 frames by hand. The file header explains each frame:
- `40{"accessToken":…}` to connect
- `420["signin",…]` and `421["sendMessage",…]` with acks
- `3` and `42["pong"]` as heartbeats; the server drops the socket after about 40 s without them
- `41` to disconnect

The connection step keeps only the latest frame it received, so the checks poll it. Under load, another buyer's broadcast can overwrite an ack before the check reads it. Such a sign-in passes as `joined: "unconfirmed"` rather than failing.

## Login API: what the flows rely on

These were confirmed against UAT on 2026-11-01. The source is `auth-service` (UAT branch) and `user-service`.

| Call | Notes |
|---|---|
| `POST /api/v1/auth/v2/otp/verify` | Login. Body: `{country_code:"+91", mobile, otp, user_type, device_id:null}`. Send `device_id: null` explicitly. Tokens are **two envelopes deep**: `data.data.access_token`. No prior "send OTP" call is needed for a test number |
| `GET /api/v1/user/<userType>` | Profile, with a Bearer token. Returns 401 with no token or a bad one |
| `POST /api/v1/user/verifyLoginToken` | The token check every service uses, notification-service's socket included |
| `POST /api/v1/user/rotate-token` | `{refresh_token}`. A forged refresh token gives **401**; a malformed one gives **422**. The response's `refresh_token` may be `null` (keep the old one) |
| `POST /api/v1/auth/v2/signout` | Returns 200, but **does not revoke** the access token, which stays valid until it expires |

- **Test numbers** (`OTP_TEST_MOBILE` with `OTP_BYPASS_CODE`) log in **in every environment, production included**. They are exempt from rate limits and from the 5-wrong-attempts lockout.
- **Token lifetime:** `expires_in` is `86400` on UAT; the code default is 3600.

## DevTools format notes (CLI 1.6.1)

Verified while building these flows. The docs page is wrong on the first two.

- `ws_send` takes `ws_connection_node_name` (not `connection`), and `wait` takes `duration_ms` (not `duration: 2s`).
- A `for` loop's body depends on `Loop.loop`. The step after the loop must depend on **`Loop.then`**. A plain `depends_on: Loop` never runs, and the flow still exits 0.
- **Chaining:** `'{{ Login.response.body.data.data.access_token }}'` in a later step's field. The step must `depends_on` the step it reads; steps without `depends_on` run in parallel.
- **Secrets:** `'{{ #env:NAME }}'` written directly in a request field or `ws_send` message. It reads the process environment, then `./.env`. Inside `environments:` values it is **not** resolved.
- **Assertions** are [expr](https://expr-lang.org) expressions such as `response.status == 200` or `x matches "^eyJ"`. A failure prints every value involved, except JWT-looking strings, which are redacted.
- **Environment:** the CLI uses `active_environment`; there's no `--env` flag. Studio has an environment menu.
- **Templates:** `faker.sentence()`, `ulid()` and `now()` give a fresh value on every call. Load mode has no per-VU data (no VU index, no CSV feed).
- **JS steps** run in one long-lived Node worker (CLI: system Node; Studio: its bundled Node 24). That has three consequences:
  - `process.env` is readable.
  - `import()` is blocked, but `process.getBuiltinModule("node:child_process")` works.
  - Properties set on `process` survive from step to step and from one load iteration to the next.

  A step that takes more than 5 s fails with `context deadline exceeded`, and no YAML key changes that.
- **Reports:** the JSON report includes request and response bodies (test number, OTP, tokens), so the scripts only write console and JUnit output.
# flows
