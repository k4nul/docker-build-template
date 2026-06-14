ARG RUNTIME_IMAGE=alpine:3.20
FROM ${RUNTIME_IMAGE}

ARG APP_USER=app
ARG OCI_TITLE="Example App"
ARG OCI_DESCRIPTION="Reusable Docker build template image"
ARG OCI_SOURCE="https://example.com/repository"
ARG OCI_REVISION="unknown"
ARG OCI_LICENSES="MIT"
LABEL org.opencontainers.image.title="${OCI_TITLE}" \
      org.opencontainers.image.description="${OCI_DESCRIPTION}" \
      org.opencontainers.image.source="${OCI_SOURCE}" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.licenses="${OCI_LICENSES}"

WORKDIR /app

RUN case "$APP_USER" in \
      ""|*[!A-Za-z0-9_-]*) \
        echo "APP_USER must contain only letters, numbers, underscores, or dashes" >&2; \
        exit 2; \
        ;; \
    esac && \
    addgroup -S "$APP_USER" && \
    adduser -S "$APP_USER" -G "$APP_USER"
COPY . /app
RUN chown -R "$APP_USER:$APP_USER" /app

USER ${APP_USER}
CMD ["sh", "-c", "ls -la /app && sleep infinity"]
