#!/bin/bash
echo "🔍 Installing Vinit_recon..."

# Create installation directory
mkdir -p ~/.Vinit_recon
cd ~/.Vinit_recon

echo "📦 Installing required dependencies..."

install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        echo "➡ Installing $1..."
        sudo apt-get install -y "$2" > /dev/null 2>&1
    else
        echo "✔ $1 already installed"
    fi
}

# Update apt repository list silently
sudo apt-get update > /dev/null 2>&1

# Install Recon Tools
install_if_missing "subfinder" "subfinder"
install_if_missing "httpx" "httpx-toolkit"
install_if_missing "waybackurls" "waybackurls"
install_if_missing "nikto" "nikto"
install_if_missing "nmap" "nmap"

# Dirsearch installation (manually)
if [ ! -d "/opt/dirsearch" ]; then
    echo "➡ Installing dirsearch..."
    sudo git clone https://github.com/maurosoria/dirsearch /opt/dirsearch > /dev/null 2>&1
    sudo ln -sf /opt/dirsearch/dirsearch.py /usr/local/bin/dirsearch
else
    echo "✔ dirsearch already installed"
fi

echo "📥 Downloading Vinit_recon tool..."

# Download binary from GitHub Releases (UPDATE USERNAME BEFORE USE)
curl -L -o Vinit_recon \
"https://github.com/<your-username>/Vinit_recon/releases/download/v1.0/Vinit_recon"

chmod +x Vinit_recon

echo ""
echo "🎯 Installation Complete!"
echo "Run the tool using:"
echo ""
echo "   ~/.Vinit_recon/Vinit_recon"
echo ""
echo "🚀 Happy Recon with Vinit_recon!"
