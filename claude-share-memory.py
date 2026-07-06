#!/usr/bin/env python3
"""跨 profile 共用專案 memory：以 main 為主，補進其他 profile 的獨有檔。

共用正本位置 = ~/.claude/projects/<slug>/memory
- main 已有的檔：絕對不動（同名 main 勝）
- main 缺、其他 profile 才有的檔：補進正本
- main 沒有該 project（如 iso）：以檔案最多的 profile 當底，其餘補獨有
- MEMORY.md：按 (檔名.md) 去重合併，正本/基礎版的行優先
- 被降級的 profile memory 目錄：改名備份 memory.bak.<ts>，再換成 symlink

用法：  python3 share_memory.py            # dry-run，只印計劃
        python3 share_memory.py --apply    # 實際執行
"""
import os, sys, glob, hashlib, shutil, re, datetime

HOME = os.path.expanduser("~")
APPLY = "--apply" in sys.argv
TS = datetime.datetime.now().strftime("%Y%m%d%H%M%S")

def md5(p):
    with open(p, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()

def files_in(d):
    return sorted(f for f in os.listdir(d)
                  if os.path.isfile(os.path.join(d, f)))

def canon_of(slug):
    return f"{HOME}/.claude/projects/{slug}/memory"

# ---- 蒐集每個 slug 的所有來源 ----
slugs = {}   # slug -> {source_name: dir}
main_glob = f"{HOME}/.claude/projects/*/memory"
prof_glob = f"{HOME}/.claude_profiles/*/projects/*/memory"

for m in glob.glob(main_glob):
    if os.path.islink(m):  # 已經是 symlink 就跳過
        continue
    slug = m.split("/projects/")[1].split("/")[0]
    slugs.setdefault(slug, {})["main"] = m

for pd in glob.glob(prof_glob):
    prof = pd.split("/.claude_profiles/")[1].split("/")[0]
    slug = pd.split("/projects/")[1].split("/")[0]
    slugs.setdefault(slug, {})[prof] = pd

FILE_RE = re.compile(r"\(([^)]+\.md)\)")

def merge_memory_index(base_path, add_path):
    """把 add_path(MEMORY.md) 裡、base 沒有的檔案指標行 append 到 base。"""
    base_lines = []
    seen_files = set()
    if os.path.exists(base_path):
        base_lines = open(base_path, encoding="utf-8").read().splitlines()
        for ln in base_lines:
            mo = FILE_RE.search(ln)
            if mo:
                seen_files.add(mo.group(1))
    added = []
    for ln in open(add_path, encoding="utf-8").read().splitlines():
        mo = FILE_RE.search(ln)
        if mo and mo.group(1) not in seen_files:
            added.append(ln)
            seen_files.add(mo.group(1))
    if added:
        out = base_lines + ([""] if base_lines and base_lines[-1].strip() else []) + added
        if APPLY:
            with open(base_path, "w", encoding="utf-8") as fh:
                fh.write("\n".join(out) + "\n")
    return len(added)

# ---- 處理每個 slug ----
plan = []
for slug in sorted(slugs):
    srcs = slugs[slug]
    canon = canon_of(slug)
    # 來源處理順序：main 先（絕對基礎），其餘 profile 按檔案數多→少
    order = []
    if "main" in srcs:
        order.append("main")
    profs = [s for s in srcs if s != "main"]
    profs.sort(key=lambda s: len(files_in(srcs[s])), reverse=True)
    order += profs

    canon_exists_main = "main" in srcs   # canon 本身就是 main 的目錄
    if APPLY:
        os.makedirs(canon, exist_ok=True)

    log = [f"\n████ {slug}   來源順序: {', '.join(order)}"]
    if not canon_exists_main:
        log.append(f"    (main 無此 project → 以 {profs[0]} 為底建立共用正本)")

    for src in order:
        d = srcs[src]
        if src == "main":
            log.append(f"    • main：{len(files_in(d))} 檔，作為正本基礎（不動）")
            continue
        # profile 來源：補獨有檔、合併索引、備份、symlink
        added_files, skipped, idx_added = [], 0, 0
        for f in files_in(d):
            sp = os.path.join(d, f)
            cp = os.path.join(canon, f)
            if f == "MEMORY.md":
                if os.path.exists(cp):
                    idx_added = merge_memory_index(cp, sp)
                else:
                    if APPLY:
                        shutil.copy2(sp, cp)
                    added_files.append(f)
                continue
            if os.path.exists(cp):
                skipped += 1
            else:
                if APPLY:
                    shutil.copy2(sp, cp)
                added_files.append(f)
        bak = f"{d}.bak.{TS}"
        if APPLY:
            os.rename(d, bak)
            os.symlink(canon, d)
        log.append(f"    • {src}：補 {len(added_files)} 檔"
                   + (f" {added_files}" if added_files else "")
                   + f"、同名跳過 {skipped}、索引補 {idx_added} 行"
                   + f" → 備份 {os.path.basename(bak)}、symlink→正本")
    plan.append("\n".join(log))

print("=" * 60)
print("DRY-RUN 計劃" if not APPLY else "已執行")
print("=" * 60)
print("\n".join(plan))
print("\n" + ("（這只是計劃，加 --apply 才會動手）" if not APPLY else "✅ 完成"))
