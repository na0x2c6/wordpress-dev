ARG WP_IMAGE_TAG=latest
FROM docker.io/library/wordpress:${WP_IMAGE_TAG}

# Install mhsendmail
RUN curl -sS https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 -L -o /usr/local/bin/mhsendmail \
    && chmod +x /usr/local/bin/mhsendmail \
    && echo 'sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=127.0.0.1:1025"' > /usr/local/etc/php/conf.d/sendmail.ini
