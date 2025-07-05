#!/bin/bash

# Script to manage Dockerized Asterisk instances with random ports

set -eo pipefail # Exit on error, treat unset variables as an error, and propagate pipeline failures

# --- Configuration ---
readonly IMAGE_NAME="asterisk-randomport"
readonly IMAGE_TAG="18.6"
readonly FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOCKERFILE_PATH="${SCRIPT_DIR}/Dockerfile"
readonly CONFIG_TEMPLATE_DIR="${SCRIPT_DIR}" # Assuming templates are in the same dir

# --- Logging and Utility Functions ---
log() {
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

error_exit() {
    echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1" >&2
    exit 1
}

# --- Docker Image Management ---

# Check if the Docker image exists locally
check_docker_image() {
    log "Checking for Docker image: ${FULL_IMAGE_NAME}..."
    if docker image inspect "${FULL_IMAGE_NAME}" &> /dev/null; then
        log "Docker image ${FULL_IMAGE_NAME} found."
        return 0 # True, image exists
    else
        log "Docker image ${FULL_IMAGE_NAME} not found."
        return 1 # False, image does not exist
    fi
}

# Build the Asterisk Docker image
build_asterisk_image() {
    log "Building Asterisk Docker image: ${FULL_IMAGE_NAME}..."
    if [ ! -f "${DOCKERFILE_PATH}" ]; then
        error_exit "Dockerfile not found at ${DOCKERFILE_PATH}"
    fi

    # The Dockerfile uses ARG ASTERISK_VERSION, we can pass it here if needed,
    # but it's also defined in the Dockerfile itself.
    # For consistency, ensure ASTERISK_VERSION in Dockerfile matches IMAGE_TAG if used.
    if docker build -t "${FULL_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" "${SCRIPT_DIR}" --build-arg ASTERISK_VERSION=${IMAGE_TAG%.*}.0; then # Assuming IMAGE_TAG is like 18.6
        log "Successfully built Docker image: ${FULL_IMAGE_NAME}"
    else
        error_exit "Failed to build Docker image: ${FULL_IMAGE_NAME}. Check Docker build output for details."
    fi
}


# --- Main Script Logic (Initial) ---
main() {
    log "Starting Dockerized Asterisk Management Script..."

    # Ensure Docker is installed and running
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed. Please install Docker and try again."
    fi
    if ! docker info &> /dev/null; then
        error_exit "Docker daemon does not seem to be running."
    fi


    # Check if image exists, build if not
    if ! check_docker_image; then
        log "Attempting to build the image as it was not found."
        build_asterisk_image
    fi

    # Placeholder for further actions (will be expanded in next steps)
    log "Script setup and image check complete."
    log "Next steps: Implement port generation and container launching."
    echo
    # echo "Usage: $0 create  # (More commands to be added)"
    # echo

    # --- Test port generation and config generation (temporary) ---
    # local sip_port rtp_start_port rtp_end_port instance_id temp_config_dir
    # instance_id=$(uuidgen | cut -d'-' -f1) # Short UUID for instance ID
    # sip_port=$(generate_random_port 40000 45000 "udp")
    # rtp_start_port=$(generate_random_port 45001 55000 "udp") # Ensure RTP range doesn't overlap SIP initially
    # rtp_end_port=$((rtp_start_port + 200)) # Example RTP range size
    #
    # log "Generated SIP Port: ${sip_port}"
    # log "Generated RTP Start Port: ${rtp_start_port}"
    # log "Generated RTP End Port: ${rtp_end_port}"
    #
    # temp_config_dir=$(generate_asterisk_configs "${instance_id}" "${sip_port}" "${rtp_start_port}" "${rtp_end_port}")
    # if [ -n "${temp_config_dir}" ]; then
    #     log "Configs generated in: ${temp_config_dir}"
    #     log "Contents of pjsip.conf:"
    #     cat "${temp_config_dir}/pjsip.conf"
    #     log "Contents of rtp.conf:"
    #     cat "${temp_config_dir}/rtp.conf"
    #     # rm -rf "${temp_config_dir}" # Clean up test configs
    # else
    #     error_exit "Failed to generate configs for testing."
    # fi
    # --- End Test ---

    # Actual command parsing will go here
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 <command> [options]"
        echo "Commands:"
        echo "  create    Create and start a new Asterisk instance."
        # echo "  list      List running Asterisk instances."
        # echo "  stop <id> Stop an Asterisk instance."
        # echo "  start <id> Start a stopped Asterisk instance."
        # echo "  logs <id> View logs of an Asterisk instance."
        # echo "  destroy <id> Stop and remove an Asterisk instance."
        exit 1
    fi

    local command="$1"
    shift

    case "${command}" in
        "build")
            build_asterisk_image
            ;;
        "create")
            launch_new_instance
            ;;
        *)
            error_exit "Unknown command: ${command}"
            ;;
    esac

}

