#!/bin/bash

# Stop on the first sign of trouble
set -e

if [ $UID != 0 ]; then
    echo "ERROR: Operation not permitted. Forgot sudo?"
    exit 1
fi

echo "Gongomesh Gateway installer for the -Hat"

# Update the gateway installer to the correct branch
echo "Updating installer files..."
OLD_HEAD=$(git rev-parse HEAD)
git fetch
git checkout
git pull
NEW_HEAD=$(git rev-parse HEAD)

if [[ $OLD_HEAD != $NEW_HEAD ]]; then
    echo "New installer found. Restarting process..."
    exec "./install.sh"
fi

# Request gateway configuration data
# There are two ways to do it, manually specify everything
# or rely on the gateway EUI and retrieve settings files from remote (recommended)
echo "Gongomesh Gateway configuration:"

# Try to get gateway ID from MAC address

# Get first non-loopback network device that is currently connected
GATEWAY_EUI_NIC=$(ip -oneline link show up 2>&1 | grep -v LOOPBACK | sed -E 's/^[0-9]+: ([0-9a-z]+): .*/\1/' | head -1)
if [[ -z $GATEWAY_EUI_NIC ]]; then
    echo "ERROR: No network interface found. Cannot set gateway ID."
    exit 1
fi

# Then get EUI based on the MAC address of that device
GATEWAY_EUI=$(cat /sys/class/net/$GATEWAY_EUI_NIC/address | awk -F\: '{print $1$2$3"FFFE"$4$5$6}')
GATEWAY_EUI=${GATEWAY_EUI^^} # toupper

echo "Detected EUI $GATEWAY_EUI from $GATEWAY_EUI_NIC"

read -r -p "Do you want to use remote settings file? [y/N]" response
response=${response,,} # tolower

if [[ $response =~ ^(yes|y) ]]; then
    NEW_HOSTNAME="gongomesh-gateway"
    REMOTE_CONFIG=true
else
    printf "       Host name [gongomesh-gateway]:"
    read NEW_HOSTNAME
    if [[ $NEW_HOSTNAME == "" ]]; then NEW_HOSTNAME="gongomesh-gateway"; fi

    printf "       Descriptive name [gongomesh-lorawan]:"
    read GATEWAY_NAME
    if [[ $GATEWAY_NAME == "" ]]; then GATEWAY_NAME="gomgomesh-lorawan"; fi

    printf "       Contact email: "
    read GATEWAY_EMAIL

    printf "       Latitude [0]: "
    read GATEWAY_LAT
    if [[ $GATEWAY_LAT == "" ]]; then GATEWAY_LAT=0; fi

    printf "       Longitude [0]: "
    read GATEWAY_LON
    if [[ $GATEWAY_LON == "" ]]; then GATEWAY_LON=0; fi

    printf "       Altitude [0]: "
    read GATEWAY_ALT
    if [[ $GATEWAY_ALT == "" ]]; then GATEWAY_ALT=0; fi
fi


# Change hostname if needed
CURRENT_HOSTNAME=$(hostname)

if [[ $NEW_HOSTNAME != $CURRENT_HOSTNAME ]]; then
    echo "Updating hostname to '$NEW_HOSTNAME'..."
    hostname $NEW_HOSTNAME
    echo $NEW_HOSTNAME > /etc/hostname
    sed -i "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/" /etc/hosts
fi

# Install LoRaWAN packet forwarder repositories
INSTALL_DIR="/opt/gongomesh-gateway"
if [ ! -d "$INSTALL_DIR" ]; then mkdir $INSTALL_DIR; fi
cp ./rak2247_rpi.h $INSTALL_DIR
pushd $INSTALL_DIR

# Remove WiringPi built from source (older installer versions)
if [ -d wiringPi ]; then
    pushd wiringPi
    ./build uninstall
    popd
    rm -rf wiringPi
fi

# Build LoRa gateway app
if [ ! -d lora_gateway_legacy ]; then
    git clone  https://github.com/wenderson-ferreira/lora_gateway_legacy.git
    pushd lora_gateway_legacy
else
    pushd lora_gateway_legacy
    git fetch origin
    git checkout main
    git reset --hard
fi

