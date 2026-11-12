#!/usr/bin/env python3
"""Shared Community Dock rules for validation, import and catalog generation.

A dock lives in Docks/<pack-id>/ as pack.json plus at most one background image
named <assetKey>.jpg or <assetKey>.heic. pack.json carries no inline `data` and
no `url`; the catalog generator adds urls. The caps mirror the app's decoder
(docs/community-docks.md in the DockDoor Pro repo).
"""
import hashlib
import json
import re
import struct
from pathlib import Path

PACK_FILE = "pack.json"
FORMAT_VERSION = 2
ORIGINALS_PREFIX = "originals."
ID_PATTERN = re.compile(r"^(originals\.[a-z0-9]+(?:-[a-z0-9]+)*|community\.(?:[a-z0-9]{12}|[a-z0-9]+(?:-[a-z0-9]+)*))$")
ASSET_KEY = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
IGNORED_ENTRIES = {".DS_Store"}

MAX_NAME = 40
MAX_TAGLINE = 80
MAX_TAGS = 5
MAX_TAG_LENGTH = 24
MAX_LAYOUT = 64
MAX_STACKS = 12
MAX_WIDGETS_PER_STACK = 8
MAX_PACK_BYTES = 64 * 1024
MAX_IMAGE_BYTES = 400 * 1024
MAX_IMAGE_SIDE = 2560
USER_CONTENT_KINDS = {"app", "folder", "file", "url", "appGroup"}

# declared type -> (file extension, magic check)
ASSET_TYPES = {"public.jpeg": "jpg", "public.heic": "heic"}
HEIC_BRANDS = {b"heic", b"heix", b"hevc", b"hevx", b"heim", b"heis", b"mif1", b"msf1"}


class DockRuleError(Exception):
    """One or more rule violations for a dock folder."""

    def __init__(self, problems):
        super().__init__("; ".join(problems))
        self.problems = problems


def is_official_id(pack_id: str) -> bool:
    return pack_id.startswith(ORIGINALS_PREFIX)


def jpeg_size(data: bytes):
    """(width, height) from the first SOF marker, or None when not parseable."""
    if data[:2] != b"\xff\xd8":
        return None
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            return None
        marker = data[i + 1]
        if marker == 0xFF:
            i += 1
            continue
        if marker in (0x01, *range(0xD0, 0xD9)):
            i += 2
            continue
        length = struct.unpack(">H", data[i + 2:i + 4])[0]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            if i + 9 > len(data):
                return None
            height, width = struct.unpack(">HH", data[i + 5:i + 9])
            return width, height
        i += 2 + length
    return None


def heic_size(data: bytes):
    """(width, height) from the first ispe box, or None when absent."""
    at = data.find(b"ispe")
    if at < 0 or at + 16 > len(data):
        return None
    width, height = struct.unpack(">II", data[at + 8:at + 16])
    return width, height


