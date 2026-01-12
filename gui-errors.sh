#!/bin/bash

# Purpose: Diagnose graphical startup issues on Debian 13 with Cinnamon
# Author: Copilot for Jacob
# Usage: Run as regular user; sudo only needed for journalctl system logs

echo -e "\n🧠 Session Type:"
echo "DESKTOP_SESSION: $DESKTOP_SESSION"
echo "XDG_SESSION_DESKTOP: $XDG_SESSION_DESKTOP"
#echo "Current session file: $(basename $(ps -p $(pgrep -u $USER -f cinnamon-session) -o cmd= | awk '{print $1}'))"

pid=$(pgrep -u "$USER" -f cinnamon-session | head -n 1)

if [[ -n "$pid" ]]; then
    cmd=$(ps -p "$pid" -o cmd= | awk '{print $1}')
    session_file=$(basename "$cmd")
    echo "Current session file: $session_file"
else
    echo "Cinnamon session not found for user $USER"
fi

# Check available sessions
echo -e "\n📂 Available Sessions:"
ls /usr/share/xsessions/

# Check OpenGL renderer
echo -e "\n🎨 OpenGL Renderer:"
glxinfo | grep "OpenGL renderer"

# Check if Cinnamon is running in software rendering
echo -e "\n🧪 Cinnamon Rendering Mode:"
grep -i "software rendering" ~/.xsession-errors | tail -n 5

# Check for drawable errors
echo -e "\n⚠️ Drawable Errors:"
grep -i "failed to create drawable" ~/.xsession-errors | tail -n 5

# Check VBoxClient status
echo -e "\n📦 VirtualBox Guest Additions:"
pgrep VBoxClient >/dev/null && echo "VBoxClient is running." || echo "VBoxClient is NOT running."

# Check graphics controller (requires VBoxManage on host)
echo -e "\n🖥️ VirtualBox Graphics Controller (host-side check):"
echo "Run this on your host: VBoxManage showvminfo <VM_NAME> | grep 'Graphics Controller'"

echo -e "\n✅ Done. Review any warnings above and consider switching to Cinnamon session at login if needed."

echo "🔍 Checking graphical startup logs..."

# 1. Systemd journal errors (current boot)
echo -e "\n--- Systemd Journal Errors ---"
sudo journalctl -b -p err | grep -Ei 'xorg|cinnamon|lightdm|gdm|sddm' || echo "No critical errors found."

# 2. Xorg log errors and warnings
echo -e "\n--- Xorg Log (/var/log/Xorg.0.log) ---"
if [ -f /var/log/Xorg.0.log ]; then
    grep -E '^\(EE\)|^\(WW\)' /var/log/Xorg.0.log || echo "No Xorg errors/warnings found."
else
    echo "Xorg log not found."
fi

# 3. Cinnamon session logs
echo -e "\n--- Cinnamon Session Logs ---"
journalctl --user -b | grep -i cinnamon || echo "No Cinnamon session errors found."

# 4. Display manager logs
echo -e "\n--- Display Manager Logs ---"
for dm in lightdm gdm sddm; do
    echo -e "\n[$dm]"
    sudo journalctl -u $dm | tail -n 20
done

# 5. Xsession errors
echo -e "\n--- ~/.xsession-errors ---"
[ -f ~/.xsession-errors ] && tail -n 20 ~/.xsession-errors || echo "No xsession error file found."

echo -e "\n✅ Diagnostic complete."
