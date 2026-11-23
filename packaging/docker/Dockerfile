FROM nginx:1.28-alpine@sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236
ENV APP_SERVICE_UPSTREAM=http://192.168.1.55:18280
COPY build/web/ /usr/share/nginx/html/
COPY packaging/docker/default.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 8080
