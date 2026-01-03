#!/bin/bash

# ===========================
# Auto Recon Script - Clean Output Version
# ===========================

set -e  # Exit on error
set -o pipefail  # Catch pipe errors

DOMAIN="$1"
OUTPUT_DIR="$2"

# Validate inputs
if [ -z "$DOMAIN" ]; then
    echo "ERROR: No domain provided"
    exit 1
fi

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="recon_${DOMAIN}_$(date +%Y%m%d_%H%M%S)"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR" || exit 1

# Create log file (not shown to user)
LOG_FILE="execution.log"
exec 2>"$LOG_FILE"  # Send stderr to log file

# Main output file for user
MAIN_OUTPUT="scan_results.txt"
SUMMARY_FILE="executive_summary.md"
FILES_LIST="generated_files.txt"

echo "Starting reconnaissance scan for: $DOMAIN" > "$MAIN_OUTPUT"
echo "Scan started: $(date)" >> "$MAIN_OUTPUT"
echo "==========================================" >> "$MAIN_OUTPUT"
echo "" >> "$MAIN_OUTPUT"

# Function for clean progress updates
progress_update() {
    local phase="$1"
    local message="$2"
    echo "[$(date '+%H:%M:%S')] $phase: $message" >> "$MAIN_OUTPUT"
    echo "$phase" > current_phase.txt
}

# Function to run command quietly
run_silent() {
    local cmd="$1"
    local timeout="${2:-300}"
    local description="$3"
    local output_file="$4"
    
    progress_update "PROGRESS" "$description..."
    
    # Run command with timeout, capture output to file
    timeout "$timeout" bash -c "$cmd" > "$output_file" 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✓ $description completed" >> "$MAIN_OUTPUT"
    elif [ $? -eq 124 ]; then
        echo "⚠ $description timed out" >> "$MAIN_OUTPUT"
    else
        echo "✗ $description failed" >> "$MAIN_OUTPUT"
    fi
}

# ==========================================
# PHASE 1: INITIALIZATION
# ==========================================
progress_update "INIT" "Initializing scan for $DOMAIN"
echo "Target: $DOMAIN" >> "$MAIN_OUTPUT"

# ==========================================
# PHASE 2: SUBDOMAIN ENUMERATION
# ==========================================
progress_update "SUBDOMAINS" "Discovering subdomains"

# 1. Subfinder
if command -v subfinder >/dev/null 2>&1; then
    run_silent "subfinder -d '$DOMAIN' -silent" 120 "Subdomain enumeration" "subfinder_raw.txt"
    
    if [ -s subfinder_raw.txt ]; then
        sort -u subfinder_raw.txt > subdomains.txt
        SUBS_COUNT=$(wc -l < subdomains.txt)
        echo "Subdomains found: $SUBS_COUNT" >> "$MAIN_OUTPUT"
        echo "Sample subdomains:" >> "$MAIN_OUTPUT"
        head -5 subdomains.txt | sed 's/^/  - /' >> "$MAIN_OUTPUT"
    else
        echo "No subdomains found via subfinder" >> "$MAIN_OUTPUT"
        touch subdomains.txt
    fi
else
    echo "Subfinder not available, skipping..." >> "$MAIN_OUTPUT"
    touch subdomains.txt
fi

# ==========================================
# PHASE 3: ACTIVE HOST DISCOVERY
# ==========================================
progress_update "ACTIVE_HOSTS" "Finding active hosts"

if command -v httpx >/dev/null 2>&1 && [ -s subdomains.txt ]; then
    # Create URLs list
    cat subdomains.txt | while read sub; do
        echo "https://$sub"
        echo "http://$sub"
    done > urls_to_check.txt
    
    run_silent "httpx -l urls_to_check.txt -silent -status-code -title" 180 "Active host discovery" "httpx_results.txt"
    
    # Extract active hosts
    grep -oP '^\S+' httpx_results.txt 2>/dev/null | sed 's|^https\?://||' | sort -u > active_hosts.txt
    ACTIVE_COUNT=$(wc -l < active_hosts.txt 2>/dev/null || echo 0)
    
    echo "Active hosts found: $ACTIVE_COUNT" >> "$MAIN_OUTPUT"
    if [ $ACTIVE_COUNT -gt 0 ]; then
        echo "Top active hosts:" >> "$MAIN_OUTPUT"
        head -5 httpx_results.txt | sed 's/^/  - /' >> "$MAIN_OUTPUT"
    fi
    
    # Clean httpx output for display
    grep -oP '^\S+' httpx_results.txt > active_urls_clean.txt
else
    echo "Active host discovery skipped" >> "$MAIN_OUTPUT"
    touch active_hosts.txt
fi

# ==========================================
# PHASE 4: CONTENT DISCOVERY
# ==========================================
progress_update "CONTENT" "Discovering web content"

# Wayback URLs
if command -v waybackurls >/dev/null 2>&1; then
    run_silent "waybackurls '$DOMAIN' | head -100" 60 "Historical URL discovery" "historical_urls.txt"
    HISTORICAL_COUNT=$(wc -l < historical_urls.txt 2>/dev/null || echo 0)
    echo "Historical URLs found: $HISTORICAL_COUNT" >> "$MAIN_OUTPUT"
fi

