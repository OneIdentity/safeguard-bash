FROM alpine
LABEL maintainer="support@oneidentity.com"

LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="oneidentity/safeguard-bash"
LABEL org.label-schema.description="Safeguard Bash scripting environment"
LABEL org.label-schema.url="https://github.com/OneIdentity/safeguard-bash"
LABEL org.label-schema.vcs-url="https://github.com/OneIdentity/safeguard-bash"
LABEL org.label-schema.vcs-ref=$VCS_REF
LABEL org.label-schema.vendor="One Identity LLC"
LABEL org.label-schema.version=$BUILD_VERSION
LABEL org.label-schema.docker.cmd="docker run -it oneidentity/safeguard-bash"

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

