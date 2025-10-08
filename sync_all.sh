#!/bin/bash

# User and Group Synchronization Script
# Usage: ./sync_users_groups.sh [source_host] [options]
# 
# This script synchronizes users and groups from a source system
# Handles both local file sync and remote system sync

set -euo pipefail

# Configuration
SCRIPT_NAME=$(basename "$0")
LOG_FILE="/var/log/user_sync.log"
BACKUP_DIR="/var/backups/user_sync_$(date +%Y%m%d_%H%M%S)"
DRY_RUN=false
VERBOSE=false
SYNC_PASSWORDS=true
SYNC_SHADOWS=true
MIN_UID=1000
MAX_UID=999999
MIN_GID=1000
MAX_GID=999999

# System files
PASSWD_FILE="/etc/passwd"
GROUP_FILE="/etc/group"
SHADOW_FILE="/etc/shadow"
GSHADOW_FILE="/etc/gshadow"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Colored output functions
info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
    log "INFO" "$*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
    log "WARN" "$*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    log "ERROR" "$*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
    log "SUCCESS" "$*"
}

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [SOURCE]

Synchronize users and groups from source to current system.

SOURCE:
    user@host:/path    Remote system (will use scp/ssh)
    /path/to/files     Local directory containing passwd, group, etc.
    (none)             Interactive mode to specify source

OPTIONS:
    -d, --dry-run      Show what would be done without making changes
    -v, --verbose      Enable verbose output
    --no-passwords     Skip password synchronization
    --no-shadows       Skip shadow file synchronization
    --min-uid NUM      Minimum UID to sync (default: 1000)
    --max-uid NUM      Maximum UID to sync (default: 999999)
    --min-gid NUM      Minimum GID to sync (default: 1000)
    --max-gid NUM      Maximum GID to sync (default: 999999)
    -h, --help         Show this help message

Examples:
    $SCRIPT_NAME --dry-run user@server:/etc
    $SCRIPT_NAME /backup/etc_files
    $SCRIPT_NAME --no-passwords --min-uid 1500 user@backup-server:/etc

EOF
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Create backup directory
create_backup() {
    info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    for file in "$PASSWD_FILE" "$GROUP_FILE" "$SHADOW_FILE" "$GSHADOW_FILE"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$BACKUP_DIR/"
            info "Backed up $file"
        fi
    done
}

# Fetch files from remote source
fetch_remote_files() {
    local source="$1"
    local temp_dir="$2"
    
    info "Fetching files from remote source: $source"
    
    # Extract user@host and path
    local user_host="${source%:*}"
    local remote_path="${source#*:}"
    
    # Fetch each file
    for file in passwd group shadow gshadow; do
        local remote_file="$remote_path/$file"
        local local_file="$temp_dir/$file"
        
        if scp "$user_host:$remote_file" "$local_file" 2>/dev/null; then
            info "Fetched $remote_file"
        else
            warn "Could not fetch $remote_file (may not exist)"
        fi
    done
}

# Copy files from local source
copy_local_files() {
    local source="$1"
    local temp_dir="$2"
    
    info "Copying files from local source: $source"
    
    for file in passwd group shadow gshadow; do
        local source_file="$source/$file"
        local dest_file="$temp_dir/$file"
        
        if [[ -f "$source_file" ]]; then
            cp "$source_file" "$dest_file"
            info "Copied $source_file"
        else
            warn "Source file $source_file does not exist"
        fi
    done
}

# Filter users/groups by UID/GID range
filter_by_range() {
    local file="$1"
    local min_id="$2"
    local max_id="$3"
    local id_field="$4"  # 3 for UID, 3 for GID
    
    awk -F: -v min="$min_id" -v max="$max_id" -v field="$id_field" \
        '$field >= min && $field <= max' "$file"
}

