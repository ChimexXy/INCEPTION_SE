# =============================================================================
#  BONUS - vsftpd, FTP access to the WordPress website volume
# =============================================================================
FROM debian:bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends vsftpd \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/vsftpd/empty

COPY conf/ftp.conf /etc/vsftpd.conf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 21 = control channel, 21000-21010 = passive data channels.
EXPOSE 21 21000-21010

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["vsftpd", "/etc/vsftpd.conf"]
