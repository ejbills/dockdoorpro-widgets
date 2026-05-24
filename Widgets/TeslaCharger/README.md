# Tesla Charger Widget

Tesla Charger is a DockDoor Pro widget for Tesla owners who want live charging status in the dock and quick Fleet API charging controls from the widget panel.

The widget uses Tesla's official Fleet API. Each user must bring their own Tesla developer application and OAuth credentials; the widget does not ship with any shared Tesla account, token, key, or backend service.

## What It Shows

- Battery percentage, charge limit, charging state, power, current, voltage, and energy added
- Vehicle name, model, trim, VIN, odometer, software version, active FSD package, and latest release note title
- A Tesla-hosted vehicle render, with Fleet API paint color override when available
- Cached last-good data while the vehicle is asleep or temporarily unavailable

## Commands

The panel includes buttons for:

- Start charging
- Stop charging
- Open charge port
- Set charge limit
- Set charging amps

Command success depends on Tesla account scopes, region, vehicle support, virtual key setup, and whether the vehicle requires signed commands. If a command fails, confirm that the Tesla developer app requested the command scopes listed below and that the vehicle accepts Fleet API commands for your account.

## Tesla Developer Setup

Create a Tesla developer app at the Tesla Developer Portal:

1. Open `https://developer.tesla.com`.
2. Create an application for personal use.
3. Enable OAuth authorization-code and client-credentials grants.
4. Add this redirect URI:

   ```text
   http://localhost:8765/callback
   ```

5. Add this origin:

   ```text
   http://localhost:8765
   ```

6. Request these scopes:

   ```text
   openid offline_access vehicle_device_data vehicle_cmds vehicle_charging_cmds
   ```

The visible names in Tesla's UI are usually Vehicle Information, Vehicle Commands, and Vehicle Charging Management.

## Public Key And Partner Registration

Tesla Fleet API apps need a public key hosted on a domain you control. GitHub Pages, Netlify, Cloudflare Pages, or your own website are fine.

Generate a keypair:

```bash
python3 scripts/tesla-widget-auth.py generate-keypair
```

Host the generated public key at exactly this path on your domain:

```text
https://YOUR_DOMAIN/.well-known/appspecific/com.tesla.3p.public-key.pem
```

Keep the private key local. Do not upload `private-key.pem`.

After the public key URL is live, register the domain with Tesla:

```bash
python3 scripts/tesla-widget-auth.py register --domain YOUR_DOMAIN
```

Use only the domain name for `--domain`, for example `example.com`, not the `.well-known` path.

## Local Login

Configure the helper with the client ID and client secret from your Tesla developer app:

```bash
python3 scripts/tesla-widget-auth.py configure \
  --client-id YOUR_CLIENT_ID \
  --client-secret YOUR_CLIENT_SECRET
```

Sign in with your Tesla account:

```bash
python3 scripts/tesla-widget-auth.py login
```

The helper opens Tesla OAuth in your browser, receives the localhost callback, stores tokens under:

```text
~/Library/Application Support/DDP Tesla Charger Widget/
```

It also writes the Fleet API base URL, access token, and VIN into DockDoor Pro widget defaults.
The helper also writes the OAuth client ID and refresh token so the widget can renew expired access tokens automatically.

Refresh tokens later with:

```bash
python3 scripts/tesla-widget-auth.py refresh
```

## Vehicle Image

The widget can render a Tesla-hosted vehicle image using your live vehicle configuration:

```bash
python3 -m pip install Pillow
python3 scripts/tesla-widget-auth.py render-image
```

This downloads a Tesla compositor image, applies the Fleet API paint color override when available, crops transparent padding, and writes the image path into DockDoor Pro settings.

Tesla's Fleet API does not expose the exact custom Paint Shop texture from the Tesla app avatar. The helper uses official Tesla compositor imagery plus the vehicle's live paint override.

## DockDoor Pro Settings

The widget exposes these settings in DockDoor Pro:

- Fleet API Base URL
- Tesla OAuth Access Token
- Tesla OAuth Refresh Token
- Tesla OAuth Client ID
- Vehicle VIN
- Skin Image URL
- Local Skin Image Path
- Refresh Interval Seconds
- Wake Vehicle Before Refresh

Most users should use `scripts/tesla-widget-auth.py configure`, `login`, and `render-image` instead of filling these manually.

## Security Notes

- OAuth tokens are stored locally in the user's Application Support folder.
- The widget reads the access token from DockDoor Pro defaults to call Tesla Fleet API directly.
- The widget reads the refresh token and client ID from DockDoor Pro defaults only to renew an expired access token.
- Do not share `tokens.json`, `partner-token.json`, `oauth-client.json`, or `private-key.pem`.
- Do not commit those files to GitHub.
- If a token or private key is exposed, revoke the Tesla developer app secret and re-authorize the account.

## Troubleshooting

If the panel says the vehicle is asleep or offline, that is usually Tesla returning HTTP 408. The widget keeps showing cached last-good data. Wake the car from the Tesla app or enable Wake Vehicle Before Refresh in the widget settings if you want refreshes to wake the vehicle.

If commands fail but data loads, confirm your OAuth scopes include `vehicle_cmds` and `vehicle_charging_cmds`, then check whether your vehicle requires virtual key setup or signed commands.

If no vehicle appears, run:

```bash
python3 scripts/tesla-widget-auth.py status
python3 scripts/tesla-widget-auth.py refresh
```

Then restart DockDoor Pro.
