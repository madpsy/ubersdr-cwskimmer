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
    : ${FREQ_CALIBRATION:=1}

    # Build array of enabled bands (in order)
    ENABLED_BANDS=()
    BAND_NAMES=("160M" "80M" "60M" "40M" "30M" "20M" "17M" "15M" "12M" "10M")
    BAND_VARS=("$BAND_160M" "$BAND_80M" "$BAND_60M" "$BAND_40M" "$BAND_30M" "$BAND_20M" "$BAND_17M" "$BAND_15M" "$BAND_12M" "$BAND_10M")

    for i in {0..9}; do
        if [ "${BAND_VARS[$i]}" = "true" ]; then
            ENABLED_BANDS+=("$i")
        fi
    done

    ENABLED_COUNT=${#ENABLED_BANDS[@]}
    echo "Total enabled bands: $ENABLED_COUNT"

    # Split bands between two instances (SkimSrv has 8-band limit)
    # Instance 1: First 8 enabled bands (or all if <=8)
    # Instance 2: Remaining bands (9th and 10th if enabled)

    # Build SegmentSel192 for instance 1
    SEGMENT_SEL_1="0000000000"
    SEGMENT_SEL_2="0000000000"

    if [ $ENABLED_COUNT -le 8 ]; then
        # All bands go to instance 1
        for band_idx in "${ENABLED_BANDS[@]}"; do
            SEGMENT_SEL_1="${SEGMENT_SEL_1:0:$band_idx}1${SEGMENT_SEL_1:$((band_idx+1))}"
        done
        echo "Instance 1: All $ENABLED_COUNT enabled bands"
        echo "Instance 2: No bands (standby)"
    else
        # First 8 bands to instance 1, remaining to instance 2
        for i in {0..7}; do
            if [ $i -lt $ENABLED_COUNT ]; then
                band_idx=${ENABLED_BANDS[$i]}
                SEGMENT_SEL_1="${SEGMENT_SEL_1:0:$band_idx}1${SEGMENT_SEL_1:$((band_idx+1))}"
            fi
        done

        for i in {8..9}; do
            if [ $i -lt $ENABLED_COUNT ]; then
                band_idx=${ENABLED_BANDS[$i]}
                SEGMENT_SEL_2="${SEGMENT_SEL_2:0:$band_idx}1${SEGMENT_SEL_2:$((band_idx+1))}"
            fi
        done
        echo "Instance 1: First 8 enabled bands"
        echo "Instance 2: Remaining $((ENABLED_COUNT - 8)) band(s)"
    fi

    echo ""
    echo "Band configuration:"
    echo "  160m: $BAND_160M"
    echo "  80m:  $BAND_80M"
    echo "  60m:  $BAND_60M"
    echo "  40m:  $BAND_40M"
    echo "  30m:  $BAND_30M"
    echo "  20m:  $BAND_20M"
    echo "  17m:  $BAND_17M"
    echo "  15m:  $BAND_15M"
    echo "  12m:  $BAND_12M"
    echo "  10m:  $BAND_10M"
    echo ""
    echo "Instance 1 SegmentSel192: $SEGMENT_SEL_1"
    echo "Instance 2 SegmentSel192: $SEGMENT_SEL_2"

    # Configure instance 1
    echo "Configuring SkimSrv instance 1..."
    sed "s/^CenterFreqs192=.*/CenterFreqs192=1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000/g" "$PATH_INI_SKIMSRV" | \
    sed "s|^CwSegments=.*|CwSegments=1800000-1840000,3500000-3570000,5258000-5370000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,50000000-50100000|g" | \
    sed "s/^SegmentSel192=.*/SegmentSel192=$SEGMENT_SEL_1/g" | \
    sed "s/^Port=.*/Port=7300/g" | \
    sed "s/^FreqCalibration=.*/FreqCalibration=$FREQ_CALIBRATION/g" > "$PATH_INI_SKIMSRV.tmp"
    cat "$PATH_INI_SKIMSRV.tmp" > "$PATH_INI_SKIMSRV"
    rm -f "$PATH_INI_SKIMSRV.tmp"

    echo "SkimSrv instance 1 configured successfully"
fi

# Configure SkimSrv instance 2
echo "Configuring SkimSrv instance 2 at $PATH_INI_SKIMSRV_2"
if [ -f "$PATH_INI_SKIMSRV_2" ]; then
    # Initialize if empty
    if [ ! -s "$PATH_INI_SKIMSRV_2" ]; then
        echo "Initializing empty SkimSrv-2.ini with template..."
        cat > "$PATH_INI_SKIMSRV_2" << 'EOF'
[Window]
MainFormLeft=543
MainFormTop=130
[User]
Call=
Name=
QTH=
Square=
[Telnet]
Port=7301
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
SegmentSel192=0000000000
CwSegments=1800000-1840000,3500000-3570000,5258000-5370000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,50000000-50100000
ThreadCount=2
DeviceName=01 UberSDR-IQ192
Rate=2
FreqCalibration=1
EOF
    fi

    # Configure with user settings and band selection
    CALLSIGN_ESC=$(printf '%s\n' "$CALLSIGN" | sed 's/[[\.*^$/]/\\&/g')
    QTH_ESC=$(printf '%s\n' "$QTH" | sed 's/[[\.*^$/]/\\&/g')
    NAME_ESC=$(printf '%s\n' "$NAME" | sed 's/[[\.*^$/]/\\&/g')
    SQUARE_ESC=$(printf '%s\n' "$SQUARE" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Call=.*/Call=$CALLSIGN_ESC/g" "$PATH_INI_SKIMSRV_2" | \
    sed "s/^QTH=.*/QTH=$QTH_ESC/g" | \
    sed "s/^Name=.*/Name=$NAME_ESC/g" | \
    sed "s/^Square=.*/Square=$SQUARE_ESC/g" | \
    sed "s/^CenterFreqs192=.*/CenterFreqs192=1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000/g" | \
    sed "s|^CwSegments=.*|CwSegments=1800000-1840000,3500000-3570000,5258000-5370000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,50000000-50100000|g" | \
    sed "s/^SegmentSel192=.*/SegmentSel192=$SEGMENT_SEL_2/g" | \
    sed "s/^Port=.*/Port=7301/g" | \
    sed "s/^FreqCalibration=.*/FreqCalibration=$FREQ_CALIBRATION/g" > "$PATH_INI_SKIMSRV_2.tmp"
    cat "$PATH_INI_SKIMSRV_2.tmp" > "$PATH_INI_SKIMSRV_2"
    rm -f "$PATH_INI_SKIMSRV_2.tmp"

    echo "SkimSrv instance 2 configured successfully"
fi

# Configure RBN Aggregator
echo "Configure RBN Aggregator with Callsign: $CALLSIGN using $PATH_INI_AGGREGATOR"
#sed -i 's/Skimmer Call=.*/Skimmer Call='$CALLSIGN'/g' "$PATH_INI_AGGREGATOR"
#cat "$PATH_INI_AGGREGATOR"
sed -i 's/CW0SKIM/'$CALLSIGN'/g' "$PATH_INI_AGGREGATOR"

# Configure Secondary Skimmer 1 to connect to SkimSrv instance 2 (port 7301)
echo "Configuring Aggregator Secondary Skimmer 1 for SkimSrv instance 2..."
sed -i "s/^Secondary Skimmer 1 Callsign=.*/Secondary Skimmer 1 Callsign=$CALLSIGN/g" "$PATH_INI_AGGREGATOR"
sed -i 's/^Secondary Skimmer 1 Port=.*/Secondary Skimmer 1 Port=7301/g' "$PATH_INI_AGGREGATOR"
sed -i 's/^Secondary Skimmer 1 Auto Start=.*/Secondary Skimmer 1 Auto Start=True/g' "$PATH_INI_AGGREGATOR"
echo "Aggregator configured to connect to both SkimSrv instances (ports 7300 and 7301)"

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

# Initialize UberSDRIntf-2.ini if it's empty (bind mount created empty file on first run)
if [ -f "$PATH_INI_UBERSDR_2" ] && [ ! -s "$PATH_INI_UBERSDR_2" ]; then
    echo "Initializing empty UberSDRIntf-2.ini with template..."
    cat > "$PATH_INI_UBERSDR_2" << 'EOF'
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

# Configure UberSDR driver for instance 2 - always set from .env values
echo "Configuring UberSDR driver for instance 2 at $PATH_INI_UBERSDR_2"
if [ -f "$PATH_INI_UBERSDR_2" ]; then
    echo "Setting UberSDR driver instance 2 with host: $UBERSDR_HOST, port: $UBERSDR_PORT"
    # Use temp file for bind-mounted files (sed -i doesn't work on bind mounts)
    # Escape special characters in variables for sed
    UBERSDR_HOST_ESC=$(printf '%s\n' "$UBERSDR_HOST" | sed 's/[[\.*^$/]/\\&/g')
    UBERSDR_PORT_ESC=$(printf '%s\n' "$UBERSDR_PORT" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Host=.*/Host=$UBERSDR_HOST_ESC/g" "$PATH_INI_UBERSDR_2" | \
    sed "s/^Port=.*/Port=$UBERSDR_PORT_ESC/g" > "$PATH_INI_UBERSDR_2.tmp"
    cat "$PATH_INI_UBERSDR_2.tmp" > "$PATH_INI_UBERSDR_2"
    rm -f "$PATH_INI_UBERSDR_2.tmp"
    echo "UberSDRIntf-2.ini configured successfully"
else
    echo "Warning: UberSDRIntf-2.ini not found at $PATH_INI_UBERSDR_2"
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
