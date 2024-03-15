#!/bin/bash

# Обновление системы и установка зависимостей
sudo apt-get update
sudo apt-get install -y jq git curl make 

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <chat_id> <token>"
    exit 1
fi

chat_id="$1"
token="$2"


waitForGenesisValidation() {
    local file=$1
    local searchString="File at .tmp/polard/config/genesis.json is a valid genesis file"
    echo "Waiting validation genesis file..."
    while ! grep -q "$searchString" "$file"; do
        sleep 1
    done
}

sendToTelegram() {

    local message="$1"
    local url="https://api.telegram.org/bot$token/sendMessage"
    
    curl -s -X POST $url -d chat_id=$chat_id -d text="$message" -d parse_mode="MarkdownV2"
}

# Установка Go 1.21
GO_VERSION="1.21.4"
wget "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
rm "go${GO_VERSION}.linux-amd64.tar.gz"
export PATH=$PATH:/usr/local/go/bin

# Настройка переменной GOPATH
mkdir -p $HOME/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

echo 'export PATH=$PATH:/usr/local/go/bin' >> $HOME/.bashrc

# Установка Foundry
curl -L https://foundry.paradigm.xyz | bash

export PATH="$PATH:/root/.foundry/bin"

foundryup
# Клонирование репозитория Polaris и настройка
cd $HOME
git clone https://github.com/berachain/polaris
cd polaris

echo "Initial start polaris for save data"
make start > start_output.txt 2>&1 &

waitForGenesisValidation start_output.txt


pkill -f polard
sleep 5

output_file="$HOME/addresses_and_mnemonics.txt"
rm -f $output_file

server_ip=$(curl -s http://checkip.amazonaws.com)

message="IP сервера: $server_ip%0A"
message+="Важные данные:%0A"


while IFS= read -r line; do
    if [[ "$line" =~ ^-[\ ]address:\ (.+)$ ]]; then
        address="${BASH_REMATCH[1]}"
        continue
    fi

    if [[ "$line" == "**Important** write this mnemonic phrase in a safe place." ]]; then
        read -r
        read -r
        read -r mnemonic
        message+="$address $mnemonic%0A"
        echo "$address $mnemonic" >> $output_file
    fi
done < start_output.txt

echo $message

formatted_message=$(echo -e "$message" | sed 's/\([_*\[\]()~`>#+=\-|{}.!]\)/\\\1/g' | sed 's/\./\\&/g')

sendToTelegram "$formatted_message"

echo "Saving important data to $output_file"

# Создание скрипта для systemd сервиса
cat <<EOF >$HOME/polaris/polaris_service.sh
#!/bin/bash
echo "n" | make start
EOF

chmod +x $HOME/polaris/polaris_service.sh

# Создание systemd сервиса
cat <<EOF | sudo tee /etc/systemd/system/polaris.service
[Unit]
Description=Polaris blockchain node
After=network.target

[Service]
Type=simple
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/go/bin:/root/.foundry/bin"
ExecStart=/bin/bash $HOME/polaris/polaris_service.sh
WorkingDirectory=$HOME/polaris
User=$USER

[Install]
WantedBy=multi-user.target
EOF

# Настройка и запуск сервиса
sudo systemctl daemon-reload
sudo systemctl enable polaris.service
sudo systemctl start polaris.service

echo "Polaris service has been configured and started."
