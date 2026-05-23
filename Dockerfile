# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ARG BUILD_JOBS=4
ARG ACORE_REPO=https://github.com/mod-playerbots/azerothcore-wotlk.git
ARG ACORE_REF=Playerbot

RUN apt-get update

RUN apt-get install -y git

RUN apt-get install -y cmake

RUN apt-get install -y make gcc g++ clang ccache

RUN apt-get install -y libmysqlclient-dev libssl-dev libbz2-dev libreadline-dev libncurses-dev libboost-all-dev

RUN apt-get install -y mysql-client p7zip-full wget curl ca-certificates

RUN rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --branch="${ACORE_REF}" "${ACORE_REPO}" .

COPY modules.lock /tmp/modules.lock
COPY scripts/clone-modules.sh /tmp/clone-modules.sh

RUN chmod +x /tmp/clone-modules.sh

RUN /tmp/clone-modules.sh /tmp/modules.lock /src/modules

RUN mkdir -p /src/build

WORKDIR /src/build

RUN cmake ../ \
    -DCMAKE_INSTALL_PREFIX=/azerothcore/env/dist \
    -DTOOLS=0 \
    -DSCRIPTS=static \
    -DMODULES=static \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

RUN --mount=type=cache,target=/root/.cache/ccache \
    make -j"${BUILD_JOBS}"

RUN make install

RUN strip /azerothcore/env/dist/bin/worldserver /azerothcore/env/dist/bin/authserver || true


FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update

RUN apt-get install -y libmysqlclient21

RUN apt-get install -y libssl3 libbz2-1.0 libreadline8t64 libncurses6

RUN apt-get install -y libboost-all-dev

RUN apt-get install -y mysql-client curl ca-certificates

RUN rm -rf /var/lib/apt/lists/*

WORKDIR /azerothcore

COPY --from=builder /azerothcore /azerothcore

COPY --from=builder /src/modules /azerothcore/modules-source

EXPOSE 3724 8085 7878

CMD ["/azerothcore/env/dist/bin/worldserver"]
