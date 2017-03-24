# VERSION 0.5
# AUTHOR:         Olav Grønås Gjerde <olav@backupbay.com>
# DESCRIPTION:    Image with MoinMoin wiki, uwsgi, nginx and self signed SSL
# TO_BUILD:       docker build -t moinmoin .
# TO_RUN:         docker run -it -p 80:80 -p 443:443 --name my_wiki moinmoin

FROM debian:jessie
MAINTAINER Olav Grønås Gjerde <olav@backupbay.com>

# Set the version you want of MoinMoin
ENV MM_VERSION 1.9.9
ENV MM_CSUM 4397d7760b7ae324d7914ffeb1a9eeb15e09933b61468072acd3c3870351efa4

# Install software
RUN apt-get update && apt-get install -qqy --no-install-recommends \
  python \
  curl \
  openssl \
  nginx \
  uwsgi \
  uwsgi-plugin-python \
  rsyslog

# Download MoinMoin
RUN curl -Ok \
  https://bitbucket.org/thomaswaldmann/moin-1.9/get/$MM_VERSION.tar.gz
RUN if [ "$MM_CSUM" != "$(sha1sum $MM_VERSION.tar.gz | awk '{print($1)}')" ];\
  then exit 1; fi;
RUN mkdir moinmoin
RUN tar xf $MM_VERSION.tar.gz -C moinmoin --strip-components=1

# Install MoinMoin
RUN cd moinmoin && python setup.py install --force --prefix=/usr/local
ADD wikiconfig.py /usr/local/share/moin/
RUN mkdir /usr/local/share/moin/underlay
RUN chown -Rh www-data:www-data /usr/local/share/moin/underlay
# Because of a permission error with chown I change the user here
# This is related to an known permission issue with Docker and AUFS
# https://github.com/docker/docker/issues/1295
USER www-data
RUN cd /usr/local/share/moin/ && tar xf underlay.tar -C underlay --strip-components=1
USER root
RUN chown -R www-data:www-data /usr/local/share/moin/data
ADD logo.png /usr/local/lib/python2.7/dist-packages/MoinMoin/web/static/htdocs/common/

# Configure nginx
ADD nginx.conf /etc/nginx/
ADD moinmoin.conf /etc/nginx/sites-available/
RUN mkdir -p /var/cache/nginx/cache
RUN ln -s /etc/nginx/sites-available/moinmoin.conf \
  /etc/nginx/sites-enabled/moinmoin.conf
RUN rm /etc/nginx/sites-enabled/default

# Create self signed certificate
ADD generate_ssl_key.sh /usr/local/bin/
RUN /usr/local/bin/generate_ssl_key.sh moinmoin.example.org
RUN mv cert.pem /etc/ssl/certs/
RUN mv key.pem /etc/ssl/private/

# Cleanup
RUN rm $MM_VERSION.tar.gz
RUN rm -rf /moinmoin
RUN rm /usr/local/share/moin/underlay.tar
RUN apt-get purge -qqy curl
RUN apt-get autoremove -qqy && apt-get clean
RUN rm -rf /tmp/* /var/lib/apt/lists/*

VOLUME /usr/local/share/moin/data

EXPOSE 80
EXPOSE 443

CMD service rsyslog start && service nginx start && \
  uwsgi --uid www-data \
    -s /tmp/uwsgi.sock \
    --plugins python \
    --pidfile /var/run/uwsgi-moinmoin.pid \
    --wsgi-file server/moin.wsgi \
    -M -p 4 \
    --chdir /usr/local/share/moin \
    --python-path /usr/local/share/moin \
    --harakiri 30 \
    --die-on-term
