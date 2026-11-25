# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0


FROM docker.io/library/ruby:4.0.5-alpine3.22@sha256:fae3127404cb61d6897d7eed08e65ec7ccc96ba0542dc7c44712efa9b2ef78f0 AS builder

COPY ./src/email/Gemfile Gemfile
COPY ./src/email/Gemfile.lock Gemfile.lock

RUN apk update && \
    apk add make gcc musl-dev gcompat && \
    bundle install

FROM docker.io/library/ruby:4.0.5-alpine3.22@sha256:fae3127404cb61d6897d7eed08e65ec7ccc96ba0542dc7c44712efa9b2ef78f0

COPY --from=builder /usr/local/bundle/ /usr/local/bundle/

WORKDIR /email_server

COPY ./src/email/views/ views/

COPY ./src/email/Gemfile Gemfile
COPY ./src/email/Gemfile.lock Gemfile.lock
COPY ./src/email/email_server.rb email_server.rb

ARG EMAIL_PORT=6060
EXPOSE ${EMAIL_PORT}
# Run as a non-root user. If the container is ever broken into, the attacker
# is not root inside it. Matches runAsUser in the Helm chart.
ENV HOME=/tmp
USER 10001

ENTRYPOINT ["bundle", "exec", "ruby", "email_server.rb"]
