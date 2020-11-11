FROM alpine
LABEL maintainer="support@oneidentity.com" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.name="oneidentity/safeguard-bash" \
      org.label-schema.description="Safeguard Bash scripting environment" \
      org.label-schema.url="https://github.com/OneIdentity/safeguard-bash" \
      org.label-schema.vcs-url="https://github.com/OneIdentity/safeguard-bash" \
      org.label-schema.vcs-ref=$APPVEYOR_REPO_COMMIT \
      org.label-schema.vendor="One Identity LLC" \
      org.label-schema.version=$APPVEYOR_BUILD_VERSION \
      org.label-schema.docker.cmd="docker run -it oneidentity/safeguard-bash"

RUN apk -U --no-cache add \
        shadow \
        vim \
        curl \
        jq \
        grep \
        sed \
        coreutils \
        util-linux \
        bash \
        openssl \
        openssh \
    && rm /usr/bin/vi \
    && ln -s /usr/bin/vim /usr/bin/vi \
    && groupadd -r safeguard \
    && useradd -r -g safeguard -s /bin/bash safeguard \
    && mkdir -p /home/safeguard \
    && chown -R safeguard:safeguard /home/safeguard

COPY src/ /scripts/
COPY samples/ /samples/
COPY test/ /test/
COPY .bashrc /home/safeguard/

USER safeguard
WORKDIR /home/safeguard

ENTRYPOINT ["/bin/bash"]
CMD ["-c","exec /bin/bash --rcfile <(echo '. /home/safeguard/.bashrc; /scripts/connect-safeguard.sh')"]

