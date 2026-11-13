# bash-log-toolkit

A set of Bash scripts for analyzing Linux logs with nothing but the standard Unix tools (`grep`, `awk`, `sed`, `sort`, `uniq`, `journalctl`). There are no extra dependencies, so it works as soon as you copy it onto an Ubuntu or Debian server.

It looks at SSH attacks and web traffic using only the tools Linux already ships with.

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

`FILE` can be a plain log, a `.gz` archive (for example `auth.log.2.gz`) or `-` for stdin.

## Install

```bash
git clone https://github.com/faridtagizada/bash-log-toolkit.git
cd bash-log-toolkit
chmod +x logtool scripts/*.sh
```

You need Bash 4+, `grep`, `awk`, `sed` and `gzip`. The `journal` command also needs systemd.

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

== Path traversal (requests: 3) ==
      3  198.51.100.7
...
Total matches: 20 (one request can fall into several categories)
```

## How it works

`ssh-ips` is really just this pipeline:

```bash
grep 'Failed password' auth.log \
  | sed -nE 's/.* from ([^ ]+) port [0-9]+.*/\1/p' \
  | sort | uniq -c | sort -rn | head -n 10
```

`grep` keeps only the failed password lines, `sed` pulls out the address after the last `from` (IPv4 or IPv6), `sort | uniq -c` counts identical IPs and `sort -rn` puts the biggest first. The address is taken after the *last* `from` because sshd writes the username first, and an attacker can try a username like `x from 8.8.8.8 port 1`.

One detail worth knowing: for a single attempt on an invalid user, sshd writes both an `Invalid user ...` line and a `Failed password for invalid user ...` line. Only the second one is counted, otherwise every attempt would show up twice (there is a test for this).

Another one: when the same line repeats, rsyslog (on by default in Ubuntu) writes `message repeated 2 times: [ Failed password ...]` instead. That line stands for two more attempts, so the SSH commands expand it before counting.

`ssh-hourly` understands both the classic syslog timestamp (`Oct  8 03:10:01`) and the ISO 8601 one that Ubuntu 24.04 uses by default (`2026-10-08T03:10:01+04:00`).

## Bash or Python?

Bash needs nothing installed and is very quick for a "what's going on right now" look at a server. Python is nicer once the logic gets harder (sliding windows, correlating events), and it is easier to test and extend. So: Bash for quick diagnostics, Python for real detection and reporting.

## Tests

```bash
bash tests/run_tests.sh
```

39 tests. They check the counts, that clean traffic produces no false alarms (also with a Referer like `/admin/` or a Google search for `union select`), stdin and gzip input, both timestamp formats, rsyslog's `message repeated` lines, IPv6 addresses, the `journal` command (against a fake `journalctl`) and the error cases. The scripts were also run through `shellcheck` (`shellcheck logtool lib/*.sh scripts/*.sh`).

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

- `web-suspicious` is regex matching on the request line (and the User-Agent for scanners). It doesn't URL-decode and doesn't look at the Referer, so it can give false positives and false negatives, and it is no substitute for a real WAF or IDS.
- Only the Apache/Nginx "combined" format is supported.
- `journal` may need `sudo` or membership of the `systemd-journal` group to see everything.
- On Ubuntu 24.04, `/var/log/auth.log` only exists if `rsyslog` is installed (`sudo apt install rsyslog`). Without it, use `journalctl -u ssh`.

## TODO

- a time range filter (`--since` / `--until`)
- CSV and JSON output (`--format`)
- analysis of `fail2ban` and `ufw` logs

## License

MIT
