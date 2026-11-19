"""Render the real Shared camps window (CampMap.lua) from the test harness into an SVG/HTML preview.

The harness has no layout engine, so this records anchors, colours, alpha and fonts while the Lua builds the window,
then resolves the anchors itself. Classic textures are emulated (stone, gold border, red panel buttons, map art grey).
  /tmp/qs-test-env/bin/python tools/preview_camp_window.py OUTPUT.html [objective-name-to-highlight]
"""
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from test_camp_map import game  # noqa: E402

RECORD = r'''
local function patch(o)
  if o.__patched then return o end
  o.__patched = true
  o.pts = {}
  local sp = o.SetPoint
  function o:SetPoint(p, rel, rp, x, y)
    if type(rel) == "number" then rel, rp, x, y = nil, p, rel, rp end
    self.pts[#self.pts + 1] = { p, rel, rp or p, x or 0, y or 0 }; sp(self, p, rel, rp, x, y)
  end
  function o:ClearAllPoints() self.pts = {}; self.all = nil end
  function o:SetAllPoints(rel) self.all = rel or self.parent end
  function o:SetColorTexture(r, g, b, a) self.rgba = { r, g, b, a or 1 } end
  function o:SetAlpha(a) self.alpha = a end
  function o:SetFontObject(f) self.fontObj = f end
  function o:SetJustifyH(j) self.justify = j end
  local cf, ct, cl = o.CreateFontString, o.CreateTexture, o.CreateLine
  function o:CreateFontString(n, layer, font) local c = patch(cf(self, n, layer, font)); c.fontObj = font; return c end
  function o:CreateTexture(n, layer) local c = patch(ct(self, n, layer)); c.layer = layer; return c end
  if cl then function o:CreateLine(n, layer) local c = patch(cl(self, n, layer)); c.layer = layer; return c end end
  return o
end
local realCreate = CreateFrame
function CreateFrame(kind, name, parent, template) return patch(realCreate(kind, name, parent, template)) end
'''

FONT = {"GameFontNormal": (13, "#ffd100"), "GameFontNormalSmall": (11, "#ffd100"), "GameFontHighlightSmall": (11, "#ffffff"),
        "GameFontDisableSmall": (10, "#9d9d9d"), "GameFontHighlight": (13, "#ffffff")}


def colour_codes(text):
    """WoW |cffRRGGBB ... |r runs -> [(colour or None, text)]."""
    out, cur, pos = [], None, 0
    for m in re.finditer(r"\|c[fF]{2}([0-9a-fA-F]{6})|\|r", text):
        if m.start() > pos:
            out.append((cur, text[pos:m.start()]))
        cur = ("#" + m.group(1)) if m.group(1) else None
        pos = m.end()
    if pos < len(text):
        out.append((cur, text[pos:]))
    return out


class Layout:
    def __init__(self, g):
        self.g = g
        self.cache = {}

    def size(self, o):
        if o.isFontString and not o.width:
            fs = FONT.get(o.fontObj or "GameFontHighlightSmall", (11, "#fff"))[0]
            plain = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(o.text or ""))
            return len(plain) * fs * 0.52, fs + 2
        return (o.width or 0), (o.height or 0)

    def rect(self, o):
        """(left, top, width, height) in screen px, y down."""
        key = self.g.eval("tostring")(o)
        if key in self.cache:
            return self.cache[key]
        if o.parent is None:                      # UIParent (or a frame without parent): the whole screen
            r = (0, 0, 1920, 1080)
            self.cache[key] = r
            return r
        parent = o.parent
        if o.all:
            r = self.rect(o.all)
            self.cache[key] = r
            return r
        pts = list(o.pts.values()) if o.pts else []
        w, h = self.size(o)
        if not pts:
            pr = self.rect(parent)
            r = (pr[0] + (pr[2] - w) / 2, pr[1] + (pr[3] - h) / 2, w, h)
            self.cache[key] = r
            return r

        def anchor(rr, name):
            x = rr[0] + (0 if "LEFT" in name else rr[2] if "RIGHT" in name else rr[2] / 2)
            y = rr[1] + (0 if "TOP" in name else rr[3] if "BOTTOM" in name else rr[3] / 2)
            return x, y
        placed = []
        for p in pts:
            rel = p[2] if p[2] else parent
            ax, ay = anchor(self.rect(rel), p[3])
            placed.append((p[1], ax + p[4], ay - p[5]))
        if len(placed) >= 2 and placed[0][0] == "TOPLEFT" and placed[-1][0] == "BOTTOMRIGHT":
            (_, x1, y1), (_, x2, y2) = placed[0], placed[-1]
            r = (x1, y1, x2 - x1, y2 - y1)
        elif len(placed) >= 2 and placed[0][0] == "BOTTOMLEFT" and placed[-1][0] == "BOTTOMRIGHT":
            (_, x1, y1), (_, x2, _) = placed[0], placed[-1]
            r = (x1, y1 - h, x2 - x1, h)
        else:
            name, x, y = placed[-1]
            left = x - (0 if "LEFT" in name else w if "RIGHT" in name else w / 2)
            top = y - (0 if "TOP" in name else h if "BOTTOM" in name else h / 2)
            r = (left, top, w, h)
        self.cache[key] = r
        return r