# Check for conflicts
check_conflicts() {
    local source_passwd="$1"
    local source_group="$2"
    
    local conflicts=0
    
    info "Checking for conflicts..."
    
    # Check username conflicts
    while IFS=: read -r username _ uid _; do
        if [[ $uid -ge $MIN_UID && $uid -le $MAX_UID ]]; then
            if getent passwd "$username" >/dev/null 2>&1; then
                local existing_uid=$(getent passwd "$username" | cut -d: -f3)
                if [[ "$existing_uid" != "$uid" ]]; then
                    warn "Username conflict: $username (existing UID: $existing_uid, source UID: $uid)"
                    ((conflicts++))
                fi
            fi
        fi
    done < "$source_passwd"
    
    # Check UID conflicts
    while IFS=: read -r username _ uid _; do
        if [[ $uid -ge $MIN_UID && $uid -le $MAX_UID ]]; then
            if getent passwd "$uid" >/dev/null 2>&1; then
                local existing_user=$(getent passwd "$uid" | cut -d: -f1)
                if [[ "$existing_user" != "$username" ]]; then
                    warn "UID conflict: $uid (existing user: $existing_user, source user: $username)"
                    ((conflicts++))
                fi
            fi
        fi
    done < "$source_passwd"
    
    # Check group conflicts
    while IFS=: read -r groupname _ gid _; do
        if [[ $gid -ge $MIN_GID && $gid -le $MAX_GID ]]; then
            if getent group "$groupname" >/dev/null 2>&1; then
                local existing_gid=$(getent group "$groupname" | cut -d: -f3)
                if [[ "$existing_gid" != "$gid" ]]; then
                    warn "Group name conflict: $groupname (existing GID: $existing_gid, source GID: $gid)"
                    ((conflicts++))
                fi
            fi
            
            if getent group "$gid" >/dev/null 2>&1; then
                local existing_group=$(getent group "$gid" | cut -d: -f1)
                if [[ "$existing_group" != "$groupname" ]]; then
                    warn "GID conflict: $gid (existing group: $existing_group, source group: $groupname)"
                    ((conflicts++))
                fi
            fi
        fi
    done < "$source_group"
    
    if [[ $conflicts -gt 0 ]]; then
        error "Found $conflicts conflicts. Please resolve manually or adjust UID/GID ranges."
        return 1
    fi
    
    success "No conflicts detected"
    return 0
}

# Sync groups
sync_groups() {
    local source_group="$1"
    local source_gshadow="$2"
    
    info "Syncing groups..."
    
    local groups_added=0
    
    while IFS=: read -r groupname password gid members; do
        if [[ $gid -ge $MIN_GID && $gid -le $MAX_GID ]]; then
            if ! getent group "$groupname" >/dev/null 2>&1; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    info "[DRY RUN] Would add group: $groupname (GID: $gid)"
                else
                    groupadd -g "$gid" "$groupname"
                    info "Added group: $groupname (GID: $gid)"
                    ((groups_added++))
                fi
            else
                [[ "$VERBOSE" == "true" ]] && info "Group already exists: $groupname"
            fi
        fi
    done < "$source_group"
    
    # Sync gshadow if available and enabled
    if [[ "$SYNC_SHADOWS" == "true" && -f "$source_gshadow" ]]; then
        info "Syncing group shadow entries..."
        while IFS=: read -r groupname password admins members; do
            local gid=$(getent group "$groupname" 2>/dev/null | cut -d: -f3)
            if [[ -n "$gid" && $gid -ge $MIN_GID && $gid -le $MAX_GID ]]; then
                if [[ "$DRY_RUN" == "false" ]]; then
                    # Update gshadow entry
                    local gshadow_line="$groupname:$password:$admins:$members"
                    if grep -q "^$groupname:" /etc/gshadow; then
                        sed -i "s/^$groupname:.*/$gshadow_line/" /etc/gshadow
                    else
                        echo "$gshadow_line" >> /etc/gshadow
                    fi
                fi
            fi
        done < "$source_gshadow"
    fi
    
    success "Synced $groups_added groups"
}

