# -*- coding: utf-8 -*-
import os
import csv
import tkinter as tk # 用于自动复制剪贴板

# ================= 配置区域 =================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_ENV = os.path.join(BASE_DIR, "worker.env")

# 端口池 (自动轮询)
PORTS_HTTP = [80, 8080, 8880, 2052, 2082, 2086, 2095]
PORTS_HTTPS = [443, 2053, 2083, 2087, 2096, 8443]
# ===========================================

def get_latest_folder(sub_folder):
    """获取最新日期的 History 文件夹"""
    path = os.path.join(BASE_DIR, sub_folder, "History")
    if not os.path.exists(path): return None
    dirs = [d for d in os.listdir(path) if os.path.isdir(os.path.join(path, d))]
    if not dirs: return None
    dirs.sort(reverse=True) # 2026_02-11 排在最前
    return os.path.join(path, dirs[0])

def get_top_domains(file_path, count=10):
    """解析 CDNym.txt"""
    if not os.path.exists(file_path): return []
    res = []
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                parts = line.split("ms")
                if len(parts) > 1:
                    domain = parts[1].strip().lstrip("：:").strip()
                    if domain: res.append(domain)
                if len(res) >= count: break
    except: pass
    return res

def get_top_ips(file_path, count=10):
    """解析 CSV 第一列"""
    if not os.path.exists(file_path): return []
    res = []
    try:
        with open(file_path, 'r', encoding='utf-8-sig') as f:
            reader = csv.reader(f)
            next(reader, None)
            for row in reader:
                if row: res.append(row[0].strip())
                if len(res) >= count: break
    except: pass
    return res

def set_clipboard(text):
    """将生成的配置自动复制到系统剪贴板"""
    try:
        root = tk.Tk()
        root.withdraw()
        root.clipboard_clear()
        root.clipboard_append(text)
        root.update()
        root.destroy()
        return True
    except:
        return False

def main():
    print(f"🚀 工作目录: {BASE_DIR}")
    
    dir_dom = get_latest_folder("domain")
    dir_ip  = get_latest_folder("ip")
    if not dir_dom or not dir_ip:
        print("❌ 找不到 History 目录")
        return

    list_v4  = get_top_ips(os.path.join(dir_ip, "result.csv"))
    list_v6  = get_top_ips(os.path.join(dir_ip, "result_v6.csv"))
    list_dom = get_top_domains(os.path.join(dir_dom, "CDNym.txt"))

    # 兜底填充
    if not list_v4: list_v4 = ["104.16.1.1"] 
    if not list_v6: list_v6 = list_v4
    if not list_dom: list_dom = list_v4

    env = {}
    # 组装 1-13 组数据
    for i in range(4): # 1-4: IPv4 (80)
        env[f"ip{i+1}"] = list_v4[i % len(list_v4)]
        env[f"pt{i+1}"] = PORTS_HTTP[i % len(PORTS_HTTP)]
    for i in range(3): # 5-7: Domain (80)
        env[f"ip{i+5}"] = list_dom[i % len(list_dom)]
        env[f"pt{i+5}"] = PORTS_HTTP[(i+4) % len(PORTS_HTTP)]
    for i in range(4): # 8-11: IPv6 (443)
        env[f"ip{i+8}"] = list_v6[i % len(list_v6)]
        env[f"pt{i+8}"] = PORTS_HTTPS[i % len(PORTS_HTTPS)]
    env["ip12"] = list_dom[3] if len(list_dom) > 3 else list_dom[0] # 12: Domain (443)
    env["pt12"] = PORTS_HTTPS[4 % len(PORTS_HTTPS)]
    env["ip13"] = list_v4[0] # 13: IPv4复用 (443)
    env["pt13"] = PORTS_HTTPS[5 % len(PORTS_HTTPS)]

    # 构造带注释的格式化内容
    content = ""
    for i in range(1, 14):
        if i == 1: content += "# IPv4地址 (80系)\n"
        elif i == 5: content += "\n# Domain域名 (80系)\n"
        elif i == 8: content += "\n# IPv6地址 (443系)\n"
        elif i == 12: content += "\n# Domain域名 (443系)\n"
        elif i == 13: content += "\n# IPv4复用 (443系)\n"
        
        content += f'ip{i}="{env[f"ip{i}"]}"\n'
        content += f'pt{i}="{env[f"pt{i}"]}"\n'

    try:
        # 1. 写入文件
        with open(OUTPUT_ENV, "w", encoding="utf-8") as f:
            f.write(content)
        
        # 2. 终端全量预览 (不再省略)
        print("\n" + "="*20 + " 全量配置预览 " + "="*20)
        print(content.strip())
        print("="*54)

        # 3. 自动复制到剪贴板
        if set_clipboard(content):
            print(f"\n✅ 成功生成: {OUTPUT_ENV}")
            print("📋 配置已自动复制到剪贴板！请直接在 Cloudflare 粘贴。")
        else:
            print(f"\n✅ 成功生成: {OUTPUT_ENV} (复制失败，请手动打开文件)")

    except Exception as e:
        print(f"❌ 操作失败: {e}")

if __name__ == "__main__":
    main()