def visible(o):
    while o is not None:
        if not o.shown:
            return False
        o = o.parent
    return True


def render(g, win):
    L = Layout(g)
    wx, wy, ww, wh = L.rect(win)
    out = []
    LAYER = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 9}

    def walk(o, depth):
        kids = list(o.children.values()) if o.children else []
        regions = [k for k in kids if k.isTexture or k.isFontString or k.isLine]
        frames = [k for k in kids if not (k.isTexture or k.isFontString or k.isLine)]
        regions.sort(key=lambda k: (0 if not k.isFontString else 1, LAYER.get(k.layer or "ARTWORK", 2)))
        for r in regions:
            if not visible(r) or (r.layer == "HIGHLIGHT"):
                continue
            draw(r)
        for f in frames:
            if visible(f):
                walk(f, depth + 1)

    def alpha_of(o):
        a = 1.0
        while o is not None:
            a *= o.alpha if o.alpha is not None else 1.0
            o = o.parent
        return a

    def draw(r):
        if r.isLine:
            if not (r.startPoint and r.endPoint):
                return
            sp, ep = r.startPoint, r.endPoint
            base = L.rect(sp[2])
            x1, y1 = base[0] + sp[3], base[1] - sp[4]
            x2, y2 = base[0] + ep[3], base[1] - ep[4]
            c = r.rgba or {1: 1, 2: 1, 3: 1, 4: 1}
            out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="rgb(%d,%d,%d)" stroke-opacity="%.2f" stroke-width="%.1f" stroke-linecap="round"/>'
                       % (x1, y1, x2, y2, c[1] * 255, c[2] * 255, c[3] * 255, c[4] * alpha_of(r), r.thickness or 1))
            return
        x, y, w, h = L.rect(r)
        if r.isFontString:
            text = str(r.text or "")
            if not text:
                return
            size, colour = FONT.get(r.fontObj or "GameFontHighlightSmall", (11, "#ffffff"))
            tw = len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * 0.52
            anchor = "start" if (r.width and (r.justify or "LEFT") == "LEFT") else "middle"
            tx = x if anchor == "start" else x + w / 2
            if r.width and anchor == "middle":
                tx = x + w / 2
            if not r.width:
                tx, anchor = x, "start"
            boxw = w if (r.width or r.all) else 0
            if boxw:
                anchor = "start" if r.justify == "LEFT" else "middle"
                tx = x if anchor == "start" else x + w / 2
            plain = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)
            per = max(1, int(boxw / (size * 0.52))) if boxw else 10 ** 6
            words, lines_, cur = plain.split(" "), [], ""
            for wd in words:
                if cur and len(cur) + 1 + len(wd) > per:
                    lines_.append(cur); cur = wd
                else:
                    cur = (cur + " " + wd) if cur else wd
            lines_.append(cur)
            if len(lines_) == 1:
                spans = "".join('<tspan fill="%s">%s</tspan>' % (c or colour, html.escape(t)) for c, t in colour_codes(text))
                ty = y + h / 2 + size * 0.36
                out.append('<text x="%.1f" y="%.1f" font-size="%d" text-anchor="%s" fill-opacity="%.2f" class="t">%s</text>'
                           % (tx, ty, size, anchor, alpha_of(r), spans))
            else:                                   # wrapped, bottom-aligned like the matrix headers
                top = y + h - len(lines_) * (size + 1)
                for i, ln in enumerate(lines_):
                    out.append('<text x="%.1f" y="%.1f" font-size="%d" text-anchor="%s" fill="%s" class="t">%s</text>'
                               % (tx, top + (i + 1) * (size + 1) - 2, size, anchor, colour, html.escape(ln)))
            return
        if w <= 0 or h <= 0:
            return
        tex = r.texture or ""
        a = alpha_of(r)
        if "TempPortraitAlphaMask" in tex:
            c = r.vertex or {1: 1, 2: 1, 3: 1, 4: 1}
            out.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="rgb(%d,%d,%d)" fill-opacity="%.2f"/>'
                       % (x + w / 2, y + h / 2, w / 2, h / 2, c[1] * 255, c[2] * 255, c[3] * 255, (c[4] if c[4] is not None else 1) * a))
            if c[4] is not None and c[4] < 0.5 and w > 20:
                out.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="none" stroke="rgb(%d,%d,%d)" stroke-opacity="%.2f" stroke-width="1"/>'
                           % (x + w / 2, y + h / 2, w / 2, h / 2, c[1] * 255, c[2] * 255, c[3] * 255, min(1, c[4] * 2.5) * a))
        elif "UI-DialogBox-Background" in tex:
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="url(#stone)" fill-opacity="%.2f"/>' % (x, y, w, h, a))
        elif "UI-Panel-Button" in tex:
            if "Up" in tex:
                out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="3" fill="url(#btn)" stroke="#2a0600" fill-opacity="%.2f"/>' % (x, y, w, h, a))
        elif "UI-DialogBox-Header" in tex:
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="6" fill="url(#plate)" stroke="#8a6a1a"/>' % (x + 40, y + 12, w - 80, 26))
        elif r.rgba:
            c = r.rgba
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="rgb(%d,%d,%d)" fill-opacity="%.2f"/>'
                       % (x, y, w, h, c[1] * 255, c[2] * 255, c[3] * 255, (c[4] if c[4] is not None else 1) * a))
        elif tex.startswith("Interface\\WorldMap") or isinstance(r.texture, (int, float)):
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#3d3a2c" stroke="#4a4636" stroke-width="0.5"/>' % (x, y, w, h))

    # window chrome: stone + gold dialog border
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="10" fill="#0e0d0b"/>' % (wx, wy, ww, wh))
    walk(win, 0)
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="10" fill="none" stroke="#c9a43a" stroke-width="5"/>' % (wx + 4, wy + 4, ww - 8, wh - 8))
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="8" fill="none" stroke="#5a4510" stroke-width="2"/>' % (wx + 8, wy + 8, ww - 16, wh - 16))
    # inset rims around the two panels
    for p in (win.net, win.map):
        if p is None:
            continue
        x, y, w, h = L.rect(p)
        out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#8c6d2c" stroke-width="1.5"/>' % (x, y, w, h))
    return wx, wy, ww, wh, "\n".join(out)


