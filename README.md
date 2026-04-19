# FluxTunnel
> SSH Reverse Tunnel Manager — اتصال امن سرور ایران به VPS خارج

![Version](https://img.shields.io/badge/version-0.3.0-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![License](https://img.shields.io/badge/license-MIT-orange)

---

## معرفی

FluxTunnel یک تونل معکوس SSH می‌سازد که سرور ایران را از طریق یک VPS خارج در دسترس قرار می‌دهد.  
مناسب برای اتصال ربات فروش به پنل x-ui بدون نیاز به IP مستقیم ایران، حتی زمانی که دسترسی مستقیم به اینترنت خارج مسدود است.

```
سرور ایران  ──SSH Reverse Tunnel──►  VPS خارج  ◄──  ربات / کاربر
```

### ویژگی‌ها
- **اتصال خودکار** — در صورت قطع، تونل به‌صورت خودکار reconnect می‌کند
- **پشتیبانی از SOCKS5** — برای سرورهایی که دسترسی مستقیم به اینترنت ندارند
- **مدیریت پسورد رمزنگاری‌شده** — ذخیره امن با AES-256
- **چند تونل همزمان** — تا ۲۰ تونل موازی
- **سرویس systemd** — اجرای خودکار بعد از ریبوت
- **منوی تعاملی** — نصب، ویرایش، حذف، لاگ زنده

---

## پیش‌نیازها

| سرور | نیاز |
|------|------|
| VPS خارج | `openssh-server` — معمولاً از پیش نصب است |
| سرور ایران | `autossh` یا `ssh`، `nc`، `sshpass` — اسکریپت خودکار نصب می‌کند |

---

## نصب

### مرحله ۱ — سرور خارج (VPS) را آماده کن

روی **VPS خارج** اجرا کن:

```bash
bash <(curl -s https://raw.githubusercontent.com/Aminroo/FluxTunnel/main/setup.sh)
```

از منو گزینه **`2) Server Setup`** را انتخاب کن.

این مرحله:
- `GatewayPorts clientspecified` را در sshd تنظیم می‌کند (لازم برای bind روی `0.0.0.0`)
- پورت‌های تونل را در فایروال باز می‌کند
- منتظر اتصال سرور ایران می‌ماند

---

### مرحله ۲ — سرور ایران را وصل کن

اگر سرور ایران دسترسی مستقیم به اینترنت خارج **ندارد** (از طریق پروکسی):

```bash
bash <(curl -x socks5h://YOUR_PROXY_IP:PORT -s https://raw.githubusercontent.com/Aminroo/FluxTunnel/main/setup.sh)
```

اگر دسترسی مستقیم **دارد**:

```bash
bash <(curl -s https://raw.githubusercontent.com/Aminroo/FluxTunnel/main/setup.sh)
```

از منو گزینه **`1) Client Setup`** را انتخاب کن.

---

### مرحله ۳ — پاسخ به سوالات Client Setup

| سوال | پاسخ |
|------|------|
| SOCKS5 proxy? | اگر دسترسی مستقیم نداری: `1 (Yes)` → آدرس پروکسی |
| SSH host | IP سرور خارج (VPS) |
| SSH user | `root` |
| SSH port | `22` (یا پورت SSH سفارشی) |
| Authentication | `1 (Password)` → رمز SSH سرور خارج را وارد کن |
| تعداد تونل | `1` (یا بیشتر در صورت نیاز) |
| Remote port on VPS | پورتی که روی VPS باز می‌شود — مثلاً `20000` |
| Local port to forward | پورت سرویس روی سرور ایران — مثلاً `54321` برای x-ui |

> **نکته پروکسی:** پروکسی باید یک inbound داشته باشد که ترافیک outbound را به اینترنت route کند. اگر پروکسی خود x-ui را به عنوان proxy استفاده می‌کنی، مطمئن شو که outbound آن به اینترنت آزاد وصل است — در غیر این صورت تونل connect نخواهد شد.

---

### مرحله ۴ — تأیید اتصال

روی **VPS خارج** بزن:

```bash
ss -tlnp | grep 20000
```

✅ **اتصال موفق:**
```
LISTEN  0  128  0.0.0.0:20000  0.0.0.0:*
```

⚠️ **GatewayPorts مشکل دارد:**
```
LISTEN  0  128  127.0.0.1:20000  0.0.0.0:*
```
→ دوباره **Server Setup** را روی VPS اجرا کن تا `GatewayPorts` درست تنظیم شود.

❌ **پورت اصلاً باز نیست** → لاگ سرور ایران را بررسی کن:
```bash
journalctl -u ssh-tunnel -n 50
```

---

## نتیجه

بعد از اتصال موفق:

```
http://VPS_IP:20000  →  پنل x-ui سرور ایران
```

ربات فروش یا هر سرویس دیگری می‌تواند از طریق IP و پورت VPS به پنل x-ui ایران دسترسی داشته باشد.

---

## مدیریت سرویس

```bash
# وضعیت سرویس
systemctl status ssh-tunnel

# ری‌استارت
systemctl restart ssh-tunnel

# لاگ زنده
journalctl -u ssh-tunnel -f

# منوی کامل (لیست تونل‌ها، ویرایش، حذف، آپدیت)
sudo bash setup.sh
```

---

## گزینه‌های منو

| گزینه | کاربرد |
|-------|---------|
| `1) Client Setup` | نصب تونل روی سرور ایران |
| `2) Server Setup` | آماده‌سازی VPS برای دریافت تونل |
| `3) List tunnels` | مشاهده تونل‌های تنظیم‌شده و وضعیت آن‌ها |
| `4) Edit tunnel` | ویرایش پورت، هاست، یا پروکسی یک تونل |
| `5) Delete tunnel` | حذف یک تونل |
| `6) Password manager` | مشاهده و مدیریت پسوردهای ذخیره‌شده |
| `7) Restart service` | ری‌استارت سرویس تونل |
| `8) View live logs` | مشاهده لاگ زنده |
| `9) Update script` | آپدیت به آخرین نسخه از GitHub |
| `10) Uninstall` | حذف کامل FluxTunnel |

---

## عیب‌یابی

| مشکل | راه‌حل |
|------|--------|
| پورت روی `127.0.0.1` باز شد | Server Setup را دوباره روی VPS اجرا کن — `GatewayPorts` درست نشده |
| `curl` به GitHub وصل نشد | پروکسی را چک کن — از `-x socks5h://...` استفاده کن |
| سرویس مدام restart می‌شود | `journalctl -u ssh-tunnel -n 50` را بررسی کن |
| `Connection timed out` | IP و پورت VPS را چک کن — فایروال را بررسی کن |
| بعد از ریبوت تونل وصل نمی‌شود | `systemctl enable ssh-tunnel` را اجرا کن |
| چند تونل قدیمی زنده مانده‌اند | `pkill -9 -f "ssh -N"` سپس `systemctl restart ssh-tunnel` |

---

## ساختار فایل‌ها

```
/etc/ssh-tunnel/
├── tunnels.conf       # تنظیمات تونل‌ها
├── auth.conf          # پسوردهای رمزنگاری‌شده (chmod 600)
├── .enc_key           # کلید AES-256 (chmod 600)
├── ssh_t1.conf        # ssh config تونل شماره ۱
├── mode               # client یا server
└── tunnel.log         # لاگ اتصالات

/usr/local/bin/ssh-tunnel     # اسکریپت اجرایی تونل
/etc/systemd/system/ssh-tunnel.service
```

---

## امنیت

- پسوردها با **AES-256-CBC** و کلید تصادفی یکتا رمزنگاری می‌شوند
- کلید رمزنگاری در `/etc/ssh-tunnel/.enc_key` با دسترسی `600` ذخیره می‌شود
- ProxyCommand از طریق فایل ssh_config پاس می‌شود (نه environment variable)
- اتصال SSH از طریق **key-based authentication** برقرار می‌شود

---

## لایسنس

MIT License
