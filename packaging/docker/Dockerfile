FROM python:3.14.2-slim-bookworm@sha256:5b500436b051b112e0e834533a4d42a28e4a79c7a5c10f3fd44b47ba1b487995 AS web-layers
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
