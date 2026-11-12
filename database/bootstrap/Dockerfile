FROM scratch

ARG VCS_REF

LABEL org.opencontainers.image.title="Emporio B2B PostgreSQL roles bootstrap" \
      org.opencontainers.image.description="Transport-only package for the canonical Infra roles bootstrap SQL" \
      org.opencontainers.image.source="https://github.com/EmporioB2B/Infra" \
      org.opencontainers.image.revision="${VCS_REF}"

COPY roles.sql /bootstrap/roles.sql

# This image is an artifact container and must not be run as a service.
CMD ["/bootstrap/roles.sql"]
