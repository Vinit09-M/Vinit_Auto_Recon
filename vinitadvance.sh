#!/bin/bash

########################
#   COLORS & STYLES   #
########################
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
BOLD='\e[1m'
RESET='\e[0m'

########################
#   BANNER FUNCTION   #
########################
banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
██╗   ██╗██╗███╗   ██╗██╗████████╗
██║   ██║██║████╗  ██║██║╚══██╔══╝
██║   ██║██║██╔██╗ ██║██║   ██║   
╚██╗ ██╔╝██║██║╚██╗██║██║   ██║   
 ╚████╔╝ ██║██║ ╚████║██║   ██║   
  ╚═══╝  ╚═╝╚═╝  ╚═══╝╚═╝   ╚═╝   

        🚀 Vinit AutoRecon 🚀
EOF
    echo -e "${RESET}"
}

########################
#   SECTION HEADER    #
########################
section() {
    echo -e ""
    echo -e "${BLUE}────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}${YELLOW}▶ $1${RESET}"
    echo -e "${BLUE}────────────────────────────────────────────${RESET}"
}

########################
#  SIMPLE STATUS ICON #
########################
status_line() {
    local status=$1
    local msg=$2

    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}[✔]${RESET} $msg"
    else
        echo -e "${RED}[✖]${RESET} $msg"
    fi
}

########################
#     RECON FUNCS     #
########################

run_subfinder() {
    section "Step 1: Subdomain Enumeration (subfinder)"
    subfinder -d "$domain" -silent -o subs.txt > /dev/null 2>&1
    sf_status=$?

    if [ -s subs.txt ]; then
        subs_count=$(wc -l < subs.txt)
        status_line $sf_status "Subdomains found: ${CYAN}$subs_count${RESET} (saved in subs.txt)"
    else
        status_line 1 "No subdomains found or subfinder error."
    fi
}

run_httpx() {
    section "Step 2: Checking Active Hosts (httpx)"
    if [ -s subs.txt ]; then
        httpx -l subs.txt -silent -mc 200,302 -o active.txt > /dev/null 2>&1
        httpx_status=$?

        if [ -s active.txt ]; then
            active_count=$(wc -l < active.txt)
            status_line $httpx_status "Active domains: ${CYAN}$active_count${RESET} (saved in active.txt)"
        else
            status_line 1 "No active domains detected from subs.txt."
        fi
    else
        echo -e "${RED}[!] subs.txt is empty or missing, run Subfinder first.${RESET}"
    fi
}


run_wayback() {
    section "Step 3: Wayback Historical URLs (waybackurls)"
    waybackurls "$domain" > wayback.txt 2>/dev/null
    wb_status=$?

    if [ -s wayback.txt ]; then
        wayback_count=$(wc -l < wayback.txt)
        status_line $wb_status "Historical URLs collected: ${CYAN}$wayback_count${RESET} (saved in wayback.txt)"
    else
        status_line 1 "No historical URLs collected."
    fi
}

run_dirsearch() {
    section "Step 4: Directory Enumeration (dirsearch)"
    echo -e "${YELLOW}Running Dirsearch... (This may take time)${RESET}"
    dirsearch -u "https://$domain" --crawl -r -q -o dirsearch.txt > /dev/null 2>&1
    ds_status=$?

    if [ -s dirsearch.txt ]; then
        status_line $ds_status "Dirsearch results saved in dirsearch.txt"
    else
        status_line 1 "No results or Dirsearch error."
    fi
}

run_nikto() {
    section "Step 5: Web Server Scan (nikto)"
    echo -e "${YELLOW}Running Nikto scan... (This may take time)${RESET}"
    nikto -h "https://$domain" -o nikto.txt > /dev/null 2>&1
    nikto_status=$?

    if [ -s nikto.txt ]; then
        status_line $nikto_status "Nikto scan results saved in nikto.txt"
    else
        status_line 1 "No Nikto output or scan failed."
    fi
}

