# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV CCACHE_DIR=/root/.cache/ccache
ENV CCACHE_MAXSIZE=5G

ARG BUILD_JOBS=4
ARG ACORE_REPO=https://github.com/mod-playerbots/azerothcore-wotlk.git
ARG ACORE_REF=Playerbot

# RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
#     apt-get update && apt-get install -y --no-install-recommends \
#       git \
#       cmake \
#       make \
#       gcc \
#       g++ \
#       clang \
#       ccache \
#       libmysqlclient-dev \
#       libssl-dev \
#       libbz2-dev \
#       libreadline-dev \
#       libncurses-dev \
#       libboost-all-dev \
#       mysql-client \
#       p7zip-full \
#       wget \
#       curl \
#       ca-certificates \
#     && rm -rf /var/lib/apt/lists/*
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      git \
      cmake \
      make \
      gcc \
      g++ \
      clang \
      ccache \
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
    make -j"${BUILD_JOBS}"

RUN make install

RUN strip \
      /azerothcore/env/dist/bin/worldserver \
      /azerothcore/env/dist/bin/authserver \
      /azerothcore/env/dist/bin/dbimport \
    || true


FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      libmysqlclient21 \
      libssl3 \
      libbz2-1.0 \
      libreadline8t64 \
      libncurses6 \
      libboost-all-dev \
      mysql-client \
      curl \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --system --create-home --home-dir /azerothcore --shell /usr/sbin/nologin acore

WORKDIR /azerothcore

COPY --from=builder --chown=acore:acore /azerothcore /azerothcore
COPY --from=builder --chown=acore:acore /src/data/sql /src/data/sql
COPY --from=builder --chown=acore:acore /src/modules /src/modules

RUN test -d /src/modules/mod-playerbots/data/sql/playerbots/base
RUN test -f /src/modules/mod-playerbots/data/sql/playerbots/base/playerbots_account_keys.sql
RUN test -f /src/modules/mod-ah-bot/data/sql/db-world/mod_auctionhousebot.sql

RUN mkdir -p /azerothcore/env/dist/logs /azerothcore/env/dist/temp

RUN cp /azerothcore/env/dist/etc/authserver.conf.dist /azerothcore/env/dist/etc/authserver.conf
RUN cp /azerothcore/env/dist/etc/worldserver.conf.dist /azerothcore/env/dist/etc/worldserver.conf

RUN cp /azerothcore/env/dist/etc/modules/AutoBalance.conf.dist /azerothcore/env/dist/etc/modules/AutoBalance.conf
RUN cp /azerothcore/env/dist/etc/modules/mod_ahbot.conf.dist /azerothcore/env/dist/etc/modules/mod_ahbot.conf
RUN cp /azerothcore/env/dist/etc/modules/playerbots.conf.dist /azerothcore/env/dist/etc/modules/playerbots.conf
RUN cp /azerothcore/env/dist/etc/modules/SoloLfg.conf.dist /azerothcore/env/dist/etc/modules/SoloLfg.conf
RUN cp /azerothcore/env/dist/etc/modules/transmog.conf.dist /azerothcore/env/dist/etc/modules/transmog.conf

RUN chown -R acore:acore /azerothcore/env/dist/etc /azerothcore/env/dist/logs /azerothcore/env/dist/temp


RUN /azerothcore/env/dist/bin/authserver --version
RUN /azerothcore/env/dist/bin/worldserver --version

RUN ldd /azerothcore/env/dist/bin/worldserver | grep "not found" && exit 1 || true
RUN ldd /azerothcore/env/dist/bin/authserver | grep "not found" && exit 1 || true
# RUN test -x /azerothcore/env/dist/bin/dbimport
RUN su -s /bin/sh acore -c "/azerothcore/env/dist/bin/authserver --version"
RUN su -s /bin/sh acore -c "/azerothcore/env/dist/bin/worldserver --version"

EXPOSE 3724 8085 7878

USER acore

CMD ["/azerothcore/env/dist/bin/worldserver"]
