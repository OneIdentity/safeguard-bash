FROM alpine
MAINTAINER support@oneidentity.com

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