run_nmap() {
    section "Step 6: Nmap Scan on Active Hosts"
    if [ -s active.txt ]; then
        echo -e "${YELLOW}Running Nmap scan on active domains...${RESET}"
        while read -r url; do
            # Remove protocol (http/https) and anything after first slash
            host=$(echo "$url" | sed -E 's|https?://||; s|/.*$||')
            # Safe filename
            safe_host=$(echo "$host" | tr '/:' '_')

            nmap -sV -oN "nmap/nmap_${safe_host}.txt" "$host" > /dev/null 2>&1
            echo -e "${GREEN}[✔]${RESET} Nmap scan completed for ${CYAN}$host${RESET} → nmap/nmap_${safe_host}.txt"
        done < active.txt
    else
        echo -e "${RED}[!] active.txt is empty or missing, run HTTPX first.${RESET}"
    fi
}

########################
#       MENU UI       #
########################
show_menu() {
    echo -e ""
    echo -e "${BLUE}────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}${YELLOW}:: Select a Recon Module ::${RESET}"
    echo -e "${BLUE}────────────────────────────────────────────${RESET}"
    echo -e "${CYAN}[01]${RESET} Subdomain Enumeration (Subfinder)"
    echo -e "${CYAN}[02]${RESET} Check Active Hosts (HTTPX)"
    echo -e "${CYAN}[03]${RESET} Collect Wayback URLs"
    echo -e "${CYAN}[04]${RESET} Directory Scan (Dirsearch)"
    echo -e "${CYAN}[05]${RESET} Nikto Web Scan"
    echo -e "${CYAN}[06]${RESET} Nmap Ports & Services Scan"
    echo -e "${GREEN}[07]${RESET} 🚀 Recon All (Full AutoRecon)"
    echo -e ""
    echo -e "${RED}[00]${RESET} Exit"
    echo -e ""
    read -p "[-] Select an option: " option
}

run_choice() {
    case $option in
        1) run_subfinder; exit 0 ;;
        2) run_httpx; exit 0 ;;
        3) run_wayback; exit 0 ;;
        4) run_dirsearch; exit 0 ;;
        5) run_nikto; exit 0 ;;
        6) run_nmap; exit 0 ;;
        7) run_subfinder
           run_httpx
           run_wayback
           run_dirsearch
           run_nikto
           run_nmap
           exit 0 ;;
        0) echo -e "${RED}Exiting...${RESET}"; exit 0 ;;
        *) echo -e "${RED}[!] Invalid option${RESET}"; exit 1 ;;
    esac
}


########################
#      MAIN FLOW      #
########################
banner

echo -ne "${BOLD}${CYAN}Enter Domain Name (example: xyz.com): ${RESET}"
read domain

echo -e ""
echo -e "${MAGENTA}${BOLD}Starting Recon for:${RESET} ${YELLOW}$domain${RESET}"
echo -e "${BLUE}============================================${RESET}"

# Prepare folders
mkdir -p "recon_$domain"
cd "recon_$domain" || exit 1
mkdir -p nmap
rm -f nmap_*.txt 2>/dev/null

# Show menu & run selected option
show_menu
run_choice

########################
#   SUMMARY SECTION    #
########################
echo -e ""
echo -e "${BLUE}============================================${RESET}"
echo -e "${BOLD}${GREEN}Recon Finished (Vinit AutoRecon)${RESET}"
echo -e "${BLUE}============================================${RESET}"
echo -e "📌 ${CYAN}subs.txt${RESET}         - Discovered subdomains (if created)"
echo -e "📌 ${CYAN}active.txt${RESET}       - Alive domains (if created)"
echo -e "📌 ${CYAN}wayback.txt${RESET}      - Historical URLs (if created)"
echo -e "📌 ${CYAN}dirsearch.txt${RESET}    - Hidden directories/files (if created)"
echo -e "📌 ${CYAN}nikto.txt${RESET}        - Web server scan (if created)"
echo -e "📂 ${CYAN}nmap/${RESET}            - All Nmap scan results (if created)"
echo -e "📁 Folder: ${MAGENTA}recon_$domain${RESET}"
echo -e "${BLUE}============================================${RESET}"
echo -e ""