def main():
    if len(sys.argv) < 2:
        raise SystemExit("Usage: preview_camp_window.py OUTPUT.html [objective name]")
    g = game("modern")
    g.run(RECORD)
    g.eval("NS.campMap.openTable")()
    win = g.eval("NS.campMap._table()")
    if len(sys.argv) > 2:
        cols = list(g.eval("NS.questPlanner.campView()").columns.values())
        idx = next(i + 1 for i, c in enumerate(cols) if c.name == sys.argv[2])
        g.eval("NS.campMap._focus")(idx)
    # the map art: two fake tiles so the panel shows the zone art area (the real client draws Blizzard's map art)
    x, y, w, h, body = render(g, win)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%d %d %d %d" width="%d" height="%d">' % (x - 6, y - 26, w + 12, h + 32, w + 12, h + 32)
           + '''<defs>
<pattern id="stone" width="64" height="64" patternUnits="userSpaceOnUse"><rect width="64" height="64" fill="#1b1916"/>
<path d="M0 20 L64 24 M0 44 L64 40 M22 0 L18 64 M46 0 L50 64" stroke="#24211c" stroke-width="3"/></pattern>
<linearGradient id="btn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a3140f"/><stop offset="1" stop-color="#5a0806"/></linearGradient>
<linearGradient id="plate" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b2d10"/><stop offset="1" stop-color="#1c1407"/></linearGradient>
</defs><style>.t{font-family:"Friz Quadrata TT","Palatino Linotype",Georgia,serif;paint-order:stroke;stroke:#000;stroke-width:2px}</style>'''
           + body + "</svg>")
    out = pathlib.Path(sys.argv[1]).resolve()
    out.write_text("<!doctype html><meta charset=utf-8><title>Shared camps - preview</title>"
                   "<body style='margin:0;background:#2b2b2b'>" + svg + "</body>")
    print("wrote", out)


if __name__ == "__main__":
    main()
