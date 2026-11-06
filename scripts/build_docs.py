#!/usr/bin/env python3
"""
產生 docs/architecture/index.html：頁面說明、頁面地圖、架構圖、資料結構圖、循序圖。

自動產生（讀程式碼，不用維護）：
  - 頁面地圖：哪個畫面會打開哪個畫面（畫面 = View/<頁>/ 底下檔名以 View 結尾的檔案）
  - 分層架構總覽、各頁依賴圖：依檔案之間引用到的型別名稱
  - 資料結構圖：讀 CoreData model
手動維護（腳本檢查有沒有漏）：
  - docs/architecture/pages.md：每個畫面一段說明，標題格式 `## 型別名｜中文名`
  - docs/architecture/sequences/*.md：循序圖，第一行 `# 標題`，內含 ```mermaid 區塊

用法：
  python3 scripts/build_docs.py           產生 HTML
  python3 scripts/build_docs.py --check   只檢查：缺說明、說明多出不存在的畫面、
                                          循序圖引用不存在的型別、HTML 不是最新 → 回傳 1
"""
import html
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Tilli"
MODEL = SRC / "Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents"
DOCS = ROOT / "docs/architecture"
PAGES_MD = DOCS / "pages.md"
SEQ_DIR = DOCS / "sequences"
OUT = DOCS / "index.html"
MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"

EXCLUDED_DIRS = {"_Deprecated", "Preview Content"}

# 頁面資料夾的中文名（RootTabView 底下的分頁）
PAGE_FOLDER_TITLES = {
    "Root": "根畫面",
    "EventsPage": "場次",
    "POSPage": "收銀",
    "InventoryPage": "管理商品",
    "ReportsPage": "報表",
    "MyPage": "我的",
}

# 架構圖只畫這幾層（Model、Utilities、Extensions 人人都用，畫進去只會是雜訊）
DIAGRAM_LAYERS = ["View", "ViewModel", "Service", "Data", "External"]

# 循序圖裡以這些字尾結尾的參與者，必須是程式碼裡存在的型別
CHECKED_SUFFIXES = (
    "View", "ViewModel", "Repository", "Recorder", "Index", "Store", "Service",
    "Calculator", "Allocator", "Exporter", "DataSource", "Manager", "Pricing",
    "Applier", "Validator", "Availability", "Breakdown",
)

TYPE_DECL = re.compile(
    r"^\s*(?:@\w+\s+)*(?:(?:public|private|fileprivate|internal|final|open|indirect)\s+)*"
    r"(?:class|struct|enum|actor|protocol)\s+([A-Z]\w*)",
    re.M,
)
IMPORT = re.compile(r"^import\s+(\w+)", re.M)
EXTERNAL_PREFIXES = ("Firebase", "GoogleSignIn", "Kingfisher", "Alamofire")


# ---------------------------------------------------------------------------
# 讀程式碼
# ---------------------------------------------------------------------------

class SwiftFile:
    def __init__(self, path: Path):
        self.path = path
        self.rel = path.relative_to(SRC)
        self.stem = path.stem
        raw = path.read_text(encoding="utf-8")
        self.types = set(TYPE_DECL.findall(raw))
        self.imports = set(IMPORT.findall(raw))
        self.tokens = set(re.findall(r"\b[A-Z]\w*\b", strip_comments_and_strings(raw)))
        parts = self.rel.parts
        self.layer = parts[0] if len(parts) > 1 else "App"
        self.group = "/".join(parts[:2]) if len(parts) > 2 else self.layer

    @property
    def page_folder(self):
        parts = self.rel.parts
        if parts[0] in ("View", "ViewModel") and len(parts) > 2:
            return parts[1]
        return None

    @property
    def is_screen(self):
        return (self.layer == "View" and self.page_folder not in (None, "Components")
                and self.stem.endswith("View"))