# Directory enumeration (quick scan)
if command -v dirsearch >/dev/null 2>&1; then
    mkdir -p dirsearch
    run_silent "dirsearch -u 'https://$DOMAIN' -e php,html,js,txt -t 5 -x 404,500 --format=plain -o dirsearch/results.txt" 120 "Directory enumeration" "dirsearch/log.txt"
    
    if [ -s dirsearch/results.txt ]; then
        DIR_COUNT=$(grep -c "^\[" dirsearch/results.txt 2>/dev/null || echo 0)
        echo "Directories/files found: $DIR_COUNT" >> "$MAIN_OUTPUT"
    fi
fi

# ==========================================
# PHASE 5: VULNERABILITY SCAN
# ==========================================
progress_update "SECURITY" "Running security checks"

if command -v nikto >/dev/null 2>&1; then
    mkdir -p nikto
    run_silent "nikto -h 'https://$DOMAIN' -o nikto/results.txt -Format txt" 180 "Vulnerability scan" "nikto/log.txt"
    
    if [ -s nikto/results.txt ]; then
        VULN_COUNT=$(grep -c "+ " nikto/results.txt 2>/dev/null || echo 0)
        echo "Potential vulnerabilities: $VULN_COUNT" >> "$MAIN_OUTPUT"
    fi
fi

# ==========================================
# PHASE 6: PORT SCANNING
# ==========================================
progress_update "PORTS" "Scanning for open ports"

if command -v nmap >/dev/null 2>&1 && [ -s active_hosts.txt ]; then
    mkdir -p nmap
    MAIN_HOST=$(head -1 active_hosts.txt)
    
    if [ -n "$MAIN_HOST" ]; then
        # Quick port scan
        run_silent "nmap -T4 -F '$MAIN_HOST'" 120 "Quick port scan" "nmap/quick_scan.txt"
        
        # Check if host is up
        if grep -q "Host is up" nmap/quick_scan.txt; then
            # Service detection
            run_silent "nmap -sV -sC -T4 '$MAIN_HOST'" 300 "Service detection" "nmap/service_scan.txt"
            
            OPEN_PORTS=$(grep -c "open" nmap/service_scan.txt 2>/dev/null || echo 0)
            echo "Open ports on $MAIN_HOST: $OPEN_PORTS" >> "$MAIN_OUTPUT"
            
            if [ $OPEN_PORTS -gt 0 ]; then
                echo "Open services:" >> "$MAIN_OUTPUT"
                grep "open" nmap/service_scan.txt | head -3 | sed 's/^/  - /' >> "$MAIN_OUTPUT"
            fi
        fi
    fi
fi

# ==========================================
# PHASE 7: GENERATE REPORTS
# ==========================================
progress_update "REPORTING" "Generating final reports"

# Create executive summary
cat > "$SUMMARY_FILE" << EOF
# Executive Summary
## Reconnaissance Report for $DOMAIN

## Scan Information
- **Target**: $DOMAIN
- **Scan Date**: $(date)
- **Scan Duration**: $SECONDS seconds
- **Report Generated**: $(date)

## Key Findings
1. **Subdomains Discovered**: ${SUBS_COUNT:-0}
2. **Active Hosts**: ${ACTIVE_COUNT:-0}
3. **Historical URLs**: ${HISTORICAL_COUNT:-0}
4. **Directory Findings**: ${DIR_COUNT:-0}
5. **Potential Vulnerabilities**: ${VULN_COUNT:-0}
6. **Open Ports**: ${OPEN_PORTS:-0}

## Recommendations
1. Review exposed subdomains
2. Check for misconfigurations
3. Implement security headers
4. Monitor for unauthorized access

## Files Generated
$(find . -type f -name "*.txt" -o -name "*.md" | sed 's|^\./||' | sort)

---
*This report was generated automatically by Auto Recon Tool*
EOF

# Create files list
find . -type f \( -name "*.txt" -o -name "*.md" -o -name "*.log" \) | sed 's|^\./||' | sort > "$FILES_LIST"

# Final summary
echo "" >> "$MAIN_OUTPUT"
echo "==========================================" >> "$MAIN_OUTPUT"
echo "SCAN COMPLETED" >> "$MAIN_OUTPUT"
echo "==========================================" >> "$MAIN_OUTPUT"
echo "Total duration: $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds" >> "$MAIN_OUTPUT"
echo "" >> "$MAIN_OUTPUT"
echo "SUMMARY:" >> "$MAIN_OUTPUT"
echo "• Subdomains: ${SUBS_COUNT:-0}" >> "$MAIN_OUTPUT"
echo "• Active Hosts: ${ACTIVE_COUNT:-0}" >> "$MAIN_OUTPUT"
echo "• Historical URLs: ${HISTORICAL_COUNT:-0}" >> "$MAIN_OUTPUT"
echo "• Directory Findings: ${DIR_COUNT:-0}" >> "$MAIN_OUTPUT"
echo "• Potential Vulnerabilities: ${VULN_COUNT:-0}" >> "$MAIN_OUTPUT"
echo "• Open Ports: ${OPEN_PORTS:-0}" >> "$MAIN_OUTPUT"
echo "" >> "$MAIN_OUTPUT"
echo "Report files saved in: $(pwd)" >> "$MAIN_OUTPUT"

# Create completion flag
echo "COMPLETED" > scan_status.txt
echo "100" > progress.txt

exit 0
