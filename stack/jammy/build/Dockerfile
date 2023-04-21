FROM ubuntu:jammy

ARG sources='deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy main restricted universe multiverse \n deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy-updates main restricted universe multiverse \n deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse'
ARG packages='base-files build-essential ca-certificates libc6 libssl3 netbase openssl tzdata zlib1g-dev git curl'
ARG package_args='--allow-downgrades --allow-remove-essential --allow-change-held-packages --no-install-recommends'
ENV CNB_USER_ID=1000
ENV CNB_GROUP_ID=1000
ENV CNB_STACK_ID=io.paketo.stacks.tiny
LABEL io.buildpacks.stack.id=io.paketo.stacks.tiny

RUN groupadd cnb --gid ${CNB_GROUP_ID} && \
  useradd --uid ${CNB_USER_ID} --gid ${CNB_GROUP_ID} -m -s /bin/bash cnb && \
  echo "$sources" > /etc/apt/sources.list && \
  echo "Package: $packages\nPin: release c=multiverse\nPin-Priority: -1\n\nPackage: $packages\nPin: release c=restricted\nPin-Priority: -1\n" > /etc/apt/preferences

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
