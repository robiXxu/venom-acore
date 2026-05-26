# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV CCACHE_DIR=/root/.cache/ccache
ENV CCACHE_MAXSIZE=2G

ARG BUILD_JOBS=2
ARG ACORE_REPO=https://github.com/mod-playerbots/azerothcore-wotlk.git
ARG ACORE_REF=Playerbot

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      git \
      cmake \
      make \
      gcc \
      g++ \
      clang \
      ccache \
      libmysqlclient-dev \
      libssl-dev \
      libbz2-dev \
      libreadline-dev \
      libncurses-dev \
      libboost-all-dev \
      mysql-client \
      p7zip-full \
      curl \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --branch="${ACORE_REF}" --depth=1 "${ACORE_REPO}" .

COPY modules.lock /tmp/modules.lock
COPY scripts/clone-modules.sh /tmp/clone-modules.sh

RUN chmod +x /tmp/clone-modules.sh \
    && /tmp/clone-modules.sh /tmp/modules.lock /src/modules \
    && mkdir -p /src/build

WORKDIR /src/build

RUN --mount=type=cache,target=/root/.cache/ccache \
    cmake ../ \
      -DCMAKE_INSTALL_PREFIX=/azerothcore/env/dist \
      -DTOOLS=1 \
      -DSCRIPTS=static \
      -DMODULES=static \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

RUN --mount=type=cache,target=/root/.cache/ccache \
    if [ "${BUILD_JOBS}" = "auto" ]; then \
      make -j"$(nproc)"; \
    else \
      make -j"${BUILD_JOBS}"; \
    fi

RUN make install

# Copy all module config templates into the standard AzerothCore module config dir.
# Then create active .conf files from .conf.dist without overwriting existing files.
RUN set -eu; \
    mkdir -p /azerothcore/env/dist/etc/modules; \
    find /src/modules -path "*/conf/*.conf.dist" -type f -exec cp -vn {} /azerothcore/env/dist/etc/modules/ \; ; \
    find /azerothcore/env/dist/etc/modules -name "*.conf.dist" -type f -exec sh -c 'cp -n "$1" "${1%.dist}"' _ {} \;

RUN strip /azerothcore/env/dist/bin/worldserver /azerothcore/env/dist/bin/authserver || true


FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      libmysqlclient21 \
      libssl3 \
      libbz2-1.0 \
      libreadline8t64 \
      libncurses6 \
      libboost-filesystem1.83.0 \
      libboost-iostreams1.83.0 \
      libboost-program-options1.83.0 \
      libboost-system1.83.0 \
      libboost-thread1.83.0 \
      libboost-regex1.83.0 \
      mysql-client \
      curl \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --system --create-home --home-dir /azerothcore --shell /usr/sbin/nologin acore

WORKDIR /azerothcore

COPY --from=builder --chown=acore:acore /azerothcore /azerothcore
COPY --from=builder --chown=acore:acore /src/data/sql /src/data/sql
COPY --from=builder --chown=acore:acore /src/modules /src/modules
COPY --from=builder --chown=acore:acore /tmp/modules.lock /tmp/modules.lock

# Verify every module from modules.lock exists in /src/modules.
RUN set -eu; \
    while IFS='|' read -r name repo ref; do \
      [ -z "$name" ] && continue; \
      case "$name" in \#*) continue ;; esac; \
      test -d "/src/modules/$name"; \
    done < /tmp/modules.lock

# Optional build log visibility: list module configs and SQL files.
# Keep this while debugging; remove later if you want quieter builds.
RUN set -eu; \
    while IFS='|' read -r name repo ref; do \
      [ -z "$name" ] && continue; \
      case "$name" in \#*) continue ;; esac; \
      echo "== $name =="; \
      if [ -d "/src/modules/$name/conf" ]; then \
        find "/src/modules/$name/conf" -type f -name "*.conf.dist" | sort; \
      else \
        echo "No conf dir"; \
      fi; \
      if [ -d "/src/modules/$name/data/sql" ]; then \
        find "/src/modules/$name/data/sql" -type f -name "*.sql" | sort; \
      else \
        echo "No data/sql dir"; \
      fi; \
    done < /tmp/modules.lock

RUN mkdir -p /azerothcore/env/dist/logs /azerothcore/env/dist/temp

RUN cp -n /azerothcore/env/dist/etc/authserver.conf.dist /azerothcore/env/dist/etc/authserver.conf
RUN cp -n /azerothcore/env/dist/etc/worldserver.conf.dist /azerothcore/env/dist/etc/worldserver.conf

# Ensure active module config files exist for every installed .conf.dist.
RUN find /azerothcore/env/dist/etc/modules -name "*.conf.dist" -type f -exec sh -c 'cp -n "$1" "${1%.dist}"' _ {} \;

RUN chown -R acore:acore \
      /azerothcore/env/dist/etc \
      /azerothcore/env/dist/logs \
      /azerothcore/env/dist/temp

RUN /azerothcore/env/dist/bin/authserver --version
RUN /azerothcore/env/dist/bin/worldserver --version

RUN ldd /azerothcore/env/dist/bin/worldserver | grep "not found" && exit 1 || true
RUN ldd /azerothcore/env/dist/bin/authserver | grep "not found" && exit 1 || true

RUN su -s /bin/sh acore -c "/azerothcore/env/dist/bin/authserver --version"
RUN su -s /bin/sh acore -c "/azerothcore/env/dist/bin/worldserver --version"

EXPOSE 3724 8085 7878

USER acore

CMD ["/azerothcore/env/dist/bin/worldserver"]
