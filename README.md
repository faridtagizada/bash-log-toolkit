# bash-log-toolkit

A set of Bash scripts for analyzing Linux logs with nothing but the standard Unix tools (`grep`, `awk`, `sed`, `sort`, `uniq`, `journalctl`). There are no extra dependencies, so it works as soon as you copy it onto an Ubuntu or Debian server.

It answers the first questions you have about a server (who is hammering SSH, what is hitting the web server) with the tools Linux already ships with.

## Commands

Everything goes through one entry point, `./logtool <command>`.

| Command | What it does |
|---|---|
| `ssh-ips [-n COUNT] FILE` | IPs with the most failed SSH attempts |
| `ssh-users [-n COUNT] FILE` | Usernames attackers try most often |
| `ssh-hourly FILE` | Failed attempts per hour, as an ASCII chart |
| `web [-n COUNT] FILE` | Access log summary: status codes, top IPs, URLs and User-Agents |
| `web-suspicious FILE` | SQL injection, path traversal, XSS, scanners and probing for sensitive files |
| `journal [-s TIME]` | Error summary from `journalctl`, failed services, SSH attempts |

`FILE` can be a plain log, a `.gz`, `.xz` or `.bz2` archive (for example `auth.log.2.gz`) or `-` for stdin. A damaged archive is an error, not an empty report.

## Install

```bash
git clone https://github.com/faridtagizada/bash-log-toolkit.git
cd bash-log-toolkit
chmod +x logtool scripts/*.sh
```

You need Bash 4+, `grep`, `awk`, `sed` and `gzip` (`xz` and `bzip2` only for those archives). The `journal` command also needs systemd.

## Usage

```bash
# with the sample logs
./logtool ssh-ips samples/auth.log
./logtool ssh-users -n 5 samples/auth.log
./logtool ssh-hourly samples/auth.log
./logtool web samples/access.log
./logtool web-suspicious samples/access.log

# on a real server
sudo ./logtool ssh-ips /var/log/auth.log
sudo ./logtool ssh-ips /var/log/auth.log.2.gz
zcat /var/log/nginx/access.log.*.gz | ./logtool web -
./logtool journal -s "6 hours ago"
```

Example output:

```
$ ./logtool ssh-ips samples/auth.log
Top 10 IPs by failed SSH attempts
ATTEMPTS  IP
      12  203.0.113.5
       5  198.51.100.7
       2  192.0.2.44

$ ./logtool ssh-hourly samples/auth.log
Failed SSH attempts by hour
...
03:00      12  ########################################
...
14:00       7  #######################
...

$ ./logtool web-suspicious samples/access.log
Suspicious activity report: samples/access.log

== SQL injection (requests: 4) ==
      4  203.0.113.5
         1 of them got a 2xx answer - look at those first

== Path traversal (requests: 3) ==
      3  198.51.100.7
...
Total matches: 20 (one request can fall into several categories)
```

On a server where password login is switched off, sshd never logs `Failed password`. `ssh-ips` then shows the connections that were turned away earlier:

```
Top 10 IPs by failed SSH attempts
ATTEMPTS  IP
  (no failed password attempts found)

Rejected before a password was tried (invalid user, or closed while authenticating)
ATTEMPTS  IP
       2  192.0.2.77
```

## How it works

The idea behind `ssh-ips` is this pipeline:

```bash
grep 'Failed password' auth.log \
  | grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' \
  | awk '{print $2}' | sort | uniq -c | sort -rn | head -n 10
```

`grep` keeps only the failed password lines, `grep -o` pulls out the `from <IP>` part, `awk` strips the word `from`, and `sort | uniq -c` counts identical IPs and `sort -rn` puts the biggest first.

Real logs need more care than that, so the three SSH commands share one `awk` parser (`ssh_failed_events` in `lib/common.sh`):

- The address is read from the end of the line. The user name is chosen by the attacker and logged as is, so a name such as `x from 10.0.0.1` would otherwise put a made-up address into the report.
- rsyslog's `message repeated 5 times: [ ... ]` counts as five more attempts.
- For a single attempt on an invalid user, sshd writes both an `Invalid user ...` line and a `Failed password for invalid user ...` line. The attempt is counted once (there is a test for this).
- IPv6 addresses are counted like IPv4 ones.

`ssh-hourly` understands both the classic syslog timestamp (`Oct  8 03:10:01`) and the ISO 8601 one that Ubuntu 24.04 uses by default (`2026-10-08T03:10:01+04:00`).

The web commands split each line by its quotes, not by blanks, so a request line of `"-"` (a timeout) or a URL with a blank in it does not shift the status code. `web-suspicious` matches the URL patterns against the request and the scanner names against the User-Agent, so `/api/unmapped` is not an `nmap` scan and a Referer with `/admin` in it is not admin probing.

## Bash or Python?

Bash needs nothing installed and is very quick for a "what's going on right now" look at a server. Python is nicer once the logic gets harder (sliding windows, correlating events), and it is easier to test and extend. So: Bash for quick diagnostics, Python for real detection and reporting.

## Tests

```bash
bash tests/run_tests.sh
```

55 tests. They check the counts, that clean traffic produces no false alarms, stdin and compressed input, both timestamp formats, forged user names, repeated messages, a key-only server, the `journal` command (against a fake `journalctl`) and the error cases. GitHub Actions runs them on every push together with `shellcheck`.

## Layout

```
bash-log-toolkit/
├── logtool                 # entry point
├── lib/common.sh           # shared functions (stdin/gz handling, validation)
├── scripts/                # one script per command
├── samples/                # sample auth.log, auth_iso.log, access.log
└── tests/                  # run_tests.sh plus fake journalctl/systemctl
```

## Limitations

- The SSH commands read OpenSSH's own messages (`Failed password`, `Invalid user`, `... authenticating user ... [preauth]`). PAM lines and `Failed publickey` are not counted.
- `web-suspicious` is regex matching. It doesn't URL-decode, so it can give false positives and false negatives, and it is no substitute for a real WAF or IDS.
- Only the Apache/Nginx "combined" format is supported.
- `journal` may need `sudo` or membership of the `systemd-journal` group to see everything.
- On Ubuntu 24.04, `/var/log/auth.log` only exists if `rsyslog` is installed (`sudo apt install rsyslog`). Without it, use `journalctl -u ssh`.

## TODO

- a time range filter (`--since` / `--until`)
- CSV and JSON output (`--format`)
- analysis of `fail2ban` and `ufw` logs

## License

MIT