# Sync users
sync_users() {
    local source_passwd="$1"
    local source_shadow="$2"
    
    info "Syncing users..."
    
    local users_added=0
    
    while IFS=: read -r username password uid gid gecos home shell; do
        if [[ $uid -ge $MIN_UID && $uid -le $MAX_UID ]]; then
            if ! getent passwd "$username" >/dev/null 2>&1; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    info "[DRY RUN] Would add user: $username (UID: $uid, GID: $gid)"
                else
                    # Create user
                    useradd -u "$uid" -g "$gid" -c "$gecos" -d "$home" -s "$shell" -M "$username"
                    info "Added user: $username (UID: $uid)"
                    ((users_added++))
                    
                    # Create home directory if it doesn't exist
                    if [[ ! -d "$home" && "$home" != "/dev/null" ]]; then
                        mkdir -p "$home"
                        chown "$username:$gid" "$home"
                        chmod 755 "$home"
                        info "Created home directory: $home"
                    fi
                fi
            else
                [[ "$VERBOSE" == "true" ]] && info "User already exists: $username"
            fi
        fi
    done < "$source_passwd"
    
    # Sync shadow passwords if available and enabled
    if [[ "$SYNC_PASSWORDS" == "true" && "$SYNC_SHADOWS" == "true" && -f "$source_shadow" ]]; then
        info "Syncing user passwords..."
        while IFS=: read -r username password lastchg min max warn inactive expire flag; do
            local uid=$(getent passwd "$username" 2>/dev/null | cut -d: -f3)
            if [[ -n "$uid" && $uid -ge $MIN_UID && $uid -le $MAX_UID ]]; then
                if [[ "$DRY_RUN" == "false" ]]; then
                    # Update shadow entry
                    local shadow_line="$username:$password:$lastchg:$min:$max:$warn:$inactive:$expire:$flag"
                    if grep -q "^$username:" /etc/shadow; then
                        sed -i "s/^$username:.*/$shadow_line/" /etc/shadow
                    else
                        echo "$shadow_line" >> /etc/shadow
                    fi
                fi
            fi
        done < "$source_shadow"
    fi
    
    success "Synced $users_added users"
}

# Main function
main() {
    local source=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --no-passwords)
                SYNC_PASSWORDS=false
                shift
                ;;
            --no-shadows)
                SYNC_SHADOWS=false
                shift
                ;;
            --min-uid)
                MIN_UID="$2"
                shift 2
                ;;
            --max-uid)
                MAX_UID="$2"
                shift 2
                ;;
            --min-gid)
                MIN_GID="$2"
                shift 2
                ;;
            --max-gid)
                MAX_GID="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [[ -z "$source" ]]; then
                    source="$1"
                else
                    error "Unknown option: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check if running as root
    check_root
    
    # Create log file
    touch "$LOG_FILE"
    
    info "Starting user and group synchronization"
    info "Dry run: $DRY_RUN"
    info "UID range: $MIN_UID - $MAX_UID"
    info "GID range: $MIN_GID - $MAX_GID"
    
    # Create backup
    if [[ "$DRY_RUN" == "false" ]]; then
        create_backup
    fi
    
    # Create temporary directory for source files
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Get source files
    if [[ -z "$source" ]]; then
        error "No source specified"
        usage
        exit 1
    elif [[ "$source" == *":"* ]]; then
        # Remote source
        fetch_remote_files "$source" "$temp_dir"
    else
        # Local source
        copy_local_files "$source" "$temp_dir"
    fi
    
    # Check if we have required files
    if [[ ! -f "$temp_dir/passwd" ]]; then
        error "No passwd file found in source"
        exit 1
    fi
    
    if [[ ! -f "$temp_dir/group" ]]; then
        error "No group file found in source"
        exit 1
    fi
    
    # Check for conflicts
    if ! check_conflicts "$temp_dir/passwd" "$temp_dir/group"; then
        exit 1
    fi
    
    # Sync groups first (users depend on groups)
    sync_groups "$temp_dir/group" "$temp_dir/gshadow"
    
    # Sync users
    sync_users "$temp_dir/passwd" "$temp_dir/shadow"
    
    success "User and group synchronization completed"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Backup created in: $BACKUP_DIR"
        info "Log file: $LOG_FILE"
    fi
}

# Run main function with all arguments
main "$@"
