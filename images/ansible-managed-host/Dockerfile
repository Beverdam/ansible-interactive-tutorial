FROM ubuntu:26.04
LABEL maintainer="Beverdam"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        iputils-ping \
        netbase \
        net-tools \
        python3 \
        python3-apt \
        git \
        openssh-server \
        vim \
        sudo \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ~/.ssh && ssh-keygen -N "" -t ed25519 -f ~/.ssh/id_ed25519
COPY common/id_ed25519.pub /root/.ssh/authorized_keys
RUN chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys

COPY ["common/.vimrc", "common/.profile", "/root/"]
COPY common/start.sh /start.sh
RUN chmod +x /start.sh

WORKDIR /root
ENV ALLOW_EXIT=true
CMD ["/start.sh"]
