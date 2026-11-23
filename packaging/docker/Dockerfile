FROM python:3.14.2-slim-bookworm@sha256:e87711ef5c86aaeaa7031718a69db79d334d94c545c709583f651b8185870941 AS web-layers
COPY build/web/ /web/
COPY packaging/docker/prepare_web_layers.py /prepare_web_layers.py
COPY packaging/docker/default.conf.template /default.conf.template
RUN python /prepare_web_layers.py /web /layers /default.conf.template

FROM nginx:1.28-alpine@sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236
ENV APP_SERVICE_UPSTREAM=http://192.168.1.55:18280
ENV NGINX_ENVSUBST_FILTER="^APP_SERVICE_UPSTREAM$"
COPY --link --from=web-layers /layers/nginx/ /
COPY --link --from=web-layers /layers/engine/ /
COPY --link --from=web-layers /layers/fonts/ /
COPY --link --from=web-layers /layers/media/ /
COPY --link --from=web-layers /layers/app/ /
COPY --link --from=web-layers /layers/etag/ /
EXPOSE 8080
