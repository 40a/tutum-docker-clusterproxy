FROM ubuntu:latest
MAINTAINER Bernardo Pericacho <bernardo@tutum.co>

# Install required packages
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y haproxy supervisor python-pip

# Add configuration and scripts
ADD haproxy.cfg /etc/haproxy/haproxy.cfg
ADD haproxy.cfg.json /etc/haproxy/empty_haproxy.cfg.json
ADD haproxy.cfg.json /etc/haproxy/haproxy.cfg.json
ADD requirements.txt /requirements.txt
ADD supervisord-balancer.conf /etc/supervisor/conf.d/supervisord-balancer.conf
ADD main.py /main.py
ADD run.sh /run.sh
RUN chmod 755 /*.sh
RUN pip install -r /requirements.txt

EXPOSE 80
CMD ["/run.sh"]