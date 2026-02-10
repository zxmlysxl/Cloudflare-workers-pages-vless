# -*- coding: utf-8 -*-
import os
import csv

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

def get_top_domains(file_path, count=4):
    """
    解析 CDNym.txt (直接取前N行)
    格式兼容: "66.39 ms：www.boba88slot.com" (注意中文冒号)
    """
    if not os.path.exists(file_path): return []
    res = []
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                
                # 核心修复：先用 'ms' 切割，取后半部分
                # 例子: "66.39 ms：www.xxx.com" -> ["66.39 ", "：www.xxx.com"]
                parts = line.split("ms")
                if len(parts) > 1:
                    # 去掉可能存在的中文冒号、英文冒号、空格
                    domain = parts[1].strip().lstrip("：:").strip()
                    if domain: res.append(domain)
                
                if len(res) >= count: break # 取够了就停
    except Exception as e:
        print(f"❌ 读取域名出错: {e}")
    return res

def get_top_ips(file_path, count=4):
    """
    解析 CSV (直接取前N行)
    格式: IP地址,延迟... (直接取第一列)
    """
    if not os.path.exists(file_path): return []
    res = []
    try:
        # 使用 utf-8-sig 自动处理 BOM 头
        with open(file_path, 'r', encoding='utf-8-sig') as f:
            reader = csv.reader(f)
            next(reader, None) # 跳过第一行表头 (IP地址,最小延迟...)
            
            for row in reader:
                if not row: continue
                ip = row[0].strip() # 只要第一列
                if ip: res.append(ip)
                if len(res) >= count: break
    except Exception as e:
        print(f"❌ 读取IP出错 {os.path.basename(file_path)}: {e}")
    return res

def main():
    print(f"🚀 工作目录: {BASE_DIR}")
    
    # 1. 找文件
    dir_dom = get_latest_folder("domain")
    dir_ip  = get_latest_folder("ip")
    
    if not dir_dom or not dir_ip:
        print("❌ 找不到 History 目录，请检查路径结构")
        return

    file_dom = os.path.join(dir_dom, "CDNym.txt")
    file_v4  = os.path.join(dir_ip, "result.csv")
    file_v6  = os.path.join(dir_ip, "result_v6.csv")

    # 2. 读数据 (既然文件已排序，直接读 Top N)
    # 我们总共需要: 4个v4, 4个v6, 4个域名
    list_v4  = get_top_ips(file_v4, 10)     # 多读几个备用
    list_v6  = get_top_ips(file_v6, 10)
    list_dom = get_top_domains(file_dom, 10)

    print(f"📊 读取结果: IPv4={len(list_v4)}个, IPv6={len(list_v6)}个, 域名={len(list_dom)}个")

    # 3. 兜底 (如果数据不够，循环填充)
    if not list_v4: list_v4 = ["104.16.1.1"] 
    if not list_v6: list_v6 = list_v4 # 没v6就用v4顶替
    if not list_dom: list_dom = list_v4 # 没域名就用IP顶替

    # 4. 组装变量
    env = {}

    # === [IP1 - IP7] 80系端口 (Non-TLS) ===
    # 需求: 4个 IPv4 + 3个 域名
    
    # 1-4: IPv4
    for i in range(4):
        idx = i + 1
        env[f"ip{idx}"] = list_v4[i % len(list_v4)]
        env[f"pt{idx}"] = PORTS_HTTP[i % len(PORTS_HTTP)]

    # 5-7: 域名
    for i in range(3):
        idx = i + 5
        env[f"ip{idx}"] = list_dom[i % len(list_dom)]
        # 端口接续轮询
        env[f"pt{idx}"] = PORTS_HTTP[(i+4) % len(PORTS_HTTP)]

    # === [IP8 - IP13] 443系端口 (TLS) ===
    # 需求: 4个 IPv6 + 1个 域名 + 1个 最佳IPv4复用

    # 8-11: IPv6
    for i in range(4):
        idx = i + 8
        env[f"ip{idx}"] = list_v6[i % len(list_v6)]
        env[f"pt{idx}"] = PORTS_HTTPS[i % len(PORTS_HTTPS)]

    # 12: 剩余那个域名 (取第4个域名，index为3)
    env["ip12"] = list_dom[3] if len(list_dom) > 3 else list_dom[0]
    env["pt12"] = PORTS_HTTPS[4 % len(PORTS_HTTPS)] # 2096

    # 13: 复用最佳 IPv4
    env["ip13"] = list_v4[0]
    env["pt13"] = PORTS_HTTPS[5 % len(PORTS_HTTPS)] # 8443

    # 5. 写入文件
    content = ""
    # 按顺序排序写入，方便查看
    for i in range(1, 14):
        content += f'ip{i}="{env[f"ip{i}"]}"\n'
        content += f'pt{i}="{env[f"pt{i}"]}"\n'

    try:
        with open(OUTPUT_ENV, "w", encoding="utf-8") as f:
            f.write(content)
        print("-" * 30)
        print(f"✅ 成功生成: {OUTPUT_ENV}")
        print("👀 预览前 8 行:")
        print("\n".join(content.split("\n")[:8]))
        print("-" * 30)
    except Exception as e:
        print(f"❌ 写入失败: {e}")

if __name__ == "__main__":
    main()