#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Colors
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
MAGENTA="\e[35m"
BOLD="\e[1m"
RESET="\e[0m"

# System Info
hostname=$(hostname)
uptime=$(uptime -p)
memory=$(free -h | awk '/^Mem:/ {print $3 " / " $2}')
disk=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " used)"}')
cpus=$(nproc)
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | sed 's/^.*: //')

# Welcome message
echo -e "${YELLOW}${BOLD} -=[ Welcome to debian.theflat.gen.nz]=-   [$(date)] ${RESET}"
echo -e "${BLUE}-----------------------------------------------------${RESET}"
echo -e "${GREEN} • Access is monitored and logged."
echo -e " • Remember to be excellent to each other."
echo -e " • Contact dev@theflat.gen.nz if issues arise.${RESET}"
echo ""

echo -e "${MAGENTA}${BOLD} System Information:${RESET}"
echo -e "${GREEN} • Hostname:   ${hostname}"
echo -e " • Uptime:     ${uptime}"
echo -e " • Memory:     ${memory}"
echo -e " • Disk Usage: ${disk}"
echo -e " • CPU:        ${cpu_model} (${cpus} cores)"
echo -e "${BLUE}-----------------------------------------------------${RESET}"

# Optional: Use fortune + cowsay if installed
if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1; then
    echo -e "${CYAN} $(fortune | cowsay) ${RESET}"
else
    # Manual random quotes (fallback)
    quotes=(
      "\"Talk is cheap. Show me the code.\" – Linus Torvalds"
      "\"The quieter you become, the more you are able to hear.\" – Ram Dass"
      "\"It always seems impossible until it's done.\" – Nelson Mandela"
      "\"Don't cross the streams!\" – Egon Spengler"
      "\"There is no cloud. It's just someone else's computer.\""
    )
    random_index=$((RANDOM % ${#quotes[@]}))
    echo -e "${CYAN} Tip of the day:\n  ${quotes[$random_index]} ${RESET}"
fi

echo -e "${BLUE}-----------------------------------------------------${RESET}"

echo "Debian Disclaimer:

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law."
echo ""

echo -e "${GREEN}TO-DO List: ${RESET}"
echo -e "${MAGENTA}
1. Remember to check the cc configuration if/when GCC is updated.
   sudo update-alternatives --config cc
2. Check .bashrc for aliases and updates when compiling from source.
${RESET}"