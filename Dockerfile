FROM centos:6
MAINTAINER javier.ramon@gmail.com
ENV LC_ALL en_US.UTF-8

ENV CCC_DIR /var/lib/ccc
ENV CCC_COREOS_VERSIONS stable beta alpha
ENV CCC_SERVERNAME ccc-server
ENV CCC_SERVERDOMAIN ccc.local
ENV CCC_DNS1 8.8.8.8
ENV CCC_DNS2 8.8.4.4

# Automatically detect server ip data by default (use with docker run option: --net host)
# for explicit ip data use format: A.B.C.D/NN
ENV CCC_SERVERIPDATA /

RUN yum install -y \
	dnsmasq \
	openssh \
	openssh-clients \
	syslinux-nonlinux \
	uuid \
	wget \
	which

COPY etc/sysconfig/ccc /etc/sysconfig/
COPY etc/dnsmasq.conf /etc/dnsmasq.conf.base

COPY usr/local/bin/ccc_node /usr/local/bin/
COPY usr/local/bin/ccc_nodes /usr/local/bin/

RUN chmod a+x /usr/local/bin/*

EXPOSE 53
EXPOSE 69

COPY entrypoint.sh /
COPY cloud-init.yml.default.template /

VOLUME ${CCC_DIR}
WORKDIR ${CCC_DIR}

CMD [ "/entrypoint.sh" ]

