# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20230612-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.15.4-erlang-26.0.2-debian-bullseye-20230612-slim
#

FROM ubuntu:22.04 as builder

# install build dependencies
RUN apt update -y && apt-get install -y software-properties-common
RUN apt-get update -y && apt-get install -y build-essential git curl wget \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN add-apt-repository ppa:rabbitmq/rabbitmq-erlang
RUN apt-get install -y elixir erlang-dev erlang-xmerl

# cuda bs
RUN apt update -q && apt install -y ca-certificates wget && \
    wget -qO /cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i /cuda-keyring.deb && apt update -q

ARG CUDA_VERSION=12-2

# install build dependencies
RUN apt update -y && apt-get install -y software-properties-common
RUN apt install -y git cuda-nvcc-${CUDA_VERSION} libcublas-${CUDA_VERSION} libcudnn8

# prepare build dir
WORKDIR /app
COPY / ./

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV SHELL=/bin/bash
ENV ERL_AFLAGS "-proto_dist inet6_tcp"
ENV MIX_ENV="prod"
ENV PORT="8080"
ENV XLA_TARGET="cuda120"
ENV BUMBLEBEE_CACHE_DIR="/data/cache/bumblebee"
ENV XLA_CACHE_DIR="/data/cache/xla"

# install mix dependencies
#COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
#RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
#COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

#COPY priv priv

#COPY lib lib

#COPY assets assets

# compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
#COPY config/runtime.exs config/

#COPY rel rel
RUN mix release

# Only copy the final release from the build stage
#COPY _build/${MIX_ENV}/rel/live_llm ./

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV ERL_AFLAGS "-proto_dist inet6_tcp"
ENV BUMBLEBEE_CACHE_DIR="/data/cache/bumblebee"
ENV XLA_CACHE_DIR="/data/cache/xla"

RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/_build/prod/rel/live_llm/bin/server"]