def magic_matches(asset_type: str, data: bytes) -> bool:
    if asset_type == "public.jpeg":
        return data[:3] == b"\xff\xd8\xff"
    if asset_type == "public.heic":
        return data[4:8] == b"ftyp" and data[8:12] in HEIC_BRANDS
    return False


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def load_pack(folder: Path) -> dict:
    """Parses pack.json, requiring a regular file under the size cap and a JSON object."""
    pack_json = folder / PACK_FILE
    if pack_json.is_symlink() or not pack_json.is_file():
        raise DockRuleError([f"{PACK_FILE} is missing or not a regular file"])
    if pack_json.stat().st_size > MAX_PACK_BYTES:
        raise DockRuleError([f"{PACK_FILE} is larger than {MAX_PACK_BYTES // 1024} KB"])
    try:
        pack = json.loads(pack_json.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise DockRuleError([f"{PACK_FILE} is not valid JSON: {error}"])
    if not isinstance(pack, dict):
        raise DockRuleError([f"{PACK_FILE} must be a JSON object"])
    return pack


def check_metadata(folder: Path, pack: dict) -> list[str]:
    problems = []
    if pack.get("format") != FORMAT_VERSION or not _is_int(pack.get("format")):
        problems.append(f"'format' must be {FORMAT_VERSION}")
    pack_id = pack.get("id")
    if not isinstance(pack_id, str) or not ID_PATTERN.match(pack_id):
        problems.append("'id' must be originals.<slug> or community.<slug> (lowercase letters, digits, hyphens)")
    elif pack_id != folder.name:
        problems.append(f"folder name '{folder.name}' must equal the pack id '{pack_id}'")
    name = pack.get("name")
    if not isinstance(name, str) or not 1 <= len(name) <= MAX_NAME or not name.strip():
        problems.append(f"'name' must be 1 to {MAX_NAME} characters")
    tagline = pack.get("tagline", "")
    if not isinstance(tagline, str) or len(tagline) > MAX_TAGLINE:
        problems.append(f"'tagline' must be a string of at most {MAX_TAGLINE} characters")
    tags = pack.get("tags", [])
    if not isinstance(tags, list) or len(tags) > MAX_TAGS:
        problems.append(f"'tags' must be a list of at most {MAX_TAGS}")
    elif any(not isinstance(tag, str) or not 1 <= len(tag) <= MAX_TAG_LENGTH for tag in tags):
        problems.append(f"each tag must be 1 to {MAX_TAG_LENGTH} characters")
    author = pack.get("author")
    if not isinstance(author, dict) or not isinstance(author.get("name"), str):
        problems.append("'author' must be an object with a 'name'")
    elif author.get("isOfficial") is True:
        problems.append("'author.isOfficial' must not be true; officialness comes only from the originals. id prefix")
    if "createdAt" in pack and not isinstance(pack["createdAt"], str):
        problems.append("'createdAt' must be an ISO 8601 string")
    return problems


def check_structure(pack: dict) -> list[str]:
    problems = []
    layout = pack.get("layout", [])
    if not isinstance(layout, list):
        problems.append("'layout' must be a list")
    else:
        if len(layout) > MAX_LAYOUT:
            problems.append(f"'layout' has {len(layout)} entries; the limit is {MAX_LAYOUT}")
        for entry in layout:
            if not isinstance(entry, dict):
                problems.append("every 'layout' entry must be an object")
                break
            if entry.get("kind") in USER_CONTENT_KINDS:
                problems.append(f"layout kind '{entry['kind']}' is user content and cannot be shared")
    stacks = pack.get("stacks", [])
    if not isinstance(stacks, list):
        problems.append("'stacks' must be a list")
    else:
        if len(stacks) > MAX_STACKS:
            problems.append(f"'stacks' has {len(stacks)} entries; the limit is {MAX_STACKS}")
        for stack in stacks:
            if not isinstance(stack, dict):
                problems.append("every stack must be an object")
                break
            for field in ("widgetIds", "widgetInstances"):
                items = stack.get(field, [])
                if isinstance(items, list) and len(items) > MAX_WIDGETS_PER_STACK:
                    problems.append(f"stack '{stack.get('id')}' has {len(items)} widgets; the limit is {MAX_WIDGETS_PER_STACK}")
    for field in ("look", "fallbacks", "requires", "preview"):
        if field in pack and not isinstance(pack[field], dict):
            problems.append(f"'{field}' must be an object")
    return problems


def check_assets(folder: Path, pack: dict) -> list[str]:
    """Asset declaration, background reference and the image file itself."""
    problems = []
    assets = pack.get("assets", {})
    background = pack.get("background")
    if not isinstance(assets, dict):
        return ["'assets' must be an object"]
    if background is not None and not isinstance(background, dict):
        return ["'background' must be an object"]
    referenced = background.get("asset") if background else None
    if len(assets) > 1:
        problems.append("a dock may carry at most one asset")
    if background and referenced not in assets:
        problems.append(f"background references asset '{referenced}' which is not declared")
    for key in assets:
        if key != referenced:
            problems.append(f"asset '{key}' is not referenced by background.asset")
    for key, asset in assets.items():
        if not ASSET_KEY.match(key):
            problems.append(f"asset key '{key}' must be 1 to 32 letters, digits, hyphens or underscores")
            continue
        if not isinstance(asset, dict):
            problems.append(f"asset '{key}' must be an object")
            continue
        if "data" in asset or "url" in asset:
            problems.append(f"asset '{key}' must not carry 'data' or 'url' (the file lives beside pack.json)")
        asset_type = asset.get("type")
        extension = ASSET_TYPES.get(asset_type)
        if extension is None:
            problems.append(f"asset '{key}' type must be one of: {', '.join(sorted(ASSET_TYPES))}")
            continue
        path = folder / f"{key}.{extension}"
        if path.is_symlink() or not path.is_file():
            problems.append(f"asset file {path.name} is missing")
            continue
        data = path.read_bytes()
        if not magic_matches(asset_type, data):
            problems.append(f"{path.name} is not a valid {asset_type} file (magic bytes)")
            continue
        if len(data) > MAX_IMAGE_BYTES:
            problems.append(f"{path.name} is {len(data) // 1024} KB; the limit is {MAX_IMAGE_BYTES // 1024} KB")
        if asset.get("bytes") != len(data) or not _is_int(asset.get("bytes")):
            problems.append(f"asset '{key}' bytes {asset.get('bytes')!r} does not match the file ({len(data)})")
        digest = hashlib.sha256(data).hexdigest()
        if not isinstance(asset.get("sha256"), str) or not SHA256.match(asset["sha256"]) or asset["sha256"] != digest:
            problems.append(f"asset '{key}' sha256 does not match {path.name}")
        actual = jpeg_size(data) if asset_type == "public.jpeg" else heic_size(data)
        if asset_type == "public.jpeg" and actual is None:
            problems.append(f"{path.name} has no readable JPEG dimensions")
            continue
        width, height = asset.get("width"), asset.get("height")
        if not _is_int(width) or not _is_int(height) or width < 1 or height < 1:
            problems.append(f"asset '{key}' needs integer width and height")
            continue
        if actual is not None and (actual[0], actual[1]) != (width, height):
            problems.append(f"asset '{key}' declares {width}x{height} but the image is {actual[0]}x{actual[1]}")
        if max(actual or (width, height)) > MAX_IMAGE_SIDE:
            problems.append(f"{path.name} longest side exceeds {MAX_IMAGE_SIDE} px")
    return problems


def check_folder_contents(folder: Path, pack: dict) -> list[str]:
    """Only pack.json and the file of the referenced asset may live in a dock folder."""
    allowed = {PACK_FILE}
    assets = pack.get("assets", {})
    if isinstance(assets, dict) and len(assets) <= 1:
        for key, asset in assets.items():
            extension = ASSET_TYPES.get(asset.get("type")) if isinstance(asset, dict) else None
            if extension and ASSET_KEY.match(key):
                allowed.add(f"{key}.{extension}")
    problems = []
    for entry in sorted(folder.iterdir()):
        if entry.name in IGNORED_ENTRIES:
            continue
        if entry.is_symlink():
            problems.append(f"{entry.name} is a symlink")
        elif entry.is_dir():
            problems.append(f"{entry.name}/ is a folder; docks may not contain folders")
        elif entry.name not in allowed:
            problems.append(f"{entry.name} is not allowed (only {PACK_FILE} and the referenced background image)")
    return problems


def validate(folder: Path) -> dict:
    """Validates a dock folder and returns its parsed pack.json, or raises DockRuleError."""
    pack = load_pack(folder)
    problems = check_metadata(folder, pack) + check_structure(pack) + check_assets(folder, pack) + check_folder_contents(folder, pack)
    if problems:
        raise DockRuleError(problems)
    return pack


def asset_path(folder: Path, key: str, asset: dict) -> Path:
    return folder / f"{key}.{ASSET_TYPES[asset['type']]}"
