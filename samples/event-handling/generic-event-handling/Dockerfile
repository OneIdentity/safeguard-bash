# This Dockerfile will create a new image based on the default safeguard-bash image
# that is found at the root of the safeguard-bash repository. The build.sh script will
# create an image called safeguard-eventdemo based on this Dockerfile. The build.sh
# script is also called from run.sh.
FROM oneidentity/safeguard-bash:latest
MAINTAINER support@oneidentity.com

# This image adds a new script (certificate-login.sh) from this directory. This script
# contains the real functionality for what this container will do in production. In this
# case, it simply run through the sample code in certificate-login.sh using bootstrap
# admin.
COPY generic-event-handler.sh /scripts/
COPY sample-event-listener.sh /scripts/

# When started using 'docker run', a container based on this image will start /bin/bash
# the same way that the safeguard-bash does.
ENTRYPOINT ["/bin/bash"]

# These arguments will be passed to safeguard-certdemo by default, but they can be
# overridden by arguments passed to 'docker run'. In this case the defaults will give
# us exactly what we need. The only reason to override would be to debug the container
# which you could do by passing '-c /bin/bash' to either docker run or run.sh.
CMD ["/scripts/sample-event-listener.sh"]