mv ../rak2247_rpi.h ./libloragw/inc/
sed -i -e 's/PLATFORM= kerlink/PLATFORM= rak2247_rpi/g' ./libloragw/library.cfg

make

popd

# Build packet forwarder
if [ ! -d packet_forwarder_legacy ]; then
    git clone  https://github.com/wenderson-ferreira/packet_forwarder_legacy.git
    pushd packet_forwarder_legacy
else
    pushd packet_forwarder_legacy
    git fetch origin
    git checkout main
    git reset --hard
fi

make

popd

# Symlink poly packet forwarder
if [ ! -d bin ]; then mkdir bin; fi
if [ -f ./bin/poly_pkt_fwd ]; then rm ./bin/poly_pkt_fwd; fi
ln -s $INSTALL_DIR/packet_forwarder/poly_pkt_fwd/poly_pkt_fwd ./bin/poly_pkt_fwd
cp -f ./packet_forwarder/poly_pkt_fwd/global_conf.json ./bin/global_conf.json

LOCAL_CONFIG_FILE=$INSTALL_DIR/bin/local_conf.json

# Remove old config file
if [ -e $LOCAL_CONFIG_FILE ]; then rm $LOCAL_CONFIG_FILE; fi;

if [ "$REMOTE_CONFIG" = true ] ; then
    # Get remote configuration repo
    if [ ! -d gateway-remote-config ]; then
        git clone https://github.com/wenderson-ferreira/gateway-remote-config.git
        pushd gateway-remote-config
    else
        pushd gateway-remote-config
        git pull
        git reset --hard
    fi

    ln -s $INSTALL_DIR/gateway-remote-config/$GATEWAY_EUI.json $LOCAL_CONFIG_FILE

    popd
