# # https://blog.devops.dev/deploy-geo-restriced-service-with-nginx-geoip2-and-docker-7042fe380726
# # FROM public.ecr.aws/nginx/nginx:1.28
# # FROM public.ecr.aws/nginx/nginx-unprivileged:1.28
# ARG NGINX_VERSION=1.28.0
# FROM nginx:$NGINX_VERSION
# ARG NGINX_VERSION=1.28.0
# ARG GEOIP2_VERSION=3.4
# RUN mkdir -p /var/lib/GeoIP/
# RUN apt-get update \
#     && apt-get install -y \
#         build-essential \
#         libpcre3-dev \
#         zlib1g-dev \
#         libgeoip-dev \
#         libmaxminddb-dev \
#         wget \
#         curl \
#         git
# RUN cd /opt \
#     && git clone --depth 1 -b $GEOIP2_VERSION --single-branch https://github.com/leev/ngx_http_geoip2_module.git \
#     && wget -O - http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz | tar zxfv - \
#     && mv /opt/nginx-$NGINX_VERSION /opt/nginx \
#     && cd /opt/nginx \
#     && ./configure --with-compat --add-dynamic-module=/opt/ngx_http_geoip2_module \
#     && make modules

# FROM nginx:$NGINX_VERSION
# RUN mkdir -p /usr/share/GeoIP /etc/nginx/geoip2

# # Téléchargement sécurisé depuis MaxMind
# RUN --mount=type=secret,id=maxmind_token \
#     MAXMIND_LICENSE_KEY=$(cat /run/secrets/maxmind_token) && \
#     curl -sSLo /tmp/GeoLite2-Country.tar.gz -u ${MAXMIND_LICENSE_KEY} "https://download.maxmind.com/geoip/databases/GeoIP2-City-CSV/download?&suffix=tar.gz" \
#     && tar -xz -C /usr/share/GeoIP --strip-components=1 -f /tmp/GeoLite2-Country.tar.gz \
#     && rm /tmp/GeoLite2-Country.tar.gz

# FROM nginx:$NGINX_VERSION
# COPY --from=0 /opt/nginx/objs/ngx_http_geoip2_module.so /usr/lib/nginx/modules
# COPY --from=1 /usr/share/GeoIP /usr/share/GeoIP
# RUN apt-get update \
#     && apt-get install -y --no-install-recommends --no-install-suggests libmaxminddb0 \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/* \
#     && chmod -R 644 /usr/lib/nginx/modules/ngx_http_geoip2_module.so

FROM public.ecr.aws/nginx/nginx:1.28
COPY source/* /usr/share/nginx/html/