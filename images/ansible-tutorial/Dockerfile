FROM turkenh/nutsh:v2.0.0

# Pinned versions (Alpine 3.21 package index at the time of writing) for
# reproducible builds -- the old `apk add --no-cache ansible` pulled
# whatever Ansible was current on each rebuild, which is how content
# written against pre-2.9 Ansible (`when: foo|failed`, since fixed) ended
# up silently incompatible with a modern ansible-core.
RUN apk add --no-cache \
      ansible=11.1.0-r0 \
      ansible-core=2.18.1-r0 \
      openssh \
      fping \
      curl \
      git

WORKDIR /root

RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh && mkdir /etc/ansible

COPY common/ansible.cfg /etc/ansible/ansible.cfg

COPY ["common/id_ed25519", "common/id_ed25519.pub", "/root/.ssh/"]
COPY ["common/.vimrc", "common/.profile", "/root/"]

RUN chmod 644 /root/.ssh/id_ed25519.pub && chmod 600 /root/.ssh/id_ed25519

ENTRYPOINT ["nutsh", "run", "/tutorials"]
