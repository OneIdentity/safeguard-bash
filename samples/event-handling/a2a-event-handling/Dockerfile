# This Dockerfile will create a new image based on the default safeguard-bash image
# that is found at the root of the safeguard-bash repository. The build.sh script will
# create an image called safeguard-dockerdemo based on this Dockerfile. The build.sh
# script is also called from run.sh.
FROM oneidentity/safeguard-bash:latest
MAINTAINER support@oneidentity.com

# This image adds a new script (sample_a2a_listener.sh) from this directory. This script
# contains the real functionality for what this container will do in production. In this
# case, it will call handle-a2a-password-event.sh with parameters based on some
# environment variables and call the a2a_password_event_handler.sh script from the
# samples/events/ directory that is already embedded in safeguard-bash. This handler
# script just logs out the current password each time it changes.
COPY sample_a2a_listener.sh /scripts/

# To do something interesting with a2a and this framework, you would want to add your
# own script using a COPY statement that does something important with the password.
# Then you could update sample_a2a_listener.sh to call your script.
#COPY yourscript.sh /scripts/

# When started using 'docker run', a container based on this image will start /bin/bash
# the same way that the safeguard-bash does.
ENTRYPOINT ["/bin/bash"]

# These arguments will be passed to safeguard-dockerdemo by default, but they can be
# overridden by arguments passed to 'docker run'. In this case the defaults will give
# us exactly what we need. The only reason to override would be to debug the container
# which you could do by passing '-c /bin/bash' to either docker run or run.sh.
CMD ["/scripts/sample_a2a_listener.sh"]

# When you call 'docker run' on safeguard-dockerdemo, or use the run.sh script in this
# directory, the container will check to see if it has the right environment variables
# before it tries to connect to Safeguard. You can set environment variables via the
# 'docker run' command using '-e' option or better yet (without exposing them in
# command history) using the '--env-file' option. You can use run.sh to specify arguments
# to 'docker run'.
