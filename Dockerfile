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
        openssh \
    && rm /usr/bin/vi \
    && ln -s /usr/bin/vim /usr/bin/vi

COPY scripts/ /scripts/
COPY .bashrc /root/

ENTRYPOINT ["/bin/bash"]
CMD ["-c","exec /bin/bash --rcfile <(echo '. /root/.bashrc; /scripts/login-safeguard.sh')"]

