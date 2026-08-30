#!/bin/sh
# =============================================================================
#  FTP entrypoint - creates the FTP account, then execs vsftpd as PID 1.
# =============================================================================
set -eu

FTP_PASSWORD="$(cat /run/secrets/ftp_password)"
FTP_ROOT=/var/www/html

# vsftpd refuses users whose shell is not in /etc/shells.
grep -qx /usr/sbin/nologin /etc/shells || echo /usr/sbin/nologin >> /etc/shells

WWW_UID="$(id -u www-data)"
WWW_GID="$(id -g www-data)"

if ! id "$FTP_USER" >/dev/null 2>&1; then
    echo "[ftp] creating user ${FTP_USER} (uid ${WWW_UID}, gid ${WWW_GID})"
    # The account deliberately shares www-data's uid (-o allows a duplicate
    # uid). The WordPress volume is owned by www-data with 0755 permissions, so
    # sharing only the *group* would give read-only access and every upload
    # would fail; sharing the uid makes the FTP user the owner of the website
    # files, which is exactly what an FTP account on this volume is for.
    useradd -M -o -u "$WWW_UID" -g "$WWW_GID" \
            -d "$FTP_ROOT" -s /usr/sbin/nologin "$FTP_USER"
fi

echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
echo "$FTP_USER" > /etc/vsftpd.userlist

echo "[ftp] serving ${FTP_ROOT} as ${FTP_USER}, starting vsftpd as PID 1"
exec "$@"
