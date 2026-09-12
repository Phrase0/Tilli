#!/usr/bin/env python3
"""
檢查 CoreData 的每個屬性都在 ARCHITECTURE.md §4 的分類表上有一列。

規則：
  CoreData 有、表上沒有        → ❌ 未分類（必須補上）
  表上標「現有」、CoreData 沒有 → ❌ 表過期（必須更新）
  表上標「新增」、CoreData 沒有 → ⏳ 待實作（正常）
  表上標「刪除」、CoreData 還有 → ⏳ 待移除（正常）

用法：python3 scripts/check_field_classification.py [model_contents] [architecture.md]
"""
import re, sys, xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents"
DOC = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "ARCHITECTURE.md"


def load_coredata():
    root = ET.parse(MODEL).getroot()
    return {
        e.get("name"): {a.get("name") for a in e.findall("attribute")}
        for e in root.findall("entity")
    }


def load_doc():
    """解析 ### CDXxx 段落底下的表格，回傳 {entity: {field: status}}"""
    text = DOC.read_text(encoding="utf-8")
    result, current = {}, None
    for line in text.splitlines():
        m = re.match(r"^###\s+(CD\w+)\s*$", line)
        if m:
            current = m.group(1)
            result[current] = {}
            continue
        if re.match(r"^##\s", line):       # 進入新的大節就停止歸屬
            current = None
        if current is None or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 3:
            continue
        fm = re.match(r"^`(\w+)`$", cells[0])
        if not fm:
            continue                        # 表頭、分隔線、非欄位列
        status = re.sub(r"[*`]", "", cells[2]).strip()
        result[current][fm.group(1)] = status
    return result


def main():
    cd, doc = load_coredata(), load_doc()
    errors, pending = [], []

    for entity, attrs in sorted(cd.items()):
        if entity not in doc:
            errors.append(f"entity `{entity}` 在 ARCHITECTURE.md 完全沒有段落")
            continue
        for a in sorted(attrs):
            if a not in doc[entity]:
                errors.append(f"{entity}.{a} → ❌ 未分類")
            elif doc[entity][a] == "新增":
                pending.append(f"{entity}.{a} → ⚠️ 標「新增」但 CoreData 已存在，請改成「現有」")

    for entity, fields in sorted(doc.items()):
        if entity not in cd:
            if not all(s == "刪除" for s in fields.values()):
                errors.append(f"entity `{entity}` 在文件上但 CoreData 沒有")
            continue
        for f, status in sorted(fields.items()):
            if f in cd[entity]:
                if status == "刪除":
                    pending.append(f"{entity}.{f} → ⏳ 待移除")
            else:
                if status == "新增":
                    pending.append(f"{entity}.{f} → ⏳ 待實作")
                else:
                    errors.append(f"{entity}.{f} → ❌ 表過期（標「{status}」但 CoreData 沒有此欄位）")

    total_cd = sum(len(v) for v in cd.values())
    total_doc = sum(len(v) for v in doc.values())
    print(f"CoreData：{len(cd)} entity / {total_cd} 屬性")
    print(f"分類表　：{len(doc)} entity / {total_doc} 列")
    print()

    if pending:
        print(f"⏳ 計畫中（{len(pending)}）")
        for p in pending:
            print("   " + p)
        print()

    if errors:
        print(f"❌ 錯誤（{len(errors)}）")
        for e in errors:
            print("   " + e)
        sys.exit(1)

    print("✅ 所有 CoreData 屬性都已分類")


if __name__ == "__main__":
    main()
