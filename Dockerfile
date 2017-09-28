FROM alpine

RUN apk -U --no-cache add \
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
    && ln -s /usr/bin/vim /usr/bin/vi

COPY src/ /scripts/
COPY .bashrc /root/

ENTRYPOINT ["/bin/bash"]
CMD ["-c","exec /bin/bash --rcfile <(echo '. /root/.bashrc; /scripts/connect-safeguard.sh')"]

