#
# The Alluxio Open Foundation licenses this work under the Apache License, version 2.0
# (the "License"). You may not use this work except in compliance with the License, which is
# available at www.apache.org/licenses/LICENSE-2.0
#
# This software is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
# either express or implied, as more fully set forth in the License.
#
# See the NOTICE file distributed with this work for information regarding copyright ownership.
#

# ARG defined before the first FROM can be used in FROM lines
# Only 8 and 11 are supported.
ARG JAVA_VERSION=8

# Setup CSI
FROM golang:1.15.13-alpine AS csi-dev
ENV GO111MODULE=on
RUN mkdir -p /alluxio-csi
COPY integration/docker/csi /alluxio-csi
RUN cd /alluxio-csi && \
    CGO_ENABLED=0 go build -o /usr/local/bin/alluxio-csi

# We have to do an ADD to put the tarball into extractor, then do a COPY with chown into final
# ADD then chown in two steps will double the image size
#   See - https://stackoverflow.com/questions/30085621/why-does-chown-increase-size-of-docker-image
#       - https://github.com/moby/moby/issues/5505
#       - https://github.com/moby/moby/issues/6119
# ADD with chown doesn't chown the files inside tarball
#   See - https://github.com/moby/moby/issues/35525
FROM alpine:3.10.2 AS alluxio-extractor
# Note that downloads for *-SNAPSHOT tarballs are not available.
ARG ALLUXIO_TARBALL=http://downloads.alluxio.io/downloads/files/2.9.0/alluxio-2.9.0-bin.tar.gz
# (Alert):It's not recommended to set this Argument to true, unless you know exactly what you are doing
ARG ENABLE_DYNAMIC_USER=false

ADD ${ALLUXIO_TARBALL} /opt/
# Remote tarball needs to be untarred. Local tarball is untarred automatically.
# Use ln -s instead of mv to avoid issues with Centos (see https://github.com/moby/moby/issues/27358)
RUN cd /opt && \
    (if ls | grep -q ".tar.gz"; then tar -xzf *.tar.gz && rm *.tar.gz; fi) && \
    ln -s alluxio-* alluxio