else
    echo -e "{\n\t\"SX1301_conf\": {
    \n\t\"lorawan_public\": true,
    \n\t\"clksrc\": 1,
    \n\t\"antenna_gain\": 0,
    \n\t\"radio_0\": {
    \n\t\t\"enable\": true,
    \n\t\t\"type\": \"SX1257\",
    \n\t\t\"freq\": 917200000,
    \n\t\t\"rssi_offset\": -166,
    \n\t\t\"tx_enable\": true,
    \n\t\t\"tx_freq_min\": 915000000,
    \n\t\t\"tx_freq_max\": 928000000
    \n},
    \n\t\"radio_1\": {
    \n\t\t\"enable\": true,
    \n\t\t\"type\": \"SX1257\",
    \n\t\t\"freq\": 917900000,
    \n\t\t\"rssi_offset\": -166,
    \n\t\t\"tx_enable\": false
    \n},
    \n\t\"chan_multiSF_0\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 0,
    \n\t\t\"if\": -400000
    \n},
    \n\t\"chan_multiSF_1\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 0,
    \n\t\t\"if\": -200000
    \n},
    \n\t\"chan_multiSF_2\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 0,
    \n\t\t\"if\": 0
    \n},
    \n\t\"chan_multiSF_3\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 0,
    \n\t\t\"if\": 200000
    \n},
    \n\t\t\"chan_multiSF_4\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 1,
    \n\t\t\"if\": -300000
    \n},
    \n\t\"chan_multiSF_5\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 1,
    \n\t\t\"if\": -100000
    \n},
    \n\t\"chan_multiSF_6\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 1,
    \n\t\t\"if\": 100000
    \n},
    \n\t\t\"chan_multiSF_7\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 1,
    \n\t\t\"if\": 300000
    \n},
    \n\t\t\"chan_Lora_std\": {
    \n\t\t\"enable\": true,
    \n\t\t\"radio\": 0,
    \n\t\t\"if\": 300000,
    \n\t\t\"bandwidth\": 500000,
    \n\t\t\"spread_factor\": 8
    \n},
    \n\t\t\"chan_FSK\": {
    \n\t\t\"enable\": false
    \n},
    \n\t\"tx_lut_0\": {
    \n\t\t\"pa_gain\": 0,
    \n\t\t\"mix_gain\": 8,
    \n\t\t\"rf_power\": -6,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\t\"tx_lut_1\": {
    \n\t\t\"pa_gain\": 0,
    \n\t\t\"mix_gain\": 10,
    \n\t\t\"rf_power\": -3,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_2\": {
    \n\t\t\"pa_gain\": 0,
    \n\t\t\"mix_gain\": 12,
    \n\t\t\"rf_power\": 0,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_3\": {
    \n\t\t\"pa_gain\": 1,
    \n\t\t\"mix_gain\": 8,
    \n\t\t\"rf_power\": 3,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_4\": {
    \n\t\t\"pa_gain\": 1,
    \n\t\t\"mix_gain\": 10,
    \n\t\t\"rf_power\": 6,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\t\"tx_lut_5\": {
    \n\t\t\"pa_gain\": 1,
    \n\t\t\"mix_gain\": 12,
    \n\t\t\"rf_power\": 10,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_6\": {
    \n\t\t\"pa_gain\": 1,
    \n\t\t\"mix_gain\": 13,
    \n\t\t\"rf_power\": 11,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_7\": {
    \n\t\t\"pa_gain\": 2,
    \n\t\t\"mix_gain\": 9,
    \n\t\t\"rf_power\": 12,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_8\": {
    \n\t\t\"pa_gain\": 1,
    \n\t\t\"mix_gain\": 15,
    \n\t\t\"rf_power\": 13,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_9\": {
    \n\t\t\"pa_gain\": 2,
    \n\t\t\"mix_gain\": 10,
    \n\t\t\"rf_power\": 14,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_10\": {
    \n\t\t\"pa_gain\": 2,
    \n\t\t\"mix_gain\": 11,
    \n\t\t\"rf_power\": 16,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_11\": {
    \n\t\t\"pa_gain\": 3,
    \n\t\t\"mix_gain\": 9,
    \n\t\t\"rf_power\": 20,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_12\": {
    \n\t\t\"pa_gain\": 3,
    \n\t\t\"mix_gain\": 10,
    \n\t\t\"rf_power\": 23,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_13\": {
    \n\t\t\"pa_gain\": 3,
    \n\t\t\"mix_gain\": 11,
    \n\t\t\"rf_power\": 25,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_14\": {
    \n\t\t\"pa_gain\": 3,
    \n\t\t\"mix_gain\": 12,
    \n\t\t\"rf_power\": 26,
    \n\t\t\"dig_gain\": 0
    \n},
    \n\t\"tx_lut_15\": {
    \n\t\t\"pa_gain\": 3,
    \n\t\t\"mix_gain\": 14,
    \n\t\t\"rf_power\": 27,
    \n\t\t\"dig_gain\": 0
    }
  },\n\t\"gateway_conf\": {\n\t\t\"gateway_ID\": \"$GATEWAY_EUI\",\n\t\t\"server_address\": \"au1.cloud.thethings.network\",\n\t\t\"serv_port_up\": 1700,\n\t\t\"serv_port_down\": 1700,\n\t\t\"servers\": [ { \"gateway_ID\": \"$GATEWAY_EUI\",\n\"server_address\": \"au1.cloud.thethings.network\", \n\"serv_port_up\": 1700, \n\"serv_port_down\": 1700, \n\"serv_enabled\": true } ],\n\t\t\"ref_latitude\": $GATEWAY_LAT,\n\t\t\"ref_longitude\": $GATEWAY_LON,\n\t\t\"ref_altitude\": $GATEWAY_ALT,\n\t\t\"contact_email\": \"$GATEWAY_EMAIL\",\n\t\t\"description\": \"$GATEWAY_NAME\" \n\t}\n}" >$LOCAL_CONFIG_FILE
fi

popd

echo "Gateway EUI is: $GATEWAY_EUI"
echo "The hostname is: $NEW_HOSTNAME"
echo "Open TTN console and register your gateway using your EUI: https://console.thethingsnetwork.org/gateways OR ThingsBOT LNS"
echo
echo "Installation completed."

# Start packet forwarder as a service
cp ./start.sh $INSTALL_DIR/bin/
cp ./gongomesh-gateway.service /lib/systemd/system/
systemctl enable gongomesh-gateway.service

echo "The system will reboot in 5 seconds..."
sleep 5
shutdown -r now
