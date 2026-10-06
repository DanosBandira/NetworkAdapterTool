"""Render an SVG to PNGs at several sizes with headless Edge, then pack them
into a Windows .ico (PNG-compressed entries). Standard library only.

Usage (regenerates the app icon from icon.svg):
    python tool/svg_to_ico.py icon.svg windows/runner/resources/app_icon.ico <work dir>

The work dir receives the intermediate PNGs (icon_<size>.png) for review.
"""
import base64
import json
import pathlib
import re
import struct
import subprocess
import sys

svg_path = pathlib.Path(sys.argv[1]).resolve()
ico_path = pathlib.Path(sys.argv[2]).resolve()
# Absolute because Edge needs a file:// URI for the render page.
preview_dir = pathlib.Path(sys.argv[3]).resolve()
preview_dir.mkdir(parents=True, exist_ok=True)
sizes = [16, 24, 32, 48, 64, 128, 256]
edge = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

svg_data_url = "data:image/svg+xml;base64," + base64.b64encode(svg_path.read_bytes()).decode()
html = f"""<!doctype html><html><body><script>
const sizes = {json.dumps(sizes)};
const image = new Image();
image.onload = () => {{
  const result = {{}};
  for (const size of sizes) {{
    const canvas = document.createElement('canvas');
    canvas.width = size; canvas.height = size;
    const context = canvas.getContext('2d');
    context.imageSmoothingQuality = 'high';
    context.drawImage(image, 0, 0, size, size);
    result[size] = canvas.toDataURL('image/png');
  }}
  document.body.setAttribute('data-icons', JSON.stringify(result));
}};
image.onerror = () => document.body.setAttribute('data-icons', 'ERROR');
image.src = {json.dumps(svg_data_url)};
</script></body></html>"""
html_path = preview_dir / "render_icon.html"
html_path.write_text(html, encoding="utf-8")

dom = subprocess.run(
    [edge, "--headless=new", "--disable-gpu", "--virtual-time-budget=5000",
     f"--user-data-dir={preview_dir / 'edge-profile'}", "--dump-dom", html_path.as_uri()],
    capture_output=True, text=True, timeout=120,
).stdout
match = re.search(r"data-icons=\"([^\"]+)\"", dom)
if not match or match.group(1) == "ERROR":
    sys.exit("rendering failed:\n" + dom[:500])
icons = json.loads(match.group(1).replace("&quot;", '"'))

pngs = []
for size in sizes:
    png = base64.b64decode(icons[str(size)].split(",", 1)[1])
    (preview_dir / f"icon_{size}.png").write_bytes(png)
    pngs.append((size, png))

# ICONDIR + one ICONDIRENTRY per image; width/height 0 means 256.
header = struct.pack("<HHH", 0, 1, len(pngs))
offset = len(header) + 16 * len(pngs)
entries, payload = b"", b""
for size, png in pngs:
    dimension = 0 if size == 256 else size
    entries += struct.pack("<BBBBHHII", dimension, dimension, 0, 0, 1, 32, len(png), offset + len(payload))
    payload += png
ico_path.write_bytes(header + entries + payload)
print(f"wrote {ico_path} with sizes {sizes} ({ico_path.stat().st_size} bytes)")
