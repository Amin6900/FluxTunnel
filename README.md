# FluxTunnel

> SSH Reverse Tunnel — اتصال پنل ایران به سرور خارج

---

## معرفی

FluxTunnel یک تونل معکوس SSH می‌سازد که سرور ایران را از طریق VPS خارج در دسترس قرار می‌دهد.  
مناسب برای اتصال ربات فروش به پنل x-ui بدون نیاز به IP مستقیم ایران.

```
سرور ایران  ──SSH Reverse──►  VPS خارج  ◄──  ربات فروش
```

---

## نصب

### ۱ — سرور خارج (VPS) — اول اجرا کن

```bash
bash <(curl -s https://raw.githubusercontent.com/Aminroo/FluxTunnel/main/setup.sh)
```

از منو گزینه `2) Server Setup` را انتخاب کن. پورت پیش‌فرض `20000` را تأیید کن.

---

### ۲ — سرور ایران

اگر سرور ایران به اینترنت خارج دسترسی مستقیم ندارد، از طریق پروکسی اجرا کن:

```bash
bash <(curl -x socks5h://YOUR_PROXY:PORT -s https://raw.githubusercontent.com/Aminroo/FluxTunnel/main/setup.sh)
```

> پروکسی باید در x-ui طوری تنظیم شود که inbound از طریق یک outbound سالم به اینترنت route شود، در غیر این صورت تونل وصل نخواهد شد.
---

### ۳ — جواب سوالات (گزینه 1 — Client Setup)

| سوال | جواب |
|------|------|
| SOCKS5 proxy داری؟ | `1 (Yes)` → آدرس پروکسی خودت |
| SSH host | IP سرور خارج |
| SSH user | `root` |
| SSH port | `22` |
| Auth | `1 (Password)` → رمز SSH |
| تعداد تونل | `1` |
| Remote port on VPS | `20000` |
| Local port to forward | پورت پنل x-ui ایران (مثلاً `54321`) |

---

### ۴ — تأیید اتصال

روی VPS اجرا کن:

```bash
ss -tlnp | grep 20000
```

خروجی مورد انتظار:

```
LISTEN  0  128  0.0.0.0:20000  0.0.0.0:*
```

اگر `127.0.0.1:20000` بود یعنی `GatewayPorts` فعال نیست — دوباره Server Setup را اجرا کن.

---

## نتیجه

```
  http://VPS_IP:20000  →  پنل x-ui ایران
```

---

## مدیریت سرویس

```bash
systemctl status ssh-tunnel      # وضعیت
systemctl restart ssh-tunnel     # ری‌استارت
journalctl -u ssh-tunnel -f      # لاگ زنده
sudo bash setup.sh               # منوی کامل
```

---

## عیب‌یابی

| مشکل | راه‌حل |
|------|--------|
| پورت روی `127.0.0.1` bind شد | Server Setup را دوباره روی VPS اجرا کن |
| curl به GitHub وصل نشد | پروکسی را چک کن |
| سرویس مدام restart می‌شود | `journalctl -u ssh-tunnel -n 50` را بررسی کن |
