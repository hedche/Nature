#!/bin/bash
# terraform-retry.sh - Retry terraform apply until OCI capacity available
#
# This script continuously attempts terraform apply across multiple availability
# domains until successful. Designed for OCI Free Tier ARM instance capacity issues.
#
# Usage: ./terraform-retry.sh

set -o pipefail  # Capture exit codes in pipes correctly

# ============================================================================
# CONFIGURATION
# ============================================================================

DELAY=600                           # 30 minutes (1800 seconds) between retries
LOG_FILE="terraform-retry.log"       # Log file path
SHAPE_NAME="VM.Standard.A1.Flex"     # ARM shape to check for
ALL_ADS=(1 2 3)                     # All possible ADs to try

# ============================================================================
# TRACKING VARIABLES
# ============================================================================

TOTAL_ATTEMPTS=0
declare -A AD_ATTEMPTS              # Associative array for per-AD attempt counts
declare -A AD_UNAVAILABLE           # Track ADs where shape is unavailable
START_TIME=$(date +%s)

# ============================================================================
# COLOR CODES
# ============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# ============================================================================
# FUNCTIONS
# ============================================================================

# Log message to both console and file
# Usage: log "message" "$COLOR"
log() {
    local message="$1"
    local color="${2:-$NC}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Console output with color
    echo -e "${color}[${timestamp}] ${message}${NC}"

    # File output without color codes
    echo "[${timestamp}] ${message}" >> "$LOG_FILE"
}

# Format seconds into human-readable duration
# Usage: format_duration $seconds
format_duration() {
    local total_seconds=$1
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))

    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $seconds
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $seconds
    else
        printf "%ds" $seconds
    fi
}

# Print statistics summary
print_statistics() {
    local end_time=$(date +%s)
    local total_runtime=$((end_time - START_TIME))

    echo ""
    log "==================== STATISTICS ====================" "$BLUE"
    log "Total runtime: $(format_duration $total_runtime)" "$CYAN"
    log "Total attempts: $TOTAL_ATTEMPTS" "$CYAN"

    # Print stats for all ADs that were attempted (sorted by AD number)
    for ad in $(echo "${!AD_ATTEMPTS[@]}" | tr ' ' '\n' | sort -n); do
        if [ ${AD_ATTEMPTS[$ad]} -gt 0 ]; then
            log "  - Availability Domain $ad: ${AD_ATTEMPTS[$ad]} attempts" "$CYAN"
        fi
    done

    if [ $TOTAL_ATTEMPTS -gt 0 ]; then
        local avg_time=$((total_runtime / TOTAL_ATTEMPTS))
        log "Average time per attempt: ~$(format_duration $avg_time)" "$CYAN"
    fi

    log "====================================================" "$BLUE"
    echo ""
}

# Handle interrupt signal (Ctrl+C)
handle_interrupt() {
    echo ""  # New line after ^C
    log "Script interrupted by user. Exiting..." "$YELLOW"
    print_statistics
    exit 130
}

# Check if error is a capacity issue
# Usage: is_capacity_error
# Returns: 0 if capacity error, 1 if not
is_capacity_error() {
    # Create a temporary file to capture recent terraform output
    local temp_output=$(mktemp)
    tail -100 "$LOG_FILE" > "$temp_output" 2>/dev/null || return 1

    # Check for capacity-related error patterns
    if grep -q "Out of host capacity" "$temp_output"; then
        rm "$temp_output"
        return 0
    fi

    rm "$temp_output"
    return 1
}

# Check if error indicates shape not available in AD
# Usage: is_shape_unavailable_error
# Returns: 0 if shape unavailable, 1 if not
is_shape_unavailable_error() {
    # Create a temporary file to capture recent terraform output
    local temp_output=$(mktemp)
    tail -100 "$LOG_FILE" > "$temp_output" 2>/dev/null || return 1

    # Check for 404 NotAuthorizedOrNotFound error (indicates shape not available in AD)
    if grep -q "404-NotAuthorizedOrNotFound" "$temp_output"; then
        rm "$temp_output"
        return 0
    fi

    rm "$temp_output"
    return 1
}

# Get list of ADs to try (excluding those marked unavailable)
# Usage: get_available_ads
# Returns: Space-separated list of AD numbers
get_available_ads() {
    local ads_to_try=""

    for ad in "${ALL_ADS[@]}"; do
        # Skip if this AD is marked as unavailable
        if [ "${AD_UNAVAILABLE[$ad]}" != "1" ]; then
            ads_to_try="$ads_to_try $ad"
        fi
    done

    # Trim leading space
    ads_to_try=$(echo "$ads_to_try" | sed 's/^ //')

    # If all ADs are unavailable, return all (to handle edge cases)
    if [ -z "$ads_to_try" ]; then
        echo "${ALL_ADS[*]}"
    else
        echo "$ads_to_try"
    fi
}

# ============================================================================
# SIGNAL HANDLING
# ============================================================================

trap 'handle_interrupt' SIGINT SIGTERM

# ============================================================================
# INITIALIZATION
# ============================================================================

