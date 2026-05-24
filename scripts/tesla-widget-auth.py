#!/usr/bin/env python3
import argparse
import base64
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


APP_DIR = Path.home() / "Library" / "Application Support" / "DDP Tesla Charger Widget"
CONFIG_PATH = APP_DIR / "oauth-client.json"
TOKEN_PATH = APP_DIR / "tokens.json"
PARTNER_TOKEN_PATH = APP_DIR / "partner-token.json"
KEY_DIR = APP_DIR / "tesla-fleet-key"
PRIVATE_KEY_PATH = KEY_DIR / "private-key.pem"
PUBLIC_KEY_PATH = KEY_DIR / "com.tesla.3p.public-key.pem"
DOCKDOOR_DOMAIN = "com.ejbills.DockDoorPro"
WIDGET_ID = "tesla-charger"
AUTH_URL = "https://auth.tesla.com/oauth2/v3/authorize"
TOKEN_URL = "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token"
DEFAULT_AUDIENCE = "https://fleet-api.prd.na.vn.cloud.tesla.com"
DEFAULT_REDIRECT_URI = "http://localhost:8765/callback"
DEFAULT_SCOPE = "openid offline_access vehicle_device_data vehicle_cmds vehicle_charging_cmds"
COMPOSITOR_URL = "https://static-assets.tesla.com/v1/compositor/"


def ensure_app_dir():
    APP_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(APP_DIR, 0o700)


def atomic_json_write(path, data):
    ensure_app_dir()
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    os.chmod(tmp, 0o600)
    tmp.replace(path)


