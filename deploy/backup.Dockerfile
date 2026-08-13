FROM postgres:16-alpine

RUN apk add --no-cache age aws-cli tzdata

COPY deploy/backup.sh /usr/local/bin/backup.sh
COPY deploy/verify-backup.sh /usr/local/bin/verify-backup.sh
COPY deploy/configure-storage.sh /usr/local/bin/configure-storage.sh
COPY deploy/image-lifecycle.json /usr/local/share/muto/image-lifecycle.json

RUN chmod 0755 /usr/local/bin/backup.sh /usr/local/bin/verify-backup.sh \
    /usr/local/bin/configure-storage.sh

CMD ["sh", "-c", "echo '17 2 * * * /usr/local/bin/backup.sh' | crontab - && crond -f -l 2"]