log "========================================================" "$BLUE"
log "  OCI Terraform Retry Script - Starting" "$BLUE"
log "========================================================" "$BLUE"
log "Configuration:" "$CYAN"
log "  - Delay between rounds: 30 minutes" "$CYAN"
log "  - Shape: ${SHAPE_NAME}" "$CYAN"
log "  - Log file: $LOG_FILE" "$CYAN"
log "  - Strategy: Dynamically check ADs each round, wait 30 min between rounds" "$CYAN"
log "========================================================" "$BLUE"
echo ""

# ============================================================================
# MAIN RETRY LOOP
# ============================================================================

ROUND=0

while true; do
    ((ROUND++))

    log "════════════════════════════════════════════════════" "$BLUE"
    log "Starting Round #${ROUND}" "$BLUE"
    log "════════════════════════════════════════════════════" "$BLUE"
    echo ""

    # Get available ADs for this round (excludes ADs where shape is unavailable)
    available_ads_str=$(get_available_ads)
    IFS=' ' read -r -a ADS <<< "$available_ads_str"

    # Initialize AD attempt counters for any new ADs
    for ad in "${ADS[@]}"; do
        if [ -z "${AD_ATTEMPTS[$ad]}" ]; then
            AD_ATTEMPTS[$ad]=0
        fi
    done

    # Log which ADs we'll try
    if [ ${#ADS[@]} -eq 0 ]; then
        log "✗ No available ADs to try!" "$RED"
        print_statistics
        exit 1
    fi

    unavailable_list=""
    for ad in "${ALL_ADS[@]}"; do
        if [ "${AD_UNAVAILABLE[$ad]}" == "1" ]; then
            unavailable_list="$unavailable_list $ad"
        fi
    done

    if [ -n "$unavailable_list" ]; then
        log "Skipping ADs (shape unavailable):$unavailable_list" "$YELLOW"
    fi
    log "Will try ADs in this round: ${ADS[*]}" "$CYAN"
    echo ""

    # Try each AD in this round
    for CURRENT_AD in "${ADS[@]}"; do
        # Increment counters
        ((TOTAL_ATTEMPTS++))
        ((AD_ATTEMPTS[$CURRENT_AD]++))

        # Calculate elapsed time
        current_time=$(date +%s)
        elapsed=$((current_time - START_TIME))

        # Log attempt info
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$CYAN"
        log "Attempt #${TOTAL_ATTEMPTS} - Round #${ROUND} (Runtime: $(format_duration $elapsed))" "$CYAN"
        log "Trying Availability Domain: $CURRENT_AD" "$CYAN"

        # Build dynamic AD stats string
        ad_stats=""
        for ad_num in $(echo "${!AD_ATTEMPTS[@]}" | tr ' ' '\n' | sort -n); do
            if [ -n "$ad_stats" ]; then
                ad_stats="${ad_stats}, "
            fi
            ad_stats="${ad_stats}AD${ad_num}=${AD_ATTEMPTS[$ad_num]}"
        done
        log "AD Stats: ${ad_stats}" "$CYAN"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$CYAN"
        echo ""

        # Run terraform apply with current AD
        # Use a temp file to capture output, then tee to log
        terraform apply -auto-approve -var="availability_domain=${CURRENT_AD}" 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[0]}

        echo ""

        # Check result
        if [ $EXIT_CODE -eq 0 ]; then
            # Success!
            log "✓ SUCCESS! Terraform apply completed successfully on AD ${CURRENT_AD}!" "$GREEN"
            print_statistics
            log "Your K3s cluster is now being provisioned. Check outputs above for details." "$GREEN"
            exit 0
        else
            # Failed - determine why
            if is_capacity_error; then
                # Capacity error - this is expected, continue to next AD
                log "⚠ Capacity error in AD ${CURRENT_AD} (expected, will try next AD)" "$YELLOW"
                echo ""
            elif is_shape_unavailable_error; then
                # Shape not available in this AD - mark it and skip in future rounds
                AD_UNAVAILABLE[$CURRENT_AD]=1
                log "⚠ Shape ${SHAPE_NAME} not available in AD ${CURRENT_AD}" "$YELLOW"
                log "  This AD will be skipped in future rounds" "$YELLOW"
                echo ""
            else
                # Non-capacity error - this is a real problem, stop retrying
                log "✗ ERROR: Non-capacity error detected!" "$RED"
                log "This appears to be a configuration, authentication, or other error." "$RED"
                log "Please review the terraform output above and fix the issue." "$RED"
                log "Common issues:" "$RED"
                log "  - Authentication/credentials problems" "$RED"
                log "  - Invalid configuration syntax" "$RED"
                log "  - Network connectivity issues" "$RED"
                log "  - Resource quota exceeded (permanent limit)" "$RED"
                echo ""
                print_statistics
                exit 1
            fi
        fi
    done

    # All ADs in this round failed with capacity errors
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$YELLOW"
    log "All ADs exhausted in Round #${ROUND}" "$YELLOW"

    # Calculate next attempt time
    next_attempt_time=$(date -r $(($(date +%s) + DELAY)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$(($(date +%s) + DELAY))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "in 30 minutes")

    log "Next round: #$((ROUND + 1)) at ${next_attempt_time}" "$CYAN"
    log "Waiting 30 minutes before next round..." "$CYAN"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$YELLOW"
    echo ""

    # Sleep for the delay period
    sleep $DELAY
done