def strip_comments_and_strings(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    text = re.sub(r'"""(.*?)"""', '""', text, flags=re.S)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    return text


def load_files():
    files = []
    for p in sorted(SRC.rglob("*.swift")):
        if any(part in EXCLUDED_DIRS for part in p.relative_to(SRC).parts):
            continue
        files.append(SwiftFile(p))
    return files


def build_graph(files):
    """回傳 (type → 宣告檔案, 檔案 → 引用到的檔案集合, 檔案 → 外部套件集合)"""
    owner = {}
    for f in files:
        for t in f.types:
            owner.setdefault(t, f)
    refs = defaultdict(set)
    for f in files:
        for tok in f.tokens:
            g = owner.get(tok)
            if g is not None and g is not f:
                refs[f].add(g)
    externals = {f: {m for m in f.imports if m.startswith(EXTERNAL_PREFIXES)} for f in files}
    return owner, refs, externals


def diagram_layer(f: SwiftFile):
    return f.layer if f.layer in DIAGRAM_LAYERS else None


# ---------------------------------------------------------------------------
# Mermaid 產生
# ---------------------------------------------------------------------------

def node_id(name: str) -> str:
    return re.sub(r"\W", "_", name)


def external_group(module: str) -> str:
    for p in EXTERNAL_PREFIXES:
        if module.startswith(p):
            return p
    return module


LAYER_TITLES = {
    "View": "畫面 View",
    "ViewModel": "ViewModel",
    "Service": "共用計算 Service",
    "Data": "資料層 Data",
    "External": "外部套件",
}


def overview_mermaid(files, refs, externals):
    """分層總覽：節點是資料夾，邊是資料夾之間有引用"""
    groups = defaultdict(set)
    for f in files:
        if diagram_layer(f):
            groups[f.layer].add(f.group)
    edges = set()
    ext_used = set()
    for f in files:
        if not diagram_layer(f) or f.group == "View/Components":
            continue
        for g in refs[f]:
            if diagram_layer(g) and g.group != f.group and g.group != "View/Components":
                if layer_rank(g.layer) >= layer_rank(f.layer):
                    edges.add((f.group, g.group))
        for m in externals[f]:
            e = "External/" + external_group(m)
            ext_used.add(e)
            edges.add((f.group, e))
    groups["External"] = ext_used
    lines = ["flowchart LR"]
    for layer in DIAGRAM_LAYERS:
        members = sorted(g for g in groups.get(layer, ()) if g != "View/Components")
        if not members:
            continue
        lines.append(f'  subgraph {node_id("L_" + layer)}["{LAYER_TITLES[layer]}"]')
        lines.append("    direction TB")
        for g in members:
            label = group_label(g)
            cls = ":::ext" if layer == "External" else ""
            lines.append(f'    {node_id(g)}["{label}"]{cls}')
        lines.append("  end")
    for a, b in sorted(edges):
        lines.append(f"  {node_id(a)} --> {node_id(b)}")
    lines.append("  classDef ext stroke-dasharray: 4 3")
    return "\n".join(lines)


def layer_rank(layer):
    return DIAGRAM_LAYERS.index(layer) if layer in DIAGRAM_LAYERS else 99


def group_label(group: str) -> str:
    parts = group.split("/")
    if len(parts) == 2 and parts[0] in ("View", "ViewModel"):
        title = PAGE_FOLDER_TITLES.get(parts[1])
        return f"{parts[1]}<br/>{title}" if title else parts[1]
    return parts[-1]


def page_dependency_mermaid(folder, files, refs, externals):
    """單一頁面資料夾：畫面 → ViewModel → Service → Data → 外部套件（只畫有用到的）"""
    roots = [f for f in files if f.page_folder == folder and f.layer in ("View", "ViewModel")]
    included = set(roots)
    stack = list(roots)
    while stack:
        f = stack.pop()
        for g in refs[f]:
            if g in included:
                continue
            if f in roots and g.page_folder == folder:
                included.add(g)
                stack.append(g)
            elif g.layer in ("Service", "Data") or (g.layer == "ViewModel" and f.layer == "View"):
                included.add(g)
                stack.append(g)
    by_layer = defaultdict(list)
    for f in included:
        by_layer[f.layer].append(f)
    ext = defaultdict(set)
    for f in included:
        for m in externals[f]:
            ext[f].add(external_group(m))
    lines = ["flowchart LR"]
    for layer in ("View", "ViewModel", "Service", "Data"):
        members = sorted(by_layer.get(layer, []), key=lambda x: x.stem)
        if not members:
            continue
        lines.append(f'  subgraph {node_id("L_" + layer)}["{LAYER_TITLES[layer]}"]')
        lines.append("    direction TB")
        for f in members:
            lines.append(f'    {node_id(f.stem)}["{f.stem}"]')
        lines.append("  end")
    ext_names = sorted({m for ms in ext.values() for m in ms})
    if ext_names:
        lines.append(f'  subgraph L_External["{LAYER_TITLES["External"]}"]')
        lines.append("    direction TB")
        for m in ext_names:
            lines.append(f'    X_{node_id(m)}["{m}"]:::ext')
        lines.append("  end")
    for f in sorted(included, key=lambda x: x.stem):
        for g in sorted(refs[f] & included, key=lambda x: x.stem):
            if layer_rank(g.layer) >= layer_rank(f.layer) and not (
                f.layer == g.layer == "View" and g.page_folder != folder
            ):
                lines.append(f"  {node_id(f.stem)} --> {node_id(g.stem)}")
        for m in sorted(ext[f]):
            lines.append(f"  {node_id(f.stem)} -.-> X_{node_id(m)}")
    lines.append("  classDef ext stroke-dasharray: 4 3")
    return "\n".join(lines)


def screen_links(files, refs):
    """畫面 → 它會打開（引用到）的其他畫面"""
    # 只認畫面本身的型別名（= 檔名），同檔案裡宣告的小元件不算「打開這個畫面」
    screens = [f for f in files if f.is_screen]
    out = {s: sorted((t for t in screens if t is not s and t.stem in s.tokens), key=lambda x: x.stem)
           for s in screens}
    incoming = defaultdict(list)
    for s, targets in out.items():
        for t in targets:
            incoming[t].append(s)
    return screens, out, incoming


def navigation_mermaid(screens, out, titles):
    lines = ["flowchart LR"]
    by_folder = defaultdict(list)
    for s in screens:
        by_folder[s.page_folder].append(s)
    for folder in sorted(by_folder, key=folder_order):
        lines.append(f'  subgraph F_{node_id(folder)}["{PAGE_FOLDER_TITLES.get(folder, folder)}"]')
        for s in sorted(by_folder[folder], key=lambda x: x.stem):
            title = titles.get(s.stem, "")
            label = f"{title}<br/><small>{s.stem}</small>" if title else s.stem
            lines.append(f'    {node_id(s.stem)}["{label}"]')
        lines.append("  end")
    for s in sorted(out, key=lambda x: x.stem):
        for t in out[s]:
            lines.append(f"  {node_id(s.stem)} --> {node_id(t.stem)}")
    return "\n".join(lines)


def folder_order(folder):
    keys = list(PAGE_FOLDER_TITLES)
    return keys.index(folder) if folder in keys else len(keys)


MERMAID_TYPES = {
    "Integer 16": "Int16", "Integer 32": "Int32", "Integer 64": "Int64",
    "Boolean": "Bool", "Binary": "Binary", "Transformable": "Transformable",
}


def er_mermaid():
    root = ET.parse(MODEL).getroot()
    lines = ["erDiagram"]
    seen = set()
    entities = root.findall("entity")
    for e in entities:
        name = e.get("name")
        for r in e.findall("relationship"):
            dest = r.get("destinationEntity")
            inverse = r.get("inverseName")
            key = tuple(sorted([(name, r.get("name")), (dest, inverse or "")]))
            if key in seen:
                continue
            seen.add(key)
            inv = None
            if inverse:
                inv = next((x for x in root.find(f"entity[@name='{dest}']").findall("relationship")
                            if x.get("name") == inverse), None)
            left = cardinality(inv, left=True) if inv is not None else "||"
            right = cardinality(r, left=False)
            label = f'{r.get("name")} ({r.get("deletionRule")})'
            lines.append(f'  {name} {left}--{right} {dest} : "{label}"')
    for e in entities:
        lines.append(f"  {e.get('name')} {{")
        for a in e.findall("attribute"):
            t = a.get("attributeType")
            t = MERMAID_TYPES.get(t, t).replace(" ", "")
            note = ' "optional"' if a.get("optional") == "YES" else ""
            lines.append(f"    {t} {a.get('name')}{note}")
        lines.append("  }")
    return "\n".join(lines)


def cardinality(rel, left):
    many = rel.get("toMany") == "YES"
    optional = rel.get("optional") == "YES"
    if many:
        return "}o" if left else "o{"
    if optional:
        return "|o" if left else "o|"
    return "||"


# ---------------------------------------------------------------------------
# 手動維護的文件
# ---------------------------------------------------------------------------

def load_pages():
    """回傳 {型別名: (中文名, 說明 markdown)}，依檔案順序"""
    pages = {}
    if not PAGES_MD.exists():
        return pages
    current, title, buf = None, "", []
    for line in PAGES_MD.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^##\s+(\w+)\s*[｜|]\s*(.+?)\s*$", line)
        if m:
            if current:
                pages[current] = (title, "\n".join(buf).strip())
            current, title, buf = m.group(1), m.group(2), []
        elif current:
            buf.append(line)
    if current:
        pages[current] = (title, "\n".join(buf).strip())
    return pages


def load_sequences():
    seqs = []
    for p in sorted(SEQ_DIR.glob("*.md")):
        text = p.read_text(encoding="utf-8")
        m = re.match(r"^#\s+(.+)$", text, re.M)
        title = m.group(1).strip() if m else p.stem
        blocks = re.findall(r"```mermaid\n(.*?)```", text, re.S)
        body = re.sub(r"^#\s+.+$", "", text, count=1, flags=re.M)
        body = re.sub(r"```mermaid\n.*?```", "\0MERMAID\0", body, flags=re.S)
        seqs.append((p, title, body.strip(), blocks))
    return seqs


def mini_markdown(text: str) -> str:
    """段落、清單、`程式碼`、**粗體**"""
    out, para, items = [], [], []

    def inline(s):
        s = html.escape(s)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        return s

    def flush():
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
            para.clear()
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items.clear()

    for line in text.splitlines():
        s = line.strip()
        if not s:
            flush()
        elif s.startswith(("- ", "* ")):
            if para:
                flush()
            items.append(s[2:])
        else:
            if items:
                flush()
            para.append(s)
    flush()
    return "\n".join(out)


# ---------------------------------------------------------------------------
# 檢查
# ---------------------------------------------------------------------------

def check_content(files, owner, pages, seqs):
    errors = []
    screens = {f.stem for f in files if f.is_screen}
    for s in sorted(screens - set(pages)):
        errors.append(f"pages.md 缺少畫面說明：## {s}｜中文名")
    for s in sorted(set(pages) - screens):
        errors.append(f"pages.md 有不存在的畫面：{s}（已改名或刪除？）")
    for p, _title, _body, blocks in seqs:
        if not blocks:
            errors.append(f"{p.relative_to(ROOT)} 沒有 ```mermaid 區塊")
        for block in blocks:
            for m in re.finditer(r"^\s*(?:participant|actor)\s+(\w+)", block, re.M):
                name = m.group(1)
                if name.endswith(CHECKED_SUFFIXES) and name not in owner:
                    errors.append(f"{p.relative_to(ROOT)} 引用了不存在的型別：{name}")
    return errors


# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------

def mermaid_block(src: str, extra_class: str = "") -> str:
    return f'<div class="diagram {extra_class}"><pre class="mermaid">{html.escape(src)}</pre></div>'


def chip_list(items):
    if not items:
        return '<span class="muted">—</span>'
    return " ".join(f"<code>{html.escape(i)}</code>" for i in items)


def render(files, owner, refs, externals, pages, seqs):
    screens, out_links, incoming = screen_links(files, refs)
    titles = {k: v[0] for k, v in pages.items()}

    # ---- 頁面 ----
    page_sections = []
    by_folder = defaultdict(list)
    for s in screens:
        by_folder[s.page_folder].append(s)
    ordered_names = list(pages)
    for folder in sorted(by_folder, key=folder_order):
        cards = []
        members = sorted(by_folder[folder],
                         key=lambda x: ordered_names.index(x.stem) if x.stem in ordered_names else 999)
        for s in members:
            title, desc = pages.get(s.stem, ("（尚未撰寫）", ""))
            vms = sorted(g.stem for g in refs[s] if g.layer == "ViewModel")
            services = sorted({g.stem for v in [s] + [g for g in refs[s] if g.layer == "ViewModel"]
                               for g in refs[v] if g.layer in ("Service", "Data")})
            ext = sorted({external_group(m) for v in [s] + [g for g in refs[s] if g.layer == "ViewModel"]
                          for m in externals[v]})
            cards.append(f"""
<article class="card" id="page-{s.stem}">
  <header><h3>{html.escape(title)}</h3><code class="type">{s.stem}</code></header>
  <div class="desc">{mini_markdown(desc) if desc else '<p class="muted">尚未撰寫說明</p>'}</div>
  <dl>
    <dt>從哪裡進來</dt><dd>{chip_list([titles.get(x.stem, x.stem) for x in incoming.get(s, [])])}</dd>
    <dt>會打開</dt><dd>{chip_list([titles.get(x.stem, x.stem) for x in out_links[s]])}</dd>
    <dt>ViewModel</dt><dd>{chip_list(vms)}</dd>
    <dt>共用計算／資料層</dt><dd>{chip_list(services)}</dd>
    {'<dt>外部套件</dt><dd>' + chip_list(ext) + '</dd>' if ext else ''}
  </dl>
</article>""")
        page_sections.append(
            f'<section class="folder"><h2>{PAGE_FOLDER_TITLES.get(folder, folder)}'
            f' <span class="muted">{folder}</span></h2><div class="cards">{"".join(cards)}</div></section>'
        )

    # ---- 架構 ----
    arch = [
        "<h2>分層架構總覽</h2>",
        '<p class="muted">箭頭表示「會用到」。只畫 View → ViewModel → Service → Data → 外部套件，'
        "Model、Utilities、Extensions 每層都會用，不畫。虛線框是外部套件。</p>",
        mermaid_block(overview_mermaid(files, refs, externals), "wide"),
    ]
    for folder in sorted({f.page_folder for f in files if f.page_folder and f.page_folder != "Components"},
                         key=folder_order):
        arch.append(f"<h2>{PAGE_FOLDER_TITLES.get(folder, folder)}"
                    f' <span class="muted">{folder}</span></h2>')
        arch.append(mermaid_block(page_dependency_mermaid(folder, files, refs, externals), "wide"))

    # ---- 流程 ----
    seq_html = []
    toc = []
    for i, (p, title, body, blocks) in enumerate(seqs):
        anchor = f"seq-{p.stem}"
        toc.append(f'<li><a href="#{anchor}">{html.escape(title)}</a></li>')
        parts = body.split("\0MERMAID\0")
        rendered = []
        for j, part in enumerate(parts):
            rendered.append(mini_markdown(part))
            if j < len(blocks):
                rendered.append(mermaid_block(blocks[j], "wide"))
        seq_html.append(f'<section class="seq" id="{anchor}"><h2>{html.escape(title)}</h2>{"".join(rendered)}</section>')

    stats = (f"{len(files)} 個 Swift 檔、{len(screens)} 個畫面、"
             f"{len(ET.parse(MODEL).getroot().findall('entity'))} 個 CoreData entity、{len(seqs)} 張循序圖")

    return TEMPLATE.format(
        mermaid_url=MERMAID_URL,
        stats=stats,
        nav=mermaid_block(navigation_mermaid(screens, out_links, titles), "wide"),
        pages="".join(page_sections),
        arch="".join(arch),
        er=mermaid_block(er_mermaid(), "wide"),
        seq_toc="".join(toc),
        seqs="".join(seq_html) or '<p class="muted">尚無循序圖</p>',
    )


TEMPLATE = """<!doctype html>
<!-- 由 scripts/build_docs.py 自動產生，請勿手改。說明改 docs/architecture/pages.md，循序圖改 docs/architecture/sequences/ -->
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tilli 架構地圖</title>
<style>
:root {{
  --bg: #fafaf9; --surface: #ffffff; --text: #1c1917; --muted: #78716c;
  --border: #e7e5e4; --accent: #0f766e; --code-bg: #f5f5f4;
}}
@media (prefers-color-scheme: dark) {{
  :root {{
    --bg: #161514; --surface: #1f1e1c; --text: #e7e5e4; --muted: #a8a29e;
    --border: #3a3734; --accent: #5eead4; --code-bg: #2a2826;
  }}
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--text);
  font: 15px/1.6 -apple-system, BlinkMacSystemFont, "PingFang TC", "Noto Sans TC", sans-serif; }}
header.top {{ padding: 20px 16px 0; max-width: 1200px; margin: 0 auto; }}
header.top h1 {{ margin: 0 0 4px; font-size: 22px; }}
nav.tabs {{ position: sticky; top: 0; z-index: 2; background: var(--bg); border-bottom: 1px solid var(--border); }}
nav.tabs .inner {{ max-width: 1200px; margin: 0 auto; padding: 0 16px; display: flex; gap: 4px; overflow-x: auto; }}
nav.tabs button {{ border: 0; background: none; color: var(--muted); font: inherit; padding: 12px 14px;
  border-bottom: 2px solid transparent; cursor: pointer; white-space: nowrap; }}
nav.tabs button[aria-selected="true"] {{ color: var(--accent); border-bottom-color: var(--accent); font-weight: 600; }}
main {{ max-width: 1200px; margin: 0 auto; padding: 16px; }}
.tab {{ display: none; }}
.tab.active {{ display: block; }}
h2 {{ font-size: 18px; margin: 28px 0 12px; }}
h3 {{ font-size: 16px; margin: 0; }}
.muted {{ color: var(--muted); font-weight: normal; font-size: 13px; }}
code {{ background: var(--code-bg); border-radius: 4px; padding: 1px 5px; font-size: 12.5px;
  font-family: ui-monospace, "SF Mono", Menlo, monospace; }}
.cards {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 12px; }}
.card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 14px 16px; }}
.card header {{ display: flex; justify-content: space-between; align-items: baseline; gap: 8px; flex-wrap: wrap; }}
.card .desc p {{ margin: 8px 0; }}
.card .desc ul {{ margin: 6px 0; padding-left: 20px; }}
.card dl {{ display: grid; grid-template-columns: max-content 1fr; gap: 4px 10px; margin: 10px 0 0;
  font-size: 13px; border-top: 1px dashed var(--border); padding-top: 10px; }}
.card dt {{ color: var(--muted); }}
.card dd {{ margin: 0; display: flex; flex-wrap: wrap; gap: 4px; }}
.diagram {{ background: var(--surface); border: 1px solid var(--border); border-radius: 10px;
  padding: 12px; overflow-x: auto; margin: 8px 0 16px; }}
.diagram pre.mermaid {{ margin: 0; background: none; text-align: center; }}
.diagram.wide svg {{ max-width: none !important; }}
.seq-toc {{ padding-left: 20px; }}
.seq p {{ max-width: 760px; }}
a {{ color: var(--accent); }}
@media (max-width: 480px) {{ .cards {{ grid-template-columns: 1fr; }} }}
</style>
</head>
<body>
<header class="top">
  <h1>Tilli 架構地圖</h1>
  <p class="muted">{stats}。由 <code>scripts/build_docs.py</code> 在每次 commit 前自動產生。</p>
</header>
<nav class="tabs"><div class="inner" role="tablist">
  <button role="tab" data-tab="pages" aria-selected="true">頁面說明</button>
  <button role="tab" data-tab="nav" aria-selected="false">頁面地圖</button>
  <button role="tab" data-tab="arch" aria-selected="false">架構圖</button>
  <button role="tab" data-tab="er" aria-selected="false">資料結構</button>
  <button role="tab" data-tab="seq" aria-selected="false">流程（循序圖）</button>
</div></nav>
<main>
  <section class="tab active" id="tab-pages">{pages}</section>
  <section class="tab" id="tab-nav">
    <h2>頁面地圖</h2>
    <p class="muted">箭頭：左邊的畫面會打開右邊的畫面（依程式碼引用自動產生）。</p>
    {nav}
  </section>
  <section class="tab" id="tab-arch">{arch}</section>
  <section class="tab" id="tab-er">
    <h2>CoreData 資料結構</h2>
    <p class="muted">連線標籤是 relationship 名稱與刪除規則（Cascade 會連帶刪除、Nullify 只清掉關聯）。欄位分類以 ARCHITECTURE.md §4 為準。</p>
    {er}
  </section>
  <section class="tab" id="tab-seq">
    <h2>流程</h2>
    <ul class="seq-toc">{seq_toc}</ul>
    {seqs}
  </section>
</main>
<script src="{mermaid_url}"></script>
<script>
(function () {{
  var dark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  mermaid.initialize({{ startOnLoad: false, theme: dark ? "dark" : "neutral", securityLevel: "loose",
    flowchart: {{ htmlLabels: true, useMaxWidth: false }}, sequence: {{ useMaxWidth: false }},
    er: {{ layoutDirection: "LR", useMaxWidth: false }} }});
  var rendered = {{}};
  function show(name) {{
    document.querySelectorAll(".tab").forEach(function (t) {{ t.classList.toggle("active", t.id === "tab-" + name); }});
    document.querySelectorAll("nav.tabs button").forEach(function (b) {{
      b.setAttribute("aria-selected", b.dataset.tab === name ? "true" : "false");
    }});
    if (!rendered[name]) {{
      rendered[name] = true;
      mermaid.run({{ nodes: document.querySelectorAll("#tab-" + name + " pre.mermaid") }});
    }}
    try {{ history.replaceState(null, "", "#" + name); }} catch (e) {{}}
  }}
  document.querySelectorAll("nav.tabs button").forEach(function (b) {{
    b.addEventListener("click", function () {{ show(b.dataset.tab); }});
  }});
  var initial = (location.hash || "").replace("#", "");
  show(["pages", "nav", "arch", "er", "seq"].indexOf(initial) >= 0 ? initial : "pages");
}})();
</script>
</body>
</html>
"""


def main():
    check = "--check" in sys.argv
    files = load_files()
    owner, refs, externals = build_graph(files)
    pages = load_pages()
    seqs = load_sequences()
    errors = check_content(files, owner, pages, seqs)
    output = render(files, owner, refs, externals, pages, seqs)

    if check:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != output:
            errors.append("docs/architecture/index.html 不是最新，請執行 python3 scripts/build_docs.py")
        for e in errors:
            print("❌", e)
        if errors:
            sys.exit(1)
        print("✅ 架構文件完整且是最新")
        return

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(output, encoding="utf-8")
    print(f"已產生 {OUT.relative_to(ROOT)}")
    for e in errors:
        print("⚠️ ", e)


if __name__ == "__main__":
    main()
