# --- STAGE 1: Builder (Construção do Frontend) ---
FROM node:16 AS builder

WORKDIR /appsmith-source

# Copia as definições de dependência do frontend
COPY app/client/package*.json app/client/
WORKDIR /appsmith-source/app/client
RUN npm install

# Copia o restante do código-fonte do frontend
COPY app/client/ .

# Constrói o frontend
RUN npm run build

# --- STAGE 2: Final Image (Imagem Final do Appsmith) ---
ARG BASE=appsmith/appsmith-ce:v1.42
FROM ${BASE}

ENV IN_DOCKER=1

ARG APPSMITH_CLOUD_SERVICES_BASE_URL
ENV APPSMITH_CLOUD_SERVICES_BASE_URL=${APPSMITH_CLOUD_SERVICES_BASE_URL}

ARG APPSMITH_SEGMENT_CE_KEY
ENV APPSMITH_SEGMENT_CE_KEY=${APPSMITH_SEGMENT_CE_KEY}

COPY deploy/docker/fs /

RUN <<END
  if ! [ -f info.json ]; then
    echo "Missing info.json" >&2
    exit 1
  fi

  if ! [ -f server/mongo/server.jar -a -f server/pg/server.jar ]; then
    echo "Missing one or both server.jar files in the right place. Are you using the build script?" >&2
    exit 1
  fi
END

# Adiciona o frontend "buildado" do estágio builder
COPY --from=builder /appsmith-source/app/client/packages/rts/dist rts/
COPY --from=builder /appsmith-source/app/client/build editor/

ENV PATH /opt/bin:/opt/java/bin:/opt/node/bin:$PATH

RUN <<END
  set -o errexit

  # Permite a execução dos scripts .sh, exceto em node_modules
  find . \( -name node_modules -prune \) -o \( -type f -name '*.sh' \) -exec chmod +x '{}' +

  # Garante permissão de execução para scripts customizados
  chmod +x /opt/bin/* /watchtower-hooks/*.sh

  # Desativa bits setuid/setgid (segurança)
  find / \( -path /proc -prune \) -o \( \( -perm -2000 -o -perm -4000 \) -exec chmod -s '{}' + \) || true

  mkdir -p /.mongodb/mongosh /appsmith-stacks
  chmod ugo+w /etc /appsmith-stacks
  chmod -R ugo+w /var/run /.mongodb /etc/ssl /usr/local/share
END

LABEL com.centurylinklabs.watchtower.lifecycle.pre-check=/watchtower-hooks/pre-check.sh
LABEL com.centurylinklabs.watchtower.lifecycle.pre-update=/watchtower-hooks/pre-update.sh

EXPOSE 80
EXPOSE 443
ENTRYPOINT [ "/opt/appsmith/entrypoint.sh" ]
HEALTHCHECK --interval=15s --timeout=15s --start-period=45s CMD "/opt/appsmith/healthcheck.sh"
CMD ["/usr/bin/supervisord", "-n"]