RUN if [ ${ENABLE_DYNAMIC_USER} = "true" ] ; then \
       chmod -R 777 /opt/* ; \
    fi

# Configure Java
FROM centos:7 as build_java8

RUN sed -i 's|mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-* \
    && sed -i 's|#baseurl=http://mirror.centos.org|baseurl=https://vault.centos.org|g' /etc/yum.repos.d/CentOS-* \
    && yum clean all && yum makecache

RUN \
    yum update -y && yum upgrade -y && \
    yum install -y java-1.8.0-openjdk-devel java-1.8.0-openjdk && \
    yum clean all
ENV JAVA_HOME /usr/lib/jvm/java-1.8.0-openjdk
# Disable JVM DNS cache in java8 (https://github.com/Alluxio/alluxio/pull/9452)
RUN echo "networkaddress.cache.ttl=0" >> /usr/lib/jvm/java-1.8.0-openjdk/jre/lib/security/java.security

FROM centos:7 as build_java11

RUN sed -i 's|mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-* \
    && sed -i 's|#baseurl=http://mirror.centos.org|baseurl=https://vault.centos.org|g' /etc/yum.repos.d/CentOS-* \
    && yum clean all && yum makecache

RUN \
    yum update -y && yum upgrade -y && \
    yum install -y java-11-openjdk-devel java-11-openjdk && \
    yum clean all
ENV JAVA_HOME /usr/lib/jvm/java-11-openjdk
# Disable JVM DNS cache in java11 (https://github.com/Alluxio/alluxio/pull/9452)
RUN echo "networkaddress.cache.ttl=0" >> /usr/lib/jvm/java-11-openjdk/conf/security/java.security

FROM build_java${JAVA_VERSION} AS runtime

WORKDIR /

# Install libfuse2 and libfuse3. Libfuse2 setup is modified from cheyang/fuse2:ubuntu1604-customize to be applied on centOS
RUN \
    yum install -y ca-certificates pkgconfig wget udev git && \
    yum install -y gcc gcc-c++ make cmake gettext-devel libtool autoconf && \
    git clone https://github.com/Alluxio/libfuse.git && \
    cd libfuse && \
    git checkout fuse_2_9_5_customize_multi_threads && \
    bash makeconf.sh && \
    ./configure && \
    make -j8 && \
    make install && \
    cd .. && \
    rm -rf libfuse && \
    yum install -y fuse3 fuse3-devel fuse3-lib && \
    yum clean all

# Configuration for the modified libfuse2
ENV MAX_IDLE_THREADS "64"

# /lib64 is for rocksdb native libraries, /usr/local/lib is for libfuse2 native libraries
ENV LD_LIBRARY_PATH "/lib64:/usr/local/lib:${LD_LIBRARY_PATH}"

ARG ALLUXIO_USERNAME=alluxio
ARG ALLUXIO_GROUP=alluxio
ARG ALLUXIO_UID=1000
ARG ALLUXIO_GID=1000

# For dev image to know the user
ENV ALLUXIO_DEV_UID=${ALLUXIO_UID}

ARG ENABLE_DYNAMIC_USER=true

# Add Tini for Alluxio helm charts (https://github.com/Alluxio/alluxio/pull/12233)
# - https://github.com/krallin/tini
ENV TINI_VERSION v0.18.0
ARG TARGETARCH
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-${TARGETARCH} /usr/local/bin/tini
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) TINI_SHA256=eadb9d6e2dc960655481d78a92d2c8bc021861045987ccd3e27c7eae5af0cf33 ;; \
      arm64) TINI_SHA256=ce3f642d73d58d7c8d745e65b5a9b5de7040fbfa1f7bee2f6207bb28207d8ca1 ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    echo "${TINI_SHA256}  /usr/local/bin/tini" | sha256sum -c -; \
    chmod +x /usr/local/bin/tini

# If Alluxio user, group, gid, and uid aren't root|0, create the alluxio user and set file permissions accordingly
RUN if [ ${ALLUXIO_USERNAME} != "root" ] \
    && [ ${ALLUXIO_GROUP} != "root" ] \
    && [ ${ALLUXIO_UID} -ne 0 ] \
    && [ ${ALLUXIO_GID} -ne 0 ]; then \
      groupadd --gid ${ALLUXIO_GID} ${ALLUXIO_GROUP} && \
      useradd --system -m --uid ${ALLUXIO_UID} --gid ${ALLUXIO_GROUP} ${ALLUXIO_USERNAME} && \
      usermod -a -G root ${ALLUXIO_USERNAME} && \
      mkdir -p /journal && \
      chown -R ${ALLUXIO_UID}:${ALLUXIO_GID} /journal && \
      chmod -R g=u /journal && \
      mkdir /mnt/alluxio-fuse && \
      chown -R ${ALLUXIO_UID}:${ALLUXIO_GID} /mnt/alluxio-fuse; \
    fi

# Docker 19.03+ required to expand variables in --chown argument
# https://github.com/moby/buildkit/pull/926#issuecomment-503943557
COPY --from=alluxio-extractor --chown=${ALLUXIO_USERNAME}:${ALLUXIO_GROUP} /opt /opt/
COPY --chown=${ALLUXIO_USERNAME}:${ALLUXIO_GROUP} integration/docker/conf /opt/alluxio/conf/
COPY --chown=${ALLUXIO_USERNAME}:${ALLUXIO_GROUP} integration/docker/entrypoint.sh /
COPY --from=csi-dev /usr/local/bin/alluxio-csi /usr/local/bin/
COPY integration/jnifuse/native/src/main/native/libjnifuse /tmp/jnifuse-src
COPY integration/docker/scripts/install-jni-fuse-libs.sh /usr/local/bin/install-jni-fuse-libs

# Compile JNI FUSE native libraries from source for multi-arch support
# The pre-compiled libraries in the tarball are x86-64 only
RUN set -eux; \
    yum install -y fuse-devel fuse3-devel; \
    mkdir -p /tmp/jnifuse-out; \
    make -f /tmp/jnifuse-src/Makefile \
      SRC_DIR=/tmp/jnifuse-src \
      OUTPUT_DIR=/tmp/jnifuse-out; \
    FUSE_JAR="$(find /opt/alluxio/integration/fuse -maxdepth 1 \
      -name 'alluxio-fuse-*.jar' -print -quit)"; \
    test -n "${FUSE_JAR}"; \
    chmod +x /usr/local/bin/install-jni-fuse-libs; \
    /usr/local/bin/install-jni-fuse-libs \
      "${TARGETARCH}" /tmp/jnifuse-out "${FUSE_JAR}" /usr/local/lib; \
    ldconfig; \
    ! ldd /usr/local/lib/libjnifuse.so | grep -q 'not found'; \
    ! ldd /usr/local/lib/libjnifuse3.so | grep -q 'not found'; \
    rm -rf /tmp/jnifuse-src /tmp/jnifuse-out; \
    rm -f /usr/local/bin/install-jni-fuse-libs; \
    yum remove -y gcc-c++ make fuse-devel fuse3-devel; \
    yum clean all

RUN if [ ${ENABLE_DYNAMIC_USER} = "true" ] ; then \
       chmod -R 777 /journal; \
       chmod -R 777 /mnt; \
       # Enable user_allow_other option for fuse in non-root mode
       echo "user_allow_other" >> /etc/fuse.conf; \
    fi

USER ${ALLUXIO_UID}

WORKDIR /opt/alluxio

ENV PATH="/opt/alluxio/bin:${PATH}"

ENTRYPOINT ["/entrypoint.sh"]

# Development image. Keep all tools from the historical Dockerfile-dev while inheriting the
# architecture-correct runtime, CSI binary, tini binary, and JNI FUSE libraries above.
FROM runtime AS dev

USER root

ARG JAVA_VERSION=8
ARG TARGETARCH
ARG ASYNC_PROFILER_VERSION=2.9
ARG ASYNC_PROFILER_DOWNLOAD_BASE=https://github.com/async-profiler/async-profiler/releases/download

RUN set -eux; \
    yum install -y \
      java-11-openjdk-devel java-11-openjdk \
      ca-certificates pkgconfig wget udev git gcc gcc-c++ make cmake \
      gettext-devel libtool autoconf unzip vim fuse-devel fuse3-devel; \
    yum clean all; \
    ln -sfn /usr/lib/jvm/java-1.8.0-openjdk /usr/lib/jvm/java-8-openjdk

ENV JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk

RUN echo "networkaddress.cache.ttl=0" >> \
      /usr/lib/jvm/java-11-openjdk/conf/security/java.security

ARG ARTHAS_VERSION=3.4.6
RUN set -eux; \
    wget -qO /tmp/arthas.zip \
      "https://github.com/alibaba/arthas/releases/download/arthas-all-${ARTHAS_VERSION}/arthas-bin.zip"; \
    mkdir -p /opt/arthas; \
    unzip /tmp/arthas.zip -d /opt/arthas; \
    rm -f /tmp/arthas.zip

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) ASYNC_PROFILER_ARCH=x64; ASYNC_PROFILER_SHA256=b9a094bc480f233f72141b7793c098800054438e0e6cfe5b7f2fe13ef4ad11f0 ;; \
      arm64) ASYNC_PROFILER_ARCH=arm64; ASYNC_PROFILER_SHA256=00c91439b2fc95fa518e47570c451d92c8670c0cd68d908ee53397bb35a42779 ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    wget -qO /tmp/async-profiler.tar.gz \
      "${ASYNC_PROFILER_DOWNLOAD_BASE}/v${ASYNC_PROFILER_VERSION}/async-profiler-${ASYNC_PROFILER_VERSION}-linux-${ASYNC_PROFILER_ARCH}.tar.gz"; \
    echo "${ASYNC_PROFILER_SHA256}  /tmp/async-profiler.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/async-profiler.tar.gz -C /opt; \
    mv "/opt/async-profiler-${ASYNC_PROFILER_VERSION}-linux-${ASYNC_PROFILER_ARCH}" \
      /opt/async-profiler; \
    test -x /opt/async-profiler/profiler.sh; \
    rm -f /tmp/async-profiler.tar.gz

USER ${ALLUXIO_DEV_UID}

# Keep the production image as the default target for existing build commands.
FROM runtime AS final
