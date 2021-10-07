# Pull base image (source and instructions on how to build at
# https://github.com/CentOS/sig-cloud-instance-build/blob/master/docker/centos-8.ks)
FROM centos:8
LABEL maintainer="brian@interlinx.bc.ca"

RUN systemd-machine-id-setup
