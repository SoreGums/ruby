ARG BASE_IMAGE_TAG

FROM soregums/base-ruby:${BASE_IMAGE_TAG}

ARG RUBY_DEV

ARG WODBY_USER_ID=1000
ARG WODBY_GROUP_ID=1000

ENV RUBY_DEV="${RUBY_DEV}" \
    SSHD_PERMIT_USER_ENV="yes"

ENV APP_ROOT="/usr/src/app" \
    CONF_DIR="/usr/src/conf" \
    FILES_DIR="/mnt/files" \
    SSHD_HOST_KEYS_DIR="/etc/ssh" \
    ENV="/home/wodby/.shrc" \
    \
    GIT_USER_EMAIL="wodby@example.com" \
    GIT_USER_NAME="wodby" \
    \
    RAILS_ENV="development"

RUN set -xe; \
    \
    # Delete existing user/group if uid/gid occupied.
    existing_group=$(getent group "${WODBY_GROUP_ID}" | cut -d: -f1); \
    if [[ -n "${existing_group}" ]]; then delgroup "${existing_group}"; fi; \
    existing_user=$(getent passwd "${WODBY_USER_ID}" | cut -d: -f1); \
    if [[ -n "${existing_user}" ]]; then deluser "${existing_user}"; fi; \
    \
	addgroup --gid "${WODBY_GROUP_ID}" --system wodby; \
	adduser --uid "${WODBY_USER_ID}" --disabled-password --system --shell /bin/bash --gid "${WODBY_GROUP_ID}" wodby; \
	sed -i '/^wodby/s/!/*/' /etc/shadow; \
    \
    apt-get update; \
    # slim is too slim, make some diredctories for postgresql-client
    # https://github.com/dalibo/temboard/issues/211#issuecomment-342205157
    mkdir -p /usr/share/man/man1; \
    mkdir -p /usr/share/man/man7; \
    apt-get install -y --no-install-recommends \
        postgresql-client; \
	apt-get install -y --no-install-recommends \
        libfreetype6 \
        git \
        curl \
        wget \
        libgmp10 \
        libicu57 \
        # Too big, removed
        #imagemagick \
        libjpeg62-turbo \
        libjpeg-turbo-progs \
        libldap-2.4-2 \
        libmemcached11 \
        libpng16-16 \
        librdkafka1 \
        libxslt1.1 \
        make \
        mariadb-client-10.1 \
        nano \
        openssh-server \
        librabbitmq4 \
        sqlite3 \
        sudo \
        tig \
        tmux \
        libyaml-0-2; \
    \
    if [ -n "${RUBY_DEV}" ]; then \
        apt-get install -y --no-install-recommends \
            gnupg \
            build-essential \
            libffi-dev \
            linux-headers-amd64 \
            # Too big, removed
            #libmagickwand-dev \
            libpq-dev \
            libsqlite3-dev \
            libmariadbd-dev; \
        # nodejs 10.x, npm, yarn
        curl -sL https://deb.nodesource.com/setup_10.x | bash -; \
        curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -; \
        echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list; \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            nodejs \
            yarn; \
        # su-exec
        git clone https://github.com/ncopa/su-exec.git; \
        cd su-exec; \
        make; \
        mv su-exec /sbin/su-exec; \
        cd ..; \
        rm -Rf su-exec; \
    else \
        # su-exec
        apt-get install -y --no-install-recommends \
            make \
            gcc; \
        git clone https://github.com/ncopa/su-exec.git; \
        cd su-exec; \
        make; \
        mv su-exec /sbin/su-exec; \
        cd ..; \
        rm -Rf su-exec; \
        apt-get purge -y \
            make \
            gcc; \
    fi; \
    # Install redis-cli.
    apt-get install -y --no-install-recommends redis-tools; \
    mv /usr/bin/redis-cli /tmp/; \
    apt purge -y redis-tools; \
    mv /tmp/redis-cli /usr/bin; \
    \
    install -o wodby -g wodby -d \
        "${APP_ROOT}" \
        "${CONF_DIR}" \
        "${FILES_DIR}/public" \
        "${FILES_DIR}/private" \
        /home/wodby/.ssh; \
    \
    { \
        echo 'export PS1="\u@${WODBY_APP_NAME:-ruby}.${WODBY_ENVIRONMENT_NAME:-container}:\w $ "'; \
        echo "export PATH=${PATH}"; \
    } | tee /home/wodby/.shrc; \
    cp /home/wodby/.shrc /home/wodby/.bashrc; \
    cp /home/wodby/.shrc /home/wodby/.bash_profile; \
    \
    # Configure sudoers
    { \
        echo 'Defaults env_keep += "APP_ROOT FILES_DIR"' ; \
        \
        if [ -n "${RUBY_DEV}" ]; then \
            echo 'wodby ALL=(root) NOPASSWD:SETENV:ALL'; \
        else \
            echo -n 'wodby ALL=(root) NOPASSWD:SETENV: ' ; \
            echo -n '/usr/local/bin/gen_ssh_keys, ' ; \
            echo -n '/usr/local/bin/init_container, ' ; \
            echo -n '/usr/sbin/sshd, ' ; \
            echo '/usr/sbin/crond' ; \
        fi; \
    } | tee /etc/sudoers.d/wodby; \
    \
    # Configure ldap
    mkdir /etc/openldap; \
    echo "TLS_CACERTDIR /etc/ssl/certs/" >> /etc/openldap/ldap.conf; \
    \
    touch \
        /etc/ssh/sshd_config \
        /usr/local/etc/unicorn.rb \
        /usr/local/etc/puma.rb \
        /etc/init.d/unicorn; \
    \
    chown wodby:wodby \
        /etc/ssh/sshd_config \
        /usr/local/etc/unicorn.rb \
        /usr/local/etc/puma.rb \
        /etc/init.d/unicorn \
        /home/wodby/.*; \
    \
    # gotpl
    gotpl_url="https://github.com/wodby/gotpl/releases/download/0.1.5/gotpl-linux-amd64-0.1.5.tar.gz"; \
    wget -qO- "${gotpl_url}" | tar xz -C /usr/local/bin; \
    \
    apt-get autoremove -y; \
    apt-get autoclean; \
    rm -rf /var/lib/apt/lists/*;

USER wodby

WORKDIR ${APP_ROOT}
EXPOSE 8000

COPY templates /etc/gotpl/
COPY docker-entrypoint.sh /
COPY bin /usr/local/bin/

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["puma", "-C", "/usr/local/etc/puma.rb"]
