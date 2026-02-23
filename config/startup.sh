#!/bin/bash
#set d -e 

# Configure Skimmer Server
echo "Configure Skimmer with Callsign: $CALLSIGN, QTH: $QTH, Name: $NAME, Grid: $SQUARE using $PATH_INI_SKIMSRV"
sed -i 's/Call=/Call='$CALLSIGN'/g' "$PATH_INI_SKIMSRV"
sed -i 's/QTH=/QTH='$QTH'/g' "$PATH_INI_SKIMSRV"
sed -i 's/Name=/Name='$NAME'/g' "$PATH_INI_SKIMSRV"
sed -i 's/Square=/Square='$SQUARE'/g' "$PATH_INI_SKIMSRV"

# Configure RBN Aggregator
echo "Configure RBN Aggregator with Callsign: $CALLSIGN using $PATH_INI_AGGREGATOR"
#sed -i 's/Skimmer Call=.*/Skimmer Call='$CALLSIGN'/g' "$PATH_INI_AGGREGATOR"
#cat "$PATH_INI_AGGREGATOR"
sed -i 's/CW0SKIM/'$CALLSIGN'/g' "$PATH_INI_AGGREGATOR"
#cat "$PATH_INI_AGGREGATOR"
# FIXME: only debug stuff
cp "$PATH_INI_AGGREGATOR" /root/
chmod oag-r "$PATH_INI_AGGREGATOR"

# Configure UberSDR driver
echo "Configure UberSDR driver with host: $UBERSDR_HOST, port: $UBERSDR_PORT using $PATH_INI_UBERSDR"
if [ -f "$PATH_INI_UBERSDR" ]; then
    sed -i 's/Host=.*/Host='$UBERSDR_HOST'/g' "$PATH_INI_UBERSDR"
    sed -i 's/Port=.*/Port='$UBERSDR_PORT'/g' "$PATH_INI_UBERSDR"
fi

echo "Configure supervisor for aggregator ${V_RBNAGGREGATOR}"
sed -i 's/6\.3/'$V_RBNAGGREGATOR'/g' /etc/supervisor/conf.d/supervisord.conf

echo "Configure supervisor for skimmer ${V_SKIMMERSRV}"
sed -i 's/1\.6/'$V_SKIMMERSRV'/g' /etc/supervisor/conf.d/supervisord.conf

echo "Start using logfiles $LOGFILE_UBERSDR and $LOGIFLE_AGGREGATOR"
touch $LOGFILE_UBERSDR
touch $LOGIFLE_AGGREGATOR

tail -f $LOGFILE_UBERSDR $LOGIFLE_AGGREGATOR &


exec "$@"
