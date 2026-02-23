# AIO

--

## Install 
1. Download Script
```
wget https://raw.githubusercontent.com/AhollL/AIO/main/aio.sh
```
2. Izin & Jalankan
```
chmod +x aio.sh
sudo ./aio.sh
```

--

## Troubleshoot
- Jika konflik port: Edit config manual (`/usr/local/etc/xray/config.json` untuk Xray, `/etc/zivpn/config.json` untuk ZIVPN) lalu restart service.
- Cek status: `systemctl status xray` atau `systemctl status zivpn`.
- Cek firewall: `ufw status`.
- Cek iptables: `iptables -t nat -L -v -n`.
- Log: `/var/log/xray/` untuk Xray, `journalctl -u zivpn` untuk ZIVPN.
- Jika uninstall ZIVPN gagal hapus rules: Jalankan manual `iptables -t nat -F` dan `ufw reset` (hati-hati, ini reset semua rules
