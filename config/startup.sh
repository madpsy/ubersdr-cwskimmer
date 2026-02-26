#!/bin/bash
#set d -e

# Ensure restart trigger directory exists
mkdir -p /var/run/restart-trigger

# Initialize SkimSrv.ini if it's empty (bind mount created empty file on first run)
if [ -f "$PATH_INI_SKIMSRV" ] && [ ! -s "$PATH_INI_SKIMSRV" ]; then
    echo "Initializing empty SkimSrv.ini with template..."
    cat > "$PATH_INI_SKIMSRV" << 'EOF'
[Window]
MainFormLeft=543
MainFormTop=130
[User]
Call=
Name=
QTH=
Square=
[Telnet]
Port=7300
PasswordRequired=0
Password=
CqOnly=0
AllowAnn=1
AnnUserOnly=0
AnnUser=
MinQuality=1
[Skimmer]
CenterFreqs48=1822750,3522750,3568250,7022750,10122750,14022750,14068250,18090750,21022750,21068250,24912750,28022750,28068250,50022750,50068250,50113750,50159250
CenterFreqs96=1845500,3545500,7045500,10145500,14045500,18113500,21045500,24935500,28045500,28136500,50045500,50136500
CenterFreqs192=1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000
SegmentSel48=00010000000000000
SegmentSel96=001111111
SegmentSel192=011111111
CwSegments=1800000-1840000,3500000-3570000,5258000-5370000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,50000000-50100000
ThreadCount=2
DeviceName=01 UberSDR-IQ192
Rate=2
FreqCalibration=1
EOF
fi

# Configure Skimmer Server - always set from .env values
echo "Configuring SkimSrv at $PATH_INI_SKIMSRV"
if [ -f "$PATH_INI_SKIMSRV" ]; then
    echo "Setting SkimSrv with Callsign: $CALLSIGN, QTH: $QTH, Name: $NAME, Grid: $SQUARE"
    # Use temp file for bind-mounted files (sed -i doesn't work on bind mounts)
    # Escape special characters in variables for sed
    CALLSIGN_ESC=$(printf '%s\n' "$CALLSIGN" | sed 's/[[\.*^$/]/\\&/g')
    QTH_ESC=$(printf '%s\n' "$QTH" | sed 's/[[\.*^$/]/\\&/g')
    NAME_ESC=$(printf '%s\n' "$NAME" | sed 's/[[\.*^$/]/\\&/g')
    SQUARE_ESC=$(printf '%s\n' "$SQUARE" | sed 's/[[\.*^$/]/\\&/g')
    
    sed "s/^Call=.*/Call=$CALLSIGN_ESC/g" "$PATH_INI_SKIMSRV" | \
    sed "s/^QTH=.*/QTH=$QTH_ESC/g" | \
    sed "s/^Name=.*/Name=$NAME_ESC/g" | \
    sed "s/^Square=.*/Square=$SQUARE_ESC/g" > "$PATH_INI_SKIMSRV.tmp"
    cat "$PATH_INI_SKIMSRV.tmp" > "$PATH_INI_SKIMSRV"
    rm -f "$PATH_INI_SKIMSRV.tmp"

    # Build SegmentSel192 based on band enable/disable environment variables
    echo "Building band selection from environment variables..."

    # Default values if not set
    : ${BAND_160M:=false}
    : ${BAND_80M:=true}
    : ${BAND_60M:=true}
    : ${BAND_40M:=true}
    : ${BAND_30M:=true}
    : ${BAND_20M:=true}
    : ${BAND_17M:=true}
    : ${BAND_15M:=true}
    : ${BAND_12M:=true}
    : ${BAND_10M:=true}

    # Convert true/false to 1/0 for each band
    SEG_160M=$([ "$BAND_160M" = "true" ] && echo "1" || echo "0")
    SEG_80M=$([ "$BAND_80M" = "true" ] && echo "1" || echo "0")
    SEG_60M=$([ "$BAND_60M" = "true" ] && echo "1" || echo "0")
    SEG_40M=$([ "$BAND_40M" = "true" ] && echo "1" || echo "0")
    SEG_30M=$([ "$BAND_30M" = "true" ] && echo "1" || echo "0")
    SEG_20M=$([ "$BAND_20M" = "true" ] && echo "1" || echo "0")
    SEG_17M=$([ "$BAND_17M" = "true" ] && echo "1" || echo "0")
    SEG_15M=$([ "$BAND_15M" = "true" ] && echo "1" || echo "0")
    SEG_12M=$([ "$BAND_12M" = "true" ] && echo "1" || echo "0")
    SEG_10M=$([ "$BAND_10M" = "true" ] && echo "1" || echo "0")

    # Build the SegmentSel192 string
    SEGMENT_SEL="${SEG_160M}${SEG_80M}${SEG_60M}${SEG_40M}${SEG_30M}${SEG_20M}${SEG_17M}${SEG_15M}${SEG_12M}${SEG_10M}"

    echo "Band configuration:"
    echo "  160m: $BAND_160M ($SEG_160M)"
    echo "  80m:  $BAND_80M ($SEG_80M)"
    echo "  60m:  $BAND_60M ($SEG_60M)"
    echo "  40m:  $BAND_40M ($SEG_40M)"
    echo "  30m:  $BAND_30M ($SEG_30M)"
    echo "  20m:  $BAND_20M ($SEG_20M)"
    echo "  17m:  $BAND_17M ($SEG_17M)"
    echo "  15m:  $BAND_15M ($SEG_15M)"
    echo "  12m:  $BAND_12M ($SEG_12M)"
    echo "  10m:  $BAND_10M ($SEG_10M)"
    echo "  SegmentSel192: $SEGMENT_SEL"

    # Always overwrite CenterFreqs192, CwSegments, and SegmentSel192 with fixed values
    echo "Setting CenterFreqs192, CwSegments, and SegmentSel192..."
    sed "s/^CenterFreqs192=.*/CenterFreqs192=1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000/g" "$PATH_INI_SKIMSRV" | \
    sed "s|^CwSegments=.*|CwSegments=1800000-1840000,3500000-3570000,5258000-5370000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,50000000-50100000|g" | \
    sed "s/^SegmentSel192=.*/SegmentSel192=$SEGMENT_SEL/g" > "$PATH_INI_SKIMSRV.tmp"
    cat "$PATH_INI_SKIMSRV.tmp" > "$PATH_INI_SKIMSRV"
    rm -f "$PATH_INI_SKIMSRV.tmp"

    echo "SkimSrv.ini configured successfully"
