FluxTunnel — نصب کامل
۱ — سرور خارج (VPS) — اول اجرا کن
# گزینه 2 بزن، پورت 20000 تأیید کن
bash <(curl -s https://raw.githubusercontent.com/Aminroo/FluxTunnel/main/setup.sh)
۲ — سرور ایران — از طریق پروکسی x-ui
# پروکسی: weira.ir:27142 (mixed inbound)
bash <(curl -x socks5h://YOUR_PROXY:PORT -s https://raw.githubusercontent.com/Aminroo/FluxTunnel/main/setup.sh)
چون inbound از نوع mixed هست، هم socks5h:// هم http:// کار می‌کنه. socks5h بهتره چون DNS را هم از طریق پروکسی رزالو می‌کنه.
۳ — جواب سوالات (گزینه 1 — Client Setup)
SOCKS5 proxy داری؟
1 (Yes) → YOUR_PROXY:PORT
SSH host
IP سرور خارج
SSH user
root
SSH port
22
Auth
1 (Password) → رمز SSH وارد کن
تعداد تونل
1
Remote port on VPS
20000
Local port to forward
54321 ← پورت پنل x-ui ایران
۴ — تأیید
# روی VPS چک کن
ss -tlnp | grep 20000
# باید ببینی: 0.0.0.0:20000
ربات فروش → http://VPS_IP:20000 → پنل x-ui ایران
پورت پنل x-ui را دقیق وارد کن. پیش‌فرض 54321 است ولی اگر تغییر دادی همون را بزن
