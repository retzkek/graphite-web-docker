FROM docker.io/library/alpine:3.19 as base

RUN true \
 && apk add --no-cache \
      cairo \
      findutils \
      librrd \
      memcached \
      py3-pyldap \
      redis \
      runit \
      sqlite \
      expect \
      py3-mysqlclient \
      mysql-dev \
      mysql-client \
      postgresql-dev \
      postgresql-client

FROM base as build

ARG python_binary=python3
ARG python_extra_flags="--single-version-externally-managed --root=/"
ENV PYTHONDONTWRITEBYTECODE=1

RUN true \
 && apk add --update \
      alpine-sdk \
      git \
      libffi-dev \
      pkgconfig \
      openldap-dev \
      python3-dev \
      rrdtool-dev \
      wget \
 && $python_binary -m venv /opt/graphite \
 && . /opt/graphite/bin/activate \
 && pip install \
      django~=3.2

ARG version=1.1.10

# install graphite
ARG graphite_version=${version}
ARG graphite_repo=https://github.com/graphite-project/graphite-web.git
RUN . /opt/graphite/bin/activate \
 && git clone -b ${graphite_version} --depth 1 ${graphite_repo} /usr/local/src/graphite-web \
 && cd /usr/local/src/graphite-web \
 && pip3 install -r requirements.txt \
 && $python_binary ./setup.py install --prefix=/opt/graphite --install-lib=/opt/graphite/webapp $python_extra_flags

# config graphite
ADD local_settings.py /opt/graphite/webapp/graphite/local_settings.py
ADD graphite_wsgi.py /opt/graphite/conf
WORKDIR /opt/graphite/webapp
RUN mkdir -p /var/log/graphite/ \
  && PYTHONPATH=/opt/graphite/webapp /opt/graphite/bin/django-admin collectstatic --noinput --settings=graphite.settings

FROM base as production

COPY --from=build /opt /opt

ADD run.sh /run.sh
ADD local_settings.py /opt/graphite/webapp/graphite
ADD graphite_wsgi.py /opt/graphite/conf

RUN mkdir -p /data/graphite/conf && \
    mkdir -p /data/graphite/storage/whisper && \
    mkdir -p /data/graphite/storage/log/webapp && \
    mkdir -p /var/log/graphite && \
    touch /data/graphite/storage/index && \
    chmod 0775 /data/graphite/storage /data/graphite/storage/whisper && \
    chmod +x /run.sh

# Expose Port
EXPOSE 8000

VOLUME ["/data/graphite"]

ENV PYTHONPATH=/opt/graphite/webapp
ENV GRAPHITE_STORAGE_DIR /data/graphite/storage
ENV GRAPHITE_CONF_DIR /data/graphite/conf

STOPSIGNAL SIGTERM

CMD  ["/run.sh"]
