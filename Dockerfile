# ============================================================
# BASE IMAGE: Rocky Linux 9
# WHY: Rocky Linux 9 is a community enterprise OS, binary-compatible
# with RHEL 9. It replaces CentOS. It has long-term support,
# security patches, and is widely used in enterprise environments.
# ============================================================
FROM rockylinux:9

# ============================================================
# LABELS
# WHY: Labels are metadata attached to the image. They help with
# image management, auditing, and tooling (e.g., Renovate bot
# reads org.opencontainers labels to auto-update image versions).
# ============================================================
LABEL org.opencontainers.image.title="Apache Karaf"
LABEL org.opencontainers.image.version="4.2.16"
LABEL org.opencontainers.image.base.name="rockylinux:9"
LABEL maintainer="devops-team@company.com"

# ============================================================
# ENVIRONMENT VARIABLES - set early so all subsequent RUN steps
# can use them and they are baked into the image layers.
# ============================================================

# JAVA_HOME: standard variable that tells Java-based tools where JRE lives
ENV JAVA_HOME=/usr/lib/jvm/jre-11-openjdk

# KARAF_VERSION: centralise the version so you only update ONE place
ENV KARAF_VERSION=4.2.16

# KARAF_HOME: the directory where Karaf is installed
ENV KARAF_HOME=/opt/karaf

# PATH: prepend both Java and Karaf bin dirs so `java`, `karaf`
# commands work without full paths inside the container
ENV PATH=$JAVA_HOME/bin:$KARAF_HOME/bin:$PATH

# ============================================================
# INSTALL JRE 11
# WHY: Karaf 4.2.16 runs on Java 8-11. JRE (not JDK) is used
# because we only RUN Java apps, not compile them — smaller image.
#
# --nodocs      → skips installing man pages/docs → smaller image
# --setopt=install_weak_deps=0 → skips optional dependencies → smaller image
# && dnf clean all → removes dnf cache → reduces image layer size
# rm -rf /var/cache/dnf → removes residual cache files
# ============================================================
RUN dnf install -y \
      java-11-openjdk-headless \
      wget \
      tar \
      --nodocs \
      --setopt=install_weak_deps=0 \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# ============================================================
# DOWNLOAD & INSTALL APACHE KARAF 4.2.16
# WHY: wget fetches the official Apache tarball. We verify with
# sha512 checksum (SECURITY BEST PRACTICE) to ensure the binary
# was not tampered with during download.
# ============================================================
RUN wget -q https://downloads.apache.org/karaf/${KARAF_VERSION}/apache-karaf-${KARAF_VERSION}.tar.gz \
         -O /tmp/karaf.tar.gz \
    # Download the official checksum file from Apache
    && wget -q https://downloads.apache.org/karaf/${KARAF_VERSION}/apache-karaf-${KARAF_VERSION}.tar.gz.sha512 \
         -O /tmp/karaf.tar.gz.sha512 \
    # Verify checksum — exits non-zero (build FAILS) if tampered
    && sha512sum -c /tmp/karaf.tar.gz.sha512 \
    # Extract to /opt/
    && tar -xzf /tmp/karaf.tar.gz -C /opt/ \
    # Rename to a clean, version-independent directory name
    && mv /opt/apache-karaf-${KARAF_VERSION} /opt/karaf \
    # Remove the tarball — we don't need it in the final image
    && rm /tmp/karaf.tar.gz /tmp/karaf.tar.gz.sha512

# ============================================================
# CREATE A DEDICATED NON-ROOT USER  ← SECURITY BEST PRACTICE
# WHY: Running as root inside a container is dangerous. If an
# attacker exploits the app, they'd have root access on the node.
# A dedicated system user (-r = system, no login shell, no home).
# -s /sbin/nologin → cannot login interactively (extra security)
# ============================================================
RUN groupadd -r karaf && \
    useradd -r \
            -g karaf \
            -d /opt/karaf \
            -s /sbin/nologin \
            -c "Karaf service account" \
            karaf

# ============================================================
# SET OWNERSHIP
# WHY: The karaf user must own its own directory to read configs,
# write logs, and run. We give ownership BEFORE switching user.
# ============================================================
RUN chown -R karaf:karaf /opt/karaf

# ============================================================
# SWITCH TO NON-ROOT USER  ← SECURITY BEST PRACTICE
# WHY: All subsequent instructions and the final CMD/ENTRYPOINT
# run as this user — not root. This is the container equivalent
# of the principle of least privilege.
# ============================================================
USER karaf

# ============================================================
# WORKDIR
# WHY: Sets the working directory for CMD and ENTRYPOINT.
# Using WORKDIR is cleaner than `cd` in CMD because it creates
# the directory if missing and is explicit in `docker inspect`.
# ============================================================
WORKDIR /opt/karaf

# ============================================================
# EXPOSE PORTS
# WHY: Documentation for which ports the container listens on.
# 8181 → Karaf HTTP/HTTPS (web console)
# 1099 → Karaf RMI Registry
# 44444 → Karaf RMI Server
# NOTE: EXPOSE alone does NOT publish ports — that's done by
# -p in docker run or containerPort in Kubernetes.
# ============================================================
EXPOSE 8181 1099 44444

# ============================================================
# HEALTHCHECK
# WHY: Docker (and Kubernetes liveness probes) use this to
# determine if the container is healthy. If unhealthy,
# Kubernetes will restart the pod automatically.
# ============================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8181/system/console || exit 1

# ============================================================
# ENTRYPOINT + CMD PATTERN  ← BEST PRACTICE
# ENTRYPOINT: sets the binary that always runs (cannot be overridden without --entrypoint)
# CMD: default arguments — can be overridden at runtime
# Together: `docker run <image> client` would run `karaf client`
# ============================================================
ENTRYPOINT ["/opt/karaf/bin/karaf"]
CMD ["server"]