# --- Port Ranges and Instance Configuration ---
readonly HOST_SIP_PORT_MIN=40000
readonly HOST_SIP_PORT_MAX=45000
readonly HOST_RTP_PORT_MIN=45001
# Max start port for RTP range on HOST. Container RTP range is fixed.
readonly HOST_RTP_PORT_MAX=55000
readonly RTP_RANGE_SIZE=200      # Number of ports in the RTP range

# Define Asterisk internal container ports (these are fixed)
readonly CONTAINER_SIP_PORT=5060
readonly CONTAINER_RTP_START_PORT=10000
readonly CONTAINER_RTP_END_PORT=$((CONTAINER_RTP_START_PORT + RTP_RANGE_SIZE - 1))


# Directory to keep track of instance temporary config directories for cleanup
TEMP_CONFIG_DIRS_TO_CLEAN=()
cleanup_temp_dirs() {
    if [ ${#TEMP_CONFIG_DIRS_TO_CLEAN[@]} -gt 0 ]; then
        log "Cleaning up temporary configuration directories..."
        for dir in "${TEMP_CONFIG_DIRS_TO_CLEAN[@]}"; do
            if [ -d "$dir" ]; then
                log "Removing $dir"
                rm -rf "$dir"
            fi
        done
    fi
}
trap cleanup_temp_dirs EXIT


# --- Port Management ---

# Check if a port is available (not in use by TCP or UDP)
# Uses ss if available, otherwise falls back to netstat
is_port_available() {
    local port_to_check="$1"
    local protocol="$2" # "tcp" or "udp" or "both"

    if command -v ss &>/dev/null; then
        # Check with ss (more modern)
        # -l: listening sockets, -n: numeric ports, -p: processes, -u: udp, -t: tcp, -a: all
        if [[ "$protocol" == "udp" ]]; then
            ss -lunp | awk '{print $5}' | grep -q ":${port_to_check}$"
        elif [[ "$protocol" == "tcp" ]]; then
            ss -ltnp | awk '{print $4}' | grep -q ":${port_to_check}$"
        else # both
            ss -ltunp | awk '{print $5}' | grep -q ":${port_to_check}$"
        fi
    elif command -v netstat &>/dev/null; then
        # Check with netstat (older, but more widely available)
        # -l: listening, -n: numeric, -u: udp, -t: tcp, -p: programs (requires sudo often for pid)
        if [[ "$protocol" == "udp" ]]; then
            netstat -lunp 2>/dev/null | awk '{print $4}' | grep -q ":${port_to_check}$"
        elif [[ "$protocol" == "tcp" ]]; then
            netstat -ltnp 2>/dev/null | awk '{print $4}' | grep -q ":${port_to_check}$"
        else # both
            netstat -ltunp 2>/dev/null | awk '{print $4}' | grep -q ":${port_to_check}$"
        fi
    else
        log "Warning: Neither 'ss' nor 'netstat' found. Cannot reliably check port availability. Assuming port is available."
        return 0 # Assume available if tools are missing
    fi

    if [ $? -eq 0 ]; then
        return 1 # Port is in use
    else
        return 0 # Port is available
    fi
}

# Generate a random port within a given range, ensuring it's not in use.
# Usage: generate_random_port <min_port> <max_port> <protocol>
generate_random_port() {
    local min_port=$1
    local max_port=$2
    local protocol=${3:-"udp"} # Default to udp if not specified
    local random_port
    local attempts=0
    local max_attempts=20

    while [ $attempts -lt $max_attempts ]; do
        random_port=$(shuf -i "${min_port}-${max_port}" -n 1)
        if is_port_available "${random_port}" "${protocol}"; then
            echo "${random_port}"
            return 0
        fi
        attempts=$((attempts + 1))
    done

    error_exit "Failed to find an available random port in range ${min_port}-${max_port} for ${protocol} after ${max_attempts} attempts."
    return 1
}

# --- Asterisk Configuration Generation ---

# Generate Asterisk configuration files for an instance
# Usage: generate_asterisk_configs <instance_id> <sip_port> <rtp_start> <rtp_end>
# Returns the path to the temporary directory containing the generated configs.
generate_asterisk_configs() {
    local instance_id="$1"
    local sip_port="$2"
    local rtp_start="$3"
    local rtp_end="$4"

    local temp_dir
    temp_dir=$(mktemp -d -t asterisk_config_"${instance_id}"_XXXXXX)
    if [ ! -d "$temp_dir" ]; then
        error_exit "Failed to create temporary directory for Asterisk configs."
    fi

    log "Generating configs for instance ${instance_id} in ${temp_dir}..."

    # Check for template files
    for tpl in pjsip.conf.tpl rtp.conf.tpl extensions.conf.tpl; do
        if [ ! -f "${CONFIG_TEMPLATE_DIR}/${tpl}" ]; then
            rm -rf "${temp_dir}" # Clean up before exiting
            error_exit "Configuration template ${CONFIG_TEMPLATE_DIR}/${tpl} not found."
        fi
    done

    # Process pjsip.conf
    sed -e "s/__SIP_PORT__/${sip_port}/g" \
        -e "s/__INSTANCE_ID__/${instance_id}/g" \
        "${CONFIG_TEMPLATE_DIR}/pjsip.conf.tpl" > "${temp_dir}/pjsip.conf"

    # Process rtp.conf
    sed -e "s/__RTP_START__/${rtp_start}/g" \
        -e "s/__RTP_END__/${rtp_end}/g" \
        "${CONFIG_TEMPLATE_DIR}/rtp.conf.tpl" > "${temp_dir}/rtp.conf"

    # Process extensions.conf
    sed -e "s/__INSTANCE_ID__/${instance_id}/g" \
        "${CONFIG_TEMPLATE_DIR}/extensions.conf.tpl" > "${temp_dir}/extensions.conf"

    # Copy any other .conf files that don't need templating (if any)
    # For example, if you had a static modules.conf or logger.conf
    # cp "${CONFIG_TEMPLATE_DIR}/modules.conf" "${temp_dir}/modules.conf" 2>/dev/null || true

    log "Successfully generated Asterisk configuration files in ${temp_dir}"
    echo "${temp_dir}" # Return the path to the config directory
}


# --- Docker Container Management ---

# Launch a new Asterisk instance
launch_new_instance() {
    log "Attempting to launch a new Asterisk instance..."

    local instance_id
    instance_id=$(uuidgen | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]') # short, lowercase uuid

    local host_sip_port
    local host_rtp_start_port
    local host_rtp_end_port
    local temp_config_dir
    local container_name

    container_name="asterisk-instance-${instance_id}"

    # Generate ports
    log "Generating random ports for instance ${instance_id}..."
    host_sip_port=$(generate_random_port "${HOST_SIP_PORT_MIN}" "${HOST_SIP_PORT_MAX}" "udp")
    # Ensure RTP start port allows for the full range without exceeding max_port or common ephemeral ranges
    local max_rtp_alloc_port=$((HOST_RTP_PORT_MAX - RTP_RANGE_SIZE + 1))
    host_rtp_start_port=$(generate_random_port "${HOST_RTP_PORT_MIN}" "${max_rtp_alloc_port}" "udp")
    host_rtp_end_port=$((host_rtp_start_port + RTP_RANGE_SIZE -1)) # Inclusive range

    log "Instance ${instance_id} - Host SIP Port: ${host_sip_port}/udp"
    log "Instance ${instance_id} - Host RTP Range: ${host_rtp_start_port}-${host_rtp_end_port}/udp"

    # Generate Asterisk configurations using the defined CONTAINER ports for internal config
    log "Generating Asterisk configuration for instance ${instance_id} using internal ports SIP: ${CONTAINER_SIP_PORT}, RTP: ${CONTAINER_RTP_START_PORT}-${CONTAINER_RTP_END_PORT}"
    temp_config_dir=$(generate_asterisk_configs \
        "${instance_id}" \
        "${CONTAINER_SIP_PORT}" \
        "${CONTAINER_RTP_START_PORT}" \
        "${CONTAINER_RTP_END_PORT}")

    if [ -z "${temp_config_dir}" ] || [ ! -d "${temp_config_dir}" ]; then
        error_exit "Failed to generate Asterisk configs for instance ${instance_id}. Aborting launch."
    fi
    TEMP_CONFIG_DIRS_TO_CLEAN+=("$temp_config_dir") # Add to cleanup list

    log "Launching Docker container ${container_name} for instance ${instance_id}..."
    # Port mapping: Host's random ports map to Container's fixed internal ports.
    # Host SIP Port: ${host_sip_port} -> Container SIP Port: ${CONTAINER_SIP_PORT}
    # Host RTP Range: ${host_rtp_start_port}-${host_rtp_end_port} -> Container RTP Range: ${CONTAINER_RTP_START_PORT}-${CONTAINER_RTP_END_PORT}

    # Note on --tmpfs /var/run/asterisk: This ensures the PID file is in a memory filesystem.
    # The entrypoint script in the Dockerfile already creates /var/run/asterisk and chowns it.
    # Using --user $(id -u):$(id -g) might be problematic if the asterisk user UID/GID in container is different
    # The Dockerfile creates an 'asterisk' user. The entrypoint script uses 'gosu asterisk' to run.
    if docker run -d \
        --name "${container_name}" \
        --rm \
        -p "${host_sip_port}:${CONTAINER_SIP_PORT}/udp" \
        -p "${host_rtp_start_port}-${host_rtp_end_port}:${CONTAINER_RTP_START_PORT}-${CONTAINER_RTP_END_PORT}/udp" \
        -v "${temp_config_dir}:/etc/asterisk:ro" \
        --tmpfs /var/run/asterisk \
        "${FULL_IMAGE_NAME}"; then

        log "Successfully launched Asterisk instance:"
        echo "  Instance ID:    ${instance_id}"
        echo "  Container Name: ${container_name}"
        echo "  Host SIP Port:  ${host_sip_port}/udp (maps to container ${CONTAINER_SIP_PORT}/udp)"
        echo "  Host RTP Range: ${host_rtp_start_port}-${host_rtp_end_port}/udp (maps to container ${CONTAINER_RTP_START_PORT}-${CONTAINER_RTP_END_PORT}/udp)"
        echo "  Config Dir:     ${temp_config_dir} (mounted read-only)"
        echo
        echo "To view logs: docker logs ${container_name}"
        echo "To access Asterisk CLI: docker exec -it ${container_name} asterisk -rvvv"
        echo "To stop and remove: docker stop ${container_name}"
    else
        error_exit "Failed to launch Docker container for instance ${instance_id}. Check Docker logs for ${container_name} if it was created."
        # Config dir will be cleaned up by the trap
    fi
}


# Call main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
