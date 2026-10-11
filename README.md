# Bash Log Toolkit

Linux log fayllarını yalnız standart Unix alətləri (`grep`, `awk`, `sed`, `sort`, `uniq`, `journalctl`) ilə analiz edən Bash skriptləri toplusu. Heç bir əlavə kitabxana tələb etmir, istənilən Ubuntu/Debian serverdə dərhal işləyir.

Layihənin məqsədi: eyni işi (SSH hücumlarını və veb trafikini analiz etmək) Python-un əvəzinə **Linux-un öz alətləri ilə** görmək və Python-dakı Log Analyzer ilə müqayisə etmək.

## Əmrlər
Vahid giriş nöqtəsi: `./logtool <əmr>`

| Əmr | Nə edir |
|---|---|
| `ssh-ips [-n SAY] FAYL` | Ən çox uğursuz SSH cəhdi edən IP-lər |
| `ssh-users [-n SAY] FAYL` | Hücumçuların ən çox sınadığı istifadəçi adları |
| `ssh-hourly FAYL` | Uğursuz cəhdlərin saat üzrə ASCII qrafiki |
| `web [-n SAY] FAYL` | Access log: status kodları, top IP/URL/User-Agent |
| `web-suspicious FAYL` | SQL injection, path traversal, XSS, skaner və həssas fayl axtarışı |
| `journal [-s ZAMAN]` | `journalctl` ilə xəta xülasəsi, uğursuz servislər, SSH cəhdləri |

`FAYL` ola bilər: adi log faylı, `.gz` arxivi (məs. `auth.log.2.gz`) və ya `-` (stdin).

## Quraşdırma
```bash
git clone https://github.com/<istifadəçi_adın>/bash-log-toolkit.git
cd bash-log-toolkit
chmod +x logtool scripts/*.sh
```
Tələblər: Bash 4+, `grep`, `awk`, `sed`, `gzip`. `journal` əmri üçün `systemd` lazımdır.

## İstifadə nümunələri
```bash
# Nümunə loglarla
./logtool ssh-ips samples/auth.log
./logtool ssh-users -n 5 samples/auth.log
./logtool ssh-hourly samples/auth.log
./logtool web samples/access.log
./logtool web-suspicious samples/access.log

# Real serverdə
sudo ./logtool ssh-ips /var/log/auth.log
sudo ./logtool ssh-ips /var/log/auth.log.2.gz
zcat /var/log/nginx/access.log.*.gz | ./logtool web -
./logtool journal -s "6 hours ago"
```

### Nümunə çıxış
```
$ ./logtool ssh-ips samples/auth.log
Ən çox uğursuz SSH cəhdi edən IP-lər (top 10)
   CƏHD  IP
      12  203.0.113.5
       5  198.51.100.7
       2  192.0.2.44

$ ./logtool ssh-hourly samples/auth.log
03:00      12  ########################################
...
14:00       7  #######################
```
> Real serverin loglarında işlədib öz ekran görüntünü əlavə et.

## Skriptlər necə işləyir
`ssh-ips` əslində bu boru xəttidir:
```bash
grep 'Failed password' auth.log \
  | grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' \
  | awk '{print $2}' | sort | uniq -c | sort -rn | head -n 10
```
1. `grep` yalnız uğursuz parol sətirlərini seçir
2. `grep -o` yalnız `from <IP>` hissəsini çıxarır
3. `awk` IP-ni ayırır
4. `sort | uniq -c` eyni IP-ləri sayır, `sort -rn` böyükdən kiçiyə düzür

Maraqlı detal: sshd eyni cəhd üçün həm `Invalid user ...`, həm də `Failed password for invalid user ...` sətri yazır. Yalnız ikincini saydığımız üçün cəhdlər ikiqat görünmür (test ilə yoxlanılıb).

`ssh-hourly` həm klassik syslog vaxtını (`Oct  8 03:10:01`), həm də Ubuntu 24.04-də default olan ISO 8601 vaxtını (`2026-10-08T03:10:01+04:00`) tanıyır.

## Python (Log Analyzer) ilə müqayisə
| | Bash toolkit | Python Log Analyzer |
|---|---|---|
| Quraşdırma | Heç nə lazım deyil | Python + kitabxanalar |
| Sürət (kiçik/orta log) | Çox sürətli | Sürətli |
| Mürəkkəb məntiq (sürüşən pəncərə, korrelyasiya) | Çətin | Asan |
| Testlər, struktur, genişlənmə | Məhduddur | Yaxşıdır |
| Serverdə sürətli "bir baxışda" analiz | İdeal | Orta |

Nəticə: sürətli diaqnostika üçün Bash, mürəkkəb aşkarlama və hesabat üçün Python.

## Testlər
```bash
bash tests/run_tests.sh
```
32 test: düzgün say, təmiz trafikdə yalan həyəcan olmaması, stdin/gzip dəstəyi, hər iki vaxt formatı, saxta `journalctl` ilə `journal` əmri və xəta halları. Skriptlər `shellcheck` ilə yoxlanılıb (`shellcheck logtool lib/*.sh scripts/*.sh`).

## Layihə strukturu
```
bash-log-toolkit/
├── logtool                 # giriş nöqtəsi
├── lib/common.sh           # ümumi funksiyalar (stdin/gz, yoxlamalar)
├── scripts/                # hər əmr üçün ayrıca skript
├── samples/                # nümunə auth.log, auth_iso.log, access.log
└── tests/                  # run_tests.sh + saxta journalctl/systemctl
```

## Məhdudiyyətlər
- Yalnız IPv4 tanınır (`ssh-ips`)
- `web-suspicious` regex əsaslıdır: URL-i decode etmir, yalan müsbət/mənfi mümkündür; real WAF və ya IDS əvəzi deyil
- Yalnız Apache/Nginx "combined" formatı
- `journal` tam nəticə üçün `sudo` və ya `systemd-journal` qrupu tələb edə bilər
- Ubuntu 24.04-də `/var/log/auth.log` yalnız `rsyslog` quraşdırılıbsa mövcuddur (`sudo apt install rsyslog`); əks halda `journalctl -u ssh` istifadə et

## Gələcək planlar
- [ ] IPv6 dəstəyi
- [ ] `--since/--until` ilə vaxt aralığı filtri
- [ ] CSV/JSON çıxışı (`--format`)
- [ ] `fail2ban`/`ufw` loglarının analizi

## Lisenziya
MIT