fi

# Configure RBN Aggregator
echo "Configure RBN Aggregator with Callsign: $CALLSIGN using $PATH_INI_AGGREGATOR"
#sed -i 's/Skimmer Call=.*/Skimmer Call='$CALLSIGN'/g' "$PATH_INI_AGGREGATOR"
#cat "$PATH_INI_AGGREGATOR"
sed -i 's/CW0SKIM/'$CALLSIGN'/g' "$PATH_INI_AGGREGATOR"
#cat "$PATH_INI_AGGREGATOR"
# FIXME: only debug stuff
cp "$PATH_INI_AGGREGATOR" /root/
chmod oag-r "$PATH_INI_AGGREGATOR"

# Initialize UberSDRIntf.ini if it's empty (bind mount created empty file on first run)
if [ -f "$PATH_INI_UBERSDR" ] && [ ! -s "$PATH_INI_UBERSDR" ]; then
    echo "Initializing empty UberSDRIntf.ini with template..."
    cat > "$PATH_INI_UBERSDR" << 'EOF'
; UberSDR Interface Configuration File
[Server]
Host=ubersdr.local
Port=8080
debug_rec=0

[Calibration]
FrequencyOffset=0
swap_iq=1
EOF
fi

# Configure UberSDR driver - always set from .env values
echo "Configuring UberSDR driver at $PATH_INI_UBERSDR"
if [ -f "$PATH_INI_UBERSDR" ]; then
    echo "Setting UberSDR driver with host: $UBERSDR_HOST, port: $UBERSDR_PORT"
    # Use temp file for bind-mounted files (sed -i doesn't work on bind mounts)
    # Escape special characters in variables for sed
    UBERSDR_HOST_ESC=$(printf '%s\n' "$UBERSDR_HOST" | sed 's/[[\.*^$/]/\\&/g')
    UBERSDR_PORT_ESC=$(printf '%s\n' "$UBERSDR_PORT" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Host=.*/Host=$UBERSDR_HOST_ESC/g" "$PATH_INI_UBERSDR" | \
    sed "s/^Port=.*/Port=$UBERSDR_PORT_ESC/g" > "$PATH_INI_UBERSDR.tmp"
    cat "$PATH_INI_UBERSDR.tmp" > "$PATH_INI_UBERSDR"
    rm -f "$PATH_INI_UBERSDR.tmp"
    echo "UberSDRIntf.ini configured successfully"
else
    echo "Warning: UberSDRIntf.ini not found at $PATH_INI_UBERSDR"
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
