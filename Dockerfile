# Dockerfile for Asterisk 18.6.0 with minimal PJSIP modules

FROM debian:bullseye-slim AS builder

ARG ASTERISK_VERSION=18.6.0
ARG JQ_VERSION=1.6

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    git \
    uuid-dev \
    libedit-dev \
    libjansson-dev \
    libsqlite3-dev \
    libxml2-dev \
    libssl-dev \
    pkg-config \
    # For menuselect.makeopts manipulation
    # We need jq to modify the menuselect.makeopts file non-interactively.
    # Debian Bullseye has jq 1.6 in its repos.
    jq \
    && rm -rf /var/lib/apt/lists/*

# Download and extract Asterisk
WORKDIR /usr/src
RUN wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz && \
    tar -zxvf asterisk-${ASTERISK_VERSION}.tar.gz && \
    rm asterisk-${ASTERISK_VERSION}.tar.gz && \
    cd asterisk-${ASTERISK_VERSION} && \
    # Configure Asterisk (bundling jansson to avoid potential version issues)
    ./configure --with-jansson-bundled && \
    # Create initial menuselect.makeopts
    make menuselect.makeopts && \
    # Disable module categories for a minimal build (adjust as needed)
    # This is a common strategy for minimal builds.
    # First, disable almost everything, then enable specifics.
    # Turning off categories in menuselect.makeopts:
    # menuselect/menuselect --disable-category MENUSELECT_ADDONS .
    # menuselect/menuselect --disable-category MENUSELECT_APPS .
    # ... and so on for other categories.
    # Then enable specific modules or sub-categories.
    # For PJSIP, RTP, and core codecs:
    # General approach: Disable broad categories, then enable specific items.
    # This example focuses on disabling categories that are often large or non-essential for a basic PJSIP setup.
    # It's often easier to blacklist categories and then cherry-pick essentials.

    # Disable Addons
    sed -i 's/^MENUSELECT_ADDONS=.*$/MENUSELECT_ADDONS=/g' menuselect.makeopts && \
    # Disable most Applications (we'll add back essentials if needed via specific module enables)
    sed -i 's/^MENUSELECT_APPS=.*$/MENUSELECT_APPS=/g' menuselect.makeopts && \
    # Disable most Channel Drivers (PJSIP will be enabled specifically)
    sed -i 's/^MENUSELECT_CHANNELS=.*$/MENUSELECT_CHANNELS=/g' menuselect.makeopts && \
    # Disable MOH (Music On Hold)
    sed -i 's/^MENUSELECT_MOH=.*$/MENUSELECT_MOH=/g' menuselect.makeopts && \
    # Disable Formats (most are not needed for ulaw/alaw/gsm)
    sed -i 's/^MENUSELECT_FORMATS=.*$/MENUSELECT_FORMATS=/g' menuselect.makeopts && \
    # Disable PBX Modules (essentials will be kept)
    # sed -i 's/^MENUSELECT_PBX=.*$/MENUSELECT_PBX=/g' menuselect.makeopts && \ # Keep pbx_config etc.
    # Disable Test Modules
    sed -i 's/^MENUSELECT_TESTS=.*$/MENUSELECT_TESTS=/g' menuselect.makeopts && \

    # Enable essential modules using menuselect --enable
    # This requires a more complex interaction or manually editing menuselect.makeopts based on known module names.
    # For now, we'll rely on the default enabled essentials and the specific enables below.

    # Enable PJSIP and its dependencies
    menuselect/menuselect --enable chan_pjsip menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_authenticator_digest menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_caller_id menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_dialog_info_body_generator menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_diversion menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_endpoint_identifier_ip menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_mwi menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_notify menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_outbound_publish menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_outbound_registration menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_publish_asterisk_event menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_registrar menuselect.makeopts && \
    menuselect/menuselect --enable res_pjsip_session menuselect.makeopts && \
    # Enable RTP resource
    menuselect/menuselect --enable res_rtp_asterisk menuselect.makeopts && \
    # Enable essential codecs
    menuselect/menuselect --enable codec_alaw menuselect.makeopts && \
    menuselect/menuselect --enable codec_ulaw menuselect.makeopts && \
    menuselect/menuselect --enable codec_gsm menuselect.makeopts && \
    # Enable essential PBX components
    menuselect/menuselect --enable pbx_config menuselect.makeopts && \
    menuselect/menuselect --enable func_logic menuselect.makeopts && \
    menuselect/menuselect --enable func_strings menuselect.makeopts && \
    # Enable essential Core Sound Packages (already default usually, but good to be explicit)
    menuselect/menuselect --enable CORE-SOUNDS-EN-ULAW menuselect.makeopts && \
    menuselect/menuselect --enable CORE-SOUNDS-EN-ALAW menuselect.makeopts && \
    menuselect/menuselect --enable CORE-SOUNDS-EN-GSM menuselect.makeopts && \
    # Compile and install
    make && \
    make install && \
    # make samples # We will provide our own configs
    # make config # Not needed for docker if we manage startup
    # Reduce size by removing documentation, etc.
    rm -rf /usr/src/asterisk-${ASTERISK_VERSION}/docs && \
    rm -rf /usr/src/asterisk-${ASTERISK_VERSION}/門* && \ # Chinese docs
    rm -rf /var/lib/asterisk/static-http && \
    # Clean up .git directories if any were pulled by scripts (unlikely here)
    find /usr/src/asterisk-${ASTERISK_VERSION} -name ".git" -type d -exec rm -rf {} \;


# Create final image
FROM debian:bullseye-slim

ARG ASTERISK_USER=asterisk
ARG ASTERISK_GROUP=asterisk

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install runtime dependencies (very few needed if compiled statically, but some shared libs might be)
# libjansson4 is needed if not bundled. libxml2, libsqlite3, libedit2, libssl1.1
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libedit2 \
    libjansson4 \
    libsqlite3-0 \
    libxml2 \
    libssl1.1 \
    # Add other runtime deps if Asterisk complains, e.g. libxslt1.1, sox (for audio conversion if needed by an app)
    # For basic PJSIP, the above should be close.
    # Add curl or wget if scripts inside the container need to fetch things at runtime
    curl \
    gosu \ # For simpler user switching
    && rm -rf /var/lib/apt/lists/*

# Copy compiled Asterisk from builder stage
COPY --from=builder /usr/lib/asterisk /usr/lib/asterisk
COPY --from=builder /usr/sbin/asterisk /usr/sbin/asterisk
COPY --from=builder /usr/sbin/safe_asterisk /usr/sbin/safe_asterisk
COPY --from=builder /etc/asterisk /etc/asterisk
COPY --from=builder /var/lib/asterisk /var/lib/asterisk
COPY --from=builder /var/spool/asterisk /var/spool/asterisk
COPY --from=builder /var/log/asterisk /var/log/asterisk
COPY --from=builder /var/run/asterisk /var/run/asterisk # Will be a tmpfs mount in docker run

# Create Asterisk user and group
RUN groupadd -r ${ASTERISK_GROUP} && \
    useradd -r -g ${ASTERISK_GROUP} -d /var/lib/asterisk -s /bin/false ${ASTERISK_USER} && \
    # Fix permissions
    mkdir -p /etc/asterisk /var/log/asterisk /var/lib/asterisk/sounds /var/run/asterisk /var/spool/asterisk && \
    chown -R ${ASTERISK_USER}:${ASTERISK_GROUP} /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk /var/run/asterisk && \
    chmod -R 750 /var/spool/asterisk && \
    # Remove default configs that will be mounted from host
    rm -f /etc/asterisk/*.conf && \
    rm -rf /etc/asterisk/*.d

# Expose default ports (will be mapped to random host ports)
# PJSIP default port
EXPOSE 5060/udp
# RTP default range (adjust if your rtp.conf uses a different range internally)
EXPOSE 10000-20000/udp

# Create a simple entrypoint script
COPY <<EOF /usr/local/bin/docker-entrypoint.sh
#!/bin/bash
set -e

# If CMD is 'asterisk', then run Asterisk
if [ "$1" = 'asterisk' ]; then
    # Ensure /var/run/asterisk exists and has correct permissions
    # This is important if /var/run is not a tmpfs or gets cleared
    mkdir -p /var/run/asterisk
    chown ${ASTERISK_USER}:${ASTERISK_GROUP} /var/run/asterisk

    # Run Asterisk as the asterisk user
    # -f: foreground, -vvvg: verbose, -c: console
    # Use gosu to drop privileges
    exec gosu ${ASTERISK_USER} /usr/sbin/asterisk -f -vvvg -c
fi

# Otherwise, execute CMD
exec "$@"
EOF
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["asterisk"]

WORKDIR /var/lib/asterisk