def load_json(path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def configure(args):
    config = {
        "client_id": args.client_id.strip(),
        "client_secret": args.client_secret.strip(),
        "redirect_uri": args.redirect_uri,
        "audience": args.audience,
        "scope": args.scope,
        "vehicle_vin": args.vehicle_vin.strip(),
    }
    if not config["client_id"] or not config["client_secret"]:
        raise SystemExit("client_id and client_secret are required")
    atomic_json_write(CONFIG_PATH, config)
    write_widget_defaults(config=config)
    print(f"Saved OAuth client config to {CONFIG_PATH}")


def make_pkce():
    raw = secrets.token_urlsafe(64)
    digest = hashlib.sha256(raw.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")
    return raw, challenge


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    server_version = "TeslaWidgetOAuth/1.0"

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        self.server.auth_code = params.get("code", [None])[0]
        self.server.auth_state = params.get("state", [None])[0]
        self.server.auth_error = params.get("error", [None])[0]
        ok = self.server.auth_code and not self.server.auth_error
        body = (
            "<html><body><h1>Tesla login complete</h1>"
            "<p>You can close this tab and return to Codex.</p></body></html>"
            if ok
            else "<html><body><h1>Tesla login failed</h1><p>Return to Codex for details.</p></body></html>"
        )
        self.send_response(200 if ok else 400)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body.encode("utf-8"))

    def log_message(self, fmt, *args):
        return


def login(_args):
    config = load_json(CONFIG_PATH)
    verifier, challenge = make_pkce()
    state = secrets.token_urlsafe(24)
    redirect_uri = config.get("redirect_uri", DEFAULT_REDIRECT_URI)
    port = urllib.parse.urlparse(redirect_uri).port or 8765

    params = {
        "response_type": "code",
        "client_id": config["client_id"],
        "redirect_uri": redirect_uri,
        "scope": config.get("scope", DEFAULT_SCOPE),
        "state": state,
        "nonce": secrets.token_urlsafe(16),
        "prompt": "login",
        "prompt_missing_scopes": "true",
        "require_requested_scopes": "true",
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    url = AUTH_URL + "?" + urllib.parse.urlencode(params)

    server = http.server.HTTPServer(("127.0.0.1", port), CallbackHandler)
    server.timeout = 240
    server.auth_code = None
    server.auth_state = None
    server.auth_error = None

    subprocess.run(["open", url], check=False)
    print("Opened Tesla login in your browser. Waiting for OAuth callback...")

    deadline = time.time() + 240
    while time.time() < deadline and not server.auth_code and not server.auth_error:
        server.handle_request()

    if server.auth_error:
        raise SystemExit(f"Tesla authorization failed: {server.auth_error}")
    if not server.auth_code:
        raise SystemExit("Timed out waiting for Tesla OAuth callback")
    if server.auth_state != state:
        raise SystemExit("OAuth state mismatch; refusing token exchange")

    token = exchange_code(config, server.auth_code, verifier)
    atomic_json_write(TOKEN_PATH, token)
    config = sync_vehicle_vin(config, token)
    write_widget_defaults(config=config, token=token)
    print(f"Saved tokens to {TOKEN_PATH}")
    print("Wrote DockDoor Pro widget defaults. Restart DockDoor Pro if the widget does not refresh.")


def exchange_code(config, code, verifier):
    payload = {
        "grant_type": "authorization_code",
        "client_id": config["client_id"],
        "client_secret": config["client_secret"],
        "code": code,
        "audience": config.get("audience", DEFAULT_AUDIENCE),
        "redirect_uri": config.get("redirect_uri", DEFAULT_REDIRECT_URI),
        "code_verifier": verifier,
    }
    return post_form(payload)


def refresh(_args):
    config = load_json(CONFIG_PATH)
    tokens = load_json(TOKEN_PATH)
    refresh_token = tokens.get("refresh_token")
    if not refresh_token:
        raise SystemExit("No refresh_token found; run login again")
    payload = {
        "grant_type": "refresh_token",
        "client_id": config["client_id"],
        "refresh_token": refresh_token,
    }
    token = post_form(payload)
    atomic_json_write(TOKEN_PATH, token)
    config = sync_vehicle_vin(config, token)
    write_widget_defaults(config=config, token=token)
    print("Refreshed Tesla token and updated DockDoor Pro widget defaults.")


def post_form(payload):
    data = urllib.parse.urlencode(payload).encode("utf-8")
    request = urllib.request.Request(
        TOKEN_URL,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Tesla token request failed: HTTP {exc.code}: {body}")


def partner_token(_args):
    config = load_json(CONFIG_PATH)
    token = request_partner_token(config)
    atomic_json_write(PARTNER_TOKEN_PATH, token)
    print(f"Saved partner token to {PARTNER_TOKEN_PATH}")


def request_partner_token(config):
    payload = {
        "grant_type": "client_credentials",
        "client_id": config["client_id"],
        "client_secret": config["client_secret"],
        "audience": config.get("audience", DEFAULT_AUDIENCE),
        "scope": "openid vehicle_device_data vehicle_cmds vehicle_charging_cmds",
    }
    return post_form(payload)


def generate_keypair(args):
    KEY_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(KEY_DIR, 0o700)
    if PRIVATE_KEY_PATH.exists() and PUBLIC_KEY_PATH.exists() and not args.force:
        raise SystemExit(f"Keypair already exists in {KEY_DIR}. Re-run with --force to replace it.")

    subprocess.run(
        ["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(PRIVATE_KEY_PATH)],
        check=True,
    )
    subprocess.run(
        ["openssl", "ec", "-in", str(PRIVATE_KEY_PATH), "-pubout", "-out", str(PUBLIC_KEY_PATH)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    os.chmod(PRIVATE_KEY_PATH, 0o600)
    os.chmod(PUBLIC_KEY_PATH, 0o644)
    print(f"Private key: {PRIVATE_KEY_PATH}")
    print(f"Public key:  {PUBLIC_KEY_PATH}")
    print("Host the public key at: https://YOUR_DOMAIN/.well-known/appspecific/com.tesla.3p.public-key.pem")


def register(args):
    domain = args.domain.strip().removeprefix("https://").removeprefix("http://").strip("/")
    if not domain:
        raise SystemExit("--domain is required, for example: --domain example.com")

    config = load_json(CONFIG_PATH)
    partner = request_partner_token(config)
    atomic_json_write(PARTNER_TOKEN_PATH, partner)
    token = partner.get("access_token")
    if not token:
        raise SystemExit("Partner token response did not include access_token")

    url = config.get("audience", DEFAULT_AUDIENCE).rstrip("/") + "/api/1/partner_accounts"
    payload = json.dumps({"domain": domain}).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            print(f"Registered partner account for {domain}: HTTP {response.status}")
            print(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Partner registration failed: HTTP {exc.code}: {body}")


def render_image(args):
    try:
        from PIL import Image
    except ImportError:
        raise SystemExit("Pillow is required for render-image")

    config = load_json(CONFIG_PATH)
    tokens = load_json(TOKEN_PATH)
    vin = config.get("vehicle_vin")
    if not vin:
        raise SystemExit("No vehicle VIN configured; run login or refresh first")

    vehicle_data = fleet_get(config, tokens, f"/api/1/vehicles/{vin}/vehicle_data")
    options_data = fleet_get(config, tokens, f"/api/1/dx/vehicles/options?vin={urllib.parse.quote(vin)}")
    response = vehicle_data.get("response", {})
    vehicle_config = response.get("vehicle_config", {})
    active_options = [
        item.get("code", "").lstrip("$")
        for item in options_data.get("codes", [])
        if item.get("isActive") and item.get("code")
    ]
    color_code = next((code for code in active_options if code.startswith("P")), None)
    wheel_code = next((code for code in active_options if code.startswith("W")), None)
    model = car_model_code(vehicle_config.get("car_type"))
    options = ",".join(f"${code}" for code in [color_code, wheel_code] if code)
    if not options:
        options = "$PPSW,$W41B"

    params = urllib.parse.urlencode({
        "model": model,
        "view": "STUD_3QTR",
        "size": str(args.size),
        "bkba_opt": "1",
        "options": options,
    }, safe="$,")
    base_image_url = f"{COMPOSITOR_URL}?{params}"

    output = Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp_base = output.with_suffix(".base.png")
    urllib.request.urlretrieve(base_image_url, tmp_base)

    image = Image.open(tmp_base).convert("RGBA")
    override = parse_paint_override(vehicle_config.get("paint_color_override"))
    if override:
        image = colorize_white_body(image, override)
    image = crop_transparent_bounds(image, padding=24)
    image.save(output)
    tmp_base.unlink(missing_ok=True)
    defaults_write("skinImagePath", str(output))
    print(f"Rendered Tesla API/compositor image to {output}")
    print(f"Compositor URL: {base_image_url}")
    if override:
        print(f"Applied Fleet API paint_color_override RGB: {override[0]}, {override[1]}, {override[2]}")


def fleet_get(config, tokens, path):
    token = tokens.get("access_token")
    if not token:
        raise SystemExit("No access_token found; run login first")
    url = config.get("audience", DEFAULT_AUDIENCE).rstrip("/") + path
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Fleet API request failed: HTTP {exc.code}: {body}")


def car_model_code(car_type):
    return {
        "model3": "m3",
        "modely": "my",
        "models": "ms",
        "modelx": "mx",
    }.get(car_type, "m3")


def parse_paint_override(value):
    if not value:
        return None
    try:
        parts = [float(part.strip()) for part in str(value).split(",")]
    except ValueError:
        return None
    if len(parts) < 3:
        return None
    return tuple(max(0, min(255, int(round(part)))) for part in parts[:3])


def colorize_white_body(image, target_rgb):
    import colorsys

    target_h, target_s, _ = colorsys.rgb_to_hsv(
        target_rgb[0] / 255,
        target_rgb[1] / 255,
        target_rgb[2] / 255,
    )
    pixels = image.load()
    width, height = image.size

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            # Tesla's compositor body paint is near-neutral and bright. Leave dark glass,
            # tires, shadows, and saturated tail lights/headlights alone.
            if s < 0.18 and 0.45 < v < 0.98:
                strength = min(1.0, max(0.0, (v - 0.45) / 0.35))
                nr, ng, nb = colorsys.hsv_to_rgb(target_h, min(1.0, target_s * 0.95), v)
                blend = 0.82 * strength
                pixels[x, y] = (
                    int(r * (1 - blend) + nr * 255 * blend),
                    int(g * (1 - blend) + ng * 255 * blend),
                    int(b * (1 - blend) + nb * 255 * blend),
                    a,
                )
    return image


def crop_transparent_bounds(image, padding=0):
    alpha = image.getchannel("A").point(lambda value: 255 if value > 16 else 0)
    bbox = alpha.getbbox()
    if not bbox:
        return image
    left, top, right, bottom = bbox
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(image.width, right + padding)
    bottom = min(image.height, bottom + padding)
    return image.crop((left, top, right, bottom))


def write_widget_defaults(config=None, token=None):
    if config:
        defaults_write("apiBaseURL", config.get("audience", DEFAULT_AUDIENCE))
        if config.get("client_id"):
            defaults_write("clientId", config["client_id"])
        if config.get("vehicle_vin"):
            defaults_write("vehicleVin", config["vehicle_vin"])
    if token and token.get("access_token"):
        defaults_write("accessToken", token["access_token"])
    if token and token.get("refresh_token"):
        defaults_write("refreshToken", token["refresh_token"])


def sync_vehicle_vin(config, token):
    if config.get("vehicle_vin") or not token.get("access_token"):
        return config

    url = config.get("audience", DEFAULT_AUDIENCE).rstrip("/") + "/api/1/vehicles"
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token['access_token']}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        print(f"Could not auto-discover vehicle VIN: {exc}")
        return config

    vehicles = payload.get("response") or []
    if not vehicles:
        print("No vehicles returned by Fleet API; set vehicle VIN manually in DockDoor settings.")
        return config

    first = vehicles[0]
    vin = first.get("vin")
    if vin:
        updated = dict(config)
        updated["vehicle_vin"] = vin
        atomic_json_write(CONFIG_PATH, updated)
        print("Auto-discovered vehicle VIN and saved it to widget defaults.")
        return updated
    return config


def defaults_write(key, value):
    subprocess.run(
        [
            "defaults",
            "write",
            DOCKDOOR_DOMAIN,
            f"widget.{WIDGET_ID}.{key}",
            str(value),
        ],
        check=True,
    )


def status(_args):
    print(f"Config: {'present' if CONFIG_PATH.exists() else 'missing'} ({CONFIG_PATH})")
    print(f"Tokens: {'present' if TOKEN_PATH.exists() else 'missing'} ({TOKEN_PATH})")
    print(f"Partner token: {'present' if PARTNER_TOKEN_PATH.exists() else 'missing'} ({PARTNER_TOKEN_PATH})")
    if TOKEN_PATH.exists():
        tokens = load_json(TOKEN_PATH)
        expires_in = tokens.get("expires_in")
        print(f"Last token response includes access token: {'yes' if tokens.get('access_token') else 'no'}")
        if expires_in:
            print(f"Token expires_in from last response: {expires_in} seconds")


def main():
    parser = argparse.ArgumentParser(description="Tesla OAuth helper for the DockDoor Pro Tesla Charger widget")
    sub = parser.add_subparsers(dest="command", required=True)

    setup = sub.add_parser("configure", help="Save OAuth client credentials locally")
    setup.add_argument("--client-id", required=True)
    setup.add_argument("--client-secret", required=True)
    setup.add_argument("--vehicle-vin", default="")
    setup.add_argument("--redirect-uri", default=DEFAULT_REDIRECT_URI)
    setup.add_argument("--audience", default=DEFAULT_AUDIENCE)
    setup.add_argument("--scope", default=DEFAULT_SCOPE)
    setup.set_defaults(func=configure)

    login_parser = sub.add_parser("login", help="Open Tesla OAuth login and save tokens")
    login_parser.set_defaults(func=login)

    refresh_parser = sub.add_parser("refresh", help="Refresh tokens and update widget defaults")
    refresh_parser.set_defaults(func=refresh)

    partner_parser = sub.add_parser("partner-token", help="Request a client-credentials partner token")
    partner_parser.set_defaults(func=partner_token)

    key_parser = sub.add_parser("generate-keypair", help="Generate a Tesla Fleet API public/private keypair")
    key_parser.add_argument("--force", action="store_true", help="Replace an existing keypair")
    key_parser.set_defaults(func=generate_keypair)

    register_parser = sub.add_parser("register", help="Register the public-key domain with Tesla Fleet API")
    register_parser.add_argument("--domain", required=True, help="Domain hosting the Tesla public key, without a path")
    register_parser.set_defaults(func=register)

    render_parser = sub.add_parser("render-image", help="Render a Tesla-hosted vehicle image using live Fleet API config")
    render_parser.add_argument(
        "--output",
        default=str(APP_DIR / "assets" / "tesla-api-render.png"),
    )
    render_parser.add_argument("--size", type=int, default=800)
    render_parser.set_defaults(func=render_image)

    status_parser = sub.add_parser("status", help="Show local helper status")
    status_parser.set_defaults(func=status)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
