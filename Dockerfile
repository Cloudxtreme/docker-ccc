FROM centos:6
MAINTAINER javier.ramon@gmail.com

ENV CC_DIR /var/lib/cc
ENV CC_COREOS_VERSIONS stable beta alpha
ENV CC_SERVERNAME cc-server
ENV CC_SERVERDOMAIN cc.local
ENV CC_DNS1 8.8.8.8
ENV CC_DNS2 8.8.4.4

# Automatically detect server ip data by default (use with docker run option: --net host)
# for explicit ip data use format: A.B.C.D/NN
ENV CC_SERVERIPDATA /

RUN yum install -y \
	dnsmasq \
	openssh \
	syslinux-nonlinux \
	uuid \
	wget \
	which

COPY etc/sysconfig/cc /etc/sysconfig/
COPY etc/dnsmasq.conf /etc/dnsmasq.conf.base

COPY usr/local/bin/cc_node /usr/local/bin/
COPY usr/local/bin/cc_nodes /usr/local/bin/

RUN chmod a+x /usr/local/bin/*

EXPOSE 53
EXPOSE 69

COPY entrypoint.sh /
COPY cloud-init.yml.default.template /

VOLUME ${CC_DIR}
WORKDIR ${CC_DIR}

CMD [ "/entrypoint.sh" ]

