FROM nousresearch/hermes-agent:latest

# Skills baked into image at a path outside the data volume.
# Entrypoint copies them into /opt/data on every start,
# so pulling a new image automatically updates skills.
COPY skills/ /oya-skills/
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV HERMES_HOME=/opt/data

VOLUME ["/opt/data"]

EXPOSE 8642

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["hermes", "gateway", "start"]
