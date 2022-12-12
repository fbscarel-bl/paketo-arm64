## For the Base image (both build & run)
FROM ubuntu:focal as base

ARG STACK_ID

ENV CNB_USER_ID=1000
ENV CNB_GROUP_ID=1000
ENV CNB_STACK_ID=${STACK_ID}
LABEL io.buildpacks.stack.id=${STACK_ID}

RUN groupadd cnb --gid ${CNB_GROUP_ID} && \
  useradd --uid ${CNB_USER_ID} --gid ${CNB_GROUP_ID} -m -s /bin/bash cnb

FROM base as build

ARG sources
ARG packages
ARG package_args='--allow-downgrades --allow-remove-essential --allow-change-held-packages --no-install-recommends'

RUN echo "$sources" > /etc/apt/sources.list
RUN echo "Package: $packages\nPin: release c=multiverse\nPin-Priority: -1\n\nPackage: $packages\nPin: release c=restricted\nPin-Priority: -1\n" > /etc/apt/preferences

RUN echo "debconf debconf/frontend select noninteractive" | debconf-set-selections && \
  export DEBIAN_FRONTEND=noninteractive && \
  apt-get -y $package_args update && \
  apt-get -y $package_args upgrade && \
  apt-get -y $package_args install locales && \
  locale-gen en_US.UTF-8 && \
  update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
  apt-get -y $package_args install $packages && \
  rm -rf /var/lib/apt/lists/* /tmp/* /etc/apt/preferences

RUN for path in /workspace /workspace/source-ws /workspace/source; do git config --system --add safe.directory "${path}"; done

RUN curl -sSfL -o /usr/local/bin/yj https://github.com/sclevine/yj/releases/latest/download/yj-linux-amd64 \
  && chmod +x /usr/local/bin/yj

FROM ubuntu:bionic AS builder

ARG packages

RUN apt-get update && \
  apt-get install -y xz-utils binutils zstd

ADD install-certs.sh .

ADD files/passwd /tiny/etc/passwd
ADD files/nsswitch.conf /tiny/etc/nsswitch.conf
ADD files/group /tiny/etc/group

RUN mkdir -p /tiny/tmp /tiny/var/lib/dpkg/status.d/

# This creates a nonroot user, which is present on Google's distroless image
RUN mkdir -p /tiny/home/nonroot \
    && chown 65532:65532 /tiny/home/nonroot

RUN echo "Package: $packages\nPin: release c=multiverse\nPin-Priority: -1\n\nPackage: $packages\nPin: release c=restricted\nPin-Priority: -1\n" > /etc/apt/preferences

# We can't use dpkg -i (even with --instdir=/tiny) because we don't want to
# install the dependencies, and dpkg-deb has no way to ignore all dependencies;
# each dependency must be explicitly listed
RUN apt download $packages \
    && for pkg in $packages; do \
      dpkg-deb --field $pkg*.deb > /tiny/var/lib/dpkg/status.d/$pkg \
      && dpkg-deb --extract $pkg*.deb /tiny; \
    done

RUN ./install-certs.sh

RUN find /tiny/usr/share/doc/*/* ! -name copyright | xargs rm -rf && \
  rm -rf \
    /tiny/etc/update-motd.d/* \
    /tiny/usr/share/man/* \
    /tiny/usr/share/lintian/*

ADD files/os-release /tmp/etc/os-release

RUN grep -v 'PRETTY_NAME=' "/tiny/etc/os-release" \
      | grep -v 'HOME_URL=' \
      | grep -v 'SUPPORT_URL=' \
      | grep -v 'BUG_REPORT_URL=' \
      | tee /tmp/etc/os-release-upstream \
    && rm /tiny/etc/os-release \
    && cat /tmp/etc/os-release-upstream /tmp/etc/os-release \
      | tee /tiny/etc/os-release

# Distroless images use /var/lib/dpkg/status.d/<file> instead of /var/lib/dpkg/status
RUN rm -rf /tiny/var/lib/dpkg/status

FROM scratch
COPY --from=builder /tiny/ /
