#!/bin/bash

# Kurulum için gerekli yollar
XRAY_PATH="/usr/local/bin/xray"
V2RAY_PATH="/usr/local/bin/v2ray"
SERVICE_PATH="/etc/systemd/system"
CONFIG_PATH="/etc/xray/config.json"
ARCH=$(uname -m)

echo "🚀 Xray / V2Ray Kurulumu Başlıyor..."

# Kullanıcıya hangi çekirdeği yüklemek istediğini sor
echo "Kurulum Seçimi: "
echo "1) Xray"
echo "2) V2Ray"
read -p "Seçiminizi yapın (1-2): " core_choice

# Seçime göre ilgili değişkenleri belirle
if [[ "$core_choice" == "1" ]]; then
    CORE_NAME="Xray"
    CORE_PATH=$XRAY_PATH
    CORE_SERVICE="xray"
    CORE_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux"
elif [[ "$core_choice" == "2" ]]; then
    CORE_NAME="V2Ray"
    CORE_PATH=$V2RAY_PATH
    CORE_SERVICE="v2ray"
    CORE_URL="https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux"
else
    echo "⚠ Geçersiz seçim, çıkılıyor..."
    exit 1
fi

# Mimarinin belirlenmesi
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH_SUFFIX="64"
elif [[ "$ARCH" == "aarch64" ]]; then
    ARCH_SUFFIX="arm64-v8a"
elif [[ "$ARCH" == "armv7l" ]]; then
    ARCH_SUFFIX="arm32-v7a"
else
    echo "⚠ Desteklenmeyen mimari: $ARCH"
    exit 1
fi

# Bağımlılıkları yükle
echo "📦 Gerekli bağımlılıklar yükleniyor..."
apt update && apt install -y curl unzip

# Mevcut kurulum varsa kaldır
if [ -f "$CORE_PATH" ]; then
    echo "⚠ Mevcut $CORE_NAME kurulumu bulundu, eski sürüm kaldırılıyor..."
    systemctl stop $CORE_SERVICE
    rm -f $CORE_PATH
fi

# Çekirdek dosyasını indir
echo "⬇ $CORE_NAME ($ARCH_SUFFIX) indiriliyor..."
mkdir -p /usr/local/bin
curl -L -o /tmp/$CORE_NAME.zip $CORE_URL-$ARCH_SUFFIX.zip

# İndirme başarılı mı kontrol et
if [ $? -ne 0 ]; then
    echo "❌ İndirme başarısız oldu! Çıkılıyor..."
    exit 1
fi

# Dosyaları çıkart ve yetki ver
unzip -o /tmp/$CORE_NAME.zip -d /usr/local/bin/
chmod +x $CORE_PATH

# Sistem servis dosyasını oluştur
echo "⚙ $CORE_NAME servis dosyası oluşturuluyor..."
cat > $SERVICE_PATH/$CORE_SERVICE.service <<EOF
[Unit]
Description=$CORE_NAME Service
After=network.target

[Service]
User=nobody
NoNewPrivileges=true
ExecStart=$CORE_PATH -config $CONFIG_PATH
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Servisi başlat ve etkinleştir
systemctl daemon-reload
systemctl enable $CORE_SERVICE
systemctl start $CORE_SERVICE

echo "✅ $CORE_NAME başarıyla kuruldu ve çalıştırıldı."

# Menü sistemini yükle
echo "📜 Menü dosyası oluşturuluyor..."
cat > /usr/local/bin/menu <<'EOF'
#!/bin/bash
CONFIG_PATH="/etc/xray/config.json"
SERVICE_NAME=$(systemctl list-units --type=service --no-pager | grep -E 'xray|v2ray' | awk '{print $1}')

function create_config() {
    read -p "VLESS Linkini Yapıştır: " vless_link

    # VLESS linkini parçalarına ayır
    address=$(echo "$vless_link" | sed -n 's/.*@[^:]*:\(.*\)/\1/p')
    port=$(echo "$vless_link" | sed -n 's/.*:\([0-9]*\)?.*/\1/p')
    uuid=$(echo "$vless_link" | sed -n 's/vless:\/\/\([^@]*\)@.*/\1/p')
    sni=$(echo "$vless_link" | grep -oP 'sni=\K[^&]*')

    if [ -z "$sni" ]; then
        sni="youtube.com"
    fi

    cat > $CONFIG_PATH <<EOL
{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "tag": "socks"
    }
  ],
  "log": {
    "loglevel": "none"
  },
  "outbounds": [
    {
      "mux": {
        "enabled": true,
        "concurrency": 8
      },
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$address",
            "port": $port,
            "users": [
              {
                "id": "$uuid",
                "encryption": "none",
                "level": 8
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$sni",
          "allowInsecure": true
        },
        "wsSettings": {
          "path": "/"
        }
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    }
  ]
}
EOL

    echo "✅ Yeni config oluşturuldu: $CONFIG_PATH"
}

function restart_core() {
    systemctl restart $SERVICE_NAME
    echo "✅ $SERVICE_NAME yeniden başlatıldı."
}

while true; do
    clear
    echo "====== Xray / V2Ray Config Menü ======"
    echo "1) Yeni VLESS Linki Gir ve Config Oluştur"
    echo "2) Servisi Yeniden Başlat"
    echo "3) Çıkış"
    read -p "Seçim Yap (1-3): " choice

    case $choice in
        1) create_config ;;
        2) restart_core ;;
        3) exit 0 ;;
        *) echo "⚠ Geçersiz seçim!" ;;
    esac

    read -p "Devam etmek için ENTER tuşuna bas..."
done
EOF

chmod +x /usr/local/bin/menu
echo "✅ Menü başarıyla yüklendi. Artık 'menu' komutu ile kullanabilirsin!"

# Menü otomatik çalıştır
menu
