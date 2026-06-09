ARG RUNTIME_IMAGE=alpine:3.20
FROM ${RUNTIME_IMAGE}

ARG APP_USER=app
WORKDIR /app

RUN addgroup -S ${APP_USER} && adduser -S ${APP_USER} -G ${APP_USER}
COPY . /app
RUN chown -R ${APP_USER}:${APP_USER} /app

USER ${APP_USER}
CMD ["sh", "-c", "ls -la /app && sleep infinity"]
